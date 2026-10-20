#Requires -Module Pester

# Issue #370: PostgreSQL helpers must return exactly one typed result. The
# temporary .pgpass cleanup runs in a `finally` block; any value that cleanup
# emits becomes part of the helper's output, so a failed authentication could
# become the truthy collection ($false, $true). These tests drive the real
# helpers against synthetic psql/createdb/pg_restore/pg_dump executables (no
# PostgreSQL server, service, registry, or user configuration is touched).
# Inventory rows: PG-S10, INV-PG-05 (docs/RC8-REMEDIATION-INVENTORY.md).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'PostgreSQL helper test bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'tpm-postgres-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    $script:logPath = Join-Path $TestDrive 'test.log'
    $script:logWarnShown = $false
    $script:logFailedCount = 0

    # One synthetic console program, copied under each tool name. Its exit code
    # and stdout come from FAKE_<TOOL>_EXIT / FAKE_<TOOL>_OUT. Compiled with the
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
        param([string]$Name, [string]$Exit = '', [string]$Out = '')
        [Environment]::SetEnvironmentVariable("FAKE_$($Name.ToUpperInvariant())_EXIT", $Exit, 'Process')
        [Environment]::SetEnvironmentVariable("FAKE_$($Name.ToUpperInvariant())_OUT", $Out, 'Process')
    }
    function Reset-FakeTools {
        foreach ($n in 'psql', 'createdb', 'pg_restore', 'pg_dump', 'dropdb') { Set-FakeTool -Name $n }
    }
    function Remove-OwnedPgPassFixture {
        # Cleanup-failure tests replace Remove-PostgresPgPassFile with a mock
        # that throws. This deletes the exact credential file that call
        # created (and only that path, which must be a tpm-pgpass file in
        # TEMP) so the simulated failure leaves no synthetic credential behind.
        param([string]$Path)
        if ([string]::IsNullOrEmpty($Path)) { throw 'Cleanup-failure mock received no credential path.' }
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
        $full = [IO.Path]::GetFullPath($Path)
        if ([IO.Path]::GetDirectoryName($full) -ne $tempRoot -or [IO.Path]::GetFileName($full) -notlike 'tpm-pgpass-*.conf') { throw "Refusing to delete an unexpected path: $full" }
        if ([IO.File]::Exists($full)) { [IO.File]::Delete($full) }
        if ([IO.File]::Exists($full)) { throw "Synthetic credential fixture remains: $full" }
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
    foreach ($n in 'psql', 'createdb', 'pg_restore', 'pg_dump', 'dropdb') {
        [Environment]::SetEnvironmentVariable("FAKE_$($n.ToUpperInvariant())_EXIT", [NullString]::Value, 'Process')
        [Environment]::SetEnvironmentVariable("FAKE_$($n.ToUpperInvariant())_OUT", [NullString]::Value, 'Process')
    }
}

