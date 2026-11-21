#Requires -Module Pester

# Screen inventory guard. A fixed Write-Host line wider than the default 80-column console (79 usable cells)
# wraps in the middle of a word. Lines that adapt to the window width are covered by their own tests; this guard
# keeps the number of fixed-width lines from growing. When you shorten or wrap some of these lines, lower the
# number below. Never raise it: wrap the new text with Write-TpmText instead.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix411 bootstrap could not parse the manager.' }
    $script:F411Wide = @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Host' -and
        $node.CommandElements.Count -ge 2 -and
        $node.CommandElements[1] -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
        $node.CommandElements[1].Value.Length -gt 79
    }, $true))
    $script:F411Baseline = 243
}

Describe 'Fixed-width screen lines do not grow past the default console width' {
    It 'has no more fixed Write-Host lines over 79 characters than the recorded count' {
        $lines = @($script:F411Wide | ForEach-Object { $_.Extent.StartLineNumber })
        $lines.Count | Should -BeLessOrEqual $script:F411Baseline -Because ('new wide lines start at: ' + (($lines | Select-Object -Last 10) -join ', '))
    }
}
