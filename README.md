# district-engineering-standards

How a small school-district technology team makes its engineering standards enforceable, written so another
district can copy it. Published by Agua Fria Union High School District (AFUHSD), Arizona.

The method is Peninsula School District's (PSD401, Washington). We learned it from their public repositories and
their entries in the Agentic Builders cookbook, a public collection of K-12 builds. Their examples are Node, Python and cloud. Examples in this
repository cover common Windows, IIS and SQL Server environments. The ideas are theirs and are
credited below. The text, the JSON files and the scripts in this repository are our own writing. See
[`NOTICE.md`](NOTICE.md) for what is original and what is credited.

## The one idea

A written standard holds only while the person or the agent reading it cooperates. A required check blocks the
merge for everyone who is not a configured bypass actor, whether they cooperate or not. So the goal of the program is to turn each standard into something that fails a build or refuses a
push: a CI job, an organization ruleset, a hook, or a canary repo that breaks on purpose.

This repository ships the method, the rulesets and the script that applies them. It does not ship a reusable CI
workflow, a security scanner or a canary. It recommends no specific implementation of those. Peninsula's public organization, linked under Credit, is the
place to look for worked examples.

## Why this setup exists

These are the problems a district technology team meets when it lets coding agents build and operate things, and
what we do about each. The format is adapted from Byungkyu Lee's
[claude-academic-setup](https://github.com/letitbk/claude-academic-setup).

| | Problem | What we do |
|---|---|---|
| 1 | [Can I trust what the agent says it did?](docs/why-this-setup.md#1-can-i-trust-what-the-agent-says-it-did) | A definition of done before work starts, a verify gate, and counts in the pull request with what was not verified |
| 2 | [Who checks the agent?](docs/why-this-setup.md#2-who-checks-the-agent) | A model from another vendor reviews every agent pull request, and review notes name their evidence |
| 3 | [Who did this, a person or an agent?](docs/why-this-setup.md#3-who-did-this-a-person-or-an-agent) | The agent has its own GitHub identity, signs every comment, and needs a person's approval to reach a default branch |
| 4 | [Who changes production?](docs/why-this-setup.md#4-who-changes-production) | The agent writes the script and stops. A person runs it, dry run first |
| 5 | [Where does student data go?](docs/why-this-setup.md#5-where-does-student-data-go) | A self-hosted model is preferred, counts not rows, and no identifier in anything published |
| 6 | [Will a secret end up in git?](docs/why-this-setup.md#6-will-a-secret-end-up-in-git) | The repository holds the shape of the configuration, a commit hook refuses secrets, and agents never silence a scanner |
| 7 | [Agents forget what the district knows](docs/why-this-setup.md#7-agents-forget-what-the-district-knows) | Shared skills for what an agent must not get wrong, and an ontology of how the district operates |
| 8 | [What if it fails and nobody hears?](docs/why-this-setup.md#8-what-if-it-fails-and-nobody-hears) | One register of jobs, a non-zero exit on any failure, and a watchdog for work that nothing runs |
| 9 | [Agents do more than asked](docs/why-this-setup.md#9-agents-do-more-than-asked) | An out-of-scope list in the issue, one worktree per task, files staged by name, and protected paths |
| 10 | [How do other builders publish safely?](docs/why-this-setup.md#10-how-do-other-builders-publish-safely) | A branch, a pull request, a person's review, and then the merge is the publish |
| 11 | [Agents write text people cannot read](docs/why-this-setup.md#11-agents-write-text-people-cannot-read) | Plain style rules: outcome first, short sentences, roles not people |

[Why this setup exists](docs/why-this-setup.md) gives the full answer to each problem, with one known limit for
each.

## What is here

| Path | What |
|---|---|
| [`docs/why-this-setup.md`](docs/why-this-setup.md) | Eleven problems with trusting coding agents in a district, and what we do about each |
| [`docs/program.md`](docs/program.md) | The four outcomes, the eight rules, and the phases with their exit criteria |
| [`docs/tier-model.md`](docs/tier-model.md) | Tier A, B and C, and the custom properties every ruleset targets |
| [`docs/naming.md`](docs/naming.md) | The repository naming rule and how to rename without breaking anything |
| [`docs/self-healing.md`](docs/self-healing.md) | The detect, diagnose, repair, learn ladder and the bug-to-pull-request pipeline |
| [`docs/public-readiness.md`](docs/public-readiness.md) | The checklist a repo passes before it goes public |
| [`docs/plugin-on-windows.md`](docs/plugin-on-windows.md) | Compatibility notes for running Peninsula's `/plan` and `/lfg` coding plugin on Windows |
| [`rulesets/`](rulesets/) | Four organization rulesets as JSON, and a dry-run-first script that applies them |
| [`org/properties-schema.json`](org/properties-schema.json) | The custom-property schema the rulesets depend on |
| [`tests/apply.tests.ps1`](tests/apply.tests.ps1) | A test of the apply script against a fake `gh`, so nothing is sent anywhere |

## First 10 minutes

1. Read [`docs/program.md`](docs/program.md). It is the map.
2. Read [`docs/tier-model.md`](docs/tier-model.md) and decide which of your repos are Tier A.
3. Look at what the rulesets would do to your organization, without changing anything:

   ```
   pwsh -NoProfile -File rulesets/apply.ps1 -Org YOUR_ORG
   pwsh -NoProfile -File rulesets/apply.ps1 -Org YOUR_ORG -Name baseline
   pwsh -NoProfile -File rulesets/apply.ps1 -Org YOUR_ORG -Name agent-guard
   ```

   Replace `YOUR_ORG` with your organization's name. All three are dry runs, and together they cover the four
   rulesets. Each reads your organization's rulesets and prints what it would create or change. No
   ruleset is created or changed without `-Execute`. You need to be able to read your organization's rulesets.
4. Read [`rulesets/README.md`](rulesets/README.md) before you pass `-Execute`. Start every ruleset in `evaluate`.

You need the GitHub CLI (`gh`), PowerShell 7 and git. These files use organization rulesets, targeting by custom
property, and required reviewers from a named team. Each depends on your GitHub plan. Check that yours offers all
three before you plan around them. A plan that lacks one rejects the file when it is applied.

## What this is not

- It is not an operational repository. It is a fresh snapshot of reusable material, not a publication of any
  private repository's commit history.
- It is not a report on any district's state. There is no scorecard, repository list or decision log here.
- It is not a complete kit. See the note above on what is not shipped.

## Credit

Peninsula School District built the pattern: reusable CI with thin callers, tiered rulesets flipped from evaluate
to active, a canary repo, the issue contract, and the `/plan` and `/lfg` loop in their `psd-coding-system` plugin.
Their work is public at <https://github.com/psd401>. Two starting points: their plugin marketplace,
<https://github.com/psd401/psd-claude-plugins>, and their canary, <https://github.com/psd401/psd-standards-canary>.

Maintainer: Luke Allpress, Director of Innovation, AFUHSD.

## License

MIT. See [`LICENSE`](LICENSE).
