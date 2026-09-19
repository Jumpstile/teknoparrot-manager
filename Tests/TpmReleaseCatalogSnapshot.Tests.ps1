BeforeAll {
    $repoRoot = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
    $snapshotRoot = Join-Path $repoRoot 'contracts\snapshots\TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628'
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
        $result.SnapshotId | Should -Be 'TPM-GAME-SUPPORT-RELEASE-1.0.0.2128-ASSET-9E6A8628'
        $result.AssetSha256 | Should -Be '9e6a8628d365a9d7c32f1dee07f1a62799656a9fdb1b58afe863526c5cf84901'
        $result.ManifestFileCount | Should -Be 2231
    }

    It 'records the exact catalog counts and content-addressed identity' {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.SnapshotId | Should -Match '-ASSET-9E6A8628$'
        $manifest.Release.Version | Should -Be '1.0.0.2128'
        $manifest.Release.AssetSize | Should -Be 153159505
        $manifest.CatalogCounts.GameProfiles | Should -Be 925
        $manifest.CatalogCounts.GameSetup | Should -Be 383
        $manifest.CatalogCounts.Metadata | Should -Be 923
        $manifest.CatalogCounts.TotalFiles | Should -Be 2231
        @($manifest.Files).Count | Should -Be 2231
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

    It 'persists machine-generated delta counts and the canonical jdredd identity' {
        $delta = Get-Content -LiteralPath $deltaPath -Raw | ConvertFrom-Json
        $delta.HistoricalProfileCount | Should -Be 695
        $delta.CurrentProfileCount | Should -Be 925
        $delta.AddedProfileCount | Should -Be 230
        $delta.RemovedProfileCount | Should -Be 0
        $delta.SemanticChangedProfileCount | Should -Be 38
        $delta.SemanticUnchangedProfileCount | Should -Be 657
        @($delta.Added).Count | Should -Be 230
        @($delta.Removed).Count | Should -Be 0
        @($delta.Changed).Count | Should -Be 38
        @($delta.Unchanged).Count | Should -Be 657
        @($delta.Added) | Should -Contain 'jdredd'
        @($delta.Added) | Should -Not -Contain 'jdreedd'
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
        $manifest.SourceProof.Commit | Should -Be 'dc998e374608abbda373bb3c236db5b26b5afca7'
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
        (Get-Content -LiteralPath (Join-Path $snapshotRoot 'release-evidence.json') -Raw) | Should -Match '9e6a8628d365a9d7c32f1dee07f1a62799656a9fdb1b58afe863526c5cf84901'
    }
}
