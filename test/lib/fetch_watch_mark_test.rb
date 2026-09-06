require "test_helper"

class FetchWatchMarkTest < ActiveSupport::TestCase
  setup do
    @path = Rails.root.join("tmp", "fetch-watch-mark-test-#{SecureRandom.hex(4)}.json")
  end

  teardown do
    File.delete(@path) if File.exist?(@path)
  end

  test "an empty mark replays nothing" do
    mark = FetchWatch::Mark.load(@path, board: "board-1")

    assert mark.empty?
    refute mark.replay?(event("e1", "2026-08-21T10:00:00.000Z"))
  end

  test "events newer than the mark are replayed" do
    mark = FetchWatch::Mark.load(@path, board: "board-1")
    mark.record(event("e1", "2026-08-21T10:00:00.000Z"))

    refute mark.replay?(event("e0", "2026-08-21T09:59:59.999Z"))
    assert mark.replay?(event("e2", "2026-08-21T10:00:00.001Z"))
  end

  test "an event at the same instant as the mark is replayed unless already seen" do
    mark = FetchWatch::Mark.load(@path, board: "board-1")
    mark.record(event("e1", "2026-08-21T10:00:00.000Z"))

    refute mark.replay?(event("e1", "2026-08-21T10:00:00.000Z"))
    assert mark.replay?(event("e2", "2026-08-21T10:00:00.000Z"))
  end

  test "recording an older event does not move the mark backwards" do
    mark = FetchWatch::Mark.load(@path, board: "board-1")
    mark.record(event("e2", "2026-08-21T10:00:00.000Z"))
    mark.record(event("e1", "2026-08-21T09:00:00.000Z"))

    refute mark.replay?(event("e3", "2026-08-21T09:30:00.000Z"))
  end

  test "the mark survives a save and load" do
    mark = FetchWatch::Mark.load(@path, board: "board-1")
    mark.record(event("e1", "2026-08-21T10:00:00.000Z"))
    mark.save

    reloaded = FetchWatch::Mark.load(@path, board: "board-1")

    refute reloaded.empty?
    refute reloaded.replay?(event("e1", "2026-08-21T10:00:00.000Z"))
    assert reloaded.replay?(event("e2", "2026-08-21T10:00:00.000Z"))
  end

  test "saving creates the parent directory" do
    nested = Rails.root.join("tmp", "fetch-watch-mark-#{SecureRandom.hex(4)}", "last.json")
    mark = FetchWatch::Mark.load(nested, board: "board-1")
    mark.record(event("e1", "2026-08-21T10:00:00.000Z"))
    mark.save

    assert File.exist?(nested)
  ensure
    FileUtils.rm_rf(nested.dirname)
  end

  test "boards keep separate marks in one file" do
    personal = FetchWatch::Mark.load(@path, board: "board-personal")
    personal.record(event("e1", "2026-08-21T10:00:00.000Z"))
    personal.save
    work = FetchWatch::Mark.load(@path, board: "board-work")
    work.record(event("w1", "2026-08-21T11:00:00.000Z"))
    work.save

    reloaded = FetchWatch::Mark.load(@path, board: "board-personal")

    assert reloaded.replay?(event("e2", "2026-08-21T10:30:00.000Z"))
    refute FetchWatch::Mark.load(@path, board: "board-work").replay?(event("w0", "2026-08-21T10:30:00.000Z"))
  end

  test "a mark from before boards were keyed is not read as any board's mark" do
    File.write(@path, JSON.generate("last_event_at" => "2026-08-21T10:00:00.000Z", "recent_ids" => []))

    assert FetchWatch::Mark.load(@path, board: "board-personal").empty?
  end

  test "only recent ids are kept" do
    mark = FetchWatch::Mark.load(@path, board: "board-1")
    101.times { |i| mark.record(event("e#{i}", "2026-08-21T10:00:00.000Z")) }

    assert mark.replay?(event("e0", "2026-08-21T10:00:00.000Z"))
    refute mark.replay?(event("e100", "2026-08-21T10:00:00.000Z"))
  end

  private
    def event(id, created_at)
      FetchWatch::Event.new("id" => id, "created_at" => created_at)
    end
end
