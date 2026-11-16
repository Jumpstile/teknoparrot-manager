#Requires -Module Pester
# FIX60: runtime tests for #371 (outer PostgreSQL cleanup must not start the service while an
# unfinished trust-rule repair may be in place) and #338 (migrated PostgreSQL backups appear in the
# default restore discovery). Every fixture lives under $TestDrive; services, native PostgreSQL
# commands and prompts are mocked. Nothing touches a real PostgreSQL install, service or user data.
#
# #371 note: the option-12 cleanup is top-level script code inside the main menu loop, so it cannot
# be called as a function. These tests execute the REAL production functions
# (Restore-PostgresServiceState and the trust-rule marker helpers) and the REAL production `finally`
# block of the option-12 try statement, which is cut out of the parsed source (never re-typed here)
# and run inside a small harness. Since FIX95 (B1) TeknoParrot Manager no longer writes the trust
# rule; the marker these tests create stands in for one left behind by an older build.

BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }

    # The extracted functions live in a throwaway "program folder" so that $PSScriptRoot inside them
    # (the legacy backup-root location) is a folder owned by this test file.
    $script:Fix60ProgramDir = Join-Path $TestDrive 'fix60-program'
    [void][System.IO.Directory]::CreateDirectory($script:Fix60ProgramDir)
    $functionAsts = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionsPath = Join-Path $script:Fix60ProgramDir 'fix60-functions.ps1'
    ($functionAsts | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionsPath -Encoding UTF8
    $progressDir = Join-Path $script:Fix60ProgramDir 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressDir)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressDir 'TpmProgress.psm1') -Force
    . $functionsPath
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    # The one option-12 try statement whose finally restores the original PostgreSQL service state.
    $outer = @($ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.TryStatementAst] -and $null -ne $n.Finally -and
        @($n.Finally.FindAll({ param($c)
            $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'Restore-PostgresServiceState' -and
            $c.Extent.Text -eq 'Restore-PostgresServiceState -WasRunning $postgresServiceWasRunning'
        }, $true)).Count -gt 0
    }, $true))
    if ($outer.Count -ne 1) { throw 'Expected one option-12 try/finally that restores the original PostgreSQL service state.' }
    $script:Fix60OuterTry = $outer[0]

    # Wraps the production finally statements (verbatim, taken from the AST) so they run with the
    # variables the surrounding menu loop would have set. $Body stands in for the try body.
    function New-Fix60OuterCleanupHarness {
        $statements = (@($script:Fix60OuterTry.Finally.Statements | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine)
        $template = @'
param([object]$postgresServiceWasRunning, [scriptblock]$Body)
$postgresServiceRestoreFailed = $false
$outPw = $null
$postgresStatus = [pscustomobject]@{ Fix60 = $true }
$isPostgresRecoveryResume = $false
$postgresSetupBodyDone = $false
try {
    & $Body
} finally {
__STATEMENTS__
    $script:Fix60RestoreFailedObserved = $postgresServiceRestoreFailed
}
'@
        return [scriptblock]::Create($template.Replace('__STATEMENTS__', $statements))
    }
    function Invoke-Fix60OuterCleanup {
        param([object]$WasRunning, [scriptblock]$Body = {})
        $script:Fix60RestoreFailedObserved = $null
        $harness = New-Fix60OuterCleanupHarness
        & $harness -postgresServiceWasRunning $WasRunning -Body $Body
    }
    # Writes the trust-rule marker an older build's interrupted reset left behind (same JSON and ACL
    # steps as that build's writer, which FIX95 removed from the product).
    function Write-Fix60LegacyTrustRuleMarker {
        param([string]$HbaPath, [string]$BackupHbaPath, [string]$OriginalSha256, [string]$TrustSha256)
        $markerPath = Get-PostgresTrustRuleMarkerPath
        $directory = [System.IO.Path]::GetDirectoryName($markerPath)
        [void][System.IO.Directory]::CreateDirectory($directory)
        Lock-PostgresRecoveryDirectory -Path $directory
        [System.IO.File]::WriteAllBytes($markerPath, [byte[]]@())
        Lock-PostgresRecoveryFile -Path $markerPath
        $marker = [pscustomobject]@{
            Schema = 'TPM.PostgresTrustRuleMarker.v1'
            Guid = [guid]::NewGuid().ToString()
            HbaPath = $HbaPath
            BackupHbaPath = $BackupHbaPath
            OriginalSha256 = $OriginalSha256.ToUpperInvariant()
            TrustSha256 = $TrustSha256.ToUpperInvariant()
            CreatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        }
        [System.IO.File]::WriteAllBytes($markerPath, (New-Object System.Text.UTF8Encoding $false).GetBytes(($marker | ConvertTo-Json)))
        return $markerPath
    }
    function Get-Fix60TreeHash {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return 'ABSENT' }
        return (@(Get-ChildItem -LiteralPath $Path -Recurse -File | Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($Path.Length) + ':' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }) -join '|')
    }
    function New-Fix60PgBackup {
        param([string]$ParentRoot, [string]$Name, [string[]]$Databases, [string]$Kind = 'PostgresBackups')
        $folder = Join-Path (Join-Path $ParentRoot $Kind) $Name
        [void][System.IO.Directory]::CreateDirectory($folder)
        foreach ($database in $Databases) {
            [System.IO.File]::WriteAllBytes((Join-Path $folder ($database + '.backup')), [System.Text.Encoding]::ASCII.GetBytes(('PGDMP synthetic {0} {1} {2}' -f $Kind, $Name, $database)))
        }
        return $folder
    }
}

