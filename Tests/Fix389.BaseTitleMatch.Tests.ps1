#Requires -Module Pester

# Issue #389 coverage. Game folder names often carry notes in parentheses after the
# title, for example "Raiden IV (1.03J)(Landscape,Bezel)(2012-12-27)(JPN)". The notes
# lowered the name similarity score, so the right profile was not picked. The title
# before the first note is now scored too. These tests use names from the real
# game list and prove that the better score is used, that look-alike titles still
# stay apart, and that a title-only match which ties with another profile is not guessed.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $script:Fix389Source = Get-Content -LiteralPath $sourcePath -Raw
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')" }

    $wanted = @('Get-NormalizedGameKey', 'Get-DiceSimilarity', 'Get-TpmBaseTitleKey', 'Resolve-BestFuzzyMatch', 'Get-TpmTeknoParrotNamesForCodes', 'Get-TpmTeknoParrotGameName', 'Get-TpmTeknoParrotMetadataFacts')
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $wanted }, $true))
    if (@($functions | ForEach-Object { $_.Name } | Sort-Object -Unique).Count -ne $wanted.Count) {
        throw ("Expected one definition of each of: {0}" -f ($wanted -join ', '))
    }
    $functionPath = Join-Path $TestDrive ('fix389-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1

    function Invoke-Fix389Match {
        param([string]$Folder, [string[]]$Codes)
        $matchList = @($Codes | ForEach-Object { [pscustomobject]@{ Code = $_ } })
        $norm = Get-NormalizedGameKey $Folder
        return Resolve-BestFuzzyMatch -NormFolder $norm -MatchList $matchList -RawThrillsAliases @{} -NormBaseTitle (Get-TpmBaseTitleKey $Folder)
    }
}

Describe 'Get-TpmBaseTitleKey' {
    It 'drops everything from the first parenthesis' {
        (Get-TpmBaseTitleKey 'Raiden IV (1.03J)(Landscape,Bezel)(2012-12-27)(JPN)') | Should -Be (Get-NormalizedGameKey 'Raiden IV')
    }
    It 'drops everything from the first square bracket' {
        (Get-TpmBaseTitleKey 'Raiden IV [Taito NESiCAxLive]') | Should -Be (Get-NormalizedGameKey 'Raiden IV')
    }
    It 'returns the normal key when there are no notes' {
        (Get-TpmBaseTitleKey 'Space Invaders') | Should -Be (Get-NormalizedGameKey 'Space Invaders')
    }
    It 'returns an empty string for empty, blank or null input' {
        Get-TpmBaseTitleKey '' | Should -Be ''
        Get-TpmBaseTitleKey '   ' | Should -Be ''
        Get-TpmBaseTitleKey $null | Should -Be ''
    }
    It 'returns an empty string when the name starts with a note' {
        Get-TpmBaseTitleKey '(JPN) Something' | Should -Be ''
    }
}

Describe 'Resolve-BestFuzzyMatch with a base title' {
    It 'matches a title whose notes would otherwise lower the score' {
        $r = Invoke-Fix389Match -Folder 'GigaWing Generations (Landscape,Bezel)(2.02J)(2004-09-22)' -Codes @('GigaWingGenerations', 'GigaWing2', 'Aleste')
        $r.IsConfidentMatch | Should -BeTrue
        $r.Best.Code | Should -Be 'GigaWingGenerations'
    }
    It 'keeps Raiden III and Raiden IV apart' {
        $codes = @('RaidenIII', 'RaidenIV', 'RaidenIVNesica')
        (Invoke-Fix389Match -Folder 'Raiden III (1.02)(Landscape)(2013-01-10)' -Codes $codes).Best.Code | Should -Be 'RaidenIII'
        (Invoke-Fix389Match -Folder 'Raiden IV (1.03J)(Landscape,Bezel)(2012-12-27)' -Codes $codes).Best.Code | Should -Be 'RaidenIV'
    }
    It 'keeps Space Invaders and Space Invaders Frenzy apart' {
        $codes = @('SpaceInvaders', 'SpaceInvadersFrenzy')
        (Invoke-Fix389Match -Folder 'Space Invaders (1.05)(Reshade+Bezel)' -Codes $codes).Best.Code | Should -Be 'SpaceInvaders'
        (Invoke-Fix389Match -Folder 'Space Invaders Frenzy (1.21)(2017-08-14)' -Codes $codes).Best.Code | Should -Be 'SpaceInvadersFrenzy'
    }
    It 'does not match an unrelated game' {
        $r = Invoke-Fix389Match -Folder 'Dead or Alive 6 (1.00.00)(2019-06-26)' -Codes @('MetalGearArcade', 'Aleste', 'Pengo5')
        $r.IsConfidentMatch | Should -BeFalse
    }
    It 'never scores lower than before when no base title is given' {
        $matchList = @([pscustomobject]@{ Code = 'RaidenIV' })
        $norm = Get-NormalizedGameKey 'Raiden IV (1.03J)(Landscape,Bezel)'
        $without = Resolve-BestFuzzyMatch -NormFolder $norm -MatchList $matchList -RawThrillsAliases @{}
        $with = Resolve-BestFuzzyMatch -NormFolder $norm -MatchList $matchList -RawThrillsAliases @{} -NormBaseTitle (Get-TpmBaseTitleKey 'Raiden IV (1.03J)(Landscape,Bezel)')
        $with.BestScore | Should -BeGreaterOrEqual $without.BestScore
    }
    It 'reports a tie when two profiles score the same, so the match is not confident' {
        $r = Invoke-Fix389Match -Folder 'Blade Strangers (APM3)(2.01.00)' -Codes @('BladeStrangers', 'BladeStrangersAPM3')
        $r.IsConfidentMatch | Should -BeFalse
    }
}

