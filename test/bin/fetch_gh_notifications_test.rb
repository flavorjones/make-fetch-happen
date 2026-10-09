require "test_helper"
require "open3"

# Runs bin/fetch-gh-notifications against fake `gh` and `fizzy` executables
# that answer from canned JSON and log every call.
class FetchGhNotificationsScriptTest < ActiveSupport::TestCase
  setup do
    @dir = Rails.root.join("tmp", "fetch-gh-notifications-test-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@dir)
    @lanes = Hash.new { |lanes, lane| lanes[lane] = [] }
    @comments = {}
    @states = {}
    @advisories = {}
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

  test "the script says what it is reading" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/1")

    output = run_script

    assert_match(/open cards.*1/, output)
    assert_match(/closed cards.*0/, output)
    assert_match(/not-now cards.*0/, output)
  end

  test "an artifact already carded in any lane gets a comment instead of a second card, and is marked read" do
    @lanes["not_now"] << card("https://github.com/rails/rails/pull/58781", number: 600)

    run_script notification("41", "mention", "rails/rails", "pulls/58781", "Stop setting the ACL")

    assert_empty fizzy_calls("card", "create")
    comment = fizzy_calls("comment", "create").sole
    assert_equal "600", argument(comment, "--card")
    assert_equal "New GitHub activity on a thread that mentions you.", argument(comment, "--body")
    assert_equal [ "/notifications/threads/41" ], marked_read
  end

  test "the comment links the latest GitHub comment when there is one" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/58781", number: 600)
    @comments["https://api.github.com/repos/rails/rails/issues/comments/9"] = "https://github.com/rails/rails/pull/58781#issuecomment-9"

    run_script notification("41", "mention", "rails/rails", "pulls/58781", "Stop setting the ACL",
      latest_comment_url: "https://api.github.com/repos/rails/rails/issues/comments/9")

    assert_equal "New GitHub activity on a thread that mentions you: [latest comment](https://github.com/rails/rails/pull/58781#issuecomment-9).",
      argument(fizzy_calls("comment", "create").sole, "--body")
  end

  test "a done review card moves back to Next while its pull request is open" do
    @lanes["closed"] << card("https://github.com/rails/rails/pull/58781", number: 600, tags: %w[review oss], closed: true)
    @states["https://api.github.com/repos/rails/rails/pulls/58781"] = "open"

    run_script notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL")

    assert_equal "New GitHub activity on a pull request that requests your review.", argument(fizzy_calls("comment", "create").sole, "--body")
    move = fizzy_calls("card", "column").sole
    assert_equal [ "600", "col-next" ], [ move[2], argument(move, "--column") ]
  end

  test "a done review card for a merged or closed pull request stays done, and still gets the comment" do
    @lanes["closed"] << card("https://github.com/rails/rails/pull/58781", number: 600, tags: %w[review oss], closed: true)
    @states["https://api.github.com/repos/rails/rails/pulls/58781"] = "closed"

    run_script notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL")

    assert_equal 1, fizzy_calls("comment", "create").size
    assert_empty fizzy_calls("card", "column")
    assert_equal [ "/notifications/threads/41" ], marked_read
  end

  test "a done review card stays done when its pull request can't be read" do
    @lanes["closed"] << card("https://github.com/rails/rails/pull/58781", number: 600, tags: %w[review oss], closed: true)

    run_script notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL")

    assert_equal 1, fizzy_calls("comment", "create").size
    assert_empty fizzy_calls("card", "column")
  end

  test "a done review card moves once however many notifications it gets" do
    @lanes["closed"] << card("https://github.com/rails/rails/pull/58781", number: 600, tags: %w[review oss], closed: true)
    @states["https://api.github.com/repos/rails/rails/pulls/58781"] = "open"

    run_script \
      notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL", updated_at: "2026-10-07T00:00:00Z"),
      notification("42", "mention", "rails/rails", "pulls/58781", "Stop setting the ACL", updated_at: "2026-10-06T00:00:00Z")

    assert_equal 2, fizzy_calls("comment", "create").size
    assert_equal 1, fizzy_calls("card", "column").size
  end

  test "a latest comment that can't be read leaves the link out" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/58781", number: 600)

    run_script notification("41", "mention", "rails/rails", "pulls/58781", "Stop setting the ACL",
      latest_comment_url: "https://api.github.com/repos/rails/rails/issues/comments/404")

    assert_equal "New GitHub activity on a thread that mentions you.", argument(fizzy_calls("comment", "create").sole, "--body")
    assert_equal [ "/notifications/threads/41" ], marked_read
  end

  test "a done card moves back to Next while its issue or discussion is open, whatever its tags" do
    @lanes["closed"] << card("https://github.com/basecamp/hotcell/discussions/107", number: 649, tags: %w[oss], closed: true)
    @lanes["closed"] << card("https://github.com/rails/rails/issues/55881", number: 650, tags: %w[mentioned oss], closed: true)
    @states["https://api.github.com/repos/basecamp/hotcell/discussions/107"] = "open"
    @states["https://api.github.com/repos/rails/rails/issues/55881"] = "open"

    run_script \
      notification("41", "mention", "basecamp/hotcell", "discussions/107", "Using a Docker Cell From Rails Running on macOS", type: "Discussion"),
      notification("42", "mention", "rails/rails", "issues/55881", "Flaky test", type: "Issue")

    assert_equal %w[649 650], fizzy_calls("card", "column").map { it[2] }.sort
  end

  test "a done card for a closed issue stays done" do
    @lanes["closed"] << card("https://github.com/rails/rails/issues/55881", number: 650, tags: %w[mentioned oss], closed: true)
    @states["https://api.github.com/repos/rails/rails/issues/55881"] = "closed"

    run_script notification("42", "mention", "rails/rails", "issues/55881", "Flaky test", type: "Issue")

    assert_equal 1, fizzy_calls("comment", "create").size
    assert_empty fizzy_calls("card", "column")
  end

  test "a done security advisory card stays done" do
    @lanes["closed"] << card("https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-bbbb",
      number: 618, title: "nokogiri: NONET bypass on JRuby", tags: %w[oss security], closed: true)
    @advisories["sparklemotion/nokogiri"] = [ advisory("sparklemotion/nokogiri", "GHSA-bbbb", "NONET bypass on JRuby") ]

    run_script advisory_notification("43", "sparklemotion/nokogiri", "NONET bypass on JRuby", "comment")

    assert_equal 1, fizzy_calls("comment", "create").size
    assert_empty fizzy_calls("card", "column")
  end

  test "an open review card stays where it is" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/58781", number: 600, tags: %w[review oss])

    run_script notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL")

    assert_empty fizzy_calls("card", "column")
  end

  test "two notifications about one artifact make one card, and the older one comments on it" do
    run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "Fix it", updated_at: "2026-10-06T00:00:00Z"),
      notification("42", "review_requested", "rails/rails", "pulls/1", "Fix it", updated_at: "2026-10-07T00:00:00Z")

    assert_equal 1, fizzy_calls("card", "create").size
    assert_equal %w[review oss], fizzy_calls("card", "tag").map { argument(it, "--tag") }
    assert_equal [ [ "700", "New GitHub activity on a thread that mentions you." ] ], fizzy_calls("comment", "create").map { [ argument(it, "--card"), argument(it, "--body") ] }
    assert_equal %w[/notifications/threads/42 /notifications/threads/41], marked_read
  end

  test "other reasons are left alone" do
    run_script \
      notification("41", "subscribed", "rails/rails", "pulls/1", "Watching"),
      notification("42", "team_mention", "basecamp/launchpad", "pulls/2", "Team")

    assert_empty fizzy_calls("card", "create")
    assert_empty marked_read
  end

  test "a security advisory becomes a golden security card that refs the advisory, and is marked done" do
    @advisories["sparklemotion/nokogiri"] = [ advisory("sparklemotion/nokogiri", "GHSA-bbbb", "NONET bypass on JRuby") ]

    run_script advisory_notification("43", "sparklemotion/nokogiri", "NONET bypass on JRuby", "subscribed")

    create = fizzy_calls("card", "create").sole
    assert_equal "nokogiri: NONET bypass on JRuby", argument(create, "--title")
    assert_includes argument(create, "--description"), %(href="https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-bbbb")
    assert_equal %w[oss security], fizzy_calls("card", "tag").map { argument(it, "--tag") }
    assert_equal [ %w[card golden 700] ], fizzy_calls("card", "golden").map { it.first(3) }
    assert_equal [ "/notifications/threads/43" ], marked_done
    assert_empty marked_read
  end

  test "a security advisory whose repo's advisories can't be listed still gets a card" do
    run_script advisory_notification("43", "sparklemotion/nokogiri", "NONET bypass on JRuby", "subscribed")

    description = argument(fizzy_calls("card", "create").sole, "--description")
    assert_includes description, "<p>rel</p>"
    refute_includes description, "<p>ref</p>"
    assert_equal [ "/notifications/threads/43" ], marked_done
  end

  test "a security advisory already reffed by a done card gets a comment instead of a second card" do
    @lanes["closed"] << card("https://github.com/sparklemotion/mechanize/security/advisories/GHSA-2mwr",
      number: 227, title: "mechanize: cross-host redirect header leak", closed: true)
    @advisories["sparklemotion/mechanize"] = [ advisory("sparklemotion/mechanize", "GHSA-2mwr", "Mechanize sends credential headers to another host after an HTTP redirect") ]

    run_script advisory_notification("43", "sparklemotion/mechanize", "Mechanize sends credential headers to another host after an HTTP redirect", "comment")

    assert_empty fizzy_calls("card", "create")
    comment = fizzy_calls("comment", "create").sole
    assert_equal [ "227", "Someone commented on the report." ], [ argument(comment, "--card"), argument(comment, "--body") ]
    assert_empty fizzy_calls("card", "column")
    assert_equal [ "/notifications/threads/43" ], marked_done
  end

  test "a security advisory card without a ref is found by its title" do
    @lanes["all"] << { "number" => 618, "title" => "nokogiri: NONET bypass on JRuby", "tags" => %w[oss security], "closed" => false }

    run_script advisory_notification("43", "sparklemotion/nokogiri", "NONET bypass on JRuby", "state_change")

    assert_empty fizzy_calls("card", "create")
    assert_equal [ [ "618", "The report's state changed." ] ], fizzy_calls("comment", "create").map { [ argument(it, "--card"), argument(it, "--body") ] }
  end

  test "advisories are listed once per repo" do
    @advisories["sparklemotion/nokogiri"] = [ advisory("sparklemotion/nokogiri", "GHSA-bbbb", "NONET bypass on JRuby") ]

    run_script \
      advisory_notification("43", "sparklemotion/nokogiri", "NONET bypass on JRuby", "subscribed"),
      advisory_notification("44", "sparklemotion/nokogiri", "Use-after-free", "subscribed")

    assert_equal 1, calls("gh").count { it.last.include?("/security-advisories") }
  end

  test "a dry run creates, comments, moves and marks nothing" do
    @lanes["closed"] << card("https://github.com/rails/rails/pull/2", tags: %w[review], closed: true)
    @states["https://api.github.com/repos/rails/rails/pulls/2"] = "open"

    run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "Fix it"),
      notification("42", "review_requested", "rails/rails", "pulls/2", "Review it"),
      advisory_notification("43", "sparklemotion/nokogiri", "NONET bypass on JRuby", "subscribed"),
      args: [ "--dry-run" ]

    assert_empty fizzy_calls("card", "create")
    assert_empty fizzy_calls("card", "golden")
    assert_empty fizzy_calls("comment", "create")
    assert_empty fizzy_calls("card", "column")
    assert_empty marked_read
    assert_empty marked_done
  end

  private
    def notification(id, reason, repo, path, title, type: "PullRequest", updated_at: "2026-10-07T00:00:00Z", latest_comment_url: nil)
      owner, name = repo.split("/")
      { "id" => id, "reason" => reason, "updated_at" => updated_at,
        "repository" => { "name" => name, "full_name" => repo, "private" => owner == "basecamp", "owner" => { "login" => owner } },
        "subject" => { "title" => title, "type" => type, "url" => path && "https://api.github.com/repos/#{repo}/#{path}",
                       "latest_comment_url" => latest_comment_url } }
    end

    def advisory_notification(id, repo, title, reason)
      owner, name = repo.split("/")
      { "id" => id, "reason" => reason, "updated_at" => "2026-10-05T14:14:39Z",
        "repository" => { "name" => name, "full_name" => repo, "private" => false, "owner" => { "login" => owner } },
        "subject" => { "title" => title, "type" => "RepositoryAdvisory", "url" => nil, "latest_comment_url" => nil } }
    end

    def advisory(repo, ghsa_id, summary)
      { "ghsa_id" => ghsa_id, "summary" => summary, "updated_at" => "2026-10-05T14:14:05Z",
        "html_url" => "https://github.com/#{repo}/security/advisories/#{ghsa_id}" }
    end

    def card(ref, number: 600, title: "rails: Some card", tags: [], closed: false)
      { "number" => number, "title" => title, "tags" => tags, "closed" => closed, "description_html" => FetchGhNotifications.frontmatter([ [ "ref", ref ] ]) }
    end

    def run_script(*notifications, args: [])
      File.write(@dir.join("notifications.json"), [ notifications ].to_json)
      @lanes.each { |lane, cards| File.write(@dir.join("cards-#{lane}.json"), { data: cards }.to_json) }
      File.write(@dir.join("comments.json"), @comments.to_json)
      File.write(@dir.join("states.json"), @states.to_json)
      @advisories.each { |repo, list| File.write(@dir.join("advisories-#{repo.tr("/", "_")}.json"), [ list ].to_json) }
      fake("gh", <<~'RUBY')
        if ARGV.include?("PATCH") || ARGV.include?("DELETE") then exit
        elsif (repo = ARGV.last[%r{/repos/(.+)/security-advisories}, 1])
          path = File.join(DIR, "advisories-#{repo.tr("/", "_")}.json")
          abort "HTTP 404" unless File.exist?(path)
          print File.read(path)
        elsif ARGV.last.start_with?("/notifications?") then print File.read(File.join(DIR, "notifications.json"))
        elsif (html_url = JSON.parse(File.read(File.join(DIR, "comments.json")))[ARGV.last])
          print({ html_url: html_url }.to_json)
        elsif (state = JSON.parse(File.read(File.join(DIR, "states.json")))[ARGV.last])
          print({ state: state }.to_json)
        else abort "HTTP 404: #{ARGV.last}"
        end
      RUBY
      fake("fizzy", <<~'RUBY')
        if ARGV.first(2) == %w[card list]
          path = File.join(DIR, "cards-#{ARGV[ARGV.index("--indexed-by") + 1]}.json")
          print File.exist?(path) ? File.read(path) : { data: [] }.to_json
        elsif ARGV.first(2) == %w[card create] then print({ data: { number: 700 } }.to_json)
        elsif ARGV.first(2) == %w[column list] then print({ data: [ { id: "col-next", name: "Next" }, { id: "col-ip", name: "In Progress" } ] }.to_json)
        else print({ data: {} }.to_json)
        end
      RUBY

      env = { "PATH" => "#{@dir}:#{ENV["PATH"]}" }
      output, status = Open3.capture2e(env, Rails.root.join("bin", "fetch-gh-notifications").to_s, *args)
      assert status.success?, output
      output
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

    def marked_done
      calls("gh").select { it.include?("DELETE") }.map(&:last)
    end

    def argument(call, flag)
      call[call.index(flag) + 1]
    end
end
