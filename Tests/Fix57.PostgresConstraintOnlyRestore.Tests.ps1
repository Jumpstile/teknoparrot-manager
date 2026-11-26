# FIX57 (found by the real-data smoke test N18): the bundled backups of Power Putt 2013, Silver Strike Bowling, Target Toss Pro
# and Golden Tee 2019 restore every table and row, but pg_restore 8.3 exits 1 because five foreign-key CONSTRAINT entries cannot be
# created (numeric vs integer key columns). The product treated that as a failed restore and rolled the whole setup back.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent $PSScriptRoot
    $script:ProductPath = Join-Path $script:RepoRoot 'TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:ProductPath, [ref]$tokens, [ref]$parseErrors)
    # FIX125: the checked command uses the one pg_restore judgment, the known-warning parser and the plural helper.
    # FIX129: and the quoted-name reader, the field reader and the redaction helper (the judgment now runs in memory on the raw text).
    foreach ($name in @('Invoke-Postgres83RestoreCommandChecked', 'Get-PostgresRestoreJudgement', 'Get-PostgresKnownConstraintRestoreWarnings', 'ConvertFrom-PostgresQuotedIdentifier', 'ConvertTo-PostgresRedactedText', 'Get-TpmTransactionField', 'Format-TpmCountNoun')) {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    function Invoke-Postgres83RestoreCommand {
        param($ToolName, $Arguments, $SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
        $command = [pscustomobject]@{ ToolName = $ToolName; ExitCode = $script:FakeExit; Succeeded = ($script:FakeExit -eq 0); Output = $script:FakeOutput }
        return (Add-FakePostgresInterpretation -Command $command -Interpret $Interpret -InterpretContext $InterpretContext)
    }
    function New-RestoreOutput {
        param([string[]]$Types, [int]$Reported = -1)
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('pg_restore: [archiver (db)] Error while PROCESSING TOC:')
        $i = 110
        foreach ($t in $Types) {
            $lines.Add(('pg_restore: [archiver (db)] Error from TOC entry {0}; 0 6590844 {1} category1_attr_fk postgres' -f $i, $t))
            $lines.Add('pg_restore: [archiver (db)] could not execute query: ERROR:  foreign key constraint "category1_attr_fk" cannot be implemented')
            # FIX95: the real 8.3 error is followed by this DETAIL; the known case requires it.
            $lines.Add('DETAIL:  Key columns "attr" and "id" are of incompatible types: numeric and integer.')
            # FIX125: the known case also requires the failed statement, an ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY.
            $lines.Add('    Command was: ALTER TABLE ONLY category1')
            $lines.Add('    ADD CONSTRAINT category1_attr_fk FOREIGN KEY (attr) REFERENCES attr(id);')
            $i += 2
        }
        if ($Reported -lt 0) { $Reported = $Types.Count }
        $lines.Add(('WARNING: errors ignored on restore: {0}' -f $Reported))
        return ($lines -join "`r`n")
    }
    $script:Five = @('CONSTRAINT','CONSTRAINT','CONSTRAINT','CONSTRAINT','CONSTRAINT')
}

Describe 'FIX57 pg_restore exit 1 caused only by foreign-key constraint entries' {
    It 'accepts the real five-constraint pattern for the forward restore and records the warning' {
        # Mutation: remove the accept branch -> the owner library setup rolls back (the N18 failure).
        $script:FakeExit = 1; $script:FakeOutput = New-RestoreOutput -Types $script:Five
        $log = New-Object System.Collections.Generic.List[object]
        $r = Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'x', 'f') -CommandLog $log -DatabaseName 'GameDBPPL13' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true
        $r.Succeeded | Should -BeTrue
        # FIX95 (S1): the warning names a KNOWN limitation and the count, not "all data was restored" for any case.
        $r.AcceptedWarnings | Should -Match '^Finished with a known limitation: 5 links between tables '
        @($r.AcceptedConstraintNames).Count | Should -Be 5
        $log.Count | Should -Be 1
    }
    It 'still fails without the opt-in switch (rollback dump restores stay strict)' {
        # Mutation: accept without the switch -> a damaged rollback dump would be treated as restored.
        $script:FakeExit = 1; $script:FakeOutput = New-RestoreOutput -Types $script:Five
        $log = New-Object System.Collections.Generic.List[object]
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'x', 'f') -CommandLog $log -DatabaseName 'GameDBPPL13' } | Should -Throw '*failed with exit code 1*'
    }
    It 'fails when any ignored error is not a constraint (a missing table or data error is a real failure)' {
        # Mutation: accept any exit 1 -> a restore that lost table data would pass.
        $script:FakeExit = 1; $script:FakeOutput = New-RestoreOutput -Types @('CONSTRAINT', 'TABLE DATA', 'CONSTRAINT')
        $log = New-Object System.Collections.Generic.List[object]
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'x', 'f') -CommandLog $log -DatabaseName 'GameDBPPL13' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true } | Should -Throw '*failed with exit code 1*'
    }
    It 'fails when pg_restore reports more ignored errors than the constraint entries that were listed' {
        # Mutation: ignore the count -> unlisted errors would be hidden.
        $script:FakeExit = 1; $script:FakeOutput = New-RestoreOutput -Types $script:Five -Reported 7
        $log = New-Object System.Collections.Generic.List[object]
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'x', 'f') -CommandLog $log -DatabaseName 'GameDBPPL13' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true } | Should -Throw '*failed with exit code 1*'
    }
    It 'fails for any other exit code or tool, and for output with no constraint entries' {
        # Mutation: accept exit 2 or psql -> a connection failure or a killed restore would pass.
        $log = New-Object System.Collections.Generic.List[object]
        $script:FakeExit = 2; $script:FakeOutput = New-RestoreOutput -Types $script:Five
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('x') -CommandLog $log -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true } | Should -Throw '*exit code 2*'
        $script:FakeExit = 1
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'psql.exe' -Arguments @('x') -CommandLog $log -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true } | Should -Throw '*exit code 1*'
        $script:FakeOutput = 'pg_restore: [archiver] could not open input file'
        { Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('x') -CommandLog $log -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true } | Should -Throw '*exit code 1*'
    }
}
