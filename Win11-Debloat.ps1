#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cemal.cloud | Windows 11 aggressive debloat.

.DESCRIPTION
    Removes Copilot, Recall, Xbox, Widgets, consumer/promoted apps, OneDrive and
    (where Microsoft allows it) Edge. Turns off telemetry, ads, suggestions and
    Bing in Start. Every registry change is recorded in an undo manifest so
    Win11-Restore.ps1 can roll it back.

    Kept on purpose (work machine safe):
      Microsoft Store, winget, Terminal, Photos, Calculator, Notepad, Paint,
      Snipping Tool, Camera, Media Player, Teams (work), Outlook, WebView2,
      Windows Search service (Outlook needs it), Print Spooler, WSL, Hyper-V.

    Before touching anything the script:
      1. creates a System Restore point,
      2. exports the affected registry hives (.reg),
      3. saves the installed app list,
      4. writes an undo manifest (undo.json).

    Backups and the log go to %ProgramData%\CemalCloud\Win11Debloat\<timestamp>\

.PARAMETER DryRun
    Show what would change. Nothing is modified.

.PARAMETER KeepEdge
    Do not try to uninstall Edge (Edge policies are still applied).

.PARAMETER KeepOneDrive
    Do not uninstall OneDrive.

.PARAMETER KeepXbox
    Keep Xbox apps, services and Game Bar.

.PARAMETER KeepOutlookNew
    Keep the "new Outlook" app (Microsoft.OutlookForWindows). Removed by default
    because the classic Outlook from Microsoft 365 is not affected.

.PARAMETER KeepThirdParty
    Keep third-party store apps (Spotify, Netflix, Disney+, Prime Video,
    LinkedIn, Messenger/Facebook, Instagram, TikTok, X, Plex, McAfee, games).
    Without this switch they are removed for ALL users, including their
    offline data, even if someone installed them on purpose.

.PARAMETER SkipUiTweaks
    Skip quality-of-life tweaks (file extensions, classic context menu, etc.).

.PARAMETER SkipRestorePoint
    Continue even if a restore point cannot be created.

.PARAMETER Force
    Skip safety checks (non-Windows 11 build, OneDrive signed in or folder
    backup active, no alternative browser before removing Edge). Use with care.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -KeepEdge -KeepXbox

