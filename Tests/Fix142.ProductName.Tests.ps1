# The product is called TeknoParrot Manager (TPM where short). Text people read must never call it "the Manager"
# or just "Manager", and must not name HyperSpin, which TeknoParrot Manager does not support.
# Checks run on the whole file text, so a name wrapped across a line break is also caught.
# Allowed: "TeknoParrot Manager", "TeknoParrot-Manager" file names, "TeknoParrot" at the end of one line with
# "Manager" at the start of the next, and code identifiers (Get-ManagerVersionIdentity, $ManagerRoot).
# Allow-list (internal process documents, not read by users): the docs in $internalDocs below and the
# docs\architecture, docs\remediation, docs\governance, docs\adr and docs\templates folders. They are skipped
# by the bare-Manager and HyperSpin checks only. The program file TeknoParrot-Manager.ps1 is skipped by the
# bare-Manager check because it holds code identifiers and internal log lines that say "Manager".
BeforeDiscovery {
    $root = Split-Path -Parent $PSScriptRoot
    $internalDocs = @(
        'ADVERSARIAL-TESTING-PLAN.md', 'CROSS-PROJECT-CERTIFICATION-SUITE-PORTABILITY.md', 'DISCOVERABILITY-BASELINE.md'
    )
    $internalFolders = @('architecture', 'remediation', 'governance', 'adr', 'templates')
    $userFiles = @(
        'TeknoParrot-Manager.ps1', 'TeknoParrot-Manager-CHANGELOG.txt', 'TeknoParrot-Manager-README.txt',
        'TeknoParrot-Manager-QuickStart.txt', 'README.md', 'QUICKSTART.md'
    ) | ForEach-Object { Join-Path $root $_ }
    $docs = @(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Filter '*.md' -File -Recurse)
    $allFiles = @($userFiles) + @($docs | ForEach-Object { $_.FullName })
    $userFiles += @($docs | Where-Object {
            $rel = $_.FullName.Substring($root.Length + 1).Split('\')
            -not ($rel[1] -in $internalFolders) -and -not ($rel.Count -eq 2 -and $rel[1] -in $internalDocs)
        } | ForEach-Object { $_.FullName })
    $script:f142All = @($allFiles | ForEach-Object { @{ Path = $_; Name = $_.Substring($root.Length + 1) } })
    $script:f142User = @($userFiles | ForEach-Object { @{ Path = $_; Name = $_.Substring($root.Length + 1) } })
    $script:f142Guides = @($script:f142User | Where-Object { $_.Name -ne 'TeknoParrot-Manager.ps1' })
}

BeforeAll {
    function Get-F142Hits([string]$Path, [string]$Name, [string]$Pattern, [bool]$CaseSensitive) {
        $text = [System.IO.File]::ReadAllText($Path)
        $options = if ($CaseSensitive) { [Text.RegularExpressions.RegexOptions]::None } else { [Text.RegularExpressions.RegexOptions]::IgnoreCase }
        foreach ($m in [regex]::Matches($text, $Pattern, $options)) {
            $line = 1 + ($text.Substring(0, $m.Index) -split "`n").Count - 1
            "${Name}:${line}: $($m.Value -replace '\s+', ' ')"
        }
    }
    # "the/this/a Manager" (also across a line break), but not a call such as "the manager (" in code text.
    $script:f142TheManager = '\b(the|this|a)\s+manager\b(?!\s*\()'
    # Any "Manager" that does not follow "TeknoParrot" (space, hyphen, dot or line break): "Old Manager names", "Manager's".
    $script:f142BareManager = '(?<!TeknoParrot[\s\-.\\]+)\bManager\b'
}

Describe 'Fix142 product name' {
    It '<Name> never says "the Manager"' -ForEach $script:f142All {
        $hits = @(Get-F142Hits $Path $Name $script:f142TheManager $false)
        $hits.Count | Should -Be 0 -Because ($hits -join "`n")
    }

    It '<Name> never says a bare "Manager"' -ForEach $script:f142Guides {
        $hits = @(Get-F142Hits $Path $Name $script:f142BareManager $true)
        $hits.Count | Should -Be 0 -Because ($hits -join "`n")
    }

    It '<Name> does not name HyperSpin' -ForEach $script:f142User {
        $hits = @(Get-F142Hits $Path $Name 'HyperSpin' $false)
        $hits.Count | Should -Be 0 -Because ($hits -join "`n")
    }
}
