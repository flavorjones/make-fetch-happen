# FETCH Design

## Summary

FETCH (Fizzy External Tracker for Card Happenings) is a Rails app for triaging notifications from external services. A recurring job syncs all unread notifications from each source (GitHub first) into a local database. A fast web UI presents pending notifications one at a time for a triage decision: dismiss, open, add to backlog, or trash. Notifications whose underlying artifact already has a Fizzy card skip triage entirely; FETCH comments on the card automatically.

Fizzy remains the canonical backlog. FETCH is the subsystem that precedes a Fizzy card: it decides which notifications deserve one.

## Design Principles

1. **Upstream is the source of truth for pending work.** A notification's unread state at the source is the durable record that it still needs triage. The local database is an ephemeral working copy: if it is lost, re-syncing the unread notifications restores the queue.

2. **Triage commits upstream.** Every triage decision completes by marking the notification read at the source, so it never shows up again. Triaged rows are kept locally as an activity log, but the log is best-effort and disposable.

3. **Fizzy cards are canonical for the backlog.** The local card index is a fast lookup cache, rebuildable at any time by scanning the Fizzy board. Cards store their artifact link in `ref` frontmatter, so the mapping can always be reconstructed from Fizzy alone.

4. **All remote I/O happens in jobs.** Anything that reads or writes a remote resource (source APIs, Fizzy) runs in a background job. The web UI request cycle touches only the local database, which is what keeps triage fast. A triage action updates the local row immediately and enqueues jobs for the remote side effects.

5. **Multi-source by design.** Each source is an adapter that knows how to fetch unread notifications, derive a normalized artifact URL, and perform the upstream effects (mark read, unsubscribe). The notification schema is source-agnostic: a few promoted columns plus the source's raw JSON payload.

## Data Model

### Notification

One row per notification thread from a source. Identity is `(source, external_id)`, unique together: re-syncing the same thread upserts the existing row. When new upstream activity makes a previously-triaged thread unread again, the upsert returns it to `pending`.

| Column | Type | Notes |
|--------|------|-------|
| `source` | string | `"github"` for now |
| `external_id` | string | The source's notification/thread id |
| `artifact_url` | string, indexed | Normalized web URL for the underlying artifact, e.g. `https://github.com/owner/repo/issues/42` |
| `title` | string | Promoted from the payload for display |
| `reason` | string | Why the source notified us (`mention`, `review_requested`, `subscribed`, ...) |
| `subject_type` | string | `Issue`, `PullRequest`, `Discussion`, ... |
| `repo` | string | e.g. `sparklemotion/nokogiri` |
| `source_updated_at` | datetime | The source's activity timestamp |
| `state` | string | `pending`, `dismissed`, `trashed`, `backlogged`, `forwarded` |
| `payload` | json | The source's complete raw notification JSON |

The payload keeps source fidelity without schema churn: new sources store their native JSON as-is, and fields we did not promote remain queryable via SQLite's JSON functions.

Artifact identity is the normalized `artifact_url`. Each source adapter derives it from its native representation (GitHub: the API `subject.url` becomes a web URL, including the `/pulls/` to `/pull/` rename), and the same normalization is applied to card `ref` values, so notifications and cards join on exact string equality.

A notification has zero or one card, and a card has many notifications (over time, as thread activity recurs), associated through `artifact_url` rather than a foreign key since either side can exist first.

### Card

Local index of Fizzy cards, keyed by artifact.

| Column | Type | Notes |
|--------|------|-------|
| `artifact_url` | string, unique index | Normalized from the card's `ref` frontmatter |
| `fizzy_card_number` | integer | |
| `title` | string | For display when auto-filing |

## Triage Actions

Actions are not records; they are the transitions of the notification's `state` machine. Each row here describes a transition and its upstream effect.

