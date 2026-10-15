<#
    Cemal.cloud win11-debloat | CI round-trip test (Windows PowerShell 5.1, admin)

    1. -DryRun must not change any registry value and must not write undo.json
    2. A real run must apply the expected values
    3. Guard: -Check finds nothing right after a run; after simulated drift
       (what a feature update does) it reports exactly that, -Reapply fixes it,
       the scheduled task installs, runs and fixes drift on its own
    4. A second run must be safe (repeat runs after feature updates)
    5. Win11-Restore.ps1 must put every checked value back exactly as before,
       including removing keys the debloat script created, and remove the guard

    Runs on a disposable CI VM. Do not run this on your own machine.
#>
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$base = Join-Path $env:ProgramData 'CemalCloud\Win11Debloat'

function Get-Val([string]$Path, [string]$Name) {
    if (-not (Test-Path -LiteralPath $Path)) { return '<nokey>' }
    $k = Get-Item -LiteralPath $Path
    $vn = if ($Name -eq '(Default)') { '' } else { $Name }
    if ($k.GetValueNames() -contains $vn) {
        return [string]$k.GetValue($vn, $null, 'DoNotExpandEnvironmentNames')
    }
    return '<novalue>'
}

function Invoke-Script([string]$File, [string[]]$Arguments, [int]$Expect = 0) {
    Write-Host ""
    Write-Host ">>> $File $($Arguments -join ' ')" -ForegroundColor Cyan
    # stdout only: with ErrorActionPreference Stop, 2>&1 would turn native stderr into errors
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $File) @Arguments | Out-String
    $code = $LASTEXITCODE
    Write-Host $out
    $script:LastOut = $out
    if ($code -ne $Expect) { throw "$File exited with $code (expected $Expect)" }
}

$checks = @(
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Name = 'AllowTelemetry'; Want = '0' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'; Name = 'TurnOffWindowsCopilot'; Want = '1' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Name = 'DisableAIDataAnalysis'; Want = '1' },
    @{ Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'; Name = 'StartupBoostEnabled'; Want = '0' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Name = 'HideFileExt'; Want = '0' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; Name = 'SilentInstalledAppsEnabled'; Want = '0' },
    @{ Path = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'; Name = '(Default)'; Want = '' }
)
if (Get-Service -Name DiagTrack -ErrorAction SilentlyContinue) {
    $checks += @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Services\DiagTrack'; Name = 'Start'; Want = '4' }
}

$before = @{}
foreach ($c in $checks) { $before["$($c.Path)|$($c.Name)"] = Get-Val $c.Path $c.Name }
Write-Host "Windows build $([Environment]::OSVersion.Version.Build), $($checks.Count) registry checks"
$before.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("  before  {0} = [{1}]" -f $_.Name, $_.Value) }

$failures = New-Object System.Collections.ArrayList
$script:Passed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green; $script:Passed++ }
    else {
        Write-Host "  FAIL  $Msg" -ForegroundColor Red; [void]$failures.Add($Msg)
        if ($env:GITHUB_ACTIONS) { Write-Host "::error title=Round trip::$Msg" }
    }
}

# ---------------------------------------------------------------- 1. dry run
Invoke-Script 'Win11-Debloat.ps1' @('-DryRun', '-Force')
foreach ($c in $checks) {
    $k = "$($c.Path)|$($c.Name)"
    Assert ((Get-Val $c.Path $c.Name) -eq $before[$k]) "dry run left $k unchanged"
}
$manifests = @(Get-ChildItem $base -Recurse -Filter 'undo.json' -ErrorAction SilentlyContinue)
Assert ($manifests.Count -eq 0) 'dry run wrote no undo.json'

