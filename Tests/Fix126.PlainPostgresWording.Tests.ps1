#Requires -Module Pester

# FIX126: two PostgreSQL screens still showed technical text on the main screen.
#   1. The rebuild ("reinitialize") success screen said "with a known limitation:" plus the note "5 links between tables ...".
#   2. The progress step "PostgreSQL leftover check" was shown raw ("PostgreSQL leftover check done").
# The same rule covers the screen of a PostgreSQL setup that did not finish: its reasons can hold raw tool text (error blocks,
# exit codes, names). On the main screen all of that is gone. It is shown only under Details (key D) and it is always in the log.
# The production script is parsed and only the named functions are dot-sourced; no top-level product code runs, no PostgreSQL
# is started and no real data is read. The screens are recorded through stand-ins for Write-Host, Write-TpmText and
# Show-TpmDetailBlocks. TPM_REAL_DATA_TESTS is not touched.
# What this CANNOT prove: how the real console lays the Details blocks out (Show-TpmDetailBlocks is a stand-in here; its layout
# has its own tests) or a real rebuild.

BeforeAll {
    $script:F126ProductPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F126ProductPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX126 tests could not parse the production script.' }
    $script:F126FunctionText = @{}
    foreach ($name in @('Write-PostgresReinitializeSuccess', 'Write-PostgresReinitializeDetails', 'Write-PostgresKeptDatabaseBackupNotice', 'Get-TpmTransactionField', 'Add-TpmDetailLine', 'Write-TpmPostgresSetupFailure', 'Get-PostgresSetupFailureReasonLines', 'Get-PostgresNotReadyNextStep', 'Test-TpmTransactionUserSafeSummary', 'Get-TpmFriendlyProgressLabel', 'Write-TpmCompactExtractionProgress')) {
        $found = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name }, $true))
        if ($found.Count -ne 1) { throw ('FIX126 tests expected one {0}, found {1}.' -f $name, $found.Count) }
        $script:F126FunctionText[$name] = $found[0].Extent.Text
        if ($name -ne 'Write-TpmCompactExtractionProgress') { . ([scriptblock]::Create($found[0].Extent.Text)) }
    }

    # Stand-ins. Write-Host is mocked per test; these record the Details view and the log.
    function Write-Log { param([string]$msg) [void]$script:F126Log.Add([string]$msg) }
    function Read-HostSafe { param([string]$Prompt) $script:F126Prompts.Add([string]$Prompt) | Out-Null; return [string]$script:F126Answer }
    function Write-TpmText { param($Text, $Color, $Indent, $MaxWidth, $HangingIndent, [switch]$BreakLongWords, [switch]$BlankBefore) [void]$script:F126Details.Add([string]$Text) }
    function Show-TpmDetailBlocks {
        param($Blocks, $Note, $HeadingColor)
        foreach ($block in @($Blocks)) {
            [void]$script:F126Blocks.Add($block)
            [void]$script:F126Details.Add([string]$block.Heading)
            foreach ($line in @($block.Lines)) { [void]$script:F126Details.Add([string]$line) }
        }
    }

    $script:F126Forbidden = @('known limitation', 'foreign key', 'pg_restore', 'constraint', 'exit', 'numeric')

    $script:F126Message = 'Finished with a known limitation: 5 links between tables in the game''s own backup could not be made. This is a known problem with that backup. The tables and their rows were restored.'
    function New-F126RebuildResult {
        param([switch]$Clean, [string]$KeptCopy = '')
        if ($Clean) { return [pscustomobject]@{ Summary = 'PostgreSQL reinitialize completed and was verified for the selected games.'; Warnings = @(); TechnicalDetails = [pscustomobject]@{ AcceptedRestoreLimitations = @(); KeptDatabaseBackups = @() } } }
        $limitation = [pscustomobject]@{ Database = 'GameDB19'; Message = $script:F126Message; ConstraintNames = @('category1_attr_fk', 'category2_attr_fk') }
        $kept = if ($KeptCopy) { @($KeptCopy) } else { @() }
        return [pscustomobject]@{
            Summary = 'PostgreSQL reinitialize completed and was verified for the selected games.'
            Warnings = @('GameDB19: ' + $script:F126Message)
            TechnicalDetails = [pscustomobject]@{ AcceptedRestoreLimitations = @($limitation); KeptDatabaseBackups = $kept }
        }
    }
    function New-F126FailedSetupResult {
        $reason = 'Database GameDB19 could not be created: pg_restore: [archiver (db)] Error from TOC entry 110; 0 3172634 CONSTRAINT category1_attr_fk postgres' + "`r`n" + 'ERROR:  foreign key constraint "category1_attr_fk" cannot be implemented' + "`r`n" + 'DETAIL:  Key columns are of incompatible types: numeric and integer. pg_restore ended with exit code 2.'
        return [pscustomobject]@{
            Outcome = 'ROLLED_BACK_VERIFIED'
            ReasonCode = 'POSTGRES_DATABASE_ROLLBACK_VERIFIED'
            Summary = 'Setup stopped. Everything was put back the way it was, and checked.'
            TechnicalDetails = [pscustomobject]@{ Stage = 'DatabaseCreation'; FailureReasons = @($reason) }
            RecoveryActions = @(@{ Id = 'Review'; Label = 'Open Details and review the preserved PostgreSQL setup evidence.' })
        }
    }
}

