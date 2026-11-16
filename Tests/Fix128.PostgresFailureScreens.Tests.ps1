#Requires -Module Pester

# FIX128: PostgreSQL failure, refusal and recovery screens in plain words.
#   B3  A failed or rolled-back run says in plain words what happened to the data. Tool names, exit codes, result codes and raw tool
#       text are only under Details (key D) and in the log. No "previous verified state", "recovery-complete", "did not claim".
#   S7  A failed PostgreSQL install no longer says "No PostgreSQL or profile changes were made" after the Windows installer ran.
#   S8  The leftover-refusal screen warns before it mentions deleting, and never implies that a listed folder is safe to delete.
#   N9  "blocked" is not used for every non-success; the restore and rebuild screens say "Details" (one name); the Details totals use
#       the same names as the count line on the result screen.
# The production script is parsed and its functions are dot-sourced; no top-level product code runs. Every console write, prompt and
# log line is a mock. No PostgreSQL, service, installer, network or real data is used (TPM_REAL_DATA_TESTS is not touched).
# What this CANNOT prove: how the real console lays the screens out, the real installer, or the top-level menu code that chooses
# which screen to show (that code is not a function and is not run here).

BeforeAll {
    $script:F128ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:F128Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F128ProductPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX128 tests could not parse the production script.' }
    $functionText = @($script:F128Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F128FunctionFile = Join-Path $TestDrive 'tpm-fix128-functions.ps1'
    [System.IO.File]::WriteAllText($script:F128FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F128FunctionFile

    # The words a beginner should not meet on a PostgreSQL failure screen.
    $script:F128Jargon = '(?i)verified state|previous verified|recovery-complete|recovery complete|did not claim|transaction|rollback|rolled back|blocked|pg_restore|createdb|exit code|ROLLED_BACK|ACTION_REQUIRED|FAILED_BEFORE|GameDB\d'

    function New-F128Result {
        param([string]$Outcome, [string]$ProductState, [string]$Summary = 'A summary.', [string[]]$Reasons = @('Database GameDB19 could not be created: pg_restore: Error from TOC entry 110; pg_restore ended with exit code 2.'))
        return [pscustomobject]@{
            Outcome = $Outcome
            ProductState = $ProductState
            ReasonCode = 'FIXTURE_REASON'
            Summary = $Summary
            TechnicalDetails = [pscustomobject]@{ Stage = 'DatabaseCreation'; FailureReasons = @($Reasons) }
            RecoveryActions = @(@{ Id = 'Review'; Label = 'Open Details and review the preserved PostgreSQL setup evidence.' })
        }
    }
    function Reset-F128Capture {
        $script:F128Screen = New-Object System.Collections.Generic.List[string]
        $script:F128Log = New-Object System.Collections.Generic.List[string]
        $script:F128Details = New-Object System.Collections.Generic.List[string]
        $script:F128Prompts = New-Object System.Collections.Generic.List[string]
        $script:F128Answers = New-Object System.Collections.Generic.Queue[string]
    }
    # Standard stand-ins. The details view is recorded line by line, headings included.
    function Set-F128Mocks {
        Mock Write-Host { [void]$script:F128Screen.Add([string]($Object -join ' ')) }
        Mock Write-Log { [void]$script:F128Log.Add([string]$msg) }
        Mock Write-TpmText { [void]$script:F128Details.Add([string]$Text) }
        Mock Show-TpmDetailBlocks {
            foreach ($block in @($Blocks)) {
                [void]$script:F128Details.Add([string]$block.Heading)
                foreach ($line in @($block.Lines)) { [void]$script:F128Details.Add([string]$line) }
            }
        }
        Mock Read-HostSafe {
            [void]$script:F128Prompts.Add([string]$Prompt)
            if ($script:F128Answers.Count -gt 0) { return $script:F128Answers.Dequeue() }
            return ''
        }
    }
}

Describe 'FIX128 the plain sentence about the data (Get-TpmPostgresDataSafetyText)' {
    It 'says <Outcome> / <State> in plain words and never more than the result proves' -TestCases @(
        @{ Outcome = 'ROLLED_BACK_VERIFIED'; State = 'UNCHANGED'; Match = 'back the way it was.*checked'; NotMatch = 'Nothing was changed|may be left over' }
        @{ Outcome = 'FAILED_BEFORE_MUTATION'; State = 'UNCHANGED'; Match = '^Nothing was changed\.$'; NotMatch = 'back the way it was|may be left over' }
        @{ Outcome = 'ACTION_REQUIRED'; State = 'UNKNOWN'; Match = 'may be left over.*ask for help'; NotMatch = 'Nothing was changed|back the way it was' }
        @{ Outcome = 'ACTION_REQUIRED'; State = 'UNCHANGED'; Match = 'databases were not changed.*temporary files'; NotMatch = 'may be left over|back the way it was' }
        @{ Outcome = 'PARTIAL_APPLIED'; State = 'PARTIAL_KNOWN'; Match = 'some were not'; NotMatch = 'Nothing was changed|back the way it was' }
        @{ Outcome = 'CLEANUP_RESIDUE'; State = 'INTENDED'; Match = 'leftover files'; NotMatch = 'Nothing was changed|may be left over' }
    ) {
        param($Outcome, $State, $Match, $NotMatch)
        # Mutation: return 'Nothing was changed.' (or the rolled-back sentence) for every outcome -> an unverified or partial result
        # is described as safe. That is the same class of untrue claim as S7.
        $text = Get-TpmPostgresDataSafetyText -Result (New-F128Result -Outcome $Outcome -ProductState $State)
        $text | Should -Match $Match
        $text | Should -Not -Match $NotMatch
        $text | Should -Not -Match $script:F128Jargon
    }

    It 'gives the careful sentence when there is no result at all' {
        # Mutation: treat a missing result as "nothing was changed".
        Get-TpmPostgresDataSafetyText -Result $null | Should -Match 'may be left over'
        Get-TpmPostgresDataSafetyText -Result $null | Should -Not -Match 'Nothing was changed'
    }

    It 'only says "nothing was changed" for a stop after an earlier install or rebuild when PostgreSQL itself did not change' {
        # Mutation: Get-TpmPostgresNothingChangedText ignores the flag.
        Get-TpmPostgresNothingChangedText -PostgresChanged $false | Should -BeExactly 'Nothing was changed.'
        $changed = Get-TpmPostgresNothingChangedText -PostgresChanged $true
        $changed | Should -Not -Match '^Nothing was changed'
        $changed | Should -Match 'game settings were not changed'
        $changed | Should -Match 'PostgreSQL itself was installed or rebuilt'
    }
}

Describe 'FIX128 S7 a failed install tells the truth' {
    It 'says parts of PostgreSQL may be on the PC once the installer ran, and gives the next step' {
        # Mutation: keep "No PostgreSQL or profile changes were made." for every failed install.
        $view = Get-PostgresInstallFailureView -InstallerRan $true
        $view.Screen | Should -Match 'Parts of it may now be on this PC'
        $view.Screen | Should -Match 'games and game settings were not changed'
        $view.DataSafety | Should -Match 'Parts of PostgreSQL may be left on this PC'
        $view.DataSafety | Should -Not -Match 'No PostgreSQL or profile changes were made'
        $view.DataSafety | Should -Not -Match '^Nothing was changed'
        $view.Next | Should -Match 'open View Log, then choose PostgreSQL setup again'
        $view.Next | Should -Match 'read the warning on that screen before you delete anything'
        $view.ResumeMessage | Should -Match 'Parts of it may now be on this PC'
        foreach ($text in @($view.Screen, $view.Next, $view.Message, $view.DataSafety, $view.ResumeMessage)) { $text | Should -Not -Match $script:F128Jargon }
    }

    It 'still says nothing was changed when the install stopped before the installer ran' {
        # Mutation: always use the "parts may be on this PC" text, which would scare a user whose PC was not touched.
        $view = Get-PostgresInstallFailureView -InstallerRan $false
        $view.Screen | Should -BeExactly 'PostgreSQL was not installed. Nothing was changed.'
        $view.DataSafety | Should -BeExactly 'Nothing was changed.'
        $view.ResumeMessage | Should -Not -Match 'Parts of it'
    }

    Context 'Install-Postgres83 records whether the Windows installer ran' {
        BeforeEach {
            Reset-F128Capture
            Set-F128Mocks
            $script:F128InstallerCalls = 0
            $script:F128ServiceThere = $false
            $script:F128SavedTemp = $env:TEMP
            $env:TEMP = Join-Path $TestDrive ('f128-install-temp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            [void][System.IO.Directory]::CreateDirectory($env:TEMP)
            Mock Test-RunningAsAdministrator { $true }
            Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $false; Objects = @() } }
            Mock Read-ConfirmedPostgresPassword { 'Fix128-Install-Pw1' }
            Mock Get-PostgresGuideRelease { [pscustomobject]@{ DownloadUrl = 'https://example.invalid/guide.zip'; SizeBytes = 1; SizeMB = 1 } }
            Mock Invoke-PostgresGuideDownload { $true }
            Mock Expand-ZipFileSafe { [System.IO.File]::WriteAllText((Join-Path $DestDir 'postgresql-8.3-int.msi'), 'fixture') }
            Mock Invoke-PostgresMsiPackage { $script:F128InstallerCalls++; $true }
            Mock Test-PostgresInstalled { $script:F128ServiceThere }
            Mock Get-PostgresServiceStatusText { 'Running' }
            Mock Write-TpmCompactExtractionProgress {}
        }
        AfterEach { $env:TEMP = $script:F128SavedTemp }

        It 'marks the installer as run when it ran and the service check failed, and the failure text then says so' {
            # Mutation: never set the flag (or set it only on success) -> the failure screen claims nothing was changed.
            $script:PostgresInstallerRan = $false
            $out = $null
            Install-Postgres83 -OutSuperPasswordPlain ([ref]$out) | Should -BeFalse
            $script:F128InstallerCalls | Should -Be 1
            $script:PostgresInstallerRan | Should -BeTrue
            (Get-PostgresInstallFailureView -InstallerRan ([bool]$script:PostgresInstallerRan)).Screen | Should -Match 'Parts of it may now be on this PC'
            # The old line that called a failed install a plain "did not complete successfully" is gone from the screen; the log has the fact.
            @($script:F128Log | Where-Object { $_ -match 'Parts of PostgreSQL may now be on this PC' }).Count | Should -Be 1
        }

        It 'leaves the flag false when the installer was refused before it ran (leftovers found)' {
            # Mutation: set the flag at the top of the function instead of just before the installer call.
            Mock Get-PostgresPartialInstallInventory { [pscustomobject]@{ Found = $true; Objects = @([pscustomobject]@{ Kind = 'Folder'; Description = "Folder 'C:\X'"; PlainDescription = "The PostgreSQL folder 'C:\X'" }) } }
            $script:PostgresInstallerRan = $true
            $out = $null
            Install-Postgres83 -OutSuperPasswordPlain ([ref]$out) | Should -BeFalse
            $script:F128InstallerCalls | Should -Be 0
            $script:PostgresInstallerRan | Should -BeFalse
            (Get-PostgresInstallFailureView -InstallerRan ([bool]$script:PostgresInstallerRan)).Screen | Should -BeExactly 'PostgreSQL was not installed. Nothing was changed.'
        }

        It 'resets the flag at the start of every call (a stale value from an earlier run must not leak)' {
            # Mutation: remove the reset -> a refusal after an earlier failed install still reads "parts may be on this PC".
            Mock Test-RunningAsAdministrator { $false }
            $script:PostgresInstallerRan = $true
            $out = $null
            Install-Postgres83 -OutSuperPasswordPlain ([ref]$out) | Should -BeFalse
            $script:PostgresInstallerRan | Should -BeFalse
        }

        It 'leaves the flag false on a good install' {
            $script:F128ServiceThere = $true
            $out = $null
            Install-Postgres83 -OutSuperPasswordPlain ([ref]$out) | Should -BeTrue
            $script:F128InstallerCalls | Should -Be 1
        }
    }
}

Describe 'FIX128 S8 the leftover-refusal screen warns before it mentions deleting' {
    BeforeEach {
        Reset-F128Capture
        Set-F128Mocks
        $script:F128Inventory = [pscustomobject]@{
            Found = $true
            Objects = @(
                [pscustomobject]@{ Kind = 'InstalledProgram'; Description = "Installed program 'PostgreSQL 8.3' (C:\TPM-Test\PostgreSQL\8.3)"; PlainDescription = "The PostgreSQL program 'PostgreSQL 8.3' (C:\TPM-Test\PostgreSQL\8.3)" }
                [pscustomobject]@{ Kind = 'InstallationRegistration'; Description = 'PostgreSQL installation registration in the Windows registry (HKLM\SOFTWARE\PostgreSQL\Installations)'; PlainDescription = 'A PostgreSQL entry in the Windows settings' }
                [pscustomobject]@{ Kind = 'Service'; Description = "Windows service 'TPMTestPostgres' (Stopped)"; PlainDescription = 'The PostgreSQL background service (it is Stopped)' }
                [pscustomobject]@{ Kind = 'Folder'; Description = "Folder 'C:\TPM-Test\PostgreSQL\8.3'"; PlainDescription = "The PostgreSQL folder 'C:\TPM-Test\PostgreSQL\8.3'" }
                [pscustomobject]@{ Kind = 'WindowsAccount'; Description = "Windows account 'postgres' (SID S-1-5-21-1-2-3-1001)"; PlainDescription = "The Windows user account named 'postgres'" }
            )
        }
    }

    It 'warns about data loss and asks the user to copy a folder first or ask someone, before any delete step' {
        # Mutation: put the old steps back without the warning ("Delete any listed PostgreSQL folder that is still present.").
        Show-PostgresPartialInstallRefusal -Inventory $script:F128Inventory
        $lines = @($script:F128Screen)
        $text = ($lines -join ' ') -replace '\s+', ' '
        $text | Should -Match 'Do not delete anything on this list unless you are sure what it is\.'
        $text | Should -Match 'can hold game databases and saved scores'
        $text | Should -Match 'Deleting it erases them for good'
        $text | Should -Match 'Copy the folder to a safe place first'
        $text | Should -Match 'ask someone who knows computers before you delete or uninstall anything'
        $warningLine = @(0..($lines.Count - 1) | Where-Object { $lines[$_] -match 'Do not delete anything on this list' })[0]
        $firstStep = @(0..($lines.Count - 1) | Where-Object { $lines[$_] -match '^\s+1\) ' })[0]
        $warningLine | Should -BeLessThan $firstStep
        $copyLine = @(0..($lines.Count - 1) | Where-Object { $lines[$_] -match 'Copy the folder to a safe place first' })[0]
        $copyLine | Should -BeLessThan $firstStep
    }

    It 'never tells the user to delete a listed folder without copying it first' {
        # Mutation: step 4 says "Delete any listed PostgreSQL folder that is still present."
        Show-PostgresPartialInstallRefusal -Inventory $script:F128Inventory
        $text = @($script:F128Screen) -join "`n"
        $text | Should -Not -Match '(?i)delete any listed'
        $text | Should -Not -Match '(?i)delete the postgres'
        $step4 = @($script:F128Screen | Where-Object { $_ -match '^\s+4\) ' })
        $step4.Count | Should -Be 1
        $step4[0] | Should -Match 'may hold your data'
        $step4[0] | Should -Match 'Copy it to a safe place before you delete it'
        $step4[0] | Should -Not -Match '^\s+4\) Delete'
    }

    It 'lists the items in plain words; the registry path, the account SID and the service name are only in the log' {
        # Mutation: print Description (the technical text) on the screen again.
        Show-PostgresPartialInstallRefusal -Inventory $script:F128Inventory
        $screen = @($script:F128Screen) -join "`n"
        $screen | Should -Match "The PostgreSQL folder 'C:\\TPM-Test\\PostgreSQL\\8.3'"
        $screen | Should -Match "The Windows user account named 'postgres'"
        $screen | Should -Not -Match 'HKLM|S-1-5-21|SID|TPMTestPostgres|registry'
        $log = @($script:F128Log) -join "`n"
        $log | Should -Match 'S-1-5-21-1-2-3-1001'
        $log | Should -Match 'HKLM\\SOFTWARE\\PostgreSQL\\Installations'
        $log | Should -Match 'TPMTestPostgres'
        @($script:F128Log | Where-Object { $_ -like '*refused*nothing removed*' }).Count | Should -Be 1
    }

    It 'still lists an item that has no plain description (an older inventory object)' {
        # Mutation: print only PlainDescription -> an object without one prints an empty bullet.
        $old = [pscustomobject]@{ Found = $true; Objects = @([pscustomobject]@{ Kind = 'Folder'; Description = "Folder 'C:\Old'" }) }
        Show-PostgresPartialInstallRefusal -Inventory $old
        @($script:F128Screen) | Should -Contain "    - Folder 'C:\Old'"
    }
}

Describe 'FIX128 B3 the Details view of a PostgreSQL setup that did not finish' {
    BeforeEach { Reset-F128Capture; Set-F128Mocks }

    It 'keeps the summary and the reasons in the log, and shows them under Details (one name) only when D is pressed' {
        # Mutation: the Summary is dropped from the log or from Details; or the heading goes back to "Technical details".
        $summary = 'Setup stopped. Everything was put back the way it was, and checked.'
        $script:F128Answers.Enqueue('D')
        Write-TpmPostgresSetupFailure -Result (New-F128Result -Outcome 'ROLLED_BACK_VERIFIED' -ProductState 'UNCHANGED' -Summary $summary) -OfferDetails
        ($script:F128Screen -join "`n") | Should -Not -Match $script:F128Jargon
        ($script:F128Screen -join "`n") | Should -Not -Match 'Error from TOC'
        ($script:F128Log -join "`n") | Should -Match ([regex]::Escape('Postgres setup failure summary: ' + $summary))
        ($script:F128Log -join "`n") | Should -Match 'pg_restore: Error from TOC entry 110'
        $details = @($script:F128Details)
        $details | Should -Contain 'Details'
        $details | Should -Not -Contain 'Technical details'
        $details | Should -Contain ('Result: ' + $summary)
        ($details -join "`n") | Should -Match 'pg_restore: Error from TOC entry 110'
        ($details -join "`n") | Should -Match 'exit code 2'
    }
}

Describe 'FIX128 B3 the main screen of a PostgreSQL setup that did not finish' {
    BeforeEach { Reset-F128Capture; Set-F128Mocks }

    It 'prints the plain summary line, offers D, and shows nothing technical until D is pressed' {
        # Mutation: print the reasons (tool name, error block, exit code) on the main screen, or open Details without the key.
        $summary = 'Setup stopped. Everything was put back the way it was, and checked.'
        $script:F128Answers.Enqueue('')
        Write-TpmPostgresSetupFailure -Result (New-F128Result -Outcome 'ROLLED_BACK_VERIFIED' -ProductState 'UNCHANGED' -Summary $summary) -OfferDetails
        @($script:F128Screen) | Should -Be @(('  PostgreSQL setup did not complete successfully: ' + $summary))
        @($script:F128Prompts) | Should -Be @('  Press D to see why, or Enter to continue')
        @($script:F128Details).Count | Should -Be 0
        ($script:F128Log -join "`n") | Should -Match 'pg_restore: Error from TOC entry 110'
    }

    It 'points to the log and asks nothing where nothing can be asked (the protected resume window)' {
        # Mutation: prompt in the child window.
        Write-TpmPostgresSetupFailure -Result (New-F128Result -Outcome 'ACTION_REQUIRED' -ProductState 'UNKNOWN' -Summary 'Setup stopped, and TeknoParrot Manager could not check that your data is back as it was. Ask for help before you try again.')
        @($script:F128Prompts).Count | Should -Be 0
        @($script:F128Screen) | Should -Contain '  The log says why.'
        ($script:F128Screen -join "`n") | Should -Not -Match $script:F128Jargon
    }
}

Describe 'FIX128 N9 the rebuild failure screen does not say "blocked" for every non-success' {
    BeforeEach { Reset-F128Capture; Set-F128Mocks }

    It 'says what happened for <Outcome> and offers Details' -TestCases @(
        @{ Outcome = 'ROLLED_BACK_VERIFIED'; State = 'UNCHANGED'; Headline = 'The rebuild did not finish.'; Data = 'back the way it was' }
        @{ Outcome = 'ACTION_REQUIRED'; State = 'UNKNOWN'; Headline = 'The rebuild did not finish.'; Data = 'may be left over' }
        @{ Outcome = 'PARTIAL_APPLIED'; State = 'PARTIAL_KNOWN'; Headline = 'The rebuild worked for some of the games but not for all of them.'; Data = 'some were not' }
    ) {
        param($Outcome, $State, $Headline, $Data)
        # Mutation: print "PostgreSQL reinitialize blocked: <Summary>" for every result that is not SUCCEEDED.
        $script:F128Answers.Enqueue('')
        Write-PostgresReinitializeFailure -Result (New-F128Result -Outcome $Outcome -ProductState $State -Summary 'The rebuild did not finish.') -SuperPasswordPlain 'Secret-128' -OfferDetails
        $screen = @($script:F128Screen)
        $screen[0] | Should -BeExactly ('  ' + $Headline)
        $screen[1] | Should -Match ([regex]::Escape($Data))
        ($screen -join "`n") | Should -Not -Match $script:F128Jargon
        @($script:F128Prompts) | Should -Be @('  Press D for details, or Enter to continue')
    }

    It 'says "did not start" and "Nothing was changed." when the rebuild stopped before it changed anything' {
        # Mutation: call a stop before any change "blocked".
        $result = New-F128Result -Outcome 'FAILED_BEFORE_MUTATION' -ProductState 'UNCHANGED' -Summary 'The rebuild did not start because the safety copy could not be made. Nothing was changed.'
        Write-PostgresReinitializeFailure -Result $result -OfferDetails
        $script:F128Screen[0] | Should -BeExactly '  The rebuild did not start because the safety copy could not be made. Nothing was changed.'
        ($script:F128Screen -join "`n") | Should -Not -Match '(?i)blocked|verified'
    }

    It 'shows the redacted reasons under Details and in the log, never the password' {
        # Mutation: skip the redaction on the way to the Details view or the log.
        $result = New-F128Result -Outcome 'ACTION_REQUIRED' -ProductState 'UNKNOWN'
        $result | Add-Member -NotePropertyName Errors -NotePropertyValue @('createdb failed with password=Secret-128 in the text') -Force
        $script:F128Answers.Enqueue('D')
        Write-PostgresReinitializeFailure -Result $result -SuperPasswordPlain 'Secret-128' -OfferDetails
        $details = $script:F128Details -join "`n"
        $details | Should -Match 'createdb failed with password=\[REDACTED\]'
        $details | Should -Not -Match 'Secret-128'
        ($script:F128Log -join "`n") | Should -Match 'createdb failed with password=\[REDACTED\]'
        ($script:F128Log -join "`n") | Should -Not -Match 'Secret-128'
        @($script:F128Details) | Should -Contain 'Details'
        @($script:F128Details) | Should -Not -Contain 'Technical details'
        ($script:F128Screen -join "`n") | Should -Not -Match 'createdb|Secret-128'
    }

    It 'points to the log and asks nothing where nothing can be asked (the protected resume window)' {
        # Mutation: prompt in the child window.
        Write-PostgresReinitializeFailure -Result (New-F128Result -Outcome 'ROLLED_BACK_VERIFIED' -ProductState 'UNCHANGED')
        @($script:F128Prompts).Count | Should -Be 0
        @($script:F128Screen) | Should -Contain '  The log has more.'
    }

    Context 'the whole guided choice' {
        BeforeEach {
            $script:F128Backup = Join-Path $TestDrive ('f128-reinit-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.backup')
            Set-Content -LiteralPath $script:F128Backup -Value 'backup'
            $script:F128Plan = [pscustomobject]@{ GameLabel = 'Game A'; ProfileName = 'GameA'; Database = 'GameDbA'; BackupFile = $script:F128Backup; Encoding = 'UTF8' }
            Mock Get-PostgresReinitializePlansFromProfiles { @($script:F128Plan) }
            Mock Test-RunningAsAdministrator { $true }
            Mock Invoke-TpmProgressGroup { & $Action }
            Mock Test-PostgresReinitializePlan { $true }
        }

        It 'does not call a verified rollback "blocked", and reports that data may have changed' {
            # Mutation: throw the Summary and print it after "blocked:"; or return DatabaseMayHaveChanged = $false.
            Mock Reset-PostgresDatabaseFromBackup { [pscustomobject]@{ Outcome = 'ROLLED_BACK_VERIFIED'; Items = @('GameDbA'); Succeeded = $false; RestoredOriginal = $true; Reason = '' } }
            $script:F128Answers.Enqueue('YES')
            $script:F128Answers.Enqueue('')
            $result = Invoke-PostgresReinitializeChoice -FailureDiagnoses @([pscustomobject]@{ Database = 'GameDbA' }) -UserProfilesDir $TestDrive -ConfigPath (Join-Path $TestDrive 'config.json') -ScriptPath (Join-Path $TestDrive 'script.ps1') -TpRoot $TestDrive -SuperPasswordPlain 'Secret-128' -RecoveryBackup ([pscustomobject]@{ Path = $TestDrive; Verified = $true })
            $result.Outcome | Should -BeExactly 'Blocked'
            $result.DatabaseMayHaveChanged | Should -BeTrue
            $result.Error | Should -Match 'put back and checked'
            $failureText = @($script:F128Screen | Where-Object { $_ -match 'rebuild' }) -join "`n"
            $failureText | Should -Match 'The rebuild did not finish\.'
            ($script:F128Screen -join "`n") | Should -Not -Match '(?i)reinitialize blocked|previous database state|verified'
            ($script:F128Screen -join "`n") | Should -Match 'back the way it was'
        }

        It 'says data may have been changed, not "nothing was changed", when the rebuild itself stops unexpectedly' {
            # Mutation: report the unexpected stop as "Nothing was changed.".
            Mock Invoke-TpmProgressGroup { throw 'engine failure password=Secret-128' }
            $script:F128Answers.Enqueue('YES')
            $result = Invoke-PostgresReinitializeChoice -FailureDiagnoses @([pscustomobject]@{ Database = 'GameDbA' }) -UserProfilesDir $TestDrive -ConfigPath (Join-Path $TestDrive 'config.json') -ScriptPath (Join-Path $TestDrive 'script.ps1') -TpRoot $TestDrive -SuperPasswordPlain 'Secret-128' -RecoveryBackup ([pscustomobject]@{ Path = $TestDrive; Verified = $true })
            $result.Outcome | Should -BeExactly 'Blocked'
            $result.DatabaseMayHaveChanged | Should -BeTrue
            $result.Error | Should -Not -Match 'Secret-128'
            $screen = $script:F128Screen -join "`n"
            $screen | Should -Match 'may have been changed'
            $screen | Should -Not -Match 'Nothing was changed|Secret-128'
            ($script:F128Log -join "`n") | Should -Not -Match 'Secret-128'
        }

        It 'does not mark a stop before any change as a change' {
            # Mutation: set DatabaseMayHaveChanged for every failure -> a later "nothing was changed" claim is never made.
            Mock Invoke-PostgresReinitializePlan { New-F128Result -Outcome 'FAILED_BEFORE_MUTATION' -ProductState 'UNCHANGED' -Summary 'The rebuild did not start because your games changed. Nothing was changed.' }
            $script:F128Answers.Enqueue('YES')
            $script:F128Answers.Enqueue('')
            $result = Invoke-PostgresReinitializeChoice -FailureDiagnoses @([pscustomobject]@{ Database = 'GameDbA' }) -UserProfilesDir $TestDrive -ConfigPath (Join-Path $TestDrive 'config.json') -ScriptPath (Join-Path $TestDrive 'script.ps1') -TpRoot $TestDrive -SuperPasswordPlain 'Secret-128' -RecoveryBackup ([pscustomobject]@{ Path = $TestDrive; Verified = $true })
            $result.Outcome | Should -BeExactly 'Blocked'
            $result.DatabaseMayHaveChanged | Should -BeFalse
            @($script:F128Screen) | Should -Contain '  The rebuild did not start because your games changed. Nothing was changed.'
        }
    }
}

Describe 'FIX128 the summaries a rebuild result carries are plain words' {
    BeforeEach {
        Reset-F128Capture
        Set-F128Mocks
        $script:F128Backup = Join-Path $TestDrive ('f128-plan-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.backup')
        Set-Content -LiteralPath $script:F128Backup -Value 'backup'
        $script:F128Plan = [pscustomobject]@{ GameLabel = 'Game A'; ProfileName = 'GameA'; Database = 'GameDbA'; BackupFile = $script:F128Backup; Encoding = 'UTF8' }
        $script:F128Json = ConvertTo-PostgresReinitializePlanJson -Plans @($script:F128Plan)
        $script:F128Hash = Get-PostgresReinitializePlanHash -PlanJson $script:F128Json
        Mock Get-PostgresReinitializePlansFromProfiles { @($script:F128Plan) }
    }

    It 'says "put back and checked" for a rolled-back rebuild and "could not check" for an unchecked one' {
        # Mutation: the old "The previous database state was restored and verified." / "...final state could not be verified." summaries.
        Mock Reset-PostgresDatabaseFromBackup { [pscustomobject]@{ Outcome = 'ROLLED_BACK_VERIFIED'; Items = @('GameDbA'); Succeeded = $false; RestoredOriginal = $true; Reason = '' } }
        $rolledBack = Invoke-PostgresReinitializePlan -PlanJson $script:F128Json -PlanHash $script:F128Hash -UserProfilesDir $TestDrive -SuperPasswordPlain 'x' -RecoveryBackup ([pscustomobject]@{ Path = $TestDrive; Verified = $true })
        $rolledBack.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        $rolledBack.Summary | Should -BeExactly 'The rebuild did not finish. Your old data was put back and checked.'
        Mock Reset-PostgresDatabaseFromBackup { [pscustomobject]@{ Succeeded = $false; RestoredOriginal = $false; Reason = 'destructive reset failed' } }
        $unchecked = Invoke-PostgresReinitializePlan -PlanJson $script:F128Json -PlanHash $script:F128Hash -UserProfilesDir $TestDrive -SuperPasswordPlain 'x' -RecoveryBackup ([pscustomobject]@{ Path = $TestDrive; Verified = $true })
        $unchecked.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $unchecked.Summary | Should -Match 'could not check that your data is back as it was'
        $unchecked.Summary | Should -Match 'Ask for help'
        foreach ($summary in @($rolledBack.Summary, $unchecked.Summary)) { $summary | Should -Not -Match $script:F128Jargon }
    }

    It 'says "did not start ... Nothing was changed." for a stop before the first change' {
        # Mutation: "stopped before a database change because verified recovery evidence was unavailable".
        Mock Reset-PostgresDatabaseFromBackup { throw 'must not run' }
        $result = Invoke-PostgresReinitializePlan -PlanJson $script:F128Json -PlanHash $script:F128Hash -UserProfilesDir $TestDrive -SuperPasswordPlain 'x' -RecoveryBackup ([pscustomobject]@{ Path = $TestDrive; Verified = $false })
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.Summary | Should -BeExactly 'The rebuild did not start because the safety copy could not be made. Nothing was changed.'
        $result.Summary | Should -Not -Match $script:F128Jargon
    }
}

Describe 'FIX128 the PostgreSQL restore screen' {
    BeforeEach {
        Reset-F128Capture
        Set-F128Mocks
        $script:F128Root = Join-Path $TestDrive ('f128-restore-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $folder = Join-Path $script:F128Root '2026-11-01_10-00-00_000_fixture'
        [void][System.IO.Directory]::CreateDirectory($folder)
        [System.IO.File]::WriteAllText((Join-Path $folder 'GameDB01.backup'), 'backup')
        Mock Test-PostgresManualRecoveryRequired { $false }
        Mock Test-PostgresInstalled { $false }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-TpmChoice { '1' }
    }

    It 'says "<Expect>" and never "<Banned>" for <Outcome> / <State>' -TestCases @(
        @{ Outcome = 'ROLLED_BACK_VERIFIED'; State = 'UNCHANGED'; Expect = 'The restore did not finish. Your data is back the way it was.'; Banned = 'Previous database state' }
        @{ Outcome = 'ACTION_REQUIRED'; State = 'UNKNOWN'; Expect = 'The restore did not finish. Some changes may be left over.'; Banned = 'could not be verified' }
        @{ Outcome = 'ACTION_REQUIRED'; State = 'UNCHANGED'; Expect = 'Your databases were not changed, but some temporary files were left behind.'; Banned = 'could not be verified' }
        @{ Outcome = 'CLEANUP_RESIDUE'; State = 'INTENDED'; Expect = 'some leftover files need cleaning up'; Banned = 'verified state' }
    ) {
        param($Outcome, $State, $Expect, $Banned)
        # Mutation: the old lines "Restore did not finish. Previous database state was restored and verified." / "Restore needs attention.
        # Previous database state could not be verified." (the same words for a cleanup problem that left the databases alone).
        $tx = [pscustomobject]@{ Outcome = $Outcome; ProductState = $State; ReasonCode = 'FIXTURE'; TechnicalDetails = [pscustomobject]@{ EvidenceRoot = 'C:\Evidence'; KeptDatabaseBackups = @() }; DatabaseReceipts = @() }
        Mock Invoke-PostgresRestoreTransaction { $tx }.GetNewClosure()
        $script:F128Answers.Enqueue('YES')
        $script:F128Answers.Enqueue('')
        [void](Invoke-RestorePostgresBackup -BackupRoot $script:F128Root)
        # The backup menu above the result lists the databases by their names (existing behavior), so the jargon check starts after the warning.
        $afterWarning = @($script:F128Screen | Select-Object -Skip (1 + [array]::IndexOf(@($script:F128Screen), '             and keeps that copy after a good restore.')))
        $afterWarning.Count | Should -BeGreaterThan 0
        $screen = $script:F128Screen -join "`n"
        $screen | Should -Match ([regex]::Escape($Expect))
        $screen | Should -Not -Match ([regex]::Escape($Banned))
        ($afterWarning -join "`n") | Should -Not -Match $script:F128Jargon
        @($script:F128Prompts) | Should -Contain '  Press D for details, or Enter to continue'
    }

    It 'names the screen that D opens "Details" and shows the receipts there' {
        # Mutation: the heading goes back to "Technical details" (two names for one screen).
        $receipt = [pscustomobject]@{ Database = 'GameDB01'; Succeeded = $false; RollbackVerified = $true; FailureStage = 'Restore'; Error = 'pg_restore ended with exit code 2'; RollbackError = '' }
        $tx = [pscustomobject]@{ Outcome = 'ROLLED_BACK_VERIFIED'; ProductState = 'UNCHANGED'; ReasonCode = 'ROLLED_BACK_VERIFIED'; TechnicalDetails = [pscustomobject]@{ EvidenceRoot = 'C:\Evidence'; KeptDatabaseBackups = @() }; DatabaseReceipts = @($receipt) }
        Mock Invoke-PostgresRestoreTransaction { $tx }.GetNewClosure()
        $script:F128Answers.Enqueue('YES')
        $script:F128Answers.Enqueue('d')
        [void](Invoke-RestorePostgresBackup -BackupRoot $script:F128Root)
        @($script:F128Details) | Should -Contain 'Details'
        @($script:F128Details) | Should -Not -Contain 'Technical details'
        @($script:F128Details) | Should -Contain 'Error: pg_restore ended with exit code 2'
        ($script:F128Screen -join "`n") | Should -Not -Match 'pg_restore|exit code'
    }

    It 'does not print the raw reason on the restore screen when the restore did not finish' {
        # Mutation: print the receipt error (tool name and exit code) on the main restore screen again.
        $receipt = [pscustomobject]@{ Database = 'GameDB01'; Succeeded = $false; RollbackVerified = $true; FailureStage = 'Restore'; Error = 'pg_restore ended with exit code 2'; RollbackError = '' }
        $tx = [pscustomobject]@{ Outcome = 'ROLLED_BACK_VERIFIED'; ProductState = 'UNCHANGED'; ReasonCode = 'ROLLED_BACK_VERIFIED'; TechnicalDetails = [pscustomobject]@{ EvidenceRoot = 'C:\Evidence'; KeptDatabaseBackups = @() }; DatabaseReceipts = @($receipt) }
        Mock Invoke-PostgresRestoreTransaction { $tx }.GetNewClosure()
        $script:F128Answers.Enqueue('YES')
        $script:F128Answers.Enqueue('')
        [void](Invoke-RestorePostgresBackup -BackupRoot $script:F128Root)
        ($script:F128Screen -join "`n") | Should -Not -Match 'pg_restore|exit code|GameDB01 '
        @($script:F128Details).Count | Should -Be 0
    }
}

Describe 'FIX128 the recovery action labels (footer of a failed PostgreSQL setup) are plain words' {
    It 'says plain words for <Id>' -TestCases @(
        @{ Id = 'postgres-scan' }, @{ Id = 'postgres-install-handoff' }, @{ Id = 'postgres-service-state' }, @{ Id = 'postgres-install-failed' }
        @{ Id = 'postgres-backup-unverified' }, @{ Id = 'postgres-profile-recovery' }, @{ Id = 'postgres-profile-errors' }, @{ Id = 'postgres-service-restore' }
        @{ Id = 'postgres-manual-recovery' }, @{ Id = 'postgres-transaction-result' }, @{ Id = 'postgres-transaction-failed' }
    ) {
        param($Id)
        # Mutation: bring back "without claiming PostgreSQL setup complete", "correcting the reported issue", "verified backup", "authentication policy".
        $actions = @(Get-PostgresRecoveryActions -FailureId $Id)
        $actions.Count | Should -Be 2
        foreach ($action in $actions) {
            [string]$action.Label | Should -Not -Match '(?i)claim|protected|authentication policy|verified|evidence|reported issue|profile setup'
            [string]$action.Label | Should -Not -BeNullOrEmpty
        }
        @($actions | Where-Object { $_.Id -eq 'Stop' })[0].Label | Should -BeExactly 'Go back to the menu. PostgreSQL setup is not finished.'
    }
}

Describe 'FIX128 B3 a PostgreSQL failure branch offers Details (D) when it has technical lines' {
    BeforeEach {
        Reset-F128Capture
        Set-F128Mocks
        $script:F128Context = [pscustomobject]@{ Failure = [pscustomobject]@{ FailureId = 'postgres-install-failed' } }
        Mock Acknowledge-TpmWorkflowFailure {}
        Mock Stop-TpmWorkflowStatus {}
        Mock Close-TpmWorkflowStatus {}
    }

    It 'asks "Press D for details", shows the lines only after D, and writes them to the log' {
        # Mutation: ignore -DetailBlocks (the old "Press Enter to acknowledge this result" with no key), or show the lines without D.
        $blocks = @(@{ Heading = 'What happened'; Lines = @('Installer ran: yes', 'Reason: The Windows installer did not leave a working PostgreSQL service.') })
        $script:F128Answers.Enqueue('')
        Resolve-TpmWorkflowFailure -Context $script:F128Context -FailureId 'postgres-install-failed' -Message 'PostgreSQL did not finish installing.' -DataSafety 'x' -DetailBlocks $blocks -Acknowledge
        @($script:F128Prompts) | Should -Be @('  Press D for details, or Enter to acknowledge this result')
        @($script:F128Details).Count | Should -Be 0
        ($script:F128Log -join "`n") | Should -Match 'Failure detail \[postgres-install-failed\] \[What happened\]: Installer ran: yes'

        Reset-F128Capture
        $script:F128Answers.Enqueue('D')
        $script:F128Answers.Enqueue('')
        Resolve-TpmWorkflowFailure -Context $script:F128Context -FailureId 'postgres-install-failed' -Message 'PostgreSQL did not finish installing.' -DataSafety 'x' -DetailBlocks $blocks -Acknowledge
        @($script:F128Prompts).Count | Should -Be 2
        @($script:F128Details) | Should -Contain 'What happened'
        @($script:F128Details) | Should -Contain 'Installer ran: yes'
        Should -Invoke Acknowledge-TpmWorkflowFailure -Times 2 -Exactly
    }

    It 'keeps the plain "press Enter" question when there is nothing technical to show' {
        # Mutation: always offer D (an empty Details screen).
        $script:F128Answers.Enqueue('d')
        Resolve-TpmWorkflowFailure -Context $script:F128Context -FailureId 'postgres-install-failed' -Message 'm' -DataSafety 'x' -Acknowledge
        @($script:F128Prompts) | Should -Be @('  Press Enter to acknowledge this result')
        @($script:F128Details).Count | Should -Be 0
    }
}