Describe 'PostgreSQL helper result contract (issue #370)' {
    BeforeEach { Reset-FakeTools; $script:PgPassBefore = [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process') }
    AfterEach {
        Reset-FakeTools
        [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process') | Should -Be $script:PgPassBefore -Because 'the process PGPASSFILE value must be restored exactly'
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

        It 'throws instead of returning success when credential cleanup fails after successful authentication' {
            Set-FakeTool -Name psql -Exit '0'
            Mock Remove-PostgresPgPassFile { Remove-OwnedPgPassFixture -Path $Path; throw 'Postgres: temporary credential cleanup failed.' }
            { [void](Test-PostgresPassword -SuperPasswordPlain 'pw') } | Should -Throw '*cleanup failed*'
        }

        It 'removes the exact temporary credential file it created when psql exits <Exit>' -TestCases @(
            @{ Exit = '0' }
            @{ Exit = '1' }
        ) {
            param($Exit)
            # Spy on the real creator so the assertion is about this call's
            # own file, not a count of every pgpass file in the shared TEMP.
            $script:RealNewPgPassFile = ${function:New-PostgresPgPassFile}
            $script:CreatedPgPass = $null
            Mock New-PostgresPgPassFile { $created = & $script:RealNewPgPassFile -Password $Password; $script:CreatedPgPass = $created; $created }
            Set-FakeTool -Name psql -Exit $Exit
            [void](Test-PostgresPassword -SuperPasswordPlain 'pw')
            $script:CreatedPgPass | Should -Not -BeNullOrEmpty
            Test-Path -LiteralPath $script:CreatedPgPass | Should -BeFalse
        }

        It 'restores a <State> PGPASSFILE exactly when psql exits <Exit> and cleanup <Cleanup>' -TestCases @(
            @{ State = 'unset'; Exit = '0'; Cleanup = 'succeeds' }
            @{ State = 'unset'; Exit = '1'; Cleanup = 'succeeds' }
            @{ State = 'unset'; Exit = '0'; Cleanup = 'fails' }
            @{ State = 'empty'; Exit = '0'; Cleanup = 'succeeds' }
            @{ State = 'empty'; Exit = '1'; Cleanup = 'succeeds' }
            @{ State = 'empty'; Exit = '0'; Cleanup = 'fails' }
            @{ State = 'nonempty'; Exit = '0'; Cleanup = 'succeeds' }
            @{ State = 'nonempty'; Exit = '1'; Cleanup = 'succeeds' }
            @{ State = 'nonempty'; Exit = '0'; Cleanup = 'fails' }
        ) {
            param($State, $Exit, $Cleanup)
            switch ($State) {
                'unset' { [Environment]::SetEnvironmentVariable('PGPASSFILE', [NullString]::Value, 'Process') }
                'empty' { [Environment]::SetEnvironmentVariable('PGPASSFILE', '', 'Process') }
                'nonempty' { [Environment]::SetEnvironmentVariable('PGPASSFILE', (Join-Path $TestDrive 'caller-pgpass.conf'), 'Process') }
            }
            $established = [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process')
            try {
                # Windows PowerShell 5.1 (.NET Framework) cannot hold an empty
                # environment value; setting '' removes it, so there the
                # "empty" case is established as unset. PowerShell 7 keeps ''.
                if ($State -eq 'empty' -and $PSVersionTable.PSEdition -eq 'Core') { $established | Should -BeExactly '' }
                if ($State -eq 'unset') { $established | Should -BeNullOrEmpty; ($null -eq $established) | Should -BeTrue }
                Set-FakeTool -Name psql -Exit $Exit
                if ($Cleanup -eq 'fails') {
                    Mock Remove-PostgresPgPassFile { Remove-OwnedPgPassFixture -Path $Path; throw 'Postgres: temporary credential cleanup failed.' }
                    { [void](Test-PostgresPassword -SuperPasswordPlain 'pw') } | Should -Throw '*cleanup failed*'
                } else {
                    [void](Test-PostgresPassword -SuperPasswordPlain 'pw')
                }
                $after = [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process')
                ($null -eq $after) | Should -Be ($null -eq $established)
                if ($null -ne $established) { $after | Should -BeExactly $established }
            } finally {
                if ($null -eq $script:PgPassBefore) { [Environment]::SetEnvironmentVariable('PGPASSFILE', [NullString]::Value, 'Process') }
                else { [Environment]::SetEnvironmentVariable('PGPASSFILE', $script:PgPassBefore, 'Process') }
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

        It 'throws when cleanup fails after a successful query' {
            Set-FakeTool -Name psql -Exit '0' -Out '1'
            Mock Remove-PostgresPgPassFile { Remove-OwnedPgPassFixture -Path $Path; throw 'Postgres: temporary credential cleanup failed.' }
            { Get-PostgresDatabaseState -DbName 'GameDB06' -SuperPasswordPlain 'pw' } | Should -Throw '*cleanup failed*'
        }

        It 'Test-PostgresDatabaseExists returns exactly one Boolean for present and absent databases' {
            Set-FakeTool -Name psql -Exit '0' -Out '1'
            $present = @(Test-PostgresDatabaseExists -DbName 'GameDB06' -SuperPasswordPlain 'pw')
            Set-FakeTool -Name psql -Exit '0' -Out ''
            $absent = @(Test-PostgresDatabaseExists -DbName 'GameDB06' -SuperPasswordPlain 'pw')
            $present.Count | Should -Be 1; $present[0] | Should -BeExactly $true
            $absent.Count | Should -Be 1; $absent[0] | Should -BeExactly $false
        }
    }

    Context 'New-PostgresDatabaseFromBackup' {
        BeforeEach {
            $script:BackupFile = Join-Path $TestDrive ('db-' + [guid]::NewGuid().ToString('N') + '.backup')
            [IO.File]::WriteAllText($script:BackupFile, 'synthetic', (New-Object System.Text.UTF8Encoding $false))
        }

        It 'returns exactly one Boolean <Expected> when createdb=<Createdb> pg_restore=<Restore> verify="<Verify>"' -TestCases @(
            @{ Createdb = '0'; Restore = '0'; Verify = '1'; Expected = $true }
            @{ Createdb = '1'; Restore = '0'; Verify = '1'; Expected = $false }
            @{ Createdb = '0'; Restore = '1'; Verify = '1'; Expected = $false }
            @{ Createdb = '0'; Restore = '0'; Verify = ''; Expected = $false }
        ) {
            param($Createdb, $Restore, $Verify, $Expected)
            Set-FakeTool -Name createdb -Exit $Createdb
            Set-FakeTool -Name pg_restore -Exit $Restore
            Set-FakeTool -Name psql -Exit '0' -Out $Verify
            $result = @(New-PostgresDatabaseFromBackup -DbName 'GameDB06' -Encoding 'UTF8' -BackupFile $script:BackupFile -SuperPasswordPlain 'pw')
            $result.Count | Should -Be 1
            $result[0] | Should -BeOfType [bool]
            $result[0] | Should -Be $Expected
        }

        It 'throws when cleanup fails after a successful restore' {
            Set-FakeTool -Name createdb -Exit '0'; Set-FakeTool -Name pg_restore -Exit '0'; Set-FakeTool -Name psql -Exit '0' -Out '1'
            Mock Remove-PostgresPgPassFile { Remove-OwnedPgPassFixture -Path $Path; throw 'Postgres: temporary credential cleanup failed.' }
            { New-PostgresDatabaseFromBackup -DbName 'GameDB06' -Encoding 'UTF8' -BackupFile $script:BackupFile -SuperPasswordPlain 'pw' } | Should -Throw '*cleanup failed*'
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

    It 'guided recovery reports PASSWORD_VERIFICATION_FAILED when the real password probe fails' {
        Mock New-PostgresRecoveryBackup { [pscustomobject]@{ Verified = $true; Path = 'synthetic-backup' } }
        Mock Reset-PostgresPasswordAutomatically { [pscustomobject]@{ Succeeded = $true } }
        Set-FakeTool -Name psql -Exit '1'
        $result = @(Invoke-PostgresSelectedPasswordRecovery -UserProfilesDir $TestDrive -PasswordPlain 'pw')
        $result.Count | Should -Be 1
        $result[0].Succeeded | Should -BeExactly $false
        $result[0].Reason | Should -Be 'PASSWORD_VERIFICATION_FAILED'
    }

    It 'guided recovery succeeds only when the real password probe succeeds' {
        Mock New-PostgresRecoveryBackup { [pscustomobject]@{ Verified = $true; Path = 'synthetic-backup' } }
        Mock Reset-PostgresPasswordAutomatically { [pscustomobject]@{ Succeeded = $true } }
        Set-FakeTool -Name psql -Exit '0'
        $result = @(Invoke-PostgresSelectedPasswordRecovery -UserProfilesDir $TestDrive -PasswordPlain 'pw')
        $result.Count | Should -Be 1
        $result[0].Succeeded | Should -BeExactly $true
    }

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
        Mock Get-PostgresBackupFile { $script:SetupBackupFile }
        Mock Save-Xml { throw 'Save-Xml must not run after a failed database creation.' }
        Set-FakeTool -Name psql -Exit '0' -Out ''
        Set-FakeTool -Name createdb -Exit '1'
        $result = @(Invoke-PostgresGameSetup -UserProfilesDir $profiles -SuperPasswordPlain 'new' -RecoveryBackup ([pscustomobject]@{ Verified = $true; Path = 'synthetic-backup' }))
        $result.Count | Should -Be 1
        $result[0].RecoveryBlocked | Should -BeExactly $true
        $result[0].DbCreated | Should -Be 0
        $result[0].Configured | Should -Be 0
        Should -Invoke Save-Xml -Times 0
        [IO.File]::ReadAllBytes($profilePath) | Should -Be $before
    }
}
