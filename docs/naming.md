# Repository naming

This is Peninsula's rule with a prefix of your own. Below, `<prefix>` is your district's short prefix. In the
commands, replace the words in capitals with your own values.

## The rule

1. **`<prefix>-<product>`** for anything district-specific: apps, jobs, feeds, infrastructure and documents.
   `<product>` is the name staff use for it, not an internal abbreviation.
2. **A plain generic name** for anything you intend to publish for other districts. The name says what the tool
   does, not who wrote it. This repository follows that rule.
3. **`template-<stack>-<kind>`** for starter repositories, for example `template-dotnet-razor-app` or
   `template-python-job`.
4. **Lowercase kebab-case only.** No underscores, dots or capitals. Python package names inside stay snake_case.
5. **The default branch is `main`**, everywhere.
6. **The repository name `.github`** is reserved for the organization defaults and the reusable workflow library.
   This is the special repository of that name, not the `.github/` folder every repository may have.

## Renaming a repository does not move its folder

GitHub redirects the old URL for git and for the web, so existing clones usually keep working for a while. Do
not rely on it: the redirect stops if the old name is ever reused, and integrations, badges and hard-coded
references can still need changing. **Local folders do not move**, and anything tied to a path on disk, such as a scheduled task, should stay where it is. A rename is:

1. `gh repo rename NEW_NAME -R YOUR_ORG/OLD_NAME`
2. `git remote set-url origin https://github.com/YOUR_ORG/NEW_NAME.git` in every clone, including any self-hosted runner.
3. In the same pull request: update every `uses: YOUR_ORG/OLD_NAME/...`, deploy workflow, README badge, skill reference
   and outside link.
4. Rename `master` to `main` in the same wave if needed:
   `gh api -X POST repos/YOUR_ORG/YOUR_REPO/branches/master/rename -f new_name=main`.
   The runner, the deploy scripts and any `@master` reference must change in the same wave.
5. Record the rename and the date.

Do it in batches of three to five repositories with a day between batches. Never rename a repository that has an
open deploy or an unmerged release branch.

## Notes

- Keep a rename map: current name, proposed name, who owns it, and what must happen first. Some renames wait on
  other work, and the map is where that is written down.
- Tell the owner before you rename their repository, and do not reuse the old name.
- An old repository may need an archive decision rather than a new name. Treat archiving as its own wave.
