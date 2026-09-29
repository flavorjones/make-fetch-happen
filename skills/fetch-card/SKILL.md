---
name: fetch-card
description: |
  Create and maintain Fizzy cards that track external reports and notifications
  (GitHub issues and PRs, HackerOne reports, security advisories, review requests).
  Defines the card conventions: title format, tags, the frontmatter key/value table,
  the column state machine and its entry actions, and golden-ness. Use whenever
  creating a card for an external artifact, updating the frontmatter of an existing
  card, or moving a card between columns.
triggers:
  # Direct invocations
  - fetch-card
  - /fetch-card
  # Card creation from external artifacts
  - make a card for
  - create a card for
  - track this report
  - track this issue
  # Frontmatter maintenance
  - update the frontmatter
  - set the output
  - record the worktree
  # State transitions
  - move the card to
  - change the state
  - mark it in progress
  - mark it done
  # Chronicling progress
  - chronicle
  - journal
---

# fetch-card

Conventions for Fizzy cards that track external reports and notifications. Load the "fizzy" skill before interacting with the application.

These conventions apply to the backlog boards, one per Fizzy account, and every `fizzy`
command acts as the bot user, never as Mike. A profile is pinned to one account, so the
bot has one per board: `fetchbot_personal` for **Personal Backlog** on the personal account
(6097036) and `fetchbot_37signals` for **Mike's 37signals Backlog** on the 37signals
account (5986089). Mike's own profile is the CLI default, so the bot must be selected
explicitly. Export the profile for the board you are working once per session rather
than passing `--profile` on every call:

```bash
export FIZZY_PROFILE=fetchbot_37signals
BOARD=$(fizzy board list --all --jq '.data[] | select(.name == "Mike'"'"'s 37signals Backlog") | .id')
```

Card numbers restart per account, so a card is `<account>/<number>`, never a bare
number: `fizzy card show 419` answers for whichever profile is exported. Card URLs carry
the account: `https://app.fizzy.do/5986089/cards/12`.

Some pieces of information we need to know:

- tags: labels or categories associated with the card
- project name: generally the project repository name, e.g. "https://github.com/sparklemotion/nokogiri" becomes "nokogiri"
- ref: a reference URL for the external report or issue

## Reading command output

Shape a response with `--jq`, never with `head` or `tail`. Truncating cuts off the `ok`
envelope, a write that succeeded reads as a failure, and the retry duplicates the
reaction, comment, or move:

```bash
fizzy reaction create --card N --comment ID --content "👍" --jq '{ok, id: .data.id}'
```

When you do need the whole response, `tee` it to `./tmp/` and read from the file, so a
missing field is one more `--jq` away instead of a second write.

Before repeating **any** write, re-read the state (`fizzy comment list --card N --all`,
`fizzy card show N`) and confirm the first attempt really did not land.

## Title

The title should always be in the format:

    <project_name>: <description>

so all cards related to the "nokogiri" project will start with "nokogiri". The description should be inferred from the notification or the original issue's title.

## Tags

Common tags:

- "oss" for open source projects
- "37signals" for work-related (every card on the 37signals board)
- "security" for security-related
- "review" for requests for review (as in a pull request)

## Frontmatter

The card description should always start with an HTML table to track key/value pairs. Common frontmatter keys:

- "ref" as noted above is the URL for the external resource or artifact
- "rel" is for related information, such as an RFC
- "worktree" is for work in progress, the absolute path on disk to the directory in which the work is happening
- "output" is for work that is pending review, for example the URL for a pull request generated for the fix
- "is blocked by" and "blocks" are for dependencies between cards — see "Dependencies"

The table is Lexxy rich text. Each row is a header cell holding the key and a data cell holding the value:

```html
<figure class="lexxy-content__table-wrapper"><table><tbody>
<tr><th class="lexxy-content__table-cell--header"><p>ref</p></th><td><p><a href="URL">URL</a></p></td></tr>
</tbody></table></figure>
```

One value per row. A key that needs several values — two "rel" links, three "blocks" —
gets one row per value, repeating the key, rather than several values stacked in a single
cell. Repeated keys are expected and read correctly; a crowded cell does not.

Only the table has to be HTML — the rest of the description can be markdown in the same file, and Fizzy renders it. See "Comments".

When updating an existing card, preserve the description's existing HTML structure and add or edit rows rather than rewriting the description. Write the full description to a file and update with:

    fizzy card update NUMBER --description_file path.html

Frontmatter rows are added and removed by the state machine's entry actions — see "State".

### Dependencies