Describe 'FIX126 rebuild success screen' {
    BeforeEach {
        $script:F126Screen = New-Object System.Collections.Generic.List[string]
        $script:F126Log = New-Object System.Collections.Generic.List[string]
        $script:F126Details = New-Object System.Collections.Generic.List[string]
        $script:F126Blocks = New-Object System.Collections.Generic.List[object]
        $script:F126Prompts = New-Object System.Collections.Generic.List[string]
        $script:F126Answer = ''
        Mock Write-Host { [void]$script:F126Screen.Add([string]($Object -join ' ')) }
    }

    It 'says the result in plain words and shows none of the technical words (<Word>) on the main screen' -TestCases @(
        @{ Word = 'known limitation' }, @{ Word = 'foreign key' }, @{ Word = 'pg_restore' }, @{ Word = 'constraint' }, @{ Word = 'exit' }, @{ Word = 'numeric' }
    ) {
        param($Word)
        # Mutation: print the note again (or the old "with a known limitation:" heading) on the main screen.
        Write-PostgresReinitializeSuccess -Result (New-F126RebuildResult)
        $screen = @($script:F126Screen) -join "`n"
        $screen | Should -Match 'PostgreSQL data was rebuilt and checked for the selected games\.'
        $screen | Should -Match 'A few harmless warnings from the game''s own backup were skipped\.'
        $screen | Should -Not -Match ('(?i)' + [regex]::Escape($Word))
        $screen | Should -Not -Match '(?i)links between tables|category1_attr_fk|GameDB19'
    }

    It 'keeps the main screen short, and says where to find more when it cannot offer Details' {
        # Mutation: spread the warning over many lines on the main screen.
        Write-PostgresReinitializeSuccess -Result (New-F126RebuildResult)
        @($script:F126Screen).Count | Should -BeLessOrEqual 4
        @($script:F126Screen) | Should -Contain '  The log has more.'
        @($script:F126Prompts).Count | Should -Be 0
    }

    It 'still has the technical text in the log: the note, the database and the constraint names' {
        # Mutation: drop the Write-Log lines when the screen text moves away -> the technical note is lost.
        Write-PostgresReinitializeSuccess -Result (New-F126RebuildResult)
        $log = @($script:F126Log) -join "`n"
        $log | Should -Match 'known limitation'
        $log | Should -Match '5 links between tables'
        $log | Should -Match 'database GameDB19 \(constraints: category1_attr_fk, category2_attr_fk\)'
    }

    It 'offers Details and shows the technical text there only when D is pressed' {
        # Mutation: show the Details view without being asked, or never show it.
        $script:F126Answer = ''
        Write-PostgresReinitializeSuccess -Result (New-F126RebuildResult) -OfferDetails
        @($script:F126Prompts) | Should -Be @('  Press D to see more, or Enter to continue')
        @($script:F126Details).Count | Should -Be 0
        @($script:F126Screen) | Should -Not -Contain '  The log has more.'

        $script:F126Prompts.Clear()
        $script:F126Answer = 'd'
        Write-PostgresReinitializeSuccess -Result (New-F126RebuildResult) -OfferDetails
        $details = @($script:F126Details) -join "`n"
        $details | Should -Match 'known limitation'
        $details | Should -Match '5 links between tables'
        $details | Should -Match 'category1_attr_fk, category2_attr_fk'
        $details | Should -Match 'GameDB19'
        # The main screen is the same either way.
        (@($script:F126Screen) -join "`n") | Should -Not -Match '(?i)known limitation|links between tables'
    }

    It 'shows the Details as short labeled blocks, one per database' {
        # Mutation: put every note in one long line.
        Write-PostgresReinitializeDetails -Result (New-F126RebuildResult)
        $byHeading = @{}
        foreach ($block in $script:F126Blocks) { $byHeading[[string]$block.Heading] = @($block.Lines) }
        $byHeading.ContainsKey('Summary') | Should -BeTrue
        $byHeading.ContainsKey('GameDB19') | Should -BeTrue
        @($byHeading['GameDB19'] | Where-Object { $_ -like 'What was skipped: Finished with a known limitation: 5 links between tables*' }).Count | Should -Be 1
        @($byHeading['GameDB19']) | Should -Contain 'Names: category1_attr_fk, category2_attr_fk'
    }

    It 'falls back to the result notes in Details when there is no limitation record' {
        # Mutation: show an empty Details view when only the Warnings text exists.
        $result = [pscustomobject]@{ Summary = ''; Warnings = @('GameDB19: ' + $script:F126Message); TechnicalDetails = $null }
        Write-PostgresReinitializeDetails -Result $result
        (@($script:F126Details) -join "`n") | Should -Match 'GameDB19: Finished with a known limitation'
    }

    It 'keeps the plain success line, with no prompt, when nothing was skipped' {
        # Mutation: always print the warning line or ask for D, so a clean rebuild looks limited.
        Write-PostgresReinitializeSuccess -Result (New-F126RebuildResult -Clean) -OfferDetails
        @($script:F126Screen) | Should -Be @('  PostgreSQL data was rebuilt and checked for the selected games.')
        @($script:F126Prompts).Count | Should -Be 0
        @($script:F126Log).Count | Should -Be 0
    }

    It 'still says where the saved copy is, and keeps that path off the technical words' {
        # Mutation: drop the kept-copy notice from the rebuild screen.
        $copy = Join-Path (Join-Path $TestDrive 'Restore-z\CurrentDatabases') 'GameDB19.current.backup'
        Write-PostgresReinitializeSuccess -Result (New-F126RebuildResult -KeptCopy $copy)
        $screen = @($script:F126Screen) -join "`n"
        $screen | Should -Match 'has kept that saved copy'
        $screen | Should -Match ([regex]::Escape((Split-Path -Parent $copy)))
        $screen | Should -Not -Match '(?i)known limitation|foreign key|pg_restore|constraint|numeric'
    }
}

