#Requires -Module Pester
# FIX52 (issue #384): TeknoParrot Manager's startup maximize must never resize a console that a terminal owns. Measured on the test PC: a
# .bat double-clicked in Explorer opens in Windows Terminal through the default-terminal hand-off WITHOUT WT_SESSION; its console window
# class is 'PseudoConsoleWindow'; the old WT_SESSION-only check let Set-ConsoleMaximizedIfSupported resize it to MaxPhysicalWindowSize
# (1904x993) while the terminal window stayed 120 columns wide. Fake-only: the three production functions are extracted from the AST, the
# window class comes from a mocked seam, and the RawUI is a recording fake. No real console is read or resized.
BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) { throw 'FIX52 bootstrap could not parse the production script.' }
    $names = @('Set-ConsoleMaximizedIfSupported', 'Test-TpmConsoleTerminalHosted', 'Get-TpmConsoleWindowClass')
    $definitions = @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -cin $names })
    if ($definitions.Count -ne $names.Count) { throw 'FIX52 bootstrap expected exactly one definition of each console-size function.' }
    foreach ($definition in $definitions) { . ([scriptblock]::Create($definition.Extent.Text)) }
    function Write-Log { param([string]$Message) [void]$script:Fix52Log.Add($Message) }
    if (-not ('Fix52RawUi' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Management.Automation.Host;
public sealed class Fix52RawUi {
    public Size MaxPhysicalWindowSize { get; set; }
    public readonly List<string> Writes = new List<string>();
    private Size buffer, window;
    public Size BufferSize { get { return buffer; } set { Writes.Add("buffer " + value.Width + "x" + value.Height); buffer = value; } }
    public Size WindowSize { get { return window; } set { Writes.Add("window " + value.Width + "x" + value.Height); window = value; } }
}
'@
    }
    # The test-PC measurement: console 120x30, MaxPhysicalWindowSize 1904x993 (handoff-probe.log, 2026-11-02 12:33).
    function New-Fix52RawUi {
        param([int]$MaxWidth = 1904, [int]$MaxHeight = 993)
        $raw = New-Object Fix52RawUi
        $raw.MaxPhysicalWindowSize = [System.Management.Automation.Host.Size]::new($MaxWidth, $MaxHeight)
        $raw.BufferSize = [System.Management.Automation.Host.Size]::new(120, 30)
        $raw.WindowSize = [System.Management.Automation.Host.Size]::new(120, 30)
        $raw.Writes.Clear()
        return $raw
    }
}

Describe 'FIX52 startup maximize inside a terminal hand-off' {
    BeforeEach {
        $script:Fix52Saved = @{}
        foreach ($name in @('WT_SESSION', 'WT_PROFILE_ID', 'TERM_PROGRAM')) {
            $script:Fix52Saved[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        $script:Fix52Class = 'PseudoConsoleWindow'
        $script:Fix52Log = New-Object System.Collections.Generic.List[string]
        $script:TpmConsoleResizeAttempted = $false
        Mock Get-TpmConsoleWindowClass { $script:Fix52Class }
    }
    AfterEach {
        foreach ($name in @('WT_SESSION', 'WT_PROFILE_ID', 'TERM_PROGRAM')) { [Environment]::SetEnvironmentVariable($name, $script:Fix52Saved[$name]) }
        $script:TpmConsoleResizeAttempted = $false
    }

    It 'does not resize a pseudo console when WT_SESSION is unset (the owner''s double-clicked .bat in Windows Terminal)' {
        # Mutation: drop the window-class check from Test-TpmConsoleTerminalHosted (back to WT_SESSION only) -> buffer and window are set
        # to 1904x993, the measured #384 state.
        $raw = New-Fix52RawUi
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        $raw.Writes.Count | Should -Be 0 -Because 'a terminal-hosted console keeps the size its terminal gave it'
        $raw.WindowSize.Width | Should -Be 120
        $raw.WindowSize.Height | Should -Be 30
        $raw.BufferSize.Width | Should -Be 120
        $script:TpmConsoleResizeAttempted | Should -BeTrue
        @($script:Fix52Log | Where-Object { $_ -match 'hosted by a terminal' }).Count | Should -Be 1
    }

    It 'still maximizes a classic conhost window exactly as before (buffer first, then window)' {
        # Mutation: make Test-TpmConsoleTerminalHosted return $true for every class -> no RawUI write in classic conhost.
        $script:Fix52Class = 'ConsoleWindowClass'
        $raw = New-Fix52RawUi -MaxWidth 160 -MaxHeight 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        ($raw.Writes -join ',') | Should -Be 'buffer 160x50,window 160x50'
        $raw.WindowSize.Width | Should -Be 160
        $raw.WindowSize.Height | Should -Be 50
    }

    It 'does not resize when the console window class cannot be read' {
        # Mutation: treat only the class 'PseudoConsoleWindow' as terminal-hosted (instead of everything that is not
        # 'ConsoleWindowClass') -> an unreadable class resizes the console.
        $script:Fix52Class = $null
        $raw = New-Fix52RawUi -MaxWidth 160 -MaxHeight 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        $raw.Writes.Count | Should -Be 0
        $raw.WindowSize.Width | Should -Be 120
    }

    It 'does not resize an unknown window class either' {
        # Mutation: same as above -> a console hosted by another terminal with its own window class is resized.
        $script:Fix52Class = 'SomeOtherTerminalWindow'
        $raw = New-Fix52RawUi -MaxWidth 160 -MaxHeight 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        $raw.Writes.Count | Should -Be 0
    }

    It 'does not resize when <Name> is set, even in a classic conhost window class' -ForEach @(
        @{ Name = 'WT_SESSION'; Value = 'a5c1e0c2-0000-4000-8000-000000000001' }
        @{ Name = 'WT_PROFILE_ID'; Value = '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}' }
        @{ Name = 'TERM_PROGRAM'; Value = 'vscode' }
    ) {
        # Mutation: drop the environment markers from Test-TpmConsoleTerminalHosted (window class only) -> resized.
        [Environment]::SetEnvironmentVariable($Name, $Value)
        $script:Fix52Class = 'ConsoleWindowClass'
        $raw = New-Fix52RawUi -MaxWidth 160 -MaxHeight 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        $raw.Writes.Count | Should -Be 0
        Should -Invoke Get-TpmConsoleWindowClass -Times 0 -Exactly -Because 'an environment marker decides without reading the window class'
    }

    It 'tries only once per run: a later call never resizes, also after the class reads as classic conhost' {
        # Mutation: set TpmConsoleResizeAttempted only after the terminal check (or not at all) -> the second call, now seeing
        # 'ConsoleWindowClass', resizes a console the first call left alone.
        $raw = New-Fix52RawUi -MaxWidth 160 -MaxHeight 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        $script:Fix52Class = 'ConsoleWindowClass'
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        $raw.Writes.Count | Should -Be 0
        $script:TpmConsoleResizeAttempted | Should -BeTrue
    }

    It 'keeps the explicit -TerminalManaged override for tests: $false resizes without asking the window class' {
        # Mutation: ignore -TerminalManaged and always run the detection -> the pseudo-console class blocks the resize.
        $raw = New-Fix52RawUi -MaxWidth 160 -MaxHeight 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw -TerminalManaged $false
        ($raw.Writes -join ',') | Should -Be 'buffer 160x50,window 160x50'
        Should -Invoke Get-TpmConsoleWindowClass -Times 0 -Exactly
    }
}
