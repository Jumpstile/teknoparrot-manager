#Requires -Module Pester

# FIX110A (S-23): manual path repair (Library Health): the result named the FIRST N input games as changed (N = how many were saved), so a skipped game A and a
#      saved game B were reported as A changed. It also called "nothing saved, but errors" a NO_OP. Now the worker returns the exact saved game codes
#      and the adapter classifies: saved and failed = PARTIAL_APPLIED, only saved = SUCCEEDED, only failed = FAILED_BEFORE_MUTATION, nothing = NO_OP.
# These tests drive the real functions with synthetic profile folders in $TestDrive. Nothing outside $TestDrive is touched.
# What this CANNOT prove: the interactive file browser and the full menu flow (they are replaced by fixtures).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f110aAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix110a-mr-functions.ps1'
    ($script:f110aAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:logPath = Join-Path $TestDrive 'fix110a-mr.log'
    $script:logWarnShown = $false

    # A games folder with one executable per game, and one broken profile (its saved path is missing) per game.
    function New-F110aRepairFixture {
        param([string[]]$Codes)
        $root = Join-Path $TestDrive ('repair-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $fixture = [ordered]@{ Root = $root; Profiles = (Join-Path $root 'UserProfiles'); Games = (Join-Path $root 'Games'); Outside = (Join-Path $root 'Outside'); Exes = @{}; OutsideExes = @{}; ProfilePaths = @{} }
        foreach ($folder in @($fixture.Profiles, $fixture.Games, $fixture.Outside)) { [void][System.IO.Directory]::CreateDirectory($folder) }
        foreach ($code in $Codes) {
            $exe = Join-Path (Join-Path $fixture.Games $code) 'game.exe'
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($exe))
            [System.IO.File]::WriteAllText($exe, 'game')
            $outsideExe = Join-Path (Join-Path $fixture.Outside $code) 'game.exe'
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outsideExe))
            [System.IO.File]::WriteAllText($outsideExe, 'outside')
            $profilePath = Join-Path $fixture.Profiles ($code + '.xml')
            [System.IO.File]::WriteAllText($profilePath, '<GameProfile><GamePath>C:\missing\game.exe</GamePath><ExecutableName>game.exe</ExecutableName></GameProfile>')
            $fixture.Exes[$code] = $exe
            $fixture.OutsideExes[$code] = $outsideExe
            $fixture.ProfilePaths[$code] = $profilePath
        }
        return [pscustomobject]$fixture
    }
}

