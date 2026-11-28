#Requires -Module Pester

# Issues 507, 510, 511: games that cannot be pointed at their files are never guessed (a different edition or version is not the same game),
# are named with their exact version, and are listed once with a choice for each (Fix, Remove, Skip, Ignore, Details).
# Real folders under $TestDrive; a drive letter that does not exist on this PC stands for the old drive.
# What this CANNOT prove: a run against the tester's real library.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'RC95U1 bootstrap could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'rc95u1-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    function Write-Log { param([string]$msg) }

    $script:r95Old = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'P', 'O', 'N', 'M' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) }) | Select-Object -First 1
    if (-not $script:r95Old) { throw 'RC95U1 needs one unused drive letter.' }

    function New-R95Game {
        param([string]$Code, [string]$OldRelative, [string]$NewRelative, [string]$ExeName = '')
        $oldPath = $script:r95Old + ':\Arcade Games\' + $OldRelative
        $exeNode = if ($ExeName) { '<ExecutableName>' + $ExeName + '</ExecutableName>' } else { '' }
        [System.IO.File]::WriteAllText((Join-Path $script:r95Profiles ($Code + '.xml')), ('<GameProfile><GamePath>{0}</GamePath>{1}</GameProfile>' -f $oldPath, $exeNode))
        if ($NewRelative) {
            $newPath = Join-Path $script:r95Games $NewRelative
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($newPath))
            [System.IO.File]::WriteAllText($newPath, 'game')
        }
    }
    function Get-R95Plan {
        param([hashtable]$Index = @{})
        return @((Repair-GamePaths -userProfilesDir $script:r95Profiles -installFolder $script:r95Games -profileIndex $Index -DryRun:$true).Reports)
    }
}

Describe 'A different edition or version is never offered as the repair (issue 511)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:r95Root = Join-Path $TestDrive ('rc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:r95Profiles = Join-Path $script:r95Root 'UserProfiles'
        $script:r95Games = Join-Path $script:r95Root 'TP Games Arcade'
        [void][System.IO.Directory]::CreateDirectory($script:r95Profiles)
        [void][System.IO.Directory]::CreateDirectory($script:r95Games)
    }

    It 'Tekken 7 Fated Retribution 1.06.00 is not pointed at the Round 2 4.20 folder that has the same game file name' {
        New-R95Game -Code 'Tekken7FR' -OldRelative 'Tekken 7 Fated Retribution (1.06.00) (2016)\TekkenGame-Win64-Shipping.exe' -NewRelative 'Tekken 7 Fated Retribution Round 2 (4.20) (2019)\TekkenGame-Win64-Shipping.exe' -ExeName 'TekkenGame-Win64-Shipping.exe'

        $reports = @(Get-R95Plan)
        $reports[0].Status | Should -Not -BeExactly 'candidate'
        $reports[0].Status | Should -BeExactly 'not-found'
        $reports[0].Reason | Should -Match 'this version of the game is not on this drive'
        $reports[0].PSObject.Properties['NewPath'] | Should -BeNullOrEmpty
    }

    It 'with both folders present the folder of the registered version is chosen' {
        New-R95Game -Code 'Tekken7FR' -OldRelative 'Tekken 7 Fated Retribution (1.06.00) (2016)\TekkenGame-Win64-Shipping.exe' -NewRelative 'Moved\Tekken 7 Fated Retribution (1.06.00) (2016)\TekkenGame-Win64-Shipping.exe' -ExeName 'TekkenGame-Win64-Shipping.exe'
        $round2 = Join-Path $script:r95Games 'Tekken 7 Fated Retribution Round 2 (4.20) (2019)\TekkenGame-Win64-Shipping.exe'
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($round2))
        [System.IO.File]::WriteAllText($round2, 'game')

        $reports = @(Get-R95Plan)
        $reports[0].Status | Should -BeExactly 'candidate'
        $reports[0].NewPath | Should -BeExactly (Join-Path $script:r95Games 'Moved\Tekken 7 Fated Retribution (1.06.00) (2016)\TekkenGame-Win64-Shipping.exe')
    }

    It 'a moved folder with the same version is still repaired' {
        New-R95Game -Code 'Tekken7FR' -OldRelative 'Tekken 7 Fated Retribution (1.06.00) (2016)\TekkenGame-Win64-Shipping.exe' -NewRelative 'Moved\Tekken 7 Fated Retribution (1.06.00) (2016)\TekkenGame-Win64-Shipping.exe' -ExeName 'TekkenGame-Win64-Shipping.exe'
        @(Get-R95Plan)[0].Status | Should -BeExactly 'candidate'
    }

    It 'a [TP] game folder of another version is not used either' {
        New-R95Game -Code 'Tekken7FR' -OldRelative 'Tekken 7 Fated Retribution (1.06.00) (2016) [TP]\TekkenGame-Win64-Shipping.exe' -NewRelative 'Tekken 7 Fated Retribution Round 2 (4.20) (2019) [TP]\TekkenGame-Win64-Shipping.exe' -ExeName 'TekkenGame-Win64-Shipping.exe'
        @(Get-R95Plan)[0].Status | Should -BeExactly 'not-found'
    }
}