| Action | Meaning | Local state | Upstream effect |
|--------|---------|-------------|-----------------|
| Dismiss | Nothing to do right now; notify me again on future activity | `dismissed` | Mark read |
| Trash | I do not care about this artifact; never notify me again | `trashed` | Unsubscribe from the thread, then mark read |
| Backlog | Track this in Fizzy | `backlogged` | Create a Fizzy card, then mark read |
| Open | Go act on it directly (e.g. reply on GitHub) | stays `pending` | None; links out to the artifact. Triage it afterward, typically with Dismiss |
| Forward comment | (automatic) artifact already has a card | `forwarded` | Comment on the card, then mark read |

## Data Flow

**Sync (recurring job, per source):**

1. Fetch all unread notifications via Link-header pagination.
2. Upsert each into `notifications`, storing the raw payload and promoted fields.
3. For each pending row, in order:
   - If the junk filter matches, mark it `trashed` and enqueue a mark-read job. Filtered rows are kept, so the filter is auditable. The filter does not unsubscribe: it is deterministic, so any re-notification is simply re-filtered.
   - Else if `artifact_url` matches the card index, enqueue a forward-comment job.
   - Else it stays `pending` and enters the triage queue.

**Triage (UI action):**

1. The UI presents pending notifications one at a time, newest context visible: title, repo, reason, and relevant payload details.
2. An action updates the local row immediately and enqueues the corresponding jobs for the remote effects listed above.

**Card index (recurring job plus write-through):**

1. A recurring scan job lists cards from the Fizzy board, extracts each card's `ref` frontmatter, normalizes it, and upserts into `cards`.
2. The backlog action's card-creation job writes its new card into the index immediately, so the index is current for our own cards between scans.

## Jobs

All remote I/O lives in jobs, run by Solid Queue:

- `SyncNotificationsJob` (per source): fetch unread, upsert, filter, route.
- `MarkNotificationReadJob`: mark the thread read at the source.
- `UnsubscribeNotificationJob`: unsubscribe/ignore the thread at the source (trash).
- `ForwardCommentJob`: comment on the existing Fizzy card, then mark read.
- `CreateCardFromNotificationJob`: create the Fizzy card per the fetch-card conventions, write it through to the card index, then mark read.
- `ScanCardsJob`: rebuild/refresh the card index from Fizzy.

Jobs are idempotent so retries are safe: mark-read and unsubscribe are naturally idempotent, and forward-comment and create-card guard on the notification's state so a retry cannot double-comment or double-create. If an upstream effect never completes, the notification simply reappears as unread on a future sync; the sync upsert doubles as the reconciliation loop.

## Web UI

A minimal, keyboard-driven triage screen: one pending notification at a time, with dismiss / trash / open / backlog actions and a count of what remains. Secondary views can come later (activity log, sync status); they are not needed for the core loop.

## GitHub Source Notes

- Endpoint: `GET /notifications` (all repos), authenticated via the `gh` CLI.
- Paginate with `Link` headers only. Do not paginate with a `before` time cursor: the API sorts and filters on an internal timestamp that can differ from the serialized `updated_at` by several seconds, so cursor comparisons against `updated_at` terminate early. (Verified empirically, 2026-07-17.)
- Mark read: `PATCH /notifications/threads/{id}` (or `DELETE` to mark done).
- Unsubscribe: `PUT /notifications/threads/{id}/subscription` with `ignored: true`.
- New activity on a read thread makes it unread again upstream, which is what re-surfaces dismissed artifacts. No local reopen logic is needed.

## Testing

- Model tests for artifact URL normalization (API URL to web URL, `/pulls/` to `/pull/`, card `ref` extraction) and state transitions.
- Job tests with stubbed source and Fizzy clients: sync upsert behavior, filter routing, auto-file, and the idempotency guards.
- System test for the triage loop: present, act, advance to the next.

## Fizzy Card Conventions

Card format, frontmatter, tags, column state, and golden-ness are defined in the `fetch-card` skill. New cards start in the "Maybe?" column.
