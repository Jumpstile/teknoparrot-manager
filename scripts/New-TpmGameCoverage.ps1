<#
Development tool (not shipped to players): one table row per game profile ID, and what TeknoParrot Manager does for it.

Inputs (all read-only; nothing in them is ever executed, and guide text is only read as text):
  -GuidePath             the Eggman guide page (.html with the game-data block) or its game-data JSON
  -SnapshotManifestPath  the pinned official catalog snapshot (contracts\snapshots\...\snapshot-manifest.json)
  -RecipesPath           scripts\TpmRequiredPatchRecipes.json (the reviewed fixes TPM applies)
  -ProductScriptPath     TeknoParrot-Manager.ps1 (its check tables are read as syntax, never run)
  -ProfilesDir           optional: saved official profile XML files (adds the executable name and emulator)
Outputs: -OutputDir gets game-coverage.csv and game-coverage-summary.json; -MarkdownPath gets docs\GAME-SUPPORT.md.

Dispositions (first match wins):
  Applied  a reviewed recipe exists for the profile ID
  Checked  TPM verifies something for it (path length, pinned file, graphics card list, emulator startup files) and warns
  Gap      the guide lists the game but the pinned catalog has no profile for it, so TPM cannot register it (exact data named)
  Guided   the guide has setup text for it and TPM shows the plain steps in the Game Notes file
  Handled  nothing in the guide needs TPM; TeknoParrot itself does the work
#>
[CmdletBinding()]
param(
    [string]$GuidePath = '',
    [string]$SnapshotManifestPath = '',
    [string]$RecipesPath = '',
    [string]$ProductScriptPath = '',
    [string]$ProfilesDir = '',
    [string]$OutputDir = '',
    [string]$MarkdownPath = ''
)

function Read-TpmCoverageGuide {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    if ([System.IO.Path]::GetExtension($Path) -ine '.json') {
        $match = [regex]::Match($text, '(?s)<script type="application/json" id="game-data">(.*?)</script>')
        if (-not $match.Success) { throw 'The guide page has no game-data block.' }
        $text = $match.Groups[1].Value
    }
    return @(@($text | ConvertFrom-Json) | ForEach-Object { $_ })
}

# The profile IDs and lists TPM checks, read as syntax from the product script (never run).
function Get-TpmCoverageCheckTables {
    param([Parameter(Mandatory)][string]$ProductScriptPath)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ProductScriptPath, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) { throw 'The product script did not parse.' }
    $table = {
        param($name)
        $assign = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $n.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -eq $name }, $true)
        if ($null -eq $assign) { return $null }
        return $assign.Right.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
    }
    $keys = { param($name) $h = & $table $name; if ($null -eq $h) { return @() }; return @($h.KeyValuePairs | ForEach-Object { [string]$_.Item1.Value }) }
    # Only the table rows that name startup files count as "checked"; the other rows only say which folder an emulator runs from.
    $startupFileKeys = {
        param($name)
        $h = & $table $name
        if ($null -eq $h) { return @() }
        $needs = @('Files', 'RequiredFiles', 'FilesFromProfile', 'InstallVia')
        return @($h.KeyValuePairs | Where-Object {
                $row = $_.Item2.Find({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)
                $null -ne $row -and @($row.KeyValuePairs | Where-Object { $needs -contains [string]$_.Item1.Value }).Count -gt 0
            } | ForEach-Object { [string]$_.Item1.Value })
    }
    $gpu = @{}
    $gpuTable = & $table 'GpuIncompatibleGames'
    if ($null -ne $gpuTable) {
        foreach ($pair in $gpuTable.KeyValuePairs) {
            $gpu[[string]$pair.Item1.Value] = @($pair.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { [string]$_.Value })
        }
    }
    return [pscustomobject]@{
        PathLimits        = @(& $keys 'RawThrillsPathLimits')
        VersionPins       = @(& $keys 'FileVersionPins')
        GpuIncompatible   = $gpu
        FirmwareEmulators = @(& $startupFileKeys 'EmulatorBiosRequirements')
    }
}

function Get-TpmCoverageText {
    param($Row, [string]$Name)
    if ($null -eq $Row -or -not $Row.PSObject.Properties[$Name] -or $null -eq $Row.$Name) { return '' }
    return ([string]$Row.$Name).Trim()
}

