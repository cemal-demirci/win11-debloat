<#
    Cemal.cloud win11-debloat | CI test of the app's window

    Starts Win11-Debloat.exe, checks that every control is there, unticks
    "Edge" and presses the Preview button like a user would, then checks that
    the dry run ran with -KeepEdge, the log shows the result and the buttons
    are enabled again.

    Second window: after an apply and a simulated Windows update (a policy
    reset), the window must notice the drift on its own when it opens.

    UI Automation is used to find the controls by their visible names; clicks
    and text reads go through the standard Win32 messages (BM_CLICK,
    BM_GETCHECK, WM_GETTEXT), which behave exactly like a mouse click.
#>
param([Parameter(Mandatory)][string]$Exe, [string]$ShotDir)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -Namespace CemalCloud -Name Win32 -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, System.Text.StringBuilder lParam);
[DllImport("user32.dll")]
public static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
[DllImport("user32.dll")]
public static extern bool IsWindowEnabled(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")]
public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
[DllImport("user32.dll")]
public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
[DllImport("dwmapi.dll")]
public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attr, out RECT r, int size);
[StructLayout(LayoutKind.Sequential)]
public struct RECT { public int Left, Top, Right, Bottom; }
'@
Add-Type -AssemblyName System.Drawing

# Screenshot of a window as it is drawn (title bar included), for the README and design review.
function Save-Shot([IntPtr]$Hwnd, [string]$Name) {
    if (-not $ShotDir) { return }
    New-Item -ItemType Directory -Path $ShotDir -Force | Out-Null
    Start-Sleep -Milliseconds 700
    $r = New-Object CemalCloud.Win32+RECT
    [void][CemalCloud.Win32]::GetWindowRect($Hwnd, [ref]$r)
    $bmp = New-Object System.Drawing.Bitmap ($r.Right - $r.Left), ($r.Bottom - $r.Top)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][CemalCloud.Win32]::PrintWindow($Hwnd, $hdc, 2)      # PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc); $g.Dispose()
    $e = New-Object CemalCloud.Win32+RECT
    if ([CemalCloud.Win32]::DwmGetWindowAttribute($Hwnd, 9, [ref]$e, 16) -eq 0) {   # visible frame, without the invisible resize border
        $crop = New-Object System.Drawing.Rectangle ($e.Left - $r.Left), ($e.Top - $r.Top), ($e.Right - $e.Left), ($e.Bottom - $e.Top)
        $c = $bmp.Clone($crop, $bmp.PixelFormat); $bmp.Dispose(); $bmp = $c
    }
    $path = Join-Path $ShotDir "$Name.png"
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "screenshot: $path"
}
$AE = [System.Windows.Automation.AutomationElement]
$TS = [System.Windows.Automation.TreeScope]
$W  = [CemalCloud.Win32]
$BM_CLICK = 0x00F5; $BM_GETCHECK = 0x00F0; $WM_GETTEXT = 0x000D; $WM_GETTEXTLENGTH = 0x000E; $WM_CLOSE = 0x0010

function Write-Diag([string]$What) {
    $msg = "$What | session $((Get-Process -Id $PID).SessionId), interactive=$([Environment]::UserInteractive)"
    if ($script:proc) {
        $script:proc.Refresh()
        $msg += ", app exited=$($script:proc.HasExited), window='$($script:proc.MainWindowTitle)'"
    }
    $crash = Join-Path $env:TEMP 'CemalCloud\Win11Debloat\crash.log'
    if (Test-Path $crash) { $msg += " | crash.log: " + ((Get-Content $crash -TotalCount 12) -join ' / ') }
    Write-Host $msg
    if ($env:GITHUB_ACTIONS) {
        # workflow commands are single-line: escape % CR LF
        Write-Host ("::error title=App UI::" + ($msg -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A'))
    }
}

function Get-Descendants($Root) {
    @($Root.FindAll($TS::Descendants, [System.Windows.Automation.Condition]::TrueCondition))
}

# Window handle of the first control whose visible name / class matches.
function Find-Control($Root, [string]$NameLike, [string]$ClassLike = '*', [int]$TimeoutSec = 30) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        foreach ($el in Get-Descendants $Root) {
            if ($el.Current.Name -like $NameLike -and $el.Current.ClassName -like $ClassLike) {
                return [IntPtr]$el.Current.NativeWindowHandle
            }
        }
        Start-Sleep -Milliseconds 500
    }
    $all = @(Get-Descendants $Root | ForEach-Object { "'$($_.Current.Name -replace '\s+', ' ')'" }) -join ', '
    Write-Diag "control '$NameLike' not found. Window contains: $all"
    exit 1
}

