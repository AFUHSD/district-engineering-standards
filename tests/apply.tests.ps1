# Tests rulesets/apply.ps1 against a fake gh. Nothing is sent to GitHub: a function named gh shadows the real
# command for the length of this script, and the organization name used does not exist.
#
# Each test builds a throwaway git repository with its own bare "origin", because -Execute insists on a clean
# main that is level with origin/main.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failed = 0
$global:FakeGh = @{ Calls = @(); LiveList = ''; LiveBody = '{}'; ChangeAfterReads = -1; Reads = 0 }

function global:gh {
    # Records every call. For a POST or PUT it also records the exact bytes of the --input file.
    $argv = @($args)
    $call = [ordered]@{ args = ($argv -join ' '); method = 'GET'; sent = $null }
    $x = [array]::IndexOf($argv, '-X'); if ($x -ge 0) { $call.method = $argv[$x + 1] }
    $i = [array]::IndexOf($argv, '--input'); if ($i -ge 0) { $call.sent = [System.IO.File]::ReadAllText($argv[$i + 1]) }
    $global:FakeGh.Calls += [pscustomobject]$call
    $global:LASTEXITCODE = 0
    if ($call.method -ne 'GET') { return '{"id": 42, "enforcement": "evaluate"}' }
    if ($call.args -match '--paginate') { return $global:FakeGh.LiveList }
    # ChangeAfterReads = n: the body read of a single ruleset changes after it has been read n times.
    $global:FakeGh.Reads++
    if ($global:FakeGh.ChangeAfterReads -ge 0 -and $global:FakeGh.Reads -gt $global:FakeGh.ChangeAfterReads) { return '{"name": "standard", "enforcement": "active"}' }
    return $global:FakeGh.LiveBody
}

