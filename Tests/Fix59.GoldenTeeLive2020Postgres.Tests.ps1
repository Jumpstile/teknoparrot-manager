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

    # Mutation: bring back the deferral or an empty database for auto-create 1 without a backup -> setup says SUCCEEDED,
    # or createdb runs, or a profile is written.
    It 'leaves out the game, is not a clean success, and creates, restores and writes nothing when GameDB20 is absent and the game ships no pg_backup' {
        $fx = New-F59Fixture -Name 'nobackup'
        $file = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1'
        $before = [System.IO.File]::ReadAllBytes($file)
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 0
        @(Get-F59RestoreCalls).Count | Should -Be 0
        $fx.State.Events.Contains('backup') | Should -BeFalse
        [System.IO.File]::ReadAllBytes($file) | Should -Be $before
        @($result.NotReadyGames | ForEach-Object { $_.Key }) | Should -Be @('GoldenTeeLive2020')
        (@($result.Warnings) -join ' | ') | Should -Match 'Golden Tee Live 2020 \[GoldenTeeLive2020\] \(GameDB20\): not made ready\. No starting database file came with this game, so its database cannot be built\.'
        (@($result.Warnings) -join ' | ') | Should -Not -Match '(?i)start (it|the game) once|TeknoParrot will'
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

    # Mutation: let an auto-create profile and another profile share one absent database although they resolve to different
    # bundled backups -> one of them would be created from the other's backup.
    It 'refuses to guess when another profile names the same absent GameDB20 and creates nothing' {
        $fx = New-F59Fixture -Name 'shared'
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -AutoCreate '1' -Backup
        $null = New-F59Profile -Fixture $fx -ProfileName 'ZSharedGame' -GameName 'Shared Game' -DbName 'GameDB20' -AutoCreate '' -Backup
        Install-F59SetupMocks -Fixture $fx

        $result = Invoke-F59Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $reasons = @(Get-PostgresSetupFailureReasonLines -TransactionResult $result)
        $reasons.Count | Should -Be 2
        foreach ($reason in $reasons) { $reason | Should -Match 'shared by profiles GoldenTeeLive2020, ZSharedGame' }
        $reasons[0] | Should -Match '^Golden Tee Live 2020 \[GoldenTeeLive2020\]:'
        @(Get-F59Calls -Tool 'createdb.exe').Count | Should -Be 0
        $fx.State.Events.Contains('backup') | Should -BeFalse
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
        $firstRun = @($details -split "`n" | Where-Object { $_ -like 'Profile ready; the database is created the first time the game starts:*' })
        $firstRun.Count | Should -Be 1
        $firstRun[0] | Should -BeExactly 'Profile ready; the database is created the first time the game starts: Golden Tee Live 2020'
        $details | Should -Match 'These games make their own database'
        $details | Should -Not -Match '(?i)expected until the first launch|does not create it|cannot make the database'
        $logged = $script:logLines -join "`n"
        $logged | Should -Match ([regex]::Escape('Library health detail [PostgreSQL]: Profile ready; the database is created the first time the game starts: Golden Tee Live 2020'))
        Should -Invoke Start-Service -Times 0 -Exactly
        Should -Invoke Stop-Service -Times 0 -Exactly
    }

    # Mutation: report a missing database of an auto-create game with no starting file as a problem again -> the health check says
    # "its database is missing" and ACTION_REQUIRED for a game that is ready and makes its own database on first start.
    It 'does not call a missing database a problem for an auto-create game with no starting file' {
        $fx = [pscustomobject]@{ Root = $script:healthRoot; Profiles = $script:profiles }
        $null = New-F59Profile -Fixture $fx -ProfileName 'GoldenTeeLive2020' -GameName 'Golden Tee Live 2020' -DbName 'GameDB20' -Pass 'synthetic-pass' -AutoCreate '1' -Complete
        [System.IO.File]::WriteAllText((Join-Path $script:PostgresBinDir 'psql.exe'), 'x')
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Get-PostgresGameDatabaseReadiness { [pscustomobject]@{ Ready = $false; TableCount = 0; Error = 'Could not connect with the settings saved in the game profile: FATAL: database "GameDB20" does not exist' } }

        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot

        @($result.PostgresDatabaseProblems).Count | Should -Be 0
        $result.Outcome | Should -Not -BeExactly 'ACTION_REQUIRED'
        $details = Get-F59HealthPostgresDetail -Result $result
        $details | Should -Match ([regex]::Escape('Profile ready; the database is created the first time the game starts: Golden Tee Live 2020'))
        $details | Should -Not -Match 'Problem - |every game database is there'
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
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        (Get-TpmLibraryHealthPostgresRow -Result $result).Text | Should -Match 'Problem .*Postgres setup \(menu 11\)'
        $details = Get-F59HealthPostgresDetail -Result $result
        $details | Should -Match ([regex]::Escape('Problem - Golden Tee Live 2020: ' + $Expected))
        $details | Should -Match 'creates and checks these databases'
        $details | Should -Not -Match '(?i)first launch|first run|unverified'
        ($script:logLines -join "`n") | Should -Match 'HealthCheck: database problem for Golden Tee Live 2020'
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
