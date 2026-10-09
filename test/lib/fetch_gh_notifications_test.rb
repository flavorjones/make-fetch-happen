require "test_helper"

class FetchGhNotificationsTest < ActiveSupport::TestCase
  test "a security advisory routes to an advisory, whatever the reason" do
    advisories = { "sparklemotion/nokogiri" => [ advisory("GHSA-bbbb", "NONET bypass on JRuby", "2026-10-05T14:14:05Z") ] }

    item = FetchGhNotifications.route(advisory_notification("NONET bypass on JRuby", reason: "subscribed"), advisories)

    assert_kind_of FetchGhNotifications::Advisory, item
    assert_equal "GHSA-bbbb", item.advisory["ghsa_id"]
  end

  test "a mention, review request or assignment routes to a participation" do
    %w[mention review_requested assign].each do |reason|
      assert_kind_of FetchGhNotifications::Participation, FetchGhNotifications.route(notification(reason), {})
    end
  end

  test "other notifications route nowhere" do
    assert_nil FetchGhNotifications.route(notification("subscribed"), {})
    assert_nil FetchGhNotifications.route(notification("team_mention"), {})
  end

  test "advisories are listed only for advisory notifications" do
    advisories = Hash.new { |_, repo| flunk "listed advisories for #{repo}" }

    assert_kind_of FetchGhNotifications::Participation, FetchGhNotifications.route(notification("mention"), advisories)
  end

  test "the web URL of a pull request, issue, discussion and commit" do
    assert_equal "https://github.com/rails/rails/pull/58781", FetchGhNotifications.web_url("https://api.github.com/repos/rails/rails/pulls/58781")
    assert_equal "https://github.com/rails/rails/issues/55881", FetchGhNotifications.web_url("https://api.github.com/repos/rails/rails/issues/55881")
    assert_equal "https://github.com/sparklemotion/nokogiri/discussions/3283", FetchGhNotifications.web_url("https://api.github.com/repos/sparklemotion/nokogiri/discussions/3283")
    assert_equal "https://github.com/rails/rails/commit/abc123", FetchGhNotifications.web_url("https://api.github.com/repos/rails/rails/commits/abc123")
  end

  test "refs are read from every frontmatter shape on the board" do
    lexxy = %(<figure class="lexxy-content__table-wrapper"><table><tbody><tr><th class="lexxy-content__table-cell--header"><p>ref</p></th><td><p><a href="https://github.com/a/b/pull/1">https://github.com/a/b/pull/1</a></p></td></tr></tbody></table></figure>)
    plain = %(<table><tbody><tr><th>ref</th><td><a href="https://github.com/a/b/pull/2">x</a></td></tr></tbody></table>)
    strong = %(<table><tbody><tr><td><strong>ref</strong></td><td><a href="https://github.com/a/b/pull/3">x</a></td></tr></tbody></table>)
    later_row = %(<table><tbody><tr><td><p>rel</p></td><td><p><a href="https://github.com/a/b/issues/9">x</a></p></td></tr><tr><td><p>ref</p></td><td><p><a href="https://github.com/a/b/pull/4">x</a></p></td></tr></tbody></table>)
    text_only = %(<table><tbody><tr><th>ref</th><td>https://github.com/a/b/pull/5</td></tr></tbody></table>)

    assert_equal [ "https://github.com/a/b/pull/1" ], FetchGhNotifications.frontmatter_refs(lexxy)
    assert_equal [ "https://github.com/a/b/pull/2" ], FetchGhNotifications.frontmatter_refs(plain)
    assert_equal [ "https://github.com/a/b/pull/3" ], FetchGhNotifications.frontmatter_refs(strong)
    assert_equal [ "https://github.com/a/b/pull/4" ], FetchGhNotifications.frontmatter_refs(later_row)
    assert_equal [ "https://github.com/a/b/pull/5" ], FetchGhNotifications.frontmatter_refs(text_only)
  end

  test "a card with several ref rows has every ref" do
    html = %(<table><tbody><tr><th>ref</th><td><a href="https://github.com/a/b/security/advisories/GHSA-1">x</a></td></tr><tr><th>ref</th><td><a href="https://github.com/a/b/security/advisories/GHSA-2">x</a></td></tr></tbody></table>)

    assert_equal [ "https://github.com/a/b/security/advisories/GHSA-1", "https://github.com/a/b/security/advisories/GHSA-2" ], FetchGhNotifications.frontmatter_refs(html)
  end

  test "a ref with http, a fragment or a trailing slash matches the bare artifact URL" do
    html = %(<table><tbody><tr><th>ref</th><td><a href="http://github.com/a/b/pull/1/#issuecomment-1">x</a></td></tr></tbody></table>)

    assert_equal [ "https://github.com/a/b/pull/1" ], FetchGhNotifications.frontmatter_refs(html)
  end

  test "a description without frontmatter has no refs" do
    assert_empty FetchGhNotifications.frontmatter_refs(nil)
    assert_empty FetchGhNotifications.frontmatter_refs("<p>just prose</p>")
  end

  test "a participation cards the artifact it is about" do
    item = FetchGhNotifications::Participation.new(notification("mention", repo: "rails/rails", path: "pulls/58781", title: "Stop setting the ACL"))

    assert_equal "rails: Stop setting the ACL", item.title
    assert_equal "https://github.com/rails/rails/pull/58781", item.ref
    assert_not item.golden?
    assert_equal "read", item.mark
  end

  test "participation tags say how Mike is involved and whose repo it is" do
    assert_equal %w[mentioned oss], FetchGhNotifications::Participation.new(notification("mention", repo: "rails/rails")).tags
    assert_equal %w[review oss], FetchGhNotifications::Participation.new(notification("review_requested", repo: "rubysec/ruby-advisory-db")).tags
    assert_equal %w[assigned 37signals], FetchGhNotifications::Participation.new(notification("assign", repo: "basecamp/launchpad")).tags
  end

  test "a participation description refs the artifact and names the reason" do
    description = FetchGhNotifications::Participation.new(notification("mention", repo: "a/b", path: "pulls/1")).description

    assert_equal [ "https://github.com/a/b/pull/1" ], FetchGhNotifications.frontmatter_refs(description)
    assert_includes description, "GitHub notification reason: mention"
  end

  test "a participation activity comment says why GitHub notified and links the latest comment" do
    assert_equal "New GitHub activity on a thread that mentions you.", FetchGhNotifications::Participation.new(notification("mention")).activity_comment(nil)
    assert_equal "New GitHub activity on a pull request that requests your review.", FetchGhNotifications::Participation.new(notification("review_requested")).activity_comment(nil)
    assert_equal "New GitHub activity on a thread assigned to you.", FetchGhNotifications::Participation.new(notification("assign")).activity_comment(nil)
    assert_equal "New GitHub activity on a thread that mentions you: [latest comment](https://github.com/a/b/pull/1#issuecomment-9).",
      FetchGhNotifications::Participation.new(notification("mention")).activity_comment("https://github.com/a/b/pull/1#issuecomment-9")
  end

  test "an advisory is found by the notification's title" do
    advisories = [
      advisory("GHSA-aaaa", "Use-after-free in XPathContext", "2026-10-02T23:17:33Z"),
      advisory("GHSA-bbbb", "NONET bypass on JRuby", "2026-10-05T14:14:05Z")
    ]

    item = FetchGhNotifications::Advisory.for(advisory_notification("NONET bypass on JRuby", updated_at: "2026-10-05T14:14:39Z"), advisories)

    assert_equal "https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-bbbb", item.ref
  end

  test "advisories sharing a title are told apart by the closest update time" do
    advisories = [
      advisory("GHSA-aaaa", "Attribute injection", "2026-02-23T03:38:11Z"),
      advisory("GHSA-bbbb", "Attribute injection", "2026-02-26T09:10:54Z")
    ]

    item = FetchGhNotifications::Advisory.for(advisory_notification("Attribute injection", updated_at: "2026-02-23T03:38:40Z"), advisories)

    assert_equal "GHSA-aaaa", item.advisory["ghsa_id"]
  end

  test "an advisory with no matching title has no ref" do
    advisories = [ advisory("GHSA-aaaa", "Use-after-free in XPathContext", "2026-10-02T23:17:33Z") ]

    item = FetchGhNotifications::Advisory.for(advisory_notification("Renamed since", updated_at: "2026-10-02T23:17:57Z"), advisories)

    assert_nil item.ref
  end

  test "an advisory makes a golden security card that is marked done" do
    item = FetchGhNotifications::Advisory.for(advisory_notification("NONET bypass on JRuby"), [])

    assert_equal "nokogiri: NONET bypass on JRuby", item.title
    assert_equal %w[oss security], item.tags
    assert item.golden?
    assert_equal "done", item.mark
  end

  test "an advisory description refs the advisory and rels the security page" do
    advisories = [ advisory("GHSA-bbbb", "NONET bypass on JRuby", "2026-10-05T14:14:05Z") ]

    description = FetchGhNotifications::Advisory.for(advisory_notification("NONET bypass on JRuby"), advisories).description

    assert_equal [
      [ "ref", "https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-bbbb" ],
      [ "rel", "https://github.com/sparklemotion/nokogiri/security/advisories" ]
    ], rows(description)
  end

  test "an advisory description rels only the security page when no advisory was found" do
    description = FetchGhNotifications::Advisory.for(advisory_notification("NONET bypass on JRuby"), []).description

    assert_equal [ [ "rel", "https://github.com/sparklemotion/nokogiri/security/advisories" ] ], rows(description)
  end

  test "an advisory activity comment says why GitHub notified" do
    {
      "comment"                  => "Someone commented on the report.",
      "state_change"             => "The report's state changed.",
      "assign"                   => "The report was assigned to you.",
      "subscribed"               => "There is new activity on the report.",
      "security_advisory_credit" => "GitHub sent a `security_advisory_credit` notification about the report."
    }.each do |reason, comment|
      assert_equal comment, FetchGhNotifications::Advisory.for(advisory_notification("x", reason: reason), []).activity_comment(nil)
    end
  end

  test "the board finds a card by any of its refs, on any lane" do
    open_card = card(600, "rails: Fix it", "https://github.com/rails/rails/pull/1")
    done_card = card(227, "mechanize: cross-host redirect header leak",
      "https://github.com/sparklemotion/mechanize/security/advisories/GHSA-1111",
      "https://github.com/sparklemotion/mechanize/security/advisories/GHSA-2222")
    board = FetchGhNotifications::Board.new([ open_card, done_card ])
    advisories = [ advisory("GHSA-2222", "Mechanize sends credential headers to another host", "2026-10-05T14:14:05Z", repo: "sparklemotion/mechanize") ]

    assert_equal open_card, board.find(FetchGhNotifications::Participation.new(notification("mention", repo: "rails/rails", path: "pulls/1")))
    assert_equal done_card, board.find(FetchGhNotifications::Advisory.for(
      advisory_notification("Mechanize sends credential headers to another host", repo: "sparklemotion/mechanize"), advisories))
  end

  test "the board finds an advisory card by title when the advisory has no ref" do
    nokogiri = card(618, "nokogiri: NONET bypass on JRuby")
    board = FetchGhNotifications::Board.new([ nokogiri ])

    assert_equal nokogiri, board.find(FetchGhNotifications::Advisory.for(advisory_notification("NONET bypass on JRuby"), []))
  end

  test "the board does not find an advisory by title when the advisory has a ref" do
    board = FetchGhNotifications::Board.new([ card(618, "nokogiri: Attribute injection", "https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-aaaa") ])
    advisories = [ advisory("GHSA-bbbb", "Attribute injection", "2026-02-26T09:10:54Z") ]

    assert_nil board.find(FetchGhNotifications::Advisory.for(advisory_notification("Attribute injection"), advisories))
  end

  test "the board never finds a participation by title" do
    board = FetchGhNotifications::Board.new([ card(600, "rails: Bump rack", "https://github.com/rails/rails/pull/1") ])

    assert_nil board.find(FetchGhNotifications::Participation.new(notification("mention", repo: "rails/rails", path: "pulls/2", title: "Bump rack")))
  end

  test "the board finds a card it was told about" do
    board = FetchGhNotifications::Board.new([])
    item = FetchGhNotifications::Participation.new(notification("mention", repo: "rails/rails", path: "pulls/1"))
    created = { "number" => "700" }

    board.add(item, created)

    assert_equal created, board.find(item)
  end

  private
    def notification(reason, repo: "rails/rails", path: "pulls/1", title: "Fix it")
      owner, name = repo.split("/")
      { "reason" => reason, "updated_at" => "2026-10-07T00:00:00Z",
        "repository" => { "name" => name, "full_name" => repo, "private" => owner == "basecamp", "owner" => { "login" => owner } },
        "subject" => { "title" => title, "type" => "PullRequest", "url" => "https://api.github.com/repos/#{repo}/#{path}" } }
    end

    def advisory_notification(title, repo: "sparklemotion/nokogiri", reason: "subscribed", updated_at: "2026-10-05T14:14:39Z")
      owner, name = repo.split("/")
      { "reason" => reason, "updated_at" => updated_at,
        "repository" => { "name" => name, "full_name" => repo, "private" => false, "owner" => { "login" => owner } },
        "subject" => { "title" => title, "type" => "RepositoryAdvisory", "url" => nil } }
    end

    def advisory(ghsa_id, summary, updated_at, repo: "sparklemotion/nokogiri")
      { "ghsa_id" => ghsa_id, "summary" => summary, "updated_at" => updated_at,
        "html_url" => "https://github.com/#{repo}/security/advisories/#{ghsa_id}" }
    end

    def card(number, title, *refs)
      rows = refs.map { %(<tr><th>ref</th><td><a href="#{it}">#{it}</a></td></tr>) }
      { "number" => number, "title" => title, "description_html" => "<table><tbody>#{rows.join}</tbody></table>" }
    end

    def rows(html)
      Nokogiri::HTML5.fragment(html).css("tr").map do |tr|
        [ tr.at_css("th.lexxy-content__table-cell--header").text, tr.at_css("td a")["href"] ]
      end
    end
end