Describe 'FIX110A S-23 manual path repair names the games that were really saved' {
    BeforeEach {
        $script:f110aLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:f110aLog.Add([string]$msg) }
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-HostSafe { 'Y' }
    }

    It 'records the saved game, not the first input game, when the first one was skipped' {
        # Mutation: take ChangedItems as the first Updated-many input codes (Select-Object -First Updated) -> the skipped game A is reported as changed and the saved game B is not.
        $fixture = New-F110aRepairFixture -Codes @('AGAME', 'BGAME')
        $script:f110aFixture = $fixture
        $beforeA = [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME'])
        Mock Read-PathWithBrowse { if ([string]$Prompt -match 'AGAME') { '' } else { $script:f110aFixture.Exes['BGAME'] } }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('AGAME', 'BGAME')
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.Mutation.ChangedItems) | Should -Be @('BGAME')
        @($result.Mutation.ChangedItems) | Should -Not -Contain 'AGAME'
        @($result.Mutation.SkippedItems) | Should -Contain 'AGAME'
        [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME']) | Should -BeExactly $beforeA
        (Read-Xml -Path $fixture.ProfilePaths['BGAME']).GameProfile.GamePath | Should -Be ([System.IO.Path]::GetFullPath($fixture.Exes['BGAME']))
    }

    It 'does not overwrite a profile that changed after it was read' {
        # Who gets hurt: a user whose TeknoParrot saved the profile while the safety backup ran lost that newer save.
        # Mutation: remove the unchanged-since-read check before Save-Xml.
        $fixture = New-F110aRepairFixture -Codes @('AGAME', 'BGAME')
        $script:f110aFixture = $fixture
        Mock Read-PathWithBrowse { $script:f110aFixture.Exes[$(if ([string]$Prompt -match 'AGAME') { 'AGAME' } else { 'BGAME' })] }
        Mock New-TpmVerifiedUserProfilesBackup {
            [System.IO.File]::WriteAllText($script:f110aFixture.ProfilePaths['AGAME'], '<GameProfile><GamePath>C:\missing\game.exe</GamePath><ExecutableName>game.exe</ExecutableName><Newer>yes</Newer></GameProfile>')
            [pscustomobject]@{ Verified = $true; Succeeded = $true; Reason = ''; Path = (Join-Path $TestDrive 'f110a-backup') }
        }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('AGAME', 'BGAME')
        [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME']) | Should -Match '<Newer>yes</Newer>'
        [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME']) | Should -Not -Match ([regex]::Escape([System.IO.Path]::GetFullPath($fixture.Exes['AGAME'])))
        @($result.Mutation.ChangedItems) | Should -Be @('BGAME')
        $result.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
    }

    It 'accepts the file the user picked when the profile records no executable name' {
        # Who gets hurt: a user whose game has no recorded executable name could not repair a moved game folder from this screen at all.
        $fixture = New-F110aRepairFixture -Codes @('NONAME')
        $script:f110aFixture = $fixture
        [System.IO.File]::WriteAllText($fixture.ProfilePaths['NONAME'], '<GameProfile><GamePath>C:\missing\game.exe</GamePath><ExecutableName></ExecutableName></GameProfile>')
        Mock Read-PathWithBrowse { $script:f110aFixture.Exes['NONAME'] }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('NONAME')
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.Mutation.ChangedItems) | Should -Be @('NONAME')
        (Read-Xml -Path $fixture.ProfilePaths['NONAME']).GameProfile.GamePath | Should -Be ([System.IO.Path]::GetFullPath($fixture.Exes['NONAME']))
    }

    It 'still refuses a picked file outside the games folder when no executable name is recorded' {
        $fixture = New-F110aRepairFixture -Codes @('NONAME')
        $script:f110aFixture = $fixture
        $before = '<GameProfile><GamePath>C:\missing\game.exe</GamePath><ExecutableName></ExecutableName></GameProfile>'
        [System.IO.File]::WriteAllText($fixture.ProfilePaths['NONAME'], $before)
        Mock Read-PathWithBrowse { $script:f110aFixture.OutsideExes['NONAME'] }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('NONAME')
        @($result.Mutation.ChangedItems).Count | Should -Be 0
        [System.IO.File]::ReadAllText($fixture.ProfilePaths['NONAME']) | Should -BeExactly $before
    }

    It 'accepts the real executable of a game in a path over 259 characters' {
        # Mutation: plain Test-Path "is it a file" before the path check -> a game TPM extracted into a long folder is refused as "not an existing file" (host with long paths off).
        $fixture = New-F110aRepairFixture -Codes @('LGAME')
        $gameRoot = Join-Path $fixture.Games 'LGAME'
        $deep = $gameRoot
        while ($deep.Length -lt 280) { $deep = Join-Path $deep 'a-long-folder-name-for-testing' }
        try {
            [void][System.IO.Directory]::CreateDirectory('\\?\' + $deep)
            $longExe = Join-Path $deep 'game.exe'
            [System.IO.File]::WriteAllText('\\?\' + $longExe, 'game')
            $script:f110aLong = $longExe
            Mock Read-PathWithBrowse { $script:f110aLong }
            $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('LGAME')
            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            @($result.Mutation.ChangedItems) | Should -Be @('LGAME')
        } finally {
            # Windows PowerShell 5.1 cannot delete this folder through a normal path, so Pester's TestDrive cleanup would fail on it.
            if ([System.IO.Directory]::Exists('\\?\' + $gameRoot)) { [System.IO.Directory]::Delete('\\?\' + $gameRoot, $true) }
        }
    }

    It 'says partial, with the exact saved and failed games, when one was saved and one was refused' {
        # Mutation: ignore the failed list when something was saved (or name the games by position) -> the refused game A is shown as changed or the failure is lost.
        $fixture = New-F110aRepairFixture -Codes @('AGAME', 'BGAME')
        $script:f110aFixture = $fixture
        Mock Read-PathWithBrowse { if ([string]$Prompt -match 'AGAME') { $script:f110aFixture.OutsideExes['AGAME'] } else { $script:f110aFixture.Exes['BGAME'] } }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('AGAME', 'BGAME')
        $result.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
        $result.ProductState | Should -BeExactly 'PARTIAL_KNOWN'
        @($result.Mutation.ChangedItems) | Should -Be @('BGAME')
        @($result.Mutation.FailedItems) | Should -Be @('AGAME')
    }

    It 'says the repair failed, not "nothing to do", when nothing was saved and a game was refused' {
        # Mutation: choose NO_OP whenever Updated is 0 (even with errors) -> a refused path is reported as "no changes needed".
        $fixture = New-F110aRepairFixture -Codes @('AGAME')
        $script:f110aFixture = $fixture
        $before = [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME'])
        Mock Read-PathWithBrowse { $script:f110aFixture.OutsideExes['AGAME'] }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('AGAME')
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'MANUAL_REPAIR_FAILED'
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        $result.Mutation.Started | Should -BeFalse
        @($result.Mutation.FailedItems) | Should -Be @('AGAME')
        @($result.Mutation.ChangedItems).Count | Should -Be 0
        $result.Summary | Should -Match 'did not save any profile'
        [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME']) | Should -BeExactly $before
    }

    It 'still says nothing to do when every game was skipped and nothing failed' {
        # Mutation: report FAILED for a result with no errors -> the all-skipped case is no longer a plain NO_OP.
        $fixture = New-F110aRepairFixture -Codes @('AGAME')
        Mock Read-PathWithBrowse { '' }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('AGAME')
        $result.Outcome | Should -BeExactly 'NO_OP'
        $result.ReasonCode | Should -BeExactly 'NO_CHANGES_NEEDED'
        @($result.Mutation.SkippedItems) | Should -Contain 'AGAME'
    }

    It 'saves nothing and says so when the safety backup cannot be checked' {
        $fixture = New-F110aRepairFixture -Codes @('AGAME')
        $script:f110aFixture = $fixture
        $before = [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME'])
        Mock Read-PathWithBrowse { $script:f110aFixture.Exes['AGAME'] }
        Mock New-TpmVerifiedUserProfilesBackup { [pscustomobject]@{ Verified = $false; Succeeded = $false; Reason = 'fixture backup failure'; Path = $null } }
        $result = Invoke-LibraryHealthManualPathRepair -UserProfilesDir $fixture.Profiles -GamesInstallFolder $fixture.Games -BrokenGames @('AGAME')
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        @($result.Mutation.ChangedItems).Count | Should -Be 0
        [System.IO.File]::ReadAllText($fixture.ProfilePaths['AGAME']) | Should -BeExactly $before
    }
}