.NOTES
    Project : Cemal.cloud win11-debloat  (https://github.com/cemal-demirci/win11-debloat)
    Tested  : Windows 11 23H2 / 24H2 / 25H2, Windows PowerShell 5.1
    License : MIT
    HKCU changes apply to the account that runs the script. Run it from the
    user account you want to clean (that account must be an administrator).
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$KeepEdge,
    [switch]$KeepOneDrive,
    [switch]$KeepXbox,
    [switch]$KeepOutlookNew,
    [switch]$KeepThirdParty,
    [switch]$SkipUiTweaks,
    [switch]$SkipRestorePoint,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$ScriptVersion = '1.0.0'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BaseDir   = Join-Path $env:ProgramData 'CemalCloud\Win11Debloat'
$BackupDir = Join-Path $BaseDir $Stamp
$UndoFile  = Join-Path $BackupDir 'undo.json'

$script:Undo  = New-Object System.Collections.ArrayList
$script:Stats = [ordered]@{ Apps = 0; Registry = 0; Tasks = 0; Features = 0; Skipped = 0; Failed = 0 }
$script:Aborted = $false

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Write-Banner {
    $c = 'Cyan'
    Write-Host ''
    Write-Host '    ____                     _       _                 _ ' -ForegroundColor $c
    Write-Host '   / ___|___ _ __ ___   __ _| |  ___| | ___  _   _  __| |' -ForegroundColor $c
    Write-Host '  | |   / _ \ ''_ ` _ \ / _` | | / __| |/ _ \| | | |/ _` |' -ForegroundColor $c
    Write-Host '  | |__|  __/ | | | | | (_| | || (__| | (_) | |_| | (_| |' -ForegroundColor $c
    Write-Host '   \____\___|_| |_| |_|\__,_|_(_)___|_|\___/ \__,_|\__,_|' -ForegroundColor $c
    Write-Host ''
    Write-Host ("  Windows 11 Debloat v{0}  |  https://cemal.cloud" -f $ScriptVersion) -ForegroundColor White
    if ($DryRun) { Write-Host '  DRY RUN: nothing will be changed' -ForegroundColor Yellow }
    Write-Host ''
}

function Write-Step([string]$Text) { Write-Host ''; Write-Host ("==> {0}" -f $Text) -ForegroundColor Cyan }
function Write-Info([string]$Text) { Write-Host ("    {0}" -f $Text) }
function Write-Ok([string]$Text)   { Write-Host ("    + {0}" -f $Text) -ForegroundColor Green }
function Write-Dry([string]$Text)  { Write-Host ("    [dry] {0}" -f $Text) -ForegroundColor DarkYellow }
function Write-Warn2([string]$Text){ Write-Host ("    ! {0}" -f $Text) -ForegroundColor Yellow }

function Add-Undo([hashtable]$Entry) { [void]$script:Undo.Add($Entry) }

function Invoke-Native {
    # Windows PowerShell 5.1 turns native stderr into terminating errors when
    # $ErrorActionPreference is 'Stop'. Run tools like reg.exe safely.
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @())
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments 2>&1 | Out-Null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Save-Undo {
    # An empty manifest from a repeat run must not hide an older, real one.
    if ($DryRun -or $script:Undo.Count -eq 0) { return }
    try {
        $json = ConvertTo-Json -InputObject @($script:Undo.ToArray()) -Depth 6
        Set-Content -LiteralPath $UndoFile -Value $json -Encoding UTF8
    } catch {
        Write-Warn2 "Could not write undo manifest: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Change helpers (all of them record undo information)
# ---------------------------------------------------------------------------
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

function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type = 'DWord'
    )
    $lookup     = if ($Name -eq '(Default)') { '' } else { $Name }
    $keyExisted = Test-Path -LiteralPath $Path
    $existed = $false; $old = $null; $oldType = $null

    if ($keyExisted) {
        $key = Get-Item -LiteralPath $Path
        if ($key.GetValueNames() -contains $lookup) {
            $existed = $true
            $old     = $key.GetValue($lookup, $null, 'DoNotExpandEnvironmentNames')
            $oldType = $key.GetValueKind($lookup).ToString()
        }
    }
    if ($existed -and $oldType -eq $Type -and ("$old" -eq "$Value")) { return }

    if ($DryRun) { Write-Dry ("reg {0}\{1} = {2}" -f $Path, $Name, $Value); return }
    $createdRoot = $null
    try {
        # Remember the top-most key we create, so restore can remove the whole
        # new branch (New-Item -Force also creates missing parents).
        if (-not $keyExisted) {
            $probe = $Path
            while ($true) {
                $parent = Split-Path -Path $probe -Parent
                if (-not $parent -or (Test-Path -LiteralPath $parent)) { break }
                $probe = $parent
            }
            $createdRoot = $probe
            New-Item -Path $Path -Force | Out-Null
        }
        # Write through .NET so '(Default)' is handled the same way as in restore.
        $wk = Open-RegKey -PsPath $Path -Writable $true
        if ($null -eq $wk) { throw "cannot open $Path for writing" }
        try { $wk.SetValue($lookup, $Value, [Microsoft.Win32.RegistryValueKind]$Type) } finally { $wk.Close() }
        Add-Undo @{ Kind = 'Reg'; Path = $Path; Name = $Name; Existed = $existed
                    OldValue = $old; OldType = $oldType; CreatedRoot = $createdRoot }
        $script:Stats.Registry++
    } catch {
        # The branch did not exist before this call, so removing it is safe.
        if ($createdRoot) { Remove-Item -LiteralPath $createdRoot -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Warn2 ("failed {0}\{1}: {2}" -f $Path, $Name, $_.Exception.Message)
        $script:Stats.Failed++
    }
}

function Disable-Svc {
    # Changes the Start value through Set-Reg so the restore script can put it back.
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    Set-Reg -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$Name" -Name 'Start' -Value 4
    if (-not $DryRun -and $svc.Status -eq 'Running') {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    }
}

function Disable-Task {
    param([Parameter(Mandatory)][string]$TaskPath, [Parameter(Mandatory)][string]$TaskName)
    $t = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t -or $t.State -eq 'Disabled') { return }
    if ($DryRun) { Write-Dry ("task {0}{1} -> disabled" -f $TaskPath, $TaskName); return }
    try {
        Disable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
        Add-Undo @{ Kind = 'Task'; Path = $TaskPath; Name = $TaskName }
        $script:Stats.Tasks++
    } catch {
        Write-Warn2 ("task {0}{1}: {2}" -f $TaskPath, $TaskName, $_.Exception.Message)
        $script:Stats.Failed++
    }
}

$script:AllPkgs  = $null
$script:AllProv  = $null
$script:Seen     = @{}     # package names already handled (patterns can overlap)

function Remove-App {
    # Removes an Appx package for all users and de-provisions it for new users.
    # Package lists are queried once (DISM is slow) and filtered per pattern.
    param([Parameter(Mandatory)][string]$Pattern)
    if ($null -eq $script:AllPkgs) {
        $script:AllPkgs = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
        try { $script:AllProv = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop) } catch { $script:AllProv = @() }
    }
    $pkgs = @($script:AllPkgs | Where-Object { $_.Name -like $Pattern })
    $prov = @($script:AllProv | Where-Object { $_.DisplayName -like $Pattern })
    if ($pkgs.Count -eq 0 -and $prov.Count -eq 0) { return }

    foreach ($p in $pkgs) {
        if ($script:Seen.ContainsKey($p.PackageFullName)) { continue }
        $script:Seen[$p.PackageFullName] = $true
        if ($p.PSObject.Properties['NonRemovable'] -and $p.NonRemovable) {
            Write-Info ("skip (system, non-removable): {0}" -f $p.Name); $script:Stats.Skipped++; continue
        }
        if ($DryRun) { Write-Dry ("remove app {0}" -f $p.Name); continue }
        try {
            Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
            Write-Ok ("removed {0}" -f $p.Name)
            Add-Undo @{ Kind = 'Appx'; Name = $p.Name }
            $script:Stats.Apps++
        } catch {
            Write-Warn2 ("could not remove {0}: {1}" -f $p.Name, $_.Exception.Message)
            $script:Stats.Failed++
        }
    }
    foreach ($p in $prov) {
        if ($script:Seen.ContainsKey($p.PackageName)) { continue }
        $script:Seen[$p.PackageName] = $true
        if ($DryRun) { Write-Dry ("de-provision {0}" -f $p.DisplayName); continue }
        try {
            Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -AllUsers -ErrorAction Stop | Out-Null
        } catch {
            try { Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null }
            catch { Write-Warn2 ("could not de-provision {0}" -f $p.DisplayName) }
        }
    }
}

