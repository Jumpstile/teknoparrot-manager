Describe 'A missing file inside a bracketed game folder ([TP]) is reported as missing' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $want = @('Get-TpmSupportNativeType', 'Get-TpmSupportFinalPathFromHandle', 'Resolve-TpmSupportExpectedFinalPath', 'Remove-TpmSupportHandle',
            'Get-TpmTreeFileState', 'Remove-TpmTreeOwnedFile', 'Test-TpmGameMutationPath', 'Remove-PostgresTrustRuleMarker')
        $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $want -contains $n.Name }, $true)
        foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
        $script:Base = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-380-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:Game = Join-Path $script:Base 'Alpha Game (1.00)[TP]'
        New-Item -ItemType Directory -Force -Path $script:Game | Out-Null
    }
    AfterAll {
        if ($script:Base -and (Test-Path -LiteralPath $script:Base)) { Remove-Item -LiteralPath $script:Base -Recurse -Force }
    }

    It 'reports a missing file in a [TP] folder as absent, not unreadable' {
        $state = Get-TpmTreeFileState -Path (Join-Path $script:Game 'winhttp.dll')
        $state.Kind | Should -Be 'Absent'
    }
    It 'reports a missing file in a [TP] folder with its own brackets as absent' {
        $state = Get-TpmTreeFileState -Path (Join-Path $script:Game 'sub[1]\file.txt')
        $state.Kind | Should -Be 'Absent'
    }
    It 'still reads a real file in a [TP] folder' {
        $p = Join-Path $script:Game 'real.txt'
        Set-Content -LiteralPath $p -Value 'x'
        (Get-TpmTreeFileState -Path $p).Kind | Should -Be 'File'
    }
    It 'still refuses a folder sitting where a file should be' {
        $d = Join-Path $script:Game 'folder.txt'
        New-Item -ItemType Directory -Path $d | Out-Null
        (Get-TpmTreeFileState -Path $d).Kind | Should -Be 'Other'
    }
    It 'undoing a file that is already gone from a [TP] folder says Absent instead of failing' {
        $r = Remove-TpmTreeOwnedFile -Path (Join-Path $script:Game 'gone.dll') -ExpectedIdentity 'any'
        $r | Should -Be 'Absent'
    }
    It 'a registered game path that is gone from a [TP] folder is reported as missing, with or without the leaf requirement' {
        $gone = Join-Path $script:Game 'gone.exe'
        (Test-TpmGameMutationPath -GamePath $gone -RequireLeaf).ReasonCode | Should -Be 'GAME_PATH_MISSING'
        (Test-TpmGameMutationPath -GamePath $gone).ReasonCode | Should -Be 'GAME_PATH_MISSING'
        (Test-TpmGameMutationPath -GamePath (Join-Path $script:Base 'Missing (1.00)[TP]\game.exe')).Valid | Should -BeFalse
    }
    It 'removing a PostgreSQL recovery marker that is already gone from a [TP] folder finishes quietly' {
        $script:MarkerForTest = Join-Path $script:Game 'marker.json'
        function Get-PostgresTrustRuleMarkerPath { return $script:MarkerForTest }
        { Remove-PostgresTrustRuleMarker } | Should -Not -Throw
        Set-Content -LiteralPath $script:MarkerForTest -Value '{}'
        { Remove-PostgresTrustRuleMarker } | Should -Not -Throw
        [System.IO.File]::Exists($script:MarkerForTest) | Should -BeFalse
    }
}

# #380, Windows PowerShell 5.1 and pwsh 7: a folder with square brackets in its name ("Game [Bracket] (1.0)") must not make
# the profile backup, the backup copy or the restore skip, miss or lose files (a bare -Path treats [..] as a wildcard).
Describe 'Backup and restore work inside a folder with square brackets (issue 380)' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $want = @('New-TpmVerifiedUserProfilesBackup', 'Get-TpmUserProfilesBackupManifest', 'Copy-TpmAutoSyncUserProfilesBackup',
            'Get-TpmUserProfilesBackupMarkerName', 'Get-TpmUserProfilesBackupStagingPrefix', 'Get-TpmUserProfilesBackupStagingPath',
            'Get-TpmUserProfilesBackupInventory', 'Get-TpmUserProfilesBackupInventoryKeys', 'Test-TpmUserProfilesMatchInventory',
            'Move-TpmDirectoryWithRetry', 'Complete-TpmUserProfilesBackupFolder', 'Test-TpmNoReparsePath',
            'Get-TpmDirectoryEntriesWithDiscoveryProgress', 'Restore-TpmLegacyUserProfilesSnapshot')
        foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $want -contains $n.Name }, $true)) { . ([scriptblock]::Create($f.Extent.Text)) }
        function Write-TpmCompactExtractionProgress { }
        function Write-Log { param($m) }
        $script:BrBase = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-380b-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:BrGame = Join-Path $script:BrBase 'Game [Bracket] (1.0)'
        function New-BracketProfiles {
            param([string]$Name)
            $dir = Join-Path $script:BrGame $Name
            [void][System.IO.Directory]::CreateDirectory((Join-Path $dir 'Sub [1]'))
            [System.IO.File]::WriteAllText((Join-Path $dir 'Alpha.xml'), '<GameProfile />')
            [System.IO.File]::WriteAllText((Join-Path $dir 'Sub [1]\Beta.xml'), '<GameProfile><A/></GameProfile>')
            return $dir
        }
    }
    AfterAll {
        if ($script:BrBase -and [System.IO.Directory]::Exists($script:BrBase)) { Remove-Item -LiteralPath $script:BrBase -Recurse -Force }
    }

    It 'a verified profile backup made inside a bracketed folder keeps every file' {
        $profiles = New-BracketProfiles -Name 'UserProfiles'
        $r = New-TpmVerifiedUserProfilesBackup -UserProfilesDir $profiles -Label 'Test'
        $r.Succeeded | Should -BeTrue
        [System.IO.File]::Exists((Join-Path $r.Path 'Alpha.xml')) | Should -BeTrue
        [System.IO.File]::Exists((Join-Path $r.Path 'Sub [1]\Beta.xml')) | Should -BeTrue
    }
    It 'the AutoSync backup copy into a bracketed folder keeps every file' {
        $profiles = New-BracketProfiles -Name 'AutoSyncSource'
        $target = Join-Path $script:BrGame 'AutoSyncCopy [2]'
        [void][System.IO.Directory]::CreateDirectory($target)
        (Copy-TpmAutoSyncUserProfilesBackup -UserProfilesDir $profiles -BackupPath $target).Succeeded | Should -BeTrue
        [System.IO.File]::Exists((Join-Path $target 'Alpha.xml')) | Should -BeTrue
        [System.IO.File]::Exists((Join-Path $target 'Sub [1]\Beta.xml')) | Should -BeTrue
    }
    It 'restoring a snapshot into a bracketed profiles folder replaces the live files with the saved ones' {
        $live = New-BracketProfiles -Name 'RestoreLive'
        $snap = Join-Path $script:BrGame 'RestoreSnap [3]'
        [void][System.IO.Directory]::CreateDirectory($snap)
        [System.IO.File]::WriteAllText((Join-Path $snap 'Saved.xml'), '<GameProfile />')
        Restore-TpmLegacyUserProfilesSnapshot -UserProfilesDir $live -RollbackDir $snap
        [System.IO.File]::Exists((Join-Path $live 'Saved.xml')) | Should -BeTrue
        [System.IO.File]::Exists((Join-Path $live 'Alpha.xml')) | Should -BeFalse
    }
}
