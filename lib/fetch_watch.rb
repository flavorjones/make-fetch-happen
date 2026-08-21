require "json"
require "openssl"

# Turns signed Fizzy webhook deliveries into the one-line events bin/fetch-watch
# prints for the fetch-monitor skill:
#
#   MENTION card=<number> comment=<id> by="<creator>"
#   TRANSITION card=<number> state="<state>" by="<creator>"
#
# Everything here is pure: no network, no shelling out. The runtime plumbing
# (funnel, webhook registration, HTTP server) lives in bin/fetch-watch.
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

    # "Done" and "Not Now" are flags on the card, not columns, and a card keeps
    # its last column when it enters either -- so check the flags first.
    def card_state
      return "Done" if eventable["closed"]
      return "Not Now" if eventable["postponed"]

      column = eventable.dig("column", "name")
      column.nil? || column.empty? ? "Maybe?" : column
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
  end

  class Pipeline
    def initialize(identity:, secret:, log: $stderr)
      @identity = identity
      @secret = secret
      @log = log
      @seen = Set.new
    end

    def process(body:, signature:)
      return log("rejected: bad signature") unless Signature.valid?(body: body, signature: signature, secret: @secret)

      event = Event.new(JSON.parse(body))
      return log("ignored #{event.id}: already delivered") unless @seen.add?(event.id)
      return log("ignored #{event.id}: own #{event.action}") if event.creator_id == @identity.id

      line_for(event)
    rescue JSON::ParserError
      log("rejected: malformed payload")
    end

    private
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
end
