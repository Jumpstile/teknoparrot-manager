#Requires -Module Pester
# Issue 347: when the status footer cannot be pinned to the console (or its pinned draw fails), the plain-text fallback must still show every
# status row, including the third row that carries the data-safety or next-step line. Before, only the first row was written.
# Fake-only: a scripted draw adapter and captured host output; no real console, no TeknoParrot, no LaunchBox.
# What this CANNOT prove: the native RawUI draw, in-place update and clear on a real PS 5.1 / PS 7 console (the ConsoleHost test in
# TeknoParrot-Manager.Tests.ps1 covers that when run in a live console). NOT RUN yet.
BeforeAll {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $script:f347Source = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
    $wanted = @('Write-TpmWorkflowStatusRowsAppend', 'Render-TpmWorkflowStatus')
    $texts = foreach ($name in $wanted) {
        $found = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $name }, $true))
        if ($found.Count -ne 1) { throw "Expected exactly one $name." }
        $found[0].Extent.Text
    }
    $functionPath = Join-Path $TestDrive 'fix347-footer-functions.ps1'
    $texts -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath

    function Get-TpmWorkflowConsoleCapability { param($Facts) [pscustomobject]@{ Mode = 'CursorFooter'; Reason = ''; Width = 100; Height = 30 } }
    function Get-TpmWorkflowStatusSnapshot { param($Context) [pscustomobject]@{} }
    function Format-TpmWorkflowStatusRows { param($Snapshot, $Width) return @('status line', 'Step 2 of 3 | Needs attention | Retry', 'Data safety: your files were not changed') }
    function Clear-TpmWorkflowFooter { param($Context) $Context.FooterBounds = $null }
}

Describe 'Issue 347 status footer fallback keeps every row' {
    It 'append-only output writes all three rows, with the safety row last' {
        $rows = @('row one', 'row two', 'Data safety: nothing was changed')
        $shown = @(& { Write-TpmWorkflowStatusRowsAppend -Rows $rows } 6>&1 | ForEach-Object { [string]$_ })
        $shown | Should -Be $rows
    }

    It 'a failed pinned draw falls back to all rows, not only the first' {
        $script:f347Appended = $null
        $adapter = @{
            Draw = { param($rows, $capability) throw 'draw is not supported here' }
            Clear = { param($bounds) }
            Append = { param($rows) $script:f347Appended = @($rows) }
        }
        $context = [pscustomobject]@{ ConsoleFacts = [pscustomobject]@{ Adapter = $adapter }; FooterBounds = $null; FooterRows = @(); RendererMode = 'CursorFooter' }
        Render-TpmWorkflowStatus -Context $context
        $context.RendererMode | Should -Be 'TemporaryAppendOnly'
        @($script:f347Appended).Count | Should -Be 3
        (@($script:f347Appended) -join "`n") | Should -Match 'Data safety: your files were not changed'
    }
}

Describe 'Issue 347 extraction progress never uses the native progress panel' {
    It 'the script has no native Write-Progress call (extraction reports through the compact renderer and the workflow group)' {
        $script:f347Source | Should -Not -Match '(?m)^\s*Write-Progress\b'
        $script:f347Source | Should -Not -Match '\|\s*Write-Progress\b'
    }
}
