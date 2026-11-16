#Requires -Module Pester

# PostgreSQL rebuild from a game's own starting file (no extension), the reason and leftover folder a rebuild keeps, the lock that stops two
# windows rebuilding at once, and the plain-words probe and saved-password helpers. Only function definitions of the production script are
# dot-sourced; the PostgreSQL 8.3 tools, lock, log and screen are in-memory fakes; every file lives under TestDrive.
# The FAT / FAT32 / exFAT branch of Test-TpmVolumeHasNoFilePermissions is driven through its optional -VolumeFormat parameter.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The rebuild tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-rebuild-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    # The script variables these tests set are put back when the file ends.
    $script:RbPrior = @{}
    foreach ($name in @('postgresSuperPasswordEncrypted', 'PostgresServiceName', 'PostgresBinDir')) {
        $variable = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:RbPrior[$name] = [pscustomobject]@{ Exists = ($null -ne $variable); Value = $(if ($null -ne $variable) { $variable.Value } else { $null }) }
    }

    # A game whose only starting file has no extension and sits in a dated pg_backup folder, plus its profile.
    function New-RbFixture {
        $root = Join-Path $TestDrive ('rb-' + [guid]::NewGuid().ToString('N'))
        $fx = [pscustomobject]@{ Root = $root; Bin = (Join-Path $root 'bin'); Evidence = (Join-Path $root 'evidence'); Profiles = (Join-Path $root 'UserProfiles'); Dated = (Join-Path $root 'Game\pg_backup\2026-11-01'); BackupFile = '' }
        New-Item -ItemType Directory -Path $fx.Bin, $fx.Evidence, $fx.Profiles, $fx.Dated -Force | Out-Null
        foreach ($tool in @(Get-Postgres83RestoreToolNames)) { New-Item -ItemType File -Path (Join-Path $fx.Bin $tool) -Force | Out-Null }
        $fx.BackupFile = Join-Path $fx.Dated '1840-postgresql_database-GameDBSSB-backup'
        [System.IO.File]::WriteAllText($fx.BackupFile, 'bundled')
        $exe = Join-Path $root 'Game\game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        $fields = ($(foreach ($f in @(@('Path', ''), @('Address', ''), @('Port', ''), @('DbName', 'GameDBSSB'), @('User', ''), @('Pass', ''))) { '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $f[0] + '</FieldName><FieldValue>' + $f[1] + '</FieldValue></FieldInformation>' }) -join '')
        $xml = '<GameProfile><GameName>SSB Game</GameName><GamePath>' + $exe + '</GamePath><ConfigValues>' + $fields + '</ConfigValues></GameProfile>'
        [System.IO.File]::WriteAllText((Join-Path $fx.Profiles 'SsbGame.xml'), $xml, (New-Object System.Text.UTF8Encoding $false))
        return $fx
    }

    # Every PostgreSQL 8.3 tool succeeds; createdb makes the database exist. Calls are recorded for the asserts.
    function Invoke-RbFake {
        param([string]$ToolName, [string[]]$Arguments)
        $db = if ($ToolName -eq 'pg_restore.exe' -and $Arguments -notcontains '--list') { [string]$Arguments[-2] } else { [string]$Arguments[-1] }
        [void]$script:RbCalls.Add([pscustomobject]@{ Tool = $ToolName; Database = $db; Arguments = @($Arguments) })
        if ($ToolName -eq 'createdb.exe') { $script:RbExists[$db] = $true }
        $text = if ($Arguments -contains '--version') { $ToolName + ' (PostgreSQL) 8.3.23' } else { '' }
        return [pscustomobject]@{ Tool = $ToolName; Executable = (Join-Path $script:PostgresBinDir $ToolName); Arguments = @($Arguments); ExitCode = 0; Succeeded = $true; Output = $text }
    }

    function Install-RbMocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:RbExists = @{}
        $script:RbCalls = New-Object System.Collections.Generic.List[object]
        $script:RbLog = New-Object System.Collections.Generic.List[string]
        $script:RbScreen = New-Object System.Collections.Generic.List[string]
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log { [void]$script:RbLog.Add([string]$msg) }
        Mock Write-Host { [void]$script:RbScreen.Add(((@($Object) | ForEach-Object { [string]$_ }) -join ' ')) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Enter-PostgresRecoveryLock { $true }
        Mock Exit-PostgresRecoveryLock {}
        Mock Test-PostgresPassword { $true }
        Mock Lock-PostgresRecoveryDirectory {}
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            Add-FakePostgresInterpretation -Command (Invoke-RbFake -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            [pscustomobject]@{ Exists = [bool]$script:RbExists[$DbName]; Verified = $true }
        }
    }

    # The plan the guided rebuild would show for the fixture game (real profile scan), then the real aggregate run.
    function Invoke-RbPlan {
        param([Parameter(Mandatory)]$Fixture)
        $json = ConvertTo-PostgresReinitializePlanJson -Plans @(Get-PostgresReinitializePlansFromProfiles -UserProfilesDir $Fixture.Profiles)
        return (Invoke-PostgresReinitializePlan -PlanJson $json -PlanHash (Get-PostgresReinitializePlanHash -PlanJson $json) -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password' -RecoveryBackup ([pscustomobject]@{ Path = $Fixture.Evidence; Verified = $true }))
    }
}

