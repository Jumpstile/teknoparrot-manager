#Requires -Module Pester

BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
    $script:pdfPath = Join-Path $script:repoRoot 'TeknoParrot-Manager-User-Guide.pdf'
    $script:stampPath = Join-Path $script:repoRoot 'docs/TeknoParrot-Manager-User-Guide.source-sha256'
    $script:guidePath = Join-Path $script:repoRoot 'docs/USER-GUIDE.md'
}

Describe 'User guide PDF shipped in the release package' {
    It 'exists and is a PDF file' {
        Test-Path -LiteralPath $script:pdfPath -PathType Leaf | Should -BeTrue
        $bytes = [IO.File]::ReadAllBytes($script:pdfPath)
        $bytes.Length | Should -BeGreaterThan 100000
        [Text.Encoding]::ASCII.GetString($bytes, 0, 5) | Should -BeExactly '%PDF-'
    }

    It 'was built from the current docs/USER-GUIDE.md (run scripts/New-UserGuidePdf.ps1 after editing the guide)' {
        Test-Path -LiteralPath $script:stampPath -PathType Leaf | Should -BeTrue
        $stamp = ([IO.File]::ReadAllText($script:stampPath)).Trim()
        $current = (Get-FileHash -LiteralPath $script:guidePath -Algorithm SHA256).Hash
        $stamp | Should -BeExactly $current
    }

    It 'is listed in the release package file map as a guide' {
        Import-Module (Join-Path $script:repoRoot 'scripts/TPMReleasePackage.Core.psm1') -Force
        $item = @(Get-TPMReleasePackageFileMapV1 -SourceRoot $script:repoRoot | Where-Object ZipPath -ceq 'TeknoParrot-Manager-User-Guide.pdf')
        $item.Count | Should -Be 1
        $item[0].SourcePath | Should -BeExactly 'TeknoParrot-Manager-User-Guide.pdf'
    }

    It 'was built from a guide with no personal paths, addresses or private names' {
        Import-Module (Join-Path $script:repoRoot 'scripts/TPMReleasePackage.Core.psm1') -Force
        $text = [IO.File]::ReadAllText($script:guidePath)
        $leaks = InModuleScope TPMReleasePackage.Core -Parameters @{ Text = $text } {
            param($Text)
            @(Get-TPMReleasePackagePathLeakPatternsV1 | Where-Object { $Text -match $_.Regex } | ForEach-Object { $_.Label })
        }
        @($leaks).Count | Should -Be 0
    }
}
