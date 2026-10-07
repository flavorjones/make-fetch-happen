require "test_helper"
require "open3"

# Runs bin/fetch-gh-security against fake `gh` and `fizzy` executables that
# answer from canned JSON and log every call.
class FetchGhSecurityScriptTest < ActiveSupport::TestCase
  setup do
    @dir = Rails.root.join("tmp", "fetch-gh-security-test-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@dir)
    @cards = []
    @advisories = {}
  end

  teardown do
    FileUtils.rm_rf(@dir)
  end

  test "a new card refs the advisory matching the notification" do
    @advisories["sparklemotion/nokogiri"] = [
      { "ghsa_id" => "GHSA-bbbb", "summary" => "NONET bypass on JRuby", "updated_at" => "2026-10-05T14:14:05Z",
        "html_url" => "https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-bbbb" }
    ]

    run_script notification("sparklemotion/nokogiri", "NONET bypass on JRuby", "subscribed")

    assert_includes created_description, "https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-bbbb"
  end

  test "a repo whose advisories can't be listed still gets a card" do
    run_script notification("sparklemotion/nokogiri", "NONET bypass on JRuby", "subscribed")

    assert_includes created_description, "<p>rel</p>"
    refute_includes created_description, "<p>ref</p>"
    assert calls("gh").any? { it.include?("DELETE") }
  end

  test "an existing card gets a comment saying why GitHub notified" do
    @cards << { "number" => 618, "title" => "nokogiri: NONET bypass on JRuby" }

    run_script notification("sparklemotion/nokogiri", "NONET bypass on JRuby", "state_change")

    comment = calls("fizzy").find { it.first(2) == %w[comment create] }
    assert_equal "The report's state changed.", comment[comment.index("--body") + 1]
  end

  private
    def notification(repo, title, reason)
      { "id" => "1", "reason" => reason, "updated_at" => "2026-10-05T14:14:39Z",
        "repository" => { "full_name" => repo },
        "subject" => { "title" => title, "type" => "RepositoryAdvisory", "url" => nil } }
    end

    def run_script(*notifications)
      File.write(@dir.join("notifications.json"), notifications.to_json)
      File.write(@dir.join("cards.json"), { data: @cards }.to_json)
      @advisories.each { |repo, list| File.write(@dir.join("#{repo.tr("/", "_")}.json"), [ list ].to_json) }
      fake("gh", <<~'RUBY')
        if ARGV.include?("DELETE") then exit
        elsif (repo = ARGV.last[%r{/repos/(.+)/security-advisories}, 1])
          path = File.join(DIR, "#{repo.tr("/", "_")}.json")
          abort "HTTP 404" unless File.exist?(path)
          print File.read(path)
        elsif ARGV.last.include?("before=") then print "[]"
        else print File.read(File.join(DIR, "notifications.json"))
        end
      RUBY
      fake("fizzy", <<~'RUBY')
        if ARGV.first(2) == %w[card list] then print File.read(File.join(DIR, "cards.json"))
        elsif ARGV.first(2) == %w[card create] then print({ data: { number: 700 } }.to_json)
        else print({ data: {} }.to_json)
        end
      RUBY

      env = { "PATH" => "#{@dir}:#{ENV["PATH"]}" }
      output, status = Open3.capture2e(env, Rails.root.join("bin", "fetch-gh-security").to_s)
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
      File.readlines(@dir.join("#{name}.log")).map { JSON.parse(it) }
    end

    def created_description
      create = calls("fizzy").find { it.first(2) == %w[card create] }
      create[create.index("--description") + 1]
    end
end
