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

These conventions apply to the **Backlog** board only, and every `fizzy` command acts as
the bot user, never as Mike. The bot is the `fetchbot` profile; Mike's own profile is the
CLI default, so the bot must be selected explicitly. Export it once per session rather
than passing `--profile fetchbot` on every call:

```bash
export FIZZY_PROFILE=fetchbot
BOARD=$(fizzy board list --jq '.data[] | select(.name == "Backlog") | .id')
```

Some pieces of information we need to know:

- tags: labels or categories associated with the card
- project name: generally the project repository name, e.g. "https://github.com/sparklemotion/nokogiri" becomes "nokogiri"
- ref: a reference URL for the external report or issue

## Title

The title should always be in the format:

    <project_name>: <description>

so all cards related to the "nokogiri" project will start with "nokogiri". The description should be inferred from the notification or the original issue's title.

## Tags

Common tags:

- "oss" for open source projects
- "37signals" for work-related
- "security" for security-related
- "review" for requests for review (as in a pull request)

## Frontmatter

The card description should always start with an HTML table to track key/value pairs. Common frontmatter keys:

- "ref" as noted above is the URL for the external resource or artifact
- "rel" is for related information, such as an RFC
- "worktree" is for work in progress, the absolute path on disk to the directory in which the work is happening
- "output" is for work that is pending review, for example the URL for a pull request generated for the fix

The table is Lexxy rich text. Each row is a header cell holding the key and a data cell holding the value:

```html
<figure class="lexxy-content__table-wrapper"><table><tbody>
<tr><th class="lexxy-content__table-cell--header"><p>ref</p></th><td><p><a href="URL">URL</a></p></td></tr>
</tbody></table></figure>
```

When updating an existing card, preserve the description's existing HTML structure and add or edit rows rather than rewriting the description. Write the full description HTML to a file and update with:

    fizzy card update NUMBER --description_file path.html

Frontmatter rows are added and removed by the state machine's entry actions — see "State".

## Comments

Never post markdown as a comment body — Fizzy renders comment bodies as rich text, and
raw markdown shows up literally. Write the comment as markdown to a temp file, convert it
to HTML with `cmark-gfm`, and post the HTML:

```bash
cmark-gfm -e table -e strikethrough -e autolink -e tasklist --github-pre-lang --unsafe \
  tmp/comment.md > tmp/comment.html
fizzy comment create --card NUMBER --body_file tmp/comment.html
```

`--unsafe` preserves raw HTML in the source, so `<action-text-attachment>` tags survive the
conversion. The same applies to `fizzy comment update`.

### Drafts posted for approval

A draft that Mike will approve and then send somewhere else — a GitHub or advisory
comment, a release note, an email — is *content*, not prose for the card. Wrap it in
`<pre><code>` … `</code></pre>` so it reaches him verbatim. Without the wrapper
`cmark-gfm` renders it, and he approves HTML he never wrote — the headings, links, and
emphasis he sees are not the markdown that gets posted.

Escape `&`, `<`, and `>` inside the wrapper. `--unsafe` passes raw HTML straight
through, so an unescaped tag in the draft renders instead of showing.

```
Draft reply for GHSA-627c-837f-8529 — approve and I'll post it:

<pre><code>## Assessment

Confirmed on `v2.14.0`. See &lt;https://example.com/poc&gt;.
</code></pre>
```

Keep your own framing (what the draft is, where it would go, what you need) as ordinary
markdown outside the wrapper.

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
| In Review | Output has been generated and is waiting on external review and feedback. |
| Pending Release | Complete and approved, but not releasable yet. Usually an embargoed security fix. Rare. |
| Done | Everything is done. |
| Not Now | Decided against — we are not going to do this. |

A new card starts in "Maybe?". Do not move a card out of "Maybe?" on your own initiative —
that is the prioritization decision the column exists to hold. Wait for Mike.

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
worktree rules in `~/CLAUDE.md` and add the "worktree" row.

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
up the worktree.

**Not Now** — clean up the worktree. There is nothing to confirm; the decision is not to do
the work.

Cleaning up the worktree means removing it, deleting its local branch, and dropping the
"worktree" row from the frontmatter:

```bash
git worktree remove PATH
git branch -d BRANCH
```

Use `git branch -D` only after Mike confirms the unmerged work is disposable.

## Golden-ness

Some cards should be marked golden (`fizzy card golden NUMBER`). New security advisories in particular, so that attention is drawn to them.
