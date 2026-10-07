require "test_helper"

class FetchGhSecurityTest < ActiveSupport::TestCase
  test "an advisory is found by the notification's title" do
    advisories = [
      advisory("GHSA-aaaa", "Use-after-free in XPathContext", "2026-10-02T23:17:33Z"),
      advisory("GHSA-bbbb", "NONET bypass on JRuby", "2026-10-05T14:14:05Z")
    ]

    found = FetchGhSecurity.advisory_for(notification("NONET bypass on JRuby", "2026-10-05T14:14:39Z"), advisories)

    assert_equal "GHSA-bbbb", found["ghsa_id"]
  end

  test "advisories sharing a title are told apart by the closest update time" do
    advisories = [
      advisory("GHSA-aaaa", "Attribute injection", "2026-02-23T03:38:11Z"),
      advisory("GHSA-bbbb", "Attribute injection", "2026-02-26T09:10:54Z")
    ]

    found = FetchGhSecurity.advisory_for(notification("Attribute injection", "2026-02-23T03:38:40Z"), advisories)

    assert_equal "GHSA-aaaa", found["ghsa_id"]
  end

  test "no advisory is found when no title matches" do
    advisories = [ advisory("GHSA-aaaa", "Use-after-free in XPathContext", "2026-10-02T23:17:33Z") ]

    assert_nil FetchGhSecurity.advisory_for(notification("Renamed since", "2026-10-02T23:17:57Z"), advisories)
  end

  test "the frontmatter refs the advisory and rels the security page" do
    frontmatter = FetchGhSecurity.frontmatter("sparklemotion/nokogiri", advisory("GHSA-bbbb", "NONET bypass on JRuby", "2026-10-05T14:14:05Z"))

    assert_equal [
      [ "ref", "https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-bbbb" ],
      [ "rel", "https://github.com/sparklemotion/nokogiri/security/advisories" ]
    ], rows(frontmatter)
  end

  test "the frontmatter rels only the security page when no advisory was found" do
    frontmatter = FetchGhSecurity.frontmatter("sparklemotion/nokogiri", nil)

    assert_equal [ [ "rel", "https://github.com/sparklemotion/nokogiri/security/advisories" ] ], rows(frontmatter)
  end

  test "the activity comment says why GitHub notified" do
    assert_equal "Someone commented on the report.", FetchGhSecurity.activity_comment("comment")
    assert_equal "The report's state changed.", FetchGhSecurity.activity_comment("state_change")
    assert_equal "The report was assigned to you.", FetchGhSecurity.activity_comment("assign")
    assert_equal "There is new activity on the report.", FetchGhSecurity.activity_comment("subscribed")
    assert_equal "GitHub sent a `security_advisory_credit` notification about the report.", FetchGhSecurity.activity_comment("security_advisory_credit")
  end

  private
    def advisory(ghsa_id, summary, updated_at)
      { "ghsa_id" => ghsa_id, "summary" => summary, "updated_at" => updated_at,
        "html_url" => "https://github.com/sparklemotion/nokogiri/security/advisories/#{ghsa_id}" }
    end

    def notification(title, updated_at)
      { "subject" => { "title" => title, "type" => "RepositoryAdvisory" }, "updated_at" => updated_at }
    end

    def rows(html)
      Nokogiri::HTML5.fragment(html).css("tr").map do |tr|
        [ tr.at_css("th.lexxy-content__table-cell--header").text, tr.at_css("td a")["href"] ]
      end
    end
end
