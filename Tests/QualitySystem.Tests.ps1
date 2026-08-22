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

Describe "Release Integrity source identity" -Tag 'ReleaseConsistency' {
    # The running source identity and the last published release are tracked
    # separately so an in-progress release cannot be mistaken for a published
    # one. After the RC6 publication they intentionally point to the same RC6
    # identity, while the assertions remain explicit about each surface.
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
        $script:LastPublishedVersion = 'v1.0 RC6'
        $script:LastPublishedRcLabel = 'RC6'
        $script:LastPublishedTag     = 'v1.0-RC6'
        $script:LastPublishedZipName = 'TeknoParrot Manager v1.0 RC6.zip'
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
        # RC6 has been validated for publication, but this test deliberately
        # does not claim real-hardware certification without that evidence.
        $topReadme | Should -Match 'published and validated'
        # Guard the regression class where a published release's own docs
        # still say it is not published.
        $topReadme | Should -Not -Match ($script:LastPublishedRcLabel + '.*(in preparation|not been published|not yet published)|intended tag|tag has not been created')
        $topReadme | Should -Not -Match '\[Download v1\.0 RC5\]'
        $topReadme | Should -Not -Match 'v1\.0 RC1|v1\.0-RC1|v1\.0\.RC1'
        # The current source identity must also use published wording.
        $topReadme | Should -Match ([regex]::Escape($script:CurrentSourceVersion) + '.*published')
        $topReadme | Should -Not -Match ([regex]::Escape($script:CurrentSourceVersion) + '.*(in progress|not yet published)')
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
        # docs\wiki-updates\Changelog.md tracks the live GitHub wiki and must
        # contain the current published release entry. It must never claim
        # "Unreleased" or omit the last published version.
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

Describe "Canonical repository discoverability contract" -Tag 'ReleaseConsistency' {
    BeforeAll {
        $script:DiscoverabilityRepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
        $script:DiscoverabilityMetadataPath = Join-Path $script:DiscoverabilityRepoRoot ".github\repository-metadata.json"
        $script:DiscoverabilityMetadata = Get-Content -LiteralPath $script:DiscoverabilityMetadataPath -Raw | ConvertFrom-Json
        $script:DiscoverabilityReadme = Get-Content -LiteralPath (Join-Path $script:DiscoverabilityRepoRoot "README.md") -Raw
        $script:DiscoverabilityChecklist = Get-Content -LiteralPath (Join-Path $script:DiscoverabilityRepoRoot "RELEASE-SAFETY-CHECKLIST.md") -Raw
    }

    It "defines version-agnostic repository metadata" {
        Test-Path -LiteralPath $script:DiscoverabilityMetadataPath -PathType Leaf | Should -BeTrue
        $script:DiscoverabilityMetadata.description | Should -Match '^TeknoParrot Manager\b'
        $script:DiscoverabilityMetadata.description | Should -Not -Match '(?i)\b(?:v?1\.0|RC\d+)\b'
        $script:DiscoverabilityMetadata.homepage | Should -Be 'https://github.com/Jumpstile/teknoparrot-manager/releases'
        $script:DiscoverabilityMetadata.homepage | Should -Not -Match '/tag/'

        $topics = @($script:DiscoverabilityMetadata.topics | ForEach-Object { [string]$_ })
        $topics.Count | Should -BeGreaterThan 0
        @($topics | Sort-Object -Unique).Count | Should -Be $topics.Count
        foreach ($topic in $topics) {
            $topic | Should -Match '^[a-z0-9]+(?:-[a-z0-9]+)*$'
        }
    }

    It "keeps supported discoverability topics explicit and non-spammy" {
        $requiredTopics = @(
            'arcade', 'arcade-games', 'crosshair', 'dgvoodoo2', 'game-manager',
            'hyperspin', 'launchbox', 'lightgun', 'powershell', 'reshade',
            'teknoparrot', 'teknoparrot-manager'
        )

        $topics = @($script:DiscoverabilityMetadata.topics | ForEach-Object { [string]$_ })
        foreach ($requiredTopic in $requiredTopics) {
            $topics | Should -Contain $requiredTopic
        }
    }

    It "keeps README identity and canonical links version-agnostic at the top" {
        $topReadme = ($script:DiscoverabilityReadme -split "`r?`n" | Select-Object -First 14) -join "`n"
        $repositoryUrlPattern = [regex]::Escape('https://github.com/Jumpstile/teknoparrot-manager')
        $releasesUrlPattern = [regex]::Escape('https://github.com/Jumpstile/teknoparrot-manager/releases')

        $topReadme | Should -Match '(?m)^# TeknoParrot Manager\s*$'
        $topReadme | Should -Match 'TeknoParrot Manager is a Windows PowerShell tool'
        $topReadme | Should -Match $repositoryUrlPattern
        $topReadme | Should -Match $releasesUrlPattern
        $topReadme | Should -Not -Match '/releases/tag/'
    }

    It "makes repository metadata part of release-consistency governance" {
        $metadataContractPattern = [regex]::Escape('.github/repository-metadata.json')
        $script:DiscoverabilityChecklist | Should -Match $metadataContractPattern
        $script:DiscoverabilityChecklist | Should -Match '(?i)live GitHub.*(description|homepage|topics)'
        $script:DiscoverabilityChecklist | Should -Match '#237'

    }
}

Describe "Active release-facing documentation" -Tag 'ReleaseConsistency' {
    BeforeAll {
        $script:RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
        $script:ActiveReleaseDocs = @(
            [pscustomobject]@{ RelativePath = 'README.md'; PrefixLines = 25 }
            [pscustomobject]@{ RelativePath = 'QUICKSTART.md'; PrefixLines = 5 }
            [pscustomobject]@{ RelativePath = 'TeknoParrot-Manager-README.txt'; PrefixLines = 18 }
            [pscustomobject]@{ RelativePath = 'TeknoParrot-Manager-QuickStart.txt'; PrefixLines = 17 }
            [pscustomobject]@{ RelativePath = 'docs\AUTO_UPDATE.md'; PrefixLines = 11 }
        )
    }

    It "keeps active release-facing prefixes on the published RC6 state" {
        foreach ($entry in $script:ActiveReleaseDocs) {
            $path = Join-Path $script:RepoRoot $entry.RelativePath
            $content = Get-Content -LiteralPath $path -Raw
            $lines = [regex]::Split($content, '\r\n|\n')
            $active = ($lines | Select-Object -First $entry.PrefixLines) -join ([string][char]10)

            $active | Should -Match 'v1\.0[- ]RC6'
            $active | Should -Match '(?i)published'
            $active | Should -Not -Match '(?i)RC[345]\s+(?:is|remains)\s+(?:the\s+)?(?:latest|current)'
            $active | Should -Not -Match '(?i)RC6.{0,120}(in progress|not yet published|has not been published)'
        }
    }

    It "rejects older RC installation or download guidance in active prefixes" {
        foreach ($entry in $script:ActiveReleaseDocs) {
            $path = Join-Path $script:RepoRoot $entry.RelativePath
            $content = Get-Content -LiteralPath $path -Raw
            $lines = [regex]::Split($content, '\r\n|\n')
            $active = ($lines | Select-Object -First $entry.PrefixLines) -join ([string][char]10)

            $active | Should -Not -Match '(?i)(download|use|install)\s+(?:the\s+)?(?:(?:current|latest)\s+)?(?:release\s+)?(?:v1\.0[- ]?)?RC[345]\b'
        }
    }

    It "states that final Version 1.0 is not published yet" {
        foreach ($entry in $script:ActiveReleaseDocs) {
            $path = Join-Path $script:RepoRoot $entry.RelativePath
            $content = Get-Content -LiteralPath $path -Raw
            $content | Should -Match '(?i)Final Version 1\.0.{0,60}(unpublished|not been published)'
        }
    }
}

Describe "Release-document consistency contract" -Tag 'ReleaseConsistency' {
    BeforeAll {
        $script:ReleaseDocumentContract = [pscustomobject]@{
            CurrentVersionLabel = 'v1.0 RC6'
            CurrentVersionPattern = 'v1\.0[- ]RC6'
        }

        $script:ReleaseDocumentConsistencyFinder = {
            param(
                [Parameter(Mandatory)]
                [object[]]$Documents,

                [Parameter(Mandatory)]
                [pscustomobject]$Contract
            )

            $findings = New-Object 'System.Collections.Generic.List[string]'
            $staleReleasePattern = '(?i)\b(?:download|use|install)\s+(?:the\s+)?(?:(?:current|latest)\s+)?(?:release\s+)?(?:v1\.0[- ]?)?RC[0-5]\b|\b(?:current|latest)\s+(?:release|release candidate|candidate)\s*(?:is|:)\s*(?:v1\.0[- ]?)?RC[0-5]\b'

            foreach ($document in $Documents) {
                if ($document.Scope -eq 'Historical') {
                    continue
                }

                $text = [string]$document.Text
                if ([string]$document.Scope -eq 'ActiveIdentity') {
                    if ($text -notmatch $Contract.CurrentVersionPattern) {
                        [void]$findings.Add("$($document.Path): active text does not identify $($Contract.CurrentVersionLabel).")
                    }

                    if ($text -notmatch '(?i)\bpublished\b') {
                        [void]$findings.Add("$($document.Path): active text does not state the current release is published.")
                    }

                    $notPublishedPattern = '(?i)' + $Contract.CurrentVersionPattern + '.{0,140}(?:in progress|not yet published|has not been published|unpublished)'
                    if ($text -match $notPublishedPattern) {
                        [void]$findings.Add("$($document.Path): current release is described as unpublished or in progress.")
                    }

                    foreach ($line in [regex]::Split($text, '\r\n|\n')) {
                        if ($line -match $staleReleasePattern) {
                            [void]$findings.Add("$($document.Path): active text gives guidance toward a superseded RC.")
                        }
                    }
                }

                if ([string]$document.Scope -eq 'ActiveBepInEx') {
                    if ($text -notmatch '(?i)\bBepInEx\s+update(?:\s+check)?\b') {
                        [void]$findings.Add("$($document.Path): active BepInEx wording does not identify an update check.")
                    }

                    if ($text -notmatch '(?i)(?:already|existing)[\s\S]{0,100}BepInEx[\s\S]{0,50}installed|BepInEx[\s\S]{0,100}(?:already|existing)[\s\S]{0,50}installed') {
                        [void]$findings.Add("$($document.Path): active BepInEx wording does not require an existing installation.")
                    }

                    if ($text -notmatch "(?i)(?:never|does not|doesn't)[\s\S]{0,60}install(?:s)?\s+BepInEx") {
                        [void]$findings.Add("$($document.Path): active BepInEx wording does not reject fresh installation.")
                    }

                    if ($text -notmatch '(?i)stable.{0,40}64-bit|64-bit.{0,40}stable') {
                        [void]$findings.Add("$($document.Path): active BepInEx wording does not constrain updates to stable 64-bit builds.")
                    }

                    if ($text -match '(?i)\bBepInEx\s+setup\b|\b(?:TPM|this mode|mode 9|the script)\s+(?:installs?|sets up|configures?)\s+BepInEx') {
                        [void]$findings.Add("$($document.Path): active BepInEx wording implies setup or fresh installation.")
                    }
                }
            }

            return $findings.ToArray()
        }

        $script:ReleaseIdentityDocuments = @(
            [pscustomobject]@{ Path = 'README.md'; Scope = 'ActiveIdentity'; Text = 'Published release candidate: v1.0 RC6. Download it from GitHub Releases.' }
            [pscustomobject]@{ Path = 'QUICKSTART.md'; Scope = 'ActiveIdentity'; Text = 'Published release candidate: v1.0 RC6. Final Version 1.0 remains unpublished.' }
        )

    }

    It "fails a fixture where active documents identify different current RCs" {
        $contradictory = @(
            $script:ReleaseIdentityDocuments[0]
            [pscustomobject]@{ Path = 'QUICKSTART.md'; Scope = 'ActiveIdentity'; Text = 'Published release candidate: v1.0 RC5. Download it from GitHub Releases.' }
        )

        $findings = @(& $script:ReleaseDocumentConsistencyFinder -Documents $contradictory -Contract $script:ReleaseDocumentContract)
        $findings.Count | Should -BeGreaterThan 0
        ($findings -join "`n") | Should -Match 'QUICKSTART\.md'
    }

    It "fails a fixture with superseded RC installation guidance" {
        $stale = @(
            [pscustomobject]@{ Path = 'README.md'; Scope = 'ActiveIdentity'; Text = 'Published release candidate: v1.0 RC6.' }
            [pscustomobject]@{ Path = 'QUICKSTART.md'; Scope = 'ActiveIdentity'; Text = 'Published release candidate: v1.0 RC6. Download v1.0-RC5 here.' }
        )

        $findings = @(& $script:ReleaseDocumentConsistencyFinder -Documents $stale -Contract $script:ReleaseDocumentContract)
        $findings.Count | Should -BeGreaterThan 0
        ($findings -join "`n") | Should -Match 'superseded RC'
    }

    It "fails a fixture that marks the current release as unpublished" {
        $unpublished = @(
            [pscustomobject]@{ Path = 'README.md'; Scope = 'ActiveIdentity'; Text = 'Published release candidate: v1.0 RC6.' }
            [pscustomobject]@{ Path = 'QUICKSTART.md'; Scope = 'ActiveIdentity'; Text = 'The current release v1.0 RC6 is not yet published.' }
        )

        $findings = @(& $script:ReleaseDocumentConsistencyFinder -Documents $unpublished -Contract $script:ReleaseDocumentContract)
        $findings.Count | Should -BeGreaterThan 0
        ($findings -join "`n") | Should -Match 'unpublished or in progress'
    }

    It "fails active BepInEx setup or fresh-install wording" {
        $misleading = @(
            [pscustomobject]@{ Path = 'README.md'; Scope = 'ActiveBepInEx'; Text = 'BepInEx setup: Mode 9 installs BepInEx fresh into every game. Stable 64-bit release.' }
        )

        $findings = @(& $script:ReleaseDocumentConsistencyFinder -Documents $misleading -Contract $script:ReleaseDocumentContract)
        $findings.Count | Should -BeGreaterThan 0
        ($findings -join "`n") | Should -Match 'setup or fresh installation'
    }

    It "allows clearly historical RC and BepInEx wording outside active guidance" {
        $documents = @(
            $script:ReleaseIdentityDocuments[0]
            [pscustomobject]@{ Path = 'docs/wiki-updates/Changelog.md'; Scope = 'Historical'; Text = 'v1.0 RC5 used the earlier BepInEx setup wording and is superseded.' }
        )

        $findings = @(& $script:ReleaseDocumentConsistencyFinder -Documents $documents -Contract $script:ReleaseDocumentContract)
        $findings.Count | Should -Be 0
    }

    It "passes the repository active release and BepInEx documents" {
        $repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
        $documents = @()

        foreach ($entry in @(
            [pscustomobject]@{ RelativePath = 'README.md' }
            [pscustomobject]@{ RelativePath = 'QUICKSTART.md' }
            [pscustomobject]@{ RelativePath = 'TeknoParrot-Manager-README.txt' }
            [pscustomobject]@{ RelativePath = 'TeknoParrot-Manager-QuickStart.txt' }
            [pscustomobject]@{ RelativePath = 'docs\AUTO_UPDATE.md' }
        )) {
            $content = Get-Content -LiteralPath (Join-Path $repoRoot $entry.RelativePath) -Raw
            $documents += [pscustomobject]@{ Path = $entry.RelativePath; Scope = 'ActiveIdentity'; Text = $content }
        }

        foreach ($relativePath in @('README.md', 'QUICKSTART.md', 'TeknoParrot-Manager-README.txt', 'TeknoParrot-Manager-QuickStart.txt')) {
            $documents += [pscustomobject]@{
                Path = $relativePath
                Scope = 'ActiveBepInEx'
                Text = Get-Content -LiteralPath (Join-Path $repoRoot $relativePath) -Raw
            }
        }

        $findings = @(& $script:ReleaseDocumentConsistencyFinder -Documents $documents -Contract $script:ReleaseDocumentContract)
        $findings.Count | Should -Be 0
    }
}
