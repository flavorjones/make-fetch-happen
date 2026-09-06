require "test_helper"

class FetchWatchCatchupTest < ActiveSupport::TestCase
  HARRY = FetchWatch::Identity.new(id: "user-harry", name: "Harry")
  MIKE  = { "id" => "user-mike", "name" => "Mike Dalessio" }

  setup do
    @path = Rails.root.join("tmp", "fetch-watch-catchup-test-#{SecureRandom.hex(4)}.json")
    @mark = FetchWatch::Mark.load(@path, board: "board-1")
    @pipeline = FetchWatch::Pipeline.new(identity: HARRY, secret: "s3cret", mark: @mark, log: StringIO.new)
  end

  teardown do
    File.delete(@path) if File.exist?(@path)
  end

  test "a first run replays nothing but marks the newest event" do
    lines = catch_up(pages: [ [ move("e3", "10:03", "Paused"), move("e2", "10:02", "Next") ] ])

    assert_empty lines
    refute @mark.empty?
    refute @mark.replay?(move("e3", "10:03", "Paused"))
    assert @mark.replay?(move("e4", "10:04", "Done"))
  end

  test "events since the mark are replayed oldest first" do
    @mark.record(FetchWatch::Event.new(move("e1", "10:01", "Next")))

    lines = catch_up(pages: [ [ move("e3", "10:03", "Paused"), move("e2", "10:02", "In Progress"), move("e1", "10:01", "Next") ] ])

    assert_equal [
      'TRANSITION account=6097036 card=113 state="In Progress" by="Mike Dalessio"',
      'TRANSITION account=6097036 card=113 state="Paused" by="Mike Dalessio"'
    ], lines
  end

  test "replay keeps paging until it passes the mark" do
    @mark.record(FetchWatch::Event.new(move("e1", "10:01", "Next")))

    lines = catch_up(pages: [
      [ move("e4", "10:04", "Done") ],
      [ move("e3", "10:03", "Paused") ],
      [ move("e2", "10:02", "In Progress"), move("e1", "10:01", "Next") ],
      [ move("e0", "10:00", "Maybe?") ]
    ])

    assert_equal 3, lines.length
    assert_equal 'TRANSITION account=6097036 card=113 state="In Progress" by="Mike Dalessio"', lines.first
  end

  test "replayed events pass through the same filters as deliveries" do
    @mark.record(FetchWatch::Event.new(move("e1", "10:01", "Next")))
    own = move("e2", "10:02", "Paused").merge("creator" => { "id" => "user-harry", "name" => "Harry" })
    chatter = comment("e3", "10:03", "<p>no mention here</p>")

    assert_empty catch_up(pages: [ [ chatter, own ] ])
  end

  test "replay advances the mark" do
    @mark.record(FetchWatch::Event.new(move("e1", "10:01", "Next")))
    catch_up(pages: [ [ move("e2", "10:02", "Paused") ] ])

    refute @mark.replay?(move("e2", "10:02", "Paused"))
  end

  test "a delivery advances the mark even when ignored" do
    own = move("e2", "10:02", "Paused").merge("creator" => { "id" => "user-harry", "name" => "Harry" })
    body = JSON.generate(own)

    assert_nil @pipeline.process(body: body, signature: OpenSSL::HMAC.hexdigest("SHA256", "s3cret", body))
    refute @mark.replay?(own)
  end

  test "an event the webhook already delivered is not emitted again by a poll" do
    @mark.record(FetchWatch::Event.new(move("e1", "10:01", "Next")))
    delivered = move("e2", "10:02", "Paused")
    body = JSON.generate(delivered)

    assert_equal 'TRANSITION account=6097036 card=113 state="Paused" by="Mike Dalessio"',
      @pipeline.process(body: body, signature: OpenSSL::HMAC.hexdigest("SHA256", "s3cret", body))

    assert_empty catch_up(pages: [ [ delivered ] ])
  end

  test "a poll acknowledges a mention the webhook never delivered" do
    @mark.record(FetchWatch::Event.new(move("e1", "10:01", "Next")))
    acknowledged = []
    pipeline = FetchWatch::Pipeline.new(identity: HARRY, secret: "s3cret", mark: @mark, log: StringIO.new,
      acknowledge: ->(event) { acknowledged << event.id })

    lines = catch_up(pages: [ [ mention("e2", "10:02") ] ], pipeline: pipeline, acknowledge: true)

    assert_equal 1, lines.length
    assert_equal [ "e2" ], acknowledged
  end

  test "the startup catch-up does not acknowledge what it replays" do
    @mark.record(FetchWatch::Event.new(move("e1", "10:01", "Next")))
    acknowledged = []
    pipeline = FetchWatch::Pipeline.new(identity: HARRY, secret: "s3cret", mark: @mark, log: StringIO.new,
      acknowledge: ->(event) { acknowledged << event.id })

    lines = catch_up(pages: [ [ mention("e2", "10:02") ] ], pipeline: pipeline)

    assert_equal 1, lines.length
    assert_empty acknowledged
  end

  private
    def catch_up(pages:, pipeline: @pipeline, acknowledge: false)
      fetch = ->(page) { pages[page - 1] || [] }
      lines = []
      FetchWatch::Catchup.new(fetch: fetch, pipeline: pipeline, mark: @mark, acknowledge: acknowledge).run { |line| lines << line }
      lines
    end

    def mention(id, time)
      comment(id, time, %(<p><action-text-attachment content-type="application/vnd.actiontext.mention" ) +
        %(content="&lt;img src=&quot;/6097036/users/user-harry/avatar&quot;&gt;"></action-text-attachment> hello</p>))
    end

    def move(id, time, column)
      { "id" => id, "action" => "card_triaged", "created_at" => "2026-08-21T#{time}:00.000Z", "creator" => MIKE,
        "eventable" => { "number" => 113, "closed" => false, "postponed" => false, "column" => { "name" => column },
                         "url" => "https://app.fizzy.do/6097036/cards/113" } }
    end

    def comment(id, time, html)
      { "id" => id, "action" => "comment_created", "created_at" => "2026-08-21T#{time}:00.000Z", "creator" => MIKE,
        "eventable" => { "id" => "c-#{id}", "body" => { "html" => html, "plain_text" => "text" },
                         "card" => { "url" => "https://app.fizzy.do/6097036/cards/113" } } }
    end
end
