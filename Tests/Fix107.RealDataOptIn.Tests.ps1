#Requires -Module Pester

# FIX107 (NEW-B3): tests are fixture-only unless the tester opts in to real data on purpose.
#   - A test case that reads data the tester owns runs only with TPM_REAL_SOURCE_TESTS=1 AND its own path variable
#     (Tests\TpmRealDataOptIn.ps1; TPM_REAL_DATA_TESTS=1 alone is not enough). A path variable that is only inherited from the environment starts nothing.
#   - The real-instance harness (scripts\Invoke-TPM-RealInstanceSmoke.ps1) reads the TeknoParrot folder it is given. It refuses to start
#     without TPM_REAL_DATA_TESTS=1, before it reads or creates anything.
#   - The certification launcher (scripts\Run-TPM-Certification-Suite.bat) has no default TeknoParrot folder any more.
# Everything here uses synthetic folders in $TestDrive. The harness and the launcher are started as child processes with a folder that does
# not exist, so even a run that gets past the gate cannot read real data.
# What this CANNOT prove: a real certification run (that needs an owner-approved folder and TPM_REAL_DATA_TESTS=1).

BeforeAll {
    . (Join-Path $PSScriptRoot 'TpmRealDataOptIn.ps1')
    $script:F107Harness = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Invoke-TPM-RealInstanceSmoke.ps1')).Path
    $script:F107Launcher = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Run-TPM-Certification-Suite.bat')).Path
    $script:F107SavedOptIn = $env:TPM_REAL_DATA_TESTS
    $script:F107SavedSource = $env:TPM_F107_FAKE_SOURCE
    $script:F107SavedRoot = $env:TPM_TEKNOPARROT_ROOT
    $script:F107SavedSourceOptIn = $env:TPM_REAL_SOURCE_TESTS
    $script:F107SavedRepoRoot = $env:TPM_REPO_ROOT

    # Runs a command with the opt-in value given ($null removes the variable) and returns exit code and all output text.
    function Invoke-F107Child {
        param([Parameter(Mandatory)][scriptblock]$Command, $OptIn)
        $ErrorActionPreference = 'Continue'
        $env:TPM_REAL_DATA_TESTS = $OptIn
        try {
            $output = @(& $Command 2>&1 | ForEach-Object { [string]$_ })
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
        } finally { $env:TPM_REAL_DATA_TESTS = $script:F107SavedOptIn }
    }

    # Copies the launcher into TestDrive next to a runner that only writes a marker (the TeknoParrot folder it was given), so a launcher
    # that goes on to start the runner can be seen without ever starting a real certification run.
    function New-F107LauncherFixture {
        $repo = Join-Path $TestDrive ('launcher-' + [guid]::NewGuid().ToString('N'))
        $scripts = Join-Path $repo 'scripts'
        [void][System.IO.Directory]::CreateDirectory($scripts)
        Copy-Item -LiteralPath $script:F107Launcher -Destination (Join-Path $scripts 'Run-TPM-Certification-Suite.bat')
        $marker = Join-Path $scripts 'runner-was-started.marker'
        Set-Content -LiteralPath (Join-Path $scripts 'Run-TPM-Tests.ps1') -Encoding ASCII -Value @(
            'param([string]$RepoPath, [string]$TeknoParrotRoot)'
            ('[System.IO.File]::WriteAllText(''{0}'', $TeknoParrotRoot)' -f $marker)
            'exit 0'
        )
        return [pscustomobject]@{ Repo = $repo; Launcher = (Join-Path $scripts 'Run-TPM-Certification-Suite.bat'); Marker = $marker }
    }
}

AfterAll {
    $env:TPM_REAL_DATA_TESTS = $script:F107SavedOptIn
    $env:TPM_F107_FAKE_SOURCE = $script:F107SavedSource
    $env:TPM_TEKNOPARROT_ROOT = $script:F107SavedRoot
    $env:TPM_REAL_SOURCE_TESTS = $script:F107SavedSourceOptIn
    $env:TPM_REPO_ROOT = $script:F107SavedRepoRoot
}

