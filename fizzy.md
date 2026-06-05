# Fizzy card format specification

Creation and maintenance of Fizzy cards to track external reports and notifications. Load the "fizzy" skill before interacting with the application.

Some pieces of information we need to know:

- tags: these are labels or categories that can be associated with a card
- project name: generally this is the project repository name, e.g. "https://github.com/sparklemotion/nokogiri" becomes "nokogiri"
- ref: a reference URL for the external report or issue

## Title

The title should always be in the format:

    "<project_name>: <description>"

so all cards related to the "nokogiri" project will start with "nokogiri". The description should be inferred from the notification or original issue's title

## Tags

Common tags I use:

- "oss" for open source projects
- "37signals" for work-related
- "security" for security-related
- "review" for requests for review (as in a pull request)

## Frontmatter

The card description should always start with an HTML table to track some key/value pairs. Common frontmatter keys:

- "ref" as noted above is the URL for the external resource or artifact
- "worktree" is for work in progress, this is the absolute path on disk to the directory in which I'm working on it
- "output" is for work that is pending review, for example the URL for a pull request generated for the fix
- "rel" is for related information, such as an RFC

## State

Fizzy uses columns to track state like a kanban board. The state of a new card should always start in the "Maybe?" column.

## Golden-ness

Some tickets should be marked golden. New security advisories in particular, so that my attention is drawn to them.
