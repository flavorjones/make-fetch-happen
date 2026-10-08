require "test_helper"

class FetchGhNotificationsTest < ActiveSupport::TestCase
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

  test "a ref with http, a fragment or a trailing slash matches the bare artifact URL" do
    html = %(<table><tbody><tr><th>ref</th><td><a href="http://github.com/a/b/pull/1/#issuecomment-1">x</a></td></tr></tbody></table>)

    assert_equal [ "https://github.com/a/b/pull/1" ], FetchGhNotifications.frontmatter_refs(html)
  end

  test "a description without frontmatter has no refs" do
    assert_empty FetchGhNotifications.frontmatter_refs(nil)
    assert_empty FetchGhNotifications.frontmatter_refs("<p>just prose</p>")
  end

  test "tags say how Mike is involved and whose repo it is" do
    assert_equal %w[mentioned oss], FetchGhNotifications.tags(notification("mention", "rails", private: false))
    assert_equal %w[review oss], FetchGhNotifications.tags(notification("review_requested", "rubysec", private: false))
    assert_equal %w[assigned 37signals], FetchGhNotifications.tags(notification("assign", "basecamp", private: true))
  end

  test "the description refs the artifact and names the reason" do
    description = FetchGhNotifications.description("https://github.com/a/b/pull/1", "mention")

    assert_equal [ "https://github.com/a/b/pull/1" ], FetchGhNotifications.frontmatter_refs(description)
    assert_includes description, "GitHub notification reason: mention"
  end

  test "the activity comment says why GitHub notified and links the latest comment" do
    assert_equal "New GitHub activity on a thread that mentions you.", FetchGhNotifications.activity_comment("mention", nil)
    assert_equal "New GitHub activity on a pull request that requests your review.", FetchGhNotifications.activity_comment("review_requested", nil)
    assert_equal "New GitHub activity on a thread assigned to you.", FetchGhNotifications.activity_comment("assign", nil)
    assert_equal "New GitHub activity on a thread that mentions you: [latest comment](https://github.com/a/b/pull/1#issuecomment-9).",
      FetchGhNotifications.activity_comment("mention", "https://github.com/a/b/pull/1#issuecomment-9")
  end

  private
    def notification(reason, owner, private:)
      { "reason" => reason, "repository" => { "owner" => { "login" => owner }, "private" => private } }
    end
end
