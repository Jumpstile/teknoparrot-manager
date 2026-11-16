#Requires -Module Pester

# Issue #370: PostgreSQL helpers must return exactly one typed result. The
# PGPASSWORD restoration runs in a `finally` block; any value that cleanup
# emits becomes part of the helper's output, so a failed authentication could
# become the truthy collection ($false, $true). Since FIX95 (S5) the password
# reaches psql only through PGPASSWORD around the one native call; no password
# file is written and PGPASSFILE is never touched. These tests drive the real
# helpers against synthetic psql/createdb/pg_restore/pg_dump executables (no
# PostgreSQL server, service, registry, or user configuration is touched).
# Inventory rows: PG-S10, INV-PG-05 (docs/RC8-REMEDIATION-INVENTORY.md).

BeforeAll {
    $script:PriorWorkflowVariableStates = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $priorValue = $null
        if ($null -ne $snapshot) { $priorValue = $snapshot.Value }
        $script:PriorWorkflowVariableStates[$name] = [pscustomobject]@{
            Exists = ($null -ne $snapshot)
            Value = $priorValue
        }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'PostgreSQL helper test bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'tpm-postgres-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    $script:logPath = Join-Path $TestDrive 'test.log'
    $script:logWarnShown = $false

    # One synthetic console program, copied under each tool name. Its exit code
    # and stdout come from FAKE_<TOOL>_EXIT / FAKE_<TOOL>_OUT. When
    # FAKE_<TOOL>_ENVFILE names a file, it records the PGPASSWORD and PGPASSFILE
    # values it inherited there and also prints PGPASSWORD to stdout (so the
    # caller's redaction can be checked). Compiled with the
    # .NET Framework C# compiler that ships with Windows, so both PowerShell
    # engines use the identical native binary.
    $script:FakeBin = Join-Path $TestDrive 'fakepg'
    [void][IO.Directory]::CreateDirectory($script:FakeBin)
    $source = Join-Path $TestDrive 'FakePgTool.cs'
    $code = @'
using System;
public static class FakePgTool {
  public static int Main(string[] args) {
    string name = System.IO.Path.GetFileNameWithoutExtension(System.Reflection.Assembly.GetEntryAssembly().Location).ToUpperInvariant();
    string output = Environment.GetEnvironmentVariable("FAKE_" + name + "_OUT");
    if (!String.IsNullOrEmpty(output)) { Console.WriteLine(output); }
    string envFile = Environment.GetEnvironmentVariable("FAKE_" + name + "_ENVFILE");
    if (!String.IsNullOrEmpty(envFile)) {
      string password = Environment.GetEnvironmentVariable("PGPASSWORD");
      string passFile = Environment.GetEnvironmentVariable("PGPASSFILE");
      System.IO.File.WriteAllLines(envFile, new string[] { "PGPASSWORD=" + (password == null ? "<unset>" : password), "PGPASSFILE=" + (passFile == null ? "<unset>" : passFile) });
      Console.WriteLine("PGPASSWORD=" + (password == null ? "<unset>" : password));
    }
    string exit = Environment.GetEnvironmentVariable("FAKE_" + name + "_EXIT");
    return String.IsNullOrEmpty(exit) ? 0 : Int32.Parse(exit);
  }
}
'@
    [IO.File]::WriteAllText($source, $code, (New-Object System.Text.UTF8Encoding $false))
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) { throw "The .NET Framework C# compiler was not found at $csc." }
    $built = Join-Path $script:FakeBin 'psql.exe'
    & $csc /nologo /target:exe "/out:$built" $source | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $built -PathType Leaf)) { throw 'The synthetic PostgreSQL tool could not be compiled.' }
    foreach ($tool in 'createdb', 'pg_restore', 'pg_dump', 'dropdb') {
        Copy-Item -LiteralPath $built -Destination (Join-Path $script:FakeBin "$tool.exe")
    }
    $script:PostgresBinDir = $script:FakeBin

    function Set-FakeTool {
        param([string]$Name, [string]$Exit = '', [string]$Out = '', [string]$EnvFile = '')
        [Environment]::SetEnvironmentVariable("FAKE_$($Name.ToUpperInvariant())_EXIT", $Exit, 'Process')
        [Environment]::SetEnvironmentVariable("FAKE_$($Name.ToUpperInvariant())_OUT", $Out, 'Process')
        [Environment]::SetEnvironmentVariable("FAKE_$($Name.ToUpperInvariant())_ENVFILE", $EnvFile, 'Process')
    }
    function Set-ProcessEnvironmentValue {
        # $null removes the variable; any other value is set as is.
        param([string]$Name, $Value)
        if ($null -eq $Value) { [Environment]::SetEnvironmentVariable($Name, [NullString]::Value, 'Process') }
        else { [Environment]::SetEnvironmentVariable($Name, [string]$Value, 'Process') }
    }
    function Reset-FakeTools {
        foreach ($n in 'psql', 'createdb', 'pg_restore', 'pg_dump', 'dropdb') { Set-FakeTool -Name $n }
    }
    function New-PostgresProfileFixture {
        param([string]$Directory, [string]$Name, [string]$DbName, [string]$GamePath, [string]$Pass = 'old', [string]$AutoCreate = '')
        $autoNode = if ($AutoCreate -ne '') { "<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Automatically create Database</FieldName><FieldValue>$AutoCreate</FieldValue></FieldInformation>" } else { '' }
        $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<GameProfile>
  <GamePath>$GamePath</GamePath>
  <ConfigValues>
    <FieldInformation><CategoryName>Postgres</CategoryName><FieldName>DbName</FieldName><FieldValue>$DbName</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Pass</FieldName><FieldValue>$Pass</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Path</FieldName><FieldValue>x</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Address</FieldName><FieldValue>127.0.0.1</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>Postgres</CategoryName><FieldName>Port</FieldName><FieldValue>5432</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>Postgres</CategoryName><FieldName>User</FieldName><FieldValue>postgres</FieldValue></FieldInformation>
    $autoNode
  </ConfigValues>
</GameProfile>
"@
        $path = Join-Path $Directory "$Name.xml"
        [IO.File]::WriteAllText($path, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $path
    }
}

