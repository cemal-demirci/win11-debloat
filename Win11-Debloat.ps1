#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cemal.cloud | Windows 11 aggressive debloat.

.DESCRIPTION
    Removes Copilot, Recall, Xbox, Widgets, consumer/promoted apps, OneDrive and
    (where Microsoft allows it) Edge. Turns off telemetry, ads, suggestions and
    Bing in Start. Applies performance settings (visual effects, transparency,
    background apps, scheduler, NTFS, service grouping, power plan on desktops).
    Every registry change is recorded in an undo manifest so Win11-Restore.ps1
    can roll it back.

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

.PARAMETER SkipPerformance
    Skip the performance settings: transparency and animations off (ClearType
    and thumbnails stay), background Store apps off, no startup delay, MMCSS and
    foreground priority, NTFS last-access updates off, service host grouping
    (not with -KeepXbox), no P2P update uploads, larger icon cache, and on
    desktops (no battery) a high performance power plan without power
    throttling. Security features (Defender, updates, CPU mitigations) are
    never touched.

.PARAMETER GamingTweaks
    Optional (off by default): mouse acceleration off ("Enhance pointer
    precision", 1:1 movement), timer resolution requests apply system-wide
    again (behaviour before Windows 10 2004; nothing is forced), the Sticky /
    Filter / Toggle Keys shortcut prompts off (the features themselves keep
    their state), Game Mode on.

.PARAMETER SkipRestorePoint
    Continue even if a restore point cannot be created.

.PARAMETER Force
    Skip safety checks (non-Windows 11 build, OneDrive signed in or folder
    backup active, no alternative browser before removing Edge). Use with care.

.PARAMETER Check
    Compare the PC with what the last run applied (state.json) and list what
    Windows changed back: registry values, scheduled tasks enabled again,
    removed apps that came back, Edge / OneDrive reinstalled. Changes nothing.
    Exit code 0 = everything in place, 10 = drift found, 2 = nothing applied yet.

.PARAMETER Reapply
    Run -Check, and if anything drifted, apply again with the options of the
    last run (no new restore point; every change is recorded for restore).

.PARAMETER InstallGuard
    Install the guard: a scheduled task that runs -Reapply two minutes after
    you sign in, so a feature update cannot quietly turn things back on.
    The script is copied to %ProgramFiles%\CemalCloud\Win11Debloat (admin-only
    folder). Every guard run is logged to guard.log in the backup folder.

.PARAMETER RemoveGuard
    Remove the guard task and its copy of the script. Win11-Restore.ps1 also
    removes it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -KeepEdge -KeepXbox

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Win11-Debloat.ps1 -Check

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
    [switch]$SkipPerformance,
    [switch]$GamingTweaks,
    [switch]$SkipRestorePoint,
    [switch]$Force,
    [switch]$Check,
    [switch]$Reapply,
    [switch]$InstallGuard,
    [switch]$RemoveGuard
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$ScriptVersion = '1.4.0'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BaseDir   = Join-Path $env:ProgramData 'CemalCloud\Win11Debloat'
$BackupDir = Join-Path $BaseDir $Stamp
$UndoFile  = Join-Path $BackupDir 'undo.json'
$StateFile = Join-Path $BaseDir 'state.json'      # what the last run applied (for -Check)
$DriftFile = Join-Path $BaseDir 'drift.json'
$GuardLog  = Join-Path $BaseDir 'guard.log'
$GuardTask = 'Cemal.cloud Win11 Debloat Guard'
$GuardDir  = Join-Path $env:ProgramFiles 'CemalCloud\Win11Debloat'
$PerfScheme = 'c3c10ad0-0000-4c00-8000-0000000c10ad'   # our power plan (copy of Ultimate / High performance)

$script:Undo  = New-Object System.Collections.ArrayList
$script:Stats = [ordered]@{ Apps = 0; Registry = 0; Tasks = 0; Features = 0; Skipped = 0; Failed = 0 }
$script:Aborted = $false
# Desired state collected during a run: every value / task this run put in place
# (changed now or already right), so -Check can tell later what Windows turned back.
$script:Desired = @{
    Reg = New-Object System.Collections.ArrayList; Tasks = New-Object System.Collections.ArrayList
    Apps = @(); Stuck = New-Object System.Collections.ArrayList
    Edge = $false; OneDrive = $false; Recall = $false; Power = $null
}
$script:Baseline = $null     # footprint before the first run (processes, services, memory)
$script:DriftExit = 0; $script:DriftCount = 0

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ''
    Write-Host ("  Cemal.cloud | Windows 11 Debloat v{0}" -f $ScriptVersion) -ForegroundColor Cyan
    if ($Check)      { Write-Host '  CHECK: comparing with the last run, nothing will be changed' -ForegroundColor Yellow }
    elseif ($DryRun) { Write-Host '  DRY RUN: nothing will be changed' -ForegroundColor Yellow }
    if ($Reapply)    { Write-Host '  REAPPLY: only if Windows turned something back' -ForegroundColor Yellow }
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
    if ($existed -and $oldType -eq $Type -and ("$old" -eq "$Value")) {
        [void]$script:Desired.Reg.Add([ordered]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
        return
    }

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
                    OldValue = $old; OldType = $oldType; CreatedRoot = $createdRoot; Value = $Value; Type = $Type }
        [void]$script:Desired.Reg.Add([ordered]@{ Path = $Path; Name = $Name; Value = $Value; Type = $Type })
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
    if (-not $t) { return }
    if ($t.State -eq 'Disabled') {
        [void]$script:Desired.Tasks.Add([ordered]@{ Path = $TaskPath; Name = $TaskName }); return
    }
    if ($DryRun) { Write-Dry ("task {0}{1} -> disabled" -f $TaskPath, $TaskName); return }
    try {
        Disable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
        Add-Undo @{ Kind = 'Task'; Path = $TaskPath; Name = $TaskName }
        [void]$script:Desired.Tasks.Add([ordered]@{ Path = $TaskPath; Name = $TaskName })
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
            [void]$script:Desired.Stuck.Add($p.Name)    # -Check must not report it forever
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

# ---------------------------------------------------------------------------
# Desired state, drift check and guard
# ---------------------------------------------------------------------------
function Protect-Dir([string]$Path) {
    # %ProgramData% lets every user create files in subfolders. Undo manifests
    # and state.json are read by elevated code (restore, guard), so only
    # Administrators and SYSTEM may write here; users can still read.
    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $inh = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $none = [System.Security.AccessControl.PropagationFlags]::None
        foreach ($rule in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
            $id = New-Object System.Security.Principal.SecurityIdentifier($rule[0])
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($id, $rule[1], $inh, $none, 'Allow')))
        }
        # .NET writes only the parts that were set (here: the DACL). Set-Acl would
        # also write an empty owner / DACL from a second object and undo this.
        [System.IO.Directory]::SetAccessControl($Path, $acl)
    } catch {
        Write-Warn2 "could not restrict permissions on ${Path}: $($_.Exception.Message)"
        return
    }
    try {
        # A folder someone else created first must not stay theirs.
        $o = New-Object System.Security.AccessControl.DirectorySecurity
        $o.SetOwner((New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        [System.IO.Directory]::SetAccessControl($Path, $o)
    } catch { }
}

function Test-TrustedFile([string]$Path) {
    # Only trust files owned by Administrators, SYSTEM, TrustedInstaller or the
    # account running this script (an elevated admin wrote them).
    try {
        $owner = (Get-Acl -LiteralPath $Path).GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    } catch { return $false }
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return @('S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464', $me) -contains $owner
}

function Get-Prop($Obj, [string]$Name) {
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($p) { return $p.Value } else { return $null }
}

function Read-State {
    if (-not (Test-Path -LiteralPath $StateFile)) { return $null }
    if (-not (Test-TrustedFile $StateFile)) {
        Write-Warn2 "ignoring $StateFile : it is not owned by an administrator"
        return $null
    }
    try { return (Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json) } catch { return $null }
}

function Save-State {
    if ($DryRun -or $script:Aborted) { return }
    $state = [ordered]@{
        Version  = $ScriptVersion
        Time     = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Backup   = $BackupDir
        Options  = [ordered]@{
            KeepEdge = [bool]$KeepEdge; KeepOneDrive = [bool]$KeepOneDrive; KeepXbox = [bool]$KeepXbox
            KeepOutlookNew = [bool]$KeepOutlookNew; KeepThirdParty = [bool]$KeepThirdParty
            SkipUiTweaks = [bool]$SkipUiTweaks; SkipPerformance = [bool]$SkipPerformance; GamingTweaks = [bool]$GamingTweaks
            Force = [bool]$Force
        }
        Reg      = @($script:Desired.Reg.ToArray())
        Tasks    = @($script:Desired.Tasks.ToArray())
        Apps     = @($script:Desired.Apps)
        Stuck    = @($script:Desired.Stuck.ToArray())
        Edge     = $script:Desired.Edge
        OneDrive = $script:Desired.OneDrive
        Recall   = $script:Desired.Recall
        Power    = $script:Desired.Power
        Baseline = $null
    }
    # Keep the footprint from before the FIRST run, so -Check compares with the untouched PC.
    $prev = Read-State
    $state.Baseline = if ($prev -and (Get-Prop $prev 'Baseline')) { Get-Prop $prev 'Baseline' } else { $script:Baseline }
    try {
        Set-Content -LiteralPath $StateFile -Value (ConvertTo-Json -InputObject $state -Depth 6) -Encoding UTF8
    } catch { Write-Warn2 "Could not write state.json: $($_.Exception.Message)" }
}

function Get-Footprint {
    # What the PC carries around: processes, service hosts, running services, memory in use.
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return [ordered]@{
        Time         = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        Processes    = @(Get-Process).Count
        Svchost      = @(Get-Process -Name svchost -ErrorAction SilentlyContinue).Count
        Services     = @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Running' }).Count
        MemoryUsedMB = [int](($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024)
    }
}

function Get-NativeText([string]$Exe, [string[]]$Arguments) {
    # stdout of a native tool as one string; stderr ignored (see Invoke-Native)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { return "$(& $Exe @Arguments 2>$null)" } finally { $ErrorActionPreference = $prev }
}

function Get-ActiveScheme {
    $out = Get-NativeText 'powercfg.exe' @('/getactivescheme')
    if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1].ToLower() }
    return $null
}

