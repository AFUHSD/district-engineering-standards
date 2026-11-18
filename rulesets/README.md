# Organization configuration as code

Every ruleset and the custom-property schema in this kit is committed first and applied from the file, so each
change has a diff and a rollback. In the commands below, replace the words in capitals with your own values.

| File | Applies to |
|---|---|
| `../org/properties-schema.json` | The custom repository properties `tier`, `lifecycle`, `owner` and `public-candidate` |
| `baseline.json` | Every repository's default branch: no deletion and no force-push |
| `standard.json` | The default branch of repositories with `tier = b-internal` |
| `production.json` | The default branch of repositories with `tier = a-production` |
| `agent-guard.json` | Every repository's default branch: for anyone outside its bypass list, a change lands only by a pull request a person in the named team approved |
| `apply.ps1` | Diffs a file against the live ruleset of the same name. Sends only with `-Execute` |

**Every file here ships with `"enforcement": "evaluate"`.** Evaluate blocks nothing. It records what would have
been blocked. Change a file to `active` in your own copy, on purpose, one ruleset at a time.

**The check has two modes.** `.github/check.ps1` as shipped is the template mode: it fails if any ruleset is not
in evaluate or names a real team. That protects this public copy. In your own copy, change the workflow step to
`./.github/check.ps1 -Adopted`, which allows `active` and real team ids and still refuses the placeholder `0`
in a ruleset that is `active`.

In both modes the check also fails if one of the four ruleset files is missing, has lost a rule it is meant to
carry, or differs at all from its pinned content, apart from the enforcement value and the team id. An approval
count, a bypass actor, a check name or an app id cannot change unnoticed. If you change a ruleset on purpose,
update its pin in `check.ps1` in the same pull request (`check.ps1 -ShowPins` prints the new value).

The script matches by name. If your organization already has an active ruleset called `baseline`, `standard`,
`production` or `agent-guard`, applying one of these files as shipped turns it back to evaluate. The dry run shows
that as a diff. Read it.

All four target `~DEFAULT_BRANCH`, so they follow repositories that still use `master` and leave feature branches
free to be deleted after merge. `baseline` and `agent-guard` apply whatever the tier, so a Tier C repository gets
those two and nothing else.

## Before you apply anything

1. **Check names.** `standard` and `production` require status checks named `ci / district-ci` and
   `security / security-scan`. Those must be the exact check-run names your own workflows produce. A required check
   that never reports blocks every pull request once the ruleset is active.
2. **Integration id.** `15368` is the GitHub Actions app. Pinning it means no other app and no status API call can
   satisfy the check. Confirm the id and the names on a real check run in your organization before you trust them:

   ```
   gh api repos/YOUR_ORG/YOUR_REPO/commits/COMMIT_SHA/check-runs --jq '.check_runs[] | [.name, .app.id] | @tsv'
   ```
3. **Team id.** `agent-guard.json` carries `0` in two places where your team's numeric id goes: the bypass list
   and the required reviewer. Both must be the same team. The check and `apply.ps1` refuse a file where they differ. Find it with
   `gh api orgs/YOUR_ORG/teams/TEAM_SLUG --jq .id`. `apply.ps1 -Execute` refuses the file while the `0` is there.
4. **Apply the property schema first**, and set `tier` on your repositories. A ruleset that targets a property no
   repository has matches nothing, silently.

   ```
   gh api -X PATCH orgs/YOUR_ORG/properties/schema --input org/properties-schema.json
   ```

## What each ruleset does

`standard` and `production` each target one tier and list the full set of gates for it. A repository is matched by
exactly one of them, so its Rule Insights read against one ruleset. They repeat `baseline`'s two rules on purpose:
the tier's guarantees then do not depend on `baseline` staying as it is.

