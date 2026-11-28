#Requires -Module Pester

# RC9.5 follow-up from a real tester log: the wrong Tekken edition is never applied, "game|game.bin" profiles are repaired by their
# [TP] folder name, and the status lines, ledger and messages are plain. Real folders under $TestDrive; an unused drive letter stands
# for the old drive. What this CANNOT prove: a run against the tester's real library.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'RC95U4 bootstrap could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'rc95u4-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    function Write-Log { param([string]$msg) }

    $script:u4Old = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'P', 'O', 'N', 'M' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) }) | Select-Object -First 1
    if (-not $script:u4Old) { throw 'RC95U4 needs one unused drive letter.' }

    function New-U4Profile {
        param([string]$Code, [string]$OldRelative, [string]$ExeName)
        $oldPath = $script:u4Old + ':\Arcade Games\' + $OldRelative
        [System.IO.File]::WriteAllText((Join-Path $script:u4Profiles ($Code + '.xml')), ('<GameProfile><GamePath>{0}</GamePath><ExecutableName>{1}</ExecutableName></GameProfile>' -f $oldPath, $ExeName))
    }
    function New-U4File {
        param([string]$Relative)
        $path = Join-Path $script:u4Games $Relative
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        [System.IO.File]::WriteAllText($path, 'game')
        return $path
    }
    function Get-U4Plan {
        param([hashtable]$Index = @{})
        return @((Repair-GamePaths -userProfilesDir $script:u4Profiles -installFolder $script:u4Games -profileIndex $Index -DryRun:$true).Reports)
    }
    $script:u4Tekken = 'TekkenGame\Binaries\Win64\TekkenGame-Win64-Shipping.exe'
}

