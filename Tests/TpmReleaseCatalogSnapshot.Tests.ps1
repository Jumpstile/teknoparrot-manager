BeforeAll {
    $repoRoot = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
    $pin = Get-Content -LiteralPath (Join-Path $repoRoot 'contracts\snapshots\CURRENT-SNAPSHOT-PIN.json') -Raw | ConvertFrom-Json
    $snapshotRoot = Join-Path $repoRoot ('contracts\snapshots\' + $pin.SnapshotId)
    $manifestPath = Join-Path $snapshotRoot 'snapshot-manifest.json'
    $deltaPath = Join-Path $snapshotRoot 'delta.json'
    $validator = Join-Path $repoRoot 'scripts\Test-TpmReleaseCatalogSnapshot.ps1'
    $schemaPaths = @(
        (Join-Path $repoRoot 'contracts\_schema\TpmReleaseCatalogSnapshotV1.schema.json'),
        (Join-Path $repoRoot 'contracts\_schema\TpmReleaseCatalogDeltaV1.schema.json')
    )
    $driftWatcher = Join-Path $repoRoot 'scripts\Test-TpmReleaseCatalogDrift.ps1'
}

Describe 'TPM immutable current-release snapshot' {
    It 'validates the committed manifest identity without network or machine state' {
        $result = & $validator -ManifestPath $manifestPath | ConvertFrom-Json
        $result.Valid | Should -BeTrue
        $result.SnapshotId | Should -Be $pin.SnapshotId
        $result.AssetSha256 | Should -Be $pin.AssetSha256
        $result.ManifestFileCount | Should -Be $pin.CatalogCounts.TotalFiles
    }

    It 'records the exact catalog counts and content-addressed identity' {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.SnapshotId | Should -Match ('-ASSET-' + $pin.AssetSha256.Substring(0, 8).ToUpperInvariant() + '$')
        $manifest.Release.Version | Should -Be $pin.Version
        $manifest.Release.AssetSize | Should -Be $pin.AssetSize
        $manifest.CatalogCounts.GameProfiles | Should -Be $pin.CatalogCounts.GameProfiles
        $manifest.CatalogCounts.GameSetup | Should -Be $pin.CatalogCounts.GameSetup
        $manifest.CatalogCounts.Metadata | Should -Be $pin.CatalogCounts.Metadata
        $manifest.CatalogCounts.TotalFiles | Should -Be $pin.CatalogCounts.TotalFiles
        @($manifest.Files).Count | Should -Be $pin.CatalogCounts.TotalFiles
    }

    It 'rejects a changed proof commit' {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.SourceProof.Commit = '31de199ac6d5468022d863b8a7e68971d7a0d1de'
        $tamperedPath = Join-Path $TestDrive 'tampered-manifest.json'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tamperedPath -Encoding UTF8
        $result = & $validator -ManifestPath $tamperedPath | ConvertFrom-Json
        $result.Valid | Should -BeFalse
        @($result.Errors) -join ';' | Should -Match 'Source-proof commit mismatch'
    }

    It 'exits with a failure code for a changed snapshot and 0 for the real one, with no switch needed' {
        # A caller that checks the exit code must not treat a tampered snapshot as verified.
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.SourceProof.Commit = '31de199ac6d5468022d863b8a7e68971d7a0d1de'
        $tamperedPath = Join-Path $TestDrive 'tampered-exit.json'
        $manifest | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tamperedPath -Encoding UTF8
        $hostExe = (Get-Process -Id $PID).Path
        [void](& $hostExe -NoProfile -File $validator -ManifestPath $tamperedPath)
        $LASTEXITCODE | Should -Be 1
        [void](& $hostExe -NoProfile -File $validator -ManifestPath $manifestPath)
        $LASTEXITCODE | Should -Be 0
    }

    It 'persists machine-generated delta counts and the canonical jdredd identity' {
        $delta = Get-Content -LiteralPath $deltaPath -Raw | ConvertFrom-Json
        $delta.HistoricalProfileCount | Should -Be $pin.Delta.Historical
        $delta.CurrentProfileCount | Should -Be $pin.Delta.Current
        $delta.AddedProfileCount | Should -Be $pin.Delta.Added
        $delta.RemovedProfileCount | Should -Be $pin.Delta.Removed
        $delta.SemanticChangedProfileCount | Should -Be $pin.Delta.Changed
        $delta.SemanticUnchangedProfileCount | Should -Be $pin.Delta.Unchanged
        @($delta.Added).Count | Should -Be $pin.Delta.Added
        @($delta.Removed).Count | Should -Be $pin.Delta.Removed
        @($delta.Changed).Count | Should -Be $pin.Delta.Changed
        @($delta.Unchanged).Count | Should -Be $pin.Delta.Unchanged
        $codes = @((Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).Files | ForEach-Object ProfileCode)
        $codes | Should -Contain 'jdredd'
        $codes | Should -Not -Contain 'jdreedd'
    }

    It 'contains no unsafe or duplicate manifest paths' {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $paths = @($manifest.Files | ForEach-Object RelativePath)
        @($paths | Where-Object { $_ -match '(^|/|\\)\.\.(?:/|\\|$)' -or [System.IO.Path]::IsPathRooted($_) -or $_ -match '\\' }).Count | Should -Be 0
        @($paths | Group-Object | Where-Object Count -gt 1).Count | Should -Be 0
        @($paths | Group-Object { $_.ToLowerInvariant() } | Where-Object Count -gt 1).Count | Should -Be 0
    }

    It 'keeps the historical contract snapshot separate' {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.DeltaManifest | Should -Be 'delta.json'
        $manifest.SourceProof.Commit | Should -Be $pin.SourceProofCommit
        @(Get-ChildItem -LiteralPath $snapshotRoot -Filter '*.zip' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $snapshotRoot -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'parses both snapshot schemas as JSON' {
        foreach ($schemaPath in $schemaPaths) {
            Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json | Out-Null
        }
    }

    It 'reports upstream drift without refreshing the historical snapshot' {
        $observed = Get-Content -LiteralPath (Join-Path $snapshotRoot 'release-evidence.json') -Raw | ConvertFrom-Json
        $observed.Current.AssetSha256 = ('a' * 64)
        $observedPath = Join-Path $TestDrive 'observed-release.json'
        $observed | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $observedPath -Encoding UTF8
        $result = & $driftWatcher -RecordedEvidencePath (Join-Path $snapshotRoot 'release-evidence.json') -ObservedReleasePath $observedPath | ConvertFrom-Json
        $result.Status | Should -Be 'NEW_RELEASE_SNAPSHOT_AVAILABLE'
        $result.Action | Should -Match 'new reviewed immutable snapshot'
        (Get-Content -LiteralPath (Join-Path $snapshotRoot 'release-evidence.json') -Raw) | Should -Match $pin.AssetSha256
    }

    It 'names the recorded snapshot from the recorded evidence, not from a fixed text' {
        $recorded = Get-Content -LiteralPath (Join-Path $snapshotRoot 'release-evidence.json') -Raw | ConvertFrom-Json
        $same = & $driftWatcher -RecordedEvidencePath (Join-Path $snapshotRoot 'release-evidence.json') -ObservedReleasePath (Join-Path $snapshotRoot 'release-evidence.json') | ConvertFrom-Json
        $same.RecordedSnapshotId | Should -Be $pin.SnapshotId
        $recorded.Current.Version = '9.9.9.9'
        $recorded.Current.AssetSha256 = ('ab12cd34' + ('0' * 56))
        $otherPath = Join-Path $TestDrive 'other-recorded.json'
        $recorded | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $otherPath -Encoding UTF8
        $other = & $driftWatcher -RecordedEvidencePath $otherPath -ObservedReleasePath $otherPath | ConvertFrom-Json
        $other.RecordedSnapshotId | Should -Be 'TPM-GAME-SUPPORT-RELEASE-9.9.9.9-ASSET-AB12CD34'
    }

    It 'says the evidence is incomplete when a recorded or observed hash is empty or short, and never calls two empty hashes up to date' {
        $good = Join-Path $snapshotRoot 'release-evidence.json'
        $recorded = Get-Content -LiteralPath $good -Raw | ConvertFrom-Json
        foreach ($bad in @('', 'abc')) {
            $recorded.Current.AssetSha256 = $bad
            $badPath = Join-Path $TestDrive ('bad-recorded-' + $bad.Length + '.json')
            $recorded | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $badPath -Encoding UTF8
            $both = & $driftWatcher -RecordedEvidencePath $badPath -ObservedReleasePath $badPath | ConvertFrom-Json
            $both.Status | Should -Be 'RECORDED_EVIDENCE_INCOMPLETE'
            $one = & $driftWatcher -RecordedEvidencePath $good -ObservedReleasePath $badPath | ConvertFrom-Json
            $one.Status | Should -Be 'OBSERVED_EVIDENCE_INCOMPLETE'
        }
        $fieldless = Join-Path $TestDrive 'fieldless.json'
        '{"Current":{"Version":"1.0"}}' | Set-Content -LiteralPath $fieldless -Encoding UTF8
        (& $driftWatcher -RecordedEvidencePath $fieldless -ObservedReleasePath $good | ConvertFrom-Json).Status | Should -Be 'RECORDED_EVIDENCE_INCOMPLETE'
        '{}' | Set-Content -LiteralPath $fieldless -Encoding UTF8
        (& $driftWatcher -RecordedEvidencePath $good -ObservedReleasePath $fieldless | ConvertFrom-Json).Status | Should -Be 'OBSERVED_EVIDENCE_INCOMPLETE'
        '{"Current":null}' | Set-Content -LiteralPath $fieldless -Encoding UTF8
        # Mutation: read Current.AssetSha256 without checking Current -> a null Current throws instead of reporting incomplete evidence.
        (& $driftWatcher -RecordedEvidencePath $fieldless -ObservedReleasePath $good | ConvertFrom-Json).Status | Should -Be 'RECORDED_EVIDENCE_INCOMPLETE'
        (& $driftWatcher -RecordedEvidencePath $good -ObservedReleasePath $fieldless | ConvertFrom-Json).Status | Should -Be 'OBSERVED_EVIDENCE_INCOMPLETE'
    }

    It 'calls the same file hash up to date even when only the letter case differs' {
        $good = Join-Path $snapshotRoot 'release-evidence.json'
        $observed = Get-Content -LiteralPath $good -Raw | ConvertFrom-Json
        $observed.Current.AssetSha256 = ([string]$observed.Current.AssetSha256).ToUpperInvariant()
        $upperPath = Join-Path $TestDrive 'observed-upper.json'
        $observed | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $upperPath -Encoding UTF8
        (& $driftWatcher -RecordedEvidencePath $good -ObservedReleasePath $upperPath | ConvertFrom-Json).Status | Should -Be 'UP_TO_DATE'
    }

    It 'says the evidence is incomplete, and does not stop with an error, when Current is null' {
        $good = Join-Path $snapshotRoot 'release-evidence.json'
        $nullCurrent = Join-Path $TestDrive 'null-current.json'
        '{"Current":null}' | Set-Content -LiteralPath $nullCurrent -Encoding UTF8
        (& $driftWatcher -RecordedEvidencePath $nullCurrent -ObservedReleasePath $good | ConvertFrom-Json).Status | Should -Be 'RECORDED_EVIDENCE_INCOMPLETE'
        (& $driftWatcher -RecordedEvidencePath $good -ObservedReleasePath $nullCurrent | ConvertFrom-Json).Status | Should -Be 'OBSERVED_EVIDENCE_INCOMPLETE'
    }

    It 'refuses to write into a folder that already holds a different snapshot, and allows the same one' {
        # Mutation: drop the check in Assert-TpmSnapshotOutputRoot -> a changed upstream asset silently overwrites the pinned evidence folder.
        $generatorAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts\TpmReleaseCatalogSnapshot.Common.ps1'), [ref]$null, [ref]$null)
        $guardAst = $generatorAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-TpmSnapshotOutputRoot' }, $true)
        Invoke-Expression $guardAst.Extent.Text
        $out = Join-Path $TestDrive 'pinned'
        [void][IO.Directory]::CreateDirectory($out)
        $manifest = Join-Path $out 'snapshot-manifest.json'
        [IO.File]::WriteAllText($manifest, '{"SnapshotId":"ID-ONE","Release":{"AssetSha256":"aaa"}}')
        { Assert-TpmSnapshotOutputRoot -ManifestPath $manifest -SnapshotId 'ID-ONE' -AssetSha256 'aaa' -OutputRoot $out } | Should -Not -Throw
        { Assert-TpmSnapshotOutputRoot -ManifestPath $manifest -SnapshotId 'ID-TWO' -AssetSha256 'bbb' -OutputRoot $out } | Should -Throw '*already holds a different snapshot*'
        { Assert-TpmSnapshotOutputRoot -ManifestPath $manifest -SnapshotId 'ID-ONE' -AssetSha256 'bbb' -OutputRoot $out } | Should -Throw
        [IO.File]::WriteAllText($manifest, 'not json')
        { Assert-TpmSnapshotOutputRoot -ManifestPath $manifest -SnapshotId 'ID-ONE' -AssetSha256 'aaa' -OutputRoot $out } | Should -Throw
        { Assert-TpmSnapshotOutputRoot -ManifestPath (Join-Path $out 'absent.json') -SnapshotId 'ID-ONE' -AssetSha256 'aaa' -OutputRoot $out } | Should -Not -Throw
    }
}
