# =============================================================================
# TeknoParrot Manager  |  v0.99.34 BETA
# Author: Jumpstile
# =============================================================================
#
# Registers your extracted games with TeknoParrot so they appear and launch
# in TeknoParrotUI, copies your controls between games of the same type, and
# keeps your game library organised. Requires Windows 10+ and PowerShell 5.1+.
#
# WHAT IT DOES
#   Registration   Scans your extracted games, matches each executable to the
#                  correct TeknoParrot GameProfiles template, and copies it to
#                  UserProfiles with <GamePath> set. Existing profiles are
#                  never overwritten.
#
#   Fuzzy matching For platforms where many games share one executable name
#                  (e.g. NESiCAxLive's game.exe), the script compares the
#                  game folder name to every candidate profile code using a
#                  Dice bigram similarity score and auto-registers the best
#                  match when confidence is high enough. Below the threshold,
#                  the best guess is shown so manual registration takes one
#                  click rather than a full search.
#
#   AutoSync       Extracts game ZIPs from a NAS or local source to a staging
#                  folder you choose, skipping unchanged games. Supports
#                  interactive selection: browse the full A-Z list, search by
#                  keyword, or extract everything not already on disk.
#
#   Propagation    You bind ONE game of each control type in TeknoParrotUI;
#                  the script copies those controls to all other games of the
#                  same type, matched by function so a wheel value never lands
#                  on a gun. Carries aim-mode settings between same-type games.
#                  Before applying, it lists each reference game's carried
#                  settings so a bad value (e.g. an axis mode left over from
#                  testing) can be caught before it spreads to every game.
#
#   Repair         Finds UserProfiles with broken or missing GamePaths and
#                  re-points them to the correct executable.
#
#   Restore        A menu option lists all timestamped backups with file
#                  counts; pick one by number and the script restores it in
#                  one step, with a process-running check and atomic cleanup.
#
#   LaunchBox      Exports a LaunchBox-compatible XML file listing every
#                  registered game with its title, emulator path, and
#                  --profile= argument, ready for the import wizard.
#
#   Device survey  Asks which controls you have and prints a tailored plan of
#                  which game to bind with which device.
#
# WHAT IT DOES NOT DO
#   Controls are copied only from a reference game you have already bound;
#   anything else is left for you and reported. Game files are not provided.
#
# REQUIREMENTS
#   - Windows 10+ with PowerShell 5.1+
#   - A TeknoParrot install with TeknoParrotUi.exe and its GameProfiles folder.
#     Run TeknoParrotUi.exe once first so it downloads its profile library.
#   - Games extracted into per-game subfolders (AutoSync can do this).
# =============================================================================

param([switch]$Unattended, [switch]$DryRun)

# Single source of truth for the version string used in the banner, log, and
# GitHub API User-Agent headers. Previously hardcoded in each of those spots
# independently, which let the User-Agent strings drift out of sync with the
# banner (caught stale at 0.70 during the v0.71 bump, again at 0.76, and
# again at 0.98 -- this line is easy to miss because it's far from the
# header comment block at the top of the file. Check it every version bump.)
$ScriptVersion = "0.99.34"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       TeknoParrot Manager  v$ScriptVersion BETA" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Load the ZIP assembly once at startup. Expand-ZipFileSafe uses ZipArchive
# instead of Expand-Archive (PS 5.1 bugs: "already exists" with -Force, partial
# folders on failure) and instead of ZipFile::ExtractToDirectory (no long-path
# support). Expand-ZipFileSafe uses \\?\ prefixes to bypass MAX_PATH.
Add-Type -AssemblyName System.IO.Compression.FileSystem

# PS 5.1 on older Windows 10 builds defaults to TLS 1.0. Ensure TLS 1.2 is
# included without removing protocols already enabled on this machine.
[System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

$logPath               = Join-Path $PSScriptRoot "TeknoParrot-Manager.log"
$script:logWarnShown   = $false   # full warning shown at most once to avoid repeated noise
$script:logFailedCount = 0        # total entries that could not be written this run

function Write-Log {
    param([string]$msg)
    $line = "[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $msg
    try {
        # AppendAllText with BOM-less UTF-8: preserves prior entries and handles
        # non-ASCII characters in paths/game names without log corruption.
        [System.IO.File]::AppendAllText($logPath, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
    } catch {
        # First failure: surface a clear warning so the user knows their session
        # is not being archived and can investigate before the run continues.
        if (-not $script:logWarnShown) {
            Write-Host "  WARNING: Cannot write to log file -- this run will not be archived." -ForegroundColor Yellow
            Write-Host "  Log path : $logPath" -ForegroundColor DarkGray
            Write-Host "  Error    : $($_.Exception.Message)" -ForegroundColor DarkGray
            $script:logWarnShown = $true
        }
        # Echo every entry that cannot be archived so nothing is silently lost.
        # The [UNLOGGED] prefix distinguishes these from normal script output.
        Write-Host ("  [UNLOGGED] {0}" -f $msg) -ForegroundColor DarkGray
        $script:logFailedCount++
    }
}

# Prompts for a file/folder path with an option to browse for it using a
# native Windows dialog instead of typing it. Typing "B" (case-insensitive)
# opens the dialog; anything else is returned exactly as before (typing the
# path manually is unchanged for anyone who never uses this). Uses
# System.Windows.Forms (ships with every Windows PowerShell 5.1 install,
# no new dependency) -- loaded lazily, only the first time this is called.
#
# Requires the STA apartment Windows PowerShell (powershell.exe) launches in
# by default -- WinForms dialogs need it. If launched under a host that
# doesn't have it (or the dialog otherwise fails to open, e.g. no desktop
# session), this fails closed to the plain manual-entry prompt rather than
# crashing the run -- browsing is a convenience layered on top of typing,
# never a replacement that could block someone who can't use it.
#
# -Mode 'Folder' shows a folder picker; 'File' shows an open-file picker
# (-FileFilter customizes the file-type list); 'SaveFile' shows a save-file
# picker (for choosing a download destination, not an existing file).
function Read-PathWithBrowse {
    param(
        [string]$Prompt,
        [ValidateSet('Folder', 'File', 'SaveFile')] [string]$Mode = 'Folder',
        [string]$FileFilter = "All files (*.*)|*.*",
        [string]$DefaultFileName = '',
        [string]$InitialDirectory = ''
    )
    $raw = (Read-Host "$Prompt (or type B to browse)").Trim()
    if ($raw.ToUpper() -ne 'B') { return $raw }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $initialDir = if ($InitialDirectory -and (Test-Path -LiteralPath $InitialDirectory)) { $InitialDirectory } else { '' }
        switch ($Mode) {
            'Folder' {
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $dlg.Description = $Prompt
                if ($initialDir) { $dlg.SelectedPath = $initialDir }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
                return ''
            }
            'File' {
                $dlg = New-Object System.Windows.Forms.OpenFileDialog
                $dlg.Filter = $FileFilter
                if ($initialDir) { $dlg.InitialDirectory = $initialDir }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
                return ''
            }
            'SaveFile' {
                $dlg = New-Object System.Windows.Forms.SaveFileDialog
                $dlg.Filter   = $FileFilter
                $dlg.FileName = $DefaultFileName
                if ($initialDir) { $dlg.InitialDirectory = $initialDir }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
                return ''
            }
        }
    } catch {
        Write-Log "Read-PathWithBrowse: dialog failed -- $_"
        Write-Host "  Could not open the file browser -- type the path instead." -ForegroundColor Yellow
        return (Read-Host "  Path").Trim()
    }
}

# Loads an XML file with external-entity / DTD resolution disabled. The profile
# files are local and trusted, so this is defense-in-depth rather than a fix for
# a real threat, but it keeps parsing safe regardless of a file's contents.
# Returns an XmlDocument (same type as an [xml] cast), or throws on parse error.
function Read-Xml {
    param([string]$path)
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.Load($path)
    return $doc
}

# Writes an XmlDocument atomically: saves to a .tmp file first, then commits
# via File.Replace() so the original is never truncated before the write
# completes. Uses BOM-less UTF-8 to match the project-wide convention.
function Save-Xml {
    param([System.Xml.XmlDocument]$doc, [string]$path)
    $tmpPath      = $path + ".tmp"
    $xws          = New-Object System.Xml.XmlWriterSettings
    $xws.Encoding = New-Object System.Text.UTF8Encoding $false
    $xws.Indent   = $true
    $xw           = [System.Xml.XmlWriter]::Create($tmpPath, $xws)
    try   { $doc.Save($xw) }
    finally { $xw.Close() }
    if (Test-Path -LiteralPath $path) {
        try {
            [System.IO.File]::Replace($tmpPath, $path, $null)
        } catch {
            [System.IO.File]::Delete($path)
            [System.IO.File]::Move($tmpPath, $path)
        }
    } else {
        [System.IO.File]::Move($tmpPath, $path)
    }
}

# Dry-run-aware wrapper around Save-Xml, used by every write site that
# participates in the AutoSync/Register preview mode (-DryRun). Centralizing
# the gate here means every call site converts with a one-line change and
# there is exactly one place that can accidentally write during a preview.
function Save-XmlMaybe {
    param([System.Xml.XmlDocument]$doc, [string]$path, [bool]$DryRun)
    if ($DryRun) { Write-Log "DryRun: would save $path"; return }
    Save-Xml $doc $path
}

# =============================================================================
# PROFILE / SCHEMA DRIFT DETECTION  (issue #43 -- pure, read-only, never writes)
# =============================================================================
# TeknoParrot's GameProfile XML schema evolves upstream (recent examples:
# CXBXR platform prep, BudgieLoader path/version fixes, VF5 profile tag
# fixes, Chihiro region options, Lindbergh ELF2 port changes). This script
# reads those profiles to drive setup; a silent schema change can make a
# correct script look broken, or -- worse -- tempt a write based on a field
# it does not actually understand. Get-GameProfileSchemaDrift classifies a
# single profile's structure against a known baseline and returns a
# structured, actionable report. It NEVER mutates the document and NEVER
# returns anything a caller is meant to write -- it is a diagnostic only.
# The cardinal safety rule it encodes: an unknown field is REPORTED, never
# acted on.

# Baseline of top-level <GameProfile> child elements this script recognizes,
# captured from live teknogods/TeknoParrotUI GameProfiles. New optional
# elements appearing upstream are surfaced as 'unknown' (informational, not
# a failure); the absence of a REQUIRED element is a hard drift finding.
$script:KnownGameProfileTopLevel = @(
    'GamePath','GamePath2','TestMenuParameter','TestMenuIsExecutable',
    'ExtraParameters','TestMenuExtraParameters','EmulationProfile',
    'GameProfileRevision','HasSeparateTestMode','ExecutableName',
    'ExecutableName2','HasTwoExecutables','LaunchSecondExecutableFirst',
    'HasTpoSupport','EmulatorType','Is64Bit','ValidMd5','ConfigValues',
    'GameName','GameGenreInternal','IconName','HasModeForSquare',
    'RequiresAdmin','InvokeFullscreenOnStartup','LaunchedFromUsb',
    'CamberWindowState'
)

# Top-level elements that must be present for this script to reason about a
# profile at all. A profile missing these is genuinely malformed/renamed
# upstream, not merely extended -- worth a hard finding.
$script:RequiredGameProfileTopLevel = @('EmulationProfile','ConfigValues')

# FieldType values this script understands inside ConfigValues. An unknown
# FieldType is reported (so a new control type is noticed) but, again, never
# acted on.
$script:KnownFieldTypes = @('Bool','Dropdown','Text','Slider')

function Get-GameProfileSchemaDrift {
    param(
        [System.Xml.XmlDocument]$Doc,
        [string[]]$KnownTopLevel    = $script:KnownGameProfileTopLevel,
        [string[]]$RequiredTopLevel = $script:RequiredGameProfileTopLevel,
        [string[]]$KnownFieldTypes  = $script:KnownFieldTypes
    )

    $unknownNodes      = New-Object System.Collections.Generic.List[string]
    $missingRequired   = New-Object System.Collections.Generic.List[string]
    $unknownFieldTypes = New-Object System.Collections.Generic.List[string]
    $present           = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $root = if ($Doc) { $Doc.SelectSingleNode("/GameProfile") } else { $null }
    if ($null -eq $root) {
        # No <GameProfile> root at all -- the strongest possible drift signal
        # (renamed root, wrong document, or corrupt). Report, never act.
        foreach ($r in $RequiredTopLevel) { [void]$missingRequired.Add($r) }
        return [pscustomobject]@{
            HasRoot           = $false
            UnknownNodes      = $unknownNodes
            MissingRequired   = $missingRequired
            UnknownFieldTypes = $unknownFieldTypes
            HasDrift          = $true
            # Cardinal invariant: drift detection is diagnostic only.
            WouldWrite        = $false
        }
    }

    $knownSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$KnownTopLevel, [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($child in $root.ChildNodes) {
        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        [void]$present.Add($child.Name)
        if (-not $knownSet.Contains($child.Name)) {
            if (-not $unknownNodes.Contains($child.Name)) { [void]$unknownNodes.Add($child.Name) }
        }
    }

    foreach ($r in $RequiredTopLevel) {
        if (-not $present.Contains($r)) { [void]$missingRequired.Add($r) }
    }

    $ftSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$KnownFieldTypes, [System.StringComparer]::OrdinalIgnoreCase)
    $fnodes = $Doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation")
    foreach ($n in $fnodes) {
        $ftNode = $n.SelectSingleNode("FieldType")
        if ($null -eq $ftNode) { continue }
        $ft = if ($ftNode.InnerText) { $ftNode.InnerText.Trim() } else { '' }
        if ($ft -and -not $ftSet.Contains($ft)) {
            if (-not $unknownFieldTypes.Contains($ft)) { [void]$unknownFieldTypes.Add($ft) }
        }
    }

    $hasDrift = ($unknownNodes.Count -gt 0) -or ($missingRequired.Count -gt 0) -or ($unknownFieldTypes.Count -gt 0)
    return [pscustomobject]@{
        HasRoot           = $true
        UnknownNodes      = $unknownNodes
        MissingRequired   = $missingRequired
        UnknownFieldTypes = $unknownFieldTypes
        HasDrift          = $hasDrift
        WouldWrite        = $false
    }
}

# Writes TeknoParrot-Manager.config.json from the current script-scope
# settings variables. Single source of truth for the config schema --
# every call site that needs to persist a settings change after this run
# calls this instead of building its own copy of the field list, so adding
# a new setting only ever means editing one place.
function Save-Config {
    $cfg = [ordered]@{
        TeknoParrotRoot              = $tpRoot
        ZipSourceFolder              = $zipSource
        ZipSourceSupplementaryFolder = $zipSourceSupplementary
        GamesInstallFolder           = $gamesInstallFolder
        RetroBat                     = $retroBat
        HyperSpinDataPath            = $hsDataPath
        ReShadeSourceDll             = $rsSourceDll
        ReShadeSourceDll32           = $rsSourceDll32
        DgVoodoo2SourceDir           = $dgSourceDir
        EggmanDatZip                 = $eggmanDatZip
        DatFilePath                  = $datFilePath
        SupplementaryDatPath         = $supplementaryDatPath
        IncludeSupplementary         = $includeSupplementary
        LaunchBoxRoot                = $lbRoot
        LaunchBoxPlatformMode        = $lbPlatformMode
        LaunchBoxCustomPlatformName  = $lbCustomPlatformName
        LaunchBoxEmulatorId          = $lbEmulatorId
        PostgresSuperPasswordEncrypted = $postgresSuperPasswordEncrypted
    }
    try {
        [System.IO.File]::WriteAllText($configPath, ($cfg | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false))
        return $true
    } catch {
        Write-Log "Config: could not save -- $_"
        return $false
    }
}

# Reads the primary ExecutableName from a profile XML using a fast regex pass,
# avoiding a full DOM parse for every file during the index scan. The regex
# matches <ExecutableName> exactly (not <ExecutableName2>). Falls back to a
# full parse if the quick read finds nothing.
function Get-PrimaryExecutableName {
    param([string]$path)
    # Uses the DOM parser directly: XmlDocument ignores XML comments by design,
    # so a commented-out <ExecutableName> alternative above the real one is
    # invisible to $x.GameProfile.ExecutableName. The previous regex fast path
    # (ReadAllText + comment-strip regex + regex match) added fragility with no
    # practical benefit -- the DOM parse handles all edge cases correctly. See
    # issues #22 and #25.
    try {
        $x = Read-Xml $path
        if ($x.GameProfile) { return [string]$x.GameProfile.ExecutableName }
    } catch { }
    return $null
}

# Some TeknoParrot profiles (HasTwoExecutables=true -- e.g. the Initial D
# Arcade Stage series, which launches a companion amdaemon.exe alongside the
# real game exe) need a second GamePath2 field set in addition to GamePath.
# Confirmed against the real teknogods/TeknoParrotUI GameProfile schema
# (GameProfile.cs): there is no separate dat/folder hint for the second exe's
# location, so this assumes the standard layout -- both exes sit in the same
# folder, since LaunchSecondExecutableFirst implies TeknoParrot itself runs
# the second exe from that same working directory. If ExecutableName2 isn't
# found there, GamePath2 is left unset rather than guessed -- registration of
# the primary exe still succeeds either way.
# Only ever skipped (left alone) when GamePath2 ALREADY points at that exact
# expected location -- not merely "non-empty". A real tester case (issue #8)
# had GamePath2 pointing at a totally different, stale folder left over from
# before a library migration: GamePath itself had since been repaired to the
# new location (Repair-GamePaths only ever touches GamePath, never
# GamePath2), but the old "never overwrite a non-empty GamePath2" rule then
# preserved that stale value forever. Comparing against the expected path
# (rather than just checking IsNullOrWhiteSpace) lets a stale GamePath2 get
# corrected the same way a stale GamePath already does, while still never
# touching one a user has deliberately pointed somewhere else for a reason.
function Set-SecondaryExecutablePath {
    param([System.Xml.XmlDocument]$Doc, [string]$PrimaryExePath)

    $hasTwoNode = $Doc.GameProfile.SelectSingleNode("HasTwoExecutables")
    if ($null -eq $hasTwoNode -or $hasTwoNode.InnerText -ne 'true') { return $false }

    $exe2Name = [string]$Doc.GameProfile.ExecutableName2
    if ([string]::IsNullOrWhiteSpace($exe2Name)) { return $false }

    $exe2Path = Join-Path ([System.IO.Path]::GetDirectoryName($PrimaryExePath)) $exe2Name.Trim()

    $gp2 = $Doc.GameProfile.SelectSingleNode("GamePath2")
    if ($null -ne $gp2 -and $gp2.InnerText.Trim() -eq $exe2Path) { return $false }

    if (-not (Test-Path -LiteralPath $exe2Path -PathType Leaf)) { return $false }

    if ($null -eq $gp2) {
        $gp2 = $Doc.CreateElement("GamePath2")
        [void]$Doc.GameProfile.AppendChild($gp2)
    }
    $gp2.InnerText = $exe2Path
    return $true
}

# Register-Games marks a folder "already registered" the moment a matching
# UserProfile file exists, without ever opening it -- correct for the common
# case (nothing to do), but it means a profile that was registered before
# Set-SecondaryExecutablePath existed (or registered directly in
# TeknoParrotUI) never gets GamePath2 backfilled, even on a v0.99.6+ run.
# Called from every "already registered, skip" branch in Register-Games
# instead of duplicating the read/check/save sequence at each site. Reads the
# EXISTING profile's own GamePath as the primary exe (not the exe currently
# being iterated) since a dat-resolved sub-path can legitimately differ from
# it. Only writes back if Set-SecondaryExecutablePath actually set a new
# value -- never touches a file that needed no change. See issue #8.
function Backfill-SecondaryExecutablePath {
    param([string]$UserProfilePath, [bool]$DryRun)
    try {
        $existingDoc = Read-Xml $UserProfilePath
        $gpNode = $existingDoc.GameProfile.SelectSingleNode("GamePath")
        if ($null -eq $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { return }
        if (Set-SecondaryExecutablePath $existingDoc $gpNode.InnerText) {
            Save-XmlMaybe $existingDoc $UserProfilePath $DryRun
            Write-Log "Backfilled GamePath2 on existing profile: $UserProfilePath"
        }
    } catch {
        Write-Log "Backfill-SecondaryExecutablePath: could not check/update '$UserProfilePath' -- $_"
    }
}

# Drive-info cache for Get-LocalDriveInfoSafe. Populated on first call within
# each menu-loop iteration; Clear-LocalDriveInfoCache resets it so the next
# call re-fetches live data (drive letter mappings can change between operations
# -- a USB drive ejected, a network share reconnecting to a different letter).
$script:LocalDriveInfoCache          = $null
$script:LocalDriveInfoCachePopulated = $false

# Runs $ScriptBlock in a background job and waits up to $TimeoutSeconds for
# it to finish, returning its output -- or $null on timeout/error. Issue #5
# (v1.0 roadmap): a residual, never-actually-reproduced theoretical risk
# that a local Win32 call could itself still block on a deeply wedged
# network share. Uses Start-Job (a separate process), not a runspace/
# thread -- PS 5.1 has no safe way to abort a thread stuck inside a native
# blocking call, so only killing the whole process actually frees it if the
# theoretical deeper hang ever turns out to be real. Generic on purpose so
# any future "local call that could theoretically still block" concern can
# reuse it rather than hand-rolling another job/timeout dance.
function Invoke-WithHardTimeout {
    param([scriptblock]$ScriptBlock, [int]$TimeoutSeconds = 5)
    $job = Start-Job -ScriptBlock $ScriptBlock
    try {
        if (Wait-Job -Job $job -Timeout $TimeoutSeconds) {
            return Receive-Job -Job $job -ErrorAction SilentlyContinue
        }
        Write-Log "Invoke-WithHardTimeout: scriptblock did not complete within ${TimeoutSeconds}s -- abandoning."
        return $null
    } catch {
        Write-Log "Invoke-WithHardTimeout: failed -- $_"
        return $null
    } finally {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

# Fetches every local drive's network-or-not status, hard-timeout-wrapped
# per issue #5 above. Returns $null on timeout/error -- callers MUST treat
# that as "could not determine drive types" and fail safe (never block,
# never crash, never claim a path is or isn't a network path it couldn't
# actually check).
#
# Deliberately returns plain [pscustomobject]s (Name/IsNetwork), NOT real
# [System.IO.DriveInfo] objects -- a real bug, confirmed from a tester's
# actual error output (issue #5 follow-up): Invoke-WithHardTimeout runs this
# in a background job (Start-Job), and PowerShell's job-result deserialization
# (Receive-Job) does not reconstruct arbitrary .NET types -- a DriveInfo that
# crosses that boundary comes back as a `Deserialized.System.IO.DriveInfo`
# PSObject stand-in, which then fails a strictly-typed [DriveInfo[]] parameter
# bind downstream with "Cannot convert ... to type System.IO.DriveInfo." The
# fix is computing the actual DriveType comparison INSIDE the job (where the
# real, live DriveInfo instances are still valid) and only ever returning
# plain string/bool data across the job boundary, which survives
# Receive-Job's deserialization intact.
function Get-LocalDriveInfoSafe {
    if (-not $script:LocalDriveInfoCachePopulated) {
        $script:LocalDriveInfoCache = Invoke-WithHardTimeout -ScriptBlock {
            [System.IO.DriveInfo]::GetDrives() | ForEach-Object {
                [pscustomobject]@{ Name = $_.Name; IsNetwork = ($_.DriveType -eq [System.IO.DriveType]::Network) }
            }
        } -TimeoutSeconds 5
        $script:LocalDriveInfoCachePopulated = $true
    }
    return $script:LocalDriveInfoCache
}

# Invalidates the drive-info cache so the next Get-LocalDriveInfoSafe call
# re-fetches live data. Called at the top of each main-menu-loop iteration
# so each mode entry always starts with a fresh snapshot.
function Clear-LocalDriveInfoCache {
    $script:LocalDriveInfoCache          = $null
    $script:LocalDriveInfoCachePopulated = $false
}

# Returns $true when $path resolves to a network location (UNC or mapped
# drive). $Drives lets a caller checking many paths in one pass (e.g.
# Find-TeknoParrotRoot enumerating every PSDrive) fetch drive info ONCE via
# Get-LocalDriveInfoSafe and reuse it, rather than this function re-running
# the hard-timeout-wrapped GetDrives() call (and paying its job-spawn cost)
# once per candidate path -- when omitted, this fetches it itself for a
# single one-off check. $Drives must be the Name/IsNetwork shape
# Get-LocalDriveInfoSafe returns (see that function's comment for why a real
# [System.IO.DriveInfo[]] can't be used here) -- deliberately untyped rather
# than re-introducing the type constraint that caused this bug.
function Test-IsNetworkPath {
    param([string]$path, $Drives = $null)
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    $path = $path.TrimEnd('\', '/')   # normalise trailing separators before matching
    if ($path -match '^\\\\') { return $true }
    if ($path -match '^([A-Za-z]):') {
        $letter = $Matches[1].ToUpper() + ':\'
        try {
            # [System.IO.DriveInfo] resolves drive type via the local Win32
            # GetDriveType() call, which reads the drive-letter mapping type
            # without contacting the remote server. Get-CimInstance's WMI
            # provider can hang 20-30s if a mapped network drive (e.g. an
            # OpenMediaVault share) has dropped off the network or gone to
            # sleep, which would stall the script at startup.
            $allDrives = if ($null -ne $Drives) { $Drives } else { Get-LocalDriveInfoSafe }
            if ($null -eq $allDrives) { return $false }   # could not determine -- fail safe
            $drive = $allDrives | Where-Object { $_.Name -eq $letter }
            if ($drive -and $drive.IsNetwork) { return $true }
        } catch {}
    }
    return $false
}

# Reads up to 20 MB from the largest ZIP in $path and returns MB/s, or $null.
# The FileStream is always disposed via finally, even if an exception occurs
# mid-read, preventing a file handle leak on the network share.
function Measure-PathThroughput {
    param([string]$path)
    $testFile = Get-ChildItem -LiteralPath $path -Filter *.zip -ErrorAction SilentlyContinue |
                Sort-Object Length -Descending | Select-Object -First 1
    if (-not $testFile -or $testFile.Length -eq 0) { return $null }
    $sampleBytes = [Math]::Min($testFile.Length, 20MB)
    $buffer      = New-Object byte[] $sampleBytes
    $fs          = $null
    try {
        $sw    = [System.Diagnostics.Stopwatch]::StartNew()
        $fs    = [System.IO.File]::OpenRead($testFile.FullName)
        $total = 0
        while ($total -lt $sampleBytes) {
            $chunk = $fs.Read($buffer, $total, $sampleBytes - $total)
            if ($chunk -eq 0) { break }
            $total += $chunk
        }
        $sw.Stop()
        if ($sw.Elapsed.TotalSeconds -lt 0.01 -or $total -eq 0) { return $null }
        return [Math]::Round(($total / 1MB) / $sw.Elapsed.TotalSeconds, 1)
    } catch { return $null }
    finally   { if ($null -ne $fs) { $fs.Dispose() } }
}

# Measures write throughput to $path by writing 10 MB of zeros to a temp file.
# Returns MB/s, or $null if $path does not exist or the write fails.
# The temp file is always removed in the finally block.
function Measure-PathWriteThroughput {
    param([string]$path)
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $testFile = Join-Path $path "._tp_write_test_tmp"
    $fs = $null
    try {
        $sampleBytes = 10MB
        $buffer      = New-Object byte[] 65536
        $sw          = [System.Diagnostics.Stopwatch]::StartNew()
        $fs          = [System.IO.File]::Open($testFile, [System.IO.FileMode]::Create,
                           [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $written = 0
        while ($written -lt $sampleBytes) {
            $chunk = [Math]::Min(65536, $sampleBytes - $written)
            $fs.Write($buffer, 0, $chunk)
            $written += $chunk
        }
        $fs.Flush()
        $sw.Stop()
        if ($sw.Elapsed.TotalSeconds -lt 0.01 -or $written -eq 0) { return $null }
        return [Math]::Round(($written / 1MB) / $sw.Elapsed.TotalSeconds, 1)
    } catch { return $null }
    finally {
        if ($null -ne $fs) { $fs.Dispose() }
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
    }
}

# True if $child is the same folder as, or inside, $parent. Both paths are
# resolved via GetFullPath (which collapses .. components) before comparison,
# so a crafted path like "staging\..\Windows" cannot bypass the prefix check.
# Used to enforce staging-folder boundaries and prevent ZIP slip.
function Test-PathInside {
    param([string]$child, [string]$parent)
    try {
        $c = [System.IO.Path]::GetFullPath($child).TrimEnd('\','/')
        $p = [System.IO.Path]::GetFullPath($parent).TrimEnd('\','/')
    } catch { return $false }
    if ($c -eq $p) { return $true }
    return $c.StartsWith($p + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

# Logs a SHA256 audit trail for a binary downloaded from a third-party
# source (GitHub Releases, a raw repo file, etc). None of the sources this
# script pulls from publish checksums to verify against, and most of the
# binaries are unsigned community builds, so there is no real trust anchor
# to enforce a pass/fail check against -- this does not block or validate
# anything. It exists so a user who wants to verify what was actually
# fetched (or diagnose a corrupted/tampered download after the fact) has a
# source URL + filename + hash + timestamp on record without having to
# reproduce the download themselves.
function Write-DownloadAudit {
    param([string]$Source, [string]$FileName, [string]$Path, [string]$Version = "")
    try {
        $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
        $verPart = if ($Version) { " Version=$Version" } else { "" }
        Write-Log "DownloadAudit: File=$FileName$verPart SHA256=$hash Source=$Source"
    } catch {
        Write-Log "DownloadAudit: could not hash $FileName -- $_"
    }
}

# Splits a TeknoParrot <ExecutableName> value into its alternatives.
# The field can contain multiple candidates separated by ; or | (e.g.
# "apacheM_HD.elf;apacheM.elf" or "game|game.bin"). Returns all non-empty parts.
function Get-ExeAlternatives {
    param([string]$exeName)
    return @($exeName -split '[;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# Scans common install locations for TeknoParrotUi.exe and returns matching
# root folder paths. Used to suggest the path on first run so the user does
# not have to type it from memory. Checks LaunchBox emulator folders, drive
# roots, and standard Program Files locations on every mounted local drive.
function Find-TeknoParrotRoot {
    $candidates = New-Object System.Collections.ArrayList
    $up = $env:USERPROFILE
    if ($up) {
        [void]$candidates.Add((Join-Path $up "LaunchBox\Emulators\TeknoParrot"))
        [void]$candidates.Add((Join-Path $up "AppData\Roaming\LaunchBox\Emulators\TeknoParrot"))
    }
    # Fetch drive type info ONCE for this whole scan (issue #5) -- both for
    # the hard-timeout job-spawn cost and to avoid the pre-existing
    # inefficiency of re-running GetDrives() once per candidate drive letter.
    $localDriveInfo = Get-LocalDriveInfoSafe
    $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                Where-Object { $_.Root -and -not (Test-IsNetworkPath $_.Root -Drives $localDriveInfo) -and (Test-Path -LiteralPath $_.Root) } |
                ForEach-Object { $_.Root.TrimEnd('\') })
    foreach ($d in $drives) {
        [void]$candidates.Add("$d\TeknoParrot")
        [void]$candidates.Add("$d\Games\TeknoParrot")
        [void]$candidates.Add("$d\Emulators\TeknoParrot")
        [void]$candidates.Add("$d\Program Files\TeknoParrot")
        [void]$candidates.Add("$d\Program Files (x86)\TeknoParrot")
    }
    $found = New-Object System.Collections.ArrayList
    foreach ($path in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $path "TeknoParrotUi.exe")) -and
            $found -notcontains $path) {
            [void]$found.Add($path)
        }
    }
    return ,$found   # comma prevents PS 5.1 from unwrapping the ArrayList into individual strings
}

# Same strategy as Find-TeknoParrotRoot, but looking for LaunchBox.exe
# itself (the LaunchBox installation root, not the TeknoParrot emulator
# folder underneath it) -- used by the direct LaunchBox integration to
# locate Data\ without asking the user to type the path from memory.
function Find-LaunchBoxRoot {
    $candidates = New-Object System.Collections.ArrayList
    $up = $env:USERPROFILE
    if ($up) {
        [void]$candidates.Add((Join-Path $up "LaunchBox"))
        [void]$candidates.Add((Join-Path $up "AppData\Roaming\LaunchBox"))
    }
    $localDriveInfo = Get-LocalDriveInfoSafe
    $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                Where-Object { $_.Root -and -not (Test-IsNetworkPath $_.Root -Drives $localDriveInfo) -and (Test-Path -LiteralPath $_.Root) } |
                ForEach-Object { $_.Root.TrimEnd('\') })
    foreach ($d in $drives) {
        [void]$candidates.Add("$d\LaunchBox")
        [void]$candidates.Add("$d\Games\LaunchBox")
        [void]$candidates.Add("$d\Program Files\LaunchBox")
        [void]$candidates.Add("$d\Program Files (x86)\LaunchBox")
    }
    $found = New-Object System.Collections.ArrayList
    foreach ($path in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $path "LaunchBox.exe")) -and
            $found -notcontains $path) {
            [void]$found.Add($path)
        }
    }
    return ,$found
}

# True if LaunchBox or BigBox is currently running. The direct LaunchBox
# integration must never write to Data\ files while LaunchBox has them
# open -- that's the same risk Export-LaunchBoxXml's header comment has
# always called out for the manual-import path, just enforced here instead
# of left to the user to remember.
function Test-LaunchBoxRunning {
    $proc = Get-Process -Name "LaunchBox", "BigBox" -ErrorAction SilentlyContinue
    return ($null -ne $proc)
}

# PowerShell 5.1 runs on .NET Framework, which has no [Path]::GetRelativePath
# (that's .NET Core-only) -- this is the standard Uri-based equivalent.
# Both inputs must be absolute; returns a backslash-separated relative path.
function Get-RelativePath {
    param([string]$basePath, [string]$targetPath)
    $baseFull = [System.IO.Path]::GetFullPath($basePath).TrimEnd('\', '/') + '\'
    $targetFull = [System.IO.Path]::GetFullPath($targetPath)
    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relUri = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relUri.ToString()).Replace('/', '\')
}

# =============================================================================
# FUZZY FOLDER-NAME MATCHING  (Feature: NESiCAxLive / shared-exe games)
# =============================================================================
#
# Many platforms (NESiCAxLive, NESiCA, Sega RingEdge 2, etc.) share a single
# executable name (e.g. "game.exe") across dozens of titles. The script cannot
# distinguish them by exe name alone. This block lets it match the FOLDER NAME
# (e.g. "Akai Katana Shin (2012)[Taito NESiCAxLive][TP]") against the profile
# code (e.g. "AkaiKatanaShinNesica") using normalised bigram similarity.
#
# Games above $FuzzyAutoThreshold are registered automatically.
# Games below the threshold appear in ACTION REQUIRED with the best-guess
# profile shown so manual registration is easier.

# Normalises a game name or profile code for fuzzy comparison. Strips years,
# bracketed and parenthesised metadata, non-alphanumeric characters, and
# lowercases the result. Also splits CamelCase profile codes into separate
# tokens so "AkaiKatanaShin" and "Akai Katana Shin" converge to the same form.
function Get-NormalizedGameKey {
    param([string]$s)
    # CamelCase split, two passes:
    #  Pass 1 -- standard boundary: lowercase -> uppercase ("AkaiKatana" -> "Akai Katana")
    $s = [regex]::Replace($s, '(?<=[a-z])(?=[A-Z])', ' ')
    #  Pass 2 -- acronym boundary: uppercase -> uppercase+lowercase ("NBANesica" -> "NBA Nesica")
    #  This handles profile codes that begin with an acronym followed by a word.
    $s = [regex]::Replace($s, '(?<=[A-Z])(?=[A-Z][a-z])', ' ')
    #  Known edge case: brand names with non-standard capitalisation like "NESiCAxLive"
    #  split as "NESi CAx Live" on pass 1 (i->C boundary). This does not affect match
    #  accuracy because (a) both folder name and profile code go through the same
    #  normalisation so Dice scores converge symmetrically, and (b) "NESiCAxLive"
    #  appears in square-bracket metadata ([Taito NESiCAxLive]) which is stripped
    #  by the bracket removal step BEFORE this function runs.
    # Remove year-in-parens like (2012)
    $s = $s -replace '\(\d{4}\)', ''
    # Remove square-bracket metadata [Taito NESiCAxLive][TP]
    $s = $s -replace '\[[^\]]*\]', ''
    # Remove full ISO date strings like (2015-12-28) (2007-02-15) used in Eggman dat names.
    # Must run before the decimal-version strip so (2015-12-28) is removed as a whole.
    $s = $s -replace '\(\d{4}-\d{2}-\d{2}\)', ''
    # Remove decimal version strings without ver/v prefix: (2.10.00) (1.00.48)
    $s = $s -replace '\(\d+\.\d[\d\.]*\)', ''
    # Remove known region/territory codes used in Eggman dat names.
    # Explicit list avoids accidentally stripping Roman numerals (II, III) or
    # meaningful abbreviations (SE) that could appear in game titles.
    $s = $s -replace '\((JPN|USA|EUR|EXP|JP|US|KOR|AUS|ASI|INTL|ARC|UNK)\)', ''
    # Remove version strings like (ver 1.1) (rev 2) (v3) (v1.2b).
    # Meaningful parenthesised names such as (Special Edition) are intentionally
    # preserved -- they may be the only differentiator between two game titles.
    $s = $s -replace '\((ver\.?|rev\.?|v)\s*[\d\.]+[a-z]?\)', ''
    # Remove parenthesised pure numbers like (2) (12) that carry no game-name info.
    $s = $s -replace '\(\d+\)', ''
    # Strip everything non-alphanumeric (spaces, hyphens, apostrophes, colons...).
    # \p{L} matches any Unicode letter so accented and non-Latin characters are
    # preserved instead of being silently dropped, keeping Dice scores valid.
    $s = $s -replace '[^\p{L}0-9]', ''
    return $s.ToLower()
}

# Sorensen-Dice coefficient on character bigrams for two pre-normalised strings.
# Returns [0.0, 1.0]. Strings shorter than 2 chars cannot form bigrams -> 0.0.
function Get-DiceSimilarity {
    param([string]$a, [string]$b)
    if ($a.Length -lt 2 -or $b.Length -lt 2) { return 0.0 }
    $ba = @{}
    for ($i = 0; $i -lt $a.Length - 1; $i++) {
        $k = $a.Substring($i, 2)
        $ba[$k] = ($ba[$k] -as [int]) + 1   # -as [int]: null (missing key) becomes 0
    }
    $bb = @{}
    for ($i = 0; $i -lt $b.Length - 1; $i++) {
        $k = $b.Substring($i, 2)
        $bb[$k] = ($bb[$k] -as [int]) + 1
    }
    $inter = 0
    foreach ($k in $ba.Keys) { if ($bb.ContainsKey($k)) { $inter += [Math]::Min($ba[$k], $bb[$k]) } }
    $totalA = 0; foreach ($v in $ba.Values) { $totalA += $v }
    $totalB = 0; foreach ($v in $bb.Values) { $totalB += $v }
    if (($totalA + $totalB) -eq 0) { return 0.0 }
    return [double](2 * $inter) / ($totalA + $totalB)
}

# Minimum Dice similarity required to auto-register a fuzzy match. Anything at
# or above this score is registered automatically; anything below appears in
# ACTION REQUIRED with the best-guess profile name shown.
$FuzzyAutoThreshold = 0.72

# Minimum score gap required between the best and runner-up candidate for the
# best one to be trusted as an auto-register decision. Without this, two
# different profiles that both happen to score at or above
# $FuzzyAutoThreshold against the same folder name were resolved purely by
# which one the candidate loop iterated to last -- no actual signal preferred
# one over the other. Set to 0.1 (not a tighter value like 0.05) because the
# audit's own real near-miss example -- a folder one character off from the
# real title vs. one character over -- produced a gap of ~0.083, which a
# tighter margin would not have caught. See issue #15.
$FuzzyTieMargin = 0.1

# Resolves the best fuzzy-match candidate for $NormFolder among $MatchList
# (profiles that share one generic executable name, e.g. "game.exe"),
# applying the $RawThrillsAliases short-name fallback the same way the
# original inline Register-Games loop did. Tracks the runner-up score too, so
# a near-tie at/above $FuzzyAutoThreshold can be told apart from a clear,
# unambiguous winner -- IsConfidentMatch is false for both "below threshold"
# and "too close to call", and the caller already has a safe fallback path
# (dat lookup, then manual-registration ACTION REQUIRED) for both. See
# issue #15.
function Resolve-BestFuzzyMatch {
    param([string]$NormFolder, [array]$MatchList, [hashtable]$RawThrillsAliases)
    $best = $null; $bestScore = 0.0; $secondScore = 0.0
    foreach ($cand in $MatchList) {
        $normCode = Get-NormalizedGameKey $cand.Code
        $score    = Get-DiceSimilarity $NormFolder $normCode
        if ($RawThrillsAliases.ContainsKey($cand.Code)) {
            $normAlias  = Get-NormalizedGameKey $RawThrillsAliases[$cand.Code].Suggested
            $aliasScore = Get-DiceSimilarity $NormFolder $normAlias
            if ($aliasScore -gt $score) { $score = $aliasScore }
        }
        if ($score -gt $bestScore) {
            $secondScore = $bestScore
            $bestScore   = $score
            $best        = $cand
        } elseif ($score -gt $secondScore) {
            $secondScore = $score
        }
    }
    $isTie = ($secondScore -gt 0) -and (($bestScore - $secondScore) -lt $FuzzyTieMargin)
    return [pscustomobject]@{
        Best             = $best
        BestScore        = $bestScore
        SecondScore      = $secondScore
        IsConfidentMatch = ($null -ne $best) -and ($bestScore -ge $FuzzyAutoThreshold) -and -not $isTie
    }
}

# Scans $folder recursively for files that TeknoParrot profiles use as their
# primary executable. This includes Windows EXE, Linux ELF, disc images (.iso,
# .gcm, .gcz), binary containers (.bin, .zip, .e4), Xbox binaries (.xbe for
# Sega Chihiro via cxbxr), Konami game DLLs (.dll), and extension-less Linux
# binaries (e.g. "game", "armyops-bin", "abc").
#
# Extension-less files are limited to 6 directory levels below $folder.
# Linux game executables are always at that depth or shallower; system files
# buried inside Lindbergh / Chihiro Linux filesystem images (e.g. X11 keyboard
# layout files like "tr") live 7-10 levels deep and are excluded by this limit.
# .dll files are included because some Konami arcade games (DDR, Steel Chronicle,
# Silent Scope, etc.) specify a game-specific DLL as their ExecutableName.
function Get-GameFiles {
    param([string]$folder)
    $exts       = @('.exe', '.elf', '.iso', '.gcm', '.gcz', '.bin', '.e4', '.zip', '.xbe', '.dll')
    $normalized = $folder -replace '/', '\'
    $baseDepth  = $normalized.TrimEnd('\').Split('\').Count
    return @(Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object {
                     $ext = $_.Extension.ToLower()
                     if ($exts -contains $ext) { return $true }
                     if ($ext -eq '') {
                         # Extension-less Linux binaries: allow up to 6 levels below the
                         # games root. Some Lindbergh titles place executables 5-6 levels
                         # deep inside their filesystem image. System files (X11 layouts,
                         # shared libraries, etc.) live 7-10 levels deep and are excluded.
                         $normFull = $_.FullName -replace '/', '\'
                         return ($normFull.Split('\').Count - $baseDepth) -le 6
                     }
                     return $false
                 })
}

# Parses a number/range string (e.g. "1,3,5-7") into a sorted list of integers
# bounded to [1, $max]. Handles reversed ranges (e.g. "7-3" is treated as "3-7").
# Warns and returns empty if the string contains characters outside the valid set
# of digits, commas, hyphens, and whitespace -- this catches accidental letter
# commands (e.g. typing "N" where a number was expected).
function Expand-NumberList {
    param([string]$str, [int]$max)   # $str avoids shadowing the $input automatic variable
    $out = [System.Collections.Generic.List[int]]::new()

    # Short-circuit on empty or whitespace-only input -- nothing to parse.
    if ([string]::IsNullOrWhiteSpace($str)) { return ,@($out) }

    # Validate: anything other than digits, commas, hyphens, and whitespace is
    # not a valid number/range expression and almost certainly a typo.
    if ($str -match '[^0-9,\s\-]') {
        Write-Host ("  NOTE: '{0}' is not a valid selection -- use digits, commas, and hyphens only (e.g. 1,3,5-7)." -f $str) -ForegroundColor Yellow
        return ,@($out)
    }

    foreach ($part in ($str -split ',')) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            # Guard against overflow: int32 max is 2,147,483,647 (10 digits).
            if ($Matches[1].Length -gt 9 -or $Matches[2].Length -gt 9) { continue }
            $from = [int]$Matches[1]; $to = [int]$Matches[2]
            if ($from -gt $to) { $tmp = $from; $from = $to; $to = $tmp }   # handle "7-3"
            $to = [Math]::Min($to, $max)   # clamp upper bound before looping
            for ($n = $from; $n -le $to; $n++) { if ($n -ge 1) { [void]$out.Add($n) } }
        } elseif ($part -match '^\d+$') {
            if ($part.Length -gt 9) { continue }   # overflow guard
            $n = [int]$part
            if ($n -ge 1 -and $n -le $max) { [void]$out.Add($n) }
        }
    }
    return ,@($out)
}

# Interactive game picker. Shows a menu with four modes:
#   A (All)    -- extract everything, no filter
#   L (Browse) -- paginated A-Z list, N/P to page, pick by number
#   S (Search) -- keyword filter, pick by number from results
#   D (Done)   -- finish and proceed with the current queue
# Browse and Search both feed into the same queue. Returns:
#   $null   -- D pressed with no games selected (skip extraction)
#   @()     -- A pressed; no filter (extract all)
#   @(...)  -- explicit whitelist of ZIP BaseName strings
function Select-GamesInteractive {
    param([string]$zipSource, [string]$installFolder, [hashtable]$datIndex = $null, [string]$userProfilesDir = '')

    if ([string]::IsNullOrWhiteSpace($zipSource) -or [string]::IsNullOrWhiteSpace($installFolder)) {
        Write-Log "Select-GamesInteractive: called with empty path -- skipping"
        return $null
    }
    $all = @(Get-ChildItem -LiteralPath $zipSource -Filter *.zip -ErrorAction SilentlyContinue |
                 Where-Object { $_.BaseName -notlike '!TeknoParrot Collection*' } |
                 Sort-Object BaseName)

    if ($all.Count -eq 0) {
        Write-Host "  No game ZIPs found in source folder." -ForegroundColor Yellow
        $subdirHits = @(Get-ChildItem -LiteralPath $zipSource -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $c = (Get-ChildItem -LiteralPath $_.FullName -Filter *.zip -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($c -gt 0) { [PSCustomObject]@{ Path = $_.FullName; Count = $c } }
        })
        if ($subdirHits.Count -gt 0) {
            Write-Host "  Tip: ZIPs found one level down -- point the source path at one of these directly:" -ForegroundColor Cyan
            foreach ($sd in $subdirHits) {
                Write-Host "    $($sd.Path)  ($($sd.Count) ZIPs)" -ForegroundColor DarkCyan
            }
        }
        return ,@()   # comma forces real array semantics -- a bare "return @()" is
                      # unwrapped to $null by the pipeline, which the caller cannot
                      # then distinguish from its own "user skipped" $null case
    }

    # Build a normalised folder map of what is already extracted in the
    # destination, using the same convention-agnostic logic as AutoSync.
    $normalizedFolderMap = Get-StagingFolderMap $installFolder

    # Split the ZIP list into already-extracted (non-empty folder exists) and
    # not-yet-extracted. The picker only shows the not-yet-extracted ones.
    $alreadyExtracted = @()
    $toExtract        = @()
    foreach ($zip in $all) {
        $norm         = $zip.BaseName -replace ' (?=[\[\(])', ''
        $existingPath = $normalizedFolderMap[$norm]
        if (-not $existingPath) { $existingPath = Resolve-RegisteredGameFolder $zip.BaseName $datIndex $userProfilesDir }
        $hasContent   = $existingPath -and
                        (Get-ChildItem -LiteralPath $existingPath -Force -ErrorAction SilentlyContinue |
                         Measure-Object).Count -gt 0
        if ($hasContent) { $alreadyExtracted += $zip } else { $toExtract += $zip }
    }

    Write-Host ""
    if ($alreadyExtracted.Count -gt 0) {
        Write-Host ("  {0} game(s) already extracted -- not shown." -f $alreadyExtracted.Count) -ForegroundColor DarkGray
    }
    if ($toExtract.Count -eq 0) {
        Write-Host "  All games are already extracted. Nothing left to do." -ForegroundColor Green
        return ,@()
    }
    Write-Host ("  {0} game(s) available to extract." -f $toExtract.Count) -ForegroundColor Cyan

    $all      = $toExtract   # picker operates only on unextracted games from here on
    $queue    = @()
    $pageSize = 20
    $done     = $false

    while (-not $done) {
        Write-Host ""
        Write-Host "  ============================================" -ForegroundColor Cyan
        $qLabel = if ($queue.Count -gt 0) { "  Queue: $($queue.Count) game(s) selected" } else { "  Queue: empty" }
        Write-Host $qLabel -ForegroundColor Cyan
        Write-Host "  ============================================" -ForegroundColor Cyan
        Write-Host "    A) All unextracted games ($($all.Count))"
        Write-Host "    L) Browse and select from list ($($all.Count) games, A-Z)"
        Write-Host "    S) Search by keyword"
        Write-Host "    D) Done -- proceed with current queue"
        Write-Host ""
        $choice = (Read-Host "  Enter A, L, S, or D").Trim().ToUpper()

        # -- ALL GAMES -------------------------------------------------------
        if ($choice -eq 'A') {
            Write-Host ""
            Write-Host "  All $($all.Count) unextracted game(s) will be extracted." -ForegroundColor Green
            return ,@()   # empty = no whitelist = extract everything; comma forces
                          # real array semantics so the caller's $null-vs-empty
                          # check doesn't see this as "nothing selected"
        }

        # -- BROWSE ----------------------------------------------------------
        elseif ($choice -eq 'L') {
            $page       = 0
            $totalPages = [Math]::Ceiling($all.Count / $pageSize)
            $browsing   = $true

            while ($browsing) {
                $start     = $page * $pageSize
                $end       = [Math]::Min($start + $pageSize - 1, $all.Count - 1)
                $pageItems = if ($start -gt $end) { @() } else { @($all[$start..$end]) }

                Write-Host ""
                Write-Host ("  Page {0} of {1}  ({2} games total)" -f ($page+1), $totalPages, $all.Count) -ForegroundColor Cyan
                Write-Host "  (* = already in queue)" -ForegroundColor DarkCyan
                Write-Host ""
                for ($i = 0; $i -lt $pageItems.Count; $i++) {
                    $marker = if ($queue -contains $pageItems[$i].BaseName) { "*" } else { " " }
                    $num    = ($i + 1).ToString().PadLeft(3)
                    Write-Host "  [$marker$num] $($pageItems[$i].BaseName)"
                }
                Write-Host ""
                Write-Host "  Numbers (e.g. 1,3,5-7)  |  N = next  |  P = prev  |  B = back to menu  |  D = done" -ForegroundColor DarkCyan
                Write-Host ""
                $cmd = (Read-Host "  >").Trim().ToUpper()

                if ($cmd -eq 'B') {
                    $browsing = $false
                } elseif ($cmd -eq 'D') {
                    $browsing = $false
                    $done     = $true
                } elseif ($cmd -eq 'N') {
                    if ($page -lt $totalPages - 1) { $page++ } else { Write-Host "  Already on last page." -ForegroundColor DarkCyan }
                } elseif ($cmd -eq 'P') {
                    if ($page -gt 0) { $page-- } else { Write-Host "  Already on first page." -ForegroundColor DarkCyan }
                } elseif ($cmd -ne '') {
                    $nums  = Expand-NumberList -str $cmd -max $pageItems.Count
                    $added = 0
                    foreach ($n in $nums) {
                        $name = $pageItems[$n - 1].BaseName
                        if ($queue -notcontains $name) { $queue += $name; $added++ }
                    }
                    if ($nums.Count -gt 0) {
                        Write-Host ("  Added {0} game(s). Queue: {1} total." -f $added, $queue.Count) -ForegroundColor Cyan
                    }
                }
            }
        }

        # -- SEARCH ----------------------------------------------------------
        elseif ($choice -eq 'S') {
            $searching = $true
            while ($searching) {
                Write-Host ""
                $term = (Read-Host "  Search keyword (or 'back' / 'done')").Trim()
                if ($term -ieq 'back') { $searching = $false; continue }
                if ($term -ieq 'done') { $searching = $false; $done = $true; continue }
                if (-not $term) { continue }

                $results = @($all | Where-Object { $_.BaseName.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
                if ($results.Count -eq 0) {
                    Write-Host "  No matches for '$term'." -ForegroundColor Yellow
                    continue
                }

                $maxShow = 40
                $shown   = [Math]::Min($results.Count, $maxShow)
                Write-Host ""
                Write-Host ("  {0} match(es) for '{1}'{2}:" -f $results.Count, $term,
                    $(if ($results.Count -gt $maxShow) { " (showing first $maxShow)" } else { "" })) -ForegroundColor Cyan
                Write-Host "  (* = already in queue)" -ForegroundColor DarkCyan
                Write-Host ""
                for ($i = 0; $i -lt $shown; $i++) {
                    $marker = if ($queue -contains $results[$i].BaseName) { "*" } else { " " }
                    $num    = ($i + 1).ToString().PadLeft(3)
                    Write-Host "  [$marker$num] $($results[$i].BaseName)"
                }
                if ($results.Count -gt $maxShow) {
                    Write-Host "  ... narrow your search to see more." -ForegroundColor DarkCyan
                }
                Write-Host ""
                $pick = (Read-Host "  Numbers to select (or Enter to search again)").Trim()
                if (-not $pick) { continue }

                $nums  = Expand-NumberList -str $pick -max $shown
                $added = 0
                foreach ($n in $nums) {
                    $name = $results[$n - 1].BaseName
                    if ($queue -notcontains $name) { $queue += $name; $added++ }
                }
                if ($nums.Count -gt 0) {
                    Write-Host ("  Added {0} game(s). Queue: {1} total." -f $added, $queue.Count) -ForegroundColor Cyan
                }
            }
        }

        # -- DONE ------------------------------------------------------------
        elseif ($choice -eq 'D') {
            $done = $true
        }
    }

    if ($queue.Count -gt 0) {
        Write-Host ""
        Write-Host "  Final queue ($($queue.Count) game(s)):" -ForegroundColor Green
        foreach ($g in $queue) { Write-Host "    + $g" -ForegroundColor Green }
        return ,$queue
    }
    Write-Host "  No games selected." -ForegroundColor Yellow
    return $null   # $null = skip this source; @() (from A) = no filter = extract all
}

# Combined game picker for AutoSync when both main and supplementary sources are configured.
# Scans both ZIP sources, merges the unextracted lists into one sorted display, and lets the
# user select from either library in a single A/L/S/D session. Supplementary entries are
# marked [+] so the user can tell the two libraries apart at a glance.
# Returns a PSCustomObject { Main; Supp }. Each property is:
#   $null   -- skip that source (D pressed with nothing selected for it)
#   @()     -- no filter; extract all (A pressed)
#   @(...)  -- explicit whitelist of ZIP BaseName strings to extract
function Select-GamesInteractiveCombined {
    param([string]$zipSourceMain, [string]$zipSourceSupp, [string]$installFolder, [hashtable]$datIndex = $null, [string]$userProfilesDir = '')

    if ([string]::IsNullOrWhiteSpace($zipSourceMain) -or [string]::IsNullOrWhiteSpace($zipSourceSupp) -or [string]::IsNullOrWhiteSpace($installFolder)) {
        Write-Log "Select-GamesInteractiveCombined: called with empty path -- skipping"
        return [PSCustomObject]@{ Main = $null; Supp = $null }
    }
    $allMain = @(Get-ChildItem -LiteralPath $zipSourceMain -Filter *.zip -ErrorAction SilentlyContinue |
                     Where-Object { $_.BaseName -notlike '!TeknoParrot Collection*' } |
                     Sort-Object BaseName)
    $allSupp = @(Get-ChildItem -LiteralPath $zipSourceSupp -Filter *.zip -ErrorAction SilentlyContinue |
                     Where-Object { $_.BaseName -notlike '!TeknoParrot Collection*' } |
                     Sort-Object BaseName)

    $normalizedFolderMap = Get-StagingFolderMap $installFolder

    # Split each source into already-extracted and available. Track which source owns each entry.
    $sourceMap   = @{}
    $alreadyMain = 0; $alreadySupp = 0
    $toExtractMain = @(); $toExtractSupp = @()

    foreach ($zip in $allMain) {
        $norm       = $zip.BaseName -replace ' (?=[\[\(])', ''
        $existing   = $normalizedFolderMap[$norm]
        if (-not $existing) { $existing = Resolve-RegisteredGameFolder $zip.BaseName $datIndex $userProfilesDir }
        $hasContent = $existing -and (Get-ChildItem -LiteralPath $existing -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
        if ($hasContent) { $alreadyMain++ } else { $toExtractMain += $zip; $sourceMap[$zip.BaseName] = 'Main' }
    }
    # Supp iterates after Main -- if the same BaseName appears in both sources,
    # 'Supp' overwrites 'Main' in $sourceMap (supplementary takes precedence).
    foreach ($zip in $allSupp) {
        $norm       = $zip.BaseName -replace ' (?=[\[\(])', ''
        $existing   = $normalizedFolderMap[$norm]
        if (-not $existing) { $existing = Resolve-RegisteredGameFolder $zip.BaseName $datIndex $userProfilesDir }
        $hasContent = $existing -and (Get-ChildItem -LiteralPath $existing -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
        if ($hasContent) { $alreadySupp++ } else { $toExtractSupp += $zip; $sourceMap[$zip.BaseName] = 'Supp' }
    }

    $all = @($toExtractMain + $toExtractSupp | Sort-Object BaseName)

    Write-Host ""
    if (($alreadyMain + $alreadySupp) -gt 0) {
        Write-Host ("  {0} game(s) already extracted -- not shown." -f ($alreadyMain + $alreadySupp)) -ForegroundColor DarkGray
    }
    if ($all.Count -eq 0) {
        Write-Host "  All games are already extracted. Nothing left to do." -ForegroundColor Green
        return [PSCustomObject]@{ Main = @(); Supp = @() }
    }
    Write-Host ("  {0} game(s) available to extract ({1} collection, {2} supplementary [+])." -f $all.Count, $toExtractMain.Count, $toExtractSupp.Count) -ForegroundColor Cyan

    $queue    = @()
    $pageSize = 20
    $done     = $false

    while (-not $done) {
        Write-Host ""
        Write-Host "  ============================================" -ForegroundColor Cyan
        Write-Host $(if ($queue.Count -gt 0) { "  Queue: $($queue.Count) game(s) selected" } else { "  Queue: empty" }) -ForegroundColor Cyan
        Write-Host "  ============================================" -ForegroundColor Cyan
        Write-Host "    A) All unextracted games ($($all.Count))"
        Write-Host "    L) Browse and select from list ($($all.Count) games, A-Z)"
        Write-Host "    S) Search by keyword"
        Write-Host "    D) Done -- proceed with current queue"
        Write-Host ""
        $choice = (Read-Host "  Enter A, L, S, or D").Trim().ToUpper()

        if ($choice -eq 'A') {
            Write-Host ""
            Write-Host "  All $($all.Count) unextracted game(s) will be extracted." -ForegroundColor Green
            return [PSCustomObject]@{ Main = @(); Supp = @() }
        }
        elseif ($choice -eq 'L') {
            $page       = 0
            $totalPages = [Math]::Ceiling($all.Count / $pageSize)
            $browsing   = $true
            while ($browsing) {
                $start     = $page * $pageSize
                $end       = [Math]::Min($start + $pageSize - 1, $all.Count - 1)
                $pageItems = if ($start -gt $end) { @() } else { @($all[$start..$end]) }
                Write-Host ""
                Write-Host ("  Page {0} of {1}  ({2} games total)" -f ($page+1), $totalPages, $all.Count) -ForegroundColor Cyan
                Write-Host "  (* = in queue | [+] = supplementary)" -ForegroundColor DarkCyan
                Write-Host ""
                for ($i = 0; $i -lt $pageItems.Count; $i++) {
                    $inQ = if ($queue -contains $pageItems[$i].BaseName) { "*" } else { " " }
                    $src = if ($sourceMap[$pageItems[$i].BaseName] -eq 'Supp') { "[+]" } else { "   " }
                    Write-Host ("  [{0}{1}] {2} {3}" -f $inQ, ($i+1).ToString().PadLeft(3), $src, $pageItems[$i].BaseName)
                }
                Write-Host ""
                Write-Host "  Numbers (e.g. 1,3,5-7)  |  N=next  P=prev  B=back  D=done" -ForegroundColor DarkCyan
                Write-Host ""
                $cmd = (Read-Host "  >").Trim().ToUpper()
                if     ($cmd -eq 'B') { $browsing = $false }
                elseif ($cmd -eq 'D') { $browsing = $false; $done = $true }
                elseif ($cmd -eq 'N') { if ($page -lt $totalPages-1) { $page++ } else { Write-Host "  Already on last page." -ForegroundColor DarkCyan } }
                elseif ($cmd -eq 'P') { if ($page -gt 0) { $page-- } else { Write-Host "  Already on first page." -ForegroundColor DarkCyan } }
                elseif ($cmd -ne '') {
                    $nums = Expand-NumberList -str $cmd -max $pageItems.Count
                    $added = 0
                    foreach ($n in $nums) {
                        $name = $pageItems[$n-1].BaseName
                        if ($queue -notcontains $name) { $queue += $name; $added++ }
                    }
                    if ($nums.Count -gt 0) { Write-Host ("  Added {0} game(s). Queue: {1} total." -f $added, $queue.Count) -ForegroundColor Cyan }
                }
            }
        }
        elseif ($choice -eq 'S') {
            $searching = $true
            while ($searching) {
                Write-Host ""
                $term = (Read-Host "  Search keyword (or 'back' / 'done')").Trim()
                if ($term -ieq 'back') { $searching = $false; continue }
                if ($term -ieq 'done') { $searching = $false; $done = $true; continue }
                if (-not $term) { continue }
                $results = @($all | Where-Object { $_.BaseName.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
                if ($results.Count -eq 0) { Write-Host "  No matches for '$term'." -ForegroundColor Yellow; continue }
                $maxShow = 40
                $shown   = [Math]::Min($results.Count, $maxShow)
                Write-Host ""
                Write-Host ("  {0} match(es) for '{1}'{2}:" -f $results.Count, $term,
                    $(if ($results.Count -gt $maxShow) { " (showing first $maxShow)" } else { "" })) -ForegroundColor Cyan
                Write-Host "  (* = in queue | [+] = supplementary)" -ForegroundColor DarkCyan
                Write-Host ""
                for ($i = 0; $i -lt $shown; $i++) {
                    $inQ = if ($queue -contains $results[$i].BaseName) { "*" } else { " " }
                    $src = if ($sourceMap[$results[$i].BaseName] -eq 'Supp') { "[+]" } else { "   " }
                    Write-Host ("  [{0}{1}] {2} {3}" -f $inQ, ($i+1).ToString().PadLeft(3), $src, $results[$i].BaseName)
                }
                if ($results.Count -gt $maxShow) { Write-Host "  ... narrow your search to see more." -ForegroundColor DarkCyan }
                Write-Host ""
                $pick = (Read-Host "  Numbers to select (or Enter to search again)").Trim()
                if (-not $pick) { continue }
                $nums  = Expand-NumberList -str $pick -max $shown
                $added = 0
                foreach ($n in $nums) {
                    $name = $results[$n-1].BaseName
                    if ($queue -notcontains $name) { $queue += $name; $added++ }
                }
                if ($nums.Count -gt 0) { Write-Host ("  Added {0} game(s). Queue: {1} total." -f $added, $queue.Count) -ForegroundColor Cyan }
            }
        }
        elseif ($choice -eq 'D') {
            $done = $true
        }
    }

    if ($queue.Count -gt 0) {
        Write-Host ""
        Write-Host "  Final queue ($($queue.Count) game(s)):" -ForegroundColor Green
        foreach ($g in $queue) {
            $tag = if ($sourceMap[$g] -eq 'Supp') { "[+] " } else { "" }
            Write-Host "    + $tag$g" -ForegroundColor Green
        }
    } else {
        Write-Host "  No games selected." -ForegroundColor Yellow
    }

    $qMain = @($queue | Where-Object { $sourceMap[$_] -ne 'Supp' })
    $qSupp = @($queue | Where-Object { $sourceMap[$_] -eq  'Supp' })
    # $null = skip that source (D with no selection); @() = no filter = all (from A only).
    return [PSCustomObject]@{
        Main = if ($qMain.Count -gt 0) { $qMain } else { $null }
        Supp = if ($qSupp.Count -gt 0) { $qSupp } else { $null }
    }
}

# =============================================================================
# CROSSHAIR MANAGEMENT
# =============================================================================
# Scans the Crosshairs subfolder (next to the script) for valid PNG files,
# generates an HTML preview the user can browse in a browser, then lets them
# pick P1 and P2 by index number before deploying to every registered lightgun
# game. Lightgun games are identified by <GunGame>true</GunGame> in their
# UserProfile XML. ElfLdr2 games share a single folder in the TeknoParrot root;
# all others receive P1.png / P2.png in the individual game exe directory.

# Returns true if $Path begins with the PNG magic bytes (89 50 4E 47 0D 0A 1A 0A).
function Test-PngFile {
    param([string]$Path)
    try {
        $bytes = New-Object byte[] 8
        $fs    = [System.IO.File]::OpenRead($Path)
        try {
            $pos = 0
            while ($pos -lt 8) {
                $n = $fs.Read($bytes, $pos, 8 - $pos)
                if ($n -eq 0) { break }
                $pos += $n
            }
        } finally { $fs.Dispose() }
        return ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and
                $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47 -and
                $bytes[4] -eq 0x0D -and $bytes[5] -eq 0x0A -and
                $bytes[6] -eq 0x1A -and $bytes[7] -eq 0x0A)
    } catch { return $false }
}

# Writes an HTML grid preview of all crosshairs to $OutPath.
# Images are referenced as relative paths so the file works anywhere on the
# same machine without embedding base64.
function Export-CrosshairPreview {
    param([string[]]$CrosshairPaths, [string]$OutPath)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">')
    [void]$sb.Append('<title>TeknoParrot Crosshairs</title><style>')
    [void]$sb.Append('body{background:#111;color:#eee;font-family:monospace;padding:16px;margin:0}')
    [void]$sb.Append('h1{color:#4af;margin-bottom:4px}p{color:#888;margin-top:0;margin-bottom:16px}')
    [void]$sb.Append('.grid{display:flex;flex-wrap:wrap;gap:8px}')
    [void]$sb.Append('.cell{background:#222;border:1px solid #333;padding:6px;text-align:center;width:84px}')
    [void]$sb.Append('.cell:hover{border-color:#4af;background:#1a2a3a}')
    [void]$sb.Append('.cell img{width:64px;height:64px;image-rendering:pixelated;display:block;margin:0 auto 4px}')
    [void]$sb.Append('.num{color:#4af;font-size:12px}.name{color:#888;font-size:10px;word-break:break-all}')
    [void]$sb.Append('</style></head><body>')
    [void]$sb.Append('<h1>TeknoParrot Crosshairs</h1>')
    [void]$sb.Append('<p>Browse below, then enter the <span style="color:#4af">index number</span> in the script to select P1 and P2.</p>')
    [void]$sb.Append('<div class="grid">')

    $i = 0
    foreach ($path in $CrosshairPaths) {
        $fname    = [System.IO.Path]::GetFileName($path)
        $stem     = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $rel      = 'Crosshairs/' + [System.Net.WebUtility]::HtmlEncode($fname)
        $stemHtml = [System.Net.WebUtility]::HtmlEncode($stem)
        [void]$sb.Append("<div class=`"cell`"><img src=`"$rel`" alt=`"$stemHtml`">")
        [void]$sb.Append("<div class=`"num`">$i</div><div class=`"name`">$stemHtml</div></div>")
        $i++
    }

    [void]$sb.Append('</div></body></html>')
    [System.IO.File]::WriteAllText($OutPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
}

# =============================================================================
# RESHADE HELPER FUNCTIONS
# =============================================================================

# Scans the first 2 MB of a game exe for graphics API imports.
# Returns the ReShade DLL name to deploy (e.g. "dxgi.dll"), or $null.
function Get-GameApiDll {
    param([string]$ExePath)
    try {
        $readLen = [int][Math]::Min((Get-Item -LiteralPath $ExePath).Length, 2097152)
        $buf     = New-Object byte[] $readLen
        $fs      = [System.IO.File]::OpenRead($ExePath)
        try {
            $pos = 0
            while ($pos -lt $readLen) {
                $n = $fs.Read($buf, $pos, $readLen - $pos)
                if ($n -eq 0) { break }
                $pos += $n
            }
        } finally { $fs.Dispose() }
        $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $pos)
        # D3D12 checked first: a title that imports both d3d11 and d3d12 (e.g. UWP-wrapped)
        # should be hooked at the outer DX12 layer, not the inner DX11 layer.
        if ($text -match '(?i)d3d12\.dll')          { return 'd3d12.dll'    }
        if ($text -match '(?i)(?:d3d11|dxgi)\.dll') { return 'dxgi.dll'     }
        if ($text -match '(?i)d3d9\.dll')            { return 'd3d9.dll'     }
        if ($text -match '(?i)opengl32\.dll')        { return 'opengl32.dll' }
        return $null
    } catch { return $null }
}

# Reads the PE Optional Header to determine whether an exe is 32-bit or 64-bit.
# Returns 'x86', 'x64', or $null on error or unrecognised format.
function Get-ExeArchitecture {
    param([string]$ExePath)
    try {
        $fs  = [System.IO.File]::OpenRead($ExePath)
        $buf = New-Object byte[] 4
        try {
            # Read 2-byte MZ signature; use a loop to guard against short reads.
            $pos = 0
            while ($pos -lt 2) {
                $n = $fs.Read($buf, $pos, 2 - $pos)
                if ($n -eq 0) { return $null }
                $pos += $n
            }
            if ($buf[0] -ne 0x4D -or $buf[1] -ne 0x5A) { return $null }
            # Read 4-byte PE header offset at 0x3C.
            [void]$fs.Seek(0x3C, [System.IO.SeekOrigin]::Begin)
            $pos = 0
            while ($pos -lt 4) {
                $n = $fs.Read($buf, $pos, 4 - $pos)
                if ($n -eq 0) { return $null }
                $pos += $n
            }
            $peOffset = [System.BitConverter]::ToInt32($buf, 0)
            # Machine word sits 4 bytes into the PE header (after the 'PE\0\0' signature).
            [void]$fs.Seek($peOffset + 4, [System.IO.SeekOrigin]::Begin)
            $pos = 0
            while ($pos -lt 2) {
                $n = $fs.Read($buf, $pos, 2 - $pos)
                if ($n -eq 0) { return $null }
                $pos += $n
            }
            $machine = [System.BitConverter]::ToUInt16($buf, 0)
            if ($machine -eq 0x014C) { return 'x86' }
            if ($machine -eq 0x8664) { return 'x64' }
            return $null
        } finally { $fs.Dispose() }
    } catch { return $null }
}

# Paginated picker over registered UserProfile XMLs.
# Returns an array of FileInfo objects for the user's selection.
function Select-RegisteredGamesInteractive {
    param([string]$UserProfilesDir)
    $fullBackupDir = Join-Path $UserProfilesDir "FullBackup"
    $profiles = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.DirectoryName -ne $fullBackupDir } |
                  Sort-Object BaseName)
    if ($profiles.Count -eq 0) {
        Write-Host "  No registered games found in UserProfiles." -ForegroundColor Yellow
        return ,@()
    }
    Write-Host ""
    Write-Host "    A) All $($profiles.Count) registered game(s)" -ForegroundColor White
    Write-Host "    L) Browse and select specific games" -ForegroundColor White
    Write-Host ""
    $pick = (Read-Host "    Enter A or L").Trim().ToUpper()
    if ($pick -eq "A") { return $profiles }

    $pageSize = 20
    $pages    = [Math]::Ceiling($profiles.Count / $pageSize)
    $page     = 0
    $selected = [System.Collections.Generic.List[object]]::new()
    while ($true) {
        $start = $page * $pageSize
        $end   = [Math]::Min($start + $pageSize - 1, $profiles.Count - 1)
        Write-Host ""
        Write-Host ("    Page {0}/{1}   (games {2}-{3} of {4})   * = selected" -f `
            ($page + 1), $pages, ($start + 1), ($end + 1), $profiles.Count) -ForegroundColor Cyan
        for ($i = $start; $i -le $end; $i++) {
            $mark = if ($selected -contains $profiles[$i]) { '*' } else { ' ' }
            Write-Host ("    {0,3}) {1} {2}" -f ($i + 1), $mark, $profiles[$i].BaseName)
        }
        Write-Host ""
        Write-Host "    Enter number(s) to toggle (e.g. 1,3,5-7) | N=next | P=prev | A=all | D=done" -ForegroundColor DarkCyan
        $inp = (Read-Host "    >").Trim().ToUpper()
        if ($inp -eq "D") { break }
        if ($inp -eq "A") { return $profiles }
        if ($inp -eq "N" -and $page -lt ($pages - 1)) { $page++; continue }
        if ($inp -eq "P" -and $page -gt 0)            { $page--; continue }
        $nums = Expand-NumberList -str $inp -max $profiles.Count
        foreach ($n in $nums) {
            $item = $profiles[$n - 1]
            if ($selected -contains $item) { [void]$selected.Remove($item) }
            else { [void]$selected.Add($item) }
        }
    }
    return @($selected)
}

# Checks the Authenticode signature on a user-provided ReShade DLL. Unlike
# the BepInEx/FFBPlugin/Eggman-dat downloads (unsigned community builds with
# no published checksum to verify against), ReShade's own installer IS
# code-signed -- and that signature is embedded in the PE itself, so it
# survives extracting/renaming the DLL out of the installer into
# Scripts\ReShade\. This gives an actual trust anchor worth checking before
# deploying the file into every selected game's folder. Informational, not
# a hard gate -- an invalid/missing signature is surfaced loudly but does
# not block setup, since the user supplied this file themselves and a
# revocation-check failure on an offline machine looks identical to a
# tampered file.
function Test-ReShadeDllSignature {
    param([string]$Path)
    try {
        $sig    = Get-AuthenticodeSignature -LiteralPath $Path
        $signer = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { "(none)" }
        return [pscustomobject]@{ Status = $sig.Status.ToString(); Signer = $signer }
    } catch {
        return [pscustomobject]@{ Status = "Error"; Signer = "(none)" }
    }
}

# Translates a [System.Management.Automation.SignatureStatus] value (or the
# "Error" sentinel Test-ReShadeDllSignature returns on an exception) into a
# plain-English explanation for the console. The raw enum name alone (e.g.
# "UnknownError") means nothing to someone who isn't a PowerShell developer
# -- this is purely a display concern, Write-Log still records the raw
# status untranslated for anyone diagnosing it later.
function Get-SignatureStatusText {
    param([string]$Status)
    switch ($Status) {
        'NotSigned'              { return "this file has no digital signature at all" }
        'HashMismatch'           { return "the file's contents don't match its signature -- it was modified after signing" }
        'NotTrusted'             { return "signed, but not by a certificate Windows trusts" }
        'NotSupportedFileFormat' { return "this isn't a file type Windows can check a signature on" }
        'Incompatible'           { return "the signature uses a format this version of Windows can't validate" }
        'UnknownError'           { return "Windows could not determine whether this file is genuinely signed (often means it isn't a valid DLL, or the signature check itself failed)" }
        'Error'                  { return "the signature check itself failed unexpectedly" }
        default                  { return "signature could not be confirmed ($Status)" }
    }
}

# Fetches the current ReShade version string from reshade.me.
# Returns e.g. "6.7.3", or $null if the site cannot be reached.
function Get-ReShadeLatestVersion {
    try {
        $resp = Invoke-WebRequest -Uri "https://reshade.me" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($resp.Content -match 'ReShade_Setup_(\d+\.\d+\.\d+(?:\.\d+)?)') { return $Matches[1] }
    } catch {}
    return $null
}

# Full ReShade install wizard: version check, preset choice, game picker, deploy.
# Resolves where ReShade would deploy for a given registered game (target
# folder + DLL name), without touching anything. Shared (read-only)
# between Invoke-ReShadeSetup and the Library health check's coverage
# stat, so the two can never disagree about where the DLL would land.
function Get-ReShadeTargetInfo {
    param([System.Xml.XmlDocument]$Doc, [string]$GamePath, [string]$ExeDir)

    $emuType = ""
    $etNode  = $Doc.GameProfile.SelectSingleNode("EmulatorType")
    if ($etNode) { $emuType = $etNode.InnerText.Trim() }

    # OpenParrot games: files go into the openparrot subfolder
    $targetDir = $ExeDir
    if ($emuType -imatch 'openparrot') {
        $opDir = Join-Path $ExeDir "openparrot"
        if (Test-Path -LiteralPath $opDir) { $targetDir = $opDir }
    }

    # BudgieLoader games always use opengl32.dll; others: detect from exe
    $apiDetected = $true
    if ($emuType -imatch 'budgieloader') {
        $dllName = "opengl32.dll"
    } else {
        $detected = Get-GameApiDll -ExePath $GamePath
        if ($detected) { $dllName = $detected } else { $dllName = "dxgi.dll"; $apiDetected = $false }
    }
    return [pscustomobject]@{ TargetDir = $targetDir; DllName = $dllName; ApiDetected = $apiDetected }
}

function Invoke-ReShadeSetup {
    param(
        [string]$UserProfilesDir,
        [string]$SourceDll,      # 64-bit DLL path (caller guarantees it exists)
        [string]$SourceDll32,    # 32-bit DLL path (optional; $null = skip x86 games)
        [string]$ConfigPath,
        [string]$TpRoot,
        [string]$Mode,
        [string]$ZipSource,
        [string]$GamesInstallFolder,
        [bool]$RetroBat,
        [string]$HsDataPath
    )

    # Version check
    $bVer = $null
    try {
        $vi   = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($SourceDll)
        $bVer = "$($vi.FileMajorPart).$($vi.FileMinorPart).$($vi.FileBuildPart)"
        Write-Host ("  ReShade (64-bit) : {0}" -f $bVer) -ForegroundColor DarkGray
    } catch {}
    if ($SourceDll32 -and (Test-Path -LiteralPath $SourceDll32)) {
        try {
            $vi32   = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($SourceDll32)
            $bVer32 = "$($vi32.FileMajorPart).$($vi32.FileMinorPart).$($vi32.FileBuildPart)"
            Write-Host ("  ReShade (32-bit) : {0}" -f $bVer32) -ForegroundColor DarkGray
        } catch {}
    } else {
        Write-Host "  ReShade (32-bit) : not found -- 32-bit games will be skipped" -ForegroundColor DarkGray
    }

    # Authenticode check on the DLL(s) before deploying them anywhere.
    foreach ($dllCheck in @(
        @{ Path = $SourceDll;   Label = "64-bit" },
        @{ Path = $SourceDll32; Label = "32-bit" }
    )) {
        if (-not $dllCheck.Path -or -not (Test-Path -LiteralPath $dllCheck.Path)) { continue }
        $sigResult = Test-ReShadeDllSignature -Path $dllCheck.Path
        $sha256    = $null
        try { $sha256 = (Get-FileHash -LiteralPath $dllCheck.Path -Algorithm SHA256).Hash } catch {}
        Write-Log ("ReShade ({0}): signature={1} signer='{2}' sha256={3}" -f $dllCheck.Label, $sigResult.Status, $sigResult.Signer, $sha256)
        if ($sigResult.Status -eq 'Valid') {
            Write-Host ("  ReShade ($($dllCheck.Label)) signature : Valid -- $($sigResult.Signer)") -ForegroundColor DarkGray
        } else {
            $statusText = Get-SignatureStatusText -Status $sigResult.Status
            Write-Host ("  ReShade ($($dllCheck.Label)) signature : not validly signed -- $statusText. (raw status: $($sigResult.Status))") -ForegroundColor Yellow
            Write-Host "  Continuing anyway since you supplied this file yourself -- just make sure" -ForegroundColor Yellow
            Write-Host "  it actually came from https://reshade.me and wasn't substituted." -ForegroundColor Yellow
        }
    }

    if ($bVer) {
        Write-Host "  Checking reshade.me for updates..." -ForegroundColor DarkGray
        $latest = Get-ReShadeLatestVersion
        if ($latest) {
            if ([version]$latest -gt [version]$bVer) {
                Write-Host ("  Newer version available: {0}  (you have {1})" -f $latest, $bVer) -ForegroundColor Yellow
                Write-Host "  Get it at  https://reshade.me  and replace ReShade\ReShade64.dll (and ReShade32.dll for 32-bit games)." -ForegroundColor Cyan
            } else {
                Write-Host ("  Up to date ({0})." -f $bVer) -ForegroundColor Green
            }
        } else {
            Write-Host "  (Could not reach reshade.me -- update check skipped.)" -ForegroundColor DarkGray
        }
    }

    # Preset / shader options
    Write-Host ""
    Write-Host "  Preset / visual effects:" -ForegroundColor Cyan
    Write-Host "    1) No preset -- just install the DLL."
    Write-Host "       Once a game launches, press the  Home  key to open the"
    Write-Host "       ReShade overlay and switch effects on or off."
    Write-Host "    2) Use a preset file -- copy a ready-made .ini to every selected game."
    Write-Host "       Useful if you already have settings you are happy with."
    Write-Host ""
    Write-Host "  Tip: drop ProfileCode.ini files into a ReShadePresets\ folder next to" -ForegroundColor DarkCyan
    Write-Host "  this script to pin a specific preset to one game -- it overrides the" -ForegroundColor DarkCyan
    Write-Host "  choice above for that game only. Profile codes are listed in" -ForegroundColor DarkCyan
    Write-Host "  TeknoParrot-Manager-controls.txt." -ForegroundColor DarkCyan
    Write-Host ""
    $presetChoice = (Read-Host "  Enter 1 or 2").Trim()
    $presetPath   = $null
    if ($presetChoice -eq "2") {
        $pInp = Read-PathWithBrowse "  Path to your ReShade preset (.ini) file" -Mode File -FileFilter "ReShade preset (*.ini)|*.ini|All files (*.*)|*.*"
        if (Test-Path -LiteralPath $pInp) {
            $presetPath = $pInp
            Write-Host "  Preset: $pInp" -ForegroundColor DarkGray
        } else {
            Write-Host "  File not found -- continuing without preset." -ForegroundColor Yellow
        }
    }

    # Per-game preset overrides: ReShadePresets\<ProfileCode>.ini always wins
    # over the global choice above for that one game. Same convention as
    # CustomThumbnails\<ProfileCode>.png (Invoke-ThumbnailDownload) -- file
    # name is the profile code, validated against registered profiles, with
    # a WRONG NAME warning for typos instead of a silent no-op.
    $reShadePresetsDir = Join-Path $PSScriptRoot "ReShadePresets"
    if (Test-Path -LiteralPath $reShadePresetsDir) {
        $presetFiles = @(Get-ChildItem -LiteralPath $reShadePresetsDir -Filter "*.ini" -File -ErrorAction SilentlyContinue)
        if ($presetFiles.Count -gt 0) {
            $knownPresetCodes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -ne "FullBackup" } |
                ForEach-Object { [void]$knownPresetCodes.Add($_.BaseName) }
            foreach ($pfile in $presetFiles) {
                $code = [System.IO.Path]::GetFileNameWithoutExtension($pfile.Name)
                if (-not $knownPresetCodes.Contains($code)) {
                    Write-Host ("  WRONG NAME: ReShadePresets\{0}" -f $pfile.Name) -ForegroundColor Yellow
                    Write-Host ("             '{0}' does not match any registered game profile code." -f $code) -ForegroundColor Yellow
                    Write-Host "             Check TeknoParrot-Manager-controls.txt for the correct" -ForegroundColor Yellow
                    Write-Host "             name, rename the file, then re-run. File will be ignored." -ForegroundColor Yellow
                    Write-Log "ReShade: per-game preset $($pfile.Name) -- no matching profile code, ignored."
                }
            }
        }
    }

    # Game selection
    Write-Host ""
    Write-Host "  Which games should get ReShade?" -ForegroundColor Cyan
    Write-Host "  You can run setup again later to add or change individual games." -ForegroundColor DarkCyan
    $selectedGames = @(Select-RegisteredGamesInteractive -UserProfilesDir $UserProfilesDir)
    if ($selectedGames.Count -eq 0) {
        Write-Host "  No games selected. ReShade setup cancelled." -ForegroundColor Yellow
        Write-Log "ReShade setup: cancelled -- no games selected."
        return
    }

    # Deploy
    Write-Host ""
    Write-Host ("  Installing ReShade into {0} game folder(s)..." -f $selectedGames.Count) -ForegroundColor Cyan
    $deployed = 0; $skipped = 0; $errors = 0; $presetOverrides = 0

    foreach ($pf in $selectedGames) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { $skipped++; continue }

            $gpNode = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { $skipped++; continue }

            $gamePath = $gpNode.InnerText.Trim()
            if (-not (Test-Path -LiteralPath $gamePath)) {
                Write-Host ("    {0}: game path not found -- skipped" -f $pf.BaseName) -ForegroundColor DarkGray
                $skipped++; continue
            }
            $exeDir = [System.IO.Path]::GetDirectoryName($gamePath)
            if ([string]::IsNullOrWhiteSpace($exeDir)) {
                Write-Host ("    {0}: invalid game path (no directory component) -- skipped" -f $pf.BaseName) -ForegroundColor Yellow
                $skipped++; continue
            }

            # Pick the right ReShade DLL based on detected exe architecture.
            $arch      = Get-ExeArchitecture -ExePath $gamePath
            $activeDll = $SourceDll   # default: 64-bit
            if ($arch -eq 'x86') {
                if ($SourceDll32 -and (Test-Path -LiteralPath $SourceDll32)) {
                    $activeDll = $SourceDll32
                } else {
                    Write-Host ("    {0}: 32-bit game -- ReShade32.dll not found; skipped." -f $pf.BaseName) -ForegroundColor Yellow
                    Write-Log "ReShade: skipped $($pf.BaseName) -- 32-bit game, no ReShade32.dll."
                    $skipped++; continue
                }
            } elseif ($arch -ne $null -and $arch -ne 'x64') {
                Write-Host ("    {0}: unsupported architecture ({1}); skipped." -f $pf.BaseName, $arch) -ForegroundColor Yellow
                Write-Log "ReShade: skipped $($pf.BaseName) -- unsupported architecture ($arch)."
                $skipped++; continue
            }

            $targetInfo = Get-ReShadeTargetInfo -Doc $doc -GamePath $gamePath -ExeDir $exeDir
            $targetDir  = $targetInfo.TargetDir
            $dllName    = $targetInfo.DllName
            if (-not $targetInfo.ApiDetected) {
                Write-Host ("    {0}: graphics API not detected, defaulting to dxgi.dll" -f $pf.BaseName) -ForegroundColor Yellow
            }

            $destDll = Join-Path $targetDir $dllName
            Copy-Item -LiteralPath $activeDll -Destination $destDll -Force -ErrorAction Stop

            # Per-game preset (ReShadePresets\<ProfileCode>.ini) always wins
            # over the global choice for this one game.
            $perGamePreset   = Join-Path $reShadePresetsDir ($pf.BaseName + ".ini")
            $effectivePreset = $null; $presetSource = $null
            if (Test-Path -LiteralPath $perGamePreset) {
                $effectivePreset = $perGamePreset; $presetSource = "per-game"
            } elseif ($presetPath) {
                $effectivePreset = $presetPath; $presetSource = "global"
            }
            if ($effectivePreset) {
                Copy-Item -LiteralPath $effectivePreset -Destination (Join-Path $targetDir "ReShade.ini") `
                          -Force -ErrorAction Stop
                if ($presetSource -eq "per-game") { $presetOverrides++ }
            }

            $presetNote = if ($presetSource) { "  (preset: $presetSource)" } else { "" }
            Write-Host ("    {0}  [{1}]{2}" -f $pf.BaseName, $dllName, $presetNote) -ForegroundColor Green
            Write-Log "ReShade: $($pf.BaseName) -> $targetDir [$dllName]$presetNote"
            $deployed++
        } catch {
            Write-Host ("    FAILED {0}: {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "ReShade: FAILED $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Installed : {0} game(s)" -f $deployed) -ForegroundColor Green
    if ($presetOverrides -gt 0) {
        Write-Host ("  Per-game presets applied : {0}" -f $presetOverrides) -ForegroundColor Cyan
    }
    if ($skipped -gt 0) {
        Write-Host ("  Skipped   : {0}  (path not found, 32-bit DLL missing, or unsupported architecture)" -f $skipped) -ForegroundColor DarkGray
    }
    if ($errors -gt 0) {
        Write-Host ("  Errors    : {0}  -- see TeknoParrot-Manager.log for details" -f $errors) -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  To turn effects on/off: launch a game and press the  Home  key." -ForegroundColor Cyan
    Write-Host "  To uninstall ReShade: delete the DLL file (e.g. dxgi.dll, d3d9.dll)" -ForegroundColor DarkCyan
    Write-Host "  from the game's folder. Your game files are never modified." -ForegroundColor DarkCyan
    Write-Log ("ReShade setup: Installed={0} Skipped={1} Errors={2} PresetOverrides={3}" -f $deployed, $skipped, $errors, $presetOverrides)
}

# =============================================================================
# Scans the first 2 MB of a game exe for legacy graphics API imports (DX8 /
# DirectDraw / Glide). Returns an array from: 'D3D8', 'DDraw', 'Glide2x',
# 'Glide3x'. Returns empty array if nothing is detected or on error.
function Get-GameLegacyApi {
    param([string]$ExePath)
    $found = @()
    try {
        $readLen = [int][Math]::Min((Get-Item -LiteralPath $ExePath).Length, 2097152)
        $buf     = New-Object byte[] $readLen
        $fs      = [System.IO.File]::OpenRead($ExePath)
        try {
            $pos = 0
            while ($pos -lt $readLen) {
                $n = $fs.Read($buf, $pos, $readLen - $pos)
                if ($n -eq 0) { break }
                $pos += $n
            }
        } finally { $fs.Dispose() }
        $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $pos)
        if ($text -match '(?i)d3d8\.dll')              { $found += 'D3D8'    }
        if ($text -match '(?i)ddraw\.dll')             { $found += 'DDraw'   }
        if ($text -match '(?i)glide2x\.dll')           { $found += 'Glide2x' }
        if ($text -match '(?i)(?:glide3x|glide)\.dll') { $found += 'Glide3x' }
    } catch {
        Write-Log "dgVoodoo2: scan failed for $ExePath -- $_"
    }
    return $found
}

# Pure, read-only check used by the Library health check's coverage
# report: given the legacy APIs an exe imports (from Get-GameLegacyApi)
# and its folder, decides whether dgVoodoo2 is already deployed there.
# Deliberately NOT shared with Invoke-DgVoodoo2Setup's own deploy logic --
# that logic also depends on which DLLs the user has actually bundled in
# their dgVoodoo2 source folder (falls back to deploying everything
# available if the ideal DLL is missing), which is a real, intentional
# difference from "does this game need dgVoodoo2 at all" -- a coverage
# report should answer the latter, independent of what's bundled.
function Test-DgVoodoo2UpToDate {
    param($Apis, [string]$ExeDir)

    if ($Apis.Count -eq 0) { return [pscustomobject]@{ Eligible = $false; UpToDate = $true } }
    $requiredDlls = @()
    if ($Apis -contains 'D3D8')    { $requiredDlls += 'D3D8.dll'    }
    if ($Apis -contains 'DDraw')   { $requiredDlls += 'DDraw.dll'   }
    if ($Apis -contains 'Glide2x') { $requiredDlls += 'Glide2x.dll' }
    if ($Apis -contains 'Glide3x') { $requiredDlls += 'Glide3x.dll' }
    $missing = @($requiredDlls | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ExeDir $_)) })
    return [pscustomobject]@{ Eligible = $true; UpToDate = ($missing.Count -eq 0) }
}

# =============================================================================
# dgVoodoo2 install wizard: auto-detect DX8/DDraw/Glide games, deploy DLLs.
function Invoke-DgVoodoo2Setup {
    param(
        [string]$UserProfilesDir,
        [string]$SourceDir,
        [string]$TpRoot
    )

    # Validate at least one expected DLL is present in the source folder.
    $allExpected = @('D3D8.dll', 'DDraw.dll', 'D3DImm.dll', 'Glide2x.dll', 'Glide3x.dll')
    $available   = @($allExpected | Where-Object { Test-Path -LiteralPath (Join-Path $SourceDir $_) })
    if ($available.Count -eq 0) {
        Write-Host ("  ERROR: No dgVoodoo2 DLLs found in: {0}" -f $SourceDir) -ForegroundColor Red
        Write-Host ("  Expected one or more of: {0}" -f ($allExpected -join ', ')) -ForegroundColor Yellow
        Write-Log "dgVoodoo2 setup: aborted -- no DLLs in $SourceDir"
        return
    }
    Write-Host ("  Available DLLs : {0}" -f ($available -join ', ')) -ForegroundColor DarkGray

    # Per-game config overrides: dgVoodoo2Presets\<ProfileCode>.conf always
    # wins over the global dgVoodoo.conf in $SourceDir for that one game.
    # Same convention as ReShadePresets\<ProfileCode>.ini (Invoke-ReShadeSetup)
    # and CustomThumbnails\<ProfileCode>.png (Invoke-ThumbnailDownload).
    $dgVoodoo2PresetsDir = Join-Path $PSScriptRoot "dgVoodoo2Presets"
    if (Test-Path -LiteralPath $dgVoodoo2PresetsDir) {
        $confFiles = @(Get-ChildItem -LiteralPath $dgVoodoo2PresetsDir -Filter "*.conf" -File -ErrorAction SilentlyContinue)
        if ($confFiles.Count -gt 0) {
            $knownConfCodes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -ne "FullBackup" } |
                ForEach-Object { [void]$knownConfCodes.Add($_.BaseName) }
            foreach ($cfile in $confFiles) {
                $code = [System.IO.Path]::GetFileNameWithoutExtension($cfile.Name)
                if (-not $knownConfCodes.Contains($code)) {
                    Write-Host ("  WRONG NAME: dgVoodoo2Presets\{0}" -f $cfile.Name) -ForegroundColor Yellow
                    Write-Host ("             '{0}' does not match any registered game profile code." -f $code) -ForegroundColor Yellow
                    Write-Host "             Check TeknoParrot-Manager-controls.txt for the correct" -ForegroundColor Yellow
                    Write-Host "             name, rename the file, then re-run. File will be ignored." -ForegroundColor Yellow
                    Write-Log "dgVoodoo2: per-game config $($cfile.Name) -- no matching profile code, ignored."
                }
            }
        }
    }

    # Scan all registered games for legacy API usage and build a detection map.
    Write-Host ""
    Write-Host "  Scanning registered games for old DirectX / Glide usage..." -ForegroundColor Cyan
    $profiles = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" } |
                  Sort-Object BaseName)
    if ($profiles.Count -eq 0) {
        Write-Host "  No registered games found." -ForegroundColor Yellow
        Write-Log "dgVoodoo2 setup: aborted -- no registered profiles."
        return
    }

    $detectedMap = @{}   # BaseName -> API array
    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { continue }
            $gpNode   = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { continue }
            $gamePath = $gpNode.InnerText.Trim()
            if (-not (Test-Path -LiteralPath $gamePath)) { continue }
            $apis = @(Get-GameLegacyApi -ExePath $gamePath)
            if ($apis.Count -gt 0) { $detectedMap[$pf.BaseName] = $apis }
        } catch {
            Write-Log "dgVoodoo2 scan: error reading $($pf.BaseName) -- $_"
        }
    }

    Write-Host ("  Scanned {0} game(s)." -f $profiles.Count) -ForegroundColor DarkGray
    if ($detectedMap.Count -gt 0) {
        Write-Host ("  Auto-detected {0} game(s) using legacy APIs:" -f $detectedMap.Count) -ForegroundColor Cyan
        foreach ($name in ($detectedMap.Keys | Sort-Object)) {
            Write-Host ("    {0}  [{1}]" -f $name, ($detectedMap[$name] -join ', '))
        }
    } else {
        Write-Host "  No games were auto-detected as using legacy APIs." -ForegroundColor DarkGray
    }

    # Game selection.
    Write-Host ""
    Write-Host "  Which games should get dgVoodoo2?" -ForegroundColor Cyan
    $selectionMode = ""
    if ($detectedMap.Count -gt 0) {
        Write-Host "  A) Auto-detected games only ($($detectedMap.Count) game(s) listed above)"
        Write-Host "  M) Pick games manually from the full list"
        Write-Host "  Q) Cancel"
        $selectionMode = (Read-Host "  Enter A, M, or Q").Trim().ToUpper()
    } else {
        Write-Host "  M) Pick games manually from the full list"
        Write-Host "  Q) Cancel"
        $selectionMode = (Read-Host "  Enter M or Q").Trim().ToUpper()
    }

    $targetProfiles = @()
    if ($selectionMode -eq 'A') {
        $targetProfiles = @($profiles | Where-Object { $detectedMap.ContainsKey($_.BaseName) })
    } elseif ($selectionMode -eq 'M') {
        $targetProfiles = @(Select-RegisteredGamesInteractive -UserProfilesDir $UserProfilesDir)
    } else {
        Write-Host "  dgVoodoo2 setup cancelled." -ForegroundColor Yellow
        Write-Log "dgVoodoo2 setup: cancelled."
        return
    }

    if ($targetProfiles.Count -eq 0) {
        Write-Host "  No games selected. dgVoodoo2 setup cancelled." -ForegroundColor Yellow
        Write-Log "dgVoodoo2 setup: cancelled -- no games selected."
        return
    }

    # Deploy DLLs to each selected game folder.
    Write-Host ""
    Write-Host ("  Installing dgVoodoo2 into {0} game folder(s)..." -f $targetProfiles.Count) -ForegroundColor Cyan
    $deployed = 0; $skipped = 0; $errors = 0; $presetOverrides = 0
    $hasConf  = Test-Path -LiteralPath (Join-Path $SourceDir "dgVoodoo.conf")

    foreach ($pf in $targetProfiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { $skipped++; continue }
            $gpNode   = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { $skipped++; continue }
            $gamePath = $gpNode.InnerText.Trim()
            if (-not (Test-Path -LiteralPath $gamePath)) {
                Write-Host ("  SKIP  {0} -- exe not found." -f $pf.BaseName) -ForegroundColor Yellow
                $skipped++; continue
            }
            $exeDir = [System.IO.Path]::GetDirectoryName($gamePath)
            if ([string]::IsNullOrWhiteSpace($exeDir)) { $skipped++; continue }

            # Determine which DLLs this game needs based on detected API.
            $apis = if ($detectedMap.ContainsKey($pf.BaseName)) `
                        { @($detectedMap[$pf.BaseName]) } `
                    else `
                        { @(Get-GameLegacyApi -ExePath $gamePath) }

            $toDeploy = @()
            if ($apis.Count -eq 0) {
                $toDeploy = $available   # manual pick with no detection: deploy all available
            } else {
                if ($apis -contains 'D3D8')    { $toDeploy += @($available | Where-Object { $_ -in @('D3D8.dll',   'D3DImm.dll') }) }
                if ($apis -contains 'DDraw')   { $toDeploy += @($available | Where-Object { $_ -in @('DDraw.dll',  'D3DImm.dll') }) }
                if ($apis -contains 'Glide2x') { $toDeploy += @($available | Where-Object { $_ -eq  'Glide2x.dll'               }) }
                if ($apis -contains 'Glide3x') { $toDeploy += @($available | Where-Object { $_ -eq  'Glide3x.dll'               }) }
                $toDeploy = @($toDeploy | Select-Object -Unique)
                if ($toDeploy.Count -eq 0) {
                    Write-Host ("  WARN  {0}: detected [{1}] but none of those DLLs are in the source folder; deploying all available." -f $pf.BaseName, ($apis -join ', ')) -ForegroundColor Yellow
                    Write-Log "dgVoodoo2: $($pf.BaseName) -- detected [$($apis -join ', ')] but no matching DLLs found; deploying all available."
                    $toDeploy = $available
                }
            }

            foreach ($dllName in $toDeploy) {
                $dstDll = Join-Path $exeDir $dllName
                if (-not (Test-Path -LiteralPath $dstDll)) {
                    Copy-Item -LiteralPath (Join-Path $SourceDir $dllName) -Destination $dstDll -ErrorAction Stop
                }
            }
            # Per-game config (dgVoodoo2Presets\<ProfileCode>.conf) always wins
            # over the global dgVoodoo.conf for this one game, and -- unlike
            # the global conf -- always overwrites: it's an explicit per-game
            # action, so "never overwrite" would silently defeat it on any
            # game that already has a conf deployed from a prior run.
            $perGameConf = Join-Path $dgVoodoo2PresetsDir ($pf.BaseName + ".conf")
            $confNote    = ""
            if (Test-Path -LiteralPath $perGameConf) {
                $dstConf = Join-Path $exeDir "dgVoodoo.conf"
                Copy-Item -LiteralPath $perGameConf -Destination $dstConf -Force -ErrorAction Stop
                $presetOverrides++
                $confNote = "  (config: per-game)"
            } elseif ($hasConf) {
                $dstConf = Join-Path $exeDir "dgVoodoo.conf"
                if (-not (Test-Path -LiteralPath $dstConf)) {
                    Copy-Item -LiteralPath (Join-Path $SourceDir "dgVoodoo.conf") -Destination $dstConf -ErrorAction Stop
                }
            }
            $apiStr = if ($apis.Count -gt 0) { "  [{0}]" -f ($apis -join ', ') } else { "" }
            Write-Host ("  OK    {0}{1}{2}" -f $pf.BaseName, $apiStr, $confNote) -ForegroundColor Green
            Write-Log ("dgVoodoo2: deployed {0} to {1}{2}" -f ($toDeploy -join ', '), $exeDir, $confNote)
            $deployed++

        } catch {
            Write-Host ("  ERROR {0} -- {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "dgVoodoo2: error on $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Deployed  : {0} game(s)" -f $deployed) -ForegroundColor Green
    if ($presetOverrides -gt 0) {
        Write-Host ("  Per-game configs applied : {0}" -f $presetOverrides) -ForegroundColor Cyan
    }
    if ($skipped -gt 0) { Write-Host ("  Skipped   : {0}" -f $skipped) -ForegroundColor DarkGray }
    if ($errors  -gt 0) { Write-Host ("  Errors    : {0}" -f $errors)  -ForegroundColor Red      }
    Write-Host ""
    Write-Host "  To uninstall: delete the deployed DLL file(s) from the game folder." -ForegroundColor DarkCyan
    Write-Host "  Your original game files are never modified." -ForegroundColor DarkCyan
    Write-Log ("dgVoodoo2 setup: deployed={0} skipped={1} errors={2} presetOverrides={3}" -f $deployed, $skipped, $errors, $presetOverrides)
}

# =============================================================================
# XPath 1.0 has no escape for apostrophes in string literals; use concat()
# when the value contains one so the predicate always parses correctly.
function ConvertTo-XPathStringLiteral {
    param([string]$s)
    if ($s -notmatch "'") { return "'$s'" }
    $parts = $s.Split([char]39) | ForEach-Object { "'$_'" }
    return 'concat(' + ($parts -join ',"''",') + ')'
}

# Read-only, best-effort GPU vendor auto-detect via WMI -- no prompting.
# Returns [pscustomobject]@{ Vendor; Name } (Vendor may be $null if
# undetected). Shared by Invoke-GpuFixSetup (which falls back to an
# interactive prompt on failure) and the automatic compatibility check
# (which silently skips on failure, since it must not block an
# unattended-style run with a prompt).
function Get-DetectedGpuVendor {
    $gpuVendor = $null
    $gpuName   = $null
    try {
        # Bounded wait: a WMI service hiccup should fall through to the manual
        # vendor prompt below rather than hang the script indefinitely. Local
        # GPU enumeration doesn't have the network-round-trip hang risk that
        # Test-IsNetworkPath's drive check had, but the WMI service itself can
        # still misbehave, so this is bounded defensively rather than removed.
        $adapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop -OperationTimeoutSec 10 |
            Where-Object { $_.Name -notmatch '(?i)microsoft|virtual|remote' } |
            Sort-Object { if ($_.AdapterRAM) { [double]$_.AdapterRAM } else { 0.0 } } -Descending)
        if ($adapters.Count -gt 0) {
            $gpuName = $adapters[0].Name
            if     ($gpuName -imatch 'amd|radeon')                 { $gpuVendor = 'AMD'    }
            elseif ($gpuName -imatch 'nvidia|geforce|rtx|gtx')     { $gpuVendor = 'NVIDIA' }
            elseif ($gpuName -imatch 'intel')                      { $gpuVendor = 'Intel'  }
        }
    } catch {
        Write-Log "Get-DetectedGpuVendor: WMI detection failed -- $_"
    }
    return [pscustomobject]@{ Vendor = $gpuVendor; Name = $gpuName }
}

# Discovers GPU fix field names by scanning TeknoParrot GameProfiles at
# runtime, so newly added games with new fix fields are covered
# automatically without a script update. Shared (read-only) between
# Invoke-GpuFixSetup and the Library health check's coverage report --
# extracting this avoids the two ever silently drifting apart.
function Get-GpuFixFieldNames {
    param([string]$TpRoot)

    $gpDir         = Join-Path $TpRoot "GameProfiles"
    $boolAmdFields = [System.Collections.Generic.HashSet[string]]::new(
                         [string[]]@('EnableAmdFix','AMDCrashFix','AMDFix'),
                         [System.StringComparer]::OrdinalIgnoreCase)
    $dropdownGpuFields = [System.Collections.Generic.HashSet[string]]::new(
                             [string[]]@('GPU Fix'),
                             [System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path -LiteralPath $gpDir) {
        $gpFiles = @(Get-ChildItem -LiteralPath $gpDir -Filter "*.xml" -ErrorAction SilentlyContinue)
        foreach ($gf in $gpFiles) {
            try {
                $gdoc = Read-Xml $gf.FullName
                $fnodes = $gdoc.SelectNodes("/GameProfile/ConfigValues/FieldInformation")
                foreach ($n in $fnodes) {
                    $fn = if ($n.FieldName) { $n.FieldName.Trim() } else { '' }
                    $ft = if ($n.FieldType)  { $n.FieldType.Trim()  } else { '' }
                    if (-not $fn) { continue }
                    if ($ft -eq 'Bool' -and $fn -imatch '\bamd\b|\bradeon\b|AMDFix|AMDCrash') {
                        [void]$boolAmdFields.Add($fn)
                    } elseif ($ft -eq 'Dropdown') {
                        $opts = @($n.SelectNodes("FieldOptions/string") | ForEach-Object { $_.InnerText.Trim() })
                        if ($opts | Where-Object { $_ -imatch '^amd$|^nvidia$|^intel$|^new amd' }) {
                            [void]$dropdownGpuFields.Add($fn)
                        }
                    }
                }
            } catch {
                Write-Log ("GPU Fix: WARNING -- could not parse GameProfile '$($gf.BaseName)': $_")
            }
        }
    }
    return [pscustomobject]@{ BoolFields = $boolAmdFields; DropdownFields = $dropdownGpuFields; GameProfilesFound = (Test-Path -LiteralPath $gpDir) }
}

# Combines Get-GpuFixFieldNames and Get-FFBBlasterFieldNames into a single
# pass over GameProfiles. The Library health check needs both sets of
# fields in the same run, and calling the two functions separately means
# every GameProfile XML in the folder (TeknoParrot ships profiles for its
# entire supported-game catalog, not just the user's library, so this can
# be 1000+ files) gets parsed twice for no reason. Returns
# [pscustomobject]@{ Gpu = <same shape as Get-GpuFixFieldNames>; Ffb = <same shape as Get-FFBBlasterFieldNames> }
# -- the matching logic for each is identical to the two standalone
# functions, just evaluated in the same loop iteration. Invoke-GpuFixSetup
# and Invoke-FFBBlasterSetup keep calling their own standalone functions
# unchanged (they only ever need one or the other, never both at once), so
# this is purely additive -- only the health check's combined-need call
# site switches to use it.
function Get-GpuAndFfbFieldNames {
    param([string]$TpRoot)

    $gpDir             = Join-Path $TpRoot "GameProfiles"
    $boolAmdFields     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $dropdownGpuFields = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ffbFields         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $gpDirExists       = Test-Path -LiteralPath $gpDir

    if ($gpDirExists) {
        $gpFiles = @(Get-ChildItem -LiteralPath $gpDir -Filter "*.xml" -ErrorAction SilentlyContinue)
        foreach ($gf in $gpFiles) {
            try {
                $gdoc = Read-Xml $gf.FullName
                $fnodes = $gdoc.SelectNodes("/GameProfile/ConfigValues/FieldInformation")
                foreach ($n in $fnodes) {
                    $cn = if ($n.CategoryName) { $n.CategoryName.Trim() } else { '' }
                    $fn = if ($n.FieldName)     { $n.FieldName.Trim()     } else { '' }
                    $ft = if ($n.FieldType)     { $n.FieldType.Trim()     } else { '' }
                    if ($ft -eq 'Bool') {
                        if ($fn -and $fn -imatch '\bamd\b|\bradeon\b|AMDFix|AMDCrash') {
                            [void]$boolAmdFields.Add($fn)
                        }
                        if ($cn -imatch 'ffb.*blaster|blaster.*ffb') {
                            [void]$ffbFields.Add($cn)
                        } elseif ($fn -and $fn -imatch 'ffb.*blaster|blaster.*ffb') {
                            [void]$ffbFields.Add($fn)
                        }
                    } elseif ($ft -eq 'Dropdown') {
                        $opts = @($n.SelectNodes("FieldOptions/string") | ForEach-Object { $_.InnerText.Trim() })
                        if ($opts | Where-Object { $_ -imatch '^amd$|^nvidia$|^intel$|^new amd' }) {
                            [void]$dropdownGpuFields.Add($fn)
                        }
                    }
                }
            } catch {
                Write-Log ("GpuAndFfbFieldScan: WARNING -- could not parse GameProfile '$($gf.BaseName)': $_")
            }
        }
    }

    return [pscustomobject]@{
        Gpu = [pscustomobject]@{ BoolFields = $boolAmdFields; DropdownFields = $dropdownGpuFields; GameProfilesFound = $gpDirExists }
        Ffb = $ffbFields
    }
}

# Pure decision function: for a given UserProfile XML and the field names
# discovered by Get-GpuFixFieldNames, determines whether the profile has
# any GPU fix field at all (Eligible) and, if so, whether every such
# field already matches the value expected for $Vendor (UpToDate). Also
# returns the exact node + new value for each field that needs changing,
# so Invoke-GpuFixSetup can apply them without re-deriving the same
# vendor-specific value logic a second time.
function Test-GpuFixUpToDate {
    param([System.Xml.XmlDocument]$Doc, $BoolFields, $DropdownFields, [string]$Vendor)

    $eligible = $false
    $changes  = New-Object System.Collections.Generic.List[object]

    foreach ($fieldName in $BoolFields) {
        $xpLit = ConvertTo-XPathStringLiteral $fieldName
        $fi = $Doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$xpLit]")
        if ($null -eq $fi) { continue }
        $fvNode = $fi.SelectSingleNode("FieldValue")
        if ($null -eq $fvNode) { continue }
        $eligible = $true
        $newVal = if ($Vendor -eq 'AMD') { '1' } else { '0' }
        if ($fvNode.InnerText -ne $newVal) {
            [void]$changes.Add([pscustomobject]@{ FieldName = $fieldName; Node = $fvNode; OldValue = $fvNode.InnerText; NewValue = $newVal })
        }
    }

    foreach ($fieldName in $DropdownFields) {
        $xpLit = ConvertTo-XPathStringLiteral $fieldName
        $fi = $Doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$xpLit]")
        if ($null -eq $fi) { continue }
        $fvNode = $fi.SelectSingleNode("FieldValue")
        $opts   = @($fi.SelectNodes("FieldOptions/string") | ForEach-Object { $_.InnerText.Trim() })
        if ($null -eq $fvNode -or $opts.Count -eq 0) { continue }
        $eligible = $true

        $newVal = 'None'
        if ($Vendor -eq 'AMD') {
            if     ($opts -contains 'New AMD Driver') { $newVal = 'New AMD Driver' }
            elseif ($opts -contains 'AMD')            { $newVal = 'AMD'            }
        } elseif ($Vendor -eq 'NVIDIA') {
            if ($opts -contains 'NVIDIA') { $newVal = 'NVIDIA' }
        } elseif ($Vendor -eq 'Intel') {
            if ($opts -contains 'INTEL') { $newVal = 'INTEL' }
        }

        if ($fvNode.InnerText -ne $newVal) {
            [void]$changes.Add([pscustomobject]@{ FieldName = $fieldName; Node = $fvNode; OldValue = $fvNode.InnerText; NewValue = $newVal })
        }
    }

    return [pscustomobject]@{ Eligible = $eligible; UpToDate = ($eligible -and $changes.Count -eq 0); Changes = $changes }
}

# =============================================================================
# POSTGRESQL DETECTION  (read-only helpers, shared by Postgres setup mode
# and the Library health check's coverage report)
# =============================================================================
# Several Incredible Technologies games (Golden Tee Live, Power Putt Live,
# Silver Strike Bowling Live, Target Toss Pro, Orange County Choppers
# Pinball) need a local PostgreSQL 8.3 database. Their Postgres settings
# live inside ConfigValues/FieldInformation under CategoryName=Postgres --
# the same generic per-game-setting structure GPU Fix/FFB Blaster above
# already use -- confirmed against a real Golden Tee Live 2019 GameProfile.
# Field names are standardized across every such game (it's the same
# settings panel design), so unlike GPU Fix this never needs per-game
# field-name variant matching -- just the category existence check below.

$script:PostgresInstallDir  = "C:\Program Files (x86)\PostgreSQL\8.3"
$script:PostgresBinDir      = Join-Path $script:PostgresInstallDir "bin"
$script:PostgresServiceName = "pgsql-8.3"

# Returns $true if this profile has any Postgres-category field at all.
function Test-GameNeedsPostgres {
    param([System.Xml.XmlDocument]$Doc)
    $node = $Doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[CategoryName='Postgres']")
    return ($null -ne $node)
}

# Reads one named field's current value from the Postgres category, or
# $null if the field is missing entirely (distinct from an empty string,
# which means the field exists but is blank -- callers care about this
# distinction: "Automatically create Database" being absent means an older
# GameProfileRevision that predates the feature, not that it's off).
function Get-PostgresFieldValue {
    param([System.Xml.XmlDocument]$Doc, [string]$FieldName)
    $xpLit = ConvertTo-XPathStringLiteral $FieldName
    $fi = $Doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[CategoryName='Postgres' and FieldName=$xpLit]")
    if ($null -eq $fi) { return $null }
    $fvNode = $fi.SelectSingleNode("FieldValue")
    if ($null -eq $fvNode) { return $null }
    return $fvNode.InnerText
}

# Sets one named field's value in the Postgres category. No-op (returns
# $false) if the field doesn't exist on this profile -- never creates a
# new field, since the schema is owned by TeknoParrot's own GameProfile
# definitions, not by this script.
function Set-PostgresFieldValue {
    param([System.Xml.XmlDocument]$Doc, [string]$FieldName, [string]$Value)
    $xpLit = ConvertTo-XPathStringLiteral $FieldName
    $fi = $Doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[CategoryName='Postgres' and FieldName=$xpLit]")
    if ($null -eq $fi) { return $false }
    $fvNode = $fi.SelectSingleNode("FieldValue")
    if ($null -eq $fvNode) { return $false }
    $fvNode.InnerText = $Value
    return $true
}

# Validates a database name is safe to interpolate into a SQL string/CLI
# argument before any Postgres operation touches it. DbName ultimately
# comes from a GameProfile XML field -- shipped by TeknoParrot, but this
# script treats it as semi-trusted rather than blindly safe in a SQL
# context, matching the project's "external-ish input into a command must
# be validated" convention used elsewhere (e.g. Test-PathInside for
# filesystem paths). Every real DbName observed (GameDB19, GAMEDBPP12,
# GameDBSSB, GameDBBags, etc.) is plain alphanumeric, so this is not a
# practical restriction -- just a guard against the unexpected.
function Test-SafePostgresDbName {
    param([string]$DbName)
    return ($DbName -match '^[A-Za-z0-9_]+$')
}

# Issue #3 (v1.0 roadmap): every Postgres helper used to set $env:PGPASSWORD
# for the duration of a psql.exe/pg_dump.exe/etc. call. For the few
# milliseconds that child process runs, the password is visible in its own
# environment block to anything else on the system that can inspect a
# process's environment (Task Manager, Process Explorer, a WMI query) --
# flagged by an external review as acceptable for this project's actual
# use case (a single local arcade machine) but worth closing for v1.0.
# libpq-based tools (psql/pg_dump/pg_restore/createdb/dropdb all are)
# automatically pick up a PGPASSFILE env var pointing at a standard
# ".pgpass" credential file instead, never putting the password in their
# own environment or command line. This writes one, locked down to the
# current user via icacls, for the caller to point PGPASSFILE at and
# delete via Remove-PostgresPgPassFile when done.
#
# Single line with "*" for the database field covers every call site here --
# they all use a fixed -h 127.0.0.1 -p 5432 -U postgres and only the
# database name (or no -d at all) varies. Per the .pgpass format
# (https://www.postgresql.org/docs/current/libpq-pgpass.html), only "\" and
# ":" need escaping in a field, and only the password field here can
# realistically contain either.
function New-PostgresPgPassFile {
    param([string]$Password)
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-pgpass-" + [guid]::NewGuid().ToString("N") + ".conf")
    $escaped = $Password -replace '\\', '\\' -replace ':', '\:'
    $line = "127.0.0.1:5432:*:postgres:$escaped"
    [System.IO.File]::WriteAllText($path, $line + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
    # Best-effort hardening, not load-bearing: the temp folder itself is
    # already restricted to the current user by default NTFS inheritance,
    # so a failure here (e.g. icacls unavailable) does not block the
    # credential-file approach from working -- it just loses the extra
    # explicit lockdown.
    try {
        $owner = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls $path /inheritance:r /grant:r "${owner}:(R)" 2>&1 | Out-Null
    } catch {
        Write-Log "Postgres: could not lock down pgpass file ACL -- $_"
    }
    return $path
}

# Deletes a temporary pgpass file created by New-PostgresPgPassFile. Never
# throws -- this always runs from a `finally` block, and a failure to
# delete a temp file (e.g. AV briefly holding a handle) should never mask
# whatever the real result of the Postgres operation was.
function Remove-PostgresPgPassFile {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        try { [System.IO.File]::Delete($Path) } catch {}
    }
}

# Read-only: true if PostgreSQL 8.3 is already installed (service exists
# and psql.exe is present). Never reinstalls or modifies an existing
# install -- callers use this to skip straight to per-game configuration
# when it's already true, per the explicit "never touch an existing
# install" requirement.
function Test-PostgresInstalled {
    $svc = Get-Service -Name $script:PostgresServiceName -ErrorAction SilentlyContinue
    $psqlExists = Test-Path -LiteralPath (Join-Path $script:PostgresBinDir "psql.exe")
    return (($null -ne $svc) -and $psqlExists)
}

# Read-only: true if a database with this exact name already exists on
# the local Postgres server. This is the check that gates every
# database-creation/restore step in the setup mode -- a database that
# already exists for an already-configured game is never touched,
# recreated, or restored over.
function Test-PostgresDatabaseExists {
    param([string]$DbName, [string]$SuperPasswordPlain)
    if (-not (Test-SafePostgresDbName $DbName)) {
        Write-Log "Postgres: refusing unsafe database name '$DbName'"
        return $false
    }
    $psqlExe = Join-Path $script:PostgresBinDir "psql.exe"
    if (-not (Test-Path -LiteralPath $psqlExe)) { return $false }
    $pgpassFile = New-PostgresPgPassFile -Password $SuperPasswordPlain
    $env:PGPASSFILE = $pgpassFile
    try {
        $result = & $psqlExe -U postgres -h 127.0.0.1 -p 5432 -tAc "SELECT 1 FROM pg_database WHERE datname='$DbName'" 2>$null
        return ($result -match '1')
    } catch {
        Write-Log "Postgres: could not check database '$DbName' -- $_"
        return $false
    } finally {
        $env:PGPASSFILE = $null
        Remove-PostgresPgPassFile -Path $pgpassFile
    }
}

# Verifies a password actually authenticates against the running Postgres
# server (a trivial SELECT 1) -- called right after obtaining a password
# (decrypted from saved config, or freshly typed) so a wrong/stale
# password produces one clear error immediately, instead of a confusing
# wall of per-game failures that would otherwise all silently degrade to
# "treat as nonexistent" further downstream (every Postgres helper here
# returns $false on any connection error, including a bad password, so a
# wrong password fails safe -- nothing gets corrupted -- but it would
# otherwise look like 20 separate unrelated failures instead of one).
function Test-PostgresPassword {
    param([string]$SuperPasswordPlain)
    $psqlExe = Join-Path $script:PostgresBinDir "psql.exe"
    if (-not (Test-Path -LiteralPath $psqlExe)) { return $false }
    $pgpassFile = New-PostgresPgPassFile -Password $SuperPasswordPlain
    $env:PGPASSFILE = $pgpassFile
    try {
        & $psqlExe -U postgres -h 127.0.0.1 -p 5432 -tAc "SELECT 1" 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    } finally {
        $env:PGPASSFILE = $null
        Remove-PostgresPgPassFile -Path $pgpassFile
    }
}

# =============================================================================
# GPU Fix Setup: detect GPU vendor, scan TeknoParrot GameProfiles for fix
# fields (so newly added games are covered automatically), and apply the
# appropriate values to every registered UserProfile XML.
function Invoke-GpuFixSetup {
    param(
        [string]$UserProfilesDir,
        [string]$TpRoot
    )

    # -- GPU detection ----------------------------------------------------------
    Write-Host ""
    Write-Host "  Detecting GPU..." -ForegroundColor DarkGray
    $detected  = Get-DetectedGpuVendor
    $gpuVendor = $detected.Vendor
    $gpuName   = $detected.Name

    if ($gpuVendor) {
        Write-Host ("  Detected : {0} ({1})" -f $gpuVendor, $gpuName) -ForegroundColor DarkGray
        Write-Log "GPU Fix: detected $gpuVendor ($gpuName)"
    } else {
        Write-Host "  Could not auto-detect GPU vendor." -ForegroundColor Yellow
        if ($gpuName) { Write-Host ("  Adapter  : {0}" -f $gpuName) -ForegroundColor DarkGray }
        $inp = (Read-Host "  Enter GPU vendor (AMD / NVIDIA / Intel) or press Enter to cancel").Trim()
        if ([string]::IsNullOrWhiteSpace($inp)) {
            Write-Host "  GPU fix setup cancelled." -ForegroundColor DarkGray
            Write-Log "GPU Fix: cancelled -- vendor not detected and user did not enter one."
            return
        }
        if     ($inp -imatch '^amd$|^radeon$')     { $gpuVendor = 'AMD'    }
        elseif ($inp -imatch '^nvidia$|^geforce$')  { $gpuVendor = 'NVIDIA' }
        elseif ($inp -imatch '^intel$')             { $gpuVendor = 'Intel'  }
        else {
            Write-Host ("  Unrecognised vendor '{0}'. Use AMD, NVIDIA, or Intel." -f $inp) -ForegroundColor Red
            Write-Log "GPU Fix: cancelled -- unrecognised vendor '$inp'."
            return
        }
        Write-Host ("  Using    : {0}" -f $gpuVendor) -ForegroundColor DarkGray
        Write-Log "GPU Fix: user-specified vendor = $gpuVendor"
    }

    # -- Discover GPU fix field names from TeknoParrot GameProfiles -------------
    # Scans at runtime so newly added games with new fix fields are covered
    # automatically without requiring a script update.
    Write-Host "  Scanning GameProfiles for GPU fix fields..." -ForegroundColor DarkGray
    $gpuFields         = Get-GpuFixFieldNames -TpRoot $TpRoot
    $boolAmdFields     = $gpuFields.BoolFields
    $dropdownGpuFields = $gpuFields.DropdownFields
    if ($gpuFields.GameProfilesFound) {
        Write-Log ("GPU Fix: discovered fields -- Bool AMD: [{0}]  Dropdown GPU: [{1}]" -f `
            ($boolAmdFields -join ', '), ($dropdownGpuFields -join ', '))
    } else {
        Write-Host ("  GameProfiles folder not found -- using built-in field list.") -ForegroundColor DarkGray
        Write-Log "GPU Fix: GameProfiles not found -- using fallback field list."
    }

    # -- Backup UserProfiles before any write ------------------------------------
    # This setup writes vendor-fix fields into every registered profile, so it
    # needs the same backup-before-destructive-operation safety net as
    # Invoke-CursorHideSetup -- without it, a bad GPU detection or a corrupted
    # GameProfiles scan would overwrite every UserProfile XML with no way back.
    $backupRoot = Join-Path $UserProfilesDir "FullBackup"
    $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path $backupRoot ("GpuFix_" + $timestamp)
    try {
        [void][System.IO.Directory]::CreateDirectory($backupRoot)
        [void][System.IO.Directory]::CreateDirectory($backupPath)
    } catch {
        Write-Host "  ERROR: Could not create backup folder: $_" -ForegroundColor Red
        Write-Log "GPU Fix: backup failed -- $_"
        return
    }
    $backupCopyErrs = $null
    # Copy-Item receives FileInfo/DirectoryInfo objects from the pipeline
    # (not path strings), so pipeline binding already bypasses wildcard
    # expansion -- safe even with [, ], $ in game folder names. If this
    # source is ever changed to raw path strings, add -LiteralPath there.
    Get-ChildItem -LiteralPath $UserProfilesDir | Where-Object { $_.Name -ne "FullBackup" } |
        Copy-Item -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable backupCopyErrs
    if ($backupCopyErrs.Count -gt 0) {
        Write-Host ("  WARNING: {0} file(s) could not be backed up." -f $backupCopyErrs.Count) -ForegroundColor Yellow
        Write-Log "GPU Fix: backup had $($backupCopyErrs.Count) error(s)"
    }
    Write-Host ("  Backup: {0}" -f $backupPath) -ForegroundColor DarkGray
    Write-Log "GPU Fix: backup at $backupPath"

    # -- Walk UserProfiles ------------------------------------------------------
    Write-Host ""
    Write-Host "  Applying GPU fixes to registered profiles..." -ForegroundColor DarkGray
    $profiles  = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -ErrorAction SilentlyContinue)
    $updated   = 0
    $unchanged = 0
    $errors    = 0

    foreach ($pf in $profiles) {
        try {
            $doc    = Read-Xml $pf.FullName
            $result = Test-GpuFixUpToDate -Doc $doc -BoolFields $boolAmdFields -DropdownFields $dropdownGpuFields -Vendor $gpuVendor

            if ($result.Changes.Count -gt 0) {
                foreach ($c in $result.Changes) {
                    $c.Node.InnerText = $c.NewValue
                    Write-Log "GPU Fix: $($pf.BaseName) :: $($c.FieldName) $($c.OldValue) -> $($c.NewValue)"
                }
                Save-Xml $doc $pf.FullName
                $updated++
                Write-Host ("    {0}" -f $pf.BaseName) -ForegroundColor Green
            } else {
                $unchanged++
            }
        } catch {
            Write-Host ("    FAILED {0}: {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "GPU Fix: FAILED $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Updated  : {0} profile(s)" -f $updated) -ForegroundColor Green
    if ($unchanged -gt 0) {
        Write-Host ("  No change: {0} (already correct or no GPU fix fields)" -f $unchanged) -ForegroundColor DarkGray
    }
    if ($errors -gt 0) {
        Write-Host ("  Errors   : {0} -- see log for details" -f $errors) -ForegroundColor Red
    }
    Write-Log ("GPU Fix: complete. Vendor={0} Updated={1} Unchanged={2} Errors={3}" -f `
        $gpuVendor, $updated, $unchanged, $errors)
}

# =============================================================================
# Full crosshair setup flow: validate collection, preview, pick, deploy.
# Updates cursor_path under [USB Port 1 guncon2] and [USB Port 2 guncon2] in PCSX2.ini.
# Handles sections that already have cursor_path (replaces), sections that exist without
# it (inserts before the next section header), and missing sections (appends at EOF).
function Set-Pcsx2CursorPaths {
    param([string]$IniPath, [string]$P1Path, [string]$P2Path)
    try {
        $lines   = [System.IO.File]::ReadAllLines($IniPath)
        $out     = New-Object System.Collections.Generic.List[string]
        $targets = @{ 'usb port 1 guncon2' = $P1Path; 'usb port 2 guncon2' = $P2Path }
        $done    = @{ 'usb port 1 guncon2' = $false;  'usb port 2 guncon2' = $false  }
        $sect    = ''

        foreach ($ln in $lines) {
            $t = $ln.Trim()
            if ($t -match '^\[(.+)\]$') {
                if ($targets.ContainsKey($sect) -and -not $done[$sect]) {
                    $out.Add("cursor_path = $($targets[$sect])")
                    $done[$sect] = $true
                }
                $sect = $matches[1].ToLower()
                $out.Add($ln); continue
            }
            if ($t -match '^cursor_path\s*=' -and $targets.ContainsKey($sect)) {
                $out.Add("cursor_path = $($targets[$sect])")
                $done[$sect] = $true; continue
            }
            $out.Add($ln)
        }
        # Handle last section (no following header to trigger flush)
        if ($targets.ContainsKey($sect) -and -not $done[$sect]) {
            $out.Add("cursor_path = $($targets[$sect])")
            $done[$sect] = $true
        }
        # Append sections that were never present in the file
        foreach ($tgt in ($done.Keys | Where-Object { -not $done[$_] })) {
            $hdr = if ($tgt -eq 'usb port 1 guncon2') { '[USB Port 1 guncon2]' } else { '[USB Port 2 guncon2]' }
            $out.Add($hdr); $out.Add("cursor_path = $($targets[$tgt])")
        }
        # Back up before overwriting -- this is the user's PCSX2 emulator
        # config, not a file this script created, so a bad parse should
        # never leave them without their original settings.
        $iniBackup = $IniPath + ".bak_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
        Copy-Item -LiteralPath $IniPath -Destination $iniBackup -ErrorAction Stop
        [System.IO.File]::WriteAllText($IniPath, ($out -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
        Write-Log "Crosshairs: updated PCSX2.ini at $IniPath (backup: $iniBackup)"
    } catch {
        Write-Host ("    WARNING: Could not update PCSX2.ini -- {0}" -f $_) -ForegroundColor Yellow
        Write-Log "Crosshairs: PCSX2.ini update failed -- $_"
    }
}

# Crosshair setup wizard: HTML preview of all crosshair PNGs, P1/P2 picker,
# deploy selected images to all registered lightgun game folders. Optionally
# hides the hardware cursor by setting HideCursor/DisableCursor=1 in every
# lightgun UserProfile (backs up profiles first).
function Invoke-CrosshairSetup {
    param([string]$UserProfilesDir, [string]$GamesInstallFolder, [string]$TpRoot)

    $crosshairsDir = Join-Path $PSScriptRoot "Crosshairs"
    $previewPath   = Join-Path $PSScriptRoot "TeknoParrot-Crosshairs-Preview.html"

    if (-not (Test-Path -LiteralPath $crosshairsDir)) {
        Write-Host "  ERROR: Crosshairs folder not found: $crosshairsDir" -ForegroundColor Red
        Write-Host "  Place PNG crosshair files in a 'Crosshairs' subfolder next to the script." -ForegroundColor Yellow
        Write-Log "Crosshairs: Crosshairs folder not found"; return
    }

    # Scan and validate -- any PNG in the folder is a candidate
    $allFiles = @(Get-ChildItem -LiteralPath $crosshairsDir -Filter "*.png" -File -ErrorAction SilentlyContinue |
                     Sort-Object Name)
    $valid   = [System.Collections.Generic.List[string]]::new()
    $invalid = [System.Collections.Generic.List[string]]::new()

    foreach ($f in $allFiles) {
        if (Test-PngFile -Path $f.FullName) { $valid.Add($f.FullName) }
        else {
            $invalid.Add($f.Name)
            Write-Log "Crosshairs: rejected invalid PNG -- $($f.Name)"
        }
    }

    if ($invalid.Count -gt 0) {
        Write-Host ("  WARNING: {0} file(s) failed PNG validation and were skipped:" -f $invalid.Count) -ForegroundColor Yellow
        foreach ($n in $invalid) { Write-Host "    $n" -ForegroundColor DarkGray }
    }
    if ($valid.Count -eq 0) {
        Write-Host "  No valid PNG crosshairs found in: $crosshairsDir" -ForegroundColor Red
        Write-Log "Crosshairs: no valid PNGs found"; return
    }

    Write-Host ("  Found {0} valid crosshair(s). Generating preview..." -f $valid.Count) -ForegroundColor Cyan
    Export-CrosshairPreview -CrosshairPaths $valid.ToArray() -OutPath $previewPath
    Write-Host "  Preview: $previewPath" -ForegroundColor Cyan
    Write-Host "  Opening in browser -- browse the grid, then come back here." -ForegroundColor DarkCyan
    if (Test-Path -LiteralPath $previewPath -PathType Leaf) { Start-Process -FilePath $previewPath }
    Write-Host ""

    # Remembers the last P1/P2 choice (by filename, not index -- indices shift
    # if PNGs are added/removed from the Crosshairs folder between runs) so a
    # re-run doesn't require re-finding/re-entering the same numbers. A saved
    # name that no longer exists in $valid is silently ignored.
    $crosshairStatePath = Join-Path $PSScriptRoot "TeknoParrot-Manager-crosshairs.json"
    $lastP1Idx = $null; $lastP2Idx = $null
    if (Test-Path -LiteralPath $crosshairStatePath) {
        try {
            $crosshairState = Get-Content -LiteralPath $crosshairStatePath -Raw | ConvertFrom-Json
            if ($crosshairState.P1) {
                $hit = for ($i = 0; $i -lt $valid.Count; $i++) { if ([System.IO.Path]::GetFileNameWithoutExtension($valid[$i]) -eq $crosshairState.P1) { $i; break } }
                if ($null -ne $hit) { $lastP1Idx = $hit }
            }
            if ($crosshairState.P2) {
                $hit = for ($i = 0; $i -lt $valid.Count; $i++) { if ([System.IO.Path]::GetFileNameWithoutExtension($valid[$i]) -eq $crosshairState.P2) { $i; break } }
                if ($null -ne $hit) { $lastP2Idx = $hit }
            }
        } catch { Write-Log "Crosshairs: could not read last-used state -- $_" }
    }

    # Pick P1
    $p1Idx = $null
    while ($null -eq $p1Idx) {
        $promptText = if ($null -ne $lastP1Idx) {
            "  P1 crosshair index (0-{0}, Enter for last used: {1} {2})" -f ($valid.Count - 1), $lastP1Idx, [System.IO.Path]::GetFileNameWithoutExtension($valid[$lastP1Idx])
        } else { "  P1 crosshair index (0-{0})" -f ($valid.Count - 1) }
        $raw = (Read-Host $promptText).Trim()
        if ($raw -eq '' -and $null -ne $lastP1Idx) { $p1Idx = $lastP1Idx }
        elseif ($raw -match '^\d+$' -and $raw.Length -le 9 -and [int]$raw -lt $valid.Count) { $p1Idx = [int]$raw }
        else { Write-Host ("  Enter a number between 0 and {0}." -f ($valid.Count - 1)) -ForegroundColor Yellow }
    }
    # Pick P2
    $p2Idx = $null
    while ($null -eq $p2Idx) {
        $promptText = if ($null -ne $lastP2Idx) {
            "  P2 crosshair index (0-{0}, or same as P1, Enter for last used: {1} {2})" -f ($valid.Count - 1), $lastP2Idx, [System.IO.Path]::GetFileNameWithoutExtension($valid[$lastP2Idx])
        } else { "  P2 crosshair index (0-{0}, or same as P1)" -f ($valid.Count - 1) }
        $raw = (Read-Host $promptText).Trim()
        if ($raw -eq '' -and $null -ne $lastP2Idx) { $p2Idx = $lastP2Idx }
        elseif ($raw -match '^\d+$' -and $raw.Length -le 9 -and [int]$raw -lt $valid.Count) { $p2Idx = [int]$raw }
        else { Write-Host ("  Enter a number between 0 and {0}." -f ($valid.Count - 1)) -ForegroundColor Yellow }
    }

    $p1Name = [System.IO.Path]::GetFileNameWithoutExtension($valid[$p1Idx])
    $p2Name = [System.IO.Path]::GetFileNameWithoutExtension($valid[$p2Idx])
    Write-Host ""
    Write-Host "  P1: $p1Name    P2: $p2Name" -ForegroundColor Green
    Write-Log "Crosshairs: P1=$p1Name  P2=$p2Name"

    try {
        [System.IO.File]::WriteAllText($crosshairStatePath, ([ordered]@{ P1 = $p1Name; P2 = $p2Name } | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
    } catch { Write-Log "Crosshairs: could not save last-used state -- $_" }

    # Locate ElfLdr2 folder -- search common names then any elf-named subfolder
    $elfDir = $null
    foreach ($candidate in @("ElfLdr2","ElfLoader2","elf","elf2","ElfLdr")) {
        $try = Join-Path $TpRoot $candidate
        if (Test-Path -LiteralPath $try) { $elfDir = $try; break }
    }
    if (-not $elfDir) {
        $elfDir = Get-ChildItem -LiteralPath $TpRoot -Directory -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -imatch 'elf' } |
                  Select-Object -First 1 -ExpandProperty FullName
    }

    # Locate pcsx2x6 folder -- search common names then any pcsx2-prefixed subfolder
    $pcsx2Dir = $null
    foreach ($candidate in @("pcsx2x6","PCSX2x6","pcsx2","PCSX2")) {
        $try = Join-Path $TpRoot $candidate
        if (Test-Path -LiteralPath $try) { $pcsx2Dir = $try; break }
    }
    if (-not $pcsx2Dir) {
        $pcsx2Dir = Get-ChildItem -LiteralPath $TpRoot -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -imatch '^pcsx2' } |
                    Select-Object -First 1 -ExpandProperty FullName
    }

    # Deploy
    Write-Host ""
    Write-Host "  Deploying to lightgun games..." -ForegroundColor Cyan
    $deployed = 0; $skipped = 0; $errors = 0; $elfDeployed = $false; $pcsx2Deployed = $false

    $xmlFiles = Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -ne "FullBackup" }

    foreach ($pf in $xmlFiles) {
        try {
            $doc     = Read-Xml $pf.FullName
            if ($null -eq $doc.GameProfile) { continue }
            $gunNode = $doc.GameProfile.SelectSingleNode("GunGame")
            if (-not $gunNode -or $gunNode.InnerText -ne "true") { continue }

            $emuType = ""
            $etNode  = $doc.GameProfile.SelectSingleNode("EmulatorType")
            if ($etNode) { $emuType = $etNode.InnerText.Trim() }

            if ($emuType -eq "ElfLdr2") {
                # All ElfLdr2 lightgun games share one folder -- deploy once
                if (-not $elfDeployed) {
                    $dest = if ($elfDir) { $elfDir } else { $TpRoot }
                    Copy-Item -LiteralPath $valid[$p1Idx] -Destination (Join-Path $dest "P1.png") -Force -ErrorAction Stop
                    Copy-Item -LiteralPath $valid[$p2Idx] -Destination (Join-Path $dest "P2.png") -Force -ErrorAction Stop
                    Write-Host ("    ElfLdr2 -> {0}" -f $dest) -ForegroundColor Green
                    Write-Log "Crosshairs: deployed to ElfLdr2 folder $dest"
                    $elfDeployed = $true
                }
                $deployed++; continue
            }

            if ($emuType -eq "Pcsx2x6") {
                # All Pcsx2x6 lightgun games share one emulator folder -- deploy once
                # Also updates inis\PCSX2.ini with the cursor_path for each USB port.
                if (-not $pcsx2Deployed) {
                    if ($pcsx2Dir) {
                        $p1Dest = Join-Path $pcsx2Dir "P1.png"
                        $p2Dest = Join-Path $pcsx2Dir "P2.png"
                        Copy-Item -LiteralPath $valid[$p1Idx] -Destination $p1Dest -Force -ErrorAction Stop
                        Copy-Item -LiteralPath $valid[$p2Idx] -Destination $p2Dest -Force -ErrorAction Stop
                        $iniPath = Join-Path $pcsx2Dir "inis\PCSX2.ini"
                        if (Test-Path -LiteralPath $iniPath) {
                            Set-Pcsx2CursorPaths -IniPath $iniPath -P1Path $p1Dest -P2Path $p2Dest
                            Write-Host ("    Pcsx2x6 -> {0}  (PCSX2.ini updated)" -f $pcsx2Dir) -ForegroundColor Green
                        } else {
                            Write-Host ("    Pcsx2x6 -> {0}  (PCSX2.ini not found; PNGs copied)" -f $pcsx2Dir) -ForegroundColor Green
                            Write-Log "Crosshairs: Pcsx2x6 PCSX2.ini not found at $iniPath"
                        }
                        Write-Log "Crosshairs: deployed to Pcsx2x6 folder $pcsx2Dir"
                        $pcsx2Deployed = $true
                    } else {
                        Write-Host "    Pcsx2x6: emulator folder not found in TeknoParrot root -- skipped" -ForegroundColor Yellow
                        Write-Log "Crosshairs: Pcsx2x6 folder not found in $TpRoot"
                    }
                }
                $deployed++; continue
            }

            # Standard game: copy to the game exe directory
            $gpNode = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { $skipped++; continue }
            $exeDir = [System.IO.Path]::GetDirectoryName($gpNode.InnerText.Trim())
            if ([string]::IsNullOrWhiteSpace($exeDir) -or -not (Test-Path -LiteralPath $exeDir)) { $skipped++; continue }

            Copy-Item -LiteralPath $valid[$p1Idx] -Destination (Join-Path $exeDir "P1.png") -Force -ErrorAction Stop
            Copy-Item -LiteralPath $valid[$p2Idx] -Destination (Join-Path $exeDir "P2.png") -Force -ErrorAction Stop
            Write-Host ("    {0} -> {1}" -f $pf.BaseName, $exeDir) -ForegroundColor Green
            Write-Log "Crosshairs: deployed $($pf.BaseName) -> $exeDir"
            $deployed++
        } catch {
            Write-Host ("    FAILED {0}: {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "Crosshairs: error on $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Deployed : {0} lightgun game(s)" -f $deployed) -ForegroundColor Green
    if ($skipped -gt 0) { Write-Host ("  Skipped  : {0} (no path or folder not found)" -f $skipped) -ForegroundColor DarkGray }
    if ($errors  -gt 0) { Write-Host ("  Errors   : {0}" -f $errors) -ForegroundColor Red }
    Write-Log ("Crosshairs: done. Deployed={0} Skipped={1} Errors={2}" -f $deployed, $skipped, $errors)

    Write-Host ""
    $hideCursor = (Read-Host "  Also hide the Windows cursor for all lightgun games? (Y/N)").Trim().ToUpper()
    if ($hideCursor -eq "Y") {
        Write-Host ""
        Invoke-CursorHideSetup -UserProfilesDir $UserProfilesDir
    }
}

# =============================================================================
# Sets the cursor-hide field (HideCursor / "Hide Cursor" / DisableCursor) to 1
# in every registered lightgun UserProfile. Backs up UserProfiles first since
# it modifies XMLs. Skips profiles that have no cursor field or are already set.
function Invoke-CursorHideSetup {
    param([string]$UserProfilesDir)

    $cursorFields = @("HideCursor", "Hide Cursor", "DisableCursor")

    $backupRoot = Join-Path $UserProfilesDir "FullBackup"
    $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path $backupRoot ("CursorHide_" + $timestamp)
    try {
        [void][System.IO.Directory]::CreateDirectory($backupRoot)
        [void][System.IO.Directory]::CreateDirectory($backupPath)
    } catch {
        Write-Host "  ERROR: Could not create backup folder: $_" -ForegroundColor Red
        Write-Log "CursorHide: backup failed -- $_"
        return
    }
    $backupCopyErrs = $null
    # Copy-Item receives FileInfo/DirectoryInfo objects from the pipeline
    # (not path strings), so pipeline binding already bypasses wildcard
    # expansion -- safe even with [, ], $ in game folder names. If this
    # source is ever changed to raw path strings, add -LiteralPath there.
    Get-ChildItem -LiteralPath $UserProfilesDir | Where-Object { $_.Name -ne "FullBackup" } |
        Copy-Item -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable backupCopyErrs
    if ($backupCopyErrs.Count -gt 0) {
        Write-Host ("  WARNING: {0} file(s) could not be backed up." -f $backupCopyErrs.Count) -ForegroundColor Yellow
        Write-Log "CursorHide: backup had $($backupCopyErrs.Count) error(s)"
    }
    Write-Host ("  Backup: {0}" -f $backupPath) -ForegroundColor DarkGray
    Write-Log "CursorHide: backup at $backupPath"

    $updated = 0; $alreadySet = 0; $noField = 0; $errors = 0

    $xmlFiles = Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -ne "FullBackup" }

    foreach ($pf in $xmlFiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if ($null -eq $doc.GameProfile) { continue }
            $gunNode = $doc.GameProfile.SelectSingleNode("GunGame")
            if (-not $gunNode -or $gunNode.InnerText -ne "true") { continue }

            $changed = $false
            $wasSet  = $false
            foreach ($fieldName in $cursorFields) {
                $fi = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$(ConvertTo-XPathStringLiteral $fieldName)]")
                if ($null -eq $fi) { continue }
                $fv = $fi.SelectSingleNode("FieldValue")
                if ($null -eq $fv) { continue }
                if ($fv.InnerText -eq "1") { $wasSet = $true; continue }
                $fv.InnerText = "1"
                $changed = $true
            }

            if ($changed) {
                Save-Xml $doc $pf.FullName
                Write-Host ("    Updated : {0}" -f $pf.BaseName) -ForegroundColor Green
                Write-Log "CursorHide: updated $($pf.BaseName)"
                $updated++
            } elseif ($wasSet) {
                $alreadySet++
            } else {
                $noField++
            }
        } catch {
            Write-Host ("    FAILED  {0}: {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "CursorHide: error on $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Updated  : {0} lightgun game(s)" -f $updated) -ForegroundColor Green
    if ($alreadySet -gt 0) { Write-Host ("  Already  : {0} (cursor already hidden)" -f $alreadySet) -ForegroundColor DarkGray }
    if ($noField   -gt 0) { Write-Host ("  No field : {0} (profile has no cursor field)" -f $noField) -ForegroundColor DarkGray }
    if ($errors    -gt 0) { Write-Host ("  Errors   : {0}" -f $errors) -ForegroundColor Red }
    Write-Log ("CursorHide: done. Updated={0} AlreadySet={1} NoField={2} Errors={3}" -f $updated, $alreadySet, $noField, $errors)
}

# =============================================================================
# Extracts a ZIP to a destination directory using \\?\ extended-length paths on
# every file write, bypassing Windows' 260-character MAX_PATH limit. Replaces
# ZipFile::ExtractToDirectory which throws PathTooLongException for games with
# deeply-nested internal paths. Includes a zip-slip guard.
function Expand-ZipFileSafe {
    param([string]$ZipPath, [string]$DestDir, [string]$GameName = '')

    # GetFullPath on the (short) base is safe. We deliberately avoid calling
    # GetFullPath on the combined base+entry path: on .NET 4.x (PS 5.1) that
    # throws PathTooLongException before \\?\ is ever applied, defeating the
    # whole purpose of this function.
    $destFull  = [System.IO.Path]::GetFullPath($DestDir).TrimEnd('\')
    # The \\?\ long-path prefix has a different form for UNC paths
    # (\\server\share\...) than for drive-letter paths -- a naive
    # '\\?\' + $destFull concatenation produces an invalid
    # '\\?\\\server\share\...' for UNC destinations. Build the correct
    # prefix once so every long-path target below uses the right form.
    $longPrefixBase = if ($destFull -match '^\\\\[^\?]') {
        '\\?\UNC\' + $destFull.Substring(2)
    } else {
        '\\?\' + $destFull
    }
    $label     = if ($GameName) { $GameName } else { [System.IO.Path]::GetFileNameWithoutExtension($ZipPath) }
    $archive   = $null
    try {
        $archive   = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $fileCount = ($archive.Entries | Where-Object { $_.Name -ne '' }).Count
        $current   = 0
        foreach ($entry in $archive.Entries) {
            $rel = $entry.FullName.Replace('/', '\').TrimStart('\')

            # Zip-slip guard: reject traversal (..) and absolute paths.
            # String-level check avoids the 260-char limit of GetFullPath on
            # .NET 4.x. Rooted check blocks entries like C:\evil\path.exe.
            if ($rel -match '(^|\\)\.\.($|\\)' -or [System.IO.Path]::IsPathRooted($rel)) {
                throw "ZIP entry escapes destination folder: $($entry.FullName)"
            }

            # Directory entry: Name is empty string when FullName ends with /
            if ($entry.Name -eq '' -or $rel.EndsWith('\')) {
                [void][System.IO.Directory]::CreateDirectory($longPrefixBase + '\' + $rel.TrimEnd('\'))
                continue
            }

            $current++
            if ($fileCount -gt 0) {
                $pct = [Math]::Min(100, [int](($current / $fileCount) * 100))
                Write-Progress -Activity "Extracting: $label" `
                               -Status ("File {0} of {1}" -f $current, $fileCount) `
                               -PercentComplete $pct
            }

            $longTarget = $longPrefixBase + '\' + $rel
            # CreateDirectory is idempotent; no Exists check needed (also avoids TOCTOU).
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($longTarget))

            $src = $entry.Open()
            try {
                $dst = [System.IO.File]::Open($longTarget, [System.IO.FileMode]::Create,
                           [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                try   { $src.CopyTo($dst) }
                finally { $dst.Dispose() }
            } finally { $src.Dispose() }
        }
    } finally {
        if ($archive) { $archive.Dispose() }
        Write-Progress -Activity "Extracting: $label" -Completed
    }
}

# Extracts NAS ZIPs to a local folder. Tracks state to skip unchanged games.
# Never deletes local games. ZIP base names listed in $noSync are skipped.
# If $onlySync is non-empty, only ZIPs whose base name is in the list are extracted.
function Invoke-AutoSync {
    param([string]$zipSource, [string]$installFolder, [string]$syncStatePath,
          $noSync = @(), $onlySync = @(), [bool]$retroBat = $false, [bool]$DryRun = $false,
          [hashtable]$datIndex = $null, [string]$userProfilesDir = '')

    $syncState = @{}
    if (Test-Path -LiteralPath $syncStatePath) {
        try {
            $loaded = Get-Content -LiteralPath $syncStatePath -Raw | ConvertFrom-Json
            foreach ($prop in $loaded.PSObject.Properties) { $syncState[$prop.Name] = $prop.Value }
        } catch { Write-Log "AutoSync: could not read sync state -- starting fresh." }
    }

    $zipFiles = Get-ChildItem -LiteralPath $zipSource -Filter *.zip -ErrorAction SilentlyContinue
    if (-not $zipFiles -or $zipFiles.Count -eq 0) {
        Write-Host "  No ZIP files found in source. Skipping extraction." -ForegroundColor Yellow
        $subdirHits = @(Get-ChildItem -LiteralPath $zipSource -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $c = (Get-ChildItem -LiteralPath $_.FullName -Filter *.zip -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($c -gt 0) { [PSCustomObject]@{ Path = $_.FullName; Count = $c } }
        })
        if ($subdirHits.Count -gt 0) {
            Write-Host "  Tip: ZIPs found one level down -- point the source path at one of these directly:" -ForegroundColor Cyan
            foreach ($sd in $subdirHits) {
                Write-Host "    $($sd.Path)  ($($sd.Count) ZIPs)" -ForegroundColor DarkCyan
            }
        }
        return @{ Synced = 0; UpToDate = 0; Failed = 0; Skipped = 0; WouldSync = 0 }
    }

    $synced = 0; $upToDate = 0; $failed = 0; $skipped = 0; $wouldSync = 0

    if ($onlySync.Count -gt 0) {
        Write-Host "  Whitelist active: only extracting $($onlySync.Count) game(s) listed in onlySync." -ForegroundColor Cyan
    }

    # Build a normalised-name map of every folder already in the staging
    # directory. Normalisation removes spaces immediately before ( or [ so that
    # "Game (ver) [Platform] [TP]" (old convention) and
    # "Game(ver)[Platform][TP]" (new convention) map to the same key.
    # This prevents AutoSync from creating duplicate folders when a game was
    # extracted under the old naming convention and the ZIP now uses the new one.
    $normalizedFolderMap = Get-StagingFolderMap $installFolder

    foreach ($zip in $zipFiles) {
        $rawName    = [System.IO.Path]::GetFileNameWithoutExtension($zip.Name)
        if ($noSync -contains $rawName) {
            Write-Host "  Skipped (override) : $rawName" -ForegroundColor DarkGray
            $skipped++; continue
        }
        # Skip collection metadata files (changelog, game notes, readme).
        # These start with "!TeknoParrot Collection" regardless of date suffix.
        if ($rawName -like '!TeknoParrot Collection*') {
            Write-Host "  Skipped (metadata)  : $rawName" -ForegroundColor DarkGray
            $skipped++; continue
        }
        # If a whitelist is active, skip anything not on it.
        if ($onlySync.Count -gt 0 -and $onlySync -notcontains $rawName) {
            $skipped++; continue
        }
        # Use the raw ZIP base name as the folder name so it matches the
        # collection's naming convention exactly -- e.g.
        # "Game Name (ver) (date) [Platform] [TP]". This avoids garbled names
        # and prevents duplicate folders alongside manually-extracted games.
        $extractFolderName = if ($retroBat) { "$rawName.teknoparrot" } else { $rawName }
        $extractDir = Join-Path $installFolder $extractFolderName
        # Defence in depth: confirm the resolved folder still lands inside
        # $installFolder before any destructive use below. A ZIP base name
        # cannot legally contain \ or / on Windows, so this should never
        # trip, but every other site that joins a script folder with an
        # externally-influenced name carries this same guard.
        if (-not (Test-PathInside $extractDir $installFolder)) {
            Write-Host "  Skipped (unsafe path) : $rawName" -ForegroundColor Red
            Write-Log "AutoSync: skipped '$rawName' -- resolved extract path '$extractDir' is outside install folder '$installFolder'"
            $skipped++; continue
        }
        # Sentinel lives next to the game folder (not inside it) so we do not
        # need to pre-create the game directory. Expand-Archive creates the
        # directory itself; pre-creating it caused PS 5.1 to throw "already
        # exists" even when -Force was supplied.
        $sentinel   = Join-Path $installFolder "$extractFolderName.extracting"
        $nasModStr  = $zip.LastWriteTimeUtc.ToString("o")
        $stored     = $syncState[$rawName]

        # Resolve an existing folder using the normalised map, which matches
        # both exact names and old-convention names for the same game. If
        # that fails (e.g. a folder renamed to something the name-matching
        # logic can't predict), fall back to the game's own registered
        # GamePath, if any -- see Resolve-RegisteredGameFolder, issue #13.
        $normZip       = $rawName -replace ' (?=[\[\(])', ''
        $matchedFolder = if ($normalizedFolderMap.ContainsKey($normZip)) { $normalizedFolderMap[$normZip] } else { $null }
        if (-not $matchedFolder) { $matchedFolder = Resolve-RegisteredGameFolder $rawName $datIndex $userProfilesDir }

        $needsSync = $false; $reason = ""
        if ($null -eq $stored) {
            # Game not yet tracked. Only treat the folder as "already extracted"
            # if the matched folder (exact or old-convention) has content --
            # empty folders are failed extractions that should be retried.
            $hasContent = $matchedFolder -and
                          (-not (Test-Path -LiteralPath $sentinel)) -and
                          ((Get-ChildItem -LiteralPath $matchedFolder -Force -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0)
            if ($hasContent) {
                $syncState[$rawName] = [ordered]@{
                    NasSize = $zip.Length; NasLastModified = $nasModStr
                    LocalPath = $matchedFolder; SyncedAt = (Get-Date).ToUniversalTime().ToString("o")
                }
                $label = if ($matchedFolder -ne $extractDir) { "  Already extracted  : $rawName`n    (old name: $(Split-Path $matchedFolder -Leaf))" } else { "  Already extracted  : $rawName" }
                Write-Host $label -ForegroundColor DarkGray
                $upToDate++; continue
            }
            $needsSync = $true; $reason = "new"
        } elseif ([long]$stored.NasSize -ne $zip.Length -or $stored.NasLastModified -ne $nasModStr) {
            $needsSync = $true; $reason = "changed on NAS"
        } elseif (-not (($stored.LocalPath -and (Test-Path -LiteralPath $stored.LocalPath)) -or (Test-Path -LiteralPath $extractDir))) {
            if ($matchedFolder -and (Test-Path -LiteralPath $matchedFolder)) {
                # Folder was renamed since the last sync (e.g. a manual PATH
                # TOO LONG short-name rename per ACTION REQUIRED, issue #13)
                # -- found via the normalised map. Heal the stored path so
                # future runs hit the Test-Path fast path above directly.
                $stored.LocalPath = $matchedFolder
            } else {
                $needsSync = $true; $reason = "not extracted"
            }
        } elseif (Test-Path -LiteralPath $sentinel) {
            $needsSync = $true; $reason = "incomplete previous extraction"
        }

        if (-not $needsSync) { Write-Host "  Up to date : $rawName" -ForegroundColor DarkGray; $upToDate++; continue }

        if ($DryRun) {
            Write-Host "  Would extract ($reason) : $rawName" -ForegroundColor Yellow
            Write-Log "AutoSync DryRun: would extract $rawName ($reason)"
            $wouldSync++
            continue
        }

        Write-Host "  Extracting ($reason) : $rawName" -ForegroundColor Yellow
        Write-Log "AutoSync: extracting $rawName ($reason)"

        # The sentinel's entire lifecycle -- creation and guaranteed cleanup --
        # is owned by this single try/finally. The finally block has one
        # responsibility: remove the sentinel. It runs unconditionally on
        # success, on any exception, on continue, and on Ctrl+C
        # (PipelineStoppedException), because try/finally always executes its
        # finally clause before control leaves the block, regardless of how.
        try {
            # Create sentinel before any file operations. An unremoved sentinel
            # on the next run triggers a re-extraction, keeping state consistent.
            # If creation itself fails, the outer catch handles it and the
            # finally still runs (Remove-Item on a missing file is a no-op).
            [System.IO.File]::WriteAllText($sentinel, '', (New-Object System.Text.UTF8Encoding $false))

            # All extraction work is nested here so the sentinel's finally
            # always fires after it completes, regardless of how it exits.
            try {
                # Clear any existing (stale or partial) game folder before
                # extracting. Treat removal failures as fatal: a partial old
                # folder combined with a fresh extraction produces a corrupt
                # mixed-version game.
                if (Test-Path -LiteralPath $extractDir) {
                    $removeErrs = @()
                    Remove-Item -LiteralPath $extractDir -Recurse -Force `
                                -ErrorAction SilentlyContinue -ErrorVariable removeErrs
                    if ($removeErrs.Count -gt 0) {
                        Write-Host "    FAILED (could not clear existing folder -- files may be in use):" -ForegroundColor Red
                        Write-Host "    $($removeErrs[0])" -ForegroundColor Red
                        Write-Log "AutoSync: FAILED $rawName -- could not clear $extractDir : $($removeErrs[0])"
                        # Remove the sync-state entry so next run re-attempts rather
                        # than treating a corrupt/partial folder as up to date.
                        [void]$syncState.Remove($rawName)
                        $failed++
                        continue   # outer finally fires before the loop advances
                    }
                }
                # Expand-ZipFileSafe uses \\?\ extended-length paths for every file
                # write, bypassing MAX_PATH. The destination folder does not exist
                # yet (cleared above); the function creates it during extraction.
                Expand-ZipFileSafe -ZipPath $zip.FullName -DestDir $extractDir -GameName $rawName
                $syncState[$rawName] = [ordered]@{
                    NasSize = $zip.Length; NasLastModified = $nasModStr
                    LocalPath = $extractDir; SyncedAt = (Get-Date).ToUniversalTime().ToString("o")
                }
                Write-Host "    -> $extractDir" -ForegroundColor Green
                Write-Log "AutoSync: completed $rawName -> $extractDir"
                $synced++
            } catch {
                Write-Host "    FAILED : $_" -ForegroundColor Red
                Write-Log "AutoSync: FAILED $rawName -- $_"
                # Remove the partial folder so the next run does not misclassify
                # a half-extracted game as already complete (sentinel gone + some
                # files present = indistinguishable from a successful extraction).
                if (-not [string]::IsNullOrWhiteSpace($extractDir)) {
                    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                $failed++
            }
        } catch {
            # Reached only when WriteAllText failed (sentinel could not be created).
            Write-Host "    FAILED (could not create extraction sentinel): $_" -ForegroundColor Red
            Write-Log "AutoSync: FAILED $rawName -- sentinel creation error: $_"
            $failed++
        } finally {
            # Sole responsibility of this block: remove the sentinel file.
            # Intentionally the only statement here so nothing can prevent it
            # from running or delay it. Remove-Item with SilentlyContinue is
            # safe even when the sentinel was never created.
            Remove-Item -LiteralPath $sentinel -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $DryRun) {
        try { [System.IO.File]::WriteAllText($syncStatePath, ($syncState | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding $false)) }
        catch { Write-Log "AutoSync: WARNING -- could not save sync state: $_" }
    }

    return @{ Synced = $synced; UpToDate = $upToDate; Failed = $failed; Skipped = $skipped; WouldSync = $wouldSync }
}

# Builds a lookup of TeknoParrot profiles keyed by their executable name(s)
# (lowercased). Each <ExecutableName> may contain multiple alternatives
# separated by ; or | -- all alternatives are indexed so any matching file
# found on disk correctly identifies the game.
function Build-ProfileIndex {
    param([string]$gameProfilesDir)
    $index = @{}
    $templates = Get-ChildItem -LiteralPath $gameProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue
    foreach ($tpl in $templates) {
        $exe = Get-PrimaryExecutableName $tpl.FullName
        if ($exe -and $exe.Trim() -ne "") {
            foreach ($alt in (Get-ExeAlternatives $exe.Trim())) {
                $k = $alt.ToLower()
                if (-not $index.ContainsKey($k)) { $index[$k] = @() }
                $index[$k] += [pscustomobject]@{
                    Code         = $tpl.BaseName
                    TemplatePath = $tpl.FullName
                    ExeName      = $exe.Trim()
                }
            }
        }
    }
    return $index
}

# Streaming XmlReader parser for No-Intro Logiqx XML dat files.
# Reads <game name="..."><GameProfile>...<Executable>... without loading the
# entire document into memory -- required for the 584 MB collection dat.
# Skips <rom> nodes (hash tables) to stay fast.
# Returns normalised-name -> { ProfileCode, Executable } hashtable.
function Build-DatIndexFromStream {
    param([System.IO.Stream]$stream)
    $index    = @{}
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.IgnoreWhitespace = $true
    $settings.DtdProcessing    = [System.Xml.DtdProcessing]::Prohibit
    $reader = [System.Xml.XmlReader]::Create($stream, $settings)
    try {
        $gameName    = ''
        $profCode    = ''
        $exePath     = ''
        $insideGame  = $false
        $currentElem = ''
        # Skip() already advances the reader onto the next sibling node (the
        # following <rom>, or the </game> EndElement if that was the last
        # one) -- it does NOT need (or want) a further Read() to get there.
        # The loop used to call Read() unconditionally every iteration, so
        # after every Skip() it silently consumed and discarded whatever
        # node Skip() had just landed on. With dozens to hundreds of <rom>
        # entries per game, that discarded one real node per skip, and once
        # the cumulative drift landed exactly on a game's own </game> node,
        # that game's EndElement (and its ProfileCode/Executable capture)
        # never fired at all. Confirmed empirically against a real
        # collection dat: this silently dropped roughly half of all <game>
        # entries (493 opened, only 236 closed) before this fix, regardless
        # of whether the game had a valid ProfileCode. See issue #12.
        $advance = $true
        while ($true) {
            if ($advance) { if (-not $reader.Read()) { break } }
            $advance = $true
            if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                $currentElem = $reader.Name
                if ($currentElem -eq 'game') {
                    $gameName    = $reader.GetAttribute('name')
                    $profCode    = ''
                    $exePath     = ''
                    $insideGame  = $true
                } elseif ($currentElem -eq 'rom' -and $insideGame) {
                    $reader.Skip()   # each <game> has hundreds of <rom> hash entries; skip for perf
                    $currentElem = ''
                    $advance     = $false   # already positioned on the next node -- don't double-advance
                }
            } elseif ($reader.NodeType -eq [System.Xml.XmlNodeType]::Text -and $insideGame) {
                if     ($currentElem -eq 'GameProfile')                           { $profCode = $reader.Value }
                elseif ($currentElem -eq 'Executable' -and -not $exePath) { $exePath  = $reader.Value }
            } elseif ($reader.NodeType -eq [System.Xml.XmlNodeType]::EndElement -and $reader.Name -eq 'game') {
                $insideGame = $false
                if ($profCode -and $gameName) {
                    $normName = Get-NormalizedGameKey $gameName
                    if ($normName -and -not $index.ContainsKey($normName)) {
                        $index[$normName] = [pscustomobject]@{
                            ProfileCode = $profCode.Trim()
                            Executable  = $exePath.Trim()
                        }
                    }
                }
            }
        }
    } finally {
        $reader.Close()
    }
    return $index
}

# Reads the collection dat directly from inside the Eggman ZIP without extracting.
# ZipArchive is opened, the matching entry stream is passed to Build-DatIndexFromStream,
# and the archive is disposed in the finally block regardless of outcome.
function Build-DatIndexFromZip {
    param([string]$zipPath, [string]$entryPattern = '*Collection*_RomVault*.dat')
    $za = $null
    try {
        $za    = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        $entry = @($za.Entries | Where-Object { $_.FullName -like $entryPattern })[0]
        if (-not $entry) {
            Write-Host ("  WARNING: No dat entry matching '{0}' in ZIP." -f $entryPattern) -ForegroundColor Yellow
            Write-Log ("DatIndex (ZIP): no entry matching '{0}'." -f $entryPattern)
            return @{}
        }
        Write-Host ("    Reading: {0}" -f $entry.Name) -ForegroundColor DarkGray
        $stream = $entry.Open()
        try   { return Build-DatIndexFromStream $stream }
        finally { if ($stream) { $stream.Close() } }
    } catch {
        Write-Host ("  WARNING: Could not read dat from ZIP -- {0}" -f $_) -ForegroundColor Yellow
        Write-Log "DatIndex (ZIP): parse failed -- $_"
        return @{}
    } finally {
        if ($za) { $za.Dispose() }
    }
}


# Parses a No-Intro style TeknoParrot dat file from disk using streaming XmlReader.
# Replaces the old DOM-based approach which could not handle the 584 MB collection dat.
# Returns normalised-name -> { ProfileCode, Executable } hashtable.
function Build-DatIndex {
    param([string]$datPath)
    try {
        $fs = [System.IO.File]::OpenRead($datPath)
        try   { return Build-DatIndexFromStream $fs }
        finally { if ($fs) { $fs.Close() } }
    } catch {
        Write-Host ("  WARNING: Could not parse dat file -- {0}" -f $_) -ForegroundColor Yellow
        Write-Log "DatIndex: parse failed -- $_"
        return @{}
    }
}

# Reads the plain-text game-notes file bundled in the Eggman ZIP.
# Format: sections delimited by lines of 60+ '=' chars.
# First non-blank line of each section: "Game Name (ProfileCode)"
# Remaining lines: the note body.
# Returns ProfileCode.ToLower() -> trimmed note text hashtable.
function Build-GameNotesIndexFromStream {
    param([System.IO.Stream]$stream)
    $index   = @{}
    $reader  = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
    try {
        $code       = ''
        $noteLines  = New-Object System.Collections.Generic.List[string]
        $inSection  = $false
        $headerRead = $false

        while (-not $reader.EndOfStream) {
            $ln = $reader.ReadLine()
            if ($ln -match '^={60,}') {
                if ($code -and $noteLines.Count -gt 0) {
                    $body = (($noteLines | Where-Object { $_.Trim() }) -join "`n").Trim()
                    if ($body) { $index[$code] = $body }
                }
                $code = ''; $noteLines.Clear(); $inSection = $true; $headerRead = $false
                continue
            }
            if (-not $inSection) { continue }
            if (-not $headerRead) {
                if ([string]::IsNullOrWhiteSpace($ln)) { continue }
                $m = [regex]::Match($ln, '\(([A-Za-z][A-Za-z0-9_]*)\)\s*$')
                if ($m.Success) { $code = $m.Groups[1].Value.ToLower() }
                $headerRead = $true
            } else {
                $noteLines.Add($ln)
            }
        }
        if ($code -and $noteLines.Count -gt 0) {
            $body = (($noteLines | Where-Object { $_.Trim() }) -join "`n").Trim()
            if ($body) { $index[$code] = $body }
        }
    } finally { $reader.Close() }
    return $index
}

function Build-GameNotesIndex {
    param([string]$path)
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try   { return Build-GameNotesIndexFromStream $fs }
        finally { if ($fs) { $fs.Close() } }
    } catch { Write-Log "NotesIndex: parse failed -- $_"; return @{} }
}

function Build-GameNotesIndexFromZip {
    param([string]$zipPath)
    $za = $null
    try {
        $za    = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        $entry = @($za.Entries | Where-Object { $_.Name -like '*.txt' -and $_.Name -ilike '*note*' })[0]
        if (-not $entry) { return @{} }
        Write-Host ("    Reading: {0}" -f $entry.Name) -ForegroundColor DarkGray
        $stream = $entry.Open()
        try   { return Build-GameNotesIndexFromStream $stream }
        finally { if ($stream) { $stream.Close() } }
    } catch { Write-Log "NotesIndex (ZIP): parse failed -- $_"; return @{} }
    finally  { if ($za) { $za.Dispose() } }
}

# Queries the teknogods/TeknoParrotUI GitHub repo tree for all GameProfile XML
# filenames. Falls back to scanning the local GameProfiles folder if GitHub is
# unreachable. Returns a HashSet[string] of profile code stems (e.g. "BladeArcus").
function Get-TeknoParrotProfileSet {
    param([string]$localGameProfilesDir = '')
    $result = New-Object 'System.Collections.Generic.HashSet[string]'([StringComparer]::OrdinalIgnoreCase)
    $loaded = $false
    # Resolve the repo's actual default branch instead of hardcoding "master" --
    # if teknogods/TeknoParrotUI ever renames its default branch, this still
    # finds it. Falls back to "master" (today's known default) on any failure
    # so a transient API error doesn't block profile discovery entirely.
    $branch = 'master'
    try {
        $repoResp = Invoke-WebRequest -Uri 'https://api.github.com/repos/teknogods/TeknoParrotUI' `
                        -UseBasicParsing -TimeoutSec 10 -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
        $defaultBranch = ($repoResp.Content | ConvertFrom-Json).default_branch
        if (-not [string]::IsNullOrWhiteSpace($defaultBranch)) { $branch = $defaultBranch }
    } catch {
        Write-Log "ProfileSet (GitHub): could not resolve default branch, falling back to 'master' -- $_"
    }
    $branchEncoded = [System.Uri]::EscapeDataString($branch)
    $apiUri = "https://api.github.com/repos/teknogods/TeknoParrotUI/git/trees/$branchEncoded?recursive=1"
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $apiUri -UseBasicParsing -TimeoutSec 20 `
                        -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
            $tree   = ($resp.Content | ConvertFrom-Json).tree
            $prefix = 'TeknoParrotUi.Common/GameProfiles/'
            foreach ($node in $tree) {
                if ($node.type -eq 'blob' -and $node.path -like ($prefix + '*.xml')) {
                    $stem = [System.IO.Path]::GetFileNameWithoutExtension($node.path.Substring($prefix.Length))
                    if ($stem -match '^[\w]+$') { [void]$result.Add($stem) }   # security: reject stems with path separators or dots
                }
            }
            if ($result.Count -gt 0) {
                Write-Log "ProfileSet (GitHub): $($result.Count) profiles from teknogods/TeknoParrotUI."
                $loaded = $true
            } else {
                Write-Log "ProfileSet (GitHub): 0 profiles returned -- API may have changed."
            }
            break
        } catch {
            $status = 0
            if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
            if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) {
                Write-Log "ProfileSet (GitHub): query failed -- $_"; break
            }
            Write-Log "ProfileSet (GitHub): attempt $attempt failed, retrying in 5s -- $_"
            Start-Sleep -Seconds 5
        }
    }
    if (-not $loaded -and $localGameProfilesDir -and (Test-Path -LiteralPath $localGameProfilesDir)) {
        Get-ChildItem -LiteralPath $localGameProfilesDir -Filter '*.xml' -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $s = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
                if ($s -match '^[\w]+$') { [void]$result.Add($s) }
            }
        Write-Log "ProfileSet (local fallback): $($result.Count) profiles from $localGameProfilesDir"
    }
    return $result
}

# Resolves a dat ProfileCode to the correct template filename stem.
# Priority: (1) exact local template; (2) code in GitHub profileSet; (3) fuzzy
# match against profileSet above $FuzzyAutoThreshold; (4) return original.
function Resolve-ProfileCode {
    param([string]$code, [string]$gameProfilesDir,
          [System.Collections.Generic.HashSet[string]]$profileSet = $null)
    if (-not $code) { return $code }
    if ($gameProfilesDir -and (Test-Path -LiteralPath (Join-Path $gameProfilesDir ($code + ".xml")))) {
        return $code
    }
    if ($null -eq $profileSet -or $profileSet.Count -eq 0) { return $code }
    if ($profileSet.Contains($code)) { return $code }
    $normCode  = Get-NormalizedGameKey $code
    $bestScore = 0.0
    $bestMatch = $null
    foreach ($candidate in $profileSet) {
        $score = Get-DiceSimilarity $normCode (Get-NormalizedGameKey $candidate)
        if ($score -gt $bestScore) { $bestScore = $score; $bestMatch = $candidate }
    }
    if ($bestScore -ge $FuzzyAutoThreshold -and $null -ne $bestMatch -and $bestMatch -match '^[\w]+$') {
        Write-Log ("Resolve-ProfileCode: '{0}' -> '{1}' (score {2})" -f $code, $bestMatch, [Math]::Round($bestScore,2))
        return $bestMatch
    }
    # Below threshold -- return the original code unchanged (not $null).
    # Register-Games depends on receiving a usable string even when resolution fails.
    return $code
}

# Queries the GitHub API for the latest Eggman dat release asset.
# Eggmansworld/Datfiles posted its final release ("LAST UPDATE FROM THIS
# REPO!!") and moved the TeknoParrot dats to Eggmansworld/TeknoParrot.
# The new repo also switched from a fixed "teknoparrot" release tag to a
# date-based tag per release (e.g. "2026-06-17"), so a fixed-tag lookup
# can no longer work -- query "latest" instead. Asset naming is unchanged
# (still matches 'TeknoParrot*Collection*RomVault*.zip').
# Returns [pscustomobject]@{DownloadUrl; FileName; SizeMB} or $null on failure.
function Get-EggmanDatRelease {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $apiUri = 'https://api.github.com/repos/Eggmansworld/TeknoParrot/releases/latest'
            $resp   = Invoke-WebRequest -Uri $apiUri -UseBasicParsing -TimeoutSec 20 `
                          -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
            $rel    = $resp.Content | ConvertFrom-Json
            $asset  = @($rel.assets) | Where-Object { $_.name -like 'TeknoParrot*Collection*RomVault*.zip' } |
                          Select-Object -First 1
            if (-not $asset) { return $null }
            if ($asset.browser_download_url -notmatch '^https://[a-zA-Z0-9._-]*(github\.com|githubusercontent\.com)/') {
                Write-Log "EggmanDat: unexpected download URL format -- skipping."
                return $null
            }
            return [pscustomobject]@{
                DownloadUrl = $asset.browser_download_url
                FileName    = $asset.name
                SizeMB      = [Math]::Round($asset.size / 1MB, 1)
            }
        } catch {
            $status = 0
            if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
            if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) {
                Write-Log "EggmanDat: GitHub release query failed -- $_"; return $null
            }
            Write-Log "EggmanDat: attempt $attempt failed, retrying in 5s -- $_"
            Start-Sleep -Seconds 5
        }
    }
    return $null
}

# Downloads the Eggman dat ZIP. Uses BITS (shows a progress bar) with an
# Invoke-WebRequest fallback. Cleans up any partial file on failure.
function Invoke-EggmanDatDownload {
    param([string]$downloadUrl, [string]$savePath)
    try {
        $bitsOk = $false
        $bitsSvc = try { Get-Service -Name BITS -ErrorAction Stop } catch { $null }
        if ($bitsSvc -ne $null -and $bitsSvc.Status -eq 'Running') {
            try {
                Start-BitsTransfer -Source $downloadUrl -Destination $savePath `
                    -Description "TeknoParrot Eggman dat" `
                    -DisplayName "Downloading dat ZIP..." `
                    -ErrorAction Stop
                $bitsOk = $true
            } catch {
                Write-Log "EggmanDat: BITS transfer failed (${_}), trying Invoke-WebRequest."
            }
        }
        if (-not $bitsOk) {
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $savePath -UseBasicParsing -ErrorAction Stop
                    break
                } catch {
                    $status = 0
                    if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
                    try { if (Test-Path -LiteralPath $savePath) { [System.IO.File]::Delete($savePath) } } catch {}
                    if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) { throw }
                    Write-Host ("  Attempt $attempt failed -- retrying in 10s...") -ForegroundColor Yellow
                    Write-Log "EggmanDat: download attempt $attempt failed -- retrying"
                    Start-Sleep -Seconds 10
                }
            }
        }
        Write-DownloadAudit -Source $downloadUrl -FileName ([System.IO.Path]::GetFileName($savePath)) -Path $savePath
        return $true
    } catch {
        Write-Host ("  Download failed: {0}" -f $_) -ForegroundColor Red
        Write-Log "EggmanDat: download failed -- $_"
        try { if (Test-Path -LiteralPath $savePath) { [System.IO.File]::Delete($savePath) } } catch {}
        return $false
    }
}

# Shared interactive download step for a resolved Eggman dat release: checks
# the release's filename is safe to use as a save path (defense against a
# crafted GitHub Releases response -- same convention as every other
# live-fetched filename in this script), prompts for a save location
# (defaulting next to the script), and downloads. Used by both the
# first-time dat setup prompt and the "check for a newer release" prompt on
# later runs, so there is exactly one place that does this safety check.
# Returns the saved path on success, or $null on failure/abort.
function Invoke-EggmanDatDownloadInteractive {
    param([pscustomobject]$rel)

    $safeDatFileName = [System.IO.Path]::GetFileName($rel.FileName)
    $defaultSavePath = Join-Path $PSScriptRoot $safeDatFileName
    $unsafeFileName  = [string]::IsNullOrWhiteSpace($safeDatFileName) -or -not (Test-PathInside $defaultSavePath $PSScriptRoot)
    if ($unsafeFileName) {
        Write-Log "EggmanDat: SECURITY -- unsafe release filename '$($rel.FileName)'"
        Write-Host "  Unexpected filename from GitHub -- skipped for safety." -ForegroundColor Red
        return $null
    }
    $rawSave = Read-PathWithBrowse "  Save to (Enter for default: $defaultSavePath)" -Mode SaveFile `
                   -FileFilter "ZIP files (*.zip)|*.zip|All files (*.*)|*.*" -DefaultFileName $safeDatFileName -InitialDirectory $PSScriptRoot
    if (-not $rawSave) { $rawSave = $defaultSavePath }
    Write-Host "  Downloading -- this may take a few minutes..." -ForegroundColor Cyan
    if (Invoke-EggmanDatDownload $rel.DownloadUrl $rawSave) { return $rawSave }
    return $null
}

# =============================================================================
# POSTGRESQL INSTALL ORCHESTRATION
# =============================================================================
# Confirmed working via multiple real install attempts on a real machine
# this session (several genuine failures along the way, each root-caused
# via verbose MSI logs -- see LESSONS_LEARNED.md's PostgreSQL install notes
# for the full story). Key facts baked into the property list below:
#   - Targets postgresql-8.3-int.msi directly, NOT the postgresql-8.3.msi
#     wrapper -- the wrapper is a near-empty UI shell with no real
#     Feature/Component data of its own; under /qn it has nothing to do
#     and fails.
#   - INTERNALLAUNCH=1 satisfies the internal MSI's own LaunchCondition
#     ("INTERNALLAUNCH=1 OR Installed"), bypassing the wrapper entirely.
#   - ROOTDRIVE=C:\ is required -- without it, MSI's default drive-
#     selection heuristic can pick whatever local drive has the most free
#     space, which would not match the hardcoded
#     C:\Program Files (x86)\PostgreSQL\8.3\ path baked into every
#     GameProfile's Path field.
#   - SERVICEDOMAIN must be the real computer name, NOT the Win32 "local
#     machine" literal "." -- this custom action does its own domain\
#     username string handling and does not resolve "." correctly, which
#     manifests as "No mapping between account names and security IDs
#     was done".

# Queries the GitHub API for the Eggmansworld/tp-it-guides "universal-guide"
# release, which bundles both the PDF setup guide and the actual
# PostgreSQL 8.3 installer files. Unlike the Eggman dat repo, this repo
# hosts several distinct release tags for different purposes (a
# customization guide, a score-submission pack, an obsolete-guides
# archive) -- "latest" would return whichever was most recently published,
# not necessarily this one, so this fetches by the specific known tag.
# Returns [pscustomobject]@{DownloadUrl; FileName; SizeMB} or $null on failure.
function Get-PostgresGuideRelease {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $apiUri = 'https://api.github.com/repos/Eggmansworld/tp-it-guides/releases/tags/universal-guide'
            $resp   = Invoke-WebRequest -Uri $apiUri -UseBasicParsing -TimeoutSec 20 `
                          -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
            $rel    = $resp.Content | ConvertFrom-Json
            $asset  = @($rel.assets) | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
            if (-not $asset) { return $null }
            if ($asset.browser_download_url -notmatch '^https://[a-zA-Z0-9._-]*(github\.com|githubusercontent\.com)/') {
                Write-Log "PostgresGuide: unexpected download URL format -- skipping."
                return $null
            }
            return [pscustomobject]@{
                DownloadUrl = $asset.browser_download_url
                FileName    = $asset.name
                SizeMB      = [Math]::Round($asset.size / 1MB, 1)
            }
        } catch {
            $status = 0
            if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
            if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) {
                Write-Log "PostgresGuide: GitHub release query failed -- $_"; return $null
            }
            Write-Log "PostgresGuide: attempt $attempt failed, retrying in 5s -- $_"
            Start-Sleep -Seconds 5
        }
    }
    return $null
}

# Downloads the guide ZIP. Same BITS-with-fallback shape as Invoke-EggmanDatDownload.
function Invoke-PostgresGuideDownload {
    param([string]$downloadUrl, [string]$savePath)
    try {
        $bitsOk = $false
        $bitsSvc = try { Get-Service -Name BITS -ErrorAction Stop } catch { $null }
        if ($bitsSvc -ne $null -and $bitsSvc.Status -eq 'Running') {
            try {
                Start-BitsTransfer -Source $downloadUrl -Destination $savePath `
                    -Description "PostgreSQL setup guide" `
                    -DisplayName "Downloading installer..." `
                    -ErrorAction Stop
                $bitsOk = $true
            } catch {
                Write-Log "PostgresGuide: BITS transfer failed (${_}), trying Invoke-WebRequest."
            }
        }
        if (-not $bitsOk) {
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $savePath -UseBasicParsing -ErrorAction Stop
                    break
                } catch {
                    $status = 0
                    if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
                    try { if (Test-Path -LiteralPath $savePath) { [System.IO.File]::Delete($savePath) } } catch {}
                    if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) { throw }
                    Write-Host ("  Attempt $attempt failed -- retrying in 10s...") -ForegroundColor Yellow
                    Write-Log "PostgresGuide: download attempt $attempt failed -- retrying"
                    Start-Sleep -Seconds 10
                }
            }
        }
        Write-DownloadAudit -Source $downloadUrl -FileName ([System.IO.Path]::GetFileName($savePath)) -Path $savePath
        return $true
    } catch {
        Write-Host ("  Download failed: {0}" -f $_) -ForegroundColor Red
        Write-Log "PostgresGuide: download failed -- $_"
        try { if (Test-Path -LiteralPath $savePath) { [System.IO.File]::Delete($savePath) } } catch {}
        return $false
    }
}

# True if the current process has Administrator privileges. Installing
# PostgreSQL as a Windows service requires this -- the first such check in
# this script, since every other write this script makes is to ordinary
# user-writable folders or files this script's own process already has
# rights to.
function Test-RunningAsAdministrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Decrypts a SecureString to plaintext only as long as needed, then
# explicitly zeroes and frees the unmanaged memory holding it -- letting GC
# eventually collect a managed string isn't the same as zeroing the bytes,
# and a password is worth being careful about even briefly. Also used by
# the DPAPI-encrypted config storage below to decrypt back to plaintext
# only at the point of use.
function ConvertFrom-SecureStringPlain {
    param([System.Security.SecureString]$Secure)
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)
    }
}

# Encrypts a plaintext password for storage in config.json via Windows
# DPAPI (ConvertFrom-SecureString with no -Key ties the result to the
# current Windows user + machine) -- the inverse of
# ConvertFrom-SecureStringPlain. Used to persist the Postgres superuser
# password after a successful install; nothing else in this script has
# ever needed to store a secret before this feature.
function ConvertTo-PostgresEncryptedPassword {
    param([string]$PlainText)
    $secure = ConvertTo-SecureString -String $PlainText -AsPlainText -Force
    return ($secure | ConvertFrom-SecureString)
}

# Prompts twice and requires both entries to match, so a typo doesn't
# silently set a password the user didn't intend. Returns plaintext (the
# caller is responsible for clearing it once consumed).
function Read-ConfirmedPostgresPassword {
    param([string]$WhatFor)
    while ($true) {
        $first  = Read-Host "  Enter $WhatFor" -AsSecureString
        $second = Read-Host "  Re-enter the same password to confirm" -AsSecureString
        $firstPlain  = ConvertFrom-SecureStringPlain $first
        $secondPlain = ConvertFrom-SecureStringPlain $second
        if ($firstPlain -eq $secondPlain) {
            $secondPlain = $null
            return $firstPlain
        }
        $firstPlain = $null
        Write-Host "  Those two didn't match -- let's try again." -ForegroundColor Yellow
    }
}

# Cross-checks PostgreSQL's own installation registry record -- written by
# the EnterpriseDB-based installer under \Installations\<install-id>,
# independent of the generic Windows Installer Uninstall key already
# checked in Remove-PostgresPartialInstall below -- against the expected
# install directory. Issue #4 (v1.0 roadmap): a second, independent
# registry source agreeing before any destructive msiexec /x call.
#
# Deliberately supplementary, not a new blocking gate: a PARTIAL/failed
# install -- the exact case Remove-PostgresPartialInstall exists to clean
# up -- may never have reached the install stage that writes this key at
# all, so its absence here is "no additional information," never a reason
# to skip cleanup. Only an explicit MISMATCH (the key exists, has an entry,
# and that entry's install directory points somewhere other than expected)
# is a red flag worth refusing to act on.
#
# The exact install-id subkey name under \Installations\ (the issue
# suggests "postgresql-8.3") is NOT assumed -- this dev machine has no real
# PostgreSQL install to verify that against (same constraint as the
# project's "no game data on this machine" note), so every existing
# install-id subkey is checked rather than guessing one exact name. "Base
# Directory" is the documented value name EnterpriseDB's installer writes
# there; if that's ever wrong on a real system, Get-ItemProperty simply
# returns nothing for it, which still degrades safely to "no additional
# information" rather than a false positive.
function Test-PostgresInstallationsRegistry {
    param([string]$ExpectedInstallDir)
    $expected = $ExpectedInstallDir.TrimEnd('\')
    $roots = @(
        "HKLM:\SOFTWARE\PostgreSQL\Installations\*",
        "HKLM:\SOFTWARE\WOW6432Node\PostgreSQL\Installations\*"
    )
    $entries = @(Get-ItemProperty -Path $roots -ErrorAction SilentlyContinue |
                     Where-Object { $_.'Base Directory' })
    if ($entries.Count -eq 0) {
        return [pscustomobject]@{ HasRecord = $false; Mismatch = $false }
    }
    # -ieq (case-insensitive EXACT equality), not -like -- this is a literal
    # path comparison, not a wildcard pattern match. Using -like here would
    # treat any `[`, `]`, or `*` in either path as wildcard syntax.
    $matching = @($entries | Where-Object { $_.'Base Directory'.TrimEnd('\') -ieq $expected })
    return [pscustomobject]@{ HasRecord = $true; Mismatch = ($matching.Count -eq 0) }
}

# Cleans up a half-installed/stale PostgreSQL 8.3 before a fresh install
# attempt. A failed install can leave a real Windows account, an orphaned
# user profile, and a ProfileList registry SID entry behind even when the
# installer itself reports failure -- confirmed empirically this session.
# Safe to call even when nothing is present -- every step checks first and
# skips cleanly. Never called when Test-PostgresInstalled is already true.
function Remove-PostgresPartialInstall {
    Write-Log "Postgres: checking for partial/stale install before fresh attempt..."

    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $expectedInstallDir = $script:PostgresInstallDir.TrimEnd('\')
    $pgInstallationsCheck = Test-PostgresInstallationsRegistry -ExpectedInstallDir $expectedInstallDir
    $pgEntries = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
                     Where-Object { $_.DisplayName -like "PostgreSQL*8.3*" }
    foreach ($entry in $pgEntries) {
        # Only ever uninstall an entry confirmed to be OUR install location --
        # someone could have an unrelated standalone PostgreSQL 8.3 for
        # legacy dev work at a different path, and a DisplayName match alone
        # is not enough to assume it's safe to remove. Case-insensitive EXACT
        # equality (-ine), not -notlike -- this was previously -notlike, which
        # treats the path as a wildcard pattern; a real path containing `[`,
        # `]`, or `*` could have matched/missed unintentionally. Caught in a
        # full deep-scan review; harmless today since the path is a hardcoded
        # constant with no wildcard metacharacters, but -ine is the correct
        # operator for what this comparison actually means.
        $installLoc = if ($entry.InstallLocation) { $entry.InstallLocation.TrimEnd('\') } else { '' }
        if ($installLoc -ine $expectedInstallDir) {
            Write-Log "Postgres: skipping uninstall of '$($entry.DisplayName)' -- InstallLocation '$installLoc' does not match our expected path, not touching it."
            continue
        }
        if ($pgInstallationsCheck.HasRecord -and $pgInstallationsCheck.Mismatch) {
            Write-Log "Postgres: skipping uninstall of '$($entry.DisplayName)' -- PostgreSQL's own Installations registry record disagrees with the matched InstallLocation, not touching it."
            continue
        }
        $productCode = $entry.PSChildName
        if ($productCode -notmatch '^\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$') { continue }
        $uninstallLog = Join-Path $env:TEMP ("pg83-uninstall-" + [guid]::NewGuid().ToString("N") + ".log")
        try {
            Start-Process -FilePath "msiexec.exe" -ArgumentList @("/x", $productCode, "/qn", "/l*v", "`"$uninstallLog`"") -Wait -PassThru | Out-Null
            Write-Log "Postgres: uninstalled stale entry $productCode"
        } finally {
            Remove-Item -LiteralPath $uninstallLog -Force -ErrorAction SilentlyContinue
        }
    }

    # Only the exact service name our own install recipe creates -- not a
    # wildcard match, since an unrelated Postgres install (a different
    # version, or a hand-named service) must never be stopped or deleted
    # by this cleanup.
    $pgServices = @(Get-Service -Name $script:PostgresServiceName -ErrorAction SilentlyContinue)
    foreach ($svc in $pgServices) {
        if ($svc.Status -eq 'Running') { Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue }
        & sc.exe delete $svc.Name | Out-Null
        Write-Log "Postgres: removed leftover service $($svc.Name)"
    }

    if (Test-Path -LiteralPath $script:PostgresInstallDir) {
        Remove-Item -LiteralPath $script:PostgresInstallDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Postgres: removed leftover $script:PostgresInstallDir"
    }

    $pgUser = Get-LocalUser -Name "postgres" -ErrorAction SilentlyContinue
    if ($pgUser) {
        Remove-LocalUser -Name "postgres" -ErrorAction SilentlyContinue
        Write-Log "Postgres: removed leftover local user 'postgres'"
    }

    # Remove-LocalUser does not clean up the profile folder or its
    # ProfileList registry SID mapping -- a stale entry here produces "No
    # mapping between account names and security IDs was done" on the next
    # install attempt (confirmed empirically this session).
    $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    $staleProfiles = Get-ChildItem -Path $profileListPath -ErrorAction SilentlyContinue | Where-Object {
        $imagePath = (Get-ItemProperty -Path $_.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        $imagePath -and ($imagePath -like "*\postgres")
    }
    foreach ($sidKey in $staleProfiles) {
        $imagePath = (Get-ItemProperty -Path $sidKey.PSPath -Name ProfileImagePath).ProfileImagePath
        Remove-Item -Path $sidKey.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $imagePath) {
            Remove-Item -LiteralPath $imagePath -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Log "Postgres: removed orphaned profile registration for $imagePath"
    }
    if (Test-Path -LiteralPath "C:\Users\postgres") {
        Remove-Item -LiteralPath "C:\Users\postgres" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Installs PostgreSQL 8.3 silently using the confirmed-working property set
# above. Requires Administrator (creates a Windows service + a local user
# account) -- prints a clear message and returns $false rather than failing
# unhelpfully if not elevated. Returns $true on confirmed success
# (Test-PostgresInstalled checked afterward, not just msiexec's exit code,
# since a misleading "success" with no real service was observed during
# this session's testing). The superuser password is returned via
# $OutSuperPasswordPlain so the caller can DPAPI-encrypt and save it --
# this function never persists anything itself, and always deletes its
# working folder (including the verbose install log, which logs connection
# passwords in plaintext in deferred custom-action data even though the
# command-line echo masks them) in a `finally` block regardless of outcome.
function Install-Postgres83 {
    param([ref]$OutSuperPasswordPlain)

    if (-not (Test-RunningAsAdministrator)) {
        Write-Host "  ERROR: Installing PostgreSQL requires Administrator privileges." -ForegroundColor Red
        Write-Host "  Close this window and re-run TeknoParrot Manager as Administrator." -ForegroundColor Yellow
        Write-Log "Postgres install: aborted -- not running as Administrator."
        return $false
    }

    Write-Host ""
    Write-Host "  PostgreSQL 8.3 is required by one or more of your registered games." -ForegroundColor Cyan
    Write-Host "  It's a small local database program that runs quietly in the" -ForegroundColor DarkGray
    Write-Host "  background and only talks to TeknoParrot -- nothing is sent over" -ForegroundColor DarkGray
    Write-Host "  the internet, and it won't interfere with anything else on your PC." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  You'll be asked for two different passwords:" -ForegroundColor White
    Write-Host "    1) A SERVICE ACCOUNT password -- for a Windows account Windows uses" -ForegroundColor DarkGray
    Write-Host "       to run PostgreSQL in the background. You'll almost never need it again." -ForegroundColor DarkGray
    Write-Host "    2) A DATABASE password -- this is the important one. It gets saved" -ForegroundColor DarkGray
    Write-Host "       (encrypted) so every Postgres game can be configured automatically." -ForegroundColor DarkGray
    Write-Host ""

    $svcPwPlain   = Read-ConfirmedPostgresPassword "the SERVICE ACCOUNT password"
    Write-Host ""
    $superPwPlain = Read-ConfirmedPostgresPassword "the DATABASE password"
    Write-Host ""

    Write-Host "  Checking for the PostgreSQL installer..." -ForegroundColor Cyan
    $rel = Get-PostgresGuideRelease
    if ($null -eq $rel) {
        Write-Host "  ERROR: Could not reach GitHub to download the installer." -ForegroundColor Red
        Write-Log "Postgres install: aborted -- could not fetch release info."
        $svcPwPlain = $null; $superPwPlain = $null
        return $false
    }

    $workDir = Join-Path $env:TEMP ("pg83-install-" + [guid]::NewGuid().ToString("N"))
    [void][System.IO.Directory]::CreateDirectory($workDir)
    $zipPath = Join-Path $workDir "guide.zip"

    try {
        Write-Host "  Downloading installer ($($rel.SizeMB) MB, this may take a minute)..." -ForegroundColor Cyan
        if (-not (Invoke-PostgresGuideDownload $rel.DownloadUrl $zipPath)) {
            Write-Host "  ERROR: Download failed." -ForegroundColor Red
            return $false
        }
        Expand-ZipFileSafe -ZipPath $zipPath -DestDir $workDir -GameName "PostgreSQL installer"
        $msiFile = Get-ChildItem -LiteralPath $workDir -Filter "postgresql-8.3-int.msi" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $msiFile) {
            Write-Host "  ERROR: Installer file not found inside the downloaded ZIP." -ForegroundColor Red
            Write-Log "Postgres install: aborted -- postgresql-8.3-int.msi not found after extraction."
            return $false
        }

        Remove-PostgresPartialInstall

        Write-Host "  Installing PostgreSQL 8.3 -- this can take a minute or two..." -ForegroundColor Cyan
        $logPath = Join-Path $workDir "pg83-install.log"
        $msiArgs = @(
            "/i", "`"$($msiFile.FullName)`"",
            "/qn",
            "/l*v", "`"$logPath`"",
            "INTERNALLAUNCH=1",
            "ROOTDRIVE=C:\",
            "SERVICEACCOUNT=postgres",
            "SERVICEDOMAIN=$env:COMPUTERNAME",
            "SERVICEPASSWORD=`"$svcPwPlain`"",
            "SERVICEPASSWORDV=`"$svcPwPlain`"",
            "CREATESERVICEUSER=1",
            "SUPERUSER=postgres",
            "SUPERPASSWORD=`"$superPwPlain`"",
            "LISTENPORT=5432",
            "LOCALE=C",
            "ENCODING=UTF8",
            "CLENCODE=UTF8",
            "PERMITREMOTE=0",
            "RUNSTACKBUILDER=0",
            "DOSERVICE=1",
            "DOINITDB=1"
        )
        # Known, accepted limitation: passing SERVICEPASSWORD/SUPERPASSWORD
        # as msiexec command-line properties means they are briefly visible
        # to anything that can inspect this process's command line (Task
        # Manager's command-line column, Process Explorer, a WMI
        # Win32_Process query) for the duration of this one call. MSI's own
        # SecureCustomProperties marking (confirmed present for both
        # properties when the MSI's tables were inspected this session)
        # only redacts them from msiexec's *own* verbose log -- it does not
        # hide them from the OS-level process command line. There is no
        # msiexec mechanism that avoids this for a silent property-driven
        # install; it is an inherent trade-off of this approach, not
        # something this script can route around. The exposure window is
        # already minimized (synchronous call, passwords cleared from this
        # script's own memory immediately after).
        $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
        $svcPwPlain = $null
        [GC]::Collect()

        if ($proc.ExitCode -ne 0 -or -not (Test-PostgresInstalled)) {
            Write-Host "  ERROR: PostgreSQL install did not complete successfully." -ForegroundColor Red
            Write-Log "Postgres install: FAILED -- msiexec exit code $($proc.ExitCode)"
            $superPwPlain = $null
            return $false
        }

        Write-Host "  PostgreSQL 8.3 installed and running." -ForegroundColor Green
        Write-Log "Postgres install: succeeded."
        $OutSuperPasswordPlain.Value = $superPwPlain
        return $true
    } finally {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# =============================================================================
# POSTGRESQL PER-GAME SETUP  (field configuration + database creation/restore)
# =============================================================================

# Locates the right backup file inside a game's own pg_backup folder. Per
# the guide: backups may sit directly inside pg_backup\, or inside a
# YYYY-MM-DD-named subfolder; when subfolders exist, the most recent one
# (by name -- they're ISO-formatted and sort correctly as strings) is used.
# The right file within is the one with the highest leading 4-digit
# number. Hardcoding the exact filename per the guide's Appendix A was
# deliberately avoided -- the guide itself says these drift as games get
# updated. Returns the full file path, or $null if pg_backup doesn't exist
# or contains nothing recognizable.
function Get-PostgresBackupFile {
    param([string]$GameFolder)

    $pgBackupDir = Join-Path $GameFolder "pg_backup"
    if (-not (Test-Path -LiteralPath $pgBackupDir)) { return $null }

    $dateSubfolders = @(Get-ChildItem -LiteralPath $pgBackupDir -Directory -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' } | Sort-Object Name -Descending)
    $searchDir = if ($dateSubfolders.Count -gt 0) { $dateSubfolders[0].FullName } else { $pgBackupDir }

    $candidates = @(Get-ChildItem -LiteralPath $searchDir -File -ErrorAction SilentlyContinue)
    if ($candidates.Count -eq 0) { return $null }

    $best = $candidates | Sort-Object -Descending -Property {
        if ($_.Name -match '^(\d{4})') { [int]$Matches[1] } else { -1 }
    } | Select-Object -First 1
    return $best.FullName
}

# Creates a database and restores a game's bundled backup into it. Only
# ever called for a database confirmed NOT to already exist
# (Test-PostgresDatabaseExists gates every call site in
# Invoke-PostgresGameSetup below) -- never recreates or overwrites an
# existing database. $Encoding should be "UTF8" only for the Golden Tee
# Live 2006 database (GameDB06); "SQL_ASCII" for every other game, per the
# guide's Appendix A -- this is a static, empirically-confirmed exception
# (same category as the project's existing hardcoded
# $RawThrillsPathLimits/$FileVersionPins lists), not something derived at
# runtime. pg_restore warnings on stderr are expected and ignored per the
# guide ("IGNORE the warning about errors on restore") -- only a database
# that doesn't exist afterward is treated as a real failure.
function New-PostgresDatabaseFromBackup {
    param([string]$DbName, [string]$Encoding, [string]$BackupFile, [string]$SuperPasswordPlain)

    if (-not (Test-SafePostgresDbName $DbName)) {
        Write-Log "Postgres: refusing unsafe database name '$DbName'"
        return $false
    }

    $createdbExe  = Join-Path $script:PostgresBinDir "createdb.exe"
    $psqlExe      = Join-Path $script:PostgresBinDir "psql.exe"
    $pgRestoreExe = Join-Path $script:PostgresBinDir "pg_restore.exe"

    $pgpassFile = New-PostgresPgPassFile -Password $SuperPasswordPlain
    $env:PGPASSFILE = $pgpassFile
    try {
        & $createdbExe -U postgres -h 127.0.0.1 -p 5432 -E $Encoding -T template0 $DbName 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Postgres: createdb failed for '$DbName' (exit $LASTEXITCODE)"
            return $false
        }

        & $psqlExe -U postgres -h 127.0.0.1 -p 5432 -d $DbName -c "ALTER DATABASE `"$DbName`" SET standard_conforming_strings = on;" 2>&1 | Out-Null

        & $pgRestoreExe -U postgres -h 127.0.0.1 -p 5432 -d $DbName $BackupFile 2>&1 | Out-Null
        return (Test-PostgresDatabaseExists -DbName $DbName -SuperPasswordPlain $SuperPasswordPlain)
    } catch {
        Write-Log "Postgres: database creation failed for '$DbName' -- $_"
        return $false
    } finally {
        $env:PGPASSFILE = $null
        Remove-PostgresPgPassFile -Path $pgpassFile
    }
}

# Main per-game Postgres setup pass: for every registered profile that
# needs Postgres, fills in connection fields (Path/Address/Port/User only
# when currently empty -- in practice TeknoParrot ships these already
# correctly pre-filled, so this is normally a no-op; Pass only when
# currently empty, NEVER overwriting an existing value, since the user may
# have already configured it correctly and silently overwriting it is
# exactly what this script's "never overwrite existing config" convention
# exists to prevent) and, for profiles whose GameProfile predates the
# "Automatically create Database" feature, creates and restores that
# game's database -- but only when Test-PostgresDatabaseExists first
# confirms it doesn't already exist. Returns
# [pscustomobject]@{ Configured; DbCreated; AlreadyConfigured; Errors }
# counts. Caller is responsible for the backup pass
# (Backup-PostgresDatabases) before calling this.
function Invoke-PostgresGameSetup {
    param([string]$UserProfilesDir, [string]$SuperPasswordPlain)

    $relBinPath = $script:PostgresBinDir.TrimEnd('\') + '\'
    $results = [ordered]@{ Configured = 0; DbCreated = 0; AlreadyConfigured = 0; Errors = 0 }

    $profiles = Get-ChildItem -LiteralPath $UserProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Directory.Name -ne "FullBackup" }

    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { continue }
            if (-not (Test-GameNeedsPostgres $doc)) { continue }

            $gpNode   = $doc.GameProfile.SelectSingleNode("GamePath")
            $gamePath = if ($gpNode) { $gpNode.InnerText } else { "" }
            if (-not $gamePath -or -not (Test-Path -LiteralPath $gamePath)) { continue }
            $gameFolder = Split-Path -Parent $gamePath

            $dbName = Get-PostgresFieldValue $doc "DbName"
            if ([string]::IsNullOrWhiteSpace($dbName) -or -not (Test-SafePostgresDbName $dbName)) {
                Write-Log "Postgres: $($pf.BaseName) has no usable DbName -- skipped."
                $results.Errors++
                continue
            }

            $changed = $false
            if ([string]::IsNullOrWhiteSpace((Get-PostgresFieldValue $doc "Path")))    { if (Set-PostgresFieldValue $doc "Path" $relBinPath)    { $changed = $true } }
            if ([string]::IsNullOrWhiteSpace((Get-PostgresFieldValue $doc "Address"))) { if (Set-PostgresFieldValue $doc "Address" "127.0.0.1") { $changed = $true } }
            if ([string]::IsNullOrWhiteSpace((Get-PostgresFieldValue $doc "Port")))    { if (Set-PostgresFieldValue $doc "Port" "5432")          { $changed = $true } }
            if ([string]::IsNullOrWhiteSpace((Get-PostgresFieldValue $doc "User")))    { if (Set-PostgresFieldValue $doc "User" "postgres")      { $changed = $true } }
            if ([string]::IsNullOrWhiteSpace((Get-PostgresFieldValue $doc "Pass"))) {
                if (Set-PostgresFieldValue $doc "Pass" $SuperPasswordPlain) { $changed = $true }
            }

            if (Test-PostgresDatabaseExists -DbName $dbName -SuperPasswordPlain $SuperPasswordPlain) {
                if ($changed) { Save-Xml $doc $pf.FullName; $results.Configured++ }
                else { $results.AlreadyConfigured++ }
                Write-Log "Postgres: $($pf.BaseName) -- database '$dbName' already exists, left untouched."
                continue
            }

            $autoCreate = Get-PostgresFieldValue $doc "Automatically create Database"
            if ($autoCreate -eq "1") {
                # TPUI's own first-launch flow creates the database itself --
                # nothing more for this script to do beyond the field updates above.
                if ($changed) { Save-Xml $doc $pf.FullName; $results.Configured++ }
                Write-Log "Postgres: $($pf.BaseName) -- deferring database creation to TPUI's own Express install."
                continue
            }

            # Older GameProfileRevision predating that feature -- create
            # and restore the database ourselves.
            $backupFile = Get-PostgresBackupFile $gameFolder
            if (-not $backupFile) {
                Write-Log "Postgres: $($pf.BaseName) -- no pg_backup file found, database not created."
                if ($changed) { Save-Xml $doc $pf.FullName; $results.Configured++ }
                $results.Errors++
                continue
            }

            $encoding = if ($dbName -eq 'GameDB06') { 'UTF8' } else { 'SQL_ASCII' }
            if (New-PostgresDatabaseFromBackup -DbName $dbName -Encoding $encoding -BackupFile $backupFile -SuperPasswordPlain $SuperPasswordPlain) {
                $results.DbCreated++
                Write-Log "Postgres: $($pf.BaseName) -- created and restored database '$dbName'."
            } else {
                $results.Errors++
                Write-Log "Postgres: $($pf.BaseName) -- FAILED to create/restore database '$dbName'."
            }

            if ($changed) { Save-Xml $doc $pf.FullName; $results.Configured++ }
        } catch {
            Write-Log "Postgres: error processing $($pf.Name) -- $_"
            $results.Errors++
        }
    }

    return [pscustomobject]$results
}

# =============================================================================
# FFB ARCADE PLUGIN  (force feedback / rumble for arcade racers and shooters)
# =============================================================================
# Source: mightymikem/FFBArcadePlugin, an actively-maintained fork of
# Boomslangnz/FFBArcadePlugin. Deploys one compiled DLL (MAME32.dll x86 /
# MAME64.dll x64) into a game's folder, renamed to whatever DLL that
# specific game expects to load (d3d9.dll, d3d11.dll, opengl32.dll,
# xinput1_3.dll, or winmm.dll). The per-game destination filename is a
# fixed lookup tied to specific titles, not auto-detected from the exe --
# so unlike ReShade it cannot be guessed at runtime; it is fetched live
# from the upstream AutoSetup.cmd build script instead of hardcoded here,
# so this automatically tracks whatever the fork currently supports.

# Fetches and parses the upstream AutoSetup.cmd to build a folder-name ->
# destination-DLL-filename map. The file has a very regular shape:
#   cd <FolderName>
#   rename dinput8.dll <destination>.dll
#   cd..
# (folder names are quoted only when they contain special characters, e.g.
# `cd "Sega Race TV"` vs `cd Afterburner Climax` -- the regex handles both).
# Returns an empty hashtable (not a hardcoded fallback list) if the fetch
# fails after retries -- there is nothing meaningful to fall back to since
# the table only exists upstream.
function Get-FFBPluginGameMap {
    $map = @{}
    $uri = 'https://raw.githubusercontent.com/mightymikem/FFBArcadePlugin/master/AutoSetup.cmd'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 20 `
                        -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
            $ms = [regex]::Matches($resp.Content, '(?m)^cd\s+"?([^"\r\n]+?)"?\s*\r?\nrename\s+dinput8\.dll\s+(\S+)\s*\r?\ncd\.\.')
            foreach ($m in $ms) {
                $folderName = $m.Groups[1].Value.Trim()
                $destDll    = $m.Groups[2].Value.Trim()
                if ($folderName -and $destDll) { $map[$folderName] = $destDll }
            }
            if ($map.Count -gt 0) {
                Write-Log "FFBPlugin: $($map.Count) game(s) in the live AutoSetup.cmd table."
            } else {
                Write-Log "FFBPlugin: 0 entries parsed from AutoSetup.cmd -- format may have changed."
            }
            return $map
        } catch {
            $status = 0
            if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
            if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) {
                Write-Log "FFBPlugin: AutoSetup.cmd fetch failed -- $_"
                return $map
            }
            Write-Log "FFBPlugin: attempt $attempt failed, retrying in 5s -- $_"
            Start-Sleep -Seconds 5
        }
    }
    return $map
}

# Downloads MAME32.dll / MAME64.dll directly from the repo root (plain
# files, not inside the release ZIP -- no extraction step needed).
# Returns $true if at least one architecture's DLL was downloaded.
function Invoke-FFBPluginDownload {
    param([string]$destDir)
    [void][System.IO.Directory]::CreateDirectory($destDir)
    $got = $false
    foreach ($dllName in @('MAME32.dll', 'MAME64.dll')) {
        $uri      = "https://raw.githubusercontent.com/mightymikem/FFBArcadePlugin/master/$dllName"
        $destPath = Join-Path $destDir $dllName
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                Invoke-WebRequest -Uri $uri -OutFile $destPath -UseBasicParsing -ErrorAction Stop `
                    -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
                $got = $true
                Write-Log "FFBPlugin: downloaded $dllName"
                Write-DownloadAudit -Source $uri -FileName $dllName -Path $destPath
                break
            } catch {
                $status = 0
                if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
                try { if (Test-Path -LiteralPath $destPath) { [System.IO.File]::Delete($destPath) } } catch {}
                if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) {
                    Write-Log "FFBPlugin: $dllName download failed -- $_"
                    break
                }
                Start-Sleep -Seconds 5
            }
        }
    }
    return $got
}

# Deploys FFB plugin DLLs to registered games matched against the live
# AutoSetup.cmd table by fuzzy folder-name similarity. Never overwrites an
# existing file at the destination filename (ReShade or anything else
# already occupying that hook point) -- skips and reports instead.
function Invoke-FFBPluginSetup {
    param([string]$UserProfilesDir, [string]$CacheDir, [string[]]$NativeEnabledCodes = @())

    # A caller passing an explicit $null overrides the default above (PowerShell
    # does not apply a parameter default when $null is passed deliberately) --
    # guard here too, since HashSet's constructor throws on a null collection.
    if ($null -eq $NativeEnabledCodes) { $NativeEnabledCodes = @() }
    $nativeEnabledSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$NativeEnabledCodes, [System.StringComparer]::OrdinalIgnoreCase)

    Write-Host ""
    Write-Host "  Fetching the current supported-games list..." -ForegroundColor DarkGray
    $gameMap = Get-FFBPluginGameMap
    if ($gameMap.Count -eq 0) {
        Write-Host "  Could not reach GitHub to fetch the FFB plugin game list -- try again later." -ForegroundColor Red
        Write-Log "FFBPlugin setup: aborted -- game map fetch failed."
        return
    }
    Write-Host ("  {0} game(s) in the upstream table." -f $gameMap.Count) -ForegroundColor DarkGray

    Write-Host "  Downloading the FFB plugin DLLs..." -ForegroundColor DarkGray
    if (-not (Invoke-FFBPluginDownload -destDir $CacheDir)) {
        Write-Host "  Could not download the FFB plugin DLLs -- try again later." -ForegroundColor Red
        Write-Log "FFBPlugin setup: aborted -- DLL download failed."
        return
    }
    $srcDll32 = Join-Path $CacheDir "MAME32.dll"
    $srcDll64 = Join-Path $CacheDir "MAME64.dll"

    $profiles = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" })
    if ($profiles.Count -eq 0) {
        Write-Host "  No registered games found." -ForegroundColor Yellow
        Write-Log "FFBPlugin setup: aborted -- no registered profiles."
        return
    }

    # Pre-normalise the FFB table once for fuzzy matching.
    $normFfbList = @(foreach ($name in $gameMap.Keys) {
        [pscustomobject]@{ Name = $name; Norm = (Get-NormalizedGameKey $name); Dest = $gameMap[$name] }
    })

    Write-Host ""
    Write-Host ("  Matching {0} registered game(s) against the FFB table..." -f $profiles.Count) -ForegroundColor Cyan

    # First pass: resolve a candidate match for every profile (regardless of
    # native status) so overlaps -- games covered by BOTH mechanisms -- can be
    # surfaced and decided on once, rather than silently defaulting to native.
    $candidates = @()
    $matchErrors = 0
    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { continue }
            $gpNode = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { continue }
            $gamePath = $gpNode.InnerText.Trim()
            if (-not (Test-Path -LiteralPath $gamePath)) { continue }
            $exeDir     = [System.IO.Path]::GetDirectoryName($gamePath)
            $folderName = Split-Path -Path $exeDir -Leaf
            $normFolder = Get-NormalizedGameKey $folderName

            $best = $null; $bestScore = 0.0
            foreach ($cand in $normFfbList) {
                $score = Get-DiceSimilarity $normFolder $cand.Norm
                if ($score -gt $bestScore) { $bestScore = $score; $best = $cand }
            }
            if ($null -eq $best -or $bestScore -lt $FuzzyAutoThreshold) { continue }

            $candidates += [pscustomobject]@{
                Profile = $pf; GamePath = $gamePath; ExeDir = $exeDir
                Match = $best; Score = $bestScore
            }
        } catch {
            Write-Host ("    ERROR {0} -- {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "FFBPlugin: error reading $($pf.BaseName) -- $_"
            $matchErrors++
        }
    }

    # Overlaps: profiles with a confident third-party match that are ALSO
    # already covered by native FFB Blaster. Ask once, covering all of them,
    # instead of silently preferring native or prompting per game.
    $overlaps = @($candidates | Where-Object { $nativeEnabledSet.Contains($_.Profile.BaseName) })
    $useNativeForOverlaps = $true
    if ($overlaps.Count -gt 0) {
        Write-Host ""
        Write-Host ("  {0} game(s) are covered by BOTH FFB Blaster and the third-party plugin:" -f $overlaps.Count) -ForegroundColor Cyan
        foreach ($ov in $overlaps) { Write-Host ("    - {0}" -f $ov.Profile.BaseName) -ForegroundColor DarkGray }
        $ans = (Read-Host "  Use FFB Blaster (native) for these games instead of the third-party plugin? (Y/N)").Trim().ToUpper()
        $useNativeForOverlaps = ($ans -eq "Y")
        Write-Log ("FFBPlugin: {0} overlapping game(s) with native FFB Blaster -- user chose {1}" -f $overlaps.Count, $(if ($useNativeForOverlaps) {"native"} else {"third-party plugin"}))
    }

    # Two distinct reasons get tracked separately, not combined into one
    # "no match" bucket: $skippedNoMatch is a game the live AutoSetup.cmd
    # table doesn't know about at all (nothing this script can do); a game
    # the table DOES match but whose 32-bit/64-bit MAME DLL isn't present
    # locally is a different, user-fixable situation (go get that DLL) and
    # gets its own $skippedDllMissing counter instead -- conflating the two
    # under one label would make "no match" misleadingly look like every
    # one of those games is simply unsupported.
    $deployed = 0; $skippedNative = 0; $skippedCollision = 0
    $skippedNoMatch = 0; $skippedDllMissing = 0; $errors = $matchErrors
    $noMatchCount = $profiles.Count - $candidates.Count - $matchErrors
    $skippedNoMatch += $noMatchCount

    foreach ($c in $candidates) {
        $pf = $c.Profile
        try {
            if ($nativeEnabledSet.Contains($pf.BaseName) -and $useNativeForOverlaps) {
                # Native FFB Blaster covers this game and the user chose to
                # keep native for overlaps -- don't deploy the third-party DLL.
                $skippedNative++
                continue
            }

            $exeDir   = $c.ExeDir
            $destDll  = $c.Match.Dest
            $destPath = Join-Path $exeDir $destDll
            # Security: $destDll comes from the live AutoSetup.cmd fetched from
            # GitHub (untrusted input) -- verify the resolved path still lands
            # inside the game's own folder before writing anything. A crafted
            # rename line (e.g. "..\..\evil.dll") would otherwise escape the
            # intended destination folder.
            if (-not (Test-PathInside $destPath $exeDir)) {
                Write-Host ("    SKIP  {0}: destination filename '{1}' is unsafe -- not deploying." -f $pf.BaseName, $destDll) -ForegroundColor Red
                Write-Log "FFBPlugin: SECURITY -- skipped $($pf.BaseName), destDll '$destDll' resolves outside $exeDir"
                $errors++
                continue
            }
            if (Test-Path -LiteralPath $destPath) {
                Write-Host ("    SKIP  {0}: {1} already exists (ReShade or another hook) -- not overwritten." -f $pf.BaseName, $destDll) -ForegroundColor Yellow
                Write-Log "FFBPlugin: skipped $($pf.BaseName) -- $destDll already occupied at $destPath"
                $skippedCollision++
                continue
            }

            $arch   = Get-ExeArchitecture -ExePath $c.GamePath
            $srcDll = if ($arch -eq 'x86') { $srcDll32 } else { $srcDll64 }
            if (-not (Test-Path -LiteralPath $srcDll)) {
                Write-Host ("    SKIP  {0}: {1}-bit DLL not available." -f $pf.BaseName, $(if ($arch -eq 'x86') {'32'} else {'64'})) -ForegroundColor Yellow
                $skippedDllMissing++; continue
            }

            Copy-Item -LiteralPath $srcDll -Destination $destPath -ErrorAction Stop
            Write-Host ("    OK    {0}  [{1}]  (matched '{2}', {3})" -f $pf.BaseName, $destDll, $c.Match.Name, [Math]::Round($c.Score,2)) -ForegroundColor Green
            Write-Log "FFBPlugin: deployed $destDll to $exeDir (matched '$($c.Match.Name)', score $([Math]::Round($c.Score,2)))"
            $deployed++
        } catch {
            Write-Host ("    ERROR {0} -- {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "FFBPlugin: error on $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Deployed           : {0} game(s)" -f $deployed) -ForegroundColor Green
    if ($skippedNative -gt 0) {
        Write-Host ("  Skipped (native)   : {0}  (FFB Blaster already covers these -- preferred over the plugin)" -f $skippedNative) -ForegroundColor DarkGray
    }
    if ($skippedCollision -gt 0) {
        Write-Host ("  Skipped (collision): {0}  (a hook DLL already exists -- not overwritten)" -f $skippedCollision) -ForegroundColor Yellow
    }
    if ($skippedNoMatch -gt 0) {
        Write-Host ("  Skipped (no match) : {0}  (not in the plugin's supported-games list)" -f $skippedNoMatch) -ForegroundColor DarkGray
    }
    if ($skippedDllMissing -gt 0) {
        Write-Host ("  Skipped (no DLL)   : {0}  (matched, but the 32-bit or 64-bit plugin DLL isn't downloaded)" -f $skippedDllMissing) -ForegroundColor Yellow
    }
    if ($errors -gt 0) {
        Write-Host ("  Errors             : {0}  -- see TeknoParrot-Manager.log for details" -f $errors) -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "  To uninstall: delete the deployed DLL file from the game's folder." -ForegroundColor DarkCyan
    Write-Log ("FFBPlugin setup: deployed={0} skippedNative={1} skippedCollision={2} skippedNoMatch={3} skippedDllMissing={4} errors={5}" -f $deployed, $skippedNative, $skippedCollision, $skippedNoMatch, $skippedDllMissing, $errors)
}

# Discovers the FFB Blaster Bool field name by scanning TeknoParrot
# GameProfiles at runtime -- never hardcoded. Shared (read-only) between
# Invoke-FFBBlasterSetup and the Library health check's coverage report.
function Get-FFBBlasterFieldNames {
    param([string]$GameProfilesDir)

    $ffbFields = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $GameProfilesDir) {
        $gpFiles = @(Get-ChildItem -LiteralPath $GameProfilesDir -Filter "*.xml" -ErrorAction SilentlyContinue)
        foreach ($gf in $gpFiles) {
            try {
                $gdoc = Read-Xml $gf.FullName
                $fnodes = $gdoc.SelectNodes("/GameProfile/ConfigValues/FieldInformation")
                foreach ($n in $fnodes) {
                    $cn = if ($n.CategoryName) { $n.CategoryName.Trim() } else { '' }
                    $fn = if ($n.FieldName)     { $n.FieldName.Trim()     } else { '' }
                    $ft = if ($n.FieldType)     { $n.FieldType.Trim()     } else { '' }
                    if ($ft -ne 'Bool') { continue }
                    if ($cn -imatch 'ffb.*blaster|blaster.*ffb') {
                        [void]$ffbFields.Add($cn)
                    } elseif ($fn -and $fn -imatch 'ffb.*blaster|blaster.*ffb') {
                        # Older TP builds that put the identifying text on
                        # FieldName instead of CategoryName -- fall back to
                        # treating the field name itself as the category key.
                        [void]$ffbFields.Add($fn)
                    }
                }
            } catch {
                Write-Log ("FFBBlaster: WARNING -- could not parse GameProfile '$($gf.BaseName)': $_")
            }
        }
    }
    return $ffbFields
}

# Pure decision function: for a given UserProfile XML and the category
# keys discovered by Get-FFBBlasterFieldNames (a CategoryName on newer TP
# builds, or a literal FieldName on older ones -- see that function's
# fallback), determines whether the profile has an FFB Blaster field at
# all (Eligible) and whether it is already set to '1' (UpToDate). Returns
# the exact node + target value for any field that needs changing,
# mirroring Test-GpuFixUpToDate.
function Test-FFBBlasterUpToDate {
    param([System.Xml.XmlDocument]$Doc, $Categories)

    $eligible = $false
    $changes  = New-Object System.Collections.Generic.List[object]

    foreach ($key in $Categories) {
        $xpLit = ConvertTo-XPathStringLiteral $key
        $fis = @($Doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation[CategoryName=$xpLit]"))
        if ($fis.Count -eq 0) {
            # Fallback for older-build profiles where $key is a literal FieldName.
            $fis = @($Doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation[FieldName=$xpLit]"))
        }
        foreach ($fi in $fis) {
            $ft = if ($fi.FieldType) { $fi.FieldType.Trim() } else { '' }
            if ($ft -ne 'Bool') { continue }
            $fvNode = $fi.SelectSingleNode("FieldValue")
            if ($null -eq $fvNode) { continue }
            $eligible = $true
            $fieldName = if ($fi.FieldName) { $fi.FieldName.Trim() } else { '' }
            if ($fvNode.InnerText -ne '1') {
                [void]$changes.Add([pscustomobject]@{ FieldName = $fieldName; Node = $fvNode; OldValue = $fvNode.InnerText; NewValue = '1' })
            }
        }
    }

    return [pscustomobject]@{ Eligible = $eligible; UpToDate = ($eligible -and $changes.Count -eq 0); Changes = $changes }
}

# Platforms/emulation paths on which TeknoParrot's native FFB Blaster is
# NOT currently supported, keyed by the GameProfile's own EmulationProfile
# (or EmulatorType) value -- compared case-insensitively. This is an
# explicit deny-list, not an allow-list: the script does NOT maintain a
# positive roster of every supported platform (that would go stale on every
# upstream addition and wrongly mark brand-new platforms as unsupported).
# Instead, only platforms POSITIVELY known not to support FFB Blaster are
# listed here, so a write is blocked for them even if a profile somehow
# carries an FFB-Blaster-shaped field. 'pcsx2x6' is the confirmed case
# (issue #41): TeknoParrot's PCSX2 fork does not implement FFB Blaster, and
# its profiles legitimately have no such field today -- but a future
# upstream change must never cause this script to enable it there. Add a
# platform here only after positively confirming FFB Blaster does not work
# on it; never the reverse.
$script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')

# Regex identifying any FieldInformation node (by CategoryName or FieldName)
# that LOOKS like an FFB Blaster control, regardless of whether it is a
# well-formed Bool field. Used to distinguish "this game genuinely has no
# FFB Blaster control" (Unsupported) from "something FFB-Blaster-shaped is
# here but does not match the schema we know how to write" (Unknown).
$script:FFBBlasterNamePattern = 'ffb.*blaster|blaster.*ffb'

# Pure capability/safety gate for native FFB Blaster on a single profile.
# Supersedes a bare Test-FFBBlasterUpToDate call at every decision point
# (Invoke-FFBBlasterSetup and the Library health check) so the platform
# deny-list and the unknown-field safety state are enforced in exactly one
# place. Returns a structured outcome -- this is the canonical shape the
# whole FFB Blaster feature reasons about (issue #41):
#   Status     : 'Supported' | 'Unsupported' | 'Unknown'
#   Reason     : human-readable explanation (for logs + the user summary)
#   WouldWrite : $true ONLY when Status='Supported' AND a field actually
#                needs changing -- the single signal a caller may write on.
#   Eligible   : a well-formed Bool FFB Blaster field is present
#   UpToDate   : that field is already enabled
#   Changes    : the exact node(s)+value(s) to write (from
#                Test-FFBBlasterUpToDate), empty unless Status='Supported'
#   Platform   : the EmulationProfile/EmulatorType value examined
# Decision order (deny-list first, so an unsupported platform can never be
# written even if it carries a matching field):
#   1. Platform in $FFBBlasterUnsupportedPlatforms        -> Unsupported
#   2. Well-formed Bool FFB Blaster field present         -> Supported
#   3. FFB-Blaster-shaped field present but malformed     -> Unknown
#      (drift: wrong FieldType, no FieldValue, etc.)
#   4. No FFB-Blaster-shaped field at all                 -> Unsupported
# Only case 2 ever permits a write; cases 1/3/4 always set WouldWrite=$false.
function Get-FFBBlasterSupport {
    param([System.Xml.XmlDocument]$Doc, $Categories)

    # Platform identity: prefer EmulationProfile, fall back to EmulatorType
    # (both carry 'pcsx2x6' on a real PCSX2 fork profile -- confirmed against
    # live teknogods/TeknoParrotUI GameProfiles).
    $platform = ''
    if ($Doc.GameProfile) {
        $epNode = $Doc.GameProfile.SelectSingleNode("EmulationProfile")
        if ($epNode -and $epNode.InnerText) { $platform = $epNode.InnerText.Trim() }
        if ([string]::IsNullOrWhiteSpace($platform)) {
            $etNode = $Doc.GameProfile.SelectSingleNode("EmulatorType")
            if ($etNode -and $etNode.InnerText) { $platform = $etNode.InnerText.Trim() }
        }
    }

    $emptyChanges = New-Object System.Collections.Generic.List[object]

    # 1. Deny-list gate -- always first, never overridden by field presence.
    foreach ($bad in $script:FFBBlasterUnsupportedPlatforms) {
        if ($platform -and ($platform -ieq $bad)) {
            return [pscustomobject]@{
                Status     = 'Unsupported'
                Reason     = "FFB Blaster is not supported on the '$platform' platform"
                WouldWrite = $false
                Eligible   = $false
                UpToDate   = $false
                Changes    = $emptyChanges
                Platform   = $platform
            }
        }
    }

    # 2. Well-formed Bool field present?
    $result = Test-FFBBlasterUpToDate -Doc $Doc -Categories $Categories
    if ($result.Eligible) {
        $would = ($result.Changes.Count -gt 0)
        $reason = if ($would) { "FFB Blaster field present and not yet enabled" }
                  else        { "FFB Blaster field present and already enabled" }
        return [pscustomobject]@{
            Status     = 'Supported'
            Reason     = $reason
            WouldWrite = $would
            Eligible   = $true
            UpToDate   = $result.UpToDate
            Changes    = $result.Changes
            Platform   = $platform
        }
    }

    # 3. Anything FFB-Blaster-shaped present that we could NOT treat as a
    #    writable Bool field? That is schema drift -- never write, flag for
    #    manual review.
    $shaped = $false
    if ($Doc.GameProfile) {
        $fnodes = $Doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation")
        foreach ($n in $fnodes) {
            $cn = if ($n.CategoryName) { $n.CategoryName.Trim() } else { '' }
            $fn = if ($n.FieldName)     { $n.FieldName.Trim()     } else { '' }
            if (($cn -and $cn -imatch $script:FFBBlasterNamePattern) -or
                ($fn -and $fn -imatch $script:FFBBlasterNamePattern)) {
                $shaped = $true; break
            }
        }
    }
    if ($shaped) {
        return [pscustomobject]@{
            Status     = 'Unknown'
            Reason     = "An FFB Blaster-like field was found but does not match the known Bool schema -- skipped for manual review"
            WouldWrite = $false
            Eligible   = $false
            UpToDate   = $false
            Changes    = $emptyChanges
            Platform   = $platform
        }
    }

    # 4. No FFB Blaster control of any shape -- this game simply does not
    #    have the feature.
    return [pscustomobject]@{
        Status     = 'Unsupported'
        Reason     = "This game has no FFB Blaster field"
        WouldWrite = $false
        Eligible   = $false
        UpToDate   = $false
        Changes    = $emptyChanges
        Platform   = $platform
    }
}

# Sets up TeknoParrot's own built-in "FFB Blaster" force feedback, a
# per-game Bool field in GameProfiles -- paywalled (any paid TeknoParrot
# membership). The script cannot check subscription status, so it must
# ask before touching anything: enabling the field has no effect at all
# without a membership, so there is no point doing it on spec.
# Returns the list of profile codes successfully enabled or already
# enabled, so the third-party plugin setup can ask the user whether to
# keep native or switch to the plugin for any game covered by both.
function Invoke-FFBBlasterSetup {
    param([string]$UserProfilesDir, [string]$TpRoot)

    Write-Host ""
    Write-Host "  FFB Blaster is TeknoParrot's own built-in force feedback." -ForegroundColor Cyan
    Write-Host "  It is included with any paid TeknoParrot membership" -ForegroundColor Cyan
    Write-Host "  (teknoparrot.com/en/Home/Subscription)." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Do you have an active, paid TeknoParrot membership? (Y/N)" -ForegroundColor Yellow
    Write-Host "  If you answer N, FFB Blaster will NOT be set up -- it does not work" -ForegroundColor Yellow
    Write-Host "  without one, and there is no point enabling a field that has no effect." -ForegroundColor Yellow
    $hasSub = (Read-Host "  Answer").Trim().ToUpper()
    if ($hasSub -ne "Y") {
        Write-Host "  Skipped -- no membership." -ForegroundColor DarkGray
        Write-Log "FFBBlaster setup: skipped -- user has no TeknoParrot membership."
        return ,@()   # comma forces real array semantics, not $null -- see
                      # Invoke-FFBPluginSetup's -NativeEnabledCodes param
    }

    # Discover the field name dynamically -- never hardcoded, same pattern
    # as Invoke-GpuFixSetup's $boolAmdFields discovery.
    Write-Host "  Scanning GameProfiles for FFB Blaster fields..." -ForegroundColor DarkGray
    $gpDir     = Join-Path $TpRoot "GameProfiles"
    $ffbFields = Get-FFBBlasterFieldNames -GameProfilesDir $gpDir
    if ($ffbFields.Count -eq 0) {
        # Before giving up, check whether there ARE any FFB-Blaster-shaped
        # fields in the GameProfiles at all, just not of type Bool. If so,
        # this is a schema drift situation (upstream changed the FieldType),
        # not simply "TeknoParrot does not support FFB Blaster here yet" --
        # and the two cases deserve different user-facing messages.
        $shapedNonBoolCount = 0
        if (Test-Path -LiteralPath $gpDir) {
            foreach ($gf in @(Get-ChildItem -LiteralPath $gpDir -Filter "*.xml" -ErrorAction SilentlyContinue)) {
                try {
                    $gdoc = Read-Xml $gf.FullName
                    $fnodes = $gdoc.SelectNodes("/GameProfile/ConfigValues/FieldInformation")
                    foreach ($n in $fnodes) {
                        $cn = if ($n.CategoryName) { $n.CategoryName.Trim() } else { '' }
                        $fn = if ($n.FieldName)     { $n.FieldName.Trim()     } else { '' }
                        $ft = if ($n.FieldType)     { $n.FieldType.Trim()     } else { '' }
                        if ($ft -ieq 'Bool') { continue }   # Already caught by Get-FFBBlasterFieldNames
                        if (($cn -and $cn -imatch $script:FFBBlasterNamePattern) -or
                            ($fn -and $fn -imatch $script:FFBBlasterNamePattern)) {
                            $shapedNonBoolCount++
                        }
                    }
                } catch { }
            }
        }
        if ($shapedNonBoolCount -gt 0) {
            Write-Host "  WARNING: FFB Blaster-shaped fields were found in GameProfiles, but" -ForegroundColor Yellow
            Write-Host "  none have the expected Bool type -- this may indicate an upstream" -ForegroundColor Yellow
            Write-Host ("  schema change ({0} field(s) affected). Skipped for manual review." -f $shapedNonBoolCount) -ForegroundColor Yellow
            Write-Host "  Run Get-GameProfileSchemaDrift against a sample profile to confirm." -ForegroundColor DarkGray
            Write-Log ("FFBBlaster setup: aborted -- {0} FFB-Blaster-shaped non-Bool field(s) detected (schema drift)." -f $shapedNonBoolCount)
        } else {
            Write-Host "  No FFB Blaster field found in any GameProfile -- this TeknoParrot" -ForegroundColor Yellow
            Write-Host "  install may not support it yet." -ForegroundColor Yellow
            Write-Log "FFBBlaster setup: aborted -- no FFB Blaster field discovered."
        }
        return ,@()
    }
    Write-Log ("FFBBlaster: discovered fields -- [{0}]" -f ($ffbFields -join ', '))

    # Backup before writing -- this touches every matching UserProfile.
    $backupRoot = Join-Path $UserProfilesDir "FullBackup"
    $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path $backupRoot ("FFBBlaster_" + $timestamp)
    try {
        [void][System.IO.Directory]::CreateDirectory($backupRoot)
        [void][System.IO.Directory]::CreateDirectory($backupPath)
    } catch {
        Write-Host "  ERROR: Could not create backup folder: $_" -ForegroundColor Red
        Write-Log "FFBBlaster: backup failed -- $_"
        return ,@()
    }
    $backupCopyErrs = $null
    Get-ChildItem -LiteralPath $UserProfilesDir | Where-Object { $_.Name -ne "FullBackup" } |
        Copy-Item -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable backupCopyErrs
    if ($backupCopyErrs.Count -gt 0) {
        Write-Host ("  WARNING: {0} file(s) could not be backed up." -f $backupCopyErrs.Count) -ForegroundColor Yellow
    }
    Write-Host ("  Backup: {0}" -f $backupPath) -ForegroundColor DarkGray
    Write-Log "FFBBlaster: backup at $backupPath"

    Write-Host ""
    Write-Host "  Enabling FFB Blaster on registered profiles..." -ForegroundColor DarkGray
    $profiles = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" })
    $enabledCodes = New-Object System.Collections.Generic.List[string]
    $updated = 0; $unchanged = 0; $unsupported = 0; $unknown = 0; $errors = 0
    $unknownNames = New-Object System.Collections.Generic.List[string]
    $skippedPlatforms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($pf in $profiles) {
        try {
            $doc    = Read-Xml $pf.FullName
            # Single structured capability+safety gate (issue #41). Only a
            # 'Supported' outcome with WouldWrite/Changes ever causes a write;
            # 'Unsupported' (no field, or an unsupported platform such as
            # pcsx2x6) and 'Unknown' (drifted/unrecognized field shape) are
            # both skipped without touching the profile.
            $support = Get-FFBBlasterSupport -Doc $doc -Categories $ffbFields
            switch ($support.Status) {
                'Unsupported' {
                    $unsupported++
                    if ($support.Platform -and ($script:FFBBlasterUnsupportedPlatforms -icontains $support.Platform)) {
                        [void]$skippedPlatforms.Add($support.Platform)
                    }
                    Write-Log "FFBBlaster: $($pf.BaseName) :: unsupported -- $($support.Reason)"
                    continue
                }
                'Unknown' {
                    $unknown++
                    [void]$unknownNames.Add($pf.BaseName)
                    Write-Log "FFBBlaster: $($pf.BaseName) :: unknown -- $($support.Reason) (NOT written)"
                    continue
                }
            }
            # Supported from here on.
            [void]$enabledCodes.Add($pf.BaseName)
            if ($support.WouldWrite) {
                foreach ($c in $support.Changes) {
                    $c.Node.InnerText = $c.NewValue
                    Write-Log "FFBBlaster: $($pf.BaseName) :: $($c.FieldName) -> $($c.NewValue)"
                }
                Save-Xml $doc $pf.FullName
                $updated++
                Write-Host ("    {0}" -f $pf.BaseName) -ForegroundColor Green
            } else {
                $unchanged++
            }
        } catch {
            Write-Host ("    FAILED {0}: {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "FFBBlaster: FAILED $($pf.BaseName) -- $_"
            $errors++
        }
    }

    $supportedTotal = $updated + $unchanged
    Write-Host ""
    Write-Host "  FFB Blaster support check:" -ForegroundColor Cyan
    Write-Host ("    Supported profiles  : {0}" -f $supportedTotal) -ForegroundColor Green
    Write-Host ("    Unsupported profiles: {0}" -f $unsupported) -ForegroundColor DarkGray
    Write-Host ("    Unknown profiles    : {0}" -f $unknown) -ForegroundColor $(if ($unknown -gt 0) {'Yellow'} else {'DarkGray'})
    Write-Host ""
    Write-Host ("  Updated  : {0} profile(s)" -f $updated) -ForegroundColor Green
    if ($unchanged -gt 0) { Write-Host ("  No change: {0} (already enabled)" -f $unchanged) -ForegroundColor DarkGray }
    foreach ($plat in $skippedPlatforms) {
        Write-Host ("  Skipped {0} profiles because FFB Blaster is not currently supported there." -f $plat) -ForegroundColor DarkGray
    }
    if ($unknown -gt 0) {
        Write-Host ("  Unknown  : {0} profile(s) had an unrecognized FFB Blaster field and were NOT changed -- review manually:" -f $unknown) -ForegroundColor Yellow
        Write-Host ("    {0}" -f ($unknownNames -join ', ')) -ForegroundColor DarkGray
    }
    if ($errors -gt 0)    { Write-Host ("  Errors   : {0} -- see log for details" -f $errors) -ForegroundColor Red }
    Write-Log ("FFBBlaster setup: complete. Supported={0} Updated={1} Unchanged={2} Unsupported={3} Unknown={4} Errors={5}" -f $supportedTotal, $updated, $unchanged, $unsupported, $unknown, $errors)
    return @($enabledCodes)
}

# =============================================================================
# BEPINEX UPDATE CHECKER  (Unity modding/plugin framework some games need)
# =============================================================================
# BepInEx is a third-party Unity plugin/modding framework. Several
# TeknoParrot games require a community BepInEx plugin to get controls or
# fixes working (the live-fetched example list is shown in the menu --
# see Get-BepInExRequiredGames below). This script never installs BepInEx
# fresh into a game -- only checks/updates EXISTING installs, and only
# the x64 stable line (never x86, never a pre-release), per explicit
# project policy.

# Fetches the live list of games known to require BepInEx, for display
# only (menu text, not used to gate any actual logic -- the update check
# itself only ever acts on games that already have BepInEx installed).
# Source: eggmansworld.github.io/TeknoParrot, the structured replacement
# for the old plain-text gamenotes doc, already used for the v0.88-v0.90
# compatibility tables. That site has no clean "requires BepInEx" tag, so
# this matches a tight phrase pattern against the free-text notes field
# instead -- verified against the live data to reproduce the same games
# this script used to hardcode here, so it tracks new additions without
# becoming stale. Returns an empty array (never a hardcoded fallback list)
# if the fetch fails -- the caller falls back to generic wording.
function Get-BepInExRequiredGames {
    $games = Get-EggmanGameData
    if (-not $games) { return ,@() }
    $pattern = '(?i)requires?\s+(the\s+)?(latest\s+)?BepInEx|must\s+use\s+(the\s+)?(latest\s+)?BepInEx'
    return @($games | Where-Object { $_.notes -and $_.notes -match $pattern } |
              Select-Object -ExpandProperty game_name)
}

# Shared fetch+parse for the eggmansworld.github.io structured compatibility
# data (the <script type="application/json" id="game-data"> block). Returns
# the full deserialized array, or $null if the fetch/parse fails. Both
# Get-BepInExRequiredGames and Get-GameSetupNotes hit the same endpoint --
# centralizing the fetch-with-retry + regex-extract logic here means there's
# only one copy that can drift out of sync with the page's actual markup.
function Get-EggmanGameData {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri 'https://eggmansworld.github.io/TeknoParrot/' `
                        -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
            $m = [regex]::Match($resp.Content, '(?s)<script type="application/json" id="game-data">(.*?)</script>')
            if (-not $m.Success) { return $null }
            return @($m.Groups[1].Value | ConvertFrom-Json)
        } catch {
            $status = 0
            if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
            if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) {
                Write-Log "EggmanGameData: fetch failed -- $_"; return $null
            }
            Start-Sleep -Seconds 5
        }
    }
    return $null
}

# Fetches the latest STABLE x64 BepInEx release info, fetch-with-retry
# shape identical to Get-EggmanDatRelease/Get-FFBPluginGameMap.
# Returns [pscustomobject]@{ Version; DownloadUrl; FileName } or $null.
function Get-BepInExLatestRelease {
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $apiUri = 'https://api.github.com/repos/BepInEx/BepInEx/releases'
            $resp   = Invoke-WebRequest -Uri $apiUri -UseBasicParsing -TimeoutSec 20 `
                          -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
            $releases = $resp.Content | ConvertFrom-Json
            # Releases are returned newest-first; prerelease=false reliably
            # distinguishes the v5-lts stable line from v6-bleeding-edge
            # pre-releases -- no tag-name parsing needed.
            $stable = @($releases | Where-Object { -not $_.prerelease }) | Select-Object -First 1
            if (-not $stable) { return $null }
            $x64Asset = @($stable.assets | Where-Object { $_.name -like 'BepInEx_win_x64_*.zip' }) | Select-Object -First 1
            if (-not $x64Asset) { return $null }
            if ($x64Asset.browser_download_url -notmatch '^https://[a-zA-Z0-9._-]*(github\.com|githubusercontent\.com)/') {
                Write-Log "BepInEx: unexpected download URL format -- skipping."
                return $null
            }
            $verStr = $stable.tag_name.TrimStart('v')
            return [pscustomobject]@{
                Version = $verStr; DownloadUrl = $x64Asset.browser_download_url; FileName = $x64Asset.name
            }
        } catch {
            $status = 0
            if ($_.Exception.Response) { try { $status = [int]$_.Exception.Response.StatusCode } catch {} }
            if ($attempt -ge 3 -or ($status -ge 400 -and $status -lt 500)) {
                Write-Log "BepInEx: release query failed -- $_"; return $null
            }
            Write-Log "BepInEx: attempt $attempt failed, retrying in 5s -- $_"
            Start-Sleep -Seconds 5
        }
    }
    return $null
}

# Returns the installed BepInEx version string for a game's exe folder, or
# $null if BepInEx is not installed there. BepInEx\core\BepInEx.dll's own
# FileVersion is the only reliable version source -- .doorstop_version is
# the unrelated Doorstop bootstrap version, not BepInEx's.
function Get-BepInExInstalledVersion {
    param([string]$ExeDir)
    $dllPath = Join-Path $ExeDir 'BepInEx\core\BepInEx.dll'
    if (-not (Test-Path -LiteralPath $dllPath)) { return $null }
    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($dllPath)
        if ([string]::IsNullOrWhiteSpace($vi.FileVersion)) { return $null }
        return $vi.FileVersion
    } catch { return $null }
}

# Returns 'x64', 'x86', or $null for an installed BepInEx's architecture.
# BepInEx's own managed DLLs are AnyCPU/MSIL in BOTH the win_x64 and win_x86
# zips, so they cannot reveal which build is installed -- only the native
# Doorstop winhttp.dll shim's PE machine type can.
function Get-BepInExInstalledArch {
    param([string]$ExeDir)
    $whPath = Join-Path $ExeDir 'winhttp.dll'
    if (-not (Test-Path -LiteralPath $whPath)) { return $null }
    return Get-ExeArchitecture -ExePath $whPath
}

# Walks every registered profile with an existing BepInEx install, checks
# each against the latest stable x64 release, and offers a single batched
# update for everything outdated. Never touches a game without BepInEx
# already installed, and never touches an x86 install (policy: x64 only).
function Invoke-BepInExUpdateCheck {
    param([string]$UserProfilesDir, [string]$CacheDir)

    Write-Host ""
    Write-Host "  Checking the latest stable BepInEx release..." -ForegroundColor DarkGray
    $latest = Get-BepInExLatestRelease
    if (-not $latest) {
        Write-Host "  Could not reach GitHub to check the latest BepInEx version -- try again later." -ForegroundColor Red
        Write-Log "BepInEx update check: aborted -- release query failed."
        return
    }
    Write-Host ("  Latest stable: {0}" -f $latest.Version) -ForegroundColor DarkGray

    $profiles = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" })
    if ($profiles.Count -eq 0) {
        Write-Host "  No registered games found." -ForegroundColor Yellow
        Write-Log "BepInEx update check: aborted -- no registered profiles."
        return
    }

    $outdated = @(); $upToDate = 0; $skippedX86 = 0; $errors = 0

    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { continue }
            $gpNode = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { continue }
            $gamePath = $gpNode.InnerText.Trim()
            if (-not (Test-Path -LiteralPath $gamePath)) { continue }
            $exeDir = [System.IO.Path]::GetDirectoryName($gamePath)

            $installedVer = Get-BepInExInstalledVersion -ExeDir $exeDir
            if (-not $installedVer) { continue }   # BepInEx not installed here -- not relevant to this feature

            $arch = Get-BepInExInstalledArch -ExeDir $exeDir
            if ($arch -eq 'x86') {
                $skippedX86++
                continue
            }
            if ($arch -ne 'x64') { continue }   # could not determine arch -- skip rather than guess

            $instParsed = $null; $latestParsed = $null
            if (-not [version]::TryParse($installedVer, [ref]$instParsed)) { continue }
            if (-not [version]::TryParse($latest.Version, [ref]$latestParsed)) { continue }

            if ($instParsed -lt $latestParsed) {
                $outdated += [pscustomobject]@{ Code = $pf.BaseName; ExeDir = $exeDir; Installed = $installedVer }
            } else {
                $upToDate++
            }
        } catch {
            Write-Log "BepInEx update check: error reading $($pf.BaseName) -- $_"
            $errors++
        }
    }

    if ($outdated.Count -eq 0) {
        Write-Host ""
        Write-Host ("  Up to date  : {0} game(s)" -f $upToDate) -ForegroundColor Green
        if ($skippedX86 -gt 0) {
            Write-Host ("  32-bit (skipped): {0}  (this script only manages 64-bit installs)" -f $skippedX86) -ForegroundColor DarkGray
        }
        if ($errors -gt 0) { Write-Host ("  Errors      : {0}" -f $errors) -ForegroundColor Red }
        Write-Log ("BepInEx update check: complete. UpToDate={0} 32bitSkipped={1} Errors={2}" -f $upToDate, $skippedX86, $errors)
        return
    }

    Write-Host ""
    Write-Host ("  {0} game(s) have an outdated BepInEx install:" -f $outdated.Count) -ForegroundColor Cyan
    foreach ($o in ($outdated | Sort-Object Code)) {
        Write-Host ("    - {0}: {1} -> {2}" -f $o.Code, $o.Installed, $latest.Version) -ForegroundColor DarkGray
    }
    $ans = (Read-Host ("  Update BepInEx to {0} for these {1} game(s)? (Y/N)" -f $latest.Version, $outdated.Count)).Trim().ToUpper()
    if ($ans -ne "Y") {
        Write-Host "  Skipped -- no changes made." -ForegroundColor DarkGray
        Write-Log "BepInEx update check: user declined the batched update."
        return
    }

    Write-Host "  Downloading BepInEx $($latest.Version) (x64)..." -ForegroundColor DarkGray
    [void][System.IO.Directory]::CreateDirectory($CacheDir)
    # Security: $latest.FileName comes from the GitHub Releases API (untrusted
    # input) -- strip to a bare filename and verify containment before using
    # it as a download destination, same pattern as the FFB plugin fix.
    $safeFileName = [System.IO.Path]::GetFileName($latest.FileName)
    $zipPath = Join-Path $CacheDir $safeFileName
    if ([string]::IsNullOrWhiteSpace($safeFileName) -or -not (Test-PathInside $zipPath $CacheDir)) {
        Write-Host "  Could not reach GitHub to check the latest BepInEx version -- try again later." -ForegroundColor Red
        Write-Log "BepInEx update check: SECURITY -- aborted, unsafe release filename '$($latest.FileName)'"
        return
    }
    $downloaded = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-WebRequest -Uri $latest.DownloadUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop `
                -Headers @{ 'User-Agent' = "TeknoParrot-Manager/$ScriptVersion" }
            $downloaded = $true
            Write-DownloadAudit -Source $latest.DownloadUrl -FileName $safeFileName -Path $zipPath -Version $latest.Version
            break
        } catch {
            try { if (Test-Path -LiteralPath $zipPath) { [System.IO.File]::Delete($zipPath) } } catch {}
            if ($attempt -ge 3) { break }
            Start-Sleep -Seconds 5
        }
    }
    if (-not $downloaded) {
        Write-Host "  Could not download the BepInEx ZIP -- try again later." -ForegroundColor Red
        Write-Log "BepInEx update check: aborted -- ZIP download failed."
        return
    }

    $updated = 0; $updateErrors = 0
    foreach ($o in $outdated) {
        try {
            $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
            $backupPath = Join-Path $o.ExeDir ("BepInEx_Backup_" + $timestamp)
            [void][System.IO.Directory]::CreateDirectory($backupPath)
            foreach ($item in @('BepInEx', 'doorstop_config.ini', 'winhttp.dll', '.doorstop_version', 'changelog.txt')) {
                $srcItem = Join-Path $o.ExeDir $item
                if (Test-Path -LiteralPath $srcItem) {
                    Copy-Item -LiteralPath $srcItem -Destination $backupPath -Recurse -Force -ErrorAction Stop
                }
            }
            Expand-ZipFileSafe -ZipPath $zipPath -DestDir $o.ExeDir -GameName $o.Code
            Write-Host ("    OK    {0}  ({1} -> {2})" -f $o.Code, $o.Installed, $latest.Version) -ForegroundColor Green
            Write-Log "BepInEx: updated $($o.Code) from $($o.Installed) to $($latest.Version) (backup: $backupPath)"
            $updated++
        } catch {
            Write-Host ("    ERROR {0} -- {1}" -f $o.Code, $_) -ForegroundColor Red
            Write-Log "BepInEx: error updating $($o.Code) -- $_"
            $updateErrors++
        }
    }

    Write-Host ""
    Write-Host ("  Updated     : {0} game(s)" -f $updated) -ForegroundColor Green
    if ($upToDate -gt 0) { Write-Host ("  Up to date  : {0}" -f $upToDate) -ForegroundColor DarkGray }
    if ($skippedX86 -gt 0) { Write-Host ("  32-bit (skipped): {0}" -f $skippedX86) -ForegroundColor DarkGray }
    if ($updateErrors -gt 0) { Write-Host ("  Errors      : {0} -- see log for details" -f $updateErrors) -ForegroundColor Red }
    Write-Log ("BepInEx update check: complete. Updated={0} UpToDate={1} 32bitSkipped={2} Errors={3}" -f $updated, $upToDate, $skippedX86, $updateErrors)
}

# Scans the install folder for executables and registers matching TeknoParrot
# profiles by setting <GamePath> in a copy written to UserProfiles. Three passes:
#   1 -- exe filename -> profile index (built from <ExecutableName> in GameProfile XMLs)
#   2 -- dat lookup for folders whose exe name is not in any profile
#   3 -- Dice-match normalised folder name against profile code names, resolving
#        games with empty <ExecutableName> (BladeStrangers, LuigisMansion, etc.)
# Existing UserProfiles are never overwritten.
# A profile code can only be claimed once per run (TeknoParrot allows exactly
# one GamePath per profile). Folders that resolve to a code already claimed by
# an earlier folder (e.g. several ROM revisions sharing one generic exe name
# and one profile, like multiple Virtua Fighter 5 Lindbergh dumps) are added to
# $ambiguous with Reason="duplicate" instead of being silently dropped.
function Register-Games {
    param([string]$userProfilesDir, [string]$installFolder, [hashtable]$profileIndex,
          [string]$gameProfilesDir = '', [hashtable]$datIndex = $null,
          [System.Collections.Generic.HashSet[string]]$profileSet = $null,
          [bool]$DryRun = $false,
          [string]$tpRootDir = '', [hashtable]$subFolderMap = $null)

    if ($null -eq $datIndex) { $datIndex = @{} }

    $exeFiles       = Get-GameFiles $installFolder
    $registered     = New-Object System.Collections.ArrayList
    $already        = New-Object System.Collections.ArrayList
    $ambiguous      = New-Object System.Collections.ArrayList
    $seenCodes      = @{}
    $codeClaimedBy  = @{}   # profile code -> folder name that already claimed it this run
    # Snapshot of codes that already had a UserProfile BEFORE this run started.
    # Needed to tell apart two genuinely different situations that both make
    # $seenCodes.ContainsKey($code) true: (1) the code was already registered
    # (by TeknoParrotUI or an earlier run) before this run touched anything --
    # not a conflict, just report "Already"; vs (2) two folders THIS run both
    # resolved to the SAME unclaimed code -- a real conflict between two
    # fresh candidates. Without this distinction, a folder whose own exe
    # happens to share a name with dozens of other titles (e.g. NESiCAxLive's
    # game.exe) gets falsely flagged as "duplicate" every time an unrelated
    # already-registered sibling from that same shared-exe pool is scanned
    # first and incidentally marks this folder's own code as "seen".
    $preExistingCodes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem -LiteralPath $userProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -ne "FullBackup" } |
        ForEach-Object { [void]$preExistingCodes.Add($_.BaseName) }
    # Maps an exe's exact full path to the profile code already pointing at it
    # (if any). This is a stronger, name-independent signal than fuzzy-matching
    # the folder name against candidate profile codes: it catches a folder
    # whose correct profile is already configured even when that profile's own
    # code never scores high enough against the folder name to be picked
    # automatically (e.g. a generic/typo'd code like "Primevil" for "Primeval
    # Hunt"), and even when the correct profile was never a fuzzy-match
    # candidate at all because its own ExecutableName differs from this exe's
    # filename (e.g. "Nosferatu" not appearing among the "main.exe" candidates
    # for Nosferatu Lilinor). See issue #9.
    $gamePathIndex = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem -LiteralPath $userProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -ne "FullBackup" } |
        ForEach-Object {
            try {
                $existingDoc = Read-Xml $_.FullName
                $gpNode = $existingDoc.GameProfile.SelectSingleNode("GamePath")
                if ($null -ne $gpNode -and $gpNode.InnerText) {
                    # Trim() first: a GamePath written by a tool other than this
                    # script's own Save-Xml could carry incidental leading/trailing
                    # whitespace, which would otherwise make this key never match
                    # $exe.FullName (a clean FileInfo path) even when they refer to
                    # the same file. See issue #9.
                    $gamePathIndex[$gpNode.InnerText.Trim().TrimEnd('\')] = $_.BaseName
                }
            } catch {
                Write-Log ("Register-Games: WARNING -- could not parse existing UserProfile '$($_.BaseName)' while building GamePath index: $_")
            }
        }
    $installBase    = $installFolder.TrimEnd('\')
    $matchedFolders = @{}   # folders that matched at least one profile key
    $allExeFolders  = @{}   # folders containing any recognisable executable
    $_regTotal = $exeFiles.Count
    $_regI     = 0

    foreach ($exe in $exeFiles) {
        $_regI++
        if ($_regTotal -gt 0) {
            Write-Progress -Activity "Scanning game library" `
                           -Status ("({0}/{1}) {2}" -f $_regI, $_regTotal, $exe.Directory.Name) `
                           -PercentComplete ([int]($_regI / $_regTotal * 100))
        }
        $relPath    = $exe.FullName.Substring($installBase.Length).TrimStart('\')
        $folderName = ($relPath -split '\\')[0]
        $folderKey  = $folderName -replace '\.(teknoparrot|parrot|game)$', ''   # strip suffix for matching/tracking
        $allExeFolders[$folderKey] = $folderName   # store original name (with any suffix) for path resolution

        $key = $exe.Name.ToLower()
        if (-not $profileIndex.ContainsKey($key)) { continue }

        $matchList = $profileIndex[$key]

        # Same executable name maps to more than one profile.
        # Attempt folder-name fuzzy matching before giving up.
        if ($matchList.Count -gt 1) {
            # $matchedFolders is set per conclusive outcome below, NOT
            # unconditionally just because this exe's filename happened to
            # appear in $profileIndex. A folder can contain more than one
            # exe-like file (an installer, an uninstaller, a redistributable
            # stub, the real launcher); if an unrelated one of those happens
            # to collide with some other profile's <ExecutableName>, marking
            # the whole folder "matched" on that collision alone would
            # permanently block Pass 2/3 below from ever getting a chance to
            # resolve the folder's REAL exe via the dat -- even though this
            # specific exe was never actually identified. $resolved tracks
            # whether THIS exe's own outcome was conclusive; it defaults true
            # and is only flipped false at the genuinely-unresolved "shared"
            # ambiguous outcomes further down. See issue #10.
            $resolved = $true

            # Exact-path check first, ahead of any fuzzy-name matching: if an
            # existing UserProfile already points its GamePath at this exact
            # exe, this folder is fully handled regardless of whether that
            # profile's own code name fuzzy-matches the folder name at all, or
            # was even among $matchList's candidates. See issue #9.
            if ($gamePathIndex.ContainsKey($exe.FullName)) {
                $existingCode = $gamePathIndex[$exe.FullName]
                if (-not $seenCodes.ContainsKey($existingCode)) {
                    if ($already -notcontains $existingCode) { [void]$already.Add($existingCode) }
                    $seenCodes[$existingCode] = $true
                    $codeClaimedBy[$existingCode] = "(already registered in TeknoParrotUI)"
                    Backfill-SecondaryExecutablePath (Join-Path $userProfilesDir ($existingCode + ".xml")) $DryRun
                }
                $matchedFolders[$folderKey] = $true
                continue
            }

            # $folderKey has the RetroBat suffix stripped, ready to normalise.
            # The $RawThrillsPathLimits alias fallback (e.g. NicktoonsNitro -> NTN,
            # for a folder renamed to this script's own PATH TOO LONG suggestion --
            # see issue #13) is handled inside Resolve-BestFuzzyMatch.
            $normFolder  = Get-NormalizedGameKey $folderKey

            $fuzzyResult    = Resolve-BestFuzzyMatch -NormFolder $normFolder -MatchList $matchList -RawThrillsAliases $RawThrillsPathLimits
            $bestFuzzy      = $fuzzyResult.Best
            $bestFuzzyScore = $fuzzyResult.BestScore

            if ($fuzzyResult.IsConfidentMatch) {
                # High-confidence fuzzy match: register automatically.
                $code = $bestFuzzy.Code
                if ($seenCodes.ContainsKey($code)) {
                    if ($preExistingCodes.Contains($code)) {
                        # Already registered before this run started (TeknoParrotUI
                        # or an earlier run) -- not a conflict from this run's
                        # perspective, just confirm it's set and move on. (Guard
                        # against a duplicate "Already" entry: an earlier folder's
                        # alreadyReg scan may have already recorded this same code.)
                        if ($already -notcontains $code) { [void]$already.Add($code) }
                    } else {
                        # Another folder already claimed this profile code THIS run --
                        # TeknoParrot can only point one profile at one executable, so
                        # this is a real conflict, not a silent duplicate to drop.
                        [void]$ambiguous.Add([pscustomobject]@{
                            Exe        = $exe.FullName
                            Codes      = $code
                            BestGuess  = $code
                            BestScore  = 1.0
                            Reason     = "duplicate"
                            ClaimedBy  = $codeClaimedBy[$code]
                        })
                    }
                    continue
                }
                $userProfile = Join-Path $userProfilesDir ($code + ".xml")
                if (Test-Path -LiteralPath $userProfile) {
                    [void]$already.Add($code); $seenCodes[$code] = $true; $codeClaimedBy[$code] = $folderName
                    Backfill-SecondaryExecutablePath $userProfile $DryRun
                } else {
                    # Mark seen before the file operation so that if Save throws,
                    # a second exe match for the same code doesn't cause a duplicate
                    # attempt (and duplicate error output) within the same run.
                    $seenCodes[$code] = $true
                    $codeClaimedBy[$code] = $folderName
                    try {
                        $tpl = Read-Xml $bestFuzzy.TemplatePath
                        $gp  = $tpl.GameProfile.SelectSingleNode("GamePath")
                        if ($null -eq $gp) {
                            $gp = $tpl.CreateElement("GamePath")
                            [void]$tpl.GameProfile.PrependChild($gp)
                        }
                        $gp.InnerText = $exe.FullName
                        Set-SecondaryExecutablePath $tpl $exe.FullName
                        Save-XmlMaybe $tpl $userProfile $DryRun
                        [void]$registered.Add([pscustomobject]@{
                            Code        = $code
                            GamePath    = $exe.FullName
                            FuzzyScore  = [Math]::Round($bestFuzzyScore, 2)
                            FuzzyFolder = $folderName
                        })
                        Write-Log "Registered (fuzzy $([Math]::Round($bestFuzzyScore,2))) $code -> $($exe.FullName)  [folder: $folderName]"
                    } catch {
                        Write-Host "  FAILED to register $code : $_" -ForegroundColor Red
                        Write-Log "Register (fuzzy) FAILED $code -- $_"
                    }
                }
            } else {
                # Bug fix: check if any candidate is already registered (UserProfile
                # exists) before flagging as ACTION REQUIRED. A game registered via
                # TeknoParrotUI would have a .xml file even though the fuzzy score is
                # below the auto-register threshold.
                $alreadyReg = @($matchList | Where-Object {
                    Test-Path -LiteralPath (Join-Path $userProfilesDir ($_.Code + ".xml"))
                })
                foreach ($ar in $alreadyReg) {
                    if (-not $seenCodes.ContainsKey($ar.Code)) {
                        if ($already -notcontains $ar.Code) { [void]$already.Add($ar.Code) }
                        $seenCodes[$ar.Code] = $true
                        $codeClaimedBy[$ar.Code] = "(already registered in TeknoParrotUI)"
                        Backfill-SecondaryExecutablePath (Join-Path $userProfilesDir ($ar.Code + ".xml")) $DryRun
                    }
                }

                # A sibling sharing this exe name being already registered does NOT
                # mean THIS folder's own game is handled -- e.g. H2Overdrive already
                # having a profile says nothing about whether X-Games Snowboarder
                # (a different game sharing the same generic sdaemon.exe loader)
                # does. Only skip this folder if its OWN best-guess candidate
                # specifically is among the already-registered set; otherwise it
                # still needs the dat lookup / manual-registration fallback below,
                # even though some unrelated sibling is already fine.
                $ownAlreadyRegistered = ($null -ne $bestFuzzy) -and
                    (@($alreadyReg | Where-Object { $_.Code -eq $bestFuzzy.Code }).Count -gt 0)

                if (-not $ownAlreadyRegistered) {
                    # Dat-based disambiguation: look up the normalised folder name in the
                    # dat index. The dat's <GameProfile> is authoritative, so if a match is
                    # found we use it directly instead of falling through to ambiguous.
                    $datEntry = if ($datIndex.Count -gt 0) { $datIndex[$normFolder] } else { $null }
                    if ($null -ne $datEntry) {
                        $datCode = $datEntry.ProfileCode
                        # Profile codes are purely alphanumeric; reject anything else to
                        # prevent path traversal via a crafted dat file.
                        if ($datCode -match '^[\w]+$') {
                            if ($gameProfilesDir) {
                                $datCode = Resolve-ProfileCode $datCode $gameProfilesDir $profileSet
                            }
                            $userProfile = Join-Path $userProfilesDir ($datCode + ".xml")
                            if ($seenCodes.ContainsKey($datCode)) {
                                if ($preExistingCodes.Contains($datCode)) {
                                    if ($already -notcontains $datCode) { [void]$already.Add($datCode) }
                                } else {
                                    [void]$ambiguous.Add([pscustomobject]@{
                                        Exe        = $exe.FullName
                                        Codes      = $datCode
                                        BestGuess  = $datCode
                                        BestScore  = 1.0
                                        Reason     = "duplicate"
                                        ClaimedBy  = $codeClaimedBy[$datCode]
                                    })
                                }
                            } else {
                                $seenCodes[$datCode] = $true
                                $codeClaimedBy[$datCode] = $folderName
                                if (Test-Path -LiteralPath $userProfile) {
                                    [void]$already.Add($datCode)
                                    Backfill-SecondaryExecutablePath $userProfile $DryRun
                                } else {
                                    $templatePath = Join-Path $gameProfilesDir ($datCode + ".xml")
                                    $exeToUse     = $exe.FullName
                                    if (-not [string]::IsNullOrWhiteSpace($datEntry.Executable)) {
                                        $relExe     = $datEntry.Executable.TrimStart('\', '/')
                                        # Guard: a bare backslash/slash normalises to an empty
                                        # string; using it as a path component would match the
                                        # game folder itself rather than an executable.
                                        if ($relExe) {
                                            $folderFull = Join-Path $installBase $folderName
                                            $datExe     = Join-Path $folderFull $relExe
                                            # Security: dat-supplied path must stay inside the game folder.
                                            if (Test-PathInside $datExe $folderFull) {
                                                if     (Test-Path -LiteralPath $datExe -PathType Leaf) { $exeToUse = $datExe }
                                                elseif (Test-Path -LiteralPath ($datExe + ".exe")) { $exeToUse = $datExe + ".exe" }
                                                elseif (Test-Path -LiteralPath ($datExe + ".elf")) { $exeToUse = $datExe + ".elf" }
                                            }
                                        }
                                    }
                                    if (Test-Path -LiteralPath $templatePath) {
                                        try {
                                            $tpl = Read-Xml $templatePath
                                            $gp  = $tpl.GameProfile.SelectSingleNode("GamePath")
                                            if ($null -eq $gp) {
                                                $gp = $tpl.CreateElement("GamePath")
                                                [void]$tpl.GameProfile.PrependChild($gp)
                                            }
                                            $gp.InnerText = $exeToUse
                                            Set-SecondaryExecutablePath $tpl $exeToUse
                                            Save-XmlMaybe $tpl $userProfile $DryRun
                                            [void]$registered.Add([pscustomobject]@{
                                                Code     = $datCode
                                                GamePath = $exeToUse
                                                DatMatch = $true
                                            })
                                            Write-Log "Registered (dat) $datCode -> $exeToUse"
                                        } catch {
                                            Write-Host "  FAILED to register $datCode : $_" -ForegroundColor Red
                                            Write-Log "Register (dat) FAILED $datCode -- $_"
                                        }
                                    } else {
                                        Write-Log ("DatIndex: template '{0}.xml' not in GameProfiles -- flagging as ambiguous." -f $datCode)
                                        [void]$ambiguous.Add([pscustomobject]@{
                                            Exe       = $exe.FullName
                                            Codes     = ($matchList | ForEach-Object { $_.Code }) -join ", "
                                            BestGuess = $datCode
                                            BestScore = 1.0
                                            Reason    = "shared"
                                        })
                                        $resolved = $false
                                    }
                                }
                            }
                        } else {
                            Write-Log ("DatIndex: invalid ProfileCode '{0}' -- skipped." -f $datCode)
                            [void]$ambiguous.Add([pscustomobject]@{
                                Exe       = $exe.FullName
                                Codes     = ($matchList | ForEach-Object { $_.Code }) -join ", "
                                BestGuess = if ($null -ne $bestFuzzy) { $bestFuzzy.Code } else { $null }
                                BestScore = [Math]::Round($bestFuzzyScore, 2)
                                Reason    = "shared"
                            })
                            $resolved = $false
                        }
                    } else {
                        # Below threshold with no dat entry: flag for manual registration.
                        [void]$ambiguous.Add([pscustomobject]@{
                            Exe       = $exe.FullName
                            Codes     = ($matchList | ForEach-Object { $_.Code }) -join ", "
                            BestGuess = if ($null -ne $bestFuzzy) { $bestFuzzy.Code } else { $null }
                            BestScore = [Math]::Round($bestFuzzyScore, 2)
                            Reason    = "shared"
                        })
                        $resolved = $false
                    }
                }
            }
            # Only mark the folder as accounted for if this exe's own outcome
            # was conclusive (registered/already/duplicate-conflict) -- not
            # when it fell through to a genuinely-unresolved "shared"
            # ambiguous entry. An unresolved exe leaves the folder eligible
            # for Pass 2/3 below, in case a DIFFERENT exe in this same folder
            # (or the folder's name itself) resolves cleanly via the dat or a
            # profile-code fuzzy match. See issue #10.
            if ($resolved) { $matchedFolders[$folderKey] = $true }
            continue
        }

        # A single candidate for this exe name is always a confident,
        # unambiguous identification (unlike the $matchList.Count -gt 1
        # branch above, this never falls through to an unresolved "shared"
        # outcome) -- safe to mark the folder accounted for unconditionally.
        $matchedFolders[$folderKey] = $true

        $match = $matchList[0]
        $code  = $match.Code
        if ($seenCodes.ContainsKey($code)) {
            if ($preExistingCodes.Contains($code)) {
                if ($already -notcontains $code) { [void]$already.Add($code) }
            } else {
                # Another folder already claimed this profile code THIS run. Most
                # often this is multiple ROM revisions of the same game sharing one
                # generic exe name and one TeknoParrot profile (e.g. several Virtua
                # Fighter 5 Lindbergh revisions). TeknoParrot can only point that
                # profile at one executable, so surface it instead of dropping it.
                [void]$ambiguous.Add([pscustomobject]@{
                    Exe        = $exe.FullName
                    Codes      = $code
                    BestGuess  = $code
                    BestScore  = 1.0
                    Reason     = "duplicate"
                    ClaimedBy  = $codeClaimedBy[$code]
                })
            }
            continue
        }

        $userProfile = Join-Path $userProfilesDir ($code + ".xml")
        if (Test-Path -LiteralPath $userProfile) {
            [void]$already.Add($code)
            $seenCodes[$code] = $true
            $codeClaimedBy[$code] = $folderName
            Backfill-SecondaryExecutablePath $userProfile $DryRun
            continue
        }

        # Mark seen before the file operation for the same reason as the fuzzy
        # path: prevents a duplicate attempt if a second matching exe is found.
        $seenCodes[$code] = $true
        $codeClaimedBy[$code] = $folderName
        try {
            $tpl = Read-Xml $match.TemplatePath
            # SelectSingleNode returns the node if it exists (even when empty)
            # and $null only when truly absent. This avoids creating a second
            # GamePath element, which would make the value assignment ambiguous.
            $gp = $tpl.GameProfile.SelectSingleNode("GamePath")
            if ($null -eq $gp) {
                $gp = $tpl.CreateElement("GamePath")
                [void]$tpl.GameProfile.PrependChild($gp)
            }
            $gp.InnerText = $exe.FullName
            Set-SecondaryExecutablePath $tpl $exe.FullName
            Save-XmlMaybe $tpl $userProfile $DryRun
            [void]$registered.Add([pscustomobject]@{ Code = $code; GamePath = $exe.FullName })
            Write-Log "Registered $code -> $($exe.FullName)"
        } catch {
            Write-Host "  FAILED to register $code : $_" -ForegroundColor Red
            Write-Log "Register FAILED $code -- $_"
        }
    }
    Write-Progress -Activity "Scanning game library" -Completed

    # Second pass: folders that had recognisable executables but none of them were
    # in $profileIndex (no exe->profile mapping). These are typically games whose
    # executable name is not listed in any GameProfile XML -- common with pcsx2x6,
    # ELF-based Lindbergh games, or custom loaders. Try the dat index: first an
    # exact normalised-name lookup, then a fuzzy scan of all dat keys.
    if ($datIndex.Count -gt 0 -and $gameProfilesDir) {
        foreach ($folderKey in @($allExeFolders.Keys | Where-Object { -not $matchedFolders.ContainsKey($_) })) {
            $origName   = $allExeFolders[$folderKey]
            $normFolder = Get-NormalizedGameKey $folderKey
            $datEntry   = $datIndex[$normFolder]
            $datScore   = 1.0

            # Fuzzy dat scan when no exact name match (handles slightly misnamed folders)
            if ($null -eq $datEntry) {
                $bestScore = 0.0
                $bestKey   = $null
                foreach ($dk in $datIndex.Keys) {
                    $score = Get-DiceSimilarity $normFolder $dk
                    if ($score -gt $bestScore) { $bestScore = $score; $bestKey = $dk }
                }
                if ($bestScore -ge $FuzzyAutoThreshold -and $null -ne $bestKey) {
                    $datEntry = $datIndex[$bestKey]
                    $datScore = $bestScore
                }
            }

            if ($null -eq $datEntry) { continue }

            $datCode = $datEntry.ProfileCode
            if ($datCode -notmatch '^[\w]+$') {
                Write-Log ("DatIndex (pass2): invalid ProfileCode '{0}' -- skipped folder {1}" -f $datCode, $folderKey)
                continue
            }
            if ($gameProfilesDir) {
                $datCode = Resolve-ProfileCode $datCode $gameProfilesDir $profileSet
            }

            $matchedFolders[$folderKey] = $true   # prevents folder appearing in $unmatched

            if ($seenCodes.ContainsKey($datCode)) {
                if ($preExistingCodes.Contains($datCode)) {
                    if ($already -notcontains $datCode) { [void]$already.Add($datCode) }
                } else {
                    $dupFolderFull = Join-Path $installBase $origName
                    $dupExe = @($exeFiles | Where-Object {
                        $_.FullName.Length -gt $dupFolderFull.Length -and
                        $_.FullName.StartsWith($dupFolderFull + '\')
                    })[0]
                    [void]$ambiguous.Add([pscustomobject]@{
                        Exe        = if ($dupExe) { $dupExe.FullName } else { $dupFolderFull }
                        Codes      = $datCode
                        BestGuess  = $datCode
                        BestScore  = 1.0
                        Reason     = "duplicate"
                        ClaimedBy  = $codeClaimedBy[$datCode]
                    })
                }
                continue
            }
            $seenCodes[$datCode] = $true
            $codeClaimedBy[$datCode] = $origName

            $userProfile = Join-Path $userProfilesDir ($datCode + ".xml")
            if (Test-Path -LiteralPath $userProfile) {
                [void]$already.Add($datCode)
                Backfill-SecondaryExecutablePath $userProfile $DryRun
                continue
            }

            $templatePath = Join-Path $gameProfilesDir ($datCode + ".xml")
            if (-not (Test-Path -LiteralPath $templatePath)) {
                Write-Log ("DatIndex (pass2): no GameProfiles template for '{0}' -- skipping {1}" -f $datCode, $folderKey)
                continue
            }

            # Resolve the exe: dat's Executable path first, then any file in the folder.
            $folderFull = Join-Path $installBase $origName
            $exeToUse   = $null
            if (-not [string]::IsNullOrWhiteSpace($datEntry.Executable)) {
                $relExe = $datEntry.Executable.TrimStart('\', '/')
                if ($relExe) {
                    $datExe = Join-Path $folderFull $relExe
                    if (Test-PathInside $datExe $folderFull) {
                        if     (Test-Path -LiteralPath $datExe              -PathType Leaf) { $exeToUse = $datExe }
                        elseif (Test-Path -LiteralPath ($datExe + ".exe") -PathType Leaf) { $exeToUse = $datExe + ".exe" }
                        elseif (Test-Path -LiteralPath ($datExe + ".elf") -PathType Leaf) { $exeToUse = $datExe + ".elf" }
                    }
                }
            }
            if (-not $exeToUse) {
                # Fallback: pick the first matching file already found for this folder
                $first = @($exeFiles | Where-Object {
                    $_.FullName.Length -gt $folderFull.Length -and
                    $_.FullName.StartsWith($folderFull + '\')
                })[0]
                if ($first) { $exeToUse = $first.FullName }
            }
            if (-not $exeToUse) {
                Write-Log ("DatIndex (pass2): no exe found for '{0}' in folder {1}" -f $datCode, $folderKey)
                continue
            }

            try {
                $tpl = Read-Xml $templatePath
                $gp  = $tpl.GameProfile.SelectSingleNode("GamePath")
                if ($null -eq $gp) {
                    $gp = $tpl.CreateElement("GamePath")
                    [void]$tpl.GameProfile.PrependChild($gp)
                }
                $gp.InnerText = $exeToUse
                Set-SecondaryExecutablePath $tpl $exeToUse
                Save-XmlMaybe $tpl $userProfile $DryRun
                $label = if ($datScore -lt 1.0) { "dat/fuzzy $([Math]::Round($datScore,2))" } else { "dat/exact" }
                [void]$registered.Add([pscustomobject]@{
                    Code        = $datCode
                    GamePath    = $exeToUse
                    DatMatch    = $true
                    FuzzyScore  = if ($datScore -lt 1.0) { [Math]::Round($datScore, 2) } else { $null }
                    FuzzyFolder = if ($datScore -lt 1.0) { $origName } else { $null }
                })
                Write-Log "Registered ($label) $datCode -> $exeToUse"
            } catch {
                Write-Host "  FAILED to register $datCode : $_" -ForegroundColor Red
                Write-Log "Register (dat pass2) FAILED $datCode -- $_"
            }
        }
    }

    # Third pass: folders still unmatched -- Dice-compare normalised folder name
    # against normalised profile code names. Targets games whose GameProfile has
    # an empty <ExecutableName> (BladeStrangers, LuigisMansion, PokkenTournament,
    # etc.) that never entered $profileIndex and have no dat entry.
    if ($gameProfilesDir -and $profileSet -and $profileSet.Count -gt 0) {
        $normCodeList = @(foreach ($code in $profileSet) {
            $n = Get-NormalizedGameKey $code
            if ($n) { [pscustomobject]@{ Code = $code; Norm = $n } }
        })

        foreach ($folderKey in @($allExeFolders.Keys | Where-Object { -not $matchedFolders.ContainsKey($_) })) {
            $origName   = $allExeFolders[$folderKey]
            $normFolder = Get-NormalizedGameKey $folderKey
            if (-not $normFolder) { continue }

            $bestScore = 0.0
            $bestCode  = $null
            foreach ($nc in $normCodeList) {
                $score = Get-DiceSimilarity $normFolder $nc.Norm
                if ($score -gt $bestScore) { $bestScore = $score; $bestCode = $nc.Code }
            }
            if ($bestScore -lt $FuzzyAutoThreshold -or -not $bestCode) { continue }

            $matchedFolders[$folderKey] = $true

            if ($seenCodes.ContainsKey($bestCode)) {
                if ($preExistingCodes.Contains($bestCode)) {
                    if ($already -notcontains $bestCode) { [void]$already.Add($bestCode) }
                } else {
                    $dupFolderFull = Join-Path $installBase $origName
                    $dupExe = @($exeFiles | Where-Object {
                        $_.FullName.Length -gt $dupFolderFull.Length -and
                        $_.FullName.StartsWith($dupFolderFull + '\')
                    })[0]
                    [void]$ambiguous.Add([pscustomobject]@{
                        Exe        = if ($dupExe) { $dupExe.FullName } else { $dupFolderFull }
                        Codes      = $bestCode
                        BestGuess  = $bestCode
                        BestScore  = 1.0
                        Reason     = "duplicate"
                        ClaimedBy  = $codeClaimedBy[$bestCode]
                    })
                }
                continue
            }
            $seenCodes[$bestCode] = $true
            $codeClaimedBy[$bestCode] = $origName

            $userProfile = Join-Path $userProfilesDir ($bestCode + ".xml")
            if (Test-Path -LiteralPath $userProfile) {
                [void]$already.Add($bestCode)
                Backfill-SecondaryExecutablePath $userProfile $DryRun
                continue
            }

            $templatePath = Join-Path $gameProfilesDir ($bestCode + ".xml")
            if (-not (Test-Path -LiteralPath $templatePath)) {
                Write-Log ("ProfileCode (pass3): no template for '{0}' -- skipping {1}" -f $bestCode, $folderKey)
                continue
            }

            # Prefer .exe > .elf > extension-less > .xbe > .dll when GameProfile
            # has no ExecutableName to guide us.
            $folderFull = Join-Path $installBase $origName
            $candidates = @($exeFiles | Where-Object {
                $_.FullName.Length -gt $folderFull.Length -and
                $_.FullName.StartsWith($folderFull + '\')
            })
            $exeToUse = $null
            foreach ($prio in @('.exe', '.elf', '', '.xbe', '.dll')) {
                $hit = @($candidates | Where-Object { $_.Extension.ToLower() -eq $prio })[0]
                if ($hit) { $exeToUse = $hit.FullName; break }
            }
            if (-not $exeToUse -and $candidates.Count -gt 0) { $exeToUse = $candidates[0].FullName }
            if (-not $exeToUse) {
                Write-Log ("ProfileCode (pass3): no exe found for '{0}' in folder {1}" -f $bestCode, $folderKey)
                continue
            }

            try {
                $tpl = Read-Xml $templatePath
                $gp  = $tpl.GameProfile.SelectSingleNode("GamePath")
                if ($null -eq $gp) {
                    $gp = $tpl.CreateElement("GamePath")
                    [void]$tpl.GameProfile.PrependChild($gp)
                }
                $gp.InnerText = $exeToUse
                Set-SecondaryExecutablePath $tpl $exeToUse
                Save-XmlMaybe $tpl $userProfile $DryRun
                [void]$registered.Add([pscustomobject]@{
                    Code        = $bestCode
                    GamePath    = $exeToUse
                    DatMatch    = $false
                    FuzzyScore  = [Math]::Round($bestScore, 2)
                    FuzzyFolder = $origName
                })
                Write-Log ("Registered (code/fuzzy {0}) {1} -> {2}" -f [Math]::Round($bestScore,2), $bestCode, $exeToUse)
            } catch {
                Write-Host "  FAILED to register $bestCode : $_" -ForegroundColor Red
                Write-Log "Register (pass3) FAILED $bestCode -- $_"
            }
        }
    }

    # A folder can contain more than one exe-like file -- e.g. a dedicated
    # launcher (already cleanly matched to its own profile elsewhere in this
    # loop) sitting alongside an unrelated generic/shared stub (which only
    # collided with OTHER profiles' ExecutableName and was reported above as
    # "shared"/ambiguous). $matchedFolders already tracks every folder that
    # got a conclusive match from ANY of its exes; $unmatched below already
    # filters against it, but $ambiguous never did, so a folder whose real
    # game was already correctly registered via one exe could still show up
    # in the "needs manual registration" report because of a second,
    # unrelated exe in the same folder. Drop any ambiguous entry whose
    # folder is in $matchedFolders by now -- the folder is accounted for
    # Pass 4: subFolderMap -- profile codes whose executable lives in a known
    # subfolder of the TeknoParrot root rather than in the staging folder.
    # Example: CrediarDolphin titles whose game files must live at
    # TeknoParrot\CrediarDolphin\User\Wii\. Configured in overrides.json:
    # { "subFolderMap": { "TatsunokoCap": "CrediarDolphin\\User\\Wii" } }
    if ($subFolderMap -and $subFolderMap.Count -gt 0 -and $gameProfilesDir -and
        $tpRootDir -and (Test-Path -LiteralPath $tpRootDir)) {
        foreach ($sfCode in @($subFolderMap.Keys)) {
            $sfCode = [string]$sfCode
            if ($sfCode -notmatch '^[\w]+$') {
                Write-Log "Register-Games: subFolderMap key '$sfCode' contains invalid characters -- skipped."
                continue
            }
            if ($preExistingCodes.Contains($sfCode) -or $seenCodes.ContainsKey($sfCode)) { continue }
            $sfSubPath = [string]$subFolderMap[$sfCode]
            $sfScanDir = Join-Path $tpRootDir $sfSubPath
            if (-not (Test-Path -LiteralPath $sfScanDir)) { continue }
            $sfTplPath = Join-Path $gameProfilesDir "$sfCode.xml"
            if (-not (Test-Path -LiteralPath $sfTplPath)) { continue }
            $sfExeName = Get-PrimaryExecutableName $sfTplPath
            if (-not $sfExeName) { continue }
            $sfExePath = Join-Path $sfScanDir $sfExeName
            if (-not (Test-Path -LiteralPath $sfExePath -PathType Leaf)) { continue }
            $sfUserProfile = Join-Path $userProfilesDir "$sfCode.xml"
            if (Test-Path -LiteralPath $sfUserProfile) {
                [void]$already.Add($sfCode)
                $seenCodes[$sfCode] = $true
                Backfill-SecondaryExecutablePath $sfUserProfile $DryRun
                continue
            }
            $seenCodes[$sfCode] = $true
            try {
                $sfTpl = Read-Xml $sfTplPath
                $sfGp  = $sfTpl.GameProfile.SelectSingleNode("GamePath")
                if ($null -eq $sfGp) {
                    $sfGp = $sfTpl.CreateElement("GamePath")
                    [void]$sfTpl.GameProfile.PrependChild($sfGp)
                }
                $sfGp.InnerText = $sfExePath
                Set-SecondaryExecutablePath $sfTpl $sfExePath
                Save-XmlMaybe $sfTpl $sfUserProfile $DryRun
                [void]$registered.Add([pscustomobject]@{ Code = $sfCode; GamePath = $sfExePath; SubFolderMatch = $true })
                Write-Log "Registered (subFolderMap) $sfCode -> $sfExePath"
            } catch {
                Write-Host "  FAILED to register $sfCode (subFolderMap) : $_" -ForegroundColor Red
                Write-Log "Register FAILED $sfCode (subFolderMap) -- $_"
            }
        }
    }

    # regardless of what this particular exe resolved to. See issue #9
    # (Nosferatu Lilinor: NLAM.exe cleanly registers the real profile, but a
    # generic "main" stub in the same folder collides with WMMT3/WMMT3DXP
    # and was being reported as still needing registration).
    $ambiguous = @($ambiguous | Where-Object {
        $rel        = if ($_.Exe.Length -gt $installBase.Length) { $_.Exe.Substring($installBase.Length).TrimStart('\') } else { $_.Exe }
        $folderName = ($rel -split '\\')[0]
        $folderKey  = $folderName -replace '\.(teknoparrot|parrot|game)$', ''
        -not $matchedFolders.ContainsKey($folderKey)
    })

    $unmatched = @($allExeFolders.Keys | Where-Object { -not $matchedFolders.ContainsKey($_) } | Sort-Object)
    return [pscustomobject]@{ Registered = $registered; Already = $already; Ambiguous = $ambiguous; Unmatched = $unmatched }
}

# Checks every UserProfile's GamePath and re-points broken ones (empty path or
# missing file). Locates the game's executable by name in the install folder.
# An exe name is only used to auto-fix a path when it belongs to exactly ONE
# profile in the TeknoParrot library AND exactly ONE file is found on disk.
# If the exe name is shared by multiple profiles (e.g. sdaemon.exe, game.exe)
# it is always flagged as ambiguous -- even if only one file exists on disk --
# because there is no safe way to know which game the file belongs to.
# Profiles with a valid, working path are left untouched.
function Repair-GamePaths {
    param([string]$userProfilesDir, [string]$installFolder, [hashtable]$profileIndex, [bool]$DryRun = $false)

    # Map filename (lowercased) -> list of full paths found on disk.
    # Uses Get-GameFiles so .xbe, .dll, ELF, disc images, and extension-less
    # binaries are all included alongside Windows EXE files.
    $exeMap = @{}
    foreach ($file in (Get-GameFiles $installFolder)) {
        $k = $file.Name.ToLower()
        if (-not $exeMap.ContainsKey($k)) { $exeMap[$k] = New-Object System.Collections.ArrayList }
        [void]$exeMap[$k].Add($file.FullName)
    }

    $reports = New-Object System.Collections.ArrayList
    $files = Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        try { $doc = Read-Xml $f.FullName } catch { Write-Log "Repair-GamePaths: could not parse $($f.Name) -- $_"; continue }
        if ($null -eq $doc.GameProfile) { continue }

        $gpNode  = $doc.GameProfile.SelectSingleNode("GamePath")
        $curPath = if ($gpNode) { $gpNode.InnerText } else { "" }
        $exeName = [string]$doc.GameProfile.ExecutableName

        if ($curPath -and (Test-Path -LiteralPath $curPath)) { continue }   # path is fine

        if ([string]::IsNullOrWhiteSpace($exeName)) {
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "no-exe-name" })
            continue
        }
        # If this exe name maps to more than one profile in the library it is
        # inherently ambiguous -- never auto-assign it regardless of what is on disk.
        $alts         = Get-ExeAlternatives $exeName.Trim()
        $profileCount = ($alts | ForEach-Object {
            $ak = $_.ToLower()
            if ($profileIndex.ContainsKey($ak)) { $profileIndex[$ak].Count } else { 0 }
        } | Measure-Object -Maximum).Maximum
        if (-not $profileCount) { $profileCount = 0 }
        if ($profileCount -gt 1) {
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "ambiguous"; Exe = $exeName })
            continue
        }

        # Try each alternative name in the on-disk map.
        $key = $null
        foreach ($alt in $alts) {
            $ak = $alt.ToLower()
            if ($exeMap.ContainsKey($ak)) { $key = $ak; break }
        }
        if ($null -eq $key) {
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "not-found"; Exe = $exeName })
            continue
        }
        if ($exeMap[$key].Count -gt 1) {
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "ambiguous"; Exe = $exeName })
            continue
        }

        # Exe name is unique in the library and only one file exists on disk -- safe to fix.
        $newPath = $exeMap[$key][0]
        try {
            if ($null -eq $gpNode) {
                $gpNode = $doc.CreateElement("GamePath")
                [void]$doc.GameProfile.PrependChild($gpNode)
            }
            $gpNode.InnerText = $newPath
            Save-XmlMaybe $doc $f.FullName $DryRun
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "fixed"; NewPath = $newPath })
            Write-Log "Repair: fixed $($f.BaseName) -> $newPath"
        } catch {
            Write-Log "Repair: FAILED to save $($f.Name) -- $_"
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "save-failed" })
        }
    }
    return $reports
}

# Read-only library status: classifies every UserProfile's GamePath as
# valid / broken / empty, the same check Repair-GamePaths already does
# (Test-Path on $curPath), but reports only -- never writes, never scans
# the install folder, never touches the network. Safe to run any time as a
# fast health check between full AutoSync/Register runs.
function Invoke-LibraryHealthCheck {
    param([string]$UserProfilesDir, [string]$LogPath, [string]$TpRoot)

    $profiles = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" } | Sort-Object BaseName)

    $valid = New-Object System.Collections.ArrayList
    $broken = New-Object System.Collections.ArrayList
    $empty = New-Object System.Collections.ArrayList

    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { [void]$broken.Add($pf.BaseName); continue }
            $gpNode  = $doc.GameProfile.SelectSingleNode("GamePath")
            $curPath = if ($gpNode) { $gpNode.InnerText.Trim() } else { "" }
            if ([string]::IsNullOrWhiteSpace($curPath)) {
                [void]$empty.Add($pf.BaseName)
            } elseif (Test-Path -LiteralPath $curPath) {
                [void]$valid.Add($pf.BaseName)
            } else {
                [void]$broken.Add($pf.BaseName)
            }
        } catch {
            [void]$broken.Add($pf.BaseName)
            Write-Log "HealthCheck: could not parse $($pf.Name) -- $_"
        }
    }

    Write-Host ""
    Write-Host ("  Registered profiles : {0}" -f $profiles.Count) -ForegroundColor Cyan
    Write-Host ("  Valid GamePath      : {0}" -f $valid.Count) -ForegroundColor Green
    if ($broken.Count -gt 0) {
        Write-Host ("  Broken GamePath     : {0}" -f $broken.Count) -ForegroundColor Red
        Write-Host ("    {0}" -f ($broken -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host "  Broken GamePath     : 0" -ForegroundColor Green
    }
    if ($empty.Count -gt 0) {
        Write-Host ("  Empty GamePath      : {0}" -f $empty.Count) -ForegroundColor Yellow
        Write-Host ("    {0}" -f ($empty -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host "  Empty GamePath      : 0" -ForegroundColor Green
    }
    if ($broken.Count -gt 0 -or $empty.Count -gt 0) {
        Write-Host ""
        Write-Host "  Run Register only (mode 2) or AutoSync (mode 1) and choose Repair" -ForegroundColor DarkCyan
        Write-Host "  to fix broken paths automatically where possible." -ForegroundColor DarkCyan
    }

    # -- Optional-setup coverage: GPU fix + FFB Blaster -------------------------
    # Read-only, local-only (no network) -- mirrors Invoke-GpuFixSetup and
    # Invoke-FFBBlasterSetup's detection via the shared Get-*FieldNames /
    # Test-*UpToDate helpers, but never writes anything. Third-party FFB
    # plugin coverage is deliberately NOT checked here -- it requires a
    # live fetch of the AutoSetup.cmd table, which would break this mode's
    # "no network access" guarantee; run mode 7 to check that instead.
    $gpuFixNeeded     = New-Object System.Collections.ArrayList
    $ffbBlasterNeeded = New-Object System.Collections.ArrayList
    $dgVoodoo2Needed  = New-Object System.Collections.ArrayList
    $postgresNeeded   = New-Object System.Collections.ArrayList
    $postgresConfigured = 0
    $reShadeCount     = 0
    $bepInExCount     = 0
    $detected         = Get-DetectedGpuVendor
    $combinedFields    = Get-GpuAndFfbFieldNames -TpRoot $TpRoot
    $gpuFields        = $combinedFields.Gpu
    $ffbFields        = $combinedFields.Ffb

    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { continue }
            if ($detected.Vendor) {
                $gpuResult = Test-GpuFixUpToDate -Doc $doc -BoolFields $gpuFields.BoolFields -DropdownFields $gpuFields.DropdownFields -Vendor $detected.Vendor
                if ($gpuResult.Eligible -and -not $gpuResult.UpToDate) { [void]$gpuFixNeeded.Add($pf.BaseName) }
            }
            # Use the same structured gate the setup flow uses (issue #41) so
            # the health check agrees exactly with what Invoke-FFBBlasterSetup
            # would actually do: only a 'Supported' profile that still needs a
            # write is reported as needing the fix. An unsupported platform
            # (e.g. pcsx2x6) or an unrecognized/drifted field is never flagged
            # here as "not applied" -- it cannot and should not be applied.
            $ffbSupport = Get-FFBBlasterSupport -Doc $doc -Categories $ffbFields
            if ($ffbSupport.Status -eq 'Supported' -and $ffbSupport.WouldWrite) { [void]$ffbBlasterNeeded.Add($pf.BaseName) }

            if (Test-GameNeedsPostgres $doc) {
                if ([string]::IsNullOrWhiteSpace((Get-PostgresFieldValue $doc "Pass"))) {
                    [void]$postgresNeeded.Add($pf.BaseName)
                } else {
                    $postgresConfigured++
                }
            }

            # dgVoodoo2 / ReShade / BepInEx all need a resolved, existing exe
            # path -- skip silently for broken/empty profiles (already
            # reported above).
            $gpNode   = $doc.GameProfile.SelectSingleNode("GamePath")
            $gamePath = if ($gpNode) { $gpNode.InnerText.Trim() } else { "" }
            if ([string]::IsNullOrWhiteSpace($gamePath) -or -not (Test-Path -LiteralPath $gamePath)) { continue }
            $exeDir = [System.IO.Path]::GetDirectoryName($gamePath)
            if ([string]::IsNullOrWhiteSpace($exeDir)) { continue }

            $apis = @(Get-GameLegacyApi -ExePath $gamePath)
            $dgResult = Test-DgVoodoo2UpToDate -Apis $apis -ExeDir $exeDir
            if ($dgResult.Eligible -and -not $dgResult.UpToDate) { [void]$dgVoodoo2Needed.Add($pf.BaseName) }

            $rsInfo = Get-ReShadeTargetInfo -Doc $doc -GamePath $gamePath -ExeDir $exeDir
            if (Test-Path -LiteralPath (Join-Path $rsInfo.TargetDir $rsInfo.DllName)) { $reShadeCount++ }

            if (Get-BepInExInstalledVersion -ExeDir $exeDir) { $bepInExCount++ }
        } catch {
            Write-Log "HealthCheck: coverage check could not parse $($pf.Name) -- $_"
        }
    }

    Write-Host ""
    Write-Host "  Optional setup coverage:" -ForegroundColor Cyan
    if ($detected.Vendor) {
        if ($gpuFixNeeded.Count -gt 0) {
            Write-Host ("  GPU fix not applied : {0}  (detected: {1})" -f $gpuFixNeeded.Count, $detected.Vendor) -ForegroundColor Yellow
            Write-Host ("    {0}" -f ($gpuFixNeeded -join ', ')) -ForegroundColor DarkGray
        } else {
            Write-Host ("  GPU fix not applied : 0  (detected: {0})" -f $detected.Vendor) -ForegroundColor Green
        }
    } else {
        Write-Host "  GPU fix coverage    : skipped (could not auto-detect GPU vendor)" -ForegroundColor DarkGray
    }
    if ($ffbBlasterNeeded.Count -gt 0) {
        Write-Host ("  FFB Blaster not on  : {0}" -f $ffbBlasterNeeded.Count) -ForegroundColor Yellow
        Write-Host ("    {0}" -f ($ffbBlasterNeeded -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host "  FFB Blaster not on  : 0" -ForegroundColor Green
    }
    Write-Host "  FFB plugin coverage : not checked here (needs network access -- run mode 7)" -ForegroundColor DarkGray
    if ($dgVoodoo2Needed.Count -gt 0) {
        Write-Host ("  dgVoodoo2 not applied : {0}  (legacy DX8/DDraw/Glide games)" -f $dgVoodoo2Needed.Count) -ForegroundColor Yellow
        Write-Host ("    {0}" -f ($dgVoodoo2Needed -join ', ')) -ForegroundColor DarkGray
    } else {
        Write-Host "  dgVoodoo2 not applied : 0  (legacy DX8/DDraw/Glide games)" -ForegroundColor Green
    }
    if ($gpuFixNeeded.Count -gt 0 -or $ffbBlasterNeeded.Count -gt 0 -or $dgVoodoo2Needed.Count -gt 0) {
        Write-Host ""
        Write-Host "  Run mode 4 (ReShade), 5 (dgVoodoo2), 6 (GPU fix), or 7 (FFB) to apply these." -ForegroundColor DarkCyan
    }

    # Postgres coverage is entirely read-only here -- never calls
    # Install-Postgres83 or Invoke-PostgresGameSetup, same separation of
    # concerns as the other coverage sections above.
    $postgresInstalled = Test-PostgresInstalled
    Write-Host ""
    Write-Host ("  PostgreSQL service  : {0}" -f $(if ($postgresInstalled) { "installed and running" } else { "not installed" })) -ForegroundColor $(if ($postgresInstalled) { "Green" } else { "DarkGray" })
    if ($postgresNeeded.Count -gt 0) {
        Write-Host ("  Postgres not configured : {0}  (needs a database password set)" -f $postgresNeeded.Count) -ForegroundColor Yellow
        Write-Host ("    {0}" -f ($postgresNeeded -join ', ')) -ForegroundColor DarkGray
    } elseif ($postgresConfigured -gt 0) {
        Write-Host "  Postgres not configured : 0" -ForegroundColor Green
    }
    if ($postgresConfigured -gt 0) {
        Write-Host ("  Postgres configured : {0}" -f $postgresConfigured) -ForegroundColor DarkGray
    }
    if ($postgresNeeded.Count -gt 0) {
        Write-Host "  Run mode 11 (Postgres setup) to apply these." -ForegroundColor DarkCyan
    }

    Write-Host ""
    Write-Host "  Informational (not flagged as needing attention -- ReShade and BepInEx" -ForegroundColor DarkGray
    Write-Host "  are per-game choices, not a hardware/membership-driven yes-or-no):" -ForegroundColor DarkGray
    Write-Host ("    ReShade installed  : {0} of {1} registered games" -f $reShadeCount, $valid.Count) -ForegroundColor DarkGray
    Write-Host ("    BepInEx installed  : {0} of {1} registered games" -f $bepInExCount, $valid.Count) -ForegroundColor DarkGray

    if ($LogPath -and (Test-Path -LiteralPath $LogPath)) {
        try {
            $lastRun = Get-Content -LiteralPath $LogPath -ErrorAction Stop | Select-String "^\[.*\] Completed\. " | Select-Object -Last 1
            if ($lastRun) {
                Write-Host ""
                Write-Host ("  Last full run : {0}" -f $lastRun.Line) -ForegroundColor DarkGray
            }
        } catch {}
    }

    Write-Log ("HealthCheck: total={0} valid={1} broken={2} empty={3} gpuFixNeeded={4} ffbBlasterNeeded={5} dgVoodoo2Needed={6} reShadeCount={7} bepInExCount={8}" -f `
        $profiles.Count, $valid.Count, $broken.Count, $empty.Count, $gpuFixNeeded.Count, $ffbBlasterNeeded.Count, $dgVoodoo2Needed.Count, $reShadeCount, $bepInExCount)
}

# =============================================================================
# COMPATIBILITY WARNINGS  (Raw Thrills path-length + iDmacDrv32 version pins)
# =============================================================================
# Static, empirically-documented facts about specific old game builds --
# not something that changes upstream, so hardcoded here rather than
# live-fetched (unlike the FFB table, which tracks a live upstream project).

# Standard CRC-32 (IEEE 802.3 polynomial), table-driven. .NET has no
# built-in CRC32 type, so this is a small self-contained implementation.
function Get-Crc32 {
    param([string]$Path)
    # PowerShell parses 0xFFFFFFFF / 0xEDB88320 as negative Int32 literals
    # (they exceed Int32.MaxValue), which breaks casting/bxor against
    # [uint32] values -- use the decimal equivalents instead so they
    # promote to Int64 and cast to UInt32 cleanly.
    $poly    = 3988292384  # 0xEDB88320
    $allOnes = 4294967295  # 0xFFFFFFFF
    $crcTable = New-Object 'System.UInt32[]' 256
    for ($i = 0; $i -lt 256; $i++) {
        $c = [uint32]$i
        for ($j = 0; $j -lt 8; $j++) {
            if (($c -band 1) -ne 0) { $c = [uint32]($poly -bxor ($c -shr 1)) }
            else { $c = [uint32]($c -shr 1) }
        }
        $crcTable[$i] = $c
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $crc = [uint32]$allOnes
    foreach ($b in $bytes) {
        $crc = [uint32]($crcTable[($crc -bxor $b) -band 0xFF] -bxor ($crc -shr 8))
    }
    return ('{0:X8}' -f [uint32]($crc -bxor $allOnes))
}

# Raw Thrills used three engine generations with different hard-coded
# install-path length limits. Exceeding the limit causes the game to fail
# to launch. Value = @{ Limit; Suggested } -- Suggested is the short
# folder rename the community has settled on for that title.
$RawThrillsPathLimits = @{
    # ~64-char limit (old engine, strictest)
    'BBHPro'           = @{ Limit = 64; Suggested = 'BBHP'   }
    'BBHHome'          = @{ Limit = 64; Suggested = 'BBHPH'  }
    'FNF'              = @{ Limit = 64; Suggested = 'FNF'    }
    'FNFSB'            = @{ Limit = 64; Suggested = 'FNFSB'  }
    'GHA'              = @{ Limit = 64; Suggested = 'GHA'    }
    'NicktoonsNitro'   = @{ Limit = 64; Suggested = 'NTN'    }
    'Terminator'       = @{ Limit = 64; Suggested = 'TERM'   }
    'TargetTerrorGold' = @{ Limit = 64; Suggested = 'TTG'    }
    # ~96-char limit (mid-era engine)
    'AliensArmageddon' = @{ Limit = 96; Suggested = 'ALIENS' }
    'BBHWorld'         = @{ Limit = 96; Suggested = 'BBHW'   }
    'Cars'             = @{ Limit = 96; Suggested = 'CARS'   }
    'DirtyDrivin'      = @{ Limit = 96; Suggested = 'DRTYDR' }
    'FNFSB2'           = @{ Limit = 96; Suggested = 'FNFSB2' }
    'Frogger'          = @{ Limit = 96; Suggested = 'FROGGR' }
    'H2Overdrive'      = @{ Limit = 96; Suggested = 'H2OVER' }
    'JurassicPark'     = @{ Limit = 96; Suggested = 'JURASS' }
    'SnoCross'         = @{ Limit = 96; Suggested = 'WXGSNO' }
    # Standalone case, not a Raw Thrills title but the same kind of
    # hard-coded limit -- TPUI itself shows a warning dialog for this one.
    'YugiohDT6U'       = @{ Limit = 64; Suggested = 'YUGIOH' }
}

# Builds the normalised folder-name -> path map used by the extraction
# pickers (Select-GamesInteractive, Select-GamesInteractiveCombined) and
# Invoke-AutoSync to decide whether a ZIP's game is already extracted.
# Normalisation strips the .teknoparrot/.parrot/.game suffix and removes a
# space immediately before ( or [ so old- and new-convention folder names
# for the same game map to the same key (see callers' original comments).
#
# Also registers each PATH TOO LONG entry's original Code under its
# Suggested short name's existing folder (issue #13): a folder manually
# renamed to the short name this script itself recommended in ACTION
# REQUIRED (e.g. "AliensArmageddon" -> "ALIENS") no longer normalises to
# match the ZIP's original name, so without this it gets reported as
# "available to extract" even though it is already there.
#
# NOTE on this backfill's actual reach (found while investigating a
# follow-up report on issue #13): $RawThrillsPathLimits's keys are PROFILE
# CODES (e.g. "Cars", "DirtyDrivin"), the same short identifiers used for
# UserProfiles\<Code>.xml -- NOT the ZIP's own filename. A ZIP in this
# collection is named with the full descriptive RomVault/Eggman convention
# (e.g. "Cars (1.42)(2013-08-28)[Raw Thrills PC][TP].zip"), and AutoSync
# extracts it into a folder of that same full name. So this backfill only
# actually helps the (apparently rare) case where a ZIP's bare base name
# happens to equal its own profile code with no version/date metadata --
# for the common case it registers a map key ($code) that the caller never
# queries (callers look up the ZIP's full base name, not the profile
# code), so it silently does nothing. Left in place since it's harmless
# and still correct for that narrow case; Resolve-RegisteredGameFolder
# below is the real, general-purpose fix for the rest.
function Get-StagingFolderMap {
    param([string]$installFolder)
    $map = @{}
    foreach ($dir in (Get-ChildItem -LiteralPath $installFolder -Directory -ErrorAction SilentlyContinue)) {
        $norm = ($dir.Name -replace '\.(teknoparrot|parrot|game)$', '') -replace ' (?=[\[\(])', ''
        if (-not $map.ContainsKey($norm)) { $map[$norm] = $dir.FullName }
    }
    foreach ($code in $RawThrillsPathLimits.Keys) {
        $suggested = $RawThrillsPathLimits[$code].Suggested
        if ($map.ContainsKey($suggested) -and -not $map.ContainsKey($code)) {
            $map[$code] = $map[$suggested]
        }
    }
    return $map
}

# Folder-name matching (Get-StagingFolderMap above) cannot recognise a
# folder that was renamed to anything other than a name the script itself
# would derive from the ZIP -- a hand-picked short name, a reorganised
# subfolder, anything. But if the game is already fully registered with a
# working GamePath, its real folder location is sitting right there in the
# UserProfile XML, independent of what the folder happens to be named.
# This resolves a ZIP to that real folder via the collection dat (ZIP base
# name -> ProfileCode -> UserProfiles\<ProfileCode>.xml -> GamePath's
# containing folder), so a registered game is never reported as "available
# to extract" again regardless of how its folder is named. Returns $null
# if the dat has no entry, no matching profile is registered, or the
# registered GamePath does not actually exist on disk. See issue #13.
function Resolve-RegisteredGameFolder {
    param([string]$rawZipName, [hashtable]$datIndex, [string]$userProfilesDir)
    if (-not $datIndex -or $datIndex.Count -eq 0 -or -not $userProfilesDir) { return $null }
    $datEntry = $datIndex[(Get-NormalizedGameKey $rawZipName)]
    if (-not $datEntry -or -not $datEntry.ProfileCode) { return $null }
    # Profile codes are purely alphanumeric; reject anything else before joining
    # into a path -- the dat is externally-sourced, untrusted input, same as the
    # ProfileCode check in Register-Games (see SECURITY.md).
    if ($datEntry.ProfileCode -notmatch '^[\w]+$') { return $null }
    $profilePath = Join-Path $userProfilesDir "$($datEntry.ProfileCode).xml"
    if (-not (Test-Path -LiteralPath $profilePath)) { return $null }
    try {
        $doc    = Read-Xml $profilePath
        $gpNode = $doc.GameProfile.SelectSingleNode("GamePath")
        if ($null -eq $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { return $null }
        $gamePath = $gpNode.InnerText.Trim().TrimEnd('\')
        if (-not (Test-Path -LiteralPath $gamePath)) { return $null }
        return [System.IO.Path]::GetDirectoryName($gamePath)
    } catch { return $null }
}

# Specific games need a SPECIFIC OLD CRC of a specific file -- a newer
# version causes a coin error or other failure. This is the opposite of
# the usual "stale dll" case TPUI already self-heals (deploying its own
# current copy), so it is never auto-fixed here -- only flagged, since
# "fixing" it in the wrong direction breaks the game.
$FileVersionPins = @{
    'BBCF'                    = @{ FileName = 'iDmacDrv32.dll'; RequiredCrc = 'F1FF8CC9' }
    'BBCP'                    = @{ FileName = 'iDmacDrv32.dll'; RequiredCrc = 'F1FF8CC9' }
    'BlazBlueContinuumShift'  = @{ FileName = 'iDmacDrv32.dll'; RequiredCrc = 'BCB0E7FE' }
    'BlazBlueContinuumShift2' = @{ FileName = 'iDmacDrv32.dll'; RequiredCrc = 'BCB0E7FE' }
    'BlazBlueCrossTagBattle'  = @{ FileName = 'iDmacDrv32.dll'; RequiredCrc = 'BCB0E7FE' }
    'ttt2'                    = @{ FileName = 'EBOOT.BIN';      RequiredCrc = '3DD05100' }
}

# Specific games are confirmed NOT to work on specific GPU vendors -- not
# a setup mistake, no fix exists, so this is informational only (unlike
# the other two checks, there's nothing to do except know about it before
# troubleshooting blind). NVIDIA has no known-broken titles in this data.
$GpuIncompatibleGames = @{
    'AMD' = @(
        'BorderBreakScramble', 'GoldenTeeLive2011', 'GoldenTeeLive2012', 'GoldenTeeLive2013',
        'GoldenTeeLive2014', 'GoldenTeeLive2015', 'GoldenTeeLive2016', 'GoldenTeeLive2017',
        'GoldenTeeLive2018', 'OCCPinball', 'PowerPuttLive2012', 'PowerPuttLive2013',
        'ProjectDiva', 'SonicDashExtreme', 'TargetTossProLawndarts', 'WonderlandWars'
    )
    'Intel' = @(
        'abc', 'abcELF2', 'BorderBreakScramble', 'ChronoRegalia', 'Drakons', 'FrenzyExpress',
        'GoldenTeeLive2011', 'GoldenTeeLive2012', 'GoldenTeeLive2013', 'GoldenTeeLive2014',
        'GoldenTeeLive2015', 'GoldenTeeLive2016', 'GoldenTeeLive2017', 'GoldenTeeLive2018',
        'GoldenTeeLive2019', 'HydroThunder', 'IDZTP', 'IDZv2TP', 'LGJS', 'LGJSElf2', 'LGJ',
        'SegaOlympic2016', 'SegaOlympic2020', 'MIB', 'OffroadThunder', 'OCCPinball',
        'PowerPuttLive2012', 'PowerPuttLive2013', 'ProjectDiva', 'PullTheTrigger',
        'ShiningForceCross', 'ShiningForceCrossElysion', 'ShiningForceCrossRaid',
        'ShiningForceCrossExlesia', 'SkyCurser', 'SonicBlastHeroes', 'SonicDashExtreme',
        'SpaceWarp66', 'TargetTossProLawndarts', 'TempleRun', 'TokyoCop', '2Spicy',
        '2SpicyElf2', 'WildWestShootout', 'WonderlandWars'
    )
}

# Word-wraps free text (e.g. a community notes field) to a fixed width,
# returning one string per output line, each pre-fixed with Indent. Existing
# line breaks in the input (paragraph breaks, blank separator lines) are
# preserved as their own wrap groups rather than being collapsed -- notes
# pulled from eggmansworld.github.io are often multi-paragraph and lose all
# readability if reflowed into one block.
function Format-NoteLines {
    param([string]$Text, [int]$Width = 74, [string]$Indent = "    ")
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($rawLine in ($Text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($rawLine)) { $out.Add(""); continue }
        $cur = ""
        foreach ($word in ($rawLine -split '\s+')) {
            if ($cur -eq "") { $cur = $word }
            elseif (($cur.Length + 1 + $word.Length) -le $Width) { $cur += " $word" }
            else { $out.Add("$Indent$cur"); $cur = $word }
        }
        if ($cur -ne "") { $out.Add("$Indent$cur") }
    }
    return $out
}

# Returns per-game special setup notes + the executable TeknoParrot expects,
# for every CURRENTLY REGISTERED profile whose eggmansworld.github.io entry
# has a non-empty notes field. Joined on profile_name == ProfileCode (the
# profile XML's own basename) -- the same key already used to drive the
# hardcoded compatibility tables above. Network fetch, same convention as
# Get-BepInExRequiredGames: returns an empty array (never a hardcoded
# fallback) if the fetch fails, caller just sees nothing to report.
function Get-GameSetupNotes {
    param([string]$UserProfilesDir)

    $games = Get-EggmanGameData
    if (-not $games) { return ,@() }

    $registeredCodes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -ne "FullBackup" } |
        ForEach-Object { [void]$registeredCodes.Add($_.BaseName) }

    return @($games | Where-Object { $_.notes -and $registeredCodes.Contains($_.profile_name) } |
              ForEach-Object {
                  [pscustomobject]@{
                      Code     = $_.profile_name
                      GameName = $_.game_name
                      SetupExe = $_.setup_exe
                      Notes    = $_.notes
                  }
              })
}

# Read-only scan for all three checks above. Returns
# [pscustomobject]@{ PathTooLong = @(...); DllMismatch = @(...); GpuIncompatible = @(...) }.
# Each PathTooLong entry: @{ Code; Length; Limit; Suggested }.
# Each DllMismatch entry: @{ Code; FileName; Found; Required }.
# Each GpuIncompatible entry: @{ Code; Vendor }.
function Get-CompatibilityWarnings {
    param([string]$UserProfilesDir)

    $pathTooLong  = @()
    $dllMismatch  = @()
    $gpuIncompatible = @()

    # Best-effort, silent GPU detection -- never prompts. If undetected
    # (or vendor is NVIDIA, which has no known-broken titles here), the
    # GPU-incompatibility check is simply skipped for this run.
    $detectedVendor = (Get-DetectedGpuVendor).Vendor
    $gpuList = if ($detectedVendor -and $GpuIncompatibleGames.ContainsKey($detectedVendor)) {
        [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$GpuIncompatibleGames[$detectedVendor], [System.StringComparer]::OrdinalIgnoreCase)
    } else { $null }

    $profiles = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" })

    foreach ($pf in $profiles) {
        $code = $pf.BaseName
        $relevant = $RawThrillsPathLimits.ContainsKey($code) -or $FileVersionPins.ContainsKey($code) -or
                    ($gpuList -and $gpuList.Contains($code))
        if (-not $relevant) { continue }
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { continue }
            $gpNode = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { continue }
            $curPath = $gpNode.InnerText.Trim()
            if (-not (Test-Path -LiteralPath $curPath)) { continue }

            if ($RawThrillsPathLimits.ContainsKey($code)) {
                $info = $RawThrillsPathLimits[$code]
                if ($curPath.Length -gt $info.Limit) {
                    $pathTooLong += [pscustomobject]@{
                        Code = $code; Length = $curPath.Length
                        Limit = $info.Limit; Suggested = $info.Suggested
                    }
                }
            }

            if ($FileVersionPins.ContainsKey($code)) {
                $pin     = $FileVersionPins[$code]
                $exeDir  = [System.IO.Path]::GetDirectoryName($curPath)
                $dllPath = Join-Path $exeDir $pin.FileName
                if (Test-Path -LiteralPath $dllPath) {
                    try {
                        $foundCrc = Get-Crc32 -Path $dllPath
                        if ($foundCrc -ne $pin.RequiredCrc) {
                            $dllMismatch += [pscustomobject]@{
                                Code = $code; FileName = $pin.FileName
                                Found = $foundCrc; Required = $pin.RequiredCrc
                            }
                        }
                    } catch {
                        Write-Log "CompatibilityWarnings: could not CRC $($pin.FileName) for $code -- $_"
                    }
                }
                # File simply missing: not flagged. TPUI deploys its own
                # current copy at first launch -- nothing to warn about yet.
            }

            if ($gpuList -and $gpuList.Contains($code)) {
                $gpuIncompatible += [pscustomobject]@{ Code = $code; Vendor = $detectedVendor }
            }
        } catch {
            Write-Log "CompatibilityWarnings: could not parse $($pf.Name) -- $_"
        }
    }

    return [pscustomobject]@{ PathTooLong = $pathTooLong; DllMismatch = $dllMismatch; GpuIncompatible = $gpuIncompatible }
}

# =============================================================================
# CONTROL PROPAGATION HELPERS
# =============================================================================
#
# Profiles have no default XML namespace, so plain XPath works. The button
# layout is /GameProfile/JoystickButtons/JoystickButtons (an outer wrapper
# element containing one inner element per button).

# True if a button node already carries any input binding child.
function Test-ButtonIsBound {
    param($btn)
    return ($null -ne $btn.SelectSingleNode("RawInputButton")) -or
           ($null -ne $btn.SelectSingleNode("DirectInputButton")) -or
           ($null -ne $btn.SelectSingleNode("XInputButton"))
}

# Returns the inner button nodes of a profile [xml] document.
function Get-ButtonNodes {
    param($doc)
    return $doc.SelectNodes("/GameProfile/JoystickButtons/JoystickButtons")
}

# Composite match key for a button: "InputMapping|AnalogType".
# Returns $true if a JoystickButtons ButtonName refers to a pure directional
# control (Up/Down/Left/Right joystick axis) rather than an action button.
# After stripping a leading player-number prefix (P1/P2/Player 1/Player 2),
# the remaining label must consist ONLY of direction words. Any additional
# qualifier (Punch, Kick, Shoulder, Fire, etc.) means the slot is an action
# button that happens to use a direction word as a positional modifier (e.g.
# "Left Punch", "Left Shoulder") -- not a joystick axis.
# Used by Invoke-ControlPropagation to guard against copying e.g. SF3's D-pad
# Up binding into a target game's "Left Punch" slot when both share the same
# InputMapping key (P1ButtonUp) but mean completely different physical controls.
function Test-ButtonNameDirectional {
    param([string]$name)
    $n = $name.Trim() -replace '(?i)^\s*(player\s*[12]|p[12])\s+', ''
    $words = ($n -split '\s+') | Where-Object { $_ -ne '' }
    if ($words.Count -eq 0) { return $false }
    $dirWords = @('up','down','left','right','north','south','east','west')
    foreach ($w in $words) {
        if ($dirWords -notcontains $w.ToLower()) { return $false }
    }
    return $true
}

# AnalogType is absent on many template buttons; it defaults to None on both
# sides so a minimal template button still matches a bound archetype button.
function Get-ButtonKey {
    param($btn)
    $imNode = $btn.SelectSingleNode("InputMapping")
    if ($null -eq $imNode -or [string]::IsNullOrWhiteSpace($imNode.InnerText)) { return $null }
    $im = $imNode.InnerText.Trim()
    $atNode = $btn.SelectSingleNode("AnalogType")
    if ($atNode -and -not [string]::IsNullOrWhiteSpace($atNode.InnerText)) {
        $at = $atNode.InnerText.Trim()
    } else {
        $at = "None"
    }
    return "$im|$at"
}

# Classifies a profile's control family from its button set. This is what
# keeps bindings from crossing between game types (a wheel binding can never
# land on a gun, because driving and lightgun are different classes).
# Infers the control family from a profile's AnalogType values.
# NOTE: "spinner" cannot be auto-detected from AnalogType alone -- spinner
# games must be assigned via familyOverride in overrides.json.
function Get-ProfileFamily {
    param($doc)
    $hasWheel = $false; $hasGun = $false; $hasTrackball = $false; $hasOtherAxis = $false
    foreach ($btn in (Get-ButtonNodes $doc)) {
        $imNode = $btn.SelectSingleNode("InputMapping")
        $im = if ($imNode) { $imNode.InnerText.Trim() } else { "" }
        $atNode = $btn.SelectSingleNode("AnalogType")
        $at = if ($atNode -and -not [string]::IsNullOrWhiteSpace($atNode.InnerText)) { $atNode.InnerText.Trim() } else { "None" }
        if ($im -eq "P1Trackball" -or $im -eq "P2Trackball") { $hasTrackball = $true }
        switch ($at) {
            "Wheel"                 { $hasWheel = $true }
            "Gas"                   { $hasWheel = $true }
            "Brake"                 { $hasWheel = $true }
            "AnalogJoystick"        { $hasGun = $true }   # TeknoParrot uses analog joystick axes to represent lightgun aim
            "AnalogJoystickReverse" { $hasGun = $true }
            "None"                  { }
            default                 { $hasOtherAxis = $true }
        }
    }
    if ($hasWheel)     { return "driving"   }
    if ($hasGun)       { return "lightgun"  }
    if ($hasTrackball) { return "trackball" }
    if ($hasOtherAxis) { return "analog"    }
    return "button"
}

# Reads the "Input API" FieldValue, or $null if the profile has no such field.
function Get-ProfileInputApi {
    param($doc)
    $f = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$(ConvertTo-XPathStringLiteral 'Input API')]")
    if ($null -eq $f) { return $null }
    $v = $f.SelectSingleNode("FieldValue")
    if ($null -eq $v) { return $null }
    return $v.InnerText.Trim()
}

# Sets the "Input API" FieldValue, but only if the field exists AND lists the
# requested API among its options. Returns $true on success. This matters
# because a RawInput binding will not work if the profile's API says XInput.
# Sets the "Input API" FieldValue. Normally only succeeds if the profile's
# FieldOptions already lists the requested API -- this matters because a
# RawInput binding will not work if the profile's API says XInput. The one
# exception is "MergedInput": TeknoParrot's own UI has been confirmed
# (issue #1) to dynamically materialize "MergedInput" into a legacy
# profile's on-disk FieldOptions the first time it's selected there, so an
# absent FieldOptions entry for that specific value does not mean the
# profile can't actually use it -- it just hasn't been touched in the TP
# UI yet. Mirror that behavior here so a propagated XInput-style binding
# is actually visible/usable without requiring the user to manually
# re-toggle every target game in the TeknoParrot UI first.
function Set-ProfileInputApi {
    param($doc, [string]$api)
    $f = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$(ConvertTo-XPathStringLiteral 'Input API')]")
    if ($null -eq $f) { return $false }
    $optsNode = $f.SelectSingleNode("FieldOptions")
    $opts = if ($optsNode) { @($optsNode.SelectNodes("string") | ForEach-Object { $_.InnerText.Trim() }) } else { @() }
    if ($opts -notcontains $api) {
        if ($api -ne 'MergedInput' -or $null -eq $optsNode) { return $false }
        $newOpt = $doc.CreateElement("string")
        $newOpt.InnerText = $api
        [void]$optsNode.AppendChild($newOpt)
    }
    $v = $f.SelectSingleNode("FieldValue")
    if ($null -eq $v) { return $false }
    $v.InnerText = $api
    return $true
}

# Longest common prefix of a list of strings. Used to turn a device's bind
# names into a single device name. Returns "" for an empty list.
function Get-LongestCommonPrefix {
    param($strings)
    $arr = @($strings)
    if ($arr.Count -eq 0) { return "" }
    $prefix = [string]$arr[0]
    foreach ($s in $arr) {
        $max = [Math]::Min($prefix.Length, $s.Length)
        $i = 0
        while ($i -lt $max -and $prefix[$i] -eq $s[$i]) { $i++ }
        $prefix = $prefix.Substring(0, $i)
        if ($prefix.Length -eq 0) { break }
    }
    return $prefix
}

# Returns the distinct device names a profile is bound to. Buttons are grouped
# by their device path, and each device's name is the longest common prefix of
# its bind names (e.g. "Ultimarc I-PAC A" + "Ultimarc I-PAC F" -> "Ultimarc
# I-PAC"). This lets you confirm each game type uses the device you intend
# before copying its controls to other games.
function Get-ProfileDevices {
    param($doc)
    $byPath = @{}
    $tagOf  = @{}
    foreach ($btn in (Get-ButtonNodes $doc)) {
        foreach ($tag in @("RawInputButton","DirectInputButton","XInputButton")) {
            $bind = $btn.SelectSingleNode($tag)
            if ($null -ne $bind) {
                $dp      = $bind.SelectSingleNode("DevicePath")
                $pathKey = if ($dp) { $dp.InnerText } else { $tag }
                $bnNode  = $btn.SelectSingleNode("BindName")
                $bn      = if ($bnNode) { $bnNode.InnerText } else { "" }
                if (-not $byPath.ContainsKey($pathKey)) {
                    $byPath[$pathKey] = New-Object System.Collections.ArrayList
                    $tagOf[$pathKey]  = $tag
                }
                if ($bn -and $bn -ne 'None') { [void]$byPath[$pathKey].Add($bn) }
                break
            }
        }
    }
    $names = New-Object System.Collections.ArrayList
    foreach ($pathKey in $byPath.Keys) {
        # The API comes from the binding element type, not a guess -- a gamepad
        # read via RawInput is labelled RawInput, not XInput.
        switch ($tagOf[$pathKey]) {
            "XInputButton"      { $api = "XInput"      }
            "DirectInputButton" { $api = "DirectInput" }
            default             { $api = "RawInput"    }
        }
        $name = (Get-LongestCommonPrefix $byPath[$pathKey]).Trim()
        if ([string]::IsNullOrWhiteSpace($name)) {
            # No usable bind names: fall back to a friendly device path (e.g.
            # "Windows Mouse Cursor"), but not a raw HID path.
            if ($pathKey -and -not $pathKey.StartsWith('\\?\')) { $name = $pathKey }
            else { $name = "(unnamed device)" }
        }
        # Replace TeknoParrot's generic "Input Device N" label with the actual
        # API so the report is accurate and readable (e.g. "XInput Device 0").
        if     ($name -match '^Input Device (\d+)') { $name = "$api Device $($Matches[1])" }
        elseif ($name -match '^Input Device')       { $name = "$api Device" }
        if ($names -notcontains $name) { [void]$names.Add($name) }
    }
    return $names
}

# Config fields that describe INPUT behaviour (aim mode, sensitivity, axis
# handling). These are safe to copy between same-type games so a propagated
# game reproduces the reference game's feel. A field is copied only when the target
# also defines it, so nothing is ever invented. Verified present in real
# lightgun profiles (e.g. "Use Relative Input", relative sensitivity, cursor).
# Copying is only as correct as the reference game's own values -- the
# pre-propagation summary (Section 10) prints these before the user confirms,
# so a wrong value on the reference (e.g. an axis mode left over from
# testing with a keyboard instead of a real wheel) is caught before it
# fans out to every other game of that type.
$InputConfigFields = @(
    "Use Relative Input",
    "Player 1 Relative Sensitivity",
    "Player 2 Relative Sensitivity",
    "HideCursor",
    "Reverse Y Axis",
    "Reverse Throttle Axis",
    "Use Keyboard/Button For Axis",
    "Keyboard/Button Axis X/Y Sensitivity",
    "Keyboard/Button Axis Throttle Sensitivity"
)

# Known carried-setting values that usually mean the reference game was bound
# with a substitute device (keyboard, mouse) instead of its real hardware --
# the same root cause as "Use Keyboard/Button For Axis" left True on a wheel
# game. Each entry: the family this applies to, the carried field name, the
# value that triggers the warning, and why it matters.
$ConfigCarryWarnings = @(
    @{ Family = "driving";  Field = "Use Keyboard/Button For Axis"; Value = "True"
       Message = "wheel/pedal axes will be read as digital keyboard/button input, not analog -- should be False if you bind with a real wheel." },
    @{ Family = "lightgun"; Field = "Use Relative Input"; Value = "True"
       Message = "gun aim will be read as relative mouse-style movement, not absolute screen position -- should usually be False for a real lightgun that reports absolute coordinates." }
)

# Returns warning strings for a family's carried config values: known
# device-mismatch combos (see $ConfigCarryWarnings) plus any "...Sensitivity"
# field carried as literal 0, which would silently disable aiming/axis
# response on every propagated game of that type.
function Get-ConfigCarryFlags {
    param([string]$family, $configCarry)
    $flags = New-Object System.Collections.ArrayList
    foreach ($rule in $ConfigCarryWarnings) {
        if ($rule.Family -eq $family -and $configCarry.ContainsKey($rule.Field) -and $configCarry[$rule.Field] -eq $rule.Value) {
            [void]$flags.Add("$($rule.Field)=$($rule.Value) -- $($rule.Message)")
        }
    }
    foreach ($key in $configCarry.Keys) {
        if ($key -match 'Sensitivity$' -and $configCarry[$key].Trim() -eq "0") {
            [void]$flags.Add("$key=0 -- this disables aiming/axis response entirely.")
        }
    }
    return $flags
}

# Returns a hashtable { FieldName = FieldValue } for those of $names that the
# profile's ConfigValues actually contains.
function Get-ConfigFieldMap {
    param($doc, $names)
    $out = @{}
    foreach ($fi in $doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation")) {
        $fn = $fi.SelectSingleNode("FieldName")
        if ($null -eq $fn) { continue }
        $name = $fn.InnerText.Trim()
        if ($names -contains $name) {
            $fv = $fi.SelectSingleNode("FieldValue")
            if ($null -ne $fv) { $out[$name] = $fv.InnerText }
        }
    }
    return $out
}

# Sets a ConfigValues field's value if the field exists in the profile.
# Returns $true if it was set. (Field names are a fixed internal whitelist,
# so the XPath literal below is not built from external input.)
function Set-ConfigField {
    param($doc, [string]$name, [string]$value)
    $fi = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$(ConvertTo-XPathStringLiteral $name)]")
    if ($null -eq $fi) { return $false }
    $fv = $fi.SelectSingleNode("FieldValue")
    if ($null -eq $fv) { return $false }
    $fv.InnerText = $value
    return $true
}

# Scans UserProfiles and returns the bound-game pool: every profile that the
# user has bound to a meaningful degree (>= $minBound bound buttons). Each
# entry carries its family, Input API, and a map of (key -> bound button node)
# used as the source of truth for copying. Includes previously-propagated profiles
# intentionally: on re-runs they act as archetypes for any newly registered games.
function Build-ArchetypePool {
    param([string]$userProfilesDir, [int]$minBound)
    $pool  = New-Object System.Collections.ArrayList
    $files = Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        try { $doc = Read-Xml $f.FullName }
        catch { Write-Log "Pool scan: could not parse $($f.Name)"; continue }
        if ($null -eq $doc.GameProfile) { continue }
        $map = @{}; $boundCount = 0
        foreach ($btn in (Get-ButtonNodes $doc)) {
            if (Test-ButtonIsBound $btn) {
                $key = Get-ButtonKey $btn
                if ($key) { $map[$key] = $btn; $boundCount++ }
            }
        }
        if ($boundCount -ge $minBound) {
            [void]$pool.Add([pscustomobject]@{
                Code        = $f.BaseName
                Path        = $f.FullName
                Family      = (Get-ProfileFamily $doc)
                InputApi    = (Get-ProfileInputApi $doc)
                Devices     = (Get-ProfileDevices $doc)
                ConfigCarry = (Get-ConfigFieldMap $doc $InputConfigFields)
                Map         = $map
                BoundCount  = $boundCount
            })
        }
    }
    return $pool
}

# For each UNbound (or barely-bound) profile, choose the best same-family
# reference game by key overlap, copy its bindings into matching unbound
# buttons, carry its Input API, and record what was bound vs left manual.
# Reference games are never modified. Returns a list of per-game report objects.
function Invoke-ControlPropagation {
    param([string]$userProfilesDir, $pool, [int]$minBound, $noPropagate = @(), $forceArchetype = @{}, $familyOverride = @{}, $canonicalArchetype = @{}, [bool]$DryRun = $false)

    $reports     = New-Object System.Collections.ArrayList
    $files       = Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue
    $sourcePaths = @{}
    foreach ($s in $pool) { $sourcePaths[$s.Path] = $true }

    foreach ($f in $files) {
        # An archetype's BINDINGS are never modified, full stop. Its own
        # Input API may only be corrected against a family's user-
        # designated canonical archetype (canonicalArchetype in
        # overrides.json) -- never a heuristic guess. v0.99.12 tried
        # guessing via best non-self button overlap, reasoning that an
        # archetype can itself be sitting on a stale API, and actively
        # broke a real tester's library: almost every well-bound
        # button-family profile is simultaneously a pool member (the same
        # $minBound threshold drives both), so the "best overlap" heuristic
        # -- which is fine for deciding what bindings to COPY -- ended up
        # cross-correcting unrelated, independently-correct archetypes
        # against each other with no actual signal for which one is right.
        # Confirmed in a real run: StreetFighterIII3rdStrike, the tester's
        # own deliberately-configured MergedInput reference, got silently
        # flipped to DirectInput because a different archetype (BBCF) won
        # the overlap comparison. Reverted in v0.99.14. canonicalArchetype
        # (v0.99.17) sidesteps that exact problem: correction only ever
        # runs when the user has explicitly named the one correct archetype
        # for that family, and only ever pulls from that one designated
        # source -- never a guess. See issue #1.
        if ($sourcePaths.ContainsKey($f.FullName)) {
            $selfEntry = $null
            foreach ($s in $pool) { if ($s.Path -eq $f.FullName) { $selfEntry = $s; break } }
            if ($selfEntry -and $canonicalArchetype.ContainsKey($selfEntry.Family)) {
                $canonCode = [string]$canonicalArchetype[$selfEntry.Family]
                if ($selfEntry.Code -ne $canonCode) {
                    $canon = $null
                    foreach ($s in $pool) { if ($s.Code -eq $canonCode) { $canon = $s; break } }
                    if ($canon -and $canon.InputApi -and $canon.InputApi -ne $selfEntry.InputApi) {
                        try { $canonDoc = Read-Xml $f.FullName }
                        catch { Write-Log "Propagation: could not parse $($f.Name) for canonical Input API check"; continue }
                        if ($null -ne $canonDoc.GameProfile -and (Set-ProfileInputApi $canonDoc $canon.InputApi)) {
                            try {
                                Save-XmlMaybe $canonDoc $f.FullName $DryRun
                                # Update the in-memory pool entry too, not just the file on disk --
                                # $selfEntry is the same object instance referenced by $pool, so this
                                # is visible to every later iteration of this same loop. Without this,
                                # a non-archetype profile that propagates from $selfEntry later in this
                                # very run (e.g. a target alphabetically after this archetype) would
                                # still copy the now-stale pre-correction InputApi, since $best.InputApi
                                # below is read from this same pool snapshot. Confirmed on a real
                                # tester's log: BBCF's correction and ChronoRegalia/dbzenkai/
                                # PokkenTournament/PPQ propagating FROM BBCF with the old DirectInput
                                # value happened in the same second of the same run. See issue #1.
                                $selfEntry.InputApi = $canon.InputApi
                                [void]$reports.Add([pscustomobject]@{
                                    Code = $f.BaseName; Status = "api-fixed-canonical"
                                    Archetype = $canon.Code; ArchetypeApi = $canon.InputApi
                                })
                                Write-Log "Propagation: $($f.BaseName) (archetype) Input API corrected to $($canon.InputApi) to match user-designated canonical archetype $($canon.Code) for family $($selfEntry.Family)"
                            } catch {
                                Write-Log "Propagation: FAILED to save canonical Input API fix for $($f.Name) -- $_"
                                [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "save-failed"; Archetype = $canon.Code })
                            }
                        }
                    }
                }
            }
            continue
        }
        if ($noPropagate -contains $f.BaseName) {
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "skipped-override" })
            continue
        }

        try { $doc = Read-Xml $f.FullName }
        catch { Write-Log "Propagation: could not parse $($f.Name)"; continue }
        if ($null -eq $doc.GameProfile) { continue }

        $btns = Get-ButtonNodes $doc
        if ($null -eq $btns -or $btns.Count -eq 0) { continue }

        $alreadyBound = 0
        foreach ($b in $btns) { if (Test-ButtonIsBound $b) { $alreadyBound++ } }
        $buttonsAlreadyBound = ($alreadyBound -ge $minBound)

        $targetFamily = if ($familyOverride.ContainsKey($f.BaseName)) {
            $familyOverride[$f.BaseName]
        } else {
            Get-ProfileFamily $doc
        }

        # If this game is pinned to a specific archetype via overrides, use it
        # (this is an explicit user choice, so family is not enforced here).
        $best = $null; $bestOverlap = 0; $forced = $false
        if ($forceArchetype.ContainsKey($f.BaseName)) {
            $wantCode = [string]$forceArchetype[$f.BaseName]
            foreach ($s in $pool) { if ($s.Code -eq $wantCode) { $best = $s; $forced = $true; break } }
            if ($null -eq $best) {
                Write-Log "Propagation: pinned archetype '$wantCode' for $($f.BaseName) not found; using best match."
            }
        }

        # Otherwise pick the best same-family archetype by how many of this
        # game's keys it can supply. Ties go to the more completely-bound one.
        # Computed even when this profile's buttons are already bound (below)
        # -- needed there too, to check whether the archetype's Input API can
        # be retroactively applied without touching any button binding.
        if ($null -eq $best) {
            foreach ($s in $pool) {
                if ($s.Family -ne $targetFamily) { continue }
                $ov = 0
                foreach ($b in $btns) { $k = Get-ButtonKey $b; if ($k -and $s.Map.ContainsKey($k)) { $ov++ } }
                if ($ov -gt $bestOverlap -or ($ov -eq $bestOverlap -and $null -ne $best -and $s.BoundCount -gt $best.BoundCount)) {
                    $best = $s; $bestOverlap = $ov
                }
            }
            if ($null -eq $best -or $bestOverlap -eq 0) {
                if ($buttonsAlreadyBound) {
                    [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "skipped-bound" })
                } else {
                    [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "no-archetype"; Family = $targetFamily })
                }
                continue
            }
        }

        # A profile whose buttons are already configured is never re-bound
        # (this loop never touches a working binding), but the Input API
        # fix from issue #1 only runs from inside this same per-profile pass
        # -- without this branch it could never reach an already-bound
        # profile on any later run, even after the fix shipped, since this
        # function would always continue past it above. Checking and
        # correcting just the Input API field here, independent of button
        # binding, lets that fix apply retroactively. See issue #1.
        if ($buttonsAlreadyBound) {
            $currentApi = Get-ProfileInputApi $doc
            $apiSet = $false
            if ($best.InputApi -and $best.InputApi -ne $currentApi) {
                $apiSet = Set-ProfileInputApi $doc $best.InputApi
            }

            # Report-only: scan bound slots for directional/action classification
            # mismatch vs the archetype. Never rewrites -- only flags for ACTION
            # REQUIRED output so the user knows which slots need a manual rebind
            # in TeknoParrot's own UI. Same Test-ButtonNameDirectional logic the
            # non-bound copy path uses to PREVENT these mismatches going forward.
            # See issue #17.
            $mismatchSlots = New-Object System.Collections.ArrayList
            foreach ($b in $btns) {
                if (-not (Test-ButtonIsBound $b)) { continue }
                $k = Get-ButtonKey $b
                if (-not $k -or -not $best.Map.ContainsKey($k)) { continue }
                $srcNameNode = $best.Map[$k].SelectSingleNode("ButtonName")
                $srcName = if ($srcNameNode) { $srcNameNode.InnerText } else { "" }
                $nameNode = $b.SelectSingleNode("ButtonName")
                $btnName = if ($nameNode) { $nameNode.InnerText } else { "" }
                if ((Test-ButtonNameDirectional $srcName) -ne (Test-ButtonNameDirectional $btnName)) {
                    [void]$mismatchSlots.Add($btnName)
                }
            }
            $mismatchStr = if ($mismatchSlots.Count -gt 0) { $mismatchSlots -join ', ' } else { $null }

            if ($apiSet) {
                try {
                    Save-XmlMaybe $doc $f.FullName $DryRun
                    [void]$reports.Add([pscustomobject]@{
                        Code = $f.BaseName; Status = "api-fixed"
                        Archetype = $best.Code; ArchetypeApi = $best.InputApi
                        MismatchSlots = $mismatchStr
                    })
                    Write-Log "Propagation: $($f.BaseName) already bound -- updated Input API to $($best.InputApi) to match archetype $($best.Code)"
                } catch {
                    Write-Log "Propagation: FAILED to save Input API fix for $($f.Name) -- $_"
                    [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "save-failed"; Archetype = $best.Code })
                }
            } else {
                [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "skipped-bound"; MismatchSlots = $mismatchStr })
            }
            if ($mismatchStr) {
                Write-Log "Propagation: $($f.BaseName) already bound -- $($mismatchSlots.Count) slot(s) have directional/action mismatch vs archetype $($best.Code): $mismatchStr -- rebind in TeknoParrot UI"
            }
            continue
        }

        $boundNow = 0
        $manual   = New-Object System.Collections.ArrayList
        foreach ($b in @($btns)) {                     # @() snapshots before tree edits
            if (Test-ButtonIsBound $b) { continue }
            $k        = Get-ButtonKey $b
            $nameNode = $b.SelectSingleNode("ButtonName")
            $btnName  = if ($nameNode) { $nameNode.InnerText } else { "" }
            if ($k -and $best.Map.ContainsKey($k)) {
                # Guard: skip the copy if source and target disagree on whether
                # this slot is a joystick direction vs an action button. Some
                # game profiles reuse the same InputMapping enum value (e.g.
                # P1ButtonUp, P1Button1) for completely different physical
                # controls across titles. Example: P1ButtonUp is the Up
                # direction in SF3 but "Left Punch" in Tekken 6; P1Button1 is
                # LP in SF3 but the UP direction in Rampage. Copying across
                # that semantic boundary bakes in wrong, non-fixable bindings
                # (the profile then counts as REFERENCE and is never revisited).
                # Test-ButtonNameDirectional classifies a slot as directional
                # only when its label, after stripping the player-number prefix,
                # consists exclusively of direction words. A mismatch (one side
                # directional, other side not) is treated as manual. See #17.
                $srcNameNode = $best.Map[$k].SelectSingleNode("ButtonName")
                $srcName = if ($srcNameNode) { $srcNameNode.InnerText } else { "" }
                if ((Test-ButtonNameDirectional $srcName) -ne (Test-ButtonNameDirectional $btnName)) {
                    if ($btnName) { [void]$manual.Add($btnName) }
                    continue
                }
                # Clone the archetype's whole bound node (preserving the exact
                # element order TeknoParrot writes), then restore THIS game's
                # own display name. The clone carries the real device + key.
                $imported = $doc.ImportNode($best.Map[$k], $true)
                $impName  = $imported.SelectSingleNode("ButtonName")
                if ($impName -and $nameNode) { $impName.InnerText = $btnName }
                [void]$b.ParentNode.ReplaceChild($imported, $b)
                $boundNow++
            } elseif ($btnName) {
                [void]$manual.Add($btnName)
            }
        }

        $apiSet = $false
        if ($best.InputApi) { $apiSet = Set-ProfileInputApi $doc $best.InputApi }

        # Carry input-behaviour config (aim mode, sensitivity, axis handling)
        # from the archetype, but only fields this target also defines.
        $cfgCarried = New-Object System.Collections.ArrayList
        foreach ($cf in $best.ConfigCarry.Keys) {
            if (Set-ConfigField $doc $cf $best.ConfigCarry[$cf]) { [void]$cfgCarried.Add($cf) }
        }

        try {
            Save-XmlMaybe $doc $f.FullName $DryRun
            [void]$reports.Add([pscustomobject]@{
                Code = $f.BaseName; Status = "bound"; Family = $targetFamily
                Archetype = $best.Code; ArchetypeApi = $best.InputApi; ApiSet = $apiSet
                Bound = $boundNow; Manual = $manual; ConfigCarried = $cfgCarried; Forced = $forced
            })
            Write-Log "Propagated $($f.BaseName): family=$targetFamily src=$($best.Code) bound=$boundNow api=$($best.InputApi)/set=$apiSet config=$($cfgCarried -join ';')"
        } catch {
            Write-Log "Propagation: FAILED to save $($f.Name) -- $_"
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "save-failed"; Archetype = $best.Code })
        }
    }
    return $reports
}

# Asks the user which control devices they have and want to use, then prints a
# tailored plan of which game to bind with which device. This is guidance
# only: it reads no files and changes nothing. The actual copying happens
# later, after the user binds those games and re-runs.
function Invoke-DeviceSurvey {

    # Scriptblock instead of a nested function: PowerShell nested functions
    # escape into session scope after the first call, polluting the environment
    # for the rest of the session. A scriptblock stays local to this function.
    $readYesNo = { param([string]$q) return ((Read-Host "   $q (Y/N)").Trim().ToUpper() -eq "Y") }

    Write-Host ""
    Write-Host " Which controls do you have and want to use?" -ForegroundColor Cyan
    Write-Host " (Answer Y or N. This only prints a plan; it changes nothing.)" -ForegroundColor DarkCyan
    Write-Host ""

    $hasXbox      = & $readYesNo "Xbox / XInput controller?"
    $hasArcade    = & $readYesNo "Arcade joystick + buttons?"
    $hasTrackball = & $readYesNo "Trackball?"
    $hasSpinner   = & $readYesNo "Spinner (single-axis dial)?"
    $hasWheel     = & $readYesNo "Steering wheel + pedals?"
    $hasGun       = & $readYesNo "Lightgun?"
    $hasKeyboard  = & $readYesNo "Keyboard (no game controller)?"

    # Resolve one device per game family from what the user has, preferring the
    # purpose-built control and falling back to the most versatile available.
    $plan = [ordered]@{}

    if ($hasTrackball) { $plan["Trackball games (Golden Tee, Silver Strike)"] = "your trackball" }

    if     ($hasArcade)   { $plan["Fighting / classic arcade"] = "your arcade stick + buttons" }
    elseif ($hasXbox)     { $plan["Fighting / classic arcade"] = "your Xbox pad" }
    elseif ($hasKeyboard) { $plan["Fighting / classic arcade"] = "your keyboard" }

    if     ($hasWheel)   { $plan["Driving games"] = "your wheel + pedals" }
    elseif ($hasXbox)    { $plan["Driving games"] = "your Xbox pad (analog steering, triggers, gears)" }
    elseif ($hasSpinner) { $plan["Driving games"] = "your spinner for steering, buttons for gas/brake" }

    if ($hasGun) {
        $plan["Lightgun games"] = "your lightgun"
    } else {
        # No gun: trackball (relative/mouse aim) is the suggested fallback, with
        # the Xbox right stick as the alternative. Ask only if both are present.
        if ($hasTrackball -and $hasXbox) {
            Write-Host ""
            Write-Host "   No lightgun. For gun games, aim with:" -ForegroundColor Yellow
            Write-Host "     1) Trackball       (precise, but no fixed center; you roll to aim)"
            Write-Host "     2) Xbox right stick (smooth and self-centering)"
            if ((Read-Host "   Choose 1 or 2").Trim() -eq "2") {
                $plan["Lightgun games (no gun)"] = "your Xbox right stick (analog aim)"
            } else {
                $plan["Lightgun games (no gun)"] = "your trackball (relative/mouse aim)"
            }
        }
        elseif ($hasTrackball) { $plan["Lightgun games (no gun)"] = "your trackball (relative/mouse aim)" }
        elseif ($hasXbox)      { $plan["Lightgun games (no gun)"] = "your Xbox right stick (analog aim)" }
    }

    if     ($hasXbox)     { $plan["All other games"] = "your Xbox pad" }
    elseif ($hasArcade)   { $plan["All other games"] = "your arcade stick + buttons" }
    elseif ($hasKeyboard) { $plan["All other games"] = "your keyboard" }

    Write-Host ""
    Write-Host " ----------------------------------------------------------" -ForegroundColor Cyan
    Write-Host " YOUR BINDING PLAN" -ForegroundColor Cyan
    Write-Host " ----------------------------------------------------------" -ForegroundColor Cyan
    if ($plan.Count -eq 0) {
        Write-Host "  No devices selected -- nothing to plan." -ForegroundColor Yellow
        Write-Log "Device survey: no devices selected."
        return
    }
    Write-Host " In TeknoParrotUi.exe, bind ONE game of each type below using the"
    Write-Host " device shown, then re-run this script and choose Propagate:"
    Write-Host ""
    foreach ($k in $plan.Keys) {
        Write-Host ("   - {0}" -f $k) -ForegroundColor Green
        Write-Host ("       bind with: {0}" -f $plan[$k]) -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host " Bind each one completely, including Test, Service, Coin, Start." -ForegroundColor DarkCyan
    if (-not $hasGun -and (@($plan.Keys) -match "Lightgun")) {
        Write-Host ""
        Write-Host " Gun games without a gun aim with mouse/cursor or stick input." -ForegroundColor Yellow
        Write-Host " Propagation now also carries the aim-mode settings (relative" -ForegroundColor Yellow
        Write-Host " input, sensitivity, hide-cursor) between gun games, so they" -ForegroundColor Yellow
        Write-Host " match your bound game's settings. If one still aims oddly, check that" -ForegroundColor Yellow
        Write-Host " game's own settings in the TeknoParrot UI." -ForegroundColor Yellow
    }
    Write-Log "Device survey: plan=$($plan.Count) items; xbox=$hasXbox arcade=$hasArcade trackball=$hasTrackball spinner=$hasSpinner wheel=$hasWheel gun=$hasGun keyboard=$hasKeyboard"
}

# =============================================================================
# RESTORE FROM BACKUP
# =============================================================================
# Lists all timestamped backups in UserProfiles\FullBackup, lets the user pick
# one, confirms, then copies it back to UserProfiles -- overwriting current files.
# The FullBackup subfolder itself is never touched during the restore.
function Invoke-RestoreBackup {
    param([string]$userProfilesDir)

    $backupRoot = Join-Path $userProfilesDir "FullBackup"
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        Write-Host "  No backups found in: $backupRoot" -ForegroundColor Yellow
        return
    }

    $backups = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
                     Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        Write-Host "  No backup folders found." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Available backups (most recent first):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b         = $backups[$i]
        $fileCount = (Get-ChildItem -LiteralPath $b.FullName -File -ErrorAction SilentlyContinue).Count
        Write-Host ("    {0,3})  {1}   ({2} file(s))" -f ($i + 1), $b.Name, $fileCount)
    }
    Write-Host ""
    $choice = (Read-Host "  Enter number to restore, or Enter to cancel").Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-Host "  Restore cancelled." -ForegroundColor DarkGray
        Write-Log "Restore: cancelled by user."
        return
    }
    if ($choice -notmatch '^\d+$' -or $choice.Length -gt 9 -or [int]$choice -lt 1 -or [int]$choice -gt $backups.Count) {
        Write-Host "  Invalid selection. Restore cancelled." -ForegroundColor Yellow
        Write-Log "Restore: invalid selection '$choice'."
        return
    }
    $selected = $backups[[int]$choice - 1]

    $backupXmls = @(Get-ChildItem -LiteralPath $selected.FullName -Filter "*.xml" -File `
                        -ErrorAction SilentlyContinue)
    if ($backupXmls.Count -eq 0) {
        Write-Host ("  ERROR: Selected backup '{0}' contains no XML profiles -- restore aborted." -f $selected.Name) -ForegroundColor Red
        Write-Log "Restore: aborted -- backup '$($selected.Name)' contains no XML files."
        return
    }

    Write-Host ""
    Write-Host ("  Selected : {0}  ({1} profile(s))" -f $selected.Name, $backupXmls.Count) -ForegroundColor Yellow
    Write-Host "  WARNING  : This will OVERWRITE all current UserProfiles with the backup." -ForegroundColor Yellow
    $confirm = (Read-Host "  Type YES to confirm").Trim()
    if ($confirm.ToUpper() -ne "YES") {
        Write-Host "  Restore cancelled." -ForegroundColor DarkGray
        Write-Log "Restore: user did not confirm."
        return
    }

    # TeknoParrot must be fully closed before files can be safely replaced.
    # If it is running, profile files it has open cannot be deleted, which
    # would leave the UserProfiles directory in a mixed old/new state.
    $tpProcess = Get-Process -Name "TeknoParrotUi" -ErrorAction SilentlyContinue
    if ($tpProcess) {
        Write-Host "  ERROR: TeknoParrotUi.exe is currently running." -ForegroundColor Red
        Write-Host "  Close TeknoParrot completely and then re-run the restore." -ForegroundColor Yellow
        Write-Log "Restore: aborted -- TeknoParrotUi.exe is running."
        return
    }

    # Remove current UserProfiles content, keeping FullBackup intact.
    # Use Where-Object instead of -Exclude for reliable PS 5.1 behaviour.
    # Treat any deletion failures as fatal: a partial delete followed by a
    # partial copy would leave UserProfiles in an undefined mixed state.
    $deleteErrs = @()
    # Remove-Item receives FileInfo/DirectoryInfo objects from the pipeline
    # (not path strings), so pipeline binding already bypasses wildcard
    # expansion -- safe even with [, ], $ in game folder names. If this
    # source is ever changed to raw path strings, add -LiteralPath there.
    Get-ChildItem -LiteralPath $userProfilesDir | Where-Object { $_.Name -ne "FullBackup" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable deleteErrs
    if ($deleteErrs.Count -gt 0) {
        Write-Host ("  ERROR: {0} file(s) could not be removed." -f $deleteErrs.Count) -ForegroundColor Red
        Write-Host "  Make sure TeknoParrot is fully closed and no files are open, then try again." -ForegroundColor Yellow
        Write-Log "Restore: FAILED -- $($deleteErrs.Count) file(s) could not be removed."
        return
    }

    # Copy backup into UserProfiles. Copy-Item receives FileInfo/DirectoryInfo
    # objects from the pipeline (not path strings), so pipeline binding
    # already bypasses wildcard expansion -- safe even with [, ], $ in game
    # folder names. If this source is ever changed to raw path strings, add
    # -LiteralPath there.
    $restoreErrs = @()
    Get-ChildItem -LiteralPath $selected.FullName |
        Copy-Item -Destination $userProfilesDir -Recurse -Force `
                  -ErrorAction SilentlyContinue -ErrorVariable restoreErrs
    $errCount = $restoreErrs.Count

    if ($errCount -gt 0) {
        Write-Host ("  WARNING: {0} file(s) could not be restored -- check TeknoParrot-Manager.log." -f $errCount) -ForegroundColor Yellow
        Write-Log "Restore: completed with $errCount error(s) from $($selected.Name)"
    } else {
        Write-Host "  Restore complete." -ForegroundColor Green
        Write-Log "Restore: completed from $($selected.Name), no errors."
    }
}

# =============================================================================
# LAUNCHBOX XML EXPORT  (standalone file only -- no direct LaunchBox writes)
# =============================================================================
# Reads every UserProfile that has a valid GamePath and builds a LaunchBox-
# compatible XML file the user can inspect and import manually. Writing
# directly to LaunchBox's Arcade.xml is intentionally not done here: LaunchBox
# must be fully closed before its database files are modified externally, its
# XML schema can vary between versions, and game entries must be associated with
# a specific internal emulator ID that only LaunchBox itself can assign safely.
# Manual import takes about 30 seconds and avoids every one of those risks.
#
# Returns the count of games written, or -1 on a fatal write error.
#
# NOTE: <ApplicationPath> below is deliberately the GameProfile XML's own
# path relative to the LaunchBox root, NOT the game's executable. This was
# confirmed against a real, working LaunchBox installation's live
# Data\Platforms\TeknoParrot.xml: LaunchBox's TeknoParrot emulator entry
# uses CommandLine "--profile=%romfile%.xml" with FileNameWithoutExtensionAndPath
# enabled, so the "rom" LaunchBox launches against IS the profile XML --
# %romfile% resolves to the bare profile filename, and the literal ".xml"
# is appended by the emulator's own command-line template.
function Export-LaunchBoxXml {
    param([string]$userProfilesDir, [string]$lbRoot, [string]$outputPath)

    $files = Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Directory.Name -ne "FullBackup" }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<?xml version="1.0" encoding="utf-8"?>')
    [void]$sb.AppendLine('<LaunchBox>')

    $count = 0
    foreach ($f in $files) {
        try {
            $doc = Read-Xml $f.FullName
            if ($null -eq $doc.GameProfile) { continue }

            $gpNode   = $doc.GameProfile.SelectSingleNode("GamePath")
            $gamePath = if ($gpNode) { $gpNode.InnerText } else { "" }
            if (-not $gamePath -or -not (Test-Path -LiteralPath $gamePath)) { continue }

            # Friendly title: try the Description field; fall back to
            # CamelCase-split profile code ("AkaiKatanaShinNesica" -> "Akai Katana Shin Nesica")
            $descNode = $doc.GameProfile.SelectSingleNode("Description")
            if ($descNode -and -not [string]::IsNullOrWhiteSpace($descNode.InnerText)) {
                $title = $descNode.InnerText.Trim()
            } else {
                $title = [regex]::Replace($f.BaseName, '(?<=[a-z])(?=[A-Z])', ' ')
            }

            $appPath = if ($lbRoot) { Get-RelativePath $lbRoot $f.FullName } else { $f.FullName }

            $esc = [System.Security.SecurityElement]
            [void]$sb.AppendLine('  <Game>')
            [void]$sb.AppendLine("    <Title>$($esc::Escape($title))</Title>")
            [void]$sb.AppendLine("    <Platform>Arcade</Platform>")
            [void]$sb.AppendLine("    <ApplicationPath>$($esc::Escape($appPath))</ApplicationPath>")
            [void]$sb.AppendLine("    <CommandLine />")
            [void]$sb.AppendLine("    <RomPath>$($esc::Escape($gamePath))</RomPath>")
            [void]$sb.AppendLine("    <Favorite>false</Favorite>")
            [void]$sb.AppendLine("    <Completed>false</Completed>")
            [void]$sb.AppendLine("    <Hidden>false</Hidden>")
            [void]$sb.AppendLine("    <Enabled>true</Enabled>")
            [void]$sb.AppendLine("    <Notes>Exported by TeknoParrot Manager</Notes>")
            [void]$sb.AppendLine('  </Game>')
            $count++
        } catch {
            Write-Log "LaunchBox export: skipped $($f.Name) -- $_"
        }
    }

    [void]$sb.AppendLine('</LaunchBox>')

    try {
        [System.IO.File]::WriteAllText($outputPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
        return $count
    } catch {
        Write-Log "LaunchBox export: FAILED to write file -- $_"
        return -1
    }
}

# =============================================================================
# LAUNCHBOX DIRECT INTEGRATION  (writes straight into LaunchBox's Data\ files)
# =============================================================================
# Real-world schema below (Emulator/Platform/Game field names and values) was
# captured from a working LaunchBox installation's live Data\Emulators.xml and
# Data\Platforms\TeknoParrot.xml -- not guessed. Confirmed via a LaunchBox
# forum admin post that TeknoParrot's profile structure is not understood by
# LaunchBox's own auto-import, which is why ScrapeAs=Arcade and
# DisableAutoImport=true matter for any platform this script creates.

# Strips characters that are invalid in a Windows filename from a
# user-typed custom platform name, since the name doubles as the
# Data\Platforms\<name>.xml filename. Falls back to "TeknoParrot" if
# nothing valid remains.
function Get-SafeLaunchBoxPlatformFileName {
    param([string]$platformName)
    $clean = [regex]::Replace($platformName, '[\\/:*?"<>|]', '').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = "TeknoParrot" }
    return $clean
}

# Backs up only the specific Data\ files about to be modified -- never the
# whole Data\ folder, since some platform files (Arcade.xml) run 20+ MB and
# copying everything on every run would be slow for no benefit. Files are
# copied into Scripts\LaunchBoxBackups\<timestamp>\ preserving their path
# relative to the LaunchBox root, so a restore is a straight copy back
# (see Invoke-RestoreLaunchBoxBackup). Returns the backup folder path, or
# $null on failure -- writing to LaunchBox's live files without a
# successful backup first is never acceptable.
function Backup-LaunchBoxFiles {
    param([string]$lbRoot, [string[]]$relativeFiles)

    $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path (Join-Path $PSScriptRoot "LaunchBoxBackups") $timestamp

    try {
        foreach ($rel in $relativeFiles) {
            $srcFull = Join-Path $lbRoot $rel
            if (-not (Test-Path -LiteralPath $srcFull)) { continue }   # nothing to back up yet (new platform file)
            $dstFull = Join-Path $backupPath $rel
            if (-not (Test-PathInside $dstFull $backupPath)) {
                Write-Log "LaunchBox backup: FAILED -- '$rel' would escape the backup folder"
                return $null
            }
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $dstFull))
            Copy-Item -LiteralPath $srcFull -Destination $dstFull -Force
        }
    } catch {
        Write-Log "LaunchBox backup: FAILED -- $_"
        return $null
    }
    Write-Log "LaunchBox backup: saved to $backupPath"
    return $backupPath
}

# Restores a previous LaunchBox backup by copying each backed-up file back
# to its original relative location under the LaunchBox root. Mirrors
# Invoke-RestoreBackup's UX (list by timestamp, confirm with YES, refuse
# while the target app is running) so both restore flows feel like the
# same feature.
function Invoke-RestoreLaunchBoxBackup {
    param([string]$lbRoot)

    $backupRoot = Join-Path $PSScriptRoot "LaunchBoxBackups"
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        Write-Host "  No LaunchBox backups found in: $backupRoot" -ForegroundColor Yellow
        return
    }

    $backups = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        Write-Host "  No LaunchBox backup folders found." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Available LaunchBox backups (most recent first):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b         = $backups[$i]
        $fileCount = (Get-ChildItem -LiteralPath $b.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host ("    {0,3})  {1}   ({2} file(s))" -f ($i + 1), $b.Name, $fileCount)
    }
    Write-Host ""
    $choice = (Read-Host "  Enter number to restore, or Enter to cancel").Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-Host "  Restore cancelled." -ForegroundColor DarkGray
        Write-Log "LaunchBox restore: cancelled by user."
        return
    }
    if ($choice -notmatch '^\d+$' -or $choice.Length -gt 9 -or [int]$choice -lt 1 -or [int]$choice -gt $backups.Count) {
        Write-Host "  Invalid selection. Restore cancelled." -ForegroundColor Yellow
        Write-Log "LaunchBox restore: invalid selection '$choice'."
        return
    }
    $selected = $backups[[int]$choice - 1]

    Write-Host ""
    Write-Host ("  Selected : {0}" -f $selected.Name) -ForegroundColor Yellow
    Write-Host "  WARNING  : This will OVERWRITE the current LaunchBox Emulators.xml," -ForegroundColor Yellow
    Write-Host "             Platforms.xml, and any platform file(s) in this backup." -ForegroundColor Yellow
    $confirm = (Read-Host "  Type YES to confirm").Trim()
    if ($confirm.ToUpper() -ne "YES") {
        Write-Host "  Restore cancelled." -ForegroundColor DarkGray
        Write-Log "LaunchBox restore: user did not confirm."
        return
    }

    if (Test-LaunchBoxRunning) {
        Write-Host "  ERROR: LaunchBox or BigBox is currently running." -ForegroundColor Red
        Write-Host "  Close it completely and then re-run the restore." -ForegroundColor Yellow
        Write-Log "LaunchBox restore: aborted -- LaunchBox/BigBox is running."
        return
    }

    $backupFiles = @(Get-ChildItem -LiteralPath $selected.FullName -Recurse -File -ErrorAction SilentlyContinue)
    $errCount = 0
    foreach ($bf in $backupFiles) {
        try {
            $rel = Get-RelativePath $selected.FullName $bf.FullName
            $dst = Join-Path $lbRoot $rel
            if (-not (Test-PathInside $dst $lbRoot)) { $errCount++; continue }
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $dst))
            Copy-Item -LiteralPath $bf.FullName -Destination $dst -Force
        } catch {
            $errCount++
            Write-Log "LaunchBox restore: failed to restore $($bf.FullName) -- $_"
        }
    }

    if ($errCount -gt 0) {
        Write-Host ("  WARNING: {0} file(s) could not be restored -- check TeknoParrot-Manager.log." -f $errCount) -ForegroundColor Yellow
        Write-Log "LaunchBox restore: completed with $errCount error(s) from $($selected.Name)"
    } else {
        Write-Host "  Restore complete." -ForegroundColor Green
        Write-Log "LaunchBox restore: completed from $($selected.Name), no errors."
    }
}

# Finds the existing TeknoParrot <Emulator> entry in Emulators.xml by
# Title (so re-runs, and machines that already configured this by hand,
# Returns the InnerText of a named child element, or "" if the child is
# absent -- guards against malformed/legacy LaunchBox XML entries that may
# be missing a field this script expects, rather than crashing the whole
# run on one unexpected node.
function Get-XmlChildText {
    param([System.Xml.XmlNode]$node, [string]$childName)
    $child = $node.SelectSingleNode($childName)
    if ($null -eq $child) { return "" }
    return $child.InnerText
}

# Sets a child element's text, creating the child first if it is
# unexpectedly missing (e.g. a cloned template from an older LaunchBox
# schema) -- a live write to LaunchBox's own database should never crash
# over one missing field.
function Set-XmlChildText {
    param([System.Xml.XmlNode]$node, [string]$childName, [string]$value)
    $child = $node.SelectSingleNode($childName)
    if ($null -eq $child) {
        $child = $node.OwnerDocument.CreateElement($childName)
        [void]$node.AppendChild($child)
    }
    $child.InnerText = $value
}

# =============================================================================
# POSTGRESQL DATABASE BACKUP/RESTORE
# =============================================================================

# Backs up every Postgres database belonging to a registered, Postgres-
# needing game that currently exists, into
# Scripts\PostgresBackups\<timestamp>\<dbname>.backup (pg_dump custom
# format, matching what pg_restore expects). Runs unconditionally at the
# start of the Postgres setup mode, before any install/create/restore work
# -- same "always back up first, regardless of whether this run changes
# anything" convention already used at the start of every AutoSync/
# Register run. Skipped (logged, not an error) if PostgreSQL isn't
# installed yet or no Postgres databases exist -- nothing to back up on a
# first run. Returns the backup folder path, or $null if nothing was
# backed up.
function Backup-PostgresDatabases {
    param([string]$UserProfilesDir, [string]$SuperPasswordPlain)

    if (-not (Test-PostgresInstalled)) { return $null }

    $dbNames = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $profiles = Get-ChildItem -LiteralPath $UserProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Directory.Name -ne "FullBackup" }
    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            if (-not $doc.GameProfile) { continue }
            if (-not (Test-GameNeedsPostgres $doc)) { continue }
            $dbName = Get-PostgresFieldValue $doc "DbName"
            if (-not [string]::IsNullOrWhiteSpace($dbName) -and (Test-SafePostgresDbName $dbName)) {
                if (Test-PostgresDatabaseExists -DbName $dbName -SuperPasswordPlain $SuperPasswordPlain) {
                    [void]$dbNames.Add($dbName)
                }
            }
        } catch {
            Write-Log "Postgres backup: could not check $($pf.Name) -- $_"
        }
    }

    if ($dbNames.Count -eq 0) {
        Write-Log "Postgres backup: no existing databases to back up."
        return $null
    }

    $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path (Join-Path $PSScriptRoot "PostgresBackups") $timestamp
    [void][System.IO.Directory]::CreateDirectory($backupPath)

    $pgDumpExe = Join-Path $script:PostgresBinDir "pg_dump.exe"
    $pgpassFile = New-PostgresPgPassFile -Password $SuperPasswordPlain
    $env:PGPASSFILE = $pgpassFile
    try {
        foreach ($dbName in $dbNames) {
            $destFile = Join-Path $backupPath "$dbName.backup"
            & $pgDumpExe -U postgres -h 127.0.0.1 -p 5432 -F c -f $destFile $dbName 2>&1 | Out-Null
            if (Test-Path -LiteralPath $destFile) {
                Write-Log "Postgres backup: dumped $dbName -> $destFile"
            } else {
                Write-Log "Postgres backup: FAILED to dump $dbName"
            }
        }
    } finally {
        $env:PGPASSFILE = $null
        Remove-PostgresPgPassFile -Path $pgpassFile
    }

    return $backupPath
}

# Restores a previous Postgres database backup. Mirrors
# Invoke-RestoreLaunchBoxBackup's UX (list by timestamp, confirm with YES)
# so all three restore flows under menu 9 feel like the same feature.
# Necessarily destructive to each restored database's CURRENT content --
# warned clearly before proceeding. Requires PostgreSQL to already be
# installed and running (it always will be if there's anything to
# restore).
function Invoke-RestorePostgresBackup {
    $backupRoot = Join-Path $PSScriptRoot "PostgresBackups"
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        Write-Host "  No Postgres database backups found in: $backupRoot" -ForegroundColor Yellow
        return
    }

    $backups = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($backups.Count -eq 0) {
        Write-Host "  No Postgres backup folders found." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "  Available Postgres database backups (most recent first):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $backups.Count; $i++) {
        $b = $backups[$i]
        $dbFiles = @(Get-ChildItem -LiteralPath $b.FullName -Filter "*.backup" -File -ErrorAction SilentlyContinue)
        $names = ($dbFiles | ForEach-Object { $_.BaseName }) -join ', '
        Write-Host ("    {0,3})  {1}   ({2} database(s): {3})" -f ($i + 1), $b.Name, $dbFiles.Count, $names)
    }
    Write-Host ""
    $choice = (Read-Host "  Enter number to restore, or Enter to cancel").Trim()
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-Host "  Restore cancelled." -ForegroundColor DarkGray
        Write-Log "Postgres restore: cancelled by user."
        return
    }
    if ($choice -notmatch '^\d+$' -or $choice.Length -gt 9 -or [int]$choice -lt 1 -or [int]$choice -gt $backups.Count) {
        Write-Host "  Invalid selection. Restore cancelled." -ForegroundColor Yellow
        Write-Log "Postgres restore: invalid selection '$choice'."
        return
    }
    $selected = $backups[[int]$choice - 1]
    $backupFiles = @(Get-ChildItem -LiteralPath $selected.FullName -Filter "*.backup" -File -ErrorAction SilentlyContinue)
    if ($backupFiles.Count -eq 0) {
        Write-Host "  ERROR: Selected backup contains no .backup files -- restore aborted." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host ("  Selected : {0}  ({1} database(s))" -f $selected.Name, $backupFiles.Count) -ForegroundColor Yellow
    Write-Host "  WARNING  : This will REPLACE the current content of each database" -ForegroundColor Yellow
    Write-Host "             listed above with this backup's snapshot." -ForegroundColor Yellow
    $confirm = (Read-Host "  Type YES to confirm").Trim()
    if ($confirm.ToUpper() -ne "YES") {
        Write-Host "  Restore cancelled." -ForegroundColor DarkGray
        Write-Log "Postgres restore: user did not confirm."
        return
    }

    if (-not (Test-PostgresInstalled)) {
        Write-Host "  ERROR: PostgreSQL is not installed -- nothing to restore into." -ForegroundColor Red
        Write-Log "Postgres restore: aborted -- PostgreSQL not installed."
        return
    }

    $superPwPlain = $null
    if ($postgresSuperPasswordEncrypted) {
        try {
            $secure = ConvertTo-SecureString -String $postgresSuperPasswordEncrypted
            $savedPwPlain = ConvertFrom-SecureStringPlain $secure
            if (Test-PostgresPassword $savedPwPlain) { $superPwPlain = $savedPwPlain }
        } catch {
            Write-Log "Postgres restore: could not decrypt saved password -- $_"
        }
    }
    if (-not $superPwPlain) {
        $superPwSecure = Read-Host "  Enter your PostgreSQL database password" -AsSecureString
        $typedPwPlain  = ConvertFrom-SecureStringPlain $superPwSecure
        if (-not (Test-PostgresPassword $typedPwPlain)) {
            Write-Host "  ERROR: That password did not work against your PostgreSQL server." -ForegroundColor Red
            Write-Log "Postgres restore: aborted -- password verification failed."
            return
        }
        $superPwPlain = $typedPwPlain
    }

    $dropdbExe = Join-Path $script:PostgresBinDir "dropdb.exe"
    $errCount = 0
    try {
        foreach ($bf in $backupFiles) {
            $dbName = $bf.BaseName
            if (-not (Test-SafePostgresDbName $dbName)) { $errCount++; continue }
            $pgpassFile = New-PostgresPgPassFile -Password $superPwPlain
            $env:PGPASSFILE = $pgpassFile
            try {
                & $dropdbExe -U postgres -h 127.0.0.1 -p 5432 --if-exists $dbName 2>&1 | Out-Null
            } finally {
                $env:PGPASSFILE = $null
                Remove-PostgresPgPassFile -Path $pgpassFile
            }
            $encoding = if ($dbName -eq 'GameDB06') { 'UTF8' } else { 'SQL_ASCII' }
            if (New-PostgresDatabaseFromBackup -DbName $dbName -Encoding $encoding -BackupFile $bf.FullName -SuperPasswordPlain $superPwPlain) {
                Write-Host ("    Restored: {0}" -f $dbName) -ForegroundColor Green
                Write-Log "Postgres restore: restored $dbName from $($bf.FullName)"
            } else {
                Write-Host ("    FAILED  : {0}" -f $dbName) -ForegroundColor Red
                Write-Log "Postgres restore: FAILED to restore $dbName"
                $errCount++
            }
        }
    } finally {
        $superPwPlain = $null
    }

    if ($errCount -gt 0) {
        Write-Host ("  WARNING: {0} database(s) could not be restored -- check TeknoParrot-Manager.log." -f $errCount) -ForegroundColor Yellow
    } else {
        Write-Host "  Restore complete." -ForegroundColor Green
    }
}

# never get a duplicate), or creates one using field values verified
# against a real, working LaunchBox installation. $emulatorsDoc is modified
# in place but not saved -- the caller saves once after all changes for
# this run are made. Returns the Emulator's ID (GUID string).
function Get-OrCreateLaunchBoxEmulator {
    param([System.Xml.XmlDocument]$emulatorsDoc, [string]$tpRoot, [string]$lbRoot)

    $emulatorNodes = @($emulatorsDoc.SelectNodes("/LaunchBox/Emulator"))
    $existing = $emulatorNodes | Where-Object { (Get-XmlChildText $_ "Title") -eq "TeknoParrot" } | Select-Object -First 1
    if ($existing) {
        $existingId = Get-XmlChildText $existing "ID"
        if ($existingId) { return $existingId }
        # Matched by title but missing an ID -- treat as malformed and fall
        # through to creating a fresh, well-formed entry instead of
        # returning an empty emulator ID that would break every downstream
        # Game/EmulatorPlatform link.
    }

    $relAppPath = Get-RelativePath $lbRoot (Join-Path $tpRoot "TeknoParrotUi.exe")
    $newId = [guid]::NewGuid().ToString()

    $fields = [ordered]@{
        ApplicationPath                      = $relAppPath
        CommandLine                          = "--profile=%romfile%.xml"
        DefaultPlatform                      = ""
        ID                                   = $newId
        Title                                = "TeknoParrot"
        NoQuotes                             = "true"
        NoSpace                              = "true"
        HideConsole                          = "true"
        FileNameWithoutExtensionAndPath      = "true"
        AutoHotkeyScript                     = ""
        AutoExtract                          = "false"
        UseStartupScreen                     = "true"
        HideAllNonExclusiveFullscreenWindows = "false"
        StartupLoadDelay                     = "25000"
        HideMouseCursorInGame                = "true"
        DisableShutdownScreen                = "false"
        AggressiveWindowHiding                = "false"
        UsePauseScreen                       = "false"
        PauseAutoHotkeyScript                = ""
        ResumeAutoHotkeyScript               = ""
        DefaultPauseSettingsPushed           = "true"
        SuspendProcessOnPause                = "true"
        ForcefulPauseScreenActivation        = "true"
        LoadStateAutoHotkeyScript            = ""
        SaveStateAutoHotkeyScript            = ""
        ResetAutoHotkeyScript                = ""
        SwapDiscsAutoHotkeyScript            = ""
        ExitAutoHotkeyScript                 = ""
        SkipVersionCheck                     = "false"
        LoginToCheevoOnGameLaunch            = "true"
        EnableHardcoreAchievements           = "true"
    }

    $emulatorNode = $emulatorsDoc.CreateElement("Emulator")
    foreach ($key in $fields.Keys) {
        $child = $emulatorsDoc.CreateElement($key)
        $child.InnerText = $fields[$key]
        [void]$emulatorNode.AppendChild($child)
    }
    [void]$emulatorsDoc.DocumentElement.AppendChild($emulatorNode)
    Write-Log "LaunchBox: created new Emulator entry for TeknoParrot (ID=$newId)"
    return $newId
}

# Finds an existing <Platform> definition in Platforms.xml by name (Arcade
# always exists already; "TeknoParrot" or a custom name might not), or
# creates a minimal one. ScrapeAs=Arcade and DisableAutoImport=true are not
# arbitrary -- TeknoParrot is not a real platform as far as LaunchBox's own
# auto-import is concerned (confirmed via a LaunchBox forum admin post:
# "the platform is Arcade ... TeknoParrot ... won't work via the
# auto-import system right now ... a limitation by design"), so any
# platform this script manages must scrape as Arcade and stay excluded
# from LaunchBox's own auto-import sweeps. No other metadata (notes,
# release date, BigBox theme, etc.) is fabricated -- left blank for the
# user to fill in via LaunchBox's own platform editor if they want to.
# Returns $true if a new platform was created, $false if one already existed.
function Get-OrCreateLaunchBoxPlatform {
    param([System.Xml.XmlDocument]$platformsListDoc, [string]$platformName, [string]$tpRoot, [string]$lbRoot)

    $platformNodes = @($platformsListDoc.SelectNodes("/LaunchBox/Platform"))
    $existing = $platformNodes | Where-Object { (Get-XmlChildText $_ "Name") -eq $platformName } | Select-Object -First 1
    if ($existing) { return $false }

    $relFolder = Get-RelativePath $lbRoot (Join-Path $tpRoot "GameProfiles")

    $fields = [ordered]@{
        Category                = ""
        LocalDbParsed           = "true"
        Name                    = $platformName
        LastSelectedChild       = ""
        ReleaseDate             = ""
        Developer               = ""
        Manufacturer            = ""
        Cpu                     = ""
        Memory                  = ""
        Graphics                = ""
        Sound                   = ""
        Display                 = ""
        Media                   = ""
        MaxControllers          = ""
        Folder                  = $relFolder
        Notes                   = ""
        VideosFolder            = ""
        FrontImagesFolder       = ""
        BackImagesFolder        = ""
        ClearLogoImagesFolder   = ""
        FanartImagesFolder      = ""
        ScreenshotImagesFolder  = ""
        BannerImagesFolder      = ""
        SteamBannerImagesFolder = ""
        ManualsFolder           = ""
        MusicFolder             = ""
        ScrapeAs                = "Arcade"
        VideoPath               = ""
        ImageType               = ""
        SortTitle                = ""
        LastGameId              = ""
        BigBoxView              = ""
        BigBoxTheme             = ""
        AndroidThemeVideoPath   = ""
        HideInBigBox            = "false"
        DisableAutoImport       = "true"
    }

    $platformNode = $platformsListDoc.CreateElement("Platform")
    foreach ($key in $fields.Keys) {
        $child = $platformsListDoc.CreateElement($key)
        $child.InnerText = $fields[$key]
        [void]$platformNode.AppendChild($child)
    }
    [void]$platformsListDoc.DocumentElement.AppendChild($platformNode)
    Write-Log "LaunchBox: created new Platform '$platformName'"
    return $true
}

# Ensures an <EmulatorPlatform> link exists between the TeknoParrot
# emulator and a platform. $isNewPlatform controls Default -- true only
# when the platform itself was just created (nothing else could already
# depend on its default emulator); false when linking into an existing
# platform like Arcade, so an existing default emulator there is never
# silently overridden.
function Add-LaunchBoxEmulatorPlatformLink {
    param([System.Xml.XmlDocument]$emulatorsDoc, [string]$emulatorId, [string]$platformName, [bool]$isNewPlatform)

    $linkNodes = @($emulatorsDoc.SelectNodes("/LaunchBox/EmulatorPlatform"))
    $existing = $linkNodes | Where-Object {
        (Get-XmlChildText $_ "Emulator") -eq $emulatorId -and
        (Get-XmlChildText $_ "Platform") -eq $platformName
    } | Select-Object -First 1
    if ($existing) { return }

    $fields = [ordered]@{
        Emulator           = $emulatorId
        Platform           = $platformName
        CommandLine        = ""
        Default            = if ($isNewPlatform) { "true" } else { "false" }
        M3uDiscLoadEnabled = "false"
        AutoExtract        = "false"
    }
    $linkNode = $emulatorsDoc.CreateElement("EmulatorPlatform")
    foreach ($key in $fields.Keys) {
        $child = $emulatorsDoc.CreateElement($key)
        $child.InnerText = $fields[$key]
        [void]$linkNode.AppendChild($child)
    }
    [void]$emulatorsDoc.DocumentElement.AppendChild($linkNode)
    Write-Log "LaunchBox: linked TeknoParrot emulator to platform '$platformName'"
}

# Hardcoded skeleton used only when the target platform file has zero
# existing <Game> entries to clone a template from (e.g. a platform this
# script just created). Field values match a real entry captured from a
# working LaunchBox installation, with every scraped/stateful field
# blanked -- see New-LaunchBoxGameEntry's generic reset logic for why most
# fields here are intentionally empty/false/0: this script has no way to
# populate real box art, genre, developer, etc. for an arbitrary game, so
# new entries are left for the user to fill in later via LaunchBox's own
# "search for metadata" feature.
$script:LaunchBoxGameSkeletonFields = [ordered]@{
    GogAppId = ""; OriginAppId = ""; OriginInstallPath = ""; VideoPath = ""; ThemeVideoPath = "";
    ApplicationPath = ""; CommandLine = ""; Completed = "false"; ConfigurationCommandLine = "";
    ConfigurationPath = ""; DateAdded = ""; DateModified = ""; Developer = ""; DosBoxConfigurationPath = "";
    Emulator = ""; Favorite = "false"; ID = ""; ManualPath = ""; MusicPath = ""; Notes = ""; Platform = "";
    Publisher = ""; Rating = ""; ReleaseDate = ""; RootFolder = ""; ScummVMAspectCorrection = "false";
    ScummVMFullscreen = "false"; ScummVMGameDataFolderPath = ""; ScummVMGameType = ""; SortTitle = "";
    Source = ""; StarRatingFloat = "0"; StarRating = "0"; CommunityStarRating = "0";
    CommunityStarRatingTotalVotes = "0"; Status = ""; DatabaseID = ""; WikipediaURL = ""; Title = "";
    UseDosBox = "false"; UseScummVM = "false"; Version = ""; Series = ""; PlayMode = ""; Region = "";
    PlayCount = "0"; PlayTime = "0"; Portable = "false"; Hide = "false"; Broken = "false"; CloneOf = "";
    Genre = ""; MissingVideo = "true"; MissingBoxFrontImage = "true"; MissingScreenshotImage = "true";
    MissingMarqueeImage = "true"; MissingClearLogoImage = "true"; MissingBackgroundImage = "true";
    MissingBox3dImage = "true"; MissingCartImage = "true"; MissingCart3dImage = "true"; MissingManual = "true";
    MissingBannerImage = "true"; MissingMusic = "true"; UseStartupScreen = "false";
    HideAllNonExclusiveFullscreenWindows = "false"; StartupLoadDelay = "0"; HideMouseCursorInGame = "false";
    DisableShutdownScreen = "false"; AggressiveWindowHiding = "false";
    OverrideDefaultStartupScreenSettings = "false"; UsePauseScreen = "false"; PauseAutoHotkeyScript = "";
    ResumeAutoHotkeyScript = ""; OverrideDefaultPauseScreenSettings = "false"; SuspendProcessOnPause = "false";
    ForcefulPauseScreenActivation = "false"; LoadStateAutoHotkeyScript = ""; SaveStateAutoHotkeyScript = "";
    ResetAutoHotkeyScript = ""; SwapDiscsAutoHotkeyScript = ""; CustomDosBoxVersionPath = "";
    ReleaseType = ""; MaxPlayers = "0"; VideoUrl = ""; RetroAchievementsBeatenSoftcore = "false";
    RetroAchievementsBeatenHardcore = "false"; HasCloudSynced = "false"; Progress = "Not Started / Unplayed";
}

# Identity fields every new entry sets explicitly -- everything else is
# either a generic type-pattern reset (cloned-template path) or already
# blank/neutral (hardcoded-skeleton path).
$script:LaunchBoxGameIdentityFields = @('ID', 'Title', 'Platform', 'Emulator', 'ApplicationPath', 'CommandLine', 'DateAdded', 'DateModified')

# Builds one <Game> XML element for a TeknoParrot profile and appends it to
# $platformGamesDoc. If the platform file already has an existing <Game>
# entry, clones it as a template and generically resets every non-identity
# field by type (Missing* -> true; true/false -> false; numeric -> 0;
# anything else non-empty -> blank) rather than hand-maintaining a list of
# ~80 field names -- this adapts automatically to whatever LaunchBox
# version/schema the user actually has, since it is their own real data.
# Falls back to the hardcoded skeleton above only when there is no
# existing entry to clone from. Returns $true if a new entry was created,
# $false if one already exists for this profile (matched by
# ApplicationPath) -- re-runs never duplicate or touch a user's existing
# favorites/playtime for a game they already have.
function New-LaunchBoxGameEntry {
    param(
        [System.Xml.XmlDocument]$platformGamesDoc,
        [string]$relProfilePath,
        [string]$title,
        [string]$platformName,
        [string]$emulatorId
    )

    $gameNodes = @($platformGamesDoc.SelectNodes("/LaunchBox/Game"))
    $already = $gameNodes | Where-Object { (Get-XmlChildText $_ "ApplicationPath") -eq $relProfilePath } | Select-Object -First 1
    if ($already) { return $false }

    $now = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffffzzz")

    if ($gameNodes.Count -gt 0) {
        $template = $gameNodes[0]
        $newNode  = $template.CloneNode($true)
        foreach ($child in @($newNode.ChildNodes)) {
            $name = $child.Name
            if ($script:LaunchBoxGameIdentityFields -contains $name) { continue }
            if ($name -like 'Missing*') { $child.InnerText = 'true'; continue }
            if ([string]::IsNullOrEmpty($child.InnerText)) { continue }
            if ($child.InnerText -eq 'true' -or $child.InnerText -eq 'false') { $child.InnerText = 'false'; continue }
            if ($child.InnerText -match '^-?\d+(\.\d+)?$') { $child.InnerText = '0'; continue }
            $child.InnerText = ''
        }
    } else {
        $newNode = $platformGamesDoc.CreateElement("Game")
        foreach ($key in $script:LaunchBoxGameSkeletonFields.Keys) {
            $child = $platformGamesDoc.CreateElement($key)
            $child.InnerText = $script:LaunchBoxGameSkeletonFields[$key]
            [void]$newNode.AppendChild($child)
        }
    }

    Set-XmlChildText $newNode "ID"              ([guid]::NewGuid().ToString())
    Set-XmlChildText $newNode "Title"           $title
    Set-XmlChildText $newNode "Platform"        $platformName
    Set-XmlChildText $newNode "Emulator"        $emulatorId
    Set-XmlChildText $newNode "ApplicationPath" $relProfilePath
    Set-XmlChildText $newNode "CommandLine"     ""
    Set-XmlChildText $newNode "DateAdded"       $now
    Set-XmlChildText $newNode "DateModified"    $now

    [void]$platformGamesDoc.DocumentElement.AppendChild($newNode)
    return $true
}

# Orchestrates a full direct-write pass: backs up the files about to
# change, creates/reuses the TeknoParrot Emulator entry, creates/reuses
# each target Platform, links them, and adds a <Game> entry for every
# registered TeknoParrot profile that doesn't already have one in that
# platform file. $platformNames is one or two platform display names (two
# only for the "Both Arcade and a dedicated platform" choice). All targets
# either succeed together or nothing is saved -- never a half-written state
# where some platform files reflect new games and Emulators.xml/
# Platforms.xml do not. Returns @{ Results = <name->count>; BackupPath =
# <path> } on success, or $null if refused/failed before anything changed.
function Invoke-LaunchBoxDirectWrite {
    param([string]$userProfilesDir, [string]$tpRoot, [string]$lbRoot, [string[]]$platformNames)

    if (Test-LaunchBoxRunning) {
        Write-Host "  ERROR: LaunchBox or BigBox is currently running." -ForegroundColor Red
        Write-Host "  Close it completely, then try again." -ForegroundColor Yellow
        Write-Log "LaunchBox direct-write: aborted -- LaunchBox/BigBox is running."
        return $null
    }

    $dataDir          = Join-Path $lbRoot "Data"
    $platformsDir     = Join-Path $dataDir "Platforms"
    $emulatorsXmlPath = Join-Path $dataDir "Emulators.xml"
    $platformsXmlPath = Join-Path $dataDir "Platforms.xml"

    if (-not (Test-Path -LiteralPath $emulatorsXmlPath) -or -not (Test-Path -LiteralPath $platformsXmlPath)) {
        Write-Host "  ERROR: Could not find Emulators.xml / Platforms.xml under $dataDir" -ForegroundColor Red
        Write-Log "LaunchBox direct-write: aborted -- Data files not found under $dataDir"
        return $null
    }

    # Resolve and sanitize the platform file path for every target up
    # front, refusing the whole operation if any name is unsafe -- never
    # partially write some platforms and refuse others.
    $platformFiles = [ordered]@{}
    foreach ($name in $platformNames) {
        $safeName = Get-SafeLaunchBoxPlatformFileName $name
        $filePath = Join-Path $platformsDir "$safeName.xml"
        if (-not (Test-PathInside $filePath $platformsDir)) {
            Write-Host "  ERROR: '$name' is not a valid platform name." -ForegroundColor Red
            Write-Log "LaunchBox direct-write: aborted -- unsafe platform name '$name'"
            return $null
        }
        $platformFiles[$name] = $filePath
    }

    $relBackupFiles = New-Object System.Collections.ArrayList
    [void]$relBackupFiles.Add("Data\Emulators.xml")
    [void]$relBackupFiles.Add("Data\Platforms.xml")
    foreach ($name in $platformFiles.Keys) {
        [void]$relBackupFiles.Add((Get-RelativePath $lbRoot $platformFiles[$name]))
    }
    $backupPath = Backup-LaunchBoxFiles -lbRoot $lbRoot -relativeFiles $relBackupFiles
    if (-not $backupPath) {
        Write-Host "  ERROR: Could not back up LaunchBox files -- aborting without making changes." -ForegroundColor Red
        Write-Host "  The script will not write to LaunchBox without a successful backup first." -ForegroundColor Red
        return $null
    }

    $emulatorsDoc     = Read-Xml $emulatorsXmlPath
    $platformsListDoc = Read-Xml $platformsXmlPath
    $emulatorId       = Get-OrCreateLaunchBoxEmulator -emulatorsDoc $emulatorsDoc -tpRoot $tpRoot -lbRoot $lbRoot

    $files = Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Directory.Name -ne "FullBackup" }

    $results      = [ordered]@{}
    $platformDocs = [ordered]@{}

    foreach ($name in $platformFiles.Keys) {
        $filePath = $platformFiles[$name]
        $isNewFile = -not (Test-Path -LiteralPath $filePath)

        $platformGamesDoc = if ($isNewFile) {
            $doc = New-Object System.Xml.XmlDocument
            [void]$doc.AppendChild($doc.CreateXmlDeclaration("1.0", $null, "yes"))
            [void]$doc.AppendChild($doc.CreateElement("LaunchBox"))
            $doc
        } else {
            Read-Xml $filePath
        }

        $platformCreated = Get-OrCreateLaunchBoxPlatform -platformsListDoc $platformsListDoc -platformName $name -tpRoot $tpRoot -lbRoot $lbRoot
        Add-LaunchBoxEmulatorPlatformLink -emulatorsDoc $emulatorsDoc -emulatorId $emulatorId -platformName $name -isNewPlatform $platformCreated

        $added = 0
        foreach ($f in $files) {
            try {
                $profileDoc = Read-Xml $f.FullName
                if ($null -eq $profileDoc.GameProfile) { continue }
                $gpNode   = $profileDoc.GameProfile.SelectSingleNode("GamePath")
                $gamePath = if ($gpNode) { $gpNode.InnerText } else { "" }
                if (-not $gamePath -or -not (Test-Path -LiteralPath $gamePath)) { continue }

                $descNode = $profileDoc.GameProfile.SelectSingleNode("Description")
                if ($descNode -and -not [string]::IsNullOrWhiteSpace($descNode.InnerText)) {
                    $title = $descNode.InnerText.Trim()
                } else {
                    $title = [regex]::Replace($f.BaseName, '(?<=[a-z])(?=[A-Z])', ' ')
                }

                $relProfilePath = Get-RelativePath $lbRoot $f.FullName
                $createdGame = New-LaunchBoxGameEntry -platformGamesDoc $platformGamesDoc -relProfilePath $relProfilePath `
                                   -title $title -platformName $name -emulatorId $emulatorId
                if ($createdGame) { $added++ }
            } catch {
                Write-Log "LaunchBox direct-write: skipped $($f.Name) for platform '$name' -- $_"
            }
        }

        $platformDocs[$name] = @{ Doc = $platformGamesDoc; Path = $filePath }
        $results[$name] = $added
    }

    try {
        Save-Xml $emulatorsDoc $emulatorsXmlPath
        Save-Xml $platformsListDoc $platformsXmlPath
        foreach ($name in $platformDocs.Keys) {
            Save-Xml $platformDocs[$name].Doc $platformDocs[$name].Path
        }
    } catch {
        Write-Host "  ERROR: Failed while saving LaunchBox files -- $_" -ForegroundColor Red
        Write-Host "  A backup from before any changes is at: $backupPath" -ForegroundColor Yellow
        Write-Log "LaunchBox direct-write: FAILED during save -- $_"
        return $null
    }

    Write-Log "LaunchBox direct-write: complete. Backup at $backupPath"
    return @{ Results = $results; BackupPath = $backupPath }
}

# =============================================================================
# HYPERSPIN 2 JSON EXPORT  (optional)
# =============================================================================
# Adds registered TeknoParrot games to HyperSpin 2's game list JSON.
# HyperSpin 2 stores one JSON file per system under <dataPath>\games\.
# The TeknoParrot file is identified by looking for one whose games have
# .xml ROM entries (the format TeknoParrot uses for its profile files).
# Games already present (matched by fileName) are never duplicated.
# The existing file is backed up before any write.
function Export-HyperSpinJson {
    param([string]$userProfilesDir, [string]$hsDataPath)

    # Refuse to write if HyperSpin is running -- check first so we fail fast
    # before doing any file I/O rather than processing everything and then failing.
    if (Get-Process -Name "HyperSpin" -ErrorAction SilentlyContinue) {
        Write-Host "  ERROR: HyperSpin is running. Close it before updating the game list." -ForegroundColor Red
        Write-Log "HyperSpin export: aborted -- HyperSpin is running"
        return -1
    }

    # Locate and parse emulators.json
    $emuPath = Join-Path $hsDataPath "emulators.json"
    if (-not (Test-Path -LiteralPath $emuPath)) {
        Write-Host "  ERROR: emulators.json not found: $emuPath" -ForegroundColor Red
        Write-Log "HyperSpin export: emulators.json not found at $emuPath"
        return -1
    }
    try {
        $emuList = Get-Content -LiteralPath $emuPath -Raw | ConvertFrom-Json
    } catch {
        Write-Host "  ERROR: Could not parse emulators.json: $_" -ForegroundColor Red
        Write-Log "HyperSpin export: failed to parse emulators.json -- $_"
        return -1
    }

    # Find TeknoParrot entry by title. Strip spaces and punctuation before
    # comparing so "Tekno Parrot", "TeknoParrot", "teknoparrot" all match.
    $tpEmu = $emuList | Where-Object {
        $_.title -and ($_.title -replace '[^a-zA-Z0-9]', '') -ieq 'TeknoParrot'
    } | Select-Object -First 1
    if (-not $tpEmu) {
        Write-Host "  ERROR: TeknoParrot emulator not found in emulators.json." -ForegroundColor Red
        Write-Host "  (Searched for any emulator whose title is 'TeknoParrot' after removing spaces/punctuation.)" -ForegroundColor DarkGray
        Write-Log "HyperSpin export: TeknoParrot not found in emulators.json"
        return -1
    }

    # Get the system GUID from the emulator entry directly. This means the export
    # works even when no TeknoParrot games have been added to HyperSpin 2 yet,
    # eliminating the "add one game manually first" prerequisite.
    $tpSystemGuid = [string]$tpEmu.id
    if ([string]::IsNullOrEmpty($tpSystemGuid)) {
        Write-Host "  WARNING: TeknoParrot emulator entry has no 'id' field in emulators.json." -ForegroundColor Yellow
        Write-Host "  Game entries will be written with an empty systemId; HyperSpin 2 may not" -ForegroundColor Yellow
        Write-Host "  associate them with the TeknoParrot system until the emulator is re-added." -ForegroundColor Yellow
        Write-Log "HyperSpin export: WARNING -- emulator entry has no id; systemId will be empty."
    }

    # Locate the games folder; create it if HyperSpin 2 has not yet made it.
    $gamesDir = Join-Path $hsDataPath "games"
    if (-not (Test-Path -LiteralPath $gamesDir)) {
        try {
            [void][System.IO.Directory]::CreateDirectory($gamesDir)
            Write-Log "HyperSpin export: created games folder at $gamesDir"
        } catch {
            Write-Host "  ERROR: HyperSpin games folder not found and could not be created: $_" -ForegroundColor Red
            Write-Log "HyperSpin export: games folder missing and creation failed -- $_"
            return -1
        }
    }

    $tpGamesPath = $null
    $newFile     = $false   # true when we create the games file from scratch this run

    # Primary scan: match games files by system GUID. Works with 0 or more existing
    # games and is reliable regardless of the file's name.
    if ($tpSystemGuid) {
        foreach ($gf in (Get-ChildItem -LiteralPath $gamesDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            try {
                $sample    = Get-Content -LiteralPath $gf.FullName -Raw | ConvertFrom-Json
                $firstGame = if ($sample -is [array]) { $sample[0] } else { $sample }
                if ($firstGame -and [string]$firstGame.gameSystemId -eq $tpSystemGuid) {
                    $tpGamesPath = $gf.FullName; break
                }
            } catch { Write-Log "HyperSpin export: GUID scan skipped $($gf.Name) -- $_"; continue }
        }
    }

    # Fallback scan: match by .xml ROM entries (for installs where the emulator
    # entry has no id field, or the system GUID could not be determined).
    if (-not $tpGamesPath) {
        foreach ($gf in (Get-ChildItem -LiteralPath $gamesDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            try {
                $sample    = Get-Content -LiteralPath $gf.FullName -Raw | ConvertFrom-Json
                $firstGame = if ($sample -is [array]) { $sample[0] } else { $sample }
                # PS 5.1 may return a single-element JSON array as a bare PSCustomObject
                # rather than a one-element array.  Normalise roms to an array either way.
                $firstRom  = if ($firstGame -and $firstGame.roms -is [array]) { $firstGame.roms[0] } else { $firstGame.roms }
                if ($firstGame -and $firstRom -and $firstRom.name -like "*.xml") {
                    $tpGamesPath = $gf.FullName
                    if (-not $tpSystemGuid) { $tpSystemGuid = [string]$firstGame.gameSystemId }
                    break
                }
            } catch { Write-Log "HyperSpin export: ROM scan skipped $($gf.Name) -- $_"; continue }
        }
    }

    # No games file found -- create a new empty one named after the emulator title.
    # This eliminates the prerequisite of adding one game manually first.
    # Guard: only write when no file with that name already exists on disk -- a file
    # could exist outside the scanned paths (manual creation, alternate HS install).
    if (-not $tpGamesPath) {
        $safeName = ($tpEmu.title -replace '[^A-Za-z0-9\-\.]', '_').Trim('_')
        if ([string]::IsNullOrEmpty($safeName)) { $safeName = 'TeknoParrot' }
        $tpGamesPath = Join-Path $gamesDir "$safeName.json"
        if (-not (Test-Path -LiteralPath $tpGamesPath)) {
            try {
                [System.IO.File]::WriteAllText($tpGamesPath, '[]', (New-Object System.Text.UTF8Encoding $false))
                Write-Log "HyperSpin export: created new games file at $tpGamesPath"
                $newFile = $true
            } catch {
                Write-Host "  ERROR: Could not create TeknoParrot games file: $_" -ForegroundColor Red
                Write-Log "HyperSpin export: could not create games file -- $_"
                return -1
            }
        } else {
            Write-Log "HyperSpin export: using existing file at $tpGamesPath (found outside scanned paths)"
        }
    }

    # Load existing game list
    try {
        $existing = New-Object System.Collections.ArrayList
        # @() guard: ConvertFrom-Json returns $null for an empty "[]" in PS 5.1, not an empty array.
        foreach ($g in @(Get-Content -LiteralPath $tpGamesPath -Raw | ConvertFrom-Json)) {
            [void]$existing.Add($g)
        }
    } catch {
        Write-Host "  ERROR: Could not read games file: $_" -ForegroundColor Red
        Write-Log "HyperSpin export: failed to read games file -- $_"
        return -1
    }

    # Build set of already-known profile codes (case-insensitive)
    $known = @{}
    foreach ($g in $existing) {
        if ($g.fileName) { $known[$g.fileName.ToLower()] = $true }
    }

    # Iterate UserProfiles; add each game not already in HyperSpin
    $added   = 0
    $now     = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
    $xmlFiles = Get-ChildItem -LiteralPath $userProfilesDir -Filter "*.xml" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -ne "FullBackup" }

    foreach ($pf in $xmlFiles) {
        $code = $pf.BaseName
        if ($known.ContainsKey($code.ToLower())) { continue }

        try {
            $doc    = Read-Xml $pf.FullName
            if ($null -eq $doc.GameProfile) { continue }
            $gpNode = $doc.GameProfile.SelectSingleNode("GamePath")
            if (-not $gpNode -or [string]::IsNullOrWhiteSpace($gpNode.InnerText)) { continue }
            if (-not (Test-Path -LiteralPath $gpNode.InnerText.Trim())) { continue }

            $descNode = $doc.GameProfile.SelectSingleNode("Description")
            $title = if ($descNode -and -not [string]::IsNullOrWhiteSpace($descNode.InnerText)) {
                $descNode.InnerText.Trim()
            } else {
                [regex]::Replace($code, '(?<=[a-z])(?=[A-Z])', ' ')
            }
        } catch { continue }

        $gameId = [System.Guid]::NewGuid().ToString()
        $romId  = [System.Guid]::NewGuid().ToString()

        $romObj = [ordered]@{
            id              = $romId
            name            = "$code.xml"
            size            = $null
            crc             = $null
            md5             = $null
            sha1            = $null
            relatedGameId   = $gameId
            relatedSystemId = $tpSystemGuid
            active          = $true
            createdDate     = $now
            modifiedDate    = $now
        }

        $gameObj = [ordered]@{
            id                            = $gameId
            name                          = $title
            description                   = $title
            releaseYear                   = $null
            releaseDate                   = $null
            cooperative                   = $false
            players                       = 1
            videoUrl                      = ""
            developer                     = ""
            publisher                     = ""
            esrb                          = "Not Rated"
            genres                        = ""
            gameSystemId                  = $tpSystemGuid
            fileName                      = $code
            releaseType                   = "Released"
            communityRating               = $null
            communityRatingCount          = $null
            wikipediaURL                  = ""
            cloneOf                       = $null
            referenceId                   = $null
            datFileId                     = $null
            metadataEnrichmentProvider    = $null
            metadataEnrichmentCandidateId = $null
            metadataEnrichmentAppliedDate = $null
            titleId                       = $null
            createdDate                   = $now
            modifiedDate                  = $now
            platform                      = $null
            maxPlayers                    = $null
            overview                      = $null
            databaseID                    = $null
            alternateNames                = $null
            roms                          = @($romObj)
            criticRatings                 = @()
        }

        [void]$existing.Add($gameObj)
        $known[$code.ToLower()] = $true
        $added++
    }

    if ($added -eq 0) {
        Write-Log "HyperSpin export: no new games to add (all already present)"
        return 0
    }

    # Back up the games file before writing, but only when it pre-existed.
    # A freshly-created empty file needs no backup.
    $backupPath = $null
    if (-not $newFile) {
        $backupPath = $tpGamesPath + ".bak_" + (Get-Date).ToString("yyyyMMdd_HHmmss")
        try {
            Copy-Item -LiteralPath $tpGamesPath -Destination $backupPath -ErrorAction Stop
        } catch {
            Write-Host "  ERROR: Could not back up games file: $_" -ForegroundColor Red
            Write-Log "HyperSpin export: backup failed -- $_"
            return -1
        }
    }

    try {
        $allGames = @($existing.ToArray())
        $json = ConvertTo-Json -InputObject @($allGames) -Depth 10
        # Atomic write: a crash mid-write must never leave $tpGamesPath
        # truncated, since on a pre-existing file there is no automatic
        # restore from the .bak_ copy above -- same pattern as Save-Xml,
        # including its Delete+Move fallback (File.Replace's 3-arg overload
        # throws "The path is empty" on some .NET builds even with a real
        # source/destination, so it cannot be relied on alone).
        $tmpPath = $tpGamesPath + ".tmp"
        [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding $false))
        try {
            [System.IO.File]::Replace($tmpPath, $tpGamesPath, $null)
        } catch {
            [System.IO.File]::Delete($tpGamesPath)
            [System.IO.File]::Move($tmpPath, $tpGamesPath)
        }
    } catch {
        Write-Host "  ERROR: Could not write games file: $_" -ForegroundColor Red
        Write-Log "HyperSpin export: write failed -- $_"
        return -1
    }

    $backupNote = if ($backupPath) { " (backup: $backupPath)" } else { "" }
    Write-Log "HyperSpin export: added $added game(s) to $tpGamesPath$backupNote"
    return $added
}

# =============================================================================
# THUMBNAIL DOWNLOAD  (optional, fetches game icons from GitHub)
# =============================================================================
# Downloads ProfileCode.png from the TeknoParrotUIThumbnails repository into
# <TeknoParrotRoot>\Icons\ -- the exact path TeknoParrotUI reads at startup.
# Only fetches icons that are absent; never overwrites existing files.
# Source: https://github.com/teknogods/TeknoParrotUIThumbnails
function Invoke-ThumbnailDownload {
    param([string]$userProfilesDir, [string]$tpRoot)

    $iconsDir = Join-Path $tpRoot "Icons"
    if (-not (Test-Path -LiteralPath $iconsDir)) {
        try {
            [void][System.IO.Directory]::CreateDirectory($iconsDir)
            Write-Log "Thumbnails: created Icons folder at $iconsDir"
        } catch {
            Write-Host "  ERROR: Could not create Icons folder: $_" -ForegroundColor Red
            Write-Log "Thumbnails: could not create Icons folder -- $_"
            return
        }
    }

    # Load registered profiles first -- needed for custom thumbnail validation below.
    $profiles = @(Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" })

    if ($profiles.Count -eq 0) {
        Write-Host "  No registered profiles found." -ForegroundColor DarkGray
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "CustomThumbnails")) {
            Write-Host "  (Custom thumbnails in CustomThumbnails\ will be processed once games are registered.)" -ForegroundColor DarkGray
        }
        Write-Log "Thumbnails: no registered profiles -- custom copy and download skipped."
        return
    }

    # Build a case-insensitive lookup of all registered profile codes.
    $knownCodes = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $profiles) { [void]$knownCodes.Add($p.BaseName) }

    # Copy custom thumbnails from Scripts\CustomThumbnails\ into the Icons folder.
    # Each file is validated against the registered profile codes first.
    $customThumbDir = Join-Path $PSScriptRoot "CustomThumbnails"
    if (Test-Path -LiteralPath $customThumbDir) {
        $customFiles = @(Get-ChildItem -LiteralPath $customThumbDir -Filter "*.png" -File -ErrorAction SilentlyContinue)
        if ($customFiles.Count -gt 0) {
            Write-Host ("  Custom thumbnails folder: {0} PNG file(s) found." -f $customFiles.Count) -ForegroundColor Cyan
            $custCopied = 0; $custSkipped = 0; $custBadName = 0
            foreach ($cf in $customFiles) {
                $code = [System.IO.Path]::GetFileNameWithoutExtension($cf.Name)
                if (-not $knownCodes.Contains($code)) {
                    Write-Host ("  WRONG NAME: CustomThumbnails\{0}" -f $cf.Name) -ForegroundColor Yellow
                    Write-Host ("             '{0}' does not match any registered game profile code." -f $code) -ForegroundColor Yellow
                    Write-Host "             Check TeknoParrot-Manager-controls.txt for the correct" -ForegroundColor Yellow
                    Write-Host "             name, rename the file, then re-run. File was not copied." -ForegroundColor Yellow
                    Write-Log "Thumbnails: custom $($cf.Name) -- no matching profile code, skipped."
                    $custBadName++
                    continue
                }
                $dest = Join-Path $iconsDir $cf.Name
                if (Test-Path -LiteralPath $dest) {
                    $custSkipped++
                } else {
                    try {
                        Copy-Item -LiteralPath $cf.FullName -Destination $dest -ErrorAction Stop
                        Write-Log "Thumbnails: copied custom $($cf.Name)"
                        $custCopied++
                    } catch {
                        Write-Host ("  WARNING: Could not copy {0} -- {1}" -f $cf.Name, $_) -ForegroundColor Yellow
                        Write-Log "Thumbnails: failed to copy custom $($cf.Name) -- $_"
                    }
                }
            }
            if ($custCopied   -gt 0) { Write-Host ("  Copied  : {0} custom thumbnail(s) to Icons folder." -f $custCopied)   -ForegroundColor Green   }
            if ($custSkipped  -gt 0) { Write-Host ("  Skipped : {0} -- icon already present."             -f $custSkipped)  -ForegroundColor DarkGray }
            if ($custBadName  -gt 0) { Write-Host ("  Invalid : {0} -- wrong filename (see above)."       -f $custBadName)  -ForegroundColor Yellow   }
            Write-Log ("Thumbnails: custom copied={0} skipped={1} badName={2}" -f $custCopied, $custSkipped, $custBadName)
        }
    }

    $missing      = New-Object System.Collections.ArrayList
    $alreadyCount = 0
    foreach ($f in $profiles) {
        if (Test-Path -LiteralPath (Join-Path $iconsDir ($f.BaseName + ".png"))) {
            $alreadyCount++
        } else {
            [void]$missing.Add($f.BaseName)
        }
    }

    Write-Host ("  {0} profile(s): {1} already have an icon, {2} missing." -f `
        $profiles.Count, $alreadyCount, $missing.Count) -ForegroundColor Cyan

    if ($missing.Count -eq 0) {
        Write-Host "  All registered games already have icons. Nothing to download." -ForegroundColor Green
        Write-Log "Thumbnails: all $alreadyCount icons already present."
        return
    }

    $baseUrl = "https://raw.githubusercontent.com/teknogods/TeknoParrotUIThumbnails/master/Icons/"
    $fetched  = 0
    $notAvail = 0
    $failed   = 0
    $i        = 0
    $total    = $missing.Count

    foreach ($code in $missing) {
        $i++
        $destPath = Join-Path $iconsDir ($code + ".png")
        $url      = $baseUrl + [Uri]::EscapeDataString($code + ".png")
        Write-Host ("  [{0,3}/{1}] {2}" -f $i, $total, $code) -ForegroundColor DarkCyan -NoNewline
        $dlOk = $false
        for ($attempt = 1; $attempt -le 3 -and -not $dlOk; $attempt++) {
            try {
                Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing `
                                  -TimeoutSec 30 -ErrorAction Stop
                Write-Host "  OK" -ForegroundColor Green
                Write-Log "Thumbnails: downloaded $code"
                $fetched++
                $dlOk = $true
            } catch {
                $statusCode = 0
                if ($_.Exception.Response) {
                    try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
                }
                if (Test-Path -LiteralPath $destPath) {
                    Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
                }
                if ($statusCode -eq 404) {
                    Write-Host "  not in repo" -ForegroundColor DarkGray
                    $notAvail++
                    break   # 404 is definitive -- no point retrying
                }
                if ($attempt -lt 3) {
                    Write-Host ("  attempt $attempt failed, retrying..." ) -ForegroundColor Yellow
                    Write-Log "Thumbnails: attempt $attempt FAILED $code -- $($_.Exception.Message)"
                    Start-Sleep -Seconds 5
                } else {
                    Write-Host ("  FAILED ({0})" -f $_.Exception.Message) -ForegroundColor Red
                    Write-Log "Thumbnails: FAILED $code -- $($_.Exception.Message)"
                    $failed++
                }
            }
        }
    }

    Write-Host ""
    $failSuffix = if ($failed -gt 0) { ", $failed failed" } else { "" }
    Write-Host ("  Thumbnails: {0} fetched, {1} already present, {2} not in repo{3}." -f `
        $fetched, $alreadyCount, $notAvail, $failSuffix) -ForegroundColor Green
    Write-Log ("Thumbnails: fetched=$fetched alreadyPresent=$alreadyCount notAvail=$notAvail failed=$failed")
}

# =============================================================================
# CONTROLS STATUS REPORT
# =============================================================================
# Writes a snapshot of every registered game's control state to a persistent
# text file. Groups by control family, shows propagation source and any
# buttons still left manual. Overwrites the previous file on every call --
# it is a current-state view, not an append log.
# Returns the number of games written, or -1 on write failure.
function Write-ControlsStatus {
    param([string]$userProfilesDir, $pool, $propagationReports, [string]$outputPath)

    $poolCodes = @{}
    if ($null -ne $pool) { foreach ($s in $pool) { $poolCodes[$s.Code] = $true } }

    $reportMap = @{}
    if ($null -ne $propagationReports) {
        foreach ($r in $propagationReports) { $reportMap[$r.Code] = $r }
    }

    $files = @(Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Directory.Name -ne "FullBackup" } |
               Sort-Object BaseName)

    $rows = New-Object System.Collections.ArrayList
    foreach ($f in $files) {
        try { $doc = Read-Xml $f.FullName } catch { Write-Log "Write-ControlsStatus: could not parse $($f.Name) -- $_"; continue }
        if ($null -eq $doc.GameProfile) { continue }

        $family = Get-ProfileFamily $doc
        $btns   = @(Get-ButtonNodes $doc)
        $bound  = 0
        $manual = New-Object System.Collections.ArrayList
        foreach ($b in $btns) {
            if (Test-ButtonIsBound $b) {
                $bound++
            } else {
                $n = $b.SelectSingleNode("ButtonName")
                if ($n -and -not [string]::IsNullOrWhiteSpace($n.InnerText)) {
                    [void]$manual.Add($n.InnerText.Trim())
                }
            }
        }

        $status = ""; $reference = ""
        if ($poolCodes.ContainsKey($f.BaseName)) {
            $status = "REFERENCE"
            if ($reportMap.ContainsKey($f.BaseName) -and $reportMap[$f.BaseName].Status -eq "api-fixed-canonical") {
                $r = $reportMap[$f.BaseName]
                $status = "REFERENCE (Input API corrected)"; $reference = $r.Archetype
            }
        }
        elseif ($reportMap.ContainsKey($f.BaseName)) {
            $r = $reportMap[$f.BaseName]
            switch ($r.Status) {
                "bound"            { $status = "propagated"; $reference = $r.Archetype }
                "api-fixed"        { $status = "already bound (Input API corrected)"; $reference = $r.Archetype }
                "skipped-bound"    { $status = "already bound" }
                "skipped-override" { $status = "skipped (override)" }
                "no-archetype"     { $status = "no reference game" }
                "save-failed"      { $status = "save failed" }
                default            { $status = $r.Status }
            }
        }
        elseif ($bound -ge 5) { $status = "bound" }
        elseif ($bound -gt 0) { $status = "partial" }
        else                  { $status = "no controls" }

        # If the propagation run flagged directionally-mismatched slots on this
        # already-bound profile, surface them distinctly so they appear in the
        # controls-status output. The profile's bindings were never changed --
        # these slots need manual attention in TeknoParrot's own UI. See #17.
        $mismatch = New-Object System.Collections.ArrayList
        if ($reportMap.ContainsKey($f.BaseName) -and $reportMap[$f.BaseName].MismatchSlots) {
            foreach ($slot in ($reportMap[$f.BaseName].MismatchSlots -split ', ')) {
                [void]$mismatch.Add($slot)
            }
        }

        [void]$rows.Add([pscustomobject]@{
            Code = $f.BaseName; Family = $family
            Bound = $bound; Total = $btns.Count
            Manual = $manual; Mismatch = $mismatch; Status = $status; Reference = $reference
        })
    }

    $knownFamilies = @('button','driving','lightgun','trackball','analog','spinner')
    $extraFamilies = @($rows | ForEach-Object { $_.Family } | Sort-Object -Unique |
                       Where-Object { $knownFamilies -notcontains $_ })
    $allFamilies   = $knownFamilies + $extraFamilies

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("TeknoParrot Manager -- Controls Status")
    [void]$sb.AppendLine("Generated : $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$sb.AppendLine("Profiles  : $($rows.Count)")
    [void]$sb.AppendLine(("=" * 80))

    foreach ($fam in $allFamilies) {
        $group = @($rows | Where-Object { $_.Family -eq $fam } | Sort-Object Code)
        if ($group.Count -eq 0) { continue }
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("[$fam]")
        foreach ($row in $group) {
            $boundLabel = "{0}/{1} bound" -f $row.Bound, $row.Total
            $refPart    = if ($row.Reference) { "  <- $($row.Reference)" } else { "" }
            [void]$sb.AppendLine(("  {0,-44} {1,-12}  {2}{3}" -f $row.Code, $boundLabel, $row.Status, $refPart))
            if ($row.Manual.Count -gt 0) {
                [void]$sb.AppendLine("    manual: $($row.Manual -join ', ')")
            }
            if ($row.Mismatch.Count -gt 0) {
                [void]$sb.AppendLine("    mismatch (rebind in TeknoParrot UI): $($row.Mismatch -join ', ')")
            }
        }
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine(("=" * 80))

    try {
        [System.IO.File]::WriteAllText($outputPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))
        return $rows.Count
    } catch {
        Write-Log "Controls status: FAILED to write -- $_"
        return -1
    }
}

Write-Log "Script started (v$ScriptVersion$(if ($Unattended) { ' [Unattended]' }))."

# =============================================================================
# SECTION 1 -- Load or prompt for configuration
# =============================================================================

$configPath         = Join-Path $PSScriptRoot "TeknoParrot-Manager.config.json"
$tpRoot             = $null
$mode               = $null   # "AutoSync", "RegisterOnly", "CrosshairSetup", "ReShadeSetup", "DgVoodoo2Setup", "GpuFixSetup", "FFBSetup", "BepInExUpdate", "Restore", or "HealthCheck"
$pendingApplyMode   = $null   # set when a preview run's "Apply for real now?" prompt is answered Y -- tells the
                               # next loop iteration to silently re-enter the same mode and run it for real,
                               # instead of showing the menu again.
$forceRealApply     = $false  # consumed once, right after $pendingApplyMode triggers a re-entry, to force
                               # $dryRunActive = $false without re-asking the preview question.
$zipSource               = $null   # AutoSync only (main collection)
$zipSourceSupplementary  = $null   # AutoSync supplementary source (optional, separate library); $null or ''=not configured
$gamesInstallFolder = $null   # always (the extracted-games root to register)
$retroBat           = $false  # true = extracted folders named GameName.teknoparrot (RetroBat/Batocera)
$hsDataPath         = $null   # HyperSpin 2 data folder (e.g. C:\ProgramData\HyperSpin\data)
$rsSourceDll        = $null   # ReShade 64-bit DLL (bundled at ReShade\ReShade64.dll or user-provided)
$rsSourceDll32      = $null   # ReShade 32-bit DLL (bundled at ReShade\ReShade32.dll or user-provided)
$dgSourceDir        = $null   # dgVoodoo2 DLL folder (bundled at dgVoodoo2\ or user-provided)
$datFilePath          = ''      # optional collection .dat file path (overrides ZIP)
$eggmanDatZip         = ''      # path to Eggman ZIP (contains both dats + notes)
$supplementaryDatPath = ''      # supplementary .dat path (when using separate files)
$includeSupplementary = $false  # whether to build the supplementary index
$lbRoot                     = $null   # LaunchBox install root (containing LaunchBox.exe), if found/entered
$lbPlatformMode             = $null   # "Arcade" / "TeknoParrot" / "Custom" / "Both"
$lbCustomPlatformName       = $null   # only set when $lbPlatformMode is "Custom"
$lbEmulatorId               = $null   # cached GUID of the TeknoParrot Emulator entry in LaunchBox's Emulators.xml
$postgresSuperPasswordEncrypted = $null   # DPAPI-encrypted (ConvertFrom-SecureString, current user+machine) Postgres superuser password
$configAccepted       = $false  # true when the user accepted a saved config this run

if ($Unattended -and -not (Test-Path -LiteralPath $configPath)) {
    Write-Host ""
    Write-Host "ERROR: Unattended mode requires saved settings." -ForegroundColor Red
    Write-Host "Run the script once interactively to save your configuration, then retry with -Unattended." -ForegroundColor Yellow
    Write-Log "ERROR: Unattended mode -- no saved config at $configPath"; exit 1
}

if (Test-Path -LiteralPath $configPath) {
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if ($null -eq $cfg) { throw "Config file parsed as null -- file may be empty or corrupt." }
        if ([string]::IsNullOrWhiteSpace($cfg.TeknoParrotRoot) -or
            [string]::IsNullOrWhiteSpace($cfg.GamesInstallFolder)) {
            throw "Config is missing TeknoParrotRoot or GamesInstallFolder -- treating as corrupt."
        }
        Write-Host "Saved configuration found:" -ForegroundColor Cyan
        Write-Host "  TeknoParrot root     : $($cfg.TeknoParrotRoot)"
        if ($cfg.ZipSourceFolder)              { Write-Host "  ZIP source folder    : $($cfg.ZipSourceFolder)" }
        if ($cfg.ZipSourceSupplementaryFolder) { Write-Host "  ZIP supplementary    : $($cfg.ZipSourceSupplementaryFolder)" }
        Write-Host "  Games install folder : $($cfg.GamesInstallFolder)"
        if ($cfg.RetroBat)         { Write-Host "  RetroBat mode        : Yes" }
        if ($cfg.HyperSpinDataPath){ Write-Host "  HyperSpin data path  : $($cfg.HyperSpinDataPath)" }
        if ($cfg.ReShadeSourceDll)   { Write-Host "  ReShade DLL (64-bit) : $($cfg.ReShadeSourceDll)" }
        if ($cfg.ReShadeSourceDll32) { Write-Host "  ReShade DLL (32-bit) : $($cfg.ReShadeSourceDll32)" }
        if ($cfg.DgVoodoo2SourceDir) { Write-Host "  dgVoodoo2 folder     : $($cfg.DgVoodoo2SourceDir)" }
        if ($cfg.EggmanDatZip)          { Write-Host "  Eggman dat ZIP       : $($cfg.EggmanDatZip)" }
        if ($cfg.DatFilePath)           { Write-Host "  Collection dat       : $($cfg.DatFilePath)" }
        if ($cfg.SupplementaryDatPath)  { Write-Host "  Supplementary dat    : $($cfg.SupplementaryDatPath)" }
        if ($cfg.IncludeSupplementary)  { Write-Host "  Supplementary index  : Yes" }
        if ($cfg.LaunchBoxRoot)         { Write-Host "  LaunchBox root       : $($cfg.LaunchBoxRoot)" }
        if ($cfg.LaunchBoxPlatformMode) { Write-Host "  LaunchBox platform   : $($cfg.LaunchBoxPlatformMode)" }
        Write-Host ""
        if ($Unattended) {
            Write-Host "  [Unattended] Using saved settings." -ForegroundColor DarkCyan
            Write-Log "Unattended: auto-accepted saved settings."
            $use = "Y"
        } else {
            $use = (Read-Host "Use these settings? (Y/N)").Trim()
        }
        if ($use.ToUpper() -eq "Y") {
            # A config saved by an older script version could have
            # TeknoParrotRoot stored as a JSON array instead of a plain
            # string (confirmed from a real tester's config.json) --
            # coerce to a scalar defensively so a stale file from before
            # this fix doesn't keep propagating the wrong type forever
            # (Save-Config below would otherwise just re-save whatever
            # type $tpRoot currently holds).
            $tpRoot             = if ($cfg.TeknoParrotRoot -is [array]) { [string]$cfg.TeknoParrotRoot[0] } else { [string]$cfg.TeknoParrotRoot }
            $zipSource          = $cfg.ZipSourceFolder
            if ($null -ne $cfg.ZipSourceSupplementaryFolder) { $zipSourceSupplementary = "$($cfg.ZipSourceSupplementaryFolder)" }
            $gamesInstallFolder = $cfg.GamesInstallFolder
            if ($null -ne $cfg.RetroBat) { $retroBat = [bool]$cfg.RetroBat }
            if ($cfg.HyperSpinDataPath)  { $hsDataPath  = $cfg.HyperSpinDataPath  }
            if ($cfg.ReShadeSourceDll)   { $rsSourceDll   = $cfg.ReShadeSourceDll   }
            if ($cfg.ReShadeSourceDll32) { $rsSourceDll32 = $cfg.ReShadeSourceDll32 }
            if ($cfg.DgVoodoo2SourceDir) { $dgSourceDir   = $cfg.DgVoodoo2SourceDir }
            if ($cfg.EggmanDatZip)         { $eggmanDatZip         = $cfg.EggmanDatZip         }
            if ($cfg.DatFilePath)          { $datFilePath           = $cfg.DatFilePath           }
            if ($cfg.SupplementaryDatPath) { $supplementaryDatPath  = $cfg.SupplementaryDatPath  }
            if ($null -ne $cfg.IncludeSupplementary) { $includeSupplementary = [bool]$cfg.IncludeSupplementary }
            if ($cfg.LaunchBoxRoot)               { $lbRoot               = $cfg.LaunchBoxRoot }
            if ($cfg.LaunchBoxPlatformMode)        { $lbPlatformMode       = $cfg.LaunchBoxPlatformMode }
            if ($cfg.LaunchBoxCustomPlatformName)  { $lbCustomPlatformName = $cfg.LaunchBoxCustomPlatformName }
            if ($cfg.LaunchBoxEmulatorId)          { $lbEmulatorId         = $cfg.LaunchBoxEmulatorId }
            if ($cfg.PostgresSuperPasswordEncrypted) { $postgresSuperPasswordEncrypted = $cfg.PostgresSuperPasswordEncrypted }
            # A saved "Custom" platform choice with no name is a corrupt/incomplete
            # config (e.g. hand-edited or from an older version) -- silently
            # falling back to a default name would be a confusing surprise, so
            # clear the saved mode and let the platform-choice menu re-ask instead.
            if ($lbPlatformMode -eq "Custom" -and [string]::IsNullOrWhiteSpace($lbCustomPlatformName)) {
                $lbPlatformMode = $null
            }
            $configAccepted = $true
        }
        Write-Host ""
    } catch {
        Write-Host "WARNING: Saved configuration could not be read (file may be corrupt)." -ForegroundColor Yellow
        Write-Host "         Falling through to manual prompts." -ForegroundColor DarkCyan
        Write-Log "Config: could not parse config.json -- $_"
        Write-Host ""
    }
}

if (-not $tpRoot) {
    $detected = @(Find-TeknoParrotRoot)
    if ($Unattended) {
        if ($detected.Count -ge 1) {
            $tpRoot = $detected[0]
            Write-Host "  [Unattended] TeknoParrot auto-detected at: $tpRoot" -ForegroundColor DarkCyan
            Write-Log "Unattended: TeknoParrot auto-detected at $tpRoot"
        } else {
            Write-Host "ERROR: Unattended mode -- could not auto-detect TeknoParrot and no saved path." -ForegroundColor Red
            Write-Log "ERROR: Unattended mode -- TeknoParrot root not found."; exit 1
        }
    } elseif ($detected.Count -eq 1) {
        Write-Host ""
        Write-Host "  Auto-detected TeknoParrot at: $($detected[0])" -ForegroundColor Cyan
        $useIt = (Read-Host "  Use this path? (Y/N)").Trim().ToUpper()
        if ($useIt -eq "Y") { $tpRoot = $detected[0] }
    } elseif ($detected.Count -gt 1) {
        Write-Host ""
        Write-Host "  Found TeknoParrot in multiple locations:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $detected.Count; $i++) {
            Write-Host ("    {0}) {1}" -f ($i + 1), $detected[$i])
        }
        $pick = (Read-Host "  Enter number to use one, or N to type the path manually").Trim()
        if ($pick -match '^\d+$' -and $pick.Length -le 9) {
            $idx = [int]$pick - 1
            if ($idx -ge 0 -and $idx -lt $detected.Count) { $tpRoot = $detected[$idx] }
        }
    }
    if (-not $tpRoot) {
        $tpRoot = Read-PathWithBrowse "Enter TeknoParrot root folder (containing TeknoParrotUi.exe)"
    }
}

if (-not $gamesInstallFolder) {
    if ($Unattended) {
        Write-Host "ERROR: Unattended mode -- games install folder not in saved settings." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- gamesInstallFolder not set."; exit 1
    }
    $gamesInstallFolder = Read-PathWithBrowse "Enter folder containing your extracted games (e.g. E:\TeknoParrotGames)"
}

if (-not $configAccepted -and -not $Unattended) {
    Write-Host ""
    Write-Host "  Is this a RetroBat/Batocera installation?" -ForegroundColor Cyan
    Write-Host "  (Y = game folders use a RetroBat suffix: .teknoparrot / .parrot / .game)" -ForegroundColor DarkCyan
    Write-Host "  (extracted folders will be named  GameName.teknoparrot)" -ForegroundColor DarkCyan
    $rbChoice = (Read-Host "  Use RetroBat folder naming? (Y/N)").Trim().ToUpper()
    $retroBat = ($rbChoice -eq "Y")
    if ($retroBat) { Write-Log "RetroBat mode enabled by user." }
}

if (-not $eggmanDatZip -and -not $datFilePath -and -not $Unattended) {
    Write-Host ""
    Write-Host "  Eggman dat files (optional)" -ForegroundColor Cyan
    Write-Host "  Used to accurately register shared-exe games, ELF-based games," -ForegroundColor DarkCyan
    Write-Host "  and slightly misnamed folders. The ZIP (~145 MB) contains both dats." -ForegroundColor DarkCyan
    Write-Host "    D) Download from GitHub now  (~145 MB)"
    Write-Host "    Z) I have the ZIP already -- enter path"
    Write-Host "    F) I have separate dat files -- enter paths"
    Write-Host "    N) Skip"
    $datChoice = (Read-Host "  Choice (D/Z/F/N)").Trim().ToUpper()
    $raw = ''   # shared path variable for Z and fallback paths

    if ($datChoice -eq 'D') {
        Write-Host "  Checking GitHub for latest Eggman dat release..." -ForegroundColor Cyan
        $rel = Get-EggmanDatRelease
        if ($null -ne $rel) {
            Write-Host ("  Found: {0}  ({1} MB)" -f $rel.FileName, $rel.SizeMB) -ForegroundColor Cyan
            $savedPath = Invoke-EggmanDatDownloadInteractive $rel
            if ($savedPath) {
                $eggmanDatZip = $savedPath
                Write-Host "  Saved: $savedPath" -ForegroundColor Green
                Write-Log "EggmanDat: downloaded to $savedPath"
                $askSupp = (Read-Host "  Also index supplementary dat for alternate version info? (Y/N)").Trim().ToUpper()
                $includeSupplementary = ($askSupp -eq 'Y')
                if ($includeSupplementary) { Write-Log "EggmanDat: supplementary indexing enabled." }
            } else {
                Write-Host "  Enter path to existing ZIP or .dat file, or press Enter to skip:" -ForegroundColor Yellow
                $raw      = Read-PathWithBrowse "  Path" -Mode File -FileFilter "ZIP/dat files (*.zip;*.dat)|*.zip;*.dat|All files (*.*)|*.*"
                $datChoice = 'FALLBACK'
            }
        } else {
            Write-Host "  Could not reach GitHub. Enter path to existing ZIP or .dat file, or press Enter to skip:" -ForegroundColor Yellow
            $raw      = Read-PathWithBrowse "  Path" -Mode File -FileFilter "ZIP/dat files (*.zip;*.dat)|*.zip;*.dat|All files (*.*)|*.*"
            $datChoice = 'FALLBACK'
        }
    }

    if ($datChoice -eq 'Z' -or $datChoice -eq 'FALLBACK') {
        if ($datChoice -eq 'Z') { $raw = Read-PathWithBrowse "  Path to Eggman dat ZIP" -Mode File -FileFilter "ZIP files (*.zip)|*.zip|All files (*.*)|*.*" }
        if ($raw) {
            if (Test-Path -LiteralPath $raw) {
                $ext = [System.IO.Path]::GetExtension($raw).ToLower()
                if ($ext -eq '.zip') {
                    $eggmanDatZip = $raw
                    Write-Log "EggmanDat: ZIP configured at $raw"
                    $askSupp = (Read-Host "  Also index supplementary dat for alternate version info? (Y/N)").Trim().ToUpper()
                    $includeSupplementary = ($askSupp -eq 'Y')
                    if ($includeSupplementary) { Write-Log "EggmanDat: supplementary indexing enabled." }
                } elseif ($ext -eq '.dat') {
                    $datFilePath = $raw
                    Write-Log "Config: datFilePath set to $raw"
                } else {
                    Write-Host "  WARNING: Expected .zip or .dat file -- dat skipped." -ForegroundColor Yellow
                    Write-Log ("EggmanDat: unrecognised file type '{0}' at {1} -- skipped." -f $ext, $raw)
                }
            } else {
                Write-Host "  WARNING: File not found -- dat skipped." -ForegroundColor Yellow
                Write-Log "EggmanDat: file not found at $raw -- skipped."
            }
        }
    }

    if ($datChoice -eq 'F') {
        $rawColl = Read-PathWithBrowse "  Path to collection dat file" -Mode File -FileFilter "dat files (*.dat)|*.dat|All files (*.*)|*.*"
        if ($rawColl) {
            if (Test-Path -LiteralPath $rawColl) {
                $datFilePath = $rawColl
                Write-Log "Config: datFilePath (collection) set to $rawColl"
                Write-Host "  Supplementary dat (press Enter to skip):" -ForegroundColor DarkCyan
                $rawSupp = Read-PathWithBrowse "  Path to supplementary dat file" -Mode File -FileFilter "dat files (*.dat)|*.dat|All files (*.*)|*.*"
                if ($rawSupp) {
                    if (Test-Path -LiteralPath $rawSupp) {
                        $supplementaryDatPath = $rawSupp
                        $includeSupplementary = $true
                        Write-Log "Config: supplementaryDatPath set to $rawSupp"
                    } else {
                        Write-Host "  WARNING: Supplementary dat not found -- skipped." -ForegroundColor Yellow
                        Write-Log "Config: supplementary dat not found at $rawSupp -- skipped."
                    }
                }
            } else {
                Write-Host "  WARNING: Collection dat not found -- dat skipped." -ForegroundColor Yellow
                Write-Log "Config: collection dat not found at $rawColl -- skipped."
            }
        }
    }
} elseif ($eggmanDatZip -and -not $Unattended) {
    # A dat ZIP is already configured -- offer a lightweight check for a
    # newer release instead of silently reusing the same file forever.
    # Direct .dat file mode ($datFilePath) has no GitHub release counterpart
    # to check against, so this only applies to ZIP mode.
    Write-Host ""
    $checkUpdate = (Read-Host "Check for a newer Eggman dat release? (Y/N)").Trim().ToUpper()
    if ($checkUpdate -eq 'Y') {
        Write-Host "  Checking GitHub for latest Eggman dat release..." -ForegroundColor Cyan
        $rel = Get-EggmanDatRelease
        if ($null -eq $rel) {
            Write-Host "  Could not reach GitHub -- keeping your current dat file." -ForegroundColor Yellow
        } else {
            $currentSizeMB = if (Test-Path -LiteralPath $eggmanDatZip) { [Math]::Round((Get-Item -LiteralPath $eggmanDatZip).Length / 1MB, 1) } else { 0 }
            Write-Host ("  Latest available : {0}  ({1} MB)" -f $rel.FileName, $rel.SizeMB) -ForegroundColor Cyan
            Write-Host ("  Currently using  : {0}  ({1} MB)" -f (Split-Path -Leaf $eggmanDatZip), $currentSizeMB) -ForegroundColor Cyan
            $doUpdate = (Read-Host "  Download and switch to the latest release? (Y/N)").Trim().ToUpper()
            if ($doUpdate -eq 'Y') {
                $savedPath = Invoke-EggmanDatDownloadInteractive $rel
                if ($savedPath) {
                    $eggmanDatZip = $savedPath
                    Write-Host "  Updated: $savedPath" -ForegroundColor Green
                    Write-Log "EggmanDat: updated to $savedPath"
                    [void](Save-Config)
                } else {
                    Write-Host "  Download failed -- keeping your current dat file." -ForegroundColor Yellow
                }
            }
        }
    }
}

# =============================================================================
# SECTION 2 -- Validate TeknoParrot root, locate GameProfiles and UserProfiles
# =============================================================================

if (-not (Test-Path -LiteralPath $tpRoot)) {
    Write-Host ""; Write-Host "ERROR: TeknoParrot root folder not found: $tpRoot" -ForegroundColor Red
    Write-Log "ERROR: TeknoParrot root not found."; exit 1
}

# TeknoParrot's launcher is TeknoParrotUi.exe (Windows path checks are
# case-insensitive, so this also matches TeknoParrotUI.exe).
$tpExe = Join-Path $tpRoot "TeknoParrotUi.exe"
if (-not (Test-Path -LiteralPath $tpExe)) {
    Write-Host ""; Write-Host "ERROR: TeknoParrotUi.exe not found in: $tpRoot" -ForegroundColor Red
    Write-Host "Make sure the path points to the TeknoParrot root folder." -ForegroundColor Yellow
    Write-Log "ERROR: TeknoParrotUi.exe not found."; exit 1
}

$gameProfilesDir = Join-Path $tpRoot "GameProfiles"
if (-not (Test-Path -LiteralPath $gameProfilesDir)) {
    Write-Host ""; Write-Host "ERROR: GameProfiles folder not found in: $tpRoot" -ForegroundColor Red
    Write-Host "This folder ships with TeknoParrot and is required to register games." -ForegroundColor Yellow
    Write-Host "Run TeknoParrotUi.exe once and let it complete its updates, then retry." -ForegroundColor Yellow
    Write-Log "ERROR: GameProfiles folder not found."; exit 1
}

$userProfilesDir = Join-Path $tpRoot "UserProfiles"
if (-not (Test-Path -LiteralPath $userProfilesDir)) {
    try {
        [void][System.IO.Directory]::CreateDirectory($userProfilesDir)
    } catch {
        Write-Host ""; Write-Host "ERROR: Could not create UserProfiles folder: $_" -ForegroundColor Red
        Write-Log "ERROR: Could not create UserProfiles folder -- $_"; exit 1
    }
}

Write-Log "Validated. tpRoot=$tpRoot install=$gamesInstallFolder"

# =============================================================================
# SECTION 4 -- Save configuration
# =============================================================================

if (-not (Save-Config)) {
    Write-Host "  WARNING: Could not save configuration -- settings will not be remembered." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Green
Write-Host "  TeknoParrot root     : $tpRoot"
if ($zipSource)               { Write-Host "  ZIP source folder    : $zipSource" }
if ($zipSourceSupplementary)  { Write-Host "  ZIP supplementary    : $zipSourceSupplementary" }
Write-Host "  Games install folder : $gamesInstallFolder"
if ($retroBat)             { Write-Host "  RetroBat mode        : Yes (*.teknoparrot / *.parrot / *.game recognised)" -ForegroundColor Cyan }
if ($eggmanDatZip)         { Write-Host "  Eggman dat ZIP       : $eggmanDatZip" }
elseif ($datFilePath)      { Write-Host "  Collection dat       : $datFilePath" }
if ($supplementaryDatPath) { Write-Host "  Supplementary dat    : $supplementaryDatPath" }
elseif ($includeSupplementary -and $eggmanDatZip) { Write-Host "  Supplementary index  : Yes (from ZIP)" }

# =============================================================================
# SECTION 4b -- Per-game overrides  (TeknoParrot-Manager.overrides.json)
# =============================================================================
# Created empty on first run. Edit with any text editor to fine-tune behaviour:
#   noSync         : ZIP base names to always skip during extraction.
#   onlySync       : Whitelist -- if non-empty, only these ZIPs are extracted
#                    (bypasses the interactive picker; useful for scripted runs).
#   noPropagate    : Profile codes to leave untouched during propagation.
#   forceArchetype : { "ProfileCode": "ArchetypeCode" } -- pin a game to a
#                    specific archetype instead of the automatic best match.
#   familyOverride : { "ProfileCode": "family" } -- override the auto-detected
#                    control family. Valid values: button, driving, lightgun,
#                    trackball, analog, spinner. Fixes mis-classified titles
#                    (e.g. FamilyGuyBowling detected as lightgun; set "trackball").
#   canonicalArchetype : { "family": "ProfileCode" } -- the one archetype in
#                    that family whose Input API is treated as correct. An
#                    archetype is otherwise never modified (see issue #1);
#                    this is the one explicit, user-chosen exception -- every
#                    OTHER archetype in that same family gets its own Input
#                    API corrected to match the designated one, if different.
#                    Deliberately NOT a heuristic guess (v0.99.12 tried
#                    guessing via best button-overlap and broke a real
#                    tester's library by cross-correcting independently
#                    correct archetypes against each other -- reverted in
#                    v0.99.14). Leave unset for a family to never correct
#                    any archetype in it.

$overridesPath         = Join-Path $PSScriptRoot "TeknoParrot-Manager.overrides.json"
$noSyncList            = @()
$onlySyncList          = @()
$noPropagateList       = @()
$forceArchetypeMap     = @{}
$familyOverrideMap     = @{}
$canonicalArchetypeMap = @{}
$subFolderMap          = @{}
$validFamilies         = @('button','driving','lightgun','trackball','analog','spinner')

if (-not (Test-Path -LiteralPath $overridesPath)) {
    $ovTemplate = [ordered]@{
        _comment           = "noSync/onlySync/noPropagate: lists of ZIP base names (without .zip). onlySync acts as a whitelist -- only listed games are extracted. forceArchetype: { GameCode: ArchetypeCode } pins a game to a specific reference game. familyOverride: { GameCode: 'button'|'driving'|'lightgun'|'trackball'|'analog' } overrides the auto-detected control family (fixes mis-classified games like FamilyGuyBowling). canonicalArchetype: { family: ArchetypeCode } the one archetype per family whose Input API is treated as correct -- every other archetype in that family gets its Input API corrected to match it. subFolderMap: { ProfileCode: 'relative\\subpath' } for games whose executable lives in a specific subfolder of the TeknoParrot root rather than in the staging folder (e.g. CrediarDolphin titles). datFile: full path to a No-Intro TeknoParrot dat file; when set the script uses it to auto-register games with shared executable names (like game.exe) without needing fuzzy matching."
        noSync             = @()
        onlySync           = @()
        noPropagate        = @()
        forceArchetype     = [ordered]@{}
        familyOverride     = [ordered]@{}
        canonicalArchetype = [ordered]@{}
        subFolderMap       = [ordered]@{}
        datFile            = ""
    }
    try { [System.IO.File]::WriteAllText($overridesPath, ($ovTemplate | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding $false)) }
    catch { Write-Log "Overrides: could not create template -- $_" }
}

if (Test-Path -LiteralPath $overridesPath) {
    try {
        $ov = Get-Content -LiteralPath $overridesPath -Raw | ConvertFrom-Json
        if ($ov.noSync)      { $noSyncList      = @($ov.noSync) }
        if ($ov.onlySync)    { $onlySyncList    = @($ov.onlySync) }
        if ($ov.noPropagate) { $noPropagateList = @($ov.noPropagate) }
        if ($ov.forceArchetype) {
            foreach ($p in $ov.forceArchetype.PSObject.Properties) { $forceArchetypeMap[$p.Name] = [string]$p.Value }
        }
        if ($ov.familyOverride) {
            foreach ($p in $ov.familyOverride.PSObject.Properties) {
                $fv = [string]$p.Value
                if ($validFamilies -contains $fv) {
                    $familyOverrideMap[$p.Name] = $fv
                } else {
                    Write-Host ("  WARNING: familyOverride for '{0}' has unknown family '{1}' -- ignored." -f $p.Name, $fv) -ForegroundColor Yellow
                    Write-Log "Overrides: familyOverride '$($p.Name)' has unknown value '$fv' -- ignored."
                }
            }
        }
        if ($ov.canonicalArchetype) {
            foreach ($p in $ov.canonicalArchetype.PSObject.Properties) {
                $fam = $p.Name
                if ($validFamilies -contains $fam) {
                    $canonicalArchetypeMap[$fam] = [string]$p.Value
                } else {
                    Write-Host ("  WARNING: canonicalArchetype has unknown family '{0}' -- ignored." -f $fam) -ForegroundColor Yellow
                    Write-Log "Overrides: canonicalArchetype has unknown family '$fam' -- ignored."
                }
            }
        }
        if ($ov.subFolderMap) {
            foreach ($p in $ov.subFolderMap.PSObject.Properties) { $subFolderMap[$p.Name] = [string]$p.Value }
        }
        if ($ov.datFile -and -not [string]::IsNullOrWhiteSpace([string]$ov.datFile)) {
            $datFilePath = [string]$ov.datFile
        }
        $ovCount = $noSyncList.Count + $onlySyncList.Count + $noPropagateList.Count + $forceArchetypeMap.Count + $familyOverrideMap.Count + $canonicalArchetypeMap.Count + $subFolderMap.Count
        if ($ovCount -gt 0 -or $datFilePath) {
            Write-Host ""
            $datLabel = if ($datFilePath) { ", datFile=yes" } else { "" }
            $sfmLabel = if ($subFolderMap.Count -gt 0) { ", subFolderMap=$($subFolderMap.Count)" } else { "" }
            Write-Host "Overrides: noSync=$($noSyncList.Count), onlySync=$($onlySyncList.Count), noPropagate=$($noPropagateList.Count), pinned=$($forceArchetypeMap.Count), familyOverride=$($familyOverrideMap.Count), canonicalArchetype=$($canonicalArchetypeMap.Count)$sfmLabel$datLabel" -ForegroundColor DarkCyan
        }
        Write-Log "Overrides: noSync=$($noSyncList.Count) onlySync=$($onlySyncList.Count) noPropagate=$($noPropagateList.Count) pinned=$($forceArchetypeMap.Count) familyOverride=$($familyOverrideMap.Count) canonicalArchetype=$($canonicalArchetypeMap.Count) subFolderMap=$($subFolderMap.Count) datFile=$datFilePath"
    } catch {
        Write-Host "WARNING: could not read TeknoParrot-Manager.overrides.json; ignoring overrides." -ForegroundColor Yellow
        Write-Log "Overrides: parse error -- ignoring."
    }
}

# =============================================================================
# DAT FILE INDEX  (loaded once before the menu loop; reused each run)
# Priority: EggmanDatZip (ZIP mode) > DatFilePath (direct file mode)
# =============================================================================

$datIndex   = @{}
$suppIndex  = @{}   # supplementary dat index: normalizedName -> {ProfileCode, Executable}
$suppCodes  = New-Object 'System.Collections.Generic.HashSet[string]'([StringComparer]::OrdinalIgnoreCase)
$notesIndex = @{}   # game notes index: ProfileCode.ToLower() -> notes text string

if ($eggmanDatZip) {
    if (Test-Path -LiteralPath $eggmanDatZip) {
        Write-Host ""
        Write-Host "Loading collection dat from ZIP..." -ForegroundColor DarkGray
        $datIndex = Build-DatIndexFromZip $eggmanDatZip
        if ($datIndex.Count -gt 0) {
            Write-Host ("  Collection dat: {0} games indexed." -f $datIndex.Count) -ForegroundColor DarkGray
            Write-Log "DatIndex (ZIP): $($datIndex.Count) entries from $eggmanDatZip"
        } else {
            Write-Host "  Collection dat: no entries found -- check ZIP contains a *Collection*_RomVault*.dat entry." -ForegroundColor Yellow
            Write-Log "DatIndex (ZIP): 0 entries from $eggmanDatZip."
        }
        if ($includeSupplementary) {
            Write-Host "  Loading supplementary dat from ZIP..." -ForegroundColor DarkGray
            $suppIndex = Build-DatIndexFromZip $eggmanDatZip '*Supplementary*_RomVault*.dat'
            if ($suppIndex.Count -gt 0) {
                Write-Host ("  Supplementary dat: {0} entries indexed (override collection)." -f $suppIndex.Count) -ForegroundColor DarkGray
                Write-Log "SuppIndex (ZIP): $($suppIndex.Count) entries from $eggmanDatZip"
            } else {
                Write-Host "  Supplementary dat: no entries found." -ForegroundColor Yellow
                Write-Log "SuppIndex (ZIP): 0 entries from $eggmanDatZip."
            }
        }
        Write-Host "  Loading game notes from ZIP..." -ForegroundColor DarkGray
        $notesIndex = Build-GameNotesIndexFromZip $eggmanDatZip
        if ($notesIndex.Count -gt 0) {
            Write-Host ("  Game notes: {0} entries indexed." -f $notesIndex.Count) -ForegroundColor DarkGray
            Write-Log "NotesIndex (ZIP): $($notesIndex.Count) entries from $eggmanDatZip"
        }
    } else {
        Write-Host ("  WARNING: Eggman dat ZIP not found at: {0}" -f $eggmanDatZip) -ForegroundColor Yellow
        Write-Log "DatIndex (ZIP): file not found at $eggmanDatZip -- skipping."
    }
} elseif ($datFilePath) {
    if (Test-Path -LiteralPath $datFilePath) {
        Write-Host ""
        Write-Host "Loading collection dat..." -ForegroundColor DarkGray
        $datIndex = Build-DatIndex $datFilePath
        if ($datIndex.Count -gt 0) {
            Write-Host ("  Collection dat: {0} games indexed." -f $datIndex.Count) -ForegroundColor DarkGray
            Write-Log "DatIndex: $($datIndex.Count) entries from $datFilePath"
        } else {
            Write-Host "  Collection dat: no entries found -- check that the file has <GameProfile> elements." -ForegroundColor Yellow
            Write-Log "DatIndex: 0 entries from $datFilePath -- file parsed but no valid game entries found."
        }
        if ($supplementaryDatPath) {
            if (Test-Path -LiteralPath $supplementaryDatPath) {
                Write-Host "  Loading supplementary dat..." -ForegroundColor DarkGray
                $suppIndex = Build-DatIndex $supplementaryDatPath
                if ($suppIndex.Count -gt 0) {
                    Write-Host ("  Supplementary dat: {0} entries indexed (override collection)." -f $suppIndex.Count) -ForegroundColor DarkGray
                    Write-Log "SuppIndex: $($suppIndex.Count) entries from $supplementaryDatPath"
                } else {
                    Write-Host "  Supplementary dat: no entries found." -ForegroundColor Yellow
                    Write-Log "SuppIndex: 0 entries from $supplementaryDatPath."
                }
            } else {
                Write-Host ("  WARNING: Supplementary dat not found at: {0}" -f $supplementaryDatPath) -ForegroundColor Yellow
                Write-Log "SuppIndex: file not found at $supplementaryDatPath -- skipping."
            }
        }
        # Look for a notes text file alongside the dat (e.g. extracted from the ZIP)
        $notesCandidate = Get-ChildItem -LiteralPath ([System.IO.Path]::GetDirectoryName($datFilePath)) `
                              -Filter '*.txt' -File -ErrorAction SilentlyContinue |
                          Where-Object { $_.Name -ilike '*note*' } |
                          Select-Object -First 1 -ExpandProperty FullName
        if ($notesCandidate) {
            Write-Host "  Loading game notes..." -ForegroundColor DarkGray
            $notesIndex = Build-GameNotesIndex $notesCandidate
            if ($notesIndex.Count -gt 0) {
                Write-Host ("  Game notes: {0} entries indexed." -f $notesIndex.Count) -ForegroundColor DarkGray
                Write-Log "NotesIndex: $($notesIndex.Count) entries from $notesCandidate"
            }
        }
    } else {
        Write-Host ("  WARNING: Collection dat not found at: {0}" -f $datFilePath) -ForegroundColor Yellow
        Write-Log "DatIndex: file not found at $datFilePath -- skipping."
    }
}

# Merge supplementary overrides into the collection index.
# Supplementary entries take precedence for the same normalised game name,
# so the alternate version from the supplementary dat is used instead of
# the collection version (only one version can be installed at a time).
if ($suppIndex.Count -gt 0) {
    foreach ($k in $suppIndex.Keys) {
        $datIndex[$k] = $suppIndex[$k]
        [void]$suppCodes.Add($suppIndex[$k].ProfileCode)
    }
    Write-Log "DatIndex: merged $($suppIndex.Count) supplementary overrides ($($suppCodes.Count) profile codes)."
}

# =============================================================================
# PROFILE SET  (fetched once; used by Resolve-ProfileCode during registration)
# =============================================================================
$profileSet = $null
if ($datIndex.Count -gt 0 -and $gameProfilesDir) {
    Write-Host ""
    Write-Host "Loading TeknoParrot GameProfiles list..." -ForegroundColor DarkGray
    $profileSet = Get-TeknoParrotProfileSet $gameProfilesDir
    if ($profileSet.Count -gt 0) {
        Write-Host ("  Profile set: {0} profiles (used for dat code resolution)." -f $profileSet.Count) -ForegroundColor DarkGray
    } else {
        Write-Host "  Profile set: could not load (GitHub unreachable and GameProfiles folder empty)." -ForegroundColor Yellow
    }
}

# =============================================================================
# MAIN MENU LOOP
# =============================================================================
try {
while ($true) {
    # Refresh the drive-info snapshot at the start of each menu iteration so
    # any drive changes since the last pass (USB ejected, network share
    # reconnected to a different letter) are picked up rather than using
    # stale cached data from the previous mode's run.
    Clear-LocalDriveInfoCache
    $mode = $null

    # A just-finished preview run's "Apply for real now?" prompt was
    # answered Y -- silently re-enter the same mode instead of showing
    # the menu again, and force a real (non-preview) pass this time.
    if ($pendingApplyMode) {
        $mode = $pendingApplyMode
        $pendingApplyMode = $null
        $forceRealApply = $true
    }
    if ($mode) {
        # Skip straight past the menu -- fall through to the mode body below.
    } else {
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " Mode" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host "  1) AutoSync        -- Extract ZIPs (NAS or local) to a local"
    Write-Host "                        folder, then register the games."
    Write-Host "  2) Register only   -- Games are already extracted; just register."
    Write-Host "  3) Crosshair setup -- Pick and deploy custom crosshairs to all"
    Write-Host "                        registered lightgun games."
    Write-Host "  4) ReShade setup   -- Add visual enhancements (sharper image, better"
    Write-Host "                        colours, scanlines, borders). Optional -- games"
    Write-Host "                        work perfectly without this."
    Write-Host "  5) dgVoodoo2 setup -- Fix old DX8, DirectDraw, and Glide games that"
    Write-Host "                        crash or show black screens. Optional."
    Write-Host "  6) GPU fix setup   -- Auto-detect your GPU (AMD / NVIDIA / Intel) and"
    Write-Host "                        apply the matching compatibility fix to every"
    Write-Host "                        registered game that has one. Optional."
    Write-Host "  7) Force feedback (FFB) setup -- Wheel/stick rumble and force feedback."
    Write-Host "                        Covers TeknoParrot's built-in FFB Blaster (needs a"
    Write-Host "                        paid membership) and a free third-party plugin."
    Write-Host "  8) BepInEx update check -- Checks games with BepInEx already installed"
    Write-Host "                        against the latest stable release and offers to"
    Write-Host "                        update (64-bit only). Never installs it fresh."
    Write-Host "  9) Restore backup  -- Roll UserProfiles back to a previous backup."
    Write-Host "  10) Library health check -- Read-only: reports registered/broken/"
    Write-Host "                        unregistered counts plus GPU fix / FFB Blaster /"
    Write-Host "                        dgVoodoo2 coverage and ReShade/BepInEx install"
    Write-Host "                        counts. No extraction, registration, repair, or"
    Write-Host "                        network access -- just a fast status check."
    Write-Host "  11) Postgres setup -- Installs/configures the local PostgreSQL"
    Write-Host "                        database that some Incredible Technologies"
    Write-Host "                        games need (Golden Tee Live, Power Putt Live,"
    Write-Host "                        Silver Strike Bowling Live, Target Toss Pro)."
    Write-Host "                        Requires running this script as Administrator"
    Write-Host "                        if PostgreSQL isn't installed yet."
    Write-Host "  12) Exit"
    Write-Host ""
    if ($Unattended) {
        Write-Host "  [Unattended] Mode must be set before starting." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- reached menu loop."; exit 1
    }
    $modeChoice = (Read-Host "Enter 1-12").Trim()
    switch ($modeChoice) {
        "1"     { $mode = "AutoSync"       }
        "2"     { $mode = "RegisterOnly"   }
        "3"     { $mode = "CrosshairSetup" }
        "4"     { $mode = "ReShadeSetup"   }
        "5"     { $mode = "DgVoodoo2Setup" }
        "6"     { $mode = "GpuFixSetup"    }
        "7"     { $mode = "FFBSetup"       }
        "8"     { $mode = "BepInExUpdate"  }
        "9"     { $mode = "Restore"        }
        "10"    { $mode = "HealthCheck"    }
        "11"    { $mode = "PostgresSetup"  }
        "12"    { break }
        default { Write-Host "  Invalid choice. Enter 1-12." -ForegroundColor Yellow; continue }
    }
    if ($modeChoice -eq "12") { break }
    }

    if ($mode -eq "Restore") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " Restore from Backup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host "  1) TeknoParrot UserProfiles backup"
        Write-Host "  2) LaunchBox library backup (only relevant if you've used the"
        Write-Host "     direct LaunchBox integration)"
        Write-Host "  3) Postgres database backup (only relevant if you've used the"
        Write-Host "     Postgres setup mode)"
        $restoreChoice = (Read-Host "  Enter 1-3").Trim()
        if ($restoreChoice -eq "2") {
            if (-not $lbRoot) {
                Write-Host "  No LaunchBox root is configured yet -- nothing to restore." -ForegroundColor Yellow
            } else {
                Invoke-RestoreLaunchBoxBackup -lbRoot $lbRoot
            }
        } elseif ($restoreChoice -eq "3") {
            Invoke-RestorePostgresBackup
        } else {
            Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        }
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "   Done." -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Log "Restore complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "HealthCheck") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " Library Health Check (read-only)" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Invoke-LibraryHealthCheck -UserProfilesDir $userProfilesDir -LogPath $logPath -TpRoot $tpRoot
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "   Done." -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Log "Health check complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "PostgresSetup") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " PostgreSQL Setup (Incredible Technologies games)" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan

        Write-Host "  Scanning registered games for Postgres requirements..." -ForegroundColor DarkGray
        $needCount = 0
        $pgProfiles = Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
                          Where-Object { $_.Directory.Name -ne "FullBackup" }
        foreach ($pf in $pgProfiles) {
            try {
                $doc = Read-Xml $pf.FullName
                if ($doc.GameProfile -and (Test-GameNeedsPostgres $doc)) { $needCount++ }
            } catch {}
        }

        if ($needCount -eq 0) {
            Write-Host "  No registered games need PostgreSQL -- nothing to do." -ForegroundColor Green
            Write-Log "Postgres setup: no Postgres-needing games registered."
            [void](Read-Host "  Press Enter to return to menu")
            continue
        }

        Write-Host ("  {0} registered game(s) need PostgreSQL." -f $needCount) -ForegroundColor Cyan

        if (-not (Test-PostgresInstalled) -and -not (Test-RunningAsAdministrator)) {
            Write-Host ""
            Write-Host "  PostgreSQL is not installed yet, and installing it requires" -ForegroundColor Red
            Write-Host "  Administrator privileges (it creates a Windows service and a" -ForegroundColor Red
            Write-Host "  Windows user account)." -ForegroundColor Red
            Write-Host ""
            Write-Host "  Close this window and re-run TeknoParrot Manager as Administrator" -ForegroundColor Yellow
            Write-Host "  (right-click TeknoParrot-Manager.bat -> Run as administrator), then" -ForegroundColor Yellow
            Write-Host "  choose this mode again." -ForegroundColor Yellow
            Write-Log "Postgres setup: aborted -- PostgreSQL not installed and not running as Administrator."
            [void](Read-Host "  Press Enter to return to menu")
            continue
        }

        $superPwPlain = $null
        if (Test-PostgresInstalled) {
            Write-Host "  PostgreSQL is already installed -- it will not be reinstalled or modified." -ForegroundColor Green
            if ($postgresSuperPasswordEncrypted) {
                try {
                    $secure = ConvertTo-SecureString -String $postgresSuperPasswordEncrypted
                    $savedPwPlain = ConvertFrom-SecureStringPlain $secure
                    if (Test-PostgresPassword $savedPwPlain) {
                        $superPwPlain = $savedPwPlain
                    } else {
                        Write-Log "Postgres setup: saved password no longer works -- will re-prompt."
                    }
                } catch {
                    Write-Log "Postgres setup: could not decrypt saved password -- $_"
                }
            }
            if (-not $superPwPlain) {
                Write-Host "  Enter your existing PostgreSQL database password to continue:" -ForegroundColor Cyan
                $superPwSecure  = Read-Host "  Password" -AsSecureString
                $typedPwPlain   = ConvertFrom-SecureStringPlain $superPwSecure
                if (-not (Test-PostgresPassword $typedPwPlain)) {
                    Write-Host "  ERROR: That password did not work against your PostgreSQL server." -ForegroundColor Red
                    Write-Log "Postgres setup: aborted -- password verification failed."
                    [void](Read-Host "  Press Enter to return to menu")
                    continue
                }
                $superPwPlain = $typedPwPlain
                $postgresSuperPasswordEncrypted = ConvertTo-PostgresEncryptedPassword $superPwPlain
                if (Save-Config) { Write-Log "Postgres setup: saved (encrypted) password for future runs." }
            }
        } else {
            $outPw = [ref]$null
            if (-not (Install-Postgres83 -OutSuperPasswordPlain $outPw)) {
                Write-Host "  PostgreSQL setup did not complete -- see TeknoParrot-Manager.log." -ForegroundColor Red
                [void](Read-Host "  Press Enter to return to menu")
                continue
            }
            $superPwPlain = $outPw.Value
            $postgresSuperPasswordEncrypted = ConvertTo-PostgresEncryptedPassword $superPwPlain
            if (Save-Config) { Write-Log "Postgres setup: saved (encrypted) database password." }
        }

        Write-Host ""
        Write-Host "  Backing up existing Postgres databases..." -ForegroundColor Cyan
        $pgBackupPath = Backup-PostgresDatabases -UserProfilesDir $userProfilesDir -SuperPasswordPlain $superPwPlain
        if ($pgBackupPath) {
            Write-Host ("  Backup saved : {0}" -f $pgBackupPath) -ForegroundColor DarkCyan
        } else {
            Write-Host "  No existing databases to back up yet." -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "  Configuring games and creating any missing databases..." -ForegroundColor Cyan
        $pgResults = Invoke-PostgresGameSetup -UserProfilesDir $userProfilesDir -SuperPasswordPlain $superPwPlain
        $superPwPlain = $null
        [GC]::Collect()

        Write-Host ""
        Write-Host "  Results:" -ForegroundColor Cyan
        Write-Host ("    Fields updated         : {0}" -f $pgResults.Configured) -ForegroundColor Green
        Write-Host ("    Databases created      : {0}" -f $pgResults.DbCreated) -ForegroundColor Green
        Write-Host ("    Already configured     : {0}" -f $pgResults.AlreadyConfigured) -ForegroundColor DarkGray
        if ($pgResults.Errors -gt 0) {
            Write-Host ("    Errors                 : {0}  (see TeknoParrot-Manager.log)" -f $pgResults.Errors) -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "  If anything looks wrong, use menu option 9 (Restore backup) ->" -ForegroundColor DarkCyan
        Write-Host "  Postgres database backup to undo database changes." -ForegroundColor DarkCyan
        Write-Log ("Postgres setup: complete. Configured={0} DbCreated={1} AlreadyConfigured={2} Errors={3}" -f $pgResults.Configured, $pgResults.DbCreated, $pgResults.AlreadyConfigured, $pgResults.Errors)
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "CrosshairSetup") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " Crosshair Setup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Invoke-CrosshairSetup -UserProfilesDir $userProfilesDir `
                              -GamesInstallFolder $gamesInstallFolder `
                              -TpRoot $tpRoot
        Write-Host ""
        Write-Host "Done." -ForegroundColor Green
        Write-Log "Crosshair setup complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "ReShadeSetup") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " ReShade Visual Enhancements Setup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        $bundledDll   = Join-Path $PSScriptRoot "ReShade\ReShade64.dll"
        $bundledDll32 = Join-Path $PSScriptRoot "ReShade\ReShade32.dll"
        if (-not $rsSourceDll -or -not (Test-Path -LiteralPath $rsSourceDll)) {
            if (Test-Path -LiteralPath $bundledDll) {
                $rsSourceDll = $bundledDll
            } else {
                Write-Host ""
                Write-Host "  ReShade 64-bit DLL not found." -ForegroundColor Yellow
                Write-Host "  To get it:" -ForegroundColor Cyan
                Write-Host "    1. Download the installer from  https://reshade.me" -ForegroundColor White
                Write-Host "    2. Run it and point it at any TeknoParrot game exe." -ForegroundColor White
                Write-Host "       It creates a DLL (e.g. dxgi.dll) in that game folder." -ForegroundColor White
                Write-Host "    3. Copy that DLL to  $PSScriptRoot\ReShade\  and name it  ReShade64.dll" -ForegroundColor White
                Write-Host "       Then re-run this script." -ForegroundColor White
                Write-Host "    -- OR --" -ForegroundColor DarkCyan
                Write-Host "    Enter the full path to the DLL file now:" -ForegroundColor White
                Write-Host ""
                $inp = Read-PathWithBrowse "  Path to ReShade 64-bit DLL (or press Enter to cancel)" -Mode File -FileFilter "DLL files (*.dll)|*.dll|All files (*.*)|*.*"
                if ([string]::IsNullOrWhiteSpace($inp) -or -not (Test-Path -LiteralPath $inp)) {
                    Write-Host "  File not found. ReShade setup cancelled." -ForegroundColor Red
                    Write-Log "ReShade setup: aborted -- DLL not found."
                    [void](Read-Host "  Press Enter to return to menu")
                    continue
                }
                if ([System.IO.Path]::GetExtension($inp).ToLower() -ne '.dll') {
                    Write-Host "  That file does not appear to be a DLL. Cancelled." -ForegroundColor Red
                    Write-Log "ReShade setup: aborted -- file is not a .dll."
                    [void](Read-Host "  Press Enter to return to menu")
                    continue
                }
                $rsSourceDll = $inp
            }
            if (Save-Config) {
                Write-Log "Config: saved ReShadeSourceDll = $rsSourceDll"
            } else {
                Write-Log "Config: could not save ReShadeSourceDll"
            }
        }
        if (-not $rsSourceDll32 -or -not (Test-Path -LiteralPath $rsSourceDll32)) {
            if (Test-Path -LiteralPath $bundledDll32) { $rsSourceDll32 = $bundledDll32 }
        }
        Invoke-ReShadeSetup -UserProfilesDir $userProfilesDir `
                            -SourceDll $rsSourceDll `
                            -SourceDll32 $rsSourceDll32 `
                            -ConfigPath $configPath `
                            -TpRoot $tpRoot `
                            -Mode $mode `
                            -ZipSource $zipSource `
                            -GamesInstallFolder $gamesInstallFolder `
                            -RetroBat $retroBat `
                            -HsDataPath $hsDataPath
        Write-Host ""
        Write-Host "Done." -ForegroundColor Green
        Write-Log "ReShade setup complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "DgVoodoo2Setup") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " dgVoodoo2 Legacy Compatibility Setup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        $bundledDg = Join-Path $PSScriptRoot "dgVoodoo2"
        if (-not $dgSourceDir -or -not (Test-Path -LiteralPath $dgSourceDir)) {
            if (Test-Path -LiteralPath $bundledDg) {
                $dgSourceDir = $bundledDg
            } else {
                Write-Host ""
                Write-Host "  dgVoodoo2 DLL folder not found." -ForegroundColor Yellow
                Write-Host "  To get dgVoodoo2:" -ForegroundColor Cyan
                Write-Host "    1. Download the latest ZIP from  https://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/" -ForegroundColor White
                Write-Host "    2. Open the ZIP and copy these files into a new folder called  dgVoodoo2\" -ForegroundColor White
                Write-Host "       next to this script:" -ForegroundColor White
                Write-Host "         From the MS\x86\ subfolder : D3D8.dll  DDraw.dll  D3DImm.dll" -ForegroundColor White
                Write-Host "         From the 3Dfx\x86\ subfolder : Glide2x.dll  Glide3x.dll" -ForegroundColor White
                Write-Host "         From the root of the ZIP   : dgVoodoo.conf" -ForegroundColor White
                Write-Host "       Then re-run this script." -ForegroundColor White
                Write-Host "    -- OR --" -ForegroundColor DarkCyan
                Write-Host "    Enter the full path to a folder that already contains those files:" -ForegroundColor White
                Write-Host ""
                $inp = Read-PathWithBrowse "  Path to dgVoodoo2 folder (or press Enter to cancel)"
                if ([string]::IsNullOrWhiteSpace($inp) -or -not (Test-Path -LiteralPath $inp)) {
                    Write-Host "  Folder not found. dgVoodoo2 setup cancelled." -ForegroundColor Red
                    Write-Log "dgVoodoo2 setup: aborted -- folder not found."
                    [void](Read-Host "  Press Enter to return to menu")
                    continue
                }
                $dgSourceDir = $inp
            }
            if (Save-Config) {
                Write-Log "Config: saved DgVoodoo2SourceDir = $dgSourceDir"
            } else {
                Write-Log "Config: could not save DgVoodoo2SourceDir"
            }
        }
        Invoke-DgVoodoo2Setup -UserProfilesDir $userProfilesDir `
                              -SourceDir $dgSourceDir `
                              -TpRoot $tpRoot
        Write-Host ""
        Write-Host "Done." -ForegroundColor Green
        Write-Log "dgVoodoo2 setup complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "GpuFixSetup") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " GPU Compatibility Fix Setup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  This scans your registered games and applies the correct GPU"
        Write-Host "  compatibility fix for your graphics card to each profile that"
        Write-Host "  supports one. It is safe to re-run any time you update your GPU"
        Write-Host "  drivers or switch to a new card."
        Invoke-GpuFixSetup -UserProfilesDir $userProfilesDir `
                           -TpRoot $tpRoot
        Write-Host ""
        Write-Host "Done." -ForegroundColor Green
        Write-Log "GPU fix setup complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "FFBSetup") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " Force Feedback (FFB) Setup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Force feedback makes a wheel or stick push back / rumble to match"
        Write-Host "  what's happening on screen (e.g. road vibration, recoil, collisions)."
        Write-Host "  Two independent ways to get it, covering different games -- both can"
        Write-Host "  be set up, neither requires the other:"
        Write-Host ""
        Write-Host "    1) FFB Blaster -- TeknoParrot's own built-in force feedback."
        Write-Host "       Native and well-integrated, but requires an active paid"
        Write-Host "       TeknoParrot membership (teknoparrot.com/en/Home/Subscription)."
        Write-Host "    2) Third-party FFB plugin -- a free, separately-maintained DLL"
        Write-Host "       (mightymikem/FFBArcadePlugin) that adds force feedback to a"
        Write-Host "       different set of arcade titles. No subscription needed."
        Write-Host ""
        Write-Host "  If a game is covered by both, you'll be asked which one to use for it."

        $nativeEnabledCodes = Invoke-FFBBlasterSetup -UserProfilesDir $userProfilesDir -TpRoot $tpRoot

        Write-Host ""
        $doFfbPlugin = (Read-Host "  Also set up the free third-party FFB plugin (covers additional games)? (Y/N)").Trim().ToUpper()
        if ($doFfbPlugin -eq "Y") {
            $ffbCacheDir = Join-Path $PSScriptRoot "FFBPlugin"
            Invoke-FFBPluginSetup -UserProfilesDir $userProfilesDir -CacheDir $ffbCacheDir -NativeEnabledCodes $nativeEnabledCodes
        } else {
            Write-Log "FFBPlugin setup: skipped by user choice."
        }

        Write-Host ""
        Write-Host "Done." -ForegroundColor Green
        Write-Log "FFB setup complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    if ($mode -eq "BepInExUpdate") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " BepInEx Update Check" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  BepInEx is a third-party Unity plugin/modding framework. Some"
        Write-Host "  TeknoParrot games need it for controls or fixes to work via a"
        Write-Host "  community plugin." -NoNewline
        $requiredGames = Get-BepInExRequiredGames
        if ($requiredGames.Count -gt 0) {
            Write-Host " Known examples:"
            $lineLen = 70; $line = "    "; $firstR = $true
            foreach ($g in $requiredGames) {
                $add = if ($firstR) { $g } else { ", $g" }
                if (($line + $add).Length -gt $lineLen) {
                    Write-Host $line -ForegroundColor White
                    $line = "    $g"; $firstR = $false
                } else { $line += $add; $firstR = $false }
            }
            if ($line.Trim()) { Write-Host $line -ForegroundColor White }
        } else {
            Write-Host ""
        }
        Write-Host ""
        Write-Host "  This ONLY checks/updates games that already have BepInEx installed --"
        Write-Host "  it never installs BepInEx into a game that doesn't have it. Only the"
        Write-Host "  latest STABLE 64-bit release is ever used; 32-bit installs are left"
        Write-Host "  alone (update those manually), and pre-release builds are never used."
        Write-Host ""
        Write-Host "  Troubleshooting: https://docs.bepinex.dev/articles/user_guide/troubleshooting.html"
        Write-Host "  Clean manual reset: delete doorstop_config.ini, winhttp.dll,"
        Write-Host "  .doorstop_version, changelog.txt, and the BepInEx folder from the"
        Write-Host "  game's folder, then reinstall."

        $bepInExCacheDir = Join-Path $PSScriptRoot "BepInExCache"
        Invoke-BepInExUpdateCheck -UserProfilesDir $userProfilesDir -CacheDir $bepInExCacheDir

        Write-Host ""
        Write-Host "Done." -ForegroundColor Green
        Write-Log "BepInEx update check complete."
        [void](Read-Host "  Press Enter to return to menu")
        continue
    }

    $zipPathsJustCaptured = $false
    if ($mode -eq "AutoSync" -and -not $zipSource) {
        Write-Host ""
        Write-Host "  Main collection ZIP folder" -ForegroundColor Cyan
        Write-Host "  Point directly at the folder containing the .zip files, not a parent folder." -ForegroundColor DarkCyan
        Write-Host "  Example: W:\ROMS\TeknoParrot Collection" -ForegroundColor DarkCyan
        $zipSource = Read-PathWithBrowse "  Path"
        $zipPathsJustCaptured = $true
    }
    if ($mode -eq "AutoSync" -and ($null -eq $zipSourceSupplementary -or $zipSourceSupplementary -eq '') -and -not $Unattended) {
        Write-Host ""
        Write-Host "  Supplementary games folder (optional)" -ForegroundColor Cyan
        Write-Host "  Point directly at the folder containing the Supplementary .zip files, not a parent folder." -ForegroundColor DarkCyan
        Write-Host "  Example: W:\ROMS\TeknoParrot Supplementary" -ForegroundColor DarkCyan
        $rawSupp = Read-PathWithBrowse "  Path (or press Enter to skip)"
        if ($rawSupp -and (Test-Path -LiteralPath $rawSupp)) {
            $zipSourceSupplementary = $rawSupp
            Write-Log "Config: supplementary ZIP source set to $rawSupp"
        } elseif ($rawSupp) {
            Write-Host "  Folder not found -- supplementary source skipped." -ForegroundColor Yellow
            Write-Log "Config: supplementary ZIP source not found at $rawSupp -- skipped."
        } else {
            $zipSourceSupplementary = ''
            Write-Log "Config: supplementary ZIP source skipped by user."
        }
        $zipPathsJustCaptured = $true
    }
    if ($zipPathsJustCaptured) {
        if (Save-Config) {
            Write-Log "Config: saved ZIP source path(s)."
        } else {
            Write-Log "Config: could not re-save after ZIP source prompt."
        }
    }

    if ($mode -eq "AutoSync") {
        if (-not (Test-Path -LiteralPath $zipSource)) {
            Write-Host ""; Write-Host "ERROR: ZIP source folder not found: $zipSource" -ForegroundColor Red
            Write-Log "ERROR: ZIP source not found."; [void](Read-Host "  Press Enter to return to menu"); continue
        }
        $autoSyncDriveInfo = Get-LocalDriveInfoSafe
        if (Test-IsNetworkPath $gamesInstallFolder -Drives $autoSyncDriveInfo) {
            Write-Host ""
            Write-Host "  WARNING: The staging folder is on a network path." -ForegroundColor Yellow
            Write-Host "  Games will be extracted to -- and played from -- the network drive." -ForegroundColor Yellow
            Write-Host "  A local drive (e.g. D:\TeknoParrotGames) is faster and recommended." -ForegroundColor Yellow
            Write-Host "  Measuring write speed to the staging drive..." -ForegroundColor Cyan
            $stagingMbps = Measure-PathWriteThroughput $gamesInstallFolder
            if ($stagingMbps) {
                if ($stagingMbps -ge 500) {
                    Write-Host ("  Write speed: {0} MB/s -- fast enough for smooth extraction and gameplay." -f $stagingMbps) -ForegroundColor Green
                } elseif ($stagingMbps -ge 150) {
                    Write-Host ("  Write speed: {0} MB/s -- extraction will work but games may stutter during play." -f $stagingMbps) -ForegroundColor Yellow
                } else {
                    Write-Host ("  Write speed: {0} MB/s -- too slow for reliable extraction or play. Local drive strongly recommended." -f $stagingMbps) -ForegroundColor Red
                }
                Write-Log "Network staging benchmark: $stagingMbps MB/s"
            } else {
                Write-Host "  Write speed could not be measured (staging folder may not exist yet or is read-only)." -ForegroundColor DarkCyan
                Write-Log "Network staging benchmark: skipped (folder not found or write failed)"
            }
            if ($Unattended) {
                Write-Host "  [Unattended] Continuing with network staging folder." -ForegroundColor Yellow
                Write-Log "Unattended: network staging folder -- continuing."
            } else {
                $contNet = (Read-Host "  Continue with network staging folder? (Y/N)").Trim()
                if ($contNet.ToUpper() -ne "Y") {
                    Write-Host "Aborted." -ForegroundColor Yellow
                    Write-Log "Aborted: user declined network staging folder."
                    [void](Read-Host "  Press Enter to return to menu"); continue
                }
            }
            Write-Log "Network staging folder accepted: $gamesInstallFolder"
        }
        if (Test-PathInside $gamesInstallFolder $tpRoot) {
            Write-Host ""; Write-Host "ERROR: The staging folder is inside the TeknoParrot folder." -ForegroundColor Red
            Write-Host "Choose a staging folder outside $tpRoot to keep the emulator folder clean." -ForegroundColor Yellow
            Write-Log "ERROR: staging folder inside TeknoParrot root."; [void](Read-Host "  Press Enter to return to menu"); continue
        }
        if ((Test-PathInside $gamesInstallFolder $zipSource) -or (Test-PathInside $zipSource $gamesInstallFolder)) {
            Write-Host ""; Write-Host "ERROR: The staging folder and the ZIP source overlap." -ForegroundColor Red
            Write-Host "Keep them on separate paths so the original games folder stays clean." -ForegroundColor Yellow
            Write-Log "ERROR: staging folder overlaps ZIP source."; [void](Read-Host "  Press Enter to return to menu"); continue
        }
        if (-not (Test-Path -LiteralPath $gamesInstallFolder)) {
            try {
                [void][System.IO.Directory]::CreateDirectory($gamesInstallFolder)
                Write-Host "Created staging folder: $gamesInstallFolder" -ForegroundColor Green
            } catch {
                Write-Host ""; Write-Host "ERROR: Could not create staging folder: $_" -ForegroundColor Red
                Write-Log "ERROR: Could not create staging folder -- $_"; [void](Read-Host "  Press Enter to return to menu"); continue
            }
        }
        try {
            $zipBytes = (Get-ChildItem -LiteralPath $zipSource -Filter *.zip -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if (-not $zipBytes) { $zipBytes = 0 }
            $root      = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($gamesInstallFolder))
            $drive     = New-Object System.IO.DriveInfo($root)
            $freeBytes = $drive.AvailableFreeSpace
            Write-Host ("  Staging drive {0} free: {1} GB; ZIPs total ~{2} GB (need ~{3} GB extracted)." -f `
                $root, [Math]::Round($freeBytes/1GB,1), [Math]::Round($zipBytes/1GB,1), [Math]::Round(($zipBytes*1.5)/1GB,1)) -ForegroundColor DarkCyan
            if ($freeBytes -lt ($zipBytes * 1.5)) {
                Write-Host "  WARNING: free space on the staging drive may be insufficient." -ForegroundColor Yellow
                if ($Unattended) {
                    Write-Host "  [Unattended] Continuing despite low free space." -ForegroundColor Yellow
                    Write-Log "Unattended: low disk space warning -- continuing."
                } else {
                    $cont = (Read-Host "  Continue anyway? (Y/N)").Trim()
                    if ($cont.ToUpper() -ne "Y") { Write-Host "Aborted." -ForegroundColor Yellow; Write-Log "Aborted: low staging-drive space."; [void](Read-Host "  Press Enter to return to menu"); continue }
                }
            }
            Write-Log "Space check: free=$([Math]::Round($freeBytes/1GB,1))GB zips=$([Math]::Round($zipBytes/1GB,1))GB"
        } catch { Write-Log "Space check skipped: $_" }

        if (Test-IsNetworkPath $zipSource -Drives $autoSyncDriveInfo) {
            Write-Host ""
            Write-Host "Network ZIP source detected: $zipSource" -ForegroundColor Yellow
            Write-Host "Running throughput benchmark..." -ForegroundColor Cyan
            $mbps = Measure-PathThroughput $zipSource
            if ($mbps) {
                if     ($mbps -ge 500) { $rating = "Excellent" }
                elseif ($mbps -ge 250) { $rating = "Good"      }
                elseif ($mbps -ge 150) { $rating = "Adequate"  }
                else                   { $rating = "Poor"       }
                Write-Host "  Throughput : $mbps MB/s  [$rating]" -ForegroundColor Cyan
                Write-Host "  (AutoSync copies games to your local drive, so play" -ForegroundColor DarkCyan
                Write-Host "   performance does not depend on this speed.)" -ForegroundColor DarkCyan
                Write-Log "NAS benchmark: $mbps MB/s ($rating)"
            } else {
                Write-Host "  Benchmark skipped (no ZIPs found yet or read error)." -ForegroundColor DarkCyan
            }
        }
    } else {
        if (-not (Test-Path -LiteralPath $gamesInstallFolder)) {
            Write-Host ""; Write-Host "ERROR: Games install folder not found: $gamesInstallFolder" -ForegroundColor Red
            Write-Log "ERROR: install folder not found."; [void](Read-Host "  Press Enter to return to menu"); continue
        }
    }

    Write-Log "Mode=$mode install=$gamesInstallFolder"

    # Preview mode: -DryRun on the command line always applies; otherwise
    # ask once per AutoSync/Register run (skipped entirely when -Unattended,
    # which by definition never prompts -- pass -DryRun alongside
    # -Unattended to preview a scheduled run instead).
    if ($forceRealApply) {
        # Re-entering right after a preview run's "Apply for real now?" was
        # answered Y -- skip the prompt entirely and force a real pass.
        $dryRunActive   = $false
        $forceRealApply = $false
    } else {
        $dryRunActive = [bool]$DryRun
        if (-not $Unattended -and -not $dryRunActive) {
            Write-Host ""
            $previewAns = (Read-Host "  Run in PREVIEW mode first? No changes will be written -- this just shows what AutoSync/Register would do. (Y/N)").Trim().ToUpper()
            $dryRunActive = ($previewAns -eq "Y")
        }
    }
    if ($dryRunActive) { Write-Log "PREVIEW MODE active for this run -- no changes will be written." }

    $backupRoot = Join-Path $userProfilesDir "FullBackup"
    $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path $backupRoot $timestamp

Write-Host ""
if ($dryRunActive) {
    Write-Host "PREVIEW MODE -- skipping backup (nothing will be changed)." -ForegroundColor Yellow
} else {
Write-Host "Backing up UserProfiles..." -ForegroundColor Cyan

# Guard: if the backup folder cannot be created the script exits here rather
# than proceeding with modifications that have no restore point.
try {
    [void][System.IO.Directory]::CreateDirectory($backupRoot)
    [void][System.IO.Directory]::CreateDirectory($backupPath)
} catch {
    Write-Host "  ERROR: Could not create backup folder: $_" -ForegroundColor Red
    Write-Host "  The script will not continue without a successful backup." -ForegroundColor Red
    Write-Log "Backup FAILED: could not create backup folder -- $_"
    [void](Read-Host "  Press Enter to return to menu")
    continue
}

# Use Where-Object instead of -Exclude so FullBackup is reliably excluded
# across all PowerShell 5.1 versions (-Exclude has known edge-case behaviour).
# Copy-Item below receives FileInfo/DirectoryInfo objects from the pipeline
# (not path strings), so pipeline binding already bypasses wildcard
# expansion -- safe even with [, ], $ in game folder names. If this source
# is ever changed to raw path strings, add -LiteralPath there.
$backupErrors = 0
Get-ChildItem -LiteralPath $userProfilesDir | Where-Object { $_.Name -ne "FullBackup" } |
    Copy-Item -Destination $backupPath -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable copyErrs
$backupErrors = $copyErrs.Count
if ($backupErrors -gt 0) {
    Write-Host "  WARNING: $backupErrors file(s) could not be backed up." -ForegroundColor Yellow
    Write-Host "  Continuing without a complete backup means you may not be able to fully" -ForegroundColor Yellow
    Write-Host "  restore this run's changes if something goes wrong." -ForegroundColor Yellow
    Write-Log "Backup WARNING: $backupErrors file(s) failed to copy."
    if ($Unattended) {
        Write-Host "  [Unattended] Continuing despite incomplete backup." -ForegroundColor Yellow
        Write-Log "Unattended: incomplete backup -- continuing."
    } else {
        $contBackup = (Read-Host "  Continue anyway? (Y/N)").Trim().ToUpper()
        if ($contBackup -ne "Y") {
            Write-Host "Aborted." -ForegroundColor Yellow
            Write-Log "Aborted: user declined to continue with incomplete backup."
            [void](Read-Host "  Press Enter to return to menu")
            continue
        }
    }
}
Write-Host "Backup saved to: $backupPath" -ForegroundColor Green
Write-Log "Backup created at $backupPath"
}

# =============================================================================
# SECTION 6 -- AutoSync: game selection and extraction
# =============================================================================

if ($mode -eq "AutoSync") {
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " AutoSync: Extracting Games" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " New and changed games are extracted; unchanged games skipped." -ForegroundColor DarkCyan
    Write-Host " Local games are never deleted automatically." -ForegroundColor DarkCyan
    if ($retroBat) { Write-Host " RetroBat mode: folders extracted as GameName.teknoparrot" -ForegroundColor Cyan }
    Write-Host ""

    # Pre-validate the supplementary source now so we can decide whether to use the
    # combined picker. If invalid, errors are shown here before the picker runs.
    $onlySyncListSupp = $null
    $suppValid        = $false
    if ($zipSourceSupplementary) {
        if (-not (Test-Path -LiteralPath $zipSourceSupplementary)) {
            Write-Host "  WARNING: Supplementary ZIP folder not found: $zipSourceSupplementary -- skipped." -ForegroundColor Yellow
            Write-Log "AutoSync: supplementary ZIP source not found -- skipped."
        } elseif ((Test-PathInside $gamesInstallFolder $zipSourceSupplementary) -or
                  (Test-PathInside $zipSourceSupplementary $gamesInstallFolder)) {
            Write-Host "  ERROR: Supplementary ZIP folder overlaps the staging folder -- skipped." -ForegroundColor Red
            Write-Log "AutoSync: supplementary ZIP source overlaps staging folder -- skipped."
        } elseif (Test-PathInside $zipSourceSupplementary $tpRoot) {
            Write-Host "  ERROR: Supplementary ZIP folder is inside the TeknoParrot folder -- skipped." -ForegroundColor Red
            Write-Log "AutoSync: supplementary ZIP source is inside TeknoParrot root -- skipped."
        } else {
            $suppValid = $true
        }
    }

    # Picker return conventions (also used by overrides and unattended paths):
    #   $null   = skip this source entirely (user pressed D with nothing selected)
    #   @()     = no filter; extract all unextracted games (A was pressed, or unattended)
    #   @(...)  = whitelist; extract only the named games
    #
    # If onlySync is already populated from the overrides file, use it directly.
    # Otherwise run the interactive picker. When the supplementary source is valid,
    # both libraries are presented in a single combined list (Select-GamesInteractiveCombined).
    $combinedPickerRan = $false
    if ($onlySyncList.Count -eq 0) {
        if ($Unattended) {
            Write-Host "  [Unattended] Game selection: all unextracted games." -ForegroundColor DarkCyan
            Write-Log "Unattended: game selection = all."
        } elseif ($suppValid) {
            # Combined picker: both collection and supplementary shown in one sorted list.
            $combined          = Select-GamesInteractiveCombined -zipSourceMain $zipSource `
                                     -zipSourceSupp $zipSourceSupplementary -installFolder $gamesInstallFolder `
                                     -datIndex $datIndex -userProfilesDir $userProfilesDir
            $onlySyncList      = $combined.Main
            $onlySyncListSupp  = $combined.Supp
            $combinedPickerRan = $true
        } else {
            $onlySyncList = Select-GamesInteractive -zipSource $zipSource -installFolder $gamesInstallFolder -datIndex $datIndex -userProfilesDir $userProfilesDir
            # $null means user pressed D with nothing selected -- leave as $null (skip).
            # @() means A was pressed (no filter). Other values are explicit selections.
        }
    }
    # When the combined picker did not run (unattended, or overrides pre-set the main list),
    # default supplementary to all unextracted games. When the picker ran, $onlySyncListSupp
    # is already set by the picker ($null = skip, @() = all, @(...) = specific).
    if ($suppValid -and -not $combinedPickerRan -and $null -eq $onlySyncListSupp) {
        $onlySyncListSupp = @()
    }

    $syncStatePath = Join-Path $gamesInstallFolder "TeknoParrot-Manager.syncstate.json"

    $sync = $null
    if ($null -ne $onlySyncList) {
        $sync = Invoke-AutoSync -zipSource $zipSource -installFolder $gamesInstallFolder `
                    -syncStatePath $syncStatePath -noSync $noSyncList -onlySync $onlySyncList -retroBat $retroBat -DryRun $dryRunActive `
                    -datIndex $datIndex -userProfilesDir $userProfilesDir
    } else {
        Write-Host "  No games selected -- skipping main extraction." -ForegroundColor Yellow
        Write-Log "AutoSync: main extraction skipped -- no games selected."
    }

    # Supplementary extraction pass -- selection was already resolved above.
    $syncSupp = $null
    if ($suppValid) {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " AutoSync: Supplementary Games" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " Supplementary source: $zipSourceSupplementary" -ForegroundColor DarkCyan
        Write-Host ""
        if ($null -ne $onlySyncListSupp) {
            if ($Unattended) {
                Write-Host "  [Unattended] Game selection: all unextracted supplementary games." -ForegroundColor DarkCyan
                Write-Log "Unattended: supplementary game selection = all."
            }
            $syncSupp = Invoke-AutoSync -zipSource $zipSourceSupplementary -installFolder $gamesInstallFolder `
                            -syncStatePath $syncStatePath -noSync $noSyncList -onlySync $onlySyncListSupp -retroBat $retroBat -DryRun $dryRunActive `
                            -datIndex $datIndex -userProfilesDir $userProfilesDir
        } else {
            Write-Host "  No supplementary games selected -- skipping." -ForegroundColor Yellow
            Write-Log "AutoSync: supplementary extraction skipped -- no games selected."
        }
    }

    Write-Host ""
    Write-Host "Extraction summary:" -ForegroundColor Green
    if ($sync -and $syncSupp) { Write-Host "  Collection:" -ForegroundColor Cyan }
    if ($sync) {
        Write-Host "  Extracted  : $($sync.Synced)"   -ForegroundColor Green
        Write-Host "  Up to date : $($sync.UpToDate)"  -ForegroundColor DarkGray
        if ($sync.WouldSync -gt 0) { Write-Host "  Would extract : $($sync.WouldSync)  (preview -- nothing written yet)" -ForegroundColor Yellow }
        if ($sync.Skipped -gt 0) { Write-Host "  Skipped    : $($sync.Skipped)  (per-game override)" -ForegroundColor DarkGray }
        if ($sync.Failed  -gt 0) { Write-Host "  Failed     : $($sync.Failed)  (see TeknoParrot-Manager.log)" -ForegroundColor Red }
    } else {
        Write-Host "  Collection : skipped (no games selected)" -ForegroundColor DarkGray
    }
    if ($syncSupp) {
        Write-Host "  Supplementary:" -ForegroundColor Cyan
        Write-Host "  Extracted  : $($syncSupp.Synced)"   -ForegroundColor Green
        Write-Host "  Up to date : $($syncSupp.UpToDate)"  -ForegroundColor DarkGray
        if ($syncSupp.WouldSync -gt 0) { Write-Host "  Would extract : $($syncSupp.WouldSync)  (preview -- nothing written yet)" -ForegroundColor Yellow }
        if ($syncSupp.Skipped -gt 0) { Write-Host "  Skipped    : $($syncSupp.Skipped)  (per-game override)" -ForegroundColor DarkGray }
        if ($syncSupp.Failed  -gt 0) { Write-Host "  Failed     : $($syncSupp.Failed)  (see TeknoParrot-Manager.log)" -ForegroundColor Red }
    } elseif ($suppValid) {
        Write-Host "  Supplementary: skipped (no games selected)" -ForegroundColor DarkGray
    }
}

# =============================================================================
# SECTION 7 -- Build profile index from GameProfiles
# =============================================================================

Write-Host ""
Write-Host "Indexing TeknoParrot game profiles..." -ForegroundColor Cyan
$profileIndex = Build-ProfileIndex $gameProfilesDir
Write-Host "  Indexed $($profileIndex.Keys.Count) executable names across the profile set." -ForegroundColor DarkCyan
Write-Log "Profile index built: $($profileIndex.Keys.Count) executable keys."

if ($profileIndex.Keys.Count -eq 0) {
    Write-Host ""
    Write-Host "ERROR: No usable profiles found in GameProfiles." -ForegroundColor Red
    Write-Host "Run TeknoParrotUi.exe once to let it download/update profiles, then retry." -ForegroundColor Yellow
    Write-Log "ERROR: empty profile index."
    [void](Read-Host "  Press Enter to return to menu")
    continue
}

# =============================================================================
# SECTION 8 -- Register games
# =============================================================================

Write-Host ""
Write-Host "--------------------------------------------" -ForegroundColor Cyan
Write-Host " Registering Games" -ForegroundColor Cyan
Write-Host "--------------------------------------------" -ForegroundColor Cyan
Write-Host " Scanning: $gamesInstallFolder" -ForegroundColor DarkCyan
Write-Host ""

$result = Register-Games -userProfilesDir $userProfilesDir -installFolder $gamesInstallFolder -profileIndex $profileIndex -gameProfilesDir $gameProfilesDir -datIndex $datIndex -profileSet $profileSet -DryRun $dryRunActive -tpRootDir $tpRoot -subFolderMap $subFolderMap

foreach ($r in $result.Registered) {
    if ($r.DatMatch) {
        Write-Host ("  Registered (dat)       : {0}" -f $r.Code) -ForegroundColor Green
    } elseif ($r.FuzzyScore) {
        Write-Host ("  Registered (fuzzy {0}) : {1}" -f $r.FuzzyScore, $r.Code) -ForegroundColor Cyan
        Write-Host ("               folder  : {0}" -f $r.FuzzyFolder) -ForegroundColor DarkGray
    } elseif ($r.SubFolderMatch) {
        Write-Host ("  Registered (tp-root)   : {0}" -f $r.Code) -ForegroundColor Green
    } else {
        Write-Host ("  Registered             : {0}" -f $r.Code) -ForegroundColor Green
    }
    Write-Host "               $($r.GamePath)" -ForegroundColor DarkGray
}
foreach ($a in $result.Already) {
    Write-Host "  Already set : $a  (UserProfile exists, left unchanged)" -ForegroundColor DarkGray
}

# Collect unique game folders that need manual registration, keeping the most
# useful executable per folder (fewest profile matches = most specific hint).
# Multiple ambiguous files in the same folder collapse to one entry.
$manualRegData = @{}   # folderName -> @{ ExeName; ProfileCount; Profiles }
if ($result.Ambiguous.Count -gt 0) {
    $installBase = $gamesInstallFolder.TrimEnd('\')
    foreach ($amb in $result.Ambiguous) {
        $rel        = if ($amb.Exe.Length -gt $installBase.Length) { $amb.Exe.Substring($installBase.Length).TrimStart('\') } else { $amb.Exe }
        $folderName = $rel.Split('\')[0]
        $exeName    = [System.IO.Path]::GetFileName($amb.Exe)
        $count      = @($amb.Codes.Split(',')).Count
        if (-not $manualRegData.ContainsKey($folderName) -or $count -lt $manualRegData[$folderName].ProfileCount) {
            $manualRegData[$folderName] = @{
                Exe          = $amb.Exe
                ExeName      = $exeName
                ProfileCount = $count
                Profiles     = $amb.Codes
                BestGuess    = $amb.BestGuess
                BestScore    = $amb.BestScore
                Reason       = $amb.Reason
                ClaimedBy    = $amb.ClaimedBy
            }
        }
    }
}

# Duplicate profile codes (Reason="duplicate": exactly one profile code,
# contested by exactly one other folder) are resolvable in-script -- unlike
# "shared" conflicts (one exe name maps to several different games' profile
# codes), there's no ambiguity about WHICH profile is in play, only which
# folder it should point at. Offer to fix these now instead of sending the
# user to TeknoParrotUI for something this script can do directly.
$duplicateConflicts = @($manualRegData.GetEnumerator() | Where-Object { $_.Value.Reason -eq "duplicate" })
if ($duplicateConflicts.Count -gt 0 -and -not $Unattended) {
    Write-Host ""
    Write-Host ("  {0} duplicate profile conflict(s) found (one profile code claimed by two folders)." -f $duplicateConflicts.Count) -ForegroundColor Yellow
    $resolveChoice = (Read-Host "  Resolve them now by picking which folder keeps the profile? (Y/N)").Trim().ToUpper()
    if ($resolveChoice -eq "Y") {
        foreach ($entry in $duplicateConflicts) {
            $folderName = $entry.Key
            $info       = $entry.Value
            $code       = $info.Profiles   # single code for a "duplicate" entry
            $userProfilePath = Join-Path $userProfilesDir ($code + ".xml")
            $currentExe = $null
            try {
                $curDoc = Read-Xml $userProfilePath
                $curGp  = $curDoc.GameProfile.SelectSingleNode("GamePath")
                if ($curGp) { $currentExe = $curGp.InnerText.Trim() }
            } catch {
                Write-Log "Duplicate resolution: could not read current GamePath for $code -- $_"
            }
            Write-Host ""
            Write-Host ("  Profile          : {0}" -f $code) -ForegroundColor Yellow
            Write-Host ("  Currently set to : {0}" -f $currentExe) -ForegroundColor DarkGray
            Write-Host ("  Conflicting copy : {0}" -f $info.Exe) -ForegroundColor DarkGray
            $pick = (Read-Host "  [K]eep current / [S]witch to conflicting copy / [Q]uit resolving").Trim().ToUpper()
            if ($pick -eq "Q") { break }
            if ($pick -eq "S") {
                try {
                    $swDoc = Read-Xml $userProfilePath
                    $swGp  = $swDoc.GameProfile.SelectSingleNode("GamePath")
                    if ($null -eq $swGp) {
                        $swGp = $swDoc.CreateElement("GamePath")
                        [void]$swDoc.GameProfile.PrependChild($swGp)
                    }
                    $swGp.InnerText = $info.Exe
                    Save-XmlMaybe $swDoc $userProfilePath $dryRunActive
                    $switchMsg = if ($dryRunActive) { "[Preview] Would switch." } else { "Switched." }
                    Write-Host "  $switchMsg" -ForegroundColor (if ($dryRunActive) { "DarkCyan" } else { "Green" })
                    Write-Log "Duplicate resolution: $code switched to $($info.Exe) (was $currentExe)"
                    $manualRegData.Remove($folderName)
                } catch {
                    Write-Host "  FAILED to switch: $_" -ForegroundColor Red
                    Write-Log "Duplicate resolution FAILED for $code -- $_"
                }
            } else {
                Write-Host "  Kept current. Still listed in ACTION REQUIRED." -ForegroundColor DarkGray
            }
        }
    }
}

if ($manualRegData.Count -gt 0) {
    Write-Host ""
    Write-Host ("  {0} game(s) need manual registration -- see ACTION REQUIRED at the end of this run." -f $manualRegData.Count) -ForegroundColor Yellow
}
if ($result.Unmatched.Count -gt 0) {
    Write-Host ("  {0} game folder(s) not recognised by TeknoParrot -- see ACTION REQUIRED at the end of this run." -f $result.Unmatched.Count) -ForegroundColor Yellow
}

# =============================================================================
# SECTION 8b -- Download game thumbnails (optional)
# =============================================================================

Write-Host ""
if ($dryRunActive) {
    Write-Log "PreviewMode: thumbnail download skipped."
    $doThumb = "N"
} elseif ($Unattended) {
    Write-Host "  [Unattended] Downloading missing thumbnails." -ForegroundColor DarkCyan
    Write-Log "Unattended: thumbnail download = Y."
    $doThumb = "Y"
} else {
    Write-Host "  Tip: to add your own thumbnails, create a  CustomThumbnails\  folder next to" -ForegroundColor DarkCyan
    Write-Host "  this script and drop  ProfileCode.png  files in it. The profile code is" -ForegroundColor DarkCyan
    Write-Host "  the game's filename in UserProfiles\ (without .xml), or check the" -ForegroundColor DarkCyan
    Write-Host "  TeknoParrot-Manager-controls.txt file for a full list of registered codes." -ForegroundColor DarkCyan
    $doThumb = (Read-Host "Download thumbnails for registered games missing an icon? (Y/N)").Trim().ToUpper()
}
if ($doThumb -eq "Y") {
    Write-Host ""
    Write-Host "Downloading thumbnails from TeknoParrotUIThumbnails..." -ForegroundColor Cyan
    Write-Host " Source: https://github.com/teknogods/TeknoParrotUIThumbnails" -ForegroundColor DarkCyan
    Write-Host ""
    Invoke-ThumbnailDownload -userProfilesDir $userProfilesDir -tpRoot $tpRoot
}

# =============================================================================
# SECTION 9  -- Game repair: fix broken GamePaths
# =============================================================================

Write-Host ""
if ($Unattended) {
    Write-Host "  [Unattended] Running repair." -ForegroundColor DarkCyan
    Write-Log "Unattended: repair = Y."
    $doRepair = "Y"
} else {
    $doRepair = (Read-Host "Check for and repair broken game paths now? (Y/N)").Trim()
}
$nf   = @(); $amb2 = @()   # initialise so the final summary can reference them safely
if ($doRepair.Trim().ToUpper() -eq "Y") {
    Write-Host ""
    Write-Host "Repairing game paths..." -ForegroundColor Cyan
    $repair = Repair-GamePaths -userProfilesDir $userProfilesDir -installFolder $gamesInstallFolder -profileIndex $profileIndex -DryRun $dryRunActive
    $fixed = @($repair | Where-Object { $_.Status -eq "fixed" })
    $nf    = @($repair | Where-Object { $_.Status -eq "not-found" })
    $amb2  = @($repair | Where-Object { $_.Status -eq "ambiguous" })
    $noex  = @($repair | Where-Object { $_.Status -eq "no-exe-name" })
    $sf    = @($repair | Where-Object { $_.Status -eq "save-failed" })
    if ($fixed.Count -eq 0 -and $nf.Count -eq 0 -and $amb2.Count -eq 0 -and $sf.Count -eq 0) {
        Write-Host "  All game paths are valid. Nothing to repair." -ForegroundColor Green
    } else {
        foreach ($r in $fixed) {
            Write-Host "  Fixed : $($r.Code)" -ForegroundColor Green
            Write-Host "          $($r.NewPath)" -ForegroundColor DarkGray
        }
        foreach ($r in $sf) {
            Write-Host "  Save failed : $($r.Code)  (see TeknoParrot-Manager.log)" -ForegroundColor Red
        }
        if ($nf.Count -gt 0) {
            Write-Host ("  {0} game(s) not yet extracted -- extract first, then re-run Repair." -f $nf.Count) -ForegroundColor DarkCyan
        }
        if ($amb2.Count -gt 0) {
            Write-Host ("  {0} profile(s) could not be auto-fixed -- see ACTION REQUIRED at the end of this run." -f $amb2.Count) -ForegroundColor Yellow
        }
    }
    Write-Log "Repair: fixed=$($fixed.Count) notfound=$($nf.Count) manualreg=$($amb2.Count) noexe=$($noex.Count) savefail=$($sf.Count)"
}

# =============================================================================
# SECTION 10 -- Control propagation
# =============================================================================

$MinBoundForArchetype = 5
$noArchetypeItems     = @()   # populated after propagation; used in ACTION REQUIRED
$reports              = $null  # populated if propagation runs; used by Write-ControlsStatus

Write-Host ""
Write-Host "--------------------------------------------" -ForegroundColor Cyan
Write-Host " Control Propagation" -ForegroundColor Cyan
Write-Host "--------------------------------------------" -ForegroundColor Cyan

$pool = Build-ArchetypePool -userProfilesDir $userProfilesDir -minBound $MinBoundForArchetype

if ($pool.Count -eq 0) {
    # First run: nothing to copy FROM yet. Help the user plan what to bind.
    Write-Host " No fully-bound example games found yet, so there is nothing" -ForegroundColor Yellow
    Write-Host " to copy controls from yet. Let's plan which games to bind first." -ForegroundColor Yellow
    if (-not $Unattended) { Invoke-DeviceSurvey }
    Write-Log "Propagation: no reference games found (>= $MinBoundForArchetype bound buttons)$(if (-not $Unattended) { '; ran device survey' })."
} else {
    Write-Host " Found these bound games to copy controls FROM:" -ForegroundColor Green
    foreach ($s in $pool) {
        $apiLabel = if ($s.InputApi) { $s.InputApi } else { "n/a" }
        $devLabel = if ($s.Devices.Count -gt 0) { ($s.Devices -join ", ") } else { "?" }
        Write-Host ("    {0,-26} [{1}]  {2} buttons" -f $s.Code, $s.Family, $s.BoundCount) -ForegroundColor DarkGray
        Write-Host ("        api={0}   device(s): {1}" -f $apiLabel, $devLabel) -ForegroundColor DarkGray
        if ($s.ConfigCarry.Count -gt 0) {
            $cfgLabel = ($s.ConfigCarry.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "
            Write-Host ("        settings that will be copied: {0}" -f $cfgLabel) -ForegroundColor DarkGray
            foreach ($flag in (Get-ConfigCarryFlags $s.Family $s.ConfigCarry)) {
                Write-Host ("        WARNING: $flag") -ForegroundColor Red
            }
        }
    }
    Write-Host ""
    Write-Host " This copies each game's controls to your OTHER games of the SAME" -ForegroundColor DarkCyan
    Write-Host " type. It never changes a game you have already bound, and it leaves" -ForegroundColor DarkCyan
    Write-Host " game-specific controls (gear shifts, special buttons) unbound for" -ForegroundColor DarkCyan
    Write-Host " you to set. Your UserProfiles were backed up at the start of this run." -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host " IMPORTANT: the 'settings that will be copied' lines above apply to" -ForegroundColor Yellow
    Write-Host " EVERY other game of that type. Check them against your real hardware" -ForegroundColor Yellow
    Write-Host " now -- for example 'Use Keyboard/Button For Axis' should be False if" -ForegroundColor Yellow
    Write-Host " you bind with a real wheel, and 'Use Relative Input' should match how" -ForegroundColor Yellow
    Write-Host " your lightgun reports position. If anything looks wrong, answer N," -ForegroundColor Yellow
    Write-Host " fix the game above in TeknoParrotUI, then re-run." -ForegroundColor Yellow
    Write-Host ""
    if (-not $Unattended -and (Read-Host " Want a recommended binding plan for more control types first? (Y/N)").Trim().ToUpper() -eq "Y") {
        Invoke-DeviceSurvey
        Write-Host ""
    }
    if ($Unattended) {
        Write-Host "  [Unattended] Propagating controls." -ForegroundColor DarkCyan
        Write-Log "Unattended: propagation = Y."
        $goCtl = "Y"
    } else {
        $goCtl = (Read-Host " Propagate controls now? (Y/N)").Trim()
    }
    if ($goCtl.ToUpper() -eq "Y") {
        $reports = Invoke-ControlPropagation -userProfilesDir $userProfilesDir -pool $pool -minBound $MinBoundForArchetype -noPropagate $noPropagateList -forceArchetype $forceArchetypeMap -familyOverride $familyOverrideMap -canonicalArchetype $canonicalArchetypeMap -DryRun $dryRunActive
        Write-Host ""
        Write-Host " Results:" -ForegroundColor Green
        foreach ($r in $reports) {
            switch ($r.Status) {
                "bound" {
                    $pin = if ($r.Forced) { "  (pinned)" } else { "" }
                    Write-Host ("    {0}{1}" -f $r.Code, $pin) -ForegroundColor Green
                    Write-Host ("       copied from {0} [{1}] -- bound {2} control(s)" -f $r.Archetype, $r.Family, $r.Bound) -ForegroundColor DarkGray
                    if ($r.ConfigCarried.Count -gt 0) {
                        Write-Host ("       carried settings: {0}" -f ($r.ConfigCarried -join ", ")) -ForegroundColor DarkGray
                    }
                    if (-not $r.ApiSet -and $r.ArchetypeApi) {
                        Write-Host ("       NOTE: left Input API unchanged ('{0}' not offered by this game)" -f $r.ArchetypeApi) -ForegroundColor Yellow
                    }
                    if ($r.Manual.Count -gt 0) {
                        Write-Host ("       still manual: {0}" -f ($r.Manual -join ", ")) -ForegroundColor Yellow
                    }
                }
                "no-archetype"     { Write-Host ("    {0}  -- no '{1}' example game bound yet; controls will be set once you bind one (see ACTION REQUIRED)" -f $r.Code, $r.Family) -ForegroundColor Yellow }
                "api-fixed"        { Write-Host ("    {0}  -- already bound; Input API corrected to '{1}' (matched from {2})" -f $r.Code, $r.ArchetypeApi, $r.Archetype) -ForegroundColor Green }
                "api-fixed-canonical" { Write-Host ("    {0}  -- archetype; Input API corrected to '{1}' (matched from canonical archetype {2})" -f $r.Code, $r.ArchetypeApi, $r.Archetype) -ForegroundColor Green }
                "skipped-bound"    { Write-Host ("    {0}  -- already bound, left unchanged" -f $r.Code) -ForegroundColor DarkGray }
                "skipped-override" { Write-Host ("    {0}  -- skipped (per-game override)" -f $r.Code) -ForegroundColor DarkGray }
                "save-failed"      { Write-Host ("    {0}  -- ERROR saving (see TeknoParrot-Manager.log)" -f $r.Code) -ForegroundColor Red }
            }
            if ($r.MismatchSlots) {
                Write-Host ("       ACTION REQUIRED -- directional/action mismatch: {0}" -f $r.MismatchSlots) -ForegroundColor Yellow
                Write-Host ("       Rebind these slots manually in TeknoParrot's own UI (see issue #17)" ) -ForegroundColor Yellow
            }
        }
        $nb               = @($reports | Where-Object { $_.Status -eq "bound" -or $_.Status -eq "api-fixed" -or $_.Status -eq "api-fixed-canonical" }).Count
        $noArchetypeItems = @($reports | Where-Object { $_.Status -eq "no-archetype" })
        Write-Host ""
        Write-Host (" Games updated: {0}" -f $nb) -ForegroundColor Green
        Write-Host ""
        Write-Host " IMPORTANT: launch ONE updated game in TeknoParrot and test its" -ForegroundColor Cyan
        Write-Host " controls before trusting the rest. If anything is wrong, restore" -ForegroundColor Cyan
        Write-Host (" from the backup made at the start of this run:" ) -ForegroundColor Cyan
        Write-Host ("    {0}" -f $backupPath) -ForegroundColor Cyan
        Write-Log "Propagation: completed. Games updated=$nb"
    } else {
        Write-Host " Skipped control propagation." -ForegroundColor DarkGray
        Write-Log "Propagation: user declined."
    }
}

# =============================================================================
# Done
# =============================================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
if ($dryRunActive) {
    Write-Host "   PREVIEW MODE -- no changes were written." -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  You'll be asked below whether to apply these changes for real." -ForegroundColor Yellow
} else {
    Write-Host "   Done." -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  Newly registered : $($result.Registered.Count)" -ForegroundColor Green
Write-Host "  Already present  : $($result.Already.Count)"    -ForegroundColor DarkGray
if ($result.Ambiguous.Count -gt 0) {
    Write-Host "  Manual needed    : $($manualRegData.Count) game(s)  (see ACTION REQUIRED below)" -ForegroundColor Yellow
}
if ($result.Unmatched.Count -gt 0) {
    Write-Host ("  Not in TeknoParrot : {0} folder(s)  (see ACTION REQUIRED below)" -f $result.Unmatched.Count) -ForegroundColor Yellow
}
Write-Host ""
if (-not $dryRunActive) { Write-Host "  Backup : $backupPath" -ForegroundColor DarkCyan }
Write-Host "  Log    : $logPath"    -ForegroundColor DarkCyan

$csStatusPath = Join-Path $PSScriptRoot "TeknoParrot-Manager-controls.txt"
$csCount = Write-ControlsStatus -userProfilesDir $userProfilesDir -pool $pool -propagationReports $reports -outputPath $csStatusPath
if ($csCount -ge 0) {
    Write-Host "  Controls : $csStatusPath" -ForegroundColor DarkCyan
    Write-Log "Controls status: wrote $csCount games to $csStatusPath"
}

Write-Log "Completed. Registered=$($result.Registered.Count) Already=$($result.Already.Count) ManualReg=$($result.Ambiguous.Count) Unmatched=$($result.Unmatched.Count)"

# =============================================================================
# GAME INFO -- source tag and notes for newly registered games
# =============================================================================

if ($result.Registered.Count -gt 0 -and $notesIndex.Count -gt 0) {
    $infoItems = @($result.Registered | Where-Object { $notesIndex.ContainsKey($_.Code.ToLower()) })
    if ($infoItems.Count -gt 0) {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "   Game Info (from dat)" -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        foreach ($r in $infoItems) {
            $key = $r.Code.ToLower()
            Write-Host ""
            Write-Host ("  {0}" -f $r.Code) -ForegroundColor Yellow
            if ($suppCodes.Contains($r.Code)) {
                Write-Host "  Source: supplementary dat (alternate version used instead of collection)" -ForegroundColor DarkCyan
            }
            if ($notesIndex.ContainsKey($key)) {
                Write-Host "  Notes:" -ForegroundColor Cyan
                $noteLines = ($notesIndex[$key] -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 4
                foreach ($nl in $noteLines) {
                    Write-Host ("    {0}" -f $nl.Trim()) -ForegroundColor DarkGray
                }
            }
        }
        Write-Host ""
    }
}

# =============================================================================
# LAUNCHBOX XML EXPORT  (optional, runs before ACTION REQUIRED)
# =============================================================================

Write-Host ""
if ($dryRunActive) {
    $doLBSetup = "N"
    Write-Log "PreviewMode: LaunchBox setup skipped."
} elseif ($Unattended) {
    $doLBSetup = "N"
    Write-Log "Unattended: LaunchBox setup skipped."
} else {
    Write-Host "  Add your registered games to LaunchBox now? (Y/N)" -ForegroundColor Cyan
    Write-Host "    This writes directly into LaunchBox's library -- no import wizard" -ForegroundColor DarkGray
    Write-Host "    needed. LaunchBox must be closed first; the script checks for you." -ForegroundColor DarkGray
    Write-Host "    (Prefer the old manual-import reference file instead? Answer N here," -ForegroundColor DarkGray
    Write-Host "     then Y to the next question.)" -ForegroundColor DarkGray
    $doLBSetup = (Read-Host "  Y/N").Trim().ToUpper()
}

if ($doLBSetup -eq "Y" -and -not $lbRoot) {
    $lbDetected = @(Find-LaunchBoxRoot)
    if ($lbDetected.Count -eq 1) {
        Write-Host ""
        Write-Host "  Auto-detected LaunchBox at: $($lbDetected[0])" -ForegroundColor Cyan
        $useLbIt = (Read-Host "  Use this path? (Y/N)").Trim().ToUpper()
        if ($useLbIt -eq "Y") { $lbRoot = $lbDetected[0] }
    } elseif ($lbDetected.Count -gt 1) {
        Write-Host ""
        Write-Host "  Found LaunchBox in multiple locations:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $lbDetected.Count; $i++) {
            Write-Host ("    {0}) {1}" -f ($i + 1), $lbDetected[$i])
        }
        $lbPick = (Read-Host "  Enter number to use one, or N to type the path manually").Trim()
        if ($lbPick -match '^\d+$' -and $lbPick.Length -le 9) {
            $lbIdx = [int]$lbPick - 1
            if ($lbIdx -ge 0 -and $lbIdx -lt $lbDetected.Count) { $lbRoot = $lbDetected[$lbIdx] }
        }
    }
    if (-not $lbRoot) {
        $lbInput = Read-PathWithBrowse "  Enter LaunchBox root folder (containing LaunchBox.exe), or press Enter to skip"
        if ($lbInput -and (Test-Path -LiteralPath (Join-Path $lbInput "LaunchBox.exe"))) {
            $lbRoot = $lbInput
        } elseif ($lbInput) {
            Write-Host "  LaunchBox.exe not found at that path -- direct LaunchBox setup skipped." -ForegroundColor Yellow
        }
    }
    if ($lbRoot) { [void](Save-Config) }
}

if ($doLBSetup -eq "Y" -and $lbRoot -and (Test-LaunchBoxRunning)) {
    Write-Host "  LaunchBox or BigBox is currently running -- close it and re-run this step." -ForegroundColor Yellow
    Write-Host "  Falling back to the manual-import reference file instead." -ForegroundColor DarkCyan
    $doLBSetup = "N"
    $doLB = "Y"
} elseif ($doLBSetup -eq "Y" -and -not $lbRoot) {
    Write-Host "  LaunchBox path not available -- falling back to the manual-import reference file." -ForegroundColor Yellow
    $doLBSetup = "N"
    $doLB = "Y"
} elseif ($doLBSetup -ne "Y" -and -not $dryRunActive -and -not $Unattended) {
    $doLB = (Read-Host "  Export a LaunchBox manual-import reference file instead? (Y/N)").Trim().ToUpper()
} else {
    $doLB = "N"
}

if ($doLBSetup -eq "Y") {
    $usesSavedChoice = $false
    if ($lbPlatformMode -and -not $Unattended) {
        $savedLabel = if ($lbPlatformMode -eq "Custom") { $lbCustomPlatformName } else { $lbPlatformMode }
        $useSaved = (Read-Host "  Use saved LaunchBox platform choice ($savedLabel)? (Y/N)").Trim().ToUpper()
        $usesSavedChoice = ($useSaved -eq "Y")
    }
    if (-not $usesSavedChoice) {
        Write-Host ""
        Write-Host "  How should TeknoParrot games appear in LaunchBox?" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "    1) Mixed into your existing Arcade platform"
        Write-Host "       (recommended if you browse all arcade games together)"
        Write-Host "    2) A separate `"TeknoParrot`" platform"
        Write-Host "       (recommended if you want them grouped on their own)"
        Write-Host "    3) A separate platform with a name you choose"
        Write-Host "    4) Both -- mixed into Arcade AND a separate TeknoParrot platform"
        Write-Host ""
        $platChoice = (Read-Host "  Enter 1-4").Trim()
        switch ($platChoice) {
            "1" { $lbPlatformMode = "Arcade" }
            "2" { $lbPlatformMode = "TeknoParrot" }
            "3" {
                $lbPlatformMode = "Custom"
                $lbCustomPlatformName = (Read-Host "  Enter a platform name").Trim()
                if ([string]::IsNullOrWhiteSpace($lbCustomPlatformName)) { $lbCustomPlatformName = "TeknoParrot" }
            }
            "4" { $lbPlatformMode = "Both" }
            default { $lbPlatformMode = "TeknoParrot" }
        }
        [void](Save-Config)
    }

    $lbTargetPlatforms = switch ($lbPlatformMode) {
        "Arcade" { @("Arcade") }
        "Custom" { @($lbCustomPlatformName) }
        "Both"   { @("Arcade", "TeknoParrot") }
        default  { @("TeknoParrot") }
    }

    $lbWriteResult = Invoke-LaunchBoxDirectWrite -userProfilesDir $userProfilesDir -tpRoot $tpRoot -lbRoot $lbRoot -platformNames $lbTargetPlatforms
    if ($null -eq $lbWriteResult) {
        Write-Host "  LaunchBox setup did not complete -- see TeknoParrot-Manager.log. No changes were made." -ForegroundColor Red
    } else {
        Write-Host ""
        Write-Host "  LaunchBox setup complete." -ForegroundColor Green
        foreach ($name in $lbWriteResult.Results.Keys) {
            Write-Host ("    {0,-12} : {1} game(s) added" -f $name, $lbWriteResult.Results[$name]) -ForegroundColor Green
        }
        Write-Host ("  Backup saved : {0}" -f $lbWriteResult.BackupPath) -ForegroundColor DarkCyan
        Write-Host "  If anything looks wrong in LaunchBox, use menu option 9 (Restore" -ForegroundColor DarkCyan
        Write-Host "  backup) -> LaunchBox library backup to undo this." -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  New games have no box art/metadata yet -- in LaunchBox, right-click a" -ForegroundColor DarkCyan
        Write-Host "  game and use 'Edit... -> Search' to fetch it, the same way you would" -ForegroundColor DarkCyan
        Write-Host "  for any manually-imported game." -ForegroundColor DarkCyan
        Write-Log ("LaunchBox direct-write: " + (($lbWriteResult.Results.Keys | ForEach-Object { "$_=$($lbWriteResult.Results[$_])" }) -join ", "))
    }
}

if ($doLB -eq "Y") {
    $lbPath  = Join-Path $PSScriptRoot "TeknoParrot-LaunchBox-Import.xml"
    $lbCount = Export-LaunchBoxXml -userProfilesDir $userProfilesDir -lbRoot $lbRoot -outputPath $lbPath
    if ($lbCount -lt 0) {
        Write-Host "  LaunchBox export failed -- see TeknoParrot-Manager.log" -ForegroundColor Red
    } else {
        Write-Host ("  Exported : {0} game(s)" -f $lbCount) -ForegroundColor Green
        Write-Host "  File     : $lbPath" -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  HOW TO IMPORT INTO LAUNCHBOX" -ForegroundColor Cyan
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  Important: LaunchBox must be fully CLOSED before importing." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Step 1.  Close LaunchBox completely." -ForegroundColor White
        Write-Host "  Step 2.  Open LaunchBox." -ForegroundColor White
        Write-Host "  Step 3.  Go to  Tools -> Import -> Emulated Games." -ForegroundColor White
        Write-Host "  Step 4.  On the first screen:" -ForegroundColor White
        Write-Host "             - Emulator: select TeknoParrot (or add it first -- see below)." -ForegroundColor DarkGray
        Write-Host "             - Import type: 'Import ROM files'." -ForegroundColor DarkGray
        Write-Host ("             - Folder: {0}" -f (Join-Path $tpRoot "UserProfiles")) -ForegroundColor DarkGray
        Write-Host "             - File types: *.xml  (import the profile files themselves," -ForegroundColor DarkGray
        Write-Host "               not the game executables -- TeknoParrot launches games" -ForegroundColor DarkGray
        Write-Host "               by profile, so the profile XML is what LaunchBox treats" -ForegroundColor DarkGray
        Write-Host "               as the 'rom' for each game)." -ForegroundColor DarkGray
        Write-Host "  Step 5.  Follow the wizard. LaunchBox will assign game names," -ForegroundColor White
        Write-Host "             metadata, and box art automatically." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  If TeknoParrot is not yet in LaunchBox's emulator list:" -ForegroundColor Cyan
        Write-Host "    a. Go to  Tools -> Manage -> Emulators -> Add." -ForegroundColor DarkGray
        Write-Host "    b. Name: TeknoParrot" -ForegroundColor DarkGray
        Write-Host ("    c. Emulator path: {0}" -f (Join-Path $tpRoot "TeknoParrotUi.exe")) -ForegroundColor DarkGray
        Write-Host "    d. Command-line parameters: --profile=%romfile%.xml" -ForegroundColor DarkGray
        Write-Host "    e. Exit Script tab: add a script so Escape cleanly quits" -ForegroundColor DarkGray
        Write-Host "       TeknoParrot back to LaunchBox (without one, Escape may not" -ForegroundColor DarkGray
        Write-Host "       exit the game properly)." -ForegroundColor DarkGray
        Write-Host "    f. Save, then re-run the import wizard." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Seeing full-screen issues only when launching through LaunchBox?" -ForegroundColor Cyan
        Write-Host "    Go to  Tools -> Manage -> Emulators -> TeknoParrot -> Edit ->" -ForegroundColor DarkGray
        Write-Host "    Startup Screen tab, and disable 'Enable Game Startup Screen'." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  The exported XML file ($lbPath)" -ForegroundColor DarkCyan
        Write-Host "  is a reference showing all registered games, their profile codes," -ForegroundColor DarkCyan
        Write-Host "  and executable paths. You do not need to import it directly." -ForegroundColor DarkCyan
        Write-Log "LaunchBox export: exported $lbCount games to $lbPath"
    }
}

# =============================================================================
# HYPERSPIN 2 EXPORT  (optional, runs after LaunchBox export)
# =============================================================================

Write-Host ""
if ($dryRunActive) {
    $doHS = "N"
    Write-Log "PreviewMode: HyperSpin 2 export skipped."
} elseif ($Unattended) {
    $doHS = "N"
    Write-Log "Unattended: HyperSpin 2 export skipped."
} else {
    $doHS = (Read-Host "Export registered games to HyperSpin 2? (Y/N)").Trim().ToUpper()
}
if ($doHS -eq "Y") {
    if (-not $hsDataPath) {
        Write-Host ""
        Write-Host "  Enter HyperSpin 2 data folder path." -ForegroundColor Cyan
        $hsInput = Read-PathWithBrowse "  Path (default: C:\ProgramData\HyperSpin\data)" -InitialDirectory "C:\ProgramData\HyperSpin"
        if ([string]::IsNullOrWhiteSpace($hsInput)) { $hsInput = "C:\ProgramData\HyperSpin\data" }
        $hsDataPath = $hsInput

        if (Save-Config) {
            Write-Log "Config: saved HyperSpinDataPath = $hsDataPath"
        } else {
            Write-Log "Config: could not save HyperSpinDataPath"
        }
    }

    Write-Host ""
    $hsCount = Export-HyperSpinJson -userProfilesDir $userProfilesDir -hsDataPath $hsDataPath
    if ($hsCount -lt 0) {
        Write-Host "  HyperSpin 2 export failed -- see TeknoParrot-Manager.log" -ForegroundColor Red
    } elseif ($hsCount -eq 0) {
        Write-Host "  HyperSpin 2 already up to date -- no new games to add." -ForegroundColor Green
    } else {
        Write-Host ("  Added : {0} game(s) to HyperSpin 2" -f $hsCount) -ForegroundColor Green
        Write-Host ""
        Write-Host "  Games are added with title only. Use HyperSpin's Scrape feature" -ForegroundColor DarkCyan
        Write-Host "  to fetch box art, descriptions, and ratings for the new entries." -ForegroundColor DarkCyan
        Write-Log "HyperSpin 2: exported $hsCount game(s)"
    }
}

# =============================================================================
# CROSSHAIR SETUP  (optional, runs after HyperSpin export)
# =============================================================================

Write-Host ""
if ($Unattended) {
    $doCrosshairs = "N"
    Write-Log "Unattended: crosshair setup skipped."
} else {
    $doCrosshairs = (Read-Host "Configure custom crosshairs for lightgun games? (Y/N)").Trim().ToUpper()
}
if ($doCrosshairs -eq "Y") {
    Write-Host ""
    Write-Host "Crosshair Setup" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Invoke-CrosshairSetup -UserProfilesDir $userProfilesDir `
                          -GamesInstallFolder $gamesInstallFolder `
                          -TpRoot $tpRoot
}

# =============================================================================
# RESHADE SETUP  (optional, runs after crosshair setup)
# =============================================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host "   OPTIONAL: ReShade Visual Enhancements" -ForegroundColor DarkCyan
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  ReShade is a free tool that can make your arcade games look better"
Write-Host "  on modern screens. It works by applying real-time visual effects"
Write-Host "  on top of the game -- your game files are never touched."
Write-Host ""
Write-Host "  Popular effects:"
Write-Host "    Sharpening   -- removes the blurry look of upscaled games"
Write-Host "    CRT scanlines -- makes games look like an authentic arcade monitor"
Write-Host "    Colour boost  -- makes older games more vivid and punchy"
Write-Host "    Borders       -- adds decorative bezel artwork around the game"
Write-Host ""
Write-Host "  Your games work perfectly WITHOUT ReShade -- this is 100% optional."
Write-Host "  It can be removed at any time by deleting one file from a game folder."
Write-Host "  Press Home while in-game to open the ReShade overlay and pick effects."
Write-Host ""
if ($Unattended) {
    $doReShade = "N"
    Write-Log "Unattended: ReShade setup skipped."
} else {
    $doReShade = (Read-Host "Set up ReShade visual enhancements for your games? (Y/N)").Trim().ToUpper()
}
$rsSetupDone = $false
if ($doReShade -eq "Y") {
    # Locate 64-bit DLL: bundled copy first, then config, then prompt
    $bundledDll2   = Join-Path $PSScriptRoot "ReShade\ReShade64.dll"
    $bundledDll2_32 = Join-Path $PSScriptRoot "ReShade\ReShade32.dll"
    if (-not $rsSourceDll -or -not (Test-Path -LiteralPath $rsSourceDll)) {
        if (Test-Path -LiteralPath $bundledDll2) {
            $rsSourceDll = $bundledDll2
        } else {
            Write-Host ""
            Write-Host "  ReShade 64-bit DLL not found." -ForegroundColor Yellow
            Write-Host "  To get it:" -ForegroundColor Cyan
            Write-Host "    1. Download the installer from  https://reshade.me" -ForegroundColor White
            Write-Host "    2. Run it and point it at any TeknoParrot game exe." -ForegroundColor White
            Write-Host "       It will create a DLL file (e.g. dxgi.dll) in that game folder." -ForegroundColor White
            Write-Host "    3. Copy that DLL to  $PSScriptRoot\ReShade\  and rename it  ReShade64.dll" -ForegroundColor White
            Write-Host "       Then re-run this script and choose option 4 from the menu." -ForegroundColor White
            Write-Host "    -- OR --" -ForegroundColor DarkCyan
            Write-Host "    Enter the full path to the DLL file now:" -ForegroundColor White
            Write-Host ""
            $rsInp = Read-PathWithBrowse "  Path to ReShade 64-bit DLL (or press Enter to skip)" -Mode File -FileFilter "DLL files (*.dll)|*.dll|All files (*.*)|*.*"
            if (-not [string]::IsNullOrWhiteSpace($rsInp) -and (Test-Path -LiteralPath $rsInp) -and
                ([System.IO.Path]::GetExtension($rsInp).ToLower() -eq '.dll')) {
                $rsSourceDll = $rsInp
            } else {
                if (-not [string]::IsNullOrWhiteSpace($rsInp)) {
                    Write-Host "  File not found or is not a .dll -- ReShade setup skipped." -ForegroundColor DarkGray
                } else {
                    Write-Host "  ReShade setup skipped." -ForegroundColor DarkGray
                }
                Write-Log "ReShade post-run: skipped -- DLL not found or invalid."
                $doReShade = "N"
            }
        }
        if ($doReShade -eq "Y") {
            if (Save-Config) {
                Write-Log "Config: saved ReShadeSourceDll = $rsSourceDll"
            } else {
                Write-Log "Config: could not save ReShadeSourceDll"
            }
        }
    }
    # Auto-detect bundled 32-bit DLL; no error if absent.
    if (-not $rsSourceDll32 -or -not (Test-Path -LiteralPath $rsSourceDll32)) {
        if (Test-Path -LiteralPath $bundledDll2_32) { $rsSourceDll32 = $bundledDll2_32 }
    }
    if ($doReShade -eq "Y") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " ReShade Visual Enhancements Setup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        $rsSetupDone = $true
        Invoke-ReShadeSetup -UserProfilesDir $userProfilesDir `
                            -SourceDll $rsSourceDll `
                            -SourceDll32 $rsSourceDll32 `
                            -ConfigPath $configPath `
                            -TpRoot $tpRoot `
                            -Mode $mode `
                            -ZipSource $zipSource `
                            -GamesInstallFolder $gamesInstallFolder `
                            -RetroBat $retroBat `
                            -HsDataPath $hsDataPath
    }
}
# =============================================================================
# DGVOODOO2 SETUP  (optional, runs after ReShade setup)
# =============================================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host "   OPTIONAL: dgVoodoo2 Legacy Compatibility" -ForegroundColor DarkCyan
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Some older arcade games use DirectX 8, DirectDraw, or the Glide API"
Write-Host "  from 3dfx. On modern PCs these can cause crashes, black screens, or"
Write-Host "  missing graphics."
Write-Host ""
Write-Host "  dgVoodoo2 is a free compatibility layer that translates those old"
Write-Host "  graphics calls into modern DirectX 11/12. It works by placing small"
Write-Host "  DLL files in the game folder -- your original game files are never changed."
Write-Host ""
Write-Host "  Only run this for games that crash or show black screens on first launch."
Write-Host "  Games that run fine do not need it."
Write-Host ""
if ($Unattended) {
    $doDgVoodoo = "N"
    Write-Log "Unattended: dgVoodoo2 setup skipped."
} else {
    $doDgVoodoo = (Read-Host "Set up dgVoodoo2 for old DX8/Glide games? (Y/N)").Trim().ToUpper()
}
if ($doDgVoodoo -eq "Y") {
    $bundledDg2 = Join-Path $PSScriptRoot "dgVoodoo2"
    if (-not $dgSourceDir -or -not (Test-Path -LiteralPath $dgSourceDir)) {
        if (Test-Path -LiteralPath $bundledDg2) {
            $dgSourceDir = $bundledDg2
        } else {
            Write-Host ""
            Write-Host "  dgVoodoo2 DLL folder not found." -ForegroundColor Yellow
            Write-Host "  To get dgVoodoo2:" -ForegroundColor Cyan
            Write-Host "    1. Download the latest ZIP from  https://dege.freeweb.hu/dgVoodoo2/dgVoodoo2/" -ForegroundColor White
            Write-Host "    2. Open the ZIP and copy these files into a new folder called  dgVoodoo2\" -ForegroundColor White
            Write-Host "       next to this script:" -ForegroundColor White
            Write-Host "         From the MS\x86\ subfolder : D3D8.dll  DDraw.dll  D3DImm.dll" -ForegroundColor White
            Write-Host "         From the 3Dfx\x86\ subfolder : Glide2x.dll  Glide3x.dll" -ForegroundColor White
            Write-Host "         From the root of the ZIP   : dgVoodoo.conf" -ForegroundColor White
            Write-Host "       Then re-run this script and choose option 5 from the menu." -ForegroundColor White
            Write-Host "    -- OR --" -ForegroundColor DarkCyan
            Write-Host "    Enter the full path to a folder that already contains those files:" -ForegroundColor White
            Write-Host ""
            $dgInp = Read-PathWithBrowse "  Path to dgVoodoo2 folder (or press Enter to skip)"
            if (-not [string]::IsNullOrWhiteSpace($dgInp) -and (Test-Path -LiteralPath $dgInp)) {
                $dgSourceDir = $dgInp
            } else {
                if (-not [string]::IsNullOrWhiteSpace($dgInp)) {
                    Write-Host "  Folder not found -- dgVoodoo2 setup skipped." -ForegroundColor DarkGray
                } else {
                    Write-Host "  dgVoodoo2 setup skipped." -ForegroundColor DarkGray
                }
                Write-Log "dgVoodoo2 post-run: skipped -- folder not found."
                $doDgVoodoo = "N"
            }
        }
        if ($doDgVoodoo -eq "Y") {
            if (Save-Config) {
                Write-Log "Config: saved DgVoodoo2SourceDir = $dgSourceDir"
            } else {
                Write-Log "Config: could not save DgVoodoo2SourceDir"
            }
        }
    }
}
$dgSetupDone = $false
if ($doDgVoodoo -eq "Y") {
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " dgVoodoo2 Legacy Compatibility Setup" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    $dgSetupDone = $true
    Invoke-DgVoodoo2Setup -UserProfilesDir $userProfilesDir `
                          -SourceDir $dgSourceDir `
                          -TpRoot $tpRoot
}
# =============================================================================
# GPU FIX SETUP  (optional, runs after dgVoodoo2 setup)
# =============================================================================

Write-Host ""
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host "   OPTIONAL: GPU Compatibility Fixes" -ForegroundColor DarkCyan
Write-Host "============================================" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Some games include settings that fix graphical issues specific to"
Write-Host "  AMD, NVIDIA, or Intel graphics cards. This step auto-detects your"
Write-Host "  GPU and applies the right fix to every registered game that has one."
Write-Host ""
Write-Host "  Safe to run any time -- re-run if you change or update your GPU."
Write-Host ""
if ($dryRunActive) {
    $doGpuFix = "N"
    Write-Log "PreviewMode: GPU fix setup offer skipped."
} elseif ($Unattended) {
    $doGpuFix = "N"
    Write-Log "Unattended: GPU fix setup skipped."
} else {
    $doGpuFix = (Read-Host "Apply GPU compatibility fixes for your games? (Y/N)").Trim().ToUpper()
}
$gpuSetupDone = $false
if ($doGpuFix -eq "Y") {
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " GPU Compatibility Fix Setup" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    $gpuSetupDone = $true
    Invoke-GpuFixSetup -UserProfilesDir $userProfilesDir `
                       -TpRoot $tpRoot
}
# =============================================================================
# ACTION REQUIRED -- collects everything the user must do manually
# =============================================================================

$compatWarnings = Get-CompatibilityWarnings -UserProfilesDir $userProfilesDir
$setupNotes     = Get-GameSetupNotes -UserProfilesDir $userProfilesDir

$hasAnyAction = ($manualRegData.Count -gt 0) -or ($amb2.Count -gt 0) -or
                ($nf.Count -gt 0) -or ($noArchetypeItems.Count -gt 0) -or
                ($result.Unmatched.Count -gt 0) -or
                ($compatWarnings.PathTooLong.Count -gt 0) -or
                ($compatWarnings.DllMismatch.Count -gt 0) -or
                ($compatWarnings.GpuIncompatible.Count -gt 0) -or
                ($setupNotes.Count -gt 0)

if ($hasAnyAction) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Yellow
    Write-Host "   ACTION REQUIRED" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Yellow

    # -- 1. Games needing manual registration ---------------------------------
    if ($manualRegData.Count -gt 0) {
        Write-Host ""
        Write-Host "  REGISTER THESE GAMES IN TEKNOPARROTUI" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  The script found these games on disk but cannot register them" -ForegroundColor DarkCyan
        Write-Host "  automatically. Either the name of the executable file is shared" -ForegroundColor DarkCyan
        Write-Host "  by multiple TeknoParrot profiles, or the one profile it matches" -ForegroundColor DarkCyan
        Write-Host "  is already pointed at a different copy of this game." -ForegroundColor DarkCyan
        Write-Host "  Open TeknoParrotUI -> Add Game -> select the profile -> browse" -ForegroundColor DarkCyan
        Write-Host "  to the executable shown below." -ForegroundColor DarkCyan
        Write-Host ""
        foreach ($folderName in ($manualRegData.Keys | Sort-Object)) {
            $info    = $manualRegData[$folderName]
            $count   = $info.ProfileCount
            $exeName = $info.ExeName
            Write-Host "  Game   : $folderName" -ForegroundColor Yellow
            Write-Host "  Run    : $exeName" -ForegroundColor DarkGray
            if ($info.Reason -eq "duplicate") {
                $claimedBy = if ($info.ClaimedBy) { $info.ClaimedBy } else { "another folder" }
                Write-Host ("  Note   : profile '{0}' is already used by: {1}" -f $info.Profiles, $claimedBy) -ForegroundColor Cyan
                Write-Host "           TeknoParrot can only point one profile at one executable -- this" -ForegroundColor DarkCyan
                Write-Host "           copy needs its own profile, or you must choose which copy to use." -ForegroundColor DarkCyan
                Write-Host ""
                continue
            }
            if ($info.BestGuess -and $info.BestScore -ge 0.40) {
                Write-Host ("  Best guess : {0}  (similarity {1} -- below auto-register threshold {2})" -f `
                    $info.BestGuess, $info.BestScore, $FuzzyAutoThreshold) -ForegroundColor Cyan
            }
            if ($count -le 15) {
                Write-Host "  Profiles ($count) : $($info.Profiles)" -ForegroundColor DarkCyan
            } else {
                Write-Host "  Profiles : shared by $count games -- search by game name in TeknoParrotUI" -ForegroundColor DarkCyan
            }
            Write-Host ""
        }
    }

    # -- 2. Repair: broken paths that could not be auto-fixed -----------------
    if ($amb2.Count -gt 0) {
        $byExe = @{}
        foreach ($r in $amb2) {
            $k = $r.Exe
            if (-not $byExe.ContainsKey($k)) { $byExe[$k] = [System.Collections.Generic.List[string]]::new() }
            $byExe[$k].Add($r.Code)
        }
        Write-Host "  FIX THESE GAME PATHS IN TEKNOPARROTUI" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  These profiles exist but have a broken or empty path to their" -ForegroundColor DarkCyan
        Write-Host "  game. The script could not repair them automatically because" -ForegroundColor DarkCyan
        Write-Host "  the executable name is shared by multiple TeknoParrot profiles." -ForegroundColor DarkCyan
        Write-Host "  Open TeknoParrotUI, find each profile, and point it to the" -ForegroundColor DarkCyan
        Write-Host "  correct game folder." -ForegroundColor DarkCyan
        Write-Host ""
        foreach ($exeName in ($byExe.Keys | Sort-Object)) {
            $codes = ($byExe[$exeName] | Sort-Object) -join ", "
            Write-Host "  Executable : $exeName" -ForegroundColor Yellow
            Write-Host "  Profiles   : $codes" -ForegroundColor DarkGray
            Write-Host ""
        }
    }

    # -- 3. Games not yet extracted (informational) ---------------------------
    if ($nf.Count -gt 0) {
        Write-Host "  EXTRACT THESE GAMES FIRST, THEN RE-RUN REPAIR" -ForegroundColor DarkCyan
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  These profiles exist but their game has not been extracted to" -ForegroundColor DarkCyan
        Write-Host "  your staging folder yet. No action needed now -- use AutoSync" -ForegroundColor DarkCyan
        Write-Host "  to extract the game, then re-run the script and choose Repair." -ForegroundColor DarkCyan
        Write-Host ""
        $lineLen = 70; $line = "  "; $first = $true
        foreach ($item in ($nf | Sort-Object Code | ForEach-Object { $_.Code })) {
            $add = if ($first) { $item } else { ", $item" }
            if (($line + $add).Length -gt $lineLen) {
                Write-Host $line -ForegroundColor DarkGray
                $line = "  $item"; $first = $false
            } else { $line += $add; $first = $false }
        }
        if ($line.Trim()) { Write-Host $line -ForegroundColor DarkGray }
        Write-Host ""
    }

    # -- 4. Control types with no reference game bound yet --------------------
    if ($noArchetypeItems.Count -gt 0) {
        $byFamily = @{}
        foreach ($r in $noArchetypeItems) {
            if (-not $byFamily.ContainsKey($r.Family)) { $byFamily[$r.Family] = [System.Collections.Generic.List[string]]::new() }
            $byFamily[$r.Family].Add($r.Code)
        }
        $familyExamples = @{
            'button'    = 'Street Fighter III, BlazBlue, Tekken 7, Dead or Alive 5'
            'driving'   = 'Daytona Championship USA, Initial D, OutRun 2 SP, F-Zero AX'
            'lightgun'  = 'House of the Dead 4, Aliens Extermination, Point Blank, Rambo'
            'trackball' = 'Golden Tee Live, Silver Strike Bowling, Target Toss Pro'
            'spinner'   = 'any spinner-based game in TeknoParrot'
            'analog'    = 'any analog-stick game in TeknoParrot'
        }
        Write-Host ""
        Write-Host "  SET UP CONTROLS FOR THESE GAME TYPES IN TEKNOPARROTUI" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  These games could not receive controls automatically because" -ForegroundColor DarkCyan
        Write-Host "  you have not yet set up controls for that type of game." -ForegroundColor DarkCyan
        Write-Host "  Pick ONE game of each type, bind it fully in TeknoParrotUI" -ForegroundColor DarkCyan
        Write-Host "  (every button, axis, Test, Service, Coin, Start), then" -ForegroundColor DarkCyan
        Write-Host "  re-run this script and choose Propagate." -ForegroundColor DarkCyan
        Write-Host ""
        foreach ($family in ($byFamily.Keys | Sort-Object)) {
            $codes      = ($byFamily[$family] | Sort-Object) -join ", "
            $suggestion = if ($familyExamples.ContainsKey($family)) { $familyExamples[$family] } else { "any $family game in TeknoParrot" }
            Write-Host ("  {0} GAMES  ({1} game(s) waiting for controls):" -f $family.ToUpper(), $byFamily[$family].Count) -ForegroundColor Yellow
            Write-Host "  Waiting : $codes" -ForegroundColor DarkGray
            Write-Host "  Pick one to bind first: $suggestion" -ForegroundColor DarkCyan
            Write-Host ""
        }
    }

    # -- 5. Game folders not recognised by TeknoParrot ------------------------
    if ($result.Unmatched.Count -gt 0) {
        Write-Host ""
        Write-Host "  GAME FOLDERS NOT RECOGNISED BY TEKNOPARROT" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  These folders contained game files but none of their" -ForegroundColor DarkCyan
        Write-Host "  executables matched any profile in TeknoParrot's library." -ForegroundColor DarkCyan
        Write-Host "  They are likely games TeknoParrot does not yet support, or" -ForegroundColor DarkCyan
        Write-Host "  utilities / launchers that live alongside your games." -ForegroundColor DarkCyan
        Write-Host "  No action is required -- this is informational only." -ForegroundColor DarkCyan
        Write-Host ""
        $lineLen = 70; $line = "  "; $firstU = $true
        foreach ($folder in $result.Unmatched) {
            $add = if ($firstU) { $folder } else { ", $folder" }
            if (($line + $add).Length -gt $lineLen) {
                Write-Host $line -ForegroundColor DarkGray
                $line = "  $folder"; $firstU = $false
            } else { $line += $add; $firstU = $false }
        }
        if ($line.Trim()) { Write-Host $line -ForegroundColor DarkGray }
        Write-Host ""
    }

    # -- 6. Raw Thrills games whose install path is too long ------------------
    if ($compatWarnings.PathTooLong.Count -gt 0) {
        Write-Host ""
        Write-Host "  PATH TOO LONG -- THESE GAMES MAY FAIL TO LAUNCH" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  These specific games have a hard-coded limit on how long their" -ForegroundColor DarkCyan
        Write-Host "  full install path can be. Past that limit, the game will not start." -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  HOW TO FIX:" -ForegroundColor DarkCyan
        Write-Host "    1. Close TeknoParrot if it is open." -ForegroundColor DarkCyan
        Write-Host "    2. Move/rename the game's folder to the short name shown below," -ForegroundColor DarkCyan
        Write-Host "       placed as close to a drive root as possible (e.g. D:\TPGames\<name>)." -ForegroundColor DarkCyan
        Write-Host "    3. Re-run this script (mode 1 or 2) and choose Repair when offered." -ForegroundColor DarkCyan
        Write-Host ""
        foreach ($w in ($compatWarnings.PathTooLong | Sort-Object Code)) {
            Write-Host ("  Game        : {0}" -f $w.Code) -ForegroundColor Yellow
            Write-Host ("  Current path: {0} characters (limit ~{1})" -f $w.Length, $w.Limit) -ForegroundColor DarkGray
            Write-Host ("  Rename to   : {0}" -f $w.Suggested) -ForegroundColor Cyan
            Write-Host ""
        }
    }

    # -- 7. iDmacDrv32.dll version pins (BlazBlue-series) ----------------------
    if ($compatWarnings.DllMismatch.Count -gt 0) {
        Write-Host ""
        Write-Host "  FILE VERSION MISMATCH -- THESE GAMES NEED A SPECIFIC OLDER FILE" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  These games require a SPECIFIC OLDER version of a particular file." -ForegroundColor DarkCyan
        Write-Host "  A newer version causes errors (e.g. a coin error) and the game will" -ForegroundColor DarkCyan
        Write-Host "  not start correctly. This is the opposite of the usual fix -- do NOT" -ForegroundColor DarkCyan
        Write-Host "  let TeknoParrot redeploy its current copy here, that makes it worse." -ForegroundColor DarkCyan
        Write-Host ""
        Write-Host "  HOW TO FIX:" -ForegroundColor DarkCyan
        Write-Host "    1. Join the TeknoParrot Discord (linked from teknoparrot.com)." -ForegroundColor DarkCyan
        Write-Host "    2. In the #fixes channel, ask for or search for the file named" -ForegroundColor DarkCyan
        Write-Host "       below, matching the required CRC32 shown for your game." -ForegroundColor DarkCyan
        Write-Host "    3. Replace that file in the game's own folder with the one you got." -ForegroundColor DarkCyan
        Write-Host ""
        foreach ($w in ($compatWarnings.DllMismatch | Sort-Object Code)) {
            Write-Host ("  Game           : {0}" -f $w.Code) -ForegroundColor Yellow
            Write-Host ("  File           : {0}" -f $w.FileName) -ForegroundColor DarkGray
            Write-Host ("  Current CRC32  : {0}" -f $w.Found) -ForegroundColor DarkGray
            Write-Host ("  Required CRC32 : {0}" -f $w.Required) -ForegroundColor Cyan
            Write-Host ""
        }
    }

    # -- 8. Games known not to work on the detected GPU vendor (informational) -
    if ($compatWarnings.GpuIncompatible.Count -gt 0) {
        $gpuVendorSeen = $compatWarnings.GpuIncompatible[0].Vendor
        Write-Host ""
        Write-Host ("  KNOWN {0} GPU INCOMPATIBILITY -- NO FIX AVAILABLE" -f $gpuVendorSeen.ToUpper()) -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ("  These registered games are confirmed NOT to work on {0} GPUs." -f $gpuVendorSeen) -ForegroundColor DarkCyan
        Write-Host "  This is a known limitation of the game/emulation layer, not a setup" -ForegroundColor DarkCyan
        Write-Host "  mistake on your end -- there is no fix to apply. Informational only." -ForegroundColor DarkCyan
        Write-Host ""
        $lineLen = 70; $line = "  "; $firstG = $true
        foreach ($w in ($compatWarnings.GpuIncompatible | Sort-Object Code | ForEach-Object { $_.Code })) {
            $add = if ($firstG) { $w } else { ", $w" }
            if (($line + $add).Length -gt $lineLen) {
                Write-Host $line -ForegroundColor DarkGray
                $line = "  $w"; $firstG = $false
            } else { $line += $add; $firstG = $false }
        }
        if ($line.Trim()) { Write-Host $line -ForegroundColor DarkGray }
        Write-Host ""
    }

    # -- 9. Game-specific setup notes (informational) -------------------------
    if ($setupNotes.Count -gt 0) {
        Write-Host ""
        Write-Host "  GAME-SPECIFIC SETUP NOTES" -ForegroundColor Yellow
        Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "  These registered games have special setup notes from the community" -ForegroundColor DarkCyan
        Write-Host "  compatibility database. Read them before troubleshooting blind." -ForegroundColor DarkCyan
        Write-Host ""
        $sortedNotes = @($setupNotes | Sort-Object Code)
        for ($i = 0; $i -lt $sortedNotes.Count; $i++) {
            $sn = $sortedNotes[$i]
            Write-Host ("  Game : {0} ({1})" -f $sn.Code, $sn.GameName) -ForegroundColor Yellow
            if ($sn.SetupExe) { Write-Host ("  Run  : {0}" -f $sn.SetupExe) -ForegroundColor DarkGray }
            Write-Host "  Notes:" -ForegroundColor Cyan
            foreach ($line in (Format-NoteLines -Text $sn.Notes)) { Write-Host $line -ForegroundColor DarkCyan }
            Write-Host ""
            if ($i -lt ($sortedNotes.Count - 1)) {
                Write-Host "  ----------------------------------------------------------" -ForegroundColor DarkGray
                Write-Host ""
            }
        }
    }

    Write-Host "============================================" -ForegroundColor Yellow

    $defaultActionPath = Join-Path $PSScriptRoot "TeknoParrot-Manager-ActionItems.txt"
    $actionPath = $defaultActionPath
    if (-not $Unattended -and -not $dryRunActive) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
            $saveDialog.Title            = "Save Action Required summary"
            $saveDialog.InitialDirectory = $PSScriptRoot
            $saveDialog.FileName         = "TeknoParrot-Manager-ActionItems.txt"
            $saveDialog.Filter           = "Text files (*.txt)|*.txt|All files (*.*)|*.*"
            $saveDialog.OverwritePrompt  = $true
            if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $actionPath = $saveDialog.FileName
            } else {
                Write-Log "Action items: save dialog cancelled, using default path."
            }
        } catch {
            Write-Log "Action items: save dialog failed, using default path -- $_"
        }
    }
    $asb = New-Object System.Text.StringBuilder
    [void]$asb.AppendLine("TeknoParrot Manager - Action Required")
    [void]$asb.AppendLine("Generated: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
    [void]$asb.AppendLine("============================================================")
    if ($manualRegData.Count -gt 0) {
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("REGISTER THESE GAMES IN TEKNOPARROTUI")
        [void]$asb.AppendLine("----------------------------------------------------------")
        [void]$asb.AppendLine("Open TeknoParrotUI -> Add Game -> select the profile -> browse to the executable.")
        foreach ($fn in ($manualRegData.Keys | Sort-Object)) {
            $ai = $manualRegData[$fn]
            [void]$asb.AppendLine("")
            [void]$asb.AppendLine("  Game     : $fn")
            [void]$asb.AppendLine("  Run      : $($ai.ExeName)")
            if ($ai.Reason -eq "duplicate") {
                $claimedBy = if ($ai.ClaimedBy) { $ai.ClaimedBy } else { "another folder" }
                [void]$asb.AppendLine("  Note     : profile '$($ai.Profiles)' is already used by: $claimedBy")
                [void]$asb.AppendLine("             TeknoParrot can only point one profile at one executable -- this copy")
                [void]$asb.AppendLine("             needs its own profile, or you must choose which copy to use.")
                continue
            }
            if ($ai.BestGuess -and $ai.BestScore -ge 0.40) {
                [void]$asb.AppendLine(("  Best guess: {0}  (similarity {1})" -f $ai.BestGuess, $ai.BestScore))
            }
            if ($ai.ProfileCount -le 15) {
                [void]$asb.AppendLine("  Profiles ($($ai.ProfileCount)): $($ai.Profiles)")
            } else {
                [void]$asb.AppendLine("  Profiles : shared by $($ai.ProfileCount) games -- search by name in TeknoParrotUI")
            }
        }
    }
    if ($amb2.Count -gt 0) {
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("FIX THESE GAME PATHS IN TEKNOPARROTUI")
        [void]$asb.AppendLine("----------------------------------------------------------")
        $aByExe = @{}
        foreach ($r in $amb2) {
            if (-not $aByExe.ContainsKey($r.Exe)) { $aByExe[$r.Exe] = [System.Collections.Generic.List[string]]::new() }
            $aByExe[$r.Exe].Add($r.Code)
        }
        foreach ($exeN in ($aByExe.Keys | Sort-Object)) {
            [void]$asb.AppendLine("")
            [void]$asb.AppendLine("  Executable : $exeN")
            [void]$asb.AppendLine("  Profiles   : $(($aByExe[$exeN] | Sort-Object) -join ', ')")
        }
    }
    if ($nf.Count -gt 0) {
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("EXTRACT THESE GAMES FIRST, THEN RE-RUN REPAIR")
        [void]$asb.AppendLine("----------------------------------------------------------")
        foreach ($item in ($nf | Sort-Object Code | ForEach-Object { $_.Code })) { [void]$asb.AppendLine("  $item") }
    }
    if ($noArchetypeItems.Count -gt 0) {
        $aByFam = @{}
        foreach ($r in $noArchetypeItems) {
            if (-not $aByFam.ContainsKey($r.Family)) { $aByFam[$r.Family] = [System.Collections.Generic.List[string]]::new() }
            $aByFam[$r.Family].Add($r.Code)
        }
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("SET UP CONTROLS FOR THESE GAME TYPES IN TEKNOPARROTUI")
        [void]$asb.AppendLine("----------------------------------------------------------")
        [void]$asb.AppendLine("Bind one game of each type fully, then re-run and choose Register.")
        foreach ($fam in ($aByFam.Keys | Sort-Object)) {
            [void]$asb.AppendLine("")
            [void]$asb.AppendLine(("  {0} GAMES ({1} waiting):" -f $fam.ToUpper(), $aByFam[$fam].Count))
            [void]$asb.AppendLine("  $( ($aByFam[$fam] | Sort-Object) -join ', ' )")
        }
    }
    if ($result.Unmatched.Count -gt 0) {
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("GAME FOLDERS NOT RECOGNISED BY TEKNOPARROT (informational)")
        [void]$asb.AppendLine("----------------------------------------------------------")
        foreach ($folder in ($result.Unmatched | Sort-Object)) { [void]$asb.AppendLine("  $folder") }
    }
    if ($compatWarnings.PathTooLong.Count -gt 0) {
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("PATH TOO LONG -- THESE GAMES MAY FAIL TO LAUNCH")
        [void]$asb.AppendLine("----------------------------------------------------------")
        [void]$asb.AppendLine("How to fix: close TeknoParrot, move/rename the folder to the short name")
        [void]$asb.AppendLine("shown below (placed near a drive root, e.g. D:\TPGames\<name>), then")
        [void]$asb.AppendLine("re-run this script and choose Repair when offered.")
        foreach ($w in ($compatWarnings.PathTooLong | Sort-Object Code)) {
            [void]$asb.AppendLine("")
            [void]$asb.AppendLine("  Game        : $($w.Code)")
            [void]$asb.AppendLine("  Current path: $($w.Length) characters (limit ~$($w.Limit))")
            [void]$asb.AppendLine("  Rename to   : $($w.Suggested)")
        }
    }
    if ($compatWarnings.DllMismatch.Count -gt 0) {
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("FILE VERSION MISMATCH -- THESE GAMES NEED A SPECIFIC OLDER FILE")
        [void]$asb.AppendLine("----------------------------------------------------------")
        [void]$asb.AppendLine("How to fix: join the TeknoParrot Discord (linked from teknoparrot.com),")
        [void]$asb.AppendLine("ask in #fixes for the file named below matching the required CRC32, and")
        [void]$asb.AppendLine("replace that file in the game's own folder. Do NOT let TeknoParrot")
        [void]$asb.AppendLine("redeploy its current copy here -- that makes it worse, not better.")
        foreach ($w in ($compatWarnings.DllMismatch | Sort-Object Code)) {
            [void]$asb.AppendLine("")
            [void]$asb.AppendLine("  Game           : $($w.Code)")
            [void]$asb.AppendLine("  File           : $($w.FileName)")
            [void]$asb.AppendLine("  Current CRC32  : $($w.Found)")
            [void]$asb.AppendLine("  Required CRC32 : $($w.Required)")
        }
    }
    if ($compatWarnings.GpuIncompatible.Count -gt 0) {
        $gpuVendorSeen = $compatWarnings.GpuIncompatible[0].Vendor
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("KNOWN $($gpuVendorSeen.ToUpper()) GPU INCOMPATIBILITY -- NO FIX AVAILABLE (informational)")
        [void]$asb.AppendLine("----------------------------------------------------------")
        [void]$asb.AppendLine("These games are confirmed not to work on $gpuVendorSeen GPUs. Known")
        [void]$asb.AppendLine("limitation, not a setup mistake -- there is no fix to apply.")
        foreach ($w in ($compatWarnings.GpuIncompatible | Sort-Object Code)) { [void]$asb.AppendLine("  $($w.Code)") }
    }
    if ($setupNotes.Count -gt 0) {
        [void]$asb.AppendLine(""); [void]$asb.AppendLine("GAME-SPECIFIC SETUP NOTES (informational)")
        [void]$asb.AppendLine("----------------------------------------------------------")
        $sortedNotesFile = @($setupNotes | Sort-Object Code)
        for ($i = 0; $i -lt $sortedNotesFile.Count; $i++) {
            $sn = $sortedNotesFile[$i]
            [void]$asb.AppendLine("")
            [void]$asb.AppendLine("  Game : $($sn.Code) ($($sn.GameName))")
            if ($sn.SetupExe) { [void]$asb.AppendLine("  Run  : $($sn.SetupExe)") }
            [void]$asb.AppendLine("  Notes:")
            foreach ($line in (Format-NoteLines -Text $sn.Notes)) { [void]$asb.AppendLine($line) }
            if ($i -lt ($sortedNotesFile.Count - 1)) {
                [void]$asb.AppendLine(""); [void]$asb.AppendLine("----------------------------------------------------------")
            }
        }
    }
    try {
        [System.IO.File]::WriteAllText($actionPath, $asb.ToString(), (New-Object System.Text.UTF8Encoding $false))
        Write-Host ""
        Write-Host "  Action items saved to:" -ForegroundColor Green
        Write-Host "  $actionPath" -ForegroundColor Cyan
        Write-Host "  Open that file to review everything you need to do manually." -ForegroundColor DarkCyan
        Write-Log "Action items written to $actionPath"
    } catch {
        Write-Log "Action items: could not write file -- $_"
    }
}

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "   1. Launch TeknoParrotUi.exe -- registered games now appear."
Write-Host "   2. Work through the ACTION REQUIRED items above."
Write-Host "   3. Bind one game of each control type, then re-run and propagate."
Write-Host "   4. Test one propagated game before trusting the rest."
if ($rsSetupDone) {
    Write-Host ""
    Write-Host "  ReShade:" -ForegroundColor Cyan
    Write-Host "   - Launch any game that had ReShade installed."
    Write-Host "   - Press the  Home  key to open the effects overlay."
    Write-Host "   - Tick the effects you want and adjust with the sliders."
    Write-Host "   - Settings save automatically -- you only need to do this once per game."
    Write-Host "   - To remove ReShade from a game: delete dxgi.dll / d3d9.dll /"
    Write-Host "     opengl32.dll from that game's folder. Nothing else is affected."
}
if ($dgSetupDone) {
    Write-Host ""
    Write-Host "  dgVoodoo2:" -ForegroundColor Cyan
    Write-Host "   - Launch each game that had dgVoodoo2 installed and test it."
    Write-Host "   - If a game now crashes that worked before, the DLL may conflict --"
    Write-Host "     delete D3D8.dll / DDraw.dll / Glide2x.dll / Glide3x.dll from that"
    Write-Host "     game's folder to revert. Your game files are not affected."
}
Write-Host ""
Write-Host "  Crosshairs:" -ForegroundColor Cyan
Write-Host ("   - Custom crosshair images are in:  {0}" -f (Join-Path $PSScriptRoot "Crosshairs\"))
Write-Host "   - You can add your own PNG images to that folder at any time."
Write-Host "   - Run mode 4 (Crosshair setup) to preview and deploy them to lightgun games."
Write-Host ""

    if ($dryRunActive -and -not $Unattended) {
        $applyNow = (Read-Host "  Apply these changes for real now? (Y/N)").Trim().ToUpper()
        if ($applyNow -eq "Y") {
            $pendingApplyMode = $mode
            Write-Log "PreviewMode: user chose to apply for real -- re-entering $mode."
            continue
        }
    }

    [void](Read-Host "  Press Enter to return to menu")
} # end while ($true)
} catch {
    $errMsg  = $_.Exception.Message
    $errFull = "FATAL ERROR (unhandled): $($_.Exception)`nStack: $($_.ScriptStackTrace)"
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "  FATAL ERROR -- script aborted" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ("  {0}" -f $errMsg) -ForegroundColor Red
    Write-Host "  Full details have been written to:" -ForegroundColor Yellow
    Write-Host ("  {0}" -f (Join-Path $PSScriptRoot "TeknoParrot-Manager.log")) -ForegroundColor Yellow
    try { Write-Log $errFull } catch {}
    [void](Read-Host "  Press Enter to exit")
    exit 1
}
