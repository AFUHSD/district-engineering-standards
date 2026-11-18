<#
.SYNOPSIS
  Apply the organization rulesets in this folder to a GitHub organization. DRY-RUN by default.

.DESCRIPTION
  For each ruleset file, finds the live org ruleset with the same "name" (gh api orgs/YOUR_ORG/rulesets) and prints
  a unified diff of live -> file. The dry run only reads from GitHub. No ruleset is created or changed unless
  -Execute is passed, and -Execute takes exactly one -Name:
    no live ruleset of that name  -> POST orgs/YOUR_ORG/rulesets
    one live ruleset of that name -> PUT  orgs/YOUR_ORG/rulesets/RULESET_ID
  Two live rulesets with the same name is an error; fix it by hand first.

  Both sides are normalised before diffing: read-only fields (id, node_id, source, timestamps, _links,
  current_user_can_bypass) are dropped, keys are sorted, rules are ordered by type, and an OrganizationAdmin
  bypass read back as "actor_id": null is compared as 1 (what the API asks for on write; see README.md).

  Run as an organization owner, with your own gh login. Reads need only org read access; -Execute needs admin:org.
  -Execute refuses to run unless the checkout is on main, clean, and level with origin/main. The dry run works anywhere.
  -Execute also refuses a file that still carries the placeholder team id 0 (agent-guard.json as shipped).

.EXAMPLE
  pwsh -NoProfile -File rulesets/apply.ps1 -Org my-district                           # dry run: standard + production
  pwsh -NoProfile -File rulesets/apply.ps1 -Org my-district -Name baseline            # dry run: baseline only
  pwsh -NoProfile -File rulesets/apply.ps1 -Org my-district -Name production -Execute # create or update production
  pwsh -NoProfile -File rulesets/apply.ps1 -Org my-district -Name agent-guard         # dry run: the agent guard
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9-]*$')] [string]$Org,
    [ValidateSet('baseline', 'standard', 'production', 'agent-guard')]
    [string[]]$Name = @('standard', 'production'),
    [switch]$Execute
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Gh {
    param([string[]]$GhArgs)
    # stdout and stderr are kept apart, so a warning on stderr can never corrupt the JSON on stdout.
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $out = & gh @GhArgs 2> $errFile
        $code = $LASTEXITCODE
        $err = (Get-Content -Raw $errFile -ErrorAction SilentlyContinue)
    } finally { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
    if ($code -ne 0) { throw "gh $($GhArgs -join ' ') failed: $err $out" }
    return ($out -join "`n")
}

function Read-WriteResult {
    # After a POST or PUT has returned success, an unreadable reply must not look like a failed write.
    param([string]$Text, [string]$What)
    try { return ($Text | ConvertFrom-Json -Depth 50) }
    catch { throw "$What was accepted by GitHub, but its reply could not be read. The ruleset has probably changed. Run the dry run to check before you retry." }
}

function Test-AgentGuardTeams {
    # agent-guard must name exactly one team as a bypass actor and exactly one team as the required reviewer,
    # and they must be the same team. Returns a reason when it does not, and nothing when it does.
    param($Ruleset)
    $bypass = @(@($Ruleset.bypass_actors) | Where-Object { $_ -and $_.actor_type -eq 'Team' } | ForEach-Object { $_.actor_id })
    $reviewers = @()
    $other = 0
    foreach ($rule in @($Ruleset.rules)) {
        if ($rule -and $rule.type -eq 'pull_request' -and $rule.parameters.PSObject.Properties['required_reviewers']) {
            foreach ($rr in @($rule.parameters.required_reviewers)) {
                if ($rr.reviewer.type -eq 'Team') { $reviewers += $rr.reviewer.id } else { $other++ }
            }
        }
    }
    if ($other) { return "a required reviewer is not a Team" }
    if ($bypass.Count -ne 1) { return "expected exactly one Team in bypass_actors, found $($bypass.Count)" }
    if ($reviewers.Count -ne 1) { return "expected exactly one Team in required_reviewers, found $($reviewers.Count)" }
    if ($bypass[0] -ne $reviewers[0]) { return "the bypass team ($($bypass[0])) is not the required reviewer team ($($reviewers[0]))" }
}

function Get-TeamIds {
    # Every team id a ruleset names: in its bypass list and as a required reviewer.
    param($Ruleset)
    $ids = @()
    foreach ($a in @($Ruleset.bypass_actors)) { if ($a -and $a.actor_type -eq 'Team') { $ids += $a.actor_id } }
    foreach ($rule in @($Ruleset.rules)) {
        if ($rule -and $rule.type -eq 'pull_request' -and $rule.parameters.PSObject.Properties['required_reviewers']) {
            foreach ($rr in @($rule.parameters.required_reviewers)) { if ($rr.reviewer.type -eq 'Team') { $ids += $rr.reviewer.id } }
        }
    }
    return , $ids
}

$ReadOnly = @('id', 'node_id', 'source', 'source_type', 'created_at', 'updated_at', '_links', 'current_user_can_bypass')

