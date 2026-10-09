require "cgi"
require "nokogiri"
require "time"

# The cards bin/fetch-gh-notifications writes for GitHub notifications, and the
# board it reads them back from. Nothing here touches the network.
#
# `route` picks the kind of notification. Each kind answers the same questions:
# the card's title, ref, tags, description and golden-ness, the comment for
# later activity, whether a Done card comes back while its artifact is open,
# and how GitHub should mark the notification once handled.
module FetchGhNotifications
  REASON_TAGS = {
    "mention"          => "mentioned",
    "review_requested" => "review",
    "assign"           => "assigned"
  }.freeze

  # A thread keeps the reason it was first notified for, so later activity on a
  # thread that mentioned Mike still arrives as a "mention".
  PARTICIPATION_COMMENTS = {
    "mention"          => "New GitHub activity on a thread that mentions you",
    "review_requested" => "New GitHub activity on a pull request that requests your review",
    "assign"           => "New GitHub activity on a thread assigned to you"
  }.freeze

  ADVISORY_COMMENTS = {
    "comment"      => "Someone commented on the report.",
    "subscribed"   => "There is new activity on the report.",
    "state_change" => "The report's state changed.",
    "assign"       => "The report was assigned to you."
  }.freeze

  module_function

  # `advisories` maps a repo's full name to its security advisories, and is
  # read only for advisory notifications.
  def route(notification, advisories)
    if notification.dig("subject", "type") == "RepositoryAdvisory"
      Advisory.for(notification, advisories[notification.dig("repository", "full_name")])
    elsif REASON_TAGS.key?(notification["reason"])
      Participation.new(notification)
    end
  end

  # The API URL of a pull request uses "pulls" and of a commit "commits"; the
  # web URLs use the singular.
  def web_url(api_url)
    api_url
      .sub("https://api.github.com/repos/", "https://github.com/")
      .sub(%r{/pulls/(\d+)\z}, '/pull/\1')
      .sub(%r{/commits/(\h+)\z}, '/commit/\1')
  end

  # Cards on the board were written by hand and by several scripts, so the ref
  # row comes in more than one shape.
  def frontmatter_refs(description_html)
    Nokogiri::HTML5.fragment(description_html.to_s).css("tr").filter_map do |row|
      key, value = row.css("th, td")
      next unless key&.text&.strip == "ref" && value

      url = value.at_css("a")&.[]("href") || value.text
      url.strip.sub(/\Ahttp:/, "https:").sub(/#.*\z/, "").chomp("/")
    end
  end

  def frontmatter(rows)
    cells = rows.map do |key, url|
      url = CGI.escapeHTML(url)
      %(<tr><th class="lexxy-content__table-cell--header"><p>#{key}</p></th><td><p><a href="#{url}">#{url}</a></p></td></tr>)
    end
    %(<figure class="lexxy-content__table-wrapper"><table><tbody>#{cells.join}</tbody></table></figure>)
  end

  # A mention, review request or assignment on an issue, pull request,
  # discussion or commit.
  Participation = Data.define(:notification) do
    def title = "#{notification.dig("repository", "name")}: #{notification.dig("subject", "title")}"
    def ref = FetchGhNotifications.web_url(notification.dig("subject", "url"))
    def keys = [ ref ]
    def golden? = false
    def reopens_while_open? = %w[PullRequest Issue Discussion].include?(notification.dig("subject", "type"))
    def mark = "read"

    def tags
      tags = [ REASON_TAGS.fetch(notification["reason"]) ]
      tags << "oss" unless notification.dig("repository", "private")
      tags << "37signals" if notification.dig("repository", "owner", "login") == "basecamp"
      tags
    end

    def description
      FetchGhNotifications.frontmatter([ [ "ref", ref ] ]) +
        "<p>GitHub notification reason: #{CGI.escapeHTML(notification["reason"])}</p>"
    end

    def activity_comment(comment_url)
      sentence = PARTICIPATION_COMMENTS.fetch(notification["reason"])
      comment_url ? "#{sentence}: [latest comment](#{comment_url})." : "#{sentence}."
    end
  end

  # A repository security advisory, whatever the reason GitHub notified.
  Advisory = Data.define(:notification, :advisory) do
    # The notification carries no link to its advisory (`subject.url` is null),
    # so the title is the only key. Titles can repeat within a repo; GitHub
    # notifies within a minute of updating the advisory, so the closest update
    # time breaks the tie.
    def self.for(notification, advisories)
      notified_at = Time.iso8601(notification["updated_at"])
      advisory = advisories
        .select { it["summary"] == notification.dig("subject", "title") }
        .min_by { (Time.iso8601(it["updated_at"]) - notified_at).abs }

      new(notification:, advisory:)
    end

    def title = "#{notification.dig("repository", "name")}: #{notification.dig("subject", "title")}"
    def ref = advisory&.fetch("html_url")
    def tags = %w[oss security]
    def golden? = true
    def reopens_while_open? = false
    def mark = "done"

    # Advisories in one repo can share a title, so the title is the key only
    # when the advisory couldn't be found.
    def keys = [ ref || title ]

    def description
      rows = []
      rows << [ "ref", ref ] if ref
      rows << [ "rel", "https://github.com/#{notification.dig("repository", "full_name")}/security/advisories" ]
      FetchGhNotifications.frontmatter(rows)
    end

    def activity_comment(_comment_url)
      reason = notification["reason"]
      ADVISORY_COMMENTS.fetch(reason) { "GitHub sent a `#{reason}` notification about the report." }
    end
  end

  # The cards already on the board, found by their refs and titles.
  class Board
    def initialize(cards)
      @cards = {}
      cards.each do |card|
        [ *FetchGhNotifications.frontmatter_refs(card["description_html"]), card["title"] ].each { @cards[it] ||= card }
      end
    end

    def find(item)
      item.keys.lazy.filter_map { @cards[it] }.first
    end

    def add(item, card)
      item.keys.each { @cards[it] ||= card }
    end
  end
end
