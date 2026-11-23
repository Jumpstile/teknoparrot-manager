#Requires -Module Pester

# FIX69 PostgreSQL setup, absent database, profile says "Automatically create Database"
# = 1. Owner finding (2026-11-03, his real library): TeknoParrot's own creation is not
# hands-free, it asks the user to browse for the database backup file. Rule (tightened by FIXDB27): TeknoParrot Manager
# creates and restores the database from the game's bundled backup whatever the profile's auto-create value is (1, 0 or
# missing), then checks it with the game's own settings. Nothing is left to TeknoParrot: when the game has no bundled backup,
# or its executable cannot be found, setup stops with a plain reason. When the game ships several candidate files, the newest
# one is used (N18A, N18B). The alternate backups folder is used when the game has no other backup.
#
# The production script is parsed and only its function definitions are dot-sourced;
# no top-level product code runs in this process. The PostgreSQL 8.3 client tools are
# replaced by one in-memory fake (Invoke-Postgres83RestoreCommand and
# Get-PostgresDatabaseState are mocked), so no PostgreSQL server, service, registry or
# user configuration is touched. Every file lives under TestDrive and every profile,
# game folder and backup is a synthetic fixture. Each It names the product mutation
# that makes it fail.

BeforeAll {
    $script:Fix69PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix69PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX69 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix69FunctionFile = Join-Path $TestDrive 'tpm-fix69-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix69FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix69FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force

    # Hardware and progress-line access is external to these tests.
    function Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'NVIDIA'; Name = 'isolated fixture' } }
    function Suspend-TpmProgressLine {}
    function Resume-TpmProgressLine {}

    function New-F69Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f69-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
        $bin = Join-Path $root 'bin'
        $evidence = Join-Path $root 'evidence'
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $bin, $evidence, $profiles, (Join-Path $root 'GameProfiles') -Force | Out-Null
        foreach ($tool in @(Get-Postgres83RestoreToolNames)) { New-Item -ItemType File -Path (Join-Path $bin $tool) -Force | Out-Null }
        $state = [pscustomobject]@{
            Exists = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::Ordinal)
            Calls = New-Object System.Collections.Generic.List[object]
            Events = New-Object System.Collections.Generic.List[string]
            Log = New-Object System.Collections.Generic.List[string]
            Screen = New-Object System.Collections.Generic.List[string]
            FailRestore = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            StateChecks = New-Object System.Collections.Generic.List[string]
            NotReady = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            Empty = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        }
        return [pscustomobject]@{ Root = $root; Bin = $bin; Evidence = $evidence; Profiles = $profiles; State = $state }
    }

    # Profile with a Postgres category. -AutoCreate '' omits "Automatically create
    # Database". -BackupFiles names the files put into the game's pg_backup folder
    # (none = no pg_backup folder). Path starts blank so setup fills it; -Complete
    # fills every field the way a finished setup leaves it.
    function New-F69Profile {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$DbName,
            [string]$GameName = '',
            [string]$Pass = '',
            [string]$AutoCreate = '1',
            [string[]]$BackupFiles = @(),
            [switch]$NoGameExe,
            [switch]$Complete
        )
        $label = if ($GameName) { $GameName } else { $Name }
        $gameDir = Join-Path $Fixture.Root ('Game-' + $Name)
        New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
        $exe = Join-Path $gameDir 'game.exe'
        if (-not $NoGameExe) { New-Item -ItemType File -Path $exe -Force | Out-Null }
        if ($BackupFiles.Count -gt 0) {
            $backupDir = Join-Path $gameDir 'pg_backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            foreach ($backupName in $BackupFiles) {
                [System.IO.File]::WriteAllText((Join-Path $backupDir $backupName), ('synthetic bundled backup ' + $backupName), (New-Object System.Text.UTF8Encoding $false))
            }
        }
        $fields = New-Object System.Collections.Generic.List[object]
        [void]$fields.Add(@('Path', $(if ($Complete) { 'C:\fixture\pg\bin\' } else { '' })))
        [void]$fields.Add(@('Address', $(if ($Complete) { '127.0.0.1' } else { '' })))
        [void]$fields.Add(@('Port', $(if ($Complete) { '5432' } else { '' })))
        [void]$fields.Add(@('DbName', $DbName))
        [void]$fields.Add(@('User', $(if ($Complete) { 'postgres' } else { '' })))
        [void]$fields.Add(@('Pass', $Pass))
        if ($AutoCreate -ne '') { [void]$fields.Add(@('Automatically create Database', $AutoCreate)) }
        # The game path goes into XML text: escape it so a valid folder name with an ampersand (A&B) still gives well-formed XML.
        $xml = '<GameProfile><GameName>' + $label + '</GameName><GamePath>' + [System.Security.SecurityElement]::Escape([string]$exe) + '</GamePath><ConfigValues>'
        foreach ($field in $fields) {
            $xml += '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $field[0] + '</FieldName><FieldValue>' + $field[1] + '</FieldValue></FieldInformation>'
        }
        $xml += '</ConfigValues></GameProfile>'
        $file = Join-Path $Fixture.Profiles ($Name + '.xml')
        [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $file
    }

    function New-F69CommandResult {
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

    # In-memory PostgreSQL 8.3 client: records every call and changes the fake server
    # state the way the real createdb/dropdb/pg_restore would.
    function Invoke-F69FakeCommand {
        param([string]$ToolName, [string[]]$Arguments)
        $state = $script:F69State
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
            return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($ToolName + ' (PostgreSQL) 8.3.23'))
        }
        if ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc') {
            $query = [string]$Arguments[$Arguments.Count - 1]
            if ($query -match 'count\(\*\)') {
                if ($state.NotReady.Contains($database)) { return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 2 -Output 'psql: FATAL:  password authentication failed for user "postgres"') }
                if ($state.Empty.Contains($database)) { return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '0') }
                return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '24')
            }
            $wanted = ''
            if ($query -match "lower\('([^']+)'\)\s*$") { $wanted = $Matches[1] }
            $names = @($state.Exists.Keys | Where-Object { $state.Exists[$_] -and [string]::Equals($_, $wanted, [System.StringComparison]::OrdinalIgnoreCase) })
            return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($names -join "`n"))
        }
        if ($ToolName -eq 'psql.exe') { return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -contains '--list') { return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe') {
            [void]$state.Events.Add('pg_restore:' + $database)
            if ($state.FailRestore.Contains($database)) { return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 5 -Output 'restore failed') }
            [void]$state.Empty.Remove($database)
            return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'createdb.exe') {
            [void]$state.Events.Add('createdb:' + $database)
            $state.Exists[$database] = $true
            return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'dropdb.exe') {
            [void]$state.Events.Add('dropdb:' + $database)
            $state.Exists[$database] = $false
            return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 3 -Output 'unexpected fake tool')
    }

    function Install-F69Mocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F69State = $Fixture.State
        $script:F69Recovery = [pscustomobject]@{ Path = $Fixture.Evidence; ConfigBackups = @(); Verified = $true; ProfileBackups = @() }
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log { [void]$script:F69State.Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F69State.Screen.Add(([string]($Object -join ' '))) }
        Mock Get-ConsoleContentWidth { return 120 }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock New-PostgresRecoveryBackup { [void]$script:F69State.Events.Add('backup'); $script:F69Recovery }
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            # FIX129: the fake runs the caller's -Interpret block on its text, like the real runner does.
            Add-FakePostgresInterpretation -Command (Invoke-F69FakeCommand -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            [void]$script:F69State.StateChecks.Add($DbName)
            $exists = $false
            if ($script:F69State.Exists.ContainsKey($DbName)) { $exists = [bool]$script:F69State.Exists[$DbName] }
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
    }

    function Get-F69Calls {
        param([Parameter(Mandatory)][string]$Tool)
        return @($script:F69State.Calls | Where-Object { $_.Tool -eq $Tool -and $_.Arguments -notcontains '--version' })
    }

    function Get-F69RestoreCalls {
        return @($script:F69State.Calls | Where-Object { $_.Tool -eq 'pg_restore.exe' -and $_.Arguments -notcontains '--list' -and $_.Arguments -notcontains '--version' })
    }

    function Get-F69Value {
        param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$Field)
        return (Get-PostgresFieldValue (Read-Xml $File) $Field)
    }

    function Invoke-F69Setup {
        param([Parameter(Mandatory)]$Fixture)
        return (Invoke-PostgresGameSetup -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password')
    }

    # The PostgreSQL block of the Library Health details (the D key), as one text.
    function Get-F69HealthPostgresDetail {
        param([Parameter(Mandatory)]$Result)
        $block = @(Get-TpmLibraryHealthDetailBlocks -Result $Result | Where-Object { $_.Heading -eq 'PostgreSQL' })
        if ($block.Count -ne 1) { throw "Expected one PostgreSQL details block; found $($block.Count)." }
        return (@($block[0].Lines) -join "`n")
    }

    # One string with the indent and the wrapping removed, so a sentence can be found
    # whatever the width broke it into.
    function Get-F69Screen {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)]$Result)
        $Fixture.State.Screen.Clear()
        Write-TpmPostgresSetupResult -Result $Result
        return ((@($Fixture.State.Screen.ToArray()) -join ' ') -replace '\s+', ' ')
    }

    function New-F69GameFolder {
        param([Parameter(Mandatory)][string]$Name, [string[]]$Files = @(), [string]$Subfolder = '')
        $folder = Join-Path $TestDrive ('f69-resolver-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
        $backupDir = Join-Path $folder 'pg_backup'
        if ($Subfolder) { $backupDir = Join-Path $backupDir $Subfolder }
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $folder 'game.exe') -Force | Out-Null
        if ($Files.Count -gt 0) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            foreach ($f in $Files) { [System.IO.File]::WriteAllText((Join-Path $backupDir $f), 'synthetic') }
        }
        return $folder
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix69PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX69 auto-create = 1 with exactly one bundled backup is created and restored by TeknoParrot Manager' {
    # Mutation: leave the database to TeknoParrot after the backup is found (the old rule "auto-create 1 always defers") ->
    # no createdb/pg_restore call, DbCreated is 0.
    It 'creates GameDB19, restores the one bundled backup, fills the profile and takes the protected backup first' {
        $fx = New-F69Fixture -Name 'create'
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup')
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 1
        $creates = @(Get-F69Calls -Tool 'createdb.exe')
        $creates.Count | Should -Be 1
        $creates[0].Database | Should -BeExactly 'GameDB19'
        $restores = @(Get-F69RestoreCalls)
        $restores.Count | Should -Be 1
        $restores[0].Database | Should -BeExactly 'GameDB19'
        [string]$restores[0].Arguments[-1] | Should -Match 'Game-GoldenTeeLive2019[\\/]pg_backup[\\/]0001\.backup$'
        @($fx.State.Events | Where-Object { $_ -in @('backup', 'createdb:GameDB19', 'pg_restore:GameDB19') }) | Should -Be @('backup', 'createdb:GameDB19', 'pg_restore:GameDB19')
        @(Get-F69Calls -Tool 'dropdb.exe').Count | Should -Be 0
        $fx.State.Exists['GameDB19'] | Should -BeTrue
        (Get-F69Value -File $file -Field 'Path') | Should -BeExactly ($fx.Bin.TrimEnd('\') + '\')
        (Get-F69Value -File $file -Field 'Address') | Should -BeExactly '127.0.0.1'
        (Get-F69Value -File $file -Field 'Port') | Should -BeExactly '5432'
        (Get-F69Value -File $file -Field 'User') | Should -BeExactly 'postgres'
        (Get-F69Value -File $file -Field 'Pass') | Should -BeExactly 'fixture-password'
        @($result.TechnicalDetails.DatabaseCreationReceipts)[0].Mode | Should -BeExactly 'RestoreBundledBackup'
        (@($result.Warnings) -join ' | ') | Should -Match 'GameDB19\): the database did not exist\. TeknoParrot Manager created it and restored the backup bundled with the game'
        (@($result.Warnings) -join ' | ') | Should -Not -Match 'deferred to TeknoParrot'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        ($result.TechnicalDetails | ConvertTo-Json -Depth 12) | Should -Not -Match 'fixture-password'
    }

    # Mutation: classify the game by the auto-create value instead of what setup did -> the game is not in the "Ready" line.
    It 'puts the game in the Ready group of the result screen' {
        $fx = New-F69Fixture -Name 'screen'
        [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup'))
        Install-F69Mocks -Fixture $fx
        $result = Invoke-F69Setup -Fixture $fx

        $game = @($result.GameOutcomes)[0]
        $screen = Get-F69Screen -Fixture $fx -Result $result

        $game.Outcome | Should -BeExactly 'CreatedFromBackup'
        $screen | Should -Match ([regex]::Escape('Ready: Golden Tee Live 2019. The database was created from the game''s own backup and checked.'))
        $screen | Should -Not -Match '(?i)TeknoParrot will ask|click yes|start (it|the game|each game) once'
    }

    # Mutation: skip the drop of the database this run created after a failed restore, or
    # write the profile before the restore -> GameDB19 stays, or the profile bytes change.
    It 'drops the database it created when the restore fails, and leaves the profile as it was' {
        $fx = New-F69Fixture -Name 'rollback'
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup')
        $before = [System.IO.File]::ReadAllBytes($file)
        $fx.State.FailRestore.Add('GameDB19') | Out-Null
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        @(Get-F69Calls -Tool 'dropdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDB19')
        $fx.State.Exists['GameDB19'] | Should -BeFalse
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        $fx.State.Events.Contains('backup') | Should -BeTrue
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'Database GameDB19 could not be created'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        ($result.TechnicalDetails | ConvertTo-Json -Depth 12) | Should -Not -Match 'fixture-password'
    }

    # Mutation: skip the readiness check (or call a failed one a success) -> setup says SUCCEEDED for a database the game cannot open.
    It 'rolls everything back and says the game is not ready when the game cannot connect to its database' {
        $fx = New-F69Fixture -Name 'notready'
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup')
        $before = [System.IO.File]::ReadAllBytes($file)
        $fx.State.NotReady.Add('GameDB19') | Out-Null
        Install-F69Mocks -Fixture $fx
        # The fixture's recovery bundle holds no profile copies; this puts the saved original back the way the real restore does.
        $script:F69NotReadyFile = $file
        $script:F69NotReadyBefore = $before
        Mock Restore-PostgresProfileBackups { [System.IO.File]::WriteAllBytes($script:F69NotReadyFile, $script:F69NotReadyBefore); $true }

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        $result.Summary | Should -BeExactly 'A game database is not ready, so setup put everything back the way it was, and checked. Open Details to see which game and why.'
        @(Get-F69Calls -Tool 'dropdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDB19')
        $fx.State.Exists['GameDB19'] | Should -BeFalse
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        $reasons = @(Get-PostgresSetupFailureReasonLines -TransactionResult $result)
        ($reasons -join ' | ') | Should -Match 'Golden Tee Live 2019 \[GoldenTeeLive2019\] \(GameDB19\) is not ready: Could not connect with the settings saved in the game profile'
        ($reasons -join ' | ') | Should -Not -Match 'fixture-password'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    # Mutation: leave the readiness check out of the "nothing to change" path -> a database the game cannot open is reported ready.
    It 'also checks a database that was already there, and changes nothing when the game cannot connect to it' {
        $fx = New-F69Fixture -Name 'notready-existing'
        $fx.State.Exists['GameDB19'] = $true
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -Pass 'fixture-password' -Complete
        $xml = [System.IO.File]::ReadAllText($file).Replace('C:\fixture\pg\bin\', ($fx.Bin.TrimEnd('\') + '\'))
        [System.IO.File]::WriteAllText($file, $xml)
        $before = [System.IO.File]::ReadAllBytes($file)
        $fx.State.NotReady.Add('GameDB19') | Out-Null
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.Summary | Should -Match '^A game database is not ready, and TeknoParrot Manager changed nothing\.'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F69Calls -Tool 'dropdb.exe').Count | Should -Be 0
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match '\(GameDB19\) is not ready: Could not connect'
    }

    # Mutation: let the repeat run plan a second creation, or take a second protected
    # backup, or rewrite the profiles.
    It 'is a no-op on a repeat run: no second backup, no second creation, no profile rewrite' {
        $fx = New-F69Fixture -Name 'repeat'
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup')
        Install-F69Mocks -Fixture $fx
        $first = Invoke-F69Setup -Fixture $fx
        $first.Outcome | Should -BeExactly 'SUCCEEDED'
        $afterFirst = [System.IO.File]::ReadAllBytes($file)

        $second = Invoke-F69Setup -Fixture $fx

        $second.Outcome | Should -BeExactly 'NO_OP'
        $second.DbCreated | Should -Be 0
        [System.IO.File]::ReadAllBytes($file) | Should -Be $afterFirst
        @($fx.State.Events | Where-Object { $_ -eq 'backup' }).Count | Should -Be 1
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 1
        @(Get-F69RestoreCalls).Count | Should -Be 1
        @($second.GameOutcomes)[0].Outcome | Should -BeExactly 'AlreadyExisted'
    }

    # Mutation: skip the final database check for an auto-create 1 game (restore the old
    # "-and AutoCreate -ne $true" condition) -> the created database is looked up one time
    # fewer than the same game with auto-create 0.
    It 'checks the database it created at the end of setup exactly like it does for auto-create 0' {
        $checks = @{}
        foreach ($autoCreate in @('0', '1')) {
            $fx = New-F69Fixture -Name ('verify-' + $autoCreate)
            [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate $autoCreate -BackupFiles @('0001.backup'))
            Install-F69Mocks -Fixture $fx
            $result = Invoke-F69Setup -Fixture $fx
            $result.Outcome | Should -BeExactly 'SUCCEEDED'
            $checks[$autoCreate] = @($fx.State.StateChecks | Where-Object { $_ -ceq 'GameDB19' }).Count
        }
        $checks['1'] | Should -BeGreaterThan 2
        $checks['1'] | Should -Be $checks['0']
    }

    # Mutation: take the bundled backup for an existing database -> createdb/restore/drop
    # calls appear for GameDB19.
    It 'never touches a database that already exists, even when the game ships a backup' {
        $fx = New-F69Fixture -Name 'existing'
        $fx.State.Exists['GameDB19'] = $true
        [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup'))
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 0
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F69Calls -Tool 'dropdb.exe').Count | Should -Be 0
        @(Get-F69RestoreCalls).Count | Should -Be 0
        @($result.GameOutcomes)[0].Outcome | Should -BeExactly 'AlreadyExisted'
    }
}

Describe 'An existing database with no tables is filled from the game''s bundled backup' {
    # Mutation: treat an existing database as "already there" without counting its tables -> no restore, and the final check
    # fails with "Found 0 tables" for every game (the real dead end).
    It 'restores the bundled backup into the empty database, without creating or dropping it' {
        $fx = New-F69Fixture -Name 'empty-shell'
        $fx.State.Exists['GameDB19'] = $true
        $fx.State.Empty.Add('GameDB19') | Out-Null
        [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup'))
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F69Calls -Tool 'dropdb.exe').Count | Should -Be 0
        @(Get-F69RestoreCalls | ForEach-Object { $_.Database }) | Should -Be @('GameDB19')
        @($fx.State.Events | Where-Object { $_ -in @('backup', 'pg_restore:GameDB19') }) | Should -Be @('backup', 'pg_restore:GameDB19')
        $fx.State.Exists['GameDB19'] | Should -BeTrue
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    # Mutation: leave the failed restore in place -> the user is left with a half-filled database and no rollback.
    It 'rolls back, says which game and why, and leaves the profile as it was when the restore fails' {
        $fx = New-F69Fixture -Name 'empty-shell-fail'
        $fx.State.Exists['GameDB19'] = $true
        $fx.State.Empty.Add('GameDB19') | Out-Null
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup')
        $before = [System.IO.File]::ReadAllBytes($file)
        $fx.State.FailRestore.Add('GameDB19') | Out-Null
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'Database GameDB19 could not be created'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
    }

    # Mutation: count "could not connect" as empty -> a password problem would restore into a database that may hold data.
    It 'does not treat a database it cannot count as empty' {
        $fx = New-F69Fixture -Name 'empty-shell-unknown'
        $fx.State.Exists['GameDB19'] = $true
        $fx.State.NotReady.Add('GameDB19') | Out-Null
        [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup'))
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        @(Get-F69RestoreCalls).Count | Should -Be 0
        @(Get-F69Calls -Tool 'dropdb.exe').Count | Should -Be 0
    }

    It 'tells the user what to do next in plain words when a game database is not ready' {
        (Get-PostgresNotReadyNextStep -Text 'X [Y] (GameDBPPL12) is not ready: Found 0 tables, expected at least 1.') | Should -Match 'is empty'
        (Get-PostgresNotReadyNextStep -Text 'X [Y] (Z) is not ready: Could not connect') | Should -Match 'Open Details'
        Get-PostgresNotReadyNextStep -Text 'something else' | Should -BeNullOrEmpty
    }
}

Describe 'FIX69 auto-create = 1 uses the game''s own backup, and a game with none is left out' {
    # Mutation: leave the game out as "not ready" again -> an auto-create game with no backup is reported as needing attention and
    # asks for a pg_backup folder TeknoParrot does not need; or createdb runs (TeknoParrot makes the database, not TPM).
    It 'when every game has no pg_backup folder and TeknoParrot creates the database: sets up the profile, creates nothing, and the screen says "Profile ready"' {
        $fx = New-F69Fixture -Name 'nobackup'
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1'
        Install-F69Mocks -Fixture $fx
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = 'Could not connect with the settings saved in the game profile: FATAL: database "GameDB19" does not exist' } }

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F69RestoreCalls).Count | Should -Be 0
        (Get-PostgresFieldValue (Read-Xml $file) 'Pass') | Should -BeExactly 'fixture-password'
        @($result.NotReadyGames).Count | Should -Be 0
        @($result.GameOutcomes)[0].Outcome | Should -BeExactly 'WaitingForFirstStart'
        ($fx.State.Log -join "`n") | Should -Match 'Golden Tee Live 2019 \[GoldenTeeLive2019\] \(GameDB19\): no starting database file came with the game'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        $screen = Get-F69Screen -Fixture $fx -Result $result
        $screen | Should -Match ([regex]::Escape('Profile ready: Golden Tee Live 2019. TeknoParrot makes its database itself the first time the game starts.'))
        $screen | Should -Match 'Next: open TeknoParrot and start the game once'
        $screen | Should -Not -Match 'Could NOT be made ready|Every game database was checked and is ready'
    }

    # Mutation: let one game with no starting file stop the whole run (the old all-or-nothing preflight), or call the run a clean
    # success -> the other game is not created, or Outcome is SUCCEEDED.
    It 'sets up and checks the other game when one game has no starting database file, names the one that is not ready, and is not a clean success' {
        $fx = New-F69Fixture -Name 'one-bad'
        $good = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup')
        $bad = New-F69Profile -Fixture $fx -Name 'ZNoBackupGame' -GameName 'No Backup Game' -DbName 'GameDBNB' -AutoCreate ''
        $badBefore = [System.IO.File]::ReadAllBytes($bad)
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
        $result.Outcome | Should -Not -BeIn @('SUCCEEDED', 'NO_OP')
        $result.DbCreated | Should -Be 1
        @(Get-F69Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDB19')
        $fx.State.Exists.ContainsKey('GameDBNB') | Should -BeFalse
        (Get-F69Value -File $good -Field 'Pass') | Should -BeExactly 'fixture-password'
        [System.IO.File]::ReadAllBytes($bad) | Should -Be $badBefore
        @($result.GameOutcomes | ForEach-Object { $_.Key }) | Should -Be @('GoldenTeeLive2019')
        @($result.NotReadyGames | ForEach-Object { $_.Key }) | Should -Be @('ZNoBackupGame')
        @($result.Items) | Should -Contain 'profile:ZNoBackupGame'
        { Assert-TpmTransactionResult -Result $result } | Should -Not -Throw
        $screen = Get-F69Screen -Fixture $fx -Result $result
        $screen | Should -Match 'set up and checked, and ready'
        $screen | Should -Match ([regex]::Escape('Could NOT be made ready: No Backup Game. No starting database file came with this game, so its database cannot be built.'))
        $screen.IndexOf('set up and checked, and ready') | Should -BeLessThan $screen.IndexOf('Could NOT be made ready')
        $screen | Should -Not -Match 'Every game database was checked and is ready'
    }

    # N18B. Who gets hurt: a beginner whose game has an auto-create = 1 profile and several backups; TeknoParrot's own creation asks them to browse for a file.
    # Mutation: defer again when there are several files -> no createdb call and no restore.
    It 'restores the newest of several candidate backup files (<Name>) instead of leaving the choice to TeknoParrot' -ForEach @(
        @{ Name = 'numbered'; Files = @('0001.backup', '0002.backup'); Expected = '0002.backup' },
        @{ Name = 'three prefixed, tar-style names like Golden Tee Live 2020'; Files = @('0100postgresql_database-GameDB-backup', '0300postgresql_database-GameDB-backup', '0200postgresql_database-GameDB-backup'); Expected = '0300postgresql_database-GameDB-backup' }
    ) {
        $fx = New-F69Fixture -Name 'several'
        $file = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1' -BackupFiles $Files
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 1
        $restores = @(Get-F69RestoreCalls)
        $restores.Count | Should -Be 1
        [string]$restores[0].Arguments[-1] | Should -Match ('[\\/]' + [regex]::Escape($Expected) + '$')
        @($result.GameOutcomes)[0].Outcome | Should -BeExactly 'CreatedFromBackup'
        (Get-F69Value -File $file -Field 'DbName') | Should -BeExactly 'GameDB20'
    }

    # Mutation: ignore the alternate backups folder for an auto-create 1 game -> the game has no backup and setup stops.
    It 'creates an auto-create 1 game from its alternate backups folder when that holds the only backup' {
        $fx = New-F69Fixture -Name 'alt-defer'
        [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1')
        $altDir = Join-Path (Join-Path (Join-Path (Join-Path $fx.Root 'Game-GoldenTeeLive2019') 'pg_backup') 'alternate backups') 'pg_backup'
        New-Item -ItemType Directory -Path $altDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $altDir '1000-a-backup'), 'alt')
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 1
        [string](@(Get-F69RestoreCalls)[0].Arguments[-1]) | Should -Match '1000-a-backup$'
        @($result.GameOutcomes)[0].Outcome | Should -BeExactly 'CreatedFromBackup'
    }

    # Mutation: let the game defer (or create) when its executable cannot be found -> setup succeeds with no database, or createdb appears.
    It 'stops, naming the game, when the game executable is not available' {
        $fx = New-F69Fixture -Name 'noexe'
        [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup') -NoGameExe)
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'GameDB19 does not exist and the game executable could not be found'
    }

    # Who gets hurt: a user whose game folder path is over 259 characters (Windows PowerShell 5.1, long paths off) and whose profile says TeknoParrot creates the database; setup used to say it was left to TeknoParrot and never said why.
    # Mutation: let the missing starting file pass when the path is too long to read -> setup succeeds, createdb is not called, and no sentence about the long path appears.
    It 'stops and says the game folder path is too long to read when Windows PowerShell cannot read it' {
        $fx = New-F69Fixture -Name 'longpath'
        [void](New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -BackupFiles @('0001.backup'))
        Install-F69Mocks -Fixture $fx
        # The real long-path-off case cannot be run on a PC with long paths on; this fakes the one answer that case gives.
        Mock Get-TpmGameExeAvailability { 'PathTooLong' }

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F69RestoreCalls).Count | Should -Be 0
        $fx.State.Events.Contains('backup') | Should -BeFalse
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'GameDB19 is in a folder path longer than 259 characters.*shorter folder path'
    }

    # Mutation: let the sharing game that has no starting file be left behind pointing at the other game's database -> launching it writes
    # into the other game's saved progress; or call the run a success.
    It 'stops and changes nothing when a game with no starting file shares a database name with a game that has a backup, and says why in plain words' {
        $fx = New-F69Fixture -Name 'shared'
        $gt = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1' -BackupFiles @('0001.backup', '0002.backup')
        $other = New-F69Profile -Fixture $fx -Name 'ZSharedGame' -GameName 'Shared Game' -DbName 'GameDB20' -AutoCreate ''
        $before = @([System.IO.File]::ReadAllBytes($gt), [System.IO.File]::ReadAllBytes($other))
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        $fx.State.Events.Contains('backup') | Should -BeFalse
        [System.IO.File]::ReadAllBytes($gt) | Should -Be $before[0]
        [System.IO.File]::ReadAllBytes($other) | Should -Be $before[1]
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'Shared Game \[ZSharedGame\]: The database GameDB20 is also used by Golden Tee Live 2020.*no starting database file.*must not run on the other game''s data\. Nothing was changed'
    }
}

Describe 'FIX69 auto-create 0 or missing keeps its behavior' {
    # N18A (smoke N18, the owner's real library: 3 to 8 identical backups per game). Who gets hurt: a beginner whose game ships several backups
    # and so got no database at all.
    # Mutation: refuse again when there are several files -> no database; or pick the first/oldest name -> the 0905 file is restored.
    It 'restores the newest of several backup files for auto-create <Label> and names it in the log and the Details, not on the main screen' -ForEach @(
        @{ Label = '0'; AutoCreate = '0' },
        @{ Label = 'missing'; AutoCreate = '' }
    ) {
        $fx = New-F69Fixture -Name ('keep-' + $Label)
        [void](New-F69Profile -Fixture $fx -Name 'SilverStrike' -GameName 'Silver Strike' -DbName 'GameDBSSB' -AutoCreate $AutoCreate -BackupFiles @('0905-postgresql_database-GameDBSSB-backup', '1840-postgresql_database-GameDBSSB-backup', '1215-postgresql_database-GameDBSSB-backup'))
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 1
        $restores = @(Get-F69RestoreCalls)
        $restores.Count | Should -Be 1
        [string]$restores[0].Arguments[-1] | Should -Match '[\\/]1840-postgresql_database-GameDBSSB-backup$'
        ($fx.State.Log -join "`n") | Should -Match 'the game has 3 backup files; the newest one is used: .*1840-postgresql_database-GameDBSSB-backup'
        (@($result.Warnings) -join ' | ') | Should -Match 'came with 3 backup files, so the newest one was used: 1840-postgresql_database-GameDBSSB-backup \(in the folder pg_backup\)\.'
        $screen = Get-F69Screen -Fixture $fx -Result $result
        $screen | Should -Match ([regex]::Escape('Ready: Silver Strike. The database was created from the game''s own backup and checked.'))
        $screen | Should -Not -Match '1840'
    }

    # N18B. Who gets hurt: a user whose game keeps its only backup in the alternate backups folder and got an empty database.
    # Mutation: drop the -IncludeAlternate in the creation step -> an empty database is created; skip the direct form -> the same.
    It 'creates a missing database from a backup in the alternate backups folder (<Form>) when the game has no other backup' -ForEach @(
        @{ Form = 'nested'; Sub = 'pg_backup' },
        @{ Form = 'directly inside'; Sub = '' }
    ) {
        $fx = New-F69Fixture -Name ('alt-create-' + $Form.Replace(' ', ''))
        [void](New-F69Profile -Fixture $fx -Name 'SilverStrike' -GameName 'Silver Strike' -DbName 'GameDBSSB' -AutoCreate '')
        $altDir = Join-Path (Join-Path (Join-Path $fx.Root 'Game-SilverStrike') 'pg_backup') 'alternate backups'
        if ($Sub) { $altDir = Join-Path $altDir $Sub }
        New-Item -ItemType Directory -Path $altDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $altDir '1000-a-backup'), 'alt')
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.GameOutcomes)[0].Outcome | Should -BeExactly 'CreatedFromBackup'
        $restores = @(Get-F69RestoreCalls)
        $restores.Count | Should -Be 1
        [string]$restores[0].Arguments[-1] | Should -Match '1000-a-backup$'
    }

    # N18B. Mutation: always say "the newest one" -> two files with no time in their names are described as if one were newer.
    It 'does not call a file the newest when no file name carries a time' {
        $fx = New-F69Fixture -Name 'no-time'
        [void](New-F69Profile -Fixture $fx -Name 'SilverStrike' -GameName 'Silver Strike' -DbName 'GameDBSSB' -AutoCreate '' -BackupFiles @('backup-old', 'backup-new'))
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        [string](@(Get-F69RestoreCalls)[0].Arguments[-1]) | Should -Match 'backup-old$'
        (@($result.Warnings) -join ' | ') | Should -Match 'came with 2 backup files, their names do not say which is newest, so one was picked by name: backup-old'
        (@($result.Warnings) -join ' | ') | Should -Not -Match 'the newest one was used'
        ($fx.State.Log -join "`n") | Should -Match 'their names carry no time'
    }

    # Mutation: try the other backup files after a failed restore -> a second pg_restore call, a hidden reason.
    It 'does not try another backup file when the newest one fails to restore: the database is removed again and the reason is kept' {
        $fx = New-F69Fixture -Name 'newest-fails'
        $file = New-F69Profile -Fixture $fx -Name 'SilverStrike' -GameName 'Silver Strike' -DbName 'GameDBSSB' -AutoCreate '' -BackupFiles @('0905-a-backup', '1840-a-backup')
        $before = [System.IO.File]::ReadAllBytes($file)
        $fx.State.FailRestore.Add('GameDBSSB') | Out-Null
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        @(Get-F69RestoreCalls).Count | Should -Be 1
        $fx.State.Exists['GameDBSSB'] | Should -BeFalse
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'Database GameDBSSB could not be created'
    }

    # Mutation: defer auto-create 0 without a backup instead of failing closed, or create
    # an empty database for it.
    It 'leaves out a game when auto-create is 0 and the game has no bundled backup, and changes nothing' {
        $fx = New-F69Fixture -Name 'zero-none'
        [void](New-F69Profile -Fixture $fx -Name 'NoBackupGame' -GameName 'No Backup Game' -DbName 'GameDBNB' -AutoCreate '0')
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        @($result.NotReadyGames).Count | Should -Be 1
    }

    # Mutation: bring back the empty database for a missing auto-create field without a backup -> createdb runs and the game
    # is called ready with no tables.
    It 'leaves out a game and creates nothing when the auto-create field is missing and the game has no backup' {
        $fx = New-F69Fixture -Name 'missing-none'
        [void](New-F69Profile -Fixture $fx -Name 'NoBackupGame' -GameName 'No Backup Game' -DbName 'GameDBNB' -AutoCreate '')
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        @(Get-F69Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F69RestoreCalls).Count | Should -Be 0
        @($result.NotReadyGames).Count | Should -Be 1
    }
}

