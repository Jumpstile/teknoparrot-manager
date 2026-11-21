#Requires -Module Pester

# Issue 386: American English everywhere in the product's own text. The standing rule says screens, docs and code comments use
# American spelling. Identifier names that other code depends on (the Cancelled state, the Get-PostgresRestoreJudgement function,
# the shader names Colourfulness and colour_space that come from other projects) are not text and are left as they are.
# Mutation: put "normalised", "behaviour", "recognises", "labelled" or "licence" back into any shipped text file -> this fails.

BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:f386Files = @(
        'TeknoParrot-Manager.ps1', 'TeknoParrot-Manager-README.txt', 'TeknoParrot-Manager-QuickStart.txt',
        'TeknoParrot-Manager-CHANGELOG.txt', 'README.md', 'QUICKSTART.md', 'docs\wiki-updates\Changelog.md', 'docs\USER-GUIDE.md', 'docs\TESTER-GUIDE.md', 'scripts\TpmProgress.psm1'
    ) | ForEach-Object { [pscustomobject]@{ Name = $_; Text = [System.IO.File]::ReadAllText((Join-Path $root $_)) } }
}

Describe 'Shipped text uses American spelling (issue 386)' {
    It 'has no British spellings in any shipped text file' {
        # Case-sensitive on purpose so identifiers such as Get-PostgresRestoreJudgement and the shader name Colourfulness do not count.
        $pattern = '(recognis|Recognis|normalis|Normalis|behaviour|(?<!Mono)Behaviour|organis|Organis|labelled|Labelled|judgement|licence|Licence|colour(?!_space)|Colour(?!fulness))'
        $found = New-Object System.Collections.Generic.List[string]
        foreach ($file in $script:f386Files) {
            foreach ($m in [regex]::Matches($file.Text, $pattern)) {
                $lineStart = $file.Text.LastIndexOf("`n", $m.Index) + 1
                $lineEnd = $file.Text.IndexOf("`n", $m.Index); if ($lineEnd -lt 0) { $lineEnd = $file.Text.Length }
                $line = $file.Text.Substring($lineStart, $lineEnd - $lineStart).Trim()
                # A shader or file name that belongs to another project (CrosireLegacy.Colourfulness, Colourfulness.fx) is not our spelling.
                if ($line -match 'Colourfulness' -and $m.Value -ceq 'Colour') { continue }
                if ($line.Length -gt 120) { $line = $line.Substring(0, 120) }
                [void]$found.Add(('{0}: {1}' -f $file.Name, $line))
            }
        }
        $found | Should -BeNullOrEmpty
    }

    It 'says canceled, not cancelled, in sentences and comments' {
        $found = New-Object System.Collections.Generic.List[string]
        foreach ($file in $script:f386Files) {
            foreach ($m in [regex]::Matches($file.Text, '\b(was|were|is|been|be) cancelled\b|failed/cancelled|\bcancelled (before|by|at|the)\b')) {
                [void]$found.Add(('{0}: {1}' -f $file.Name, $m.Value))
            }
        }
        $found | Should -BeNullOrEmpty
    }
}
