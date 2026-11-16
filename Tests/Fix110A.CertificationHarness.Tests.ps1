#Requires -Module Pester

# FIX110A (review findings B-2, S-1, S-14, S-15 bullets 1 and 4, N-5): the certification wrapper, process runner and real-data helper.
#   - B-2: the fixture Pester child gets TPM_REAL_DATA_TESTS, TPM_REAL_SOURCE_TESTS and TPM_CPS3_REAL_SOURCE cleared.
#   - S-1: Run-TPM-Tests.ps1 refuses without TPM_REAL_DATA_TESTS=1 before it loads a module, probes a path or creates a folder.
#   - S-14: a timeout stops the whole process tree, the outer wait is longer than the inner one, a timeout is reported on its own,
#     and every TPM command the harness calls can be found in a module it imports (the ECVF call used a function from a module it never loads).
#   - S-15: the source stamp includes file content hashes and fails when a file cannot be read.
#   - N-5: ESC and BEL are built from character codes (Windows PowerShell 5.1 has no `e escape).
# Everything here is synthetic (TestDrive folders, throw-away sleeping processes). Nothing reads a real install or a real collection.
# What this CANNOT prove: a real timeout of a full certification run (needs an owner-approved install and about an hour).

BeforeAll {
    . (Join-Path $PSScriptRoot 'TpmRealDataOptIn.ps1')
    $script:F110Scripts = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts')).Path
    $script:F110Wrapper = Join-Path $script:F110Scripts 'Run-TPM-Tests.ps1'
    $script:F110Harness = Join-Path $script:F110Scripts 'Invoke-TPM-RealInstanceSmoke.ps1'
    Import-Module (Join-Path $script:F110Scripts 'TPMCertification.Execution.psm1') -Force
    $script:F110EnvNames = @('TPM_REAL_DATA_TESTS', 'TPM_REAL_SOURCE_TESTS', 'TPM_CPS3_REAL_SOURCE')
    $script:F110SavedEnv = @{}
    foreach ($name in $script:F110EnvNames) { $script:F110SavedEnv[$name] = [Environment]::GetEnvironmentVariable($name) }

    function Restore-F110AEnvironment {
        foreach ($name in $script:F110EnvNames) { [Environment]::SetEnvironmentVariable($name, $script:F110SavedEnv[$name]) }
    }

    # Runs a command with TPM_REAL_DATA_TESTS set to the given value ($null removes it) and returns exit code and all output text.
    function Invoke-F110AChild {
        param([Parameter(Mandatory)][scriptblock]$Command, $OptIn)
        $ErrorActionPreference = 'Continue'
        $env:TPM_REAL_DATA_TESTS = $OptIn
        try {
            $output = @(& $Command 2>&1 | ForEach-Object { [string]$_ })
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
        } finally { Restore-F110AEnvironment }
    }

    # Starts a short Windows PowerShell script under the real process runner. Returns the runner result.
    function Invoke-F110AIsolated {
        param([Parameter(Mandatory)][string]$ScriptText, [int]$TimeoutSeconds = 60, [hashtable]$Environment)
        $work = Join-Path $TestDrive ('work-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($work)
        $scriptPath = Join-Path $work 'child.ps1'
        Set-Content -LiteralPath $scriptPath -Encoding ASCII -Value $ScriptText
        $splat = @{
            FilePath = (Get-Command powershell.exe).Source
            ArgumentList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath)
            WorkingDirectoryRoot = $work; WorkingDirectory = $work; LogDirectoryRoot = $work; LogDirectory = $work
            Identity = 'fix110a'; TimeoutSeconds = $TimeoutSeconds
        }
        if ($Environment) { $splat['Environment'] = $Environment }
        return (Invoke-TPMIsolatedProcessV1 @splat)
    }
}

AfterAll {
    Restore-F110AEnvironment
}

