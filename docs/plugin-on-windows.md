# Running psd-coding-system on Windows

`psd-coding-system` is Peninsula School District's Claude Code plugin. It supplies `/plan`, `/lfg` and a
definition-of-done gate. It is built on macOS. This is an independent compatibility note for Windows that
anyone can reproduce, written against plugin version 3.8.9. It describes the plugin. It does not describe the
software any district has deployed or the controls any district relies on. The plugin changes often. Treat every behaviour described below as something to check on the
version you install, not as a current fact.

## Setup

```
winget install --id jqlang.jq -e --scope user
```

Then in Claude Code:

```
/plugin marketplace add psd401/psd-claude-plugins
/plugin install psd-coding-system@psd-claude-plugins
```

The marketplace also offers `psd-productivity`. It is Peninsula's own operations kit, tied to their vendors, so
it is unlikely to be reusable without review and adaptation.

The hooks run under Git Bash and need a real `jq` and `python3` on its PATH. On Windows `python3` is usually the
Microsoft Store stub, which makes every `.py` edit report a false syntax error. Put two shims in `~/bin`, which
Git Bash searches first. Adjust both paths to your installs:

```bash
mkdir -p ~/bin
printf '#!/usr/bin/env bash\nexec "/c/Program Files/Python311/python.exe" "$@"\n' > ~/bin/python3
printf '#!/usr/bin/env bash\nexec "$HOME/AppData/Local/Microsoft/WinGet/Links/jq.exe" "$@"\n' > ~/bin/jq
chmod +x ~/bin/python3 ~/bin/jq
```

Use Python 3.10 or later. An older interpreter flags `match` statements as syntax errors.

## Checks worth running after install

| Hook | Test | Expected |
|---|---|---|
| Secret redaction on command output | Print a fake token | Replaced with `[REDACTED]`. Normal output untouched |
| Validation after an edit | A broken `.py` file and a valid one using `match` | Blocks the broken one as feedback. Passes the valid one |
| Stop hook | A repository with no `.psd/verify.json` | Inert |

The scripts arrive with CRLF line endings when `core.autocrlf` is true. In the tested setup Git Bash ran them
anyway. If a hook fails with a stray carriage-return error, normalize the scripts to LF.

## Gaps to expect on Windows

- The finalize step searches the filesystem for the gate script, which is slow on Windows. It is harmless. Expect
  a pause.
- The signing and browser-control skills are macOS-only.
- The worktree hook symlinks `.env`. In some Git Bash configurations that becomes a copy. Check the result in
  your environment.
- Check whether `baseline.allow_preexisting_failures` in `verify.json` is read by the gate in your version. In the
  version these notes were written against, it was documented and not read.

## verify.json for .NET and Python

`/setup` detects Node and Python. For .NET, write the file by hand:

```json
{
  "commands": {
    "build": "dotnet build -c Release -warnaserror",
    "test": "dotnet test --no-build -c Release"
  },
  "e2e_required": false,
  "strictness": "block",
  "reviewers": [],
  "commit_learnings": true,
  "auto_worktree": true,
  "screenshot_dir": ".verification"
}
```

A Python job repository uses `"test": "python -m pytest -q"` and `"lint": "python -m ruff check ."`.

## What the gate does and does not prove

Prove the gate first: flip one assertion and confirm it goes red with a non-zero exit code. Then:

- **The gate reads only** `strictness`, `e2e_required` and `commands.*`. The other keys are read by `/lfg`.
- **It writes `.psd/last-gate-result`** with the status, the commit and whether the tree was dirty. A result
  recorded before the final commit carries a stale commit. The stop hook needs a result from after it.
- **`-warnaserror` proves nothing on an incremental build.** Projects that are not recompiled do not re-emit their
  warnings. Only a clean build, or CI, proves zero warnings.
- **Build always runs before test**, so `--no-build` in `test` is safe.
- **A skip must be a real skip.** Tests that need a live database should report as skipped, using a package that
  does that properly. A test that returns early reports as passed. The gate does not cover skipped paths, so say
  so in the pull request.
- **Mixed line endings leave a checkout permanently dirty**, and the gate records that every time. Fix it with a
  one-line renormalize pull request.
- **The gate proves nothing about a stale build tree.** An artifact published from a checkout an agent has built
  in can start and then fail its readiness check with no exception. Build deploy artifacts from a clean
  `git archive` export, never from a working checkout.

## Running it unattended

- **`/plan` and `/lfg` run as forked agents.** Tell them in the argument that nobody is available to answer
  questions, or the fork stalls on one. Give `/plan` the established facts, such as the exact line, the baseline
  numbers and the hazard, and let it own the design.
- **A fork can stop without reporting.** Ask every fork to push its branch and comment on the issue before it
  stops for any reason, so a stalled run can be finished by hand.
- **`auto_worktree: true` moves the parent session too.** Run one fork at a time. For a repository whose gate is
  not on `main` yet, use a fresh clone with an untracked `verify.json` and `auto_worktree: false`. Never use a
  checkout another session builds in.
- **Labels are part of the contract.** Create the ready and needs-human labels in each repository before the
  first run, not during it.
- **Cross-agent review pays for itself even when it is wrong.** A second agent's objection that the code disproves
  costs minutes to answer, and the same review usually surfaces something real.

## Longer term

A PowerShell port of the gate, with a PowerShell stop hook, would remove the dependency on Git Bash shims. Keep
Peninsula's upstream for `/plan`, `/lfg` and the review agents, and track their releases.