AfterAll {
    try {
        $savedState = Get-Variable -Name PriorWorkflowVariableStates -Scope Script -ErrorAction SilentlyContinue
        if ($null -ne $savedState) {
            $snapshots = $savedState.Value
            foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
                if (-not $snapshots.ContainsKey($name)) { continue }
                $prior = $snapshots[$name]
                if ($prior.Exists) {
                    Set-Variable -Name $name -Value $prior.Value -Scope Script
                } else {
                    $currentWorkflowVariable = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
                    if ($null -ne $currentWorkflowVariable) {
                        Remove-Variable -Name $name -Scope Script
                    }
                }
            }
            Remove-Variable -Name PriorWorkflowVariableStates -Scope Script
        }
    } finally {
        foreach ($n in 'psql', 'createdb', 'pg_restore', 'pg_dump', 'dropdb') {
            [Environment]::SetEnvironmentVariable("FAKE_$($n.ToUpperInvariant())_EXIT", [NullString]::Value, 'Process')
            [Environment]::SetEnvironmentVariable("FAKE_$($n.ToUpperInvariant())_OUT", [NullString]::Value, 'Process')
            [Environment]::SetEnvironmentVariable("FAKE_$($n.ToUpperInvariant())_ENVFILE", [NullString]::Value, 'Process')
        }
    }
}