Describe 'FIX110A N-5 technical text sanitizer builds ESC and BEL from character codes' {
    It 'removes real ANSI sequences and keeps ordinary text that merely contains e[' {
        # Mutation: put back the PowerShell 7 `e / `a escape syntax in the pattern -> under Windows PowerShell 5.1 it matches the letter e, so ordinary text such as "see[0m" is damaged.
        $esc = [string][char]27
        $bel = [string][char]7
        $text = 'see[0m ' + $esc + '[31mred' + $esc + '[0m title' + $esc + ']0;window' + $bel + ' end' + $esc + ']0;other' + $esc + '\' + ' done'
        ConvertTo-TPMSafeTechnicalTextV1 -Text $text | Should -BeExactly 'see[0m red title end done'
    }

    It 'still writes other control characters as visible hex' {
        # Mutation: drop the control-character escaping -> raw control bytes reach the operator console.
        ConvertTo-TPMSafeTechnicalTextV1 -Text ('a' + [char]1 + 'b') | Should -BeExactly 'a\x01b'
    }
}

Describe 'FIX110A S-14 the process-tree helper picks exactly the tree' {
    BeforeAll {
        $script:F110Base = [datetime]'2026-01-01T00:00:00'
        function New-F110AEntry { param([int]$Id, [int]$Parent, [int]$Minutes) [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; CreationDate = $script:F110Base.AddMinutes($Minutes) } }
    }

    It 'returns the root, its children and grandchildren with children before parents, and nothing else' {
        # Mutation: look only at direct children (or return the root alone) -> a grandchild such as a Pester process survives a timeout.
        $snapshot = @(
            (New-F110AEntry -Id 1000 -Parent 10 -Minutes 0)
            (New-F110AEntry -Id 1001 -Parent 1000 -Minutes 1)
            (New-F110AEntry -Id 1002 -Parent 1000 -Minutes 1)
            (New-F110AEntry -Id 1003 -Parent 1001 -Minutes 2)
            (New-F110AEntry -Id 2000 -Parent 10 -Minutes 0)
        )
        $ids = @(Get-TPMProcessTreeIdsV1 -RootProcessId 1000 -Snapshot $snapshot)
        @($ids | Sort-Object) | Should -Be @(1000, 1001, 1002, 1003)
        $ids.IndexOf(1003) | Should -BeLessThan $ids.IndexOf(1001)
        $ids.IndexOf(1001) | Should -BeLessThan $ids.IndexOf(1000)
        $ids.IndexOf(1002) | Should -BeLessThan $ids.IndexOf(1000)
    }

    It 'ignores a process that only claims an older, reused parent id' {
        # Mutation: ignore creation times -> an unrelated process whose recorded parent id was reused is killed with the tree.
        $snapshot = @(
            (New-F110AEntry -Id 1000 -Parent 10 -Minutes 10)
            (New-F110AEntry -Id 1001 -Parent 1000 -Minutes 11)
            (New-F110AEntry -Id 3000 -Parent 1000 -Minutes 5)
        )
        @(Get-TPMProcessTreeIdsV1 -RootProcessId 1000 -Snapshot $snapshot | Sort-Object) | Should -Be @(1000, 1001)
    }

    It 'follows children of a parent that already died when that parent was seen on an earlier pass' {
        # Mutation: forget ids from earlier passes -> a child started just before its parent was killed is left running.
        $snapshot = @(
            (New-F110AEntry -Id 1000 -Parent 10 -Minutes 0)
            (New-F110AEntry -Id 4001 -Parent 4000 -Minutes 3)
        )
        @(Get-TPMProcessTreeIdsV1 -RootProcessId 1000 -Snapshot $snapshot) | Should -Be @(1000)
        @(Get-TPMProcessTreeIdsV1 -RootProcessId 1000 -Snapshot $snapshot -KnownProcessIds @(4000) | Sort-Object) | Should -Be @(1000, 4001)
    }

    It 'never returns the current process, id 0 or id 4' {
        # Mutation: remove the self/system exclusion -> the runner can end itself or a system process.
        $snapshot = @(
            (New-F110AEntry -Id 1000 -Parent 10 -Minutes 0)
            (New-F110AEntry -Id $PID -Parent 1000 -Minutes 1)
            (New-F110AEntry -Id 4 -Parent 1000 -Minutes 1)
            (New-F110AEntry -Id 0 -Parent 1000 -Minutes 1)
        )
        @(Get-TPMProcessTreeIdsV1 -RootProcessId 1000 -Snapshot $snapshot) | Should -Be @(1000)
    }

    It 'does nothing and reports success for a process that is already gone' {
        # Mutation: kill whatever now owns the id of an exited process -> an unrelated process could be stopped.
        $gone = Start-Process -FilePath (Get-Command cmd.exe).Source -ArgumentList '/d', '/c', 'exit 0' -WindowStyle Hidden -PassThru
        [void]$gone.WaitForExit(15000)
        Stop-TPMProcessTreeV1 -ProcessId $gone.Id | Should -BeTrue
    }

    It 'only counts children of an exited root that were created after the root started' {
        # Mutation: ignore -RootStartTime -> a process that merely names a reused id as its parent is stopped with the tree.
        $snapshot = @(
            (New-F110AEntry -Id 5001 -Parent 1000 -Minutes 3)
            (New-F110AEntry -Id 5002 -Parent 1000 -Minutes -3)
        )
        $rootStart = $script:F110Base
        @(Get-TPMProcessTreeIdsV1 -RootProcessId 1000 -Snapshot $snapshot -RootStartTime $rootStart) | Should -Be @(5001)
    }

    It 'stops a child that outlived its exited root instead of reporting the tree stopped' {
        # Mutation: return $true as soon as the root is gone -> the child keeps running (and holding files) while the tree is reported stopped.
        Mock -ModuleName TPMCertification.Execution Get-TPMProcessSnapshotV1 { @([pscustomobject]@{ ProcessId = 5001; ParentProcessId = 1000; CreationDate = (Get-Date) }) }
        Mock -ModuleName TPMCertification.Execution Stop-Process { }
        [void](Stop-TPMProcessTreeV1 -ProcessId 1000 -WaitMilliseconds 0 -RootStartTime ((Get-Date).AddMinutes(-5)))
        Should -Invoke -ModuleName TPMCertification.Execution Stop-Process -Times 1 -ParameterFilter { $Id -eq 5001 }
    }
}

