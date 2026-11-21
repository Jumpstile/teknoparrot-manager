#Requires -Module Pester

# FIX70: follow-up to FIX66 (shared readability helpers and the start-up summary).
#
#  1. The start-up DAT question has exactly one blank line before it, never none and never two in a row.
#  2. The reason-code table has a plain sentence for the PostgreSQL codes, and every literal reason code in
#     the product is either in the table or on an explicit allow-list.
#  3. Write-TpmOutcome accepts an empty Title (no status line) and returns nothing unless -PassThru is given.
#  4. Write-TpmText (and a block color in Show-TpmDetailBlocks) fall back to the default color for an invalid color name.
#
# The production script is parsed and only its function definitions (and the start-up statements named below,
# cut out of the syntax tree) are run. Every file lives under TestDrive. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $script:F70Ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX70 tests could not parse the production script.' }
    $script:F70Source = $source
    $definitions = @($script:F70Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix70-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    function Install-F70Mocks {
        param([int]$Width = 80, [string[]]$Answers = @(), [bool]$Interactive = $true)
        $script:F70Screen = New-Object System.Collections.Generic.List[object]
        $script:F70Log = New-Object System.Collections.Generic.List[string]
        $script:F70Prompts = New-Object System.Collections.Generic.List[string]
        $script:F70Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:F70Width = $Width
        $script:F70Interactive = $Interactive
        foreach ($answer in $Answers) { [void]$script:F70Answers.Enqueue($answer) }
        Mock Write-Host { [void]$script:F70Screen.Add([pscustomobject]@{ Text = [string]($Object -join ' '); Color = [string]$ForegroundColor }) }
        Mock Write-Log { [void]$script:F70Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return [int]$script:F70Width }
        Mock Test-TpmInteractiveInput { return [bool]$script:F70Interactive }
        Mock Read-HostSafe {
            [void]$script:F70Prompts.Add([string]$Prompt)
            if ($script:F70Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:F70Answers.Dequeue()
        }
    }

    function Get-F70Lines { return @($script:F70Screen | ForEach-Object { $_.Text }) }

    # The number of blank lines that directly follow another blank line.
    function Get-F70DoubleBlankCount {
        param([string[]]$Lines)
        $count = 0
        for ($index = 1; $index -lt $Lines.Count; $index++) {
            if ($Lines[$index] -eq '' -and $Lines[$index - 1] -eq '') { $count++ }
        }
        return $count
    }

    # The start-up pieces, cut out of the production syntax tree by what they do (not by line number).
    function Get-F70StartupPieces {
        $pieces = @{}
        $offerAssign = @($script:F70Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -eq '$tpmOfferSavedConfig'
        }, $true))
        if ($offerAssign.Count -ne 1) { throw 'Expected exactly one $tpmOfferSavedConfig assignment.' }
        $offerBlock = @($offerAssign[0].Right.FindAll({ $args[0] -is [System.Management.Automation.Language.ScriptBlockExpressionAst] }, $true))[0]
        $offerText = $offerBlock.Extent.Text
        $pieces['Offer'] = $offerText.Substring(1, $offerText.Length - 2)

        $missingIf = @($script:F70Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and $args[0].Clauses[0].Item1.Extent.Text -like '*$eggmanDatZip -and -not (Test-Path*' -and $args[0].Clauses[0].Item1.Extent.Text -like '*$datFilePath -and -not (Test-Path*'
        }, $true)) | Select-Object -First 1
        if ($null -eq $missingIf) { throw 'Start-up missing-DAT block not found.' }
        $pieces['MissingDat'] = $missingIf.Extent.Text

        $datIf = @($script:F70Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and $args[0].Clauses[0].Item1.Extent.Text -like '*-not $eggmanDatZip -and -not $datFilePath*' -and
            @($args[0].FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Read-TpmChoice' }, $true)).Count -gt 0
        }, $true)) | Select-Object -First 1
        if ($null -eq $datIf) { throw 'Start-up DAT question block not found.' }
        $statements = @($datIf.Clauses[0].Item2.Statements)
        $choiceIndex = -1
        for ($index = 0; $index -lt $statements.Count; $index++) {
            if ($statements[$index] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $statements[$index].Left.Extent.Text -eq '$datChoice') { $choiceIndex = $index; break }
        }
        if ($choiceIndex -lt 1) { throw 'Start-up DAT choice statement not found.' }
        $pieces['Prelude'] = $script:F70Source.Substring($statements[0].Extent.StartOffset, $statements[$choiceIndex - 1].Extent.EndOffset - $statements[0].Extent.StartOffset)
        return $pieces
    }

    # Runs the named start-up pieces, in order, in one scope - as the product script does. Returns what the
    # pieces left in the variables the DAT question looks at.
    function Invoke-F70Startup {
        param([string[]]$Pieces, [hashtable]$Seed = @{})
        $configPath = $script:F70ConfigPath
        $isPostgresRecoveryResume = $false
        $postgresSuperPasswordEncrypted = $null
        $checkForUpdatesOnStartup = $true
        $unattendedModeSaved = $null
        $configAccepted = $false
        $tpRoot = $null
        $gamesInstallFolder = $null
        $pendingApplyMode = $null
        $Unattended = $false
        $eggmanDatZip = ''
        $datFilePath = ''
        $tpmPrintedAfterSavedSettings = $false
        foreach ($name in @($Seed.Keys)) { Set-Variable -Name $name -Value $Seed[$name] }
        foreach ($piece in $Pieces) { . ([scriptblock]::Create($script:F70StartupPieces[$piece])) }
        return [pscustomobject]@{ Printed = $tpmPrintedAfterSavedSettings; Accepted = $configAccepted }
    }

    # Every string literal a reason-code argument can evaluate to: a plain string, a string in parentheses or in
    # $( ), and the strings in the branches of an if / elseif / else.
    function Add-F70Literal {
        param($Node, $Into)
        if ($null -eq $Node) { return }
        if ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst]) { [void]$Into.Add([string]$Node.Value); return }
        if ($Node -is [System.Management.Automation.Language.ParenExpressionAst]) { Add-F70Literal -Node $Node.Pipeline -Into $Into; return }
        if ($Node -is [System.Management.Automation.Language.SubExpressionAst]) {
            foreach ($statement in @($Node.SubExpression.Statements)) { Add-F70Literal -Node $statement -Into $Into }
            return
        }
        if ($Node -is [System.Management.Automation.Language.PipelineAst]) {
            if (@($Node.PipelineElements).Count -eq 1) { Add-F70Literal -Node $Node.PipelineElements[0] -Into $Into }
            return
        }
        if ($Node -is [System.Management.Automation.Language.CommandExpressionAst]) { Add-F70Literal -Node $Node.Expression -Into $Into; return }
        if ($Node -is [System.Management.Automation.Language.IfStatementAst]) {
            foreach ($clause in @($Node.Clauses)) {
                foreach ($statement in @($clause.Item2.Statements)) { Add-F70Literal -Node $statement -Into $Into }
            }
            if ($Node.ElseClause) {
                foreach ($statement in @($Node.ElseClause.Statements)) { Add-F70Literal -Node $statement -Into $Into }
            }
        }
    }

    # Every -ReasonCode argument of every command, and every "ReasonCode = ..." hashtable entry, in the product.
    function Get-F70ProductReasonLiterals {
        $literals = New-Object System.Collections.Generic.List[string]
        foreach ($command in @($script:F70Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true))) {
            $elements = @($command.CommandElements)
            for ($index = 0; $index -lt $elements.Count; $index++) {
                if ($elements[$index] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$index].ParameterName -eq 'ReasonCode') {
                    $value = $elements[$index].Argument
                    if ($null -eq $value -and ($index + 1) -lt $elements.Count) { $value = $elements[$index + 1] }
                    Add-F70Literal -Node $value -Into $literals
                }
            }
        }
        foreach ($table in @($script:F70Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $true))) {
            foreach ($pair in @($table.KeyValuePairs)) {
                if ($pair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $pair.Item1.Value -eq 'ReasonCode') {
                    Add-F70Literal -Node $pair.Item2 -Into $literals
                }
            }
        }
        return @($literals.ToArray() | ForEach-Object { $_.ToUpperInvariant() } | Select-Object -Unique)
    }

    $script:F70StartupPieces = Get-F70StartupPieces
}

