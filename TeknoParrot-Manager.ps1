# =============================================================================
# TeknoParrot Manager  |  v0.29 BETA
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
Write-Host "       TeknoParrot Manager  v0.29 BETA       " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Load the ZIP assembly once at startup. ZipFile.ExtractToDirectory is used in
# place of Expand-Archive because PowerShell 5.1's Expand-Archive has known bugs:
# it can throw "already exists" even with -Force, leave partial folders behind,
# and fail silently on paths near the MAX_PATH limit.
Add-Type -AssemblyName System.IO.Compression.FileSystem

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
        Add-Content -Path $logPath -Value $line -ErrorAction Stop
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

# Reads the primary ExecutableName from a profile XML using a fast regex pass,
# avoiding a full DOM parse for every file during the index scan. The regex
# matches <ExecutableName> exactly (not <ExecutableName2>). Falls back to a
# full parse if the quick read finds nothing.
function Get-PrimaryExecutableName {
    param([string]$path)
    try {
        $raw = [System.IO.File]::ReadAllText($path)
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
    $sampleBytes = [Math]::Min($testFile.Length, 100MB)
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
                Where-Object { $_.Root -and -not (Test-IsNetworkPath $_.Root) -and (Test-Path $_.Root) } |
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
    #  Pass 1 -- standard boundary: lowercase → uppercase ("AkaiKatana" → "Akai Katana")
    $s = [regex]::Replace($s, '(?<=[a-z])(?=[A-Z])', ' ')
    #  Pass 2 -- acronym boundary: uppercase → uppercase+lowercase ("NBANesica" → "NBA Nesica")
    #  This handles profile codes that begin with an acronym followed by a word.
    $s = [regex]::Replace($s, '(?<=[A-Z])(?=[A-Z][a-z])', ' ')
    #  Known edge case: brand names with non-standard capitalisation like "NESiCAxLive"
    #  split as "NESi CAx Live" on pass 1 (i→C boundary). This does not affect match
    #  accuracy because (a) both folder name and profile code go through the same
    #  normalisation so Dice scores converge symmetrically, and (b) "NESiCAxLive"
    #  appears in square-bracket metadata ([Taito NESiCAxLive]) which is stripped
    #  by the bracket removal step BEFORE this function runs.
    # Remove year-in-parens like (2012)
    $s = $s -replace '\(\d{4}\)', ''
    # Remove square-bracket metadata [Taito NESiCAxLive][TP]
    $s = $s -replace '\[.*?\]', ''
    # Remove version strings like (ver 1.1) (rev 2) (v3) (v1.2b).
    # Meaningful parenthesised names such as (Special Edition) are intentionally
    # preserved -- they may be the only differentiator between two game titles.
    $s = $s -replace '\((ver\.?|rev\.?|v)\s*[\d\.]+[a-z]?\)', ''
    # Remove parenthesised pure numbers like (2) (12) that carry no game-name info.
    $s = $s -replace '\(\d+\)', ''
    # Strip everything non-alphanumeric (spaces, hyphens, apostrophes, colons…)
    $s = $s -replace '[^a-zA-Z0-9]', ''
    return $s.ToLower()
}

# Sørensen-Dice coefficient on character bigrams for two pre-normalised strings.
# Returns [0.0, 1.0]. Strings shorter than 2 chars cannot form bigrams → 0.0.
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
# .gcm, .gcz), binary containers (.bin, .zip, .e4), and extension-less Linux
# binaries (e.g. "game", "armyops-bin", "abc").
#
# Extension-less files are limited to 4 directory levels below $folder.
# Linux game executables are always at that depth or shallower; system files
# buried inside Lindbergh / Chihiro Linux filesystem images (e.g. X11 keyboard
# layout files like "tr") live 7-10 levels deep and are excluded by this limit.
function Get-GameFiles {
    param([string]$folder)
    $exts      = @('.exe', '.elf', '.iso', '.gcm', '.gcz', '.bin', '.e4', '.zip')
    $baseDepth = $folder.TrimEnd('\').Split('\').Count
    return @(Get-ChildItem -LiteralPath $folder -Recurse -File -ErrorAction SilentlyContinue |
                 Where-Object {
                     $ext = $_.Extension.ToLower()
                     if ($exts -contains $ext) { return $true }
                     if ($ext -eq '') {
                         # Extension-less Linux binaries: allow up to 6 levels below the
                         # games root. Some Lindbergh titles place executables 5-6 levels
                         # deep inside their filesystem image. System files (X11 layouts,
                         # shared libraries, etc.) live 7-10 levels deep and are excluded.
                         return ($_.FullName.Split('\').Count - $baseDepth) -le 6
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
    $out = @()

    # Short-circuit on empty or whitespace-only input -- nothing to parse.
    if ([string]::IsNullOrWhiteSpace($str)) { return ,$out }

    # Validate: anything other than digits, commas, hyphens, and whitespace is
    # not a valid number/range expression and almost certainly a typo.
    if ($str -match '[^0-9,\s\-]') {
        Write-Host ("  NOTE: '{0}' is not a valid selection -- use digits, commas, and hyphens only (e.g. 1,3,5-7)." -f $str) -ForegroundColor Yellow
        return ,$out
    }

    foreach ($part in ($str -split ',')) {
        $part = $part.Trim()
        if ($part -match '^(\d+)-(\d+)$') {
            $from = [int]$Matches[1]; $to = [int]$Matches[2]
            if ($from -gt $to) { $tmp = $from; $from = $to; $to = $tmp }   # handle "7-3"
            $to = [Math]::Min($to, $max)   # clamp upper bound before looping
            for ($n = $from; $n -le $to; $n++) { if ($n -ge 1) { $out += $n } }
        } elseif ($part -match '^\d+$') {
            $n = [int]$part
            if ($n -ge 1 -and $n -le $max) { $out += $n }
        }
    }
    return ,$out
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
        return @()
    }

    # Build a normalised folder map of what is already extracted in the
    # destination, using the same convention-agnostic logic as AutoSync.
    $normalizedFolderMap = @{}
    foreach ($dir in (Get-ChildItem -LiteralPath $installFolder -Directory -ErrorAction SilentlyContinue)) {
        $norm = $dir.Name -replace ' (?=[\[\(])', ''
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

        # ── ALL GAMES ───────────────────────────────────────────────────────
        if ($choice -eq 'A') {
            Write-Host ""
            Write-Host "  All $($all.Count) unextracted game(s) will be extracted." -ForegroundColor Green
            return @()   # empty = no whitelist = extract everything
        }

        # ── BROWSE ──────────────────────────────────────────────────────────
        elseif ($choice -eq 'L') {
            $page       = 0
            $totalPages = [Math]::Ceiling($all.Count / $pageSize)
            $browsing   = $true

            while ($browsing) {
                $start     = $page * $pageSize
                $end       = [Math]::Min($start + $pageSize - 1, $all.Count - 1)
                $pageItems = @($all[$start..$end])

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

        # ── SEARCH ──────────────────────────────────────────────────────────
        elseif ($choice -eq 'S') {
            $searching = $true
            while ($searching) {
                Write-Host ""
                $term = (Read-Host "  Search keyword (or 'back' / 'done')").Trim()
                if ($term -ieq 'back') { $searching = $false; continue }
                if ($term -ieq 'done') { $searching = $false; $done = $true; continue }
                if (-not $term) { continue }

                $results = @($all | Where-Object { $_.BaseName -like "*$term*" })
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

        # ── DONE ────────────────────────────────────────────────────────────
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

# Extracts NAS ZIPs to a local folder. Tracks state to skip unchanged games.
# Never deletes local games. ZIP base names listed in $noSync are skipped.
# If $onlySync is non-empty, only ZIPs whose base name is in the list are extracted.
function Invoke-AutoSync {
    param([string]$zipSource, [string]$installFolder, [string]$syncStatePath,
          $noSync = @(), $onlySync = @())

    $syncState = @{}
    if (Test-Path $syncStatePath) {
        try {
            $loaded = Get-Content $syncStatePath -Raw | ConvertFrom-Json
            foreach ($prop in $loaded.PSObject.Properties) { $syncState[$prop.Name] = $prop.Value }
        } catch { Write-Log "AutoSync: could not read sync state -- starting fresh." }
    }

    $zipFiles = Get-ChildItem -LiteralPath $zipSource -Filter *.zip -ErrorAction SilentlyContinue
    if (-not $zipFiles -or $zipFiles.Count -eq 0) {
        Write-Host "  No ZIP files found in source. Skipping extraction." -ForegroundColor Yellow
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
        $norm = $dir.Name -replace ' (?=[\[\(])', ''
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
        $extractDir = Join-Path $installFolder $rawName
        # Sentinel lives next to the game folder (not inside it) so we do not
        # need to pre-create the game directory. Expand-Archive creates the
        # directory itself; pre-creating it caused PS 5.1 to throw "already
        # exists" even when -Force was supplied.
        $sentinel   = Join-Path $installFolder "$rawName.extracting"
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
                        $failed++
                        continue   # outer finally fires before the loop advances
                    }
                }
                # Extract using ZipFile instead of Expand-Archive. PowerShell 5.1's
                # Expand-Archive has known bugs: it can throw "already exists" even
                # with -Force, leave partial folders behind on failures, and behave
                # unpredictably near the MAX_PATH limit. ZipFile is faster, more
                # reliable, and handles the same ZIP formats.
                # The destination folder was removed above, so it does not exist yet;
                # ExtractToDirectory will create it and extract into it cleanly.
                [System.IO.Compression.ZipFile]::ExtractToDirectory($zip.FullName, $extractDir)
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

# Scans the install folder for executables, matches them to profiles, copies
# matched templates to UserProfiles, and sets GamePath. Existing UserProfiles
# are left untouched (never overwritten).
function Register-Games {
    param([string]$userProfilesDir, [string]$installFolder, [hashtable]$profileIndex)

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
        $allExeFolders[$folderName] = $true

        $key = $exe.Name.ToLower()
        if (-not $profileIndex.ContainsKey($key)) { continue }
        $matchedFolders[$folderName] = $true

        $matchList = $profileIndex[$key]

        # Same executable name maps to more than one profile.
        # Attempt folder-name fuzzy matching before giving up.
        if ($matchList.Count -gt 1) {
            # $folderName is already derived above; just normalise it here.
            $normFolder  = Get-NormalizedGameKey $folderName

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
                if (Test-Path $userProfile) {
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
                        $tpl.Save($userProfile)
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
                # Below threshold: flag for manual registration but include best-guess hint.
                [void]$ambiguous.Add([pscustomobject]@{
                    Exe       = $exe.FullName
                    Codes     = ($matchList | ForEach-Object { $_.Code }) -join ", "
                    BestGuess = if ($null -ne $bestFuzzy) { $bestFuzzy.Code } else { $null }
                    BestScore = [Math]::Round($bestFuzzyScore, 2)
                })
            }
            continue
        }

        $match = $matchList[0]
        $code  = $match.Code
        if ($seenCodes.ContainsKey($code)) { continue }

        $userProfile = Join-Path $userProfilesDir ($code + ".xml")
        if (Test-Path $userProfile) {
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
            $tpl.Save($userProfile)
            [void]$registered.Add([pscustomobject]@{ Code = $code; GamePath = $exe.FullName })
            Write-Log "Registered $code -> $($exe.FullName)"
        } catch {
            Write-Host "  FAILED to register $code : $_" -ForegroundColor Red
            Write-Log "Register FAILED $code -- $_"
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
    # Uses Get-GameFiles so Linux ELF, disc images, and extension-less binaries
    # are included alongside Windows EXE files.
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
            $doc.Save($f.FullName)
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
            $doc.Save($f.FullName)
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
    if (-not (Test-Path $backupRoot)) {
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

    Write-Host ""
    Write-Host ("  Selected : {0}" -f $selected.Name) -ForegroundColor Yellow
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
# LAUNCHBOX XML EXPORT  (standalone file only — no direct LaunchBox writes)
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
            [void]$sb.AppendLine("    <Notes>Exported by TeknoParrot Manager v0.29</Notes>")
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
# THUMBNAIL DOWNLOAD  (optional, fetches game icons from GitHub)
# =============================================================================
# Downloads ProfileCode.png from the TeknoParrotUIThumbnails repository into
# <TeknoParrotRoot>\Icons\ -- the exact path TeknoParrotUI reads at startup.
# Only fetches icons that are absent; never overwrites existing files.
# Source: https://github.com/teknogods/TeknoParrotUIThumbnails
function Invoke-ThumbnailDownload {
    param([string]$userProfilesDir, [string]$tpRoot)

    $iconsDir = Join-Path $tpRoot "Icons"
    if (-not (Test-Path $iconsDir)) {
        try {
            New-Item -ItemType Directory -Path $iconsDir -ErrorAction Stop | Out-Null
            Write-Log "Thumbnails: created Icons folder at $iconsDir"
        } catch {
            Write-Host "  ERROR: Could not create Icons folder: $_" -ForegroundColor Red
            Write-Log "Thumbnails: could not create Icons folder -- $_"
            return
        }
    }

    $profiles = @(Get-ChildItem -LiteralPath $userProfilesDir -Filter *.xml -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Directory.Name -ne "FullBackup" })

    if ($profiles.Count -eq 0) {
        Write-Host "  No registered profiles found." -ForegroundColor DarkGray
        return
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

    # GitHub requires TLS 1.2; PS 5.1 may negotiate an older version by default.
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $baseUrl = "https://raw.githubusercontent.com/teknogods/TeknoParrotUIThumbnails/master/Icons/"
    $fetched  = 0
    $notAvail = 0
    $failed   = 0
    $i        = 0
    $total    = $missing.Count

    $wc = New-Object System.Net.WebClient
    try {
        foreach ($code in $missing) {
            $i++
            $destPath = Join-Path $iconsDir ($code + ".png")
            $url      = $baseUrl + [Uri]::EscapeDataString($code + ".png")
            Write-Host ("  [{0,3}/{1}] {2}" -f $i, $total, $code) -ForegroundColor DarkCyan -NoNewline
            try {
                $wc.DownloadFile($url, $destPath)
                Write-Host "  OK" -ForegroundColor Green
                Write-Log "Thumbnails: downloaded $code"
                $fetched++
            } catch [System.Net.WebException] {
                $resp       = $_.Exception.Response
                $statusCode = if ($null -ne $resp) { [int]$resp.StatusCode } else { 0 }
                if ($statusCode -eq 404) {
                    Write-Host "  not in repo" -ForegroundColor DarkGray
                    $notAvail++
                } else {
                    Write-Host ("  FAILED ({0})" -f $_.Exception.Message) -ForegroundColor Red
                    Write-Log "Thumbnails: FAILED $code -- $($_.Exception.Message)"
                    $failed++
                }
                # Remove any partial file left by a failed download.
                if (Test-Path -LiteralPath $destPath) {
                    Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
                }
            } catch {
                Write-Host ("  FAILED ({0})" -f $_) -ForegroundColor Red
                Write-Log "Thumbnails: FAILED $code -- $_"
                if (Test-Path -LiteralPath $destPath) {
                    Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
                }
                $failed++
            }
        }
    } finally {
        $wc.Dispose()
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

Write-Log "Script started (v0.29$(if ($Unattended) { ' [Unattended]' }))."

# =============================================================================
# SECTION 1 — Load or prompt for configuration
# =============================================================================

$configPath         = Join-Path $PSScriptRoot "TeknoParrot-Manager.config.json"
$tpRoot             = $null
$mode               = $null   # "AutoSync", "RegisterOnly", or "Restore"
$zipSource          = $null   # AutoSync only
$gamesInstallFolder = $null   # always (the extracted-games root to register)

if ($Unattended -and -not (Test-Path $configPath)) {
    Write-Host ""
    Write-Host "ERROR: Unattended mode requires saved settings." -ForegroundColor Red
    Write-Host "Run the script once interactively to save your configuration, then retry with -Unattended." -ForegroundColor Yellow
    Write-Log "ERROR: Unattended mode -- no saved config at $configPath"; exit 1
}

if (Test-Path $configPath) {
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        Write-Host "Saved configuration found:" -ForegroundColor Cyan
        Write-Host "  TeknoParrot root     : $($cfg.TeknoParrotRoot)"
        Write-Host "  Mode                 : $($cfg.Mode)"
        if ($cfg.ZipSourceFolder)    { Write-Host "  ZIP source folder    : $($cfg.ZipSourceFolder)" }
        Write-Host "  Games install folder : $($cfg.GamesInstallFolder)"
        Write-Host ""
        if ($Unattended) {
            Write-Host "  [Unattended] Using saved settings." -ForegroundColor DarkCyan
            Write-Log "Unattended: auto-accepted saved settings."
            $use = "Y"
        } else {
            $use = Read-Host "Use these settings? (Y/N)"
        }
        if ($use.ToUpper() -eq "Y") {
            $tpRoot             = $cfg.TeknoParrotRoot
            # Validate mode before accepting it; an unknown value falls through to the prompt.
            $knownModes = @("AutoSync", "RegisterOnly", "Restore")
            if ($cfg.Mode -and $knownModes -contains $cfg.Mode) {
                $mode = $cfg.Mode
            } else {
                if ($Unattended) {
                    Write-Host "ERROR: Unattended mode -- saved mode '$($cfg.Mode)' is not recognised." -ForegroundColor Red
                    Write-Log "ERROR: Unattended mode -- unrecognised mode '$($cfg.Mode)'."; exit 1
                }
                Write-Host "  NOTE: saved mode '$($cfg.Mode)' is not recognised -- you will be prompted." -ForegroundColor Yellow
                Write-Log "Config: unrecognised mode '$($cfg.Mode)' -- ignored."
            }
            $zipSource          = $cfg.ZipSourceFolder
            $gamesInstallFolder = $cfg.GamesInstallFolder
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
        $tpRoot = Read-Host "Enter TeknoParrot root folder (containing TeknoParrotUi.exe)"
    }
}

if (-not $mode) {
    if ($Unattended) {
        Write-Host "ERROR: Unattended mode -- no mode in saved settings." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- mode not set."; exit 1
    }
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " Mode" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host "  1) AutoSync     -- Extract ZIPs (NAS or local) to a local"
    Write-Host "                     folder, then register the games."
    Write-Host "  2) Register only -- Games are already extracted; just register."
    Write-Host "  3) Restore from backup -- Roll UserProfiles back to a previous backup."
    Write-Host ""
    $modeChoice = Read-Host "Enter 1, 2, or 3"
    switch ($modeChoice) {
        "1"     { $mode = "AutoSync"      }
        "2"     { $mode = "RegisterOnly"  }
        "3"     { $mode = "Restore"       }
        default {
            Write-Host "Unrecognised input. Defaulting to Register only." -ForegroundColor Yellow
            $mode = "RegisterOnly"
        }
    }
}

if ($mode -eq "AutoSync" -and -not $zipSource) {
    if ($Unattended) {
        Write-Host "ERROR: Unattended mode -- ZIP source folder not in saved settings." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- zipSource not set."; exit 1
    }
    $zipSource = Read-Host "Enter ZIP source folder (NAS or local, containing .zip files)"
}
if (-not $gamesInstallFolder) {
    if ($Unattended) {
        Write-Host "ERROR: Unattended mode -- games install folder not in saved settings." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- gamesInstallFolder not set."; exit 1
    }
    if ($mode -eq "AutoSync") {
        $gamesInstallFolder = Read-Host "Enter LOCAL staging folder to extract games into, on a drive with free space and OUTSIDE the TeknoParrot and source folders (e.g. D:\TeknoParrotGames)"
    } elseif ($mode -ne "Restore") {
        $gamesInstallFolder = Read-Host "Enter folder containing your extracted games (e.g. C:\TeknoParrotGames)"
    }
}

# =============================================================================
# RESTORE MODE — run restore then exit; skips all registration/propagation
# =============================================================================

if ($mode -eq "Restore") {
    if ($Unattended) {
        Write-Host "ERROR: Restore mode cannot run unattended (requires interactive selection)." -ForegroundColor Red
        Write-Log "ERROR: Unattended mode -- Restore requires user interaction."; exit 1
    }
    if (-not (Test-Path $tpRoot)) {
        Write-Host ""; Write-Host "ERROR: TeknoParrot root folder not found: $tpRoot" -ForegroundColor Red
        Write-Log "ERROR: TeknoParrot root not found (Restore mode)."; exit 1
    }
    $userProfilesDirForRestore = Join-Path $tpRoot "UserProfiles"
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " Restore from Backup" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Invoke-RestoreBackup -userProfilesDir $userProfilesDirForRestore
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "   Done." -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

# =============================================================================
# SECTION 2 — Validate TeknoParrot root, locate GameProfiles and UserProfiles
# =============================================================================

if (-not (Test-Path $tpRoot)) {
    Write-Host ""; Write-Host "ERROR: TeknoParrot root folder not found: $tpRoot" -ForegroundColor Red
    Write-Log "ERROR: TeknoParrot root not found."; exit 1
}

# TeknoParrot's launcher is TeknoParrotUi.exe (Windows path checks are
# case-insensitive, so this also matches TeknoParrotUI.exe).
$tpExe = Join-Path $tpRoot "TeknoParrotUi.exe"
if (-not (Test-Path $tpExe)) {
    Write-Host ""; Write-Host "ERROR: TeknoParrotUi.exe not found in: $tpRoot" -ForegroundColor Red
    Write-Host "Make sure the path points to the TeknoParrot root folder." -ForegroundColor Yellow
    Write-Log "ERROR: TeknoParrotUi.exe not found."; exit 1
}

$gameProfilesDir = Join-Path $tpRoot "GameProfiles"
if (-not (Test-Path $gameProfilesDir)) {
    Write-Host ""; Write-Host "ERROR: GameProfiles folder not found in: $tpRoot" -ForegroundColor Red
    Write-Host "This folder ships with TeknoParrot and is required to register games." -ForegroundColor Yellow
    Write-Host "Run TeknoParrotUi.exe once and let it complete its updates, then retry." -ForegroundColor Yellow
    Write-Log "ERROR: GameProfiles folder not found."; exit 1
}

$userProfilesDir = Join-Path $tpRoot "UserProfiles"
if (-not (Test-Path $userProfilesDir)) {
    try {
        New-Item -ItemType Directory -Path $userProfilesDir -ErrorAction Stop | Out-Null
    } catch {
        Write-Host ""; Write-Host "ERROR: Could not create UserProfiles folder: $_" -ForegroundColor Red
        Write-Log "ERROR: Could not create UserProfiles folder -- $_"; exit 1
    }
}

if ($mode -eq "AutoSync") {
    if (-not (Test-Path $zipSource)) {
        Write-Host ""; Write-Host "ERROR: ZIP source folder not found: $zipSource" -ForegroundColor Red
        Write-Log "ERROR: ZIP source not found."; exit 1
    }
    if (Test-IsNetworkPath $gamesInstallFolder) {
        Write-Host ""; Write-Host "ERROR: The staging folder must be on a local drive." -ForegroundColor Red
        Write-Host "AutoSync extracts games locally for performance. Use e.g. D:\TeknoParrotGames." -ForegroundColor Yellow
        Write-Log "ERROR: staging folder is a network path."; exit 1
    }
    # Keep the staging folder out of the emulator folder and the source folder,
    # so neither gets polluted with extracted games.
    if (Test-PathInside $gamesInstallFolder $tpRoot) {
        Write-Host ""; Write-Host "ERROR: The staging folder is inside the TeknoParrot folder." -ForegroundColor Red
        Write-Host "Choose a staging folder outside $tpRoot to keep the emulator folder clean." -ForegroundColor Yellow
        Write-Log "ERROR: staging folder inside TeknoParrot root."; exit 1
    }
    if ((Test-PathInside $gamesInstallFolder $zipSource) -or (Test-PathInside $zipSource $gamesInstallFolder)) {
        Write-Host ""; Write-Host "ERROR: The staging folder and the ZIP source overlap." -ForegroundColor Red
        Write-Host "Keep them on separate paths so the original games folder stays clean." -ForegroundColor Yellow
        Write-Log "ERROR: staging folder overlaps ZIP source."; exit 1
    }
    if (-not (Test-Path $gamesInstallFolder)) {
        New-Item -ItemType Directory -Path $gamesInstallFolder -Force | Out-Null
        Write-Host "Created staging folder: $gamesInstallFolder" -ForegroundColor Green
    }
    # Free-space check: extracted games are usually larger than their ZIPs, so
    # warn if the staging drive has less than ~1.5x the total ZIP size free.
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
                $cont = Read-Host "  Continue anyway? (Y/N)"
                if ($cont.ToUpper() -ne "Y") { Write-Host "Aborted." -ForegroundColor Yellow; Write-Log "Aborted: low staging-drive space."; exit 1 }
            }
        }
        Write-Log "Space check: free=$([Math]::Round($freeBytes/1GB,1))GB zips=$([Math]::Round($zipBytes/1GB,1))GB"
    } catch { Write-Log "Space check skipped: $_" }
} else {
    if (-not (Test-Path $gamesInstallFolder)) {
        Write-Host ""; Write-Host "ERROR: Games install folder not found: $gamesInstallFolder" -ForegroundColor Red
        Write-Log "ERROR: install folder not found."; exit 1
    }
}

Write-Log "Validated. tpRoot=$tpRoot mode=$mode install=$gamesInstallFolder"

# =============================================================================
# SECTION 3 — NAS detection and throughput benchmark
# =============================================================================

if ($mode -eq "AutoSync" -and (Test-IsNetworkPath $zipSource)) {
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

# =============================================================================
# SECTION 4 — Save configuration
# =============================================================================

$cfgOut = [ordered]@{
    TeknoParrotRoot    = $tpRoot
    Mode               = $mode
    ZipSourceFolder    = $zipSource
    GamesInstallFolder = $gamesInstallFolder
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
Write-Host "  Mode                 : $mode"
if ($zipSource)      { Write-Host "  ZIP source folder    : $zipSource" }
Write-Host "  Games install folder : $gamesInstallFolder"

# =============================================================================
# SECTION 4b — Per-game overrides  (TeknoParrot-Manager.overrides.json)
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

if (-not (Test-Path $overridesPath)) {
    $ovTemplate = [ordered]@{
        _comment       = "noSync/onlySync/noPropagate: lists of ZIP base names (without .zip). onlySync acts as a whitelist -- only listed games are extracted. forceArchetype: { GameCode: ArchetypeCode } pins a game to a specific reference game. familyOverride: { GameCode: 'button'|'driving'|'lightgun'|'trackball'|'analog' } overrides the auto-detected control family (fixes mis-classified games like FamilyGuyBowling)."
        noSync         = @()
        onlySync       = @()
        noPropagate    = @()
        forceArchetype = [ordered]@{}
        familyOverride = [ordered]@{}
    }
    try { [System.IO.File]::WriteAllText($overridesPath, ($ovTemplate | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false)) }
    catch { Write-Log "Overrides: could not create template -- $_" }
}

if (Test-Path $overridesPath) {
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
        $ovCount = $noSyncList.Count + $onlySyncList.Count + $noPropagateList.Count + $forceArchetypeMap.Count + $familyOverrideMap.Count
        if ($ovCount -gt 0) {
            Write-Host ""
            Write-Host "Overrides: noSync=$($noSyncList.Count), onlySync=$($onlySyncList.Count), noPropagate=$($noPropagateList.Count), pinned=$($forceArchetypeMap.Count), familyOverride=$($familyOverrideMap.Count)" -ForegroundColor DarkCyan
        }
        Write-Log "Overrides: noSync=$($noSyncList.Count) onlySync=$($onlySyncList.Count) noPropagate=$($noPropagateList.Count) pinned=$($forceArchetypeMap.Count) familyOverride=$($familyOverrideMap.Count)"
    } catch {
        Write-Host "WARNING: could not read TeknoParrot-Manager.overrides.json; ignoring overrides." -ForegroundColor Yellow
        Write-Log "Overrides: parse error -- ignoring."
    }
}

# =============================================================================
# SECTION 5 — Back up UserProfiles
# =============================================================================

$backupRoot = Join-Path $userProfilesDir "FullBackup"
$timestamp  = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$backupPath = Join-Path $backupRoot $timestamp

Write-Host ""
Write-Host "Backing up UserProfiles..." -ForegroundColor Cyan

# Guard: if the backup folder cannot be created the script exits here rather
# than proceeding with modifications that have no restore point.
try {
    if (!(Test-Path $backupRoot)) { New-Item -ItemType Directory -Path $backupRoot -ErrorAction Stop | Out-Null }
    New-Item -ItemType Directory -Path $backupPath -ErrorAction Stop | Out-Null
} catch {
    Write-Host "  ERROR: Could not create backup folder: $_" -ForegroundColor Red
    Write-Host "  The script will not continue without a successful backup." -ForegroundColor Red
    Write-Log "Backup FAILED: could not create backup folder -- $_"
    exit 1
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
            exit 1
        }
    }
}
Write-Host "Backup saved to: $backupPath" -ForegroundColor Green
Write-Log "Backup created at $backupPath"

# =============================================================================
# SECTION 6 — AutoSync: game selection and extraction
# =============================================================================

if ($mode -eq "AutoSync") {
    Write-Host ""
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " AutoSync: Extracting Games" -ForegroundColor Cyan
    Write-Host "--------------------------------------------" -ForegroundColor Cyan
    Write-Host " New and changed games are extracted; unchanged games skipped." -ForegroundColor DarkCyan
    Write-Host " Local games are never deleted automatically." -ForegroundColor DarkCyan
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
    $sync = Invoke-AutoSync -zipSource $zipSource -installFolder $gamesInstallFolder -syncStatePath $syncStatePath -noSync $noSyncList -onlySync $onlySyncList
    Write-Host ""
    Write-Host "Extraction summary:" -ForegroundColor Green
    Write-Host "  Extracted  : $($sync.Synced)"  -ForegroundColor Green
    Write-Host "  Up to date : $($sync.UpToDate)" -ForegroundColor DarkGray
    if ($sync.Skipped -gt 0) {
        Write-Host "  Skipped    : $($sync.Skipped)  (per-game override)" -ForegroundColor DarkGray
    }
    if ($sync.Failed -gt 0) {
        Write-Host "  Failed     : $($sync.Failed)  (see TeknoParrot-Manager.log)" -ForegroundColor Red
    }
}

# =============================================================================
# SECTION 7 — Build profile index from GameProfiles
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
    Write-Log "ERROR: empty profile index."; exit 1
}

# =============================================================================
# SECTION 8 — Register games
# =============================================================================

Write-Host ""
Write-Host "--------------------------------------------" -ForegroundColor Cyan
Write-Host " Registering Games" -ForegroundColor Cyan
Write-Host "--------------------------------------------" -ForegroundColor Cyan
Write-Host " Scanning: $gamesInstallFolder" -ForegroundColor DarkCyan
Write-Host ""

$result = Register-Games -userProfilesDir $userProfilesDir -installFolder $gamesInstallFolder -profileIndex $profileIndex

foreach ($r in $result.Registered) {
    if ($r.FuzzyScore) {
        Write-Host ("  Registered (fuzzy {0}) : {1}" -f $r.FuzzyScore, $r.Code) -ForegroundColor Cyan
        Write-Host ("               folder  : {0}" -f $r.FuzzyFolder) -ForegroundColor DarkGray
    } else {
        Write-Host "  Registered : $($r.Code)" -ForegroundColor Green
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
# SECTION 8b — Download game thumbnails (optional)
# =============================================================================

Write-Host ""
if ($Unattended) {
    Write-Host "  [Unattended] Downloading missing thumbnails." -ForegroundColor DarkCyan
    Write-Log "Unattended: thumbnail download = Y."
    $doThumb = "Y"
} else {
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
# SECTION 9  — Game repair: fix broken GamePaths
# =============================================================================

Write-Host ""
if ($Unattended) {
    Write-Host "  [Unattended] Running repair." -ForegroundColor DarkCyan
    Write-Log "Unattended: repair = Y."
    $doRepair = "Y"
} else {
    $doRepair = Read-Host "Check for and repair broken game paths now? (Y/N)"
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
# SECTION 10 — Control propagation
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
    if (-not $Unattended -and (Read-Host " Want a recommended binding plan for more control types first? (Y/N)").ToUpper() -eq "Y") {
        Invoke-DeviceSurvey
        Write-Host ""
    }
    if ($Unattended) {
        Write-Host "  [Unattended] Propagating controls." -ForegroundColor DarkCyan
        Write-Log "Unattended: propagation = Y."
        $goCtl = "Y"
    } else {
        $goCtl = Read-Host " Propagate controls now? (Y/N)"
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
# ACTION REQUIRED — collects everything the user must do manually
# =============================================================================

$hasAnyAction = ($manualRegData.Count -gt 0) -or ($amb2.Count -gt 0) -or
                ($nf.Count -gt 0) -or ($noArchetypeItems.Count -gt 0) -or
                ($result.Unmatched.Count -gt 0)

if ($hasAnyAction) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Yellow
    Write-Host "   ACTION REQUIRED" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Yellow

    # ── 1. Games needing manual registration ─────────────────────────────────
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

    # ── 2. Repair: broken paths that could not be auto-fixed ─────────────────
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

    # ── 3. Games not yet extracted (informational) ───────────────────────────
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

    # ── 4. Control types with no reference game bound yet ────────────────────
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

    # ── 5. Game folders not recognised by TeknoParrot ────────────────────────
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
}

Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "   1. Launch TeknoParrotUi.exe -- registered games now appear."
Write-Host "   2. Work through the ACTION REQUIRED items above."
Write-Host "   3. Bind one game of each control type, then re-run and propagate."
Write-Host "   4. Test one propagated game before trusting the rest."
Write-Host ""
