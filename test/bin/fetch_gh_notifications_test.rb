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
    assert_equal %w[mentioned oss p/rails], fizzy_calls("card", "tag").map { argument(it, "--tag") }
    assert_equal [ "/notifications/threads/41" ], marked_read
  end

  test "a merged or closed pull request, issue or discussion without a card is skipped, and is marked read" do
    @states["https://api.github.com/repos/rails/rails/pulls/58781"] = "closed"
    @states["https://api.github.com/repos/rails/rails/issues/55881"] = "closed"
    @states["https://api.github.com/repos/basecamp/hotcell/discussions/107"] = "closed"

    output = run_script \
      notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL"),
      notification("42", "mention", "rails/rails", "issues/55881", "Flaky test", type: "Issue"),
      notification("43", "mention", "basecamp/hotcell", "discussions/107", "Using a Docker Cell", type: "Discussion")

    assert_empty fizzy_calls("card", "create")
    assert_match %r{already closed, skipping.*https://github.com/rails/rails/pull/58781}, output
    assert_match %r{already closed, skipping.*https://github.com/rails/rails/issues/55881}, output
    assert_match %r{already closed, skipping.*https://github.com/basecamp/hotcell/discussions/107}, output
    assert_equal %w[/notifications/threads/41 /notifications/threads/42 /notifications/threads/43], marked_read.sort
  end

  test "an open pull request without a card, or one whose state can't be read, gets a card" do
    @states["https://api.github.com/repos/rails/rails/pulls/1"] = "open"

    run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "Open"),
      notification("42", "mention", "rails/rails", "pulls/404", "Unreadable")

    assert_equal [ "rails: Open", "rails: Unreadable" ], fizzy_calls("card", "create").map { argument(it, "--title") }.sort
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
    assert_equal %w[review oss p/rails], fizzy_calls("card", "tag").map { argument(it, "--tag") }
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
    assert_equal %w[oss security p/nokogiri], fizzy_calls("card", "tag").map { argument(it, "--tag") }
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

  test "a failed fizzy call shows the error fizzy printed" do
    @fizzy_error = { code: "api_error", error: "Server error (500)", ok: false }

    output = run_script notification("41", "mention", "rails/rails", "pulls/1", "Fix it"), success: false

    assert_match(/failed: .*Server error \(500\)/, output)
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

  test "a blank line sets the action lines apart from the reading lines and the summary" do
    @states["https://api.github.com/repos/rails/rails/pulls/1"] = "open"

    output = run_script notification("41", "mention", "rails/rails", "pulls/1", "Fix it")

    reading, actions, summary = output.split("\n\n")
    assert_match(/\Areading open cards/, reading)
    assert_equal 1, actions.lines.size
    assert_match(/\Adone/, summary)
  end

  test "each handled notification prints one line, led by an emoji for what happened to its card" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/2", number: 602)
    @lanes["closed"] << card("https://github.com/rails/rails/pull/3", number: 603, closed: true)
    @states["https://api.github.com/repos/rails/rails/pulls/1"] = "open"
    @states["https://api.github.com/repos/rails/rails/pulls/3"] = "open"
    @states["https://api.github.com/repos/rails/rails/pulls/4"] = "closed"

    output = run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "New", updated_at: "2026-10-07T00:00:04Z"),
      notification("42", "mention", "rails/rails", "pulls/2", "Bumped", updated_at: "2026-10-07T00:00:03Z"),
      notification("43", "mention", "rails/rails", "pulls/3", "Reactivated", updated_at: "2026-10-07T00:00:02Z"),
      notification("44", "mention", "rails/rails", "pulls/4", "Ignored", updated_at: "2026-10-07T00:00:01Z")

    assert_equal %w[✨ ⏫ 🔙 🫟], action_lines(output).map { it.split(" ").first.delete("💬") }
  end

  test "a dry run prints one line per handled notification too" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/2", number: 602)
    @lanes["closed"] << card("https://github.com/rails/rails/pull/3", number: 603, closed: true)
    @states["https://api.github.com/repos/rails/rails/pulls/1"] = "open"
    @states["https://api.github.com/repos/rails/rails/pulls/3"] = "open"
    @states["https://api.github.com/repos/rails/rails/pulls/4"] = "closed"

    output = run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "New", updated_at: "2026-10-07T00:00:04Z"),
      notification("42", "mention", "rails/rails", "pulls/2", "Bumped", updated_at: "2026-10-07T00:00:03Z"),
      notification("43", "mention", "rails/rails", "pulls/3", "Reactivated", updated_at: "2026-10-07T00:00:02Z"),
      notification("44", "mention", "rails/rails", "pulls/4", "Ignored", updated_at: "2026-10-07T00:00:01Z"),
      args: [ "--dry-run" ]

    assert_equal %w[✨ ⏫ 🔙 🫟], action_lines(output).map { it.split(" ").first.delete("💬") }
  end

  test "the action emoji is followed by an emoji for each security, review or mentioned tag" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/2", number: 602, tags: %w[security review oss])
    @states["https://api.github.com/repos/rails/rails/pulls/1"] = "open"
    @states["https://api.github.com/repos/rails/rails/pulls/3"] = "open"
    @advisories["sparklemotion/nokogiri"] = [ advisory("sparklemotion/nokogiri", "GHSA-bbbb", "NONET bypass on JRuby") ]

    output = run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "Mentioned", updated_at: "2026-10-07T00:00:03Z"),
      notification("42", "mention", "rails/rails", "pulls/2", "Tagged by hand", updated_at: "2026-10-07T00:00:02Z"),
      notification("43", "assign", "rails/rails", "pulls/3", "Assigned", updated_at: "2026-10-07T00:00:01Z"),
      advisory_notification("44", "sparklemotion/nokogiri", "NONET bypass on JRuby", "subscribed")

    assert_equal %w[✨💬 ⏫🔒👀 ✨ ✨🔒], action_lines(output).map { it.split(" ").first }
  end

  test "a card number links to the card" do
    @lanes["all"] << card("https://github.com/rails/rails/pull/2", number: 602)
    @states["https://api.github.com/repos/rails/rails/pulls/1"] = "open"

    output = run_script \
      notification("41", "mention", "rails/rails", "pulls/1", "New", updated_at: "2026-10-07T00:00:02Z"),
      notification("42", "mention", "rails/rails", "pulls/1", "New", updated_at: "2026-10-07T00:00:01Z"),
      notification("43", "mention", "rails/rails", "pulls/2", "Bumped")

    links = action_lines(output).map { it[/\e\]8;;.*?\e\]8;;\e\\/] }
    assert_equal [ "\e]8;;https://app.fizzy.do/6097036/cards/700\e\\#700\e]8;;\e\\" ] * 2 +
      [ "\e]8;;https://app.fizzy.do/6097036/cards/602\e\\#602\e]8;;\e\\" ], links
  end

  test "a dry run bumps a card it would already have moved to Next" do
    @lanes["closed"] << card("https://github.com/rails/rails/pull/58781", number: 600, closed: true)
    @states["https://api.github.com/repos/rails/rails/pulls/58781"] = "open"

    output = run_script \
      notification("41", "review_requested", "rails/rails", "pulls/58781", "Stop setting the ACL", updated_at: "2026-10-07T00:00:00Z"),
      notification("42", "mention", "rails/rails", "pulls/58781", "Stop setting the ACL", updated_at: "2026-10-06T00:00:00Z"),
      args: [ "--dry-run" ]

    assert_equal %w[🔙 ⏫], action_lines(output).map { it.split(" ").first }
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
      { "number" => number, "url" => "https://app.fizzy.do/6097036/cards/#{number}", "title" => title, "tags" => tags, "closed" => closed,
        "description_html" => FetchGhNotifications.frontmatter([ [ "ref", ref ] ]) }
    end

    def run_script(*notifications, args: [], success: true)
      File.write(@dir.join("notifications.json"), [ notifications ].to_json)
      @lanes.each { |lane, cards| File.write(@dir.join("cards-#{lane}.json"), { data: cards }.to_json) }
      File.write(@dir.join("comments.json"), @comments.to_json)
      File.write(@dir.join("states.json"), @states.to_json)
      File.write(@dir.join("fizzy-error.json"), @fizzy_error.to_json) if @fizzy_error
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
        elsif ARGV.first(2) == %w[card create] && File.exist?(error = File.join(DIR, "fizzy-error.json"))
          print File.read(error)
          exit 7
        elsif ARGV.first(2) == %w[card create] then print({ data: { number: 700, url: "https://app.fizzy.do/6097036/cards/700" } }.to_json)
        elsif ARGV.first(2) == %w[column list] then print({ data: [ { id: "col-next", name: "Next" }, { id: "col-ip", name: "In Progress" } ] }.to_json)
        else print({ data: {} }.to_json)
        end
      RUBY

      env = { "PATH" => "#{@dir}:#{ENV["PATH"]}" }
      output, status = Open3.capture2e(env, Rails.root.join("bin", "fetch-gh-notifications").to_s, *args)
      assert_equal success, status.success?, output
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

    def action_lines(output)
      output.split("\n\n")[1].lines
    end

    def argument(call, flag)
      call[call.index(flag) + 1]
    end
end
