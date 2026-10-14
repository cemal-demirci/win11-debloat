<#
    Cemal.cloud win11-debloat | CI test of the app's window (UI Automation)

    Starts Win11-Debloat.exe, checks that every control is there, unticks
    "Edge" and presses the Preview button like a user would, then checks that
    the dry run ran with -KeepEdge and that the buttons are enabled again.
#>
param([Parameter(Mandatory)][string]$Exe)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]

function Find-ById($Root, [string]$Id, [int]$TimeoutSec = 30) {
    $cond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, $Id)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $el = $Root.FindFirst($TS::Descendants, $cond)
        if ($el) { return $el }
        Start-Sleep -Milliseconds 500
    }
    $all = @($Root.FindAll($TS::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object {
        $n = ($_.Current.Name -replace '\s+', ' ')
        if ($n.Length -gt 40) { $n = $n.Substring(0, 40) + '...' }
        "$($_.Current.ControlType.ProgrammaticName -replace 'ControlType\.', '')('$n', id='$($_.Current.AutomationId)', class='$($_.Current.ClassName)')"
    }) -join '; '
    Write-Diag "UI element '$Id' not found. Window contains: $all"
    exit 1
}

function Write-Diag([string]$What) {
    $msg = "$What | session $((Get-Process -Id $PID).SessionId), interactive=$([Environment]::UserInteractive)"
    if ($script:proc) {
        $script:proc.Refresh()
        $msg += ", app exited=$($script:proc.HasExited), window handle=$($script:proc.MainWindowHandle), title='$($script:proc.MainWindowTitle)'"
    }
    $top = @($AE::RootElement.FindAll($TS::Children, [System.Windows.Automation.Condition]::TrueCondition) |
             ForEach-Object { "$($_.Current.Name) [pid $($_.Current.ProcessId)]" }) -join '; '
    $msg += ", top-level windows: $top"
    Write-Host $msg
    if ($env:GITHUB_ACTIONS) {
        # workflow commands are single-line: escape % CR LF
        Write-Host ("::error title=App UI::" + ($msg -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A'))
    }
}

trap { Write-Diag "unexpected error: $($_.Exception.Message)"; exit 1 }

$script:proc = Start-Process -FilePath $Exe -PassThru
$win = $null
$deadline = (Get-Date).AddSeconds(60)
while (-not $win -and (Get-Date) -lt $deadline) {
    $script:proc.Refresh()
    if ($script:proc.HasExited) { break }
    $h = $script:proc.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) {
        try { $win = $AE::FromHandle($h) } catch { $win = $null }
    }
    if (-not $win) { Start-Sleep -Seconds 1 }
}
if (-not $win) { Write-Diag 'main window not reachable'; exit 1 }
Write-Host "window: $($win.Current.Name)"

$failures = 0
function Check([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failures++; Write-Host "::error title=App UI::$Msg" }
}

foreach ($id in 'chkEdge', 'chkOneDrive', 'chkXbox', 'chkThirdParty', 'chkOutlook', 'chkUi',
                'btnPreview', 'btnApply', 'btnRestore', 'txtLog', 'lblStatus') {
    $el = Find-ById $win $id
    Check ($null -ne $el) "control $id exists"
}

$edge = Find-ById $win 'chkEdge'
$edge.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
$state = $edge.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
Check ($state -eq [System.Windows.Automation.ToggleState]::Off) 'Edge option can be unticked'

$preview = Find-ById $win 'btnPreview'
$preview.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()

$log = Find-ById $win 'txtLog'
$value = $log.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
$text = ''
$deadline = (Get-Date).AddSeconds(300)
while ((Get-Date) -lt $deadline) {
    $text = $value.Current.Value
    if ($text -match 'Summary' -and $preview.Current.IsEnabled) { break }
    Start-Sleep -Seconds 2
}
Write-Host '----- log shown in the window -----'
Write-Host $text
Write-Host '-----------------------------------'
Check ($text -match 'Win11-Debloat\.ps1 -DryRun -KeepEdge') 'preview ran the script with -DryRun -KeepEdge'
Check ($text -match 'DRY RUN') 'script reported dry run mode'
Check ($text -match 'Summary') 'script finished (summary shown)'
Check ($preview.Current.IsEnabled) 'buttons enabled again after the run'

$win.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
Check ($proc.WaitForExit(15000)) 'window closes'

if ($failures -gt 0) { exit 1 }
if ($env:GITHUB_ACTIONS) {
    Write-Host '::notice title=App UI::Window opened, all controls found, Edge unticked, Preview pressed, dry run ran with -KeepEdge, window closed.'
}
exit 0