Describe 'FIX133B a profile whose connection values are not the exact local ones can finish setup' {
    # Who gets hurt: a user whose profile says "localhost", "Postgres" or another bin folder. Setup only filled blank fields, the final check
    # wanted the exact local values, so every run ended in a rollback and the menu had no way out.
    # Mutation: fill only blank fields again in Invoke-PostgresGameSetup -> these runs end ACTION_REQUIRED.
    It 'corrects <Field>=<Value> and succeeds' -ForEach @(
        @{ Field = 'Address'; Value = 'localhost' }, @{ Field = 'Address'; Value = '127.0.0.1 ' },
        @{ Field = 'User'; Value = 'POSTGRES' }, @{ Field = 'Path'; Value = 'D:\other\pg\bin\' }
    ) {
        $fx = New-F69Fixture -Name 'noncanonical'
        $file = New-F69Profile -Fixture $fx -Name 'Game1' -DbName 'GameDB1' -AutoCreate '1' -BackupFiles @('0001.backup') -Complete
        $realPath = $fx.Bin.TrimEnd('\') + '\'
        $canonical = @{ Address = '127.0.0.1'; User = 'postgres'; Path = $realPath }[$Field]
        $xml = [System.IO.File]::ReadAllText($file).Replace('C:\fixture\pg\bin\', $realPath)
        $xml = $xml.Replace("<FieldName>$Field</FieldName><FieldValue>$canonical</FieldValue>", "<FieldName>$Field</FieldName><FieldValue>$Value</FieldValue>")
        [System.IO.File]::WriteAllText($file, $xml)
        Install-F69Mocks -Fixture $fx

        $result = Invoke-F69Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        (Get-F69Value -File $file -Field $Field) | Should -BeExactly $canonical
    }
}

Describe 'FIX69 the backup resolvers' {
    BeforeEach {
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
    }

    # Mutation: return a path when there are no candidates, or when the game executable is missing.
    It 'returns the newest file, and nothing when there are none or no game executable' {
        $one = New-F69GameFolder -Name 'one' -Files @('0007.backup')
        $none = New-F69GameFolder -Name 'none'

        (Get-PostgresBackupSelection -GamePath (Join-Path $one 'game.exe')).Newest | Should -BeExactly (Join-Path (Join-Path $one 'pg_backup') '0007.backup')
        (Get-PostgresBackupSelection -GamePath (Join-Path $none 'game.exe')).Newest | Should -BeNullOrEmpty
        (Get-PostgresBackupSelection -GamePath (Join-Path $one 'missing.exe')).Newest | Should -BeNullOrEmpty
        (Get-PostgresBackupSelection -GamePath '').Newest | Should -BeNullOrEmpty
    }

    # Mutation: count files of older date folders as candidates -> the count is 3, not 1.
    It 'looks only in the newest date folder, like the existing resolver' {
        $folder = New-F69GameFolder -Name 'dated' -Files @('0009.backup') -Subfolder '2026-01-01'
        $older = Join-Path (Join-Path $folder 'pg_backup') '2025-12-31'
        New-Item -ItemType Directory -Path $older -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $older '0001.backup'), 'older')
        [System.IO.File]::WriteAllText((Join-Path $older '0002.backup'), 'older')

        $selection = Get-PostgresBackupSelection -GamePath (Join-Path $folder 'game.exe')

        $selection.Newest | Should -BeExactly (Join-Path (Join-Path (Join-Path $folder 'pg_backup') '2026-01-01') '0009.backup')
        $selection.CandidateCount | Should -Be 1
    }

    # N18A. Mutation: take the first name, the oldest date folder, the note file, or the alternate backups -> a wrong or unusable file is restored.
    It 'picks the latest time in the newest date folder, and ignores a note file and the alternate backups' {
        $folder = New-F69GameFolder -Name 'newest' -Files @('0905-a-backup', '1840-a-backup', '1215-a-backup', 'notes.txt') -Subfolder '2017-05-28'
        $pg = Join-Path $folder 'pg_backup'
        foreach ($extra in @((Join-Path $pg '2017-05-27'), (Join-Path (Join-Path $pg 'alternate backups') 'pg_backup'))) {
            New-Item -ItemType Directory -Path $extra -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $extra '2359-z-backup'), 'other')
        }

        $selection = Get-PostgresBackupSelection -GamePath (Join-Path $folder 'game.exe') -IncludeAlternate

        $selection.Newest | Should -BeExactly (Join-Path (Join-Path $pg '2017-05-28') '1840-a-backup')
        $selection.CandidateCount | Should -Be 3 -Because 'notes.txt is not a backup file'
        $selection.NewestHasTime | Should -BeTrue
    }

    # N18B. Mutation: treat any four digits as a time -> 9999-x beats 1840-y; no flag -> "newest" is claimed for names without a time.
    It 'counts a leading group as a time only when it is a valid 24-hour time, and says when none is' -ForEach @(
        @{ Names = @('9999-x', '1840-y'); Newest = '1840-y'; HasTime = $true },
        @{ Names = @('2400-x', '2359-y', '0000-z'); Newest = '2359-y'; HasTime = $true },
        @{ Names = @('1260-x', '0905-y'); Newest = '0905-y'; HasTime = $true },
        @{ Names = @('backup-old', 'backup-new'); Newest = 'backup-old'; HasTime = $false },
        @{ Names = @('9999-x', '2460-y'); Newest = '9999-x'; HasTime = $false },
        @{ Names = @('0001.backup'); Newest = '0001.backup'; HasTime = $true },
        @{ Names = @('backup-old.backup', 'readme.txt', 'notes.md'); Newest = 'backup-old.backup'; HasTime = $false }
    ) {
        $folder = New-F69GameFolder -Name 'times' -Files $Names

        $selection = Get-PostgresBackupSelection -GamePath (Join-Path $folder 'game.exe')

        [System.IO.Path]::GetFileName([string]$selection.Newest) | Should -BeExactly $Newest
        $selection.NewestHasTime | Should -Be $HasTime
    }

    # Mutation: never look in the alternate backups folder, always look there, or skip the direct form -> no database for such a game, its file beats a real backup, or the direct form gives 0 files.
    It 'uses the alternate backups (its own pg_backup folder or files directly inside) only with the switch, and only when no other backup exists' {
        $nested = New-F69GameFolder -Name 'alt-nested'
        $nestedDir = Join-Path (Join-Path (Join-Path $nested 'pg_backup') 'alternate backups') 'pg_backup'
        New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null
        foreach ($name in @('1000-a-backup', '1100-a-backup')) { [System.IO.File]::WriteAllText((Join-Path $nestedDir $name), 'alt') }
        $direct = New-F69GameFolder -Name 'alt-direct'
        $directDir = Join-Path (Join-Path $direct 'pg_backup') 'alternate backups'
        New-Item -ItemType Directory -Path $directDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $directDir '1000-a-backup'), 'alt')
        $withReal = New-F69GameFolder -Name 'alt-and-real' -Files @('0001-a-backup')
        $altDir2 = Join-Path (Join-Path (Join-Path $withReal 'pg_backup') 'alternate backups') 'pg_backup'
        New-Item -ItemType Directory -Path $altDir2 -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $altDir2 '2359-a-backup'), 'alt')

        (Get-PostgresBackupSelection -GamePath (Join-Path $nested 'game.exe') -IncludeAlternate).Newest | Should -BeExactly (Join-Path $nestedDir '1100-a-backup')
        (Get-PostgresBackupSelection -GamePath (Join-Path $direct 'game.exe') -IncludeAlternate).Newest | Should -BeExactly (Join-Path $directDir '1000-a-backup')
        (Get-PostgresBackupSelection -GamePath (Join-Path $withReal 'game.exe') -IncludeAlternate).Newest | Should -BeExactly (Join-Path (Join-Path $withReal 'pg_backup') '0001-a-backup')
        (Get-PostgresBackupSelection -GamePath (Join-Path $nested 'game.exe')).CandidateCount | Should -Be 0
        (Get-PostgresBackupSelection -GamePath (Join-Path $direct 'game.exe')).CandidateCount | Should -Be 0
    }
}