# ROM-based loaders are the Tekno* loaders except the native PC one and Macaw.
function Test-TpmCoverageRomLoader {
    param([string]$Loader)
    return ($Loader -like 'Tekno*' -and $Loader -ne 'TeknoParrot' -and $Loader -ne 'TeknoMacaw')
}

# The guide's steps that the player still has to do. Text is split into sentences; a sentence counts as a step when it starts with an
# instruction word (Set, Enable, Install, ...) or says "you need" / "must". Not steps: the ZIP or EXE to select (TeknoParrot Manager sets the
# game file from the catalog profile), "Select Game Revision" (each guide version is its own profile and its Game Revision already holds that
# set), "Set CD Image Folder" (TeknoParrot Manager sets it after registration when exactly one matching CHD is found), "keep the BIOS ZIP
# beside it" and "Select CHD Root below the ROM ZIP" or a CHD second game file (Partner: found or checked in Library Health), "user-supplied ROM
# required" statements, "Development only" and "Latest revision" remarks, and everything after "Controls:" (controls are set up from the controls guide).
function Get-TpmCoverageManualSteps {
    param([string[]]$Text)
    $partnerPattern = '(?i)\.zip\b.*\b(same folder|beside)\b'
    $donePattern = '(?i)^Select [\w.\-]+\.(zip|exe|elf|xbe|chd)( or the merged [\w.\-]+\.zip)?( \([^)]*\))?( as the game file)?( and [\w.\-]+\.chd as the Game CHD)?( as the first game path and the game CHD as the second)?\.?$|^Select [\w.\-]+\.zip or the merged parent archive [\w.\-]+\.zip\.?$|^Select the merged [\w.\-]+\.zip ROM archive\.?$|^Select [\w.\-]+\.zip from your [\w ]+ ROM folder\.?$|^Select a merged ROM ZIP|^No separate game ROM ZIP|^(Development only|Latest revision)|\b(user-supplied|requires the matching)\b|^Select (the exact set in )?Game Revision\b|^Set CD Image Folder\b|^Select AMD Fix in settings\b'
    $stepPattern = '(?i)^(set|enable|disable|turn|use|edit|install|download|copy|delete|rename|extract|run|ensure|make sure|press|select|choose|apply|change|add|remove|open|go to|enter|replace|put|place|configure|calibrate|bind|plug|connect|launch|start|unzip|convert|always|read|try|do|don''t|never|switch|update|patch|reference|reset|click|right-click|create|move|unpack|keep|requires?)\b|\b(you(''ll)? need|you must|must be|needs? to be)\b'
    $steps = New-Object System.Collections.Generic.List[string]
    $partner = $false
    foreach ($chunk in @($Text)) {
        if ([string]::IsNullOrWhiteSpace($chunk)) { continue }
        $cut = [regex]::Replace($chunk, '(?s)\bControls:.*$', '')
        foreach ($sentence in @($cut -split '(?<=[.!?])\s+|\r?\n')) {
            $s = ($sentence -replace '^\s*-\s*', '').Trim()
            if (-not $s) { continue }
            if ($s -match $partnerPattern -or $s -match '(?i)^Select CHD Root below|\bas the Game CHD\b|\bthe game CHD as the second\b') { $partner = $true; continue }
            if ($s -match $donePattern) { continue }
            if ($s -match $stepPattern) { [void]$steps.Add($s) }
        }
    }
    return [pscustomobject]@{ Steps = $steps.ToArray(); Partner = $partner }
}

