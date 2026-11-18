# Self-repairing software: the ladder

This is a reference design. It describes a target, rung by rung, for any team to build toward. It is not a
description of any one organization's running system.

Peninsula's "self-healing" is two separate things. Keep them apart.

- **Runtime healing.** The running system notices it is wedged and recovers by itself: a guard that rebuilds a
  stuck database pool, workers that start dark, outboxes with idempotency keys.
- **Code healing.** A bug report becomes a fix pull request with no human typing: a tagged help-desk ticket becomes
  a GitHub issue, a scheduled agent run picks it up, several models review it, and a person merges.

Both sit on the same base: **you can only repair what you can detect, and you can only trust a repair you can verify.**

## The ladder

| Rung | What it does | What to build |
|---|---|---|
| **L0 Detect** | Know it is broken before a user does | A shallow and a deep health endpoint on every app. **One prober** over every deep endpoint. A **synthetic canary** per Tier A app: a read-only transaction every few minutes, where a missing result counts as a failure. A **runner check**. **Freshness checks**, where a stale source is an alarm and not an empty page |
| **L1 Diagnose** | Say why, with evidence | Feed any model deterministic inputs: the terminal error and a head and tail excerpt. **Every alarm links to a runbook** in the owning repository |
| **L2 Repair at runtime** | Safe, reversible actions with no code change | A **repair allowlist**: recycle one app pool, restart one service, re-run a job once. Each action is rate-limited, logged, and followed by a notification. Anything off the list goes to a person |
| **L3 Repair code** | Bug to pull request to human merge | The pipeline below |
| **L4 Learn** | Make the same failure less likely to recur | The agent writes a learning into the repository, and learnings are folded into the instructions agents read. Each incident adds a canary probe or a test |

A note on L1: a model digest tends to be reliable at saying *that* something failed and much less reliable about
*why*. Treat the stated cause as a lead, not a finding.

## L3: the code-repair pipeline

```
Help-desk ticket --(staff add a tag such as "agent-fix")--> triage that removes personal data
   |   writes a contract issue with an ID-only reproduction
   v
GitHub issue in the app repository, labelled ready, with a definition-of-done block
   v  scheduled routine (every few hours, ONE issue per run, max turns, kill switch)
agent in a worktree: implement -> verify gate (build, test, SQL guards) -> pull request with evidence
   v
CI: reusable workflow + security scan + advisory AI review
   v
Human review -> merge -> deploy, behind an environment approval
```

## Guardrails

Most are Peninsula's.

1. **Sanitize before anything leaves.** A help-desk ticket may contain personal data about students or staff.
   Remove it on infrastructure you control before any text goes to a hosted service, and check the result with a
   deterministic scan, not with a model's say-so.
2. **Only explicitly tagged tickets.** An untagged ticket is never processed.
3. **One issue per run, bounded.** Max turns, a timeout, and a kill switch that is checked first.
4. **Protected paths.** The agent never edits workflow files, hook configuration, agent configuration, deploy
   scripts, or SQL migrations that have already been applied. It labels the pull request for a human instead.
5. **Never auto-merge.** AI review is advisory and never counts as approval.
6. **Human-only actions stay human** no matter who asks: production deploy approval, credential rotation, messages
   to real families, SQL grants.

## Build order

1. The prober, the runner check and runbook stubs. No agent is involved, so this is the cheapest value.
2. A verify gate in two pilot repositories, so the agent has something to satisfy.
3. Advisory AI review in CI, so the agent has a reviewer to wait for.
4. The manual loop: a person labels an issue ready and starts the agent by hand. Do this ten times and write down
   what broke.
5. Only then schedule it.
6. Runtime repairs, last and narrowest.
