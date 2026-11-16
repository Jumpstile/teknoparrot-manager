#Requires -Module Pester

# FIX110A S-2: a progress drawing failure never interrupts the work it reports on, and genuine cancellation still stops it.
#   Module (scripts\TpmProgress.psm1): a drawing error in an update, in the first frame, in the closing frame, in the prompt lift, or a
#   failure the refresh writer reported on its own is swallowed once and written to the owner's log hook. The renderer of that operation
#   stays off, the operation stays open for ownership and its close, and nothing is retried. Cancellation (a canceled token or a stopped
#   pipeline) is never swallowed.
#   Product wrappers (Write-TpmCompactExtractionProgress, Invoke-TpmProgressGroup): the same rule, so a mutation loop, a rollback and
#   a result already verified keep going and keep their result.
#   N-3: the Stalled look follows the CURRENT silence, not the history of an earlier stall.
# Every console write is a mock. The product script is parsed and only the progress wrappers are dot-sourced from a copy in TestDrive.
# What this CANNOT prove: how a real console reacts to a failing write.

BeforeAll {
    $script:F110ModuleSource = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1'))
    $script:F110ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
}

Describe 'FIX110A S-2 the progress module contains drawing failures' {
    BeforeAll {
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module $script:F110ModuleSource -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }
    BeforeEach {
        $global:F110Now = [datetime]'2026-01-01T00:00:00'
        $global:F110Lines = New-Object System.Collections.Generic.List[string]
        $global:F110Log = New-Object System.Collections.Generic.List[string]
        $global:F110Fail = $null
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:F110Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine {
            if ($null -ne $global:F110Fail) { throw $global:F110Fail }
            [void]$global:F110Lines.Add($Text)
        } -ModuleName TpmProgress
        Set-TpmProgressRenderLogger -Logger { param([string]$Message) [void]$global:F110Log.Add($Message) }
    }
    AfterEach {
        $global:F110Fail = $null
        Set-TpmProgressRenderLogger -Logger $null
        Stop-TpmProgressAbandoned
        Remove-Variable -Name F110Now, F110Lines, F110Log, F110Fail -Scope Global -ErrorAction SilentlyContinue
    }

    It 'swallows a drawing failure in an update, logs it once, stops drawing and still closes' {
        # Mutation: rethrow the render failure after the cleanup (the old Write-TpmProgressFrame) -> the update throws and the caller's work stops.
        # Mutation: keep drawing after the failure -> lines keep arriving and the log repeats.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' -Total 10 | Out-Null
        $global:F110Lines.Clear()
        $global:F110Fail = 'console write failed'
        { Set-TpmProgressStage -Stage 'Files one' -Current 1 -Total 10 } | Should -Not -Throw
        @($global:F110Log).Count | Should -Be 1
        $global:F110Log[0] | Should -Match 'console write failed'
        $global:F110Fail = $null
        { Set-TpmProgressStage -Stage 'Files two' -Current 2 -Total 10 } | Should -Not -Throw
        $global:F110Lines.Count | Should -Be 0
        Test-TpmProgressActive | Should -BeTrue
        { Complete-TpmProgressOperation -State Final } | Should -Not -Throw
        $global:F110Lines.Count | Should -Be 0
        Test-TpmProgressActive | Should -BeFalse
        @($global:F110Log).Count | Should -Be 1
    }

    It 'does not throw when the first frame cannot be drawn and keeps the group open for its tasks' {
        # Mutation: throw (or drop the operation) when the first frame fails -> Start throws, the group owner is gone and the next task call throws.
        $global:F110Fail = 'no console'
        { Start-TpmProgressOperation -Title 'Workflow' -Group | Out-Null } | Should -Not -Throw
        Test-TpmProgressGroupOwned | Should -BeTrue
        { Add-TpmProgressTask -Description 'Row' -Total 3 | Out-Null } | Should -Not -Throw
        @($global:F110Log).Count | Should -Be 1
        { Complete-TpmProgressOperation -State Final } | Should -Not -Throw
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'does not throw when the closing frame cannot be drawn' {
        # Mutation: let the closing-frame error escape Complete-TpmProgressOperation (the old behavior) -> a verified result turns into an exception.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        $global:F110Fail = 'closing write failed'
        { Complete-TpmProgressOperation -State Final } | Should -Not -Throw
        Test-TpmProgressActive | Should -BeFalse
        @($global:F110Log).Count | Should -Be 1
        $global:F110Log[0] | Should -Match 'closing write failed'
    }

    It 'closes without a throw when the refresh writer reported its own failure and draws no closing frame' {
        # Mutation: raise Live.Failure at the terminal close again (throw $op.Live.Failure) -> the close throws.
        # Mutation: draw the closing frame although the renderer failed -> a line appears after the failure.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        $global:F110Lines.Clear()
        InModuleScope TpmProgress {
            try { throw 'writer died' } catch { $script:TpmProgressOp.Live.Failure = $_ }
        }
        { Complete-TpmProgressOperation -State Final } | Should -Not -Throw
        $global:F110Lines.Count | Should -Be 0
        Test-TpmProgressActive | Should -BeFalse
        @($global:F110Log).Count | Should -Be 1
        $global:F110Log[0] | Should -Match 'writer died'
    }

    It 'lets a canceled token propagate from an update and from the close, and does not log it as a drawing failure' {
        # Mutation: swallow every exception type in the containment -> cancellation is lost and these Should -Throw fail.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' -Total 10 | Out-Null
        $global:F110Fail = [System.OperationCanceledException]::new('canceled')
        { Set-TpmProgressStage -Stage 'Files one' -Current 1 -Total 10 } | Should -Throw '*canceled*'
        Test-TpmProgressActive | Should -BeFalse
        $global:F110Fail = $null
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        $global:F110Fail = [System.OperationCanceledException]::new('canceled at close')
        { Complete-TpmProgressOperation -State Final } | Should -Throw '*canceled at close*'
        Test-TpmProgressActive | Should -BeFalse
        @($global:F110Log).Count | Should -Be 0
    }

    It 'lets a canceled token propagate from the first frame' {
        # Mutation: contain the first-frame error of any type -> Start swallows the cancellation and returns an open operation.
        $global:F110Fail = [System.OperationCanceledException]::new('canceled at start')
        { Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null } | Should -Throw '*canceled at start*'
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'recognizes cancellation anywhere in the error chain and nothing else' -ForEach @(
        @{ Name = 'stopped pipeline'; Expected = $true; Make = { [System.Activator]::CreateInstance([System.Management.Automation.PipelineStoppedException], $true) } }
        @{ Name = 'cancelled token'; Expected = $true; Make = { [System.OperationCanceledException]::new('x') } }
        @{ Name = 'cancellation wrapped in another exception'; Expected = $true; Make = { [System.InvalidOperationException]::new('outer', [System.OperationCanceledException]::new('inner')) } }
        @{ Name = 'ordinary failure'; Expected = $false; Make = { [System.InvalidOperationException]::new('plain') } }
        @{ Name = 'nothing'; Expected = $false; Make = { $null } }
    ) {
        # Mutation: test only the top exception type, or treat every exception as cancellation -> a wrapped cancellation is lost or a drawing error propagates.
        $error1 = & $Make
        Test-TpmProgressCancellationError -ErrorRecord $error1 | Should -Be $Expected
        if ($null -ne $error1) {
            $record = [System.Management.Automation.ErrorRecord]::new($error1, 'F110', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            Test-TpmProgressCancellationError -ErrorRecord $record | Should -Be $Expected
        }
    }

    It 'does not throw when lifting the bar for a prompt fails' {
        # Mutation: let the live-region erase error escape Suspend-TpmProgressLine -> a password or question prompt is aborted by a drawing error.
        Mock Remove-TpmProgressLiveRegion { throw 'erase failed' } -ModuleName TpmProgress
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' | Out-Null
        { Suspend-TpmProgressLine } | Should -Not -Throw
        @($global:F110Log).Count | Should -Be 1
        $global:F110Log[0] | Should -Match 'erase failed'
        { Resume-TpmProgressLine } | Should -Not -Throw
        { Complete-TpmProgressOperation -State Final } | Should -Not -Throw
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'shows a recovered stall as running again and a live stall as stalled' {
        # Mutation: pick the plain-frame look from the remembered StalledFor (the old line) -> the recovered work still reads stalled.
        # Mutation: never show Stalled -> a work that really is silent reads running.
        Start-TpmProgressOperation -Title 'Copy' -Stage 'Files' -Total 10 | Out-Null
        $global:F110Now = $global:F110Now.AddSeconds(75)
        Set-TpmProgressStage -Stage 'Files one' -Current 1 -Total 10
        (Get-TpmProgressState).Outcome | Should -BeExactly 'Stalled'
        $global:F110Now = $global:F110Now.AddSeconds(2)
        $global:F110Lines.Clear()
        Set-TpmProgressStage -Stage 'Files two' -Current 2 -Total 10
        $global:F110Lines.Count | Should -BeGreaterThan 0
        $global:F110Lines[$global:F110Lines.Count - 1] | Should -Not -Match 'stalled'
        $global:F110Now = $global:F110Now.AddSeconds(70)
        $global:F110Lines.Clear()
        InModuleScope TpmProgress { Write-TpmProgressFrame -Force -Sync }
        $global:F110Lines.Count | Should -BeGreaterThan 0
        $global:F110Lines[$global:F110Lines.Count - 1] | Should -Match 'stalled'
    }
}

Describe 'FIX110A S-2 the product progress wrappers never stop the work' {
    BeforeAll {
        # The wrappers are copied into TestDrive next to a copy of the module, so their own Import-TpmProgressModule loads that copy.
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F110ProductPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'FIX110A tests could not parse the production script.' }
        $wanted = @('Import-TpmProgressModule', 'Write-TpmCompactExtractionProgress', 'Get-TpmProgressCloseState', 'Invoke-TpmProgressGroup')
        $texts = foreach ($name in $wanted) {
            $nodes = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name }, $true))
            if ($nodes.Count -ne 1) { throw ('FIX110A tests expected one {0}, found {1}.' -f $name, $nodes.Count) }
            $nodes[0].Extent.Text
        }
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'scripts') -Force | Out-Null
        Copy-Item -LiteralPath $script:F110ModuleSource -Destination (Join-Path $TestDrive 'scripts\TpmProgress.psm1') -Force
        $functionPath = Join-Path $TestDrive 'wrappers.ps1'
        [System.IO.File]::WriteAllText($functionPath, ($texts -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
        . $functionPath
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module (Join-Path $TestDrive 'scripts\TpmProgress.psm1') -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }
    BeforeEach {
        $global:F110Now = [datetime]'2026-01-01T00:00:00'
        $global:F110Lines = New-Object System.Collections.Generic.List[string]
        $global:F110Log = New-Object System.Collections.Generic.List[string]
        $global:F110Fail = $null
        function Write-Log { param([string]$msg) [void]$global:F110Log.Add($msg) }
        Mock Get-TpmProgressDefaultColumns { @('Spinner', 'Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining') } -ModuleName TpmProgress
        Mock Start-TpmProgressRefresh {} -ModuleName TpmProgress
        Mock Get-TpmProgressCursorVisible { $true } -ModuleName TpmProgress
        Mock Set-TpmProgressCursorVisible {} -ModuleName TpmProgress
        Mock Get-TpmProgressNow { $global:F110Now } -ModuleName TpmProgress
        Mock Test-TpmProgressOutputRedirected { $true } -ModuleName TpmProgress
        Mock Test-TpmProgressColorEnabled { $false } -ModuleName TpmProgress
        Mock Get-TpmProgressStyle { 'Ascii' } -ModuleName TpmProgress
        Mock Write-TpmProgressPlainLine {
            if ($null -ne $global:F110Fail) { throw $global:F110Fail }
            [void]$global:F110Lines.Add($Text)
        } -ModuleName TpmProgress
    }
    AfterEach {
        $global:F110Fail = $null
        Stop-TpmProgressAbandoned
        Set-TpmProgressRenderLogger -Logger $null
        Remove-Variable -Name F110Now, F110Lines, F110Log, F110Fail -Scope Global -ErrorAction SilentlyContinue
    }

    It 'registers the log hook, so a drawing failure lands in the manager log and the mutation loop finishes' {
        # Mutation: drop the Set-TpmProgressRenderLogger line from Import-TpmProgressModule -> the failure is swallowed silently and the log stays empty.
        # Mutation: let the wrapper rethrow drawing errors -> the loop stops after the first item.
        $global:F110Fail = 'console write failed'
        $written = New-Object System.Collections.Generic.List[int]
        foreach ($item in 1..4) {
            Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Profile update' -Current $item -Total 4 -Completed
            [void]$written.Add($item)
        }
        ($written -join ',') | Should -BeExactly '1,2,3,4'
        @($global:F110Log | Where-Object { $_ -match 'console write failed' }).Count | Should -Be 1
    }

    It 'keeps a verified return value when the closing update of the bar fails in a finally block' {
        # Mutation: remove the try/catch in Write-TpmCompactExtractionProgress -> the close in the finally replaces the verified return with an exception.
        function Invoke-F110Download {
            try {
                Write-TpmCompactExtractionProgress -Phase Checking -Label 'Downloading file' -Current 5 -Total 5 -Completed
                return 'verified'
            } finally {
                Write-TpmCompactExtractionProgress -Phase Checking -Label 'Downloading file' -Current 0 -Total 0 -Complete -Outcome Final
            }
        }
        Mock Complete-TpmProgressOperation { throw 'close failed' }
        Invoke-F110Download | Should -BeExactly 'verified'
        @($global:F110Log | Where-Object { $_ -match 'close failed' }).Count | Should -Be 1
    }

    It 'keeps rolling back when the rollback progress update fails' {
        # Mutation: remove the try/catch in Write-TpmCompactExtractionProgress -> the first failed update stops the remaining restores.
        $restored = New-Object System.Collections.Generic.List[string]
        Mock Set-TpmProgressStage { throw 'stage update failed' }
        foreach ($name in @('A', 'B', 'C')) {
            Write-TpmCompactExtractionProgress -Phase Repairing -Label 'PostgreSQL profile rollback' -Current 1 -Total 3
            [void]$restored.Add($name)
        }
        Write-TpmCompactExtractionProgress -Phase Repairing -Label 'PostgreSQL profile rollback' -Current 3 -Total 3 -Complete -Outcome Error
        ($restored -join ',') | Should -BeExactly 'A,B,C'
        @($global:F110Log | Where-Object { $_ -match 'stage update failed' }).Count | Should -Be 3
    }

    It 'drops a non-drawing error of the module call and lets cancellation through' {
        # Mutation: remove the cancellation check in the wrapper -> the canceled token is swallowed and the loop goes on.
        Mock Set-TpmProgressStage { throw 'Unknown progress task ID: 9' }
        { Write-TpmCompactExtractionProgress -Phase Scanning -Label 'Row' -Current 1 -Total 5 } | Should -Not -Throw
        @($global:F110Log | Where-Object { $_ -match 'Unknown progress task ID' }).Count | Should -Be 1
        Mock Set-TpmProgressStage { throw [System.OperationCanceledException]::new('canceled') }
        { Write-TpmCompactExtractionProgress -Phase Scanning -Label 'Row' -Current 2 -Total 5 } | Should -Throw '*canceled*'
    }

    It 'runs the group action and returns its result when the group bar cannot start' {
        # Mutation: Start-TpmProgressOperation outside the try (the old Invoke-TpmProgressGroup) -> the workflow never runs.
        Mock Start-TpmProgressOperation { throw 'no console' }
        $script:f110Ran = $false
        $result = Invoke-TpmProgressGroup -Title 'Workflow' -Action { $script:f110Ran = $true; [pscustomobject]@{ Outcome = 'SUCCEEDED' } }
        $script:f110Ran | Should -BeTrue
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($global:F110Log | Where-Object { $_ -match 'Progress group could not start' }).Count | Should -Be 1
    }

    It 'does not run the group action when the start is cancelled' {
        # Mutation: swallow cancellation at the group start -> the workflow runs although the user canceled.
        Mock Start-TpmProgressOperation { throw [System.OperationCanceledException]::new('canceled at start') }
        $script:f110Ran = $false
        { Invoke-TpmProgressGroup -Title 'Workflow' -Action { $script:f110Ran = $true } } | Should -Throw '*canceled at start*'
        $script:f110Ran | Should -BeFalse
    }

    It 'keeps the workflow result when the group bar fails to draw while the workflow runs' {
        # Mutation: remove the module containment -> the leaf update throws inside the action and the result becomes a failure.
        $script:f110Ran = $false
        $result = Invoke-TpmProgressGroup -Title 'Workflow' -Action {
            $global:F110Fail = 'console write failed'
            Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Profile update' -Current 1 -Total 2
            Write-TpmCompactExtractionProgress -Phase Repairing -Label 'Profile update' -Current 2 -Total 2
            $script:f110Ran = $true
            [pscustomobject]@{ Outcome = 'SUCCEEDED' }
        }
        $script:f110Ran | Should -BeTrue
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Test-TpmProgressActive | Should -BeFalse
    }

    It 'still raises the error of a failing group action' {
        # Mutation: swallow the action error in the group wrapper -> a failed workflow looks like it finished.
        { Invoke-TpmProgressGroup -Title 'Workflow' -Action { throw 'real workflow failure' } } | Should -Throw '*real workflow failure*'
        Test-TpmProgressActive | Should -BeFalse
    }
}
