# Parses every JSON file and every PowerShell script in the repository, and checks the ruleset files.
# It checks syntax, and that each ruleset still has the rules, targets and required checks this kit promises.
# It does not validate the files against the GitHub API.
#
# Two modes:
#   (default)  Template mode, for the public copy. Every ruleset must be in evaluate and name no real team (id 0).
#   -Adopted   For an organization's own copy. Allows active and real team ids. Still refuses an active ruleset
#              that names the placeholder team 0, because nobody could satisfy it.
param([switch]$Adopted, [switch]$ShowPins)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

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

# What each ruleset file must still contain. A change that removes one of these is a weakening, and it must be
# made here, on purpose, in the same pull request.
$Expected = @{
    'baseline'    = @{ Rules = @('deletion', 'non_fast_forward'); Checks = @(); Target = 'all' }
    'standard'    = @{ Rules = @('deletion', 'non_fast_forward', 'pull_request', 'required_status_checks'); Checks = @('ci / district-ci'); Target = 'b-internal' }
    'production'  = @{ Rules = @('deletion', 'non_fast_forward', 'pull_request', 'required_status_checks'); Checks = @('ci / district-ci', 'security / security-scan'); Target = 'a-production' }
    'agent-guard' = @{ Rules = @('pull_request'); Checks = @(); Target = 'all' }
}

function Test-RulesetShape {
    # Returns the reasons a ruleset no longer has the shape this kit promises. Nothing when it does.
    param($Ruleset, $Expect)
    $why = @()
    if ($Ruleset.target -ne 'branch') { $why += "target is '$($Ruleset.target)', expected branch" }
    if (@($Ruleset.conditions.ref_name.include) -notcontains '~DEFAULT_BRANCH') { $why += 'it does not target ~DEFAULT_BRANCH' }
    $types = @($Ruleset.rules | ForEach-Object { $_.type })
    foreach ($t in $Expect.Rules) { if ($types -notcontains $t) { $why += "rule '$t' is missing" } }
    if ($Expect.Target -eq 'all') {
        if (-not $Ruleset.conditions.PSObject.Properties['repository_name'] -or @($Ruleset.conditions.repository_name.include) -notcontains '~ALL') { $why += 'it does not target every repository' }
    } else {
        $vals = @()
        if ($Ruleset.conditions.PSObject.Properties['repository_property']) { $vals = @($Ruleset.conditions.repository_property.include | Where-Object { $_.name -eq 'tier' } | ForEach-Object { $_.property_values }) }
        if ($vals.Count -ne 1 -or $vals[0] -ne $Expect.Target) { $why += "it does not target exactly tier '$($Expect.Target)'" }
    }
    $checkRule = @($Ruleset.rules | Where-Object { $_.type -eq 'required_status_checks' })
    $contexts = @()
    if ($checkRule.Count) { $contexts = @($checkRule[0].parameters.required_status_checks | ForEach-Object { $_.context }) }
    foreach ($c in $Expect.Checks) { if ($contexts -notcontains $c) { $why += "required check '$c' is missing" } }
    if ($checkRule.Count) { foreach ($s in @($checkRule[0].parameters.required_status_checks)) { if (-not $s.PSObject.Properties['integration_id']) { $why += "required check '$($s.context)' is not pinned to an app" } } }
    foreach ($a in @($Ruleset.bypass_actors)) {
        if ($a.actor_type -eq 'OrganizationAdmin' -and $a.actor_id -ne 1) { $why += 'an OrganizationAdmin bypass has an actor_id other than 1' }
        if ($Ruleset.name -ne 'agent-guard' -and $a.bypass_mode -ne 'pull_request') { $why += "a bypass actor has mode '$($a.bypass_mode)', expected pull_request" }
    }
    return , $why
}

# The exact content of each ruleset, pinned. The pin ignores only what an adopter is meant to change: the
# enforcement value and the team id. Anything else (an approval count, a bypass actor, a check name, the app id a
# check is pinned to, a condition) changes the pin and fails the check until the pin is updated on purpose.
# Print the current pins with: pwsh -NoProfile -File .github/check.ps1 -ShowPins
$Pins = @{
    'baseline'    = 'f6979c2f50512ddb26259afa1b8ffb128b3be5f0532dc1ef23aeae7481f424ef'
    'standard'    = 'ebbc1f22a8e85e51e4e8a4a4f2695aa329bbbf36f54ce28ccd491b690107fe8a'
    'production'  = '0961efba0891df795f8881edc01d52bcf48208eb9b1ecb6942ebb511804806d3'
    'agent-guard' = '0ca6118f47eaa2b5ca4aab3a925f19ddebf18aec41d3c827d5bd654591c258df'
}

