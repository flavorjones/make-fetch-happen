---
name: fetch-card
description: |
  Create and maintain Fizzy cards that track external reports and notifications
  (GitHub issues and PRs, HackerOne reports, security advisories, review requests).
  Defines the card conventions: title format, tags, the frontmatter key/value table,
  column state, and golden-ness. Use whenever creating a card for an external
  artifact or updating the frontmatter of an existing card.
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
---

# fetch-card

Conventions for Fizzy cards that track external reports and notifications. Load the "fizzy" skill before interacting with the application.

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

Typical lifecycle: a card is created with "ref"; "worktree" is added when work starts; "output" is added when a pull request goes up for review.

## State

Fizzy uses columns to track state like a kanban board. A new card should always start in the "Maybe?" column.

## Golden-ness

Some cards should be marked golden (`fizzy card golden NUMBER`). New security advisories in particular, so that attention is drawn to them.
