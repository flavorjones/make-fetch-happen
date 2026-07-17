require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  test "lists cards with fizzy number, title, and artifact url" do
    Card.create!(artifact_url: "https://github.com/a/b/issues/1", fizzy_card_number: 42, title: "b: fix the thing")

    get cards_url

    assert_response :success
    assert_select "td", text: /42/
    assert_select "td", text: "b: fix the thing"
    assert_select "a[href=?]", "https://github.com/a/b/issues/1"
  end

  test "paginates at 50 per page" do
    60.times do |i|
      Card.create!(artifact_url: "https://github.com/a/b/issues/#{i}", fizzy_card_number: i, title: "card #{i}")
    end

    get cards_url
    assert_select "tbody tr", count: 50

    get cards_url(page: 2)
    assert_select "tbody tr", count: 10
  end
end
