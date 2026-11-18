# Security

This repository holds documents, JSON ruleset definitions and PowerShell scripts. Its only automatic execution is
the read-only validation workflow on pull requests and pushes to `main`.

## Reporting a problem

Use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"), when
it is enabled. If that button is missing, open an issue that says only that you have a security report, with no detail, and a
maintainer will arrange a private channel. Please do not put detail in a public issue for:

- a flaw in `rulesets/apply.ps1` that could change an organization's rulesets without `-Execute`, or apply a file
  other than the one shown in the dry run;
- anything in this repository that looks like it identifies an internal system, an account or a person and should
  not be public.

Reports are reviewed as capacity permits. No response-time commitment is offered.

## What to expect from the script

`rulesets/apply.ps1` is a dry run unless you pass `-Execute`. With `-Execute` it changes branch rules across an
entire GitHub organization, using your own `gh` login. Read the diff it prints first, and start every ruleset in
`evaluate`.
