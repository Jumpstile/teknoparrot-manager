#Requires -Module Pester

# FIX130: setup rollback and records. What the product reports about a setup that did not finish must be true.
#   S6  Item ids: a database is 'database:<name>' in EVERY list of the setup result (the profile-failure rollback used the bare name, so
#       a failed drop was "unknown" under one id and "completed" under another).
#   S10 The database-creation phase fails closed: an unexpected error or a stop OUTSIDE the per-database try, and a stop that leaves no
#       creation result, end in a verified rollback of only what this run created (never a silent leftover or an escaped exception).
#   S11 A small durable journal of the databases THIS run creates: on disk BEFORE createdb runs, cleared on a verified success or a
#       verified rollback, found and handled by the next run in plain words; only a database the journal names is ever dropped.
#   S12 Reinitialize uses the game's one unambiguous backup file (the rule fresh setup uses) and the confirm screen names that file.
#   N6  The "tables and rows were restored" claim is gone: only what was checked is said.
#
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs. The PostgreSQL 8.3
# client tools are replaced by one in-memory fake, so no PostgreSQL server, service, registry or user configuration is touched. Every file
# lives under TestDrive. Each It names the product mutation that makes it fail.

BeforeAll {
    $script:F130PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:F130PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $script:F130ProductionSource = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:F130ProductionSource, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX130 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F130FunctionFile = Join-Path $TestDrive 'tpm-fix130-functions.ps1'
    [System.IO.File]::WriteAllText($script:F130FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F130FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $script:logPath = Join-Path $TestDrive 'fix130.log'

    function New-F130Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f130-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
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
            Screen = New-Object System.Collections.Generic.List[string]
            FailCreate = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            FailDrop = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            JournalAtCreate = @{}
            JournalPath = Join-Path $root 'PostgresSetupCreatedDatabases.journal.json'
        }
        return [pscustomobject]@{ Root = $root; Bin = $bin; Evidence = $evidence; Profiles = $profiles; State = $state }
    }

    function New-F130Profile {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$DbName,
            [string[]]$BackupNames = @('0001.backup')
        )
        $gameDir = Join-Path $Fixture.Root ('Game-' + $Name)
        New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
        $exe = Join-Path $gameDir 'game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        if (@($BackupNames).Count -gt 0) {
            $backupDir = Join-Path $gameDir 'pg_backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            foreach ($backupName in $BackupNames) { [System.IO.File]::WriteAllText((Join-Path $backupDir $backupName), 'bundled', (New-Object System.Text.UTF8Encoding $false)) }
        }
        $xml = '<GameProfile><GameName>' + $Name + '</GameName><GamePath>' + $exe + '</GamePath><ConfigValues>'
        foreach ($field in @(@('Path', ''), @('Address', ''), @('Port', ''), @('DbName', $DbName), @('User', ''), @('Pass', ''))) {
            $xml += '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $field[0] + '</FieldName><FieldValue>' + $field[1] + '</FieldValue></FieldInformation>'
        }
        $xml += '</ConfigValues></GameProfile>'
        $file = Join-Path $Fixture.Profiles ($Name + '.xml')
        [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $file
    }

    function New-F130CommandResult {
        param([string]$ToolName, [string[]]$Arguments, [int]$ExitCode, [string]$Output = '')
        return [pscustomobject]@{ Tool = $ToolName; Executable = Join-Path $script:PostgresBinDir $ToolName; Arguments = @($Arguments); ExitCode = $ExitCode; Succeeded = ($ExitCode -eq 0); Output = $Output }
    }

    function Invoke-F130FakeCommand {
        param([string]$ToolName, [string[]]$Arguments)
        $state = $script:F130State
        $database = ''
        $encoding = ''
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if ($Arguments[$i] -ceq '-d') { $database = [string]$Arguments[$i + 1] }
            if ($Arguments[$i] -ceq '-E') { $encoding = [string]$Arguments[$i + 1] }
        }
        if ($ToolName -in @('createdb.exe', 'dropdb.exe')) { $database = [string]$Arguments[$Arguments.Count - 1] }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -notcontains '--list') { $database = [string]$Arguments[$Arguments.Count - 2] }
        [void]$state.Calls.Add([pscustomobject]@{ Tool = $ToolName; Database = $database; Encoding = $encoding; Arguments = @($Arguments) })
        if ($Arguments -contains '--version') { return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($ToolName + ' (PostgreSQL) 8.3.23')) }
        if ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc') {
            $query = [string]$Arguments[$Arguments.Count - 1]
            if ($query -match 'count\(\*\)') { return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '24') }
            $wanted = ''
            if ($query -match "lower\('([^']+)'\)\s*$") { $wanted = $Matches[1] }
            $names = @($state.Exists.Keys | Where-Object { $state.Exists[$_] -and [string]::Equals($_, $wanted, [System.StringComparison]::OrdinalIgnoreCase) })
            return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($names -join "`n"))
        }
        if ($ToolName -eq 'psql.exe') { return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe') { return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'createdb.exe') {
            [void]$state.Events.Add('createdb:' + $database)
            # What is on disk at the moment createdb runs (S11: the journal must already name this database).
            $state.JournalAtCreate[$database] = if ([System.IO.File]::Exists($state.JournalPath)) { [System.IO.File]::ReadAllText($state.JournalPath) } else { $null }
            if ($state.FailCreate.Contains($database)) { return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 1 -Output 'createdb failed') }
            $state.Exists[$database] = $true
            return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'dropdb.exe') {
            [void]$state.Events.Add('dropdb:' + $database)
            if ($state.FailDrop.Contains($database)) { return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 1 -Output 'dropdb failed') }
            $state.Exists[$database] = $false
            return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        return (New-F130CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 3 -Output 'unexpected fake tool')
    }

    function Install-F130Mocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F130State = $Fixture.State
        $script:F130Recovery = [pscustomobject]@{ Path = $Fixture.Evidence; ConfigBackups = @(); Verified = $true; ProfileBackups = @() }
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log { [void]$script:F130State.Log.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-TpmText { [void]$script:F130State.Screen.Add([string]$Text) }
        Mock Write-Host { [void]$script:F130State.Screen.Add(((@($Object) | ForEach-Object { [string]$_ }) -join ' ')) }
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Assert-PostgresRecoveryDirectoryAcl {}
        Mock Restore-PostgresProfileBackups { $true }
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            Add-FakePostgresInterpretation -Command (Invoke-F130FakeCommand -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            $exists = $false
            if ($script:F130State.Exists.ContainsKey($DbName)) { $exists = [bool]$script:F130State.Exists[$DbName] }
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
    }

    function Invoke-F130Setup {
        param([Parameter(Mandatory)]$Fixture)
        return (Invoke-PostgresGameSetup -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password' -RecoveryBackup $script:F130Recovery)
    }

    function Get-F130Calls {
        param([Parameter(Mandatory)][string]$Tool)
        return @($script:F130State.Calls | Where-Object { $_.Tool -eq $Tool -and $_.Arguments -notcontains '--version' })
    }

    function Write-F130Journal {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][object[]]$Entries)
        $document = [ordered]@{ Schema = 'TPM.PostgresSetupJournal.v1'; RunId = 'earlier'; Entries = @($Entries | ForEach-Object { [ordered]@{ Database = $_[0]; Stage = $_[1]; UpdatedUtc = '2026-11-01T10:00:00.0000000Z' } }) }
        [System.IO.File]::WriteAllText($Fixture.State.JournalPath, ($document | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-F130Mutation {
        param([Parameter(Mandatory)]$Result)
        return (Get-TpmTransactionField -Object $Result -Name 'Mutation')
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:F130PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX130 S6 one item id form in every list of the setup result' {
    It 'shows a database whose rollback drop failed only as unknown, under its database: id, when the profile write fails' {
        # Mutation: give the profile-failure rollback the bare database name again (use $dbRollback.FailedItems as they are) -> UnknownItems
        # holds 'GameDBA', CompletedItems still holds 'database:GameDBA', and this test fails on both.
        $fx = New-F130Fixture -Name 's6a'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.FailDrop.Add('GameDBA') | Out-Null
        Install-F130Mocks -Fixture $fx
        Mock Save-Xml { throw 'disk full' }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $mutation = Get-F130Mutation -Result $result
        @($mutation.UnknownItems) | Should -Be @('database:GameDBA')
        @($mutation.CompletedItems) | Should -Not -Contain 'database:GameDBA'
        @($mutation.FailedItems) | Should -Not -Contain 'database:GameDBA'
        @($mutation.UnknownItems) + @($mutation.CompletedItems) + @($mutation.FailedItems) + @($mutation.UnattemptedItems) + @($mutation.SkippedItems) | Should -Not -Contain 'GameDBA'
        @($result.Rollback.FailedItems) | Should -Be @('database:GameDBA')
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'lists a database that was dropped and checked with its database: id in the rollback record' {
        # Mutation: put the bare names back into RestoredItems of the combined rollback -> Rollback.Items holds 'GameDBA'.
        $fx = New-F130Fixture -Name 's6b'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Install-F130Mocks -Fixture $fx
        Mock Save-Xml { throw 'disk full' }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        @($result.Rollback.Items) | Should -Contain 'database:GameDBA'
        @($result.Rollback.Items) | Should -Not -Contain 'GameDBA'
        $fx.State.Exists['GameDBA'] | Should -BeFalse
    }

    It 'does not list the same database twice as unknown when its drop failed and its state is also unverified' {
        # Mutation: remove the Select-Object -Unique on the unknown list of the creation-failure result -> Assert-TpmTransactionResult throws "duplicate item".
        $fx = New-F130Fixture -Name 's6c'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.FailDrop.Add('GameDBA') | Out-Null
        Install-F130Mocks -Fixture $fx
        Mock New-PostgresDatabaseFromBackup {
            param($DbName, $Encoding, $BackupFile, $SuperPasswordPlain, [scriptblock]$BeforeCreate)
            # createdb may have run, but its state was never verified at the mutation boundary: the database is a rollback candidate AND unknown.
            $script:F130State.Exists[$DbName] = $true
            [pscustomobject]@{ Succeeded = $false; MutationAttempted = $true; DatabaseMayExist = $true; Error = 'the state could not be checked'; PreMutationState = [pscustomobject]@{ Verified = $false; Exists = $null }; PostMutationState = $null; FinalVerification = [pscustomobject]@{ Attempted = $false; Passed = $false; Exists = $null }; Commands = @(); Database = $DbName }
        }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        @((Get-F130Mutation -Result $result).UnknownItems) | Should -Be @('database:GameDBA')
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }
}

Describe 'FIX130 S10 the database-creation phase fails closed' {
    It 'rolls back what this run created, and returns a result, when an error is raised outside the per-database try' {
        # Mutation: remove the outer catch of the creation phase -> the exception leaves Invoke-PostgresGameSetup, no result, GameDBA stays.
        $fx = New-F130Fixture -Name 's10a'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $null = New-F130Profile -Fixture $fx -Name 'BGame' -DbName 'GameDBB'
        Install-F130Mocks -Fixture $fx
        Mock Write-TpmCompactExtractionProgress { if ($Label -eq 'PostgreSQL database creation' -and $Current -eq 2 -and -not $Complete) { throw 'unexpected progress failure' } }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        $result.Summary | Should -BeExactly 'Setup stopped. Everything was put back the way it was, and checked.'
        @(Get-F130Calls -Tool 'dropdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
        $fx.State.Exists['GameDBA'] | Should -BeFalse
        @(Get-F130Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        ($fx.State.Log -join "`n") | Should -Match 'database creation phase stopped unexpectedly'
    }

    It 'reports a failure before any database was touched as a failure before the change, not as an unknown state' {
        # Mutation: treat "creation not started" like "creation result unavailable" (preMutationUnknown stays true) -> ACTION_REQUIRED / UNKNOWN.
        $fx = New-F130Fixture -Name 's10b'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Install-F130Mocks -Fixture $fx
        Mock Write-TpmCompactExtractionProgress { if ($Label -eq 'PostgreSQL database creation' -and $Current -eq 1 -and -not $Complete) { throw 'unexpected progress failure' } }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        @(Get-F130Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F130Calls -Tool 'dropdb.exe').Count | Should -Be 0
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'rolls back a database whose creation was started when no creation result came back (the journal note proves it may exist)' {
        # Mutation: ignore the journal note in the failure result (journalInFlight stays false) -> the database is not dropped, outcome ACTION_REQUIRED.
        $fx = New-F130Fixture -Name 's10c'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Install-F130Mocks -Fixture $fx
        Mock New-PostgresDatabaseFromBackup {
            param($DbName, $Encoding, $BackupFile, $SuperPasswordPlain, [scriptblock]$BeforeCreate)
            & $BeforeCreate $DbName
            $script:F130State.Exists[$DbName] = $true
            throw 'stopped between createdb and the result'
        }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        @(Get-F130Calls -Tool 'dropdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
        $fx.State.Exists['GameDBA'] | Should -BeFalse
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'reports a stop (Ctrl+C) that was rolled back and checked as a cancel' {
        # Mutation: do not detect the stop in the creation-phase catch -> Cancelled is not set. (A real PipelineStoppedException would end the
        # test run itself, so the detection helper is replaced; its real behavior is tested separately below.)
        $fx = New-F130Fixture -Name 's10d'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Mock Test-TpmErrorIsPipelineStop { $true }
        Install-F130Mocks -Fixture $fx
        Mock New-PostgresDatabaseFromBackup {
            param($DbName, $Encoding, $BackupFile, $SuperPasswordPlain, [scriptblock]$BeforeCreate)
            & $BeforeCreate $DbName
            $script:F130State.Exists[$DbName] = $true
            throw 'stopped between createdb and the result'
        }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        [bool]$result.Cancelled | Should -BeTrue
        $fx.State.Exists['GameDBA'] | Should -BeFalse
    }

    It 'finds a stop inside a nested error (Test-TpmErrorIsPipelineStop)' {
        # Mutation: look only at the outer exception, not its inner exceptions -> the wrapped stop is missed.
        $inner = [System.Management.Automation.PipelineStoppedException]::new()
        $wrapped = [System.InvalidOperationException]::new('wrapper', $inner)
        Test-TpmErrorIsPipelineStop -ErrorRecord ([System.Management.Automation.ErrorRecord]::new($wrapped, 'x', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)) | Should -BeTrue
        Test-TpmErrorIsPipelineStop -ErrorRecord ([System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new('plain'), 'x', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)) | Should -BeFalse
    }
}

Describe 'FIX130 S11 the journal of the databases a setup run creates' {
    It 'has the database on disk, named with stage Creating, before createdb runs' {
        # Mutation: do not call the BeforeCreate journal hook before createdb (or write the journal after createdb) -> the file is absent at createdb time.
        $fx = New-F130Fixture -Name 's11a'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $atCreate = $fx.State.JournalAtCreate['GameDBA']
        $atCreate | Should -Not -BeNullOrEmpty
        $journal = @(ConvertFrom-PostgresSetupJournalText -Text $atCreate)
        $journal.Count | Should -Be 1
        $journal[0].Database | Should -BeExactly 'GameDBA'
        $journal[0].Stage | Should -BeExactly 'Creating'
        $atCreate | Should -Not -Match 'fixture-password'
    }

    It 'clears the journal after a verified success' {
        # Mutation: do not clear the journal after the final verification -> the file stays.
        $fx = New-F130Fixture -Name 's11b'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse
    }

    It 'clears the journal after a verified rollback (creation failure and profile-write failure)' {
        # Mutation: do not clear the journal after Restore-PostgresSetupCreatedDatabases verified the drop -> the file stays.
        $fx = New-F130Fixture -Name 's11c'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $null = New-F130Profile -Fixture $fx -Name 'BGame' -DbName 'GameDBB'
        $fx.State.FailCreate.Add('GameDBB') | Out-Null
        Install-F130Mocks -Fixture $fx
        $failedCreation = Invoke-F130Setup -Fixture $fx
        $failedCreation.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse

        $fx2 = New-F130Fixture -Name 's11c2'
        $null = New-F130Profile -Fixture $fx2 -Name 'AGame' -DbName 'GameDBA'
        Install-F130Mocks -Fixture $fx2
        Mock Save-Xml { throw 'disk full' }
        $failedProfile = Invoke-F130Setup -Fixture $fx2
        $failedProfile.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        [System.IO.File]::Exists($fx2.State.JournalPath) | Should -BeFalse
    }

    It 'keeps the entry in the journal when the rollback drop could not be verified' {
        # Mutation: clear the whole journal whatever the rollback result is -> the unverified database loses its record.
        $fx = New-F130Fixture -Name 's11d'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.FailDrop.Add('GameDBA') | Out-Null
        Install-F130Mocks -Fixture $fx
        Mock Save-Xml { throw 'disk full' }

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $found = Read-PostgresSetupJournal -Path $fx.State.JournalPath
        $found.Status | Should -BeExactly 'Present'
        @($found.Entries | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
    }

    It 'does not create a database when its journal note cannot be written' {
        # Mutation: ignore a failed journal write (swallow it in the BeforeCreate hook) -> createdb runs with no note on disk.
        $fx = New-F130Fixture -Name 's11e'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Install-F130Mocks -Fixture $fx
        Mock Save-PostgresSetupJournal { throw 'no space left' }

        $result = Invoke-F130Setup -Fixture $fx

        @(Get-F130Calls -Tool 'createdb.exe').Count | Should -Be 0
        $fx.State.Exists.ContainsKey('GameDBA') | Should -BeFalse
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'safety note'
    }

    It 'drops the unfinished database of an earlier run and rebuilds it, and reports the game as created' {
        # Mutation: plan a journal-named existing database as present (DbExists stays true) -> no drop, no createdb, the game is reported as already set up.
        $fx = New-F130Fixture -Name 's11f2'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.Exists['GameDBA'] = $true
        Write-F130Journal -Fixture $fx -Entries @(, @('GameDBA', 'Creating'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($fx.State.Events | Where-Object { $_ -in @('dropdb:GameDBA', 'createdb:GameDBA') }) | Should -Be @('dropdb:GameDBA', 'createdb:GameDBA')
        $fx.State.Exists['GameDBA'] | Should -BeTrue
        @($result.GameOutcomes | ForEach-Object { $_.Outcome }) | Should -Be @('CreatedFromBackup')
        (@($result.Warnings) -join "`n") | Should -Match 'Database GameDBA: an earlier setup stopped while building it'
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'removes nothing when an unfinished database cannot be built again because the game backup is not found' {
        # Mutation: let the journal recovery drop it anyway -> the database is gone and the game cannot be rebuilt.
        $fx = New-F130Fixture -Name 's11n'
        $file = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA' -BackupNames @()
        $text = [System.IO.File]::ReadAllText($file).Replace('</ConfigValues>', '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Automatically create Database</FieldName><FieldValue>1</FieldValue></FieldInformation></ConfigValues>')
        [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
        $fx.State.Exists['GameDBA'] = $true
        Write-F130Journal -Fixture $fx -Entries @(, @('GameDBA', 'Creating'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -Not -BeExactly 'SUCCEEDED'
        @($fx.State.Events | Where-Object { $_ -like 'dropdb:*' }) | Should -BeNullOrEmpty
        $fx.State.Exists['GameDBA'] | Should -BeTrue
    }

    It 'reads a game path that has spaces around it' {
        $fx = New-F130Fixture -Name 's11p'
        $file = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $text = [System.IO.File]::ReadAllText($file).Replace('<GamePath>', '<GamePath>  ').Replace('</GamePath>', '  </GamePath>')
        [System.IO.File]::WriteAllText($file, $text, (New-Object System.Text.UTF8Encoding $false))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.GameOutcomes | ForEach-Object { $_.Outcome }) | Should -Be @('CreatedFromBackup')
    }

    It 'says in plain words what it found and what it will do, before it changes anything' {
        # Mutation: remove the plain-words notice -> the screen has no "An earlier setup did not finish." lines.
        $fx = New-F130Fixture -Name 's11g'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.Exists['GameDBA'] = $true
        Write-F130Journal -Fixture $fx -Entries @(, @('GameDBA', 'Creating'))
        Install-F130Mocks -Fixture $fx

        $null = Invoke-F130Setup -Fixture $fx

        $screen = $fx.State.Screen -join "`n"
        $screen | Should -Match 'An earlier setup did not finish\.'
        $screen | Should -Match 'It was building 1 game database\. TeknoParrot Manager made it itself, and it may be only partly filled\.'
        $screen | Should -Match 'will remove only that unfinished copy and build it again\. Nothing else is touched\.'
        $screen | Should -Not -Match 'GameDBA' -Because 'the database name belongs in Details and the log, not on the plain screen'
    }

    It 'never drops a database the journal does not name with stage Creating' {
        # Mutation: drop every existing database that a profile uses (or every journal entry whatever its stage) -> GameDBOther / GameDBDone are dropped.
        $fx = New-F130Fixture -Name 's11h'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $null = New-F130Profile -Fixture $fx -Name 'OtherGame' -DbName 'GameDBOther'
        $null = New-F130Profile -Fixture $fx -Name 'DoneGame' -DbName 'GameDBDone'
        $fx.State.Exists['GameDBA'] = $true
        $fx.State.Exists['GameDBOther'] = $true
        $fx.State.Exists['GameDBDone'] = $true
        Write-F130Journal -Fixture $fx -Entries @(@('GameDBA', 'Creating'), @('GameDBDone', 'Created'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F130Calls -Tool 'dropdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
        $fx.State.Exists['GameDBOther'] | Should -BeTrue
        $fx.State.Exists['GameDBDone'] | Should -BeTrue
        (@($result.Warnings) -join "`n") | Should -Match 'Database GameDBDone: an earlier setup finished building it'
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse
    }

    It 'keeps a complete database an earlier run finished and clears its note when nothing else is to do' {
        # Mutation: treat stage Created like Creating -> the complete database is dropped.
        $fx = New-F130Fixture -Name 's11i'
        $null = New-F130Profile -Fixture $fx -Name 'DoneGame' -DbName 'GameDBDone'
        $fx.State.Exists['GameDBDone'] = $true
        Write-F130Journal -Fixture $fx -Entries @(, @('GameDBDone', 'Created'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        @(Get-F130Calls -Tool 'dropdb.exe').Count | Should -Be 0
        $fx.State.Exists['GameDBDone'] | Should -BeTrue
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'stops before any change, and leaves the file alone, when the journal cannot be read' {
        # Mutation: ignore an unreadable journal and go on (or delete it) -> databases are created over an unknown earlier state.
        $fx = New-F130Fixture -Name 's11j'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        [System.IO.File]::WriteAllText($fx.State.JournalPath, '{ this is not a journal', (New-Object System.Text.UTF8Encoding $false))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'POSTGRES_SETUP_JOURNAL_UNREADABLE'
        $result.Summary | Should -Match 'cannot read'
        @(Get-F130Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F130Calls -Tool 'dropdb.exe').Count | Should -Be 0
        [System.IO.File]::ReadAllText($fx.State.JournalPath) | Should -BeExactly '{ this is not a journal'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'asks for attention, creates nothing and keeps the entry when the unfinished database cannot be dropped and checked' {
        # Mutation: go on to create the database after a failed recovery drop -> createdb runs over the half-restored database.
        $fx = New-F130Fixture -Name 's11k'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.Exists['GameDBA'] = $true
        $fx.State.FailDrop.Add('GameDBA') | Out-Null
        Write-F130Journal -Fixture $fx -Entries @(, @('GameDBA', 'Creating'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $result.ReasonCode | Should -BeExactly 'POSTGRES_SETUP_JOURNAL_RECOVERY_UNVERIFIED'
        @((Get-F130Mutation -Result $result).UnknownItems) | Should -Be @('database:GameDBA')
        @(Get-F130Calls -Tool 'createdb.exe').Count | Should -Be 0
        (Read-PostgresSetupJournal -Path $fx.State.JournalPath).Status | Should -BeExactly 'Present'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'clears a note for a database that is already gone, without dropping anything' {
        # Mutation: call dropdb for every journal entry without looking at the database -> a dropdb call appears.
        $fx = New-F130Fixture -Name 's11l'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Write-F130Journal -Fixture $fx -Entries @(, @('GameDBGone', 'Creating'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F130Calls -Tool 'dropdb.exe').Count | Should -Be 0
        [System.IO.File]::Exists($fx.State.JournalPath) | Should -BeFalse
    }

    It 'reads only journals it fully recognizes' -TestCases @(
        @{ Why = 'another schema'; Text = '{"Schema":"Other","Entries":[]}' }
        @{ Why = 'an unsafe database name'; Text = '{"Schema":"TPM.PostgresSetupJournal.v1","Entries":[{"Database":"x; drop","Stage":"Creating"}]}' }
        @{ Why = 'an unknown stage'; Text = '{"Schema":"TPM.PostgresSetupJournal.v1","Entries":[{"Database":"GameDBA","Stage":"Done"}]}' }
        @{ Why = 'a database listed twice'; Text = '{"Schema":"TPM.PostgresSetupJournal.v1","Entries":[{"Database":"GameDBA","Stage":"Creating"},{"Database":"GameDBA","Stage":"Created"}]}' }
        @{ Why = 'text that is not JSON'; Text = 'nope' }
    ) {
        # Mutation: accept any entry shape (skip the validation in ConvertFrom-PostgresSetupJournalText) -> an unsafe name or stage reaches a drop.
        { ConvertFrom-PostgresSetupJournalText -Text $Text } | Should -Throw
    }

    It 'writes the journal atomically and reads it back, and removes the file when no entry is left' {
        # Mutation: write straight over the file or keep an empty file -> the read-back or the removal check fails.
        $path = Join-Path $TestDrive ('f130-journal-' + [guid]::NewGuid().ToString('N') + '.json')
        Mock Assert-PostgresRecoveryDirectoryAcl {}
        Save-PostgresSetupJournal -Path $path -RunId 'abc' -Entries @([pscustomobject]@{ Database = 'GameDBA'; Stage = 'Creating'; UpdatedUtc = 'now' }, [pscustomobject]@{ Database = 'GameDBB'; Stage = 'Created'; UpdatedUtc = 'now' })
        $found = Read-PostgresSetupJournal -Path $path
        $found.Status | Should -BeExactly 'Present'
        @($found.Entries | ForEach-Object { $_.Database + ':' + $_.Stage }) | Should -Be @('GameDBA:Creating', 'GameDBB:Created')
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -Filter ((Split-Path -Leaf $path) + '.*.tmp')).Count | Should -Be 0
        Save-PostgresSetupJournal -Path $path -RunId 'abc' -Entries @()
        [System.IO.File]::Exists($path) | Should -BeFalse
        (Read-PostgresSetupJournal -Path $path).Status | Should -BeExactly 'None'
    }
}

Describe 'FIX130 S12 reinitialize uses the newest backup file of the game and names it' {
    BeforeEach {
        $script:F130Screen = New-Object System.Collections.Generic.List[string]
        $script:F130Log = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:F130Log.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host { [void]$script:F130Screen.Add(((@($Object) | ForEach-Object { [string]$_ }) -join ' ')) }
    }

    It 'uses the newest backup file of the game, and none when there is none' {
        # Mutation: pick no file when there are several -> the two-file game gets an empty BackupFile. Mutation: call Get-PostgresBackupFile -> a name-number guess.
        $fx = New-F130Fixture -Name 's12a'
        $null = New-F130Profile -Fixture $fx -Name 'OneGame' -DbName 'GameDBOne' -BackupNames @('0001.backup')
        $null = New-F130Profile -Fixture $fx -Name 'TwoGame' -DbName 'GameDBTwo' -BackupNames @('0001.backup', '0002.backup')
        $null = New-F130Profile -Fixture $fx -Name 'NoGame' -DbName 'GameDBNo' -BackupNames @()

        $plans = @(Get-PostgresReinitializePlansFromProfiles -UserProfilesDir $fx.Profiles)

        $one = @($plans | Where-Object { $_.Database -ceq 'GameDBOne' })[0]
        $two = @($plans | Where-Object { $_.Database -ceq 'GameDBTwo' })[0]
        $none = @($plans | Where-Object { $_.Database -ceq 'GameDBNo' })[0]
        [System.IO.Path]::GetFileName([string]$one.BackupFile) | Should -BeExactly '0001.backup'
        $one.BackupCandidateCount | Should -Be 1
        [System.IO.Path]::GetFileName([string]$two.BackupFile) | Should -BeExactly '0002.backup'
        $two.BackupCandidateCount | Should -Be 2
        [string]$none.BackupFile | Should -BeExactly ''
        $none.BackupCandidateCount | Should -Be 0
    }

    It 'never plans a rebuild from the alternate backups folder' {
        # Who gets hurt: a user whose only spare dump sits in the alternate backups folder; a rebuild REPLACES their data with it.
        # Mutation: pass -IncludeAlternate in Get-PostgresReinitializePlansFromProfiles -> BackupFile is the spare file.
        $fx = New-F130Fixture -Name 's12alt'
        $null = New-F130Profile -Fixture $fx -Name 'AltGame' -DbName 'GameDBAlt' -BackupNames @()
        $altDir = Join-Path (Join-Path (Join-Path (Join-Path $fx.Root 'Game-AltGame') 'pg_backup') 'alternate backups') 'pg_backup'
        New-Item -ItemType Directory -Path $altDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $altDir '1000-a-backup'), 'alt')

        $plan = @(Get-PostgresReinitializePlansFromProfiles -UserProfilesDir $fx.Profiles)[0]

        [string]$plan.BackupFile | Should -BeExactly ''
        $plan.BackupCandidateCount | Should -Be 0
    }

    It 'shows the file name, in plain words, on the confirm screen and keeps the full path off it' {
        # Mutation: remove the "It will use this file" line from the confirm screen -> the name is not shown.
        $fx = New-F130Fixture -Name 's12b'
        $null = New-F130Profile -Fixture $fx -Name 'OneGame' -DbName 'GameDBOne' -BackupNames @('0001.backup')
        Mock Read-HostSafe { 'no' }

        $result = Invoke-PostgresReinitializeChoice -FailureDiagnoses @([pscustomobject]@{ Database = 'GameDBOne' }) -UserProfilesDir $fx.Profiles -ConfigPath 'config.json' -ScriptPath 'script.ps1' -TpRoot $fx.Root -SuperPasswordPlain 'fixture-password' -RecoveryBackup $null

        $result.Outcome | Should -BeExactly 'Cancelled'
        $screen = $script:F130Screen -join "`n"
        $screen | Should -Match 'It will use this file that came with the game: 0001\.backup'
        $screen | Should -Not -Match ([regex]::Escape($fx.Root))
        ($script:F130Log -join "`n") | Should -Match 'would be rebuilt from .*0001\.backup'
    }

    It 'tells the user which of several starting files will be used and whether it is the newest' {
        # Mutation: drop the line -> a beginner is not told that the game came with several files; claim "newest" for names without a time -> untrue text.
        $fx = New-F130Fixture -Name 's12c'
        $null = New-F130Profile -Fixture $fx -Name 'TwoGame' -DbName 'GameDBTwo' -BackupNames @('0905-a', '1840-a')
        $null = New-F130Profile -Fixture $fx -Name 'NoTimeGame' -DbName 'GameDBNoTime' -BackupNames @('backup-old', 'backup-new')
        Mock Read-HostSafe { 'no' }

        $result = Invoke-PostgresReinitializeChoice -FailureDiagnoses @([pscustomobject]@{ Database = 'GameDBTwo' }, [pscustomobject]@{ Database = 'GameDBNoTime' }) -UserProfilesDir $fx.Profiles -ConfigPath 'config.json' -ScriptPath 'script.ps1' -TpRoot $fx.Root -SuperPasswordPlain 'fixture-password' -RecoveryBackup $null

        $result.Outcome | Should -BeExactly 'Cancelled'
        $screen = $script:F130Screen -join "`n"
        $screen | Should -Match 'It will use this file that came with the game: 1840-a'
        $screen | Should -Match 'The game came with 2 such files; this is the newest one\.'
        $screen | Should -Match 'It will use this file that came with the game: backup-old'
        $screen | Should -Match 'The game came with 2 such files and their names do not say which is newest; this one was picked by name\.'
        $screen | Should -Not -Match 'cannot tell which one belongs'
    }
}

Describe 'FIX130 N6 the restore message claims only what was checked' {
    It 'does not say that the tables and their rows were restored, and still counts the known warnings' {
        # Mutation: put "The tables and their rows were restored." back into the accepted-warning text -> the first assertion fails.
        Mock Invoke-Postgres83RestoreCommand {
            [pscustomobject]@{ Tool = 'pg_restore.exe'; ExitCode = 1; Succeeded = $false; TimedOut = $false; Output = 'known warnings'; Interpretation = [pscustomobject]@{ Accepted = $true; Reason = 'KnownWarningsOnly'; KnownWarningCount = 3; ConstraintNames = @('fk_a', 'fk_b', 'fk_c') } }
        }
        $log = New-Object System.Collections.Generic.List[object]

        $command = Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDBA', 'backup.file') -SuperPasswordPlain 'fixture-password' -CommandLog $log -DatabaseName 'GameDBA' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true

        $command.AcceptedWarnings | Should -Not -Match 'tables and their rows'
        $command.AcceptedWarnings | Should -Match '^Finished with a known limitation: 3 links between tables in the game''s own backup could not be made\.'
        $command.AcceptedWarnings | Should -Match 'The restore tool reported no other problem\.$'
        $command.AcceptedWarningCount | Should -Be 3
    }
}

Describe 'FIX130 S11 recovery accounting' {
    It 'counts every database the recovery dropped as changed, even when a later one could not be dropped' {
        # Mutation: record only recovered databases that are not planned again -> the dropped GameDBA shows as unattempted in the failure result.
        $fx = New-F130Fixture -Name 's11m'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $null = New-F130Profile -Fixture $fx -Name 'BGame' -DbName 'GameDBB'
        $fx.State.Exists['GameDBA'] = $true
        $fx.State.Exists['GameDBB'] = $true
        $fx.State.FailDrop.Add('GameDBB') | Out-Null
        Write-F130Journal -Fixture $fx -Entries @(@('GameDBA', 'Creating'), @('GameDBB', 'Creating'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $mutation = Get-F130Mutation -Result $result
        @($mutation.UnknownItems) | Should -Be @('database:GameDBB')
        @($mutation.CompletedItems) | Should -Contain 'database:GameDBA'
        @($mutation.UnattemptedItems) | Should -Not -Contain 'database:GameDBA'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    It 'does not say a complete database was kept when it is gone' {
        # Mutation: note every Created entry as kept whether or not the database exists -> the false "was kept" note appears.
        $fx = New-F130Fixture -Name 's11n'
        $null = New-F130Profile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        Write-F130Journal -Fixture $fx -Entries @(, @('GameDBA', 'Created'))
        Install-F130Mocks -Fixture $fx

        $result = Invoke-F130Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        (@($result.Warnings) -join "`n") | Should -Not -Match 'was kept'
        @(Get-F130Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDBA')
    }
}