function Get-TpmCoverageDisposition {
    param([Parameter(Mandatory)]$Row, [string[]]$RecipeIds, $Tables)
    $id = [string]$Row.ProfileId
    if ($RecipeIds -contains $id) {
        return [pscustomobject]@{ Disposition = 'Applied'; Reason = 'A reviewed fix for this game is applied by TeknoParrot Manager.' }
    }
    $checks = New-Object System.Collections.Generic.List[string]
    if ($Tables.PathLimits -contains $id) { [void]$checks.Add('path length') }
    if ($Tables.VersionPins -contains $id) { [void]$checks.Add('pinned file version') }
    foreach ($vendor in @($Tables.GpuIncompatible.Keys)) { if (@($Tables.GpuIncompatible[$vendor]) -contains $id) { [void]$checks.Add($vendor + ' graphics card list') } }
    if (@($Tables.FirmwareEmulators | Where-Object { $_ -ieq [string]$Row.Loader }).Count -gt 0) { [void]$checks.Add('emulator startup files') }
    if ($checks.Count -gt 0) {
        return [pscustomobject]@{ Disposition = 'Checked'; Reason = ('TeknoParrot Manager checks and warns: ' + ($checks -join ', ') + '.') }
    }
    if ($Row.InGuide -and -not $Row.InCatalog) {
        return [pscustomobject]@{ Disposition = 'Gap'; Reason = 'The pinned catalog has no TeknoParrot profile for this game, so TeknoParrot Manager cannot register it.' }
    }
    if ($Row.HasManualStep) {
        return [pscustomobject]@{ Disposition = 'Guided'; Reason = 'The guide has a step TeknoParrot Manager cannot do safely by itself; the Game Notes file shows it.' }
    }
    if ($Row.DoneByCheck) {
        return [pscustomobject]@{ Disposition = 'Checked'; Reason = 'TeknoParrot Manager finds the second game file or partner ZIP beside the game and reports it in Library Health when it is missing.' }
    }
    return [pscustomobject]@{ Disposition = 'Handled'; Reason = 'The guide text is only information, or a step TeknoParrot Manager does itself (it sets the game file from the catalog profile).' }
}

