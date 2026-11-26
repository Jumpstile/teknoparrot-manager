param([string]$RepositoryRoot = [IO.Path]::GetDirectoryName($PSScriptRoot))

BeforeAll {
    $script:MigrationProbeEvidence=[string]$TestDrive
    $script:MigrationSource=Join-Path $RepositoryRoot 'TeknoParrot-Manager.ps1'
    $errors=$null
    $script:MigrationAst=[Management.Automation.Language.Parser]::ParseFile($script:MigrationSource,[ref]$null,[ref]$errors)
    if($errors.Count){throw 'Source parse failed.'}
    foreach($function in @($script:MigrationAst.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.FunctionDefinitionAst]})){
        . ([scriptblock]::Create($function.Extent.Text))
    }
    function Write-TpmCompactExtractionProgress {param($Phase,$Label,$Current,$Total,$StartedAt,[switch]$Complete)}
    function Write-Log {param([string]$msg)}
    function New-OverridesMigrationFixture {
        param([switch]$WithLog)
        $root=Join-Path $script:MigrationProbeEvidence ('pester-'+[guid]::NewGuid().ToString('N'))
        if(-not (Test-TpmNoReparsePath $root)){throw 'Fixture path is unsafe.'}
        $program=Join-Path $root 'program'
        $tp=Join-Path $root 'TeknoParrot'
        [void][IO.Directory]::CreateDirectory($program)
        [void][IO.Directory]::CreateDirectory($tp)
        $layout=Initialize-TpmOwnedLayout -Layout (Get-TpmOwnedLayout -TeknoParrotRoot $tp)
        foreach($path in @($program,$tp,$layout.Root,$layout.Backups,$layout.Reports)){
            if(-not ([IO.Path]::GetFullPath($path).StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)) -or -not (Test-TpmNoReparsePath $path)){throw 'Fixture containment failed.'}
        }
        $overrides=Join-Path $program 'TeknoParrot-Manager.overrides.json'
        [IO.File]::WriteAllText($overrides,'{"onlySync":["OWNER_CUSTOM_SENTINEL"],"noSync":[],"subFolderMap":{"ProbeGame":"ProbeFolder"},"datFile":""}',(New-Object Text.UTF8Encoding($false)))
        if($WithLog){[IO.File]::WriteAllText((Join-Path $program 'TeknoParrot-Manager.log'),'fixture migration log',(New-Object Text.UTF8Encoding($false)))}
        [pscustomobject]@{Root=$root;Program=$program;Layout=$layout;Overrides=$overrides;Sha256=(Get-FileHash -LiteralPath $overrides).Hash}
    }
    function Read-ActualStartupOverridesFixture {
        param([Parameter(Mandatory)]$Fixture)
        $fixtureScriptRoot=$Fixture.Program
        $statements=@($script:MigrationAst.EndBlock.Statements)
        $start=-1;$end=-1
        for($i=0;$i -lt $statements.Count;$i++){
            if($statements[$i] -is [Management.Automation.Language.AssignmentStatementAst] -and $statements[$i].Left.Extent.Text -ceq '$overridesPath'){$start=$i;break}
        }
        for($i=$start;$i -lt $statements.Count;$i++){
            if($statements[$i] -is [Management.Automation.Language.IfStatementAst] -and $statements[$i].Extent.Text.StartsWith('if (Test-Path -LiteralPath $overridesPath)')){$end=$i;break}
        }
        if($start -lt 0 -or $end -lt $start){throw 'Startup fragment not found.'}
        $snippet=(($statements[$start..$end]|ForEach-Object {$_.Extent.Text}) -join "`n").Replace('$PSScriptRoot','$fixtureScriptRoot')
        if($snippet -match 'Start-Process|Invoke-WebRequest|Invoke-RestMethod|Remove-Item|Move-Item|Copy-Item'){throw 'Unexpected operation in startup fragment.'}
        . ([scriptblock]::Create($snippet))
        return [pscustomobject]@{OnlySync=@($onlySyncList);SubFolderMap=$subFolderMap;Path=$overridesPath}
    }
    function Get-ActualConsumerDefaultFixture {
        param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Layout)
        $fixtureScriptRoot=$Root
        if($Name -in @('PostgresBackups','PostgresRecoveryBackups')){
            $priorLayout=Get-Variable -Name TpmOwnedLayout -Scope Script -ErrorAction SilentlyContinue
            try {
                $script:TpmOwnedLayout=$Layout
                $rootFunction=$script:MigrationAst.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-TpmOwnedBackupsRoot'},$true)
                if(-not $rootFunction){throw 'Owned backup root helper was not found.'}
                . ([scriptblock]::Create($rootFunction.Extent.Text.Replace('$PSScriptRoot','$fixtureScriptRoot')))
                if($Name -eq 'PostgresBackups'){
                    return (Join-Path (Get-TpmOwnedBackupsRoot -BackupName 'PostgresBackups') 'PostgresBackups')
                }
                $recoveryFunction=$script:MigrationAst.Find({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-PostgresRecoveryBackupRoot'},$true)
                if(-not $recoveryFunction){throw 'PostgreSQL recovery backup root helper was not found.'}
                . ([scriptblock]::Create($recoveryFunction.Extent.Text.Replace('$PSScriptRoot','$fixtureScriptRoot')))
                return (Get-PostgresRecoveryBackupRoot)
            } finally {
                if($priorLayout){Set-Variable -Name TpmOwnedLayout -Value $priorLayout.Value -Scope Script}
                else {Remove-Variable -Name TpmOwnedLayout -Scope Script -ErrorAction SilentlyContinue}
            }
        }
        if($Name -eq 'BepInExCache'){
            $assignment=@($script:MigrationAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$bepInExCacheDir'},$true))
            if($assignment.Count -ne 1){throw 'Actual BepInEx cache assignment was not unique.'}
            . ([scriptblock]::Create($assignment[0].Extent.Text.Replace('$PSScriptRoot','$fixtureScriptRoot')))
            return $bepInExCacheDir
        }
        throw 'Unrecognized active consumer fixture.'
    }
}

Describe 'Owner 34 active overrides survive owned-state migration' {
    It 'keeps custom filters and folder overrides available to actual startup after accepted migration' {
        $f=New-OverridesMigrationFixture -WithLog
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout -Unattended
        $migration.Outcome | Should -BeExactly 'SUCCEEDED'
        $migration.Backup.Verified | Should -BeTrue
        $loaded=Read-ActualStartupOverridesFixture -Fixture $f
        $loaded.OnlySync | Should -Contain 'OWNER_CUSTOM_SENTINEL'
        $loaded.SubFolderMap['ProbeGame'] | Should -BeExactly 'ProbeFolder'
        (Get-FileHash -LiteralPath $f.Overrides).Hash | Should -BeExactly $f.Sha256
        Test-Path -LiteralPath (Join-Path $f.Layout.Reports 'TeknoParrot-Manager.overrides.json') | Should -BeFalse
        [IO.File]::ReadAllText((Join-Path $f.Layout.Logs 'TeknoParrot-Manager.log')) | Should -BeExactly 'fixture migration log'
    }

    It 'treats an overrides-only legacy folder as no migration work and preserves its bytes' {
        $f=New-OverridesMigrationFixture
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout -Unattended
        $migration.Outcome | Should -BeExactly 'NO_OP'
        $migration.ReasonCode | Should -BeExactly 'NO_LEGACY_STATE'
        (Get-FileHash -LiteralPath $f.Overrides).Hash | Should -BeExactly $f.Sha256
        @($migration.Mutation.ChangedItems).Count | Should -Be 0
    }

    It 'preserves active overrides and all other source state when migration is declined' {
        $f=New-OverridesMigrationFixture -WithLog
        # A log alone is migrated silently (no question); a legacy controls file is real work that needs the user's consent.
        [IO.File]::WriteAllText((Join-Path $f.Program 'TeknoParrot-Manager-controls.txt'),'legacy controls',(New-Object Text.UTF8Encoding($false)))
        Mock Read-TpmYesNo {'N'}
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'NO_OP'
        $migration.ReasonCode | Should -BeExactly 'DECLINED'
        (Get-FileHash -LiteralPath $f.Overrides).Hash | Should -BeExactly $f.Sha256
        Test-Path -LiteralPath (Join-Path $f.Program 'TeknoParrot-Manager.log') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $f.Program 'TeknoParrot-Manager-controls.txt') | Should -BeTrue
    }

    It 'preserves active overrides when another managed destination is occupied' {
        $f=New-OverridesMigrationFixture -WithLog
        # The log is not the occupied item: a script-folder log whose managed log already exists is merged at startup instead.
        New-Item -ItemType Directory -Path (Join-Path $f.Program 'ReShadePresets'),(Join-Path $f.Layout.Assets 'ReShadePresets') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $f.Program 'ReShadePresets\a.ini'),'legacy controls',(New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $f.Layout.Assets 'ReShadePresets\a.ini'),'occupied destination',(New-Object Text.UTF8Encoding($false)))
        Mock Read-TpmYesNo {'Y'}
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $migration.ReasonCode | Should -BeExactly 'DESTINATION_OCCUPIED'
        (Get-FileHash -LiteralPath $f.Overrides).Hash | Should -BeExactly $f.Sha256
        [IO.File]::ReadAllText((Join-Path $f.Layout.Assets 'ReShadePresets\a.ini')) | Should -BeExactly 'occupied destination'
        [IO.File]::ReadAllText((Join-Path $f.Program 'ReShadePresets\a.ini')) | Should -BeExactly 'legacy controls'
        [IO.File]::ReadAllText((Join-Path $f.Program 'TeknoParrot-Manager.log')) | Should -BeExactly 'fixture migration log'
        Test-Path -LiteralPath (Join-Path $f.Layout.Logs 'TeknoParrot-Manager.log') | Should -BeFalse
    }

    It 'an unattended run does not move the user folders and does not ask' {
        $f=New-OverridesMigrationFixture -WithLog
        [IO.File]::WriteAllText((Join-Path $f.Program 'TeknoParrot-Manager-controls.txt'),'legacy controls',(New-Object Text.UTF8Encoding($false)))
        Mock Read-TpmYesNo {'Y'}
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout -Unattended
        $migration.Outcome | Should -BeExactly 'NO_OP'
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
        [IO.File]::ReadAllText((Join-Path $f.Program 'TeknoParrot-Manager-controls.txt')) | Should -BeExactly 'legacy controls'
        Test-Path -LiteralPath (Join-Path $f.Program 'TeknoParrot-Manager.log') | Should -BeTrue
    }

    It 'keeps settings in the script folder after a declined tidy-up so the next start still runs' {
        $f=New-OverridesMigrationFixture
        $legacyConfig=Join-Path $f.Program 'TeknoParrot-Manager.config.json'
        [IO.File]::WriteAllText($legacyConfig,'{"TeknoParrotRoot":"x"}',(New-Object Text.UTF8Encoding($false)))
        Mock Read-TpmYesNo {'N'}
        $first=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $first.ReasonCode | Should -BeExactly 'DECLINED'
        $path=Get-TpmConfigPathAfterMigration -CurrentPath $legacyConfig -ScriptRoot $f.Program -Layout $f.Layout
        $path | Should -BeExactly $legacyConfig
        [IO.File]::WriteAllText($path,'{"TeknoParrotRoot":"y"}',(New-Object Text.UTF8Encoding($false)))
        Test-Path -LiteralPath $f.Layout.ConfigPath | Should -BeFalse
        $second=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $second.ReasonCode | Should -BeExactly 'DECLINED'
        Test-TpmOwnedMigrationStartupAllowed -MigrationResult $second | Should -BeTrue
    }

    It 'uses the managed settings file once the settings were moved' {
        $f=New-OverridesMigrationFixture
        $legacyConfig=Join-Path $f.Program 'TeknoParrot-Manager.config.json'
        [IO.File]::WriteAllText($legacyConfig,'{"TeknoParrotRoot":"x"}',(New-Object Text.UTF8Encoding($false)))
        Mock Read-TpmYesNo {'Y'}
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-TpmConfigPathAfterMigration -CurrentPath $legacyConfig -ScriptRoot $f.Program -Layout $f.Layout | Should -BeExactly $f.Layout.ConfigPath
    }

    It 'aborts before any move when a managed-state safety backup fails, preserves overrides, and does not stop the next start' {
        $f=New-OverridesMigrationFixture -WithLog
        Mock Copy-Item {throw 'controlled fixture backup failure'}
        Mock Read-TpmYesNo {'Y'}
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $migration.ReasonCode | Should -BeExactly 'BACKUP_FAILED'
        $migration.Cleanup.ResiduePresent | Should -BeTrue
        $migration.Backup.Verified | Should -BeFalse
        Test-TpmOwnedMigrationStartupAllowed -MigrationResult $migration | Should -BeTrue
        (Get-FileHash -LiteralPath $f.Overrides).Hash | Should -BeExactly $f.Sha256
        Test-Path -LiteralPath (Join-Path $f.Program 'TeknoParrot-Manager.log') | Should -BeTrue
    }

    It 'moves a program-folder dgVoodoo2Presets folder to the managed Assets folder where dgVoodoo2 setup reads it' {
        $f=New-OverridesMigrationFixture
        $presets=Join-Path $f.Program 'dgVoodoo2Presets'
        [void][IO.Directory]::CreateDirectory($presets)
        [IO.File]::WriteAllText((Join-Path $presets 'VF5.conf'),'per-game conf',(New-Object Text.UTF8Encoding($false)))
        Mock Read-TpmYesNo {'Y'}
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'SUCCEEDED'
        [IO.File]::ReadAllText((Join-Path $f.Layout.Assets 'dgVoodoo2Presets\VF5.conf')) | Should -BeExactly 'per-game conf'
        Test-Path -LiteralPath $presets | Should -BeFalse
    }

    It 'keeps <Name> bytes discoverable at the current consumer default after migration' -ForEach @(
        @{Name='PostgresBackups'},@{Name='BepInExCache'}
    ) {
        $f=New-OverridesMigrationFixture -WithLog
        $legacy=Join-Path $f.Program $Name
        [void][IO.Directory]::CreateDirectory($legacy)
        $file=Join-Path $legacy 'owner-sentinel.bin'
        [IO.File]::WriteAllBytes($file,[byte[]](0,1,127,128,254,255))
        $before=(Get-FileHash -LiteralPath $file).Hash
        $consumer=Get-ActualConsumerDefaultFixture -Name $Name -Root $f.Program -Layout $f.Layout
        $consumer | Should -BeExactly $legacy
        Test-Path -LiteralPath (Join-Path $consumer 'owner-sentinel.bin') | Should -BeTrue
        Mock Read-TpmYesNo {'Y'}
        $migration=Invoke-TpmOwnedMigration -ScriptRoot $f.Program -Layout $f.Layout
        $migration.Outcome | Should -BeExactly 'SUCCEEDED'
        $migration.Backup.Verified | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $consumer 'owner-sentinel.bin') | Should -BeTrue
        (Get-FileHash -LiteralPath (Join-Path $consumer 'owner-sentinel.bin')).Hash | Should -BeExactly $before
        $bucket=if($Name -eq 'BepInExCache'){'Cache'}else{'Backups'}
        Test-Path -LiteralPath (Join-Path $f.Layout.$bucket $Name) | Should -BeFalse
    }
    It 'keeps LaunchBox backup history outside the owned-state migration inventory' {
        $f=New-OverridesMigrationFixture
        $legacy=Join-Path $f.Program 'LaunchBoxBackups'
        [void][IO.Directory]::CreateDirectory($legacy)
        [IO.File]::WriteAllBytes((Join-Path $legacy 'owner-sentinel.bin'),[byte[]](0,1,127,128,254,255))
        $items=@(Get-TpmLegacyOwnedItems -ScriptRoot $f.Program)
        $items.Name | Should -Not -Contain 'LaunchBoxBackups'
        [IO.File]::ReadAllBytes((Join-Path $legacy 'owner-sentinel.bin')) | Should -Be ([byte[]](0,1,127,128,254,255))
    }
}
