#Requires -Module Pester

# Issue 387 and 389 (game types): every game type is known, and the Library health check says plainly what a player must do.
#   - A game type that is not in the table is flagged by name, never ignored.
#   - A development-only game (TeknoTJC today) is "not available yet", not a failure.
#   - The emulator folder is looked for on disk (Dolphin runs from CrediarDolphin, TeknoMacaw from the TeknoParrot folder).
#   - A game with no executable name and no setup file is listed as "pick the game file by hand".
#   - System 11: a set of ZIPs ("child.zip;parent.zip") needs both; "*.chd" finds the one disc image (never guesses between two);
#     saved flash/EEPROM files are copied only from the player's own set and never replace a file.
# Synthetic files only, under TestDrive. The product script is parsed and only its function definitions and the table are loaded.
# What this CANNOT prove: how a real console paints the rows, or that System 11 accepts the saved files.

BeforeAll {
    $script:F387GProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($script:F387GProductionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX387 game type tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix387g-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $assignment = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$EmulatorBiosRequirements' })
    if ($assignment.Count -ne 1) { throw 'FIX387 game type tests expected exactly one production assignment of $EmulatorBiosRequirements.' }
    $script:EmulatorBiosRequirements = & ([scriptblock]::Create($assignment[0].Right.Extent.Text))
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:ScriptVersion = 'test'
    $script:tpRoot = $null
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    function New-F387GRoot {
        $root = Join-Path $TestDrive ('f387g-' + [guid]::NewGuid().ToString('N'))
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        return [pscustomobject]@{ Root = $root; Profiles = $profiles }
    }

    function Add-F387GProfile {
        param($Fixture, [string]$Code, [string]$Type, [string]$Exe = 'game.exe', [bool]$DevOnly = $false, [string]$GamePath = '', [string]$Exe2 = '', [bool]$Two = $false)
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><GamePath>{0}</GamePath><EmulatorType>{1}</EmulatorType><ExecutableName>{2}</ExecutableName><ExecutableName2>{3}</ExecutableName2><HasTwoExecutables>{4}</HasTwoExecutables><DevOnly>{5}</DevOnly></GameProfile>' -f $GamePath, $Type, $Exe, $Exe2, $Two.ToString().ToLowerInvariant(), $DevOnly.ToString().ToLowerInvariant()
        [System.IO.File]::WriteAllText((Join-Path $Fixture.Profiles ($Code + '.xml')), $xml)
    }

    function Get-F387GReport {
        param($Fixture)
        return (Get-TpmGameTypeReport -Profiles @(Get-ChildItem -LiteralPath $Fixture.Profiles -Filter '*.xml') -TeknoParrotRoot $Fixture.Root)
    }

    function New-F387GZip {
        param([string]$Path, [hashtable]$Entries)
        $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries.Keys) {
                $entry = $zip.CreateEntry($name)
                $stream = $entry.Open()
                try { $bytes = [System.Text.Encoding]::ASCII.GetBytes([string]$Entries[$name]); $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
    }
}

Describe 'Game types in the Library health check (issues 387 and 389)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
    }

    It 'flags a game type that is not in the table, by name, and says so in a row' {
        $fixture = New-F387GRoot
        Add-F387GProfile -Fixture $fixture -Code 'Fine' -Type 'TeknoNaomi'
        Add-F387GProfile -Fixture $fixture -Code 'Strange' -Type 'TeknoBrandNew'
        New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'TeknoNaomi') -Force | Out-Null
        $report = Get-F387GReport -Fixture $fixture
        @($report.Unknown).Count | Should -Be 1
        $report.Unknown[0].Type | Should -Be 'TeknoBrandNew'
        @($report.Unknown[0].Games) | Should -Be @('Strange')
        $row = @(Get-TpmGameTypeRows -Report $report | Where-Object { $_.Area -eq 'Game types' })[0]
        $row.Text | Should -Match '^Needs attention - 1 game has a game type that TeknoParrot Manager does not know'
        (@(Get-TpmGameTypeDetailBlocks -Report $report)[0].Lines -join ' ') | Should -Match 'Unknown game type TeknoBrandNew: Strange'
    }

    It 'says OK when every game has a known type and its emulator folder' {
        $fixture = New-F387GRoot
        Add-F387GProfile -Fixture $fixture -Code 'Fine' -Type 'TeknoNaomi'
        New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'TeknoNaomi') -Force | Out-Null
        $rows = @(Get-TpmGameTypeRows -Report (Get-F387GReport -Fixture $fixture))
        @($rows | Where-Object { $_.Area -eq 'Game types' })[0].Text | Should -Be 'OK'
    }

    It 'calls a development-only game "not available yet" and says nothing once it is released' {
        $fixture = New-F387GRoot
        Add-F387GProfile -Fixture $fixture -Code 'JcDev' -Type 'TeknoTJC' -DevOnly $true
        New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'TeknoTJC') -Force | Out-Null
        $report = Get-F387GReport -Fixture $fixture
        @($report.NotAvailable) | Should -Be @('JcDev')
        (@(Get-TpmGameTypeRows -Report $report | Where-Object { $_.Area -eq 'Game types' })[0].Text) | Should -Match '1 game is not available yet'
        Add-F387GProfile -Fixture $fixture -Code 'JcDev' -Type 'TeknoTJC' -DevOnly $false
        @((Get-F387GReport -Fixture $fixture).NotAvailable).Count | Should -Be 0
    }

    It 'finds Dolphin in CrediarDolphin and TeknoMacaw in the TeknoParrot folder, and reports an emulator that is not there' {
        $fixture = New-F387GRoot
        Add-F387GProfile -Fixture $fixture -Code 'GcGame' -Type 'Dolphin'
        Add-F387GProfile -Fixture $fixture -Code 'AcioGame' -Type 'TeknoMacaw'
        Add-F387GProfile -Fixture $fixture -Code 'GhostGame' -Type 'TeknoZeus'
        New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'CrediarDolphin') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'TeknoParrot') -Force | Out-Null
        $report = Get-F387GReport -Fixture $fixture
        @($report.EmulatorMissing).Count | Should -Be 1
        $report.EmulatorMissing[0].Type | Should -Be 'TeknoZeus'
        (@(Get-TpmGameTypeRows -Report $report | Where-Object { $_.Area -eq 'Game types' })[0].Text) | Should -Match 'the emulator for 1 game is not in your TeknoParrot folder'
    }

    It 'lists a game with no executable name and no setup file, but not one that has a setup file or a game path' {
        $fixture = New-F387GRoot
        $exe = Join-Path $fixture.Root 'picked.exe'
        [System.IO.File]::WriteAllText($exe, 'x')
        Add-F387GProfile -Fixture $fixture -Code 'NoExe' -Type 'TeknoParrot' -Exe ''
        Add-F387GProfile -Fixture $fixture -Code 'HasSetup' -Type 'TeknoParrot' -Exe ''
        Add-F387GProfile -Fixture $fixture -Code 'Picked' -Type 'TeknoParrot' -Exe '' -GamePath $exe
        New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'TeknoParrot') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $fixture.Root 'GameSetup') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $fixture.Root 'GameSetup\HasSetup.xml'), '<GameSetup><GameExecutableLocation>a\b.exe</GameExecutableLocation></GameSetup>')
        $report = Get-F387GReport -Fixture $fixture
        @($report.NeedsManualExe) | Should -Be @('NoExe')
        (@(Get-TpmGameTypeRows -Report $report | Where-Object { $_.Area -eq 'Game files' })[0].Text) | Should -Match '1 game needs you to pick the game file by hand'
    }

    It 'does not call games unknown when the table is not loaded' {
        $saved = $script:EmulatorBiosRequirements
        try {
            $script:EmulatorBiosRequirements = $null
            $fixture = New-F387GRoot
            Add-F387GProfile -Fixture $fixture -Code 'Strange' -Type 'TeknoBrandNew'
            @(Get-TpmGameTypeRows -Report (Get-F387GReport -Fixture $fixture)).Count | Should -Be 0
        } finally { $script:EmulatorBiosRequirements = $saved }
    }
}

