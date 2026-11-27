#Requires -Module Pester

# FIX59 (issue #350) Golden Tee Live 2020 PostgreSQL support. The upstream profile
# GoldenTeeLive2020.xml uses DbName GameDB20 and "Automatically create Database" = 1.
# Since FIXDB27 TeknoParrot Manager always creates that database from the game's own
# bundled backup and checks it with the game's own settings; with no backup it stops and
# says the game cannot be made ready (nothing is left for TeknoParrot to create). It must
# not substitute another Golden Tee year's backup, schema or database. Existing data is
# preserved; a reset only ever uses a starting database that ships with the game.
#
# The production script is parsed and only its function definitions are dot-sourced;
# no top-level product code runs in this process. The PostgreSQL 8.3 client tools are
# replaced by one in-memory fake, so no PostgreSQL server, service, registry or user
# configuration is touched. Every file lives under TestDrive and every profile, game
# folder and backup is a synthetic fixture (no game payload, no real credential).
# Each It names the product mutation that makes it fail.

BeforeAll {
    $script:Fix59PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix59PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX59 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix59FunctionFile = Join-Path $TestDrive 'tpm-fix59-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix59FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix59FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force

    # Hardware and progress-line access is external to these tests.
    function Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = 'NVIDIA'; Name = 'isolated fixture' } }
    function Suspend-TpmProgressLine {}
    function Resume-TpmProgressLine {}

    function New-F59Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f59-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
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
        }
        return [pscustomobject]@{ Root = $root; Bin = $bin; Evidence = $evidence; Profiles = $profiles; State = $state }
    }

    # Profile shaped like the upstream Golden Tee Live 2020 profile: a Postgres category
    # with Path, Address, Port, DbName, User, Pass and "Automatically create Database".
    # Path starts blank so the tests can see setup fill it. -AutoCreate '' omits the field.
    function New-F59Profile {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$ProfileName,
            [Parameter(Mandatory)][string]$GameName,
            [AllowEmptyString()][string]$DbName,
            [string]$Pass = '',
            [string]$AutoCreate = '1',
            [string]$Storage = '',
            [switch]$Backup,
            [switch]$Complete
        )
        $gameDir = Join-Path $Fixture.Root ('Game-' + $ProfileName)
        New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
        $exe = Join-Path $gameDir 'game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        if ($Backup) {
            $backupDir = Join-Path $gameDir 'pg_backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $backupDir '0001.backup'), 'synthetic bundled backup', (New-Object System.Text.UTF8Encoding $false))
        }
        $fields = New-Object System.Collections.Generic.List[object]
        [void]$fields.Add(@('Path', $(if ($Complete) { 'C:\fixture\pg\bin\' } else { '' })))
        [void]$fields.Add(@('Address', $(if ($Complete) { '127.0.0.1' } else { '' })))
        [void]$fields.Add(@('Port', $(if ($Complete) { '5432' } else { '' })))
        [void]$fields.Add(@('DbName', $DbName))
        [void]$fields.Add(@('User', $(if ($Complete) { 'postgres' } else { '' })))
        [void]$fields.Add(@('Pass', $Pass))
        if ($AutoCreate -ne '') { [void]$fields.Add(@('Automatically create Database', $AutoCreate)) }
        $xml = '<GameProfile><GameName>' + $GameName + '</GameName><GamePath>' + $exe + '</GamePath><ConfigValues>'
        if ($Storage -ne '') { $xml += '<FieldInformation><CategoryName>Database</CategoryName><FieldName>Storage</FieldName><FieldValue>' + $Storage + '</FieldValue></FieldInformation>' }
        foreach ($field in $fields) {
            $xml += '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $field[0] + '</FieldName><FieldValue>' + $field[1] + '</FieldValue></FieldInformation>'
        }
        $xml += '</ConfigValues></GameProfile>'
        $file = Join-Path $Fixture.Profiles ($ProfileName + '.xml')
        [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $file
    }

    # The PostgreSQL block of the Library Health details (the D key), as one text.
    function Get-F59HealthPostgresDetail {
        param([Parameter(Mandatory)]$Result)
        $block = @(Get-TpmLibraryHealthDetailBlocks -Result $Result | Where-Object { $_.Heading -eq 'PostgreSQL' })
        if ($block.Count -ne 1) { throw "Expected one PostgreSQL details block; found $($block.Count)." }
        return (@($block[0].Lines) -join "`n")
    }

    function New-F59CommandResult {
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
    function Invoke-F59FakeCommand {
        param([string]$ToolName, [string[]]$Arguments)
        $state = $script:F59State
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
            return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($ToolName + ' (PostgreSQL) 8.3.23'))
        }
        if ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc') {
            $query = [string]$Arguments[$Arguments.Count - 1]
            if ($query -match 'count\(\*\)') { return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '24') }
            $wanted = ''
            if ($query -match "lower\('([^']+)'\)\s*$") { $wanted = $Matches[1] }
            $names = @($state.Exists.Keys | Where-Object { $state.Exists[$_] -and [string]::Equals($_, $wanted, [System.StringComparison]::OrdinalIgnoreCase) })
            return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($names -join "`n"))
        }
        if ($ToolName -eq 'psql.exe') { return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -contains '--list') { return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe') {
            [void]$state.Events.Add('pg_restore:' + $database)
            return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'createdb.exe') {
            [void]$state.Events.Add('createdb:' + $database)
            $state.Exists[$database] = $true
            return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'dropdb.exe') {
            [void]$state.Events.Add('dropdb:' + $database)
            $state.Exists[$database] = $false
            return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        return (New-F59CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 3 -Output 'unexpected fake tool')
    }

    function Install-F59SetupMocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F59State = $Fixture.State
        $script:F59Recovery = [pscustomobject]@{ Path = $Fixture.Evidence; ConfigBackups = @(); Verified = $true; ProfileBackups = @() }
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log { [void]$script:F59State.Log.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock New-PostgresRecoveryBackup { [void]$script:F59State.Events.Add('backup'); $script:F59Recovery }
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            # FIX129: the fake runs the caller's -Interpret block on its text, like the real runner does.
            Add-FakePostgresInterpretation -Command (Invoke-F59FakeCommand -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            $exists = $false
            if ($script:F59State.Exists.ContainsKey($DbName)) { $exists = [bool]$script:F59State.Exists[$DbName] }
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
    }

    function Get-F59Calls {
        param([Parameter(Mandatory)][string]$Tool)
        return @($script:F59State.Calls | Where-Object { $_.Tool -eq $Tool -and $_.Arguments -notcontains '--version' })
    }

    function Get-F59RestoreCalls {
        return @($script:F59State.Calls | Where-Object { $_.Tool -eq 'pg_restore.exe' -and $_.Arguments -notcontains '--list' -and $_.Arguments -notcontains '--version' })
    }

    function Get-F59Value {
        param([Parameter(Mandatory)][string]$File, [Parameter(Mandatory)][string]$Field)
        return (Get-PostgresFieldValue (Read-Xml $File) $Field)
    }

    function Invoke-F59Setup {
        param([Parameter(Mandatory)]$Fixture)
        return (Invoke-PostgresGameSetup -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password')
    }

    function Install-F59ChoiceMocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F59State = $Fixture.State
        $script:F59Profiles = $Fixture.Profiles
        Mock Write-Log { [void]$script:F59State.Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F59State.Screen.Add(([string]($Object -join ' '))) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { @(Get-ChildItem -LiteralPath $script:F59Profiles -Filter '*.xml' -File) }
    }

    function Invoke-F59Choice {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$Database)
        return (Invoke-PostgresReinitializeChoice -FailureDiagnoses @([pscustomobject]@{ Database = $Database }) -UserProfilesDir $Fixture.Profiles `
            -ConfigPath (Join-Path $Fixture.Root 'config.json') -ScriptPath (Join-Path $Fixture.Root 'script.ps1') -TpRoot $Fixture.Root `
            -SuperPasswordPlain 'fixture-password' -RecoveryBackup ([pscustomobject]@{ Path = $Fixture.Root; Verified = $true }))
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix59PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX59 Golden Tee Live 2020 setup creates GameDB20 from the bundled backup and stops when the game has none' {
    # Mutation: leave GameDB20 to TeknoParrot (the old deferral) even when the game ships a backup -> createdb and
    # pg_restore are never called and the game is not reported as created from its backup.
    It 'creates GameDB20 from the bundled backup, fills the profile, makes the protected backup first and checks the database' {
        $fx = New-F59Fixture -Name 'create'
        $file = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1' -Backup
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 1
        @(Get-F59Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDB20')
        @(Get-F59RestoreCalls).Count | Should -Be 1
        @(Get-F59Calls -Tool 'dropdb.exe').Count | Should -Be 0
        $fx.State.Events.IndexOf('backup') | Should -BeLessThan $fx.State.Events.IndexOf('createdb:GameDB20')
        (Get-F59Value -File $file -Field 'Path') | Should -BeExactly ($fx.Bin.TrimEnd('\') + '\')
        (Get-F59Value -File $file -Field 'Address') | Should -BeExactly '127.0.0.1'
        (Get-F59Value -File $file -Field 'Port') | Should -BeExactly '5432'
        (Get-F59Value -File $file -Field 'User') | Should -BeExactly 'postgres'
        (Get-F59Value -File $file -Field 'Pass') | Should -BeExactly 'fixture-password'
        (Get-F59Value -File $file -Field 'DbName') | Should -BeExactly 'GameDB20'
        @($result.GameOutcomes)[0].Outcome | Should -BeExactly 'CreatedFromBackup'
        @($result.GameOutcomes)[0].TableCount | Should -Be 24
        (@($result.Warnings) -join ' | ') | Should -Match 'Golden Tee Live 2020 \[GoldenTeeLive2020\] \(GameDB20\): the database did not exist\. TeknoParrot Manager created it and restored the backup bundled with the game'
        (@($result.Warnings) -join ' | ') | Should -Not -Match '(?i)deferred|first run|not verified'
        ($result.TechnicalDetails | ConvertTo-Json -Depth 12) | Should -Not -Match 'fixture-password'
        ($fx.State.Log -join "`n") | Should -Not -Match 'fixture-password'
    }

    # Mutation: bring back the "left out, not ready" result for an auto-create game with no starting file -> the profile is not written
    # (no password), setup says ACTION_REQUIRED and asks the owner for a pg_backup folder TeknoParrot does not need; or createdb runs.
    It 'sets up the profile, leaves the database to TeknoParrot and reports it as ready for its first start when GameDB20 is absent and the game ships no pg_backup' {
        $fx = New-F59Fixture -Name 'nobackup'
        $file = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1'
        Install-F59SetupMocks -Fixture $fx
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = 'Could not connect with the settings saved in the game profile: FATAL: database "GameDB20" does not exist' } }

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 0
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F59RestoreCalls).Count | Should -Be 0
        (Get-F59Value -File $file -Field 'Pass') | Should -BeExactly 'fixture-password'
        (Get-F59Value -File $file -Field 'Address') | Should -BeExactly '127.0.0.1'
        @($result.NotReadyGames).Count | Should -Be 0
        @($result.GameOutcomes)[0].Outcome | Should -BeExactly 'WaitingForFirstStart'
        $result.Summary | Should -Match 'TeknoParrot makes the database of 1 game itself the first time the game starts'
        (Get-TpmPostgresSetupOutcomeLine -Outcome 'WaitingForFirstStart' -Names @('Golden Tee Live 2020')) | Should -Match '^Profile ready: Golden Tee Live 2020\. TeknoParrot makes its database itself'
        (@($result.Warnings) -join ' | ') | Should -Not -Match 'not made ready'

        # A second run changes nothing and still says the game waits for its first start.
        $profileAfterFirst = [System.IO.File]::ReadAllBytes($file)
        $second = Invoke-F59Setup -Fixture $fx
        $second.Outcome | Should -BeExactly 'NO_OP'
        [System.IO.File]::ReadAllBytes($file) | Should -Be $profileAfterFirst
        @($second.GameOutcomes)[0].Outcome | Should -BeExactly 'WaitingForFirstStart'
    }

    # Mutation: treat "cannot connect" like "database not made yet" for a game left to TeknoParrot -> a wrong password or a stopped
    # server is reported as a game that only has to be started once, and TeknoParrot then cannot make the database either.
    It 'does not call an auto-create game ready for its first start when the profile settings cannot connect' {
        $fx = New-F59Fixture -Name 'nobackup-noconnect'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1'
        Install-F59SetupMocks -Fixture $fx
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = 'Could not connect with the settings saved in the game profile: password authentication failed' } }
        Mock Restore-PostgresProfileBackups { $true }

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -Not -BeExactly 'SUCCEEDED'
        @($result.GameOutcomes | Where-Object { $_.Outcome -eq 'WaitingForFirstStart' }).Count | Should -Be 0
    }

    # Mutation: leave out the auto-create condition -> every game with no starting file (including one whose profile does not say
    # TeknoParrot creates the database) is called ready, though nothing will ever build its database.
    It 'still leaves out a game with no starting file when its profile does not say TeknoParrot creates the database (<Case>)' -ForEach @(
        @{ Case = 'auto-create is 0'; AutoCreate = '0' }
        @{ Case = 'no auto-create field'; AutoCreate = '' }
    ) {
        $fx = New-F59Fixture -Name ('nobackup-noauto-' + $Case.Replace(' ', ''))
        $file = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate $AutoCreate
        $before = [System.IO.File]::ReadAllBytes($file)
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F59RestoreCalls).Count | Should -Be 0
        $fx.State.Events.Contains('backup') | Should -BeFalse
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        @($result.NotReadyGames | ForEach-Object { $_.Key }) | Should -Be @('GoldenTeeLive2019')
        (@($result.Warnings) -join ' | ') | Should -Match 'Golden Tee Live 2019 \[GoldenTeeLive2019\] \(GameDB19\): not made ready\. No starting database file came with this game, so its database cannot be built\.'
    }

    # Mutation: key the creation decision on a Golden Tee name or year instead of the
    # profile's own database name and flag -> GameDB19 is not restored, or GameDB20 is touched.
    It 'creates only the database of an older Golden Tee year that does not auto-create and never touches an existing GameDB20 or its kept password' {
        $fx = New-F59Fixture -Name 'distinct'
        $fx.State.Exists['GameDB20'] = $true
        $gt2020 = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'owner-own-password' -AutoCreate '1' -Backup -Complete
        $gt2019 = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '0' -Backup
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 1
        $creates = @(Get-F59Calls -Tool 'createdb.exe')
        $creates.Count | Should -Be 1
        $creates[0].Database | Should -BeExactly 'GameDB19'
        $restores = @(Get-F59RestoreCalls)
        $restores.Count | Should -Be 1
        $restores[0].Database | Should -BeExactly 'GameDB19'
        @(Get-F59Calls -Tool 'dropdb.exe').Count | Should -Be 0
        $fx.State.Exists['GameDB20'] | Should -BeTrue
        @($result.PassKeptProfiles) | Should -Contain 'GoldenTeeLive2020'
        (Get-F59Value -File $gt2020 -Field 'Pass') | Should -BeExactly 'owner-own-password'
        (Get-F59Value -File $gt2019 -Field 'Pass') | Should -BeExactly 'fixture-password'
        (@($result.Warnings) -join ' | ') | Should -Not -Match 'GameDB20\): database was absent'
    }

    # Mutation: let the second run rewrite profiles or take another protected backup, or
    # report SUCCEEDED when nothing changed.
    It 'is a no-op on a repeat run: no second backup, no profile rewrite, no second creation, and the database is still reported ready' {
        $fx = New-F59Fixture -Name 'repeat'
        $file = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1' -Backup
        Install-F59SetupMocks -Fixture $fx

        $first = Invoke-F59Setup -Fixture $fx
        $first.Outcome | Should -BeExactly 'SUCCEEDED'
        $afterFirst = [System.IO.File]::ReadAllBytes($file)

        $second = Invoke-F59Setup -Fixture $fx

        $second.Outcome | Should -BeExactly 'NO_OP'
        [System.IO.File]::ReadAllBytes($file) | Should -Be $afterFirst
        @($fx.State.Events | Where-Object { $_ -eq 'backup' }).Count | Should -Be 1
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 1
        @(Get-F59RestoreCalls).Count | Should -Be 1
        @($second.GameOutcomes)[0].Outcome | Should -BeExactly 'AlreadyExisted'
        @($second.GameOutcomes)[0].TableCount | Should -Be 24
    }

    # Mutation: drop the profile name/label from the preflight reason, or skip the database-name
    # safety check for auto-create profiles -> no reason line, or setup proceeds and writes.
    It 'blocks a Golden Tee Live 2020 profile with a missing or unsafe database name, names the game, and writes nothing (<Name>)' -ForEach @(
        @{ Name = 'blank'; DbName = '' },
        @{ Name = 'unsafe'; DbName = 'Game-DB20' }
    ) {
        $fx = New-F59Fixture -Name ('badname-' + $Name)
        $file = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName $DbName -AutoCreate '1' -Backup
        $before = [System.IO.File]::ReadAllBytes($file)
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $reasons = @(Get-PostgresSetupFailureReasonLines -TransactionResult $result)
        $reasons.Count | Should -Be 1
        $reasons[0] | Should -Match 'Golden Tee Live 2020 \[GoldenTeeLive2020\]: The profile has no safe PostgreSQL database name'
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        $fx.State.Events.Contains('backup') | Should -BeFalse
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 0
    }
}

