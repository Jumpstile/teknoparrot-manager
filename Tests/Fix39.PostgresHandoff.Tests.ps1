#Requires -Module Pester

# FIX39 PostgreSQL elevated hand-off (owner report 2026-11-01): the elevated
# child closes by itself and reports a structured result; the original window
# shows one accurate message and never offers "Try again" for a used request.
# The production script is parsed and only its function definitions are
# dot-sourced; no top-level product code runs in this process. The elevated
# child is simulated by a plain child PowerShell built from the same function
# text, with prompts replaced by stubs that record a call and exit 88. No real
# elevation, PostgreSQL, service, registry or user configuration is touched;
# every file lives under TestDrive. Each It names the product mutation that
# makes it fail.

BeforeAll {
    $script:Fix39PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix39PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $script:Fix39Ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX39 tests could not parse the production script.' }
    $functionText = @($script:Fix39Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix39FunctionFile = Join-Path $TestDrive 'tpm-fix39-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix39FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix39FunctionFile
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $script:logPath = Join-Path $TestDrive 'fix39.log'
    $script:Fix39Engine = (Get-Process -Id $PID).Path

    $script:Fix39OwnerMessage = 'The PostgreSQL password was not changed. The database backup could not be completed (see View Log). Nothing else was changed.'

    function New-Fix39StatePath {
        param([Parameter(Mandatory)][string]$Directory)
        [void][System.IO.Directory]::CreateDirectory($Directory)
        return (Join-Path $Directory ('.tpm-postgres-recovery-' + [guid]::NewGuid().ToString('N') + '.json'))
    }

    # What the elevated child records when it stops after the database backup failed.
    function New-Fix39OwnerResumeState {
        param([Parameter(Mandatory)][string]$StatePath)
        return [pscustomobject]@{
            Path = $StatePath; ClaimPath = ($StatePath + '.claim'); Operation = 'Recovery'
            DatabaseBackupSucceeded = $false
        }
    }

    # The result the elevated child writes when it stops after the database backup failed.
    function New-Fix39OwnerResult {
        return (New-PostgresRecoveryHandoffResult -ResumeState (New-Fix39OwnerResumeState -StatePath $script:Fix39StatePath))
    }

    # Stands in for the Process object Start-Process -PassThru returns.
    function New-Fix39FakeProcess {
        param([int]$ExitCode, [int]$Id = $PID)
        $process = [pscustomobject]@{ ExitCode = $ExitCode; Id = $Id }
        $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($Milliseconds) return $true }
        return $process
    }

    function Invoke-Fix39Handoff {
        param([ref]$Report)
        Start-PostgresRecoveryAsAdministrator -ConfigPath (Join-Path $TestDrive 'config.json') -ScriptPath (Join-Path $TestDrive 'TeknoParrot-Manager.ps1') `
            -TpRoot $TestDrive -UserProfilesDir (Join-Path $TestDrive 'UserProfiles') -Operation Recovery -PasswordPlain 'Fixture-New-Pass-1' -HandoffReport $Report
    }

    function Write-Fix39Result {
        param($ResumeState, $Result, [switch]$Completed, [bool]$RetryIssued = $false)
        if (-not $Result) { $Result = New-PostgresRecoveryHandoffResult -ResumeState $ResumeState -Completed:$Completed -RetryIssued $RetryIssued }
        if (-not (Write-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -Result $Result)) { throw 'fixture result was not written' }
    }

    # Runs one terminal call of the protected-resume child in a separate
    # PowerShell process: the real product functions, prompts replaced by stubs
    # that print PROMPT_CALLED and exit 88, LOCALAPPDATA inside TestDrive.
    function Invoke-Fix39ChildTerminal {
        param(
            [Parameter(Mandatory)][string]$LocalAppData,
            [Parameter(Mandatory)][string]$StatePath,
            [Parameter(Mandatory)][string]$ResumeStateText,
            [Parameter(Mandatory)][string]$CallText
        )
        $harnessPath = Join-Path $TestDrive ('fix39-child-' + [guid]::NewGuid().ToString('N') + '.ps1')
        $harness = @(
            "`$ErrorActionPreference = 'Stop'"
            ("`$env:LOCALAPPDATA = '{0}'" -f $LocalAppData.Replace("'", "''"))
            (". '{0}'" -f $script:Fix39FunctionFile.Replace("'", "''"))
            'function Write-Log { param([object]$Message) }'
            'function Read-Host { [Console]::Out.WriteLine(''PROMPT_CALLED''); exit 88 }'
            'function Read-HostSafe { [Console]::Out.WriteLine(''PROMPT_CALLED''); exit 88 }'
            'function Read-TpmYesNo { [Console]::Out.WriteLine(''PROMPT_CALLED''); exit 88 }'
            'function Read-TpmChoice { [Console]::Out.WriteLine(''PROMPT_CALLED''); exit 88 }'
            'function New-PostgresRecoveryRetryState { param($State) [Console]::Out.WriteLine(''RETRY_STATE_ISSUED''); return $null }'
            '$script:PostgresRecoveryStatus = $null'
            ("`$script:PostgresRecoveryResumeToken = '{0}'" -f $StatePath.Replace("'", "''"))
            ('$script:PostgresRecoveryResumeState = ' + $ResumeStateText)
            $CallText
            '[Console]::Out.WriteLine(''FELL_THROUGH'')'
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($harnessPath, $harness, (New-Object System.Text.UTF8Encoding $false))
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $script:Fix39Engine
        $startInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $harnessPath + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) {
            try { $process.Kill() } catch {}
            throw 'The FIX39 child did not exit within the timeout (it may be waiting for a key press).'
        }
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            Id       = [int]$process.Id
            Output   = $stdoutTask.GetAwaiter().GetResult() + [Environment]::NewLine + $stderrTask.GetAwaiter().GetResult()
        }
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix39PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX39 elevated PostgreSQL hand-off' {
    Context 'elevated child closes by itself and reports its result' {
        BeforeEach {
            $script:Fix39LocalAppData = Join-Path $TestDrive ('local-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $script:Fix39StateDir = Join-Path $script:Fix39LocalAppData 'TeknoParrotManager\Recovery'
            $script:Fix39StatePath = New-Fix39StatePath -Directory $script:Fix39StateDir
            Mock Get-PostgresRecoveryStateDirectory { $script:Fix39StateDir }
            Mock Write-Log {}
        }

        # Mutations: a Read-Host/Read-HostSafe/Read-TpmYesNo in Exit-PostgresRecoveryResume
        # (PROMPT_CALLED, exit 88), dropping "$ExitCode = 0" after a verified result
        # (exit 1 keeps a Windows Terminal window open), or dropping the result write.
        It 'stops after a failed backup with exit code 0, no prompt, and a result the original window can read' {
            $resumeText = "[pscustomobject]@{ Path = `$script:PostgresRecoveryResumeToken; ClaimPath = (`$script:PostgresRecoveryResumeToken + '.claim'); Operation = 'Recovery'; NoRetry = `$true; DatabaseBackupSucceeded = `$false }"
            $run = Invoke-Fix39ChildTerminal -LocalAppData $script:Fix39LocalAppData -StatePath $script:Fix39StatePath -ResumeStateText $resumeText -CallText "Exit-PostgresRecoveryResume -Message 'TeknoParrot Manager could not finish the PostgreSQL database backup.'"

            $run.ExitCode | Should -Be 0 -Because $run.Output
            $run.Output | Should -Not -Match 'PROMPT_CALLED|RETRY_STATE_ISSUED|FELL_THROUGH'
            $read = Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -ChildProcessId $run.Id
            $read.Valid | Should -BeTrue -Because $read.Reason
            $read.Result.Outcome | Should -Be 'StoppedNoPasswordChange'
            $read.Result.StageReached | Should -Be 'DatabaseBackupFailed'
            $read.Result.BackupSucceeded | Should -BeFalse
            $read.Result.NothingElseChanged | Should -BeTrue
            $read.Result.RetryIssued | Should -BeFalse
        }

        # Mutation: issue a protected retry after an unexpected error, or say "nothing else
        # was changed" when the outcome is unknown.
        It 'reports an unexpected error as an unknown change, issues no retry and still closes without a prompt' {
            $resumeText = "[pscustomobject]@{ Path = `$script:PostgresRecoveryResumeToken; ClaimPath = (`$script:PostgresRecoveryResumeToken + '.claim'); Operation = 'Recovery' }"
            $run = Invoke-Fix39ChildTerminal -LocalAppData $script:Fix39LocalAppData -StatePath $script:Fix39StatePath -ResumeStateText $resumeText -CallText "Exit-PostgresRecoveryResume -Message 'fixture unexpected error' -UnexpectedError"

            $run.ExitCode | Should -Be 0 -Because $run.Output
            $run.Output | Should -Not -Match 'PROMPT_CALLED|RETRY_STATE_ISSUED|FELL_THROUGH'
            $read = Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -ChildProcessId $run.Id
            $read.Valid | Should -BeTrue -Because $read.Reason
            $read.Result.Outcome | Should -Be 'StoppedUnexpectedError'
            (Get-PostgresRecoveryHandoffMessage -Result $read.Result).Text | Should -Match 'cannot confirm what was changed'
        }

        # Mutation: Exit-PostgresRecoveryResumeSuccess prompts, or exits before
        # writing the Completed result the original window now requires.
        It 'writes a Completed result and exits 0 without a prompt after a finished resume' {
            $resumeText = "[pscustomobject]@{ Path = `$script:PostgresRecoveryResumeToken; ClaimPath = (`$script:PostgresRecoveryResumeToken + '.claim'); Operation = 'Recovery'; DatabaseBackupSucceeded = `$true }"
            $run = Invoke-Fix39ChildTerminal -LocalAppData $script:Fix39LocalAppData -StatePath $script:Fix39StatePath -ResumeStateText $resumeText -CallText 'Exit-PostgresRecoveryResumeSuccess -ResumeState $script:PostgresRecoveryResumeState'

            $run.ExitCode | Should -Be 0 -Because $run.Output
            $run.Output | Should -Not -Match 'PROMPT_CALLED|FELL_THROUGH'
            $read = Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -ChildProcessId $run.Id
            $read.Valid | Should -BeTrue -Because $read.Reason
            $read.Result.Outcome | Should -Be 'Completed'
        }

        # Mutation: remove the protected-resume branch from the top-level fatal
        # catch, or move it after the "Press Enter to exit" Read-Host.
        It 'sends a fatal error in the elevated child to Exit-PostgresRecoveryResume before any Read-Host' {
            $fatalTry = @($script:Fix39Ast.EndBlock.Statements | Where-Object {
                $_ -is [System.Management.Automation.Language.TryStatementAst] -and
                @($_.CatchClauses | Where-Object { $_.Body.Extent.Text -match 'FATAL ERROR -- script aborted' }).Count -gt 0
            })
            $fatalTry.Count | Should -Be 1
            $catchBody = @($fatalTry[0].CatchClauses | Where-Object { $_.Body.Extent.Text -match 'FATAL ERROR -- script aborted' })[0].Body
            $resumeExit = @($catchBody.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Exit-PostgresRecoveryResume' -and
                $args[0].Extent.Text -match '-UnexpectedError'
            }, $true))
            $prompts = @($catchBody.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -in @('Read-Host', 'Read-HostSafe')
            }, $true))
            $resumeExit.Count | Should -Be 1
            $guard = $resumeExit[0].Parent
            while ($guard -and $guard -isnot [System.Management.Automation.Language.IfStatementAst]) { $guard = $guard.Parent }
            $guard | Should -Not -BeNullOrEmpty
            $guard.Clauses[0].Item1.Extent.Text | Should -Be '$isPostgresRecoveryResume'
            foreach ($prompt in $prompts) { $prompt.Extent.StartOffset | Should -BeGreaterThan $guard.Extent.EndOffset }
        }
    }

    Context 'original window after the administrator window ends' {
        BeforeEach {
            $script:Fix39StateDir = Join-Path $TestDrive ('state-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $script:Fix39StatePath = New-Fix39StatePath -Directory $script:Fix39StateDir
            $script:Fix39RetryPath = $null
            $script:Fix39ExitCode = 1
            $script:Fix39BeforeExit = {}
            $script:Fix39MarkerState = 'None'
            $script:Fix39Lines = New-Object System.Collections.Generic.List[string]
            Mock Get-PostgresRecoveryStateDirectory { $script:Fix39StateDir }
            Mock New-PostgresRecoveryState { $script:Fix39StatePath }
            Mock Find-PostgresRecoveryRetryState { $script:Fix39RetryPath }
            Mock Request-TpmConsoleForeground { $false }
            Mock Get-PostgresTrustRuleMarkerState {
                [pscustomobject]@{ State = $script:Fix39MarkerState; LiveState = 'TemporaryTrust'; HbaPath = 'fixture-pg_hba.conf'; BackupHbaPath = 'fixture-backup.conf'; OriginalSha256 = 'fixture-hash'; MarkerPath = 'fixture-marker.json'; Reason = 'fixture' }
            }
            Mock Write-Log {}
            Mock Write-Host { $script:Fix39Lines.Add(([string]$Object).Trim()) }
            Mock Read-TpmYesNo { 'N' }
            Mock Read-HostSafe { '' }
            Mock Start-Process {
                & $script:Fix39BeforeExit
                New-Fix39FakeProcess -ExitCode $script:Fix39ExitCode
            }
        }

        # Mutations: show the old "Windows allowed ... did not finish" text or the
        # fallback notice as well, or prompt "Try again? (Y/N)" for this used request.
        It 'shows the one backup-failed message and no Try again for the owner case' {
            $script:Fix39ExitCode = 0
            $script:Fix39BeforeExit = { Write-Fix39Result -Result (New-Fix39OwnerResult) }
            $report = $null

            $elevated = Invoke-Fix39Handoff -Report ([ref]$report)

            $elevated | Should -BeFalse
            @($script:Fix39Lines | Where-Object { $_ -eq $script:Fix39OwnerMessage }).Count | Should -Be 1 -Because ($script:Fix39Lines -join ' | ')
            @($script:Fix39Lines | Where-Object { $_ -match 'Try again|did not finish\.|could not read a valid result|used this repair request' }).Count | Should -Be 0 -Because ($script:Fix39Lines -join ' | ')
            Should -Invoke Read-TpmYesNo -Times 0 -Exactly
            Should -Invoke Read-HostSafe -Times 0 -Exactly
            (Test-Path -LiteralPath ($script:Fix39StatePath + '.result')) | Should -BeFalse
        }

        # Mutation: keep "Nothing else was changed" while the original window's
        # read-only check still finds an unfinished repair (temporary trust rule).
        It 'replaces "Nothing else was changed" with the manual-recovery guidance when a repair marker remains' {
            $script:Fix39ExitCode = 0
            $script:Fix39MarkerState = 'Required'
            $script:Fix39BeforeExit = { Write-Fix39Result -Result (New-Fix39OwnerResult) }
            $report = $null

            [void](Invoke-Fix39Handoff -Report ([ref]$report))

            $report.Text | Should -Not -Match 'Nothing else was changed'
            $report.Text | Should -Match 'Stop the PostgreSQL service first'
            Should -Invoke Get-PostgresTrustRuleMarkerState -Times 1 -Exactly -ParameterFilter { $ReadOnly }
        }

        # Mutation: restore the unconditional "Try again? (Y/N)" after a used request.
        It 'never offers Try again when the request was used and no result or fresh retry exists' {
            $report = $null

            $elevated = Invoke-Fix39Handoff -Report ([ref]$report)

            $elevated | Should -BeFalse
            Should -Invoke Read-TpmYesNo -Times 0 -Exactly
            Should -Invoke Read-HostSafe -Times 0 -Exactly
            $report | Should -BeNullOrEmpty
            @($script:Fix39Lines | Where-Object { $_ -match 'used this repair request and cannot retry it' }).Count | Should -Be 1
        }

        # Mutation: drop the unexpected-error check, so a retry found after an unknown
        # outcome is offered (a second run becomes possible).
        It 'removes and never offers a protected retry found after an unexpected error' {
            $script:Fix39RetryPath = New-Fix39StatePath -Directory $script:Fix39StateDir
            [System.IO.File]::WriteAllText($script:Fix39RetryPath, '{}')
            $script:Fix39ExitCode = 0
            $script:Fix39BeforeExit = { Write-Fix39Result -Result (New-PostgresRecoveryHandoffResult -ResumeState (New-Fix39OwnerResumeState -StatePath $script:Fix39StatePath) -UnexpectedError) }
            $report = $null

            [void](Invoke-Fix39Handoff -Report ([ref]$report))

            Should -Invoke Read-TpmYesNo -Times 0 -Exactly
            Should -Invoke Start-Process -Times 1 -Exactly
            (Test-Path -LiteralPath $script:Fix39RetryPath) | Should -BeFalse
        }

        # Control for the two tests above: a request the child never used can
        # still be retried. Mutation: never offer Try again at all.
        It 'still offers Try again while the protected request is unused' {
            [System.IO.File]::WriteAllText($script:Fix39StatePath, '{}')

            [void](Invoke-Fix39Handoff -Report ([ref]$null))

            Should -Invoke Read-TpmYesNo -Times 1 -Exactly
            (Test-Path -LiteralPath $script:Fix39StatePath) | Should -BeFalse
        }

        # Wrong-account case: the administrator window never reads the request, so
        # it stays unused. Mutation: remove the cap and the user is asked again. The
        # mock answers Y once and N after, so a missing cap fails here and cannot hang.
        It 'stops offering Try again after one failed retry when the request stays unused' {
            [System.IO.File]::WriteAllText($script:Fix39StatePath, '{}')
            $script:Fix39YesNoCalls = 0
            Mock Read-TpmYesNo { $script:Fix39YesNoCalls++; if ($script:Fix39YesNoCalls -eq 1) { 'Y' } else { 'N' } }

            Invoke-Fix39Handoff -Report ([ref]$null) | Should -BeFalse

            Should -Invoke Read-TpmYesNo -Times 1 -Exactly
            Should -Invoke Start-Process -Times 2 -Exactly
            @($script:Fix39Lines | Where-Object { $_ -match 'different account' }).Count | Should -Be 1 -Because ($script:Fix39Lines -join ' | ')
            @($script:Fix39Lines | Where-Object { $_ -match 'Run as administrator' }).Count | Should -Be 1 -Because ($script:Fix39Lines -join ' | ')
            (Test-Path -LiteralPath $script:Fix39StatePath) | Should -BeFalse
        }

        # Mutation: blame a different account for every cause. A user who canceled
        # the Windows box twice must be told that, not that another account was used.
        It 'tells the user the box was canceled, not that a different account was used, after two cancels' {
            [System.IO.File]::WriteAllText($script:Fix39StatePath, '{}')
            $script:Fix39YesNoCalls = 0
            Mock Read-TpmYesNo { $script:Fix39YesNoCalls++; if ($script:Fix39YesNoCalls -eq 1) { 'Y' } else { 'N' } }
            Mock Start-Process { throw ([System.ComponentModel.Win32Exception]::new(1223)) }

            Invoke-Fix39Handoff -Report ([ref]$null) | Should -BeFalse

            Should -Invoke Read-TpmYesNo -Times 1 -Exactly
            Should -Invoke Start-Process -Times 2 -Exactly
            @($script:Fix39Lines | Where-Object { $_ -match 'different account' }).Count | Should -Be 0 -Because ($script:Fix39Lines -join ' | ')
            @($script:Fix39Lines | Where-Object { $_ -match 'was canceled\. Nothing was changed' }).Count | Should -Be 1 -Because ($script:Fix39Lines -join ' | ')
            @($script:Fix39Lines | Where-Object { $_ -match 'Run as administrator' }).Count | Should -Be 1 -Because ($script:Fix39Lines -join ' | ')
            (Test-Path -LiteralPath $script:Fix39StatePath) | Should -BeFalse
        }

        # Mutation: drop the "valid result" branch of the stop message, so a user whose
        # administrator window reported a problem is told a different account was used.
        It 'says setup did not finish, with the reason shown, and never blames a different account when a result was read twice' {
            [System.IO.File]::WriteAllText($script:Fix39StatePath, '{}')
            $script:Fix39ExitCode = 0
            $script:Fix39Resume = [pscustomobject]@{ Path = $script:Fix39StatePath; ClaimPath = ($script:Fix39StatePath + '.claim'); Operation = 'Recovery' }
            $script:Fix39BeforeExit = { Write-Fix39Result -ResumeState $script:Fix39Resume }
            $script:Fix39YesNoCalls = 0
            Mock Read-TpmYesNo { $script:Fix39YesNoCalls++; if ($script:Fix39YesNoCalls -eq 1) { 'Y' } else { 'N' } }

            Invoke-Fix39Handoff -Report ([ref]$null) | Should -BeFalse

            Should -Invoke Start-Process -Times 2 -Exactly
            @($script:Fix39Lines | Where-Object { $_ -match 'did not finish\. The reason is shown above' }).Count | Should -Be 1 -Because ($script:Fix39Lines -join ' | ')
            $expected = (Get-PostgresRecoveryHandoffMessage -Result (New-PostgresRecoveryHandoffResult -ResumeState $script:Fix39Resume)).Text
            @($script:Fix39Lines | Where-Object { $_ -eq $expected }).Count | Should -BeGreaterThan 0 -Because ($script:Fix39Lines -join ' | ')
            @($script:Fix39Lines | Where-Object { $_ -match 'different account' }).Count | Should -Be 0 -Because ($script:Fix39Lines -join ' | ')
            (Test-Path -LiteralPath $script:Fix39StatePath) | Should -BeFalse
        }

        # Mutation: treat exit code 0 alone as success again.
        It 'needs a Completed result for success; exit code 0 without one is not success' {
            $script:Fix39ExitCode = 0

            $elevated = Invoke-Fix39Handoff -Report ([ref]$null)

            $elevated | Should -BeFalse
            @($script:Fix39Lines | Where-Object { $_ -match 'could not read a valid result' }).Count | Should -Be 1
            Should -Invoke Read-TpmYesNo -Times 0 -Exactly
        }

        # Mutation: ignore the Completed result or keep using Start-Process -Wait
        # (the fake process has no -Wait semantics; the product must poll WaitForExit).
        It 'returns success for exit code 0 with a Completed result and removes the result file' {
            $script:Fix39ExitCode = 0
            $script:Fix39BeforeExit = {
                $state = New-Fix39OwnerResumeState -StatePath $script:Fix39StatePath
                $state.DatabaseBackupSucceeded = $true
                Write-Fix39Result -ResumeState $state -Completed
            }

            $elevated = Invoke-Fix39Handoff -Report ([ref]$null)

            $elevated | Should -BeTrue
            (Test-Path -LiteralPath ($script:Fix39StatePath + '.result')) | Should -BeFalse
            Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter { $Verb -eq 'RunAs' -and $PassThru -and -not $Wait }
        }
    }

    Context 'structured result round trip' {
        BeforeEach {
            $script:Fix39StateDir = Join-Path $TestDrive ('rt-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
            $script:Fix39StatePath = New-Fix39StatePath -Directory $script:Fix39StateDir
            Mock Get-PostgresRecoveryStateDirectory { $script:Fix39StateDir }
            Mock Write-Log {}
        }

        # Mutation: drop a field from the writer, or stop binding the result to the child process id.
        It 'reads back exactly what the child wrote, bound to the child process id' {
            $written = New-Fix39OwnerResult
            Write-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -Result $written | Should -BeTrue

            $read = Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -ChildProcessId $PID
            $read.Valid | Should -BeTrue
            foreach ($field in @('Operation', 'Outcome', 'StageReached', 'BackupSucceeded', 'NothingElseChanged', 'RetryIssued', 'Summary')) {
                $read.Result.$field | Should -Be $written.$field -Because $field
            }
            (Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -ChildProcessId ($PID + 1)).Valid | Should -BeFalse
        }

        # Mutation: let a second writer replace the first result (non-atomic or overwriting move).
        It 'keeps the first result when a second writer tries the same request' {
            $first = New-Fix39OwnerResult
            $second = New-PostgresRecoveryHandoffResult -ResumeState $null
            Write-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -Result $first | Should -BeTrue
            Write-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -Result $second | Should -BeFalse

            (Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath).Result.Outcome | Should -Be 'StoppedNoPasswordChange'
            @(Get-ChildItem -LiteralPath $script:Fix39StateDir -Filter '*.tmp' -Force).Count | Should -Be 0
        }

        # Mutation: write a result for a path outside TeknoParrot Manager's Recovery folder.
        It 'writes nothing for a request path outside the Recovery folder' {
            $outside = Join-Path $TestDrive ('.tpm-postgres-recovery-' + [guid]::NewGuid().ToString('N') + '.json')
            Write-PostgresRecoveryHandoffResult -StatePath $outside -Result (New-PostgresRecoveryHandoffResult -ResumeState $null) | Should -BeFalse
            (Test-Path -LiteralPath ($outside + '.result')) | Should -BeFalse
            (Read-PostgresRecoveryHandoffResult -StatePath $outside).Valid | Should -BeFalse
        }

        It 'reports a missing result as Missing' {
            $read = Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath
            $read.Valid | Should -BeFalse
            $read.Reason | Should -Be 'Missing'
        }

        # Mutation: drop any one validation rule in Read-PostgresRecoveryHandoffResult.
        It 'rejects a corrupt or inconsistent result file: <Case>' -TestCases @(
            @{ Case = 'not JSON'; Edit = { param($d, $id) 'not json {' } }
            @{ Case = 'truncated JSON'; Edit = { param($d, $id) '{"SchemaVersion":1,"Purpose":"TeknoParrotManager.PostgresRecoveryResult"' } }
            @{ Case = 'wrong purpose'; Edit = { param($d, $id) $d.Purpose = 'Other'; $d } }
            @{ Case = 'wrong schema'; Edit = { param($d, $id) $d.SchemaVersion = 2; $d } }
            @{ Case = 'other request id'; Edit = { param($d, $id) $d.IssuanceId = ('0' * 32); $d } }
            @{ Case = 'unknown outcome'; Edit = { param($d, $id) $d.Outcome = 'Fixed'; $d } }
            @{ Case = 'outcome from an older version'; Edit = { param($d, $id) $d.Outcome = 'StoppedAfterPasswordChange'; $d } }
            @{ Case = 'completed without the Completed stage'; Edit = { param($d, $id) $d.Outcome = 'Completed'; $d } }
            @{ Case = 'retry after an unexpected error'; Edit = { param($d, $id) $d.Outcome = 'StoppedUnexpectedError'; $d.RetryIssued = $true; $d } }
            @{ Case = 'text flag'; Edit = { param($d, $id) $d.NothingElseChanged = 'true'; $d } }
            @{ Case = 'unsafe summary'; Edit = { param($d, $id) $d.Summary = 'The password is C:\secret.txt'; $d } }
            @{ Case = 'empty summary'; Edit = { param($d, $id) $d.Summary = ''; $d } }
        ) {
            param($Case, $Edit)
            Write-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -Result (New-Fix39OwnerResult) | Should -BeTrue
            $resultPath = $script:Fix39StatePath + '.result'
            $data = [System.IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
            $edited = & $Edit $data $null
            $text = if ($edited -is [string]) { $edited } else { $edited | ConvertTo-Json -Depth 3 }
            [System.IO.File]::WriteAllText($resultPath, $text, (New-Object System.Text.UTF8Encoding $false))

            $read = Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath
            $read.Valid | Should -BeFalse -Because $Case
            $read.Reason | Should -Be 'Corrupt'
        }

        # Mutation: move the field checks out of the try, so a malformed child id throws
        # into the caller's "Windows did not give permission" branch.
        It 'treats a non-numeric child id as Corrupt instead of throwing' {
            Write-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -Result (New-Fix39OwnerResult) | Should -BeTrue
            $resultPath = $script:Fix39StatePath + '.result'
            $data = [System.IO.File]::ReadAllText($resultPath) | ConvertFrom-Json
            $data.ChildPid = 'not-a-number'
            [System.IO.File]::WriteAllText($resultPath, ($data | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding $false))

            $read = Read-PostgresRecoveryHandoffResult -StatePath $script:Fix39StatePath -ChildProcessId $PID
            $read.Valid | Should -BeFalse
            $read.Reason | Should -Be 'Corrupt'
        }

        # Mutation: show the reported message for a corrupt file instead of the safe fallback.
        It 'falls back without a message from a corrupt result and without Try again for a used request' {
            [System.IO.File]::WriteAllText(($script:Fix39StatePath + '.result'), 'not json {')
            $script:Fix39Lines = New-Object System.Collections.Generic.List[string]
            Mock New-PostgresRecoveryState { $script:Fix39StatePath }
            Mock Find-PostgresRecoveryRetryState { $null }
            Mock Request-TpmConsoleForeground { $false }
            Mock Write-Host { $script:Fix39Lines.Add(([string]$Object).Trim()) }
            Mock Read-TpmYesNo { 'N' }
            Mock Start-Process { New-Fix39FakeProcess -ExitCode 0 }
            $report = $null

            $elevated = Start-PostgresRecoveryAsAdministrator -ConfigPath (Join-Path $TestDrive 'config.json') -ScriptPath (Join-Path $TestDrive 'TeknoParrot-Manager.ps1') `
                -TpRoot $TestDrive -UserProfilesDir (Join-Path $TestDrive 'UserProfiles') -Operation Recovery -PasswordPlain 'Fixture-New-Pass-1' -HandoffReport ([ref]$report)

            $elevated | Should -BeFalse
            $report | Should -BeNullOrEmpty
            @($script:Fix39Lines | Where-Object { $_ -match 'could not read a valid result' }).Count | Should -Be 1
            Should -Invoke Read-TpmYesNo -Times 0 -Exactly
        }
    }
}
