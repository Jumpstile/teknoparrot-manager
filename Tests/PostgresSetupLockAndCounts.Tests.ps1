#Requires -Module Pester

# PostgreSQL setup counts, the "another window is busy" guard, a database another window just made, and the encoding a restore recreates.
# Only the production function definitions are dot-sourced; the PostgreSQL 8.3 tools are one in-memory fake. Every file lives under TestDrive.

BeforeAll {
    $script:PSLPrior = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:PSLPrior[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText($productionPath), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The production script could not be parsed.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:PSLFunctionFile = Join-Path $TestDrive 'psl-functions.ps1'
    [System.IO.File]::WriteAllText($script:PSLFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:PSLFunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $progressDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressDirectory 'TpmProgress.psm1') -Force

    function New-PSLFixture {
        $root = Join-Path $TestDrive ('psl-' + [guid]::NewGuid().ToString('N'))
        $dirs = @{ Bin = Join-Path $root 'bin'; Evidence = Join-Path $root 'evidence'; Profiles = Join-Path $root 'UserProfiles' }
        New-Item -ItemType Directory -Path @($dirs.Values) -Force | Out-Null
        foreach ($tool in @(Get-Postgres83RestoreToolNames)) { New-Item -ItemType File -Path (Join-Path $dirs.Bin $tool) -Force | Out-Null }
        $state = [pscustomobject]@{
            Exists = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::Ordinal)
            Calls = New-Object System.Collections.Generic.List[object]
            AlreadyExists = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            FailCreate = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            JournalAtCreate = @{}
            JournalPath = Join-Path $root 'PostgresSetupCreatedDatabases.journal.json'
        }
        return [pscustomobject]@{ Root = $root; Bin = $dirs.Bin; Evidence = $dirs.Evidence; Profiles = $dirs.Profiles; State = $state }
    }

    # A profile; -Connected writes the exact connection values setup wants, so setup has nothing to change in it.
    function New-PSLProfile {
        param($Fixture, [string]$Name, [string]$DbName, [switch]$Connected)
        $gameDir = Join-Path $Fixture.Root ('Game-' + $Name)
        New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
        $exe = Join-Path $gameDir 'game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        $backupDir = Join-Path $gameDir 'pg_backup'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $backupDir '0001.backup'), 'synthetic bundled backup', (New-Object System.Text.UTF8Encoding $false))
        $values = if ($Connected) { @(($Fixture.Bin.TrimEnd('\') + '\'), '127.0.0.1', '5432', 'postgres', 'fixture-password') } else { @('', '', '', '', '') }
        $xml = '<GameProfile><GameName>' + $Name + '</GameName><GamePath>' + $exe + '</GamePath><ConfigValues>'
        $fields = @(@('Path', $values[0]), @('Address', $values[1]), @('Port', $values[2]), @('DbName', $DbName), @('User', $values[3]), @('Pass', $values[4]))
        foreach ($field in $fields) { $xml += '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $field[0] + '</FieldName><FieldValue>' + $field[1] + '</FieldValue></FieldInformation>' }
        $file = Join-Path $Fixture.Profiles ($Name + '.xml')
        [System.IO.File]::WriteAllText($file, ($xml + '</ConfigValues></GameProfile>'), (New-Object System.Text.UTF8Encoding $false))
        return $file
    }

    function Invoke-PSLFakeCommand {
        param([string]$ToolName, [string[]]$Arguments)
        $state = $script:PSLState
        $database = ''
        $encoding = ''
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if ($Arguments[$i] -ceq '-d') { $database = [string]$Arguments[$i + 1] }
            if ($Arguments[$i] -ceq '-E') { $encoding = [string]$Arguments[$i + 1] }
        }
        if ($ToolName -in @('createdb.exe', 'dropdb.exe')) { $database = [string]$Arguments[$Arguments.Count - 1] }
        [void]$state.Calls.Add([pscustomobject]@{ Tool = $ToolName; Database = $database; Encoding = $encoding; Arguments = @($Arguments) })
        $exit = 0
        $output = ''
        if ($Arguments -contains '--version') { $output = $ToolName + ' (PostgreSQL) 8.3.23' }
        elseif ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc' -and [string]$Arguments[$Arguments.Count - 1] -match 'count\(\*\)') { $output = '24' }
        elseif ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc') {
            $wanted = if ([string]$Arguments[$Arguments.Count - 1] -match "lower\('([^']+)'\)\s*$") { $Matches[1] } else { '' }
            $output = @($state.Exists.Keys | Where-Object { $state.Exists[$_] -and [string]::Equals($_, $wanted, [System.StringComparison]::OrdinalIgnoreCase) }) -join "`n"
        }
        elseif ($ToolName -eq 'createdb.exe') {
            $state.JournalAtCreate[$database] = if ([System.IO.File]::Exists($state.JournalPath)) { [System.IO.File]::ReadAllText($state.JournalPath) } else { $null }
            if ($state.AlreadyExists.Contains($database)) { $state.Exists[$database] = $true; $exit = 1; $output = 'ERROR: database "' + $database + '" already exists' }
            elseif ($state.FailCreate.Contains($database)) { $exit = 1; $output = 'createdb failed' }
            else { $state.Exists[$database] = $true }
        }
        elseif ($ToolName -eq 'dropdb.exe') { $state.Exists[$database] = $false }
        return [pscustomobject]@{ Tool = $ToolName; Executable = Join-Path $script:PostgresBinDir $ToolName; Arguments = @($Arguments); ExitCode = $exit; Succeeded = ($exit -eq 0); Output = $output }
    }

    # LockTaken is what Enter-PostgresRecoveryLock reports: $false is "another window holds it".
    function Install-PSLMocks {
        param($Fixture, [bool]$LockTaken = $true)
        $script:PSLState = $Fixture.State
        $script:PSLLockTaken = $LockTaken
        $script:PSLRecovery = [pscustomobject]@{ Path = $Fixture.Evidence; ConfigBackups = @(); Verified = $true; ProfileBackups = @() }
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-TpmText {}
        Mock Write-Host {}
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock Assert-PostgresRecoveryDirectoryAcl {}
        Mock Restore-PostgresProfileBackups { $true }
        Mock Enter-PostgresRecoveryLock { $script:PSLLockTaken }
        Mock Exit-PostgresRecoveryLock {}
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            Add-FakePostgresInterpretation -Command (Invoke-PSLFakeCommand -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            $exists = $script:PSLState.Exists.ContainsKey($DbName) -and [bool]$script:PSLState.Exists[$DbName]
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
    }

    function Invoke-PSLSetup { param($Fixture) return (Invoke-PostgresGameSetup -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password' -RecoveryBackup $script:PSLRecovery) }
    function Get-PSLCalls { param([string]$Tool) return @($script:PSLState.Calls | Where-Object { $_.Tool -eq $Tool -and $_.Arguments -notcontains '--version' }) }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:PSLPrior[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'PostgreSQL setup counts' {
    It 'counts a game whose database this run built as created, and only a game that was already set up as unchanged' {
        # Who gets hurt: the user reads "Already set up: 2" for a game whose database was only just built, so the summary overstates what was already fine.
        # Mutation: count every unchanged profile in AlreadyConfigured whatever its CreateMode -> AlreadyConfigured is 2 here.
        $fx = New-PSLFixture
        $null = New-PSLProfile -Fixture $fx -Name 'AGame' -DbName 'GameDBA' -Connected
        $null = New-PSLProfile -Fixture $fx -Name 'BGame' -DbName 'GameDBB' -Connected
        $fx.State.Exists['GameDBB'] = $true
        Install-PSLMocks -Fixture $fx

        $result = Invoke-PSLSetup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 1
        $result.AlreadyConfigured | Should -Be 1
        $result.Configured | Should -Be 0
    }
}

Describe 'PostgreSQL setup when createdb says the database already exists' {
    It 'keeps no drop note for it, never drops it, and does not report success' {
        # Who gets hurt: another window just built this database; a leftover "being built" note lets the next setup drop that window's data.
        # Mutation: remove the journal clear for the already-exists failure -> the file still names GameDBA as being created.
        $fx = New-PSLFixture
        $null = New-PSLProfile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.AlreadyExists.Add('GameDBA') | Out-Null
        Install-PSLMocks -Fixture $fx

        $result = Invoke-PSLSetup -Fixture $fx

        $fx.State.JournalAtCreate['GameDBA'] | Should -Match 'Creating'
        $result.Outcome | Should -Not -BeExactly 'SUCCEEDED'
        @(Get-PSLCalls -Tool 'dropdb.exe').Count | Should -Be 0
        $fx.State.Exists['GameDBA'] | Should -BeTrue
        $left = if ([System.IO.File]::Exists($fx.State.JournalPath)) { [System.IO.File]::ReadAllText($fx.State.JournalPath) } else { '' }
        $left | Should -Not -Match 'GameDBA'
    }
}

Describe 'PostgreSQL setup while another window is changing PostgreSQL' {
    It 'does nothing and says so when the lock is held elsewhere' {
        # Who gets hurt: two windows build and drop the same databases at once and damage each other's work.
        # Mutation: ignore the Enter-PostgresRecoveryLock result in the wrapper -> setup runs, createdb is called and the profile is rewritten.
        $fx = New-PSLFixture
        $file = New-PSLProfile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $before = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        Install-PSLMocks -Fixture $fx -LockTaken $false

        $result = Invoke-PSLSetup -Fixture $fx

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'POSTGRES_BUSY'
        foreach ($tool in @('createdb.exe', 'dropdb.exe', 'pg_restore.exe')) { @(Get-PSLCalls -Tool $tool).Count | Should -Be 0 }
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash | Should -BeExactly $before
        Should -Invoke Exit-PostgresRecoveryLock -Times 0 -Exactly
    }

    It 'lets go of the lock exactly once when it took it, even though setup failed' {
        # Who gets hurt: a failed setup keeps the lock, so every later repair in any window says "busy" until it is closed.
        # Mutation: release the lock only after a successful run (or never) -> Exit-PostgresRecoveryLock is called 0 times here.
        $fx = New-PSLFixture
        $null = New-PSLProfile -Fixture $fx -Name 'AGame' -DbName 'GameDBA'
        $fx.State.FailCreate.Add('GameDBA') | Out-Null
        Install-PSLMocks -Fixture $fx

        $result = Invoke-PSLSetup -Fixture $fx

        $result.Outcome | Should -Not -BeExactly 'SUCCEEDED'
        @(Get-PSLCalls -Tool 'createdb.exe').Count | Should -Be 1
        Should -Invoke Exit-PostgresRecoveryLock -Times 1 -Exactly
    }
}

Describe 'PostgreSQL restore recreates the database with the right encoding' {
    It 'uses the encoding the existing database has now, and the plan encoding when that is unknown' {
        # Who gets hurt: a restored database comes back in a different encoding than the one the game was using, and its text breaks.
        # Mutation: always pass the plan item's Encoding to createdb -> the first case creates SQL_ASCII instead of UTF8.
        foreach ($case in @(@{ Original = 'UTF8'; Expected = 'UTF8' }, @{ Original = ''; Expected = 'SQL_ASCII' })) {
            $fx = New-PSLFixture
            $fx.State.Exists['GameDBA'] = $true
            Install-PSLMocks -Fixture $fx
            $item = [pscustomobject]@{ ItemId = 'database:GameDBA'; Database = 'GameDBA'; BackupFile = (Join-Path $fx.Root 'GameDBA'); BackupSha256 = 'x'; Encoding = 'SQL_ASCII' }
            $preState = [pscustomobject]@{ Exists = $true; OriginalEncoding = $case.Original; RollbackDumpPath = ''; RollbackDumpSha256 = '' }

            $receipt = Invoke-Postgres83RestoreDatabase -Item $item -PreState $preState -SuperPasswordPlain 'fixture-password'

            $receipt.Succeeded | Should -BeTrue
            $create = @(Get-PSLCalls -Tool 'createdb.exe')
            $create.Count | Should -Be 1
            $create[0].Encoding | Should -BeExactly $case.Expected
        }
    }
}
