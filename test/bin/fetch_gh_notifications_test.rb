require "test_helper"
require "open3"

# Runs bin/fetch-gh-notifications against fake `gh` and `fizzy` executables
# that answer from canned JSON and log every call.
class FetchGhNotificationsScriptTest < ActiveSupport::TestCase
  setup do
    @dir = Rails.root.join("tmp", "fetch-gh-notifications-test-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@dir)
    @lanes = Hash.new { |lanes, lane| lanes[lane] = [] }
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "a mention becomes a tagged card that refs the pull request, and is marked read" do
    run_script notification("41", "mention", "rails/rails", "pulls/58781", "Stop setting the ACL")

    create = fizzy_calls("card", "create").sole
    assert_equal "rails: Stop setting the ACL", argument(create, "--title")
    assert_includes argument(create, "--description"), %(href="https://github.com/rails/rails/pull/58781")
    assert_equal %w[mentioned oss], fizzy_calls("card", "tag").map { argument(it, "--tag") }
    assert_equal [ "/notifications/threads/41" ], marked_read
  end

  test "an artifact already carded in any lane gets no second card, and is marked read" do
    @lanes["closed"] << card("https://github.com/rails/rails/pull/58781")

    run_script notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL")

    assert_empty fizzy_calls("card", "create")
    assert_equal [ "/notifications/threads/41" ], marked_read
  end

  test "two notifications about one artifact make one card" do
    run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "Fix it", updated_at: "2026-10-06T00:00:00Z"),
      notification("42", "review_requested", "rails/rails", "pulls/1", "Fix it", updated_at: "2026-10-07T00:00:00Z")

    assert_equal 1, fizzy_calls("card", "create").size
    assert_equal %w[review oss], fizzy_calls("card", "tag").map { argument(it, "--tag") }
    assert_equal %w[/notifications/threads/42 /notifications/threads/41], marked_read
  end

  test "other reasons and security advisories are left alone" do
    run_script \
      notification("41", "subscribed", "rails/rails", "pulls/1", "Watching"),
      notification("42", "team_mention", "basecamp/launchpad", "pulls/2", "Team"),
      notification("43", "assign", "sparklemotion/nokogiri", nil, "Use-after-free", type: "RepositoryAdvisory")

    assert_empty fizzy_calls("card", "create")
    assert_empty marked_read
  end

  test "a dry run creates nothing and marks nothing read" do
    run_script notification("41", "mention", "rails/rails", "pulls/1", "Fix it"), args: [ "--dry-run" ]

    assert_empty fizzy_calls("card", "create")
    assert_empty marked_read
  end

  private
    def notification(id, reason, repo, path, title, type: "PullRequest", updated_at: "2026-10-07T00:00:00Z")
      owner, name = repo.split("/")
      { "id" => id, "reason" => reason, "updated_at" => updated_at,
        "repository" => { "name" => name, "full_name" => repo, "private" => owner == "basecamp", "owner" => { "login" => owner } },
        "subject" => { "title" => title, "type" => type, "url" => path && "https://api.github.com/repos/#{repo}/#{path}" } }
    end

    def card(ref)
      { "number" => 600, "description_html" => FetchGhNotifications.description(ref, "mention") }
    end

    def run_script(*notifications, args: [])
      File.write(@dir.join("notifications.json"), [ notifications ].to_json)
      @lanes.each { |lane, cards| File.write(@dir.join("cards-#{lane}.json"), { data: cards }.to_json) }
      fake("gh", <<~'RUBY')
        if ARGV.include?("PATCH") then exit
        else print File.read(File.join(DIR, "notifications.json"))
        end
      RUBY
      fake("fizzy", <<~'RUBY')
        if ARGV.first(2) == %w[card list]
          path = File.join(DIR, "cards-#{ARGV[ARGV.index("--indexed-by") + 1]}.json")
          print File.exist?(path) ? File.read(path) : { data: [] }.to_json
        elsif ARGV.first(2) == %w[card create] then print({ data: { number: 700 } }.to_json)
        else print({ data: {} }.to_json)
        end
      RUBY

      env = { "PATH" => "#{@dir}:#{ENV["PATH"]}" }
      output, status = Open3.capture2e(env, Rails.root.join("bin", "fetch-gh-notifications").to_s, *args)
      assert status.success?, output
    end

    def fake(name, body)
      path = @dir.join(name)
      File.write(path, <<~RUBY + body)
        #!/usr/bin/env ruby
        require "json"
        DIR = #{@dir.to_s.inspect}
        File.open(File.join(DIR, "#{name}.log"), "a") { it.puts ARGV.to_json }
      RUBY
      File.chmod(0o755, path)
    end

    def calls(name)
      path = @dir.join("#{name}.log")
      File.exist?(path) ? File.readlines(path).map { JSON.parse(it) } : []
    end

    def fizzy_calls(*command)
      calls("fizzy").select { it.first(command.size) == command }
    end

    def marked_read
      calls("gh").select { it.include?("PATCH") }.map(&:last)
    end

    def argument(call, flag)
      call[call.index(flag) + 1]
    end
end