Describe 'System 11 game files (issue 387)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
    }

    It 'treats child.zip;parent.zip as a set that needs both, and "a.elf;b.elf" as alternatives' {
        $set = Get-TpmGameFileSet -ExecutableName 'ddr2ml.zip;ddr2m.zip'
        $set.IsSet | Should -BeTrue
        @($set.Choices) | Should -Be @('ddr2ml.zip')
        @($set.Partners) | Should -Be @('ddr2m.zip')
        $alternatives = Get-TpmGameFileSet -ExecutableName 'apacheM_HD.elf;apacheM.elf'
        $alternatives.IsSet | Should -BeFalse
        @($alternatives.Choices) | Should -Be @('apacheM_HD.elf', 'apacheM.elf')
    }

    It 'reports the second ZIP that is not beside the game file, and nothing when it is there' {
        $folder = Join-Path $TestDrive ('set-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $child = Join-Path $folder 'ddr2ml.zip'
        [System.IO.File]::WriteAllText($child, 'x')
        @(Get-TpmMissingGameSetFiles -GamePath $child -ExecutableName 'ddr2ml.zip;ddr2m.zip') | Should -Be @('ddr2m.zip')
        [System.IO.File]::WriteAllText((Join-Path $folder 'ddr2m.zip'), 'x')
        @(Get-TpmMissingGameSetFiles -GamePath $child -ExecutableName 'ddr2ml.zip;ddr2m.zip').Count | Should -Be 0
    }

    It 'names a registered game in "Game support" when its second ZIP is missing' {
        $fixture = New-F387GRoot
        $games = Join-Path $fixture.Root 'games'
        New-Item -ItemType Directory -Path $games -Force | Out-Null
        $child = Join-Path $games 'ddr2ml.zip'
        [System.IO.File]::WriteAllText($child, 'x')
        Add-F387GProfile -Fixture $fixture -Code 'ddr2ml' -Type 'TeknoS11' -Exe 'ddr2ml.zip;ddr2m.zip' -GamePath $child
        $files = @(Get-ChildItem -LiteralPath $fixture.Profiles -Filter '*.xml')
        $summary = Get-TpmGameSupportSummary -ProfileFiles $files -ValidCodes @('ddr2ml')
        @($summary.NeedsYouNames) | Should -Be @('ddr2ml')
        [System.IO.File]::WriteAllText((Join-Path $games 'ddr2m.zip'), 'x')
        @((Get-TpmGameSupportSummary -ProfileFiles $files -ValidCodes @('ddr2ml')).NeedsYouNames).Count | Should -Be 0
    }

    It 'sets the second game file to the one disc image beside or in the game disc folder' {
        $folder = Join-Path $TestDrive ('chd-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $folder 'brvbladeg') -Force | Out-Null
        $zip = Join-Path $folder 'coh3002t.zip'
        [System.IO.File]::WriteAllText($zip, 'x')
        $chd = Join-Path $folder 'brvbladeg\braveblade.chd'
        [System.IO.File]::WriteAllText($chd, 'x')
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<GameProfile><ExecutableName>coh3002t.zip</ExecutableName><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>*.chd</ExecutableName2></GameProfile>')
        (Set-SecondaryExecutablePath $doc $zip -ProfileCode 'brvbladeg') | Should -BeTrue
        $doc.GameProfile.GamePath2 | Should -Be $chd
    }

    It 'does not guess between two disc images' {
        $folder = Join-Path $TestDrive ('chd2-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $folder 'pcnfrk') -Force | Out-Null
        $zip = Join-Path $folder 'drmn.zip'
        [System.IO.File]::WriteAllText($zip, 'x')
        [System.IO.File]::WriteAllText((Join-Path $folder 'pcnfrk\881jad01.chd'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $folder 'pcnfrk\881xxb02.chd'), 'x')
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<GameProfile><ExecutableName>drmn.zip;pcnfrk.zip</ExecutableName><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>*.chd</ExecutableName2></GameProfile>')
        (Set-SecondaryExecutablePath $doc $zip -ProfileCode 'drmn') | Should -BeFalse
        [string]$doc.GameProfile.GamePath2 | Should -Be ''
    }

    It 'does not take a disc image from another game''s folder' {
        $folder = Join-Path $TestDrive ('chd3-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $folder 'othergame') -Force | Out-Null
        $zip = Join-Path $folder 'bam2.zip'
        [System.IO.File]::WriteAllText($zip, 'x')
        [System.IO.File]::WriteAllText((Join-Path $folder 'othergame\other.chd'), 'x')
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<GameProfile><ExecutableName>bam2.zip</ExecutableName><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>*.chd</ExecutableName2></GameProfile>')
        (Set-SecondaryExecutablePath $doc $zip -ProfileCode 'bam2') | Should -BeFalse
    }
}

Describe 'System 11 saved files (issue 387)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
        $script:s11 = New-F387GRoot
        New-Item -ItemType Directory -Path (Join-Path $s11.Root 'TeknoS11') -Force | Out-Null
        foreach ($code in @('gameA', 'gameB', 'gameC')) { Add-F387GProfile -Fixture $s11 -Code $code -Type 'TeknoS11' -Exe ($code + '.zip') }
        $script:s11Set = Join-Path $s11.Root 'collection\[NVRAM] TeknoS11 preinstalled game files for System 11.zip'
        New-Item -ItemType Directory -Path (Split-Path -Parent $s11Set) -Force | Out-Null
        New-F387GZip -Path $s11Set -Entries @{
            'README.txt'                                          = 'readme'
            'TeknoS11/state/gameA/cabinet-1/at28c16.bin'          = 'flash A'
            'TeknoS11/state/gameA/cabinet-1/gnet-flash.bin'       = 'flash A2'
            'TeknoS11/state/gameB/cabinet-1/at28c16.bin'          = 'flash B'
            'TeknoS11/state/notmine/cabinet-1/at28c16.bin'        = 'not registered'
            'TeknoS11/state/gameC/cabinet-2/at28c16.bin'          = 'wrong cabinet'
        }
    }

    It 'copies the files of registered games, keeps an existing file, and says plainly which game has none' {
        $existing = Join-Path $s11.Root 'TeknoS11\state\gameB\cabinet-1'
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $existing 'at28c16.bin'), 'MY OWN SAVE')
        $plan = Get-TpmS11PreinstallPlan -SourcePath $s11Set -TeknoParrotRoot $s11.Root -GameCodes @('gameA', 'gameB', 'gameC')
        $plan.Valid | Should -BeTrue
        @($plan.NoFileGames) | Should -Be @('gameC')
        @($plan.AlreadyHave) | Should -Be @('gameB')
        @($plan.NewGames) | Should -Be @('gameA')
        $result = Invoke-TpmS11PreinstallInstall -Plan $plan -TpRoot $s11.Root
        $result.Outcome | Should -Be 'SUCCEEDED'
        $result.Complete | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $s11.Root 'TeknoS11\state\gameA\cabinet-1\at28c16.bin')) | Should -Be 'flash A'
        [System.IO.File]::ReadAllText((Join-Path $s11.Root 'TeknoS11\state\gameA\cabinet-1\gnet-flash.bin')) | Should -Be 'flash A2'
        [System.IO.File]::ReadAllText((Join-Path $existing 'at28c16.bin')) | Should -Be 'MY OWN SAVE'
        (Test-Path -LiteralPath (Join-Path $s11.Root 'TeknoS11\state\notmine')) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $s11.Root 'TeknoS11\state\gameC')) | Should -BeFalse
    }

    It 'never replaces a file that is already there, even when the set has a different one' {
        $folder = Join-Path $s11.Root 'TeknoS11\state\gameA\cabinet-1'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $folder 'at28c16.bin'), 'MY OWN SAVE')
        $plan = Get-TpmS11PreinstallPlan -SourcePath $s11Set -TeknoParrotRoot $s11.Root -GameCodes @('gameA')
        $result = Invoke-TpmS11PreinstallInstall -Plan $plan -TpRoot $s11.Root
        $result.Outcome | Should -Be 'SUCCEEDED'
        @($result.Installed) | Should -Be @('gameA\gnet-flash.bin')
        [System.IO.File]::ReadAllText((Join-Path $folder 'at28c16.bin')) | Should -Be 'MY OWN SAVE'
    }

    It 'changes nothing when every file is already there' {
        $first = Get-TpmS11PreinstallPlan -SourcePath $s11Set -TeknoParrotRoot $s11.Root -GameCodes @('gameA', 'gameB')
        [void](Invoke-TpmS11PreinstallInstall -Plan $first -TpRoot $s11.Root)
        $again = Get-TpmS11PreinstallPlan -SourcePath $s11Set -TeknoParrotRoot $s11.Root -GameCodes @('gameA', 'gameB')
        @($again.NewGames).Count | Should -Be 0
        (Invoke-TpmS11PreinstallInstall -Plan $again -TpRoot $s11.Root).Outcome | Should -Be 'NO_OP'
    }

    It 'works from an extracted folder too, and leaves no staging folder behind' {
        $extracted = Join-Path $s11.Root 'extracted'
        New-Item -ItemType Directory -Path (Join-Path $extracted 'TeknoS11\state\gameB\cabinet-1') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $extracted 'TeknoS11\state\gameB\cabinet-1\at28c16.bin'), 'flash B')
        $plan = Get-TpmS11PreinstallPlan -SourcePath $extracted -TeknoParrotRoot $s11.Root -GameCodes @('gameB')
        (Invoke-TpmS11PreinstallInstall -Plan $plan -TpRoot $s11.Root).Outcome | Should -Be 'SUCCEEDED'
        [System.IO.File]::ReadAllText((Join-Path $s11.Root 'TeknoS11\state\gameB\cabinet-1\at28c16.bin')) | Should -Be 'flash B'
        (Test-Path -LiteralPath (Join-Path $s11.Root 'TeknoParrotManager\Temp\s11-stage')) | Should -BeFalse
    }

    It 'ignores a member whose name could escape the folder' {
        $evil = Join-Path $s11.Root 'evil.zip'
        New-F387GZip -Path $evil -Entries @{ 'TeknoS11/state/gameA/cabinet-1/../../../../escaped.bin' = 'bad'; 'TeknoS11/state/gameA/cabinet-1/ok.bin' = 'ok' }
        $plan = Get-TpmS11PreinstallPlan -SourcePath $evil -TeknoParrotRoot $s11.Root -GameCodes @('gameA')
        @($plan.Items | ForEach-Object { $_.Name }) | Should -Be @('ok.bin')
        [void](Invoke-TpmS11PreinstallInstall -Plan $plan -TpRoot $s11.Root)
        (Test-Path -LiteralPath (Join-Path $s11.Root 'escaped.bin')) | Should -BeFalse
    }

    It 'refuses a location that is not a ZIP or a state folder, and changes nothing' {
        $plan = Get-TpmS11PreinstallPlan -SourcePath $s11.Root -TeknoParrotRoot $s11.Root -GameCodes @('gameA')
        $plan.Valid | Should -BeFalse
        $plan.Error | Should -Match 'no state folder'
        (Invoke-TpmS11PreinstallInstall -Plan $plan -TpRoot $s11.Root).Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        (Test-Path -LiteralPath (Join-Path $s11.Root 'TeknoS11\state')) | Should -BeFalse
    }

    It 'puts a note in the Library health check for System 11 games that have no saved files, not for games that have them' {
        $folder = Join-Path $s11.Root 'TeknoS11\state\gameA\cabinet-1'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $folder 'at28c16.bin'), 'x')
        $report = Get-F387GReport -Fixture $s11
        @($report.S11NoSavedFiles) | Should -Be @('gameB', 'gameC')
        $row = @(Get-TpmGameTypeRows -Report $report | Where-Object { $_.Area -eq 'System 11' })[0]
        $row.Text | Should -Match '^Note - 2 of 3 System 11 games have no saved setup files yet'
        $row.Text | Should -Not -Match 'Needs attention'
    }
}

