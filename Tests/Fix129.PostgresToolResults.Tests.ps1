#Requires -Module Pester

# FIX129: how the product runs and judges the PostgreSQL 8.3 tools (psql, createdb, dropdb, pg_dump, pg_restore).
#   S1  the text is judged RAW, in memory; only the stored / logged / shown text is redacted (a short password such as "1" or "db"
#       used to rewrite OIDs, names and the "1" that means "exists" before anything was parsed).
#   S2  the existence checks read STANDARD OUTPUT only, line by line (a stray stderr line made an existing database read as absent;
#       on rollback the verified drop then skipped the drop and reported a verified rollback).
#   S3  every tool is started with an English message locale (the restore checks read English text).
#   S4  every tool call has a REAL time limit; a tool that runs too long is stopped with its children and counts as failed.
#   N1  the encoding rule is written once.   N2  the restore is judged with the real result of createdb.
#   N3  a table or column called detail / error / warning in a "Command was:" continuation line is not an extra error.
#   N4  quoted identifiers (spaces, capitals, doubled quotes) are read correctly.   N5  the Fix125 test gaps.
# The production script is parsed and only the named functions are dot-sourced; no top-level product code runs. The tools are
# a small synthetic console program (compiled with the .NET Framework compiler that ships with Windows) copied under each tool
# name, so both PowerShell engines run the identical native binary. No PostgreSQL server, service, registry or profile is touched.
# What this CANNOT prove: the real text of pg_restore 8.3, that a real 8.3 server accepts PGOPTIONS "-c lc_messages=C", or a real restore.

