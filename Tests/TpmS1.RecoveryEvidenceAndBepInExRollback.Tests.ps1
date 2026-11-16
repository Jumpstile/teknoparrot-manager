param([string]$RepositoryRoot = [IO.Path]::GetDirectoryName($PSScriptRoot))

# Isolated regression tests for #332 (private PostgreSQL recovery evidence during
# owned-state migration) and #366 (BepInEx journal-based rollback). Every fixture
# lives under a fresh synthetic temp directory; nothing touches a game, profile,
# TeknoParrot/LaunchBox install, database, or service.

BeforeAll {
    $script:S1Evidence = [string]$TestDrive
    $script:S1Source = Join-Path $RepositoryRoot 'TeknoParrot-Manager.ps1'
    $errors = $null
    $script:S1Ast = [Management.Automation.Language.Parser]::ParseFile($script:S1Source, [ref]$null, [ref]$errors)
    if ($errors.Count) { throw 'Source parse failed.' }
    foreach ($function in @($script:S1Ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) {
        . ([scriptblock]::Create($function.Extent.Text))
    }
    function Write-TpmCompactExtractionProgress { param($Phase, $Label, $Current, $Total, $StartedAt, [switch]$Complete, $Outcome) }
    function Write-Log { param([string]$msg) }

    function Resolve-S1FinalPath {
        # The BepInEx recovery pinning demands canonical (non-8.3) final paths.
        param([Parameter(Mandatory)][string]$Path)
        $null = Get-TpmSupportNativeType
        $handle = [TpmSupportNativeMethods]::CreateFile($Path, [TpmSupportNativeMethods]::FileReadAttributes, 7, [IntPtr]::Zero, [TpmSupportNativeMethods]::OpenExisting, [TpmSupportNativeMethods]::FileFlagBackupSemantics, [IntPtr]::Zero)
        if ($handle.IsInvalid) { throw "Cannot resolve fixture path $Path" }
        try { return (Get-TpmSupportFinalPathFromHandle -Handle $handle).TrimEnd('\') } finally { $handle.Dispose() }
    }
    function New-S1Directory {
        # Short name: the migration backup tree appends LegacyMigration_<32 hex>\PostgresRecoveryBackups\evidence-1\..., and Windows PowerShell 5.1 fails above 259 characters on a deep sandbox temp root.
        $path = Join-Path $script:S1Evidence ('s1-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][IO.Directory]::CreateDirectory($path)
        return (Resolve-S1FinalPath -Path $path)
    }
    function Get-S1ForeignAceCount {
        param([Parameter(Mandatory)][string]$Path)
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $count = 0
        foreach ($item in @($Path) + @(Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object { $_.FullName })) {
            foreach ($ace in (Get-Acl -LiteralPath $item).Access) {
                $resolved = $null
                try { $resolved = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch {}
                if ($ace.IsInherited -or $resolved -ne $sid) { $count++ }
            }
        }
        return $count
    }
    function Get-S1Snapshot {
        param([Parameter(Mandatory)][string]$Dir)
        return @(Get-ChildItem -LiteralPath $Dir -Force -Recurse | Sort-Object FullName | ForEach-Object {
            '{0}|{1}|{2}' -f $_.FullName.Substring($Dir.Length), $_.PSIsContainer, $(if ($_.PSIsContainer) { '' } else { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
        })
    }
    function New-S1RecoveryFixture {
        $root = New-S1Directory
        $program = Join-Path $root 'program'
        $teknoParrot = Join-Path $root 'TeknoParrot'
        [void][IO.Directory]::CreateDirectory($program)
        [void][IO.Directory]::CreateDirectory($teknoParrot)
        $layout = Initialize-TpmOwnedLayout -Layout (Get-TpmOwnedLayout -TeknoParrotRoot $teknoParrot)
        $legacy = Join-Path $program 'PostgresRecoveryBackups'
        $nested = Join-Path $legacy 'evidence-1\PostgreSQL'
        [void][IO.Directory]::CreateDirectory($nested)
        [void][IO.Directory]::CreateDirectory((Join-Path $legacy 'evidence-1\Profiles'))
        [IO.File]::WriteAllText((Join-Path $nested 'pg_hba.conf'), 'host all all 127.0.0.1/32 md5', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllBytes((Join-Path $legacy 'evidence-1\TeknoParrot-Manager.config.json'), [byte[]](0, 1, 2, 250, 251, 252))
        $manifest = Get-TpmDirectoryManifest -Path $legacy
        return [pscustomobject]@{ Root = $root; Program = $program; Layout = $layout; Legacy = $legacy; Managed = (Join-Path $layout.Backups 'PostgresRecoveryBackups'); ManifestHash = $manifest.ManifestHash }
    }
    function Add-S1Staged {
        param([string]$Relative, [string]$Text)
        $path = Join-Path $script:Stage $Relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path, $Text)
    }
}

Describe '#332 PostgreSQL recovery evidence stays private through owned-state migration' {
    It 'discovers PostgresRecoveryBackups, routes it to managed Backups, and keeps the backup and final trees private' {
        $f = New-S1RecoveryFixture
        $items = @(Get-TpmLegacyOwnedItems -ScriptRoot $f.Program)
        $items.Name | Should -Contain 'PostgresRecoveryBackups'
        $items.Name | Should -Not -Contain 'PostgresBackups'
        Mock Read-TpmYesNo { 'Y' }
        $migration = Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'SUCCEEDED'
        Test-Path -LiteralPath $f.Legacy | Should -BeFalse
        (Get-TpmDirectoryManifest -Path $f.Managed).ManifestHash | Should -BeExactly $f.ManifestHash
        Get-S1ForeignAceCount -Path $f.Managed | Should -Be 0
        $backupRoot = @(Get-ChildItem -LiteralPath $f.Layout.Backups -Directory -Filter 'LegacyMigration_*')
        $backupRoot.Count | Should -Be 1
        $backupCopy = Join-Path $backupRoot[0].FullName 'PostgresRecoveryBackups'
        (Get-TpmDirectoryManifest -Path $backupCopy).ManifestHash | Should -BeExactly $f.ManifestHash
        Get-S1ForeignAceCount -Path $backupCopy | Should -Be 0
    }

    It 'stops before copying or moving when the source ACL cannot be applied' {
        $f = New-S1RecoveryFixture
        $before = Get-S1Snapshot -Dir $f.Legacy
        $legacyPath = $f.Legacy
        $script:S1Real = Get-Command Lock-PostgresRecoveryDirectory -CommandType Function
        Mock Lock-PostgresRecoveryDirectory { & $script:S1Real @PesterBoundParameters }
        Mock Lock-PostgresRecoveryDirectory { throw 'injected ACL failure' } -ParameterFilter { $Path -eq $legacyPath }
        Mock Read-TpmYesNo { 'Y' }
        $migration = Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -Not -BeExactly 'SUCCEEDED'
        Test-Path -LiteralPath $f.Managed | Should -BeFalse
        foreach ($backupRoot in @(Get-ChildItem -LiteralPath $f.Layout.Backups -Directory -Filter 'LegacyMigration_*')) {
            Test-Path -LiteralPath (Join-Path $backupRoot.FullName 'PostgresRecoveryBackups') | Should -BeFalse
        }
        Get-S1Snapshot -Dir $f.Legacy | Should -Be $before
    }

    It 'keeps every path private and deletes nothing when the source cannot be removed after the protected copy' {
        $f = New-S1RecoveryFixture
        $before = Get-S1Snapshot -Dir $f.Legacy
        $legacyPath = $f.Legacy
        $script:S1Real = Get-Command Remove-Item -CommandType Cmdlet
        Mock Remove-Item { & $script:S1Real @PesterBoundParameters }
        Mock Remove-Item { throw 'injected delete failure' } -ParameterFilter { $LiteralPath -eq $legacyPath }
        Mock Read-TpmYesNo { 'Y' }
        $migration = Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -Not -BeExactly 'SUCCEEDED'
        Get-S1Snapshot -Dir $f.Legacy | Should -Be $before
        Get-S1Snapshot -Dir $f.Managed | Should -Be $before
        Get-S1ForeignAceCount -Path $f.Legacy | Should -Be 0
        Get-S1ForeignAceCount -Path $f.Managed | Should -Be 0
        $backupCopy = Join-Path (@(Get-ChildItem -LiteralPath $f.Layout.Backups -Directory -Filter 'LegacyMigration_*')[0]).FullName 'PostgresRecoveryBackups'
        Get-S1Snapshot -Dir $backupCopy | Should -Be $before
        Get-S1ForeignAceCount -Path $backupCopy | Should -Be 0
    }

    It 'rolls back through the protected path when post-move verification fails' {
        $f = New-S1RecoveryFixture
        $before = Get-S1Snapshot -Dir $f.Legacy
        $managedPath = $f.Managed
        $script:S1Real = Get-Command Get-TpmDirectoryManifest -CommandType Function
        Mock Get-TpmDirectoryManifest { & $script:S1Real @PesterBoundParameters }
        Mock Get-TpmDirectoryManifest { [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $true; ManifestHash = 'MISMATCH'; Items = @() } } -ParameterFilter { $ProgressLabel -eq 'Owned-state destination verification' -and $Path -eq $managedPath }
        Mock Read-TpmYesNo { 'Y' }
        $migration = Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        Test-Path -LiteralPath $f.Managed | Should -BeFalse
        Get-S1Snapshot -Dir $f.Legacy | Should -Be $before
        Get-S1ForeignAceCount -Path $f.Legacy | Should -Be 0
    }

    It 'reports ACTION_REQUIRED and preserves private evidence when rollback cannot remove the destination' {
        $f = New-S1RecoveryFixture
        $before = Get-S1Snapshot -Dir $f.Legacy
        $managedPath = $f.Managed
        $script:S1Real = Get-Command Get-TpmDirectoryManifest -CommandType Function
        Mock Get-TpmDirectoryManifest { & $script:S1Real @PesterBoundParameters }
        $script:S1RealRemove = Get-Command Remove-Item -CommandType Cmdlet
        Mock Remove-Item { & $script:S1RealRemove @PesterBoundParameters }
        Mock Get-TpmDirectoryManifest { [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $true; ManifestHash = 'MISMATCH'; Items = @() } } -ParameterFilter { $ProgressLabel -eq 'Owned-state destination verification' -and $Path -eq $managedPath }
        Mock Remove-Item { throw 'injected rollback delete failure' } -ParameterFilter { $LiteralPath -eq $managedPath }
        Mock Read-TpmYesNo { 'Y' }
        $migration = Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        Get-S1Snapshot -Dir $f.Managed | Should -Be $before
        Get-S1Snapshot -Dir $f.Legacy | Should -Be $before
        Get-S1ForeignAceCount -Path $f.Managed | Should -Be 0
        Get-S1ForeignAceCount -Path $f.Legacy | Should -Be 0
    }

    It 'refuses to delete a source that gained a file after the protected copy and keeps both trees' {
        $f = New-S1RecoveryFixture
        Lock-TpmOwnedMigrationBackupTree -Path $f.Legacy -StartedAt (Get-Date)
        $before = Get-S1Snapshot -Dir $f.Legacy
        $destPath = Join-Path (New-S1Directory) 'PostgresRecoveryBackups'
        $script:S1LateFile = Join-Path $f.Legacy 'evidence-1\late-evidence.txt'
        # The late file appears after the copy was taken and while the copy is being verified.
        $script:S1Real = Get-Command Assert-TpmPrivateRecoveryTree -CommandType Function
        Mock Assert-TpmPrivateRecoveryTree { & $script:S1Real @PesterBoundParameters }
        Mock Assert-TpmPrivateRecoveryTree { [IO.File]::WriteAllText($script:S1LateFile, 'LATE') } -ParameterFilter { $Path -eq $destPath }
        { Move-TpmProtectedRecoveryTree -Source $f.Legacy -Destination $destPath -ExpectedManifestHash $f.ManifestHash -StartedAt (Get-Date) } | Should -Throw '*source changed after it was copied*'
        [IO.File]::ReadAllText($script:S1LateFile) | Should -BeExactly 'LATE'
        $after = Get-S1Snapshot -Dir $f.Legacy
        foreach ($line in $before) { $after | Should -Contain $line }
        Test-Path -LiteralPath $destPath | Should -BeTrue
    }

    It 'reports ACTION_REQUIRED and keeps the late file when evidence is written to the legacy tree after the protected copy' {
        $f = New-S1RecoveryFixture
        $before = Get-S1Snapshot -Dir $f.Legacy
        $managedPath = $f.Managed
        $script:S1LateFile = Join-Path $f.Legacy 'evidence-1\late-evidence.txt'
        $script:S1Real = Get-Command Assert-TpmPrivateRecoveryTree -CommandType Function
        Mock Assert-TpmPrivateRecoveryTree { & $script:S1Real @PesterBoundParameters }
        Mock Assert-TpmPrivateRecoveryTree { if (-not (Test-Path -LiteralPath $script:S1LateFile)) { [IO.File]::WriteAllText($script:S1LateFile, 'LATE') } } -ParameterFilter { $Path -eq $managedPath }
        Mock Read-TpmYesNo { 'Y' }
        $migration = Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -Not -BeExactly 'SUCCEEDED'
        $migration.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        [IO.File]::ReadAllText($script:S1LateFile) | Should -BeExactly 'LATE'
        $after = Get-S1Snapshot -Dir $f.Legacy
        foreach ($line in $before) { $after | Should -Contain $line }
        Test-Path -LiteralPath $f.Managed | Should -BeTrue
    }
}

Describe '#366 BepInEx tree promotion rolls back by journal and preserves foreign changes' {
    BeforeEach {
        $script:Stage = Join-Path (New-S1Directory) 'stage'
        $script:Game = Join-Path (New-S1Directory) 'game'
        [void][IO.Directory]::CreateDirectory($script:Stage)
        [void][IO.Directory]::CreateDirectory((Join-Path $script:Game 'BepInEx'))
        [IO.File]::WriteAllText((Join-Path $script:Game 'BepInEx\core.dll'), 'ORIGINAL-CORE')
        Add-S1Staged 'BepInEx\core.dll' 'NEW-CORE'
    }

    It 'restores originals and removes transaction-created directories when promotion fails after a nested file' {
        Add-S1Staged 'BepInEx\plugins\deep\p.dll' 'NEW-PLUGIN'
        Add-S1Staged 'zzz.dll' 'NEW-LAST'
        $before = Get-S1Snapshot -Dir $script:Game
        $held = [IO.File]::Open((Join-Path $script:Stage 'zzz.dll'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            $caught = $null
            try { Invoke-TpmTransactionalTreePromote -StagingDir $script:Stage -DestDir $script:Game -RelativeFiles @('BepInEx\core.dll', 'BepInEx\plugins\deep\p.dll', 'zzz.dll') } catch { $caught = $_ }
        } finally { $held.Dispose() }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -Not -Match 'ROLLBACK FAILED'
        Get-S1Snapshot -Dir $script:Game | Should -Be $before
        Test-Path -LiteralPath (Join-Path $script:Stage '.tpm-rollback-backup') | Should -BeFalse
    }

    It 'never overwrites a file created concurrently at the creation boundary' {
        Add-S1Staged 'BepInEx\z-new.dll' 'NEW-Z'
        $concurrent = Join-Path $script:Game 'BepInEx\z-new.dll'
        Mock Write-Log { if ($msg -like "*verification: 'BepInEx\z-new.dll'*") { [IO.File]::WriteAllText($concurrent, 'CONCURRENT') } }
        { Invoke-TpmTransactionalTreePromote -StagingDir $script:Stage -DestDir $script:Game -RelativeFiles @('BepInEx\core.dll', 'BepInEx\z-new.dll') } | Should -Throw
        [IO.File]::ReadAllText($concurrent) | Should -BeExactly 'CONCURRENT'
        [IO.File]::ReadAllText((Join-Path $script:Game 'BepInEx\core.dll')) | Should -BeExactly 'ORIGINAL-CORE'
    }

    It 'preserves an edited promoted file and reports ROLLBACK FAILED with evidence retained' {
        Add-S1Staged 'BepInEx\extra.dll' 'NEW-EXTRA'
        $edited = Join-Path $script:Game 'BepInEx\extra.dll'
        $validation = { [IO.File]::AppendAllText($edited, '-USER-EDIT'); return $false }
        $caught = $null
        try { Invoke-TpmTransactionalTreePromote -StagingDir $script:Stage -DestDir $script:Game -RelativeFiles @('BepInEx\core.dll', 'BepInEx\extra.dll') -ValidationScript $validation } catch { $caught = $_ }
        $caught.Exception.Message | Should -Match 'ROLLBACK FAILED'
        [IO.File]::ReadAllText($edited) | Should -BeExactly 'NEW-EXTRA-USER-EDIT'
        [IO.File]::ReadAllText((Join-Path $script:Game 'BepInEx\core.dll')) | Should -BeExactly 'ORIGINAL-CORE'
        Test-Path -LiteralPath (Join-Path $script:Stage '.tpm-rollback-backup\BepInEx\core.dll') | Should -BeTrue
    }

    It 'preserves a replaced owned directory and its foreign content' {
        Add-S1Staged 'BepInEx\owned\x.dll' 'NEW-X'
        $owned = Join-Path $script:Game 'BepInEx\owned'
        $validation = {
            Remove-Item -LiteralPath $owned -Recurse -Force
            [void][IO.Directory]::CreateDirectory($owned)
            [IO.File]::WriteAllText((Join-Path $owned 'foreign.txt'), 'FOREIGN')
            return $false
        }
        $caught = $null
        try { Invoke-TpmTransactionalTreePromote -StagingDir $script:Stage -DestDir $script:Game -RelativeFiles @('BepInEx\core.dll', 'BepInEx\owned\x.dll') -ValidationScript $validation } catch { $caught = $_ }
        $caught.Exception.Message | Should -Match 'ROLLBACK FAILED'
        [IO.File]::ReadAllText((Join-Path $owned 'foreign.txt')) | Should -BeExactly 'FOREIGN'
        [IO.File]::ReadAllText((Join-Path $script:Game 'BepInEx\core.dll')) | Should -BeExactly 'ORIGINAL-CORE'
    }

    It 'records the partial-write hash under the exclusive handle so a later concurrent edit is never removed on identity alone' {
        $source = Join-Path $script:Stage 'BepInEx\core.dll'
        $dest = Join-Path $script:Game 'BepInEx\partial.dll'
        $script:S1Identity = $null; $script:S1Partial = 'UNSET'
        { Write-TpmTreeFile -Source $source -Destination $dest -Mode Create -OnOwned { param($identity) $script:S1Identity = $identity; throw 'injected failure after ownership' } -OnPartial { param($hash) $script:S1Partial = $hash } } | Should -Throw '*injected failure after ownership*'
        $script:S1Identity | Should -Not -BeNullOrEmpty
        $script:S1Partial | Should -BeExactly (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        [IO.File]::WriteAllText($dest, 'CONCURRENT-EDIT')
        { Remove-TpmTreeOwnedFile -Path $dest -ExpectedIdentity $script:S1Identity -ExpectedSha256 $script:S1Partial } | Should -Throw '*changed after promotion*'
        [IO.File]::ReadAllText($dest) | Should -BeExactly 'CONCURRENT-EDIT'
    }

    It 'reports an unreadable partial write as unknown (null hash) rather than as owned content' {
        $source = Join-Path $script:Stage 'BepInEx\core.dll'
        $dest = Join-Path $script:Game 'BepInEx\unknown.dll'
        $script:S1Partial = 'UNSET'
        $script:S1Real = Get-Command Get-FileHash -CommandType Function,Cmdlet
        Mock Get-FileHash { & $script:S1Real @PesterBoundParameters }
        Mock Get-FileHash { throw 'injected hash failure' } -ParameterFilter { $InputStream -and $InputStream.Name -eq $dest }
        { Write-TpmTreeFile -Source $source -Destination $dest -Mode Create -OnOwned { param($identity) throw 'injected failure after ownership' } -OnPartial { param($hash) $script:S1Partial = $hash } } | Should -Throw
        $script:S1Partial | Should -BeNullOrEmpty
    }
}