Describe 'FIX126 the progress step "PostgreSQL leftover check" is shown in plain words' {
    BeforeAll {
        function Import-TpmProgressModule {}
        function Test-TpmProgressActive { return [bool]$script:F126ProgressActive }
        function Test-TpmProgressGroupOwned { return $true }
        function Get-TpmProgressTitle { return '' }
        function Register-TpmProgressOutcome { param($State) }
        function Start-TpmProgressOperation { param($Title, $Stage, $Total, $Width, [switch]$Group, $Unit = 'Items') $script:F126ProgressActive = $true }
        function Complete-TpmProgressOperation { param($State = 'Final', $Message = '', [switch]$Superseded) $script:F126ProgressActive = $false }
        function Set-TpmProgressStage {
            param([string]$Stage, [long]$Current, [long]$Total, [switch]$StageOnly, $Unit = 'Items', [switch]$SameStage, [switch]$LongStep)
            [void]$script:F126Stages.Add([string]$Stage)
        }
        . ([scriptblock]::Create($script:F126FunctionText['Write-TpmCompactExtractionProgress']))
    }
    BeforeEach {
        $script:F126Log = New-Object System.Collections.Generic.List[string]
        $script:F126Stages = New-Object System.Collections.Generic.List[string]
        $script:F126ProgressActive = $true
        $script:TpmLastLoggedProgressLabel = $null
    }

    It 'maps the raw step name to a plain label that has none of the technical words' {
        # Mutation: remove the label from the plain-label table -> the raw developer name reaches the screen.
        $plain = Get-TpmFriendlyProgressLabel -Label 'PostgreSQL leftover check'
        $plain | Should -BeExactly 'Checking for an earlier PostgreSQL'
        foreach ($word in $script:F126Forbidden) { $plain | Should -Not -Match ('(?i)' + [regex]::Escape($word)) }
        $plain | Should -Not -Match '(?i)leftover'
    }

    It 'maps the PostgreSQL group titles to plain words, and leaves plain titles alone' -TestCases @(
        @{ Title = 'PostgreSQL reinitialize'; Plain = 'Rebuilding PostgreSQL data' },
        @{ Title = 'PostgreSQL elevated setup'; Plain = 'Setting up PostgreSQL as administrator' },
        @{ Title = 'PostgreSQL backup retry'; Plain = 'Backing up PostgreSQL again' },
        # FIX127: the owner asked for a plain label for the install title as well (FIX126 had left it unchanged).
        @{ Title = 'PostgreSQL install'; Plain = 'Installing PostgreSQL' },
        @{ Title = 'PostgreSQL game setup'; Plain = 'PostgreSQL game setup' }
    ) {
        param($Title, $Plain)
        # Mutation: leave the developer-style group title out of the table.
        Get-TpmFriendlyProgressLabel -Label $Title | Should -BeExactly $Plain
    }

    It 'shows "Checking for an earlier PostgreSQL" while it runs and "... done" when it ends, and logs the raw name once' {
        # Mutation: pass the raw label on to the progress rows, or stop writing the raw name to the log.
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'PostgreSQL leftover check' -Current 0 -Total 0
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'PostgreSQL leftover check' -Current 3 -Total 0
        Write-TpmCompactExtractionProgress -Phase Checking -Label 'PostgreSQL leftover check' -Current 4 -Total 0 -Complete
        @($script:F126Stages) | Should -Be @('Checking for an earlier PostgreSQL', 'Checking for an earlier PostgreSQL', 'Checking for an earlier PostgreSQL done')
        (@($script:F126Stages) -join "`n") | Should -Not -Match '(?i)leftover'
        @($script:F126Log) | Should -Be @('Progress step: PostgreSQL leftover check (shown as "Checking for an earlier PostgreSQL")')
    }
}

