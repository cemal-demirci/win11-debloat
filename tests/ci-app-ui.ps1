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
    throw "UI element '$Id' not found"
}

$proc = Start-Process -FilePath $Exe -PassThru
$win = $null
$deadline = (Get-Date).AddSeconds(60)
$byPid = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, $proc.Id)
while (-not $win -and (Get-Date) -lt $deadline) {
    $win = $AE::RootElement.FindFirst($TS::Children, $byPid)
    if (-not $win) { Start-Sleep -Seconds 1 }
}
if (-not $win) { throw 'main window did not appear' }
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