# ---------------------------------------------------------------- 2. real run
# -SkipRestorePoint: System Restore does not exist on Windows Server runners.
# -KeepEdge: keep the CI image's browser; Edge policies are still applied.
Invoke-Script 'Win11-Debloat.ps1' @('-SkipRestorePoint', '-KeepEdge', '-Force')
foreach ($c in $checks) {
    $k = "$($c.Path)|$($c.Name)"
    $now = Get-Val $c.Path $c.Name
    Assert ($now -eq $c.Want) "debloat set $k = [$($c.Want)] (got [$now])"
}
$manifests = @(Get-ChildItem $base -Recurse -Filter 'undo.json')
Assert ($manifests.Count -eq 1) "first run wrote one undo.json (found $($manifests.Count))"
$firstRun = 'unknown'
if ($manifests.Count -ge 1) {
    $parsed  = Get-Content -LiteralPath $manifests[0].FullName -Raw | ConvertFrom-Json
    $entries = @(@($parsed) | Where-Object { $null -ne $_ })
    $count   = { param($k) @($entries | Where-Object { $_.Kind -eq $k }).Count }
    $firstRun = "{0} registry values, {1} scheduled tasks, {2} apps, {3} features" -f `
        (& $count 'Reg'), (& $count 'Task'), (& $count 'Appx'), (& $count 'Feature')
    Write-Host "first run changed: $firstRun"
}

# ---------------------------------------------------------------- 3. guard
$state = Join-Path $base 'state.json'
$guardTask = 'Cemal.cloud Win11 Debloat Guard'
$guardDir  = Join-Path $env:ProgramFiles 'CemalCloud\Win11Debloat'
$telemetry = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
$copilot   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
Assert (Test-Path -LiteralPath $state) 'first run saved state.json'
$acl = Get-Acl -LiteralPath $base
$writeBits = [int][System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, Delete, ChangePermissions, TakeOwnership'
$usersWrite = @($acl.Access | Where-Object {
    $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -match '^S-1-5-32-545$|^S-1-5-11$|^S-1-1-0$|^S-1-3-0$' -and
    ([int]$_.FileSystemRights -band $writeBits) })
Assert ($acl.AreAccessRulesProtected -and $usersWrite.Count -eq 0) 'backup folder: only admins can write (users, creator owner: read only)'

Invoke-Script 'Win11-Debloat.ps1' @('-Check') 0
Assert ("$script:LastOut" -match 'all in place') 'check right after the run: all in place'

# Simulate what a feature update does: policy reset, policy deleted, task enabled again.
# Restore undoes what the tool did. A value that was already right before the first
# run and was then changed by "Windows" ends up as Windows left it, not as before.
$simulated = @{ "$telemetry|AllowTelemetry" = '3' }
Set-ItemProperty -LiteralPath $telemetry -Name 'AllowTelemetry' -Value 3 -Type DWord
Remove-ItemProperty -LiteralPath $copilot -Name 'TurnOffWindowsCopilot'
$expectDrift = 2
$st = Get-Content -LiteralPath $state -Raw | ConvertFrom-Json
$task = @($st.Tasks) | Where-Object { $_ } | Select-Object -First 1
if ($task) {
    Enable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name | Out-Null
    $expectDrift = 3
}
Invoke-Script 'Win11-Debloat.ps1' @('-Check') 10
$drift = Get-Content -LiteralPath (Join-Path $base 'drift.json') -Raw | ConvertFrom-Json
Assert ($drift.Count -eq $expectDrift) "check found exactly the $expectDrift simulated changes (found $($drift.Count))"
Assert ("$script:LastOut" -match 'AllowTelemetry: expected 0, found 3') 'check names the reset telemetry policy'
Assert ("$script:LastOut" -match 'TurnOffWindowsCopilot: expected 1, found <missing>') 'check names the deleted Copilot policy'
if ($task) { Assert ("$script:LastOut" -match 'task enabled again') 'check names the re-enabled task' }

Invoke-Script 'Win11-Debloat.ps1' @('-Reapply') 0
Assert ((Get-Val $telemetry 'AllowTelemetry') -eq '0') 'reapply set AllowTelemetry back to 0'
Assert ((Get-Val $copilot 'TurnOffWindowsCopilot') -eq '1') 'reapply set TurnOffWindowsCopilot back to 1'
if ($task) { Assert ((Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name).State -eq 'Disabled') 'reapply disabled the task again' }
Assert ("$script:LastOut" -notmatch 'restore point created') 'reapply made no new restore point'
Invoke-Script 'Win11-Debloat.ps1' @('-Check') 0
Assert ("$script:LastOut" -match 'all in place') 'check after reapply: all in place'
Invoke-Script 'Win11-Debloat.ps1' @('-Reapply') 0
Assert ("$script:LastOut" -match 'all in place') 'reapply without drift changes nothing'

Invoke-Script 'Win11-Debloat.ps1' @('-InstallGuard') 0
$gt = Get-ScheduledTask -TaskPath '\' -TaskName $guardTask -ErrorAction SilentlyContinue
Assert ($null -ne $gt) 'guard task registered'
if ($gt) {
    Assert ($gt.Principal.RunLevel -eq 'Highest') 'guard runs with highest privileges'
    Assert (@($gt.Triggers | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' }).Count -eq 1) 'guard triggers at sign-in'
    Assert ($gt.Actions[0].Arguments -match [regex]::Escape($guardDir) -and $gt.Actions[0].Arguments -match '-Reapply') 'guard runs -Reapply from Program Files'
}
$copy = Join-Path $guardDir 'Win11-Debloat.ps1'
Assert ((Test-Path $copy) -and (Get-FileHash $copy).Hash -eq (Get-FileHash (Join-Path $root 'Win11-Debloat.ps1')).Hash) 'guard copy is identical to the repository script'

# Drift again, then let the scheduled task itself fix it.
Set-ItemProperty -LiteralPath $telemetry -Name 'AllowTelemetry' -Value 3 -Type DWord
$logFile = Join-Path $base 'guard.log'
$logBefore = if (Test-Path $logFile) { @(Get-Content $logFile).Count } else { 0 }
$guardRan = $false
try { Start-ScheduledTask -TaskPath '\' -TaskName $guardTask } catch { Write-Host "Start-ScheduledTask: $($_.Exception.Message)" }
for ($i = 0; $i -lt 60 -and -not $guardRan; $i++) {
    Start-Sleep -Seconds 3
    $lines = if (Test-Path $logFile) { @(Get-Content $logFile) } else { @() }
    if ($lines.Count -gt $logBefore -and $lines[-1] -match 'reapplied') { $guardRan = $true }
}
$info = Get-ScheduledTaskInfo -TaskPath '\' -TaskName $guardTask -ErrorAction SilentlyContinue
Write-Host ("guard task: ran={0}, last result={1}" -f $guardRan, $(if ($info) { $info.LastTaskResult } else { '?' }))
if ($guardRan) {
    Assert ((Get-Val $telemetry 'AllowTelemetry') -eq '0') 'the guard task fixed the drift by itself'
    $script:GuardNote = 'the scheduled task itself fixed a simulated drift'
} else {
    # Interactive-logon tasks may not start on a CI session; run its exact command line instead.
    Write-Host "::warning title=Guard::scheduled task did not start on this CI session (last result $(if ($info) { $info.LastTaskResult }))"
    & $gt.Actions[0].Execute -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $copy -Reapply | Out-Host
    Assert ((Get-Val $telemetry 'AllowTelemetry') -eq '0') "the guard's command line fixed the drift"
    $script:GuardNote = "the guard's command line fixed a simulated drift (task start not available on CI)"
}
Assert ((@(Get-Content $logFile)[-1]) -match 'drift 1 -> reapplied') 'guard.log records the fix'

# ---------------------------------------------------------------- 4. repeat run
Invoke-Script 'Win11-Debloat.ps1' @('-SkipRestorePoint', '-KeepEdge', '-Force')
foreach ($c in $checks) {
    $k = "$($c.Path)|$($c.Name)"
    Assert ((Get-Val $c.Path $c.Name) -eq $c.Want) "repeat run kept $k"
}

# ---------------------------------------------------------------- 5. restore
Invoke-Script 'Win11-Restore.ps1' @()
foreach ($c in $checks) {
    $k = "$($c.Path)|$($c.Name)"
    $now = Get-Val $c.Path $c.Name
    $want = $before[$k]
    if ($simulated.ContainsKey($k) -and $before[$k] -eq $c.Want) { $want = $simulated[$k] }
    Assert ($now -eq $want) "restore put back $k = [$want] (got [$now])"
}
$pending = @(Get-ChildItem $base -Recurse -Filter 'undo.json' -ErrorAction SilentlyContinue)
$done    = @(Get-ChildItem $base -Recurse -Filter 'undo.restored.json' -ErrorAction SilentlyContinue)
Assert ($pending.Count -eq 0) "no pending manifests after restore (found $($pending.Count))"
Assert ($done.Count -ge 1) "restored manifests renamed (found $($done.Count))"
Assert ($null -eq (Get-ScheduledTask -TaskPath '\' -TaskName $guardTask -ErrorAction SilentlyContinue)) 'restore removed the guard task'
Assert (-not (Test-Path -LiteralPath $guardDir)) 'restore removed the guard copy in Program Files'
Assert (-not (Test-Path -LiteralPath $state)) 'restore removed state.json'
Invoke-Script 'Win11-Debloat.ps1' @('-Check') 2
Assert $true 'check after restore: nothing applied (exit 2)'

# ---------------------------------------------------------------- result
Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) check(s) failed, $($script:Passed) passed" -ForegroundColor Red
    exit 1
}
Write-Host 'All round-trip checks passed' -ForegroundColor Green
if ($env:GITHUB_ACTIONS) {
    Write-Host ("::notice title=Windows round trip::{0} checks passed on Windows build {1}. First run changed {2}. Check found every simulated drift, -Reapply fixed it, {3}. Dry run changed nothing, restore put every checked value back and removed the guard." -f `
        $script:Passed, [Environment]::OSVersion.Version.Build, $firstRun, $script:GuardNote)
}
exit 0