Describe 'FIX110A the certification path checks work from a drive root and a share' {
    It 'keeps a drive root and a share root as they are, and trims every other trailing separator' {
        # Mutation: always TrimEnd the separators -> "C:\" becomes the drive-relative "C:" and the root comparison fails.
        InModuleScope TPMCertification.Execution {
            Get-TPMTrimmedFullPathV1 -Path 'C:\' | Should -BeExactly 'C:\'
            Get-TPMTrimmedFullPathV1 -Path 'C:\Some\Folder\' | Should -BeExactly 'C:\Some\Folder'
            Get-TPMTrimmedFullPathV1 -Path '\\server\share\' | Should -BeExactly '\\server\share'
            Get-TPMTrimmedFullPathV1 -Path '\\server\share\x\' | Should -BeExactly '\\server\share\x'
        }
    }

    It 'accepts an existing folder directly below a drive root when the drive root is the trusted anchor' {
        # Mutation: restore the TrimEnd on the root -> PROCESS_PATH_OUTSIDE_OWNED_ROOT for a path that exists.
        $driveRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
        { Assert-TPMNoReparseInChainV1 -Root $driveRoot -Target $env:SystemRoot } | Should -Not -Throw
        (Assert-TPMOwnedDirectoryV1 -Root $driveRoot -Path $env:SystemRoot) | Should -BeExactly ([IO.Path]::GetFullPath($env:SystemRoot).TrimEnd('\'))
    }

    It 'walks a UNC path from its share root' {
        # Mutation: start the walk at the server name -> a relative path that does not exist is checked and the walk throws.
        $share = '\\localhost\' + $env:SystemDrive.Substring(0, 1) + '$'
        if (-not (Test-Path -LiteralPath $share -PathType Container)) { Set-ItResult -Skipped -Because 'the administrative share is not reachable on this machine'; return }
        { Assert-TPMNoReparseInChainV1 -Root $share -Target (Join-Path $share 'Windows') } | Should -Not -Throw
    }
}

Describe 'FIX110A the logs are cleaned even when the process could not be confirmed stopped' {
    It 'removes raw escape bytes from the captured output before the unconfirmed-termination error' {
        # Mutation: throw before Write-TPMSafeTechnicalFileV1 runs -> the logs the operator is told to read still hold raw ESC bytes.
        Mock -ModuleName TPMCertification.Execution Stop-TPMProcessTreeV1 { Stop-Process -Id $ProcessId -Force; return $false }
        $work = Join-Path $TestDrive ('unconfirmed-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($work)
        $scriptPath = Join-Path $work 'child.ps1'
        Set-Content -LiteralPath $scriptPath -Encoding ASCII -Value "[Console]::Out.Write(([string][char]27) + '[31mvisible-text'); [Console]::Out.Flush(); Start-Sleep -Seconds 120"
        $thrown = $null
        try {
            Invoke-TPMIsolatedProcessV1 -FilePath (Get-Command powershell.exe).Source -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) -WorkingDirectoryRoot $work -WorkingDirectory $work -LogDirectoryRoot $work -LogDirectory $work -Identity 'unconfirmed' -TimeoutSeconds 10 | Out-Null
        } catch { $thrown = $_.Exception.Message }
        $thrown | Should -Match 'PROCESS_TERMINATION_UNCONFIRMED'
        $log = @(Get-ChildItem -LiteralPath $work -Filter '*-stdout.log' -File)[0]
        $text = [IO.File]::ReadAllText($log.FullName)
        $text | Should -Match 'visible-text'
        $text.Contains([string][char]27) | Should -BeFalse
    }
}

Describe 'FIX110A S-14 a timeout stops the whole process tree and says so' {
    It 'stops a grandchild that the direct child started, and reports the timeout' {
        # Mutation: stop only the direct child (the old Stop-Process on one id) -> the grandchild keeps running after the timeout.
        $testStart = [DateTime]::Now.AddSeconds(-2)
        $idFile = Join-Path $TestDrive ('grandchild-' + [guid]::NewGuid().ToString('N') + '.txt')
        $grandchildId = $null
        try {
            $text = @(
                '$grand = Start-Process -FilePath powershell.exe -ArgumentList ''-NoProfile'', ''-NonInteractive'', ''-Command'', ''Start-Sleep -Seconds 300'' -WindowStyle Hidden -PassThru'
                ('[System.IO.File]::WriteAllText(''{0}'', [string]$grand.Id)' -f $idFile)
                'Start-Sleep -Seconds 300'
            ) -join "`r`n"
            $result = Invoke-F110AIsolated -ScriptText $text -TimeoutSeconds 12
            $result.TimedOut | Should -BeTrue
            $result.TerminationConfirmed | Should -BeTrue
            (Get-Content -LiteralPath $result.MetadataPath -Raw | ConvertFrom-Json).TimedOut | Should -BeTrue
            Test-Path -LiteralPath $idFile | Should -BeTrue -Because 'the grandchild must have started before the timeout for this test to mean anything'
            $grandchildId = [int][System.IO.File]::ReadAllText($idFile)
            Get-Process -Id $grandchildId -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        } finally {
            if ($null -ne $grandchildId) {
                $left = Get-Process -Id $grandchildId -ErrorAction SilentlyContinue
                if ($left -and $left.ProcessName -eq 'powershell' -and $left.StartTime -ge $testStart) { Stop-Process -Id $grandchildId -Force -ErrorAction SilentlyContinue }
            }
        }
    }

    It 'reports a normal exit as not timed out, with the real exit code' {
        # Mutation: mark every run as timed out, or lose the exit code -> a finished run is reported as a timeout.
        $result = Invoke-F110AIsolated -ScriptText 'exit 5' -TimeoutSeconds 60
        $result.TimedOut | Should -BeFalse
        $result.TerminationConfirmed | Should -BeTrue
        $result.ExitCode | Should -Be 5
    }
}

Describe 'FIX110A S-14 the wrapper waits longer on the outside and reports a timeout on its own' {
    BeforeAll {
        $script:F110WrapperText = [IO.File]::ReadAllText($script:F110Wrapper)
    }

    It 'the outer relaunch wait is longer than the inner harness wait' {
        # Mutation: give both waits the same limit -> the outer run can kill the middle process before the inner run cleaned up its own children.
        $outer = [regex]::Match($script:F110WrapperText, '\$relaunchTimeoutSeconds=\$PesterRegressionTimeoutSeconds\+(\d+)')
        $inner = [regex]::Match($script:F110WrapperText, "-Identity 'certification-harness' -TimeoutSeconds \(\`$PesterRegressionTimeoutSeconds\+(\d+)\)")
        $outer.Success | Should -BeTrue
        $inner.Success | Should -BeTrue
        [int]$outer.Groups[1].Value | Should -BeGreaterThan ([int]$inner.Groups[1].Value)
        $script:F110WrapperText | Should -Match "-Identity 'pwsh-relaunch' -TimeoutSeconds \`$relaunchTimeoutSeconds"
    }

    It 'both launches check the timeout flag before they use the exit code' {
        # Mutation: drop either check -> a timeout looks like an ordinary failure (or like a missing final status).
        $script:F110WrapperText | Should -Match 'if\(\$result\.TimedOut\)\{Stop-TPMTimedOutV1 '
        $script:F110WrapperText | Should -Match 'if\(\$harnessResult\.TimedOut\)\{Stop-TPMTimedOutV1 '
    }

    It 'the timeout report says what happened in plain words and exits 71' {
        # Mutation: print the generic "exited without a final status" text, or exit 70 -> a timeout cannot be told from a crash.
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F110Wrapper, [ref]$tokens, [ref]$errors)
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Stop-TPMTimedOutV1' }, $true)
        $function | Should -Not -BeNullOrEmpty
        $command = $function.Extent.Text + "`r`nStop-TPMTimedOutV1 -TimeoutSeconds 90 -ReportDirectory 'R-dir' -LogDirectory 'L-dir'"
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($command))
        $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1 | ForEach-Object { [string]$_ })
        $LASTEXITCODE | Should -Be 71
        $joined = $output -join "`n"
        $joined | Should -Match 'FINAL STATUS: PIPELINE ABORTED'
        $joined | Should -Match 'ran out of time after 90 seconds'
        $joined | Should -Match 'Next step:'
        $joined | Should -Match 'Report: R-dir'
        $joined | Should -Match 'Technical log: L-dir'
        $joined | Should -Not -Match 'without a final status'
    }
}