When one card cannot proceed until another is finished, record it on **both** cards: "is
blocked by" on the card that is waiting, "blocks" on the card being waited on. A dependency
recorded on only one side is invisible from the other, which is exactly when it matters —
you finish a card without knowing what it unblocks.

Each value is a link to the other card, with the card number and a short label so the row
is readable without following it. A card that blocks three others gets three "blocks" rows
— never three links stacked in one cell:

```html
<tr><th class="lexxy-content__table-cell--header"><p>blocks</p></th><td><p><a href="https://app.fizzy.do/6097036/cards/478">#478 — loofah: allow boolean and empty attributes</a></p></td></tr>
<tr><th class="lexxy-content__table-cell--header"><p>blocks</p></th><td><p><a href="https://app.fizzy.do/6097036/cards/510">#510 — loofah: HTML5 empty attributes are being scrubbed</a></p></td></tr>
```

Record a dependency only where one exists in fact — a thread that says the work is waiting
on another thread, or an entry action that cannot run until another card's output lands.
Two cards on the same subject are duplicates or siblings, not a blocking pair; use "rel"
for those.

Both sides have to move together. When you add, change, or remove one direction, update the
other in the same pass, and when a card reaches "Done" or "Not Now", drop it from the "is
blocked by" row of every card it was blocking.

## Comments

Post markdown directly. Fizzy runs comment bodies through its own GFM renderer, so
markdown arrives formatted:

```bash
fizzy comment create --card NUMBER --body_file tmp/comment.md
```

Do not convert to HTML first. Fizzy renders whatever it receives, so a pre-converted body
gets markdown-rendered a second time. Raw HTML survives that pass, which is why the
conversion mostly looked like it worked, but the markdown *inside* a `<pre><code>` block
does not — it is parsed again into headings, tables, and links. The same applies to
`fizzy comment update` and to `fizzy card create`/`fizzy card update`.

Tables, strikethrough, autolinks, inline code, and fenced code blocks all render. Two
things do not:

- **Task lists.** `- [ ]` and `- [x]` render as plain bullets with the marker stripped.
  Use a different notation if the state matters.
- **Mentions.** `@name` stays literal text. A real mention is an
  `<action-text-attachment>` carrying a server-signed sgid, which the CLI cannot produce.
  Anyone on the card is notified by the comment itself, so plain text is usually enough.

Raw HTML passes through, so an `<action-text-attachment>` tag written by hand still works.
Card descriptions still need HTML for the frontmatter table — see "Frontmatter" — because
its Lexxy markup has no markdown equivalent.

### Spacing

Fizzy renders adjacent `<p>` blocks with no gap, so a body written as plain markdown
arrives as a wall of text. Put a literal `<p><br></p>` line between every pair of blocks —
paragraphs, lists, and code fences alike. It is raw HTML, so it survives the markdown pass
and becomes the blank line the renderer will not give you.

Without spacers:

```markdown
Confirmed on `v2.14.0`. The overflow is in the length prefix.

Two call sites are affected:

- `parse` truncates
- `dump` raises
```

With them:

```markdown
Confirmed on `v2.14.0`. The overflow is in the length prefix.

<p><br></p>

Two call sites are affected:

<p><br></p>

- `parse` truncates
- `dump` raises
```

### Drafts for approval

A draft that Mike will approve and then send somewhere else — a GitHub or advisory
comment, a release note, an email — is *content*, not prose for the card. He needs to read
and copy the markdown source, not a rendering of it, so put it in a fenced code block.

The fence must be longer than any fence inside the draft, and carry no info string. Eight
backticks clears an ordinary nested block:

`````
Draft reply for GHSA-627c-837f-8529 — approve and I'll post it:

````````
## Assessment

Confirmed on `v2.14.0`. See <https://example.com/poc>.

```ruby
agent.get(url)
```
````````
`````

Nothing inside needs escaping — the fence is opaque to the renderer, and `&`, `<`, and `>`
are escaped for you. The result is a single `<pre><code>` holding one text node.

Keep your own framing (what the draft is, where it would go, what you need) as ordinary
markdown outside the fence.

## Chronicling

"Chronicle" or "journal" means: add a comment to the card. Nothing else. It never
means editing the description.

A chronicle comment summarizes the state of the work so it can be picked up later in
a different session: what was decided and why, what was built, what's parked, and
what the next step is. Attach a code or diff snapshot when the working tree is about
to change.

## State

Fizzy columns are the card's state machine.

