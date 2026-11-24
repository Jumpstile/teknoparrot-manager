#Requires -Module Pester

# FIX131: repo hygiene guards.
#   S14 The release ZIP is built from an explicit allowlist (Get-TPMReleasePackageFileMapV1). Internal role, machine and lane documents
#       (AGENTS.md, CODEX.md, CHATGPT.md, TEST-PC-*.md, fix-run result and task files ...) must never be on it, and no packaged text may
#       name a private repository. Every PowerShell module must use Windows line endings, and .gitattributes must say so.
#   N11 The product does not ship, add or restore a Target Toss Pro "Bags" profile (owner decision). The docs may still say which games
#       need PostgreSQL, but must not say TeknoParrot Manager adds or restores that profile.
# What this CANNOT prove: that no private name exists in a file outside the allowlist (those files are not published by the builder), or that
# a private identifier without a recognizable shape is absent (see TPM_PACKAGE_PRIVATE_TOKENS in the release-package leak detector).
# Each It names the mutation that makes it fail.

BeforeAll {
    $script:F131Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    Import-Module (Join-Path $script:F131Root 'scripts/TPMReleasePackage.Core.psm1') -Force
    $script:F131Map = @(Get-TPMReleasePackageFileMapV1 -SourceRoot $script:F131Root)

    # Internal documents and lane artifacts. Matched against the file name (last path part).
    $script:F131InternalName = '(?i)^(AGENTS|CODEX|CHATGPT|CLAUDE|CONSTITUTION|ARCHITECTURE|PREFERENCES|INVENTORY_STANDARDS|LESSONS_LEARNED|RELEASE-SAFETY-CHECKLIST|ENGINEERING_.+|INDEPENDENT_.+|SPECIFICATION_.+)\.md$|(?i)^TEST-PC-.+\.md$|(?i)^(FIX|ASTRA).+|(?i)(-RESULT\.md|-TASK\.md|-HASHES\.json|\.diff)$'
    # Folders that hold governance, review or test material, never product files. Matched against the start of the ZIP path.
    $script:F131InternalFolder = '(?i)^(\.omp|\.github|\.worktrees|Tests|testdata|certification|quality|contracts|docs/(governance|remediation|adr|wiki-updates))/'
    $script:F131PrivateRepoName = '(?i)private-backup|private-work-backup|pi-on-the-side|teknoparrot-manager-rc8'

    function Get-F131StringText {
        param([Parameter(Mandatory)][string[]]$Files)
        $kinds = @('StringLiteral', 'StringExpandable', 'HereStringLiteral', 'HereStringExpandable')
        $text = New-Object System.Text.StringBuilder
        foreach ($file in $Files) {
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
            @($parseErrors).Count | Should -Be 0 -Because $file
            foreach ($token in $tokens) { if ($kinds -contains [string]$token.Kind) { [void]$text.AppendLine([string]$token.Value) } }
        }
        return $text.ToString()
    }
}