Describe 'FIX110A S-1 the wrapper refuses without the real-data opt-in before it does any work' {
    It 'stops with a plain message, exit 2 and nothing created when the opt-in is <Case>' -ForEach @(
        @{ Case = 'missing'; Value = $null }
        @{ Case = '0'; Value = '0' }
        @{ Case = 'true'; Value = 'true' }
    ) {
        # Mutation: remove the gate at the top of Run-TPM-Tests.ps1 (or move it below the module import) -> this lone copy reports a missing module, or goes on to create report folders.
        $scripts = Join-Path $TestDrive ('gate-' + [guid]::NewGuid().ToString('N') + '\scripts')
        [void][System.IO.Directory]::CreateDirectory($scripts)
        Copy-Item -LiteralPath $script:F110Wrapper -Destination (Join-Path $scripts 'Run-TPM-Tests.ps1')
        $harnessRoot = Join-Path $TestDrive ('no-such-harness-' + [guid]::NewGuid().ToString('N'))
        $wrapper = Join-Path $scripts 'Run-TPM-Tests.ps1'
        $result = Invoke-F110AChild -OptIn $Value -Command {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -RepoPath (Join-Path $TestDrive 'no-such-repo') -TeknoParrotRoot (Join-Path $TestDrive 'no-such-install') -HarnessRoot $harnessRoot
        }
        $result.ExitCode | Should -Be 2
        $result.Output | Should -Match 'did not start'
        $result.Output | Should -Match 'TPM_REAL_DATA_TESTS=1'
        $result.Output | Should -Match 'Nothing was read or changed'
        $result.Output | Should -Not -Match 'execution module not found'
        Test-Path -LiteralPath $harnessRoot | Should -BeFalse
    }

    It 'goes past the gate when the opt-in is exactly 1 (this lone copy then stops on its missing module)' {
        # Mutation: refuse every value, or require something other than exactly 1 -> the documented opt-in no longer starts a run.
        $scripts = Join-Path $TestDrive ('gate-' + [guid]::NewGuid().ToString('N') + '\scripts')
        [void][System.IO.Directory]::CreateDirectory($scripts)
        Copy-Item -LiteralPath $script:F110Wrapper -Destination (Join-Path $scripts 'Run-TPM-Tests.ps1')
        $wrapper = Join-Path $scripts 'Run-TPM-Tests.ps1'
        $result = Invoke-F110AChild -OptIn '1' -Command {
            & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -RepoPath (Join-Path $TestDrive 'no-such-repo') -TeknoParrotRoot (Join-Path $TestDrive 'no-such-install') -HarnessRoot (Join-Path $TestDrive 'no-such-harness')
        }
        $result.Output | Should -Not -Match 'did not start'
        $result.Output | Should -Match 'execution module not found'
        $result.ExitCode | Should -Not -Be 0
    }
}

