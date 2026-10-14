#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cemal.cloud | Roll back changes made by Win11-Debloat.ps1.

.DESCRIPTION
    Reads the undo manifests (undo.json) written by Win11-Debloat.ps1 and:
      - restores every registry value to its previous state (or removes it,
        together with any key branch the debloat script created),
      - re-enables scheduled tasks and optional features,
      - reinstalls OneDrive and Edge with winget if they were removed,
      - lists removed Store apps so they can be reinstalled from the Store.

    By default every run that has not been restored yet is rolled back, newest
    first. Each processed manifest is renamed to undo.restored.json.

    For a full roll back you can also use the System Restore point the debloat
    script created ("Cemal.cloud Win11-Debloat <timestamp>").

.PARAMETER Manifest
    Restore only this undo.json instead of all pending runs.

.PARAMETER DryRun
    Show what would be restored without changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Restore.ps1

.NOTES
    Project : Cemal.cloud win11-debloat  (https://github.com/cemal-demirci/win11-debloat)
    License : MIT
    Run as the same user that ran the debloat script (HKCU values).
#>
[CmdletBinding()]
param(
    [string]$Manifest,
    [switch]$DryRun
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host ''; Write-Host ("==> {0}" -f $Text) -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host ("    + {0}" -f $Text) -ForegroundColor Green }
function Write-Dry([string]$Text)  { Write-Host ("    [dry] {0}" -f $Text) -ForegroundColor DarkYellow }
function Write-Warn2([string]$Text){ Write-Host ("    ! {0}" -f $Text) -ForegroundColor Yellow }

function Open-RegKey {
    # 'HKLM:\SOFTWARE\X' -> RegistryKey (same 64/32-bit view as the HKLM: drive)
    param([Parameter(Mandatory)][string]$PsPath, [bool]$Writable = $false)
    $parts = $PsPath -split ':\\', 2
    if ($parts.Count -ne 2) { throw "unexpected registry path: $PsPath" }
    switch ($parts[0]) {
        'HKCU'  { $root = [Microsoft.Win32.Registry]::CurrentUser }
        'HKLM'  { $root = [Microsoft.Win32.Registry]::LocalMachine }
        default { throw "unsupported registry hive in $PsPath" }
    }
    return $root.OpenSubKey($parts[1], $Writable)
}

function Test-KeyTreeEmpty([Microsoft.Win32.RegistryKey]$Key) {
    if ($Key.ValueCount -gt 0) { return $false }
    foreach ($n in $Key.GetSubKeyNames()) {
        $c = $Key.OpenSubKey($n)
        if ($null -eq $c) { return $false }
        try { if (-not (Test-KeyTreeEmpty $c)) { return $false } } finally { $c.Close() }
    }
    return $true
}

function Convert-RegValue($Value, [string]$Type) {
    switch ($Type) {
        'DWord'       { return [int]$Value }
        'QWord'       { return [long]$Value }
        'Binary'      { return ,([byte[]]@($Value)) }
        'MultiString' { return ,([string[]]@($Value)) }
        default       { return [string]$Value }
    }
}

function Get-Prop($Obj, [string]$Name) {
    # StrictMode-safe property read (older manifests may lack newer fields)
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $null }
}

Write-Host ''
Write-Host '  Cemal.cloud | Windows 11 Debloat: restore' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Collect manifests (newest first)
# ---------------------------------------------------------------------------
$base = Join-Path $env:ProgramData 'CemalCloud\Win11Debloat'
if ($Manifest) {
    if (-not (Test-Path -LiteralPath $Manifest)) { Write-Warn2 "Manifest not found: $Manifest"; exit 1 }
    $manifests = @((Resolve-Path -LiteralPath $Manifest).Path)
} else {
    $manifests = @(Get-ChildItem $base -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending |
                   ForEach-Object { Join-Path $_.FullName 'undo.json' } |
                   Where-Object { Test-Path -LiteralPath $_ })
}
if ($manifests.Count -eq 0) { Write-Warn2 "Nothing to restore (no pending undo.json under $base)"; exit 0 }

$entries = New-Object System.Collections.ArrayList
foreach ($m in $manifests) {
    Write-Host "  Manifest: $m"
    # PS 5.1 emits a JSON array as ONE pipeline object, so assign first, then wrap.
    $parsed = Get-Content -LiteralPath $m -Raw | ConvertFrom-Json
    $list   = @(@($parsed) | Where-Object { $null -ne $_ })
    [array]::Reverse($list)                       # undo in reverse order of changes
    foreach ($e in $list) {
        Add-Member -InputObject $e -NotePropertyName '__src' -NotePropertyValue $m -Force
        [void]$entries.Add($e)
    }
}

