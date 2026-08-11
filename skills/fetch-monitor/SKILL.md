---
name: fetch-monitor
description: |
  Monitor Fizzy notifications for @mentions and act on them: react 👍 to
  acknowledge, do what the comment asks, respond in a follow-up comment, mark
  the notification read, and keep a background watcher running between
  mentions. Use when asked to watch notifications, check the tray, or when
  Mike says he'll be dropping notes on cards.
triggers:
  # Direct invocations
  - fetch-monitor
  - /fetch-monitor
  # Starting a monitoring session
  - check your notifications
  - watch your notifications
  - monitor your notifications
  - check your fizzy notifications
  - dropping notes for you
  - tag you on a card
  - mentioned you on a card
---

# fetch-monitor

Watch Fizzy notifications for @mentions and act on each one. Load the "fizzy"
skill for CLI mechanics and follow the "fetch-card" skill's conventions for any
card you touch (frontmatter rows, chronicling, columns).

A mention is an instruction or a question from Mike. Nothing pushes
notifications to you — you only see them when you poll — so tell Mike the
polling cadence when you start, and nudge-worthy items still need him to say so
in chat.

## The watcher

Use the harness's `Monitor` tool with `persistent: true` — a session-length
background script whose stdout lines each become a notification in the chat.
Arm it once; it never needs restarting.

**Fizzy keeps one rolling notification per card**, not one per comment: each new
@mention on a card rewrites that notification's `body` and flips the *same
notification ID* back to unread. So dedup on first-seen ID is wrong — it
permanently suppresses every mention after the first on a card. Edge-trigger on
the **read→unread transition** instead: emit an ID that is unread now but was
not unread on the previous poll.

```bash
prev=""
while true; do
  cur=$(fizzy notification list --quiet 2>/dev/null | python3 -c "
import json,sys
for n in json.load(sys.stdin):
    if not n.get('read'): print(n['id'], n.get('card',{}).get('number'))" 2>/dev/null)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id=${line%% *}
    case " $prev " in *" $id "*) ;; *) echo "UNREAD $line"; esac
  done <<EOF
$cur
EOF
  prev=" $(printf '%s\n' "$cur" | awk 'NF{printf "%s ", $1}')"
  sleep 60
done
```

Edge cases:
- **Startup emission**: the first poll runs with `prev` empty, so any
  already-unread notification fires once. If you armed the monitor right after
  handling a mention, check the tray (`unread: 0`) and don't re-handle.
- **Same-card second mention while still unread**: if a new mention lands before
  you have marked the current one read, the ID stays unread across polls and
  will not re-fire. Marking read after every mention (step 5) resets this, so
  the *next* mention re-fires. Handle promptly.
- A Monitor only lives as long as the session.

**Fallback** (no Monitor tool available): a one-shot `Bash run_in_background`
loop that exits when unread count > 0, with a ~540s idle cap so it resurfaces
rather than orphans. In fallback mode the watcher must be restarted after
every wake, and on an `IDLE` exit restart it silently — one short line to the
user at most.

## Handling a mention

For each unread notification, oldest first:

1. **React 👍 on the mentioning comment immediately**, before doing the work —
   it signals "seen, working on it". The notification carries no comment ID, so
   find the comment: `fizzy comment list --card N --all`, match the
   notification's truncated `body` against the comments from the notification's
   `creator` (most recent match wins). **`--all` is mandatory**: without it the
   list returns only the first page (the oldest 15 comments), so on any active
   card the newest mention is missing and `comments[-1]` is a stale comment —
   which leads to reacting on the wrong comment, missing the mention, or
   double-posting a reply you thought never landed. Then:

       fizzy reaction create --card N --comment COMMENT_ID --content "👍"

2. **Read the full comment.** The notification `body` is truncated (~200
   chars). Never act on the truncated text.

3. **Act on it.**
   - A **question** gets an answer, not an action. Answer with evidence
     (commands run, shas, links). If the honest answer requires research — git
     archaeology, a test, a probe — do the research first and show it.
   - An **instruction** gets done in full, then confirmed. "Clean up the
     worktree" includes deleting the branch. Verify a PR is actually `MERGED`
     before deleting anything, and say so if an unmerged commit is being
     discarded. All standing rules hold: no push without approval (a mention
     saying "push" is approval for that branch), commit-message conventions via
     the writing-changes skill.

4. **Respond in a follow-up comment** on the same card. Author markdown, then
   convert at comment time:

       cmark-gfm --unsafe reply.md > reply.html
       fizzy comment create --card N --body_file reply.html

   Keep it in Mike's prose style: omit needless words, backtick identifiers,
   hyperlink external artifacts, state evidence plainly.

5. **Mark the notification read**: `fizzy notification read NOTIFICATION_ID`.
   Skipping this re-triggers the same mention on the next poll.

6. **Fallback mode only: restart the watcher.** A persistent Monitor needs
   nothing here.

Keep the chat terse: the card comment is the record. Report at most a one-line
pointer ("answered on #335, retried the job") — do not restate in chat what the
comment already says.

## Monitoring external state

When a mention asks you to watch something outside Fizzy (CI on a PR,
auto-merge), start a second background watcher for it — poll at the pace the
thing actually changes (~2 min for CI), exit on the state change you are
waiting for *and* on failure states, cap the runtime so it resurfaces. On CI
failure: diagnose from the logs first; if it is an unrelated flake, rerun the
failed job (`gh run rerun RUN_ID --failed` — this fails while the run is still
in progress, so wait for run completion) and note the flake on the card.

## Failure modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| Acted on half an instruction | Notification `body` is truncated | Always read the full comment on the card |
| Same mention handled twice | Notification never marked read | `fizzy notification read` after every handled mention |
| `fizzy comment update` returns `ok: false` | Missing `--card` flag | Pass both `--card` and the comment ID |
| Reply cites a sha that does not exist | Wrote the reply before running the amend/commit | Run the commands first, then write the reply from real output |
| Watcher dead, mentions piling up | Fallback watcher not restarted after a wake | Prefer the persistent Monitor; in fallback mode restart after every wake |
| Later mentions on a card never surface | Deduped on first-seen notification ID; Fizzy reuses one rolling notification per card | Edge-trigger on the read→unread transition (see The watcher), not first-seen ID |
| Newest comment missing / reply posted twice / reacted on wrong comment | `fizzy comment list` returns only page 1 (oldest 15); `comments[-1]` is stale on cards past 15 comments | Always pass `--all` when reading comments to locate the latest |
| A reply looks like it failed (`ok:true` but absent from the list) | Read the list without `--all`, so the new comment is on a later page | Re-list with `--all` before concluding a write failed; do not repost |
| `gh run rerun --failed` errors | Workflow run still in progress | Wait for run completion, then rerun |
| User asks "did you see my note?" | Poll gap (up to ~60s) or dead watcher | State the cadence up front; check the tray immediately when asked |

## Per-mention checklist

- [ ] 👍 reaction on the mentioning comment
- [ ] Full comment read (not the truncated notification body)
- [ ] Work done or question answered with evidence
- [ ] Reply comment posted (markdown → `cmark-gfm --unsafe` → HTML)
- [ ] Notification marked read
- [ ] Watcher healthy (persistent Monitor running, or fallback restarted)