Describe 'Registration pass 3 uses the base title safely' {
    It 'scores the base title and holds title-only matches that tie' {
        $script:Fix389Source | Should -Match 'Get-TpmBaseTitleKey \$folderKey'
        $script:Fix389Source | Should -Match '\$bestViaBaseTitle -and \(\(\$bestScore - \$secondScore\) -lt \$FuzzyTieMargin\)'
    }
}

# Golden Tee Live 2021 to 2026 and PGA Tour have no entry in the Eggman DAT, and every year of the game uses the same game.bin, so the folder
# name is the only way to tell the years apart. Two consecutive years score within the tie margin, which used to stop every year from registering.
Describe 'Resolve-BestFuzzyMatch with consecutive years of one game' {
    BeforeAll {
        function Write-Log { param($msg) }
        $script:F389Years = @('GoldenTeeLive2019', 'GoldenTeeLive2020', 'GoldenTeeLive2021', 'GoldenTeeLive2022', 'GoldenTeeLive2023', 'GoldenTeePGATour2021', 'GoldenTeePGATour2022')
    }
    It 'registers the year the folder names, <Folder>' -ForEach @(
        @{ Folder = 'Golden Tee Live 2021 (16.04.15)(USA)[IT Nighthawk][TP]'; Code = 'GoldenTeeLive2021' }
        @{ Folder = 'Golden Tee Live 2020 (15.04.08)(2020-06-15)(USA)[IT Nighthawk][TP]'; Code = 'GoldenTeeLive2020' }
        @{ Folder = 'Golden Tee PGA Tour 2022 (51.05.19)(USA)[IT Nighthawk][TP]'; Code = 'GoldenTeePGATour2022' }
    ) {
        $r = Invoke-Fix389Match -Folder $Folder -Codes $script:F389Years
        $r.IsConfidentMatch | Should -BeTrue
        $r.Best.Code | Should -BeExactly $Code
    }
    It 'does not guess a year when the folder name does not say one' {
        (Invoke-Fix389Match -Folder 'Golden Tee Live (USA)[IT Nighthawk][TP]' -Codes $script:F389Years).IsConfidentMatch | Should -BeFalse
    }
    It 'still treats two profiles with the same whole name as a tie, whichever is listed first' -ForEach @(
        @{ Codes = @('BladeStrangers', 'BladeStrangersAPM3') }
        @{ Codes = @('BladeStrangersAPM3', 'BladeStrangers') }
    ) {
        (Invoke-Fix389Match -Folder 'Blade Strangers (APM3)(2.01.00)' -Codes $Codes).IsConfidentMatch | Should -BeFalse
    }
    It 'uses TeknoParrot''s own game name when the profile code has no 2024 in it' {
        $root = Join-Path $TestDrive ('tp-' + [guid]::NewGuid().ToString('N'))
        $gameProfiles = Join-Path $root 'GameProfiles'
        New-Item -ItemType Directory -Path $gameProfiles, (Join-Path $root 'Metadata') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $root 'Metadata\GoldenTeeLive2023.json'), '{ "game_name": "Golden Tee Live 2023-2024", "release_year": "2023" }')
        $folder = 'Golden Tee Live 2023-2024 (18.04.15)(USA)[IT Nighthawk][TP]'
        $codes = @('GoldenTeeLive2020', 'GoldenTeeLive2021', 'GoldenTeeLive2022', 'GoldenTeeLive2023')
        (Invoke-Fix389Match -Folder $folder -Codes $codes).IsConfidentMatch | Should -BeFalse
        $names = Get-TpmTeknoParrotNamesForCodes -GameProfilesDir $gameProfiles -Codes $codes
        $names.Keys.Count | Should -Be 1
        $matchList = @($codes | ForEach-Object { [pscustomobject]@{ Code = $_ } })
        $r = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey $folder) -MatchList $matchList -RawThrillsAliases @{} -NormBaseTitle (Get-TpmBaseTitleKey $folder) -AlternateNames $names
        $r.IsConfidentMatch | Should -BeTrue
        $r.Best.Code | Should -BeExactly 'GoldenTeeLive2023'
    }
}