Describe 'FIX70 start-up DAT question has one blank line before it' {
    BeforeEach {
        $script:F70ConfigPath = Join-Path $TestDrive ('saved-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.json')
        $settings = [pscustomobject]@{ TeknoParrotRoot = 'D:\TeknoParrotRootFolder\TeknoParrot'; GamesInstallFolder = 'F:\Arcade\ExtractedGames' }
        [System.IO.File]::WriteAllText($script:F70ConfigPath, ($settings | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
        Install-F70Mocks -Answers @('Y')
        Mock Get-EggmanDatDataRoot { return 'C:\Eggman' }
        Mock Test-TpmTransactionResult { return $true }
    }

    It 'writes the question after <Case>' -TestCases @(
        @{ Case = 'no saved settings were accepted'; Accepted = $false; Printed = $false; BlankFirst = $true },
        @{ Case = 'accepted saved settings and later output'; Accepted = $true; Printed = $true; BlankFirst = $true },
        @{ Case = 'accepted saved settings and nothing since'; Accepted = $true; Printed = $false; BlankFirst = $false }
    ) {
        param($Case, $Accepted, $Printed, $BlankFirst)
        # Mutation: drop -BlankBefore from the first DAT line (case 1 and 2 start with the question), or always add it
        # (case 3 then starts with a blank line that doubles the one the saved-settings step already wrote).
        [void](Invoke-F70Startup -Pieces @('Prelude') -Seed @{ configAccepted = $Accepted; tpmPrintedAfterSavedSettings = $Printed })
        $lines = @(Get-F70Lines)
        if ($BlankFirst) {
            $lines.Count | Should -Be 5
            $lines[0] | Should -BeExactly ''
            $lines[1] | Should -Match '^  Optional: download the DAT index'
        } else {
            $lines.Count | Should -Be 4
            $lines[0] | Should -Match '^  Optional: download the DAT index'
        }
        $lines[$lines.Count - 1] | Should -BeExactly ''
        (Get-F70DoubleBlankCount -Lines $lines) | Should -Be 0
    }

    It 'shows one blank line, not two, between the accepted saved settings and the DAT question' {
        # Mutation: write the blank line before the question without checking whether the saved-settings step
        # already ended with one -> two blank lines in a row.
        [void](Invoke-F70Startup -Pieces @('Offer', 'Prelude'))
        $lines = @(Get-F70Lines)
        $said = [array]::IndexOf($lines, 'Using your saved settings.')
        $said | Should -BeGreaterOrEqual 0
        $lines[$said + 1] | Should -BeExactly ''
        $lines[$said + 2] | Should -Match '^  Optional: download the DAT index'
        (Get-F70DoubleBlankCount -Lines $lines) | Should -Be 0
    }

    It 'writes no double blank line on the way from the saved settings to the question, and a blank line after the missing-DAT notice' {
        # Mutation: do not record that the missing-DAT notice printed -> the question follows the yellow notice directly;
        # or let the missing-DAT notice write its own blank line after the saved-settings blank -> two blank lines in a row.
        $result = Invoke-F70Startup -Pieces @('Offer', 'MissingDat', 'Prelude') -Seed @{ eggmanDatZip = 'C:\No\Such\Folder\Eggman-DAT.zip' }
        $result.Printed | Should -BeTrue
        $lines = @(Get-F70Lines)
        $notice = [array]::IndexOf($lines, '  Saved Eggman DAT ZIP was not found.')
        $notice | Should -BeGreaterThan 0
        $optional = 0
        for ($index = $notice; $index -lt $lines.Count; $index++) { if ($lines[$index] -match '^  Optional: download the DAT index') { $optional = $index; break } }
        $lines[$optional - 1] | Should -BeExactly ''
        $lines[$optional - 2] | Should -Not -BeExactly ''
        (Get-F70DoubleBlankCount -Lines $lines) | Should -Be 0
    }

    It 'reads the start-up state undefined-safe, also in strict mode: <Case>' -TestCases @(
        @{ Case = 'nothing set means add the blank line'; Seed = @{}; Expected = $false },
        @{ Case = 'accepted and nothing printed since'; Seed = @{ configAccepted = $true; tpmPrintedAfterSavedSettings = $false }; Expected = $true },
        @{ Case = 'accepted but output followed'; Seed = @{ configAccepted = $true; tpmPrintedAfterSavedSettings = $true }; Expected = $false },
        @{ Case = 'only the printed flag is set'; Seed = @{ tpmPrintedAfterSavedSettings = $false }; Expected = $false }
    ) {
        param($Case, $Seed, $Expected)
        # Mutation: read the variables directly -> an unset variable throws in strict mode (the Fix66 test runs the DAT
        # block with no start-up state), or treat an unset variable as "already blank" -> the question has no blank line before it.
        $actual = & {
            Set-StrictMode -Version Latest
            foreach ($name in @($Seed.Keys)) { Set-Variable -Name $name -Value $Seed[$name] }
            Test-TpmStartupBlankLineAlreadyWritten
        }
        $actual | Should -Be $Expected
    }
}

Describe 'FIX70 reason codes for the PostgreSQL screens' {
    BeforeAll {
        # Codes that only the automatic password reset raised (POSTGRES_RECOVERY_BUSY, RECOVERY_BACKUP_UNVERIFIED, FINAL_AUTHENTICATION_UNVERIFIED,
        # RESET_INVOCATION_UNVERIFIED) are gone with that reset (FIX95); they have no table entry and are not listed here.
        $script:F70NewCodes = @(
            'POSTGRES_ALREADY_CONFIGURED', 'POSTGRES_DATABASE_CREATION_FAILED_BEFORE_MUTATION', 'POSTGRES_SETUP_VERIFIED',
            'DATABASE_STATE_UNVERIFIED', 'REINITIALIZED', 'RECOVERY_EVIDENCE_REQUIRED', 'BACKUP_ROOT_UNVERIFIED',
            'MANUAL_RECOVERY_REQUIRED', 'TRANSACTION_RESULT_UNAVAILABLE'
        )
    }

    It 'gives <Code> one plain sentence and returns the code separately' -TestCases @(
        @{ Code = 'POSTGRES_ALREADY_CONFIGURED' }, @{ Code = 'POSTGRES_DATABASE_CREATION_FAILED_BEFORE_MUTATION' },
        @{ Code = 'POSTGRES_SETUP_VERIFIED' }, @{ Code = 'DATABASE_STATE_UNVERIFIED' }, @{ Code = 'REINITIALIZED' },
        @{ Code = 'RECOVERY_EVIDENCE_REQUIRED' }, @{ Code = 'BACKUP_ROOT_UNVERIFIED' }, @{ Code = 'MANUAL_RECOVERY_REQUIRED' },
        @{ Code = 'TRANSACTION_RESULT_UNAVAILABLE' }
    ) {
        param($Code)
        # Mutation: remove the code from the table -> Known is false and the text is the generic sentence; or write a
        # sentence that is two sentences, too long, or still uses an internal word.
        $reason = Get-TpmPlainReason -Code $Code
        $reason.Known | Should -BeTrue
        $reason.Code | Should -BeExactly $Code
        $reason.Text | Should -Not -BeExactly 'This could not be completed. Details have the technical reason.'
        $reason.Text | Should -Match '^[A-Z][^_.]*\.$'
        $reason.Text.Length | Should -BeLessThan 110
        $reason.Text | Should -Not -Match '(?i)rollback|mutation|manifest|transaction|preflight|authentication|evidence|postgres|receipt|hash'
    }

    It 'gives the nine new codes nine different sentences' {
        # Mutation: map several codes to one sentence.
        @($script:F70NewCodes | ForEach-Object { (Get-TpmPlainReason -Code $_).Text } | Select-Object -Unique).Count | Should -Be 9
    }

    It 'gives the PostgreSQL restore and recovery code <Code> its own plain sentence' -TestCases @(
        @{ Code = 'PREFLIGHT_FAILED' }, @{ Code = 'ROLLBACK_UNVERIFIED' }
    ) {
        param($Code)
        # Mutation: remove the code from the table (it is raised by the PostgreSQL restore and recovery results), or give it
        # the sentence of another code.
        $reason = Get-TpmPlainReason -Code $Code
        $reason.Known | Should -BeTrue
        $reason.Text | Should -Match '^[A-Z][^_.]*\.$'
        $reason.Text | Should -Match 'could not|nothing was changed'
        $reason.Text | Should -Not -Match '(?i)rollback|mutation|manifest|transaction|preflight|authentication|evidence|postgres|receipt|hash'
        $others = @($script:F70NewCodes | ForEach-Object { (Get-TpmPlainReason -Code $_).Text })
        $others | Should -Not -Contain $reason.Text
    }

    It 'reads <Code> as a success' -TestCases @(
        @{ Code = 'POSTGRES_SETUP_VERIFIED' }, @{ Code = 'POSTGRES_ALREADY_CONFIGURED' }, @{ Code = 'REINITIALIZED' }
    ) {
        param($Code)
        # Mutation: word a success code as a failure ("could not ...", "nothing was changed"), which would scare a beginner
        # after a good result.
        $text = (Get-TpmPlainReason -Code $Code).Text
        $text | Should -Match '\b(ready|checked)\b'
        $text | Should -Not -Match 'could not|did not|nothing was changed|failed|must|busy'
    }

    It 'reads <Code> as something that did not finish' -TestCases @(
        @{ Code = 'POSTGRES_DATABASE_CREATION_FAILED_BEFORE_MUTATION' }, @{ Code = 'DATABASE_STATE_UNVERIFIED' },
        @{ Code = 'RECOVERY_EVIDENCE_REQUIRED' }, @{ Code = 'BACKUP_ROOT_UNVERIFIED' }, @{ Code = 'MANUAL_RECOVERY_REQUIRED' },
        @{ Code = 'TRANSACTION_RESULT_UNAVAILABLE' }
    ) {
        param($Code)
        # Mutation: word a failure code as a success -> no "could not", "nothing was changed", "must", "gave no result" or "there was none" in it.
        (Get-TpmPlainReason -Code $Code).Text | Should -Match 'could not|nothing was changed|must be fixed|gave no result|there was none'
    }

    It 'has a table entry or an allow-list entry for every reason code literal in the product' {
        # Mutation: add a new -ReasonCode / ReasonCode = literal anywhere in the product without a table entry and without
        # adding it to the allow-list below -> it is listed in the failure message.
        #
        # ALLOW-LIST: codes that are intentionally NOT translated. They belong to flows whose screens do not use the shared
        # outcome screen yet (updater, file-transaction, ReShade/crosshair/FFB, library health, registration). Until such a
        # screen is rewritten, the generic sentence is shown for them and the code stays in Details and the log.
        # Add a code here only on purpose; the test below fails when an entry is no longer in the product or gets a table entry.
        $allowList = @(
            # Path checks (a result field, not a transaction reason).
            'EMPTY_PATH', 'INVALID',
            # Manager updater.
            'UPDATE_ALREADY_CURRENT', 'UPDATE_CURRENT_VERSION_INVALID', 'UPDATE_DECLINED', 'UPDATE_RELEASE_UNAVAILABLE',
            'UPDATE_RELEASE_VERSION_INVALID', 'UPDATE_REMIND_LATER',
            # Game-file transactions: CPS3, crosshair, dgVoodoo, FFB.
            'CPS3_FILE_TRANSACTION_FAILED', 'CROSSHAIR_FILE_TRANSACTION_FAILED', 'CROSSHAIR_SOURCE_UNAVAILABLE',
            'CROSSHAIR_TARGET_UNAVAILABLE', 'DGV_FILE_TRANSACTION_FAILED', 'FFB_FILE_TRANSACTION_FAILED',
            'FFB_PROFILE_REVIEW_REQUIRED', 'NO_PLUGIN_CHANGES_NEEDED',
            # ReShade undo: the engine's failure code for the file batch; the undo screen shows the UNDO_* code it is turned into.
            'RESHADE_UNDO_FAILED',
            # Bezel copy and undo (own screen sentences) and System 11 saved-file copy (own review screen sentences).
            'BEZEL_FILE_TRANSACTION_FAILED', 'BEZEL_UNDO_FAILED', 'S11_FILE_TRANSACTION_FAILED',
            # Propagate Controls baseline row: its screen words the reason with Get-TpmBaselineReasonText.
            'UNREADABLE',
            # Controls, profile writes and paths.
            'CONTROLS_PROCESSED', 'PATHS_PROCESSED', 'NO_USABLE_FAMILY_REFERENCE', 'NO_ELIGIBLE_CHANGES', 'PROFILE_BACKUP_COMPLETED_NO_WRITE',
            'PROFILE_CHANGED_BEFORE_WRITE', 'PROFILE_PLAN_CHANGED', 'PROFILE_SAVE_FAILED',
            'PROFILE_SCAN_INCOMPLETE',
            # Library health, registration and repair.
            'DETECTION_FAILED', 'HEALTH_CHECK_COMPLETED', 'HEALTH_COVERAGE_INCOMPLETE', 'INVENTORY_UNVERIFIED', 'NEW_REGISTRATION_TARGETS_UNVERIFIED', 'PREVIEW_NO_REGISTRATION', 'NO_LEGACY_STATE', 'UNATTENDED_SKIPPED', 'NO_MEMBERSHIP',
            'NO_REPAIR_CANDIDATE', 'REGISTRATION_EVIDENCE_UNAVAILABLE', 'REPAIR_PLAN_ONLY', 'SOURCE_INSPECTION_FAILED', 'SOURCE_MANIFEST_FAILED',
            # Generic engine results that are not raised by the PostgreSQL or Reset and Restore flows.
            'PREFLIGHT_INCOMPLETE', 'RESULT_UNAVAILABLE',
            # Game startup files copy (the review screen prints its own plain sentences; the code stays in the log).
            'PREREQUISITE_FILE_TRANSACTION_FAILED'
        )
        $literals = @(Get-F70ProductReasonLiterals)
        $literals.Count | Should -BeGreaterThan 90
        $missing = @($literals | Where-Object { -not (Get-TpmPlainReason -Code $_).Known -and ($allowList -notcontains $_) })
        ($missing -join ', ') | Should -BeExactly ''
        foreach ($code in $script:F70NewCodes) { $literals | Should -Contain $code }

        # The allow-list cannot go stale: every entry is still used by the product and still has no table entry.
        $stale = @($allowList | Where-Object { $literals -notcontains $_ })
        ($stale -join ', ') | Should -BeExactly ''
        $translated = @($allowList | Where-Object { (Get-TpmPlainReason -Code $_).Known })
        ($translated -join ', ') | Should -BeExactly ''
    }
}

Describe 'FIX70 Write-TpmOutcome empty title and return value' {
    It 'accepts an empty Title, prints no status line and does not log one' {
        # Mutation: remove [AllowEmptyString()] -> a parameter binding error; or print/log the empty status line.
        Install-F70Mocks -Interactive $false
        { Write-TpmOutcome -Title '' -Done @('One thing') } | Should -Not -Throw
        Install-F70Mocks -Interactive $false
        Write-TpmOutcome -Title '' -Done @('One thing')
        $lines = @(Get-F70Lines)
        $lines | Should -Contain '    - One thing'
        $lines[0] | Should -BeExactly ''
        $lines[1] | Should -BeExactly '    - One thing'
        @($script:F70Log | Where-Object { $_ -like 'Result [[]*' }).Count | Should -Be 0
        $script:F70Log | Should -Contain 'Result done: One thing'
    }

    It 'still writes the status line and its log line for a real Title' {
        # Mutation: treat every Title as empty.
        Install-F70Mocks -Interactive $false
        Write-TpmOutcome -Title 'Done.' -Status Attention
        @(Get-F70Lines) | Should -Contain '  Done.'
        $script:F70Log | Should -Contain 'Result [Attention]: Done.'
    }

    It 'returns nothing unless -PassThru is given' {
        # Mutation: always return the result object -> it leaks into the caller's output (the screen of a menu function).
        Install-F70Mocks -Interactive $false
        $leaked = Write-TpmOutcome -Title 'Done.' -Done @('One thing') -DetailBlocks @(@{ Heading = 'Game one'; Lines = @('Database: GameDB01') })
        ($null -eq $leaked) | Should -BeTrue
        $captured = & { Write-TpmOutcome -Title 'Done.' -Done @('One thing') }
        ($null -eq $captured) | Should -BeTrue
    }

    It 'returns what the Details question did with -PassThru' {
        # Mutation: ignore -PassThru -> $null, or report DetailsShown for the wrong key.
        Install-F70Mocks -Answers @('d')
        $result = Write-TpmOutcome -Title 'Done.' -Done @('One thing') -DetailBlocks @(@{ Heading = 'Game one'; Lines = @('Database: GameDB01') }) -PassThru
        $result.DetailsAvailable | Should -BeTrue
        $result.DetailsShown | Should -BeTrue
        Install-F70Mocks -Answers @('')
        $result = Write-TpmOutcome -Title 'Done.' -Done @('One thing') -DetailBlocks @(@{ Heading = 'Game one'; Lines = @('Database: GameDB01') }) -PassThru
        $result.DetailsShown | Should -BeFalse
    }
}

Describe 'FIX70 invalid color names' {
    It 'writes the line in the default color for the invalid color <Name>' -TestCases @(
        @{ Name = 'NotAColor' }, @{ Name = 'Purple' }, @{ Name = '99' }, @{ Name = '  ' }
    ) {
        param($Name)
        # Mutation: pass the color straight to Write-Host -> a parameter binding error; or accept a number
        # because [enum]::TryParse says it is a number (99 is not a console color).
        Install-F70Mocks
        { Write-TpmText -Text 'careful' -Color $Name } | Should -Not -Throw
        Install-F70Mocks
        Write-TpmText -Text 'careful' -Color $Name
        @(Get-F70Lines) | Should -Contain '  careful'
        $script:F70Screen[0].Color | Should -BeExactly ''
    }

    It 'still colors a valid color name, in any case: <Name>' -TestCases @(
        @{ Name = 'Yellow'; Expected = 'Yellow' }, @{ Name = 'yellow'; Expected = 'Yellow' }, @{ Name = 'dArKgReEn'; Expected = 'DarkGreen' }
    ) {
        param($Name, $Expected)
        # Mutation: ignore the color altogether, or reject a valid name that is not spelled exactly.
        Install-F70Mocks
        Write-TpmText -Text 'careful' -Color $Name
        $script:F70Screen[0].Color | Should -BeExactly $Expected
    }

    It 'prints a block with an invalid Color in the default color and keeps the other blocks colored' {
        # Mutation: validate only the direct Write-TpmText color, not a block color -> the details view stops with an error.
        Install-F70Mocks
        $blocks = @(
            @{ Heading = 'Game one'; Color = 'Purple'; Lines = @('Database: GameDB01') },
            @{ Heading = 'Game two'; Color = 'Yellow'; Lines = @('Database: GameDB02') }
        )
        { Show-TpmDetailBlocks -Blocks $blocks } | Should -Not -Throw
        Install-F70Mocks
        Show-TpmDetailBlocks -Blocks $blocks
        $first = @($script:F70Screen | Where-Object { $_.Text -match 'GameDB01' })[0]
        $second = @($script:F70Screen | Where-Object { $_.Text -match 'GameDB02' })[0]
        $first.Color | Should -BeExactly ''
        $second.Color | Should -BeExactly 'Yellow'
    }
}
