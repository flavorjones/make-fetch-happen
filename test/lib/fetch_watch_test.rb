require "test_helper"

class FetchWatchTest < ActiveSupport::TestCase
  HARRY = FetchWatch::Identity.new(id: "user-harry", name: "Harry")
  MIKE  = { "id" => "user-mike", "name" => "Mike Dalessio" }
  SECRET = "s3cret"

  setup do
    @pipeline = FetchWatch::Pipeline.new(identity: HARRY, secret: SECRET, log: StringIO.new)
  end

  test "a column move is a transition into that column" do
    assert_equal 'TRANSITION card=113 state="Researching" by="Mike Dalessio"',
      process(card_event("card_triaged", column: "Researching"))
  end

  test "closing a card is a transition into Done" do
    assert_equal 'TRANSITION card=113 state="Done" by="Mike Dalessio"',
      process(card_event("card_closed", column: "In Progress", closed: true))
  end

  test "postponing a card is a transition into Not Now" do
    assert_equal 'TRANSITION card=113 state="Not Now" by="Mike Dalessio"',
      process(card_event("card_postponed", column: "Next", postponed: true))
  end

  test "a card with no column is in Maybe?" do
    assert_equal 'TRANSITION card=113 state="Maybe?" by="Mike Dalessio"',
      process(card_event("card_sent_back_to_triage", column: nil))
  end

  test "a comment mentioning me is a mention" do
    assert_equal 'MENTION card=369 comment=comment-1 by="Mike Dalessio"',
      process(comment_event(mention_html("user-harry", "Harry")))
  end

  test "a comment mentioning me by plain-text handle is a mention" do
    assert_equal 'MENTION card=369 comment=comment-1 by="Mike Dalessio"',
      process(comment_event("<p>hey</p>", plain_text: "@Harry please look"))
  end

  test "a comment that does not mention me is ignored" do
    assert_nil process(comment_event("<p>Released in v2.9.6</p>"))
  end

  test "a comment mentioning someone else is ignored" do
    assert_nil process(comment_event(mention_html("user-other", "Gretchen")))
  end

  test "my own events are ignored" do
    assert_nil process(card_event("card_triaged", column: "Paused", creator: { "id" => "user-harry", "name" => "Harry" }))
  end

  test "a redelivered event is ignored" do
    payload = card_event("card_triaged", column: "Next")
    refute_nil process(payload)
    assert_nil process(payload)
  end

  test "a bad signature is rejected" do
    body = JSON.generate(card_event("card_triaged", column: "Next"))
    assert_nil @pipeline.process(body: body, signature: "deadbeef")
  end

  test "a missing signature is rejected" do
    body = JSON.generate(card_event("card_triaged", column: "Next"))
    assert_nil @pipeline.process(body: body, signature: nil)
  end

  test "malformed json is rejected" do
    assert_nil @pipeline.process(body: "{nope", signature: sign("{nope"))
  end

  test "an unknown action is ignored" do
    assert_nil process(card_event("card_assigned", column: "Next"))
  end

  private
    def process(payload)
      body = JSON.generate(payload)
      @pipeline.process(body: body, signature: sign(body))
    end

    def sign(body)
      OpenSSL::HMAC.hexdigest("SHA256", SECRET, body)
    end

    def card_event(action, column:, closed: false, postponed: false, creator: MIKE)
      card = { "id" => "card-113", "number" => 113, "closed" => closed, "postponed" => postponed,
               "url" => "https://app.fizzy.do/6097036/cards/113" }
      card["column"] = { "id" => "col-1", "name" => column } if column

      { "id" => "event-#{action}-#{column}", "action" => action, "eventable" => card, "creator" => creator }
    end

    def comment_event(html, plain_text: "text", creator: MIKE)
      { "id" => "event-comment-1", "action" => "comment_created", "creator" => creator,
        "eventable" => {
          "id" => "comment-1",
          "body" => { "html" => html, "plain_text" => plain_text },
          "card" => { "id" => "card-369", "url" => "https://app.fizzy.do/6097036/cards/369" } } }
    end

    def mention_html(user_id, name)
      %(<p><action-text-attachment sgid="x" content-type="application/vnd.actiontext.mention">) +
        %(<img src="https://app.fizzy.do/6097036/users/#{user_id}/avatar">#{name}</action-text-attachment> look</p>)
    end
end
