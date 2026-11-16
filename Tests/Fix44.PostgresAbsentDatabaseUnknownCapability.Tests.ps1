#Requires -Module Pester

# FIX44 PostgreSQL setup, absent database, unknown auto-create capability (owner
# report 2026-11-02): game profiles of the current TeknoParrot build carry no
# "Automatically create Database" field, so the capability is unknown. Setup
# used to stop for the whole library when one such profile's database was
# absent. Owner decision: TeknoParrot Manager creates a verified-absent game
# database itself (bundled pg_backup restored when the game ships one, otherwise
# an empty database), after every preflight check of every profile passed.
# Every blocked profile is reported with its own reason.
#
# The production script is parsed and only its function definitions are
# dot-sourced; no top-level product code runs in this process. The PostgreSQL 8.3
# client tools are replaced by one in-memory fake (Invoke-Postgres83RestoreCommand
# and Get-PostgresDatabaseState are mocked), so no PostgreSQL server, service,
# registry or user configuration is touched; every file lives under TestDrive.
# Each It names the product mutation that makes it fail.

BeforeAll {
    $script:Fix44PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix44PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX44 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix44FunctionFile = Join-Path $TestDrive 'tpm-fix44-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix44FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix44FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $script:logPath = Join-Path $TestDrive 'fix44.log'

    # One fixture per test: bin folder with the five 8.3 tool files, evidence
    # folder, UserProfiles folder and the fake server state.
    function New-F44Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f44-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
        $bin = Join-Path $root 'bin'
        $evidence = Join-Path $root 'evidence'
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $bin, $evidence, $profiles -Force | Out-Null
        foreach ($tool in @(Get-Postgres83RestoreToolNames)) { New-Item -ItemType File -Path (Join-Path $bin $tool) -Force | Out-Null }
        $state = [pscustomobject]@{
            Exists = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::Ordinal)
            Calls = New-Object System.Collections.Generic.List[object]
            Events = New-Object System.Collections.Generic.List[string]
            Log = New-Object System.Collections.Generic.List[string]
            FailCreate = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            FailRestore = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            UnverifiedState = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            FailCaseQuery = $false
        }
        return [pscustomobject]@{ Root = $root; Bin = $bin; Evidence = $evidence; Profiles = $profiles; State = $state }
    }

    # The owner's real profile shape: Postgres category with Path, Address,
    # Port, DbName, User and Pass only (no "Automatically create Database").
    # The game ships one bundled backup unless -NoBackup is given.
    function New-F44Profile {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$DbName,
            [string]$Pass = '',
            [string]$AutoCreate = '',
            [switch]$NoBackup,
            [switch]$NoGameExe,
            [switch]$NoPassField,
            [string]$BackupFolderName = '',
            [string]$Address = '',
            [string]$Port = '',
            [string]$User = ''
        )
        $folderName = if ($BackupFolderName) { $BackupFolderName } else { 'Game-' + $Name }
        $gameDir = Join-Path $Fixture.Root $folderName
        New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
        $exe = Join-Path $gameDir 'game.exe'
        if (-not $NoGameExe) { New-Item -ItemType File -Path $exe -Force | Out-Null }
        if (-not $NoBackup) {
            $backupDir = Join-Path $gameDir 'pg_backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $backupDir '0001.backup'), 'bundled', (New-Object System.Text.UTF8Encoding $false))
        }
        $fields = New-Object System.Collections.Generic.List[object]
        [void]$fields.Add(@('Path', ''))
        [void]$fields.Add(@('Address', $Address))
        [void]$fields.Add(@('Port', $Port))
        [void]$fields.Add(@('DbName', $DbName))
        [void]$fields.Add(@('User', $User))
        if (-not $NoPassField) { [void]$fields.Add(@('Pass', $Pass)) }
        if ($AutoCreate -ne '') { [void]$fields.Add(@('Automatically create Database', $AutoCreate)) }
        $xml = '<GameProfile><GameName>' + $Name + '</GameName><GamePath>' + $exe + '</GamePath><ConfigValues>'
        foreach ($field in $fields) {
            $xml += '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $field[0] + '</FieldName><FieldValue>' + $field[1] + '</FieldValue></FieldInformation>'
        }
        $xml += '</ConfigValues></GameProfile>'
        $file = Join-Path $Fixture.Profiles ($Name + '.xml')
        [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $file
    }

    function New-F44CommandResult {
        param([string]$ToolName, [string[]]$Arguments, [int]$ExitCode, [string]$Output = '')
        return [pscustomobject]@{
            Tool = $ToolName
            Executable = Join-Path $script:PostgresBinDir $ToolName
            Arguments = @($Arguments)
            ExitCode = $ExitCode
            Succeeded = ($ExitCode -eq 0)
            Output = $Output
        }
    }

    # In-memory PostgreSQL 8.3 client: records every call and changes the fake
    # server state the way the real createdb/dropdb/pg_restore would.
    function Invoke-F44FakeCommand {
        param([string]$ToolName, [string[]]$Arguments)
        $state = $script:F44State
        $database = ''
        $encoding = ''
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if ($Arguments[$i] -ceq '-d') { $database = [string]$Arguments[$i + 1] }
            if ($Arguments[$i] -ceq '-E') { $encoding = [string]$Arguments[$i + 1] }
        }
        if ($ToolName -in @('createdb.exe', 'dropdb.exe')) { $database = [string]$Arguments[$Arguments.Count - 1] }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -notcontains '--list') { $database = [string]$Arguments[$Arguments.Count - 2] }
        [void]$state.Calls.Add([pscustomobject]@{ Tool = $ToolName; Database = $database; Encoding = $encoding; Arguments = @($Arguments) })
        if ($Arguments -contains '--version') {
            return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($ToolName + ' (PostgreSQL) 8.3.23'))
        }
        if ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc') {
            if ($state.FailCaseQuery) { return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 2 -Output 'case query failed') }
            $query = [string]$Arguments[$Arguments.Count - 1]
            if ($query -match 'count\(\*\)') { return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '24') }
            $wanted = ''
            if ($query -match "lower\('([^']+)'\)\s*$") { $wanted = $Matches[1] }
            $names = @($state.Exists.Keys | Where-Object { $state.Exists[$_] -and [string]::Equals($_, $wanted, [System.StringComparison]::OrdinalIgnoreCase) })
            return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($names -join "`n"))
        }
        if ($ToolName -eq 'psql.exe') { return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -contains '--list') { return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe') {
            [void]$state.Events.Add('pg_restore:' + $database)
            if ($state.FailRestore.Contains($database)) { return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 5 -Output 'restore failed') }
            return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'createdb.exe') {
            [void]$state.Events.Add('createdb:' + $database)
            if ($state.FailCreate.Contains($database)) { return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 1 -Output 'createdb failed') }
            $state.Exists[$database] = $true
            return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'dropdb.exe') {
            [void]$state.Events.Add('dropdb:' + $database)
            $state.Exists[$database] = $false
            return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        return (New-F44CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 3 -Output 'unexpected fake tool')
    }

    function Install-F44Mocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F44State = $Fixture.State
        $script:F44Recovery = [pscustomobject]@{ Path = $Fixture.Evidence; ConfigBackups = @(); Verified = $true; ProfileBackups = @() }
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log { [void]$script:F44State.Log.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock New-PostgresRecoveryBackup { [void]$script:F44State.Events.Add('backup'); $script:F44Recovery }
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            # FIX129: the fake runs the caller's -Interpret block on its text, like the real runner does.
            Add-FakePostgresInterpretation -Command (Invoke-F44FakeCommand -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            $state = $script:F44State
            if ($state.UnverifiedState.Contains($DbName)) { return [pscustomobject]@{ Exists = $null; Verified = $false } }
            $exists = $false
            if ($state.Exists.ContainsKey($DbName)) { $exists = [bool]$state.Exists[$DbName] }
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
    }

    function Get-F44Calls {
        param([Parameter(Mandatory)][string]$Tool)
        return @($script:F44State.Calls | Where-Object { $_.Tool -eq $Tool -and $_.Arguments -notcontains '--version' })
    }

    function Get-F44RestoreCalls {
        return @($script:F44State.Calls | Where-Object { $_.Tool -eq 'pg_restore.exe' -and $_.Arguments -notcontains '--list' -and $_.Arguments -notcontains '--version' })
    }

    function Get-F44Value {
        param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$Field)
        return (Get-PostgresFieldValue (Read-Xml $File) $Field)
    }

    function Invoke-F44Setup {
        param([Parameter(Mandatory)]$Fixture, [string[]]$Approved = @())
        return (Invoke-PostgresGameSetup -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password' -ApprovedPassReplacements $Approved)
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix44PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX44 absent database with unknown auto-create capability is created, not a library-wide stop' {
    Context 'owner profile shape without the auto-create field' {
        # Mutation: restore the old throw "automatic creation capability is unknown" in the
        # preflight -> Outcome is FAILED_BEFORE_MUTATION / no createdb call and every
        # assertion below fails.
        It 'creates the absent database from the bundled backup, configures both profiles and leaves the existing database alone' {
            $fx = New-F44Fixture -Name 'a'
            $fx.State.Exists['GameDBPPL12'] = $true
            $existing = New-F44Profile -Fixture $fx -Name 'PowerPuttLive2012' -DbName 'GameDBPPL12'
            $absent = New-F44Profile -Fixture $fx -Name 'PowerPuttLive2013' -DbName 'GameDBPPL13'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.Errors | Should -Be 0
            $result.DbCreated | Should -Be 1
            $result.Configured | Should -Be 2
            $creates = @(Get-F44Calls -Tool 'createdb.exe')
            $creates.Count | Should -Be 1
            $creates[0].Database | Should -BeExactly 'GameDBPPL13'
            $creates[0].Encoding | Should -BeExactly 'SQL_ASCII'
            $creates[0].Arguments | Should -Contain 'template0'
            @(Get-F44RestoreCalls).Count | Should -Be 1
            @(Get-F44Calls -Tool 'dropdb.exe').Count | Should -Be 0
            $fx.State.Exists['GameDBPPL13'] | Should -BeTrue
            $fx.State.Exists['GameDBPPL12'] | Should -BeTrue
            $fx.State.Events.IndexOf('backup') | Should -BeGreaterThan -1
            $fx.State.Events.IndexOf('backup') | Should -BeLessThan $fx.State.Events.IndexOf('createdb:GameDBPPL13')
            foreach ($file in @($existing, $absent)) {
                (Get-F44Value -File $file -Field 'Address') | Should -BeExactly '127.0.0.1'
                (Get-F44Value -File $file -Field 'Port') | Should -BeExactly '5432'
                (Get-F44Value -File $file -Field 'User') | Should -BeExactly 'postgres'
                (Get-F44Value -File $file -Field 'Pass') | Should -BeExactly 'fixture-password'
                (Get-F44Value -File $file -Field 'Path') | Should -BeExactly ($fx.Bin.TrimEnd('\') + '\')
            }
            $receipts = @($result.TechnicalDetails.DatabaseCreationReceipts)
            $receipts.Count | Should -Be 1
            $receipts[0].Mode | Should -BeExactly 'RestoreBundledBackup'
            (@($result.Warnings) -join ' | ') | Should -Match 'GameDBPPL13\): the database did not exist\. TeknoParrot Manager created it and restored the backup bundled with the game'
            (@($result.Warnings) -join ' | ') | Should -Match 'does not say whether it creates the database automatically'
            @($result.GameOutcomes | Where-Object { $_.DbName -ceq 'GameDBPPL13' })[0].TableCount | Should -Be 24
            ($fx.State.Log -join "`n") | Should -Not -Match 'preflight blocked'
            ($result.TechnicalDetails | ConvertTo-Json -Depth 12) | Should -Not -Match 'fixture-password'
            @(Get-PostgresSetupFailureReasonLines -TransactionResult $result).Count | Should -Be 0
            { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        }

        # Mutation: ignore the bundled pg_backup for unknown capability -> no pg_restore call.
        It 'restores from the bundled pg_backup and uses the restore encoding' {
            $fx = New-F44Fixture -Name 'a-backup'
            $null = New-F44Profile -Fixture $fx -Name 'GolfGame' -DbName 'GameDB06'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.DbCreated | Should -Be 1
            $creates = @(Get-F44Calls -Tool 'createdb.exe')
            $creates.Count | Should -Be 1
            $creates[0].Database | Should -BeExactly 'GameDB06'
            $creates[0].Encoding | Should -BeExactly 'UTF8'
            $restores = @(Get-F44RestoreCalls)
            $restores.Count | Should -Be 1
            $restores[0].Database | Should -BeExactly 'GameDB06'
            [string]$restores[0].Arguments[-1] | Should -Match '0001\.backup$'
            @($fx.State.Events | Where-Object { $_ -in @('backup', 'createdb:GameDB06', 'pg_restore:GameDB06') }) | Should -Be @('backup', 'createdb:GameDB06', 'pg_restore:GameDB06')
            @($result.TechnicalDetails.DatabaseCreationReceipts)[0].Mode | Should -BeExactly 'RestoreBundledBackup'
            (@($result.Warnings) -join ' | ') | Should -Match 'restored the backup bundled with the game'
            { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        }

        # Mutation: skip database creation for a profile whose Pass is kept
        # (NeedsApproval), or fill Pass although it was not approved.
        It 'creates the database for a profile whose different password is kept, and keeps that password' {
            $fx = New-F44Fixture -Name 'b'
            $kept = New-F44Profile -Fixture $fx -Name 'TargetTossProBags' -DbName 'GameDBBags' -Pass 'owner-own-password' -Address '127.0.0.1' -Port '5432' -User 'postgres'
            $before = (Get-FileHash -LiteralPath $kept -Algorithm SHA256).Hash
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.DbCreated | Should -Be 1
            @(Get-F44Calls -Tool 'createdb.exe')[0].Database | Should -BeExactly 'GameDBBags'
            @($result.PassKeptProfiles) | Should -Contain 'TargetTossProBags'
            (Get-F44Value -File $kept -Field 'Pass') | Should -BeExactly 'owner-own-password'
            # Keeping a profile means no write at all: its blank Path is not filled either.
            (Get-FileHash -LiteralPath $kept -Algorithm SHA256).Hash | Should -BeExactly $before
            { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        }

        # Mutation: create or drop anything for a database that already exists.
        It 'never creates, restores or drops an existing database, even when the game ships a backup' {
            $fx = New-F44Fixture -Name 'existing'
            $fx.State.Exists['GameDBExisting'] = $true
            $null = New-F44Profile -Fixture $fx -Name 'ExistingGame' -DbName 'GameDBExisting'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.DbCreated | Should -Be 0
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            @(Get-F44Calls -Tool 'dropdb.exe').Count | Should -Be 0
            @(Get-F44RestoreCalls).Count | Should -Be 0
            (@($result.Warnings) -join ' | ') | Should -Match 'already existed and was left untouched'
        }
    }

    Context 'two profiles that name the same absent database' {
        # Mutation: remove the sibling update after a creation (second createdb call), or
        # keep the old group rule that blocks every shared absent non-TeknoParrot database.
        It 'creates a shared absent database once and configures both profiles' {
            $fx = New-F44Fixture -Name 'shared'
            $one = New-F44Profile -Fixture $fx -Name 'SharedOne' -DbName 'GameDBShared' -BackupFolderName 'Game-Shared'
            $two = New-F44Profile -Fixture $fx -Name 'SharedTwo' -DbName 'GameDBShared' -BackupFolderName 'Game-Shared'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.DbCreated | Should -Be 1
            $result.Configured | Should -Be 2
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 1
            (Get-F44Value -File $one -Field 'Pass') | Should -BeExactly 'fixture-password'
            (Get-F44Value -File $two -Field 'Pass') | Should -BeExactly 'fixture-password'
            { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        }

        # Mutation: drop the same-backup comparison (create from one of two different backups).
        It 'blocks, naming both profiles, when the two profiles resolve to different bundled backups' {
            $fx = New-F44Fixture -Name 'shared-different'
            $null = New-F44Profile -Fixture $fx -Name 'SharedOne' -DbName 'GameDBShared'
            $null = New-F44Profile -Fixture $fx -Name 'SharedTwo' -DbName 'GameDBShared'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
            $result.ReasonCode | Should -BeExactly 'POSTGRES_PREFLIGHT_FAILED'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            $reasons = @(Get-PostgresSetupFailureReasonLines -TransactionResult $result)
            $reasons.Count | Should -Be 2
            ($reasons -join ' | ') | Should -Match 'SharedOne'
            ($reasons -join ' | ') | Should -Match 'SharedTwo'
            ($reasons -join ' | ') | Should -Match 'GameDBShared'
        }
    }

    Context 'explicit auto-create values keep their existing behavior' {
        # Mutation: bring back the deferral to TeknoParrot for auto-create 1 without a backup -> setup says SUCCEEDED, nothing is
        # created and the game is left without a database.
        It 'leaves out the game, naming it, when the profile says TeknoParrot creates the database but the game has no bundled backup' {
            $fx = New-F44Fixture -Name 'e'
            $expressProfile = New-F44Profile -Fixture $fx -Name 'ExpressGame' -DbName 'GameDBExpress' -AutoCreate '1' -NoBackup
            $before = [System.IO.File]::ReadAllBytes($expressProfile)
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            $fx.State.Exists.ContainsKey('GameDBExpress') | Should -BeFalse
            @($result.NotReadyGames | ForEach-Object { $_.Key }) | Should -Be @('ExpressGame')
            (@($result.Warnings) -join ' | ') | Should -Match 'ExpressGame.*No starting database file came with this game'
            [System.IO.File]::ReadAllBytes($expressProfile) | Should -Be $before
        }

        # Mutation: ignore the bundled backup for an explicit 0.
        It 'restores the bundled backup when the profile says TeknoParrot will not create the database' {
            $fx = New-F44Fixture -Name 'f1'
            $null = New-F44Profile -Fixture $fx -Name 'LegacyGame' -DbName 'GameDBLegacy' -AutoCreate '0'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $result.DbCreated | Should -Be 1
            @(Get-F44Calls -Tool 'createdb.exe')[0].Database | Should -BeExactly 'GameDBLegacy'
            @(Get-F44RestoreCalls).Count | Should -Be 1
            @($result.TechnicalDetails.DatabaseCreationReceipts)[0].Mode | Should -BeExactly 'RestoreBundledBackup'
            (@($result.Warnings) -join ' | ') | Should -Not -Match 'does not say whether'
        }

        # Mutation: create an empty database for an explicit 0 without a bundled backup -> createdb appears.
        It 'still leaves out the game, naming it, when an explicit 0 has no bundled backup' {
            $fx = New-F44Fixture -Name 'f2'
            $before = [System.IO.File]::ReadAllBytes((New-F44Profile -Fixture $fx -Name 'LegacyNoBackup' -DbName 'GameDBLegacy2' -AutoCreate '0' -NoBackup))
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            @($result.NotReadyGames | ForEach-Object { $_.Key }) | Should -Be @('LegacyNoBackup')
            [System.IO.File]::ReadAllBytes((Join-Path $fx.Profiles 'LegacyNoBackup.xml')) | Should -Be $before
        }
    }

    Context 'blocking causes name the profile and the reason' {
        # Mutation: drop the per-profile reason (log only the profile name) or block the
        # healthy profile as well.
        It 'blocks on a profile without a safe database name, names it and its reason, and writes nothing' {
            $fx = New-F44Fixture -Name 'c'
            $good = New-F44Profile -Fixture $fx -Name 'GoodGame' -DbName 'GameDBGood'
            $null = New-F44Profile -Fixture $fx -Name 'BadNameGame' -DbName 'Bad-Name'
            $goodBefore = [System.IO.File]::ReadAllBytes($good)
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
            $result.ReasonCode | Should -BeExactly 'POSTGRES_PREFLIGHT_FAILED'
            $result.Summary | Should -BeExactly 'PostgreSQL setup stopped before changing any databases or profiles.'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            $reasons = @(Get-PostgresSetupFailureReasonLines -TransactionResult $result)
            $reasons.Count | Should -Be 1
            $reasons[0] | Should -Match 'BadNameGame.*The profile has no safe PostgreSQL database name'
            ($reasons -join ' | ') | Should -Not -Match 'GoodGame'
            ($fx.State.Log -join "`n") | Should -Match 'preflight blocked for BadNameGame: The profile has no safe PostgreSQL database name'
            [System.IO.File]::ReadAllBytes($good) | Should -Be $goodBefore
            $fx.State.Events.Contains('backup') | Should -BeFalse
            { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        }

        # Mutation: keep only the last reason in $preflightError (the FIX44 bug).
        It 'reports every blocked profile with its own reason in the log, the errors and the technical details' {
            $fx = New-F44Fixture -Name 'd'
            $null = New-F44Profile -Fixture $fx -Name 'BadNameGame' -DbName 'Bad-Name'
            $null = New-F44Profile -Fixture $fx -Name 'NoPassGame' -DbName 'GameDBNoPass' -NoPassField
            $null = New-F44Profile -Fixture $fx -Name 'UnverifiedGame' -DbName 'GameDBUnverified'
            $null = New-F44Profile -Fixture $fx -Name 'ZGoodGame' -DbName 'GameDBZGood'
            $fx.State.UnverifiedState.Add('GameDBUnverified') | Out-Null
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
            $result.Errors | Should -Be 3
            $reasons = @($result.TechnicalDetails.FailureReasons)
            $reasons.Count | Should -Be 3
            ($reasons -join ' | ') | Should -Match 'BadNameGame.*no safe PostgreSQL database name'
            ($reasons -join ' | ') | Should -Match 'NoPassGame.*no PostgreSQL Pass field'
            ($reasons -join ' | ') | Should -Match 'UnverifiedGame.*database existence result was not verified'
            ($reasons -join ' | ') | Should -Not -Match 'ZGoodGame'
            @($result.TechnicalDetails.BlockedProfiles | ForEach-Object { $_.Profile }) | Should -Be @('BadNameGame', 'NoPassGame', 'UnverifiedGame')
            $log = $fx.State.Log -join "`n"
            $log | Should -Match 'preflight blocked for BadNameGame: '
            $log | Should -Match 'preflight blocked for NoPassGame: '
            $log | Should -Match 'preflight blocked for UnverifiedGame: '
            $log | Should -Not -Match 'fixture-password'
            ($result.TechnicalDetails | ConvertTo-Json -Depth 8) | Should -Not -Match 'fixture-password'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
        }

        # Mutation: create an empty database when the game executable cannot be found
        # (a bundled backup on an unmounted drive would then be skipped for good).
        It 'blocks, naming the profile, when the game executable is missing and the database is absent' {
            $fx = New-F44Fixture -Name 'm'
            $null = New-F44Profile -Fixture $fx -Name 'MovedGame' -DbName 'GameDBMoved' -NoGameExe
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'MovedGame.*game executable could not be found'
        }
    }

    Context 'case-variant database names are never created' {
        # Mutation: remove the case-variant comparison from the preflight.
        It 'blocks the profile when a database differing only by case exists, and creates nothing' {
            $fx = New-F44Fixture -Name 'j'
            $fx.State.Exists['gamedbppl13'] = $true
            $null = New-F44Profile -Fixture $fx -Name 'PowerPuttLive2013' -DbName 'GameDBPPL13'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'PowerPuttLive2013.*differs only by case \(gamedbppl13\)'
        }

        # Mutation: treat a failed case query as "no variant".
        It 'blocks when the case comparison cannot be verified' {
            $fx = New-F44Fixture -Name 'j-unverified'
            $fx.State.FailCaseQuery = $true
            $null = New-F44Profile -Fixture $fx -Name 'CaseGame' -DbName 'GameDBCase'
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
            (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'CaseGame.*could not be compared by case'
        }

        # Mutation: remove the creation-time case check (defense if a variant appears after preflight).
        It 'refuses at the creation boundary before any mutation when a case variant exists' {
            $fx = New-F44Fixture -Name 'j-direct'
            $fx.State.Exists['GAMEDBX'] = $true
            Install-F44Mocks -Fixture $fx

            $backupFile = Join-Path $TestDrive 'f44-direct.backup'
            [System.IO.File]::WriteAllText($backupFile, 'bundled')
            $creation = New-PostgresDatabaseFromBackup -DbName 'GameDBX' -Encoding 'SQL_ASCII' -BackupFile $backupFile -SuperPasswordPlain 'fixture-password'

            $creation.Succeeded | Should -BeFalse
            $creation.FailureStage | Should -BeExactly 'CaseVariantCheck'
            $creation.MutationAttempted | Should -BeFalse
            $creation.Mode | Should -BeExactly 'RestoreBundledBackup'
            @(Get-F44Calls -Tool 'createdb.exe').Count | Should -Be 0
        }
    }

    Context 'creation failure fails closed and reports which database and why' {
        # Mutation: continue to profile writes after a failed creation, or drop a database
        # this run did not create.
        It 'stops on the first failing creation, names the database, changes no profile and drops nothing' {
            $fx = New-F44Fixture -Name 'g1'
            $fx.State.Exists['GameDBOther'] = $true
            $a = New-F44Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
            $b = New-F44Profile -Fixture $fx -Name 'BGame' -DbName 'GameDBB'
            $null = New-F44Profile -Fixture $fx -Name 'CGame' -DbName 'GameDBOther'
            $fx.State.FailCreate.Add('GameDBA') | Out-Null
            $aBefore = [System.IO.File]::ReadAllBytes($a)
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
            # FIX128 (B3): the Summary of a verified rollback is plain ("previous verified state was restored" is gone). Mutation: bring the old text back.
            $result.Summary | Should -BeExactly 'Setup stopped. Everything was put back the way it was, and checked.'
            $result.ProductState | Should -BeExactly 'UNCHANGED'
            $result.RecoveryBlocked | Should -BeTrue
            $result.DbCreated | Should -Be 0
            @(Get-F44Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
            @(Get-F44Calls -Tool 'dropdb.exe').Count | Should -Be 0
            $fx.State.Exists['GameDBOther'] | Should -BeTrue
            $reasons = @(Get-PostgresSetupFailureReasonLines -TransactionResult $result)
            $reasons.Count | Should -Be 1
            $reasons[0] | Should -Match '^Database GameDBA could not be created: '
            ($fx.State.Log -join "`n") | Should -Match 'Database GameDBA could not be created'
            [System.IO.File]::ReadAllBytes($a) | Should -Be $aBefore
            [string]::IsNullOrEmpty((Get-F44Value -File $b -Field 'Pass')) | Should -BeTrue
            { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        }

        # Mutation: skip Restore-PostgresSetupCreatedDatabases after a later creation fails.
        It 'drops only the database this run created when a later creation fails' {
            $fx = New-F44Fixture -Name 'g2'
            $fx.State.Exists['GameDBOther'] = $true
            $null = New-F44Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
            $null = New-F44Profile -Fixture $fx -Name 'BGame' -DbName 'GameDBB'
            $null = New-F44Profile -Fixture $fx -Name 'CGame' -DbName 'GameDBOther'
            $fx.State.FailCreate.Add('GameDBB') | Out-Null
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
            $result.Summary | Should -BeExactly 'Setup stopped. Everything was put back the way it was, and checked.'
            @(Get-F44Calls -Tool 'dropdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
            $fx.State.Exists['GameDBA'] | Should -BeFalse
            $fx.State.Exists['GameDBOther'] | Should -BeTrue
            (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'Database GameDBB could not be created'
            { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        }

        # Mutation: leave a database behind after a failed restore, or drop the wrong name.
        It 'drops the database it created after a failed bundled restore and reports the database' {
            $fx = New-F44Fixture -Name 'h'
            $fx.State.Exists['GameDBOther'] = $true
            $null = New-F44Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
            $null = New-F44Profile -Fixture $fx -Name 'CGame' -DbName 'GameDBOther'
            $fx.State.FailRestore.Add('GameDBA') | Out-Null
            Install-F44Mocks -Fixture $fx

            $result = Invoke-F44Setup -Fixture $fx

            $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
            $result.Summary | Should -BeExactly 'Setup stopped. Everything was put back the way it was, and checked.'
            @(Get-F44Calls -Tool 'dropdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
            $fx.State.Exists['GameDBA'] | Should -BeFalse
            $fx.State.Exists['GameDBOther'] | Should -BeTrue
            (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'Database GameDBA could not be created'
            ($result.TechnicalDetails | ConvertTo-Json -Depth 12) | Should -Not -Match 'fixture-password'
        }
    }
}