function ConvertTo-Canonical {
    param($Value, [switch]$Top)
    if ($Value -is [System.Collections.IDictionary]) {
        $sorted = [ordered]@{}
        foreach ($k in ($Value.Keys | Sort-Object)) {
            if ($Top -and $ReadOnly -contains $k) { continue }
            $v = $Value[$k]
            if ($k -eq 'rules' -and $v) { $v = @($v | Sort-Object { $_['type'] }) }
            if ($k -eq 'bypass_actors' -and $v) {
                $v = @($v | ForEach-Object {
                    $a = @{}
                    foreach ($kv in $_.GetEnumerator()) { $a[$kv.Key] = $kv.Value }
                    if ($a['actor_type'] -eq 'OrganizationAdmin' -and $null -eq $a['actor_id']) { $a['actor_id'] = 1 }
                    $a
                } | Sort-Object { "$($_['actor_type'])|$($_['actor_id'])" })
            }
            $sorted[$k] = ConvertTo-Canonical $v
        }
        return $sorted
    }
    if ($Value -is [System.Collections.IList]) { return , @($Value | ForEach-Object { ConvertTo-Canonical $_ }) }
    return $Value
}

function Get-CanonicalJson {
    param([string]$Json)
    $h = $Json | ConvertFrom-Json -AsHashtable -Depth 50
    return (ConvertTo-Canonical $h -Top | ConvertTo-Json -Depth 50)
}

$here = $PSScriptRoot

if ($Execute -and $Name.Count -ne 1) {
    # The API has no transaction. One ruleset per run, so a failure can never leave the organization half changed.
    throw "-Execute refused: name exactly one ruleset with -Name (got $($Name.Count)). The dry run may show several."
}