function Get-TpmCoverageRows {
    param([object[]]$Guide, [hashtable]$CatalogCodes, [string[]]$RecipeIds, $Tables, [hashtable]$ProfileInfo)
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $add = {
        param($row, $parent)
        $id = Get-TpmCoverageText -Row $row -Name 'profile_name'
        if (-not $id) { return }
        $source = if ($null -ne $parent) { $parent } else { $row }
        $gpu = New-Object System.Collections.Generic.List[string]
        foreach ($vendor in @('amd', 'nvidia', 'intel')) {
            $status = Get-TpmCoverageText -Row $source -Name ($vendor + '_status')
            if ($status -and $status -ne 'OK') { [void]$gpu.Add(('{0}:{1}' -f $vendor, $status)) }
        }
        $loader = Get-TpmCoverageText -Row $source -Name 'tp_loader'
        $info = $ProfileInfo[$id]
        $secondFile = Get-TpmCoverageText -Row $row -Name 'setup_exe2'
        $hasText = [bool]((Get-TpmCoverageText -Row $row -Name 'notes') -or (Get-TpmCoverageText -Row $source -Name 'general_issues') -or
            $secondFile -or (Get-TpmCoverageText -Row $row -Name 'test_exe') -or $gpu.Count -gt 0 -or
            (Get-TpmCoverageText -Row $source -Name 'amd_issues') -or (Get-TpmCoverageText -Row $source -Name 'nvidia_issues') -or (Get-TpmCoverageText -Row $source -Name 'intel_issues'))
        $stepTexts = @((Get-TpmCoverageText -Row $source -Name 'general_issues'), (Get-TpmCoverageText -Row $row -Name 'notes')) +
            @('amd', 'nvidia', 'intel' | ForEach-Object { Get-TpmCoverageText -Row $source -Name ($_ + '_issues') })
        $steps = Get-TpmCoverageManualSteps -Text $stepTexts
        $manualSteps = @($steps.Steps)
        # A "works with a fix" card is a step only when the profile has no GPU Fix setting of its own; TeknoParrot Manager's graphics-card fix setup sets that setting for the card it finds.
        $gpuFixNeeded = (@('amd', 'nvidia', 'intel' | Where-Object { (Get-TpmCoverageText -Row $source -Name ($_ + '_status')) -eq 'WITH_FIX' }).Count -gt 0)
        if ($gpuFixNeeded -and -not ($null -ne $info -and $info.HasGpuFixField)) { $manualSteps += 'graphics-card fix' }
        $suppCount = 0
        if ($source.PSObject.Properties['supp_count'] -and $null -ne $source.supp_count) { $suppCount = [int]$source.supp_count }
        if ($suppCount -gt 0) { $manualSteps += 'supplementary archive' }
        $r = [pscustomobject]@{
            ProfileId = $id; GameName = (Get-TpmCoverageText -Row $row -Name 'game_name'); Loader = $loader
            ArcadeSystem = (Get-TpmCoverageText -Row $source -Name 'arcade_system')
            Source = $(if ($null -ne $parent) { 'Version' } else { 'Guide' }); ParentId = $(if ($null -ne $parent) { Get-TpmCoverageText -Row $parent -Name 'profile_name' } else { '' })
            InGuide = $true; InCatalog = $CatalogCodes.ContainsKey($id); ProfileXmlSeen = ($null -ne $info)
            EmulatorType = $(if ($null -ne $info) { $info.EmulatorType } else { '' }); ExecutableName = $(if ($null -ne $info) { $info.ExecutableName } else { '' })
            GuideExe = (Get-TpmCoverageText -Row $row -Name 'setup_exe'); GuideSecondFile = $secondFile
            GuideStatus = (Get-TpmCoverageText -Row $source -Name 'status')
            HasNotes = [bool](Get-TpmCoverageText -Row $row -Name 'notes'); HasGeneralIssues = [bool](Get-TpmCoverageText -Row $source -Name 'general_issues')
            HasTestProgram = [bool](Get-TpmCoverageText -Row $row -Name 'test_exe'); GraphicsNotOk = ($gpu -join ' ')
            SupplementaryArchives = $suppCount; HasGuideText = $hasText
            HasManualStep = ($manualSteps.Count -gt 0); ManualSteps = ($manualSteps -join ' | '); DoneByCheck = ($steps.Partner -or [bool]$secondFile)
            RomBased = (Test-TpmCoverageRomLoader -Loader $loader)
        }
        $d = Get-TpmCoverageDisposition -Row $r -RecipeIds $RecipeIds -Tables $Tables
        $open = New-Object System.Collections.Generic.List[string]
        if ($r.InGuide -and -not $r.InCatalog) { [void]$open.Add('the current TeknoParrot profile or ROM catalog file for this game (not in the pinned catalog)') }
        elseif (-not $r.ProfileXmlSeen) { [void]$open.Add('the profile XML (only its hash is in the pinned catalog), to confirm the executable name and any second game file') }
        if ($r.GuideSecondFile -and $r.GuideSecondFile -match '(?i)\.chd$') { [void]$open.Add('the second game file (CHD) is chosen by the player; TeknoParrot Manager only checks it') }
        if ($suppCount -gt 0) { [void]$open.Add('supplementary archive: source, license and hash before TeknoParrot Manager could install it') }
        if ($r.GuideStatus -eq 'Broken') { [void]$open.Add('the guide marks this game as broken in TeknoParrot') }
        if ($r.GraphicsNotOk -and $d.Disposition -ne 'Applied') { [void]$open.Add('graphics card: the guide text only; TeknoParrot Manager sets the profile GPU Fix setting when the profile has one') }
        $r | Add-Member -NotePropertyName Disposition -NotePropertyValue $d.Disposition
        $r | Add-Member -NotePropertyName Reason -NotePropertyValue $d.Reason
        $r | Add-Member -NotePropertyName OpenItems -NotePropertyValue ($open -join '; ')
        $seen[$id] = $true
        [void]$rows.Add($r)
    }
    foreach ($game in @($Guide)) {
        & $add $game $null
        if ($game.PSObject.Properties['variants']) { foreach ($variant in @($game.variants)) { if ($variant) { & $add $variant $game } } }
    }
    # Catalog profiles the guide does not list: nothing from the guide applies, so only the recipe and check tables can match.
    foreach ($code in @($CatalogCodes.Keys | Sort-Object)) {
        if ($seen.ContainsKey($code)) { continue }
        $info = $ProfileInfo[$code]
        $r = [pscustomobject]@{
            ProfileId = $code; GameName = ''; Loader = $(if ($null -ne $info) { $info.EmulatorType } else { '(not in guide)' }); ArcadeSystem = ''; Source = 'CatalogOnly'; ParentId = ''
            InGuide = $false; InCatalog = $true; ProfileXmlSeen = ($null -ne $info); EmulatorType = $(if ($null -ne $info) { $info.EmulatorType } else { '' })
            ExecutableName = $(if ($null -ne $info) { $info.ExecutableName } else { '' }); GuideExe = ''; GuideSecondFile = ''; GuideStatus = ''
            HasNotes = $false; HasGeneralIssues = $false; HasTestProgram = $false; GraphicsNotOk = ''; SupplementaryArchives = 0; HasGuideText = $false; RomBased = $false
        }
        $d = Get-TpmCoverageDisposition -Row $r -RecipeIds $RecipeIds -Tables $Tables
        $r | Add-Member -NotePropertyName Disposition -NotePropertyValue $d.Disposition
        $r | Add-Member -NotePropertyName Reason -NotePropertyValue $d.Reason
        $r | Add-Member -NotePropertyName OpenItems -NotePropertyValue $(if ($r.ProfileXmlSeen) { '' } else { 'the guide has no entry for this profile' })
        [void]$rows.Add($r)
    }
    return $rows.ToArray()
}

