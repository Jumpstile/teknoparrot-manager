param([string]$RepositoryRoot = [IO.Path]::GetDirectoryName($PSScriptRoot))
BeforeAll {
    $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $RepositoryRoot 'TeknoParrot-Manager.ps1'),[ref]$null,[ref]$parseErrors)
    if(@($parseErrors).Count){throw 'Main parse failed.'}
    # FIX52 (#384): default detection also asks Test-TpmConsoleTerminalHosted, which reads the console window class through the
    # Get-TpmConsoleWindowClass seam; the fake below answers for a classic conhost window unless a test says otherwise.
    $definition=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -cin @('Set-ConsoleMaximizedIfSupported','Test-TpmConsoleTerminalHosted')})
    if($definition.Count -ne 2){throw 'Expected the production resize function and its terminal detection.'}
    foreach($item in $definition){. ([scriptblock]::Create($item.Extent.Text))}
    function Write-Log {param([string]$Message) $script:ViewportLog=$Message}
    function Get-TpmConsoleWindowClass {return $script:ViewportWindowClass}
    if(-not ('TpmViewportRawUi' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Management.Automation.Host;
public sealed class TpmViewportRawUi {
    public Size MaxPhysicalWindowSize {get;set;}
    public readonly List<string> Writes = new List<string>();
    public bool ThrowOnBuffer;
    private Size buffer, window;
    public Size BufferSize {get {return buffer;} set {Writes.Add("buffer"); if(ThrowOnBuffer)throw new InvalidOperationException("owned resize failure");buffer=value;}}
    public Size WindowSize {get {return window;} set {Writes.Add("window");window=value;}}
}
'@
    }
    function New-ViewportFixture([int]$MaximumWidth=1904,[int]$MaximumHeight=993){
        $raw=New-Object TpmViewportRawUi
        $raw.MaxPhysicalWindowSize=[Management.Automation.Host.Size]::new($MaximumWidth,$MaximumHeight)
        $raw.BufferSize=[Management.Automation.Host.Size]::new(120,40)
        $raw.WindowSize=[Management.Automation.Host.Size]::new(120,40)
        $raw.Writes.Clear()
        return $raw
    }
}
Describe 'Windows Terminal viewport preservation and legacy resize contract' {
    BeforeEach {
        $script:PriorWtSession=$env:WT_SESSION;$script:PriorWtProfile=$env:WT_PROFILE_ID;$script:PriorTermProgram=$env:TERM_PROGRAM
        $env:WT_PROFILE_ID=$null;$env:TERM_PROGRAM=$null
        $script:ViewportWindowClass='ConsoleWindowClass';$script:TpmConsoleResizeAttempted=$false;$script:ViewportLog=$null
    }
    AfterEach {$env:WT_SESSION=$script:PriorWtSession;$env:WT_PROFILE_ID=$script:PriorWtProfile;$env:TERM_PROGRAM=$script:PriorTermProgram;$script:TpmConsoleResizeAttempted=$false}
    It 'preserves the actual observed WT viewport despite an inflated hardware maximum by default detection' {
        $env:WT_SESSION='owned-test-session'
        $raw=New-ViewportFixture
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        $raw.WindowSize.Width|Should -Be 120
        $raw.WindowSize.Height|Should -Be 40
        $raw.BufferSize.Width|Should -Be 120
        $raw.BufferSize.Height|Should -Be 40
        $raw.Writes.Count|Should -Be 0
        $script:TpmConsoleResizeAttempted|Should -BeTrue
    }
    It 'can exercise terminal-managed behavior without changing the host environment' {
        $env:WT_SESSION=$null
        $raw=New-ViewportFixture
        Set-ConsoleMaximizedIfSupported -RawUi $raw -TerminalManaged $true
        $raw.WindowSize.Width|Should -Be 120
        $raw.WindowSize.Height|Should -Be 40
        $raw.Writes.Count|Should -Be 0
    }
    It 'preserves explicit legacy buffer-before-window growth and the once guard even in a WT test runner' {
        $env:WT_SESSION='owned-test-session'
        $raw=New-ViewportFixture 160 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw -TerminalManaged $false
        ($raw.Writes -join ',')|Should -Be 'buffer,window'
        $raw.BufferSize.Width|Should -Be 160
        $raw.BufferSize.Height|Should -Be 50
        $raw.WindowSize.Width|Should -Be 160
        $raw.WindowSize.Height|Should -Be 50
        $raw.MaxPhysicalWindowSize=[Management.Automation.Host.Size]::new(180,60)
        Set-ConsoleMaximizedIfSupported -RawUi $raw -TerminalManaged $false
        $raw.Writes.Count|Should -Be 2
        $raw.WindowSize.Width|Should -Be 160
        $raw.WindowSize.Height|Should -Be 50
    }
    It 'retains default legacy behavior when Windows Terminal identity is absent' {
        $env:WT_SESSION=$null
        $raw=New-ViewportFixture 160 50
        Set-ConsoleMaximizedIfSupported -RawUi $raw
        ($raw.Writes -join ',')|Should -Be 'buffer,window'
        $raw.WindowSize.Width|Should -Be 160
        $raw.WindowSize.Height|Should -Be 50
    }
    It 'does not assign an invalid legacy maximum' {
        $raw=New-ViewportFixture 0 0
        Set-ConsoleMaximizedIfSupported -RawUi $raw -TerminalManaged $false
        $raw.Writes.Count|Should -Be 0
        $script:TpmConsoleResizeAttempted|Should -BeTrue
    }
    It 'retains logged best-effort legacy failures without a window assignment' {
        $raw=New-ViewportFixture 160 50
        $raw.ThrowOnBuffer=$true
        {Set-ConsoleMaximizedIfSupported -RawUi $raw -TerminalManaged $false}|Should -Not -Throw
        ($raw.Writes -join ',')|Should -Be 'buffer'
        $raw.WindowSize.Width|Should -Be 120
        $script:ViewportLog|Should -Match 'Set-ConsoleMaximizedIfSupported: could not resize console'
    }
}
