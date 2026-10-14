<#
    Cemal.cloud win11-debloat | CI test of the app without its window

    1. the embedded scripts are byte-identical to the repository files
    2. the app runs as a 64-bit process with 64-bit Windows PowerShell
    3. preview, apply and restore work through the app's own process plumbing

    Runs on a disposable CI VM. Do not run this on your own machine.
#>
param([Parameter(Mandatory)][string]$Exe)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script:AppExe = (Resolve-Path -LiteralPath $Exe).Path
$work = Join-Path $env:RUNNER_TEMP 'app-test'
New-Item -ItemType Directory -Path $work -Force | Out-Null

$failures = 0
function Check([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failures++; Write-Host "::error title=App::$Msg" }
}

function Invoke-App([string[]]$Arguments) {
    $p = Start-Process -FilePath $script:AppExe -ArgumentList $Arguments -Wait -PassThru
    return $p.ExitCode
}

# 1. embedded scripts
$extract = Join-Path $work 'extracted'
$code = Invoke-App @('--extract', $extract)
Check ($code -eq 0) '--extract exits 0'
foreach ($name in 'Win11-Debloat.ps1', 'Win11-Restore.ps1') {
    $a = (Get-FileHash (Join-Path $root $name)).Hash
    $b = (Get-FileHash (Join-Path $extract $name)).Hash
    Check ($a -eq $b) "embedded $name is identical to the repository file"
}

# 2 + 3. headless runs
function Test-Run([string]$Label, [string[]]$Arguments, [string[]]$MustContain) {
    $log = Join-Path $work "$Label.log"
    $code = Invoke-App (@('--run', $log) + $Arguments)
    $text = if (Test-Path $log) { Get-Content $log -Raw } else { '' }
    Write-Host "::group::$Label log"; Write-Host $text; Write-Host '::endgroup::'
    Check ($code -eq 0) "$Label exits 0 (got $code)"
    foreach ($m in $MustContain) { Check ($text -match [regex]::Escape($m)) "$Label output contains '$m'" }
}

Test-Run 'preview' @('preview') @('64-bit process', 'System32\WindowsPowerShell', 'DRY RUN', 'Summary')
# -SkipRestorePoint: System Restore does not exist on Windows Server runners.
Test-Run 'apply'   @('apply', '-SkipRestorePoint', '-KeepEdge', '-Force') @('Summary', 'Backups + undo manifest')
Test-Run 'restore' @('restore') @('Restore finished')

$bad = Invoke-App @('--run', (Join-Path $work 'bad.log'), 'apply', '-Unknown')
Check ($bad -ne 0) 'unknown switches are rejected'

if ($failures -gt 0) { exit 1 }
if ($env:GITHUB_ACTIONS) {
    Write-Host '::notice title=App::Embedded scripts identical to the repository; 64-bit PowerShell; preview, apply and restore all exit 0 through the app; unknown switches rejected.'
}
exit 0