function Get-TpmCoverageSummary {
    param([Parameter(Mandatory)][object[]]$Rows)
    $order = @('Applied', 'Checked', 'Guided', 'Handled', 'Gap')
    $count = { param($set, $name) @($set | Where-Object { $_.Disposition -eq $name }).Count }
    $families = foreach ($group in @($Rows | Group-Object { if ($_.Loader) { $_.Loader } else { '(none)' } } | Sort-Object @{ Expression = 'Count'; Descending = $true }, Name)) {
        $f = [ordered]@{ Loader = $group.Name; Total = $group.Count; InCatalog = @($group.Group | Where-Object { $_.InCatalog }).Count; RomBased = [bool]$group.Group[0].RomBased }
        foreach ($name in $order) { $f[$name] = & $count $group.Group $name }
        [pscustomobject]$f
    }
    $totals = [ordered]@{ Total = @($Rows).Count }
    foreach ($name in $order) { $totals[$name] = & $count $Rows $name }
    $totals['InCatalog'] = @($Rows | Where-Object { $_.InCatalog }).Count
    $totals['NotInCatalog'] = @($Rows | Where-Object { $_.InGuide -and -not $_.InCatalog }).Count
    $totals['CatalogOnly'] = @($Rows | Where-Object { -not $_.InGuide }).Count
    $totals['Versions'] = @($Rows | Where-Object { $_.Source -eq 'Version' }).Count
    $totals['ProfileXmlSeen'] = @($Rows | Where-Object { $_.ProfileXmlSeen }).Count
    $totals['RomBased'] = @($Rows | Where-Object { $_.RomBased }).Count
    $totals['SupplementaryArchives'] = @($Rows | Where-Object { $_.SupplementaryArchives -gt 0 }).Count
    return [pscustomobject]@{ Totals = [pscustomobject]$totals; Families = @($families) }
}