Describe 'Real-log follow-up (RC9.5 u4)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:u4Root = Join-Path $TestDrive ('u4-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:u4Profiles = Join-Path $script:u4Root 'UserProfiles'
        $script:u4Games = Join-Path $script:u4Root 'TP Games Arcade'
        [void][System.IO.Directory]::CreateDirectory($script:u4Profiles)
        [void][System.IO.Directory]::CreateDirectory($script:u4Games)
    }

    It 'A: the three Tekken 7 profiles of the real log are never pointed at the 4.20 folder' {
        New-U4Profile -Code 'Tekken7' -OldRelative ('Tekken 7 (1.2)(2015)[Namco ES3X][TP]\' + $script:u4Tekken) -ExeName 'TekkenGame-Win64-Shipping.exe'
        New-U4Profile -Code 'Tekken7FR' -OldRelative ('Tekken 7 Fated Retribution (1.06.00)(2016)[Namco ES3X][TP]\' + $script:u4Tekken) -ExeName 'TekkenGame-Win64-Shipping.exe'
        New-U4Profile -Code 'Tekken7R2' -OldRelative ('Tekken 7 Fated Retribution Round 2 (1.08.00)(2019)[Namco ES3A][TP]\' + $script:u4Tekken) -ExeName 'TekkenGame-Win64-Shipping.exe'
        [void](New-U4File ('Tekken 7 Fated Retribution Round 2 (4.20, TR2 15.01)(2019)[Namco ES3X][TP]\' + $script:u4Tekken))
        $index = @{ 'tekkengame-win64-shipping.exe' = @('Tekken7', 'Tekken7FR', 'Tekken7R2') }
        $before = @{}
        foreach ($code in 'Tekken7', 'Tekken7FR', 'Tekken7R2') { $before[$code] = [System.IO.File]::ReadAllText((Join-Path $script:u4Profiles ($code + '.xml'))) }

        $plan = @(Get-U4Plan -Index $index)
        @($plan | Where-Object Status -eq 'candidate').Count | Should -Be 0
        foreach ($report in $plan) { $report.Reason | Should -Match 'not on this drive' }
        $applied = Repair-GamePaths -userProfilesDir $script:u4Profiles -installFolder $script:u4Games -profileIndex $index -DryRun:$false
        @($applied.Reports | Where-Object Status -eq 'fixed').Count | Should -Be 0
        foreach ($code in 'Tekken7', 'Tekken7FR', 'Tekken7R2') { [System.IO.File]::ReadAllText((Join-Path $script:u4Profiles ($code + '.xml'))) | Should -BeExactly $before[$code] }
    }

    It 'A: a candidate whose [TP] folder differs only in version or year is never ranked as the same game' {
        $old = $script:u4Old + ':\Arcade Games\Tekken 7 (1.2)(2015)[Namco ES3X][TP]\' + $script:u4Tekken
        $other = Join-Path $script:u4Games ('Tekken 7 (4.20)(2019)[Namco ES3X][TP]\' + $script:u4Tekken)
        Select-TpmMovedGameCandidate -Candidates @($other) -OldPath $old -InstallFolder $script:u4Games -Code 'Tekken7' | Should -BeNullOrEmpty
        $same = Join-Path $script:u4Games ('Tekken 7 (1.2)(2015)[Namco ES3X][TP]\' + $script:u4Tekken)
        Select-TpmMovedGameCandidate -Candidates @($other, $same) -OldPath $old -InstallFolder $script:u4Games -Code 'Tekken7' | Should -BeExactly $same
    }

    It 'B: "game|game.bin" is repaired by the [TP] folder name for <Code>, beside other games that also hold game.bin' -TestCases @(
        @{ Code = 'SilverStrikeBowlingLive'; Folder = 'Silver Strike Bowling Live (3.02.07)(2017-05-10)(USA)[IT Nighthawk][TP]' }
        @{ Code = 'GoldenTeeLive2019'; Folder = 'Golden Tee Live 2019 (1.00.00)(2018)(USA)[IT Nighthawk][TP]' }
        @{ Code = 'PowerPuttLive2013'; Folder = 'Power Putt Live 2013 (2.00.00)(2013)(USA)[IT Nighthawk][TP]' }
        @{ Code = 'TargetTossProBags'; Folder = 'Target Toss Pro Bags (1.01.00)(2016)(USA)[IT Nighthawk][TP]' }
    ) {
        New-U4Profile -Code $Code -OldRelative ($Folder + '\game.bin') -ExeName 'game|game.bin'
        $mine = New-U4File ($Folder + '\game.bin')
        foreach ($beside in 'Silver Strike Bowling Live (3.02.07)(2017-05-10)(USA)[IT Nighthawk][TP]', 'Golden Tee Live 2019 (1.00.00)(2018)(USA)[IT Nighthawk][TP]', 'Other Game (2011)[TP]') {
            if ($beside -ne $Folder) { [void](New-U4File ($beside + '\game.bin')) }
        }
        [void](New-U4File 'Other Game (2011)[TP]\game')
        foreach ($index in @(@{}, @{ 'game.bin' = @($Code, 'OtherGame'); 'game' = @($Code, 'OtherGame') })) {
            $reports = @(Get-U4Plan -Index $index | Where-Object Code -eq $Code)
            $reports[0].Status | Should -BeExactly 'candidate'
            $reports[0].NewPath | Should -BeExactly $mine
        }
    }

    It 'B: the note for a name that lists alternative file names does not call it an error' {
        $script:u4Logs = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { $script:u4Logs.Add([string]$msg) }
        Get-TpmExecutableDisplayName -Name 'game|game.bin' -Codes 'GoldenTeeLive2019' | Should -BeExactly 'game|game.bin'
        ($script:u4Logs -join ' ') | Should -Not -Match 'do not allow'
        ($script:u4Logs -join ' ') | Should -Match 'alternative file names'
    }

    It 'F: every unresolved game gets one plain status line' {
        $other = [pscustomobject]@{ Code = 'Tekken7R2'; Status = 'not-found'; Reason = 'this version of the game is not on this drive (a different version of the game is; TeknoParrot Manager will not point this game at it)'; CandidatePaths = @('G:\Games\x.exe') }
        $several = [pscustomobject]@{ Code = 'A'; Status = 'ambiguous'; Reason = 'several game files fit and the old folder names do not show which one is right'; CandidatePaths = @('G:\Games\a.exe', 'G:\Games\b.exe') }
        $nothing = [pscustomobject]@{ Code = 'B'; Status = 'not-found'; Reason = 'matching executable was not found'; CandidatePaths = @() }
        Get-TpmUnresolvedStatusLine -Report $other | Should -BeExactly 'Registered: yes. Game file found: no. Right version: no. Ready: no.'
        Get-TpmUnresolvedStatusLine -Report $several | Should -BeExactly 'Registered: yes. Game file found: yes. Right version: unknown. Ready: no.'
        Get-TpmUnresolvedStatusLine -Report $nothing | Should -BeExactly 'Registered: yes. Game file found: no. Right version: unknown. Ready: no.'
    }

    It 'E: the screen says a removed game is registered again when its files show up, and shows the status line in the list' {
        $script:tpRoot = ''
        $script:u4Said = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText { $script:u4Said.Add([string]$Text) }
        Mock Read-TpmChoice { 'R' }
        Mock Read-HostSafe { 'A' }
        Mock Read-TpmYesNo { 'Y' }
        Mock Remove-TpmGameRegistrations { [pscustomobject]@{ Removed = @('Tekken7R2'); Failed = @(); Backup = [pscustomobject]@{ Path = 'C:\Backup' } } }
        $row = [pscustomobject]@{ Code = 'Tekken7R2'; Status = 'not-found'; PreviousPath = 'G:\TP Games Arcade\Tekken 7 Fated Retribution Round 2 (1.08.00)(2019)[Namco ES3A][TP]\x.exe'; Reason = 'this version of the game is not on this drive'; CandidatePaths = @() }
        $result = Invoke-TpmUnresolvedGameOptions -Reports @($row) -UserProfilesDir $script:u4Profiles -GamesInstallFolder $script:u4Games -Interactive
        @($result.Removed) | Should -Be @('Tekken7R2')
        ($script:u4Said -join "`n") | Should -Match 'Registered: yes\. Game file found: no\. Right version: no\. Ready: no\.'
        ($script:u4Said -join "`n") | Should -Match 'next scan registers it again'
    }

    It 'D: the PostgreSQL setup-needed message explains in plain words that setup creates the database and needs the password saved first' {
        $result = [pscustomobject]@{
            PostgresServiceExists = $true; PostgresServiceStatus = 'Running'; PostgresPsqlStatus = 'Found'; PostgresInventoryStatus = 'Complete'
            PostgresNeeded = @('GoldenTeeLive2020'); PostgresNeededLabels = @('Golden Tee Live 2020'); PostgresConfiguredLabels = @(); PostgresConfigured = 0
        }
        $text = ((Get-TpmLibraryHealthDetailBlocks -Result $result | ForEach-Object { $_.Lines }) -join "`n")
        $text | Should -Match 'Setup needed for: Golden Tee Live 2020'
        $text | Should -Match 'creates that database, and it needs the PostgreSQL password saved first'
        $text | Should -Match 'Details: .*DbName'
    }
}
