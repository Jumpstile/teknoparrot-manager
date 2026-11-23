# The product is called TeknoParrot Manager or TPM. Text people read must never call it "the Manager".
# Allow-list (file name -> reason): none needed today.
BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $files = @(
        'TeknoParrot-Manager.ps1', 'TeknoParrot-Manager-CHANGELOG.txt', 'TeknoParrot-Manager-README.txt',
        'TeknoParrot-Manager-QuickStart.txt', 'README.md', 'QUICKSTART.md'
    ) | ForEach-Object { Join-Path $root $_ }
    $files += @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Filter '*.md' -File -Recurse | ForEach-Object { $_.FullName })
    $script:f142Cases = @($files | ForEach-Object { @{ Path = $_; Name = $_.Substring($root.Length + 1) } })
}

Describe 'Fix142 product name' {
    It '<Name> never says "the Manager"' -ForEach $script:f142Cases {
        $hits = New-Object System.Collections.Generic.List[string]
        $n = 0
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            $n++
            if ($line -match '(?i)\b(the|this|a) manager\b(?!\s*\()' -and $line -notmatch '(?i)\b(task|package|device|download|service|release) manager') { $hits.Add("${Name}:${n}: $($line.Trim())") }
        }
        $hits.Count | Should -Be 0 -Because ($hits -join "`n")
    }
}
