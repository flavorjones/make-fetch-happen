require "test_helper"

class CardTest < ActiveSupport::TestCase
  test "requires artifact_url and fizzy_card_number" do
    card = Card.new
    assert_not card.valid?
    assert_includes card.errors[:artifact_url], "can't be blank"
    assert_includes card.errors[:fizzy_card_number], "can't be blank"
  end

  test "enforces unique artifact_url" do
    Card.create!(artifact_url: "https://github.com/a/b/issues/1", fizzy_card_number: 1)
    dupe = Card.new(artifact_url: "https://github.com/a/b/issues/1", fizzy_card_number: 2)
    assert_not dupe.valid?
  end

  test "extracts and normalizes the ref frontmatter link" do
    html = <<~HTML
      <div class="action-text-content">
      <figure class="lexxy-content__table-wrapper"><table><tbody>
      <tr><th class="lexxy-content__table-cell--header"><p>ref</p></th><td><p><a href="https://github.com/a/b/issues/1/">https://github.com/a/b/issues/1/</a></p></td></tr>
      <tr><th class="lexxy-content__table-cell--header"><p>worktree</p></th><td><p>/home/me/work</p></td></tr>
      </tbody></table></figure>
      <p>Body text.</p>
      </div>
    HTML
    assert_equal "https://github.com/a/b/issues/1", Card.extract_artifact_url(html)
  end

  test "extracts a ref that is plain text rather than a link" do
    html = %(<table><tbody><tr><th><p>ref</p></th><td><p>https://github.com/a/b/pull/2</p></td></tr></tbody></table>)
    assert_equal "https://github.com/a/b/pull/2", Card.extract_artifact_url(html)
  end

  test "returns nil when there is no ref row" do
    html = %(<table><tbody><tr><th><p>worktree</p></th><td><p>/home/me/work</p></td></tr></tbody></table>)
    assert_nil Card.extract_artifact_url(html)
    assert_nil Card.extract_artifact_url(nil)
  end
end