function Get-WindowText([IntPtr]$Hwnd) {
    $len = $W::SendMessage($Hwnd, $WM_GETTEXTLENGTH, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32()
    $sb = New-Object System.Text.StringBuilder ($len + 1)
    [void]$W::SendMessage($Hwnd, $WM_GETTEXT, [IntPtr]($len + 1), $sb)
    $sb.ToString()
}

$failures = 0
function Check([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "  PASS  $Msg" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Msg" -ForegroundColor Red; $script:failures++; Write-Host "::error title=App UI::$Msg" }
}

trap { Write-Diag "unexpected error: $($_.Exception.Message)"; exit 1 }

function Open-App {
    $script:proc = Start-Process -FilePath $Exe -PassThru
    $w = $null
    $deadline = (Get-Date).AddSeconds(60)
    while (-not $w -and (Get-Date) -lt $deadline) {
        $script:proc.Refresh()
        if ($script:proc.HasExited) { break }
        $h = $script:proc.MainWindowHandle
        if ($h -ne [IntPtr]::Zero) {
            try { $w = $AE::FromHandle($h) } catch { $w = $null }
        }
        if (-not $w) { Start-Sleep -Seconds 1 }
    }
    if (-not $w) { Write-Diag 'main window not reachable'; exit 1 }
    return $w
}

# ---------------------------------------------------------------- start
$win = Open-App
$main = $script:proc.MainWindowHandle
[void]$W::SetForegroundWindow($main)
Write-Host "window: $($win.Current.Name)"
Check ($win.Current.Name -like 'Windows 11 Debloat*Cemal.cloud') 'window title'
Save-Shot $main 'start'

# ---------------------------------------------------------------- controls
# (ASCII-only patterns: this file is read by Windows PowerShell 5.1 without a BOM)
$chkEdge     = Find-Control $win 'Edge*'         '*BUTTON*'
$chkOneDrive = Find-Control $win 'OneDrive*'     '*BUTTON*'
$chkXbox     = Find-Control $win 'Xbox*'         '*BUTTON*'
$chkOutlook  = Find-Control $win 'Yeni Outlook*' '*BUTTON*'
$chkThird    = Find-Control $win '*parti*'       '*BUTTON*'
$chkUi       = Find-Control $win 'Aray*'         '*BUTTON*'
$chkPerf     = Find-Control $win 'Performans*'   '*BUTTON*'
$chkGaming   = Find-Control $win 'Oyuncu*'       '*BUTTON*'
$btnPreview  = Find-Control $win '*nizle'        '*BUTTON*'
$btnApply    = Find-Control $win 'Uygula'        '*BUTTON*'
$btnRestore  = Find-Control $win 'Geri al'       '*BUTTON*'
$btnCheck    = Find-Control $win 'Kontrol et'    '*BUTTON*'
$chkGuard    = Find-Control $win 'N*bet*'        '*BUTTON*'
$txtLog      = Find-Control $win '*'             '*EDIT*'
Check $true 'all 13 buttons / options and the log are present'
Check ($W::SendMessage($chkGaming, $BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -eq 0) 'gaming option is off by default'
Check ($W::SendMessage($chkGuard, $BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -eq 0) 'guard option is off while no guard is installed'

foreach ($c in $chkEdge, $chkOneDrive, $chkXbox, $chkOutlook, $chkThird, $chkUi, $chkPerf) {
    Check ($W::SendMessage($c, $BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -eq 1) "option $c is ticked by default"
}
foreach ($b in $btnPreview, $btnApply, $btnCheck, $btnRestore) {
    Check ($W::IsWindowEnabled($b)) "button $b is enabled"
}

# ---------------------------------------------------------------- untick Edge, press Preview
[void]$W::SendMessage($chkEdge, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Milliseconds 300
Check ($W::SendMessage($chkEdge, $BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -eq 0) 'Edge option unticked by a click'

[void]$W::SendMessage($btnPreview, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
Start-Sleep -Milliseconds 500
Check (-not $W::IsWindowEnabled($btnApply)) 'buttons are disabled while the script runs'

$text = ''
$deadline = (Get-Date).AddSeconds(300)
while ((Get-Date) -lt $deadline) {
    $text = Get-WindowText $txtLog
    if ($text -match 'Summary' -and $W::IsWindowEnabled($btnPreview)) { break }
    Start-Sleep -Seconds 2
}
Save-Shot $main 'preview'
Write-Host '----- log shown in the window -----'
Write-Host $text
Write-Host '-----------------------------------'
Check ($text -match 'Win11-Debloat\.ps1 -DryRun -KeepEdge') 'Preview ran the script with -DryRun -KeepEdge'
Check ($text -match 'DRY RUN') 'script reported dry run mode'
Check ($text -match 'Summary') 'script finished and the summary is shown'
Check ($W::IsWindowEnabled($btnPreview) -and $W::IsWindowEnabled($btnApply)) 'buttons enabled again after the run'
Check ($W::SendMessage($chkEdge, $BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero).ToInt32() -eq 0) 'Edge option still unticked'

# ---------------------------------------------------------------- close
[void]$W::PostMessage($main, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
Check ($script:proc.WaitForExit(15000)) 'window closes'

# ---------------------------------------------------------------- drift seen on start
$work = Join-Path $env:RUNNER_TEMP 'app-ui'
New-Item -ItemType Directory -Path $work -Force | Out-Null
$p = Start-Process -FilePath $Exe -ArgumentList '--run', (Join-Path $work 'apply.log'), 'apply', '-SkipRestorePoint', '-KeepEdge', '-Force' -Wait -PassThru
Check ($p.ExitCode -eq 0) 'apply through the app (headless) before the second window'
Set-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 3 -Type DWord

$win = Open-App
$main = $script:proc.MainWindowHandle
$lblStatus = Find-Control $win 'Durum'
$btnPreview = Find-Control $win '*nizle' '*BUTTON*'
$status = ''
$deadline = (Get-Date).AddSeconds(180)
while ((Get-Date) -lt $deadline) {
    $status = Get-WindowText $lblStatus
    if ($status -match 'geri alm' -and $W::IsWindowEnabled($btnPreview)) { break }
    Start-Sleep -Seconds 2
}
$log2 = Get-WindowText (Find-Control $win '*' '*EDIT*')
Write-Host "status: $status"
Write-Host $log2
Check ($status -match '[0-9]+ de.*geri alm') "the window found the drift by itself on start (status: $status)"
Check ($log2 -match 'AllowTelemetry: expected 0, found 3') 'the log names the changed policy'
Save-Shot $main 'drift'
[void]$W::PostMessage($main, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
Check ($script:proc.WaitForExit(15000)) 'second window closes'
$p = Start-Process -FilePath $Exe -ArgumentList '--run', (Join-Path $work 'restore.log'), 'restore' -Wait -PassThru
Check ($p.ExitCode -eq 0) 'restore through the app'

if ($failures -gt 0) { exit 1 }
if ($env:GITHUB_ACTIONS) {
    Write-Host '::notice title=App UI::Window opened with all options ticked, Edge unticked by a click, Preview pressed, the dry run ran with -KeepEdge, the log showed the summary, buttons came back, window closed. After an apply and a simulated policy reset, a new window reported the drift by itself on start.'
}
exit 0