Describe 'System 11 saved files offer (issue 387)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
        Mock Invoke-TpmProgressGroup { & $Action }
        $script:offerAsked = New-Object System.Collections.Generic.List[string]
        Mock Read-TpmYesNo { [void]$script:offerAsked.Add([string]$Prompt); 'Y' }
        $script:s11o = New-F387GRoot
        New-Item -ItemType Directory -Path (Join-Path $s11o.Root 'TeknoS11') -Force | Out-Null
        Add-F387GProfile -Fixture $s11o -Code 'gameA' -Type 'TeknoS11' -Exe 'gameA.zip'
        $script:s11oCollection = Join-Path $s11o.Root 'collection'
        New-Item -ItemType Directory -Path $s11oCollection -Force | Out-Null
        New-F387GZip -Path (Join-Path $s11oCollection '[NVRAM] TeknoS11 preinstalled game files for System 11.zip') -Entries @{ 'TeknoS11/state/gameA/cabinet-1/at28c16.bin' = 'flash A' }
    }

    It 'finds the set in the collection folder, asks once, and copies the files' {
        $result = Invoke-TpmS11PreinstallOffer -TpRoot $s11o.Root -UserProfilesDir $s11o.Profiles -SearchFolders @($s11oCollection)
        $result.Outcome | Should -Be 'SUCCEEDED'
        @($offerAsked).Count | Should -Be 1
        [System.IO.File]::ReadAllText((Join-Path $s11o.Root 'TeknoS11\state\gameA\cabinet-1\at28c16.bin')) | Should -Be 'flash A'
    }

    It 'changes nothing when the player says no' {
        Mock Read-TpmYesNo { 'N' }
        $result = Invoke-TpmS11PreinstallOffer -TpRoot $s11o.Root -UserProfilesDir $s11o.Profiles -SearchFolders @($s11oCollection)
        $result | Should -BeNullOrEmpty
        (Test-Path -LiteralPath (Join-Path $s11o.Root 'TeknoS11\state')) | Should -BeFalse
    }

    It 'does not ask when every System 11 game already has saved files' {
        $folder = Join-Path $s11o.Root 'TeknoS11\state\gameA\cabinet-1'
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $folder 'at28c16.bin'), 'MY OWN SAVE')
        $result = Invoke-TpmS11PreinstallOffer -TpRoot $s11o.Root -UserProfilesDir $s11o.Profiles -SearchFolders @($s11oCollection)
        $result | Should -BeNullOrEmpty
        @($offerAsked).Count | Should -Be 0
        [System.IO.File]::ReadAllText((Join-Path $folder 'at28c16.bin')) | Should -Be 'MY OWN SAVE'
    }

    It 'says plainly when the player has no set, and changes nothing' {
        Mock Read-TpmYesNo { 'N' }
        $result = Invoke-TpmS11PreinstallOffer -TpRoot $s11o.Root -UserProfilesDir $s11o.Profiles -SearchFolders @((Join-Path $s11o.Root 'empty'))
        $result | Should -BeNullOrEmpty
        (Test-Path -LiteralPath (Join-Path $s11o.Root 'TeknoS11\state')) | Should -BeFalse
    }
}