Describe 'FIX110A B-2 the fixture Pester child cannot inherit a real-data opt-in or a real source' {
    BeforeAll {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F110Harness, [ref]$tokens, [ref]$errors)
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-TPMPesterChildEnvironment' }, $true)
        . ([scriptblock]::Create($function.Extent.Text))
    }

    It 'lists all three variables with an empty value' {
        # Mutation: drop any one of the three names from the child environment -> that variable is inherited by the Pester child.
        $environment = New-TPMPesterChildEnvironment -RepositoryPath $TestDrive -EmptyGlobalConfigPath (Join-Path $TestDrive 'empty.config')
        foreach ($name in $script:F110EnvNames) {
            $environment.ContainsKey($name) | Should -BeTrue -Because $name
            $environment[$name] | Should -BeExactly ''
        }
    }

    It 'a child started with that environment sees none of the three variables, and this shell keeps its own values' {
        # Mutation: pass the opt-in on (value '1') or leave a variable out -> the child still sees it.
        foreach ($name in $script:F110EnvNames) { [Environment]::SetEnvironmentVariable($name, '1') }
        try {
            $environment = New-TPMPesterChildEnvironment -RepositoryPath $TestDrive -EmptyGlobalConfigPath (Join-Path $TestDrive 'empty.config')
            $text = '$names = ''TPM_REAL_DATA_TESTS'', ''TPM_REAL_SOURCE_TESTS'', ''TPM_CPS3_REAL_SOURCE''; foreach ($n in $names) { $v = [Environment]::GetEnvironmentVariable($n); if ($null -eq $v) { ''ABSENT:'' + $n } else { ''PRESENT:'' + $n + ''='' + $v } }'
            $result = Invoke-F110AIsolated -ScriptText $text -TimeoutSeconds 60 -Environment $environment
            $lines = @(Get-Content -LiteralPath $result.StdOutPath | Where-Object { $_ })
            $lines | Should -Be @('ABSENT:TPM_REAL_DATA_TESTS', 'ABSENT:TPM_REAL_SOURCE_TESTS', 'ABSENT:TPM_CPS3_REAL_SOURCE')
            foreach ($name in $script:F110EnvNames) { [Environment]::GetEnvironmentVariable($name) | Should -BeExactly '1' -Because ('this shell must keep ' + $name) }
        } finally { Restore-F110AEnvironment }
    }
}

