# Evidence run for the shared game matching engine.
#
# Runs the engine over EVERY TeknoParrot game profile in a folder, using the Eggman DAT list, the TeknoParrot metadata, the game folder
# names (only when the DAT confirms them) and a copy of the LaunchBox games database. It writes one report file with:
#   1. the totals per outcome (certain match, ambiguous, no match, not a game),
#   2. every ambiguous case, every no-match and every not-a-game profile,
#   3. a spot-check list of certain matches (both names side by side) so a person can read them,
#   4. automatic warnings for certain matches whose names look too different,
#   5. when a LaunchBox platform file is given, how the engine compares with the links LaunchBox itself made,
#   6. the full table, one line per profile.
# Everything is read-only. Point -GamesDb at a COPY of LaunchBox.Metadata.db, never at the live file, and keep -ReportPath outside
# every LaunchBox and TeknoParrot folder. Needs Windows PowerShell 5.1 (the games database reader uses winsqlite3.dll).
#
# Example:
#   powershell -NoProfile -File scripts\Invoke-TpmMatchEvidence.ps1 -TeknoParrotRoot <TeknoParrot folder> -GamesDb <copy of LaunchBox.Metadata.db> `
#       -DatFile <Eggman .dat> -ReportPath <report.txt> [-CollectionFolder <folder of Eggman game folders or ZIPs>] [-LaunchBoxPlatformFile <Data\Platforms\TeknoParrot.xml>]
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TeknoParrotRoot,
    [Parameter(Mandatory)][string]$GamesDb,
    [Parameter(Mandatory)][string]$DatFile,
    [Parameter(Mandatory)][string]$ReportPath,
    [string]$ProfileFolder = '',
    [string]$CollectionFolder = '',
    [string]$LaunchBoxPlatformFile = '',
    [string]$ProductionScript = '',
    [ValidateRange(1, 100000)][int]$SpotCheckCount = 150,
    [ValidateRange(0.1, 1.0)][double]$WarnBelow = 0.6
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
if (-not $ProfileFolder) { $ProfileFolder = Join-Path $TeknoParrotRoot 'GameProfiles' }
if (-not $ProductionScript) { $ProductionScript = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1' }
foreach ($required in @($TeknoParrotRoot, $ProfileFolder)) { if (-not (Test-Path -LiteralPath $required -PathType Container)) { throw "Folder not found: $required" } }
foreach ($required in @($GamesDb, $DatFile, $ProductionScript)) { if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "File not found: $required" } }
if ($GamesDb -match '(?i)[\\/]LaunchBox[\\/]Metadata[\\/]') { throw 'Use a copy of the games database, not the live LaunchBox file.' }