Describe 'The game type table is well formed (issue 387)' {
    It 'names a plain folder for every type that has one, and holds the types of the real install' {
        # Mutation: an absolute or doubled folder in a row would make every game of that type read as "emulator missing".
        foreach ($type in $script:EmulatorBiosRequirements.Keys) {
            $entry = $script:EmulatorBiosRequirements[$type]
            foreach ($folder in @(if ($entry.Contains('EmulatorFolders')) { $entry['EmulatorFolders'] })) { [string]$folder | Should -Match '^[A-Za-z0-9_]+$' -Because $type }
        }
        foreach ($type in @('Dolphin', 'TeknoMacaw', 'TeknoTJC', 'TeknoTPJC', 'TeknoS11', 'TeknoRender0', 'RPCS3', 'Pcsx2x6', 'cxbxr', 'Play')) {
            $script:EmulatorBiosRequirements.ContainsKey($type) | Should -BeTrue -Because $type
        }
        $script:EmulatorBiosRequirements['Dolphin']['EmulatorFolders'] | Should -Be @('CrediarDolphin')
        $script:EmulatorBiosRequirements['TeknoMacaw']['EmulatorFolders'] | Should -Be @('TeknoParrot')
    }
}

Describe 'The profile index for games that name two files (issue 387)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
    }

    It 'indexes a set of ZIPs by its first ZIP only, and a list of alternatives by every name' {
        # Mutation: index every name -> the parent ZIP of a set would register the child game on its own.
        $fixture = New-F387GRoot
        Add-F387GProfile -Fixture $fixture -Code 'ddr2ml' -Type 'TeknoS11' -Exe 'ddr2ml.zip;ddr2m.zip'
        Add-F387GProfile -Fixture $fixture -Code 'apache' -Type 'ElfLdr2' -Exe 'apacheM_HD.elf;apacheM.elf'
        $index = Build-ProfileIndex -gameProfilesDir $fixture.Profiles
        $index.ContainsKey('ddr2ml.zip') | Should -BeTrue
        $index.ContainsKey('ddr2m.zip') | Should -BeFalse
        $index.ContainsKey('apachem_hd.elf') | Should -BeTrue
        $index.ContainsKey('apachem.elf') | Should -BeTrue
    }
}

