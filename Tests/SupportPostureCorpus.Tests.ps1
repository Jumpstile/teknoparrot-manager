BeforeAll {
    $supportScript = Join-Path $PSScriptRoot '..\scripts\New-TpmSupportPostureCorpus.ps1'
    . $supportScript
    $supportRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-support-tests-' + [guid]::NewGuid().ToString('N'))
    $installedProfiles = Join-Path $supportRoot 'installed\GameProfiles'
    $upstreamProfiles = Join-Path $supportRoot 'upstream\GameProfiles'
    $fixtureRoot = Join-Path $supportRoot 'fixtures'
    $outputOne = Join-Path $supportRoot 'output-one'
    $outputTwo = Join-Path $supportRoot 'output-two'
    [void][System.IO.Directory]::CreateDirectory($installedProfiles)
    [void][System.IO.Directory]::CreateDirectory($upstreamProfiles)
    [void][System.IO.Directory]::CreateDirectory($fixtureRoot)

    function Add-SupportTestFile {
        param([string]$Root, [string]$RelativePath, [string]$Content = 'fixture')
        $path = Join-Path $Root ($RelativePath -replace '/', '\')
        $parent = [System.IO.Path]::GetDirectoryName($path)
        [void][System.IO.Directory]::CreateDirectory($parent)
        [System.IO.File]::WriteAllText($path, $Content)
    }

    $supportCases = @(
        [pscustomobject]@{ id = 'CHD-01'; profileCode = 'ChdOnly'; layoutClass = 'CHD_ONLY'; files = @('game.chd'); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-02'; profileCode = 'ChdSame'; layoutClass = 'CHD_PLUS_EXECUTABLE_SAME_FOLDER'; files = @('game.exe', 'game.chd'); exe = 'game.exe'; expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-03'; profileCode = 'ChdContentPair'; layoutClass = 'CHD_PLUS_EXECUTABLE_PLUS_CONTENT_SUBFOLDER'; files = @('game.exe', 'content/game.chd'); exe = 'game.exe'; expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-04'; profileCode = 'ChdContent'; layoutClass = 'CHD_IN_CONTENT_OR_MEDIA_SUBFOLDER'; files = @('content/game.chd'); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-05'; profileCode = 'ChdNestedOne'; layoutClass = 'CHD_NESTED_ONE_LEVEL'; files = @('nested/game.chd'); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-06'; profileCode = 'ChdNestedMany'; layoutClass = 'CHD_NESTED_MULTIPLE_LEVELS'; files = @('one/two/game.chd'); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-07'; profileCode = 'ChdMany'; layoutClass = 'MULTIPLE_CHD_CANDIDATES'; files = @('one.chd', 'two.chd'); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MULTIPLE_CHD_CANDIDATES' },
        [pscustomobject]@{ id = 'CHD-08'; profileCode = 'ChdLauncher'; layoutClass = 'CHD_PLUS_SEPARATE_LAUNCHER'; files = @('launcher.exe', 'media/game.chd'); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-09'; profileCode = 'ChdWrong'; layoutClass = 'CHD_PRESENT_WRONG_DIRECTORY_SELECTED'; files = @('game.chd'); selectedPath = 'outside'; expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'WRONG_DIRECTORY_SELECTED' },
        [pscustomobject]@{ id = 'CHD-10'; profileCode = 'ChdMissingDir'; layoutClass = 'CHD_EXPECTED_GAME_DIRECTORY_MISSING'; expectedClassification = 'BLOCKED_UNSUPPORTED'; expectedReasonCode = 'GAME_DIRECTORY_MISSING' },
        [pscustomobject]@{ id = 'CHD-11'; profileCode = 'ChdAbsent'; layoutClass = 'CHD_REQUIRED_BUT_ABSENT'; files = @('game.exe'); exe = 'game.exe'; chdRequirement = 'REQUIRED'; expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'REQUIRED_MEDIA_MISSING' },
        [pscustomobject]@{ id = 'CHD-12'; profileCode = 'ChdUnknown'; layoutClass = 'CHD_PRESENT_BUT_PROFILE_MEDIA_RULE_UNKNOWN'; files = @('game.chd'); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'CHD-13'; profileCode = 'Ordinary'; layoutClass = 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT'; files = @('ordinary.exe'); exe = 'ordinary.exe'; expectedClassification = 'AUTOMATED_SAFE'; expectedReasonCode = 'EXACT_UNIQUE_EXECUTABLE' },
        [pscustomobject]@{ id = 'CHD-14'; profileCode = 'ChdConflict'; layoutClass = 'MEDIA_LAYOUT_CONFLICTS_WITH_PROFILE'; files = @('game.exe', 'game.chd'); exe = 'game.exe'; mediaConflict = $true; expectedClassification = 'BLOCKED_UNSUPPORTED'; expectedReasonCode = 'MEDIA_LAYOUT_CONFLICT' },
        [pscustomobject]@{ id = 'CHD-15'; profileCode = 'Unobservable'; layoutClass = 'LAYOUT_UNOBSERVABLE'; files = @(); expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'MEDIA_RULE_UNKNOWN' },
        [pscustomobject]@{ id = 'SAFE-01'; profileCode = 'Protected'; layoutClass = 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT'; files = @('protected.exe'); exe = 'protected.exe'; forceProtected = $true; expectedClassification = 'BLOCKED_UNSUPPORTED'; expectedReasonCode = 'UNSAFE_GAME_PATH' },
        [pscustomobject]@{ id = 'SAFE-02'; profileCode = 'Reparse'; layoutClass = 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT'; files = @('reparse.exe'); exe = 'reparse.exe'; forceReparse = $true; expectedClassification = 'BLOCKED_UNSUPPORTED'; expectedReasonCode = 'UNSAFE_GAME_PATH' },
        [pscustomobject]@{ id = 'SAFE-03'; profileCode = 'EmptyExecutable'; layoutClass = 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT'; files = @('folder.exe'); exactFolderIdentity = $true; expectedClassification = 'AUTOMATED_SAFE'; expectedReasonCode = 'EXACT_PROFILE_FOLDER_IDENTITY' },
        [pscustomobject]@{ id = 'SAFE-04'; profileCode = 'TwoExecutables'; layoutClass = 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT'; files = @('first.exe', 'second.exe'); exe = 'first.exe|second.exe'; hasTwoExecutables = $true; expectedClassification = 'AUTOMATED_SAFE'; expectedReasonCode = 'EXACT_TWO_EXECUTABLE_PROFILE' },
        [pscustomobject]@{ id = 'SAFE-05'; profileCode = 'ExplicitChd'; layoutClass = 'CHD_ONLY'; files = @('target.chd'); exe = 'target.chd'; chdRequirement = 'EXPLICIT_TARGET'; expectedClassification = 'AUTOMATED_SAFE'; expectedReasonCode = 'EXPLICIT_UNIQUE_CHD_TARGET' },
        [pscustomobject]@{ id = 'SAFE-06'; profileCode = 'SourceConflict'; layoutClass = 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT'; files = @('conflict.exe'); exe = 'conflict.exe'; sourceConflict = $true; expectedClassification = 'REVIEW_MANUAL'; expectedReasonCode = 'SOURCE_EVIDENCE_CONFLICT' },
        [pscustomobject]@{ id = 'SAFE-07'; profileCode = 'Broken'; layoutClass = 'LAYOUT_UNOBSERVABLE'; files = @(); malformed = $true; expectedClassification = 'BLOCKED_UNSUPPORTED'; expectedReasonCode = 'MALFORMED_PROFILE_XML' }
    )
    foreach ($case in $supportCases) {
        $gameRoot = Join-Path $fixtureRoot ('games\' + $case.id)
        if ($case.profileCode -ne 'ChdMissingDir') {
            [void][System.IO.Directory]::CreateDirectory($gameRoot)
            foreach ($file in @($case.files)) { Add-SupportTestFile -Root $gameRoot -RelativePath $file }
        }
        if ($case.malformed) {
            Add-SupportTestFile -Root $installedProfiles -RelativePath ($case.profileCode + '.xml') -Content '<GameProfile><GameName>broken'
        } else {
            $xml = '<GameProfile><GameName>' + $case.profileCode + '</GameName><EmulationProfile>Raw</EmulationProfile>'
            if ($case.exe) { $xml += '<ExecutableName>' + $case.exe + '</ExecutableName>' }
            if ($case.hasTwoExecutables) { $xml += '<HasTwoExecutables>true</HasTwoExecutables><LaunchSecondExecutableFirst>false</LaunchSecondExecutableFirst>' }
            $xml += '</GameProfile>'
            Add-SupportTestFile -Root $installedProfiles -RelativePath ($case.profileCode + '.xml') -Content $xml
        }
    }
    $conflictXml = '<GameProfile><GameName>SourceConflict upstream</GameName><EmulationProfile>Raw</EmulationProfile><ExecutableName>conflict.exe</ExecutableName></GameProfile>'
    Add-SupportTestFile -Root $upstreamProfiles -RelativePath 'SourceConflict.xml' -Content $conflictXml
    $fixtureManifest = [ordered]@{ schemaVersion = 1; fixtures = @($supportCases | ForEach-Object {
        [ordered]@{
            id = $_.id; profileCode = $_.profileCode; relativeRoot = 'games/' + $_.id; layoutClass = $_.layoutClass
            selectedPath = $_.selectedPath; expectedClassification = $_.expectedClassification; expectedReasonCode = $_.expectedReasonCode
            chdRequirement = $_.chdRequirement; exactFolderIdentity = $_.exactFolderIdentity; mediaConflict = $_.mediaConflict
            forceProtected = $_.forceProtected; forceReparse = $_.forceReparse; sourceConflict = $_.sourceConflict
        }
    }) }
    [System.IO.File]::WriteAllText((Join-Path $fixtureRoot 'fixtures.json'), ($fixtureManifest | ConvertTo-Json -Depth 10))
    Add-SupportTestFile -Root (Join-Path $supportRoot 'user\UserProfiles') -RelativePath 'Ordinary.xml' -Content '<GameProfile><GamePath>games/Ordinary</GamePath><GamePath2>games/Ordinary2</GamePath2></GameProfile>'
    Add-SupportTestFile -Root $supportRoot -RelativePath 'sample.dat' -Content '<datafile><game name="Ordinary"><GameProfile>Ordinary</GameProfile><Executable>ordinary.exe</Executable></game></datafile>'

    function Invoke-TestSupportCorpus {
        param([string]$OutputRoot)
        Invoke-TpmSupportPostureCorpus -InstalledGameProfilesPath $installedProfiles -InstalledUserProfilesPath (Join-Path $supportRoot 'user\UserProfiles') -UpstreamProfileRoot $upstreamProfiles -UpstreamCommitSha 'upstream-commit-001' -InstalledTeknoParrotVersion '1.0-RC8-test' -DatFilePath (Join-Path $supportRoot 'sample.dat') -FixtureRoot $fixtureRoot -SnapshotId 'SUPPORT-TEST-SNAPSHOT' -CapturedAtUtc '2026-08-22T00:00:00Z' -OutputRoot $OutputRoot
    }
    Invoke-TestSupportCorpus -OutputRoot $outputOne | Out-Null

}

Describe 'TPM support posture corpus' {
    It 'retains the current CHD discovery boundary' {
        $main = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1') -Raw
        $match = [regex]::Match($main, '(?s)function Get-GameFiles.*?(?=\r?\nfunction )')
        $match.Success | Should -BeTrue
        $match.Value | Should -Not -Match '\.chd'
    }

    It 'emits deterministic profile posture and passes the zero UNCLASSIFIED gate' {
        $model = Get-Content -LiteralPath (Join-Path $outputOne 'support-posture.json') -Raw | ConvertFrom-Json
        $model.SchemaVersion | Should -Be 1
        $model.ProfileCount | Should -Be 22
        $model.ClassificationTotals.UNCLASSIFIED | Should -Be 0
        $model.ReleaseGate.ZeroUnclassified | Should -BeTrue
        $model.ReleaseGate.ClosureEligible | Should -BeTrue
        $model.FixtureCoverage.Failed | Should -Be 0
        @($model.ClassificationTotals.PSObject.Properties | Where-Object { $_.Value -gt 0 }).Count | Should -BeGreaterThan 1
    }

    It 'covers every CHD and ordinary layout taxonomy class' {
        $model = Get-Content -LiteralPath (Join-Path $outputOne 'support-posture.json') -Raw | ConvertFrom-Json
        $observed = @($model.Profiles | ForEach-Object { $_.LayoutObservations } | ForEach-Object LayoutClass | Sort-Object -Unique)
        foreach ($taxonomy in @('CHD_ONLY', 'CHD_PLUS_EXECUTABLE_SAME_FOLDER', 'CHD_PLUS_EXECUTABLE_PLUS_CONTENT_SUBFOLDER', 'CHD_IN_CONTENT_OR_MEDIA_SUBFOLDER', 'CHD_NESTED_ONE_LEVEL', 'CHD_NESTED_MULTIPLE_LEVELS', 'MULTIPLE_CHD_CANDIDATES', 'CHD_PLUS_SEPARATE_LAUNCHER', 'CHD_PRESENT_WRONG_DIRECTORY_SELECTED', 'CHD_EXPECTED_GAME_DIRECTORY_MISSING', 'CHD_REQUIRED_BUT_ABSENT', 'CHD_PRESENT_BUT_PROFILE_MEDIA_RULE_UNKNOWN', 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT', 'MEDIA_LAYOUT_CONFLICTS_WITH_PROFILE', 'LAYOUT_UNOBSERVABLE')) {
            $observed | Should -Contain $taxonomy
        }
    }

    It 'records source identity, raw XML hashes, malformed XML, and DAT evidence' {
        $model = Get-Content -LiteralPath (Join-Path $outputOne 'support-posture.json') -Raw | ConvertFrom-Json
        $manifest = Get-Content -LiteralPath (Join-Path $outputOne 'manifest.json') -Raw | ConvertFrom-Json
        @($manifest.Sources | Where-Object { $_.SourceId -eq 'upstream-commit-001' }).Count | Should -Be 1
        $broken = @($model.Profiles | Where-Object ProfileCode -eq 'Broken')[0]
        $broken.Classification | Should -Be 'BLOCKED_UNSUPPORTED'
        $broken.ReasonCode | Should -Be 'MALFORMED_PROFILE_XML'
        $broken.ProfileXmlSha256 | Should -Not -BeNullOrEmpty
        $model.SecondaryDat.Status | Should -Be 'READ'
        $model.SecondaryDat.EntryCount | Should -Be 1
        $model.SecondaryDat.Entries[0].ProfileCode | Should -Be 'Ordinary'
        (Get-Content -LiteralPath (Join-Path $outputOne 'support-posture.md') -Raw) | Should -Not -Match ([regex]::Escape($supportRoot))
    }

    It 'reproduces identical JSON and Markdown from the same snapshot inputs' {
        Invoke-TestSupportCorpus -OutputRoot $outputTwo | Out-Null
        (Get-TpmSupportSha256 -Path (Join-Path $outputOne 'manifest.json')) | Should -Be (Get-TpmSupportSha256 -Path (Join-Path $outputTwo 'manifest.json'))
        (Get-TpmSupportSha256 -Path (Join-Path $outputOne 'support-posture.json')) | Should -Be (Get-TpmSupportSha256 -Path (Join-Path $outputTwo 'support-posture.json'))
        (Get-TpmSupportSha256 -Path (Join-Path $outputOne 'support-posture.md')) | Should -Be (Get-TpmSupportSha256 -Path (Join-Path $outputTwo 'support-posture.md'))
    }

    It 'emits a validated contract registry aligned with the support posture snapshot' {
        $registry = Get-Content -LiteralPath (Join-Path $outputOne 'game-support-contracts.json') -Raw | ConvertFrom-Json
        $model = Get-Content -LiteralPath (Join-Path $outputOne 'support-posture.json') -Raw | ConvertFrom-Json
        $registry.SchemaVersion | Should -Be '1.3.0'
        @($registry.Contracts | Where-Object { $_.Prerequisites.ExternalSoftware.DeclarationState -eq 'NOT_DECLARED' -and @($_.Prerequisites.ExternalSoftware.Items).Count -eq 0 }).Count | Should -Be $model.ProfileCount
        $registry.ContractCount | Should -Be $model.ProfileCount
        $registry.SnapshotId | Should -Be $model.SnapshotId
        @($registry.Contracts).Count | Should -Be $model.ProfileCount
        @($registry.Contracts | Where-Object { $_.MediaRequirements -and $_.ChdRequirements -and $_.RequiredPatches -and $_.BepInExRequirements -and $_.DgVoodoo2Requirements -and $_.ReShadeCompatibility -and $_.CrosshairCompatibility -and $_.ForceFeedbackCompatibility -and $_.GpuLimitations -and $_.KnownRuntimeFixes }).Count | Should -Be $model.ProfileCount
        @($registry.Contracts | Where-Object { $_.RequiredPatches.Status -eq 'NOT_DECLARED' -and $_.BepInExRequirements.Status -eq 'NOT_DECLARED' }).Count | Should -Be $model.ProfileCount
        (Get-Content -LiteralPath (Join-Path $outputOne 'game-support-contract-validation.json') -Raw | ConvertFrom-Json).Valid | Should -BeTrue
    }

    It 'reproduces identical game contract artifacts from the same snapshot inputs' {
        (Get-TpmSupportSha256 -Path (Join-Path $outputOne 'game-support-contracts.json')) | Should -Be (Get-TpmSupportSha256 -Path (Join-Path $outputTwo 'game-support-contracts.json'))
        (Get-TpmSupportSha256 -Path (Join-Path $outputOne 'game-support-contract-validation.json')) | Should -Be (Get-TpmSupportSha256 -Path (Join-Path $outputTwo 'game-support-contract-validation.json'))
    }

    It 'keeps UserProfiles as read-only observations and excludes them from the game universe' {
        $observations = Get-Content -LiteralPath (Join-Path $outputOne 'observations\userprofiles.json') -Raw | ConvertFrom-Json
        $ordinary = @($observations.Records | Where-Object ProfileCode -eq 'Ordinary')[0]
        $ordinary.RegistrationState | Should -Be 'REGISTERED_PATH_PRESENT'
        $ordinary.GamePath2 | Should -Be 'games/Ordinary2'
        $ordinary | Should -Not -BeNullOrEmpty
    }

    It 'detects duplicate profile stems case-insensitively' {
        $duplicates = @(Get-TpmSupportDuplicateProfileStems -Profiles @(
            [pscustomobject]@{ ProfileCode = 'Duplicate' },
            [pscustomobject]@{ ProfileCode = 'duplicate' },
            [pscustomobject]@{ ProfileCode = 'Unique' }
        ))
        $duplicates | Should -Contain 'Duplicate'
        $duplicates | Should -Contain 'duplicate'
        $duplicates | Should -Not -Contain 'Unique'
    }

    It 'rejects an output root nested inside a source root' {
        { Invoke-TpmSupportPostureCorpus -InstalledGameProfilesPath $installedProfiles -OutputRoot (Join-Path $installedProfiles 'generated') } | Should -Throw '*must not be inside*'
    }
    It 'keeps the generated artifact set inside the explicit output root' {
        foreach ($relative in @('manifest.json', 'support-posture.json', 'support-posture.md', 'fixture-coverage.json', 'game-support-contracts.json', 'game-support-contract-validation.json', 'observations/userprofiles.json', 'dat/dat-summary.json')) {
            Test-Path -LiteralPath (Join-Path $outputOne ($relative -replace '/', '\')) -PathType Leaf | Should -BeTrue
        }
        $files = @(Get-ChildItem -LiteralPath $outputOne -Recurse -File)
        @($files | Where-Object { -not (Test-TpmSupportPathInside -Child $_.FullName -Parent $outputOne) }).Count | Should -Be 0
    }

}

AfterAll {
    if ($supportRoot -and (Test-Path -LiteralPath $supportRoot)) { Remove-Item -LiteralPath $supportRoot -Recurse -Force }
}
