#Requires -Module Pester

# FIX133 hygiene: the shipped changelog and docs name no tool or process, and no work-note file sits in the product tree.
#   Who gets hurt: a user (and the public repo) reading the changelog; the long technical history is kept privately, outside the tree.

BeforeAll {
    $script:F133Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    # Forbidden words from the owner rule (CHANGELOG-RULE). Built from pieces so this file does not contain them as plain words.
    $words = @('candi' + 'date', 'har' + 'ness', 'smo' + 'ke', 'O' + 'MP', 'Oh My ' + 'Pi', 'Clau' + 'de', 'Son' + 'net', 'Ast' + 'ra', 'Lu' + 'na', 'So' + 'l', 'Op' + 'us', 'Hai' + 'ku', 'Pi on the ' + 'Side', 'PO' + 'TS', 'la' + 'ne', 'coordi' + 'nator', 'Sand' + 'box run')
    $script:F133Forbidden = '(?i)\b(' + ($words -join '|') + ')\b|\bFIX\s?\d+'
    $script:F133Files = @(
        (Join-Path $script:F133Root 'TeknoParrot-Manager-CHANGELOG.txt'),
        (Join-Path $script:F133Root 'docs/wiki-updates/Changelog.md')
    )
}

Describe 'FIX133 shipped changelogs name no tool or process' {
    It 'has no forbidden word or FIX number in either changelog' {
        # Mutation: write "candidate", "harness", "smoke", "OMP" or "FIX133" into either changelog file.
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($file in $script:F133Files) {
            $text = [System.IO.File]::ReadAllText($file)
            foreach ($m in [regex]::Matches($text, $script:F133Forbidden)) { [void]$hits.Add((Split-Path $file -Leaf) + ': ' + $m.Value) }
        }
        $hits.ToArray() | Should -BeNullOrEmpty
    }

    It 'catches a forbidden word when one is planted (the check can fail)' {
        # Mutation: make the pattern match nothing -> the planted text is not reported.
        ('This RC8 ' + 'candi' + 'date fixed it (FIX' + '133)') | Should -Match $script:F133Forbidden
        'Plain words for users' | Should -Not -Match $script:F133Forbidden
    }
}

Describe 'FIX133 no work-note file in the product tree' {
    It 'has no FIX*/ASTRA* result, task, hash or diff file in the repository root' {
        # Mutation: copy any FIX123-RESULT.md or FIXFIX133-HASHES.json into the repository root.
        $lane = @(Get-ChildItem -LiteralPath $script:F133Root -File | Where-Object { $_.Name -match '(?i)^(FIX|ASTRA).+|(-RESULT\.md|-TASK\.md|-HASHES\.json|\.diff)$' } | ForEach-Object { $_.Name })
        $lane | Should -BeNullOrEmpty
    }

    It 'keeps the lane-file ignore rules in .gitignore' {
        # Mutation: delete the /FIX*-RESULT.md, /FIX*-HASHES.json, /FIX*-TASK.md or /FIX*.diff line.
        $ignore = [System.IO.File]::ReadAllText((Join-Path $script:F133Root '.gitignore'))
        foreach ($rule in @('/FIX*-RESULT.md', '/FIX*-HASHES.json', '/FIX*-TASK.md', '/FIX*.diff')) { $ignore | Should -Match ([regex]::Escape($rule)) }
    }
}
