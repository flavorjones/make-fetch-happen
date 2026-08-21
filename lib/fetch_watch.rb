require "fileutils"
require "json"
require "openssl"
require "time"

# Turns signed Fizzy webhook deliveries into the one-line events bin/fetch-watch
# prints for the fetch-monitor skill:
#
#   MENTION card=<number> comment=<id> by="<creator>"
#   TRANSITION card=<number> state="<state>" by="<creator>"
#
# Nothing here touches the network or shells out; the only side effect is the
# mark file. The runtime plumbing (funnel, webhook registration, HTTP server,
# activity-feed paging) lives in bin/fetch-watch.
module FetchWatch
  Identity = Data.define(:id, :name) do
    def first_name
      name.to_s.split.first
    end
  end

  module Signature
    def self.valid?(body:, signature:, secret:)
      return false if signature.nil? || secret.nil?

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, body)
      expected.bytesize == signature.bytesize && OpenSSL.fixed_length_secure_compare(expected, signature)
    end
  end

  class Event
    TRANSITION_ACTIONS = %w[
      card_triaged card_closed card_postponed card_auto_postponed
      card_reopened card_sent_back_to_triage card_board_changed
    ].freeze
    MENTION_CONTENT_TYPE = "application/vnd.actiontext.mention"

    def initialize(payload)
      @payload = payload
    end

    def id = @payload["id"]
    def action = @payload["action"]
    def created_at = @payload["created_at"]&.then { Time.iso8601(it) }
    def creator_id = @payload.dig("creator", "id")
    def creator_name = @payload.dig("creator", "name")
    def comment_id = eventable["id"]

    def comment? = action == "comment_created"
    def transition? = TRANSITION_ACTIONS.include?(action)

    # A comment payload references its card by id and URL only; the number is
    # the last path segment of the URL.
    def card_number
      if comment?
        eventable.dig("card", "url").to_s[%r{/cards/(\d+)}, 1]&.to_i
      else
        eventable["number"]
      end
    end

    # The action says where the card went. The card payload only says where
    # it is now, which differs for a replayed event -- so consult it only for
    # actions that don't name a destination. "Done" and "Not Now" are flags on
    # the card, not columns, and a card keeps its last column when it enters
    # either, so the flags win over the column.
    def card_state
      case action
      when "card_closed" then "Done"
      when "card_postponed", "card_auto_postponed" then "Not Now"
      when "card_sent_back_to_triage" then "Maybe?"
      when "card_triaged" then @payload.dig("particulars", "column") || current_column
      else current_state
      end
    end

    # Rendered mention attachments carry the mentioned user's avatar URL, which
    # contains their id; plain text renders a mention as "@<first name>".
    def mentions?(identity)
      html = eventable.dig("body", "html").to_s
      plain_text = eventable.dig("body", "plain_text").to_s

      (html.include?(MENTION_CONTENT_TYPE) && html.include?(identity.id)) ||
        plain_text.match?(/@#{Regexp.escape(identity.first_name)}\b/i)
    end

    private
      def eventable
        @payload.fetch("eventable", {})
      end

      def current_state
        return "Done" if eventable["closed"]
        return "Not Now" if eventable["postponed"]

        current_column
      end

      def current_column
        column = eventable.dig("column", "name")
        column.nil? || column.empty? ? "Maybe?" : column
      end
  end

  class Pipeline
    def initialize(identity:, secret:, mark: Mark.new, log: $stderr)
      @identity = identity
      @secret = secret
      @mark = mark
      @log = log
      @seen = Set.new
    end

    # A signed webhook delivery.
    def process(body:, signature:)
      return log("rejected: bad signature") unless Signature.valid?(body: body, signature: signature, secret: @secret)

      handle(Event.new(JSON.parse(body)))
    rescue JSON::ParserError
      log("rejected: malformed payload")
    end

    # An event read back from the board's activity feed, which is already
    # authenticated by the API call that fetched it.
    def replay(payload)
      handle(Event.new(payload))
    end

    private
      def handle(event)
        @mark.record(event)
        @mark.save
        return log("ignored #{event.id}: already delivered") unless @seen.add?(event.id)
        return log("ignored #{event.id}: own #{event.action}") if event.creator_id == @identity.id

        line_for(event)
      end

      def line_for(event)
        if event.comment?
          return log("ignored #{event.id}: comment without mention") unless event.mentions?(@identity)

          %(MENTION card=#{event.card_number} comment=#{event.comment_id} by="#{event.creator_name}")
        elsif event.transition?
          %(TRANSITION card=#{event.card_number} state="#{event.card_state}" by="#{event.creator_name}")
        else
          log("ignored #{event.id}: #{event.action}")
        end
      end

      def log(message)
        @log.puts(message)
        nil
      end
  end

  # Where the watcher left off, so a restart can replay what the board's
  # activity feed saw in the meantime. Events are timestamped to the
  # millisecond, so the recent ids disambiguate events sharing the newest
  # instant.
  class Mark
    RECENT_IDS = 100

    def self.load(path)
      state = JSON.parse(File.read(path))
      new(path: path, last_event_at: state["last_event_at"]&.then { Time.iso8601(it) }, recent_ids: state.fetch("recent_ids", []))
    rescue Errno::ENOENT, JSON::ParserError
      new(path: path)
    end

    def initialize(path: nil, last_event_at: nil, recent_ids: [])
      @path = path
      @last_event_at = last_event_at
      @recent_ids = recent_ids
    end

    def empty? = @last_event_at.nil?

    def replay?(event)
      event = Event.new(event) if event.is_a?(Hash)
      return false if empty? || event.created_at.nil?

      event.created_at >= @last_event_at && !@recent_ids.include?(event.id)
    end

    def record(event)
      return if event.created_at.nil?

      if @last_event_at.nil? || event.created_at > @last_event_at
        @last_event_at = event.created_at
        @recent_ids = []
      end
      @recent_ids = (@recent_ids | [ event.id ]).last(RECENT_IDS) if event.created_at == @last_event_at
    end

    def save
      return unless @path

      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.generate("last_event_at" => @last_event_at&.utc&.iso8601(3), "recent_ids" => @recent_ids))
    rescue SystemCallError => error
      warn "could not save the mark to #{@path}: #{error.message}"
    end
  end

  # Replays activity-feed events newer than the mark, oldest first. `fetch`
  # returns one page of events (newest first) for a 1-based page number.
  class Catchup
    MAX_PAGES = 20

    def initialize(fetch:, pipeline:, mark:, max_pages: MAX_PAGES)
      @fetch = fetch
      @pipeline = pipeline
      @mark = mark
      @max_pages = max_pages
    end

    def run
      if @mark.empty?
        newest = @fetch.call(1).first
        @mark.record(Event.new(newest)) if newest
      else
        missed.reverse_each do |payload|
          line = @pipeline.replay(payload)
          yield line if line && block_given?
        end
      end
      @mark.save
    end

    private
      def missed
        events = []
        (1..@max_pages).each do |page|
          batch = @fetch.call(page)
          events.concat(batch.select { @mark.replay?(it) })
          break if batch.empty? || !@mark.replay?(batch.last)
        end
        events
      end
  end
end
