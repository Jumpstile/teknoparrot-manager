#Requires -Module Pester

# FIX95 PostgreSQL safety (ASTRA RC8 audit B1, S5, S1; owner rules R1, R4, R5, R8).
#  B1: TeknoParrot Manager no longer resets the postgres password with a temporary
#      "host all postgres 127.0.0.1/32 trust" rule (a hard kill could leave it live).
#      Choosing [X] shows a help screen that changes nothing.
#  S5: the password reaches the PostgreSQL tools through PGPASSWORD set only around
#      the one child call; no password file is written and the secret never appears
#      in arguments, output or the command log.
#  S1: pg_restore exit 1 counts as finished only for the known bundled-archive
#      foreign-key problem; anything else (other error text, primary key or unique
#      entries, empty output) stays a failure, and a user-backup restore stays strict.
# The production script is parsed and only its function definitions are dot-sourced;
# no top-level product code runs. psql is a synthetic console program compiled into
# TestDrive. Nothing touches a real PostgreSQL server, service, registry or user file.

BeforeAll {
    $script:Fix95ProductionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:Fix95Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:Fix95ProductionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX95 tests could not parse the production script.' }
    $functionText = @($script:Fix95Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix95-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $script:logPath = Join-Path $TestDrive 'fix95.log'
    $script:PostgresServiceName = 'pgsql-fix95-not-installed'

    # Synthetic psql: reports what it received through the environment, never echoes the
    # password itself (only its UTF-8 hex), writes its arguments to FIX95_ARGS_FILE and
    # counts tpm-pgpass-* files in its temp folder while it runs.
    $script:Fix95Bin = Join-Path $TestDrive 'fakepg'
    [void][System.IO.Directory]::CreateDirectory($script:Fix95Bin)
    $fakeSource = Join-Path $TestDrive 'Fix95FakePsql.cs'
    $fakeCode = @'
using System;
using System.IO;
using System.Text;
public static class Fix95FakePsql {
  public static int Main(string[] args) {
    string argsFile = Environment.GetEnvironmentVariable("FIX95_ARGS_FILE");
    if (!String.IsNullOrEmpty(argsFile)) { File.WriteAllText(argsFile, String.Join("\n", args)); }
    string pw = Environment.GetEnvironmentVariable("PGPASSWORD");
    if (pw == null) { pw = ""; }
    StringBuilder hex = new StringBuilder();
    foreach (byte b in Encoding.UTF8.GetBytes(pw)) { hex.Append(b.ToString("X2")); }
    string passFile = Environment.GetEnvironmentVariable("PGPASSFILE");
    int tempFiles = Directory.GetFiles(Path.GetTempPath(), "tpm-pgpass-*").Length;
    Console.WriteLine("PWHEX=" + hex.ToString() + ";PASSFILE=" + (String.IsNullOrEmpty(passFile) ? "none" : "set") + ";TEMPFILES=" + tempFiles);
    string extra = Environment.GetEnvironmentVariable("FIX95_EXTRA_OUT");
    if (!String.IsNullOrEmpty(extra)) { Console.Error.WriteLine(extra); }
    string exit = Environment.GetEnvironmentVariable("FIX95_EXIT");
    return String.IsNullOrEmpty(exit) ? 0 : Int32.Parse(exit);
  }
}
'@
    [System.IO.File]::WriteAllText($fakeSource, $fakeCode, (New-Object System.Text.UTF8Encoding $false))
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) { throw "The .NET Framework C# compiler was not found at $csc." }
    & $csc /nologo /target:exe ("/out:" + (Join-Path $script:Fix95Bin 'psql.exe')) $fakeSource | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'The synthetic psql could not be compiled.' }
    $script:PostgresBinDir = $script:Fix95Bin

    function Get-Fix95Hex {
        param([string]$Text)
        return (@([System.Text.Encoding]::UTF8.GetBytes($Text) | ForEach-Object { $_.ToString('X2') }) -join '')
    }

    # Runs $Action with the named process environment values set, then puts every value back.
    function Invoke-Fix95WithEnvironment {
        param([Parameter(Mandatory)][hashtable]$Values, [Parameter(Mandatory)][scriptblock]$Action)
        $previous = @{}
        foreach ($key in @($Values.Keys)) {
            $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            $value = $Values[$key]
            if ($null -eq $value) { [Environment]::SetEnvironmentVariable($key, [NullString]::Value, 'Process') }
            else { [Environment]::SetEnvironmentVariable($key, [string]$value, 'Process') }
        }
        try { return (& $Action) }
        finally {
            foreach ($key in @($previous.Keys)) {
                if ($null -eq $previous[$key]) { [Environment]::SetEnvironmentVariable($key, [NullString]::Value, 'Process') }
                else { [Environment]::SetEnvironmentVariable($key, [string]$previous[$key], 'Process') }
            }
        }
    }

    # pg_restore 8.3 output for one failed TOC entry as one text block (the real shape: error
    # line, DETAIL, a "Command was:" text that continues on the next line).
    function New-Fix95TocError {
        param([int]$Id, [string]$Type, [string]$Name, [string]$ErrorText, [string]$Detail = '')
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add(('pg_restore: [archiver (db)] Error from TOC entry {0}; 2606 6590844 {1} {2} postgres' -f $Id, $Type, $Name))
        $lines.Add(('pg_restore: [archiver (db)] could not execute query: ERROR:  {0}' -f $ErrorText))
        if ($Detail) { $lines.Add(('DETAIL:  {0}' -f $Detail)) }
        $lines.Add('    Command was: ALTER TABLE ONLY category1')
        $lines.Add(('    ADD CONSTRAINT {0} FOREIGN KEY (attr) REFERENCES attr(id);' -f $Name))
        return ($lines -join "`r`n")
    }
    function New-Fix95RestoreOutput {
        param([string[]]$Entries, [int]$Reported = -1)
        if ($Reported -lt 0) { $Reported = $Entries.Count }
        $blocks = @('pg_restore: [archiver (db)] Error while PROCESSING TOC:') + $Entries + @(('WARNING: errors ignored on restore: {0}' -f $Reported))
        return ($blocks -join "`r`n")
    }
    $script:Fix95FkDetail = 'Key columns "attr" and "id" are of incompatible types: numeric and integer.'
    function New-Fix95KnownEntry {
        param([int]$Id, [string]$Name, [string]$Type = 'FK CONSTRAINT')
        return (New-Fix95TocError -Id $Id -Type $Type -Name $Name -ErrorText ('foreign key constraint "{0}" cannot be implemented' -f $Name) -Detail $script:Fix95FkDetail)
    }
}