Describe 'System 11 saved files offer: what the player reads (issue 387)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        $script:offerText = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText { [void]$script:offerText.Add([string]$Text) }
        Mock Invoke-TpmProgressGroup { & $Action }
        $script:offerAsked2 = New-Object System.Collections.Generic.List[string]
        Mock Read-TpmYesNo { [void]$script:offerAsked2.Add([string]$Prompt); 'Y' }
        $script:s11p = New-F387GRoot
        New-Item -ItemType Directory -Path (Join-Path $s11p.Root 'TeknoS11') -Force | Out-Null
        Add-F387GProfile -Fixture $s11p -Code 'gameA' -Type 'TeknoS11' -Exe 'gameA.zip'
        Add-F387GProfile -Fixture $s11p -Code 'gameZ' -Type 'TeknoS11' -Exe 'gameZ.zip'
        $script:s11pCollection = Join-Path $s11p.Root 'collection'
        New-Item -ItemType Directory -Path $s11pCollection -Force | Out-Null
        New-F387GZip -Path (Join-Path $s11pCollection '[NVRAM] TeknoS11 preinstalled game files for System 11.zip') -Entries @{ 'TeknoS11/state/gameA/cabinet-1/at28c16.bin' = 'flash A' }
    }

    It 'says in one correct sentence which game the set has no files for' {
        [void](Invoke-TpmS11PreinstallOffer -TpRoot $s11p.Root -UserProfilesDir $s11p.Profiles -SearchFolders @($s11pCollection))
        @($offerText) | Should -Contain 'Your set has no saved files for gameZ. That game starts without them.'
    }

    It 'does not ask again once the set in the collection has nothing more for the games that still have none' {
        [void](Invoke-TpmS11PreinstallOffer -TpRoot $s11p.Root -UserProfilesDir $s11p.Profiles -SearchFolders @($s11pCollection))
        $offerAsked2.Clear()
        $again = Invoke-TpmS11PreinstallOffer -TpRoot $s11p.Root -UserProfilesDir $s11p.Profiles -SearchFolders @($s11pCollection)
        $again | Should -BeNullOrEmpty
        @($offerAsked2).Count | Should -Be 0
    }
}

