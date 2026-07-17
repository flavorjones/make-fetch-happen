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
end