Describe 'PostgreSQL helper result contract (issue #370)' {
    BeforeEach {
        Reset-FakeTools
        $script:PgPasswordBefore = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
        $script:PgPassFileBefore = [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process')
    }
    AfterEach {
        Reset-FakeTools
        $pgPasswordAfter = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
        $pgPassFileAfter = [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process')
        # Put the caller's values back before asserting, so one failure cannot leak a password into later tests.
        Set-ProcessEnvironmentValue -Name 'PGPASSWORD' -Value $script:PgPasswordBefore
        Set-ProcessEnvironmentValue -Name 'PGPASSFILE' -Value $script:PgPassFileBefore
        ($null -eq $pgPasswordAfter) | Should -Be ($null -eq $script:PgPasswordBefore) -Because 'the process PGPASSWORD value must be restored exactly'
        if ($null -ne $script:PgPasswordBefore) { $pgPasswordAfter | Should -BeExactly $script:PgPasswordBefore -Because 'the process PGPASSWORD value must be restored exactly' }
        ($null -eq $pgPassFileAfter) | Should -Be ($null -eq $script:PgPassFileBefore) -Because 'the process PGPASSFILE value must never be touched'
        if ($null -ne $script:PgPassFileBefore) { $pgPassFileAfter | Should -BeExactly $script:PgPassFileBefore -Because 'the process PGPASSFILE value must never be touched' }
    }

    Context 'Test-PostgresPassword' {
        It 'returns exactly one Boolean <Expected> when psql exits <Exit>' -TestCases @(
            @{ Exit = '0'; Expected = $true }
            @{ Exit = '1'; Expected = $false }
            @{ Exit = '2'; Expected = $false }
        ) {
            param($Exit, $Expected)
            Set-FakeTool -Name psql -Exit $Exit
            $result = @(Test-PostgresPassword -SuperPasswordPlain 'pw')
            $result.Count | Should -Be 1
            $result[0] | Should -BeOfType [bool]
            $result[0] | Should -Be $Expected
        }

        It 'fails authentication as a falsy value usable directly in an if gate' {
            Set-FakeTool -Name psql -Exit '1'
            $gate = if (Test-PostgresPassword -SuperPasswordPlain 'pw') { 'accepted' } else { 'rejected' }
            $gate | Should -Be 'rejected'
        }

        It 'throws instead of returning success when restoring PGPASSWORD fails after successful authentication' {
            # Mutation: swallowing a Restore-PostgresPasswordEnvironment failure in Invoke-PostgresNativeCommand's finally makes
            # Test-PostgresPassword return $true while the password is still in the process environment.
            Set-FakeTool -Name psql -Exit '0'
            Mock Restore-PostgresPasswordEnvironment { throw 'Postgres: password environment restore failed.' }
            try {
                { [void](Test-PostgresPassword -SuperPasswordPlain 'pw') } | Should -Throw '*password environment restore failed*'
            } finally {
                # The mocked restore left the synthetic password set; put the caller's value back.
                Set-ProcessEnvironmentValue -Name 'PGPASSWORD' -Value $script:PgPasswordBefore
            }
        }

        It 'restores a <State> PGPASSWORD exactly and leaves PGPASSFILE untouched when <Helper> runs psql exiting <Exit>' -TestCases @(
            @{ State = 'unset'; Exit = '0'; Helper = 'Test-PostgresPassword' }
            @{ State = 'unset'; Exit = '1'; Helper = 'Test-PostgresPassword' }
            @{ State = 'empty'; Exit = '0'; Helper = 'Test-PostgresPassword' }
            @{ State = 'empty'; Exit = '1'; Helper = 'Test-PostgresPassword' }
            @{ State = 'nonempty'; Exit = '0'; Helper = 'Test-PostgresPassword' }
            @{ State = 'nonempty'; Exit = '1'; Helper = 'Test-PostgresPassword' }
            @{ State = 'unset'; Exit = '0'; Helper = 'Get-PostgresDatabaseState' }
            @{ State = 'unset'; Exit = '1'; Helper = 'Get-PostgresDatabaseState' }
            @{ State = 'empty'; Exit = '0'; Helper = 'Get-PostgresDatabaseState' }
            @{ State = 'empty'; Exit = '1'; Helper = 'Get-PostgresDatabaseState' }
            @{ State = 'nonempty'; Exit = '0'; Helper = 'Get-PostgresDatabaseState' }
            @{ State = 'nonempty'; Exit = '1'; Helper = 'Get-PostgresDatabaseState' }
        ) {
            param($State, $Exit, $Helper)
            # Mutation: not restoring PGPASSWORD in Invoke-PostgresNativeCommand's finally (the password stays set), restoring
            # by always removing it (a non-empty prior value is lost), typing Restore-PostgresPasswordEnvironment's parameter
            # as [string] (on PowerShell 7 an unset prior value comes back as ''), or leaving PGPASSFILE changed fails these assertions.
            try {
                switch ($State) {
                    'unset' { Set-ProcessEnvironmentValue -Name 'PGPASSWORD' -Value $null }
                    'empty' { [Environment]::SetEnvironmentVariable('PGPASSWORD', '', 'Process') }
                    'nonempty' { Set-ProcessEnvironmentValue -Name 'PGPASSWORD' -Value 'caller-prior-pgpassword' }
                }
                Set-ProcessEnvironmentValue -Name 'PGPASSFILE' -Value (Join-Path $TestDrive 'caller-pgpass-sentinel.conf')
                $established = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
                $passFileEstablished = [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process')
                # Windows PowerShell 5.1 (.NET Framework) cannot hold an empty
                # environment value; setting '' removes it, so there the
                # "empty" case is established as unset. PowerShell 7 keeps ''.
                if ($State -eq 'empty' -and $PSVersionTable.PSEdition -eq 'Core') { $established | Should -BeExactly '' }
                if ($State -eq 'unset') { ($null -eq $established) | Should -BeTrue }
                if ($State -eq 'nonempty') { $established | Should -BeExactly 'caller-prior-pgpassword' }
                Set-FakeTool -Name psql -Exit $Exit -Out '1'
                if ($Helper -eq 'Test-PostgresPassword') {
                    $result = @(Test-PostgresPassword -SuperPasswordPlain 'Helper-Secret-370')
                    $result.Count | Should -Be 1
                    $result[0] | Should -Be ($Exit -eq '0')
                } elseif ($Exit -eq '0') {
                    (Get-PostgresDatabaseState -DbName 'GameDB06' -SuperPasswordPlain 'Helper-Secret-370').Exists | Should -BeExactly $true
                } else {
                    { Get-PostgresDatabaseState -DbName 'GameDB06' -SuperPasswordPlain 'Helper-Secret-370' } | Should -Throw '*existence query failed*'
                }
                $after = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process')
                ($null -eq $after) | Should -Be ($null -eq $established)
                if ($null -ne $established) { $after | Should -BeExactly $established }
                [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process') | Should -BeExactly $passFileEstablished
            } finally {
                Set-ProcessEnvironmentValue -Name 'PGPASSWORD' -Value $script:PgPasswordBefore
                Set-ProcessEnvironmentValue -Name 'PGPASSFILE' -Value $script:PgPassFileBefore
            }
        }

        It 'hands the password to the psql child only through PGPASSWORD for <Helper> and redacts it from the returned output' -TestCases @(
            @{ Helper = 'Invoke-PostgresNativeCommand' }
            @{ Helper = 'Get-PostgresPasswordProbe' }
            @{ Helper = 'Get-PostgresDatabaseState' }
        ) {
            param($Helper)
            # Mutation: a caller that stops passing -PasswordPlain (the child sees no PGPASSWORD), dropping PasswordPlain from
            # Invoke-PostgresNativeCommand's redaction secrets (the echoed password reaches Output in the direct case), not
            # restoring the caller's PGPASSWORD, or pointing the child at a password file through PGPASSFILE fails these assertions.
            $secret = 'Child-Env-Secret-370'
            $envFile = Join-Path $TestDrive ('psql-env-' + [guid]::NewGuid().ToString('N') + '.txt')
            $sentinel = Join-Path $TestDrive 'caller-pgpass-sentinel.conf'
            try {
                Set-ProcessEnvironmentValue -Name 'PGPASSWORD' -Value 'caller-prior-pgpassword'
                Set-ProcessEnvironmentValue -Name 'PGPASSFILE' -Value $sentinel
                Set-FakeTool -Name psql -Exit '1' -EnvFile $envFile
                $visible = switch ($Helper) {
                    'Invoke-PostgresNativeCommand' {
                        # No -Secrets: PasswordPlain alone must be redacted.
                        $command = Invoke-PostgresNativeCommand -FilePath (Join-Path $script:PostgresBinDir 'psql.exe') -Arguments @('-tAc', 'SELECT 1') -PasswordPlain $secret
                        [int]$command.ExitCode | Should -Be 1
                        [string]$command.Output
                    }
                    'Get-PostgresPasswordProbe' {
                        $probe = Get-PostgresPasswordProbe -SuperPasswordPlain $secret
                        [string]$probe.State | Should -BeExactly 'Unavailable'
                        [string]$probe.Detail
                    }
                    'Get-PostgresDatabaseState' {
                        $message = $null
                        try { [void](Get-PostgresDatabaseState -DbName 'GameDB06' -SuperPasswordPlain $secret) } catch { $message = $_.Exception.Message }
                        $message | Should -Not -BeNullOrEmpty
                        $message
                    }
                }
                $childSaw = @([IO.File]::ReadAllLines($envFile))
                $childSaw | Should -Contain ('PGPASSWORD=' + $secret)
                $childSaw | Should -Contain ('PGPASSFILE=' + $sentinel)
                $visible | Should -Match 'PGPASSWORD='
                $visible.Contains($secret) | Should -BeFalse
                [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process') | Should -BeExactly 'caller-prior-pgpassword'
                [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process') | Should -BeExactly $sentinel
            } finally {
                Set-ProcessEnvironmentValue -Name 'PGPASSWORD' -Value $script:PgPasswordBefore
                Set-ProcessEnvironmentValue -Name 'PGPASSFILE' -Value $script:PgPassFileBefore
            }
        }
    }

    Context 'Get-PostgresDatabaseState' {
        It 'returns exactly one state object with Boolean Exists=<Exists> for psql output "<Out>"' -TestCases @(
            @{ Out = '1'; Exists = $true }
            @{ Out = ''; Exists = $false }
        ) {
            param($Out, $Exists)
            Set-FakeTool -Name psql -Exit '0' -Out $Out
            $result = @(Get-PostgresDatabaseState -DbName 'GameDB06' -SuperPasswordPlain 'pw')
            $result.Count | Should -Be 1
            $result[0].Verified | Should -BeExactly $true
            $result[0].Exists | Should -BeOfType [bool]
            $result[0].Exists | Should -Be $Exists
        }

        It 'throws on a nonzero query exit instead of reporting absence' {
            Set-FakeTool -Name psql -Exit '3'
            { Get-PostgresDatabaseState -DbName 'GameDB06' -SuperPasswordPlain 'pw' } | Should -Throw '*existence query failed*'
        }
    }

    Context 'Invoke-Postgres83RestoreCommand' {
        It 'returns exactly one typed command result when pg_restore exits <Exit>' -TestCases @(
            @{ Exit = '0'; Expected = $true }
            @{ Exit = '1'; Expected = $false }
        ) {
            param($Exit, $Expected)
            Set-FakeTool -Name pg_restore -Exit $Exit -Out 'synthetic diagnostic'
            $result = @(Invoke-Postgres83RestoreCommand -ToolName 'pg_restore.exe' -Arguments @('--version') -SuperPasswordPlain 'pw')
            $result.Count | Should -Be 1
            $result[0].Tool | Should -Be 'pg_restore.exe'
            $result[0].ExitCode | Should -Be ([int]$Exit)
            $result[0].Succeeded | Should -BeExactly $Expected
        }
    }

    Context 'New-PostgresDatabaseFromBackup' {
        BeforeEach {
            $script:BackupFile = Join-Path $TestDrive ('db-' + [guid]::NewGuid().ToString('N') + '.backup')
            [IO.File]::WriteAllText($script:BackupFile, 'synthetic', (New-Object System.Text.UTF8Encoding $false))
        }

        It 'returns one structured failure without mutation when the database is not verified absent' {
            Set-FakeTool -Name psql -Exit '0' -Out '1'
            $result = @(New-PostgresDatabaseFromBackup -DbName 'GameDB06' -Encoding 'UTF8' -BackupFile $script:BackupFile -SuperPasswordPlain 'pw')
            $result.Count | Should -Be 1
            @($result[0].PSTypeNames) | Should -Contain 'TPM.PostgresSetupDatabaseResult.v1'
            $result[0].Succeeded | Should -BeExactly $false
            $result[0].MutationAttempted | Should -BeExactly $false
            $result[0].FailureStage | Should -Be 'PreMutationState'
            $result[0].PreMutationState.Verified | Should -BeExactly $true
            $result[0].PreMutationState.Exists | Should -BeExactly $true
        }

        It 'returns one structured success after verified creation, restore, and final state' {
            $script:DatabaseStateCalls = 0
            Mock Get-PostgresDatabaseState {
                $script:DatabaseStateCalls++
                if ($script:DatabaseStateCalls -eq 1) {
                    [pscustomobject]@{ Exists = $false; Verified = $true }
                } else {
                    [pscustomobject]@{ Exists = $true; Verified = $true }
                }
            }
            Mock Test-Postgres83RestoreToolSet { [pscustomobject]@{ Verified = $true } }

            $result = @(New-PostgresDatabaseFromBackup -DbName 'GameDB06' -Encoding 'UTF8' -BackupFile $script:BackupFile -SuperPasswordPlain 'pw')

            $result.Count | Should -Be 1
            @($result[0].PSTypeNames) | Should -Contain 'TPM.PostgresSetupDatabaseResult.v1'
            $result[0].Succeeded | Should -BeExactly $true
            $result[0].MutationAttempted | Should -BeExactly $true
            $result[0].DatabaseMayExist | Should -BeExactly $true
            $result[0].PreMutationState.Exists | Should -BeExactly $false
            $result[0].PostMutationState.Exists | Should -BeExactly $true
            $result[0].FinalVerification.Attempted | Should -BeExactly $true
            $result[0].FinalVerification.Passed | Should -BeExactly $true
            $result[0].Commands.Count | Should -Be 4
            $script:DatabaseStateCalls | Should -Be 2
        }

        It 'returns one structured failure when a restore command fails after creation' {
            $script:DatabaseStateCalls = 0
            Mock Get-PostgresDatabaseState {
                $script:DatabaseStateCalls++
                if ($script:DatabaseStateCalls -eq 1) {
                    [pscustomobject]@{ Exists = $false; Verified = $true }
                } else {
                    [pscustomobject]@{ Exists = $true; Verified = $true }
                }
            }
            Mock Test-Postgres83RestoreToolSet { [pscustomobject]@{ Verified = $true } }
            Mock Invoke-Postgres83RestoreCommandChecked {
                param($ToolName, $Arguments, $SuperPasswordPlain, $CommandLog, $DatabaseName)
                if ($ToolName -eq 'pg_restore.exe' -and $Arguments -notcontains '--list') {
                    throw 'synthetic restore failure'
                }
                [pscustomobject]@{ Tool = $ToolName; Succeeded = $true; ExitCode = 0; Output = '' }
            }

            $result = @(New-PostgresDatabaseFromBackup -DbName 'GameDB06' -Encoding 'UTF8' -BackupFile $script:BackupFile -SuperPasswordPlain 'pw')

            $result.Count | Should -Be 1
            @($result[0].PSTypeNames) | Should -Contain 'TPM.PostgresSetupDatabaseResult.v1'
            $result[0].Succeeded | Should -BeExactly $false
            $result[0].MutationAttempted | Should -BeExactly $true
            $result[0].DatabaseMayExist | Should -BeExactly $true
            $result[0].FailureStage | Should -Be 'DatabaseRestore'
            $result[0].PostMutationState.Exists | Should -BeExactly $true
            $result[0].FinalVerification.Passed | Should -BeExactly $false
        }
    }

    Context 'Backup-PostgresDatabases' {
        It 'returns exactly one result object when database dumps fail' {
            $profiles = Join-Path $TestDrive ('profiles-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($profiles)
            [void](New-PostgresProfileFixture -Directory $profiles -Name 'GTL' -DbName 'GameDB06' -GamePath 'C:\missing\game.exe')
            Mock Test-PostgresInstalled { $true }
            Set-FakeTool -Name psql -Exit '0' -Out '1'
            Set-FakeTool -Name pg_dump -Exit '1'
            $result = @(Backup-PostgresDatabases -UserProfilesDir $profiles -SuperPasswordPlain 'pw')
            $result.Count | Should -Be 1
            $result[0].Succeeded | Should -BeExactly $false
            $result[0].ExistingDatabaseCount | Should -Be 1
        }
    }
}

Describe 'PostgreSQL consumer gates do not accept failed helper results (issue #370)' {
    BeforeEach { Reset-FakeTools }
    AfterEach { Reset-FakeTools }

    It 'profile setup blocks and writes no profile when database creation fails' {
        $profiles = Join-Path $TestDrive ('setup-' + [guid]::NewGuid().ToString('N'))
        $game = Join-Path $profiles 'Game'
        [void][IO.Directory]::CreateDirectory($game)
        $exe = Join-Path $game 'game.exe'
        [IO.File]::WriteAllText($exe, 'x')
        $profilePath = New-PostgresProfileFixture -Directory $profiles -Name 'GTL' -DbName 'GameDB06' -GamePath $exe -Pass 'old'
        $before = [IO.File]::ReadAllBytes($profilePath)
        $script:SetupBackupFile = Join-Path $game 'db.backup'
        [IO.File]::WriteAllText($script:SetupBackupFile, 'x')
        Mock Get-PostgresBackupSelection { [pscustomobject]@{ Newest = $script:SetupBackupFile; NewestHasTime = $false; CandidateCount = 1 } }
        Mock Save-Xml { throw 'Save-Xml must not run after a failed database creation.' }
        Set-FakeTool -Name psql -Exit '0' -Out ''
        Set-FakeTool -Name createdb -Exit '1'
        $recoveryRoot = Join-Path $TestDrive ('setup-recovery-' + [guid]::NewGuid().ToString('N'))
        $profileBackupRoot = Join-Path $recoveryRoot 'Profiles'
        [void][IO.Directory]::CreateDirectory($profileBackupRoot)
        $profileBackupPath = Join-Path $profileBackupRoot ([IO.Path]::GetFileName($profilePath))
        [IO.File]::Copy($profilePath, $profileBackupPath, $false)
        $recoveryBackup = [pscustomobject]@{
            Path = $recoveryRoot
            ConfigBackups = @()
            ProfileBackups = @([pscustomobject]@{
                Source = $profilePath
                Backup = $profileBackupPath
                Sha256 = (Get-FileHash -LiteralPath $profileBackupPath -Algorithm SHA256).Hash
            })
            Verified = $true
        }
        # The profile has its own password ('old'); approving the replacement means it would be written if database creation had worked, so "no write" below is a real check.
        $result = @(Invoke-PostgresGameSetup -UserProfilesDir $profiles -SuperPasswordPlain 'new' -RecoveryBackup $recoveryBackup -ApprovedPassReplacements @($profilePath))
        $result.Count | Should -Be 1
        $result[0].RecoveryBlocked | Should -BeExactly $true
        $result[0].DbCreated | Should -Be 0
        $result[0].Configured | Should -Be 0
        Should -Invoke Save-Xml -Times 0
        [IO.File]::ReadAllBytes($profilePath) | Should -Be $before
    }
}