Describe 'FIX131 S14 the release package allowlist keeps internal documents out' {
    It 'lists no internal role, machine, lane or result document, by file name or by folder' {
        # Mutation: add 'AGENTS.md' (or CODEX.md, CHATGPT.md, a TEST-PC-*.md, a FIX*-RESULT.md) to the root file list of Get-TPMReleasePackageFileMapV1,
        # or map a file under Tests\, certification\ or docs\governance\ into the ZIP -> that entry is listed here.
        $leaks = New-Object System.Collections.Generic.List[string]
        foreach ($item in $script:F131Map) {
            foreach ($path in @([string]$item.ZipPath, [string]$item.SourcePath)) {
                if ([System.IO.Path]::GetFileName($path) -match $script:F131InternalName) { [void]$leaks.Add($path) }
            }
            if ([string]$item.ZipPath -match $script:F131InternalFolder) { [void]$leaks.Add([string]$item.ZipPath) }
        }
        @($leaks | Select-Object -Unique) | Should -BeNullOrEmpty
    }

    It 'still finds an internal document when one is planted on the list (the check can fail)' {
        # Mutation: make the name pattern match nothing -> the planted entries are not reported.
        $planted = @('AGENTS.md', 'CODEX.md', 'CHATGPT.md', 'TEST-PC-CLAUDE.md', 'TEST-PC-CHATGPT.md', 'FIX123-RESULT.md', 'FIXFIX130-HASHES.json', 'ASTRA-SCAN-RESULT.md', 'CONSTITUTION.md')
        @($planted | Where-Object { $_ -notmatch $script:F131InternalName }) | Should -BeNullOrEmpty
        @('TeknoParrot-Manager.ps1', 'TeknoParrot-Manager-CHANGELOG.txt', 'docs/START-HERE.md', 'docs/TROUBLESHOOTING.md', 'LICENSE') | Where-Object { $_ -match $script:F131InternalName } | Should -BeNullOrEmpty
        ('docs/governance/tpm-contract-types.md' -match $script:F131InternalFolder) | Should -BeTrue
        ('docs/START-HERE.md' -match $script:F131InternalFolder) | Should -BeFalse
    }

    It 'names no private repository in any packaged file or path' {
        # Mutation: ship a file that names a private backup repository (an old role document named three), or paste one of those names into a packaged document or comment.
        $textExtensions = @('.ps1', '.psm1', '.md', '.txt', '.json', '.bat', '.svg')
        $hits = New-Object System.Collections.Generic.List[string]
        foreach ($item in $script:F131Map) {
            if ([string]$item.ZipPath -match $script:F131PrivateRepoName) { [void]$hits.Add('path: ' + $item.ZipPath) }
            $source = Join-Path $script:F131Root ([string]$item.SourcePath).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            if ($textExtensions -notcontains [System.IO.Path]::GetExtension($source).ToLowerInvariant()) { continue }
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            if ([System.IO.File]::ReadAllText($source) -match $script:F131PrivateRepoName) { [void]$hits.Add('text: ' + $item.ZipPath) }
        }
        $hits.ToArray() | Should -BeNullOrEmpty
    }

    It 'maps only files that exist in the source tree' {
        # Mutation: list a file that is not in the repository -> the build would fail late; listed here first.
        $missing = @($script:F131Map | Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:F131Root ([string]$_.SourcePath).Replace('/', [System.IO.Path]::DirectorySeparatorChar)) -PathType Leaf) } | ForEach-Object { [string]$_.SourcePath })
        $missing | Should -BeNullOrEmpty
    }
}

Describe 'FIX131 S14 every PowerShell module uses Windows line endings' {
    It 'has no module (psm1) with a bare line feed, and .gitattributes says psm1 is CRLF' {
        # Mutation: save any module with LF line endings, or drop the '*.psm1 text eol=crlf' line from .gitattributes (the checkout would then follow text=auto).
        $modules = @(Get-ChildItem -LiteralPath $script:F131Root -Recurse -File -Filter '*.psm1' | Where-Object { $_.FullName -notmatch '[\\/]\.(git|worktrees)[\\/]' })
        $modules.Count | Should -BeGreaterThan 10
        $lf = New-Object System.Collections.Generic.List[string]
        foreach ($module in $modules) {
            $text = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString([System.IO.File]::ReadAllBytes($module.FullName))
            if ([regex]::IsMatch($text, "(?<!`r)`n") -or [regex]::IsMatch($text, "`r(?!`n)")) { [void]$lf.Add($module.Name) }
        }
        $lf.ToArray() | Should -BeNullOrEmpty
        $rule = @([System.IO.File]::ReadAllLines((Join-Path $script:F131Root '.gitattributes')) | Where-Object { ($_ -split '\s+')[0] -ceq '*.psm1' })
        $rule.Count | Should -Be 1
        ($rule[0] -split '\s+') | Should -Contain 'eol=crlf'
    }
}

