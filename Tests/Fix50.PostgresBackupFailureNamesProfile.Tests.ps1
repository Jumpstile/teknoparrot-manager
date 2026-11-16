#Requires -Module Pester

# FIX50 PostgreSQL backup-failure screen names the profile and the reason (found
# by reading in FIX48). Backup-PostgresDatabases runs BEFORE
# Invoke-PostgresGameSetup. A profile with a missing or unsafe database name used
# to be recorded without a diagnosis, so menu 13 stopped at "PostgreSQL setup
# stopped because the database backup did not complete." without saying which
# profile or why, and the log line appeared only when another database existed.
# Owner decision: a blocked profile always shows its own reason on the screen and
# in the log; nothing is changed (fail closed); a profile whose SAFE database name
# is merely absent in the server is not a backup failure (setup creates it).
#
# The production script is parsed and only its function definitions are
# dot-sourced; no top-level product code runs in this process. PostgreSQL is
# replaced by in-memory fakes (Get-PostgresDatabaseState and
# Invoke-PostgresNativeCommand are mocked), so no PostgreSQL server, service,
# registry or user configuration is touched; every file lives under TestDrive.
# Each It names the product mutation that makes it fail.

BeforeAll {
    $script:Fix50PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix50PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX50 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix50FunctionFile = Join-Path $TestDrive 'tpm-fix50-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix50FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix50FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:logPath = Join-Path $TestDrive 'fix50.log'

    # Postgres category with the owner's real field shape. A real-looking Pass is
    # written so the tests can prove it never reaches the log or the screen.
    function New-F50Profile {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][AllowEmptyString()][string]$DbName,
            [string]$GameName = ''
        )
        $title = if ($GameName) { $GameName } else { $Name }
        $xml = '<GameProfile><GameName>' + $title + '</GameName><ConfigValues>'
        foreach ($field in @(@('Path', ''), @('Address', '127.0.0.1'), @('Port', '5432'), @('DbName', $DbName), @('User', 'postgres'), @('Pass', 'profile-secret-Pass-7731'))) {
            $xml += '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $field[0] + '</FieldName><FieldValue>' + [System.Security.SecurityElement]::Escape($field[1]) + '</FieldValue></FieldInformation>'
        }
        $xml += '</ConfigValues></GameProfile>'
        $file = Join-Path $Fixture.Profiles ($Name + '.xml')
        [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $file
    }

    function New-F50Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f50-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
        $bin = Join-Path $root 'bin'
        $profiles = Join-Path $root 'UserProfiles'
        $backups = Join-Path $root 'backups'
        New-Item -ItemType Directory -Path $bin, $profiles, $backups -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $bin 'pg_dump.exe') -Force | Out-Null
        $state = [pscustomobject]@{
            Exists = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::Ordinal)
            StateQueries = New-Object System.Collections.Generic.List[string]
            DumpDatabases = New-Object System.Collections.Generic.List[string]
            Log = New-Object System.Collections.Generic.List[string]
            Screen = New-Object System.Collections.Generic.List[string]
        }
        return [pscustomobject]@{ Root = $root; Bin = $bin; Profiles = $profiles; Backups = $backups; State = $state }
    }

    function Install-F50Mocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F50State = $Fixture.State
        $script:F50Profiles = $Fixture.Profiles
        $script:F50Backups = $Fixture.Backups
        $script:PostgresBinDir = $Fixture.Bin
        Mock Write-Log { [void]$script:F50State.Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F50State.Screen.Add(([string]($Object -join ' '))) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Test-PostgresInstalled { $true }
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { @(Get-ChildItem -LiteralPath $script:F50Profiles -Filter '*.xml' -File) }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            [void]$script:F50State.StateQueries.Add($DbName)
            $exists = $false
            if ($script:F50State.Exists.ContainsKey($DbName)) { $exists = [bool]$script:F50State.Exists[$DbName] }
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
        Mock Get-TpmOwnedBackupsRoot { $script:F50Backups }
        Mock Assert-TpmNoReparseWriteTarget {}
        Mock Invoke-PostgresNativeCommand {
            param([string]$FilePath, [string[]]$Arguments, [string[]]$Secrets, [string]$PasswordPlain)
            $dest = [string]$Arguments[$Arguments.IndexOf('-f') + 1]
            [void]$script:F50State.DumpDatabases.Add([string]$Arguments[$Arguments.Count - 1])
            [System.IO.File]::WriteAllText($dest, 'dump', (New-Object System.Text.UTF8Encoding $false))
            return [pscustomobject]@{ ExitCode = 0; Output = '' }
        }
    }

    function Invoke-F50Backup {
        param([Parameter(Mandatory)]$Fixture)
        return (Backup-PostgresDatabases -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-super-password-4402')
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix50PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX50 backup failure names the profile and the reason' {
    Context 'unsafe or missing database name, no other database exists (early return path)' {
        # Mutation: drop the New-PostgresInvalidDatabaseNameDiagnosis call (old behavior: failedDatabases only)
        # -> FailureDiagnoses is empty and every assertion on the diagnosis fails. Mutation: echo $dbName in the
        # Detail -> the "does not contain the unsafe value" assertion fails. Mutation: query the server with the
        # unsafe name -> StateQueries is not empty.
        It 'records a named plain-language diagnosis, never echoes the unsafe value and never queries the server' {
            $fx = New-F50Fixture -Name 'unsafe'
            $null = New-F50Profile -Fixture $fx -Name 'BadNameGame' -DbName "Game'DB; DROP" -GameName 'Bad Name Game'
            Install-F50Mocks -Fixture $fx

            $result = Invoke-F50Backup -Fixture $fx

            $result.Succeeded | Should -BeFalse
            $result.NoOp | Should -BeFalse
            @($result.FailureDiagnoses).Count | Should -Be 1
            $diagnosis = @($result.FailureDiagnoses)[0]
            $diagnosis.Category | Should -BeExactly 'InvalidDatabaseName'
            $diagnosis.GameLabel | Should -BeExactly 'Bad Name Game'
            $diagnosis.ProfileKey | Should -BeExactly 'BadNameGame'
            $diagnosis.Detail | Should -Match 'contains characters that are not allowed'
            $diagnosis.Detail | Should -Not -Match 'DROP'
            $diagnosis.Database | Should -BeExactly ''
            ((@($result.FailureDetails) + @($result.FailedDatabases)) -join ' | ') | Should -Not -Match 'DROP'
            $fx.State.StateQueries.Count | Should -Be 0
            $fx.State.DumpDatabases.Count | Should -Be 0
            $result.Path | Should -BeNullOrEmpty
        }

        # Mutation: remove the early-return Write-Log or the per-profile Write-Log -> no log line names the
        # profile when no other database exists (the FIX48 finding).
        It 'always writes the per-profile reason to the log, also when no other database exists' {
            $fx = New-F50Fixture -Name 'log'
            $null = New-F50Profile -Fixture $fx -Name 'BadNameGame' -DbName 'bad name!' -GameName 'Bad Name Game'
            Install-F50Mocks -Fixture $fx

            $result = Invoke-F50Backup -Fixture $fx

            $result.Succeeded | Should -BeFalse
            $logText = $fx.State.Log -join "`n"
            $logText | Should -Match 'game profile Bad Name Game \[BadNameGame\] cannot be used for PostgreSQL setup: The database name in the game profile contains characters that are not allowed'
            $logText | Should -Match 'Postgres backup incomplete\. FailedDatabases=Bad Name Game / BadNameGame; FailureDetails=Bad Name Game \[BadNameGame\]: '
            $logText | Should -Not -Match 'profile-secret-Pass-7731'
            $logText | Should -Not -Match 'fixture-super-password-4402'
        }

        # Mutation: treat only unsafe (not blank) names as a problem, or give blank names the unsafe wording.
        It 'says the database name is missing when the DbName field is empty' {
            $fx = New-F50Fixture -Name 'missing'
            $null = New-F50Profile -Fixture $fx -Name 'NoNameGame' -DbName '' -GameName 'No Name Game'
            Install-F50Mocks -Fixture $fx

            $result = Invoke-F50Backup -Fixture $fx

            $result.Succeeded | Should -BeFalse
            @($result.FailureDiagnoses).Count | Should -Be 1
            @($result.FailureDiagnoses)[0].Detail | Should -BeExactly 'The database name is missing in the game profile.'
            @($result.FailureDiagnoses)[0].ProfileKey | Should -BeExactly 'NoNameGame'
            ($fx.State.Log -join "`n") | Should -Match 'No Name Game \[NoNameGame\] cannot be used for PostgreSQL setup: The database name is missing in the game profile\.'
        }
    }

    Context 'safe database name that does not exist in the server yet' {
        # Mutation: record an absent safe database as a backup failure (or skip the Exists check and add the
        # name to the backup list) -> Succeeded is false / a pg_dump call happens / a diagnosis appears.
        It 'is not a backup failure: nothing to back up, no diagnosis, no blocked-profile log line' {
            $fx = New-F50Fixture -Name 'absent'
            $null = New-F50Profile -Fixture $fx -Name 'NewGame' -DbName 'GameDBNew' -GameName 'New Game'
            Install-F50Mocks -Fixture $fx

            $result = Invoke-F50Backup -Fixture $fx

            $result.Succeeded | Should -BeTrue
            $result.NoOp | Should -BeTrue
            $result.FailedDatabaseCount | Should -Be 0
            @($result.FailureDiagnoses).Count | Should -Be 0
            @($result.FailedDatabases).Count | Should -Be 0
            $fx.State.StateQueries | Should -Contain 'GameDBNew'
            $fx.State.DumpDatabases.Count | Should -Be 0
            ($fx.State.Log -join "`n") | Should -Not -Match 'cannot be used for PostgreSQL setup'
        }
    }

    Context 'one blocked profile next to a healthy existing database' {
        # Mutation: stop scanning at the blocked profile (or skip dumping when anything failed) -> the healthy
        # database is not backed up; mutation: add the healthy profile to the diagnoses -> the count is 2.
        It 'still backs up the existing database, fails overall and diagnoses only the blocked profile' {
            $fx = New-F50Fixture -Name 'mixed'
            $fx.State.Exists['GameDBExisting'] = $true
            $null = New-F50Profile -Fixture $fx -Name 'ExistingGame' -DbName 'GameDBExisting' -GameName 'Existing Game'
            $null = New-F50Profile -Fixture $fx -Name 'BadNameGame' -DbName 'bad-name' -GameName 'Bad Name Game'
            $null = New-F50Profile -Fixture $fx -Name 'NewGame' -DbName 'GameDBNew' -GameName 'New Game'
            Install-F50Mocks -Fixture $fx

            $result = Invoke-F50Backup -Fixture $fx

            $result.Succeeded | Should -BeFalse
            $result.ExistingDatabaseCount | Should -Be 1
            @($fx.State.DumpDatabases) | Should -Be @('GameDBExisting')
            @($result.FailureDiagnoses).Count | Should -Be 1
            @($result.FailureDiagnoses)[0].ProfileKey | Should -BeExactly 'BadNameGame'
            @($result.FailedDatabases) | Should -Be @('Bad Name Game / BadNameGame')
            $logText = $fx.State.Log -join "`n"
            $logText | Should -Match 'Bad Name Game \[BadNameGame\] cannot be used for PostgreSQL setup'
            $logText | Should -Match 'Postgres backup incomplete'
            $logText | Should -Not -Match 'New Game'
        }
    }

    Context 'backup-failure screen' {
        # Mutation: print only Get-PostgresDiagnosisAffectedLabels (old screen) -> no reason line, no
        # "database name problem" heading. Mutation: print the reason for every diagnosis -> the healthy
        # connection failure line appears in the reason block.
        It 'lists every blocked profile with its game name, profile name and reason, and no secret' {
            $fx = New-F50Fixture -Name 'screen'
            $null = New-F50Profile -Fixture $fx -Name 'BadNameGame' -DbName 'bad name!' -GameName 'Bad Name Game'
            $null = New-F50Profile -Fixture $fx -Name 'NoNameGame' -DbName '' -GameName 'No Name Game'
            Install-F50Mocks -Fixture $fx
            $result = Invoke-F50Backup -Fixture $fx
            $connection = Get-PostgresFailureDiagnosis -GameLabel 'Other Game' -ProfileKey 'OtherGame' -DbName 'GameDBOther' -Detail 'connection refused'
            $diagnoses = @($result.FailureDiagnoses) + @($connection)
            $fx.State.Screen.Clear()

            Write-PostgresBackupFailureAffectedGames -Diagnoses $diagnoses

            $screen = $fx.State.Screen -join "`n"
            $screen | Should -Match '(?m)^  Affected games:$'
            $screen | Should -Match '(?m)^    Bad Name Game$'
            $screen | Should -Match '(?m)^    No Name Game$'
            $screen | Should -Match '(?m)^  Game profiles with a database name problem:$'
            $screen | Should -Match '(?m)^    Bad Name Game \[BadNameGame\]: The database name in the game profile contains characters that are not allowed \(only letters, digits and underscore\)\.$'
            $screen | Should -Match '(?m)^    No Name Game \[NoNameGame\]: The database name is missing in the game profile\.$'
            $screen | Should -Match 'Nothing was changed\.'
            $screen | Should -Not -Match '(?m)Other Game:'
            $screen | Should -Not -Match 'OtherGame'
            $screen | Should -Not -Match 'profile-secret-Pass-7731'
            $screen | Should -Not -Match 'fixture-super-password-4402'
            $screen | Should -Not -Match 'UserProfiles|[A-Za-z]:\\'
        }

        # Mutation: always print the "database name problem" heading.
        It 'prints no database-name block when the backup failed for another reason' {
            $fx = New-F50Fixture -Name 'screen-other'
            Install-F50Mocks -Fixture $fx
            $connection = Get-PostgresFailureDiagnosis -GameLabel 'Other Game' -ProfileKey 'OtherGame' -DbName 'GameDBOther' -Detail 'connection refused'

            Write-PostgresBackupFailureAffectedGames -Diagnoses @($connection)

            $screen = $fx.State.Screen -join "`n"
            $screen | Should -Match '(?m)^    Other Game$'
            $screen | Should -Not -Match 'OtherGame|GameDBOther'
            $screen | Should -Not -Match 'database name problem'
        }
    }

    Context 'reinitialize choice after a name-only failure' {
        # Mutation: remove the empty-selection guard in Invoke-PostgresReinitializeChoice -> plan discovery runs
        # with no database filter (every game database) and a YES prompt appears.
        It 'is blocked and never discovers plans for every database' {
            $fx = New-F50Fixture -Name 'reinit'
            Install-F50Mocks -Fixture $fx
            Mock Get-PostgresReinitializePlansFromProfiles { throw 'plan discovery must not run' }
            Mock Read-HostSafe { throw 'no prompt expected' }
            $diagnosis = New-PostgresInvalidDatabaseNameDiagnosis -GameLabel 'Bad Name Game' -ProfileKey 'BadNameGame' -Problem 'The database name is missing in the game profile.'

            $choice = Invoke-PostgresReinitializeChoice -FailureDiagnoses @($diagnosis) -UserProfilesDir $fx.Profiles `
                -ConfigPath (Join-Path $fx.Root 'config.json') -ScriptPath (Join-Path $fx.Root 'script.ps1') -TpRoot $fx.Root `
                -SuperPasswordPlain 'fixture-super-password-4402' -RecoveryBackup ([pscustomobject]@{ Path = $fx.Root; Verified = $true })

            $choice.Outcome | Should -BeExactly 'Blocked'
            @($choice.Plans).Count | Should -Be 0
            Should -Invoke Get-PostgresReinitializePlansFromProfiles -Times 0 -Exactly
            Should -Invoke Read-HostSafe -Times 0 -Exactly
            ($fx.State.Screen -join "`n") | Should -Match 'could not tell exactly which games and databases to rebuild\. Nothing was changed\.'
        }
    }

    Context 'diagnosis grouping' {
        # Mutation: drop InvalidDatabaseName from the category label table -> falls back to the generic
        # "PostgreSQL backup issue" name in the read-only diagnosis.
        It 'names the category in the read-only diagnosis' {
            $fx = New-F50Fixture -Name 'repair'
            Install-F50Mocks -Fixture $fx
            Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
            Mock Invoke-PostgresNativeCommand { [pscustomobject]@{ ExitCode = 0; Output = 'pg_dump (PostgreSQL) 8.3.23' } }
            $diagnosis = New-PostgresInvalidDatabaseNameDiagnosis -GameLabel 'Bad Name Game' -ProfileKey 'BadNameGame' -Problem 'The database name is missing in the game profile.'
            $backup = [pscustomobject]@{ Succeeded = $false; FailureDiagnoses = @($diagnosis); FailureDetails = @('Bad Name Game [BadNameGame]: The database name is missing in the game profile.'); FailedDatabases = @('Bad Name Game / BadNameGame') }

            $report = Get-PostgresBackupRepairDiagnosis -BackupResult $backup

            @($report.NormalChecks | Where-Object { $_.Name -eq 'Game profile database name' }).Count | Should -Be 1
            @($report.NormalChecks | Where-Object { $_.Name -eq 'PostgreSQL backup issue' }).Count | Should -Be 0
        }
    }
}