Describe 'Registering a game that names two ZIPs (issue 387)' {
    BeforeEach {
        Mock Write-Log { }
        Mock Write-Host { }
        Mock Write-TpmText { }
        Mock Save-XmlMaybe { }
        Mock Test-TpmRegistrationLedgerConfigured { $false }
        Mock Test-TpmRegistrationLedgerStopped { $false }
        Mock Start-TpmRegistrationMapping { $null }
        Mock Complete-TpmRegistrationMapping { }
        Mock Add-TpmRegistrationMappingFailure { }
        $script:FuzzyAutoThreshold = 0.72
        $script:FuzzyTieMargin = 0.1
    }

    BeforeAll {
    # One folder named like the game with the child ZIP, and the parent ZIP only when asked for. The template names both ZIPs.
    function Invoke-F387GRegistration {
        param([bool]$WithParent)
        $root = Join-Path $TestDrive ('f387reg-' + [guid]::NewGuid().ToString('N'))
        $games = Join-Path $root 'Games'; $userProfiles = Join-Path $root 'UserProfiles'; $gameProfiles = Join-Path $root 'GameProfiles'
        New-Item -ItemType Directory -Path (Join-Path $games 'ddr2ml'), $userProfiles, $gameProfiles, (Join-Path $root 'TeknoParrot') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $games 'ddr2ml\ddr2ml.zip'), 'x')
        if ($WithParent) { [System.IO.File]::WriteAllText((Join-Path $games 'ddr2ml\ddr2m.zip'), 'x') }
        $template = Join-Path $gameProfiles 'ddr2ml.xml'
        [System.IO.File]::WriteAllText($template, '<GameProfile><GamePath></GamePath><EmulatorType>TeknoS11</EmulatorType><ExecutableName>ddr2ml.zip;ddr2m.zip</ExecutableName></GameProfile>')
        $profileIndex = Build-ProfileIndex -gameProfilesDir $gameProfiles
        $output = @(Register-GamesLegacy -userProfilesDir $userProfiles -installFolder $games -profileIndex $profileIndex `
            -gameProfilesDir $gameProfiles -datIndex @{} -profileSet $null -tpRootDir (Join-Path $root 'TeknoParrot') -subFolderMap @{} -DryRun $true)
        return $output[0]
    }
    }

    It 'does not register the game while the parent ZIP is missing' {
        # Mutation: remove the partner check from the match loop and from the two folder-name passes -> the child alone registers.
        $result = Invoke-F387GRegistration -WithParent $false
        @($result.Registered | ForEach-Object { $_.Code }) | Should -Not -Contain 'ddr2ml'
    }

    It 'registers the game when both ZIPs are in its folder' {
        $result = Invoke-F387GRegistration -WithParent $true
        @($result.Registered | ForEach-Object { $_.Code }) | Should -Contain 'ddr2ml'
    }
}

Describe 'A set is never registered by its parent ZIP (issue 387)' {
    It 'reports the game ZIP as missing when the file given is the parent ZIP' {
        # Mutation: drop the leaf check -> the parent ZIP alone passes and becomes the game path.
        $folder = Join-Path $TestDrive ('parent-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        $parent = Join-Path $folder 'ddr2m.zip'
        [System.IO.File]::WriteAllText($parent, 'x')
        @(Get-TpmMissingGameSetFiles -GamePath $parent -ExecutableName 'ddr2ml.zip;ddr2m.zip') | Should -Be @('ddr2ml.zip')
    }
}