Describe 'FIX59 Library Health separates TeknoParrot-created databases from the other profiles' {
    BeforeEach {
        $script:healthRoot = Join-Path $TestDrive ('f59-health-' + [guid]::NewGuid().ToString('N'))
        $script:profiles = Join-Path $script:healthRoot 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:profiles)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:healthRoot 'GameProfiles'))
        $script:PostgresServiceName = 'FIX59-test-service-must-never-exist'
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

    # Mutation: drop the auto-create classification (or count every populated profile as
    # auto-create) -> the list is empty, or it names Golden Tee Live 2019 and the legacy game.
    It 'lists only the explicit auto-create game, says a missing database is expected before first launch, and still counts all populated profiles' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Complete
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -Pass 'synthetic-pass' -AutoCreate '0' -Complete
        $null = New-F59Profile -Fixture $fx -ProfileName 'LegacyItGame' -GameName 'Legacy IT Game' -DbName 'GameDBLegacy' -Pass 'synthetic-pass' -AutoCreate '' -Complete

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        $result.PostgresInventoryStatus | Should -BeExactly 'Complete'
        $result.PostgresConfigured | Should -Be 3
        @($result.PostgresNeeded).Count | Should -Be 0
        @($result.PostgresAutoCreateProfiles).Count | Should -Be 1
        @($result.PostgresAutoCreateProfiles)[0] | Should -BeExactly 'Golden Tee Live 2020'
        # The default screen is short; the first-run list and its explanation are behind D (the detail blocks) and in the log.
        $details = Get-F59HealthPostgresDetail -Result $result
        $firstRun = @($details -split "`n" | Where-Object { $_ -like 'Games with no starting database file:*' })
        $firstRun.Count | Should -Be 1
        $firstRun[0] | Should -BeExactly 'Games with no starting database file: Golden Tee Live 2020'
        $details | Should -Match 'These games make their own database'
        $details | Should -Not -Match '(?i)expected until the first launch|does not create it|cannot make the database'
        # PostgreSQL is not running here, so nobody has looked at the database: the game is not called "waiting".
        $details | Should -Not -Match 'Profile ready; the database is created'
        $logged = $script:logLines -join "`n"
        $logged | Should -Match ([regex]::Escape('Library health detail [PostgreSQL]: Games with no starting database file: Golden Tee Live 2020'))
        Should -Invoke Start-Service -Times 0 -Exactly
        Should -Invoke Stop-Service -Times 0 -Exactly
    }

    # Mutation: treat a missing database of a game with no starting file as a failure -> ACTION_REQUIRED and a "Problem" row
    # for a game that only has to be started once. A missing database of a game that DOES ship a backup stays a problem
    # (covered by the test below), and a game whose database exists is not listed as waiting.
    It 'says the profile is ready and the database is created the first time the game starts, and is not a problem (<Case>)' -ForEach @(
        @{ Case = 'database not made yet'; Ready = $false; Waiting = $true }
        @{ Case = 'database already there'; Ready = $true; Waiting = $false }
    ) {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Complete
        [System.IO.File]::WriteAllText((Join-Path $script:PostgresBinDir 'psql.exe'), 'x')
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        $script:F59Ready = $Ready
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $script:F59Ready; TableCount = $(if ($script:F59Ready) { 24 } else { 0 }); Error = $(if ($script:F59Ready) { $null } else { 'Could not connect with the settings saved in the game profile: FATAL: database "GameDB20" does not exist' }) } }
        Mock New-PostgresDatabaseFromBackup { throw 'health check must never create a database' }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresDatabaseProblems).Count | Should -Be 0
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $row = (Get-TpmLibraryHealthPostgresRow -Result $result).Text
        $details = Get-F59HealthPostgresDetail -Result $result
        if ($Waiting) {
            @($result.PostgresAwaitingFirstStart) | Should -Be @('Golden Tee Live 2020')
            $row | Should -Match '^OK - profile ready; a game database is created the first time the game starts'
            $details | Should -Match ([regex]::Escape('Profile ready; the database is created the first time the game starts: Golden Tee Live 2020'))
            $details | Should -Not -Match 'every game database is there'
        } else {
            @($result.PostgresAwaitingFirstStart).Count | Should -Be 0
            $row | Should -BeExactly 'OK'
            $details | Should -Not -Match 'Profile ready; the database is created'
            $details | Should -Match 'every game database is there'
        }
        Should -Invoke New-PostgresDatabaseFromBackup -Times 0 -Exactly
    }

    # Mutation: leave the shared name out of the health scan -> two games on one database are reported as fine.
    It 'says two games that use the same database share it, needs attention, and says setup keeps both sets of progress' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2006' -GameName 'Golden Tee Live 2006' -DbName 'GameDB06' -Pass 'synthetic-pass' -AutoCreate '' -Complete
        $null = New-F59Profile -Fixture $fx -ProfileName 'OCCPinball' -GameName 'Orange County Choppers Pinball' -DbName 'GameDB06' -Pass 'synthetic-pass' -AutoCreate '' -Complete
        $null = New-F59Profile -Fixture $fx -ProfileName 'PowerPuttLive2013' -GameName 'Power Putt Live 2013' -DbName 'GameDBPPL13' -Pass 'synthetic-pass' -AutoCreate '' -Complete

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresSharedDatabases).Count | Should -Be 1
        $result.PostgresSharedDatabases[0] | Should -BeExactly 'Golden Tee Live 2006 and Orange County Choppers Pinball use the same database, GameDB06'
        # A finished check that found a shared database is a finding, not a check that could not finish (exit code 0).
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        (Get-TpmLibraryHealthPostgresRow -Result $result).Text | Should -Match '^Needs attention - some games use the same database\. Run Postgres setup \(menu 12\)'
        $details = Get-F59HealthPostgresDetail -Result $result
        $details | Should -Match 'Problem - Golden Tee Live 2006 and Orange County Choppers Pinball use the same database, GameDB06'
        $details | Should -Match 'deletes nothing and keeps both sets of progress'
    }

    # Mutation: classify by the auto-create flag before the profile is complete -> a profile
    # that still needs setup would be reported as waiting for TeknoParrot's first run.
    It 'keeps an auto-create profile with a blank password in the setup-needed list, not in the first-run list' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass '' -AutoCreate '1' -Complete

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresNeeded) | Should -Be @('GoldenTeeLive2020')
        $result.PostgresConfigured | Should -Be 0
        @($result.PostgresAutoCreateProfiles).Count | Should -Be 0
        (Get-F59HealthPostgresDetail -Result $result) | Should -Not -Match 'Profile ready; the database is created'
        ($script:logLines -join "`n") | Should -Not -Match 'Profile ready; the database is created'
    }

    # Mutation: report the auto-create list when profile coverage is incomplete -> the
    # list would be shown even though the inventory counts are withheld.
    It 'withholds the auto-create list when the profile inventory is incomplete' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Complete
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'BAD.xml'), '<GameProfile>')

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        $result.PostgresInventoryStatus | Should -BeExactly 'Unknown'
        @($result.PostgresAutoCreateProfiles).Count | Should -Be 0
        (Get-F59HealthPostgresDetail -Result $result) | Should -Not -Match 'Profile ready; the database is created'
        ($script:logLines -join "`n") | Should -Not -Match 'Profile ready; the database is created'
    }

    # Mutation: leave the database check out of the health scan -> a missing database is reported OK.
    It 'reports a game database that is <Expected> as a problem, points to Postgres setup, and creates nothing' -ForEach @(
        @{ ErrorText = 'Could not connect with the settings saved in the game profile: FATAL: database "GameDB20" does not exist'; Expected = 'its database is missing' },
        @{ ErrorText = 'Found 0 tables, expected at least 1.'; Expected = 'its database has no tables' },
        @{ ErrorText = 'Could not connect with the settings saved in the game profile: password authentication failed'; Expected = 'the game cannot connect to its database with its own settings' }
    ) {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Backup -Complete
        [System.IO.File]::WriteAllText((Join-Path $script:PostgresBinDir 'psql.exe'), 'x')
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        $script:F59ReadyError = $ErrorText
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = $script:F59ReadyError } }
        Mock New-PostgresDatabaseFromBackup { throw 'health check must never create a database' }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresDatabaseProblems) | Should -Be @('Golden Tee Live 2020: ' + $Expected)
        # A finished check that found a database problem is a finding, not a check that could not finish (exit code 0).
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        (Get-TpmLibraryHealthPostgresRow -Result $result).Text | Should -Match 'Problem .*Postgres setup \(menu 12\)'
        $details = Get-F59HealthPostgresDetail -Result $result
        $details | Should -Match ([regex]::Escape('Problem - Golden Tee Live 2020: ' + $Expected))
        $details | Should -Match 'creates and checks these databases'
        $details | Should -Not -Match '(?i)first launch|first run|unverified'
        ($script:logLines -join "`n") | Should -Match 'HealthCheck: database problem for Golden Tee Live 2020'
        Should -Invoke New-PostgresDatabaseFromBackup -Times 0 -Exactly
    }

    # Mutation: treat a profile with no capability value as "TeknoParrot creates it" (or call it a plain missing database) ->
    # the unknown list is empty, or the user is told to run setup for a database setup will not make.
    It 'says plainly when the profile does not say who creates the database, and lists the Golden Tee Live 2020 checks, without creating anything' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '' -Complete
        [System.IO.File]::WriteAllText((Join-Path $script:PostgresBinDir 'psql.exe'), 'x')
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = 'Could not connect with the settings saved in the game profile: FATAL: database "GameDB20" does not exist' } }
        Mock New-PostgresDatabaseFromBackup { throw 'health check must never create a database' }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresCapabilityUnknown) | Should -Be @('Golden Tee Live 2020')
        @($result.PostgresDatabaseProblems)[0] | Should -Match 'no starting database file came with the game'
        $details = Get-F59HealthPostgresDetail -Result $result
        $details | Should -Match ([regex]::Escape('The profile does not say who creates the database: Golden Tee Live 2020'))
        $details | Should -Match ([regex]::Escape('Golden Tee Live 2020 - Database name: GameDB20. No other game uses it.'))
        $details | Should -Match ([regex]::Escape('Golden Tee Live 2020 - Who makes the database: the profile does not say.'))
        Should -Invoke New-PostgresDatabaseFromBackup -Times 0 -Exactly
    }

    # Mutation: report OK without checking, or skip the problem list when the check passes.
    It 'says every game database is ready when the check passes' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Backup -Complete
        [System.IO.File]::WriteAllText((Join-Path $script:PostgresBinDir 'psql.exe'), 'x')
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $true; TableCount = 24; Error = $null } }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresDatabaseProblems).Count | Should -Be 0
        (Get-TpmLibraryHealthPostgresRow -Result $result).Text | Should -BeExactly 'OK'
        (Get-F59HealthPostgresDetail -Result $result) | Should -Match 'every game database is there, opens with the game''s own settings and has tables'
    }

    # Mutation: connect (or fail the scan) when PostgreSQL is not installed -> no plain "skipped" line.
    It 'skips the database check plainly when PostgreSQL is not installed' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Backup -Complete
        Mock Get-Service { throw ([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('none'), 'NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.GetServiceCommand', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)) }
        Mock Get-PostgresGameDatabaseReadiness { throw 'no connection expected' }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        $result.PostgresDatabaseCheck | Should -BeExactly 'SkippedNotInstalled'
        @($result.PostgresDatabaseProblems).Count | Should -Be 0
        (Get-F59HealthPostgresDetail -Result $result) | Should -Match 'Database check: skipped, because PostgreSQL is not installed'
        Should -Invoke Get-PostgresGameDatabaseReadiness -Times 0 -Exactly
    }

    # What a user sees with the new Internal storage choice. Mutation: ignore Storage -> the Internal game is listed as needing PostgreSQL
    # setup (and its database is opened); or the Existing PostgreSQL game is skipped too -> its setup need disappears.
    It 'skips every PostgreSQL check for an Internal game, says so in plain words, and still checks the Existing PostgreSQL game' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2026' -GameName 'Golden Tee Live 2026' -DbName 'GameDB26' -Pass '' -AutoCreate '1' -Storage 'Internal'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2025' -GameName 'Golden Tee Live 2025' -DbName 'GameDB25' -Pass '' -AutoCreate '1' -Storage 'Existing PostgreSQL'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -Pass '' -AutoCreate '0'
        Mock Get-PostgresGameDatabaseReadiness { throw 'no connection expected' }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresNeeded | Sort-Object) | Should -Be @('GoldenTeeLive2019', 'GoldenTeeLive2025')
        @($result.InternalDatabaseLabels) | Should -Be @('Golden Tee Live 2026')
        @($result.PostgresDatabaseProblems).Count | Should -Be 0
        $row = @(Get-TpmLibraryHealthRows -Result $result | Where-Object { $_.Area -eq 'Game database' })
        $row.Count | Should -Be 1
        $row[0].Text | Should -Match 'no database install is needed'
        $row[0].Text | Should -Match 'Start each game once so it creates its own database'
        $details = Get-F59HealthPostgresDetail -Result $result
        $details | Should -Match 'Games using Internal storage \(no PostgreSQL needed\): Golden Tee Live 2026'
        $details | Should -Match 'Internal is the new default'
        $details | Should -Match 'Existing PostgreSQL is for keeping an existing PostgreSQL server and its saved progress'
        Should -Invoke Get-PostgresGameDatabaseReadiness -Times 0 -Exactly
    }

    # Mutation: treat Internal as a PostgreSQL game when its Postgres fields are filled in -> a "database missing" problem appears for it.
    It 'never reports a missing database for an Internal game, even when its old PostgreSQL fields are filled in' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2026' -GameName 'Golden Tee Live 2026' -DbName 'GameDB26' -Pass 'synthetic-pass' -AutoCreate '1' -Complete -Storage 'Internal'
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = 'database "GameDB26" does not exist' } }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        $result.PostgresConfigured | Should -Be 0
        @($result.PostgresDatabaseProblems).Count | Should -Be 0
        $null | Should -Be (Get-TpmLibraryHealthPostgresRow -Result $result)
        Should -Invoke Get-PostgresGameDatabaseReadiness -Times 0 -Exactly
    }

    # Mutation: count nothing or count Internal games as needing setup -> the Postgres setup screen shows the wrong numbers.
    It 'counts Internal games apart from the games that need PostgreSQL in the setup scan' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $files = @(
            (New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2026' -GameName 'Golden Tee Live 2026' -DbName 'GameDB26' -Storage 'Internal'),
            (New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2025' -GameName 'Golden Tee Live 2025' -DbName 'GameDB25' -Storage 'Existing PostgreSQL'),
            (New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19')
        ) | ForEach-Object { Get-Item -LiteralPath $_ }

        $scan = Get-TpmPostgresRequirementScan -ProfileFiles @($files)

        $scan.NeedCount | Should -Be 2
        $scan.InternalCount | Should -Be 1
        $scan.ScanBlocked | Should -BeFalse
    }
}

Describe 'FIX59 reinitialize never offers a Golden Tee Live 2020 reset without a starting database that ships with the game' {
    BeforeEach {
        Mock Read-HostSafe { throw 'no prompt expected' }
        Mock Start-PostgresRecoveryAsAdministrator { throw 'no administrator handoff expected' }
    }

    # Mutation: remove the missing-starting-database block -> the YES prompt appears (the
    # Read-HostSafe mock throws) and the failure only shows after the user confirmed.
    It 'stops before the YES prompt, names the game, and says TeknoParrot owns database creation' {
        $fx = New-F59Fixture -Name 'reinit-none'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Complete
        Install-F59ChoiceMocks -Fixture $fx

        $choice = Invoke-F59Choice -Fixture $fx -Database 'GameDB20'

        $choice.Outcome | Should -BeExactly 'Blocked'
        $choice.Error | Should -BeExactly 'REBUILD_BACKUP_MISSING'
        @($choice.Plans).Count | Should -Be 1
        $choice.Plans[0].ProfileName | Should -BeExactly 'GoldenTeeLive2020'
        $choice.Plans[0].AutoCreate | Should -BeTrue
        Should -Invoke Read-HostSafe -Times 0 -Exactly
        Should -Invoke Start-PostgresRecoveryAsAdministrator -Times 0 -Exactly
        $screen = $fx.State.Screen -join "`n"
        $screen | Should -Match 'Golden Tee Live 2020: no starting database was found with the game'
        $screen | Should -Not -Match 'GameDB20|GoldenTeeLive2020'
        $screen | Should -Match 'tells TeknoParrot to create its database itself when it is missing'
        $screen | Should -Match 'Nothing was changed\.'
    }

    # Mutation: print the TeknoParrot-creates sentence for every profile -> a profile whose
    # capability is unknown would be told something its profile does not say.
    It 'does not claim TeknoParrot creates the database when the profile does not say so' {
        $fx = New-F59Fixture -Name 'reinit-unknown'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '' -Complete
        Install-F59ChoiceMocks -Fixture $fx

        $choice = Invoke-F59Choice -Fixture $fx -Database 'GameDB20'

        $choice.Outcome | Should -BeExactly 'Blocked'
        $choice.Error | Should -BeExactly 'REBUILD_BACKUP_MISSING'
        $screen = $fx.State.Screen -join "`n"
        $screen | Should -Match 'Golden Tee Live 2020: no starting database was found'
        $screen | Should -Not -Match 'create its database itself'
        Should -Invoke Read-HostSafe -Times 0 -Exactly
    }

    # Mutation: ignore the long-path flag in the plan -> a user whose game folder path is longer than 259 characters (Windows PowerShell 5.1, long paths off) is told no starting database exists.
    It 'says the game folder path is too long to read, instead of "no starting database", when Windows PowerShell cannot read it' {
        $fx = New-F59Fixture -Name 'reinit-longpath'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '' -Complete -Backup
        Install-F59ChoiceMocks -Fixture $fx
        Mock Get-TpmGameExeAvailability { 'PathTooLong' }

        $choice = Invoke-F59Choice -Fixture $fx -Database 'GameDB20'

        $choice.Outcome | Should -BeExactly 'Blocked'
        $choice.Error | Should -BeExactly 'REBUILD_BACKUP_MISSING'
        $screen = $fx.State.Screen -join "`n"
        $screen | Should -Match 'Golden Tee Live 2020: the game is in a folder path longer than 259 characters'
        $screen | Should -Not -Match 'no starting database was found'
        Should -Invoke Read-HostSafe -Times 0 -Exactly
    }

    # Mutation: select every Golden Tee profile (fuzzy title/year match) -> the 2019 profile
    # joins the plan, or the YES prompt is never reached for GameDB20.
    It 'plans only GameDB20 from its own bundled backup and still asks for YES; declining changes nothing' {
        $fx = New-F59Fixture -Name 'reinit-backup'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Complete -Backup
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -Pass 'synthetic-pass' -AutoCreate '0' -Complete -Backup
        Install-F59ChoiceMocks -Fixture $fx
        Mock Read-HostSafe { 'NO' }

        $choice = Invoke-F59Choice -Fixture $fx -Database 'GameDB20'

        $choice.Outcome | Should -BeExactly 'Cancelled'
        @($choice.Plans).Count | Should -Be 1
        $choice.Plans[0].ProfileName | Should -BeExactly 'GoldenTeeLive2020'
        $choice.Plans[0].Database | Should -BeExactly 'GameDB20'
        [string]$choice.Plans[0].BackupFile | Should -Match 'GoldenTeeLive2020[\\/]pg_backup[\\/]0001\.backup$'
        Should -Invoke Read-HostSafe -Times 1 -Exactly
        Should -Invoke Start-PostgresRecoveryAsAdministrator -Times 0 -Exactly
        ($fx.State.Screen -join "`n") | Should -Match 'Reinitialize canceled because YES was not typed exactly\. Nothing was changed\.'
    }
}

# Golden Tee Live 2006 and Orange County Choppers Pinball both ship with the database name GameDB06. Real backups of the Golden Tee Live games
# show the same 24 tables for every game, so one database cannot hold the progress of two games. The first profile keeps the name, the other
# gets its own database, and nothing is deleted from the shared one.
Describe 'FIX59 two games that name the same database each get their own, and nothing is lost' {
    BeforeAll {
        # A profile that already holds every value setup would write, so only a database name change can make setup save it.
        function Set-F59ProfileFullySetUp {
            param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$File)
            $doc = Read-Xml $File
            [void](Set-PostgresFieldValue $doc 'Path' ($Fixture.Bin.TrimEnd('\') + '\'))
            [void](Set-PostgresFieldValue $doc 'Address' '127.0.0.1')
            [void](Set-PostgresFieldValue $doc 'Port' '5432')
            [void](Set-PostgresFieldValue $doc 'User' 'postgres')
            [void](Set-PostgresFieldValue $doc 'Pass' 'fixture-password')
            Save-Xml $doc $File
        }
        function Get-F59BackupPath {
            param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$ProfileName)
            return (Join-Path (Join-Path (Join-Path $Fixture.Root ('Game-' + $ProfileName)) 'pg_backup') '0001.backup')
        }
        # A TAR backup the way pg_dump writes it: one toc.dat and one numbered .dat file per table.
        function New-F59TarBackup {
            param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$DataBytes)
            $stream = New-Object System.IO.MemoryStream
            foreach ($entry in @(@{ Name = 'toc.dat'; Bytes = [System.Text.Encoding]::ASCII.GetBytes('toc') }, @{ Name = '1001.dat'; Bytes = $DataBytes })) {
                $header = New-Object byte[] 512
                [System.Text.Encoding]::ASCII.GetBytes($entry.Name).CopyTo($header, 0)
                [System.Text.Encoding]::ASCII.GetBytes(([Convert]::ToString([int64]$entry.Bytes.Length, 8)).PadLeft(11, '0')).CopyTo($header, 124)
                $header[156] = [byte][char]'0'
                [System.Text.Encoding]::ASCII.GetBytes('ustar').CopyTo($header, 257)
                $stream.Write($header, 0, 512)
                $stream.Write($entry.Bytes, 0, $entry.Bytes.Length)
                $padding = (512 - ($entry.Bytes.Length % 512)) % 512
                if ($padding -gt 0) { $stream.Write((New-Object byte[] $padding), 0, $padding) }
            }
            $stream.Write((New-Object byte[] 1024), 0, 1024)
            [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
        }
    }

    # Mutation: restore both backups into the one shared database -> a single createdb, and the second game's data lands on top of the first.
    It 'creates GameDB06 for the first game and a separate database for the second, each restored from its own backup, and keeps the shared name for the first' {
        $fx = New-F59Fixture -Name 'shared-both'
        $gt = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2006' -GameName 'Golden Tee Live 2006' -DbName 'GameDB06' -AutoCreate '' -Backup
        $occ = New-F59Profile -Fixture $fx -ProfileName 'OCCPinball' -GameName 'Orange County Choppers Pinball' -DbName 'GameDB06' -AutoCreate '' -Backup
        [System.IO.File]::WriteAllText((Get-F59BackupPath -Fixture $fx -ProfileName 'GoldenTeeLive2006'), 'golden tee backup', (New-Object System.Text.UTF8Encoding $false))
        [System.IO.File]::WriteAllText((Get-F59BackupPath -Fixture $fx -ProfileName 'OCCPinball'), 'orange county choppers backup', (New-Object System.Text.UTF8Encoding $false))
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 2
        @(Get-F59Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database } | Sort-Object) | Should -Be @('GameDB06', 'GameDB06OCCPinball')
        @(Get-F59Calls -Tool 'dropdb.exe').Count | Should -Be 0
        $restores = @(Get-F59RestoreCalls)
        $restores.Count | Should -Be 2
        ($restores | Where-Object { $_.Database -ceq 'GameDB06' }).Arguments[-1] | Should -BeExactly (Get-F59BackupPath -Fixture $fx -ProfileName 'GoldenTeeLive2006')
        ($restores | Where-Object { $_.Database -ceq 'GameDB06OCCPinball' }).Arguments[-1] | Should -BeExactly (Get-F59BackupPath -Fixture $fx -ProfileName 'OCCPinball')
        (Get-F59Value -File $gt -Field 'DbName') | Should -BeExactly 'GameDB06'
        (Get-F59Value -File $occ -Field 'DbName') | Should -BeExactly 'GameDB06OCCPinball'
        $occOutcome = @($result.GameOutcomes | Where-Object { $_.Key -eq 'OCCPinball' })[0]
        $occOutcome.RenamedFrom | Should -BeExactly 'GameDB06'
        $occOutcome.SharesWith | Should -BeExactly 'Golden Tee Live 2006'
        @($result.GameOutcomes | Where-Object { $_.Key -eq 'GoldenTeeLive2006' })[0].RenamedFrom | Should -BeExactly ''
        (@($result.Warnings) -join ' | ') | Should -Match 'Own database for Orange County Choppers Pinball: it and Golden Tee Live 2006 both used the database name GameDB06\..*GameDB06 was not changed and nothing was deleted or overwritten'

        # A repeat run changes nothing: the names are now different.
        $second = Invoke-F59Setup -Fixture $fx
        $second.Outcome | Should -BeExactly 'NO_OP'
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 2
    }

    # Mutation: rename a game that has no partner -> a lone Orange County Choppers Pinball would be moved off its own database name.
    It 'does not change the database name of a game when no other game uses it' {
        $fx = New-F59Fixture -Name 'shared-one'
        $occ = New-F59Profile -Fixture $fx -ProfileName 'OCCPinball' -GameName 'Orange County Choppers Pinball' -DbName 'GameDB06' -AutoCreate '' -Backup
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F59Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDB06')
        (Get-F59Value -File $occ -Field 'DbName') | Should -BeExactly 'GameDB06'
        @($result.GameOutcomes)[0].RenamedFrom | Should -BeExactly ''
    }

    # Mutation: touch or restore over the existing shared database when the second game is added later -> GameDB06 is dropped, restored again, or its profile rewritten.
    It 'leaves an existing GameDB06 and the first game untouched, and saves the second game with its own new database even when nothing else about its profile changed' {
        $fx = New-F59Fixture -Name 'shared-existing'
        $fx.State.Exists['GameDB06'] = $true
        $gt = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2006' -GameName 'Golden Tee Live 2006' -DbName 'GameDB06' -AutoCreate '' -Backup
        $occ = New-F59Profile -Fixture $fx -ProfileName 'OCCPinball' -GameName 'Orange County Choppers Pinball' -DbName 'GameDB06' -AutoCreate '' -Backup
        Set-F59ProfileFullySetUp -Fixture $fx -File $gt
        Set-F59ProfileFullySetUp -Fixture $fx -File $occ
        $gtBefore = [System.IO.File]::ReadAllBytes($gt)
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F59Calls -Tool 'createdb.exe' | ForEach-Object { $_.Database }) | Should -Be @('GameDB06OCCPinball')
        @(Get-F59RestoreCalls | ForEach-Object { $_.Database }) | Should -Be @('GameDB06OCCPinball')
        @(Get-F59Calls -Tool 'dropdb.exe').Count | Should -Be 0
        $fx.State.Exists['GameDB06'] | Should -BeTrue
        [System.IO.File]::ReadAllBytes($gt) | Should -Be $gtBefore
        (Get-F59Value -File $occ -Field 'DbName') | Should -BeExactly 'GameDB06OCCPinball'
    }

    # Mutation: give the second game its own name but leave it with the shared one in the profile (or the reverse) -> the game opens the wrong database.
    It 'gives games with no starting file separate names too, so TeknoParrot makes two databases' {
        $fx = New-F59Fixture -Name 'shared-auto'
        $gt = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2006' -GameName 'Golden Tee Live 2006' -DbName 'GameDB06' -AutoCreate '1'
        $occ = New-F59Profile -Fixture $fx -ProfileName 'OCCPinball' -GameName 'Orange County Choppers Pinball' -DbName 'GameDB06' -AutoCreate '1'
        Install-F59SetupMocks -Fixture $fx
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = 'Could not connect with the settings saved in the game profile: FATAL: database "x" does not exist' } }

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 0
        (Get-F59Value -File $gt -Field 'DbName') | Should -BeExactly 'GameDB06'
        (Get-F59Value -File $occ -Field 'DbName') | Should -BeExactly 'GameDB06OCCPinball'
        @($result.GameOutcomes | ForEach-Object { $_.Outcome } | Select-Object -Unique) | Should -Be @('WaitingForFirstStart')
    }

    # Mutation: rename a profile whose own settings the owner chose to keep -> the owner's own settings are rewritten without being asked.
    It 'stops before changing anything when the second game keeps its own PostgreSQL settings and cannot be given its own database' {
        $fx = New-F59Fixture -Name 'shared-kept'
        $gt = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2006' -GameName 'Golden Tee Live 2006' -DbName 'GameDB06' -AutoCreate '' -Backup
        $occ = New-F59Profile -Fixture $fx -ProfileName 'OCCPinball' -GameName 'Orange County Choppers Pinball' -DbName 'GameDB06' -Pass 'owner-own-password' -AutoCreate '' -Backup -Complete
        $before = [System.IO.File]::ReadAllBytes($occ)
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 0
        [System.IO.File]::ReadAllBytes($occ) | Should -Be $before
        (@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) -join ' | ') | Should -Match 'OCCPinball.*GameDB06 is also used by the profile GoldenTeeLive2006.*cannot be given its own database'
    }

    # Mutation: pick UTF8 by name alone -> a backup whose data is not valid UTF-8 loses a whole table (the real Golden Tee Live 2006 backup does).
    It 'restores into SQL_ASCII when the backup data is not valid UTF-8, and keeps the rule by name otherwise' {
        $valid = Join-Path $TestDrive 'valid-utf8.backup'
        $invalid = Join-Path $TestDrive 'invalid-utf8.backup'
        $notTar = Join-Path $TestDrive 'not-a-tar.backup'
        New-F59TarBackup -Path $valid -DataBytes ([System.Text.Encoding]::UTF8.GetBytes("1`tcaf" + [char]0x00E9 + "`n"))
        New-F59TarBackup -Path $invalid -DataBytes ([byte[]](0x31, 0x09, 0x63, 0x61, 0x66, 0xBF, 0x0A))
        [System.IO.File]::WriteAllText($notTar, 'plain text, not a TAR archive')

        (Test-PostgresBackupDataIsUtf8 -BackupFile $valid) | Should -BeTrue
        (Test-PostgresBackupDataIsUtf8 -BackupFile $invalid) | Should -BeFalse
        (Test-PostgresBackupDataIsUtf8 -BackupFile $notTar) | Should -BeNullOrEmpty
        Get-PostgresRestoreEncoding -DbName 'GameDB06' -BackupFile $valid | Should -BeExactly 'UTF8'
        Get-PostgresRestoreEncoding -DbName 'GameDB06' -BackupFile $invalid | Should -BeExactly 'SQL_ASCII'
        Get-PostgresRestoreEncoding -DbName 'GameDB06' -BackupFile $notTar | Should -BeExactly 'UTF8'
        Get-PostgresRestoreEncoding -DbName 'GameDB06' | Should -BeExactly 'UTF8'
        Get-PostgresRestoreEncoding -DbName 'GameDB19' -BackupFile $invalid | Should -BeExactly 'SQL_ASCII'
    }
}
