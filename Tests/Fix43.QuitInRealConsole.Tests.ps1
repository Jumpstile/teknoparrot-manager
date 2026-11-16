#Requires -Module Pester
# FIX43: TeknoParrot Manager must exit after Q in a real console window. Root cause: the live progress refresh writer
# (scripts\TpmProgress.psm1, New-TpmProgressRefreshService) is a PowerShell runner on its own thread that waited forever
# once it had no operation, and nothing stopped it when the script ended; its thread was a foreground thread, so
# powershell.exe -File never exited.
# What these tests CAN prove: a child powershell.exe that creates the refresh writer the way Start-TpmProgressOperation
# does (Start-TpmProgressRefresh without -Op) and then ends - plainly, with exit 3, or with an unhandled error - exits on
# its own; the writer thread is a background thread; an idle writer ends itself when its owner runspace is gone; the
# shutdown function stops the writer and is repeatable; the product's main block stops the writer in a finally.
# What they CANNOT prove: the real-console condition. The child runs with redirected standard streams, so no live bar is
# drawn; whether the pre-fix module hangs such a child (expected, because the writer is the only foreground thread) was
# not observed on the build PC. The test-PC real-console sandbox run is the proof for the product.
BeforeDiscovery {
    $script:ChildHosts = @(@{ Name = 'Windows PowerShell 5.1'; Exe = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') })
    $pwshCommand = Get-Command -Name pwsh.exe -ErrorAction SilentlyContinue
    if ($pwshCommand) { $script:ChildHosts += @{ Name = 'PowerShell 7'; Exe = $pwshCommand.Source } }
}

BeforeAll {
    $script:ModulePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1'))
    $script:ProductPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
    $script:ChildScript = Join-Path $TestDrive 'Fix43Child.ps1'
    $childLines = @(
        'param([string]$ModulePath, [string]$Ending, [string]$Marker)',
        '$ErrorActionPreference = ''Stop''',
        'Import-Module -Name $ModulePath -Force',
        '$module = Get-Module -Name TpmProgress',
        '# The writer the way Start-TpmProgressOperation creates it (Start-TpmProgressRefresh without -Op).',
        '$service = & $module { Start-TpmProgressRefresh; $script:TpmProgressRefreshService }',
        '$deadline = [DateTime]::UtcNow.AddSeconds(10)',
        'while (-not $service.Ready -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }',
        '$hook = & $module { $script:TpmProgressExitSubscriptionId }',
        '[System.IO.File]::WriteAllText($Marker, (''ready={0};background={1};hook={2}'' -f $service.Ready, $service.Background, ($null -ne $hook)))',
        'if ($Ending -eq ''Blocked'') {',
        '    # A writer stuck on the Gate (it holds a fake session and cannot answer Stop): only the bounded wait and the background thread can let the process end.',
        '    $gate = New-Object System.Object',
        '    [System.Threading.Monitor]::Enter($gate)',
        '    & $module { param($service, $gate)',
        '        $live = [hashtable]::Synchronized(@{ Gate = $gate; Frame = (New-TpmProgressFrameState); Stop = $false; Failure = $null; CursorVisible = $null })',
        '        $service.Session = $live',
        '        [void]$service.Signal.Set()',
        '    } $service $gate',
        '    Start-Sleep -Milliseconds 1000',
        '    $watch = [System.Diagnostics.Stopwatch]::StartNew()',
        '    # The fake session is minimal, so the writer may fault on it instead of blocking; Close then rethrows the writer failure (as the product''s finally would log it). Either way Close must return quickly, clear the cache and the process must end.',
        '    $closeError = ''none''',
        '    try { & $module { Close-TpmProgressSession -WaitMs 1500 } } catch { $closeError = ''threw'' }',
        '    [System.IO.File]::AppendAllText($Marker, (('';closeMs={0};cacheCleared={1};closeError={2}'') -f [int]$watch.ElapsedMilliseconds, ($null -eq (& $module { $script:TpmProgressRefreshService })), $closeError))',
        '    $Ending = ''End''',
        '}',
        'if ($Ending -eq ''Exit3'') { exit 3 }',
        'if ($Ending -eq ''Throw'') { throw ''FIX43 unhandled error'' }'
    )
    [System.IO.File]::WriteAllText($script:ChildScript, (($childLines -join "`r`n") + "`r`n"), [System.Text.Encoding]::ASCII)

    function script:Invoke-Fix43Child {
        param([string]$Exe, [string]$Ending, [int]$TimeoutSeconds = 15)
        $marker = Join-Path $TestDrive ('marker-{0}.txt' -f [guid]::NewGuid().ToString('N'))
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Exe
        $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -ModulePath "{1}" -Ending {2} -Marker "{3}"' -f $script:ChildScript, $script:ModulePath, $Ending, $marker
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $proc.StandardInput.Close()
        $exited = $false
        $state = ''
        try {
            $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
            if (-not $exited) {
                $proc.Refresh()
                $state = 'still running after {0}s: threads={1}, cpu={2:N2}s, responding={3}' -f $TimeoutSeconds, $proc.Threads.Count, $proc.TotalProcessorTime.TotalSeconds, $proc.Responding
            }
        } finally {
            if (-not $proc.HasExited) { try { $proc.Kill() } catch {} ; [void]$proc.WaitForExit(5000) }
        }
        [pscustomobject]@{
            Exited = $exited; State = $state; ExitCode = $(if ($exited) { $proc.ExitCode } else { $null })
            Marker = $(if (Test-Path -LiteralPath $marker) { [System.IO.File]::ReadAllText($marker) } else { '' })
            Error = $(if ($exited) { $errTask.Result } else { '' })
        }
    }
}

Describe 'FIX43 a script that created the refresh writer ends on its own' {
    # Mutation (the first three tests): remove the daemon-thread line, the exit hook and the idle owner check from
    # New-TpmProgressRefreshService, i.e. the pre-FIX43 writer (endless wait, foreground thread, nothing stops it). The
    # child then never exits and the test fails with the child's state (expected; only the real-console sandbox shows
    # whether a plain non-console child hangs the same way).
    It '<Name>: ends normally with exit code 0' -ForEach $script:ChildHosts {
        $r = Invoke-Fix43Child -Exe $Exe -Ending 'End'
        $r.Marker | Should -Match 'ready=True'
        $r.Exited | Should -BeTrue -Because $r.State
        $r.ExitCode | Should -Be 0
    }
    It '<Name>: exit 3 ends with exit code 3' -ForEach $script:ChildHosts {
        $r = Invoke-Fix43Child -Exe $Exe -Ending 'Exit3'
        $r.Marker | Should -Match 'ready=True'
        $r.Exited | Should -BeTrue -Because $r.State
        $r.ExitCode | Should -Be 3
    }
    It '<Name>: an unhandled terminating error ends with exit code 1' -ForEach $script:ChildHosts {
        $r = Invoke-Fix43Child -Exe $Exe -Ending 'Throw'
        $r.Marker | Should -Match 'ready=True'
        $r.Exited | Should -BeTrue -Because $r.State
        $r.ExitCode | Should -Be 1
    }
    It '<Name>: the writer thread is a background thread and the exit handler is registered' -ForEach $script:ChildHosts {
        # Mutation: delete the IsBackground line in the writer script -> background=False; delete Register-TpmProgressExitHook
        # from New-TpmProgressRefreshService -> hook=False.
        $r = Invoke-Fix43Child -Exe $Exe -Ending 'End'
        $r.Marker | Should -Match 'background=True'
        $r.Marker | Should -Match 'hook=True'
    }
    It '<Name>: a writer that cannot answer Stop is abandoned by the bounded close and the process still ends' -ForEach $script:ChildHosts {
        # The only test of the "bounded wait + background thread" layers: the plain end, exit 3 and throw cases pass through
        # the cooperative stop. Mutation: delete the IsBackground line -> the blocked writer is a foreground thread and the
        # child never exits; make Stop-TpmProgressRefreshService ignore -WaitMs (endless EndInvoke) -> Close never returns,
        # no closeMs in the marker, the child never exits.
        $r = Invoke-Fix43Child -Exe $Exe -Ending 'Blocked'
        $r.Marker | Should -Match 'ready=True'
        $r.Marker | Should -Match 'closeMs=\d+;cacheCleared=True'
        [int]([regex]::Match($r.Marker, 'closeMs=(\d+)').Groups[1].Value) | Should -BeLessThan 6000
        $r.Exited | Should -BeTrue -Because $r.State
        $r.ExitCode | Should -Be 0
    }
}

Describe 'FIX43 refresh writer lifecycle (in process)' {
    BeforeAll {
        Get-Module -Name TpmProgress -All | Remove-Module -Force
        Import-Module $script:ModulePath -Force -ErrorAction Stop
    }
    AfterAll { Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue }

    It 'Close-TpmProgressSession stops the writer, releases its runspace and can be repeated' {
        # Mutation: make Close-TpmProgressSession not call Stop-TpmProgressRefreshService -> the writer is still running.
        $service = InModuleScope TpmProgress { Start-TpmProgressRefresh; $script:TpmProgressRefreshService }
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not $service.Ready -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
        $service.Ready | Should -BeTrue
        $service.Async.IsCompleted | Should -BeFalse
        Close-TpmProgressSession -WaitMs 5000
        $service.Async.IsCompleted | Should -BeTrue
        (InModuleScope TpmProgress { $script:TpmProgressRefreshService }) | Should -BeNullOrEmpty
        { Close-TpmProgressSession -WaitMs 5000 } | Should -Not -Throw
        { Close-TpmProgressSession } | Should -Not -Throw
    }

    It 'an idle writer ends itself when its owner runspace is gone' {
        # Mutation: put the endless WaitOne() back in the writer loop (or drop the owner check) -> the writer never ends
        # and the 10 second wait below is false.
        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.Open()
        $service = $null
        try {
            $ps = [powershell]::Create()
            $ps.Runspace = $rs
            [void]$ps.AddScript({
                param($modulePath)
                Import-Module -Name $modulePath -Force
                & (Get-Module -Name TpmProgress) { Start-TpmProgressRefresh; $script:TpmProgressRefreshService }
            }).AddArgument($script:ModulePath)
            $service = @($ps.Invoke())[0]
            $ps.Dispose()
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            while (-not $service.Ready -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
            $service.Ready | Should -BeTrue
        } finally {
            $rs.Close()
            $rs.Dispose()
        }
        try {
            $service.Async.AsyncWaitHandle.WaitOne(10000) | Should -BeTrue -Because 'the writer must end once its owner runspace is closed'
        } finally {
            $service.Stop = $true
            [void]$service.Signal.Set()
            if ($service.Async.AsyncWaitHandle.WaitOne(5000)) { $service.Runner.Dispose(); $service.Signal.Dispose() }
        }
    }
}

Describe 'FIX43 the shutdown is wired to every exit path (AST)' {
    BeforeAll {
        $parse = {
            param([string]$Path)
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
            if (@($errors).Count -gt 0) { throw ('{0} does not parse: {1}' -f $Path, $errors[0].Message) }
            $ast
        }
        $script:ModuleAst = & $parse $script:ModulePath
        $script:ProductAst = & $parse $script:ProductPath
    }

    It 'the product main block stops the progress writer in a finally' {
        # Mutation: delete the Close-TpmProgressSession call from the finally (or the finally) -> no try statement
        # with that finally remains; the one that has it must hold the main menu loop with its Q break.
        $try = @($script:ProductAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.TryStatementAst] -and $null -ne $n.Finally -and
            @($n.Finally.FindAll({ param($c) $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'Close-TpmProgressSession' }, $true)).Count -gt 0
        }, $true))
        $try.Count | Should -Be 1
        $loops = @($try[0].Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.WhileStatementAst] -and $n.Extent.Text -match "modeChoice\s+-eq\s+'Q'" }, $true))
        $loops.Count | Should -BeGreaterThan 0
        @($try[0].CatchClauses).Count | Should -BeGreaterThan 0
        # The finally must reach the module through the module object (Import-TpmProgressModule imports inside a function,
        # so a bare command name may not resolve at script scope; the empty-catch version of that call would fail silently).
        # Mutation: call Close-TpmProgressSession by bare name again, or drop the Get-Module lookup.
        $fin = $try[0].Finally
        @($fin.FindAll({ param($c) $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'Get-Module' }, $true)).Count | Should -BeGreaterThan 0
        $blocks = @($fin.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and $n.Extent.Text -match 'Close-TpmProgressSession'
        }, $true))
        $blocks.Count | Should -BeGreaterThan 0
        $bare = @($fin.FindAll({
            param($c)
            $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'Close-TpmProgressSession' -and
            @($blocks | Where-Object { $c.Extent.StartOffset -ge $_.Extent.StartOffset -and $c.Extent.EndOffset -le $_.Extent.EndOffset }).Count -eq 0
        }, $true))
        $bare.Count | Should -Be 0
        $fin.Extent.Text | Should -Match 'Write-Log'
    }

    It 'the module stops the writer on removal and registers its exit handler with the writer' {
        # Mutation: remove the Close-TpmProgressSession call from OnRemove, or Register-TpmProgressExitHook from
        # New-TpmProgressRefreshService.
        $create = $script:ModuleAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-TpmProgressRefreshService' }, $true)
        $create | Should -Not -BeNullOrEmpty
        @($create.FindAll({ param($c) $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'Register-TpmProgressExitHook' }, $true)).Count | Should -Be 1
        $onRemove = @($script:ModuleAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -match 'OnRemove' }, $true))
        $onRemove.Count | Should -Be 1
        @($onRemove[0].Right.FindAll({ param($c) $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'Close-TpmProgressSession' }, $true)).Count | Should -Be 1
    }

    It 'no writer wait is endless' {
        # Mutation: put Signal.WaitOne() back in the writer loop -> a call without a timeout is found.
        $endless = @($script:ModuleAst.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
            $n.Member.Extent.Text -eq 'WaitOne' -and @($n.Arguments).Count -eq 0
        }, $true))
        $endless.Count | Should -Be 0
    }
}
