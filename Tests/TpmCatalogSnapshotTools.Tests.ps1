#Requires -Module Pester

# scripts\New-TpmCatalogSnapshotFromInstall.ps1 and scripts\Update-TpmCatalogSnapshotPins.ps1, on small made-up installs in a temp folder.
# What this CANNOT prove: that the tool copes with the real, much larger install; that is checked by running it there.

BeforeAll {
    $repoRoot = [System.IO.Directory]::GetParent($PSScriptRoot).FullName
    $script:tool = Join-Path $repoRoot 'scripts\New-TpmCatalogSnapshotFromInstall.ps1'
    $script:verifier = Join-Path $repoRoot 'scripts\Test-TpmReleaseCatalogSnapshot.ps1'
    $script:updater = Join-Path $repoRoot 'scripts\Update-TpmCatalogSnapshotPins.ps1'
    $script:work = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-snaptools-' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($script:work)
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    function New-FixtureInstall {
        param([string]$Path, [string]$ExeText, [hashtable]$Profiles)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $Path 'GameProfiles'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $Path 'UserProfiles'))
        [System.IO.File]::WriteAllText((Join-Path $Path 'TeknoParrotUi.exe'), $ExeText, $utf8)
        foreach ($name in $Profiles.Keys) { [System.IO.File]::WriteAllText((Join-Path $Path ('GameProfiles\' + $name + '.xml')), $Profiles[$name], $utf8) }
        [System.IO.File]::WriteAllText((Join-Path $Path 'GameProfiles\readme.txt'), 'not a profile', $utf8)
        [System.IO.File]::WriteAllText((Join-Path $Path 'UserProfiles\a.xml'), '<UserSecret>do not read</UserSecret>', $utf8)
    }
    function Get-FixtureId {
        param([string]$Path, [string]$Version)
        return 'TPM-GAME-SUPPORT-RELEASE-{0}-ASSET-{1}' -f $Version, (Get-FileHash -LiteralPath (Join-Path $Path 'TeknoParrotUi.exe') -Algorithm SHA256).Hash.Substring(0, 8).ToUpperInvariant()
    }
    function Get-FolderHashes {
        param([string]$Path)
        return (@(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($Path.Length) + '=' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join '|')
    }
    function New-FixturePin {
        param([string]$SnapshotFolder, [string]$PinPath)
        $m = Get-Content -LiteralPath (Join-Path $SnapshotFolder 'snapshot-manifest.json') -Raw | ConvertFrom-Json
        $d = Get-Content -LiteralPath (Join-Path $SnapshotFolder 'delta.json') -Raw | ConvertFrom-Json
        $pin = [ordered]@{
            SnapshotId = $m.SnapshotId; Version = $m.Release.Version; AssetSha256 = $m.Release.AssetSha256; AssetSize = $m.Release.AssetSize; SourceProofCommit = $m.SourceProof.Commit
            CatalogCounts = [ordered]@{ GameProfiles = $m.CatalogCounts.GameProfiles; GameSetup = $m.CatalogCounts.GameSetup; Metadata = $m.CatalogCounts.Metadata; TotalFiles = $m.CatalogCounts.TotalFiles }
            Delta = [ordered]@{ Historical = $d.HistoricalProfileCount; Current = $d.CurrentProfileCount; Added = $d.AddedProfileCount; Removed = $d.RemovedProfileCount; Changed = $d.SemanticChangedProfileCount; Unchanged = $d.SemanticUnchangedProfileCount }
        }
        [System.IO.File]::WriteAllText($PinPath, ($pin | ConvertTo-Json -Depth 5), $utf8)
    }

    $script:profileA = '<GameProfile><GameName>A</GameName></GameProfile>'
    $script:profileB = '<GameProfile><GameName>B</GameName></GameProfile>'
    $script:profileC = '<GameProfile><GameName>C</GameName></GameProfile>'
    $script:profileX = '<GameProfile><GameName>X</GameName></GameProfile>'
    $script:installA = Join-Path $script:work 'installA'
    $script:installB = Join-Path $script:work 'installB'
    New-FixtureInstall -Path $script:installA -ExeText 'exe-A' -Profiles @{ a = $script:profileA; b = $script:profileB; c = $script:profileC; x = $script:profileX }
    # B: a same, b changed in content, c only re-indented, x gone, d new.
    New-FixtureInstall -Path $script:installB -ExeText 'exe-B' -Profiles @{ a = $script:profileA; b = '<GameProfile><GameName>B2</GameName></GameProfile>'; c = "<GameProfile>`r`n  <GameName>C</GameName>`r`n</GameProfile>"; d = '<GameProfile><GameName>D</GameName></GameProfile>' }

    $stub = [ordered]@{
        SnapshotId = 'TPM-GAME-SUPPORT-RELEASE-1.0.0.1000-ASSET-00000000'
        Release = [ordered]@{ Version = '1.0.0.1000'; Tag = 'old'; AssetName = 'old.zip'; AssetSize = 1; AssetSha256 = ('0' * 64); AssetUpdatedAt = '2026-01-01T00:00:00Z' }
        SourceProof = [ordered]@{ Commit = 'previous-proof' }
        Files = @()
    }
    $script:stubFolder = Join-Path $script:work 'stub'
    [void][System.IO.Directory]::CreateDirectory($script:stubFolder)
    [System.IO.File]::WriteAllText((Join-Path $script:stubFolder 'snapshot-manifest.json'), ($stub | ConvertTo-Json -Depth 6), $utf8)

    $script:idA = Get-FixtureId -Path $script:installA -Version '1.0.0.2000'
    $script:idB = Get-FixtureId -Path $script:installB -Version '1.0.0.2001'
    $script:out1 = Join-Path $script:work 'snapshot1'
    $script:out2 = Join-Path $script:work 'snapshot2'
    $script:beforeA = Get-FolderHashes -Path $script:installA
    $script:run1 = & $script:tool -InstallRoot $script:installA -PreviousSnapshotPath $script:stubFolder -OutputRoot $script:out1 -SnapshotId $script:idA -CapturedAtUtc '2026-11-27T10:00:00Z' -InstallVersion '1.0.0.2000' | ConvertFrom-Json
    $script:afterA = Get-FolderHashes -Path $script:installA
    $script:run2 = & $script:tool -InstallRoot $script:installB -PreviousSnapshotPath $script:out1 -OutputRoot $script:out2 -SnapshotId $script:idB -CapturedAtUtc '2026-11-27T11:00:00Z' -InstallVersion '1.0.0.2001' | ConvertFrom-Json
    $script:manifest1 = Get-Content -LiteralPath (Join-Path $script:out1 'snapshot-manifest.json') -Raw | ConvertFrom-Json
    $script:manifest2 = Get-Content -LiteralPath (Join-Path $script:out2 'snapshot-manifest.json') -Raw | ConvertFrom-Json
    $script:delta2 = Get-Content -LiteralPath (Join-Path $script:out2 'delta.json') -Raw | ConvertFrom-Json
    $script:pin2 = Join-Path $script:work 'pin2.json'
    New-FixturePin -SnapshotFolder $script:out2 -PinPath $script:pin2
}

AfterAll {
    if ($script:work -and (Test-Path -LiteralPath $script:work)) { Remove-Item -LiteralPath $script:work -Recurse -Force -ErrorAction SilentlyContinue }
}

Describe 'Snapshot from an installed folder' {
    It 'lists every profile with its path, size and SHA-256, names the exe as the asset, and leaves the install untouched' {
        $script:beforeA | Should -BeExactly $script:afterA
        $script:manifest1.SnapshotId | Should -BeExactly $script:idA
        @($script:manifest1.Files | ForEach-Object RelativePath) | Should -Be @('GameProfiles/a.xml', 'GameProfiles/b.xml', 'GameProfiles/c.xml', 'GameProfiles/x.xml')
        $b = $script:manifest1.Files | Where-Object ProfileCode -eq 'b'
        $b.Length | Should -Be ([System.IO.FileInfo](Join-Path $script:installA 'GameProfiles\b.xml')).Length
        $b.Sha256 | Should -BeExactly (Get-FileHash -LiteralPath (Join-Path $script:installA 'GameProfiles\b.xml') -Algorithm SHA256).Hash.ToLowerInvariant()
        $script:manifest1.CatalogCounts.GameProfiles | Should -Be 4
        $script:manifest1.CatalogCounts.TotalFiles | Should -Be 4
        $script:manifest1.Release.AssetName | Should -BeExactly 'TeknoParrotUi.exe'
        $script:manifest1.Release.AssetSha256 | Should -BeExactly (Get-FileHash -LiteralPath (Join-Path $script:installA 'TeknoParrotUi.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
        $script:manifest1.SourceKind | Should -BeExactly 'INSTALLED_FOLDER'
        $script:run1.SkippedFiles | Should -Contain 'GameProfiles/readme.txt'
        (Get-Content -LiteralPath (Join-Path $script:out1 'snapshot-manifest.json') -Raw) | Should -Not -Match 'UserSecret|UserProfiles'
    }

    It 'computes the delta against the previous snapshot from its manifest' {
        @($script:delta2.Added) | Should -Be @('d')
        @($script:delta2.Removed) | Should -Be @('x')
        @($script:delta2.Changed) | Should -Be @('b')
        @($script:delta2.Unchanged) | Should -Be @('a', 'c')
        $script:delta2.RawByteDifferentProfileCount | Should -Be 2
        $script:delta2.FormattingOnlyChangedProfileCount | Should -Be 1
        $script:delta2.HistoricalSnapshotId | Should -BeExactly $script:idA
    }

    It 'makes a folder the verifier accepts, and the verifier exits 0 with the install as the catalog root' {
        $result = & $script:verifier -ManifestPath (Join-Path $script:out2 'snapshot-manifest.json') -PinPath $script:pin2 -CatalogRoot $script:installB | ConvertFrom-Json
        $result.Errors | Should -BeNullOrEmpty
        $result.Valid | Should -BeTrue
        $hostExe = (Get-Process -Id $PID).Path
        [void](& $hostExe -NoProfile -File $script:verifier -ManifestPath (Join-Path $script:out2 'snapshot-manifest.json') -PinPath $script:pin2)
        $LASTEXITCODE | Should -Be 0
    }

    It 'refuses a profile that changed after the snapshot, and a manifest edited by hand' {
        $tampered = Join-Path $script:work 'installB-tampered'
        Copy-Item -LiteralPath $script:installB -Destination $tampered -Recurse
        [System.IO.File]::WriteAllText((Join-Path $tampered 'GameProfiles\a.xml'), '<GameProfile><GameName>A-changed</GameName></GameProfile>', (New-Object System.Text.UTF8Encoding($false)))
        $bad = & $script:verifier -ManifestPath (Join-Path $script:out2 'snapshot-manifest.json') -PinPath $script:pin2 -CatalogRoot $tampered | ConvertFrom-Json
        $bad.Valid | Should -BeFalse
        @($bad.Errors) -join ';' | Should -Match 'File hash/length mismatch: GameProfiles/a.xml'

        $edited = Get-Content -LiteralPath (Join-Path $script:out2 'snapshot-manifest.json') -Raw | ConvertFrom-Json
        $edited.Files[0].SemanticSha256 = ('f' * 64)
        $editedPath = Join-Path $script:work 'edited-manifest.json'
        $edited | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $editedPath -Encoding UTF8
        $bad2 = & $script:verifier -ManifestPath $editedPath -PinPath $script:pin2 | ConvertFrom-Json
        $bad2.Valid | Should -BeFalse
        @($bad2.Errors) -join ';' | Should -Match 'Semantic root digest mismatch: GameProfiles'
    }

    It 'refuses a snapshot id that is not the version plus the exe hash, and an output folder inside the install' {
        { & $script:tool -InstallRoot $script:installB -PreviousSnapshotPath $script:out1 -OutputRoot (Join-Path $script:work 'x1') -SnapshotId 'TPM-GAME-SUPPORT-RELEASE-1.0.0.2001-ASSET-DEADBEEF' -CapturedAtUtc '2026-11-27T11:00:00Z' -InstallVersion '1.0.0.2001' } | Should -Throw '*SnapshotId must be*'
        { & $script:tool -InstallRoot $script:installB -PreviousSnapshotPath $script:out1 -OutputRoot (Join-Path $script:installB 'out') -SnapshotId $script:idB -CapturedAtUtc '2026-11-27T11:00:00Z' -InstallVersion '1.0.0.2001' } | Should -Throw '*must not be inside the install*'
        Test-Path -LiteralPath (Join-Path $script:installB 'out') | Should -BeFalse
    }
}

Describe 'Moving the pins to a new snapshot' {
    BeforeAll {
        $oldId = 'TPM-GAME-SUPPORT-RELEASE-1.0.0.1000-ASSET-0000AAAA'
        $oldSha = 'a' * 64
        $script:oldId = $oldId
        $repo = Join-Path $script:work 'repo'
        $script:repo = $repo
        foreach ($folder in @('contracts\snapshots', 'scripts', 'Tests', 'docs\remediation')) { [void][System.IO.Directory]::CreateDirectory((Join-Path $repo $folder)) }
        Copy-Item -LiteralPath $script:out2 -Destination (Join-Path $repo ('contracts\snapshots\' + $script:idB)) -Recurse
        Copy-Item -LiteralPath $script:verifier -Destination (Join-Path $repo 'scripts\Test-TpmReleaseCatalogSnapshot.ps1')
        $oldPin = [ordered]@{ SnapshotId = $oldId; Version = '1.0.0.1000'; AssetSha256 = $oldSha; AssetSize = 1; SourceProofCommit = 'old'; CatalogCounts = [ordered]@{ GameProfiles = 9; GameSetup = 0; Metadata = 0; TotalFiles = 9 }; Delta = [ordered]@{ Historical = 1; Current = 9; Added = 8; Removed = 0; Changed = 0; Unchanged = 1 } }
        $script:pinFile = Join-Path $repo 'contracts\snapshots\CURRENT-SNAPSHOT-PIN.json'
        [System.IO.File]::WriteAllText($script:pinFile, ($oldPin | ConvertTo-Json -Depth 5), $utf8)
        [System.IO.File]::WriteAllText((Join-Path $repo 'docs\GUIDE.md'), "Pinned: $oldId`r`nHash $oldSha`r`n", $utf8)
        [System.IO.File]::WriteAllText((Join-Path $repo 'Tests\Some.Tests.ps1'), "`$id = '$oldId'`r`n", $utf8)
        [System.IO.File]::WriteAllText((Join-Path $repo 'docs\remediation\PR-1.md'), "History: $oldId`r`n", $utf8)
        $script:untouchedBefore = Get-FolderHashes -Path $repo
    }

    It 'with -DryRun lists the files it would change and writes nothing' {
        $r = & $script:updater -OldSnapshotId $script:oldId -NewSnapshotId $script:idB -NewVersion '1.0.0.2001' -RepoRoot $script:repo -DryRun | ConvertFrom-Json
        $r.DryRun | Should -BeTrue
        @($r.FilesChanged | ForEach-Object File) | Should -Contain 'docs\GUIDE.md'
        @($r.FilesChanged | ForEach-Object File) | Should -Contain 'Tests\Some.Tests.ps1'
        Get-FolderHashes -Path $script:repo | Should -BeExactly $script:untouchedBefore
    }

    It 'refuses a version that is not the new snapshot version, changing nothing' {
        { & $script:updater -OldSnapshotId $script:oldId -NewSnapshotId $script:idB -NewVersion '9.9.9.9' -RepoRoot $script:repo } | Should -Throw '*not 9.9.9.9*'
        Get-FolderHashes -Path $script:repo | Should -BeExactly $script:untouchedBefore
    }

    It 'rewrites the pin file and every pinned file, leaves history alone, and the verifier then accepts the new snapshot' {
        $r = & $script:updater -OldSnapshotId $script:oldId -NewSnapshotId $script:idB -NewVersion '1.0.0.2001' -RepoRoot $script:repo | ConvertFrom-Json
        $r.Verification | Should -BeExactly 'VALID'
        $pin = Get-Content -LiteralPath $script:pinFile -Raw | ConvertFrom-Json
        $pin.SnapshotId | Should -BeExactly $script:idB
        $pin.Version | Should -BeExactly '1.0.0.2001'
        $pin.AssetSha256 | Should -BeExactly $script:manifest2.Release.AssetSha256
        $pin.CatalogCounts.GameProfiles | Should -Be 4
        $pin.Delta.Added | Should -Be 1
        $pin.Delta.Removed | Should -Be 1
        $guide = Get-Content -LiteralPath (Join-Path $script:repo 'docs\GUIDE.md') -Raw
        $guide | Should -Match ([regex]::Escape($script:idB))
        $guide | Should -Match $script:manifest2.Release.AssetSha256
        $guide | Should -Not -Match 'ASSET-0000AAAA'
        (Get-Content -LiteralPath (Join-Path $script:repo 'Tests\Some.Tests.ps1') -Raw) | Should -Match ([regex]::Escape($script:idB))
        (Get-Content -LiteralPath (Join-Path $script:repo 'docs\remediation\PR-1.md') -Raw) | Should -Match 'ASSET-0000AAAA'
        @($r.HistoricalRecordsStillNamingOldSnapshot) | Should -Contain 'docs\remediation\PR-1.md'
    }

    It 'will not run again for the old id once the pin has moved' {
        { & $script:updater -OldSnapshotId $script:oldId -NewSnapshotId $script:idB -NewVersion '1.0.0.2001' -RepoRoot $script:repo } | Should -Throw '*not TPM-GAME-SUPPORT-RELEASE-1.0.0.1000-ASSET-0000AAAA*'
    }
}
