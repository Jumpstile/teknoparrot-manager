#Requires -Module Pester

# FIX69 PostgreSQL setup, absent database, profile says "Automatically create Database"
# = 1. Owner finding (2026-11-03, his real library): TeknoParrot's own creation is not
# hands-free, it asks the user to browse for the database backup file. New rule:
# when the game ships exactly one bundled backup, TeknoParrot Manager creates and
# restores the database whatever the profile's auto-create value is (1, 0 or missing).
# Creation stays with TeknoParrot only when the game has no bundled backup, or the game executable cannot be found. When the game
# ships several candidate files, the newest one is used whatever the profile's auto-create value is (N18A, N18B).
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

    $productionPath = (Resolve-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX69 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix69FunctionFile = Join-Path $TestDrive 'tpm-fix69-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix69FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix69FunctionFile
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests\TpmExtractedScriptState.ps1')
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests\TpmFakePostgresInterpret.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force

    # Hardware and progress-line access is external to these tests.
    function Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = $null; Name = 'isolated fixture' } }
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
            if ($query -match 'count\(\*\)') { return (New-F69CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '24') }
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


Describe 'Finding 8: non-canonical connection fields' {
    It 'sets <Field>=<Value> then succeeds with canonical values' -ForEach @(
        @{ Field='Address'; Value='127.0.0.1' }, @{ Field='Address'; Value='localhost' }, @{ Field='Address'; Value='127.0.0.1 ' },
        @{ Field='Port'; Value='05432' }, @{ Field='User'; Value='POSTGRES' },
        @{ Field='Path'; Value='D:\other\pg\bin\' }) {
        $fx = New-F69Fixture -Name 'nc'
        $file = New-F69Profile -Fixture $fx -Name 'Game1' -DbName 'GameDB1' -AutoCreate '1' -BackupFiles @('0001.backup') -Complete
        $x = [System.IO.File]::ReadAllText($file).Replace('C:\fixture\pg\bin\', ($fx.Bin.TrimEnd('\') + '\'))
        $realPath = $fx.Bin.TrimEnd('\') + '\'
        $canon = @{ Address='127.0.0.1'; Port='5432'; User='postgres'; Path=$realPath }[$Field]
        $x = $x.Replace("<FieldName>$Field</FieldName><FieldValue>$canon</FieldValue>", "<FieldName>$Field</FieldName><FieldValue>$Value</FieldValue>")
        [System.IO.File]::WriteAllText($file, $x)
        Install-F69Mocks -Fixture $fx
        $result = Invoke-F69Setup -Fixture $fx
        [Console]::Error.WriteLine('REASONS: ' + ((@(Get-PostgresSetupFailureReasonLines -TransactionResult $result) + @($result.Warnings)) -join ' | ') + ' LOG: ' + (($fx.State.Log | Select-Object -Last 4) -join ' / '))
        [Console]::Error.WriteLine(("OUTCOME[{0}=[{1}]]: {2}" -f $Field, $Value, $result.Outcome))
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
    }
}
