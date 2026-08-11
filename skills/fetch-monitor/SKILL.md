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
Arm it once; it never needs restarting. Emit one line per **new** unread
notification ID (edge-triggered), so a mention fires exactly one event and does
not re-fire while you are still handling it:

```bash
seen=""
while true; do
  ids=$(fizzy notification list --quiet 2>/dev/null | python3 -c "
import json,sys
for n in json.load(sys.stdin):
    if not n.get('read'): print(n['id'], n.get('card',{}).get('number'))" 2>/dev/null)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    id=${line%% *}
    case " $seen " in *" $id "*) ;; *) echo "UNREAD $line"; seen="$seen $id";; esac
  done <<EOF
$ids
EOF
  sleep 60
done
```

Edge cases: a notification marked unread *again* after being seen will not
re-fire (the `seen` dedup suppresses it); a Monitor only lives as long as the
session.

**Fallback** (no Monitor tool available): a one-shot `Bash run_in_background`
loop that exits when unread count > 0, with a ~540s idle cap so it resurfaces
rather than orphans. In fallback mode the watcher must be restarted after
every wake, and on an `IDLE` exit restart it silently — one short line to the
user at most.

## Handling a mention

For each unread notification, oldest first:

1. **React 👍 on the mentioning comment immediately**, before doing the work —
   it signals "seen, working on it". The notification carries no comment ID, so
   find the comment: `fizzy comment list --card N`, match the notification's
   truncated `body` against the comments from the notification's `creator`
   (most recent match wins). Then:

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

Also report a one-paragraph summary in the chat session so the terminal
transcript stays a complete record.

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
| `gh run rerun --failed` errors | Workflow run still in progress | Wait for run completion, then rerun |
| User asks "did you see my note?" | Poll gap (up to ~60s) or dead watcher | State the cadence up front; check the tray immediately when asked |

## Per-mention checklist

- [ ] 👍 reaction on the mentioning comment
- [ ] Full comment read (not the truncated notification body)
- [ ] Work done or question answered with evidence
- [ ] Reply comment posted (markdown → `cmark-gfm --unsafe` → HTML)
- [ ] Notification marked read
- [ ] Watcher healthy (persistent Monitor running, or fallback restarted)