| Rule (API `type`) | `standard` (Tier B) | `production` (Tier A) | What it does |
|---|---|---|---|
| `deletion` | yes | yes | The default branch cannot be deleted |
| `non_fast_forward` | yes | yes | No force-push to the default branch |
| `pull_request` | 0 approvals | 1 approval, plus code-owner approval for files `CODEOWNERS` covers | Changes reach the default branch only by a merged pull request. A direct push is rejected |
| `dismiss_stale_reviews_on_push` | n/a | yes | A push after approval dismisses the approval, so the approved code is the merged code |
| `required_review_thread_resolution` | no | yes | Every review thread is resolved before merge |
| `allowed_merge_methods` | all three | all three | The GitHub default, written out so a live read-back diffs clean |
| `required_status_checks` | CI | CI and the security scan | The named checks must pass on the pull request head. Not strict: the branch need not be up to date |

## `agent-guard`: a person between an agent and the default branch

This is separate from `baseline` on purpose. `baseline` applies to everyone, so adding "pull request and one
approval" to it would also bind any maintainers an adopter chooses to exempt. `agent-guard` gates everyone except
organization admins and one named team of people. In practice that means GitHub App identities, such as a coding
agent's, and any member outside the team.

- **`bypass_mode: always`**, not `pull_request`, so the exempted team is not affected by it at all. Whether to
  exempt anyone is the adopter's choice. Remove the team from `bypass_actors` to bind people as well.
- **The approval must come from the named team** (`required_reviewers`, every file). An approval count alone is not
  enough. Any installed app that holds `pull_requests: write` can submit an approving review, so one agent app
  could approve another's pull request. The team holds only people. Keep it that way.
- **`require_last_push_approval` is off on purpose.** With it on, a reviewer who commits a suggestion becomes the
  last pusher and can no longer approve, and the author never can. On a small team with no third eligible
  reviewer, that is a deadlock. It adds nothing against the agent,
  because `dismiss_stale_reviews_on_push` already voids an approval when the agent pushes after it.
- **Evaluate first.** Each hit in Rule Insights is either the guard working or a person who should be in the team.

## The code-owner trap

`production` requires approval from a code owner, but only for changed files that a `CODEOWNERS` file covers. With
no file, or a file with gaps, one approval from anyone with write access satisfies the rule. Give every Tier A
repository a `CODEOWNERS` with a catch-all line (`*`) first.

GitHub also ignores an author's approval of their own pull request.

- If your agents open pull requests **as a person**, that person can never be the approving code owner on an agent
  pull request. A `CODEOWNERS` file that names only that person cannot be satisfied by anyone, and the admin bypass
  becomes the only merge route.
- Name at least two code owners, or give the agent its own identity (a GitHub App). With its own identity, a
  person's approval is a real review.

## The admin bypass, and what it costs

`baseline`, `standard` and `production` let organization admins bypass through a pull request only.

- Under `standard` and `production`, a direct push to the default branch is rejected, admins included, because
  their bypass works only through a pull request. `baseline` has no pull-request rule. It stops deletion and
  force-push only, and an ordinary direct push still succeeds under it.
- `agent-guard` is different: its bypass actors have `always`, so they can push directly.
- A bypass merge is logged in Rule Insights, so each one is visible when you read the data.
- **A bypass skips the required checks as well as the review.** For an admin's own merges, CI and the security
  scan are advisory. Treat an admin merge as the exception, never the normal merge step, and count bypasses
  separately from failures when you read the data.

## Apply

`apply.ps1` is the supported way to create or change a ruleset. It is a dry run by default.

**Status of the write path: `configured-unverified`.** The read path (the dry run) has been run against a real
organization. The write path of this version has been tested only against a fake `gh` (`tests/apply.tests.ps1`).
Whether GitHub accepts each file depends on your plan and on the API as it is when you run it. Use `-Execute`
first in an organization you can afford to get wrong, create each ruleset in evaluate, run the dry run again, and
read the ruleset back before you rely on it.

