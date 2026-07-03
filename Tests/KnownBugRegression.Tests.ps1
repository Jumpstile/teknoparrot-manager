#Requires -Module Pester

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functionAsts) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }
}

Describe "Known bug regressions - game-name normalization" {
    It "strips board-code plus Ver revision tokens from affected titles" {
        (Get-NormalizedGameKey "Tekken 5.1 (TE51 Ver B)(2005)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Tekken 5.1 (2005)[Namco System 246][TP]")

        (Get-NormalizedGameKey "Time Crisis 3 (TST1 Ver A)(2003)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Time Crisis 3 (2003)[Namco System 246][TP]")

        (Get-NormalizedGameKey "Zoids Infinity (B3900076A Ver 2.02J)(2004)[Namco System 246][TP]") |
            Should -Be (Get-NormalizedGameKey "Zoids Infinity (2004)[Namco System 246][TP]")
    }

    It "strips strict hyphenated all-caps board-code tokens" {
        (Get-NormalizedGameKey "Time Crisis 4 (TSF1002-NA-A)(2006)[Namco System 256][TP]") |
            Should -Be (Get-NormalizedGameKey "Time Crisis 4 (2006)[Namco System 256][TP]")
    }

    It "does not strip meaningful parenthesized edition text" {
        Get-NormalizedGameKey "Some Game (Special Edition)" |
            Should -Not -Be (Get-NormalizedGameKey "Some Game")
    }

    It "keeps Zoids Infinity EX Plus distinct from plain Zoids Infinity" {
        Get-NormalizedGameKey "Zoids Infinity EX Plus (2004)[Namco System 246][TP]" |
            Should -Be "zoidsinfinityexplus"

        Get-NormalizedGameKey "Zoids Infinity EX Plus (2004)[Namco System 246][TP]" |
            Should -Not -Be (Get-NormalizedGameKey "Zoids Infinity (2004)[Namco System 246][TP]")
    }

    It "preserves Rev-letter tokens that are intentionally not stripped" {
        Get-NormalizedGameKey "Game (Rev C)" | Should -Be "gamerevc"
        Get-NormalizedGameKey "Game (Rev. C)" | Should -Be "gamerevc"
        Get-NormalizedGameKey "Game (Rev E)" | Should -Be "gamereve"
    }
}