AfterAll {
    foreach ($name in @($script:RbPrior.Keys)) {
        $prior = $script:RbPrior[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        else { Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue }
    }
}

Describe 'A starting file with no extension is accepted only when the rebuild names the database' {
    It 'accepts the no-extension file when the item names the database' {
        # Who gets hurt: a user whose game ships its starting database as a file with no extension; the rebuild would refuse it and the game stays broken.
        # Mutation: drop the "caller names the database" allowance for an empty extension in Get-PostgresRestoreBackupPlan -> Valid is false.
        $fx = New-RbFixture
        $plan = Get-PostgresRestoreBackupPlan -BackupFiles @([pscustomobject]@{ BackupFile = $fx.BackupFile; Database = 'GameDBSSB' }) -SelectedBackupRoot $fx.Dated
        $plan.Valid | Should -BeTrue
        @($plan.Items).Count | Should -Be 1
        $plan.Items[0].Database | Should -BeExactly 'GameDBSSB'
        [System.IO.Path]::GetFileName($plan.Items[0].BackupFile) | Should -BeExactly '1840-postgresql_database-GameDBSSB-backup'
    }

    It 'still refuses <Case> with the unexpected file type reason' -TestCases @(
        @{ Case = 'a no-extension file without a database name'; FileName = '1840-postgresql_database-GameDBSSB-backup'; Database = $null }
        @{ Case = 'a .txt file even with a database name'; FileName = 'x.txt'; Database = 'GameDBSSB' }
    ) {
        param($Case, $FileName, $Database)
        # Who gets hurt: a user who restores from a folder that holds notes or unnamed files; a wrong file would replace their data.
        # Mutation: accept any extension (or an empty one without Database) in Get-PostgresRestoreBackupPlan -> Valid is true.
        $fx = New-RbFixture
        $file = Join-Path $fx.Dated $FileName
        if (-not (Test-Path -LiteralPath $file)) { [System.IO.File]::WriteAllText($file, 'x') }
        $item = [pscustomobject]@{ BackupFile = $file }
        if ($Database) { $item | Add-Member -NotePropertyName Database -NotePropertyValue $Database }
        $plan = Get-PostgresRestoreBackupPlan -BackupFiles @($item) -SelectedBackupRoot $fx.Dated
        $plan.Valid | Should -BeFalse
        $plan.Reason | Should -BeExactly 'A selected PostgreSQL backup file had an unexpected file type.'
    }
}

Describe 'A rebuild keeps its reason, its leftover folder and its lock' {
    It 'rebuilds a game from its no-extension file, and a temporary folder that cannot be removed leaves a finished rebuild with a leftover note' {
        # Who gets hurt: a user whose rebuild worked but is told to ask for help because a temporary folder stayed behind (real transaction, aggregate and success screen).
        # Mutation: drop the CLEANUP_RESIDUE + SUCCEEDED handling in Invoke-PostgresReinitializePlan -> Outcome is ACTION_REQUIRED and the summary says the data could not be checked.
        $fx = New-RbFixture
        Install-RbMocks -Fixture $fx
        Mock Remove-Item {
            param([string]$LiteralPath)
            if ($LiteralPath -like '*\Restore-*') { throw 'forced evidence cleanup failure' }
            [System.IO.Directory]::Delete($LiteralPath, $true)
        }
        $result = Invoke-RbPlan -Fixture $fx
        $result.Outcome | Should -BeExactly 'CLEANUP_RESIDUE'
        $result.UnderlyingOutcome | Should -BeExactly 'SUCCEEDED'
        $result.Summary | Should -Match 'completed and was verified'
        $result.Summary | Should -Not -Match 'could not check that your data is back'
        @($result.Cleanup.ResiduePaths).Count | Should -Be 1
        $leftover = [string]$result.Cleanup.ResiduePaths[0]
        $leftover.StartsWith($fx.Evidence, [System.StringComparison]::OrdinalIgnoreCase) | Should -BeTrue
        Test-Path -LiteralPath $leftover -PathType Container | Should -BeTrue
        @($script:RbCalls | Where-Object { $_.Tool -eq 'createdb.exe' -and $_.Arguments -notcontains '--version' } | ForEach-Object { $_.Database }) | Should -Be @('GameDBSSB')
        @($script:RbCalls | Where-Object { $_.Tool -eq 'pg_restore.exe' -and $_.Arguments -notcontains '--list' -and [string]$_.Arguments[-1] -like '*1840-postgresql_database-GameDBSSB-backup' }).Count | Should -Be 1
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        Write-PostgresReinitializeSuccess -Result $result
        $screen = $script:RbScreen -join "`n"
        $screen | Should -Match 'PostgreSQL data was rebuilt and checked'
        $screen | Should -Match 'could not remove a temporary folder it made'
        $screen | Should -Not -Match 'did not finish'
        ($script:RbLog -join "`n") | Should -Match ([regex]::Escape($leftover))
    }

    It 'keeps the reason a database stopped in the aggregate result and in the log' {
        # Who gets hurt: a user (or the person helping them) who is told "the rebuild did not start" with no reason anywhere.
        # Mutation: stop passing $nestedErrors into the failure result of Invoke-PostgresReinitializePlan -> Errors is empty and the log has no "reason:" line.
        $fx = New-RbFixture
        Install-RbMocks -Fixture $fx
        Mock Reset-PostgresDatabaseFromBackup {
            New-TpmProfileTransactionResult -WorkflowKey 'PostgresRestore' -OperationKey 'ReinitializeDatabase' -Outcome 'FAILED_BEFORE_MUTATION' -ProductState 'UNCHANGED' -Summary 'The rebuild did not start.' -Items @('GameDBSSB') -FailedItems @('GameDBSSB') -ReasonCode 'PREFLIGHT_FAILED' -Errors @('some reason')
        }
        $result = Invoke-RbPlan -Fixture $fx
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        @($result.Errors) | Should -Contain 'some reason'
        Write-PostgresReinitializeFailure -Result $result
        ($script:RbLog -join "`n") | Should -Match 'reason: some reason'
    }

    It 'does not start, and never touches a database, while another window holds the PostgreSQL lock' {
        # Who gets hurt: a user with two TeknoParrot Manager windows open; two rebuilds changing PostgreSQL at once could leave a database half built.
        # Mutation: remove the Enter-PostgresRecoveryLock check in Invoke-PostgresReinitializePlan -> the nested reset runs (and Exit is called without a lock).
        $fx = New-RbFixture
        Install-RbMocks -Fixture $fx
        Mock Enter-PostgresRecoveryLock { $false }
        Mock Reset-PostgresDatabaseFromBackup { throw 'a rebuild must not run while the lock is held elsewhere' }
        $result = Invoke-RbPlan -Fixture $fx
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'POSTGRES_BUSY'
        $result.Summary | Should -Match 'another TeknoParrot Manager window is changing PostgreSQL'
        Should -Invoke Reset-PostgresDatabaseFromBackup -Times 0 -Exactly
        Should -Invoke Exit-PostgresRecoveryLock -Times 0 -Exactly
        $script:RbCalls.Count | Should -Be 0
    }
}

Describe 'Plain-words probe sentences and the saved-password check' {
    It 'explains a probe that did not sign in as <Case>' -TestCases @(
        @{ Case = 'a rejected password'; Reason = 'PasswordRejected'; Status = ''; Expected = 'PostgreSQL is running and it rejected the password.' }
        @{ Case = 'a stopped service'; Reason = 'ServiceNotRunning'; Status = 'Stopped'; Expected = "PostgreSQL is not running right now (the Windows service 'pgsql-8.3' is Stopped). TeknoParrot Manager cannot check any password until it runs." }
        @{ Case = 'a service that was not found'; Reason = 'ServiceNotRunning'; Status = ''; Expected = "PostgreSQL is not running right now (the Windows service 'pgsql-8.3' was not found). TeknoParrot Manager cannot check any password until it runs." }
        @{ Case = 'a missing psql.exe'; Reason = 'ClientMissing'; Status = ''; Expected = 'The PostgreSQL program psql.exe was not found, so TeknoParrot Manager cannot check the password.' }
        @{ Case = 'a failed check'; Reason = 'ProbeError'; Status = ''; Expected = 'TeknoParrot Manager could not run the password check on this PC.' }
        @{ Case = 'an unknown reason'; Reason = 'SomethingElse'; Status = ''; Expected = 'PostgreSQL did not accept the connection, and TeknoParrot Manager could not tell whether the password was the reason. This does not mean the password is wrong.' }
    ) {
        param($Case, $Reason, $Status, $Expected)
        # Who gets hurt: a user told the password is wrong when PostgreSQL is simply stopped, or the reverse.
        # Mutation: return the "password rejected" sentence for every reason -> five of these cases fail.
        $script:PostgresServiceName = 'pgsql-8.3'
        Get-PostgresProbeExplanation -Probe ([pscustomobject]@{ Reason = $Reason; ServiceStatus = $Status }) | Should -BeExactly $Expected
    }

    It 'reports a changed saved password only when the settings file holds a different one (<Case>)' -TestCases @(
        @{ Case = 'nothing saved on disk'; OnDisk = $null; Current = 'old'; Changed = $false; Kept = 'old' }
        @{ Case = 'the same value'; OnDisk = 'same'; Current = 'same'; Changed = $false; Kept = 'same' }
        @{ Case = 'a different value'; OnDisk = 'new'; Current = 'old'; Changed = $true; Kept = 'new' }
    ) {
        param($Case, $OnDisk, $Current, $Changed, $Kept)
        # Who gets hurt: a user whose elevated step saved a new password; a stale value in memory would later be written back over it.
        # Mutation: return $true whenever the disk value is non-blank (or clear the value when the disk has none) -> the first two cases fail.
        $script:RbOnDisk = $OnDisk
        Mock Get-PostgresSavedCredentialFromConfig { $script:RbOnDisk }
        $script:postgresSuperPasswordEncrypted = $Current
        Sync-PostgresSavedCredentialFromConfig | Should -Be $Changed
        $script:postgresSuperPasswordEncrypted | Should -BeExactly $Kept
    }

    It 'does not treat a network share as a drive without file permissions' {
        # Who gets hurt: a user whose TeknoParrot folder is on a share; if a share counted as "no file permissions", the owner-only check would be skipped and private PostgreSQL files left readable.
        # Mutation: return $true for a path whose root starts with two backslashes (or from the catch) in Test-TpmVolumeHasNoFilePermissions -> this fails.
        Test-TpmVolumeHasNoFilePermissions -Path '\\fixture-server\share\TeknoParrot' | Should -BeFalse
    }

    It 'treats a <Format> drive as keeping no file permissions, and an NTFS drive as keeping them' -TestCases @(
        @{ Format = 'FAT'; Expected = $true }
        @{ Format = 'FAT32'; Expected = $true }
        @{ Format = 'exFAT'; Expected = $true }
        @{ Format = 'NTFS'; Expected = $false }
    ) {
        # Who gets hurt: a user whose TeknoParrot folder is on a FAT or exFAT drive; start-up would stop on an owner-only check that drive can never pass.
        # Mutation: remove 'exFAT' from the list in Test-TpmVolumeHasNoFilePermissions -> the exFAT row fails; add 'NTFS' -> the NTFS row fails.
        Test-TpmVolumeHasNoFilePermissions -Path 'C:\fixture\TeknoParrot' -VolumeFormat $Format | Should -Be $Expected
    }
}
