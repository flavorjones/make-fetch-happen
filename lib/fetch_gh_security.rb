require "cgi"
require "time"

# The card content bin/fetch-gh-security writes for a security-advisory
# notification. Nothing here touches the network.
module FetchGhSecurity
  ACTIVITY_COMMENTS = {
    "comment"      => "Someone commented on the report.",
    "subscribed"   => "There is new activity on the report.",
    "state_change" => "The report's state changed.",
    "assign"       => "The report was assigned to you."
  }.freeze

  module_function

  # The notification carries no link to its advisory (`subject.url` is null),
  # so the title is the only key. Titles can repeat within a repo; GitHub
  # notifies within a minute of updating the advisory, so the closest update
  # time breaks the tie.
  def advisory_for(notification, advisories)
    notified_at = Time.iso8601(notification["updated_at"])

    advisories
      .select { it["summary"] == notification.dig("subject", "title") }
      .min_by { (Time.iso8601(it["updated_at"]) - notified_at).abs }
  end

  def frontmatter(repo, advisory)
    rows = []
    rows << [ "ref", advisory["html_url"] ] if advisory
    rows << [ "rel", "https://github.com/#{repo}/security/advisories" ]

    cells = rows.map do |key, url|
      url = CGI.escapeHTML(url)
      %(<tr><th class="lexxy-content__table-cell--header"><p>#{key}</p></th><td><p><a href="#{url}">#{url}</a></p></td></tr>)
    end
    %(<figure class="lexxy-content__table-wrapper"><table><tbody>#{cells.join}</tbody></table></figure>)
  end

  def activity_comment(reason)
    ACTIVITY_COMMENTS.fetch(reason) { "GitHub sent a `#{reason}` notification about the report." }
  end
end
