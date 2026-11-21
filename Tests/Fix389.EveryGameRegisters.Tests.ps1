#Requires -Module Pester

# Issues 389 and 351 (every game TeknoParrot supports must register): real-game cases.
# testdata\real-game-registration-fixture.json holds facts only (profile codes, game file names, game names) reduced from the real TeknoParrot
# profile set (build 2325) and the real Eggman collection list (2026-11-20). The test builds fake game folders from it in TestDrive and runs
# the real registration (Register-GamesLegacy, real profile writes into a temp UserProfiles folder) once, then checks what a player sees.
# Each group below is a failure that the full real-data run found before the fix:
#   - a second version of a game was dropped without a word because the first version had just been registered in the same run;
#   - a game whose name looks like another game's (The King of Fighters XII and XIV, Total Vice AAB and EBA) got the wrong profile;
#   - games whose profile names a child and a parent ZIP ("ddr2ml.zip;ddr2m.zip") were skipped although the list names the parent ZIP;
#   - the second profile the list names (ElfLdr2 for a Lindbergh game, the other profile of Raiden IV) was never registered;
#   - a profile code with a hyphen (R-Tuned) was refused as unsafe;
#   - a game file that ends in .exec or .chd was not seen as a game file;
#   - a game TeknoParrot has no profile for was shown as a failed profile code instead of "not in TeknoParrot".
# What this CANNOT prove: that a game starts, or how the real console paints the result.