```powershell
pwsh -NoProfile -File rulesets/apply.ps1 -Org YOUR_ORG                             # dry run: standard and production
pwsh -NoProfile -File rulesets/apply.ps1 -Org YOUR_ORG -Name baseline              # dry run: baseline
pwsh -NoProfile -File rulesets/apply.ps1 -Org YOUR_ORG -Name standard -Execute     # POST if none of that name exists, else PUT
```

The script matches live rulesets by `name`, drops read-only fields, and sorts keys and rules. It treats an
`OrganizationAdmin` bypass read back as `"actor_id": null` as the `1` the API asks for on write. Keep `1` in the files.

`-Execute` takes exactly one `-Name`, because the API has no transaction and a failure part-way must not leave
an organization half changed. It refuses to run unless the checkout is on `main`, level with `origin/main`, with
a clean working tree. With `-Execute` the payload is read from the commit itself (`git show HEAD:`), not from the
working tree, so what is sent is the committed JSON, with line endings normalised. GitHub offers no transaction
for rulesets, so the script looks at the live state once more just before it writes and stops if anything changed
since the diff. That narrows the gap and does not close it: nobody else should edit rulesets while you apply. The script refuses a file that carries a read-only key such as
`id`, because the diff hides those. The dry run reads the file on disk, works from any branch, and only reads
from GitHub.

**The first dry run after a create may not read "no changes".** The API can return default keys the files do not
carry. The script keeps unknown keys, so they show as `-` lines. That is read-back noise, not drift. Tolerate it.
Add a key to a file only after confirming it is in the documented request body for creating a ruleset. A key that
exists only in responses can make the update fail.

## Before a ruleset goes active

Read Rule Insights weekly for four weeks and explain every failure:

This is one line, so it works in PowerShell and in Bash:

```
gh api --paginate "orgs/YOUR_ORG/rulesets/rule-suites?time_period=week&rule_suite_result=all&per_page=100" --jq '.[] | [.pushed_at, .repository_name, .ref, .actor_name, .result, .evaluation_result] | @tsv'
```

Common gaps to look for in that data:

- **Direct pushes to the default branch.** Once `standard` or `production` is active, its pull-request
  rule refuses every direct push to the default branch of the repositories it targets, admins included. Under
  `agent-guard`, the same holds for everyone outside its bypass list. Count how much of your work lands that way before you flip anything.
  Scheduled automation that pushes fixes straight to a default branch must move to pull requests first.
- **Repositories with no CI caller.** A required check that never reports blocks every pull request. Every
  repository a ruleset targets needs a workflow that produces the named check, including the repository that holds
  the reusable workflows.
- **`CODEOWNERS` files that one person cannot satisfy.** See the trap above.

## Prove it with a canary

Keep one repository whose job is to break on purpose. After every change to a ruleset, run the probes:

1. **A direct push** of a harmless line to the default branch. Expect a rejection that names the pull-request rule.
   If it is accepted, revert it by pull request.
2. **A merge with zero approvals** by a member who is not an admin. Expect a refusal, and a merge state of `BLOCKED`.
   An admin cannot run this probe: GitHub may log an admin's merge as a bypass, which proves nothing about the rule.

In evaluate, the same two actions succeed and show up in Rule Insights as what would have been blocked. If the
direct push shows nothing from `production`, the targeting is wrong: check the repository's `tier` value.

## Roll back

The primary route is the web page: organization Settings, Rules, Rulesets, open the ruleset, and change its
enforcement status to Evaluate or Disabled. It needs an organization owner.

From the command line, the update endpoint documents its fields as optional, so this should change one field:

```bash
gh api -X PUT orgs/YOUR_ORG/rulesets/RULESET_ID -f enforcement=evaluate   # stop blocking, keep logging
gh api -X PUT orgs/YOUR_ORG/rulesets/RULESET_ID -f enforcement=disabled   # off entirely
```

Try it on a ruleset that is already in evaluate before you need it in an incident, and read the ruleset back to
confirm nothing else changed.

Then set the same `enforcement` in the file and commit it, so the file and the live ruleset agree. After any
change, run the canary probes again.