function Get-TpmCoverageMarkdown {
    param([Parameter(Mandatory)]$Summary, [string]$CatalogVersion = '', [int]$CatalogProfiles = 0)
    $t = $Summary.Totals
    $nl = "`r`n"
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('# Game support' + $nl + $nl)
    [void]$sb.Append('This page counts the games in the Eggman guide and in the TeknoParrot catalog it was checked against, grouped by emulator, and says what TeknoParrot Manager does for each group. It does not list every game by name. The one-row-per-game list is a file (`game-coverage.csv`) that the tool makes in the folder you name (see Details at the bottom). The numbers are made by a tool (`scripts\New-TpmGameCoverage.ps1`), not typed by hand.' + $nl + $nl)
    [void]$sb.Append('## What the words mean' + $nl + $nl)
    [void]$sb.Append('- **Applied**: TeknoParrot Manager applies a reviewed fix for the game (see Required game patches).' + $nl)
    [void]$sb.Append('- **Checked**: TeknoParrot Manager checks something and warns you (path too long, a pinned file, a graphics card that does not work, emulator startup files, a BIOS ZIP or second game file that is not beside the game).' + $nl)
    [void]$sb.Append('- **Guided**: the guide has a step that TeknoParrot Manager cannot safely do for you (for example install a runtime, set a network address, use a card emulator, or download a file). TeknoParrot Manager puts the step in your Game Notes file. You do the step.' + $nl)
    [void]$sb.Append('- **Handled**: the guide only gives information, or asks for something TeknoParrot Manager does itself (it sets the game file). Nothing is left for you to do except supply the game files the guide names.' + $nl)
    [void]$sb.Append('- **Gap**: TeknoParrot has no game profile for this guide entry, so there is nothing to register. The per-game row in `game-coverage.csv` says exactly what is missing.' + $nl + $nl)
    [void]$sb.Append('## Totals' + $nl + $nl)
    [void]$sb.Append(('{0} game IDs in all: {1} guide games, {2} guide versions (other ROM revisions of a game), and {3} catalog profiles that the guide does not list.' -f $t.Total, ($t.Total - $t.CatalogOnly - $t.Versions), $t.Versions, $t.CatalogOnly) + $nl + $nl)
    [void]$sb.Append('| Applied | Checked | Guided | Handled | Gap |' + $nl + '|---|---|---|---|---|' + $nl)
    [void]$sb.Append(('| {0} | {1} | {2} | {3} | {4} |' -f $t.Applied, $t.Checked, $t.Guided, $t.Handled, $t.Gap) + $nl + $nl)
    [void]$sb.Append(('The catalog used is TeknoParrot {0} with {1} game profiles. {2} guide IDs have no profile in it; those are the Gap rows. {3} guide entries have supplementary archives that TeknoParrot Manager never downloads.' -f $CatalogVersion, $CatalogProfiles, $t.NotInCatalog, $t.SupplementaryArchives) + $nl + $nl)
    [void]$sb.Append('## By emulator' + $nl + $nl)
    [void]$sb.Append('| Emulator (loader) | Game IDs | In catalog | Applied | Checked | Guided | Handled | Gap |' + $nl + '|---|---|---|---|---|---|---|---|' + $nl)
    foreach ($f in $Summary.Families) {
        [void]$sb.Append(('| {0}{1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |' -f $f.Loader, $(if ($f.RomBased) { ' (ROM)' } else { '' }), $f.Total, $f.InCatalog, $f.Applied, $f.Checked, $f.Guided, $f.Handled, $f.Gap) + $nl)
    }
    [void]$sb.Append($nl + '## What you do')
    [void]$sb.Append($nl + $nl + '- **PC games and other emulators**: register with TeknoParrot Manager, read your Game Notes file, then set up the controls in TeknoParrot.' + $nl)
    [void]$sb.Append('- **ROM games (marked ROM)**: the guide asks you to pick the exact ZIP it names, keep the BIOS ZIP in the same folder, pick the matching game revision, set the CD image folder, and for some games pick a CHD file as a second game file. TeknoParrot Manager sets the game file when a catalog profile exists. Each guide version is its own profile and already holds its game revision. After registration it sets the CD Image Folder when exactly one matching CHD is in your games folder outside the place TeknoParrot searches by itself, and it finds a second-file CHD beside the ZIP or in a folder named after the game below it. Library Health (Game support) reports a BIOS ZIP or second game file that is missing.' + $nl)
    [void]$sb.Append('- **Gap rows**: guide entries that have no TeknoParrot profile of their own. Seven are extra archives that TeknoParrot has no profile for at all (the Sega Rally 3 track mods and Escape from Monster Manor); TeknoParrot Manager lists their folders as "not in TeknoParrot" and does not call that a failure. Two (Battle Gear 3 and Wayne Gretzky''s 3D Hockey Fatality Edition) run through a linked profile.' + $nl)
    [void]$sb.Append('- **Second profile not written**: four games (House of the Dead 4, Raiden III, Raiden IV and Densha de GO) have a first profile that TeknoParrot Manager registers, and the guide also names a second profile for them. The guide does not say what that second profile is for, so TeknoParrot Manager does not write it. These four are not Gap rows. They stay on this page so they are not forgotten. (The one exception is a game whose first profile TeknoParrot has retired: its second profile is written when the game folder has the file that profile starts.)' + $nl)
    [void]$sb.Append(('- **Profiles the guide does not list**: {0} TeknoParrot profiles have no guide entry. TeknoParrot Manager registers them like any other game, so a game TeknoParrot adds later needs no TeknoParrot Manager update. The Game Notes file gives each one a plain entry, with the platform, release year and known issues from TeknoParrot''s own game information when it has them.' -f $t.CatalogOnly) + $nl + $nl)
    [void]$sb.Append('## Details (for testers)' + $nl + $nl)
    [void]$sb.Append('Run `scripts\New-TpmGameCoverage.ps1 -GuidePath <guide page or game-data JSON> -SnapshotManifestPath <snapshot-manifest.json> -ProfilesDir <saved profile XML folder> -OutputDir <folder> -MarkdownPath docs\GAME-SUPPORT.md`. The tool writes one row per game ID with its loader, what the guide says, and the exact missing data for each gap. Guide text is only read, never run. A refresh is needed whenever the guide, the catalog snapshot or the reviewed recipe list changes. `scripts\Test-TpmCatalogDrift.ps1 -ProfilesPath <TeknoParrot folder or clone of the official repository> -GuidePath <guide> -MarkdownPath docs\GAME-SUPPORT.md` makes the same page from a current TeknoParrot folder, and lists new, removed and changed profiles; a weekly workflow runs it and opens one issue when a new profile needs a decision.' + $nl)
    return $sb.ToString()
}