function New-TestRepo {
    # A copy of this repository's files, committed on main, with a bare origin it is level with.
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ('apply-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $work = Join-Path $base 'work'
    $origin = Join-Path $base 'origin.git'
    New-Item -ItemType Directory -Path $work | Out-Null
    Copy-Item -Path (Join-Path $repoRoot 'rulesets') -Destination $work -Recurse
    & git init -q --bare -b main $origin
    & git -C $work init -q -b main
    & git -C $work config core.autocrlf false
    & git -C $work -c user.name=test -c user.email=test@example.invalid add -A
    & git -C $work -c user.name=test -c user.email=test@example.invalid commit -q -m 'test'
    & git -C $work remote add origin $origin
    & git -C $work push -q origin main
    return [pscustomobject]@{ Base = $base; Work = $work; Script = (Join-Path $work 'rulesets/apply.ps1') }
}

function Set-Committed {
    # Rewrites one ruleset file in the test repository, commits it and pushes it.
    param($Repo, [string]$Name, [scriptblock]$Change)
    $p = Join-Path $Repo.Work "rulesets/$Name.json"
    $o = Get-Content -Raw $p | ConvertFrom-Json -Depth 50
    & $Change $o
    [System.IO.File]::WriteAllText($p, ($o | ConvertTo-Json -Depth 50))
    & git -C $Repo.Work -c user.name=test -c user.email=test@example.invalid commit -q -am 'change'
    & git -C $Repo.Work push -q origin main
}

function Invoke-Apply {
    # Runs the script and returns what happened: whether it threw, with what, and every gh call it made.
    param($Repo, [hashtable]$Params)
    $global:FakeGh.Calls = @()
    $global:FakeGh.Reads = 0
    $threw = $null
    $output = @()
    try { $output = @(& $Repo.Script -Org 'test-org-that-does-not-exist' @Params *>&1 | ForEach-Object { "$_" }) } catch { $threw = $_.Exception.Message }
    $script:last = [pscustomobject]@{ Threw = $threw; Output = $output; Calls = $global:FakeGh.Calls; Writes = @($global:FakeGh.Calls | Where-Object { $_.method -ne 'GET' }) }
    return $script:last
}

function Get-Flat {
    # One JSON value as a single line with its keys in order, so two spellings of the same content compare equal.
    param([string]$Json)
    function Sort-Value($v) {
        if ($v -is [System.Collections.IDictionary]) { $o = [ordered]@{}; foreach ($k in ($v.Keys | Sort-Object)) { $o[$k] = Sort-Value $v[$k] }; return $o }
        if ($v -is [System.Collections.IList]) { return , @($v | ForEach-Object { Sort-Value $_ }) }
        return $v
    }
    return (Sort-Value ($Json | ConvertFrom-Json -AsHashtable -Depth 50) | ConvertTo-Json -Depth 50 -Compress)
}

function Get-Shown {
    # The JSON body the script printed under "Would CREATE:", flattened the same way.
    param([string[]]$Output)
    $start = [array]::IndexOf($Output, '{')
    if ($start -lt 0) { $all = ($Output -join "`n"); $start = $all.IndexOf('{'); if ($start -lt 0) { return $null }; $end = $all.LastIndexOf('}'); return (Get-Flat $all.Substring($start, $end - $start + 1)) }
    $end = [array]::LastIndexOf($Output, '}')
    return (Get-Flat (($Output[$start..$end]) -join "`n"))
}

function Assert {
    param([bool]$Condition, [string]$What)
    if ($Condition) { Write-Host "ok   $What" }
    else { Write-Host "FAIL $What"; if ($script:last) { Write-Host "     threw: $($script:last.Threw)"; Write-Host "     calls: $(@($script:last.Calls | ForEach-Object { $_.method + ' ' + $_.args }) -join ' | ')" }; $script:failed++ }
}

$made = @()
try {
    # 1. A dry run never writes, whether or not a live ruleset of that name exists.
    $r = New-TestRepo; $made += $r
    $global:FakeGh.LiveList = ''
    $res = Invoke-Apply $r @{ Name = 'standard' }
    Assert ($null -eq $res.Threw -and $res.Writes.Count -eq 0) 'dry run with no live ruleset sends no write'
    $global:FakeGh.LiveList = "7`tbaseline"
    $global:FakeGh.LiveBody = Get-Content -Raw (Join-Path $r.Work 'rulesets/baseline.json')
    $res = Invoke-Apply $r @{ Name = 'baseline' }
    Assert ($null -eq $res.Threw -and $res.Writes.Count -eq 0) 'dry run with a live ruleset sends no write'

    # 2. -Execute sends the committed JSON (line endings normalised), once, as a POST when nothing of that name is live.
    $global:FakeGh.LiveList = ''
    $res = Invoke-Apply $r @{ Name = 'standard'; Execute = $true }
    $committed = (& git -C $r.Work show 'HEAD:rulesets/standard.json') -join "`n"
    Assert ($null -eq $res.Threw -and $res.Writes.Count -eq 1 -and $res.Writes[0].method -eq 'POST') '-Execute creates with one POST'
    Assert ($res.Writes.Count -eq 1 -and $res.Writes[0].sent -ceq $committed) 'the JSON text sent is the JSON text committed (line endings normalised)'
    $shown = Get-Shown $res.Output
    Assert ($shown -and $shown -ceq (Get-Flat $res.Writes[0].sent)) 'the JSON shown to the operator is semantically equal to the JSON sent'

    # 3. -Execute finds a live ruleset listed after others and updates it, instead of creating a duplicate.
    $global:FakeGh.LiveList = "5`tsomething-else`n9`tstandard"
    $global:FakeGh.LiveBody = '{"name": "standard", "enforcement": "disabled"}'
    $res = Invoke-Apply $r @{ Name = 'standard'; Execute = $true }
    Assert ($null -eq $res.Threw -and $res.Writes.Count -eq 1 -and $res.Writes[0].method -eq 'PUT' -and $res.Writes[0].args -match 'rulesets/9\b') '-Execute updates the live ruleset of that name with one PUT'

    # 4. -Execute sends the commit, not an edited working tree that git reports as clean.
    & git -C $r.Work update-index --skip-worktree rulesets/standard.json
    $p = Join-Path $r.Work 'rulesets/standard.json'
    [System.IO.File]::WriteAllText($p, ((Get-Content -Raw $p) -replace '"evaluate"', '"active"'))
    $global:FakeGh.LiveList = ''
    $res = Invoke-Apply $r @{ Name = 'standard'; Execute = $true }
    Assert ($res.Writes.Count -eq 1 -and $res.Writes[0].sent -ceq $committed -and $res.Writes[0].sent -notmatch '"active"') 'a hidden working-tree edit is not sent'

    # 4b. A live ruleset that changes between the diff and the write stops the update.
    & git -C $r.Work update-index --no-skip-worktree rulesets/standard.json
    & git -C $r.Work checkout -q -- rulesets/standard.json
    $global:FakeGh.LiveList = "9`tstandard"
    $global:FakeGh.LiveBody = '{"name": "standard", "enforcement": "disabled"}'
    $global:FakeGh.ChangeAfterReads = 1
    $res = Invoke-Apply $r @{ Name = 'standard'; Execute = $true }
    Assert ($res.Threw -match 'changed while this ran' -and $res.Writes.Count -eq 0) 'a live ruleset that changes before the write stops the update'
    $global:FakeGh.ChangeAfterReads = -1
    $global:FakeGh.LiveList = ''

    # 5. Refusals. None of these may send a write.
    $res = Invoke-Apply $r @{ Name = @('standard', 'production'); Execute = $true }
    Assert ($res.Threw -match 'exactly one' -and $res.Calls.Count -eq 0) '-Execute with two names is refused before any call'

    $res = Invoke-Apply $r @{ Name = 'agent-guard'; Execute = $true }
    Assert ($res.Threw -match 'placeholder' -and $res.Writes.Count -eq 0) '-Execute refuses the placeholder team id 0'

    $global:FakeGh.LiveList = "3`tstandard`n4`tstandard"
    $res = Invoke-Apply $r @{ Name = 'standard'; Execute = $true }
    Assert ($res.Threw -match 'resolve by hand' -and $res.Writes.Count -eq 0) 'two live rulesets of one name are refused'
    $global:FakeGh.LiveList = ''

    $r2 = New-TestRepo; $made += $r2
    Set-Content -Path (Join-Path $r2.Work 'untracked.txt') -Value 'x'
    $res = Invoke-Apply $r2 @{ Name = 'standard'; Execute = $true }
    Assert ($res.Threw -match 'not clean' -and $res.Calls.Count -eq 0) '-Execute on a dirty tree is refused before any call'

    $r3 = New-TestRepo; $made += $r3
    Set-Committed $r3 'agent-guard' { param($o) $o.bypass_actors | Where-Object { $_.actor_type -eq 'Team' } | ForEach-Object { $_.actor_id = 7 } }
    $res = Invoke-Apply $r3 @{ Name = 'agent-guard'; Execute = $true }
    Assert ($res.Threw -match 'not a usable guard' -and $res.Writes.Count -eq 0) 'a guard whose bypass team is not its reviewer team is refused'

    $r4 = New-TestRepo; $made += $r4
    Set-Committed $r4 'standard' { param($o) $o | Add-Member -NotePropertyName id -NotePropertyValue 99 }
    $res = Invoke-Apply $r4 @{ Name = 'standard'; Execute = $true }
    Assert ($res.Threw -match 'read-only key' -and $res.Writes.Count -eq 0) 'a file carrying a read-only key is refused'

    $r5 = New-TestRepo; $made += $r5
    Set-Committed $r5 'standard' { param($o) $o.bypass_actors[0].actor_id = $null }
    $res = Invoke-Apply $r5 @{ Name = 'standard'; Execute = $true }
    Assert ($res.Threw -match 'actor_id is not 1' -and $res.Writes.Count -eq 0) 'an OrganizationAdmin actor_id other than 1 is refused'
} finally {
    Remove-Item Function:\gh -ErrorAction SilentlyContinue
    Remove-Variable -Name FakeGh -Scope Global -ErrorAction SilentlyContinue
    foreach ($m in $made) { Remove-Item -Recurse -Force $m.Base -ErrorAction SilentlyContinue }
}

if ($failed) { Write-Host "$failed test(s) failed"; exit 1 }
Write-Host 'All apply tests passed.'
