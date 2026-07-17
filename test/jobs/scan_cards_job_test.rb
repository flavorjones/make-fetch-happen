require "test_helper"

class ScanCardsJobTest < ActiveJob::TestCase
  FakeFizzy = Struct.new(:cards)
  FakeCards = Struct.new(:card_hashes) do
    def list(account_id:, board_ids:)
      card_hashes.each
    end
  end

  def fizzy_returning(card_hashes)
    FakeFizzy.new(FakeCards.new(card_hashes))
  end

  def card_hash(number:, title:, ref:)
    description_html = ref &&
      %(<table><tbody><tr><th><p>ref</p></th><td><p><a href="#{ref}">#{ref}</a></p></td></tr></tbody></table>)
    { "number" => number, "title" => title, "description_html" => description_html }
  end

  test "indexes cards that have a ref and skips cards that do not" do
    fizzy = fizzy_returning([
      card_hash(number: 1, title: "nokogiri: fix leak", ref: "https://github.com/sparklemotion/nokogiri/issues/1"),
      card_hash(number: 2, title: "groceries", ref: nil)
    ])

    FizzyClient.stub :build, fizzy do
      ScanCardsJob.perform_now
    end

    assert_equal 1, Card.count
    card = Card.first
    assert_equal "https://github.com/sparklemotion/nokogiri/issues/1", card.artifact_url
    assert_equal 1, card.fizzy_card_number
    assert_equal "nokogiri: fix leak", card.title
  end

  test "updates an existing index row in place" do
    Card.create!(artifact_url: "https://github.com/a/b/issues/1", fizzy_card_number: 1, title: "old title")
    fizzy = fizzy_returning([
      card_hash(number: 1, title: "new title", ref: "https://github.com/a/b/issues/1")
    ])

    FizzyClient.stub :build, fizzy do
      ScanCardsJob.perform_now
    end

    assert_equal 1, Card.count
    assert_equal "new title", Card.first.title
  end

  test "skips a card whose artifact url duplicates an earlier card and still completes the scan" do
    Card.create!(artifact_url: "https://github.com/a/b/issues/9", fizzy_card_number: 9, title: "stale")
    fizzy = fizzy_returning([
      card_hash(number: 1, title: "first", ref: "https://github.com/a/b/issues/1"),
      card_hash(number: 2, title: "dupe", ref: "https://github.com/a/b/issues/1")
    ])

    FizzyClient.stub :build, fizzy do
      ScanCardsJob.perform_now
    end

    assert_equal [ 1 ], Card.pluck(:fizzy_card_number)
    assert_equal "first", Card.find_by(fizzy_card_number: 1).title
  end

  test "deletes index rows for cards that no longer appear" do
    Card.create!(artifact_url: "https://github.com/a/b/issues/9", fizzy_card_number: 9, title: "gone")
    fizzy = fizzy_returning([
      card_hash(number: 1, title: "still here", ref: "https://github.com/a/b/issues/1")
    ])

    FizzyClient.stub :build, fizzy do
      ScanCardsJob.perform_now
    end

    assert_equal [ 1 ], Card.pluck(:fizzy_card_number)
  end
end