if ($MyInvocation.InvocationName -eq '.') { return }

if (-not $GuidePath -or -not $SnapshotManifestPath) { throw 'Give -GuidePath and -SnapshotManifestPath.' }
$toolFolder = Split-Path -Parent $PSCommandPath
if (-not $RecipesPath) { $RecipesPath = Join-Path $toolFolder 'TpmRequiredPatchRecipes.json' }
if (-not $ProductScriptPath) { $ProductScriptPath = Join-Path $toolFolder '..\TeknoParrot-Manager.ps1' }
$guide = Read-TpmCoverageGuide -Path $GuidePath
$manifest = [System.IO.File]::ReadAllText($SnapshotManifestPath) | ConvertFrom-Json
$catalog = @{}
foreach ($file in @($manifest.Files)) { if ([string]$file.Root -eq 'GameProfiles') { $catalog[[string]$file.ProfileCode] = $true } }
$recipeIds = @(([System.IO.File]::ReadAllText($RecipesPath) | ConvertFrom-Json).Entries | ForEach-Object { [string]$_.ProfileId } | Sort-Object -Unique)
$profileInfo = @{}
if ($ProfilesDir -and (Test-Path -LiteralPath $ProfilesDir -PathType Container)) {
    foreach ($file in Get-ChildItem -LiteralPath $ProfilesDir -Filter '*.xml' -File) {
        $doc = New-Object System.Xml.XmlDocument
        $doc.XmlResolver = $null
        $doc.Load($file.FullName)
        $emulatorNode = $doc.SelectSingleNode('/GameProfile/EmulatorType')
        $exeNode = $doc.SelectSingleNode('/GameProfile/ExecutableName')
        $fieldNames = @($doc.SelectNodes('/GameProfile/ConfigValues/FieldInformation/FieldName') | ForEach-Object { $_.InnerText.Trim() })
        $profileInfo[$file.BaseName] = [pscustomobject]@{ EmulatorType = $(if ($emulatorNode) { $emulatorNode.InnerText.Trim() } else { '' }); ExecutableName = $(if ($exeNode) { $exeNode.InnerText.Trim() } else { '' }); HasGpuFixField = (@($fieldNames | Where-Object { $_ -match '^(GPU Fix|EnableAmdFix|AMDCrashFix|AMDFix|NVIDIA Fix)$' }).Count -gt 0) }
    }
}
$tables = Get-TpmCoverageCheckTables -ProductScriptPath $ProductScriptPath
$rows = @(Get-TpmCoverageRows -Guide $guide -CatalogCodes $catalog -RecipeIds $recipeIds -Tables $tables -ProfileInfo $profileInfo)
$summary = Get-TpmCoverageSummary -Rows $rows
if ($OutputDir) {
    [void][System.IO.Directory]::CreateDirectory($OutputDir)
    $rows | Export-Csv -LiteralPath (Join-Path $OutputDir 'game-coverage.csv') -NoTypeInformation -Encoding UTF8
    [System.IO.File]::WriteAllText((Join-Path $OutputDir 'game-coverage-summary.json'), ($summary | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
}
if ($MarkdownPath) {
    [System.IO.File]::WriteAllText($MarkdownPath, (Get-TpmCoverageMarkdown -Summary $summary -CatalogVersion ([string]$manifest.Release.Version) -CatalogProfiles ([int]$manifest.CatalogCounts.GameProfiles)), (New-Object System.Text.UTF8Encoding $false))
}
$summary.Totals | Format-List | Out-String | Write-Host