Describe 'FIX107 B3 a test reads real data only when the tester opted in' {
    BeforeEach {
        $script:F107Source = Join-Path $TestDrive ('source-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:F107Source)
        $env:TPM_F107_FAKE_SOURCE = $script:F107Source
    }
    AfterEach {
        $env:TPM_REAL_DATA_TESTS = $script:F107SavedOptIn
        $env:TPM_REAL_SOURCE_TESTS = $script:F107SavedSourceOptIn
        $env:TPM_F107_FAKE_SOURCE = $script:F107SavedSource
    }

    It 'returns the path only when TPM_REAL_SOURCE_TESTS is exactly 1 and the path exists' {
        # Mutation: treat an inherited path variable as enough (ignore TPM_REAL_SOURCE_TESTS) -> a real collection is read by an ordinary run.
        $env:TPM_REAL_SOURCE_TESTS = '1'
        Get-TpmRealDataSource -VariableName 'TPM_F107_FAKE_SOURCE' | Should -BeExactly $script:F107Source
        foreach ($value in @($null, '', '0', 'true', 'yes', '11', ' 1')) {
            $env:TPM_REAL_SOURCE_TESTS = $value
            Get-TpmRealDataSource -VariableName 'TPM_F107_FAKE_SOURCE' | Should -BeExactly '' -Because ("the opt-in value '{0}' is not exactly 1" -f $value)
        }
    }

    It 'does not start a real-source case just because the certification opt-in TPM_REAL_DATA_TESTS is 1' {
        # Mutation: let TPM_REAL_DATA_TESTS=1 (the certification opt-in) authorize a real-source case again -> a certification run reads an inherited owner collection (review B-2).
        $env:TPM_REAL_SOURCE_TESTS = $null
        $env:TPM_REAL_DATA_TESTS = '1'
        Get-TpmRealDataSource -VariableName 'TPM_F107_FAKE_SOURCE' | Should -BeExactly ''
    }

    It 'returns nothing when the opt-in is set but the path variable is missing or points nowhere' {
        # Mutation: return the variable's text without checking that the path exists -> a case runs against a folder that is not there.
        $env:TPM_REAL_SOURCE_TESTS = '1'
        $env:TPM_F107_FAKE_SOURCE = $null
        Get-TpmRealDataSource -VariableName 'TPM_F107_FAKE_SOURCE' | Should -BeExactly ''
        $env:TPM_F107_FAKE_SOURCE = Join-Path $TestDrive 'does-not-exist'
        Get-TpmRealDataSource -VariableName 'TPM_F107_FAKE_SOURCE' | Should -BeExactly ''
    }

    It 'the source stamp changes when a file is added, removed, resized or rewritten, and only then' {
        # Mutation: stamp only the file names (not length or time) -> a rewritten source looks untouched.
        $file = Join-Path $script:F107Source 'a.bin'
        [System.IO.File]::WriteAllBytes($file, [byte[]](1, 2, 3))
        [System.IO.File]::SetLastWriteTimeUtc($file, [datetime]'2020-01-01T00:00:00Z')
        $stamp = Get-TpmSourceStamp -Path $script:F107Source
        (Get-TpmSourceStamp -Path $script:F107Source) | Should -Be $stamp

        [System.IO.File]::SetLastWriteTimeUtc($file, [datetime]'2021-01-01T00:00:00Z')
        (Get-TpmSourceStamp -Path $script:F107Source) | Should -Not -Be $stamp
        [System.IO.File]::SetLastWriteTimeUtc($file, [datetime]'2020-01-01T00:00:00Z')
        (Get-TpmSourceStamp -Path $script:F107Source) | Should -Be $stamp

        [System.IO.File]::WriteAllBytes($file, [byte[]](1, 2, 3, 4))
        [System.IO.File]::SetLastWriteTimeUtc($file, [datetime]'2020-01-01T00:00:00Z')
        (Get-TpmSourceStamp -Path $script:F107Source) | Should -Not -Be $stamp

        [System.IO.File]::WriteAllBytes($file, [byte[]](1, 2, 3))
        [System.IO.File]::SetLastWriteTimeUtc($file, [datetime]'2020-01-01T00:00:00Z')
        $other = Join-Path $script:F107Source 'b.bin'
        [System.IO.File]::WriteAllBytes($other, [byte[]](9))
        (Get-TpmSourceStamp -Path $script:F107Source) | Should -Not -Be $stamp
        [System.IO.File]::Delete($other)
        (Get-TpmSourceStamp -Path $script:F107Source) | Should -Be $stamp
    }

    It 'stamps a single file source too' {
        # Mutation: treat a file path as a folder -> a .zip source cannot be stamped.
        $zip = Join-Path $TestDrive 'set.zip'
        [System.IO.File]::WriteAllBytes($zip, [byte[]](1, 2, 3))
        $stamp = @(Get-TpmSourceStamp -Path $zip)
        $stamp.Count | Should -Be 1
        [System.IO.File]::WriteAllBytes($zip, [byte[]](1, 2, 3, 4))
        @(Get-TpmSourceStamp -Path $zip) | Should -Not -Be $stamp
    }
}

Describe 'FIX107 B3 the real-instance harness and the launcher do not start a real-data run by default' {
    It 'the harness stops before reading or creating anything when the opt-in is <Case>' -ForEach @(
        @{ Case = 'missing'; Value = $null }
        @{ Case = '0'; Value = '0' }
        @{ Case = 'true'; Value = 'true' }
    ) {
        # Mutation: remove the TPM_REAL_DATA_TESTS gate at the top of Invoke-TPM-RealInstanceSmoke.ps1 -> the run goes on to read the folder it was given.
        $missingRoot = Join-Path $TestDrive 'no-such-install'
        $missingHarness = Join-Path $TestDrive 'no-such-harness'
        $result = Invoke-F107Child -OptIn $Value -Command {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:F107Harness -RepoPath (Join-Path $TestDrive 'no-such-repo') -TeknoParrotRoot $missingRoot -HarnessRoot $missingHarness
        }
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'did not start'
        $result.Output | Should -Match 'TPM_REAL_DATA_TESTS=1'
        $result.Output | Should -Match 'Nothing was read or changed'
        Test-Path -LiteralPath $missingHarness | Should -BeFalse
    }

    It 'the harness goes past the gate when the opt-in is exactly 1 (and then stops on the missing repository)' {
        # Mutation: refuse every value, or require something other than exactly 1 -> the documented opt-in no longer starts a run.
        $result = Invoke-F107Child -OptIn '1' -Command {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:F107Harness -RepoPath (Join-Path $TestDrive 'no-such-repo') -TeknoParrotRoot (Join-Path $TestDrive 'no-such-install') -HarnessRoot (Join-Path $TestDrive 'no-such-harness')
        }
        $result.Output | Should -Not -Match 'did not start'
        $result.ExitCode | Should -Not -Be 0
    }

    It 'the launcher refuses to run without a named TeknoParrot folder and does not fall back to a default' {
        # Mutation: put back the default TeknoParrot folder (or the prompt that offered it) -> the launcher goes on to start the runner when nobody named a folder.
        # The launcher is copied into TestDrive next to a runner that only writes a marker, and the real-data opt-in stays unset, so even a
        # regression cannot start a real certification run or touch a real install.
        $fixture = New-F107LauncherFixture
        $launcher = $fixture.Launcher
        $marker = $fixture.Marker
        $savedRoot = $env:TPM_TEKNOPARROT_ROOT
        $env:TPM_TEKNOPARROT_ROOT = $null
        $env:TPM_REPO_ROOT = $null
        try {
            # '<' nul: the .bat pauses on this path; with stdin closed a hand run at an open console never waits for a key.
            $result = Invoke-F107Child -OptIn $null -Command { & cmd.exe /d /c $launcher '<' nul }
        } finally { $env:TPM_TEKNOPARROT_ROOT = $savedRoot }
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'No TeknoParrot folder was given'
        $result.Output | Should -Match 'Nothing was read or changed'
        $result.Output | Should -Match 'console window'
        $result.Output | Should -Match 'set TPM_REAL_DATA_TESTS=1'
        $result.Output | Should -Not -Match 'Certification process exit code'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'the copied launcher hands a named folder to the runner (so the stub above can really detect a started run)' {
        # Mutation: make the launcher never start the runner -> the refusal test above would pass for the wrong reason.
        $fixture = New-F107LauncherFixture
        $launcher = $fixture.Launcher
        $marker = $fixture.Marker
        $repo = $fixture.Repo
        $named = Join-Path $TestDrive 'named-install'
        $env:TPM_REPO_ROOT = $null
        $result = Invoke-F107Child -OptIn $null -Command { & cmd.exe /d /c $launcher $repo $named }
        $result.ExitCode | Should -Be 0
        Test-Path -LiteralPath $marker | Should -BeTrue
        [System.IO.File]::ReadAllText($marker) | Should -Be $named
    }
}
