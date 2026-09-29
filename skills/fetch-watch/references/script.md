# bin/fetch-watch

`bin/fetch-watch` is the event source for the `fetch-watch` skill. It
publishes a path on the Tailscale Funnel per board, registers a Fizzy webhook
against it, and prints one line per event that matters. The supervisor reads
those lines; this file holds everything about the script itself.

## Configuration

`~/.config/fizzy/fetch-watch.json` (`--config PATH` overrides) lists the boards.
Each board lives on its own Fizzy account, and a `fizzy` profile is pinned to one
account, so each entry names a bot profile and an admin profile:

```json
{ "boards": [
    { "board": "Personal Backlog",         "bot_profile": "fetchbot_personal", "admin_profile": "mike_personal" },
    { "board": "Mike's 37signals Backlog", "bot_profile": "fetchbot_37signals", "admin_profile": "mike_37signals" } ] }
```

- **Bot profile.** `fizzy identity show --profile NAME` must list the board's
  account with the bot user (a `member`) on it. Every `fizzy` write on that
  board runs as this profile. The bot is `Harry` on the personal account and
  `Harry (Mike's Agent)` on 37signals. Mike's own profile is the CLI default, so
  a `fizzy` command without `--profile` or `FIZZY_PROFILE` posts as Mike.
- **Admin profile.** Only an account admin can register a webhook. The script
  uses this profile for the two webhook calls and nothing else, and aborts at
  startup if it is on another account or not `admin`/`owner` there.

The script runs from `~/code/oss/make-fetch-happen`, never from another
project. If the clone isn't there, say so and stop.

## Funnel

- The listener is published at a secret `/fizzy/<secret>` path per board on
  this machine's funnel hostname. It coexists with anything else on the funnel
  (basecamp-connect owns `/`) and only ever adds and removes its own paths.
- **`/keepalive` stays mounted forever.** Tailscale withdraws the funnel
  hostname from public DNS when nothing is mounted, and Fizzy then cannot
  deliver. The script checks at startup that `tailscale funnel status` shows
  `/keepalive` proxying `http://127.0.0.1:9` and mounts it if missing:

      tailscale funnel --bg --set-path /keepalive http://127.0.0.1:9

  Nothing removes it: not teardown, not cleanup. **Never run
  `tailscale funnel reset`.** It removes every path, including
  basecamp-connect's and `/keepalive`, and no webhook can be delivered until the
  DNS record propagates again.

## Output

| Line | Source |
|---|---|
| `MENTION account=A card=N comment=ID by="Mike Dalessio"` | a `comment_created` webhook whose comment @mentions the bot |
| `TRANSITION account=A card=N state="Paused" by="Mike Dalessio"` | a card move, close, postpone, reopen, or send-back-to-triage |
| `READY account=A board="…" https://…/fizzy/…` | that board's path is up and its webhook registered |

`account` is the numeric account id from the card URL
(`https://app.fizzy.do/6097036/cards/N`). Card numbers restart per account, so
the number alone names nothing.

Diagnostics (dropped deliveries, registration notices) go to stderr.

**Acknowledgement.** The moment a live delivery clears the filters, the script
reacts 👀 on the mentioning comment as the bot, so Mike gets a receipt within
seconds. Replayed and polled mentions get the 👀 too, so a comment that lands
during a restart still gets its receipt; a comment that already has the bot's 👀
is skipped.

**Replay.** Anything that happened while nothing was listening is replayed
before that board's `READY`: the script reads the board's activity feed back to
the newest event it saw last time (per board in `~/.config/fizzy/fetch-last.json`)
and runs those events through the same filters. A board's first run has no mark
and replays nothing; for that case only, unread mentions are in the tray:

    fizzy notification tray --profile NAME --jq '.data[] | select(.source_type == "mention") | {id, card: .card.number, body}'