BeforeAll {
    $sourcePath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')" }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionPath = Join-Path $TestDrive 'fix389-functions.ps1'
    [System.IO.File]::WriteAllText($functionPath, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionPath

    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:RawThrillsPathLimits = @{}
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'), [System.StringComparer]::OrdinalIgnoreCase)
    $script:fix389Log = New-Object System.Collections.Generic.List[string]
    function Write-Log { param([string]$msg) [void]$script:fix389Log.Add($msg) }
    function Write-Host { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Test-TpmRegistrationLedgerConfigured { return $false }
    function Test-TpmRegistrationLedgerStopped { return $false }
    function Start-TpmRegistrationMapping { param([Parameter(ValueFromRemainingArguments)]$Ignored) return $null }
    function Complete-TpmRegistrationMapping { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Add-TpmRegistrationMappingFailure { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Get-TpmRegisteredProfileFilesWithDiscoveryProgress {
        param([string]$UserProfilesDir, [string]$ProgressLabel, [string]$EnumerationErrorAction)
        return @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    }

    $fixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\testdata\real-game-registration-fixture.json') -Raw | ConvertFrom-Json
    $root = Join-Path $TestDrive 'fix389'
    $gameProfiles = Join-Path $root 'GameProfiles'; $userProfiles = Join-Path $root 'UserProfiles'
    $games = Join-Path $root 'Games'; $tpRoot = Join-Path $root 'TeknoParrot'
    New-Item -ItemType Directory -Path $gameProfiles, $userProfiles, $games, $tpRoot -Force | Out-Null
    $profileSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($profile in $fixture.Profiles) {
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><GamePath></GamePath><EmulatorType>{0}</EmulatorType><ExecutableName>{1}</ExecutableName>' -f $profile.EmulatorType, $profile.ExecutableName
        if ($profile.PSObject.Properties['ExecutableName2']) { $xml += '<ExecutableName2>{0}</ExecutableName2>' -f $profile.ExecutableName2 }
        if ($profile.PSObject.Properties['IsDeprecated']) { $xml += '<IsDeprecated>true</IsDeprecated>' }
        [System.IO.File]::WriteAllText((Join-Path $gameProfiles ($profile.Code + '.xml')), $xml + '</GameProfile>')
        [void]$profileSet.Add($profile.Code)
    }
    $dat = New-Object System.Text.StringBuilder
    [void]$dat.AppendLine('<?xml version="1.0"?><datafile><header><name>fixture</name><TPUISchemaVersion>1</TPUISchemaVersion></header>')
    foreach ($game in $fixture.Games) {
        $escape = { param($t) [System.Security.SecurityElement]::Escape([string]$t) }
        [void]$dat.AppendLine(('<game name="{0}"><description></description><GameProfile>{1}</GameProfile><GameProfile2>{2}</GameProfile2><Executable>{3}</Executable><Executable2></Executable2><TestMenuExecutable></TestMenuExecutable><rom name="x" size="1" crc="00000000"/></game>' -f (& $escape $game.Name), $game.GameProfile, $game.GameProfile2, (& $escape $game.Executable)))
        foreach ($file in $game.Files) {
            $path = Join-Path (Join-Path $games $game.Name) ($file -replace '/', '\')
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
            if (-not (Test-Path -LiteralPath $path)) { [System.IO.File]::WriteAllText($path, 'x') }
        }
    }
    [void]$dat.AppendLine('</datafile>')
    $datPath = Join-Path $root 'collection.dat'
    [System.IO.File]::WriteAllText($datPath, $dat.ToString(), (New-Object System.Text.UTF8Encoding $false))

    $profileIndex = Build-ProfileIndex $gameProfiles
    $datIndex = Build-DatIndex $datPath -Quiet
    $script:fix389Result = Register-GamesLegacy -userProfilesDir $userProfiles -installFolder $games -profileIndex $profileIndex -gameProfilesDir $gameProfiles `
        -datIndex $datIndex -profileSet $profileSet -DryRun $false -tpRootDir $tpRoot -subFolderMap @{} -BackupState @{ Backup = $null; Done = $true; Error = $null }
    $script:fix389Games = $games
    $script:fix389Fixture = $fixture

    function Get-F389Codes {
        param([string]$NameStart)
        $folder = @($script:fix389Fixture.Games | Where-Object { $_.Name.StartsWith($NameStart) })[0].Name
        return @($script:fix389Result.Registered | Where-Object { ([string]$_.GamePath).StartsWith((Join-Path $script:fix389Games $folder) + '\') } | ForEach-Object { [string]$_.Code })
    }
}

Describe 'Every game of the real profile and game lists registers (issues 389 and 351)' {
    It 'registers every version of a game that shares one file name, not just the first (nothing vanishes without a word)' {
        (Get-F389Codes 'Chaos Code (2011)') | Should -Contain 'CC'
        (Get-F389Codes 'Chaos Code - New Sign of Catastrophe (1.03.00)') | Should -Contain 'ChaosCodeNSOC103'
        (Get-F389Codes 'Chaos Code - New Sign of Catastrophe (2.11.00)') | Should -Contain 'ChaosCodeNSOC211'
        (Get-F389Codes 'Chaos Breaker (2011)') | Should -Contain 'ChaosBreakerNesica'
    }

    It 'gives a game the profile the list names, not the profile with the most alike name' {
        (Get-F389Codes 'The King of Fighters XII ') | Should -Contain 'KingofFightersXII'
        (Get-F389Codes 'The King of Fighters XIV') | Should -Contain 'KingOfFightersXIV'
        (Get-F389Codes 'Total Vice (AAB)') | Should -Contain 'totlvica'
        (Get-F389Codes 'Total Vice (EBA)') | Should -Contain 'totlvice'
    }

    It 'registers a game whose profile lists a child ZIP and a parent ZIP when the list names the parent ZIP' {
        foreach ($case in @(
            @{ Start = 'Dance Dance Revolution 2nd Mix - Link'; Code = 'ddr2ml'; File = 'ddr2m.zip' },
            @{ Start = 'DrumMania (GQ881'; Code = 'drmn'; File = 'pcnfrk.zip' },
            @{ Start = 'Soul Calibur (USA)'; Code = 'soulclbruc'; File = 'soulclbr.zip' },
            @{ Start = 'Virtua Fighter 3 Team Battle'; Code = 'vf3tb_m3'; File = 'vf3.zip' })) {
            (Get-F389Codes $case.Start) | Should -Contain $case.Code
            @($script:fix389Result.Registered | Where-Object { $_.Code -eq $case.Code })[0].GamePath | Should -BeLike ('*\' + $case.File)
        }
    }

    It 'registers the second profile the list names (ElfLdr2 next to a Lindbergh game, the other profile of Raiden IV) for the same folder' {
        (Get-F389Codes 'After Burner Climax') | Should -Contain 'abc'
        (Get-F389Codes 'After Burner Climax') | Should -Contain 'abcELF2'
        (Get-F389Codes '2SPICY') | Should -Contain '2SpicyElf2'
        (Get-F389Codes 'Virtua Fighter 5') | Should -Contain 'VF5BElf2'
        (Get-F389Codes 'Raiden IV') | Should -Contain 'RaidenIVNesica'
        (Get-F389Codes 'Rambo') | Should -Contain 'RamboElf2'
    }

    It 'does not guess a file for the second profile when none of the files it names is in the folder, and reports no failure' {
        (Get-F389Codes 'The House of the Dead 4') | Should -Contain 'HOTD4'
        (Get-F389Codes 'The House of the Dead 4') | Should -Not -Contain 'HOTD4ELF2'
        @($script:fix389Result.MutationRecords.Failures).Count | Should -Be 0
        ($script:fix389Log -join "`n") | Should -Match 'HOTD4ELF2 was left alone because none of its game files is in folder'
    }

    It 'accepts a profile code with a hyphen (R-Tuned)' {
        (Get-F389Codes 'R-Tuned') | Should -Contain 'R-Tuned'
        (Get-F389Codes 'R-Tuned') | Should -Contain 'R-TunedElf2'
    }

    It 'sees a game whose file ends in .exec or .chd as a game file' {
        (Get-F389Codes 'Minecraft Dungeons Arcade') | Should -Contain 'Minecraft'
        (Get-F389Codes 'Space Invaders Frenzy') | Should -Contain 'SpaceInvadersFrenzy'
        (Get-F389Codes 'Golden Tee Fore! 2004') | Should -Contain 'teknoeagle_gtfore04'
    }

    It 'registers one version of a game that has one TeknoParrot profile and reports the other as a duplicate' {
        $avalon = @($script:fix389Result.Registered | Where-Object { $_.Code -eq 'KeyOfAvalon' })
        $avalon.Count | Should -Be 1
        @($script:fix389Result.Ambiguous | Where-Object { $_.Codes -eq 'KeyOfAvalon' -and $_.Reason -eq 'duplicate' }).Count | Should -Be 1
    }

    It 'lists a game TeknoParrot has no profile for as not in TeknoParrot, not as a failed profile' {
        @($script:fix389Result.Unmatched | Where-Object { $_ -like 'SEGA Rally 3*' -or $_ -like 'Escape from Monster Manor*' }).Count | Should -Be 2
        @($script:fix389Result.MutationRecords.Failures | Where-Object { $_.Code -in @('SR3_3B', 'EFMM') }).Count | Should -Be 0
    }

    It 'accounts for every game folder: registered, reported as a duplicate, or listed as not in TeknoParrot' {
        $silent = New-Object System.Collections.Generic.List[string]
        foreach ($game in $script:fix389Fixture.Games) {
            $folder = Join-Path $script:fix389Games $game.Name
            $registered = @($script:fix389Result.Registered | Where-Object { ([string]$_.GamePath).StartsWith($folder + '\') }).Count -gt 0
            $reported = @($script:fix389Result.Ambiguous | Where-Object { ([string]$_.Exe).StartsWith($folder + '\') -or [string]$_.Exe -eq $folder }).Count -gt 0
            $listed = $script:fix389Result.Unmatched -contains $game.Name
            if (-not ($registered -or $reported -or $listed)) { [void]$silent.Add($game.Name) }
        }
        ($silent -join '; ') | Should -BeExactly ''
    }
}

Describe 'The graphics card warning also reads TeknoParrot''s own game metadata (issue 389)' {
    It 'names the games TeknoParrot marks "NO" for the card maker, and nothing for another maker or a missing file' {
        $tp = Join-Path $TestDrive 'gpu-tp'
        New-Item -ItemType Directory -Path $tp -Force | Out-Null
        # Values copied from the real Metadata.catalog.json: GoldenTeeLive2021 is amd WITH_FIX and intel NO, GoldenTeeLive2011 is NO for both, 1on1gov has no card facts.
        $catalog = '{"GoldenTeeLive2021":{"game_name":"Golden Tee Live 2021","amd":"WITH_FIX","intel":"NO"},"GoldenTeeLive2011":{"game_name":"Golden Tee Live 2011","amd":"NO","intel":"NO"},"abcELF2":{"amd":"OK","intel":"NO"},"1on1gov":{"game_name":"1 on 1 Government (Japan)"}}'
        [System.IO.File]::WriteAllText((Join-Path $tp 'Metadata.catalog.json'), $catalog)
        (@(Get-TpmMetadataGpuIncompatibleCodes -TeknoParrotRoot $tp -Vendor 'Intel') | Sort-Object) -join ',' | Should -BeExactly 'abcELF2,GoldenTeeLive2011,GoldenTeeLive2021'
        (@(Get-TpmMetadataGpuIncompatibleCodes -TeknoParrotRoot $tp -Vendor 'AMD') | Sort-Object) -join ',' | Should -BeExactly 'GoldenTeeLive2011'
        @(Get-TpmMetadataGpuIncompatibleCodes -TeknoParrotRoot $tp -Vendor 'NVIDIA').Count | Should -Be 0
        @(Get-TpmMetadataGpuIncompatibleCodes -TeknoParrotRoot (Join-Path $TestDrive 'no-such-folder') -Vendor 'Intel').Count | Should -Be 0
    }
}
