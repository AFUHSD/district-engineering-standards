# district-engineering-standards

A public, generic engineering standards kit. Documents, ruleset JSON, one operational script, a check and tests.
There is no application here and nothing to build.

## Map

| Path | What | Change it when |
|---|---|---|
| `README.md` | Purpose, first 10 minutes, credit | The contents change |
| `docs/program.md` | Outcomes, rules, phases | The method changes |
| `docs/tier-model.md` | Tiers and custom properties | A gate or a property changes |
| `docs/naming.md` | Naming rule and rename steps | The rule changes |
| `docs/self-healing.md` | The repair ladder | A rung is proven or redesigned |
| `docs/public-readiness.md` | The public checklist | A new way to leak is found |
| `docs/plugin-on-windows.md` | The coding plugin on Windows | A new lesson is learned |
| `rulesets/*.json` | Organization rulesets | A rule changes. `enforcement` stays `evaluate` and team ids stay `0` here. The check enforces both |
| `rulesets/apply.ps1` | Dry-run-first apply script | Rarely. It must stay a dry run by default |
| `org/properties-schema.json` | Custom-property schema | A property changes |
| `tests/apply.tests.ps1` | Tests of `apply.ps1` against a fake `gh` | The script changes |

## Rules for any agent working here

1. **This repository is public.** Never add an internal hostname, server or database name, IP address, account
   name, file path from a real machine, repository inventory, or a person's name other than a credited builder.
   Write the pattern, never the deployment.
2. **Never describe an open security finding**, ours or anyone's, in specifics.
3. **Never run `rulesets/apply.ps1 -Execute`.** It changes an entire organization. A person does that.
4. Work on a branch and open a pull request. A person merges.
5. Check before you finish: `pwsh -NoProfile -File .github/check.ps1` and `pwsh -NoProfile -File tests/apply.tests.ps1`.

## Commands

```
pwsh -NoProfile -File .github/check.ps1                      # the same check CI runs
pwsh -NoProfile -File tests/apply.tests.ps1                  # the apply script against a fake gh; sends nothing
pwsh -NoProfile -File rulesets/apply.ps1 -Org YOUR_ORG -Name baseline   # dry run against an organization you can read
```
