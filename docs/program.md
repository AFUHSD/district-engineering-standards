# The program

This program follows how Peninsula School District builds software. It takes their patterns one enforced step at
a time. Examples cover common Windows, IIS and SQL Server environments.

## The four outcomes

1. **Standards are enforced, not suggested.** For everyone who is not a configured bypass actor, GitHub refuses
   a direct push to the default branch and blocks the merge of a pull request whose required checks are red. A
   canary repo proves it still does. A pull request with no tests is refused only if your CI workflow fails when it finds
   zero tests. A required check knows only that a named check reported success, so build that failure in.
2. **Software repairs itself, and a human still decides what ships.** Failures are detected, diagnosed, fixed by a
   pull request and verified. The aim is that a person approves every change an agent makes, and auto-merge stays
   off. The shipped rulesets are designed to enforce that, for everyone except the bypass actors you configure, once you
   have put your team's id in `agent-guard` and changed its enforcement to `active`. As shipped they are in
   evaluate and block nothing.
3. **Repos are named for what they are and are ready to go public.** What is reusable is published from a clean
   snapshot.
4. **The team builds this way.** Each person has a learning track, and the material is shared.

## The eight rules

| Rule | What it means |
|---|---|
| Enforce, don't suggest | A skill file can be ignored. A required check blocks the merge unless someone with a configured bypass uses it, and that use is logged. The aim is for every standard to end up as CI, a ruleset or a hook. |
| Audit before you change | Every wave of changes starts with a committed baseline, so every change has a diff. |
| Evaluate before active | Rulesets and agents run in shadow mode first. Flip one thing at a time, at least two working days apart, and check the canary after each flip. |
| Agents propose, humans decide, code enforces | Keep auto-merge off. Human-only actions are listed in code. A prompt is not trusted to hold them. |
| Honest status | Each integration is `mocked`, `configured-unverified`, `live-verified` or `blocked`, with an evidence date. A passing mock never counts as live. |
| A schema beats a prompt | Model output that drives an action is an enum or a JSON schema, never free text. |
| Prove the guard fires | Every gate has a deliberate-failure test: the canary repo, the secret scanner against a planted secret, the stop hook against a red test. |
| One pull request per repo | Waves go through pull requests a person merges. Never merge a red one. Keep a register of known breakage instead of forcing merges. |

## Phases

Each phase is a GitHub milestone, and its exit criteria are the milestone's definition of done. Dates are yours to
set. The order matters more than the pace.

### Phase 0: stop the bleeding

Before you enforce anything, find what is already exposed. Run a secret scanner over the full history of every
repository, not only the current files. Look for data files that were committed and later deleted. Check that the
machines your automation depends on are actually running: a self-hosted runner that stays stopped after a reboot
fails nothing, so nothing reports it.

**Done when** a full-history scan of every affected repo finds no real secret and no personal data, every rotation
is recorded, and something alarms when a runner is not running.

### Phase 1: foundation

- Create the standards repository and the organization's `.github` repository.
- Commit an organization baseline: repositories, rulesets, Actions permissions, runners, installed apps, admins.
- Create the custom properties in [`tier-model.md`](tier-model.md). A person reviews the tier assignment before it
  is applied.
- Build one reusable CI workflow and one reusable security-scan workflow, and prove both on a canary repository.
- Trial the agent build loop on two real repositories, with one real issue shipped through it in each.

**Done when** the canary goes red on a planted secret, on a pull request with zero tests and on a failing test,
and green on a clean pull request.

### Phase 2: enforcement

- One pull request per Tier A and Tier B repository: a thin CI caller, a Dependabot file, a README, a map-style
  `CLAUDE.md`, an `AGENTS.md` pointer, a `.gitignore`, and `main` as the default branch.
- The naming wave ([`naming.md`](naming.md)), in small batches.
- Organization rulesets committed as JSON ([`../rulesets/`](../rulesets/)), every one created in evaluate.
  `baseline` only forbids deleting or force-pushing a default branch, so it is the first to flip to active, after
  its evaluate data is clean.
- AI pull-request review running as advisory only.
- Template repositories for the stacks you actually use.

**Done when** every Tier A and Tier B repository runs CI on pull requests, four weeks of evaluate data have been
read, and every failure in that data is explained.

### Phase 3: self-repair

The ladder in [`self-healing.md`](self-healing.md): one health prober across every app, a runbook for every alarm,
then the pipeline that turns a tagged help-desk ticket into a pull request a person merges.

**Done when** one real production bug has gone from ticket to merged fix through the pipeline, and each alarm
links to a runbook.

### Phase 4: public

- Choose a small number of candidates with [`public-readiness.md`](public-readiness.md).
- Publish each from a fresh, scrubbed snapshot, never from the private history.
- Flip `standard` to active, then `production`, one at a time.

**Done when** the published repositories pass the public checklist.

## How to track it

- **Issues are the tracker and the plan is the map.** No status lives in a markdown file. When the plan changes,
  it changes by pull request.
- **Every issue uses a contract:** a summary, a definition of done with binary items between
  `<!-- dod:start -->` and `<!-- dod:end -->` markers, what is out of scope, and risk and rollback. A label says an
  agent may pick the issue up. Another says an agent never may.
- **One project board** with five columns: Inbox, Ready, In progress, Awaiting human, Done.
- **A short weekly review.** A decision gets a row in an append-only decision log and closes its issue.
- **Credit.** Anything built from someone else's pattern says so in its README.

## Where to start

- Start with the baseline audit. Expect history to hold more than the current files suggest. You cannot scope the
  work without it.
- Put a ruleset in evaluate and read the data before you believe your own picture of how people push.
- The canary is a cheap and direct way to learn that a gate has silently stopped working.
- An agent that opens pull requests needs its own identity. If it opens them as a person, that person cannot
  approve them, and your review rule becomes either unmeetable or meaningless.