function Test-OnBattery {
    # Laptops and tablets keep their power plan: a performance plan drains the battery.
    try {
        if ((Get-CimInstance -ClassName Win32_ComputerSystem).PCSystemType -eq 2) { return $true }
        return (@(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop).Count -gt 0)
    } catch { return $false }
}

function Add-GuardLog([string]$Text) {
    if (-not $Reapply) { return }
    try {
        if (-not (Test-Path -LiteralPath $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null; Protect-Dir $BaseDir }
        Add-Content -LiteralPath $GuardLog -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) -Encoding UTF8
    } catch { }
}

function Invoke-DriftCheck {
    # Sets $script:DriftExit: 0 = all in place, 10 = drift, 2 = nothing applied yet.
    Write-Step 'Checking what Windows changed back since the last run'
    $state = Read-State
    if (-not $state) {
        Write-Info 'Nothing applied on this PC yet (no state.json). Run the debloat first.'
        $script:DriftExit = 2; return
    }
    Write-Info ("last run: {0} (v{1})" -f (Get-Prop $state 'Time'), (Get-Prop $state 'Version'))
    $drift = New-Object System.Collections.ArrayList
    $nReg = 0; $nTask = 0

    foreach ($e in @(Get-Prop $state 'Reg')) {
        if ($null -eq $e) { continue }
        $nReg++
        $name = [string]$e.Name; $lookup = if ($name -eq '(Default)') { '' } else { $name }
        $found = '<missing>'
        $k = $null
        try { $k = Open-RegKey -PsPath ([string]$e.Path) } catch { }
        if ($k) {
            try {
                if ($k.GetValueNames() -contains $lookup) {
                    $cur = $k.GetValue($lookup, $null, 'DoNotExpandEnvironmentNames')
                    $kind = $k.GetValueKind($lookup).ToString()
                    $found = if ($kind -eq [string]$e.Type) { "$cur" } else { "$cur ($kind)" }
                }
            } finally { $k.Close() }
        }
        if ($found -ne "$($e.Value)") {
            [void]$drift.Add([ordered]@{ Kind = 'Reg'; What = ("{0}\{1}" -f $e.Path, $name); Expected = "$($e.Value)"; Found = $found })
        }
    }

    foreach ($t in @(Get-Prop $state 'Tasks')) {
        if ($null -eq $t) { continue }
        $nTask++
        $task = Get-ScheduledTask -TaskPath ([string]$t.Path) -TaskName ([string]$t.Name) -ErrorAction SilentlyContinue
        if ($task -and $task.State -ne 'Disabled') {
            [void]$drift.Add([ordered]@{ Kind = 'Task'; What = ("{0}{1}" -f $t.Path, $t.Name); Expected = 'Disabled'; Found = "$($task.State)" })
        }
    }

    $patterns = @(@(Get-Prop $state 'Apps') | Where-Object { $_ })
    $stuck    = @(@(Get-Prop $state 'Stuck') | Where-Object { $_ })
    if ($patterns.Count -gt 0) {
        $seen = @{}
        foreach ($p in @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)) {
            if ($seen.ContainsKey($p.Name) -or $stuck -contains $p.Name) { continue }
            if ($p.PSObject.Properties['NonRemovable'] -and $p.NonRemovable) { continue }
            foreach ($pat in $patterns) {
                if ($p.Name -like $pat) {
                    $seen[$p.Name] = $true
                    [void]$drift.Add([ordered]@{ Kind = 'App'; What = $p.Name; Expected = 'removed'; Found = 'installed' })
                    break
                }
            }
        }
    }

    if ((Get-Prop $state 'Edge') -and (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe")) {
        [void]$drift.Add([ordered]@{ Kind = 'Edge'; What = 'Microsoft Edge'; Expected = 'removed'; Found = 'installed' })
    }
    if ((Get-Prop $state 'OneDrive') -and ((Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or
                                           (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe"))) {
        [void]$drift.Add([ordered]@{ Kind = 'OneDrive'; What = 'OneDrive'; Expected = 'removed'; Found = 'installed' })
    }
    if (Get-Prop $state 'Recall') {
        $f = $null
        try { $f = Get-WindowsOptionalFeature -Online -FeatureName 'Recall' -ErrorAction Stop } catch { }
        if ($f -and $f.State -eq 'Enabled') {
            [void]$drift.Add([ordered]@{ Kind = 'Feature'; What = 'Recall'; Expected = 'Disabled'; Found = 'Enabled' })
        }
    }

    $want = Get-Prop $state 'Power'
    if ($want) {
        $active = Get-ActiveScheme
        if ($active -ne $want) {
            [void]$drift.Add([ordered]@{ Kind = 'Power'; What = 'power plan'; Expected = $want; Found = "$active" })
        }
    }

    $shown = 0
    foreach ($d in $drift) {
        if ($shown -ge 40) { Write-Info ("... and {0} more (see {1})" -f ($drift.Count - $shown), $DriftFile); break }
        switch ($d.Kind) {
            'Reg'   { Write-Warn2 ("reg {0}: expected {1}, found {2}" -f $d.What, $d.Expected, $d.Found) }
            'Task'  { Write-Warn2 ("task enabled again: {0}" -f $d.What) }
            'Power' { Write-Warn2 ("power plan changed: expected {0}, found {1}" -f $d.Expected, $d.Found) }
            default { Write-Warn2 ("{0} is back: {1}" -f $d.Kind.ToLower(), $d.What) }
        }
        $shown++
    }
    $report = [ordered]@{ Time = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Count = $drift.Count
                          Checked = [ordered]@{ Registry = $nReg; Tasks = $nTask; AppPatterns = $patterns.Count }
                          Items = @($drift.ToArray()) }
    try { Set-Content -LiteralPath $DriftFile -Value (ConvertTo-Json -InputObject $report -Depth 5) -Encoding UTF8 } catch { }

    if ($drift.Count -eq 0) {
        Write-Ok ("all in place: {0} registry values, {1} scheduled tasks, removed apps still gone" -f $nReg, $nTask)
        $script:DriftExit = 0
    } else {
        Write-Info ''
        Write-Info ("DRIFT: {0} change(s) were turned back (checked {1} registry values, {2} tasks, apps)." -f $drift.Count, $nReg, $nTask)
        Write-Info 'Fix with: Win11-Debloat.ps1 -Reapply   (or "Uygula" in the app)'
        $script:DriftExit = 10
    }
    $script:DriftCount = $drift.Count

    $base = Get-Prop $state 'Baseline'
    if ($base) {
        $now = Get-Footprint
        Write-Step ("Footprint: before the first run ({0}) -> now" -f (Get-Prop $base 'Time'))
        foreach ($row in @(@('processes', 'Processes'), @('service hosts', 'Svchost'), @('running services', 'Services'))) {
            $b = [int](Get-Prop $base $row[1]); $n = [int]$now[$row[1]]
            Write-Info ("{0,-17} {1,6} -> {2,-6} ({3:+0;-0;0})" -f $row[0], $b, $n, ($n - $b))
        }
        $bm = [int](Get-Prop $base 'MemoryUsedMB'); $nm = [int]$now.MemoryUsedMB
        Write-Info ("{0,-17} {1,6} -> {2,-6} ({3:+0;-0;0} MB)" -f 'memory in use MB', $bm, $nm, ($nm - $bm))
        try {
            $boot = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
            $first = [datetime]::ParseExact([string](Get-Prop $base 'Time'), 'yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($boot -lt $first) { Write-Info 'not restarted since the first run yet: most gains show after a restart' }
        } catch { }
        Write-Info 'memory depends on what is open; compare with the same apps running'
    }
}

function Install-Guard {
    Write-Step 'Guard: re-check after every sign-in'
    if (-not (Read-State)) {
        Write-Warn2 'Apply the debloat first. The guard keeps an applied state in place.'
        return 2
    }
    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $target = Join-Path $GuardDir 'Win11-Debloat.ps1'
    if ($DryRun) {
        Write-Dry "copy scripts to $GuardDir"
        Write-Dry "scheduled task '$GuardTask': at sign-in of $user, run -Reapply"
        return 0
    }
    # %ProgramFiles% is admin-only by default, so a standard user cannot swap
    # the script that the task runs with highest privileges.
    New-Item -ItemType Directory -Path $GuardDir -Force | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination $target -Force
    $restore = Join-Path (Split-Path -Parent $PSCommandPath) 'Win11-Restore.ps1'
    if (Test-Path -LiteralPath $restore) { Copy-Item -LiteralPath $restore -Destination (Join-Path $GuardDir 'Win11-Restore.ps1') -Force }

    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action = New-ScheduledTaskAction -Execute $ps `
        -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Reapply' -f $target)
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $trigger.Delay = 'PT2M'
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $GuardTask -TaskPath '\' -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Force `
        -Description 'Cemal.cloud win11-debloat: after sign-in, re-applies only what Windows turned back. Log: %ProgramData%\CemalCloud\Win11Debloat\guard.log' | Out-Null
    Write-Ok "guard installed: runs 2 minutes after $user signs in"
    Write-Info "log    : $GuardLog"
    Write-Info 'remove : Win11-Debloat.ps1 -RemoveGuard (Win11-Restore.ps1 removes it too)'
    return 0
}

function Remove-Guard {
    Write-Step 'Guard'
    $t = Get-ScheduledTask -TaskPath '\' -TaskName $GuardTask -ErrorAction SilentlyContinue
    if ($DryRun) { if ($t) { Write-Dry "remove scheduled task '$GuardTask'" }; return 0 }
    if ($t) { Unregister-ScheduledTask -TaskPath '\' -TaskName $GuardTask -Confirm:$false; Write-Ok 'guard task removed' }
    else { Write-Info 'guard not installed' }
    if (Test-Path -LiteralPath $GuardDir) { Remove-Item -LiteralPath $GuardDir -Recurse -Force -ErrorAction SilentlyContinue }
    return 0
}

# ===========================================================================
# 0. Pre-flight
# ===========================================================================
Write-Banner

if ($InstallGuard) { exit (Install-Guard) }
if ($RemoveGuard)  { exit (Remove-Guard) }
if ($Check)        { Invoke-DriftCheck; exit $script:DriftExit }

$build = [Environment]::OSVersion.Version.Build
if ($build -lt 22000 -and -not $Force) {
    Write-Warn2 "This script targets Windows 11 (build 22000+). Detected build $build. Use -Force to override."
    exit 1
}

if ($Reapply) {
    $prev = Read-State
    Invoke-DriftCheck
    if ($script:DriftExit -ne 10) {
        Add-GuardLog ($(if ($script:DriftExit -eq 0) { 'no drift' } else { 'nothing applied yet, guard idle' }))
        exit 0
    }
    # Same choices as the last run.
    $opt = Get-Prop $prev 'Options'
    foreach ($n in 'KeepEdge', 'KeepOneDrive', 'KeepXbox', 'KeepOutlookNew', 'KeepThirdParty', 'SkipUiTweaks', 'SkipPerformance', 'GamingTweaks', 'Force') {
        Set-Variable -Name $n -Value ([bool](Get-Prop $opt $n))
    }
    Write-Step ("Reapplying with the options of the last run ({0} drifted)" -f $script:DriftCount)
}

New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
Protect-Dir $BaseDir
try { Start-Transcript -Path (Join-Path $BackupDir 'debloat.log') -Force | Out-Null } catch { }

try {
    # =======================================================================
    # 1. Safety net
    # =======================================================================
    Write-Step 'Safety net: restore point and backups'
    if ($DryRun) {
        Write-Dry 'create restore point, export registry, save app list'
    } else {
        if ($Reapply) {
            Write-Info 'no new restore point for a reapply (the first run made one); every change is still recorded'
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
        }

        $exports = [ordered]@{
            'HKLM-Policies'      = 'HKLM\SOFTWARE\Policies'
            'HKCU-Policies'      = 'HKCU\Software\Policies'
            'HKCU-CDM'           = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            'HKCU-Explorer'      = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer'
            'HKCU-Search'        = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search'
            'HKCU-Desktop'       = 'HKCU\Control Panel\Desktop'
        }
        foreach ($k in $exports.Keys) {
            [void](Invoke-Native 'reg.exe' @('export', $exports[$k], (Join-Path $BackupDir "$k.reg"), '/y'))
        }
        Get-AppxPackage -AllUsers | Select-Object Name, Version, PackageFullName |
            Sort-Object Name | Export-Csv (Join-Path $BackupDir 'apps-before.csv') -NoTypeInformation
        Write-Ok "backups in $BackupDir"
        if (-not $Reapply) { try { $script:Baseline = Get-Footprint } catch { } }
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
    $script:Desired.Apps = $apps

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
                $script:Desired.Recall = $true
            } catch { Write-Warn2 "Recall: $($_.Exception.Message)" }
        }
    } elseif ($recall) { $script:Desired.Recall = $true }

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
                $script:Desired.Edge = $true
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
                    $script:Desired.Edge = $true
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
                $script:Desired.OneDrive = $true
            } elseif ($DryRun) {
                Write-Dry 'uninstall OneDrive'
            } else {
                Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                foreach ($s in $setups) {
                    try { Start-Process -FilePath $s.Path -ArgumentList $s.Args -Wait -WindowStyle Hidden } catch { }
                }
                Add-Undo @{ Kind = 'OneDrive' }
                $script:Desired.OneDrive = $true
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
    # 9. Performance (only settings that are safe to undo; nothing that
    #    lowers security: Defender, Windows Update, CPU mitigations untouched)
    # =======================================================================
    if (-not $SkipPerformance) {
        Write-Step 'Performance: visual effects and transparency'
        # Custom visual effects: animations, fades and shadows off; ClearType,
        # thumbnails, full window drag and selection rectangle stay.
        $desk = 'HKCU:\Control Panel\Desktop'
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
        Set-Reg $desk 'UserPreferencesMask' ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) 'Binary'
        Set-Reg $desk 'FontSmoothing' '2' 'String'
        Set-Reg $desk 'DragFullWindows' '1' 'String'
        Set-Reg $desk 'MenuShowDelay' '0' 'String'
        Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
        Set-Reg $adv 'TaskbarAnimations' 0
        Set-Reg $adv 'ListviewAlphaSelect' 1
        Set-Reg $adv 'ListviewShadow' 1
        Set-Reg $adv 'IconsOnly' 0                          # keep thumbnails
        Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'AlwaysHibernateThumbnails' 0

        Write-Step 'Performance: background work'
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Task Scheduler\Maintenance' 'WakeUp' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0   # no P2P upload

        Write-Step 'Performance: scheduler, file system, services'
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 10
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38   # 0x26: short, variable, high foreground boost
        # 0x80000001: last-access timestamps off, user managed (same as "fsutil behavior set disablelastaccess 1")
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'NtfsDisableLastAccessUpdate' ([int]-2147483647)
        Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'Max Cached Icons' '4096' 'String'
        if (-not $KeepXbox) {
            # Group services into fewer svchost processes, as before Windows 10 1703 (Game Bar needs them split).
            Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' 0x7FFFFFFF
        }

        Write-Step 'Performance: power'
        if (Test-OnBattery) {
            Write-Info 'battery found (laptop / tablet / UPS): power plan and power throttling left as they are'
        } else {
            $active = Get-ActiveScheme
            if ($active -eq $PerfScheme) {
                $script:Desired.Power = $PerfScheme
            } elseif ($DryRun) {
                Write-Dry 'power plan: Cemal.cloud Performans (copy of Ultimate / High performance), power throttling off'
            } else {
                if ((Get-NativeText 'powercfg.exe' @('/list')) -notmatch $PerfScheme) {
                    if ((Invoke-Native 'powercfg.exe' @('/duplicatescheme', 'e9a42b02-d5df-448d-aa00-03f14749eb61', $PerfScheme)) -ne 0) {
                        [void](Invoke-Native 'powercfg.exe' @('/duplicatescheme', '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c', $PerfScheme))
                    }
                    [void](Invoke-Native 'powercfg.exe' @('/changename', $PerfScheme, 'Cemal.cloud Performans',
                        'Copy of Ultimate / High performance by Cemal.cloud win11-debloat'))
                }
                [void](Invoke-Native 'powercfg.exe' @('/setactive', $PerfScheme))
                if ((Get-ActiveScheme) -eq $PerfScheme) {
                    Add-Undo @{ Kind = 'Power'; Old = $active; Scheme = $PerfScheme }
                    $script:Desired.Power = $PerfScheme
                    Write-Ok 'power plan: Cemal.cloud Performans'
                } else {
                    # e.g. Modern Standby PCs only offer the Balanced plan
                    Write-Warn2 'this PC does not allow a performance power plan, kept the current one'
                    $script:Stats.Skipped++
                }
            }
            Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1
        }
    }

    # =======================================================================
    # 10. Gaming (optional, -GamingTweaks)
    # =======================================================================
    if ($GamingTweaks) {
        Write-Step 'Gaming'
        # Mouse acceleration off: 1:1 pointer movement (takes effect at the next sign-in)
        $mouse = 'HKCU:\Control Panel\Mouse'
        Set-Reg $mouse 'MouseSpeed' '0' 'String'
        Set-Reg $mouse 'MouseThreshold1' '0' 'String'
        Set-Reg $mouse 'MouseThreshold2' '0' 'String'
        # A game's timer resolution request applies system-wide again (as before 2004). Nothing is forced.
        Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel' 'GlobalTimerResolutionRequests' 1
        # Shift x5 / holding Shift / NumLock 5 s no longer pop up a dialog mid-game. Only the
        # "shortcut active" bit (0x4) is cleared, so anyone who uses these features keeps them.
        foreach ($a in @(@('StickyKeys', 510), @('Keyboard Response', 126), @('ToggleKeys', 62))) {
            $p = "HKCU:\Control Panel\Accessibility\$($a[0])"
            $cur = [int]$a[1]
            try {
                $v = (Get-ItemProperty -LiteralPath $p -Name 'Flags' -ErrorAction Stop).Flags
                if ("$v" -match '^\d+$') { $cur = [int]"$v" }
            } catch { }
            Set-Reg $p 'Flags' ([string]($cur -band (-bnot 4))) 'String'
        }
        Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    }

    # =======================================================================
    # 11. Quality-of-life tweaks
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
    Save-State
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
    Add-GuardLog ("reapply aborted, see {0}" -f $BackupDir)
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
if ($Reapply -and -not $DryRun) {
    Add-GuardLog ("drift {0} -> reapplied: {1} registry, {2} tasks, {3} apps, {4} failed. Backup: {5}" -f `
        $script:DriftCount, $script:Stats.Registry, $script:Stats.Tasks, $script:Stats.Apps, $script:Stats.Failed, $BackupDir)
    Write-Host ''
    Write-Host '  Reapplied. Sign out and back in (or restart) to see every change.' -ForegroundColor Green
} elseif (-not $DryRun) {
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