**Poll.** Every 60s (`--poll SECONDS`; `0` disables) the script re-reads the
activity feed and emits anything the webhook missed, deduped, so an event
arrives exactly once. This exists because Tailscale's public DNS for `ts.net`
fails intermittently and a failed delivery is never retried.

## What the script enforces

A line on stdout has passed all of these:

- **Signature.** `X-Webhook-Signature` is the HMAC-SHA256 of the raw body under
  the secret Fizzy issued for this run's webhook. Unsigned or mis-signed bodies
  are dropped before parsing. The funnel URL is public; this is the boundary.
- **Shape.** JSON with an event id, action, creator, and eventable.
- **Not ours.** Events whose creator is the bot user are dropped, so a worker's
  own comment or move never comes back as an event.
- **Not a redelivery.** An event id seen before in this run is dropped.
- **Comments must mention the bot**, by mention attachment carrying the bot's
  user id or `@Harry` in the plain text. Others are dropped with
  `comment without mention` on stderr.
- **Card events must be transitions**: `card_triaged`, `card_closed`,
  `card_postponed`, `card_auto_postponed`, `card_reopened`,
  `card_sent_back_to_triage`, `card_board_changed`. State is derived from the
  payload (`closed` → Done, `postponed` → Not Now, else the column name, else
  Maybe?). Assignments, renames and publishes are dropped.

Fizzy has no `comment_updated` action, so a mention edited into an existing
comment is invisible to the script. Ask Mike to post a new comment.

## Running it

Arm it under the harness's `Monitor` tool so each stdout line is a chat
notification:

    cd ~/code/oss/make-fetch-happen && sleep 5 && bin/fetch-watch

A Monitor watch expires after at most 30 minutes and kills the script, whose
teardown removes its webhooks and `/fizzy/…` paths. Before re-arming, verify the
teardown finished:

```bash
tailscale funnel status | grep -E '/fizzy|/keepalive'   # only /keepalive
fizzy webhook list --board "$BOARD" --profile ADMIN_PROFILE --jq '[.data[] | select(.name | startswith("fetch-watch"))] | length'   # 0
```

Then re-arm with the same command. Events from the gap are replayed on start.

If the process was killed without teardown (`SIGKILL`, reboot), delete each
leftover webhook with `fizzy webhook delete ID --board "$BOARD" --profile
ADMIN_PROFILE` and close its path with `tailscale funnel --set-path
/fizzy/SECRET off` (the secret is in the webhook's `payload_url`).

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| No `READY` line | Watch list missing or malformed; a bot profile does not reach the board's account; an admin profile is on another account or not an admin; funnel failed; board not found | Read stderr in the output file; fix the prerequisite; restart |
| One board's `READY` is missing | A board later in the list aborted the run before its webhook was registered | Nothing is registered until every board prepares; stderr names the board and profile |
| `READY` printed but no events arrive | Deliveries failing | `fizzy webhook deliveries --board "$BOARD" ID --profile ADMIN_PROFILE` shows each delivery's response; check the funnel path is still up |
| A mention arrives a minute late | The delivery failed and the poll picked it up | Nothing to fix |
| Deliveries fail with `dns_lookup_failed`, `dig +short @1.1.1.1 <funnel-host>` sometimes empty | Tailscale's public DNS is flapping | Not ours to fix; the poll covers it. Don't restart the script |
| Every delivery fails with `dns_lookup_failed` and `dig` is always empty | `/keepalive` was removed and Tailscale withdrew the record | Restart the script; it remounts `/keepalive`. The record can take minutes to reappear |
| Events stopped mid-session | Something ran `tailscale funnel reset` | Restart the script |
| An event from while nobody was watching never showed up | First run (no mark file), or the mark file was deleted | Check the tray for unread mentions; transitions before the first run are not recoverable |
| Old events replayed on every start | Mark file not writable | Check `~/.config/fizzy/fetch-last.json`; the script prints the write failure on stderr |
| Webhook or `/fizzy/…` path left behind | Process killed without teardown | Manual cleanup above; never `funnel reset`; leave `/keepalive` alone |