Describe 'FIX69 Library Health lists only the games TeknoParrot still has to create' {
    BeforeEach {
        $script:healthRoot = Join-Path $TestDrive ('f69-health-' + [guid]::NewGuid().ToString('N'))
        $script:profiles = Join-Path $script:healthRoot 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:profiles)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:healthRoot 'GameProfiles'))
        $script:PostgresServiceName = 'FIX69-test-service-must-never-exist'
        $script:PostgresBinDir = Join-Path $script:healthRoot 'pgsql'
        [void][System.IO.Directory]::CreateDirectory($script:PostgresBinDir)
        $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
        $script:FFBBlasterNamePattern = 'ffb.*blaster|blaster.*ffb'
        $script:hostLines = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:hostLines.Add([string]($Object -join ' ')) }
        $script:logLines = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Log { [void]$script:logLines.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-Host { 'B' }
        Mock Get-Service { [pscustomobject]@{ Status = 'Stopped' } }
        Mock Start-Service { throw 'Health Check must never start a service.' }
        Mock Stop-Service { throw 'Health Check must never stop a service.' }
    }

    # Mutation: list every auto-create 1 game as before -> Golden Tee Live 2019 (one backup)
    # appears in the list.
    It 'leaves out games that have a bundled backup (one or several) and keeps the games with none' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -Pass 'synthetic-pass' -AutoCreate '1' -BackupFiles @('0001.backup') -Complete
        $null = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -BackupFiles @('0100a', '0200a', '0300a') -Complete
        $null = New-F69Profile -Fixture $fx -Name 'NoBackupGame' -GameName 'No Backup Game' -DbName 'GameDBNB' -Pass 'synthetic-pass' -AutoCreate '1' -Complete

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        $result.PostgresConfigured | Should -Be 3
        @($result.PostgresAutoCreateProfiles).Count | Should -Be 1
        @($result.PostgresAutoCreateProfiles | Sort-Object) | Should -Be @('No Backup Game')
        # The default screen is short; the list of games with no starting database file is behind D (the detail blocks) and in the log.
        $firstRun = @((Get-F69HealthPostgresDetail -Result $result) -split "`n" | Where-Object { $_ -like 'Games with no starting database file:*' })
        $firstRun.Count | Should -Be 1
        $firstRun[0] | Should -Match 'No Backup Game'
        $firstRun[0] | Should -Not -Match 'Golden Tee Live 2019'
        $firstRun[0] | Should -Not -Match 'Golden Tee Live 2020'
        ($script:logLines -join "`n") | Should -Match ([regex]::Escape('Library health detail [PostgreSQL]: ' + $firstRun[0]))
    }

    # Mutation: print the header when the list is empty -> the header appears with 0 games.
    It 'shows no TeknoParrot-creates list when every auto-create game has one bundled backup' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F69Profile -Fixture $fx -Name 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -Pass 'synthetic-pass' -AutoCreate '1' -BackupFiles @('0001.backup') -Complete

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        $result.PostgresConfigured | Should -Be 1
        @($result.PostgresAutoCreateProfiles).Count | Should -Be 0
        (Get-F69HealthPostgresDetail -Result $result) | Should -Not -Match 'Profile ready; the database is created'
        ($script:logLines -join "`n") | Should -Not -Match 'Profile ready; the database is created'
    }

    # Mutation: plain Test-Path / Get-Item on the game folder -> a game in a path over 259 characters is skipped or counted as not checked, and its dgVoodoo2, ReShade and BepInEx state is missed.
    It 'checks a game in a path over 259 characters fully (dgVoodoo2, ReShade, BepInEx)' {
        $longRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-f69-long-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            $deep = $longRoot
            while ($deep.Length -lt 280) { $deep = Join-Path $deep 'a-long-folder-name-for-testing' }
            $bepDir = Join-Path (Join-Path $deep 'BepInEx') 'core'
            [void][System.IO.Directory]::CreateDirectory('\\?\' + $bepDir)
            $exe = Join-Path $deep 'game.exe'
            [System.IO.File]::WriteAllBytes('\\?\' + $exe, [byte[]]([System.Text.Encoding]::ASCII.GetBytes('MZ d3d8.dll')))
            [System.IO.File]::WriteAllBytes('\\?\' + (Join-Path $deep 'dxgi.dll'), [byte[]](1, 2, 3))
            [System.IO.File]::Copy((Join-Path $env:SystemRoot 'System32\kernel32.dll'), '\\?\' + (Join-Path $bepDir 'BepInEx.dll'))
            $xml = '<GameProfile><GameName>Long Game</GameName><GamePath>' + [System.Security.SecurityElement]::Escape([string]$exe) + '</GamePath><ConfigValues /></GameProfile>'
            [System.IO.File]::WriteAllText((Join-Path $script:profiles 'LongGame.xml'), $xml, (New-Object System.Text.UTF8Encoding $false))

            $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

            $result.OptionalCheckFailed | Should -Be 0
            # Mutation: plain Test-Path for the game file -> the game is listed as broken and the health details contradict themselves.
            @($result.Valid) | Should -Contain 'LongGame'
            @($result.Broken) | Should -Not -Contain 'LongGame'
            @($result.DgVoodoo2Needed) | Should -Contain 'LongGame'
            $result.ReShadeCount | Should -Be 1
            $result.BepInExCount | Should -Be 1
        } finally {
            try { [System.IO.Directory]::Delete('\\?\' + $longRoot, $true) } catch { $null = $_ }
        }
    }
}
