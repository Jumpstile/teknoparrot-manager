#Requires -Module Pester

Describe "Quality engineering system metadata" {
    It "has the regression register and testdata documentation" {
        Test-Path -LiteralPath (Join-Path $PSScriptRoot "..\docs\REGRESSION-REGISTER.md") -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $PSScriptRoot "..\testdata\README.md") -PathType Leaf | Should -BeTrue
    }

    It "has a parseable golden normalization dataset with unique ids" {
        $casePath = Join-Path $PSScriptRoot "..\testdata\golden-normalization-cases.json"
        Test-Path -LiteralPath $casePath -PathType Leaf | Should -BeTrue

        $cases = Get-Content -LiteralPath $casePath -Raw | ConvertFrom-Json
        @($cases).Count | Should -BeGreaterThan 0

        $ids = @($cases | ForEach-Object { $_.id })
        ($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be 0
        ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It "requires core fields on every golden normalization case" {
        $casePath = Join-Path $PSScriptRoot "..\testdata\golden-normalization-cases.json"
        $cases = Get-Content -LiteralPath $casePath -Raw | ConvertFrom-Json
        $allowedStatuses = @('covered','pending-fix','needs-test','investigation')
        $allowedTypes = @('positive-normalization','safety-guard','negative-match','characterization')

        foreach ($case in $cases) {
            [string]::IsNullOrWhiteSpace($case.id) | Should -BeFalse
            [string]::IsNullOrWhiteSpace($case.source) | Should -BeFalse
            [string]::IsNullOrWhiteSpace($case.expectedKey) | Should -BeFalse
            $allowedStatuses | Should -Contain $case.status
            $allowedTypes | Should -Contain $case.caseType
        }
    }

    It "keeps known quality-system files referenced by the register present" {
        $repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
        $required = @(
            'Tests\KnownBugRegression.Tests.ps1',
            'Tests\GoldenNormalization.Tests.ps1',
            'testdata\golden-normalization-cases.json'
        )

        foreach ($relative in $required) {
            Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf | Should -BeTrue
        }
    }
}

Describe "Release Integrity source identity" {
    BeforeAll {
        $script:RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
        $script:ExpectedDisplayVersion = 'v1.0 RC3'
        $script:ExpectedTag = 'v1.0-RC3'
        $script:ExpectedZipName = 'TeknoParrot Manager v1.0 RC3.zip'
    }

    It "keeps the production script header, runtime label, banner, and console preview on the same release identity" {
        $scriptPath = Join-Path $script:RepoRoot 'TeknoParrot-Manager.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should -Match ([regex]::Escape("# TeknoParrot Manager  |  $script:ExpectedDisplayVersion"))
        $content | Should -Match '\$ScriptVersion\s*=\s*"1\.0"'
        $content | Should -Match '\$ReleaseCandidateLabel\s*=\s*"RC3"'
        $content | Should -Match 'Get-ManagerVersionLine'
        $content | Should -Not -Match 'TeknoParrot Manager\s+v\$ScriptVersion RC1'
        $previewPath = Join-Path $script:RepoRoot 'scripts\Preview-TPM-ConsoleUx.ps1'
        $preview = Get-Content -LiteralPath $previewPath -Raw
        $preview | Should -Match ([regex]::Escape($script:ExpectedDisplayVersion))
    }
    It "keeps RC3 preparation documentation truthful and aligned with the intended tag" {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw
        $topReadme = ($readme -split "`r?`n" | Select-Object -First 30) -join "`n"

        $topReadme | Should -Match ([regex]::Escape($script:ExpectedDisplayVersion))
        $topReadme | Should -Match ([regex]::Escape($script:ExpectedTag))
        $topReadme | Should -Match 'in preparation'
        $topReadme | Should -Match 'not been published or hardware-certified'
        $topReadme | Should -Not -Match '\[Download v1\.0 RC3\]'
        $topReadme | Should -Not -Match 'v1\.0 RC1|v1\.0-RC1|v1\.0\.RC1'
    }

    It "keeps release guidance files aligned with the current RC identity" {
        $files = @(
            'AGENTS.md',
            'TeknoParrot-Manager-README.txt',
            'TeknoParrot-Manager-QuickStart.txt'
        )

        foreach ($relative in $files) {
            $content = Get-Content -LiteralPath (Join-Path $script:RepoRoot $relative) -Raw
            $content | Should -Match ([regex]::Escape($script:ExpectedDisplayVersion))
        }
        $agents = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'AGENTS.md') -Raw
        $agents | Should -Match ([regex]::Escape($script:ExpectedZipName))
    }

    It "keeps the RC3 changelog and release-package defaults aligned with the source identity" {
        $changelog = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'TeknoParrot-Manager-CHANGELOG.txt') -Raw
        $wikiChangelog = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs\wiki-updates\Changelog.md') -Raw
        $releasePackage = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Tests\Test-ReleasePackage.ps1') -Raw

        foreach ($content in @($changelog, $wikiChangelog)) {
            $content | Should -Match 'Unreleased'
            $content | Should -Match ([regex]::Escape($script:ExpectedDisplayVersion))
            $content | Should -Match 'Pester 5\.7\.1'
        }

        $releasePackage | Should -Match ([regex]::Escape($script:ExpectedDisplayVersion))
    }

    It "documents Release Integrity Audit as a mandatory public-release gate" {
        $checklist = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'RELEASE-SAFETY-CHECKLIST.md') -Raw

        $checklist | Should -Match 'Release Integrity Audit'
        $checklist | Should -Match 'Runtime Identity Audit'
        $checklist | Should -Match 'Release Artifact Audit'
    }
}
