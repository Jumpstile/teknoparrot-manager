# =============================================================================
# TeknoParrot Manager  |  v0.65 BETA
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

param([switch]$Unattended)

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       TeknoParrot Manager  v0.65 BETA" -ForegroundColor Cyan
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
        Add-Content -LiteralPath $logPath -Value $line -ErrorAction Stop
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

# Reads the primary ExecutableName from a profile XML using a fast regex pass,
# avoiding a full DOM parse for every file during the index scan. The regex
# matches <ExecutableName> exactly (not <ExecutableName2>). Falls back to a
# full parse if the quick read finds nothing.
function Get-PrimaryExecutableName {
    param([string]$path)
    try {
        $raw = [System.IO.File]::ReadAllText($path)
        $raw = [regex]::Replace($raw, '(?s)<!--.*?-->', '')   # strip XML comments before matching
        $m = [regex]::Match($raw, '<ExecutableName>\s*([^<]+?)\s*</ExecutableName>')
        if ($m.Success) { return $m.Groups[1].Value }
    } catch { }
    try {
        $x = Read-Xml $path
        if ($x.GameProfile) { return [string]$x.GameProfile.ExecutableName }
    } catch { }
    return $null
}

# Returns $true when $path resolves to a network location (UNC or mapped drive).
function Test-IsNetworkPath {
    param([string]$path)
    if ([string]::IsNullOrWhiteSpace($path)) { return $false }
    $path = $path.TrimEnd('\', '/')   # normalise trailing separators before matching
    if ($path -match '^\\\\') { return $true }
    if ($path -match '^([A-Za-z]):') {
        $letter = $Matches[1] + ':'
        try {
            $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$letter'" -ErrorAction Stop
            if ($disk.DriveType -eq 4) { return $true }   # 4 = Network Drive
        } catch {}
    }
    return $false
}

# Reads up to 100 MB from the largest ZIP in $path and returns MB/s, or $null.
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

# True if $child is the same folder as, or inside, $parent. Paths are fully
# resolved and compared case-insensitively. Used to keep the staging folder out
# of the emulator and source folders.
function Test-PathInside {
    param([string]$child, [string]$parent)
    try {
        $c = [System.IO.Path]::GetFullPath($child).TrimEnd('\','/')
        $p = [System.IO.Path]::GetFullPath($parent).TrimEnd('\','/')
    } catch { return $false }
    if ($c -eq $p) { return $true }
    return $c.StartsWith($p + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
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
    $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
                Where-Object { $_.Root -and -not (Test-IsNetworkPath $_.Root) -and (Test-Path -LiteralPath $_.Root) } |
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
    return ,$found
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
        $ba[$k] = ($ba[$k] -as [int]) + 1
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
# Browse and Search both feed into the same queue. Returns array of base names,
# or an empty array to mean "all games".
function Select-GamesInteractive {
    param([string]$zipSource, [string]$installFolder)

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
        return @()
    }

    # Build a normalised folder map of what is already extracted in the
    # destination, using the same convention-agnostic logic as AutoSync.
    $normalizedFolderMap = @{}
    foreach ($dir in (Get-ChildItem -LiteralPath $installFolder -Directory -ErrorAction SilentlyContinue)) {
        $norm = ($dir.Name -replace '\.(teknoparrot|parrot|game)$', '') -replace ' (?=[\[\(])', ''
        if (-not $normalizedFolderMap.ContainsKey($norm)) {
            $normalizedFolderMap[$norm] = $dir.FullName
        }
    }

    # Split the ZIP list into already-extracted (non-empty folder exists) and
    # not-yet-extracted. The picker only shows the not-yet-extracted ones.
    $alreadyExtracted = @()
    $toExtract        = @()
    foreach ($zip in $all) {
        $norm         = $zip.BaseName -replace ' (?=[\[\(])', ''
        $existingPath = $normalizedFolderMap[$norm]
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
        return @()
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
            return @()   # empty = no whitelist = extract everything
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
            if ($queue.Count -eq 0) {
                Write-Host "  Queue is empty. Use A to extract all games, or select some first." -ForegroundColor Yellow
            } else {
                $done = $true
            }
        }
    }

    if ($queue.Count -gt 0) {
        Write-Host ""
        Write-Host "  Final queue ($($queue.Count) game(s)):" -ForegroundColor Green
        foreach ($g in $queue) { Write-Host "    + $g" -ForegroundColor Green }
    } else {
        Write-Host "  No games selected." -ForegroundColor Yellow
    }

    return ,$queue
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
        try { [void]$fs.Read($bytes, 0, 8) } finally { $fs.Dispose() }
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
        return @()
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

# Fetches the current ReShade version string from reshade.me.
# Returns e.g. "6.7.3", or $null if the site cannot be reached.
function Get-ReShadeLatestVersion {
    try {
        $resp = Invoke-WebRequest -Uri "https://reshade.me" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($resp.Content -match 'ReShade_Setup_(\d+\.\d+\.\d+)') { return $Matches[1] }
    } catch {}
    return $null
}

# Full ReShade install wizard: version check, preset choice, game picker, deploy.
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
    $presetChoice = (Read-Host "  Enter 1 or 2").Trim()
    $presetPath   = $null
    if ($presetChoice -eq "2") {
        $pInp = (Read-Host "  Path to your ReShade preset (.ini) file").Trim()
        if (Test-Path -LiteralPath $pInp) {
            $presetPath = $pInp
            Write-Host "  Preset: $pInp" -ForegroundColor DarkGray
        } else {
            Write-Host "  File not found -- continuing without preset." -ForegroundColor Yellow
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
    $deployed = 0; $skipped = 0; $errors = 0

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

            $emuType = ""
            $etNode  = $doc.GameProfile.SelectSingleNode("EmulatorType")
            if ($etNode) { $emuType = $etNode.InnerText.Trim() }

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

            # OpenParrot games: files go into the openparrot subfolder
            $targetDir = $exeDir
            if ($emuType -imatch 'openparrot') {
                $opDir = Join-Path $exeDir "openparrot"
                if (Test-Path -LiteralPath $opDir) { $targetDir = $opDir }
            }

            # BudgieLoader games always use opengl32.dll; others: detect from exe
            if ($emuType -imatch 'budgieloader') {
                $dllName = "opengl32.dll"
            } else {
                $detected = Get-GameApiDll -ExePath $gamePath
                if ($detected) {
                    $dllName = $detected
                } else {
                    $dllName = "dxgi.dll"
                    Write-Host ("    {0}: graphics API not detected, defaulting to dxgi.dll" -f $pf.BaseName) -ForegroundColor Yellow
                }
            }

            $destDll = Join-Path $targetDir $dllName
            Copy-Item -LiteralPath $activeDll -Destination $destDll -Force -ErrorAction Stop
            if ($presetPath) {
                Copy-Item -LiteralPath $presetPath -Destination (Join-Path $targetDir "ReShade.ini") `
                          -Force -ErrorAction Stop
            }
            Write-Host ("    {0}  [{1}]" -f $pf.BaseName, $dllName) -ForegroundColor Green
            Write-Log "ReShade: $($pf.BaseName) -> $targetDir [$dllName]"
            $deployed++
        } catch {
            Write-Host ("    FAILED {0}: {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "ReShade: FAILED $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Installed : {0} game(s)" -f $deployed) -ForegroundColor Green
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
    Write-Log ("ReShade setup: Installed={0} Skipped={1} Errors={2}" -f $deployed, $skipped, $errors)
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
    $deployed = 0; $skipped = 0; $errors = 0
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
            if ($hasConf) {
                $dstConf = Join-Path $exeDir "dgVoodoo.conf"
                if (-not (Test-Path -LiteralPath $dstConf)) {
                    Copy-Item -LiteralPath (Join-Path $SourceDir "dgVoodoo.conf") -Destination $dstConf -ErrorAction Stop
                }
            }
            $apiStr = if ($apis.Count -gt 0) { "  [{0}]" -f ($apis -join ', ') } else { "" }
            Write-Host ("  OK    {0}{1}" -f $pf.BaseName, $apiStr) -ForegroundColor Green
            Write-Log ("dgVoodoo2: deployed {0} to {1}" -f ($toDeploy -join ', '), $exeDir)
            $deployed++

        } catch {
            Write-Host ("  ERROR {0} -- {1}" -f $pf.BaseName, $_) -ForegroundColor Red
            Write-Log "dgVoodoo2: error on $($pf.BaseName) -- $_"
            $errors++
        }
    }

    Write-Host ""
    Write-Host ("  Deployed  : {0} game(s)" -f $deployed) -ForegroundColor Green
    if ($skipped -gt 0) { Write-Host ("  Skipped   : {0}" -f $skipped) -ForegroundColor DarkGray }
    if ($errors  -gt 0) { Write-Host ("  Errors    : {0}" -f $errors)  -ForegroundColor Red      }
    Write-Host ""
    Write-Host "  To uninstall: delete the deployed DLL file(s) from the game folder." -ForegroundColor DarkCyan
    Write-Host "  Your original game files are never modified." -ForegroundColor DarkCyan
    Write-Log ("dgVoodoo2 setup: deployed={0} skipped={1} errors={2}" -f $deployed, $skipped, $errors)
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
    $gpuVendor = $null
    $gpuName   = $null
    try {
        $adapters = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop |
            Where-Object { $_.Name -notmatch '(?i)microsoft|virtual|remote' } |
            Sort-Object { if ($_.AdapterRAM) { [double]$_.AdapterRAM } else { 0.0 } } -Descending)
        if ($adapters.Count -gt 0) {
            $gpuName = $adapters[0].Name
            if     ($gpuName -imatch 'amd|radeon')                 { $gpuVendor = 'AMD'    }
            elseif ($gpuName -imatch 'nvidia|geforce|rtx|gtx')     { $gpuVendor = 'NVIDIA' }
            elseif ($gpuName -imatch 'intel')                      { $gpuVendor = 'Intel'  }
        }
    } catch {
        Write-Host ("  WARNING: GPU detection failed -- {0}" -f $_) -ForegroundColor Yellow
    }

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
    $gpDir         = Join-Path $TpRoot "GameProfiles"
    $boolAmdFields = [System.Collections.Generic.HashSet[string]]::new(
                         [string[]]@('EnableAmdFix','AMDCrashFix','AMDFix'),
                         [System.StringComparer]::OrdinalIgnoreCase)
    $dropdownGpuFields = [System.Collections.Generic.HashSet[string]]::new(
                             [string[]]@('GPU Fix'),
                             [System.StringComparer]::OrdinalIgnoreCase)

    if (Test-Path -LiteralPath $gpDir) {
        Write-Host "  Scanning GameProfiles for GPU fix fields..." -ForegroundColor DarkGray
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
        Write-Log ("GPU Fix: discovered fields -- Bool AMD: [{0}]  Dropdown GPU: [{1}]" -f `
            ($boolAmdFields -join ', '), ($dropdownGpuFields -join ', '))
    } else {
        Write-Host ("  GameProfiles folder not found at '{0}' -- using built-in field list." -f $gpDir) -ForegroundColor DarkGray
        Write-Log "GPU Fix: GameProfiles not found at $gpDir -- using fallback field list."
    }

    # -- Walk UserProfiles ------------------------------------------------------
    Write-Host ""
    Write-Host "  Applying GPU fixes to registered profiles..." -ForegroundColor DarkGray
    $profiles  = @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter "*.xml" -ErrorAction SilentlyContinue)
    $updated   = 0
    $unchanged = 0
    $errors    = 0

    foreach ($pf in $profiles) {
        try {
            $doc = Read-Xml $pf.FullName
            $changed = $false

            # Bool AMD fix fields: 1 for AMD users, 0 for everyone else.
            foreach ($fieldName in $boolAmdFields) {
                $xpLit = ConvertTo-XPathStringLiteral $fieldName
                $fi = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$xpLit]")
                if ($null -eq $fi) { continue }
                $fvNode = $fi.SelectSingleNode("FieldValue")
                if ($null -eq $fvNode) { continue }
                $newVal = if ($gpuVendor -eq 'AMD') { '1' } else { '0' }
                if ($fvNode.InnerText -ne $newVal) {
                    $oldVal           = $fvNode.InnerText
                    $fvNode.InnerText = $newVal
                    $changed          = $true
                    Write-Log "GPU Fix: $($pf.BaseName) :: $fieldName $oldVal -> $newVal"
                }
            }

            # GPU Fix dropdown fields: pick best available option for the detected vendor.
            foreach ($fieldName in $dropdownGpuFields) {
                $xpLit = ConvertTo-XPathStringLiteral $fieldName
                $fi = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName=$xpLit]")
                if ($null -eq $fi) { continue }
                $fvNode = $fi.SelectSingleNode("FieldValue")
                $opts   = @($fi.SelectNodes("FieldOptions/string") | ForEach-Object { $_.InnerText.Trim() })
                if ($null -eq $fvNode -or $opts.Count -eq 0) { continue }

                $newVal = 'None'
                if ($gpuVendor -eq 'AMD') {
                    if     ($opts -contains 'New AMD Driver') { $newVal = 'New AMD Driver' }
                    elseif ($opts -contains 'AMD')            { $newVal = 'AMD'            }
                } elseif ($gpuVendor -eq 'NVIDIA') {
                    if ($opts -contains 'NVIDIA') { $newVal = 'NVIDIA' }
                } elseif ($gpuVendor -eq 'Intel') {
                    if ($opts -contains 'INTEL') { $newVal = 'INTEL' }
                }

                if ($fvNode.InnerText -ne $newVal) {
                    $oldVal           = $fvNode.InnerText
                    $fvNode.InnerText = $newVal
                    $changed          = $true
                    Write-Log "GPU Fix: $($pf.BaseName) :: $fieldName $oldVal -> $newVal"
                }
            }

            if ($changed) {
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
        [System.IO.File]::WriteAllLines($IniPath, $out.ToArray(), (New-Object System.Text.UTF8Encoding $false))
        Write-Log "Crosshairs: updated PCSX2.ini at $IniPath"
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

    # Pick P1
    $p1Idx = $null
    while ($null -eq $p1Idx) {
        $raw = (Read-Host ("  P1 crosshair index (0-{0})" -f ($valid.Count - 1))).Trim()
        if ($raw -match '^\d+$' -and $raw.Length -le 9 -and [int]$raw -lt $valid.Count) { $p1Idx = [int]$raw }
        else { Write-Host ("  Enter a number between 0 and {0}." -f ($valid.Count - 1)) -ForegroundColor Yellow }
    }
    # Pick P2
    $p2Idx = $null
    while ($null -eq $p2Idx) {
        $raw = (Read-Host ("  P2 crosshair index (0-{0}, or same as P1)" -f ($valid.Count - 1))).Trim()
        if ($raw -match '^\d+$' -and $raw.Length -le 9 -and [int]$raw -lt $valid.Count) { $p2Idx = [int]$raw }
        else { Write-Host ("  Enter a number between 0 and {0}." -f ($valid.Count - 1)) -ForegroundColor Yellow }
    }

    $p1Name = [System.IO.Path]::GetFileNameWithoutExtension($valid[$p1Idx])
    $p2Name = [System.IO.Path]::GetFileNameWithoutExtension($valid[$p2Idx])
    Write-Host ""
    Write-Host "  P1: $p1Name    P2: $p2Name" -ForegroundColor Green
    Write-Log "Crosshairs: P1=$p1Name  P2=$p2Name"

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
            if (-not (Test-Path -LiteralPath $exeDir)) { $skipped++; continue }

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
                $fi = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='$fieldName']")
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
    param([string]$ZipPath, [string]$DestDir)

    # GetFullPath on the (short) base is safe. We deliberately avoid calling
    # GetFullPath on the combined base+entry path: on .NET 4.x (PS 5.1) that
    # throws PathTooLongException before \\?\ is ever applied, defeating the
    # whole purpose of this function.
    $destFull = [System.IO.Path]::GetFullPath($DestDir).TrimEnd('\')
    $archive  = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
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
                [void][System.IO.Directory]::CreateDirectory('\\?\' + $destFull + '\' + $rel.TrimEnd('\'))
                continue
            }

            $longTarget = '\\?\' + $destFull + '\' + $rel
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
    } finally { $archive.Dispose() }
}

# Extracts NAS ZIPs to a local folder. Tracks state to skip unchanged games.
# Never deletes local games. ZIP base names listed in $noSync are skipped.
# If $onlySync is non-empty, only ZIPs whose base name is in the list are extracted.
function Invoke-AutoSync {
    param([string]$zipSource, [string]$installFolder, [string]$syncStatePath,
          $noSync = @(), $onlySync = @(), [bool]$retroBat = $false)

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
        return @{ Synced = 0; UpToDate = 0; Failed = 0; Skipped = 0 }
    }

    $synced = 0; $upToDate = 0; $failed = 0; $skipped = 0

    if ($onlySync.Count -gt 0) {
        Write-Host "  Whitelist active: only extracting $($onlySync.Count) game(s) listed in onlySync." -ForegroundColor Cyan
    }

    # Build a normalised-name map of every folder already in the staging
    # directory. Normalisation removes spaces immediately before ( or [ so that
    # "Game (ver) [Platform] [TP]" (old convention) and
    # "Game(ver)[Platform][TP]" (new convention) map to the same key.
    # This prevents AutoSync from creating duplicate folders when a game was
    # extracted under the old naming convention and the ZIP now uses the new one.
    $normalizedFolderMap = @{}
    foreach ($dir in (Get-ChildItem -LiteralPath $installFolder -Directory -ErrorAction SilentlyContinue)) {
        $norm = ($dir.Name -replace '\.(teknoparrot|parrot|game)$', '') -replace ' (?=[\[\(])', ''
        if (-not $normalizedFolderMap.ContainsKey($norm)) {
            $normalizedFolderMap[$norm] = $dir.FullName
        }
    }

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
        # Sentinel lives next to the game folder (not inside it) so we do not
        # need to pre-create the game directory. Expand-Archive creates the
        # directory itself; pre-creating it caused PS 5.1 to throw "already
        # exists" even when -Force was supplied.
        $sentinel   = Join-Path $installFolder "$extractFolderName.extracting"
        $nasModStr  = $zip.LastWriteTimeUtc.ToString("o")
        $stored     = $syncState[$rawName]

        # Resolve an existing folder using the normalised map, which matches
        # both exact names and old-convention names for the same game.
        $normZip       = $rawName -replace ' (?=[\[\(])', ''
        $matchedFolder = if ($normalizedFolderMap.ContainsKey($normZip)) { $normalizedFolderMap[$normZip] } else { $null }

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
        } elseif ($stored.NasSize -ne $zip.Length -or $stored.NasLastModified -ne $nasModStr) {
            $needsSync = $true; $reason = "changed on NAS"
        } elseif (-not (($stored.LocalPath -and (Test-Path -LiteralPath $stored.LocalPath)) -or (Test-Path -LiteralPath $extractDir))) {
            $needsSync = $true; $reason = "not extracted"
        } elseif (Test-Path -LiteralPath $sentinel) {
            $needsSync = $true; $reason = "incomplete previous extraction"
        }

        if (-not $needsSync) { Write-Host "  Up to date : $rawName" -ForegroundColor DarkGray; $upToDate++; continue }

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
            Set-Content -LiteralPath $sentinel -Value "" -Encoding UTF8 -ErrorAction Stop

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
                Expand-ZipFileSafe -ZipPath $zip.FullName -DestDir $extractDir
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
                Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
                $failed++
            }
        } catch {
            # Reached only when Set-Content failed (sentinel could not be created).
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

    try { [System.IO.File]::WriteAllText($syncStatePath, ($syncState | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding $false)) }
    catch { Write-Log "AutoSync: WARNING -- could not save sync state: $_" }

    return @{ Synced = $synced; UpToDate = $upToDate; Failed = $failed; Skipped = $skipped }
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
        while ($reader.Read()) {
            if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                $currentElem = $reader.Name
                if ($currentElem -eq 'game') {
                    $gameName    = $reader.GetAttribute('name')
                    $profCode    = ''
                    $exePath     = ''
                    $insideGame  = $true
                } elseif ($currentElem -eq 'rom' -and $insideGame) {
                    $reader.Skip()   # skip hundreds of hash entries per game
                    $currentElem = ''
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
                $m = [regex]::Match($ln, '\(([A-Za-z0-9_]+)\)\s*$')
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
    try {
        $apiUri = 'https://api.github.com/repos/teknogods/TeknoParrotUI/git/trees/master?recursive=1'
        $resp   = Invoke-WebRequest -Uri $apiUri -UseBasicParsing -TimeoutSec 20 `
                      -Headers @{ 'User-Agent' = 'TeknoParrot-Manager/0.65' }
        $tree   = ($resp.Content | ConvertFrom-Json).tree
        $prefix = 'TeknoParrotUi.Common/GameProfiles/'
        foreach ($node in $tree) {
            if ($node.type -eq 'blob' -and $node.path -like ($prefix + '*.xml')) {
                $stem = [System.IO.Path]::GetFileNameWithoutExtension($node.path.Substring($prefix.Length))
                if ($stem -match '^[\w]+$') { [void]$result.Add($stem) }
            }
        }
        if ($result.Count -gt 0) {
            Write-Log "ProfileSet (GitHub): $($result.Count) profiles from teknogods/TeknoParrotUI."
            $loaded = $true
        } else {
            Write-Log "ProfileSet (GitHub): 0 profiles returned -- API may have changed."
        }
    } catch {
        Write-Log "ProfileSet (GitHub): query failed -- $_"
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
    return $code
}

# Queries the GitHub API for the latest Eggman dat release asset.
# Uses the "teknoparrot" tag which Eggmansworld updates with each release.
# Returns [pscustomobject]@{DownloadUrl; FileName; SizeMB} or $null on failure.
function Get-EggmanDatRelease {
    try {
        $apiUri = 'https://api.github.com/repos/Eggmansworld/Datfiles/releases/tags/teknoparrot'
        $resp   = Invoke-WebRequest -Uri $apiUri -UseBasicParsing -TimeoutSec 20 `
                      -Headers @{ 'User-Agent' = 'TeknoParrot-Manager/0.65' }
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
        Write-Log "EggmanDat: GitHub release query failed -- $_"
        return $null
    }
}

# Downloads the Eggman dat ZIP. Uses BITS (shows a progress bar) with an
# Invoke-WebRequest fallback. Cleans up any partial file on failure.
function Invoke-EggmanDatDownload {
    param([string]$downloadUrl, [string]$savePath)
    try {
        $bitsOk = $false
        try {
            Start-BitsTransfer -Source $downloadUrl -Destination $savePath `
                -Description "TeknoParrot Eggman dat" `
                -DisplayName "Downloading dat ZIP..." `
                -ErrorAction Stop
            $bitsOk = $true
        } catch {
            Write-Log "EggmanDat: BITS transfer failed (${_}), trying Invoke-WebRequest."
        }
        if (-not $bitsOk) {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $savePath -UseBasicParsing -ErrorAction Stop
        }
        return $true
    } catch {
        Write-Host ("  Download failed: {0}" -f $_) -ForegroundColor Red
        Write-Log "EggmanDat: download failed -- $_"
        try { if (Test-Path -LiteralPath $savePath) { [System.IO.File]::Delete($savePath) } } catch {}
        return $false
    }
}

# Scans the install folder for executables and registers matching TeknoParrot
# profiles by setting <GamePath> in a copy written to UserProfiles. Three passes:
#   1 -- exe filename -> profile index (built from <ExecutableName> in GameProfile XMLs)
#   2 -- dat lookup for folders whose exe name is not in any profile
#   3 -- Dice-match normalised folder name against profile code names, resolving
#        games with empty <ExecutableName> (BladeStrangers, LuigisMansion, etc.)
# Existing UserProfiles are never overwritten.
function Register-Games {
    param([string]$userProfilesDir, [string]$installFolder, [hashtable]$profileIndex,
          [string]$gameProfilesDir = '', [hashtable]$datIndex = $null,
          [System.Collections.Generic.HashSet[string]]$profileSet = $null)

    if ($null -eq $datIndex) { $datIndex = @{} }

    $exeFiles       = Get-GameFiles $installFolder
    $registered     = New-Object System.Collections.ArrayList
    $already        = New-Object System.Collections.ArrayList
    $ambiguous      = New-Object System.Collections.ArrayList
    $seenCodes      = @{}
    $installBase    = $installFolder.TrimEnd('\')
    $matchedFolders = @{}   # folders that matched at least one profile key
    $allExeFolders  = @{}   # folders containing any recognisable executable

    foreach ($exe in $exeFiles) {
        $relPath    = $exe.FullName.Substring($installBase.Length).TrimStart('\')
        $folderName = ($relPath -split '\\')[0]
        $folderKey  = $folderName -replace '\.(teknoparrot|parrot|game)$', ''   # strip suffix for matching/tracking
        $allExeFolders[$folderKey] = $folderName   # store original name (with any suffix) for path resolution

        $key = $exe.Name.ToLower()
        if (-not $profileIndex.ContainsKey($key)) { continue }
        $matchedFolders[$folderKey] = $true

        $matchList = $profileIndex[$key]

        # Same executable name maps to more than one profile.
        # Attempt folder-name fuzzy matching before giving up.
        if ($matchList.Count -gt 1) {
            # $folderKey has the RetroBat suffix stripped, ready to normalise.
            $normFolder  = Get-NormalizedGameKey $folderKey

            $bestFuzzy      = $null
            $bestFuzzyScore = 0.0
            foreach ($cand in $matchList) {
                $normCode = Get-NormalizedGameKey $cand.Code
                $score    = Get-DiceSimilarity $normFolder $normCode
                if ($score -gt $bestFuzzyScore) { $bestFuzzyScore = $score; $bestFuzzy = $cand }
            }

            if ($bestFuzzyScore -ge $FuzzyAutoThreshold -and $null -ne $bestFuzzy) {
                # High-confidence fuzzy match: register automatically.
                $code = $bestFuzzy.Code
                if ($seenCodes.ContainsKey($code)) { continue }
                $userProfile = Join-Path $userProfilesDir ($code + ".xml")
                if (Test-Path -LiteralPath $userProfile) {
                    [void]$already.Add($code); $seenCodes[$code] = $true
                } else {
                    # Mark seen before the file operation so that if Save throws,
                    # a second exe match for the same code doesn't cause a duplicate
                    # attempt (and duplicate error output) within the same run.
                    $seenCodes[$code] = $true
                    try {
                        $tpl = Read-Xml $bestFuzzy.TemplatePath
                        $gp  = $tpl.GameProfile.SelectSingleNode("GamePath")
                        if ($null -eq $gp) {
                            $gp = $tpl.CreateElement("GamePath")
                            [void]$tpl.GameProfile.PrependChild($gp)
                        }
                        $gp.InnerText = $exe.FullName
                        Save-Xml $tpl $userProfile
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
                if ($alreadyReg.Count -gt 0) {
                    foreach ($ar in $alreadyReg) {
                        if (-not $seenCodes.ContainsKey($ar.Code)) {
                            [void]$already.Add($ar.Code)
                            $seenCodes[$ar.Code] = $true
                        }
                    }
                } else {
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
                            if (-not $seenCodes.ContainsKey($datCode)) {
                                $seenCodes[$datCode] = $true
                                if (Test-Path -LiteralPath $userProfile) {
                                    [void]$already.Add($datCode)
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
                                            Save-Xml $tpl $userProfile
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
                                        })
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
                            })
                        }
                    } else {
                        # Below threshold with no dat entry: flag for manual registration.
                        [void]$ambiguous.Add([pscustomobject]@{
                            Exe       = $exe.FullName
                            Codes     = ($matchList | ForEach-Object { $_.Code }) -join ", "
                            BestGuess = if ($null -ne $bestFuzzy) { $bestFuzzy.Code } else { $null }
                            BestScore = [Math]::Round($bestFuzzyScore, 2)
                        })
                    }
                }
            }
            continue
        }

        $match = $matchList[0]
        $code  = $match.Code
        if ($seenCodes.ContainsKey($code)) { continue }

        $userProfile = Join-Path $userProfilesDir ($code + ".xml")
        if (Test-Path -LiteralPath $userProfile) {
            [void]$already.Add($code)
            $seenCodes[$code] = $true
            continue
        }

        # Mark seen before the file operation for the same reason as the fuzzy
        # path: prevents a duplicate attempt if a second matching exe is found.
        $seenCodes[$code] = $true
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
            Save-Xml $tpl $userProfile
            [void]$registered.Add([pscustomobject]@{ Code = $code; GamePath = $exe.FullName })
            Write-Log "Registered $code -> $($exe.FullName)"
        } catch {
            Write-Host "  FAILED to register $code : $_" -ForegroundColor Red
            Write-Log "Register FAILED $code -- $_"
        }
    }

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

            if ($seenCodes.ContainsKey($datCode)) { continue }
            $seenCodes[$datCode] = $true

            $userProfile = Join-Path $userProfilesDir ($datCode + ".xml")
            if (Test-Path -LiteralPath $userProfile) {
                [void]$already.Add($datCode)
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
                Save-Xml $tpl $userProfile
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

            if ($seenCodes.ContainsKey($bestCode)) { continue }
            $seenCodes[$bestCode] = $true

            $userProfile = Join-Path $userProfilesDir ($bestCode + ".xml")
            if (Test-Path -LiteralPath $userProfile) {
                [void]$already.Add($bestCode)
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
                Save-Xml $tpl $userProfile
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
    param([string]$userProfilesDir, [string]$installFolder, [hashtable]$profileIndex)

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
        try { $doc = Read-Xml $f.FullName } catch { continue }
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
            Save-Xml $doc $f.FullName
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "fixed"; NewPath = $newPath })
            Write-Log "Repair: fixed $($f.BaseName) -> $newPath"
        } catch {
            Write-Log "Repair: FAILED to save $($f.Name) -- $_"
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "save-failed" })
        }
    }
    return $reports
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
            "AnalogJoystick"        { $hasGun = $true }
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
    $f = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='Input API']")
    if ($null -eq $f) { return $null }
    $v = $f.SelectSingleNode("FieldValue")
    if ($null -eq $v) { return $null }
    return $v.InnerText.Trim()
}

# Sets the "Input API" FieldValue, but only if the field exists AND lists the
# requested API among its options. Returns $true on success. This matters
# because a RawInput binding will not work if the profile's API says XInput.
function Set-ProfileInputApi {
    param($doc, [string]$api)
    $f = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='Input API']")
    if ($null -eq $f) { return $false }
    $opts = @($f.SelectNodes("FieldOptions/string") | ForEach-Object { $_.InnerText.Trim() })
    if ($opts -notcontains $api) { return $false }
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
    $fi = $doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='$name']")
    if ($null -eq $fi) { return $false }
    $fv = $fi.SelectSingleNode("FieldValue")
    if ($null -eq $fv) { return $false }
    $fv.InnerText = $value
    return $true
}

# Scans UserProfiles and returns the bound-game pool: every profile that the
# user has bound to a meaningful degree (>= $minBound bound buttons). Each
# entry carries its family, Input API, and a map of (key -> bound button node)
# used as the source of truth for copying.
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
    param([string]$userProfilesDir, $pool, [int]$minBound, $noPropagate = @(), $forceArchetype = @{}, $familyOverride = @{})

    $reports     = New-Object System.Collections.ArrayList
    $files       = Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue
    $sourcePaths = @{}
    foreach ($s in $pool) { $sourcePaths[$s.Path] = $true }

    foreach ($f in $files) {
        if ($sourcePaths.ContainsKey($f.FullName)) { continue }   # never modify an archetype
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
        if ($alreadyBound -ge $minBound) {
            [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "skipped-bound" })
            continue
        }

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
                [void]$reports.Add([pscustomobject]@{ Code = $f.BaseName; Status = "no-archetype"; Family = $targetFamily })
                continue
            }
        }

        $boundNow = 0
        $manual   = New-Object System.Collections.ArrayList
        foreach ($b in @($btns)) {                     # @() snapshots before tree edits
            if (Test-ButtonIsBound $b) { continue }
            $k        = Get-ButtonKey $b
            $nameNode = $b.SelectSingleNode("ButtonName")
            $btnName  = if ($nameNode) { $nameNode.InnerText } else { "" }
            if ($k -and $best.Map.ContainsKey($k)) {
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
            Save-Xml $doc $f.FullName
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
    if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $backups.Count) {
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
    Get-ChildItem -LiteralPath $userProfilesDir | Where-Object { $_.Name -ne "FullBackup" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -ErrorVariable deleteErrs
    if ($deleteErrs.Count -gt 0) {
        Write-Host ("  ERROR: {0} file(s) could not be removed." -f $deleteErrs.Count) -ForegroundColor Red
        Write-Host "  Make sure TeknoParrot is fully closed and no files are open, then try again." -ForegroundColor Yellow
        Write-Log "Restore: FAILED -- $($deleteErrs.Count) file(s) could not be removed."
        return
    }

    # Copy backup into UserProfiles
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
function Export-LaunchBoxXml {
    param([string]$userProfilesDir, [string]$tpRoot, [string]$outputPath)

    $tpExe = Join-Path $tpRoot "TeknoParrotUi.exe"
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

            $esc = [System.Security.SecurityElement]
            [void]$sb.AppendLine('  <Game>')
            [void]$sb.AppendLine("    <Title>$($esc::Escape($title))</Title>")
            [void]$sb.AppendLine("    <Platform>Arcade</Platform>")
            [void]$sb.AppendLine("    <ApplicationPath>$($esc::Escape($tpExe))</ApplicationPath>")
            [void]$sb.AppendLine("    <CommandLine>$($esc::Escape("--profile=$($f.Name)"))</CommandLine>")
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
            } catch { continue }
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
            } catch { continue }
        }
    }

    # No games file found -- create a new empty one named after the emulator title.
    # This eliminates the prerequisite of adding one game manually first.
    if (-not $tpGamesPath) {
        $safeName = ($tpEmu.title -replace '[^\w\-\.]', '_').Trim('_')
        if ([string]::IsNullOrEmpty($safeName)) { $safeName = 'TeknoParrot' }
        $tpGamesPath = Join-Path $gamesDir "$safeName.json"
        try {
            [System.IO.File]::WriteAllText($tpGamesPath, '[]', (New-Object System.Text.UTF8Encoding $false))
            Write-Log "HyperSpin export: created new games file at $tpGamesPath"
            $newFile = $true
        } catch {
            Write-Host "  ERROR: Could not create TeknoParrot games file: $_" -ForegroundColor Red
            Write-Log "HyperSpin export: could not create games file -- $_"
            return -1
        }
    }

    # Load existing game list
    try {
        $existing = New-Object System.Collections.ArrayList
        foreach ($g in (Get-Content -LiteralPath $tpGamesPath -Raw | ConvertFrom-Json)) {
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
        [System.IO.File]::WriteAllText($tpGamesPath, $json, (New-Object System.Text.UTF8Encoding $false))
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
        try {
            Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing `
                              -TimeoutSec 30 -ErrorAction Stop
            Write-Host "  OK" -ForegroundColor Green
            Write-Log "Thumbnails: downloaded $code"
            $fetched++
        } catch {
            $statusCode = 0
            if ($_.Exception.Response) {
                try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
            }
            if ($statusCode -eq 404) {
                Write-Host "  not in repo" -ForegroundColor DarkGray
                $notAvail++
            } else {
                Write-Host ("  FAILED ({0})" -f $_.Exception.Message) -ForegroundColor Red
                Write-Log "Thumbnails: FAILED $code -- $($_.Exception.Message)"
                $failed++
            }
            if (Test-Path -LiteralPath $destPath) {
                Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
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
        try { $doc = Read-Xml $f.FullName } catch { continue }
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
        if     ($poolCodes.ContainsKey($f.BaseName))  { $status = "REFERENCE" }
        elseif ($reportMap.ContainsKey($f.BaseName)) {
            $r = $reportMap[$f.BaseName]
            switch ($r.Status) {
                "bound"            { $status = "propagated"; $reference = $r.Archetype }
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

        [void]$rows.Add([pscustomobject]@{
            Code = $f.BaseName; Family = $family
            Bound = $bound; Total = $btns.Count
            Manual = $manual; Status = $status; Reference = $reference
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

Write-Log "Script started (v0.65$(if ($Unattended) { ' [Unattended]' }))."

# =============================================================================
# SECTION 1 -- Load or prompt for configuration
# =============================================================================

$configPath         = Join-Path $PSScriptRoot "TeknoParrot-Manager.config.json"
$tpRoot             = $null
$mode               = $null   # "AutoSync", "RegisterOnly", "Restore", "CrosshairSetup", or "ReShadeSetup"
$zipSource               = $null   # AutoSync only (main collection)
$zipSourceSupplementary  = ''      # AutoSync supplementary source (optional, separate library)
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
        Write-Host ""
        if ($Unattended) {
            Write-Host "  [Unattended] Using saved settings." -ForegroundColor DarkCyan
            Write-Log "Unattended: auto-accepted saved settings."
            $use = "Y"
        } else {
            $use = (Read-Host "Use these settings? (Y/N)").Trim()
        }
        if ($use.ToUpper() -eq "Y") {
            $tpRoot             = $cfg.TeknoParrotRoot
            $zipSource          = $cfg.ZipSourceFolder
            if ($cfg.ZipSourceSupplementaryFolder) { $zipSourceSupplementary = $cfg.ZipSourceSupplementaryFolder }
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
        if ($pick -match '^\d+$') {
            $idx = [int]$pick - 1
            if ($idx -ge 0 -and $idx -lt $detected.Count) { $tpRoot = $detected[$idx] }
        }
    }
    if (-not $tpRoot) {
        $tpRoot = (Read-Host "Enter TeknoParrot root folder (containing TeknoParrotUi.exe)").Trim()
    }
}

if (-not $gamesInstallFolder) {
    if ($Unattended) {
        Write-Host "ERROR: Unattended mode -- games install folder not in saved settings." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- gamesInstallFolder not set."; exit 1
    }
    $gamesInstallFolder = (Read-Host "Enter folder containing your extracted games (e.g. E:\TeknoParrotGames)").Trim()
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
            $defaultSavePath = Join-Path $PSScriptRoot $rel.FileName
            $rawSave = (Read-Host "  Save to (Enter for default: $defaultSavePath)").Trim()
            if (-not $rawSave) { $rawSave = $defaultSavePath }
            Write-Host "  Downloading -- this may take a few minutes..." -ForegroundColor Cyan
            $dlOk = Invoke-EggmanDatDownload $rel.DownloadUrl $rawSave
            if ($dlOk) {
                $eggmanDatZip = $rawSave
                Write-Host "  Saved: $rawSave" -ForegroundColor Green
                Write-Log "EggmanDat: downloaded to $rawSave"
                $askSupp = (Read-Host "  Also index supplementary dat for alternate version info? (Y/N)").Trim().ToUpper()
                $includeSupplementary = ($askSupp -eq 'Y')
                if ($includeSupplementary) { Write-Log "EggmanDat: supplementary indexing enabled." }
            } else {
                Write-Host "  Enter path to existing ZIP or .dat file, or press Enter to skip:" -ForegroundColor Yellow
                $raw      = (Read-Host "  Path").Trim()
                $datChoice = 'FALLBACK'
            }
        } else {
            Write-Host "  Could not reach GitHub. Enter path to existing ZIP or .dat file, or press Enter to skip:" -ForegroundColor Yellow
            $raw      = (Read-Host "  Path").Trim()
            $datChoice = 'FALLBACK'
        }
    }

    if ($datChoice -eq 'Z' -or $datChoice -eq 'FALLBACK') {
        if ($datChoice -eq 'Z') { $raw = (Read-Host "  Path to Eggman dat ZIP").Trim() }
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
        $rawColl = (Read-Host "  Path to collection dat file").Trim()
        if ($rawColl) {
            if (Test-Path -LiteralPath $rawColl) {
                $datFilePath = $rawColl
                Write-Log "Config: datFilePath (collection) set to $rawColl"
                Write-Host "  Supplementary dat (press Enter to skip):" -ForegroundColor DarkCyan
                $rawSupp = (Read-Host "  Path to supplementary dat file").Trim()
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

$cfgOut = [ordered]@{
    TeknoParrotRoot              = $tpRoot
    ZipSourceFolder              = $zipSource
    ZipSourceSupplementaryFolder = $zipSourceSupplementary
    GamesInstallFolder           = $gamesInstallFolder
    RetroBat           = $retroBat
    HyperSpinDataPath  = $hsDataPath
    ReShadeSourceDll   = $rsSourceDll
    ReShadeSourceDll32 = $rsSourceDll32
    DgVoodoo2SourceDir   = $dgSourceDir
    EggmanDatZip         = $eggmanDatZip
    DatFilePath          = $datFilePath
    SupplementaryDatPath = $supplementaryDatPath
    IncludeSupplementary = $includeSupplementary
}
try {
    [System.IO.File]::WriteAllText($configPath, ($cfgOut | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
} catch {
    Write-Host "  WARNING: Could not save configuration -- settings will not be remembered." -ForegroundColor Yellow
    Write-Log "Config: could not save -- $_"
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

$overridesPath     = Join-Path $PSScriptRoot "TeknoParrot-Manager.overrides.json"
$noSyncList        = @()
$onlySyncList      = @()
$noPropagateList   = @()
$forceArchetypeMap = @{}
$familyOverrideMap = @{}

if (-not (Test-Path -LiteralPath $overridesPath)) {
    $ovTemplate = [ordered]@{
        _comment       = "noSync/onlySync/noPropagate: lists of ZIP base names (without .zip). onlySync acts as a whitelist -- only listed games are extracted. forceArchetype: { GameCode: ArchetypeCode } pins a game to a specific reference game. familyOverride: { GameCode: 'button'|'driving'|'lightgun'|'trackball'|'analog' } overrides the auto-detected control family (fixes mis-classified games like FamilyGuyBowling). datFile: full path to a No-Intro TeknoParrot dat file; when set the script uses it to auto-register games with shared executable names (like game.exe) without needing fuzzy matching."
        noSync         = @()
        onlySync       = @()
        noPropagate    = @()
        forceArchetype = [ordered]@{}
        familyOverride = [ordered]@{}
        datFile        = ""
    }
    try { [System.IO.File]::WriteAllText($overridesPath, ($ovTemplate | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false)) }
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
            $validFamilies = @('button','driving','lightgun','trackball','analog','spinner')
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
        if ($ov.datFile -and -not [string]::IsNullOrWhiteSpace([string]$ov.datFile)) {
            $datFilePath = [string]$ov.datFile
        }
        $ovCount = $noSyncList.Count + $onlySyncList.Count + $noPropagateList.Count + $forceArchetypeMap.Count + $familyOverrideMap.Count
        if ($ovCount -gt 0 -or $datFilePath) {
            Write-Host ""
            $datLabel = if ($datFilePath) { ", datFile=yes" } else { "" }
            Write-Host "Overrides: noSync=$($noSyncList.Count), onlySync=$($onlySyncList.Count), noPropagate=$($noPropagateList.Count), pinned=$($forceArchetypeMap.Count), familyOverride=$($familyOverrideMap.Count)$datLabel" -ForegroundColor DarkCyan
        }
        Write-Log "Overrides: noSync=$($noSyncList.Count) onlySync=$($onlySyncList.Count) noPropagate=$($noPropagateList.Count) pinned=$($forceArchetypeMap.Count) familyOverride=$($familyOverrideMap.Count) datFile=$datFilePath"
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
    $mode = $null
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " Mode" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host "  1) AutoSync        -- Extract ZIPs (NAS or local) to a local"
    Write-Host "                        folder, then register the games."
    Write-Host "  2) Register only   -- Games are already extracted; just register."
    Write-Host "  3) Restore backup  -- Roll UserProfiles back to a previous backup."
    Write-Host "  4) Crosshair setup -- Pick and deploy custom crosshairs to all"
    Write-Host "                        registered lightgun games."
    Write-Host "  5) ReShade setup   -- Add visual enhancements (sharper image, better"
    Write-Host "                        colours, scanlines, borders). Optional -- games"
    Write-Host "                        work perfectly without this."
    Write-Host "  6) dgVoodoo2 setup -- Fix old DX8, DirectDraw, and Glide games that"
    Write-Host "                        crash or show black screens. Optional."
    Write-Host "  7) GPU fix setup   -- Auto-detect your GPU (AMD / NVIDIA / Intel) and"
    Write-Host "                        apply the matching compatibility fix to every"
    Write-Host "                        registered game that has one. Optional."
    Write-Host "  8) Exit"
    Write-Host ""
    if ($Unattended) {
        Write-Host "  [Unattended] Mode must be set before starting." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- reached menu loop."; exit 1
    }
    $modeChoice = (Read-Host "Enter 1, 2, 3, 4, 5, 6, 7, or 8").Trim()
    switch ($modeChoice) {
        "1"     { $mode = "AutoSync"       }
        "2"     { $mode = "RegisterOnly"   }
        "3"     { $mode = "Restore"        }
        "4"     { $mode = "CrosshairSetup" }
        "5"     { $mode = "ReShadeSetup"   }
        "6"     { $mode = "DgVoodoo2Setup" }
        "7"     { $mode = "GpuFixSetup"    }
        "8"     { break }
        default { Write-Host "  Invalid choice. Enter 1-8." -ForegroundColor Yellow; continue }
    }
    if ($modeChoice -eq "8") { break }

    if ($mode -eq "Restore") {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " Restore from Backup" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Invoke-RestoreBackup -userProfilesDir $userProfilesDir
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Host "   Done." -ForegroundColor Cyan
        Write-Host "============================================" -ForegroundColor Cyan
        Write-Log "Restore complete."
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
                $inp = (Read-Host "  Path to ReShade 64-bit DLL (or press Enter to cancel)").Trim()
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
            $cfgRS = [ordered]@{
                TeknoParrotRoot              = $tpRoot
                ZipSourceFolder              = $zipSource
                ZipSourceSupplementaryFolder = $zipSourceSupplementary
                GamesInstallFolder           = $gamesInstallFolder
                RetroBat                     = $retroBat
                HyperSpinDataPath            = $hsDataPath
                ReShadeSourceDll             = $rsSourceDll
                ReShadeSourceDll32           = $rsSourceDll32
                DgVoodoo2SourceDir           = $dgSourceDir
            }
            try {
                [System.IO.File]::WriteAllText($configPath, ($cfgRS | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
                Write-Log "Config: saved ReShadeSourceDll = $rsSourceDll"
            } catch { Write-Log "Config: could not save ReShadeSourceDll -- $_" }
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
                $inp = (Read-Host "  Path to dgVoodoo2 folder (or press Enter to cancel)").Trim()
                if ([string]::IsNullOrWhiteSpace($inp) -or -not (Test-Path -LiteralPath $inp)) {
                    Write-Host "  Folder not found. dgVoodoo2 setup cancelled." -ForegroundColor Red
                    Write-Log "dgVoodoo2 setup: aborted -- folder not found."
                    [void](Read-Host "  Press Enter to return to menu")
                    continue
                }
                $dgSourceDir = $inp
            }
            $cfgDg = [ordered]@{
                TeknoParrotRoot              = $tpRoot
                ZipSourceFolder              = $zipSource
                ZipSourceSupplementaryFolder = $zipSourceSupplementary
                GamesInstallFolder           = $gamesInstallFolder
                RetroBat                     = $retroBat
                HyperSpinDataPath            = $hsDataPath
                ReShadeSourceDll             = $rsSourceDll
                ReShadeSourceDll32           = $rsSourceDll32
                DgVoodoo2SourceDir           = $dgSourceDir
            }
            try {
                [System.IO.File]::WriteAllText($configPath, ($cfgDg | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
                Write-Log "Config: saved DgVoodoo2SourceDir = $dgSourceDir"
            } catch { Write-Log "Config: could not save DgVoodoo2SourceDir -- $_" }
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

    if ($mode -eq "AutoSync" -and -not $zipSource) {
        Write-Host ""
        Write-Host "  Main collection ZIP folder" -ForegroundColor Cyan
        Write-Host "  Point directly at the folder containing the .zip files, not a parent folder." -ForegroundColor DarkCyan
        Write-Host "  Example: W:\ROMS\TeknoParrot Collection" -ForegroundColor DarkCyan
        $zipSource = (Read-Host "  Path").Trim()
    }
    if ($mode -eq "AutoSync" -and -not $zipSourceSupplementary -and -not $Unattended) {
        Write-Host ""
        Write-Host "  Supplementary games folder (optional)" -ForegroundColor Cyan
        Write-Host "  Point directly at the folder containing the Supplementary .zip files, not a parent folder." -ForegroundColor DarkCyan
        Write-Host "  Example: W:\ROMS\TeknoParrot Supplementary" -ForegroundColor DarkCyan
        $rawSupp = (Read-Host "  Path (or press Enter to skip)").Trim()
        if ($rawSupp -and (Test-Path -LiteralPath $rawSupp)) {
            $zipSourceSupplementary = $rawSupp
            Write-Log "Config: supplementary ZIP source set to $rawSupp"
        } elseif ($rawSupp) {
            Write-Host "  Folder not found -- supplementary source skipped." -ForegroundColor Yellow
            Write-Log "Config: supplementary ZIP source not found at $rawSupp -- skipped."
        }
    }

    if ($mode -eq "AutoSync") {
        if (-not (Test-Path -LiteralPath $zipSource)) {
            Write-Host ""; Write-Host "ERROR: ZIP source folder not found: $zipSource" -ForegroundColor Red
            Write-Log "ERROR: ZIP source not found."; [void](Read-Host "  Press Enter to return to menu"); continue
        }
        if (Test-IsNetworkPath $gamesInstallFolder) {
            Write-Host ""; Write-Host "ERROR: The staging folder must be on a local drive." -ForegroundColor Red
            Write-Host "AutoSync extracts games locally for performance. Use e.g. D:\TeknoParrotGames." -ForegroundColor Yellow
            Write-Log "ERROR: staging folder is a network path."; [void](Read-Host "  Press Enter to return to menu"); continue
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

        if (Test-IsNetworkPath $zipSource) {
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

    $backupRoot = Join-Path $userProfilesDir "FullBackup"
    $timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
    $backupPath = Join-Path $backupRoot $timestamp

Write-Host ""
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

    # If onlySync is already populated from the overrides file, use it directly.
    # Otherwise drop straight into the interactive picker (which includes All/Browse/Search).
    if ($onlySyncList.Count -eq 0) {
        if ($Unattended) {
            Write-Host "  [Unattended] Game selection: all unextracted games." -ForegroundColor DarkCyan
            Write-Log "Unattended: game selection = all."
            # $onlySyncList stays empty -- Invoke-AutoSync treats empty as no filter (all games).
        } else {
            $onlySyncList = Select-GamesInteractive -zipSource $zipSource -installFolder $gamesInstallFolder
            if ($null -eq $onlySyncList -or $onlySyncList.Count -eq 0) {
                # Empty return means "All games" was chosen or nothing is left to extract.
                # Either way, pass an empty list to Invoke-AutoSync (= no filter).
                $onlySyncList = @()
            }
        }
    }

    $syncStatePath = Join-Path $gamesInstallFolder "TeknoParrot-Manager.syncstate.json"
    $sync = Invoke-AutoSync -zipSource $zipSource -installFolder $gamesInstallFolder -syncStatePath $syncStatePath -noSync $noSyncList -onlySync $onlySyncList -retroBat $retroBat

    # Supplementary source: separate picker and separate sync pass, same staging folder.
    $syncSupp = $null
    if ($zipSourceSupplementary -and -not (Test-Path -LiteralPath $zipSourceSupplementary)) {
        Write-Host "  WARNING: Supplementary ZIP folder not found: $zipSourceSupplementary" -ForegroundColor Yellow
        Write-Log "AutoSync: supplementary ZIP source not found at $zipSourceSupplementary -- skipped."
    } elseif ($zipSourceSupplementary -and (
                  (Test-PathInside $gamesInstallFolder $zipSourceSupplementary) -or
                  (Test-PathInside $zipSourceSupplementary $gamesInstallFolder))) {
        Write-Host "  ERROR: Supplementary ZIP folder overlaps the staging folder -- skipped." -ForegroundColor Red
        Write-Log "AutoSync: supplementary ZIP source overlaps staging folder -- skipped."
    } elseif ($zipSourceSupplementary -and (Test-PathInside $zipSourceSupplementary $tpRoot)) {
        Write-Host "  ERROR: Supplementary ZIP folder is inside the TeknoParrot folder -- skipped." -ForegroundColor Red
        Write-Log "AutoSync: supplementary ZIP source is inside TeknoParrot root -- skipped."
    } elseif ($zipSourceSupplementary) {
        Write-Host ""
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " AutoSync: Supplementary Games" -ForegroundColor Cyan
        Write-Host "--------------------------------------------" -ForegroundColor Cyan
        Write-Host " Supplementary source: $zipSourceSupplementary" -ForegroundColor DarkCyan
        Write-Host ""
        $onlySyncListSupp = @()
        if ($Unattended) {
            Write-Host "  [Unattended] Game selection: all unextracted supplementary games." -ForegroundColor DarkCyan
            Write-Log "Unattended: supplementary game selection = all."
        } else {
            $onlySyncListSupp = Select-GamesInteractive -zipSource $zipSourceSupplementary -installFolder $gamesInstallFolder
            if ($null -eq $onlySyncListSupp -or $onlySyncListSupp.Count -eq 0) {
                $onlySyncListSupp = @()
            }
        }
        $syncSupp = Invoke-AutoSync -zipSource $zipSourceSupplementary -installFolder $gamesInstallFolder -syncStatePath $syncStatePath -noSync $noSyncList -onlySync $onlySyncListSupp -retroBat $retroBat
    }

    Write-Host ""
    Write-Host "Extraction summary:" -ForegroundColor Green
    if ($syncSupp) { Write-Host "  Collection:" -ForegroundColor Cyan }
    Write-Host "  Extracted  : $($sync.Synced)"   -ForegroundColor Green
    Write-Host "  Up to date : $($sync.UpToDate)"  -ForegroundColor DarkGray
    if ($sync.Skipped -gt 0) { Write-Host "  Skipped    : $($sync.Skipped)  (per-game override)" -ForegroundColor DarkGray }
    if ($sync.Failed  -gt 0) { Write-Host "  Failed     : $($sync.Failed)  (see TeknoParrot-Manager.log)" -ForegroundColor Red }
    if ($syncSupp) {
        Write-Host "  Supplementary:" -ForegroundColor Cyan
        Write-Host "  Extracted  : $($syncSupp.Synced)"   -ForegroundColor Green
        Write-Host "  Up to date : $($syncSupp.UpToDate)"  -ForegroundColor DarkGray
        if ($syncSupp.Skipped -gt 0) { Write-Host "  Skipped    : $($syncSupp.Skipped)  (per-game override)" -ForegroundColor DarkGray }
        if ($syncSupp.Failed  -gt 0) { Write-Host "  Failed     : $($syncSupp.Failed)  (see TeknoParrot-Manager.log)" -ForegroundColor Red }
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

$result = Register-Games -userProfilesDir $userProfilesDir -installFolder $gamesInstallFolder -profileIndex $profileIndex -gameProfilesDir $gameProfilesDir -datIndex $datIndex -profileSet $profileSet

foreach ($r in $result.Registered) {
    if ($r.DatMatch) {
        Write-Host ("  Registered (dat)       : {0}" -f $r.Code) -ForegroundColor Green
    } elseif ($r.FuzzyScore) {
        Write-Host ("  Registered (fuzzy {0}) : {1}" -f $r.FuzzyScore, $r.Code) -ForegroundColor Cyan
        Write-Host ("               folder  : {0}" -f $r.FuzzyFolder) -ForegroundColor DarkGray
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
        $rel        = $amb.Exe.Substring($installBase.Length).TrimStart('\')
        $folderName = $rel.Split('\')[0]
        $exeName    = [System.IO.Path]::GetFileName($amb.Exe)
        $count      = @($amb.Codes.Split(',')).Count
        if (-not $manualRegData.ContainsKey($folderName) -or $count -lt $manualRegData[$folderName].ProfileCount) {
            $manualRegData[$folderName] = @{
                ExeName    = $exeName
                ProfileCount = $count
                Profiles   = $amb.Codes
                BestGuess  = $amb.BestGuess
                BestScore  = $amb.BestScore
            }
        }
    }
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
if ($Unattended) {
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
    $repair = Repair-GamePaths -userProfilesDir $userProfilesDir -installFolder $gamesInstallFolder -profileIndex $profileIndex
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
    }
    Write-Host ""
    Write-Host " This copies each game's controls to your OTHER games of the SAME" -ForegroundColor DarkCyan
    Write-Host " type. It never changes a game you have already bound, and it leaves" -ForegroundColor DarkCyan
    Write-Host " game-specific controls (gear shifts, special buttons) unbound for" -ForegroundColor DarkCyan
    Write-Host " you to set. Your UserProfiles were backed up at the start of this run." -ForegroundColor DarkCyan
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
        $reports = Invoke-ControlPropagation -userProfilesDir $userProfilesDir -pool $pool -minBound $MinBoundForArchetype -noPropagate $noPropagateList -forceArchetype $forceArchetypeMap -familyOverride $familyOverrideMap
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
                "skipped-bound"    { Write-Host ("    {0}  -- already bound, left unchanged" -f $r.Code) -ForegroundColor DarkGray }
                "skipped-override" { Write-Host ("    {0}  -- skipped (per-game override)" -f $r.Code) -ForegroundColor DarkGray }
                "save-failed"      { Write-Host ("    {0}  -- ERROR saving (see TeknoParrot-Manager.log)" -f $r.Code) -ForegroundColor Red }
            }
        }
        $nb               = @($reports | Where-Object { $_.Status -eq "bound" }).Count
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
Write-Host "   Done." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
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
Write-Host "  Backup : $backupPath" -ForegroundColor DarkCyan
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
if ($Unattended) {
    $doLB = "N"
    Write-Log "Unattended: LaunchBox export skipped."
} else {
    $doLB = (Read-Host "Export a LaunchBox import XML for all registered games? (Y/N)").Trim().ToUpper()
}
if ($doLB -eq "Y") {
    $lbPath  = Join-Path $PSScriptRoot "TeknoParrot-LaunchBox-Import.xml"
    $lbCount = Export-LaunchBoxXml -userProfilesDir $userProfilesDir -tpRoot $tpRoot -outputPath $lbPath
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
        Write-Host "             - Folder: browse to your games staging folder." -ForegroundColor DarkGray
        Write-Host "             - File types: *.exe  (or the file type your games use)." -ForegroundColor DarkGray
        Write-Host "  Step 5.  Follow the wizard. LaunchBox will assign game names," -ForegroundColor White
        Write-Host "             metadata, and box art automatically." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  If TeknoParrot is not yet in LaunchBox's emulator list:" -ForegroundColor Cyan
        Write-Host "    a. Go to  Tools -> Manage -> Emulators -> Add." -ForegroundColor DarkGray
        Write-Host "    b. Name: TeknoParrot" -ForegroundColor DarkGray
        Write-Host ("    c. Emulator path: {0}" -f (Join-Path $tpRoot "TeknoParrotUi.exe")) -ForegroundColor DarkGray
        Write-Host "    d. Command-line parameters: --profile=`"{rom}`"" -ForegroundColor DarkGray
        Write-Host "    e. Save, then re-run the import wizard." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  The exported XML file ($lbPath)" -ForegroundColor DarkCyan
        Write-Host "  is a reference showing all registered games, their profile codes," -ForegroundColor DarkCyan
        Write-Host "  and executable paths. You do not need to import it directly." -ForegroundColor DarkCyan
        Write-Log "LaunchBox: exported $lbCount games to $lbPath"
    }
}

# =============================================================================
# HYPERSPIN 2 EXPORT  (optional, runs after LaunchBox export)
# =============================================================================

Write-Host ""
if ($Unattended) {
    $doHS = "N"
    Write-Log "Unattended: HyperSpin 2 export skipped."
} else {
    $doHS = (Read-Host "Export registered games to HyperSpin 2? (Y/N)").Trim().ToUpper()
}
if ($doHS -eq "Y") {
    if (-not $hsDataPath) {
        Write-Host ""
        Write-Host "  Enter HyperSpin 2 data folder path." -ForegroundColor Cyan
        $hsInput = (Read-Host "  Path (default: C:\ProgramData\HyperSpin\data)").Trim()
        if ([string]::IsNullOrWhiteSpace($hsInput)) { $hsInput = "C:\ProgramData\HyperSpin\data" }
        $hsDataPath = $hsInput

        $cfgUpdate = [ordered]@{
            TeknoParrotRoot    = $tpRoot
            ZipSourceFolder    = $zipSource
            GamesInstallFolder = $gamesInstallFolder
            RetroBat           = $retroBat
            HyperSpinDataPath  = $hsDataPath
            ReShadeSourceDll   = $rsSourceDll
            ReShadeSourceDll32 = $rsSourceDll32
            DgVoodoo2SourceDir = $dgSourceDir
        }
        try {
            [System.IO.File]::WriteAllText($configPath, ($cfgUpdate | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
            Write-Log "Config: saved HyperSpinDataPath = $hsDataPath"
        } catch {
            Write-Log "Config: could not save HyperSpinDataPath -- $_"
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
            Write-Host "       Then re-run this script and choose option 5 from the menu." -ForegroundColor White
            Write-Host "    -- OR --" -ForegroundColor DarkCyan
            Write-Host "    Enter the full path to the DLL file now:" -ForegroundColor White
            Write-Host ""
            $rsInp = (Read-Host "  Path to ReShade 64-bit DLL (or press Enter to skip)").Trim()
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
            $cfgRS2 = [ordered]@{
                TeknoParrotRoot              = $tpRoot
                ZipSourceFolder              = $zipSource
                ZipSourceSupplementaryFolder = $zipSourceSupplementary
                GamesInstallFolder           = $gamesInstallFolder
                RetroBat                     = $retroBat
                HyperSpinDataPath            = $hsDataPath
                ReShadeSourceDll             = $rsSourceDll
                ReShadeSourceDll32           = $rsSourceDll32
                DgVoodoo2SourceDir           = $dgSourceDir
            }
            try {
                [System.IO.File]::WriteAllText($configPath, ($cfgRS2 | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
                Write-Log "Config: saved ReShadeSourceDll = $rsSourceDll"
            } catch { Write-Log "Config: could not save ReShadeSourceDll -- $_" }
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
if (-not (Get-Variable rsSetupDone -ErrorAction SilentlyContinue)) { $rsSetupDone = $false }

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
            Write-Host "       Then re-run this script and choose option 6 from the menu." -ForegroundColor White
            Write-Host "    -- OR --" -ForegroundColor DarkCyan
            Write-Host "    Enter the full path to a folder that already contains those files:" -ForegroundColor White
            Write-Host ""
            $dgInp = (Read-Host "  Path to dgVoodoo2 folder (or press Enter to skip)").Trim()
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
            $cfgDg2 = [ordered]@{
                TeknoParrotRoot              = $tpRoot
                ZipSourceFolder              = $zipSource
                ZipSourceSupplementaryFolder = $zipSourceSupplementary
                GamesInstallFolder           = $gamesInstallFolder
                RetroBat                     = $retroBat
                HyperSpinDataPath            = $hsDataPath
                ReShadeSourceDll             = $rsSourceDll
                ReShadeSourceDll32           = $rsSourceDll32
                DgVoodoo2SourceDir           = $dgSourceDir
            }
            try {
                [System.IO.File]::WriteAllText($configPath, ($cfgDg2 | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
                Write-Log "Config: saved DgVoodoo2SourceDir = $dgSourceDir"
            } catch { Write-Log "Config: could not save DgVoodoo2SourceDir -- $_" }
        }
    }
}
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
if (-not (Get-Variable dgSetupDone -ErrorAction SilentlyContinue)) { $dgSetupDone = $false }

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
if ($Unattended) {
    $doGpuFix = "N"
    Write-Log "Unattended: GPU fix setup skipped."
} else {
    $doGpuFix = (Read-Host "Apply GPU compatibility fixes for your games? (Y/N)").Trim().ToUpper()
}
if ($doGpuFix -eq "Y") {
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " GPU Compatibility Fix Setup" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    $gpuSetupDone = $true
    Invoke-GpuFixSetup -UserProfilesDir $userProfilesDir `
                       -TpRoot $tpRoot
}
if (-not (Get-Variable gpuSetupDone -ErrorAction SilentlyContinue)) { $gpuSetupDone = $false }

# =============================================================================
# ACTION REQUIRED -- collects everything the user must do manually
# =============================================================================

$hasAnyAction = ($manualRegData.Count -gt 0) -or ($amb2.Count -gt 0) -or
                ($nf.Count -gt 0) -or ($noArchetypeItems.Count -gt 0) -or
                ($result.Unmatched.Count -gt 0)

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
        Write-Host "  automatically because the name of each executable file is shared" -ForegroundColor DarkCyan
        Write-Host "  by multiple TeknoParrot profiles. You must pick the right profile." -ForegroundColor DarkCyan
        Write-Host "  Open TeknoParrotUI -> Add Game -> select the profile -> browse" -ForegroundColor DarkCyan
        Write-Host "  to the executable shown below." -ForegroundColor DarkCyan
        Write-Host ""
        foreach ($folderName in ($manualRegData.Keys | Sort-Object)) {
            $info    = $manualRegData[$folderName]
            $count   = $info.ProfileCount
            $exeName = $info.ExeName
            Write-Host "  Game   : $folderName" -ForegroundColor Yellow
            Write-Host "  Run    : $exeName" -ForegroundColor DarkGray
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

    Write-Host "============================================" -ForegroundColor Yellow

    $actionPath = Join-Path $PSScriptRoot "TeknoParrot-Manager-ActionItems.txt"
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