Describe 'FIX110A S-14 every TPM command the real-instance harness calls can be found' {
    It 'finds each called TPM command in the harness itself or in a module or script it loads' {
        # Mutation: call a function from a module the harness never imports -> it is listed here instead of failing quietly at run time.
        $childScript = Join-Path $TestDrive 'resolve-check.ps1'
        Set-Content -LiteralPath $childScript -Encoding ASCII -Value @'
param([string]$HarnessPath)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $HarnessPath
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($HarnessPath, [ref]$tokens, [ref]$errors)
$defined = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name })
$commands = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
foreach ($command in $commands) {
    if ($command.GetCommandName() -eq 'Import-Module' -and $command.Extent.Text -match "'([^']+\.psm1)'") { Import-Module (Join-Path $scriptDir $Matches[1]) -Force }
}
foreach ($command in $commands) {
    if ($command.InvocationOperator -eq 'Dot' -and $command.Extent.Text -match "'([^']+\.ps1)'") { . (Join-Path $scriptDir $Matches[1]) }
}
$called = @($commands | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ -match '^[A-Za-z]+-TPM' } | Sort-Object -Unique)
$unresolved = @($called | Where-Object { ($defined -notcontains $_) -and -not (Get-Command $_ -ErrorAction SilentlyContinue) })
'CALLED:' + $called.Count
'UNRESOLVED:' + ($unresolved -join ';')
'@
        $output = @(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $childScript -HarnessPath $script:F110Harness 2>&1 | ForEach-Object { [string]$_ })
        $joined = $output -join "`n"
        $joined | Should -Match 'CALLED:\d+'
        [int]([regex]::Match($joined, 'CALLED:(\d+)').Groups[1].Value) | Should -BeGreaterThan 20 -Because 'the check must really have looked at the harness calls'
        $joined | Should -Match '(?m)^UNRESOLVED:$'
    }
}

