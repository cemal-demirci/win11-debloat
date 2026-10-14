<#
    Cemal.cloud win11-debloat | CI round-trip test (Windows PowerShell 5.1, admin)

    1. -DryRun must not change any registry value and must not write undo.json
    2. A real run must apply the expected values
    3. A second run must be safe (repeat runs after feature updates)
    4. Win11-Restore.ps1 must put every checked value back exactly as before,
       including removing keys the debloat script created

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

function Invoke-Script([string]$File, [string[]]$Arguments) {
    Write-Host ""
    Write-Host ">>> $File $($Arguments -join ' ')" -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root $File) @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$File exited with $code" }
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
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; [void]$failures.Add($Msg) }
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

# ---------------------------------------------------------------- 3. repeat run
Invoke-Script 'Win11-Debloat.ps1' @('-SkipRestorePoint', '-KeepEdge', '-Force')
foreach ($c in $checks) {
    $k = "$($c.Path)|$($c.Name)"
    Assert ((Get-Val $c.Path $c.Name) -eq $c.Want) "repeat run kept $k"
}

# ---------------------------------------------------------------- 4. restore
Invoke-Script 'Win11-Restore.ps1' @()
foreach ($c in $checks) {
    $k = "$($c.Path)|$($c.Name)"
    $now = Get-Val $c.Path $c.Name
    Assert ($now -eq $before[$k]) "restore put back $k = [$($before[$k])] (got [$now])"
}
$pending = @(Get-ChildItem $base -Recurse -Filter 'undo.json' -ErrorAction SilentlyContinue)
$done    = @(Get-ChildItem $base -Recurse -Filter 'undo.restored.json' -ErrorAction SilentlyContinue)
Assert ($pending.Count -eq 0) "no pending manifests after restore (found $($pending.Count))"
Assert ($done.Count -ge 1) "restored manifests renamed (found $($done.Count))"

# ---------------------------------------------------------------- result
Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red
    exit 1
}
Write-Host 'All round-trip checks passed' -ForegroundColor Green
exit 0
