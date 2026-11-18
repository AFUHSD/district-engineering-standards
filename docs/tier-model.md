# Tier model

This is Peninsula's model, adapted. The `standard` and `production` rulesets target the `tier` custom property.
`baseline` and `agent-guard` apply to every repository whatever its tier. So **a repository is born governed or
not born**: set `tier` and `lifecycle` in its first ten minutes, and `owner` as soon as one is agreed. The schema
leaves `owner` optional so that a rollout is not blocked on naming an owner for every old repository.

| Tier | Means | Gates once active |
|---|---|---|
| **A: production** | Live for staff, students or families, **or** reads or writes student or staff data, **or** runs as a scheduled production job | Pull request required. CI and the security scan are green. One human approval, from a code owner for every file `CODEOWNERS` covers. Review threads resolved. No force-push or delete |
| **B: internal** | Internal tools, libraries, MCP servers, infrastructure documents with code, skills and plugins | Pull request required. CI is green. No force-push or delete |
| **C: experiment** (the default) | Prototypes, one-offs, demos | No force-push or delete. A repository with no tests is permitted |

The table shows what `standard` and `production` add. The effective policy on a repository is the combination of
every ruleset that matches it. With `agent-guard` active, anyone outside its bypass list also needs an approval
from the named team on every repository, Tier C included. On Tier A that can mean two approvals, one from a code
owner and one from the team, unless the same person is both.

**Code-owner review only applies to files that `CODEOWNERS` covers.** With no `CODEOWNERS` file, or one with gaps,
the Tier A rule is satisfied by one approval from anyone with write access. Give every Tier A repository a
`CODEOWNERS` file with a catch-all line (`*`) before you rely on the rule.

## Custom properties

The schema is in [`../org/properties-schema.json`](../org/properties-schema.json).

| Property | Values | Notes |
|---|---|---|
| `tier` | `a-production`, `b-internal`, `c-experiment` | Required. Defaults to `c-experiment` |
| `lifecycle` | `active`, `maintenance`, `retiring`, `archived-candidate`, `archived` | Required. Defaults to `active` |
| `owner` | a GitHub login | The one person accountable |
| `public-candidate` | `true`, `false` | Treat unset as not a public candidate |

## Assigning tiers

1. Export every repository with its last push date, default branch and whether anything deploys from it.
2. Draft the assignment in a spreadsheet or TSV: one row per repository, with the reason.
3. A person who knows the estate reviews every row. Expect corrections, most often a repository that looks
   dormant and is still serving something.
4. Apply the values from the reviewed file with the API, and keep that file as the record.

Two common classification traps:

- **The data rule decides more than the hosting rule.** A small script that reads student data is Tier A even if
  it has no web page.
- **"No push in 18 months" is not "unused".** Check what calls a repository before you mark it for archive.
