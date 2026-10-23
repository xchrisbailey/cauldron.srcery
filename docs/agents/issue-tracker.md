# Issue tracker: GitHub

Issues and specs live in xchrisbailey/cauldron.srcery.
Use the gh CLI.

## Operations

- Publish: gh issue create --title "..." --body-file <file>
- Read: gh issue view <number> --json number,title,body,labels,comments
- Query: gh issue list with appropriate state and label filters
- Update: gh issue edit <number>
- Comment: gh issue comment <number> --body-file <file>
- Close: gh issue close <number>

Follow CLAUDE.md for native-epic relationships and dependency requirements.
Publishing a spec creates an issue, not a pull request.

## Pull requests as a triage surface

PRs as a request surface: no.

## Wayfinding operations

- Map: an issue labelled wayfinder:map.
- Tickets: native sub-issues of the map, labelled only with
  wayfinder:research, wayfinder:prototype, wayfinder:grilling
  or wayfinder:task.
- Link children through GitHub's sub-issue API:
  POST repos/{owner}/{repo}/issues/{parent}/sub_issues
  with sub_issue_id set to the child's database ID.
- Blocking: native issue dependencies:
  POST repos/{owner}/{repo}/issues/{child}/dependencies/blocked_by
  with issue_id set to the blocker's database ID.
  Obtain database IDs through gh api, not issue numbers or node IDs.
- Frontier: query the map's children; select open, unassigned tickets
  with zero open blockers, in map order.
- Claim: assign the ticket to the driving developer before working.
- Resolve: post a resolution comment, close the ticket, then append
  a linked one-line gist to the map's Decisions so far.
- If native relationships are unavailable, use a map task list,
  Part of references and Blocked by references as the fallback.
- Refer to maps and tickets by linked title in human-facing text.