Describe 'FIX60 #371 runtime: outer PostgreSQL cleanup restores the service state but never starts PostgreSQL over a trust-rule marker' -Tag 'FIX60' {
    BeforeEach {
        $script:TpmOwnedLayout = $null
        $pgRoot = Join-Path $TestDrive ('fix60-pg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:PostgresInstallDir = $pgRoot
        $script:PostgresBinDir = Join-Path $pgRoot 'bin'
        $script:PostgresServiceName = 'pgsql-fix60'
        $dataDir = Join-Path $pgRoot 'data'
        [void][System.IO.Directory]::CreateDirectory($dataDir)
        [void][System.IO.Directory]::CreateDirectory($script:PostgresBinDir)
        New-Item -ItemType File -Path (Join-Path $script:PostgresBinDir 'psql.exe') -Force | Out-Null
        $script:Fix60HbaPath = Join-Path $dataDir 'pg_hba.conf'
        Set-Content -LiteralPath $script:Fix60HbaPath -Value 'host all all 127.0.0.1/32 md5' -NoNewline
        $script:Fix60OriginalHash = (Get-FileHash -LiteralPath $script:Fix60HbaPath -Algorithm SHA256).Hash

        # Recovery evidence root = <program folder>\PostgresRecoveryBackups (layout is null, so the legacy root is used).
        $recoveryRoot = Join-Path $script:Fix60ProgramDir 'PostgresRecoveryBackups'
        if (Test-Path -LiteralPath $recoveryRoot) { Remove-Item -LiteralPath $recoveryRoot -Recurse -Force -ErrorAction Stop }
        $evidence = Join-Path $recoveryRoot 'evidence'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $evidence 'PostgreSQL'))
        $script:Fix60BackupHba = Join-Path $evidence 'PostgreSQL\pg_hba.conf'
        Copy-Item -LiteralPath $script:Fix60HbaPath -Destination $script:Fix60BackupHba
        Lock-PostgresRecoveryFile -Path $script:Fix60BackupHba
        Lock-PostgresRecoveryDirectory -Path $recoveryRoot

        $script:PostgresServiceStartRefusedByMarker = $false
        $script:PostgresTrustRuleMarkerState = $null

        $script:Fix60Status = 'Running'
        $script:Fix60Starts = 0
        $script:Fix60Stops = 0
        $script:Fix60StartFail = @()
        $script:Fix60StopFail = @()
        $script:Fix60RestoreFailedObserved = $null

        Mock Write-Log {}
        Mock Get-Service { [pscustomobject]@{ Status = $script:Fix60Status } }
        Mock Start-Service {
            $script:Fix60Starts++
            if (@($script:Fix60StartFail) -contains $script:Fix60Starts) { throw 'injected service start failure' }
            $script:Fix60Status = 'Running'
        }
        Mock Stop-Service {
            $script:Fix60Stops++
            if (@($script:Fix60StopFail) -contains $script:Fix60Stops) { throw 'injected service stop failure' }
            $script:Fix60Status = 'Stopped'
        }
        Mock Wait-PostgresServiceState {}
        Mock Resolve-TpmWorkflowFailure {}
        Mock Get-PostgresRecoveryActions { @() }
    }
    AfterEach {
        # A case may leave the trust-rule marker behind; later cases must start clean.
        $markerPath = Get-PostgresTrustRuleMarkerPath
        if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue }
    }

    It 'no marker: the real outer cleanup restarts a service that was running before exactly once' {
        # Mutation: deleting the Restore-PostgresServiceState call from the option-12 finally (or re-adding a latch clause that
        # blocks it) leaves the service Stopped and fails the Starts/Running assertions.
        $script:Fix60Status = 'Stopped'
        Invoke-Fix60OuterCleanup -WasRunning $true
        $script:Fix60Starts | Should -Be 1
        $script:Fix60Status | Should -BeExactly 'Running'
        $script:Fix60RestoreFailedObserved | Should -BeFalse
        $script:PostgresServiceStartRefusedByMarker | Should -BeFalse
    }

    It 'no marker: the real outer cleanup stops a service that was stopped before' {
        # Mutation: deleting the Restore-PostgresServiceState call from the option-12 finally leaves the service Running.
        $script:Fix60Status = 'Running'
        Invoke-Fix60OuterCleanup -WasRunning $false
        $script:Fix60Stops | Should -Be 1
        $script:Fix60Starts | Should -Be 0
        $script:Fix60Status | Should -BeExactly 'Stopped'
        $script:Fix60RestoreFailedObserved | Should -BeFalse
    }

    It 'the outer cleanup calls the service-state restore only when the original state was recorded' {
        # Mutation: dropping `$null -ne $postgresServiceWasRunning` from the finally condition calls the restore with no
        # recorded state (fails Times 0); dropping the call itself fails the Times 1 assertion.
        Mock Restore-PostgresServiceState { $true }
        Invoke-Fix60OuterCleanup -WasRunning $null
        Should -Invoke Restore-PostgresServiceState -Times 0 -Exactly
        $script:Fix60RestoreFailedObserved | Should -BeFalse
        Invoke-Fix60OuterCleanup -WasRunning $false
        Should -Invoke Restore-PostgresServiceState -Times 1 -Exactly -ParameterFilter { $WasRunning -is [bool] -and -not $WasRunning }
    }

    It 'no marker: the outer cleanup still reports a genuine restart failure' {
        # Mutation: a finally that swallows the restore result (or never records `$postgresServiceRestoreFailed = $true`)
        # fails the restore-failed assertion.
        $script:Fix60Status = 'Stopped'
        $script:Fix60StartFail = @(1)
        Invoke-Fix60OuterCleanup -WasRunning $true
        $script:Fix60Starts | Should -Be 1
        $script:Fix60Status | Should -BeExactly 'Stopped'
        $script:Fix60RestoreFailedObserved | Should -BeTrue
    }

    It 'older build trust-rule marker (live file <LiveState>): the outer cleanup refuses to start PostgreSQL and changes no recovery file' -TestCases @(
        @{ LiveState = 'Original' }
        @{ LiveState = 'TemporaryTrust' }
        @{ LiveState = 'Changed' }
    ) {
        param($LiveState)
        # Mutation: removing the marker start-gate from Restore-PostgresServiceState starts PostgreSQL (fails Starts/Status);
        # dropping -ReadOnly from the gate lets it clear the Original marker or restore the TemporaryTrust file and then start
        # (fails the Starts, marker and pg_hba.conf hash assertions).
        $trustText = 'host all postgres 127.0.0.1/32 trust' + "`r`n" + 'host all all 127.0.0.1/32 md5'
        $trustFile = Join-Path $TestDrive ('fix60-trust-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.conf')
        Set-Content -LiteralPath $trustFile -Value $trustText -NoNewline
        $trustHash = (Get-FileHash -LiteralPath $trustFile -Algorithm SHA256).Hash
        if ($LiveState -eq 'TemporaryTrust') { Set-Content -LiteralPath $script:Fix60HbaPath -Value $trustText -NoNewline }
        if ($LiveState -eq 'Changed') { Set-Content -LiteralPath $script:Fix60HbaPath -Value 'host all all 0.0.0.0/0 md5' -NoNewline }
        $markerPath = Write-Fix60LegacyTrustRuleMarker -HbaPath $script:Fix60HbaPath -BackupHbaPath $script:Fix60BackupHba -OriginalSha256 $script:Fix60OriginalHash -TrustSha256 $trustHash
        $markerHash = (Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash
        $hbaHash = (Get-FileHash -LiteralPath $script:Fix60HbaPath -Algorithm SHA256).Hash
        $script:Fix60Status = 'Stopped'
        Invoke-Fix60OuterCleanup -WasRunning $true
        $script:Fix60Starts | Should -Be 0
        $script:Fix60Status | Should -BeExactly 'Stopped'
        $script:Fix60RestoreFailedObserved | Should -BeTrue
        $script:PostgresServiceStartRefusedByMarker | Should -BeTrue
        [string]$script:PostgresTrustRuleMarkerState.State | Should -BeExactly 'Required'
        [string]$script:PostgresTrustRuleMarkerState.LiveState | Should -BeExactly $LiveState
        Test-Path -LiteralPath $markerPath | Should -BeTrue
        (Get-FileHash -LiteralPath $markerPath -Algorithm SHA256).Hash | Should -BeExactly $markerHash
        (Get-FileHash -LiteralPath $script:Fix60HbaPath -Algorithm SHA256).Hash | Should -BeExactly $hbaHash
    }

    It 'older build trust-rule marker: stopping a service that was stopped before is still allowed' {
        # Mutation: moving the marker start-gate ahead of the stop branch (refusing every service change while a marker exists)
        # leaves PostgreSQL running with the possible trust rule and fails the Stops/Stopped assertions.
        $markerPath = Write-Fix60LegacyTrustRuleMarker -HbaPath $script:Fix60HbaPath -BackupHbaPath $script:Fix60BackupHba -OriginalSha256 $script:Fix60OriginalHash -TrustSha256 $script:Fix60OriginalHash
        $script:Fix60Status = 'Running'
        Invoke-Fix60OuterCleanup -WasRunning $false
        $script:Fix60Stops | Should -Be 1
        $script:Fix60Starts | Should -Be 0
        $script:Fix60Status | Should -BeExactly 'Stopped'
        $script:Fix60RestoreFailedObserved | Should -BeFalse
        $script:PostgresServiceStartRefusedByMarker | Should -BeFalse
        Test-Path -LiteralPath $markerPath | Should -BeTrue
    }
}