function Get-AlternativeBrowser {
    $found = @()
    foreach ($root in 'HKLM:\SOFTWARE\Clients\StartMenuInternet', 'HKCU:\SOFTWARE\Clients\StartMenuInternet',
                      'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet') {
        if (Test-Path $root) {
            $found += Get-ChildItem $root -ErrorAction SilentlyContinue |
                      Where-Object { $_.PSChildName -notmatch 'Edge|IEXPLORE' } |
                      ForEach-Object { $_.PSChildName }
        }
    }
    return @($found | Select-Object -Unique)
}

# ===========================================================================
# 0. Pre-flight
# ===========================================================================
Write-Banner

$build = [Environment]::OSVersion.Version.Build
if ($build -lt 22000 -and -not $Force) {
    Write-Warn2 "This script targets Windows 11 (build 22000+). Detected build $build. Use -Force to override."
    exit 1
}

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
try { Start-Transcript -Path (Join-Path $BackupDir 'debloat.log') -Force | Out-Null } catch { }

try {
    # =======================================================================
    # 1. Safety net
    # =======================================================================
    Write-Step 'Safety net: restore point and backups'
    if ($DryRun) {
        Write-Dry 'create restore point, export registry, save app list'
    } else {
        # Windows allows one restore point per 24h by default. Lift that limit
        # only for this checkpoint and put the original setting straight back.
        $srKey  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
        $srName = 'SystemRestorePointCreationFrequency'
        $srHad  = $false; $srOld = $null
        try {
            $k = Get-Item -LiteralPath $srKey -ErrorAction Stop
            if ($k.GetValueNames() -contains $srName) { $srHad = $true; $srOld = $k.GetValue($srName) }
        } catch { }
        try {
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
            New-ItemProperty -LiteralPath $srKey -Name $srName -Value 0 -PropertyType DWord -Force | Out-Null
            # -WarningAction Stop: a silently skipped checkpoint must count as a failure
            Checkpoint-Computer -Description "Cemal.cloud Win11-Debloat $Stamp" -RestorePointType 'MODIFY_SETTINGS' `
                -ErrorAction Stop -WarningAction Stop
            Write-Ok 'restore point created'
        } catch {
            if ($SkipRestorePoint) {
                Write-Warn2 "restore point failed ($($_.Exception.Message)), continuing because of -SkipRestorePoint"
            } else {
                Write-Warn2 "restore point failed: $($_.Exception.Message)"
                Write-Warn2 'Aborting. Fix System Protection or re-run with -SkipRestorePoint.'
                throw 'RestorePointFailed'
            }
        } finally {
            try {
                if ($srHad) { New-ItemProperty -LiteralPath $srKey -Name $srName -Value $srOld -PropertyType DWord -Force | Out-Null }
                else { Remove-ItemProperty -LiteralPath $srKey -Name $srName -ErrorAction SilentlyContinue }
            } catch { }
        }

        $exports = [ordered]@{
            'HKLM-Policies'      = 'HKLM\SOFTWARE\Policies'
            'HKCU-Policies'      = 'HKCU\Software\Policies'
            'HKCU-CDM'           = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            'HKCU-Explorer'      = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer'
            'HKCU-Search'        = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'
        }
        foreach ($k in $exports.Keys) {
            [void](Invoke-Native 'reg.exe' @('export', $exports[$k], (Join-Path $BackupDir "$k.reg"), '/y'))
        }
        Get-AppxPackage -AllUsers | Select-Object Name, Version, PackageFullName |
            Sort-Object Name | Export-Csv (Join-Path $BackupDir 'apps-before.csv') -NoTypeInformation
        Write-Ok "backups in $BackupDir"
    }

    # =======================================================================
    # 2. Apps
    # =======================================================================
    Write-Step 'Removing preinstalled and promoted apps'
    $apps = @(
        # AI / Copilot
        'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider', 'MicrosoftWindows.Client.CoPilot*',
        'Microsoft.MicrosoftOfficeHub',           # "Microsoft 365 Copilot" hub app, not Office itself
        # Microsoft consumer apps
        'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.BingFinance',
        'Microsoft.BingSports', 'Microsoft.BingTranslator',
        # Microsoft.GetHelp is kept: Settings troubleshooters run through it on 23H2+
        'Microsoft.Getstarted', 'Microsoft.WindowsFeedbackHub',
        'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People', 'Microsoft.Todos',
        'Microsoft.PowerAutomateDesktop', 'Microsoft.WindowsMaps', 'Microsoft.ZuneVideo',
        'Microsoft.WindowsAlarms', 'Microsoft.WindowsSoundRecorder', 'Microsoft.MicrosoftJournal',
        'Microsoft.MixedReality.Portal', 'Microsoft.Microsoft3DViewer', 'Microsoft.MSPaint',
        'Microsoft.SkypeApp', 'Microsoft.Office.OneNote', 'Microsoft.Wallet', 'Microsoft.Messaging',
        'Microsoft.OneConnect', 'Microsoft.Print3D', 'Microsoft.windowscommunicationsapps',
        'Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice', 'Microsoft.Windows.DevHome',
        'Microsoft.549981C3F5F10',                # Cortana
        'MicrosoftTeams',                         # consumer "Teams (free)"; work Teams is MSTeams and is kept
        'MicrosoftCorporationII.MicrosoftFamily', 'Clipchamp.Clipchamp', 'Microsoft.Edge.GameAssist',
        # Widgets
        'MicrosoftWindows.Client.WebExperience'
    )
    if (-not $KeepThirdParty) {
        # OEM / promoted third-party apps. Removed for all users WITH their data.
        $apps += '*CandyCrush*', 'king.com.*', '*Disney*', 'SpotifyAB.SpotifyMusic', '*Facebook*', '*Instagram*',
                 'BytedancePte.Ltd.TikTok', 'AmazonVideo.PrimeVideo', '*Netflix*', '7EE7776C.LinkedInforWindows',
                 '*Twitter*', '*McAfee*', '*Duolingo*', '*PicsArt*', '*RoyalRevolt*', '*Asphalt*',
                 '*HiddenCity*', '*.Plex', '*BubbleWitch*', '*MarchofEmpires*'
    } else {
        Write-Info 'third-party apps kept (-KeepThirdParty)'
    }
    if (-not $KeepXbox) {
        $apps += 'Microsoft.GamingApp', 'Microsoft.XboxApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGameOverlay',
                 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay'
    }
    if (-not $KeepOutlookNew) { $apps += 'Microsoft.OutlookForWindows' }

    foreach ($a in $apps) { Remove-App -Pattern $a }

    # =======================================================================
    # 3. Copilot, Recall and other AI features
    # =======================================================================
    Write-Step 'Turning off Copilot, Recall and AI features'
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1   # Recall snapshots
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1
    # Paint / Notepad generative features (ignored on builds that do not have them)
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableCocreator' 1
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableGenerativeFill' 1
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint' 'DisableImageCreator' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1

    $recall = $null
    try { $recall = Get-WindowsOptionalFeature -Online -FeatureName 'Recall' -ErrorAction Stop } catch { }
    if ($recall -and $recall.State -eq 'Enabled') {
        if ($DryRun) { Write-Dry 'disable optional feature Recall' }
        else {
            try {
                Disable-WindowsOptionalFeature -Online -FeatureName 'Recall' -NoRestart -ErrorAction Stop | Out-Null
                Add-Undo @{ Kind = 'Feature'; Name = 'Recall' }
                $script:Stats.Features++
                Write-Ok 'Recall feature disabled'
            } catch { Write-Warn2 "Recall: $($_.Exception.Message)" }
        }
    }

    # =======================================================================
    # 4. Telemetry and privacy
    # =======================================================================
    Write-Step 'Reducing telemetry and tracking'
    # 0 = Security level; honoured on Enterprise/Education, Pro treats it as Required (1)
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowDeviceNameInTelemetry' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'LimitDiagnosticLogCollection' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DisableOneSettingsDownloads' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0

    # dmwappushservice is deliberately kept: Intune/MDM sync stops without it.
    foreach ($s in 'DiagTrack', 'MapsBroker', 'RetailDemo', 'WMPNetworkSvc') { Disable-Svc $s }

    $tasks = @(
        @('\Microsoft\Windows\Application Experience\', 'Microsoft Compatibility Appraiser'),
        @('\Microsoft\Windows\Application Experience\', 'Microsoft Compatibility Appraiser Exp'),
        @('\Microsoft\Windows\Application Experience\', 'ProgramDataUpdater'),
        @('\Microsoft\Windows\Application Experience\', 'StartupAppTask'),
        @('\Microsoft\Windows\Application Experience\', 'MareBackup'),
        @('\Microsoft\Windows\Customer Experience Improvement Program\', 'Consolidator'),
        @('\Microsoft\Windows\Customer Experience Improvement Program\', 'UsbCeip'),
        @('\Microsoft\Windows\Autochk\', 'Proxy'),
        @('\Microsoft\Windows\DiskDiagnostic\', 'Microsoft-Windows-DiskDiagnosticDataCollector'),
        @('\Microsoft\Windows\Feedback\Siuf\', 'DmClient'),
        @('\Microsoft\Windows\Feedback\Siuf\', 'DmClientOnScenarioDownload'),
        @('\Microsoft\Windows\Windows Error Reporting\', 'QueueReporting'),
        @('\Microsoft\Windows\Maps\', 'MapsUpdateTask'),
        @('\Microsoft\Windows\Maps\', 'MapsToastTask')
    )
    foreach ($t in $tasks) { Disable-Task -TaskPath $t[0] -TaskName $t[1] }

    # =======================================================================
    # 5. Ads, suggestions, Bing in Start, Widgets
    # =======================================================================
    Write-Step 'Removing ads, suggestions and web search in Start'
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($v in 'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OemPreInstalledAppsEnabled',
                   'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled',
                   'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled', 'RotatingLockScreenOverlayEnabled',
                   'SubscribedContentEnabled', 'SubscribedContent-310093Enabled', 'SubscribedContent-314563Enabled',
                   'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                   'SubscribedContent-353698Enabled') {
        Set-Reg $cdm $v 0
    }
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 1
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableSpotlightCollectionOnDesktop' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'Start_IrisRecommendations' 0
    Set-Reg $adv 'Start_AccountNotifications' 0
    Set-Reg $adv 'ShowSyncProviderNotifications' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested' 'Enabled' 0
    # Start menu search: local only
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'EnableDynamicContentInWSB' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
    # Widgets / News
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0

    # =======================================================================
    # 6. Xbox / Game DVR
    # =======================================================================
    if (-not $KeepXbox) {
        Write-Step 'Disabling Xbox services and Game DVR'
        foreach ($s in 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc') { Disable-Svc $s }
        Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    }

    # =======================================================================
    # 7. Edge: tame it first, then try to remove it
    # =======================================================================
    Write-Step 'Microsoft Edge'
    $edgePol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    foreach ($pair in @(
        @('StartupBoostEnabled', 0), @('BackgroundModeEnabled', 0), @('HubsSidebarEnabled', 0),
        @('CopilotCDPPageContext', 0), @('EdgeShoppingAssistantEnabled', 0), @('PersonalizationReportingEnabled', 0),
        @('ShowRecommendationsEnabled', 0), @('SpotlightExperiencesAndRecommendationsEnabled', 0),
        @('NewTabPageContentEnabled', 0), @('NewTabPageHideDefaultTopSites', 1), @('HideFirstRunExperience', 1),
        @('DiagnosticData', 0), @('EdgeFollowEnabled', 0), @('ShowMicrosoftRewards', 0))) {
        Set-Reg $edgePol $pair[0] $pair[1]
    }

    if (-not $KeepEdge) {
        $alt = @(Get-AlternativeBrowser)
        if ($alt.Count -eq 0 -and -not $Force) {
            Write-Warn2 'No other browser found. Install Firefox/Chrome/Brave first, then re-run. Edge kept (policies applied).'
            $script:Stats.Skipped++
        } else {
            if ($alt.Count -gt 0) { Write-Info ("other browser(s): {0}" -f ($alt -join ', ')) }
            $setup = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue |
                     Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $setup) {
                Write-Info 'Edge not installed'
            } elseif ($DryRun) {
                Write-Dry "uninstall Edge via $($setup.FullName)"
            } else {
                Set-Reg 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev' 'AllowUninstall' 1
                # The Edge uninstaller refuses to run while this legacy stub is missing on some builds.
                $stub = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe"
                $stubDir = Split-Path $stub
                $stubDirCreated = -not (Test-Path $stubDir)
                $stubCreated = $false
                if (-not (Test-Path $stub)) {
                    try { New-Item -ItemType File -Path $stub -Force | Out-Null; $stubCreated = $true } catch { }
                }
                Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                $p = Start-Process -FilePath $setup.FullName -PassThru -Wait -WindowStyle Hidden `
                        -ArgumentList '--uninstall', '--system-level', '--verbose-logging', '--force-uninstall'
                if ($stubCreated) { Remove-Item $stub -Force -ErrorAction SilentlyContinue }
                if ($stubCreated -and $stubDirCreated) { Remove-Item $stubDir -Force -ErrorAction SilentlyContinue }

                if (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") {
                    Write-Warn2 "Edge uninstaller declined (exit $($p.ExitCode)). Microsoft only permits this in some regions."
                    Write-Warn2 'Edge stays installed but is silenced by the policies above.'
                } else {
                    Write-Ok 'Edge removed (WebView2 runtime kept)'
                    Add-Undo @{ Kind = 'Edge' }
                    # Stop Edge Update from installing it again. WebView2 is a different app id and keeps updating.
                    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' 0
                    Set-Reg 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' 'DoNotUpdateToEdgeWithChromium' 1
                    foreach ($lnk in "$env:PUBLIC\Desktop\Microsoft Edge.lnk", "$env:USERPROFILE\Desktop\Microsoft Edge.lnk") {
                        Remove-Item $lnk -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    # =======================================================================
    # 8. OneDrive
    # =======================================================================
    if (-not $KeepOneDrive) {
        Write-Step 'OneDrive'
        $usf = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction SilentlyContinue
        $redirected = @()
        if ($usf) {
            foreach ($prop in $usf.PSObject.Properties) {
                if ($prop.Name -notlike 'PS*' -and "$($prop.Value)" -match 'OneDrive') { $redirected += $prop.Name }
            }
        }
        # A signed-in account can have online-only (Files On-Demand) files and
        # pending uploads even without folder backup.
        $odAccounts = @(Get-ChildItem 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue |
                        Where-Object { $_.GetValue('UserFolder') } |
                        ForEach-Object { $_.GetValue('UserFolder') })
        if (($redirected.Count -gt 0 -or $odAccounts.Count -gt 0) -and -not $Force) {
            if ($redirected.Count -gt 0) { Write-Warn2 ("Folders are backed up to OneDrive: {0}" -f ($redirected -join ', ')) }
            if ($odAccounts.Count -gt 0) { Write-Warn2 ("OneDrive is signed in: {0}" -f ($odAccounts -join ', ')) }
            Write-Warn2 'Removing OneDrive now could leave online-only files or pending uploads out of reach.'
            Write-Warn2 'Stop folder backup, let sync finish, sign out of OneDrive, then re-run (or use -KeepOneDrive).'
            Write-Warn2 'OneDrive kept.'
            $script:Stats.Skipped++
        } else {
            $setups = @()
            foreach ($c in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
                if (Test-Path $c) { $setups += @{ Path = $c; Args = '/uninstall' } }
            }
            foreach ($c in @(Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue)) {
                $setups += @{ Path = $c.FullName; Args = '/uninstall' }
            }
            foreach ($c in @(Get-ChildItem "$env:ProgramFiles\Microsoft OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue)) {
                $setups += @{ Path = $c.FullName; Args = '/uninstall /allusers' }
            }

            if ($setups.Count -eq 0) {
                Write-Info 'OneDrive not installed'
            } elseif ($DryRun) {
                Write-Dry 'uninstall OneDrive'
            } else {
                Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                foreach ($s in $setups) {
                    try { Start-Process -FilePath $s.Path -ArgumentList $s.Args -Wait -WindowStyle Hidden } catch { }
                }
                Add-Undo @{ Kind = 'OneDrive' }
                Write-Ok 'OneDrive uninstalled'
                Write-Info "Your local OneDrive folder ($env:USERPROFILE\OneDrive) was NOT deleted."
            }
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
            Set-Reg 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
            Set-Reg 'HKCU:\Software\Classes\WOW6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0

            # Stop OneDrive from being installed for new user profiles.
            if (-not $DryRun) {
                $hive = "$env:SystemDrive\Users\Default\NTUSER.DAT"
                if (Test-Path $hive) {
                    if ((Invoke-Native 'reg.exe' @('load', 'HKU\CC_Default', $hive)) -eq 0) {
                        [void](Invoke-Native 'reg.exe' @('delete', 'HKU\CC_Default\Software\Microsoft\Windows\CurrentVersion\Run', '/v', 'OneDriveSetup', '/f'))
                        $unloaded = $false
                        for ($i = 0; $i -lt 5 -and -not $unloaded; $i++) {
                            [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Milliseconds 500
                            $unloaded = ((Invoke-Native 'reg.exe' @('unload', 'HKU\CC_Default')) -eq 0)
                        }
                        if (-not $unloaded) {
                            Write-Warn2 'Default user hive is still loaded (HKU\CC_Default). Reboot before creating new user accounts.'
                        }
                    }
                }
            }
        }
    }

    # =======================================================================
    # 9. Quality-of-life tweaks
    # =======================================================================
    if (-not $SkipUiTweaks) {
        Write-Step 'Quality-of-life tweaks'
        Set-Reg $adv 'HideFileExt' 0                       # show file extensions
        Set-Reg $adv 'Hidden' 1                            # show hidden files
        Set-Reg $adv 'LaunchTo' 1                          # Explorer opens "This PC"
        Set-Reg $adv 'TaskbarMn' 0                         # legacy Chat icon
        Set-Reg $adv 'ShowTaskViewButton' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1   # search icon only
        # Classic right-click menu (no "Show more options")
        Set-Reg 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(Default)' '' 'String'
        # Widgets button: protected by UCPD on recent builds, the Dsh policy above already hides it
        Set-Reg $adv 'TaskbarDa' 0
    }
}
catch {
    $script:Aborted = $true
    if ("$_" -ne 'RestorePointFailed') {
        Write-Warn2 "Unexpected error: $($_.Exception.Message)"
        $script:Stats.Failed++
    }
}
finally {
    Save-Undo
}

# ===========================================================================
# Summary
# ===========================================================================
Write-Step 'Summary'
foreach ($k in $script:Stats.Keys) { Write-Info ("{0,-10} {1}" -f $k, $script:Stats[$k]) }
if (-not $DryRun) {
    Write-Info "Backups + undo manifest : $BackupDir"
    Write-Info 'Roll back with          : .\Win11-Restore.ps1'
}
if ($script:Aborted) {
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
if (-not $DryRun) {
    # Restart Explorer in this session only (other signed-in users are left alone).
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
    Write-Host '  Done. Restart Windows to apply everything.' -ForegroundColor Green
}
try { Stop-Transcript | Out-Null } catch { }
