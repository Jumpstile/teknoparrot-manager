#Requires -Module Pester

# FIX125: a game's bundled database backup restores every table and row, but pg_restore 8.3 ends with exit 1 because five
# foreign keys (numeric key column against an integer one) cannot be created. Setup rolled all new databases back for that.
# The product now judges a pg_restore result in ONE pure function, Get-PostgresRestoreJudgement:
#   accepted = no timeout AND (exit 0 OR (createdb succeeded AND exit 1 AND every error block is the numeric-vs-integer
#   ALTER TABLE ... ADD CONSTRAINT ... FOREIGN KEY error AND their number equals "errors ignored on restore: N")).
# The production script is parsed and only the named functions are dot-sourced; no top-level product code runs.
# pg_restore itself is never called: the tool runner is a stub that returns the text and exit code a test sets.
# What this CANNOT prove: the real pg_restore text of another PostgreSQL build, or a real restore.

BeforeAll {
    $script:F125ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F125ProductPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX125 tests could not parse the production script.' }
    $script:F125Ast = $ast
    # FIX129: the quoted-name reader and the redaction helper are part of the judgement path now.
    foreach ($name in @('Get-PostgresRestoreJudgement', 'Get-PostgresKnownConstraintRestoreWarnings', 'ConvertFrom-PostgresQuotedIdentifier', 'ConvertTo-PostgresRedactedText', 'Invoke-Postgres83RestoreCommandChecked', 'Format-TpmCountNoun', 'Write-TpmPostgresSetupDetails', 'Get-TpmPostgresSetupGames', 'Get-TpmPostgresSetupGameName', 'Get-TpmPostgresSetupGameDetail', 'Get-TpmTransactionField')) {
        $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
        if ($null -eq $fn) { throw ('FIX125 tests: function {0} not found in the production script.' -f $name) }
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')

    # The tool runner: returns what the test sets. TimedOut is true only when a test sets it. FIX129: like the real runner, it
    # runs the caller's -Interpret block on the raw text (Add-FakePostgresInterpretation) and a timed-out command never Succeeded.
    function Invoke-Postgres83RestoreCommand {
        param($ToolName, $Arguments, $SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
        $timedOut = [bool]$script:F125TimedOut
        $result = [pscustomobject]@{ Tool = $ToolName; Arguments = @($Arguments); ExitCode = $script:F125Exit; Succeeded = ($script:F125Exit -eq 0 -and -not $timedOut); TimedOut = $timedOut; Output = $script:F125Output }
        return (Add-FakePostgresInterpretation -Command $result -Interpret $Interpret -InterpretContext $InterpretContext -TimedOut $timedOut)
    }

    # One error block exactly as the 8.3 pg_restore prints it for these backups.
    function New-F125Block {
        param([int]$Id, [string]$Name, [string]$Table = 'category1_attr', [string]$Parent = 'category1_object', [string]$ErrorText = '', [string]$Detail = 'Key columns "object_id" and "object_id" are of incompatible types: numeric and integer.', [string]$Command = '')
        if (-not $ErrorText) { $ErrorText = ('foreign key constraint "{0}" cannot be implemented' -f $Name) }
        if (-not $Command) { $Command = ('ALTER TABLE ONLY {0} ADD CONSTRAINT {1} FOREIGN KEY (object_id) REFERENCES {2}(object_id);' -f $Table, $Name, $Parent) }
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add(('pg_restore: [archiver (db)] Error from TOC entry {0}; 0 3172634 CONSTRAINT {1} postgres' -f $Id, $Name))
        $lines.Add(('pg_restore: [archiver (db)] could not execute query: ERROR:  {0}' -f $ErrorText))
        if ($Detail) { $lines.Add(('DETAIL:  {0}' -f $Detail)) }
        $lines.Add(('    Command was: {0}' -f $Command))
        return ($lines -join "`r`n")
    }
    # The five blocks of the real run (final candidate #4) and the closing warning.
    function Get-F125FiveBlocks {
        return @(
            (New-F125Block -Id 110 -Name 'category1_attr_fk' -Table 'category1_attr' -Parent 'category1_object'),
            (New-F125Block -Id 112 -Name 'category2_attr_fk' -Table 'category2_attr' -Parent 'category2_object'),
            (New-F125Block -Id 114 -Name 'category3_attr_fk' -Table 'category3_attr' -Parent 'category3_object'),
            (New-F125Block -Id 116 -Name 'category4_fk' -Table 'category4' -Parent 'category4_object'),
            (New-F125Block -Id 118 -Name 'category5_fk' -Table 'category5' -Parent 'category5_object')
        )
    }
    function New-F125Output {
        param([string[]]$Blocks, [int]$Reported = -1)
        if ($Reported -lt 0) { $Reported = @($Blocks).Count }
        return ((@('pg_restore: [archiver (db)] Error while PROCESSING TOC:') + @($Blocks) + @(('WARNING: errors ignored on restore: {0}' -f $Reported))) -join "`r`n")
    }
    function Invoke-F125Checked {
        param([int]$ExitCode, [string]$Output, [switch]$TimedOut, [switch]$Strict)
        $script:F125Exit = $ExitCode; $script:F125Output = $Output; $script:F125TimedOut = [bool]$TimedOut
        $log = New-Object System.Collections.Generic.List[object]
        $script:F125Log = $log
        if ($Strict) { return (Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDBAnyName', 'game.backup') -CommandLog $log -DatabaseName 'GameDBAnyName') }
        return (Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', 'GameDBAnyName', 'game.backup') -CommandLog $log -DatabaseName 'GameDBAnyName' -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true)
    }
}

Describe 'FIX125 Get-PostgresRestoreJudgement accepts only a clean restore or the known warnings' {
    It 'accepts exit 0 with no warnings' {
        # Mutation: reject exit 0 when the text is empty -> every clean restore fails.
        $j = Get-PostgresRestoreJudgement -ExitCode 0 -Output '' -CreatedbSucceeded $true
        $j.Accepted | Should -BeTrue
        $j.KnownWarningCount | Should -Be 0
        $j.Reason | Should -BeExactly 'ExitZero'
    }

    It 'accepts the exact five foreign-key errors of the real run and counts them' {
        # Mutation: drop the exit-1 accept branch -> the N-run rollback (all new databases removed) comes back.
        $j = Get-PostgresRestoreJudgement -ExitCode 1 -Output (New-F125Output -Blocks (Get-F125FiveBlocks)) -CreatedbSucceeded $true
        $j.Accepted | Should -BeTrue
        $j.KnownWarningCount | Should -Be 5
        ($j.ConstraintNames -join ',') | Should -BeExactly 'category1_attr_fk,category2_attr_fk,category3_attr_fk,category4_fk,category5_fk'
        $j.Reason | Should -BeExactly 'KnownWarningsOnly'
    }

    It 'accepts the five errors of the real Golden Tee backup, where pg_restore 8.3 wraps and shortens the Command text with "..."' {
        # N18A. Mutation: require ";" at the end of the Command text again -> the game gets no database (smoke N18, Golden Tee Live 2019).
        $cut = { param($n) New-F125Block -Id (108 + 2 * $n) -Name "category${n}_attr_fk" -Command ("ALTER TABLE ONLY category${n}_attr`r`n    ADD CONSTRAINT category${n}_attr_fk FOREIGN KEY (object_id) REFERENCES category${n}_object(obj...") }
        $blocks = @(1..5 | ForEach-Object { & $cut $_ })
        $j = Get-PostgresRestoreJudgement -ExitCode 1 -Output (New-F125Output -Blocks $blocks) -CreatedbSucceeded $true
        $j.Accepted | Should -BeTrue
        $j.KnownWarningCount | Should -Be 5
        # A shortened command that is not a foreign key, or text after the "...", is still a failure.
        $check = New-F125Block -Id 110 -Name 'category1_attr_fk' -Command "ALTER TABLE ONLY category1_attr`r`n    ADD CONSTRAINT category1_attr_fk CHECK (object_id > 0..."
        (Get-PostgresRestoreJudgement -ExitCode 1 -Output (New-F125Output -Blocks @($check)) -CreatedbSucceeded $true).Accepted | Should -BeFalse
        $after = (New-F125Output -Blocks @(& $cut 1)) -replace 'WARNING:', "DROP TABLE category1_attr;`r`nWARNING:"
        (Get-PostgresRestoreJudgement -ExitCode 1 -Output $after -CreatedbSucceeded $true).Accepted | Should -BeFalse
    }

    It 'rejects exit 1 with an extra error that is not a foreign key (<Case>)' -TestCases @(
        @{ Case = 'missing table after the five'; Extra = 'pg_restore: [archiver (db)] could not execute query: ERROR:  relation "category9" does not exist'; Reported = 5 }
        @{ Case = 'missing table and the count says six'; Extra = 'pg_restore: [archiver (db)] could not execute query: ERROR:  relation "category9" does not exist'; Reported = 6 }
    ) {
        param($Case, $Extra, $Reported)
        # Mutation: ignore lines outside the known blocks -> a restore that lost data would pass.
        $text = (New-F125Output -Blocks (Get-F125FiveBlocks) -Reported $Reported) + "`r`n" + $Extra
        (Get-PostgresRestoreJudgement -ExitCode 1 -Output $text -CreatedbSucceeded $true).Accepted | Should -BeFalse
        $inside = (New-F125Output -Blocks ((Get-F125FiveBlocks) + @($Extra)) -Reported $Reported)
        (Get-PostgresRestoreJudgement -ExitCode 1 -Output $inside -CreatedbSucceeded $true).Accepted | Should -BeFalse
    }

    It 'rejects a sixth error block or a count that does not match (<Case>)' -TestCases @(
        @{ Case = 'six blocks, warning says five'; Sixth = $true; Reported = 5 }
        @{ Case = 'six blocks, warning says six, sixth is another error class'; Sixth = $true; Reported = 6; Other = $true }
        @{ Case = 'five blocks, warning says six'; Sixth = $false; Reported = 6 }
        @{ Case = 'five blocks, warning says four'; Sixth = $false; Reported = 4 }
        @{ Case = 'five blocks, no warning line'; Sixth = $false; Reported = 0; NoWarning = $true }
    ) {
        param($Case, $Sixth, $Reported, $Other, $NoWarning)
        # Mutation: ignore the "errors ignored on restore" number -> unlisted or extra errors are hidden.
        $blocks = @(Get-F125FiveBlocks)
        if ($Sixth -and $Other) { $blocks += (New-F125Block -Id 120 -Name 'category6_pkey' -ErrorText 'multiple primary keys for table "category6" are not allowed' -Detail '' -Command 'ALTER TABLE ONLY category6 ADD CONSTRAINT category6_pkey PRIMARY KEY (id);') }
        elseif ($Sixth) { $blocks += (New-F125Block -Id 120 -Name 'category6_attr_fk' -Table 'category6_attr' -Parent 'category6_object') }
        $text = New-F125Output -Blocks $blocks -Reported $Reported
        if ($NoWarning) { $text = ($text -split "`r`n" | Where-Object { $_ -notmatch '^WARNING:' }) -join "`r`n" }
        (Get-PostgresRestoreJudgement -ExitCode 1 -Output $text -CreatedbSucceeded $true).Accepted | Should -BeFalse
    }

    It 'rejects a different error class even when the count matches (<Case>)' -TestCases @(
        @{ Case = 'primary key'; Block = @{ Id = 110; Name = 'category1_pkey'; ErrorText = 'multiple primary keys for table "category1" are not allowed'; Detail = ''; Command = 'ALTER TABLE ONLY category1 ADD CONSTRAINT category1_pkey PRIMARY KEY (id);' } }
        @{ Case = 'unique index'; Block = @{ Id = 110; Name = 'category1_name_key'; ErrorText = 'could not create unique index "category1_name_key"'; Detail = 'Table contains duplicated values.'; Command = 'ALTER TABLE ONLY category1 ADD CONSTRAINT category1_name_key UNIQUE (name);' } }
        @{ Case = 'foreign key, rows missing'; Block = @{ Id = 110; Name = 'category1_attr_fk'; ErrorText = 'insert or update on table "category1_attr" violates foreign key constraint "category1_attr_fk"'; Detail = 'Key (object_id)=(7) is not present in table "category1_object".' } }
        @{ Case = 'foreign key, text against integer'; Block = @{ Id = 110; Name = 'category1_attr_fk'; Detail = 'Key columns "object_id" and "object_id" are of incompatible types: text and integer.' } }
        @{ Case = 'foreign key, no DETAIL line'; Block = @{ Id = 110; Name = 'category1_attr_fk'; Detail = '' } }
        @{ Case = 'right error text, but the statement is not a foreign key'; Block = @{ Id = 110; Name = 'category1_attr_fk'; Command = 'CREATE INDEX category1_attr_idx ON category1_attr (object_id);' } }
        @{ Case = 'statement adds a different constraint name'; Block = @{ Id = 110; Name = 'category1_attr_fk'; Command = 'ALTER TABLE ONLY category1_attr ADD CONSTRAINT other_fk FOREIGN KEY (object_id) REFERENCES category1_object(object_id);' } }
        @{ Case = 'no Command was: text at all'; Block = $null }
    ) {
        param($Case, $Block)
        # Mutation: accept any "CONSTRAINT" entry, or accept the error without its DETAIL or its ALTER TABLE statement.
        $text = if ($null -eq $Block) {
            New-F125Output -Blocks @((New-F125Block -Id 110 -Name 'category1_attr_fk').Split("`n")[0..2] -join "`n")
        } else {
            New-F125Output -Blocks @(New-F125Block @Block)
        }
        (Get-PostgresRestoreJudgement -ExitCode 1 -Output $text -CreatedbSucceeded $true).Accepted | Should -BeFalse
    }

    It 'rejects exit 1 with empty or whitespace-only text' {
        # Mutation: treat exit 1 with no captured text as finished (fail open on lost output).
        foreach ($empty in @('', '   ', "`r`n", $null)) {
            (Get-PostgresRestoreJudgement -ExitCode 1 -Output $empty -CreatedbSucceeded $true).Accepted | Should -BeFalse
        }
    }

    It 'rejects every exit code other than 0 and 1, even with the known text' {
        # Mutation: accept the known text for any non-zero code -> a connection failure or a killed restore would pass.
        foreach ($code in @(2, 3, 5, 9, 127, -1, 255)) {
            $j = Get-PostgresRestoreJudgement -ExitCode $code -Output (New-F125Output -Blocks (Get-F125FiveBlocks)) -CreatedbSucceeded $true
            $j.Accepted | Should -BeFalse -Because ('exit ' + $code)
            $j.Reason | Should -BeExactly 'ExitCodeNotOne'
        }
    }

    It 'rejects a timeout whatever the exit code and text are' {
        # Mutation: ignore TimedOut -> a restore killed after the time limit could look finished.
        (Get-PostgresRestoreJudgement -ExitCode 1 -Output (New-F125Output -Blocks (Get-F125FiveBlocks)) -CreatedbSucceeded $true -TimedOut $true).Accepted | Should -BeFalse
        (Get-PostgresRestoreJudgement -ExitCode 0 -Output '' -CreatedbSucceeded $true -TimedOut $true).Accepted | Should -BeFalse
    }

    It 'rejects the known warnings when createdb did not succeed' {
        # Mutation: drop the createdb condition -> warnings of a restore into a database TPM did not create count as finished.
        $j = Get-PostgresRestoreJudgement -ExitCode 1 -Output (New-F125Output -Blocks (Get-F125FiveBlocks)) -CreatedbSucceeded $false
        $j.Accepted | Should -BeFalse
        $j.Reason | Should -BeExactly 'DatabaseNotCreated'
    }

    It 'accepts the known warnings for any database name (there is no name list)' {
        # Mutation: bring back a list of database names in the judgement path -> a bundled backup under another name rolls everything back.
        # FIX129: the old version of this test could not fail, because the Checked function never passed the name on. Now names that
        # are in no list go through the Checked function, and the three functions of the judgement path are checked for a name list and
        # for a name input (Fix129.PostgresToolResults.Tests.ps1 repeats the first part with the real runner).
        foreach ($database in @('GameDBPPL12', 'GameDB06', 'x', ('Db' + [guid]::NewGuid().ToString('N')), 'gamedbppl13', 'ZZZ_unlisted_999')) {
            $script:F125Exit = 1; $script:F125Output = New-F125Output -Blocks (Get-F125FiveBlocks); $script:F125TimedOut = $false
            $log = New-Object System.Collections.Generic.List[object]
            $r = Invoke-Postgres83RestoreCommandChecked -ToolName 'pg_restore.exe' -Arguments @('-d', $database, 'game.backup') -CommandLog $log -DatabaseName $database -AcceptConstraintOnlyRestoreWarnings -CreatedbSucceeded $true
            $r.Succeeded | Should -BeTrue -Because $database
        }
        foreach ($name in 'Get-PostgresRestoreJudgement', 'Get-PostgresKnownConstraintRestoreWarnings', 'Invoke-Postgres83RestoreCommandChecked') {
            $fn = $script:F125Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
            $fn.Extent.Text | Should -Not -Match '(?i)GameDB' -Because ($name + ' must not name a database')
        }
        $judgement = $script:F125Ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-PostgresRestoreJudgement' }, $true)
        $judgementParameters = @($judgement.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        $judgementParameters | Should -Not -Contain 'DbName'
        $judgementParameters | Should -Not -Contain 'DatabaseName'
    }
}

Describe 'FIX125 Invoke-Postgres83RestoreCommandChecked uses the judgement' {
    It 'finishes with the known warnings, keeps the count and the names, and logs the command' {
        # Mutation: set Succeeded without recording AcceptedWarningCount -> the Details line cannot say how many warnings there were.
        $r = Invoke-F125Checked -ExitCode 1 -Output (New-F125Output -Blocks (Get-F125FiveBlocks))
        $r.Succeeded | Should -BeTrue
        $r.AcceptedWarningCount | Should -Be 5
        @($r.AcceptedConstraintNames).Count | Should -Be 5
        $r.AcceptedWarnings | Should -Match '^Finished with a known limitation: 5 links between tables '
        $script:F125Log.Count | Should -Be 1
    }

    It 'fails with the whole text when the output is not only the known warnings' {
        # Mutation: accept any exit 1 for the opted-in restore.
        $text = (New-F125Output -Blocks (Get-F125FiveBlocks)) + "`r`npg_restore: [archiver (db)] could not execute query: ERROR:  relation `"x`" does not exist"
        { Invoke-F125Checked -ExitCode 1 -Output $text } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
        $script:F125Log.Count | Should -Be 1
        $script:F125Log[0].Succeeded | Should -BeFalse
    }

    It 'stays strict for a restore that did not opt in (the user''s own backups, the rollback dump)' {
        # Mutation: accept the known warnings by default.
        { Invoke-F125Checked -ExitCode 1 -Output (New-F125Output -Blocks (Get-F125FiveBlocks)) -Strict } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
    }

    It 'fails for exit 2 and for a timeout flagged by the tool runner' {
        # Mutation: ignore the exit code or TimedOut in the checked command.
        { Invoke-F125Checked -ExitCode 2 -Output (New-F125Output -Blocks (Get-F125FiveBlocks)) } | Should -Throw -ExpectedMessage '*failed with exit code 2*'
        { Invoke-F125Checked -ExitCode 1 -Output (New-F125Output -Blocks (Get-F125FiveBlocks)) -TimedOut } | Should -Throw -ExpectedMessage '*failed with exit code 1*'
    }

    It 'fails for exit 1 with no text and says there was no diagnostic text' {
        { Invoke-F125Checked -ExitCode 1 -Output '' } | Should -Throw -ExpectedMessage '*failed with exit code 1: no diagnostic text*'
    }

    It 'leaves exit 0 a plain success without a warning record' {
        $r = Invoke-F125Checked -ExitCode 0 -Output ''
        $r.Succeeded | Should -BeTrue
        $r.PSObject.Properties['AcceptedWarningCount'] | Should -BeNullOrEmpty
    }
}

Describe 'FIX125 the Details view says it in plain words (this checks the Details view only; the main screen is not rendered here)' {
    BeforeAll {
        function Write-TpmText { param($Text, $Color, $Indent, $MaxWidth) }
        function Show-TpmDetailBlocks { param($Blocks, $Note, $HeadingColor) $script:F125Blocks = @($Blocks) }
        function Write-Host { param($Object, $ForegroundColor) }
    }

    It 'adds one plain line with the count for a database restored with known warnings, and none otherwise' {
        # Mutation: leave KnownWarningCount out of the Details block -> the owner cannot see that the backup ended with warnings.
        $games = @(
            [pscustomobject]@{ Key = 'GameA'; Name = 'Game A'; DbName = 'GameDBA'; Outcome = 'CreatedFromBackup'; AutoCreateUnknown = $false; KnownWarningCount = 5; KnownConstraintNames = @('category1_attr_fk', 'category2_attr_fk') },
            [pscustomobject]@{ Key = 'GameB'; Name = 'Game B'; DbName = 'GameDBB'; Outcome = 'CreatedFromBackup'; AutoCreateUnknown = $false; KnownWarningCount = 1 },
            [pscustomobject]@{ Key = 'GameC'; Name = 'Game C'; DbName = 'GameDBC'; Outcome = 'CreatedFromBackup'; AutoCreateUnknown = $false; KnownWarningCount = 0 }
        )
        $result = [pscustomobject]@{ Summary = ''; GameOutcomes = $games; Warnings = @(); FinalVerification = [pscustomobject]@{ Checks = @() }; RecoveryActions = @(); Configured = 3; DbCreated = 3; AlreadyConfigured = 0; Errors = 0 }
        Write-TpmPostgresSetupDetails -Result $result
        $byName = @{}
        foreach ($block in $script:F125Blocks) { $byName[[string]$block.Heading] = @($block.Lines) }
        $byName['Game A'] | Should -Contain 'Backup: The game''s backup finished with 5 warnings.'
        $byName['Game A'] | Should -Contain 'Links between tables that could not be made: category1_attr_fk, category2_attr_fk.'
        $byName['Game B'] | Should -Contain 'Backup: The game''s backup finished with 1 warning.'
        @($byName['Game C'] | Where-Object { $_ -like 'Backup:*' }).Count | Should -Be 0
        (($byName['Game A'] -join ' ') -match '(?i)constraint|foreign|pg_restore|numeric') | Should -BeFalse
    }
}