Describe 'FIX131 N11 no Target Toss Pro Bags profile is shipped, added or restored' {
    It 'has no Bags profile or database name in any string the product can use' {
        # Mutation: add 'TargetTossProBags' or 'GameDBBags' to a game list, known-limit list or restore list of the main script or a module.
        $files = @((Join-Path $script:F131Root 'TeknoParrot-Manager.ps1')) + @(Get-ChildItem -LiteralPath (Join-Path $script:F131Root 'scripts'), (Join-Path $script:F131Root 'tools') -Filter '*.psm1' -File | ForEach-Object { $_.FullName })
        $productText = Get-F131StringText -Files $files
        $productText | Should -Not -Match '(?i)TargetTossProBags|GameDBBags|BagsToss'
    }

    It 'never says in a guide that TeknoParrot Manager adds, restores or installs a Bags profile' {
        # Mutation: write "TeknoParrot Manager restores the Target Toss Pro Bags profile" (or adds, installs, ships, copies it) into any guide, wiki page or changelog line that mentions Bags.
        $guides = @(
            'README.md', 'QUICKSTART.md', 'TeknoParrot-Manager-README.txt', 'TeknoParrot-Manager-QuickStart.txt', 'TeknoParrot-Manager-CHANGELOG.txt'
        ) | ForEach-Object { Join-Path $script:F131Root $_ }
        $guides += @(Get-ChildItem -LiteralPath (Join-Path $script:F131Root 'docs') -Recurse -File | Where-Object { $_.Extension -in @('.md', '.txt') -and $_.FullName -notmatch '[\\/]docs[\\/](governance|remediation|adr)[\\/]' } | ForEach-Object { $_.FullName })
        $claims = New-Object System.Collections.Generic.List[string]
        foreach ($guide in $guides) {
            $lineNumber = 0
            foreach ($line in [System.IO.File]::ReadAllLines($guide)) {
                $lineNumber++
                if ($line -match '(?i)\bBags\b' -and $line -match '(?i)\b(add|adds|added|restore|restores|restored|install|installs|installed|ship|ships|shipped|bundle|bundles|bundled|copy|copies|copied|deploy|deploys|deployed)\b') {
                    # The changelog line that says the Bags database was REMOVED from the accepted limits is the opposite claim.
                    if ($line -match '(?i)no longer') { continue }
                    [void]$claims.Add(('{0}:{1}' -f [System.IO.Path]::GetFileName($guide), $lineNumber))
                }
            }
        }
        $claims.ToArray() | Should -BeNullOrEmpty
    }
}

Describe 'Private engineering documents are not in the public repository' {
    It 'has no role, workflow or reference document left in the tree' {
        # Mutation: put AGENTS.md, CHATGPT.md, CODEX.md, PREFERENCES.md, a TEST-PC-*.md, docs/ENGINEERING-WORKFLOW.md, the release audit or a docs/governance/reference folder back.
        $private = @('AGENTS.md', 'CHATGPT.md', 'CODEX.md', 'PREFERENCES.md', 'TEST-PC-CHATGPT.md', 'TEST-PC-CLAUDE.md',
            'docs/ENGINEERING-WORKFLOW.md', 'docs/Setting-Up-Automated-Testing-for-TeknoParrot-Manager.md', 'docs/RELEASE-RETROSPECTIVE-v1.0-RC2.1.md', 'docs/RELEASE-INTEGRITY-AUDIT-v1.0-RC2.md', 'docs/governance/reference')
        $present = @($private | Where-Object { Test-Path -LiteralPath (Join-Path $script:F131Root $_) })
        $present | Should -BeNullOrEmpty
    }

    It 'names no AI tool in a root document or any file under docs' {
        # Mutation: write ChatGPT, Claude, Codex, DeepSeek or OMP into a root .md/.txt file or into any .md/.txt/.json/.ps1 file under docs.
        $files = @(Get-ChildItem -LiteralPath $script:F131Root -File | Where-Object { $_.Extension -in @('.md', '.txt', '.bat') -and $_.Name -notmatch '-(RESULT|TASK)\.md$' })
        $files += @(Get-ChildItem -LiteralPath (Join-Path $script:F131Root 'docs') -Recurse -File | Where-Object { $_.Extension -in @('.md', '.txt', '.json', '.ps1') })
        $files.Count | Should -BeGreaterThan 20
        $hits = @($files | Where-Object { [System.IO.File]::ReadAllText($_.FullName) -cmatch 'ChatGPT|Claude|Codex|DeepSeek|OpenAI|Anthropic|\bOMP\b|Pi on the Side' } | ForEach-Object { $_.FullName.Substring($script:F131Root.Length + 1) })
        $hits | Should -BeNullOrEmpty
    }
}
