require "test_helper"

class FetchWatchKeepaliveTest < ActiveSupport::TestCase
  test "the keepalive is mounted when the funnel proxies /keepalive to the discard port" do
    assert FetchWatch::Keepalive.mounted?(funnel_status("/keepalive" => "http://127.0.0.1:9", "/fizzy/abc" => "http://127.0.0.1:4000/fizzy/abc"))
  end

  test "the keepalive is not mounted when the funnel has no /keepalive path" do
    refute FetchWatch::Keepalive.mounted?(funnel_status("/fizzy/abc" => "http://127.0.0.1:4000/fizzy/abc"))
  end

  test "the keepalive is not mounted when /keepalive proxies somewhere else" do
    refute FetchWatch::Keepalive.mounted?(funnel_status("/keepalive" => "http://127.0.0.1:4000"))
  end

  test "the keepalive is not mounted when the funnel is off" do
    refute FetchWatch::Keepalive.mounted?("{}")
  end

  private
    def funnel_status(handlers)
      JSON.generate("Web" => { "host.ts.net:443" => { "Handlers" => handlers.transform_values { { "Proxy" => it } } } })
    end
end
