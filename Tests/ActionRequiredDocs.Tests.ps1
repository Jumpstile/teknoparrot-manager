#Requires -Module Pester

# The Action Required rows in README.md and docs/USER-GUIDE.md must use the words the program really shows (issue 260).
BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $script:source = [IO.File]::ReadAllText((Join-Path $root 'TeknoParrot-Manager.ps1'))
    $script:docs = @(
        @{ Name = 'README.md'; Text = [IO.File]::ReadAllText((Join-Path $root 'README.md')) }
        @{ Name = 'docs/USER-GUIDE.md'; Text = [IO.File]::ReadAllText((Join-Path $root 'docs/USER-GUIDE.md')) }
    )

    # The sentences of the TeknoParrot first-time setup note, read from the program.
    $fn = [regex]::Match($script:source, '(?s)function Get-TeknoParrotWizardAdviceLines.*?\r?\n\}\r?\n')
    $script:wizardLines = @([regex]::Matches($fn.Value, "(?m)^\s*\(?'([^']{20,})'") | ForEach-Object { $_.Groups[1].Value.Trim() })

    # The pieces of each row title that are fixed words (text in brackets changes per game or per emulator).
    function Get-RowTitlePieces {
        param([string]$Text)
        $section = [regex]::Match($Text, '(?s)## Action Required Summary(.*?)### More detail: Action Required Summary').Groups[1].Value
        foreach ($m in [regex]::Matches($section, '(?m)^\| \*\*(.+?)\*\* \|')) {
            foreach ($piece in ($m.Groups[1].Value -split '\s*\(.*?\)\s*')) {
                $clean = $piece.Trim(' ', ':')
                if ($clean) { $clean }
            }
        }
    }
}

Describe 'Action Required rows match the program' {
    It 'the program has the first-time setup note this test reads' {
        $script:wizardLines.Count | Should -BeGreaterOrEqual 5
    }

    It '<Name> shows every sentence of the TeknoParrot first-time setup note' -ForEach $script:docs {
        $missing = @($script:wizardLines | Where-Object { $Text.IndexOf($_, [StringComparison]::Ordinal) -lt 0 })
        $missing.Count | Should -Be 0 -Because ($missing -join "`n")
    }

    It '<Name> names every Action Required row the way the program does' -ForEach $script:docs {
        $pieces = @(Get-RowTitlePieces -Text $Text)
        $pieces.Count | Should -BeGreaterThan 10
        $missing = @($pieces | Where-Object { $script:source.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -lt 0 })
        $missing.Count | Should -Be 0 -Because ($missing -join "`n")
    }
}
