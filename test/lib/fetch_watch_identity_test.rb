require "test_helper"

class FetchWatchIdentityTest < ActiveSupport::TestCase
  ACCOUNTS = [
    { "slug" => "/5986089", "user" => { "id" => "user-harry-work", "name" => "Harry (Mike's Agent)", "role" => "member" } },
    { "slug" => "/6097036", "user" => { "id" => "user-harry", "name" => "Harry", "role" => "admin" } }
  ]

  test "the identity is the user on the profile's account, not the first account listed" do
    identity = FetchWatch::Identity.on_account("6097036", ACCOUNTS)

    assert_equal "user-harry", identity.id
    assert_equal "Harry", identity.name
    assert_equal "admin", identity.role
  end

  test "a token that does not reach the account has no identity there" do
    assert_nil FetchWatch::Identity.on_account("1", ACCOUNTS)
  end
end