function Get-RulesetPin {
    param([string]$Json)
    function Sort-Value($v, [string]$key) {
        if ($v -is [System.Collections.IDictionary]) {
            $o = [ordered]@{}
            $isTeam = ($v['actor_type'] -eq 'Team') -or ($v['type'] -eq 'Team')
            foreach ($k in ($v.Keys | Sort-Object)) {
                if ($isTeam -and ($k -eq 'actor_id' -or $k -eq 'id')) { $o[$k] = 0 } else { $o[$k] = Sort-Value $v[$k] $k }
            }
            return $o
        }
        if ($v -is [System.Collections.IList]) { return , @($v | ForEach-Object { Sort-Value $_ $key }) }
        return $v
    }
    $h = $Json | ConvertFrom-Json -AsHashtable -Depth 50
    $h['enforcement'] = 'evaluate'
    $flat = Sort-Value $h '' | ConvertTo-Json -Depth 50 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return (-join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($flat)) | ForEach-Object { $_.ToString('x2') })) }
    finally { $sha.Dispose() }
}

$failed = 0

# -Force, because on Linux a folder whose name starts with a dot is hidden and would otherwise be skipped.
$json = @(Get-ChildItem -Path $root -Recurse -File -Force -Filter *.json | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($f in $json) {
    try { $null = Get-Content -Raw $f.FullName | ConvertFrom-Json -Depth 50 }
    catch { Write-Host "FAIL json   $($f.FullName): $($_.Exception.Message)"; $failed++; continue }
    Write-Host "ok   json   $($f.Name)"
}

foreach ($name in $Expected.Keys) {
    if (-not (Test-Path (Join-Path $root "rulesets/$name.json"))) { Write-Host "FAIL file   rulesets/$name.json is missing"; $failed++ }
}

foreach ($f in (Get-ChildItem -Path (Join-Path $root 'rulesets') -File -Filter *.json)) {
    try { $r = Get-Content -Raw $f.FullName | ConvertFrom-Json -Depth 50 } catch { continue }
    if ($r.name -ne $f.BaseName) { Write-Host "FAIL name   $($f.Name) has name '$($r.name)'"; $failed++ }
    if ($Expected.ContainsKey($f.BaseName)) {
        foreach ($reason in (Test-RulesetShape $r $Expected[$f.BaseName])) { Write-Host "FAIL shape  $($f.Name): $reason"; $failed++ }
        $pin = Get-RulesetPin (Get-Content -Raw $f.FullName)
        if ($ShowPins) { Write-Host "pin  $($f.BaseName) = $pin" }
        elseif ($pin -ne $Pins[$f.BaseName]) { Write-Host "FAIL pin    $($f.Name) no longer matches its pinned content. If the change is intended, update the pin in check.ps1 in the same pull request."; $failed++ }
    } else { Write-Host "FAIL file   $($f.Name) is not one of the four rulesets this kit ships"; $failed++ }
    if ($r.enforcement -notin @('evaluate', 'active', 'disabled')) { Write-Host "FAIL mode   $($f.Name) has enforcement '$($r.enforcement)'"; $failed++ }

    $teamIds = @($r.bypass_actors | Where-Object { $_.actor_type -eq 'Team' } | ForEach-Object { $_.actor_id })
    foreach ($rule in $r.rules) {
        if ($rule.type -eq 'pull_request' -and $rule.parameters.PSObject.Properties['required_reviewers']) {
            $teamIds += @($rule.parameters.required_reviewers | ForEach-Object { $_.reviewer.id })
        }
    }

    # A guard that exempts one team and requires approval from another is a typo, not a policy.
    if ($r.name -eq 'agent-guard') {
        $why = Test-AgentGuardTeams $r
        if ($why) { Write-Host "FAIL team   $($f.Name): $why"; $failed++ }
    }

    if ($Adopted) {
        if ($r.enforcement -eq 'active' -and $teamIds -contains 0) { Write-Host "FAIL team   $($f.Name) is active and still names the placeholder team 0"; $failed++ }
    } else {
        if ($r.enforcement -ne 'evaluate') { Write-Host "FAIL mode   $($f.Name) has enforcement '$($r.enforcement)', expected evaluate in the template"; $failed++ }
        foreach ($id in $teamIds) { if ($id -ne 0) { Write-Host "FAIL team   $($f.Name) names team id $id, expected the placeholder 0 in the template"; $failed++ } }
    }
}

$ps = @(Get-ChildItem -Path $root -Recurse -File -Force -Filter *.ps1 | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($f in $ps) {
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    if ($errors) { Write-Host "FAIL pwsh   $($f.FullName): $($errors[0].Message)"; $failed++ }
    else { Write-Host "ok   pwsh   $($f.Name)" }
}

if ($json.Count -eq 0 -or $ps.Count -eq 0) { Write-Host 'FAIL nothing was checked'; $failed++ }
if ($failed) { Write-Host "$failed failure(s)"; exit 1 }
$modeName = if ($Adopted) { 'adopted' } else { 'template' }
Write-Host "All checks passed ($modeName mode): $($json.Count) JSON, $($ps.Count) PowerShell."