Describe 'FIX126 the screen of a PostgreSQL setup that did not finish' {
    BeforeEach {
        $script:F126Screen = New-Object System.Collections.Generic.List[string]
        $script:F126Log = New-Object System.Collections.Generic.List[string]
        $script:F126Details = New-Object System.Collections.Generic.List[string]
        $script:F126Blocks = New-Object System.Collections.Generic.List[object]
        $script:F126Prompts = New-Object System.Collections.Generic.List[string]
        $script:F126Answer = ''
        Mock Write-Host { [void]$script:F126Screen.Add([string]($Object -join ' ')) }
    }

    It 'keeps raw tool text off the main screen (<Word>)' -TestCases @(
        @{ Word = 'known limitation' }, @{ Word = 'foreign key' }, @{ Word = 'pg_restore' }, @{ Word = 'constraint' }, @{ Word = 'exit' }, @{ Word = 'numeric' }
    ) {
        param($Word)
        # Mutation: print the failure reason lines on the main screen again.
        Write-TpmPostgresSetupFailure -Result (New-F126FailedSetupResult) -OfferDetails
        $screen = @($script:F126Screen) -join "`n"
        # FIX128: the Summary that this line prints is now plain ("Setup stopped. Everything was put back the way it was, and checked.");
        # it used to say "PostgreSQL setup stopped and the previous verified state was restored."
        $screen | Should -Match 'PostgreSQL setup did not complete successfully: Setup stopped\. Everything was put back the way it was, and checked\.'
        $screen | Should -Not -Match '(?i)verified state'
        $screen | Should -Not -Match ('(?i)' + [regex]::Escape($Word))
        $screen | Should -Not -Match 'Error from TOC|GameDB19'
    }

    It 'has every reason, line by line, in the log' {
        # Mutation: drop the Write-Log call -> the reason that left the screen is lost.
        Write-TpmPostgresSetupFailure -Result (New-F126FailedSetupResult) -OfferDetails
        $log = @($script:F126Log) -join "`n"
        $log | Should -Match 'Postgres setup failure reason: Database GameDB19 could not be created: pg_restore:'
        $log | Should -Match 'foreign key constraint "category1_attr_fk" cannot be implemented'
        $log | Should -Match 'exit code 2'
    }

    It 'shows the reason under Details only when D is pressed' {
        # Mutation: show Details without D, or never.
        $script:F126Answer = ''
        Write-TpmPostgresSetupFailure -Result (New-F126FailedSetupResult) -OfferDetails
        @($script:F126Prompts) | Should -Be @('  Press D to see why, or Enter to continue')
        @($script:F126Details).Count | Should -Be 0

        $script:F126Answer = 'D'
        Write-TpmPostgresSetupFailure -Result (New-F126FailedSetupResult) -OfferDetails
        $details = @($script:F126Details) -join "`n"
        $details | Should -Match 'Database GameDB19 could not be created: pg_restore:'
        $details | Should -Match 'foreign key constraint "category1_attr_fk" cannot be implemented'
        $details | Should -Match 'exit code 2'
        $byHeading = @{}
        foreach ($block in $script:F126Blocks) { $byHeading[[string]$block.Heading] = @($block.Lines) }
        @($byHeading['What stopped it']) | Should -Contain 'Reason code: POSTGRES_DATABASE_ROLLBACK_VERIFIED'
        @($byHeading['What stopped it']) | Should -Contain 'Stage: DatabaseCreation'
        @($byHeading['What to do next']) | Should -Contain 'Open Details and review the preserved PostgreSQL setup evidence.'
        # One line per line of the tool text, not one wall of text.
        @($byHeading['Why it stopped']).Count | Should -Be 3
    }

    It 'points to the log and does not prompt where nothing can be asked (the protected resume window)' {
        # Mutation: prompt in the child window that has no keyboard path for it.
        Write-TpmPostgresSetupFailure -Result (New-F126FailedSetupResult)
        @($script:F126Prompts).Count | Should -Be 0
        @($script:F126Screen) | Should -Contain '  The log says why.'
        (@($script:F126Screen) -join "`n") | Should -Not -Match '(?i)pg_restore|constraint|exit'
    }

    It 'names each blocked game and its short reason on the main screen when setup stopped at the profile check (N18A)' {
        # Who gets hurt: a beginner who sees "setup stopped" and cannot tell which game profile to fix. Smoke N18 found the names only in the log.
        # Mutation: drop the list -> the names are only behind D. Mutation: print every reason -> the raw tool text and the path appear.
        $result = New-F126FailedSetupResult
        $result.TechnicalDetails = [pscustomobject]@{ Stage = 'Preflight'; FailureReasons = @(
            'TargetTossProLawndartsNoPass: The profile has no PostgreSQL Pass field.',
            'Target Toss Pro Bags [TargetTossProBagsNoExe]: The profile needs database creation but its game executable is unavailable.',
            ("Raw Game [RawGame]: restore failed`r`npg_restore: exit code 2"),
            'PathGame: The file C:\Games\PathGame\game.exe is missing.') }
        Write-TpmPostgresSetupFailure -Result $result -OfferDetails
        $screen = @($script:F126Screen) -join "`n"
        $screen | Should -Match '(?m)^  These games need a fix first:$'
        $screen | Should -Match '(?m)^    TargetTossProLawndartsNoPass: The profile has no PostgreSQL Pass field\.$'
        $screen | Should -Match '(?m)^    Target Toss Pro Bags \[TargetTossProBagsNoExe\]: The profile needs database creation but its game executable is unavailable\.$'
        $screen | Should -Not -Match 'RawGame|pg_restore|PathGame|C:\\'
        @($script:F126Prompts) | Should -Be @('  Press D to see why, or Enter to continue')
        ($script:F126Log -join "`n") | Should -Match 'Postgres setup failure reason: Raw Game \[RawGame\]'
    }

    It 'says nothing extra and asks nothing when the result has no reason lines' {
        # Mutation: ask for D when there is nothing to show.
        $result = New-F126FailedSetupResult
        $result.TechnicalDetails = [pscustomobject]@{ Stage = 'DatabaseCreation'; FailureReasons = @() }
        Write-TpmPostgresSetupFailure -Result $result -OfferDetails
        @($script:F126Prompts).Count | Should -Be 0
        @($script:F126Screen).Count | Should -Be 1
    }
}