AfterAll {
    foreach ($name in @('FIX95_ARGS_FILE', 'FIX95_EXTRA_OUT', 'FIX95_EXIT')) { [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process') }
}

Describe 'FIX95 B1: no automatic password reset that loosens pg_hba.conf' {
    BeforeEach {
        $script:PostgresInstallDir = Join-Path $TestDrive ('pg-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $dataDir = Join-Path $script:PostgresInstallDir 'data'
        [void][System.IO.Directory]::CreateDirectory($dataDir)
        $script:Fix95Hba = Join-Path $dataDir 'pg_hba.conf'
        [System.IO.File]::WriteAllText($script:Fix95Hba, "host all all 127.0.0.1/32 md5`r`n", (New-Object System.Text.UTF8Encoding $false))
        $script:Fix95Outcome = $null
        Mock Write-TpmOutcome { $script:Fix95Outcome = [pscustomobject]@{ Title = $Title; Status = $Status; NotChanged = $NotChanged; Needs = @($Needs); Next = $Next; DetailBlocks = @($DetailBlocks) } }
        Mock Start-Service { throw 'FIX95: the help screen must not start a service.' }
        Mock Stop-Service { throw 'FIX95: the help screen must not stop a service.' }
        Mock Set-PostgresHbaPolicyAtomically { throw 'FIX95: the help screen must not write pg_hba.conf.' }
        Mock New-PostgresRecoveryBackup { throw 'FIX95: the help screen must not make a backup.' }
        Mock Invoke-PostgresNativeCommand { throw 'FIX95: the help screen must not run a PostgreSQL tool.' }
        Mock Start-PostgresRecoveryAsAdministrator { throw 'FIX95: the help screen must not ask for administrator rights.' }
    }

    # Mutation: let [X] start any reset step again (stop/start the service, write pg_hba.conf,
    # make a backup, run psql or hand off to an administrator window).
    It 'B1: the help screen changes nothing and names the key that types the existing password' -TestCases @(
        @{ Key = 'F' }
        @{ Key = 'P' }
    ) {
        param($Key)
        $before = (Get-FileHash -LiteralPath $script:Fix95Hba -Algorithm SHA256).Hash

        Show-PostgresPasswordResetUnavailable -EnterKey $Key

        Should -Invoke Write-TpmOutcome -Times 1 -Exactly
        $script:Fix95Outcome.Status | Should -BeExactly 'Attention'
        $script:Fix95Outcome.Title | Should -BeExactly 'TeknoParrot Manager cannot reset the PostgreSQL password for you.'
        $script:Fix95Outcome.NotChanged | Should -BeExactly 'PostgreSQL, its password and your games.'
        $script:Fix95Outcome.Next | Should -Match ('choose {0} and type it' -f $Key)
        (Get-FileHash -LiteralPath $script:Fix95Hba -Algorithm SHA256).Hash | Should -BeExactly $before
        foreach ($command in @('Start-Service', 'Stop-Service', 'Set-PostgresHbaPolicyAtomically', 'New-PostgresRecoveryBackup', 'Invoke-PostgresNativeCommand', 'Start-PostgresRecoveryAsAdministrator')) {
            Should -Invoke $command -Times 0 -Exactly
        }
    }

    # Mutation: move a technical word (pg_hba, trust, psql) into the default view, write a
    # sentence longer than 15 words there, or drop the manual steps from Details.
    It 'B1: the default view is short and plain; the technical steps are only under Details' {
        Show-PostgresPasswordResetUnavailable -EnterKey 'F'

        $defaultText = @($script:Fix95Outcome.Title, $script:Fix95Outcome.NotChanged, $script:Fix95Outcome.Next) + @($script:Fix95Outcome.Needs)
        foreach ($text in $defaultText) {
            $text | Should -Not -Match '(?i)pg_hba|trust|psql|\bTPM\b'
            foreach ($sentence in @(([string]$text) -split '(?<=[.!?])\s+' | Where-Object { $_.Trim() })) {
                @($sentence.Trim() -split '\s+').Count | Should -BeLessOrEqual 15 -Because $sentence
            }
        }
        $detailLines = @($script:Fix95Outcome.DetailBlocks | ForEach-Object { @($_.Lines) })
        ($detailLines -join "`n") | Should -Match ([regex]::Escape($script:Fix95Hba))
        ($detailLines -join "`n") | Should -Match 'host all postgres 127\.0\.0\.1/32 trust'
        (@($detailLines | Where-Object { $_ -like 'Step 7:*' }) -join '|') | Should -BeExactly 'Step 7: Open PostgreSQL setup again, choose F and type the new password.'
        @($detailLines | Where-Object { $_ -like 'Warning:*' }).Count | Should -Be 1
    }
}

Describe 'FIX95 S5: the password reaches the tools only through PGPASSWORD for one call' {
    BeforeEach {
        $script:Fix95Temp = Join-Path $TestDrive ('tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($script:Fix95Temp)
        $script:Fix95ArgsFile = Join-Path $TestDrive ('args-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.txt')
        $script:Fix95Secret = 'Fix95-S5-Secret:pw\x'
    }

    # Mutation: write a password file / set PGPASSFILE again, pass the password as an argument,
    # skip setting PGPASSWORD, or skip putting the caller's PGPASSWORD back in finally.
    It 'S5: psql sees the password in PGPASSWORD only, no password file exists, and a <Prior> PGPASSWORD is put back' -TestCases @(
        @{ Prior = 'unset'; PriorValue = $null }
        @{ Prior = 'existing'; PriorValue = 'caller-own-value' }
    ) {
        param($Prior, $PriorValue)
        $environment = @{ TMP = $script:Fix95Temp; TEMP = $script:Fix95Temp; PGPASSFILE = $null; PGPASSWORD = $PriorValue; FIX95_ARGS_FILE = $script:Fix95ArgsFile; FIX95_EXIT = '0'; FIX95_EXTRA_OUT = $null }
        $observed = Invoke-Fix95WithEnvironment -Values $environment -Action {
            $command = Invoke-Postgres83RestoreCommand -ToolName 'psql.exe' -Arguments @('-U', 'postgres', '-h', '127.0.0.1', '-p', '5432', '-d', 'postgres', '-tAc', 'SELECT 1') -SuperPasswordPlain $script:Fix95Secret
            [pscustomobject]@{ Command = $command; After = [Environment]::GetEnvironmentVariable('PGPASSWORD', 'Process'); PassFileAfter = [Environment]::GetEnvironmentVariable('PGPASSFILE', 'Process'); TempAfter = @(Get-ChildItem -LiteralPath $script:Fix95Temp -Force) }
        }

        $observed.Command.Succeeded | Should -BeTrue
        $observed.Command.Output | Should -Match ('PWHEX=' + (Get-Fix95Hex -Text $script:Fix95Secret) + ';PASSFILE=none;TEMPFILES=0')
        $observed.After | Should -Be $PriorValue
        $observed.PassFileAfter | Should -BeNullOrEmpty
        $observed.TempAfter.Count | Should -Be 0
        [System.IO.File]::ReadAllText($script:Fix95ArgsFile).Contains($script:Fix95Secret) | Should -BeFalse
        @($observed.Command.Arguments) -contains $script:Fix95Secret | Should -BeFalse
    }

    # Mutation: set PGPASSWORD for a command that has no password (a version check), which
    # would hand a stale or empty value to the tool.
    It 'S5: a command without a password leaves PGPASSWORD alone' {
        $environment = @{ TMP = $script:Fix95Temp; TEMP = $script:Fix95Temp; PGPASSFILE = $null; PGPASSWORD = $null; FIX95_ARGS_FILE = $script:Fix95ArgsFile; FIX95_EXIT = '0'; FIX95_EXTRA_OUT = $null }
        $command = Invoke-Fix95WithEnvironment -Values $environment -Action {
            Invoke-Postgres83RestoreCommand -ToolName 'psql.exe' -Arguments @('--version') -SuperPasswordPlain ''
        }
        $command.Output | Should -Match 'PWHEX=;PASSFILE=none;TEMPFILES=0'
    }

    # Mutation: drop the redaction of the password from the tool output, the command result
    # or the thrown failure (the text that reaches the log, the receipts and the Details view).
    It 'S5: a tool that prints the password never puts it in the result, the command log or the error' {
        $environment = @{ TMP = $script:Fix95Temp; TEMP = $script:Fix95Temp; PGPASSFILE = $null; PGPASSWORD = $null; FIX95_ARGS_FILE = $script:Fix95ArgsFile; FIX95_EXIT = '2'; FIX95_EXTRA_OUT = ('FATAL:  password authentication failed for user "postgres" (' + 'Fix95-S5-Secret:pw\x' + ')') }
        $log = New-Object System.Collections.Generic.List[object]
        $message = Invoke-Fix95WithEnvironment -Values $environment -Action {
            try {
                [void](Invoke-Postgres83RestoreCommandChecked -ToolName 'psql.exe' -Arguments @('-U', 'postgres', '-d', 'postgres', '-c', 'SELECT 1') -SuperPasswordPlain $script:Fix95Secret -CommandLog $log -DatabaseName 'postgres')
                'no failure'
            } catch { [string]$_.Exception.Message }
        }

        $message | Should -Match 'failed with exit code 2'
        $message | Should -Match '\[REDACTED\]'
        $message.Contains($script:Fix95Secret) | Should -BeFalse
        $log.Count | Should -Be 1
        ([string]$log[0].Output).Contains($script:Fix95Secret) | Should -BeFalse
        (@($log[0].Arguments) -join ' ').Contains($script:Fix95Secret) | Should -BeFalse
        ($log[0] | ConvertTo-Json -Depth 4).Contains($script:Fix95Secret) | Should -BeFalse
    }
}

Describe 'FIX95 S1: only the known bundled-archive foreign-key problem is accepted' {
    BeforeAll {
        function Invoke-Fix95Restore {
            param([string]$DatabaseName = 'GameDBPPL13')
            $log = New-Object System.Collections.Generic.List[object]
            return (Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', $DatabaseName, 'game.backup') -CommandLog $log -DatabaseName $DatabaseName -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true)
        }
    }
    BeforeEach {
        $script:Fix95FakeExit = 1
        $script:Fix95FakeOutput = ''
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            if ($ToolName -ne 'pg_restore.exe') { return [pscustomobject]@{ Tool = $ToolName; Arguments = @($Arguments); ExitCode = 0; Succeeded = $true; Output = '' } }
            # FIX129: the fake runs the caller's -Interpret block on its text, like the real runner does.
            $command = [pscustomobject]@{ Tool = $ToolName; Arguments = @($Arguments); ExitCode = $script:Fix95FakeExit; Succeeded = ($script:Fix95FakeExit -eq 0); Output = $script:Fix95FakeOutput }
            return (Add-FakePostgresInterpretation -Command $command -Interpret $Interpret -InterpretContext $InterpretContext)
        }
    }

    # Mutation: drop the accept branch, or stop accepting the 8.3 DETAIL / "Command was:" lines.
    It 'S1: the known numeric-vs-integer foreign keys (<Type> entries) finish with a named known limitation' -TestCases @(
        @{ Type = 'FK CONSTRAINT' }
        @{ Type = 'CONSTRAINT' }
    ) {
        param($Type)
        $script:Fix95FakeOutput = New-Fix95RestoreOutput -Entries @((New-Fix95KnownEntry -Id 110 -Name 'category1_attr_fk' -Type $Type), (New-Fix95KnownEntry -Id 112 -Name 'category2_attr_fk' -Type $Type))

        $result = Invoke-Fix95Restore

        $result.Succeeded | Should -BeTrue
        (@($result.AcceptedConstraintNames) -join ',') | Should -BeExactly 'category1_attr_fk,category2_attr_fk'
        $result.AcceptedWarnings | Should -Match '^Finished with a known limitation: 2 links between tables in the game''s own backup could not be made\.'
        $result.AcceptedWarnings | Should -Not -Match 'all data was restored'
    }

    # Mutation: accept any CONSTRAINT entry without checking its error text (the S1 finding).
    It 'S1: a CONSTRAINT entry with an unexpected error fails (<Case>)' -TestCases @(
        @{ Case = 'primary key'; Name = 'category1_pkey'; ErrorText = 'multiple primary keys for table "category1" are not allowed'; Detail = '' }
        @{ Case = 'unique key'; Name = 'category1_name_key'; ErrorText = 'could not create unique index "category1_name_key"'; Detail = 'Table contains duplicated values.' }
        @{ Case = 'foreign key, missing rows'; Name = 'category1_attr_fk'; ErrorText = 'insert or update on table "category1" violates foreign key constraint "category1_attr_fk"'; Detail = 'Key (attr)=(7) is not present in table "attr".' }
        @{ Case = 'foreign key, other types'; Name = 'category1_attr_fk'; ErrorText = 'foreign key constraint "category1_attr_fk" cannot be implemented'; Detail = 'Key columns "attr" and "id" are of incompatible types: text and integer.' }
        @{ Case = 'foreign key, other name'; Name = 'category1_attr_fk'; ErrorText = 'foreign key constraint "other_fk" cannot be implemented'; Detail = '' }
    ) {
        param($Case, $Name, $ErrorText, $Detail)
        $script:Fix95FakeOutput = New-Fix95RestoreOutput -Entries @((New-Fix95KnownEntry -Id 110 -Name 'category2_attr_fk'), (New-Fix95TocError -Id 112 -Type 'CONSTRAINT' -Name $Name -ErrorText $ErrorText -Detail $Detail))

        { Invoke-Fix95Restore } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
    }

    # Mutation: treat exit 1 with no captured text as finished (fail-open on lost output).
    It 'S1: exit 1 with empty output stays a failure that says there was no diagnostic text' {
        $script:Fix95FakeOutput = ''
        { Invoke-Fix95Restore } | Should -Throw -ExpectedMessage '*failed with exit code 1: no diagnostic text*'
    }

    # Mutation: accept an entry whose "cannot be implemented" error is not followed by the numeric/integer
    # DETAIL line (the evidence that it is the known type mismatch).
    It 'S1: a known-looking foreign-key error without the numeric/integer DETAIL fails (<Case>)' -TestCases @(
        @{ Case = 'only entry'; WithKnownFirst = $false }
        @{ Case = 'second entry'; WithKnownFirst = $true }
    ) {
        param($Case, $WithKnownFirst)
        $bare = New-Fix95TocError -Id 112 -Type 'FK CONSTRAINT' -Name 'category2_attr_fk' -ErrorText 'foreign key constraint "category2_attr_fk" cannot be implemented'
        $entries = if ($WithKnownFirst) { @((New-Fix95KnownEntry -Id 110 -Name 'category1_attr_fk'), $bare) } else { @($bare) }
        $script:Fix95FakeOutput = New-Fix95RestoreOutput -Entries $entries
        { Invoke-Fix95Restore } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
    }

    # FIX125: the known output is accepted for the databases of the bundled vendor archives (Power Putt Live 2013, Silver Strike
    # Bowling Live, Target Toss Pro Lawndarts and Golden Tee Live 2019) as for any other database name; there is no name list.
    It 'S1: the known output for vendor database <DatabaseName> finishes with the known limitation' -TestCases @(
        @{ DatabaseName = 'GameDBPPL13' }
        @{ DatabaseName = 'GameDBSSB' }
        @{ DatabaseName = 'GameDBLawn' }
        @{ DatabaseName = 'GameDB19' }
    ) {
        param($DatabaseName)
        $script:Fix95FakeOutput = New-Fix95RestoreOutput -Entries @(New-Fix95KnownEntry -Id 110 -Name 'category1_attr_fk')
        (Invoke-Fix95Restore -DatabaseName $DatabaseName).Succeeded | Should -BeTrue
    }

    # Mutation: ignore lines outside the known entries (a second, unrelated error).
    It 'S1: any other error before or after the known entries fails' {
        $known = New-Fix95KnownEntry -Id 110 -Name 'category1_attr_fk'
        $script:Fix95FakeOutput = (New-Fix95RestoreOutput -Entries @($known) -Reported 1) + "`r`npg_restore: [archiver (db)] could not execute query: ERROR:  relation `"category9`" does not exist"
        { Invoke-Fix95Restore } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
    }

    # Mutation: make Invoke-Postgres83RestoreDatabase accept the known warning by default, so a
    # restore of the user's own backup could finish without its foreign keys.
    It 'S1: a database restore is strict unless the caller opts in for a bundled archive' {
        $script:Fix95FakeOutput = New-Fix95RestoreOutput -Entries @(New-Fix95KnownEntry -Id 110 -Name 'category1_attr_fk')
        Mock Get-PostgresDatabaseState { [pscustomobject]@{ Exists = $true; Verified = $true } }
        $item = [pscustomobject]@{ ItemId = 'item-1'; Database = 'GameDBPPL13'; BackupFile = (Join-Path $TestDrive 'game.backup'); BackupSha256 = ('A' * 64); Encoding = 'SQL_ASCII' }
        $preState = [pscustomobject]@{ Exists = $false; RollbackDumpPath = ''; RollbackDumpSha256 = '' }

        $strict = Invoke-Postgres83RestoreDatabase -Item $item -PreState $preState -SuperPasswordPlain 'pw'
        $bundled = Invoke-Postgres83RestoreDatabase -Item $item -PreState $preState -SuperPasswordPlain 'pw' -AcceptConstraintOnlyRestoreWarnings

        $strict.Succeeded | Should -BeFalse
        $strict.FailureStage | Should -BeExactly 'Restore'
        $bundled.Succeeded | Should -BeTrue
        @($bundled.Commands | Where-Object { $_.PSObject.Properties['AcceptedWarnings'] }).Count | Should -Be 1
    }

    # Mutation: stop passing the opt-in from the guided rebuild of a game's bundled archive.
    It 'S1: the guided rebuild from a bundled archive opts in' {
        $backupFile = Join-Path $TestDrive 'GameDBPPL13.backup'
        [System.IO.File]::WriteAllText($backupFile, 'fixture')
        Mock Write-Log {}
        Mock Invoke-PostgresRestoreTransaction { [pscustomobject]@{ Outcome = 'SUCCEEDED'; UnderlyingOutcome = $null; RecoveryBlocked = $false; Summary = 'fixture'; Backup = [pscustomobject]@{ Items = @() } } }

        [void](Reset-PostgresDatabaseFromBackup -DbName 'GameDBPPL13' -Encoding 'SQL_ASCII' -BackupFile $backupFile -SuperPasswordPlain 'pw' -RecoveryBackup ([pscustomobject]@{ Verified = $true; Path = $TestDrive }) -Confirmed)

        Should -Invoke Invoke-PostgresRestoreTransaction -Times 1 -Exactly -ParameterFilter { $AcceptConstraintOnlyRestoreWarnings.IsPresent }
    }

    # Mutation: add the opt-in to the restore of the user's own backups (restore menu).
    It 'S1: the restore of the user''s own backups never opts in' {
        $restoreFunction = @($script:Fix95Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Invoke-RestorePostgresBackup' }, $true))
        $restoreFunction.Count | Should -Be 1
        $calls = @($restoreFunction[0].FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Invoke-PostgresRestoreTransaction' }, $true))
        $calls.Count | Should -Be 1
        @($calls[0].CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'AcceptConstraintOnlyRestoreWarnings' }).Count | Should -Be 0
    }
}
