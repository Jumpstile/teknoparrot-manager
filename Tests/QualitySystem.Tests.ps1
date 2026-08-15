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
        @($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count | Should -Be 0
        @($ids | Select-Object -Unique).Count | Should -Be $ids.Count
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
    # P1 #3 remediation note: this Describe block previously assumed "the
    # running script's own identity" and "the last actually-published
    # GitHub release" are always the same string. That assumption breaks
    # by design whenever a new RC is in progress in this repository
    # (uncommitted) but not yet published/tagged -- exactly the state this
    # remediation pass introduced (v1.0 RC6 in progress on top of the
    # published v1.0 RC5). Both identities are real, coexisting facts, so
    # this block now tracks them as two separate constants and asserts
    # each file against whichever one it is actually supposed to reflect,
    # instead of asserting they are always identical.
    BeforeAll {
        $script:RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
        # What the running script/tooling actually says right now.
        $script:CurrentSourceVersion = 'v1.0 RC6'
        $script:CurrentSourceRcLabel = 'RC6'
        # The last actually-published, tagged GitHub release. Update this
        # (and the "documentation truthful" assertions below) only when a
        # new release is genuinely published/tagged -- never as a
        # substitute for keeping CurrentSourceVersion in sync with
        # $ReleaseCandidateLabel on every version bump.
        $script:LastPublishedVersion = 'v1.0 RC5'
        $script:LastPublishedRcLabel = 'RC5'
        $script:LastPublishedTag     = 'v1.0-RC5'
        $script:LastPublishedZipName = 'TeknoParrot Manager v1.0 RC5.zip'
    }

    It "keeps the production script header, runtime label, banner, and console preview on the current source identity" {
        $scriptPath = Join-Path $script:RepoRoot 'TeknoParrot-Manager.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $content | Should -Match ([regex]::Escape("# TeknoParrot Manager  |  $script:CurrentSourceVersion"))
        $content | Should -Match '\$ScriptVersion\s*=\s*"1\.0"'
        $content | Should -Match ('\$ReleaseCandidateLabel\s*=\s*"{0}"' -f $script:CurrentSourceRcLabel)
        $content | Should -Match 'Get-ManagerVersionLine'
        $content | Should -Not -Match 'TeknoParrot Manager\s+v\$ScriptVersion RC1'
        $previewPath = Join-Path $script:RepoRoot 'scripts\Preview-TPM-ConsoleUx.ps1'
        $preview = Get-Content -LiteralPath $previewPath -Raw
        $preview | Should -Match ([regex]::Escape($script:CurrentSourceVersion))
    }
    It "keeps published-release documentation truthful about the last actually-published release" {
        $readme = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'README.md') -Raw
        $topReadme = ($readme -split "`r?`n" | Select-Object -First 40) -join "`n"

        $topReadme | Should -Match ([regex]::Escape($script:LastPublishedVersion))
        $topReadme | Should -Match ([regex]::Escape($script:LastPublishedTag))
        # RC5 was validated (exact-SHA static/analysis/Pester evidence, package
        # structure/hash) but not run through a real-hardware certification
        # pass in this environment -- "published and validated" is the honest
        # claim; do not assert "hardware-certified" unless that evidence exists.
        $topReadme | Should -Match 'published and validated'
        # Guards the exact regression class this test previously caught for
        # RC5 (a "published" release whose own docs said "not yet
        # published") -- still scoped to the LAST PUBLISHED version only.
        # It is legitimate, not a regression, for CurrentSourceVersion
        # (RC6) to say "not yet published" while it genuinely is not yet
        # published -- see the next assertion, which requires that.
        $topReadme | Should -Not -Match ($script:LastPublishedRcLabel + '.*(in preparation|not been published|not yet published)|intended tag|tag has not been created')
        $topReadme | Should -Not -Match '\[Download v1\.0 RC5\]'
        $topReadme | Should -Not -Match 'v1\.0 RC1|v1\.0-RC1|v1\.0\.RC1'
        # Positive guard (P1 #3): the top of README.md must explicitly say
        # the current in-progress source version is not yet published, on
        # the same line as its own version string -- so this distinction
        # cannot be silently deleted in a future edit without this test
        # failing (which is exactly the class of drift an independent
        # review flagged this round).
        $topReadme | Should -Match ([regex]::Escape($script:CurrentSourceVersion) + '.*(in progress|not yet published)')
    }

    It "keeps release guidance files' current-source identity aligned with the script" {
        $files = @(
            'AGENTS.md',
            'TeknoParrot-Manager-README.txt',
            'TeknoParrot-Manager-QuickStart.txt',
            'TeknoParrot-Manager.bat'
        )

        foreach ($relative in $files) {
            $content = Get-Content -LiteralPath (Join-Path $script:RepoRoot $relative) -Raw
            $content | Should -Match ([regex]::Escape($script:CurrentSourceVersion))
        }
        $agents = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'AGENTS.md') -Raw
        $currentZipName = "TeknoParrot Manager $($script:CurrentSourceVersion).zip"
        $agents | Should -Match ([regex]::Escape($currentZipName))
    }

    It "keeps the changelog and release-package defaults aligned with the current source identity" {
        $changelog = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'TeknoParrot-Manager-CHANGELOG.txt') -Raw
        $releasePackage = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'Tests\Test-ReleasePackage.ps1') -Raw

        $changelog | Should -Not -Match 'Unreleased'
        $changelog | Should -Match ([regex]::Escape($script:CurrentSourceVersion))
        $changelog | Should -Match 'Pester 5\.7\.1'

        $releasePackage | Should -Match ([regex]::Escape($script:CurrentSourceVersion))
    }

    It "keeps the wiki changelog staging doc aligned with the last actually-published release" {
        # docs\wiki-updates\Changelog.md tracks the live GitHub wiki, which
        # mirrors published releases only -- it intentionally does NOT get
        # an entry for an in-progress, uncommitted RC (wiki updates for
        # this round are explicitly out of scope; see the round's own
        # notes). It must still never claim "Unreleased" and must still
        # correctly describe the last published version.
        $wikiChangelog = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs\wiki-updates\Changelog.md') -Raw
        $wikiChangelog | Should -Not -Match 'Unreleased'
        $wikiChangelog | Should -Match ([regex]::Escape($script:LastPublishedVersion))
    }

    It "documents Release Integrity Audit as a mandatory public-release gate" {
        $checklist = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'RELEASE-SAFETY-CHECKLIST.md') -Raw

        $checklist | Should -Match 'Release Integrity Audit'
        $checklist | Should -Match 'Runtime Identity Audit'
        $checklist | Should -Match 'Release Artifact Audit'
    }
}