Describe 'FIX110A S-15 the source stamp includes content hashes and fails on an unreadable file' {
    BeforeEach {
        $script:F110Source = Join-Path $TestDrive ('stamp-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($script:F110Source)
    }

    It 'changes when a file is rewritten with the same length and the old write time is put back' {
        # Mutation: stamp only name, length and time (the FIX107 stamp) -> a same-length rewrite with a restored time looks untouched.
        $file = Join-Path $script:F110Source 'a.bin'
        $time = [datetime]'2020-01-01T00:00:00Z'
        [System.IO.File]::WriteAllBytes($file, [byte[]](1, 2, 3, 4))
        [System.IO.File]::SetLastWriteTimeUtc($file, $time)
        $stamp = Get-TpmSourceStamp -Path $script:F110Source
        [System.IO.File]::WriteAllBytes($file, [byte[]](9, 9, 9, 9))
        [System.IO.File]::SetLastWriteTimeUtc($file, $time)
        (Get-TpmSourceStamp -Path $script:F110Source) | Should -Not -Be $stamp
        [System.IO.File]::WriteAllBytes($file, [byte[]](1, 2, 3, 4))
        [System.IO.File]::SetLastWriteTimeUtc($file, $time)
        (Get-TpmSourceStamp -Path $script:F110Source) | Should -Be $stamp
    }

    It 'stamps a single file with its hash too' {
        # Mutation: hash folders only -> a .zip source can be rewritten unnoticed.
        $zip = Join-Path $script:F110Source 'set.zip'
        $time = [datetime]'2020-01-01T00:00:00Z'
        [System.IO.File]::WriteAllBytes($zip, [byte[]](1, 2, 3))
        [System.IO.File]::SetLastWriteTimeUtc($zip, $time)
        $stamp = @(Get-TpmSourceStamp -Path $zip)
        [System.IO.File]::WriteAllBytes($zip, [byte[]](3, 2, 1))
        [System.IO.File]::SetLastWriteTimeUtc($zip, $time)
        @(Get-TpmSourceStamp -Path $zip) | Should -Not -Be $stamp
    }

    It 'throws instead of returning a short stamp when a file cannot be read' {
        # Mutation: skip files that cannot be read (SilentlyContinue) -> a locked or rewritten file is left out and the stamp still matches.
        $file = Join-Path $script:F110Source 'locked.bin'
        [System.IO.File]::WriteAllBytes($file, [byte[]](1, 2, 3))
        $lock = New-Object System.IO.FileStream($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            { Get-TpmSourceStamp -Path $script:F110Source } | Should -Throw
        } finally { $lock.Dispose() }
        { Get-TpmSourceStamp -Path $script:F110Source } | Should -Not -Throw
    }
}