# Load every function of the production script (no top-level code runs), then replace the screen and log helpers with silent ones.
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $ProductionScript).Path, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'The production script could not be parsed.' }
$functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
$loadFile = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-evidence-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    [System.IO.File]::WriteAllText($loadFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $loadFile
} finally { Remove-Item -LiteralPath $loadFile -Force -ErrorAction SilentlyContinue }
$script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'), [System.StringComparer]::OrdinalIgnoreCase)
# Silent stand-ins for the log and progress helpers (set as items, so no function of the product is defined twice).
Set-Item -Path Function:\Write-Log -Value { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
Set-Item -Path Function:\Write-TpmCompactExtractionProgress -Value { param([Parameter(ValueFromRemainingArguments)]$Ignored) }

Write-Host 'Reading the Eggman list...'
$datIndex = Build-DatIndex $DatFile -Quiet
if ($datIndex.Count -eq 0) { throw 'The Eggman list could not be read.' }
$datByCode = Get-TpmDatEntriesByCode -DatIndex $datIndex
Write-Host 'Reading the games database copy...'
$index = Get-TpmGamesDbIndex -DbPath $GamesDb

# Game folders on disk (or ZIPs named like them): a folder is a source only when the list confirms it. The fake path ends with the
# file the list names inside the folder, so the same confirmation code runs as in the product.
$folderByCode = @{}
$folderCount = 0
if ($CollectionFolder) {
    if (-not (Test-Path -LiteralPath $CollectionFolder -PathType Container)) { throw "Folder not found: $CollectionFolder" }
    foreach ($item in @(Get-ChildItem -LiteralPath $CollectionFolder -Force)) {
        $folderCount++
        $folder = $item.Name -replace '(?i)\.zip$', ''
        $entry = Get-DatEntryForZipName -RawZipName $folder -DatIndex $datIndex
        if ($null -eq $entry -or [string]$entry.OriginalName -ine $folder) { continue }
        $folderByCode[([string]$entry.ProfileCode).Trim().ToLowerInvariant()] = ('X:\Collection\{0}\{1}' -f $folder, ([string]$entry.Executable).Trim())
    }
}

$files = @(Get-ChildItem -LiteralPath $ProfileFolder -Filter '*.xml' -File | Sort-Object Name)
Write-Host ('Matching {0} profiles...' -f $files.Count)
$rows = New-Object System.Collections.Generic.List[object]
$counter = 0
foreach ($file in $files) {
    $counter++
    if (($counter % 250) -eq 0) { Write-Host ('  {0} of {1}' -f $counter, $files.Count) }
    $code = $file.BaseName
    $gamePath = if ($folderByCode.ContainsKey($code.ToLowerInvariant())) { $folderByCode[$code.ToLowerInvariant()] } else { '' }
    $subject = Get-TpmProfileMatchSubject -Code $code -ProfilePath $file.FullName -TpRoot $TeknoParrotRoot -DatIndex $datIndex -DatByCode $datByCode -GamePath $gamePath
    $result = Resolve-TpmGameMatch -Index $index -Subject $subject
    [void]$rows.Add([pscustomobject]@{ Code = $code; Subject = $subject; Result = $result })
}

# ---- report ----
$report = New-Object System.Collections.Generic.List[string]
function Add-Line { param([string]$Text = '') [void]$report.Add($Text) }
$describeNames = { param($subject) (@($subject.Names | ForEach-Object { '{0}{1}: "{2}"' -f $_.Source, $(if ($_.Fallback) { ' (weak)' } else { '' }), $_.Name }) -join ' | ') }
$describeMatch = { param($match) if ($null -eq $match) { '(none)' } else { '{0} [id {1}, year {2}, developer {3}]' -f $match.Name, $match.Id, $match.Year, $match.Developer } }
$certain = @($rows | Where-Object { $_.Result.Status -eq 'Certain' })
$ambiguous = @($rows | Where-Object { $_.Result.Status -eq 'Ambiguous' })
$noMatch = @($rows | Where-Object { $_.Result.Status -eq 'NoMatch' })
$notGame = @($rows | Where-Object { $_.Result.Status -eq 'NotGame' })

Add-Line 'TeknoParrot Manager - game matching evidence run'
Add-Line ('Run at: {0}' -f $started.ToString('yyyy-MM-dd HH:mm:ss'))
Add-Line ('Profiles read: {0}   Eggman list games: {1}   Game folders on disk checked: {2} (confirmed by the list: {3})' -f $rows.Count, @($datByCode.Keys).Count, $folderCount, $folderByCode.Count)
Add-Line ('Games database platforms searched: {0}   Games in the index: {1}' -f ($index.Platforms -join ', '), $index.ById.Count)
Add-Line ('Names looked up: {0}   Profiles with a confirmed game folder: {1}' -f (($rows | ForEach-Object { @($_.Subject.Names).Count } | Measure-Object -Sum).Sum), @($rows | Where-Object { $_.Subject.FolderConfirmed }).Count)
Add-Line
Add-Line '== 1. Totals =='
Add-Line ('Certain match : {0}' -f $certain.Count)
foreach ($group in @($certain | Group-Object { $_.Result.Level } | Sort-Object Name)) { Add-Line ('    found at level {0}: {1}' -f $group.Name, $group.Count) }
Add-Line ('Ambiguous     : {0}' -f $ambiguous.Count)
foreach ($group in @($ambiguous | Group-Object { $_.Result.Reason } | Sort-Object Count -Descending)) { Add-Line ('    {0}: {1}' -f $group.Name, $group.Count) }
Add-Line ('No match      : {0}' -f $noMatch.Count)
Add-Line ('Not a game    : {0}' -f $notGame.Count)
Add-Line ('Total         : {0}' -f ($certain.Count + $ambiguous.Count + $noMatch.Count + $notGame.Count))

Add-Line
Add-Line '== 2a. Not a game (never added to LaunchBox) =='
foreach ($row in $notGame) { Add-Line ('{0}: {1} -- {2}' -f $row.Code, $row.Result.Title, $row.Result.Reason) }
Add-Line
Add-Line ('== 2b. Every ambiguous case ({0}) ==' -f $ambiguous.Count)
foreach ($row in $ambiguous) {
    Add-Line ('{0}: {1}' -f $row.Code, $row.Result.Reason)
    Add-Line ('    names  : {0}' -f (& $describeNames $row.Subject))
    Add-Line ('    facts  : year {0}, hardware {1}' -f $row.Subject.Year, $row.Subject.Hardware)
    foreach ($option in @($row.Result.Options)) { Add-Line ('    option : {0} [id {1}, score {2}]' -f $option.Name, $option.Id, $option.Score) }
    if ($row.Result.Evidence) { Add-Line ('    trail  : {0}' -f $row.Result.Evidence) }
}
Add-Line
Add-Line ('== 2c. No match ({0}) ==' -f $noMatch.Count)
foreach ($row in $noMatch) { Add-Line ('{0}: {1}' -f $row.Code, (& $describeNames $row.Subject)) }

# 3. spot check: evenly spread through the certain matches, so every kind of hardware and every level is seen.
Add-Line
$stride = [Math]::Max(1, [int][Math]::Floor($certain.Count / [double][Math]::Min($SpotCheckCount, [Math]::Max(1, $certain.Count))))
$spot = @(for ($i = 0; $i -lt $certain.Count; $i += $stride) { $certain[$i] })
Add-Line ('== 3. Spot check: {0} certain matches, both names side by side ==' -f $spot.Count)
foreach ($row in $spot) {
    Add-Line ('{0} (level {1}, {2})' -f $row.Code, $row.Result.Level, $row.Result.Reason)
    Add-Line ('    sources: {0}' -f (& $describeNames $row.Subject))
    Add-Line ('    matched: {0}' -f (& $describeMatch $row.Result.Match))
    Add-Line ('    facts  : year {0}, maker {1}' -f $row.Subject.Year, $row.Subject.Maker)
}

# 4. automatic warnings: a certain match whose name shares little with every name the sources gave.
Add-Line
$warnings = New-Object System.Collections.Generic.List[object]
foreach ($row in $certain) {
    $matchKey = Get-TpmMatchCanonKey ([string]$row.Result.Match.Name)
    $best = 0.0
    foreach ($name in @($row.Subject.Names)) {
        $score = Get-DiceSimilarity $matchKey (Get-TpmMatchCanonKey (Get-TpmMatchCleanTitle ([string]$name.Name)))
        if ($score -gt $best) { $best = $score }
    }
    $yearApart = if ($row.Subject.Year -gt 0 -and $row.Result.Match.Year -gt 0) { [Math]::Abs($row.Subject.Year - $row.Result.Match.Year) } else { 0 }
    if ($best -lt $WarnBelow -or $yearApart -ge 5) { [void]$warnings.Add([pscustomobject]@{ Row = $row; Score = $best; YearApart = $yearApart }) }
}
Add-Line ('== 4. Warnings: certain matches whose names look different (score below {0}) or whose years are 5 or more apart: {1} ==' -f $WarnBelow, $warnings.Count)
foreach ($warning in $warnings) {
    Add-Line ('{0} (level {1}, name score {2}, years apart {3})' -f $warning.Row.Code, $warning.Row.Result.Level, [Math]::Round($warning.Score, 2), $warning.YearApart)
    Add-Line ('    sources: {0}' -f (& $describeNames $warning.Row.Subject))
    Add-Line ('    matched: {0}' -f (& $describeMatch $warning.Row.Result.Match))
}

# 5. LaunchBox's own links for the same profiles (when a platform file is given).
if ($LaunchBoxPlatformFile) {
    Add-Line
    $byCode = @{}; foreach ($row in $rows) { $byCode[$row.Code.ToLowerInvariant()] = $row }
    $agree = 0; $differ = New-Object System.Collections.Generic.List[string]; $lbUnlinked = 0; $unknown = 0
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.Load((Resolve-Path -LiteralPath $LaunchBoxPlatformFile).Path)
    foreach ($game in @($doc.SelectNodes('/LaunchBox/Game'))) {
        $path = Get-XmlChildText $game 'ApplicationPath'
        $code = [System.IO.Path]::GetFileNameWithoutExtension($path).ToLowerInvariant()
        $lbId = (Get-XmlChildText $game 'DatabaseID').Trim()
        if (-not $byCode.ContainsKey($code)) { $unknown++; continue }
        if (-not $lbId -or $lbId -eq '0') { $lbUnlinked++; continue }
        $row = $byCode[$code]
        if ($row.Result.Status -eq 'Certain' -and [string]$row.Result.Match.Id -eq $lbId) { $agree++ }
        else {
            $lbGame = $index.ById[$lbId]
            [void]$differ.Add(('{0}: LaunchBox title "{1}" is linked to {2}; the engine says {3}{4}' -f $code, (Get-XmlChildText $game 'Title'), $(if ($lbGame) { '"{0}" (id {1})' -f $lbGame.Name, $lbId } else { 'id ' + $lbId }), $row.Result.Status, $(if ($row.Result.Match) { ': "{0}" (id {1})' -f $row.Result.Match.Name, $row.Result.Match.Id } else { '' })))
        }
    }
    Add-Line ('== 5. LaunchBox own links (a person adds or the scraper made them, so they can be wrong too): same as the engine {0}, different {1}, not linked in LaunchBox {2}, profile not in this folder {3} ==' -f $agree, $differ.Count, $lbUnlinked, $unknown)
    foreach ($line in $differ) { Add-Line $line }
}

Add-Line
Add-Line ('== 6. Full table ({0} profiles): code | outcome | level | title | matched game ==' -f $rows.Count)
foreach ($row in $rows) { Add-Line ('{0} | {1} | {2} | {3} | {4}' -f $row.Code, $row.Result.Status, $row.Result.Level, $row.Result.Title, $(if ($row.Result.Match) { '{0} (id {1})' -f $row.Result.Match.Name, $row.Result.Match.Id } else { '' })) }
Add-Line
Add-Line ('Finished in {0:N0} seconds.' -f ((Get-Date) - $started).TotalSeconds)

$reportFolder = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ReportPath))
if ($reportFolder -and -not (Test-Path -LiteralPath $reportFolder)) { [void][System.IO.Directory]::CreateDirectory($reportFolder) }
[System.IO.File]::WriteAllText($ReportPath, (($report.ToArray()) -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding $false))
Write-Host ('Report written: {0}' -f $ReportPath)
Write-Host ('Certain {0}, ambiguous {1}, no match {2}, not a game {3}.' -f $certain.Count, $ambiguous.Count, $noMatch.Count, $notGame.Count)