Describe 'Silver Strike Bowling Live moved from a disconnected drive (issue 511)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:r95Root = Join-Path $TestDrive ('rc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:r95Profiles = Join-Path $script:r95Root 'UserProfiles'
        $script:r95Games = Join-Path $script:r95Root 'TP Games Arcade'
        [void][System.IO.Directory]::CreateDirectory($script:r95Profiles)
        [void][System.IO.Directory]::CreateDirectory($script:r95Games)
    }

    It 'a plain old folder name finds the same game in a folder with a version and [TP] added, beside other games that use game.bin' {
        New-R95Game -Code 'SilverStrikeBowlingLive' -OldRelative 'Silver Strike Bowling Live\game.bin' -NewRelative 'Silver Strike Bowling Live (3.02.07) [TP]\game.bin' -ExeName 'game.bin'
        New-R95Game -Code 'GoldenTeeLive2020' -OldRelative 'Golden Tee Live 2020\game.bin' -NewRelative 'Golden Tee Live 2020 (1.00.00) [TP]\game.bin' -ExeName 'game.bin'
        $index = @{ 'game.bin' = @('SilverStrikeBowlingLive', 'GoldenTeeLive2020', 'TargetTossPro') }

        $reports = @(Get-R95Plan -Index $index)
        ($reports | Where-Object Code -eq 'SilverStrikeBowlingLive').Status | Should -BeExactly 'candidate'
        ($reports | Where-Object Code -eq 'SilverStrikeBowlingLive').NewPath | Should -BeExactly (Join-Path $script:r95Games 'Silver Strike Bowling Live (3.02.07) [TP]\game.bin')
    }
}

