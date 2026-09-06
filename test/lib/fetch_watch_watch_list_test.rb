require "test_helper"

class FetchWatchWatchListTest < ActiveSupport::TestCase
  test "each board is watched with its own profile pair" do
    list = FetchWatch::WatchList.parse(JSON.generate("boards" => [
      { "board" => "Personal Backlog", "bot_profile" => "fetchbot_personal", "admin_profile" => "mike_personal" },
      { "board" => "Work", "bot_profile" => "fetchbot_37signals", "admin_profile" => "mike_37signals" }
    ]))

    assert_equal [ "Personal Backlog", "Work" ], list.map(&:board)
    assert_equal [ "fetchbot_personal", "fetchbot_37signals" ], list.map(&:bot_profile)
    assert_equal [ "mike_personal", "mike_37signals" ], list.map(&:admin_profile)
  end

  test "an entry without a profile is rejected" do
    error = assert_raises(FetchWatch::WatchList::Invalid) do
      FetchWatch::WatchList.parse(JSON.generate("boards" => [ { "board" => "Work" } ]))
    end
    assert_match(/bot_profile/, error.message)
  end

  test "an empty list is rejected" do
    assert_raises(FetchWatch::WatchList::Invalid) { FetchWatch::WatchList.parse(JSON.generate("boards" => [])) }
  end
end