Describe 'FIX60 #338 runtime: migrated PostgreSQL backups in the default restore discovery' -Tag 'FIX60' {
    BeforeEach {
        $script:TpmOwnedLayout = $null
        $script:Fix60Legacy = $script:Fix60ProgramDir
        foreach ($legacyName in @('PostgresBackups', 'PostgresRecoveryBackups')) {
            $legacyPath = Join-Path $script:Fix60Legacy $legacyName
            if (Test-Path -LiteralPath $legacyPath) { Remove-Item -LiteralPath $legacyPath -Recurse -Force -ErrorAction Stop }
        }
        $script:Fix60Managed = Join-Path (Join-Path $TestDrive ('fix60-managed-' + [guid]::NewGuid().ToString('N').Substring(0, 8))) 'Backups'
        [void][System.IO.Directory]::CreateDirectory($script:Fix60Managed)
        $script:TpmOwnedLayout = [pscustomobject]@{ Backups = $script:Fix60Managed }

        $script:Fix60Host = New-Object System.Collections.Generic.List[string]
        $script:Fix60Logs = New-Object System.Collections.Generic.List[string]
        $script:Fix60Tx = $null
        $script:Fix60Choice = '1'
        Mock Write-Host { param($Object) [void]$script:Fix60Host.Add([string]$Object) }
        Mock Write-Log { param([string]$msg) [void]$script:Fix60Logs.Add($msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Test-PostgresManualRecoveryRequired { $false }
        Mock Test-PostgresInstalled { $false }
        Mock Read-TpmChoice { $script:Fix60Choice }
        Mock Read-HostSafe { 'YES' }
        Mock Invoke-PostgresRestoreTransaction {
            param($BackupFiles, $SelectedBackupRoot, $SuperPasswordPlain)
            $script:Fix60Tx = [pscustomobject]@{ Root = [string]$SelectedBackupRoot; Files = @($BackupFiles | ForEach-Object { [string]$_.Name }) }
            [pscustomobject]@{ Outcome = 'NO_OP'; ReasonCode = 'FIX60_FIXTURE'; TechnicalDetails = [pscustomobject]@{ EvidenceRoot = $null }; DatabaseReceipts = @() }
        }
    }
    AfterEach {
        $script:TpmOwnedLayout = $null
        foreach ($legacyName in @('PostgresBackups', 'PostgresRecoveryBackups')) {
            $legacyPath = Join-Path $script:Fix60Legacy $legacyName
            if (Test-Path -LiteralPath $legacyPath) { Remove-Item -LiteralPath $legacyPath -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    It 'new-only layout: lists the migrated backups newest first and hands the selected migrated folder to the restore transaction' {
        # Mutation: a resolver that ignores the managed Backups folder reads the program folder, finds nothing, and the menu/transaction assertions fail.
        $older = New-Fix60PgBackup -ParentRoot $script:Fix60Managed -Name '2026-01-01_00-00-00' -Databases @('GameDbOld')
        $newer = New-Fix60PgBackup -ParentRoot $script:Fix60Managed -Name '2026-02-02_00-00-00' -Databases @('GameDbA', 'GameDbB')
        [System.IO.Directory]::SetLastWriteTime($older, [datetime]'2026-01-01T00:00:00')
        [System.IO.Directory]::SetLastWriteTime($newer, [datetime]'2026-02-02T00:00:00')
        $before = Get-Fix60TreeHash -Path (Join-Path $script:Fix60Managed 'PostgresBackups')
        $result = Invoke-RestorePostgresBackup
        $result.Outcome | Should -BeExactly 'NO_OP'
        $menu = $script:Fix60Host -join "`n"
        $menu | Should -Match '2026-02-02_00-00-00\s+\(2 database\(s\): GameDbA, GameDbB\)'
        $menu | Should -Match '2026-01-01_00-00-00\s+\(1 database\(s\): GameDbOld\)'
        $menu.IndexOf('2026-02-02_00-00-00') | Should -BeLessThan $menu.IndexOf('2026-01-01_00-00-00')
        $script:Fix60Tx.Root | Should -Be $newer
        $script:Fix60Tx.Files | Should -Be @('GameDbA.backup', 'GameDbB.backup')
        Test-Path -LiteralPath (Join-Path $script:Fix60Legacy 'PostgresBackups') | Should -BeFalse
        Get-Fix60TreeHash -Path (Join-Path $script:Fix60Managed 'PostgresBackups') | Should -BeExactly $before
    }

    It 'legacy-only layout: still discovers the backups left in the program folder, logs the fallback, and creates or moves nothing' {
        # Mutation: a resolver that always prefers the managed folder (even when only the legacy one exists) finds no backups and fails here.
        $legacyBackup = New-Fix60PgBackup -ParentRoot $script:Fix60Legacy -Name '2025-12-12_00-00-00' -Databases @('GameDbLegacy')
        $before = Get-Fix60TreeHash -Path (Join-Path $script:Fix60Legacy 'PostgresBackups')
        $result = Invoke-RestorePostgresBackup
        $result.Outcome | Should -BeExactly 'NO_OP'
        ($script:Fix60Host -join "`n") | Should -Match '2025-12-12_00-00-00\s+\(1 database\(s\): GameDbLegacy\)'
        $script:Fix60Tx.Root | Should -Be $legacyBackup
        @($script:Fix60Logs | Where-Object { $_ -like '*using existing legacy PostgresBackups folder; no backup folders were moved or merged*' }).Count | Should -BeGreaterThan 0
        Test-Path -LiteralPath (Join-Path $script:Fix60Managed 'PostgresBackups') | Should -BeFalse
        Get-Fix60TreeHash -Path (Join-Path $script:Fix60Legacy 'PostgresBackups') | Should -BeExactly $before
    }

    It 'both layouts present: stops before any prompt or restore, merges and deletes nothing, and names neither tree as a source' {
        # Mutation: silently preferring either tree lists its backups and calls the restore transaction, failing the Times 0 and menu assertions.
        [void](New-Fix60PgBackup -ParentRoot $script:Fix60Legacy -Name '2025-12-12_00-00-00' -Databases @('GameDbLegacy'))
        [void](New-Fix60PgBackup -ParentRoot $script:Fix60Managed -Name '2026-02-02_00-00-00' -Databases @('GameDbManaged'))
        $legacyBefore = Get-Fix60TreeHash -Path (Join-Path $script:Fix60Legacy 'PostgresBackups')
        $managedBefore = Get-Fix60TreeHash -Path (Join-Path $script:Fix60Managed 'PostgresBackups')
        $result = Invoke-RestorePostgresBackup
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'BACKUP_ROOT_UNVERIFIED'
        $menu = $script:Fix60Host -join "`n"
        $menu | Should -Match 'could not be safely selected'
        $menu | Should -Not -Match 'GameDbLegacy|GameDbManaged'
        @($script:Fix60Logs | Where-Object { $_ -like '*Both managed and legacy PostgresBackups folders exist*' }).Count | Should -BeGreaterThan 0
        Should -Invoke Read-TpmChoice -Times 0 -Exactly
        Should -Invoke Invoke-PostgresRestoreTransaction -Times 0 -Exactly
        Get-Fix60TreeHash -Path (Join-Path $script:Fix60Legacy 'PostgresBackups') | Should -BeExactly $legacyBefore
        Get-Fix60TreeHash -Path (Join-Path $script:Fix60Managed 'PostgresBackups') | Should -BeExactly $managedBefore
    }

    It 'explicit -BackupRoot override: is honored and bypasses the layout conflict check' {
        # Mutation: ignoring -BackupRoot (or resolving the conflict before honoring it) lists the wrong tree or fails closed.
        [void](New-Fix60PgBackup -ParentRoot $script:Fix60Legacy -Name '2025-12-12_00-00-00' -Databases @('GameDbLegacy'))
        [void](New-Fix60PgBackup -ParentRoot $script:Fix60Managed -Name '2026-02-02_00-00-00' -Databases @('GameDbManaged'))
        $override = Join-Path $TestDrive ('fix60-override-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $overrideBackup = New-Fix60PgBackup -ParentRoot $override -Name '2026-03-03_00-00-00' -Databases @('GameDbOverride')
        $result = Invoke-RestorePostgresBackup -BackupRoot (Join-Path $override 'PostgresBackups')
        $result.Outcome | Should -BeExactly 'NO_OP'
        $script:Fix60Tx.Root | Should -Be $overrideBackup
        ($script:Fix60Host -join "`n") | Should -Not -Match 'GameDbLegacy|GameDbManaged'
    }

    It 'neither layout holds backups: reports the managed backups folder as empty and does not fall back to unrelated locations' {
        # Mutation: defaulting to the program folder instead of the managed Backups folder names the wrong path in the message.
        $result = Invoke-RestorePostgresBackup
        $result.Reason | Should -BeExactly 'NO_POSTGRES_BACKUPS'
        $expected = Join-Path $script:Fix60Managed 'PostgresBackups'
        @($script:Fix60Host | Where-Object { $_.Contains($expected) }).Count | Should -Be 1
        Should -Invoke Invoke-PostgresRestoreTransaction -Times 0 -Exactly
    }

    It 'a migrated backup that is labeled incomplete is listed as incomplete and refused, bytes retained' {
        # Mutation: ignoring the TPM-BACKUP-INCOMPLETE.txt label in the migrated folder offers the unfinished backup for restore.
        $folder = New-Fix60PgBackup -ParentRoot $script:Fix60Managed -Name '2026-02-02_00-00-00' -Databases @('GameDbA')
        [System.IO.File]::WriteAllText((Get-PostgresIncompleteBackupMarkerPath -BackupFolder $folder), 'incomplete fixture')
        $before = Get-Fix60TreeHash -Path (Join-Path $script:Fix60Managed 'PostgresBackups')
        $result = Invoke-RestorePostgresBackup
        $result.Reason | Should -BeExactly 'INCOMPLETE_POSTGRES_BACKUP'
        ($script:Fix60Host -join "`n") | Should -Match 'INCOMPLETE - cannot be restored'
        Should -Invoke Invoke-PostgresRestoreTransaction -Times 0 -Exactly
        Get-Fix60TreeHash -Path (Join-Path $script:Fix60Managed 'PostgresBackups') | Should -BeExactly $before
    }

    It 'each backup tree is routed independently: a legacy PostgresBackups folder does not block a migrated PostgresRecoveryBackups folder' {
        # Mutation: one shared legacy/managed decision for all backup names throws or picks the wrong root for one tree.
        [void](New-Fix60PgBackup -ParentRoot $script:Fix60Legacy -Name '2025-12-12_00-00-00' -Databases @('GameDbLegacy'))
        $recoveryEvidence = Join-Path (Join-Path $script:Fix60Managed 'PostgresRecoveryBackups') 'evidence-1'
        [void][System.IO.Directory]::CreateDirectory($recoveryEvidence)
        (Get-TpmOwnedBackupsRoot -BackupName 'PostgresBackups') | Should -Be $script:Fix60Legacy
        (Get-TpmOwnedBackupsRoot -BackupName 'PostgresRecoveryBackups') | Should -Be $script:Fix60Managed
        (Get-PostgresRecoveryBackupRoot) | Should -Be (Join-Path $script:Fix60Managed 'PostgresRecoveryBackups')
        (Get-PostgresTrustRuleMarkerPath) | Should -Be (Join-Path (Join-Path $script:Fix60Managed 'PostgresRecoveryBackups') 'PostgresTrustRule.marker.json')
        # Competing PostgresRecoveryBackups histories fail closed for that tree only.
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:Fix60Legacy 'PostgresRecoveryBackups'))
        { Get-PostgresRecoveryBackupRoot } | Should -Throw -ExpectedMessage '*Both managed and legacy PostgresRecoveryBackups folders exist*'
        { Get-PostgresTrustRuleMarkerPath } | Should -Throw -ExpectedMessage '*Both managed and legacy PostgresRecoveryBackups folders exist*'
        (Get-TpmOwnedBackupsRoot -BackupName 'PostgresBackups') | Should -Be $script:Fix60Legacy
    }

    It 'a backup folder that cannot be read is reported as unreadable, not as "no backups"' {
        # Mutation: -ErrorAction SilentlyContinue on the folder listing -> an unreadable folder prints "No Postgres backup folders found." and returns Succeeded.
        [void](New-Fix60PgBackup -ParentRoot $script:Fix60Managed -Name '2026-02-02_00-00-00' -Databases @('GameDbA'))
        Mock Get-ChildItem { Write-Error 'Access to the path is denied.' } -ParameterFilter { $LiteralPath -like '*PostgresBackups' -and $Directory }
        $result = Invoke-RestorePostgresBackup
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -BeExactly 'POSTGRES_BACKUP_UNREADABLE'
        $menu = $script:Fix60Host -join "`n"
        $menu | Should -Match 'could not be read'
        $menu | Should -Not -Match 'No Postgres backup folders found'
        Should -Invoke Invoke-PostgresRestoreTransaction -Times 0 -Exactly
    }
}