Describe 'Exact game names in lists (issue 507)' {
    BeforeEach {
        Mock Write-Log {}
        $script:r95Tp = Join-Path $TestDrive ('tp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:r95Tp 'Metadata'))
        $script:tpRoot = $script:r95Tp
    }

    It 'Fated Retribution and Round 2 are told apart by their version and year' {
        [System.IO.File]::WriteAllText((Join-Path $script:r95Tp 'Metadata\T7FR.json'), '{"game_name":"Tekken 7: Fated Retribution","release_year":2016}')
        [System.IO.File]::WriteAllText((Join-Path $script:r95Tp 'Metadata\T7R2.json'), '{"game_name":"Tekken 7: Fated Retribution Round 2","release_year":2019}')

        Get-TpmGameExactLabel -Code 'T7FR' -Path 'Q:\Games\Tekken 7 Fated Retribution (1.06.00) (2016)\TekkenGame-Win64-Shipping.exe' | Should -BeExactly 'Tekken 7: Fated Retribution (version 1.06.00, 2016)'
        Get-TpmGameExactLabel -Code 'T7R2' -Path 'Q:\Games\Tekken 7 Round 2 (4.20) (2019)\TekkenGame-Win64-Shipping.exe' | Should -BeExactly 'Tekken 7: Fated Retribution Round 2 (version 4.20, 2019)'
    }

    It 'a game with no known version is shown by its title alone' {
        [System.IO.File]::WriteAllText((Join-Path $script:r95Tp 'Metadata\T6.json'), '{"game_name":"Tekken 6"}')
        Get-TpmGameExactLabel -Code 'T6' -Path 'Q:\Games\Tekken 6\game.exe' | Should -BeExactly 'Tekken 6'
    }

    It 'the year comes from the folder name when TeknoParrot does not give one' {
        [System.IO.File]::WriteAllText((Join-Path $script:r95Tp 'Metadata\BR.json'), '{"game_name":"Tekken 6: Bloodline Rebellion"}')
        Get-TpmGameExactLabel -Code 'BR' -Path 'Q:\Games\Tekken 6 Bloodline Rebellion (2008)\game.exe' | Should -BeExactly 'Tekken 6: Bloodline Rebellion (2008)'
    }
}

Describe 'Remove, Ignore and the one validated game list (issues 507, 510)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:r95Root = Join-Path $TestDrive ('rm-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:r95Profiles = Join-Path $script:r95Root 'UserProfiles'
        $script:r95Games = Join-Path $script:r95Root 'Games'
        $state = Join-Path $script:r95Root 'State'
        [void][System.IO.Directory]::CreateDirectory($script:r95Profiles)
        [void][System.IO.Directory]::CreateDirectory($script:r95Games)
        [void][System.IO.Directory]::CreateDirectory($state)
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $state }
        $script:TpmValidatedGameList = $null
        $script:tpRoot = ''
        # Ready: the game file is there. Lost: the saved path is on a drive that is not connected. Ignored: ready, but on the Ignore list.
        $script:r95ReadyExe = Join-Path $script:r95Games 'Ready\game.exe'
        [void][System.IO.Directory]::CreateDirectory((Split-Path $script:r95ReadyExe))
        [System.IO.File]::WriteAllText($script:r95ReadyExe, 'game')
        $script:r95KeptFile = Join-Path $script:r95Games 'Lost Game (Other Version)\game.exe'
        [void][System.IO.Directory]::CreateDirectory((Split-Path $script:r95KeptFile))
        [System.IO.File]::WriteAllText($script:r95KeptFile, 'game')
        foreach ($entry in @(@('Ready', $script:r95ReadyExe), @('Ignored', $script:r95ReadyExe), @('Lost', ($script:r95Old + ':\Games\Lost Game\game.exe')))) {
            [System.IO.File]::WriteAllText((Join-Path $script:r95Profiles ($entry[0] + '.xml')), ('<GameProfile><GamePath>{0}</GamePath></GameProfile>' -f $entry[1]))
        }
    }
    AfterEach { $script:TpmOwnedLayout = $null; $script:TpmValidatedGameList = $null }

    It 'Remove takes the registration out after a backup and never touches a game file' {
        $result = Remove-TpmGameRegistrations -UserProfilesDir $script:r95Profiles -Codes @('Lost')

        @($result.Removed) | Should -Be @('Lost')
        Test-Path -LiteralPath (Join-Path $script:r95Profiles 'Lost.xml') | Should -BeFalse
        Test-Path -LiteralPath $script:r95KeptFile | Should -BeTrue
        Test-Path -LiteralPath $script:r95ReadyExe | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $result.Backup.Path 'Lost.xml') | Should -BeTrue
    }

    It 'Remove refuses a game whose game file is found, and keeps its registration' {
        $result = Remove-TpmGameRegistrations -UserProfilesDir $script:r95Profiles -Codes @('Ready')

        @($result.Removed).Count | Should -Be 0
        $result.Failed[0].Reason | Should -Match 'found now'
        Test-Path -LiteralPath (Join-Path $script:r95Profiles 'Ready.xml') | Should -BeTrue
    }

    It 'Ignore is saved to disk and lasts until it is turned back on' {
        Set-TpmIgnoredGames -Codes @('Ignored')
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $script:TpmOwnedLayout.State }   # a new run reads the saved file only
        @(Get-TpmIgnoredGames) | Should -Be @('Ignored')

        Set-TpmIgnoredGames -Codes @('Ignored') -Remove
        @(Get-TpmIgnoredGames).Count | Should -Be 0
    }

    It 'ignored, unresolved and disconnected-drive games are not in the list later steps use' {
        Set-TpmIgnoredGames -Codes @('Ignored')
        $list = Set-TpmValidatedGameList -UserProfilesDir $script:r95Profiles

        @($list.Eligible) | Should -Be @('Ready')
        $list.Excluded['Ignored'].Reason | Should -BeExactly 'ignored'
        $list.Excluded['Lost'].Reason | Should -BeExactly 'drive'
        $files = @(Get-ChildItem -LiteralPath $script:r95Profiles -Filter '*.xml' -File)
        @(Select-TpmEligibleProfileFiles -Files $files | ForEach-Object BaseName) | Should -Be @('Ready')
    }

    It 'a game skipped for this run is left out of the list, and a step with no list still sees every game' {
        $files = @(Get-ChildItem -LiteralPath $script:r95Profiles -Filter '*.xml' -File)
        @(Select-TpmEligibleProfileFiles -Files $files).Count | Should -Be 3

        $list = Set-TpmValidatedGameList -UserProfilesDir $script:r95Profiles -SkipCodes @('Ready')
        $list.Excluded['Ready'].Reason | Should -BeExactly 'skipped'
        @($list.Eligible) | Should -Contain 'Ignored'
    }

    It 'the registered-game picker for later steps does not offer a left-out game' {
        Mock Read-TpmChoice { 'A' }
        [void](Set-TpmValidatedGameList -UserProfilesDir $script:r95Profiles)
        $files = @(Get-ChildItem -LiteralPath $script:r95Profiles -Filter '*.xml' -File)

        @(Select-RegisteredGamesInteractive -UserProfilesDir $script:r95Profiles -Profiles $files -EligibleOnly | ForEach-Object BaseName) | Should -Not -Contain 'Lost'
        @(Select-RegisteredGamesInteractive -UserProfilesDir $script:r95Profiles -Profiles $files | ForEach-Object BaseName) | Should -Contain 'Lost'
    }
}