if ($Execute) {
    # -Execute sends the file as it is on disk, so only a clean main that is level with origin/main may send it.
    # A stale or edited baseline.json on a feature branch must never be PUT over the Active ruleset.
    $branch = (& git -C $here rev-parse --abbrev-ref HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "-Execute: $here is not in a git checkout" }
    if ($branch -ne 'main') { throw "-Execute refused: on branch '$branch'. Check out main (the merged files) and re-run." }
    $dirty = & git -C $here status --porcelain
    if ($LASTEXITCODE -ne 0) { throw '-Execute: git status failed' }
    if ($dirty) { throw "-Execute refused: the working tree is not clean:`n$($dirty -join "`n")" }
    & git -C $here fetch --quiet origin main
    if ($LASTEXITCODE -ne 0) { throw '-Execute: git fetch origin main failed' }
    $headSha = (& git -C $here rev-parse HEAD).Trim()
    $originSha = (& git -C $here rev-parse origin/main).Trim()
    if ($headSha -ne $originSha) { throw "-Execute refused: main ($headSha) is not level with origin/main ($originSha). Pull first." }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("rulesets-apply-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

try {
    # Every page, one "id<TAB>name" line per ruleset. A same-named ruleset on a later page must not be missed,
    # or -Execute would create a duplicate.
    $listing = Invoke-Gh @('api', '--paginate', "orgs/$Org/rulesets?per_page=100", '--jq', '.[] | [.id, .name] | @tsv')
    $live = @($listing -split "`r?`n" |
        Where-Object { $_.Trim() } | ForEach-Object {
            $parts = $_.Trim() -split "`t", 2
            if ($parts.Count -ne 2 -or $parts[0] -notmatch '^\d+$') { throw "could not read the ruleset list: '$_'" }
            [pscustomobject]@{ id = [long]$parts[0]; name = $parts[1] }
        })
    $mode = if ($Execute) { 'EXECUTE' } else { 'DRY RUN (pass -Execute to apply)' }
    $ghHost = if ($env:GH_HOST) { $env:GH_HOST } else { 'github.com (the gh default)' }
    Write-Host "Org $Org on $ghHost - $mode" -ForegroundColor Cyan

    foreach ($n in $Name) {
        $file = Join-Path $here "$n.json"
        if (-not (Test-Path $file)) { throw "missing $file" }
        # The content is read once and that one snapshot is diffed and sent: gh is never given $file.
        # With -Execute it comes from the commit, not the working tree, so what is sent is the committed JSON
        # (its text, with line endings normalised to LF and no trailing newline; the JSON itself is unchanged)
        # (git status can read clean while a tracked file differs, for example under skip-worktree).
        if ($Execute) {
            $raw = (& git -C $here show "HEAD:./$n.json") -join "`n"
            if ($LASTEXITCODE -ne 0) { throw "-Execute: could not read $n.json from HEAD" }
        } else {
            $raw = Get-Content -Raw $file
        }
        $send = Join-Path $scratch "$n.send.json"
        [System.IO.File]::WriteAllText($send, $raw, [System.Text.UTF8Encoding]::new($false))
        $fileObj = $raw | ConvertFrom-Json -Depth 50
        if ($fileObj.name -ne $n) { throw "$file has name '$($fileObj.name)', expected '$n'" }
        # The diff drops read-only keys from both sides. A file that carries one would send something the diff hid.
        $carried = @($fileObj.PSObject.Properties.Name | Where-Object { $ReadOnly -contains $_ })
        if ($carried) { throw "$file carries read-only key(s) $($carried -join ', '). Remove them: the diff does not show them." }
        # A file as shipped names team 0, which is no team. Sending it would create a guard nobody can satisfy.
        # The diff reads an OrganizationAdmin actor_id of null as 1. A file must say 1, so the diff shows what is sent.
        foreach ($actor in @($fileObj.bypass_actors)) {
            if ($actor -and $actor.actor_type -eq 'OrganizationAdmin' -and $actor.actor_id -ne 1) {
                throw "$file has an OrganizationAdmin bypass whose actor_id is not 1. Write 1: that is what the API asks for."
            }
        }
        $teamIds = Get-TeamIds $fileObj
        # A guard that exempts one team and requires approval from another is a typo, not a policy.
        if ($n -eq 'agent-guard') {
            $why = Test-AgentGuardTeams $fileObj
            if ($why) { throw "$file is not a usable guard: $why." }
        }
        $placeholder = $teamIds -contains 0
        if ($placeholder -and $Execute) { throw "-Execute refused: $file still has the placeholder team id 0. Put your team's id in both places first (rulesets/README.md)." }
        if ($placeholder) { Write-Host "NOTE: $n.json still has the placeholder team id 0. -Execute will refuse it." -ForegroundColor Yellow }

        Write-Host "`n=== $n  (file enforcement: $($fileObj.enforcement))" -ForegroundColor Cyan
        $match = @($live | Where-Object { $_.name -eq $n })
        if ($match.Count -gt 1) { throw "$($match.Count) live rulesets are named '$n' (ids $($match.id -join ', ')); resolve by hand" }

        if ($match.Count -eq 0) {
            Write-Host "No live ruleset named '$n'. Would CREATE:" -ForegroundColor Yellow
            Get-CanonicalJson $raw | Write-Host
            if ($Execute) {
                # GitHub has no transaction here. Look once more, so a ruleset someone created a moment ago is not duplicated.
                $again = Invoke-Gh @('api', '--paginate', "orgs/$Org/rulesets?per_page=100", '--jq', '.[] | .name')
                if (@($again -split "`r?`n" | Where-Object { $_.Trim() -eq $n }).Count) { throw "-Execute stopped: a ruleset named '$n' appeared while this ran. Nothing was sent. Run the dry run again." }
                $created = Read-WriteResult (Invoke-Gh @('api', '-X', 'POST', "orgs/$Org/rulesets", '--input', $send)) "The create of '$n'"
                Write-Host "CREATED '$n' as id $($created.id) (enforcement $($created.enforcement))" -ForegroundColor Green
                Write-Host "Record the id where your team keeps it."
            }
            continue
        }

        $id = $match[0].id
        $liveJson = Invoke-Gh @('api', "orgs/$Org/rulesets/$id")
        $a = Join-Path $scratch "$n.live.json"
        $b = Join-Path $scratch "$n.file.json"
        Set-Content -Path $a -Value (Get-CanonicalJson $liveJson) -NoNewline
        Set-Content -Path $b -Value (Get-CanonicalJson $raw) -NoNewline
        $diff = & git --no-pager diff --no-index --no-color -- $a $b
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Live ruleset $id matches the file: no changes." -ForegroundColor Green
            continue
        }
        if ($LASTEXITCODE -ne 1) { throw "git diff failed ($LASTEXITCODE)" }
        Write-Host "Live ruleset $id differs (- live, + file):" -ForegroundColor Yellow
        $diff | Select-Object -Skip 4 | ForEach-Object {
            $c = if ($_ -like '+*') { 'Green' } elseif ($_ -like '-*') { 'Red' } else { 'Gray' }
            Write-Host $_ -ForegroundColor $c
        }
        if ($Execute) {
            # Look once more. If someone changed the live ruleset after the diff above was made, stop rather than overwrite it.
            $recheck = Get-CanonicalJson (Invoke-Gh @('api', "orgs/$Org/rulesets/$id"))
            if ($recheck -cne (Get-CanonicalJson $liveJson)) { throw "-Execute stopped: live ruleset $id changed while this ran. Nothing was sent. Run the dry run again." }
            $updated = Read-WriteResult (Invoke-Gh @('api', '-X', 'PUT', "orgs/$Org/rulesets/$id", '--input', $send)) "The update of '$n'"
            Write-Host "UPDATED '$n' (id $id, enforcement $($updated.enforcement))" -ForegroundColor Green
        }
    }
    if (-not $Execute) { Write-Host "`nDry run only. Nothing was changed." -ForegroundColor Cyan }
    else { Write-Host "`nNow re-run the canary probes (rulesets/README.md)." -ForegroundColor Cyan }
} finally {
    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
}