BeforeAll {
    $script:F129ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $script:F129Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F129ProductPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX129 tests could not parse the production script.' }
    $script:F129FunctionNames = @(
        'ConvertTo-PostgresNativeArgument', 'Get-PostgresEnglishMessageEnvironment', 'Get-PostgresToolTimeoutSeconds',
        'Stop-PostgresToolProcessTree', 'Invoke-PostgresToolProcess', 'Invoke-PostgresNativeCommand', 'ConvertTo-PostgresRedactedText',
        'Test-PostgresToolExecutable', 'Set-PostgresPasswordEnvironment', 'Restore-PostgresPasswordEnvironment',
        'Get-PostgresStdoutLines', 'Get-PostgresExistenceProbeResult', 'Get-PostgresEncodingProbeResult', 'Get-PostgresCaseVariantProbeResult',
        'Get-PostgresDatabaseState', 'Get-PostgresDatabaseCaseVariantState', 'Get-PostgresPasswordProbe', 'Test-PostgresPasswordRejectionText',
        'Get-PostgresServiceStatusText', 'Invoke-Postgres83RestoreCommand', 'Invoke-Postgres83RestoreCommandChecked',
        'Invoke-Postgres83DropDatabaseVerified', 'Test-Postgres83RestoreToolSet', 'Get-Postgres83RestoreToolNames',
        'Get-PostgresRestoreJudgement', 'Get-PostgresKnownConstraintRestoreWarnings', 'ConvertFrom-PostgresQuotedIdentifier',
        'Get-PostgresRestoreEncoding', 'Format-TpmCountNoun', 'Get-TpmTransactionField', 'Test-SafePostgresDbName'
    )
    foreach ($name in $script:F129FunctionNames) {
        $fn = $script:F129Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if ($null -eq $fn) { throw ('FIX129 tests: function {0} not found in the production script.' -f $name) }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    function Write-Log { param([Parameter(ValueFromRemainingArguments = $true)]$Rest) }

    # One synthetic tool, copied under each tool name. Everything it does comes from FAKE129_<TOOL>_* variables:
    #   STDOUTFILE / STDERRFILE  text to print (ENCFILE replaces STDOUTFILE when an argument mentions pg_encoding_to_char)
    #   EXIT       exit code          SLEEP      seconds to wait before it ends
    #   ARGSFILE   writes the arguments it received, one per line
    #   ENVFILE    writes the locale / password variables it inherited
    #   PIDFILE    starts a grandchild (a copy of itself that waits) and writes "grandchildPid,ownPid"
    $script:F129Bin = Join-Path $TestDrive 'pgbin'
    [void][IO.Directory]::CreateDirectory($script:F129Bin)
    $script:F129Work = Join-Path $TestDrive 'work'
    [void][IO.Directory]::CreateDirectory($script:F129Work)
    $source = Join-Path $TestDrive 'Fake129Tool.cs'
    $code = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
public static class Fake129Tool {
  static string Get(string prefix, string name) { return Environment.GetEnvironmentVariable(prefix + name); }
  static string Show(string value) { return value == null ? "<unset>" : value; }
  public static int Main(string[] args) {
    string self = Assembly.GetEntryAssembly().Location;
    if (args.Length > 0 && args[0] == "--grandchild") { Thread.Sleep(120000); return 0; }
    string prefix = "FAKE129_" + Path.GetFileNameWithoutExtension(self).ToUpperInvariant() + "_";
    string argsFile = Get(prefix, "ARGSFILE");
    if (!String.IsNullOrEmpty(argsFile)) { File.WriteAllLines(argsFile, args); }
    string envFile = Get(prefix, "ENVFILE");
    if (!String.IsNullOrEmpty(envFile)) {
      File.WriteAllLines(envFile, new string[] {
        "LC_ALL=" + Show(Environment.GetEnvironmentVariable("LC_ALL")),
        "LC_MESSAGES=" + Show(Environment.GetEnvironmentVariable("LC_MESSAGES")),
        "LANG=" + Show(Environment.GetEnvironmentVariable("LANG")),
        "LANGUAGE=" + Show(Environment.GetEnvironmentVariable("LANGUAGE")),
        "PGOPTIONS=" + Show(Environment.GetEnvironmentVariable("PGOPTIONS")),
        "PGPASSWORD=" + Show(Environment.GetEnvironmentVariable("PGPASSWORD")) });
    }
    string pidFile = Get(prefix, "PIDFILE");
    if (!String.IsNullOrEmpty(pidFile)) {
      ProcessStartInfo info = new ProcessStartInfo(self, "--grandchild");
      info.UseShellExecute = false;
      info.CreateNoWindow = true;
      Process child = Process.Start(info);
      File.WriteAllText(pidFile, child.Id.ToString() + "," + Process.GetCurrentProcess().Id.ToString());
    }
    string outFile = Get(prefix, "STDOUTFILE");
    string encFile = Get(prefix, "ENCFILE");
    foreach (string a in args) { if (a.Contains("pg_encoding_to_char") && !String.IsNullOrEmpty(encFile)) { outFile = encFile; } }
    if (!String.IsNullOrEmpty(outFile)) { Console.Out.Write(File.ReadAllText(outFile)); Console.Out.Flush(); }
    string errFile = Get(prefix, "STDERRFILE");
    if (!String.IsNullOrEmpty(errFile)) { Console.Error.Write(File.ReadAllText(errFile)); Console.Error.Flush(); }
    string sleep = Get(prefix, "SLEEP");
    if (!String.IsNullOrEmpty(sleep)) { Thread.Sleep(Int32.Parse(sleep) * 1000); }
    string exit = Get(prefix, "EXIT");
    return String.IsNullOrEmpty(exit) ? 0 : Int32.Parse(exit);
  }
}
'@
    [IO.File]::WriteAllText($source, $code, (New-Object System.Text.UTF8Encoding $false))
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) { throw "The .NET Framework C# compiler was not found at $csc." }
    $built = Join-Path $script:F129Bin 'psql.exe'
    & $csc /nologo /target:exe "/out:$built" $source | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $built -PathType Leaf)) { throw 'The synthetic PostgreSQL tool could not be compiled.' }
    foreach ($tool in 'createdb', 'dropdb', 'pg_dump', 'pg_restore') { Copy-Item -LiteralPath $built -Destination (Join-Path $script:F129Bin "$tool.exe") }
    $script:PostgresBinDir = $script:F129Bin

    function Set-F129Tool {
        param([Parameter(Mandatory)][string]$Name, [int]$Exit = 0, [string]$StdOut = '', [string]$StdErr = '', [string]$EncStdOut = '', [int]$Sleep = 0, [string]$ArgsFile = '', [string]$EnvFile = '', [string]$PidFile = '')
        $prefix = 'FAKE129_' + $Name.ToUpperInvariant() + '_'
        $set = {
            param($Suffix, $Value)
            [Environment]::SetEnvironmentVariable($prefix + $Suffix, $Value, 'Process')
        }
        $textFile = {
            param($Suffix, $Text)
            if ($Text -eq '') { return '' }
            $path = Join-Path $script:F129Work ($Name + '-' + $Suffix + '-' + [guid]::NewGuid().ToString('N') + '.txt')
            [IO.File]::WriteAllText($path, $Text, (New-Object System.Text.UTF8Encoding $false))
            return $path
        }
        & $set 'STDOUTFILE' (& $textFile 'out' $StdOut)
        & $set 'STDERRFILE' (& $textFile 'err' $StdErr)
        & $set 'ENCFILE' (& $textFile 'enc' $EncStdOut)
        & $set 'EXIT' ([string]$Exit)
        & $set 'SLEEP' $(if ($Sleep -gt 0) { [string]$Sleep } else { '' })
        & $set 'ARGSFILE' $ArgsFile
        & $set 'ENVFILE' $EnvFile
        & $set 'PIDFILE' $PidFile
    }
    function Reset-F129Tools {
        foreach ($name in 'psql', 'createdb', 'dropdb', 'pg_dump', 'pg_restore') {
            foreach ($suffix in 'STDOUTFILE', 'STDERRFILE', 'ENCFILE', 'EXIT', 'SLEEP', 'ARGSFILE', 'ENVFILE', 'PIDFILE') {
                [Environment]::SetEnvironmentVariable(('FAKE129_' + $name.ToUpperInvariant() + '_' + $suffix), '', 'Process')
            }
        }
    }
    function Get-F129FunctionAst {
        param([string]$Name)
        return $script:F129Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $Name }, $true)
    }

    # One error block exactly as the 8.3 pg_restore prints it for these backups (multi-line statement as pg_dump writes it).
    function New-F129Block {
        param([int]$Id = 110, [string]$Name = 'category1_attr_fk', [string]$EntryName = '', [string]$EntryKind = 'CONSTRAINT', [string]$ErrorName = '', [string[]]$CommandLines = @(), [string]$Detail = 'Key columns "object_id" and "object_id" are of incompatible types: numeric and integer.', [switch]$NoDetail, [switch]$NoCommand)
        if (-not $EntryName) { $EntryName = $Name }
        if (-not $ErrorName) { $ErrorName = $Name }
        if ($CommandLines.Count -eq 0) { $CommandLines = @(('ALTER TABLE ONLY category1_attr'), ('    ADD CONSTRAINT {0} FOREIGN KEY (object_id) REFERENCES category1_object(object_id);' -f $Name)) }
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add(('pg_restore: [archiver (db)] Error from TOC entry {0}; 0 3172634 {1} {2} postgres' -f $Id, $EntryKind, $EntryName))
        $lines.Add(('pg_restore: [archiver (db)] could not execute query: ERROR:  foreign key constraint "{0}" cannot be implemented' -f $ErrorName))
        if (-not $NoDetail) { $lines.Add(('DETAIL:  {0}' -f $Detail)) }
        if (-not $NoCommand) {
            $lines.Add(('    Command was: {0}' -f $CommandLines[0]))
            foreach ($more in @($CommandLines | Select-Object -Skip 1)) { $lines.Add($more) }
        }
        return @($lines)
    }
    function New-F129Output {
        param([object[]]$Blocks, [int]$Reported = -1, [string]$Newline = "`r`n", [string]$IgnoredPrefix = '')
        if ($Reported -lt 0) { $Reported = @($Blocks).Count }
        $all = New-Object System.Collections.Generic.List[string]
        $all.Add('pg_restore: [archiver (db)] Error while PROCESSING TOC:')
        foreach ($block in @($Blocks)) { foreach ($line in @($block)) { $all.Add([string]$line) } }
        $all.Add(('{0}WARNING: errors ignored on restore: {1}' -f $IgnoredPrefix, $Reported))
        return ($all -join $Newline)
    }
    function Get-F129FiveBlocks {
        return @(1..5 | ForEach-Object { , @(New-F129Block -Id (100 + 2 * $_) -Name ('category{0}_attr_fk' -f $_)) })
    }
}