$restored = 0; $failed = 0
$failedSrc = @{}
$removedApps = New-Object System.Collections.ArrayList
$reinstall   = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------
# Pass 1: registry (policies must be gone before features are re-enabled)
# ---------------------------------------------------------------------------
Write-Step 'Registry'
foreach ($e in $entries) {
    if ($e.Kind -ne 'Reg') { continue }
    $label     = "{0}\{1}" -f $e.Path, $e.Name
    $valueName = if ($e.Name -eq '(Default)') { '' } else { [string]$e.Name }
    if ($DryRun) { Write-Dry "restore $label"; continue }
    try {
        if ($e.Existed) {
            if (-not (Test-Path -LiteralPath $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
            $k = Open-RegKey -PsPath $e.Path -Writable $true
            try {
                $k.SetValue($valueName, (Convert-RegValue $e.OldValue $e.OldType),
                            [Microsoft.Win32.RegistryValueKind]$e.OldType)
            } finally { $k.Close() }
        } else {
            $k = Open-RegKey -PsPath $e.Path -Writable $true
            if ($k) { try { $k.DeleteValue($valueName, $false) } finally { $k.Close() } }

            # Remove the key branch the debloat script created, if nothing else lives in it.
            $root = Get-Prop $e 'CreatedRoot'
            if (-not $root -and (Get-Prop $e 'KeyCreated')) { $root = $e.Path }   # older manifests
            if ($root -and (Test-Path -LiteralPath $root)) {
                $rk = Open-RegKey -PsPath $root
                $empty = $false
                if ($rk) { try { $empty = Test-KeyTreeEmpty $rk } finally { $rk.Close() } }
                if ($empty) { Remove-Item -LiteralPath $root -Recurse -Force }
            }
        }
        $restored++
    } catch {
        Write-Warn2 ("{0}: {1}" -f $label, $_.Exception.Message)
        $failed++; $failedSrc[$e.__src] = $true
    }
}
Write-Ok "$restored registry value(s) restored"

# ---------------------------------------------------------------------------
# Pass 2: tasks, features, removed components
# ---------------------------------------------------------------------------
Write-Step 'Scheduled tasks and features'
foreach ($e in $entries) {
    try {
        switch ($e.Kind) {
            'Task' {
                if ($DryRun) { Write-Dry ("enable task {0}{1}" -f $e.Path, $e.Name); continue }
                Enable-ScheduledTask -TaskPath $e.Path -TaskName $e.Name -ErrorAction Stop | Out-Null
                $restored++
            }
            'Feature' {
                if ($DryRun) { Write-Dry "enable feature $($e.Name)"; continue }
                Enable-WindowsOptionalFeature -Online -FeatureName $e.Name -NoRestart -ErrorAction Stop | Out-Null
                $restored++
            }
            'Appx'     { [void]$removedApps.Add($e.Name) }
            'OneDrive' { if (-not $reinstall.Contains('Microsoft.OneDrive')) { [void]$reinstall.Add('Microsoft.OneDrive') } }
            'Edge'     { if (-not $reinstall.Contains('Microsoft.Edge'))     { [void]$reinstall.Add('Microsoft.Edge') } }
        }
    } catch {
        Write-Warn2 ("{0} {1}: {2}" -f $e.Kind, (Get-Prop $e 'Name'), $_.Exception.Message)
        $failed++; $failedSrc[$e.__src] = $true
    }
}

if ($reinstall.Count -gt 0) {
    Write-Step 'Reinstalling removed components'
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    foreach ($id in $reinstall) {
        if ($DryRun) { Write-Dry "winget install $id"; continue }
        if (-not $winget) { Write-Warn2 "winget not available, install $id manually"; continue }
        & winget.exe install --id $id -e --silent --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) { Write-Ok "$id installed" } else { Write-Warn2 "$id install exit code $LASTEXITCODE" }
    }
}

if ($removedApps.Count -gt 0) {
    Write-Step 'Removed Store apps (reinstall from Microsoft Store if needed)'
    $removedApps | Sort-Object -Unique | ForEach-Object { Write-Host "    - $_" }
}

if (-not $DryRun) {
    # Mark fully restored runs as done; keep the ones with failures for a re-run.
    foreach ($m in $manifests) {
        if ($failedSrc.ContainsKey($m)) {
            Write-Warn2 "kept for re-run (had failures): $m"
        } else {
            Rename-Item -LiteralPath $m -NewName 'undo.restored.json' -Force -ErrorAction SilentlyContinue
        }
    }
    # Only if Explorer runs in this session (not over SSH / remoting / CI), and never fatal.
    try {
        $sid = (Get-Process -Id $PID).SessionId
        $shell = @(Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid })
        if ($shell.Count -gt 0) {
            $shell | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid })) {
                Start-Process explorer.exe
            }
        }
    } catch {
        Write-Warn2 "Could not restart Explorer: $($_.Exception.Message). Sign out and back in instead."
    }
    Write-Host ''
    Write-Host ("  Restore finished: {0} restored, {1} failed. Restart Windows to apply everything." -f $restored, $failed) -ForegroundColor Green
}
