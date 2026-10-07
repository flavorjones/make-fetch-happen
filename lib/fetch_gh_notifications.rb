require "cgi"
require "nokogiri"

# The card content bin/fetch-gh-notifications writes for a notification, and
# the refs it reads back from existing cards. Nothing here touches the network.
module FetchGhNotifications
  REASON_TAGS = {
    "mention"          => "mentioned",
    "review_requested" => "review",
    "assign"           => "assigned"
  }.freeze

  module_function

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

  def tags(notification)
    tags = [ REASON_TAGS.fetch(notification["reason"]) ]
    tags << "oss" unless notification.dig("repository", "private")
    tags << "37signals" if notification.dig("repository", "owner", "login") == "basecamp"
    tags
  end

  def description(ref, reason)
    ref = CGI.escapeHTML(ref)
    <<~HTML
      <figure class="lexxy-content__table-wrapper"><table><tbody>
      <tr><th class="lexxy-content__table-cell--header"><p>ref</p></th><td><p><a href="#{ref}">#{ref}</a></p></td></tr>
      </tbody></table></figure>
      <p>GitHub notification reason: #{reason}</p>
    HTML
  end
end
