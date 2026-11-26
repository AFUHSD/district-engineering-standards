# Why this setup exists

This page gives the full answer to each problem in the table in the [README](../README.md). The problems are the
ones a school district technology team meets when it lets coding agents build and operate things. Each section
says what we do, why, and one limit we know about.

The format is adapted from Byungkyu Lee's [claude-academic-setup](https://github.com/letitbk/claude-academic-setup),
which does the same for academic research. The problems and answers here are our own.

This page describes practice. It is not an inventory of any district's systems, and it names none.

## 1. Can I trust what the agent says it did?

An agent reports a finished task in the same confident voice whether or not the work ran. Nobody can read every
line it writes.

Our answer is to make the plan and the evidence short enough for a person to read. Work starts from an issue
with a definition of done written as items that are true or false, and a list of what is out of scope
([`program.md`](program.md#how-to-track-it)). Before it opens a pull request, the agent runs a verify gate: a
build with warnings as errors, then the full test suite. It pastes the counts into the pull request and says
plainly what it did not verify. Each integration carries one of four statuses, `mocked`,
`configured-unverified`, `live-verified` or `blocked`, with a date. A passing mock never counts as live.

**The limit.** A gate proves only what it runs. An incremental build hides old warnings, and a test that returns
early reports as passed ([`plugin-on-windows.md`](plugin-on-windows.md#what-the-gate-does-and-does-not-prove)).
The counts in a pull request are still the agent's own report until CI repeats them.

## 2. Who checks the agent?

An agent that checks its own work tends to miss the mistakes it made.

Our answer is a second model from another vendor. It is asked to review every pull request an agent opens. The
agent reads every finding and replies on its thread with what changed, or why nothing did. It resolves the
thread only after that, so an open thread always means something is still needed.

For security and platform work, the agents also keep written review notes, each in its own file. Every claim
names its primary evidence and what would overturn it. "Verified" means the reviewer looked at the live state,
not at the other agent's write-up. A request for a person to approve a live change is not ready until another
agent has reviewed it this way.

**The limit.** AI review is advisory and never counts as approval. The reviewer does not always look again after
a later push, and a summary that reads as finished can sit in front of unread findings. A person still decides
what merges.

## 3. Who did this, a person or an agent?

If an agent commits and comments as the person it works for, nobody can tell the two apart later. That person
also cannot approve their own pull request, so the review rule becomes either unmeetable or meaningless
([`rulesets/README.md`](../rulesets/README.md#the-code-owner-trap)).

Our answer is to give the agent its own GitHub App identity. Each command runs with a short-lived token narrowed
to one repository. The app has no permission to edit workflow files. The
[`agent-guard`](../rulesets/README.md#agent-guard-a-person-between-an-agent-and-the-default-branch) ruleset
requires an approval from a team that holds only people before anything reaches a default branch. Every comment
an agent posts starts with a line that says which agent wrote it and for whom. When the app is refused, the
agent stops and reports. It never retries as the person.

**The limit.** A separate identity gives attribution, not containment. An agent that runs in a person's session
can still reach that person's login, so "never retry as the person" is a rule the agent follows, not a wall. A
ruleset in evaluate only logs. Until it is active, staying off the default branch is also a rule the agent
follows.

## 4. Who changes production?

An agent that is right about a fix will apply it unless it is told to stop.

Our answer is that the agent prepares and a person acts. The agent may investigate, measure, write the script,
prove it in a sandbox and open the pull request. Then it stops and presents the change with its evidence. A
person runs it. A report of a symptom is not permission for the remedy. Scripts that change something are a dry
run by default and need an explicit switch to write, as
[`rulesets/apply.ps1`](../rulesets/README.md#apply) does. A production deploy waits on an environment approval
that a person clicks. Some actions stay with people whoever asks: deploy approval, credential rotation, access
grants and messages to families ([`self-healing.md`](self-healing.md#guardrails)).

**The limit.** The stop is an instruction. Only the environment approval is enforced, and only where the deploy
runs through the pipeline. A dry run also does not catch everything. Some failures appear only on the first real
run, so rehearse the rollback before you need it.

## 5. Where does student data go?

A coding agent session is a hosted model. Whatever a query prints into the session goes to the vendor.

Our answer has three parts. A model the district hosts itself is the preferred place for any work with students
in it. A hosted model receives student data only under a district data agreement. In both cases the agent asks
for counts and rates, not rows. No student name or identifier goes into a repository, a pull request, a review
note or a published page, and synthetic data is used for fixtures and demos. When a person needs the identifying
rows, they are delivered to that person outside the agent's transcript. Text that came from staff or families is
cleaned on our own infrastructure before it goes to a hosted service, and the result is checked with a
deterministic scan, not with a model's say-so ([`self-healing.md`](self-healing.md#guardrails)).

**The limit.** We began with "student data never reaches a hosted model" and found that a coding session could
not keep that promise by itself, so the rule is now a preference with an agreement behind it. The control is the
shape of the query. That is a rule the agent follows, not a block.

## 6. Will a secret end up in git?

Remembering not to commit secrets does not work for long. An agent also reads whatever file it is allowed to
open.

Our answer starts with configuration. The repository carries the shape of the configuration, and each machine
supplies the values through a channel git cannot see
([`public-readiness.md`](public-readiness.md#the-checklist), item 5). Where we can, we remove the secret
entirely, for example with integrated authentication in place of a stored password. A commit hook, installed
once for every repository on the machine, refuses credential-shaped paths, data files and known secret patterns.
The agent's settings carry deny rules, so it cannot read environment files, key files or the secrets folder.
Agents never add an allow-list entry to quiet a scanner. They change the content, or they stop and report.

**The limit.** A local hook exists only where it is installed, and one flag skips it. Scanning on the server has
to be turned on for each repository. A guard can also fail open after an edit, so run it against a planted
secret every time you change it.

## 7. Agents forget what the district knows

Every session starts empty. An agent that does not know a local trap writes a plausible query that is silently
wrong.

Our answer is two shared stores, both in git. The first is a repository of skills that every agent loads. It
holds what an agent must not get wrong: where data lives, how an app is hosted, how a job is registered. An
agent that learns a new trap writes it into the skill before the session ends, and a weekly scheduled audit
checks the skills against facts it can test. The second is an ontology of how the district operates: processes,
roles and decisions as records. Records name roles, never people. Every fact carries a dated source. Every
record has one of four visibility levels. A question nobody can answer goes into a ledger and is not guessed.
The public method is in [district-ontology-commons](https://github.com/lukeallpress/district-ontology-commons).

**The limit.** A record marked as drafted was written from code and documents, and its owner has not confirmed
it. A skill is also only an instruction, and an agent can ignore it. That is why the rules that matter most move
into checks ([`program.md`](program.md#the-eight-rules)).

## 8. What if it fails and nobody hears?

A job that fails quietly looks the same as a job that works. A job that never runs has no failed run to alert
on.

Our answer is to make failure loud and absence visible. Every recurring job is registered in one place with its
owner, its schedule and its last run. The exit code is the status. A batch that swallows one item's error so the
others can continue still exits non-zero at the end. A daily watchdog looks for the opposite problem, a
registered workload that nothing runs. A test that needs a live database reports as skipped. It never passes by
returning early. The wider design is in [`self-healing.md`](self-healing.md).

**The limit.** The watchdog is itself a job, and it can stop too. An alarm that carries false positives teaches
everyone to ignore it. So a job that is off on purpose is acknowledged with a written reason, and it alarms
again when it is turned back on.

## 9. Agents do more than asked

Agents add things nobody asked for and change files that have nothing to do with the task. Extra work is more to
review, and it is easy to miss.

Our answer is to make the edges of the task explicit. The issue says what is out of scope. Each task gets its
own worktree, so an agent never works in a checkout that another session is using. Files are staged by name,
never all at once, because a sweeping add also picks up whatever sits beside the files you meant. Some paths
are protected: workflow files, deploy scripts and SQL migrations that have already been applied
([`self-healing.md`](self-healing.md#guardrails)). A change to an applied migration is a new numbered script. An
audit or a review reports findings and fixes nothing.

**The limit.** Nothing measures the size of a diff. The app identity cannot edit workflow files, and that part
is enforced. The rest is instruction, and the reviewer judges whether a change stayed small.

## 10. How do other builders publish safely?

Once agents make building easy, more staff build. Giving each of them administrator rights on the web host is
not an answer.

Our answer is one route for everyone: a branch, a pull request, a review by a named person, and then the merge
to `main` is the publish. A runner on the host does the deploy, so nobody new gets host access. The app's own
identity holds the data access, not the developer, so a builder with little access can work on an app that has
more. The runner never executes deploy code from the branch it is deploying. A branch controls the artifact and
nothing else. Each app can have a development instance where email is redirected to a test recipient.

**The limit.** GitHub ignores an author's approval of their own pull request. On a team with one reviewer, that
reviewer's own changes merge by an admin bypass, and a bypass skips the required checks as well as the review
([`rulesets/README.md`](../rulesets/README.md#the-admin-bypass-and-what-it-costs)).

## 11. Agents write text people cannot read

Agents write fluent text that buries the outcome. A principal or a teacher will not dig for it.

Our answer is a short set of style rules for anything a person reads. Put the outcome first. Use short
sentences. Use no em dashes and no arrows. Name roles, not people, in documents. Refer to a pull request by a
link, never by a bare number. Give a reader a link, never a file path. Write times on the 24-hour clock. Any
message an agent sends says in its first line that an agent wrote it, so it never passes as the person.

**The limit.** Nothing checks these rules. They are a prompt, and a prompt can be ignored. A person reads the
text before it reaches staff.