AfterAll { Reset-F129Tools }

Describe 'FIX129 S1: the raw text is judged, only the stored text is redacted' {
    BeforeEach { Reset-F129Tools }
    AfterEach { Reset-F129Tools }

    It 'reads "exists" and the encoding when the password is "<Password>" (found in the text it must not rewrite)' -TestCases @(
        @{ Password = '1' }, @{ Password = 'LATIN1' }, @{ Password = 'a' }
    ) {
        param($Password)
        # Mutation: redact the output before reading it (the old order) -> the "1" becomes "[REDACTED]", the database reads absent,
        # and LATIN1 loses its characters, so the encoding reads unknown.
        Set-F129Tool -Name psql -StdOut "1`r`n" -EncStdOut "LATIN1`r`n"
        $state = Get-PostgresDatabaseState -DbName 'GameDB19' -SuperPasswordPlain $Password
        $state.Verified | Should -BeTrue
        $state.Exists | Should -BeTrue
        $state.Encoding | Should -BeExactly 'LATIN1'
    }

    It 'still reads an absent database as absent' {
        Set-F129Tool -Name psql -StdOut ''
        $state = Get-PostgresDatabaseState -DbName 'GameDB19' -SuperPasswordPlain '1'
        $state.Exists | Should -BeFalse
        $state.Verified | Should -BeTrue
    }

    It 'finds a case variant whose name contains the password' {
        # Mutation: redact before comparing -> "GAMEDB19" becomes "GAME[REDACTED]19", no longer equals the name, and the variant is missed.
        Set-F129Tool -Name psql -StdOut "GAMEDB19`r`n"
        $state = Get-PostgresDatabaseCaseVariantState -DbName 'GameDB19' -SuperPasswordPlain 'DB'
        $state.Verified | Should -BeTrue
        @($state.Variants).Count | Should -Be 1
        ($state.Variants -join ',') | Should -Not -Match 'DB'
    }

    It 'classifies a rejected password from the raw psql text even when the password is "a"' {
        # Mutation: classify the redacted text -> "p[REDACTED]ssword [REDACTED]uthentic..." is not recognized and the state is Unavailable.
        Mock Get-PostgresServiceStatusText { 'Running' }
        Set-F129Tool -Name psql -Exit 2 -StdErr 'psql: FATAL:  password authentication failed for user "postgres"'
        $probe = Get-PostgresPasswordProbe -SuperPasswordPlain 'a'
        $probe.State | Should -BeExactly 'Rejected'
        $probe.Detail | Should -Not -Match 'password authentication' -Because 'the shown text is redacted'
    }

    It 'checks the tool versions without a password, so a short password cannot rewrite "8.3"' {
        # Mutation: pass the password to the version check -> "PostgreSQL 8.3.23" is rewritten and the tool set is refused.
        foreach ($tool in 'psql', 'pg_dump', 'dropdb', 'createdb', 'pg_restore') { Set-F129Tool -Name $tool -StdOut ('{0} (PostgreSQL) 8.3.23' -f $tool) }
        $set = Test-Postgres83RestoreToolSet -SuperPasswordPlain '8'
        $set.Verified | Should -BeTrue
    }

    It 'judges a known restore on the raw text with a short password in every OID and name' {
        # Mutation: judge the redacted text (the old order) -> with the password "1" every TOC id, count and name is rewritten and the
        # known restore is refused and rolled back.
        Set-F129Tool -Name pg_restore -Exit 1 -StdErr (New-F129Output -Blocks (Get-F129FiveBlocks))
        $log = New-Object System.Collections.Generic.List[object]
        $command = Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDB19', 'game.backup') -SuperPasswordPlain '1' -CommandLog $log -DatabaseName 'GameDB19' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true
        $command.Succeeded | Should -BeTrue
        $command.AcceptedWarningCount | Should -Be 5
        $command.Output | Should -Match '\[REDACTED\]'
    }

    It 'keeps the password out of everything that is stored: the output, the names and the judgement' {
        # Mutation: keep the raw constraint names or the raw text in the command that goes to the log and the receipts. The password
        # "category" is part of every constraint name, so it is in the raw text the judgement reads.
        Set-F129Tool -Name pg_restore -Exit 1 -StdErr (New-F129Output -Blocks (Get-F129FiveBlocks))
        $log = New-Object System.Collections.Generic.List[object]
        $command = Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDB19', 'game.backup') -SuperPasswordPlain 'category' -CommandLog $log -DatabaseName 'GameDB19' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true
        $command.Succeeded | Should -BeTrue -Because 'the raw text is judged, so the password inside the names does not matter'
        $command.AcceptedWarningCount | Should -Be 5
        ($log | ConvertTo-Json -Depth 8) | Should -Not -Match 'category'
        ($command.AcceptedConstraintNames -join ' ') | Should -Not -Match 'category'
        ($command.AcceptedConstraintNames -join ' ') | Should -Match '\[REDACTED\]'
    }

    It 'never accepts known-warning text that pg_restore printed on standard output (only standard error is judged)' {
        # Mutation: judge the merged stdout+stderr text -> text that only looks like the known warnings, printed on standard output with an
        # empty standard error, makes a failed restore (exit 1) look finished.
        $text = New-F129Output -Blocks (Get-F129FiveBlocks)
        Set-F129Tool -Name pg_restore -Exit 1 -StdOut $text
        $log = New-Object System.Collections.Generic.List[object]
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDB19', 'game.backup') -SuperPasswordPlain 'pw' -CommandLog $log -DatabaseName 'GameDB19' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
        $log[0].Succeeded | Should -BeFalse
        $log[0].Interpretation.Reason | Should -BeExactly 'NotOnlyKnownWarnings'
        # The real thing on standard error is accepted, and a line of chatter on standard output next to it does not change that.
        Set-F129Tool -Name pg_restore -Exit 1 -StdErr $text -StdOut 'pg_restore: restoring'
        $okLog = New-Object System.Collections.Generic.List[object]
        (Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDB19', 'game.backup') -SuperPasswordPlain 'pw' -CommandLog $okLog -DatabaseName 'GameDB19' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true).Succeeded | Should -BeTrue
    }

    It 'redacts the text in one pass (a password that is part of the marker, or listed twice, never rewrites the marker)' {
        # Mutation: redact in a loop, one secret after the other (the old code; the runner lists the password twice: in -Secrets and as the
        # password) or redact the finished text again in Invoke-Postgres83RestoreCommand -> "[REDACTED]" becomes "[[REDACTED]ACTED]" for "RED".
        Set-F129Tool -Name psql -Exit 2 -StdErr 'FATAL: the password is RED'
        $command = Invoke-Postgres83RestoreCommand -ToolName 'psql.exe' -Arguments @('-c', 'x') -SuperPasswordPlain 'RED'
        $command.Output | Should -BeExactly 'FATAL: the password is [REDACTED]'
    }

    It 'hides every secret, the longest first, case-sensitively, and ignores empty ones' {
        # Mutation: shortest first ("abc" before "abcd" leaves a stray "d"), case-insensitive matching, or a regex special character used as a pattern.
        ConvertTo-PostgresRedactedText -Text 'abc abcd' -Secrets @('abc', 'abcd') | Should -BeExactly '[REDACTED] [REDACTED]'
        ConvertTo-PostgresRedactedText -Text 'a A b' -Secrets @('a', 'A') | Should -BeExactly '[REDACTED] [REDACTED] b'
        ConvertTo-PostgresRedactedText -Text 'a A b' -Secrets @('a') | Should -BeExactly '[REDACTED] A b'
        ConvertTo-PostgresRedactedText -Text 'x.y (z) xzy' -Secrets @('x.y', '(z)', '') | Should -BeExactly '[REDACTED] [REDACTED] xzy'
        ConvertTo-PostgresRedactedText -Text $null -Secrets @('a') | Should -BeExactly ''
    }
}

Describe 'FIX129 S2: existence is read from standard output, line by line' {
    BeforeEach { Reset-F129Tools }
    AfterEach { Reset-F129Tools }

    It 'reads "exists" when psql also writes a line on standard error' {
        # Mutation: parse the merged stdout+stderr text with a whole-text ^\s*1\s*$ (the old code) -> the database reads absent.
        Set-F129Tool -Name psql -StdOut "1`r`n" -StdErr 'WARNING:  could not set the client encoding'
        (Get-PostgresDatabaseState -DbName 'GameDB19' -SuperPasswordPlain 'pw').Exists | Should -BeTrue
    }

    It 'does not read an unrecognized answer as absent (<Case>)' -TestCases @(
        @{ Case = 'another number'; Text = "2`r`n" }
        @{ Case = 'two rows'; Text = "1`r`n1`r`n" }
        @{ Case = 'words'; Text = "psql: could not connect`r`n" }
    ) {
        param($Case, $Text)
        # Mutation: any text that is not exactly "1" means absent -> an answer nobody understood lets the setup create over a database.
        Set-F129Tool -Name psql -StdOut $Text
        { Get-PostgresDatabaseState -DbName 'GameDB19' -SuperPasswordPlain 'pw' } | Should -Throw -ExpectedMessage '*could not be read*'
    }

    It 'reads LF-only and padded answers the same way' {
        Set-F129Tool -Name psql -StdOut " 1 `n"
        (Get-PostgresDatabaseState -DbName 'GameDB19' -SuperPasswordPlain 'pw').Exists | Should -BeTrue
    }

    It 'the verified drop of a rollback drops a database that psql reports with a stray stderr line, and does not report a verified rollback when it still exists' {
        # Mutation: the old whole-text check reads the database as absent -> the drop is skipped and the rollback is called verified.
        $argsFile = Join-Path $script:F129Work 'dropdb-args.txt'
        Remove-Item -LiteralPath $argsFile -Force -ErrorAction SilentlyContinue
        Set-F129Tool -Name psql -StdOut "1`r`n" -StdErr 'WARNING:  stray line'
        Set-F129Tool -Name dropdb -ArgsFile $argsFile
        $log = New-Object System.Collections.Generic.List[object]
        $receipt = Invoke-Postgres83DropDatabaseVerified -DbName 'GameDB19' -SuperPasswordPlain 'pw' -CommandLog $log -AllowExistingDrop $true
        Test-Path -LiteralPath $argsFile | Should -BeTrue -Because 'dropdb must have been called for a database that exists'
        $receipt.Verified | Should -BeFalse -Because 'psql still says the database exists after the drop'
    }

    It 'does not drop an existing database unless the caller says it owns it' {
        # Mutation: default AllowExistingDrop back to $true -> a future caller that forgets the switch can drop a user database.
        $argsFile = Join-Path $script:F129Work 'dropdb-args-default.txt'
        Remove-Item -LiteralPath $argsFile -Force -ErrorAction SilentlyContinue
        Set-F129Tool -Name psql -StdOut "1`r`n"
        Set-F129Tool -Name dropdb -ArgsFile $argsFile
        $log = New-Object System.Collections.Generic.List[object]
        $receipt = Invoke-Postgres83DropDatabaseVerified -DbName 'GameDB19' -SuperPasswordPlain 'pw' -CommandLog $log
        Test-Path -LiteralPath $argsFile | Should -BeFalse -Because 'dropdb must not run for a database whose ownership was not stated'
        $receipt.Verified | Should -BeFalse
    }
}

Describe 'FIX129 S3: the tools are started with an English message locale' {
    BeforeEach { Reset-F129Tools }
    AfterEach { Reset-F129Tools }

    It 'builds the child environment (and keeps the options that are already set)' {
        $plain = Get-PostgresEnglishMessageEnvironment
        $plain['LC_ALL'] | Should -BeExactly 'C'
        $plain['LC_MESSAGES'] | Should -BeExactly 'C'
        $plain['LANG'] | Should -BeExactly 'C'
        $plain['LANGUAGE'] | Should -BeExactly 'en'
        $plain['PGOPTIONS'] | Should -BeExactly '-c lc_messages=C'
        $kept = Get-PostgresEnglishMessageEnvironment -ExistingOptions '-c work_mem=1MB'
        $kept['PGOPTIONS'] | Should -BeExactly '-c work_mem=1MB -c lc_messages=C'
    }

    It 'a real tool process sees the English locale even when this process is set to another language, and this process is not changed' {
        # Mutation: do not pass the locale to the child -> the tool and the server answer in the Windows language and the known text is not recognized.
        $envFile = Join-Path $script:F129Work 'env-seen.txt'
        $saved = @{}
        foreach ($name in 'LC_ALL', 'LC_MESSAGES', 'LANG', 'LANGUAGE', 'PGOPTIONS') { $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
        try {
            [Environment]::SetEnvironmentVariable('LC_ALL', 'de_DE', 'Process')
            [Environment]::SetEnvironmentVariable('LANG', 'de_DE', 'Process')
            [Environment]::SetEnvironmentVariable('LANGUAGE', 'de', 'Process')
            [Environment]::SetEnvironmentVariable('LC_MESSAGES', 'de_DE', 'Process')
            [Environment]::SetEnvironmentVariable('PGOPTIONS', '-c work_mem=1MB', 'Process')
            Set-F129Tool -Name pg_restore -EnvFile $envFile
            $result = Invoke-Postgres83RestoreCommand -ToolName 'pg_restore.exe' -Arguments @('--list', 'x.backup') -SuperPasswordPlain 'Pw-129'
            $result.Succeeded | Should -BeTrue
            $seen = @{}
            foreach ($line in [IO.File]::ReadAllLines($envFile)) { $pair = $line.Split('=', 2); $seen[$pair[0]] = $pair[1] }
            $seen['LC_ALL'] | Should -BeExactly 'C'
            $seen['LC_MESSAGES'] | Should -BeExactly 'C'
            $seen['LANG'] | Should -BeExactly 'C'
            $seen['LANGUAGE'] | Should -BeExactly 'en'
            $seen['PGOPTIONS'] | Should -BeExactly '-c work_mem=1MB -c lc_messages=C'
            $seen['PGPASSWORD'] | Should -BeExactly 'Pw-129' -Because 'the password still reaches the tool through PGPASSWORD'
            [Environment]::GetEnvironmentVariable('LANG', 'Process') | Should -BeExactly 'de_DE'
            [Environment]::GetEnvironmentVariable('PGOPTIONS', 'Process') | Should -BeExactly '-c work_mem=1MB'
        } finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process') }
        }
    }
}

Describe 'FIX129 S4: a tool call has a real time limit' {
    BeforeEach { Reset-F129Tools }
    AfterEach { Reset-F129Tools }

    It 'documents a limit a 60-minute restore of the largest bundled backup cannot reach' {
        # Mutation: a limit under 60 minutes (or none) for pg_restore / pg_dump.
        (Get-PostgresToolTimeoutSeconds -FilePath 'C:\x\pg_restore.exe') | Should -BeGreaterOrEqual (3 * 3600)
        (Get-PostgresToolTimeoutSeconds -FilePath 'C:\x\PG_DUMP.EXE') | Should -BeGreaterOrEqual (3 * 3600)
        (Get-PostgresToolTimeoutSeconds -FilePath 'C:\x\psql.exe') | Should -BeGreaterThan 0
        (Get-PostgresToolTimeoutSeconds -FilePath 'C:\x\createdb.exe') | Should -BeGreaterThan 0
    }

    It 'stops a tool that runs too long, sets TimedOut and fails closed' {
        # Mutation: no timeout in the runner (the old code waited for ever) -> this call takes the full 30 seconds and TimedOut stays false.
        Set-F129Tool -Name psql -Sleep 30 -StdOut "1`r`n"
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-PostgresNativeCommand -FilePath (Join-Path $script:F129Bin 'psql.exe') -Arguments @('-c', 'x') -TimeoutSeconds 3
        $clock.Stop()
        $result.TimedOut | Should -BeTrue
        $result.ExitCode | Should -Not -Be 0
        $result.Output | Should -Match 'gave up on psql\.exe after 3 seconds'
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 25
    }

    It 'stops the children of a tool that ran too long' {
        # Mutation: stop only the process itself (Kill without the tree) -> the grandchild keeps running for two minutes.
        $pidFile = Join-Path $script:F129Work 'pids.txt'
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        Set-F129Tool -Name pg_restore -Sleep 30 -PidFile $pidFile
        $result = Invoke-PostgresNativeCommand -FilePath (Join-Path $script:F129Bin 'pg_restore.exe') -Arguments @('x') -TimeoutSeconds 3
        $result.TimedOut | Should -BeTrue
        $ids = @([IO.File]::ReadAllText($pidFile).Trim().Split(',') | ForEach-Object { [int]$_ })
        $ids.Count | Should -Be 2
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        while ([DateTime]::UtcNow -lt $deadline -and @($ids | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue }).Count -gt 0) { Start-Sleep -Milliseconds 200 }
        foreach ($id in $ids) { (Get-Process -Id $id -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty -Because ('process ' + $id + ' must be gone') }
    }

    It 'a restore that would have ended in the known warnings after the limit is still a failure' {
        # Mutation: ignore TimedOut in the judgement or in the runner -> the late "known warnings" text is accepted.
        Mock Get-PostgresToolTimeoutSeconds { 3 }
        Set-F129Tool -Name pg_restore -Exit 1 -Sleep 20 -StdErr (New-F129Output -Blocks (Get-F129FiveBlocks))
        $log = New-Object System.Collections.Generic.List[object]
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDB19', 'game.backup') -SuperPasswordPlain 'pw' -CommandLog $log -DatabaseName 'GameDB19' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true } | Should -Throw -ExpectedMessage '*failed with exit code*(timed out)*'
        $log.Count | Should -Be 1
        $log[0].TimedOut | Should -BeTrue
        $log[0].Succeeded | Should -BeFalse
        $log[0].Interpretation.Reason | Should -BeExactly 'TimedOut'
    }

    It 'a tool that ends in time is not marked timed out and keeps its exit code and both streams' {
        Set-F129Tool -Name createdb -Exit 3 -StdOut 'out line' -StdErr 'err line'
        $result = Invoke-PostgresNativeCommand -FilePath (Join-Path $script:F129Bin 'createdb.exe') -Arguments @('x')
        $result.TimedOut | Should -BeFalse
        $result.ExitCode | Should -Be 3
        $result.Output | Should -Match 'out line'
        $result.Output | Should -Match 'err line'
    }
}

Describe 'FIX129 the command line given to a tool keeps every argument (replaces the FIX56 PowerShell-argument helper)' {
    BeforeEach { Reset-F129Tools }
    AfterEach { Reset-F129Tools }

    It 'quotes an argument the way the Windows command-line parser reads it back' -TestCases @(
        @{ Value = 'GameDBPPL13'; Expected = 'GameDBPPL13' }
        @{ Value = ''; Expected = '""' }
        @{ Value = 'C:\Program Files (x86)\PostgreSQL\8.3\bin'; Expected = '"C:\Program Files (x86)\PostgreSQL\8.3\bin"' }
        @{ Value = 'C:\Games\PowerPuttLive\'; Expected = 'C:\Games\PowerPuttLive\' }
        @{ Value = 'C:\Game Files\'; Expected = '"C:\Game Files\\"' }
        @{ Value = 'ALTER DATABASE "GameDBPPL13" SET standard_conforming_strings = on;'; Expected = '"ALTER DATABASE \"GameDBPPL13\" SET standard_conforming_strings = on;"' }
        @{ Value = 'a\"b'; Expected = '"a\\\"b"' }
    ) {
        param($Value, $Expected)
        # Mutation: leave the inner double quotes alone (the FIX56 bug: the server folds GameDBPPL13 to lowercase) or forget the doubled backslashes.
        ConvertTo-PostgresNativeArgument -Value $Value | Should -BeExactly $Expected
    }

    It 'delivers every argument unchanged to a real program' {
        # Mutation: build the command line by joining the raw arguments with spaces.
        $argsFile = Join-Path $script:F129Work 'args-seen.txt'
        $sent = @('-U', 'postgres', '-d', 'GameDBPPL13', '-c', 'ALTER DATABASE "GameDBPPL13" SET standard_conforming_strings = on;', 'C:\Backups With Space\GameDB.backup', 'C:\Dir With Space\', '', 'a\"b')
        Set-F129Tool -Name psql -ArgsFile $argsFile
        $result = Invoke-PostgresNativeCommand -FilePath (Join-Path $script:F129Bin 'psql.exe') -Arguments $sent
        $result.ExitCode | Should -Be 0
        $seen = @([IO.File]::ReadAllLines($argsFile))
        $seen.Count | Should -Be $sent.Count
        for ($i = 0; $i -lt $sent.Count; $i++) { $seen[$i] | Should -BeExactly $sent[$i] }
    }
}

Describe 'FIX129 N1 / N2: one encoding rule, and the restore is judged with the real result of createdb' {
    It 'writes the GameDB06 encoding rule only in Get-PostgresRestoreEncoding' {
        # Mutation: write the rule again in a caller (as the reinitialize plan did) -> two rules can disagree.
        $constants = @($script:F129Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -ieq 'GameDB06' }, $true))
        $constants.Count | Should -Be 1
        $owner = $constants[0].Parent
        while ($null -ne $owner -and $owner -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $owner = $owner.Parent }
        $owner.Name | Should -BeExactly 'Get-PostgresRestoreEncoding'
        Get-PostgresRestoreEncoding -DbName 'GameDB06' | Should -BeExactly 'UTF8'
        Get-PostgresRestoreEncoding -DbName 'GameDB19' | Should -BeExactly 'SQL_ASCII'
    }

    It 'refuses the known warnings when the caller did not say createdb succeeded, and accepts them when it did' {
        # Mutation: pass $true unconditionally (the old code) -> the DatabaseNotCreated branch cannot be reached.
        Reset-F129Tools
        try {
            $text = New-F129Output -Blocks (Get-F129FiveBlocks)
            Set-F129Tool -Name pg_restore -Exit 1 -StdErr $text
            $log = New-Object System.Collections.Generic.List[object]
            { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDB19', 'x') -SuperPasswordPlain 'pw' -CommandLog $log -DatabaseName 'GameDB19' -AcceptConstraintOnlyRestoreWarnings } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
            $log[0].Interpretation.Reason | Should -BeExactly 'DatabaseNotCreated'
            $okLog = New-Object System.Collections.Generic.List[object]
            $ok = Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDB19', 'x') -SuperPasswordPlain 'pw' -CommandLog $okLog -DatabaseName 'GameDB19' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true
            $ok.Succeeded | Should -BeTrue
            $ok.Interpretation.Reason | Should -BeExactly 'KnownWarningsOnly'
        } finally { Reset-F129Tools }
    }

    It 'every opted-in pg_restore call in the product passes the result of its own createdb, never a literal' {
        # Mutation: an opted-in call without -CreatedbSucceeded, or with a literal $true.
        $calls = @($script:F129Ast.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-Postgres83RestoreCommandChecked' -and $n.Extent.Text -match "'pg_restore\.exe'" -and $n.Extent.Text -match 'AcceptConstraintOnlyRestoreWarnings'
                }, $true))
        $calls.Count | Should -BeGreaterOrEqual 2
        foreach ($call in $calls) {
            $call.Extent.Text | Should -Match '-CreatedbSucceeded \$createdbSucceeded\b'
            $call.Extent.Text | Should -Not -Match '-CreatedbSucceeded \$true'
        }
    }
}

Describe 'FIX129 N3 / N4 / N5: the known-warning parser' {
    It 'accepts a multi-line "Command was:" statement as pg_dump writes it' {
        # Mutation: read only the first "Command was:" line -> the statement has no ADD CONSTRAINT and is refused.
        $names = @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks (Get-F129FiveBlocks)))
        ($names -join ',') | Should -BeExactly 'category1_attr_fk,category2_attr_fk,category3_attr_fk,category4_attr_fk,category5_attr_fk'
    }

    It 'accepts LF-only text and the "pg_restore: WARNING:" prefix' -TestCases @(
        @{ Case = 'LF only'; Newline = "`n"; Prefix = '' }
        @{ Case = 'CRLF with the tool prefix'; Newline = "`r`n"; Prefix = 'pg_restore: ' }
        @{ Case = 'LF with the tool prefix'; Newline = "`n"; Prefix = 'pg_restore: ' }
    ) {
        param($Case, $Newline, $Prefix)
        # Mutation: split only on CRLF, or require the bare WARNING line.
        @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks (Get-F129FiveBlocks) -Newline $Newline -IgnoredPrefix $Prefix)).Count | Should -Be 5 -Because $Case
    }

    It 'accepts the FK CONSTRAINT entry shape' {
        # Mutation: only the plain CONSTRAINT entry is read.
        $blocks = @(, @(New-F129Block -Id 3270 -Name 'category1_attr_fk' -EntryKind 'FK CONSTRAINT'))
        (Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks $blocks)) | Should -BeExactly 'category1_attr_fk'
    }

    It 'accepts a table, a column and a constraint called detail, error or warning (continuation lines are SQL, not messages)' {
        # Mutation: refuse a continuation line that merely contains ERROR, WARNING, DETAIL or HINT (the old rule) -> a known restore is rolled back.
        $command = @('ALTER TABLE ONLY detail', '    ADD CONSTRAINT error_fk FOREIGN KEY (warning)', '    REFERENCES hint(detail);')
        $blocks = @(, @(New-F129Block -Name 'error_fk' -CommandLines $command))
        (Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks $blocks)) | Should -BeExactly 'error_fk'
        $named = @(, @(New-F129Block -Name 'detail' -CommandLines @('ALTER TABLE ONLY error', '    ADD CONSTRAINT detail FOREIGN KEY (warning) REFERENCES hint(error);')))
        (Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks $named)) | Should -BeExactly 'detail'
    }

    It 'accepts quoted, mixed-case and spaced names, and doubled quotes inside a name' -TestCases @(
        @{ Case = 'mixed case, quoted'; Name = 'Category1_FK'; Statement = 'ADD CONSTRAINT "Category1_FK" FOREIGN KEY (a) REFERENCES b(a);' }
        @{ Case = 'spaces, quoted'; Name = 'my fk name'; Statement = 'ADD CONSTRAINT "my fk name" FOREIGN KEY (a) REFERENCES "Other Table"(a);' }
        @{ Case = 'doubled quote inside'; Name = 'odd"name'; Statement = 'ADD CONSTRAINT "odd""name" FOREIGN KEY (a) REFERENCES b(a);' }
        @{ Case = 'mixed case, not quoted'; Name = 'Category1_FK'; Statement = 'ADD CONSTRAINT Category1_FK FOREIGN KEY (a) REFERENCES b(a);' }
    ) {
        param($Case, $Name, $Statement)
        # Mutation: take the entry name as one \S+ token, or compare it with the unquoted text of the statement.
        $block = New-F129Block -Name $Name -CommandLines @('ALTER TABLE ONLY "Some Table"', ('    ' + $Statement))
        $names = @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks @(, $block)))
        $names.Count | Should -Be 1 -Because $Case
        $names[0] | Should -BeExactly $Name
    }

    It 'refuses a name that differs only by case from the one in the statement' {
        # Mutation: compare the names without case (the old (?i) over the whole pattern).
        $block = New-F129Block -Name 'Category1_FK' -CommandLines @('ALTER TABLE ONLY t', '    ADD CONSTRAINT category1_fk FOREIGN KEY (a) REFERENCES b(a);')
        @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks @(, $block))).Count | Should -Be 0
    }

    It 'still refuses real extra errors (<Case>)' -TestCases @(
        @{ Case = 'a server error after the statement'; Extra = @('ERROR:  relation "x" does not exist') }
        @{ Case = 'a tool error line after the statement'; Extra = @('pg_restore: [archiver (db)] could not execute query: ERROR:  relation "x" does not exist') }
        @{ Case = 'a warning line after the statement'; Extra = @('WARNING:  something else') }
        @{ Case = 'an unprefixed could-not line after the statement'; Extra = @('could not execute query: ERROR:  relation "x" does not exist') }
        @{ Case = 'text that is not SQL after the finished statement'; Extra = @('something nobody expected') }
    ) {
        param($Case, $Extra)
        # Mutation: treat any line after "Command was:" as a continuation of the statement.
        $blocks = @(Get-F129FiveBlocks)
        $blocks[4] = @($blocks[4]) + @($Extra)
        @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks $blocks)).Count | Should -Be 0 -Because $Case
    }

    It 'refuses a message that starts inside an unfinished statement, and a statement that never ends' {
        # Mutation: accept a "Command was:" text that does not end with a semicolon, or let a message line join the statement.
        $open = New-F129Block -Name 'category1_attr_fk' -CommandLines @('ALTER TABLE ONLY category1_attr', '    ADD CONSTRAINT category1_attr_fk FOREIGN KEY (object_id) REFERENCES category1_object(object_id)')
        @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks @(, $open))).Count | Should -Be 0
        $message = New-F129Block -Name 'category1_attr_fk' -CommandLines @('ALTER TABLE ONLY category1_attr', 'ERROR:  something', '    ADD CONSTRAINT category1_attr_fk FOREIGN KEY (a) REFERENCES b(a);')
        @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks @(, $message))).Count | Should -Be 0
    }

    It 'refuses four blocks when the warning says five, and a repeated "errors ignored" line' {
        # Mutation: ignore the count, or let a second "errors ignored" line replace the first.
        $four = @(Get-F129FiveBlocks | Select-Object -First 4)
        @(Get-PostgresKnownConstraintRestoreWarnings -Output (New-F129Output -Blocks $four -Reported 5)).Count | Should -Be 0
        $text = (New-F129Output -Blocks (Get-F129FiveBlocks)) + "`r`n" + 'WARNING: errors ignored on restore: 5'
        @(Get-PostgresKnownConstraintRestoreWarnings -Output $text).Count | Should -Be 0
        $lateSecond = (New-F129Output -Blocks (Get-F129FiveBlocks)) + "`r`npg_restore: WARNING: errors ignored on restore: 5"
        @(Get-PostgresKnownConstraintRestoreWarnings -Output $lateSecond).Count | Should -Be 0
    }

    It 'accepts the known warnings for any database name (there is no name list)' {
        # Mutation: bring back a list of database names anywhere in the judgement path -> a bundled backup under another name rolls everything back.
        # (The Fix125 version of this test could not fail: the Checked function never passed the name on.) Here the real runner is used with names
        # that are in no list, and the three functions are checked for a name list or a name input.
        Reset-F129Tools
        try {
            foreach ($database in @('GameDBPPL12', 'GameDB06', 'x', ('Db' + [guid]::NewGuid().ToString('N')), 'gamedbppl13', 'ZZZ_unlisted_999')) {
                Set-F129Tool -Name pg_restore -Exit 1 -StdErr (New-F129Output -Blocks (Get-F129FiveBlocks))
                $log = New-Object System.Collections.Generic.List[object]
                $r = Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', $database, 'game.backup') -SuperPasswordPlain 'pw' -CommandLog $log -DatabaseName $database -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true
                $r.Succeeded | Should -BeTrue -Because $database
            }
        } finally { Reset-F129Tools }
        foreach ($name in 'Get-PostgresRestoreJudgement', 'Get-PostgresKnownConstraintRestoreWarnings', 'Invoke-Postgres83RestoreCommandChecked') {
            $text = (Get-F129FunctionAst -Name $name).Extent.Text
            $text | Should -Not -Match '(?i)GameDB' -Because ($name + ' must not name a database')
        }
        $judgement = Get-F129FunctionAst -Name 'Get-PostgresRestoreJudgement'
        @($judgement.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) | Should -Not -Contain 'DbName'
        @($judgement.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) | Should -Not -Contain 'DatabaseName'
    }
}