| Column | Meaning |
|---|---|
| Maybe? | Initial state. Awaiting Mike's decision on prioritization. |
| Next | Prioritized as something Mike intends to work on. Nothing started yet. |
| Researching | More information is needed before work can start. |
| In Progress | Actively being worked on. |
| Paused | Work has stopped, usually because it is blocked or became less urgent. |
| In Review | Our output is waiting on a third party's review: a maintainer, a teammate, a reporter. It is never used when the wait is on Mike or the bot. |
| Pending Release | Complete and approved, but not releasable yet. Usually an embargoed security fix. Rare. |
| Done | Everything is done. |
| Not Now | Decided against — we are not going to do this. |

A new card starts in "Maybe?". Do not move a card out of "Maybe?" on your own initiative —
that is the prioritization decision the column exists to hold. Wait for Mike.

"In Progress" or "In Review" depends on who is holding the work up:

- The bot is waiting on Mike (approval, a decision, his review of our work): **In Progress**.
- Mike and the bot are reviewing someone else's PR: **In Progress**. The review is the task.
- Our work is waiting on someone else's review: **In Review**.

An instruction from Mike to research something ("please research this", "look into
why…", "figure out how…") is also an instruction to move the card to "Researching". Move
it first, run the entry actions, then do the research. If the card is already there, just
do the research.

The states are not a linear path. A card can move to "Paused" or "Researching" from
anywhere, and back out again.

Moving a card needs the column's ID, not its name:

```bash
COLUMN=$(fizzy column list --board "$BOARD" --jq '.data[] | select(.name == "In Progress") | .id')
fizzy card column NUMBER --column "$COLUMN"
```

"Maybe?", "Not Now", and "Done" are pseudo-columns whose IDs are the literals `maybe`,
`not-now`, and `done`.

### Entry actions

Run these whenever a card enters the state, whether you initiated the move or Mike asked
for it in a comment.

**In Progress** — if the frontmatter has no "worktree", create one following the git
worktree rules in `~/CLAUDE.md` and add the "worktree" row. See "Branch names".

**Researching** — same worktree action as "In Progress". Also, there must be a comment
saying what needs to be researched. If there isn't one, move the card and post a comment
asking Mike to add one.

**Paused** — there must be a comment saying why it's paused. If there isn't one, move the
card and post a comment asking Mike to add one.

For both, "a comment" means one posted since the card last entered the state. Fizzy logs
every move as a comment from the `System` user (`creator.role` is `"system"`), so the
latest such "moved this to …" comment marks the entry; only human comments after it count.
The one exception is the comment that triggered the move — a research instruction that
made you move the card to "Researching" is the comment, even though it predates the
`System` entry.

**In Review** — the artifact under review must be tracked as "output" in the frontmatter.
Add the row if it's missing; ask Mike for the URL if you can't determine it.

**Done** — first confirm every "output" is approved or merged (`gh pr view URL --json
state,reviewDecision`). If any isn't, leave the card where it is and say so. Otherwise clean
up.

**Not Now** — clean up. There is nothing to confirm; the decision is not to do the work.

### Branch names

A card's branch is `card-<number>-<slug>`. The number is the card number. The slug is at
most four lowercase hyphenated words naming the card's subject, taken from the title's
description part. It names the problem, never the state or the fix, so it stays true when
research turns into a fix:

    card-441-css-url-escaped-parens
    card-564-allowed-uri-ncr-control-char

The directory is `<repo>--<branch>`, per `~/CLAUDE.md`.

Never rename a branch or a worktree directory. The name is a handle, not documentation;
the PR title carries the meaning. A second branch for the same card — a prototype, a split
PR — keeps the stem and adds a suffix (`card-564-allowed-uri-ncr-control-char-alt`) so
cleanup finds it.

### Cleaning up

Cleaning up means removing the worktree, deleting **every branch the card created, remote as
well as local**, and dropping the "worktree" row from the frontmatter. Leaving the fork branch
behind is not cleaning up:

```bash
git worktree remove PATH
git branch -d BRANCH
git push REMOTE --delete BRANCH
```

Find the strays rather than assuming the frontmatter names them all — a card often spawns an
exploration or prototype branch alongside the one that became the PR:

```bash
git branch --list "*card-NUMBER*"
git ls-remote --heads REMOTE | grep card-NUMBER
```

A squash-merged branch is not an ancestor of `origin/main`, so `git branch -d` refuses it even
though the work has landed. Confirm the merge by the PR (`gh pr view URL --json state`) and then
use `-D`.

Delete a branch whose commits are not upstream only after Mike confirms that work is disposable.
Say which branch and how many commits, and leave it alone until he answers — a stray branch
belonging to a card that is still open is his, not yours.

## Golden-ness

Some cards should be marked golden (`fizzy card golden NUMBER`). New security advisories in particular, so that attention is drawn to them.
