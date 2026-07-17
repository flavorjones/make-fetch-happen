require "test_helper"

class ArtifactUrlTest < ActiveSupport::TestCase
  test "passes through a clean github issue url" do
    assert_equal "https://github.com/a/b/issues/1",
      ArtifactUrl.normalize("https://github.com/a/b/issues/1")
  end

  test "strips trailing slash and fragment and upgrades scheme" do
    assert_equal "https://github.com/a/b/pull/2",
      ArtifactUrl.normalize("http://github.com/a/b/pull/2/#discussion_r1")
  end

  test "returns nil for blank or non-http input" do
    assert_nil ArtifactUrl.normalize(nil)
    assert_nil ArtifactUrl.normalize("  ")
    assert_nil ArtifactUrl.normalize("not a url")
    assert_nil ArtifactUrl.normalize("mailto:foo@bar.com")
  end
end
