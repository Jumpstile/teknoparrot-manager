#Requires -Module Pester

# FIX110B (slice P): product text and logic findings of the whole-product review.
#   S-7   a guided rebuild that accepted the known vendor foreign-key limitation says so in its result, its details and its evidence.
#   S-9   dgVoodoo2 says (before the choice and in the results) that a per-game dgVoodoo.conf replaces the old one.
#   S-10  a BepInEx source-folder refusal has plain words and a real next step; repair-reset is not offered; the success branches wait.
#   S-11  the real run after a preview keeps what the preview used (Main, Supplementary, repair scope) and offers the preview details first.
#   S-20  one place for the TeknoParrotUI troubleshooting file (the managed Reports folder), the same in the product, the guides,
#         the startup migration and the support package.
#   N-1   plain product names in ordinary output.
# The product is never run or dot-sourced: named functions and named script-body statements are taken from the parsed script
# (AST) and run against synthetic fixtures in $TestDrive. What this CANNOT prove: how a real console paints a line, or a real
# PostgreSQL restore (pg_restore itself is never called).

BeforeAll {
    $script:F110Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:F110ScriptPath = Join-Path $script:F110Root 'TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:F110Ast = [System.Management.Automation.Language.Parser]::ParseFile($script:F110ScriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110B tests could not parse the production script.' }
    $script:F110Functions = @{}
    foreach ($node in $script:F110Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $script:F110Functions.ContainsKey($node.Name)) { $script:F110Functions[$node.Name] = $node }
    }

    # The text of the named production functions and every production function they call, except the stubbed names.
    function Get-F110FunctionText {
        param([string[]]$Roots, [string[]]$Stubs)
        $selected = @{}
        $queue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($root in $Roots) { $queue.Enqueue($root) }
        while ($queue.Count -gt 0) {
            $name = $queue.Dequeue()
            if ($selected.ContainsKey($name) -or $Stubs -contains $name) { continue }
            if (-not $script:F110Functions.ContainsKey($name)) { throw ('Missing production function: {0}' -f $name) }
            $node = $script:F110Functions[$name]
            $selected[$name] = $node
            foreach ($command in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $called = $command.GetCommandName()
                if ($called -and $script:F110Functions.ContainsKey($called)) { $queue.Enqueue($called) }
            }
        }
        return (($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n")
    }

    # The one script-body if-statement whose first condition text is $ConditionText (and whose text contains $BodyContains).
    function Get-F110TopLevelIf {
        param([string]$ConditionText, [string]$BodyContains = '')
        $found = @($script:F110Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -ceq $ConditionText -and
            ($BodyContains -eq '' -or $n.Extent.Text.Contains($BodyContains))
        }, $true))
        if ($found.Count -ne 1) { throw ('FIX110B tests expected one if-statement "{0}", found {1}.' -f $ConditionText, $found.Count) }
        return $found[0].Extent.Text
    }

    # Runs one extracted statement with the given variables, as the script body would, and returns the named variables afterwards.
    function Invoke-F110Block {
        param([string]$Text, [hashtable]$Variables, [string[]]$Outputs)
        foreach ($key in $Variables.Keys) { Set-Variable -Name $key -Value $Variables[$key] }
        foreach ($f110Once in 1) { . ([scriptblock]::Create($Text)) }
        $f110Result = @{}
        foreach ($name in $Outputs) {
            $f110Variable = Get-Variable -Name $name -ErrorAction SilentlyContinue
            $f110Result[$name] = $null
            if ($f110Variable) { $f110Result[$name] = $f110Variable.Value }
        }
        return $f110Result
    }

    $stubs = @(
        'Write-Log', 'Get-PostgresRestoreBackupPlan', 'Test-Postgres83RestoreToolSet', 'Test-PostgresPassword', 'Get-TpmFileState',
        'Invoke-Postgres83RestoreCommandChecked', 'New-PostgresRestoreEvidenceRoot', 'Get-PostgresDatabaseState',
        'Invoke-Postgres83RestoreDatabase', 'Restore-Postgres83DatabaseFromReceipt', 'ConvertTo-PostgresRedactedText',
        'Reset-PostgresDatabaseFromBackup', 'Get-PostgresReinitializePlansFromProfiles', 'Test-PostgresReinitializePlan',
        'Read-TpmYesNo', 'Read-TpmChoice', 'Read-PathWithBrowse', 'Invoke-TpmProgressGroup', 'Invoke-TpmCps3SupplementaryInstall',
        'Get-TpmDeferredDetails', 'Clear-TpmDeferredDetails', 'Show-TpmDetailBlocks'
    )
    $roots = @(
        'Get-PostgresAcceptedRestoreLimitations', 'Write-PostgresRestoreReceiptFile', 'Invoke-PostgresRestoreTransaction',
        'Invoke-PostgresReinitializePlan', 'Write-PostgresReinitializeSuccess', 'Get-TpmDgVoodoo2ResultView',
        'Get-TpmBepInExSkipWords', 'Get-TpmBepInExFailureView', 'Get-TpmLegacyOwnedItems', 'Get-TpmSupportPackageHelpBlocks',
        'Show-TpmDeferredDetails', 'Invoke-TpmCps3SupplementaryOffer'
    )
    . ([scriptblock]::Create((Get-F110FunctionText -Roots $roots -Stubs $stubs)))

    function Write-Log { param([string]$msg) }
    function Get-PostgresRestoreBackupPlan { param($BackupFiles, $SelectedBackupRoot) }
    function Test-Postgres83RestoreToolSet { param($SuperPasswordPlain) }
    function Test-PostgresPassword { param($SuperPasswordPlain) }
    function Get-TpmFileState { param($Path) }
    function Invoke-Postgres83RestoreCommandChecked { param($ToolName, $Arguments, $SuperPasswordPlain, $CommandLog, $DatabaseName, [switch]$AcceptConstraintOnlyRestoreWarnings) }
    function New-PostgresRestoreEvidenceRoot { param($EvidenceRoot) }
    function Get-PostgresDatabaseState { param($DbName, $SuperPasswordPlain) }
    function Invoke-Postgres83RestoreDatabase { param($Item, $PreState, $SuperPasswordPlain, [switch]$AcceptConstraintOnlyRestoreWarnings) }
    function Restore-Postgres83DatabaseFromReceipt { param($Receipt, $SuperPasswordPlain) }
    function ConvertTo-PostgresRedactedText { param($Text, $Secrets) }
    function Reset-PostgresDatabaseFromBackup { param($DbName, $Encoding, $BackupFile, $SuperPasswordPlain, $RecoveryBackup, [switch]$Confirmed) }
    function Get-PostgresReinitializePlansFromProfiles { param($UserProfilesDir, $OnlyDatabases) }
    function Test-PostgresReinitializePlan { param($ExpectedPlanJson, $ExpectedPlanHash, $CurrentPlans) }
    function Read-TpmYesNo { param($Prompt, $Default) }
    function Read-TpmChoice { param($Prompt, $Choices, $Default) }
    function Read-PathWithBrowse { param($Prompt, $Mode, $FileFilter) }
    function Invoke-TpmProgressGroup { param($Title, $Action) }
    function Invoke-TpmCps3SupplementaryInstall { param($SourcePath, $TpRoot, [switch]$ReplaceDifferingCache) }
    function Get-TpmDeferredDetails { }
    function Clear-TpmDeferredDetails { }
    function Show-TpmDetailBlocks { param($Blocks, $Note, $HeadingColor) }
    # Only the two helpers below are real in the preview-details test; the S-11 blocks below call them by name.
    function Select-GamesInteractive { param($zipSource, $installFolder, $datIndex, $userProfilesDir, [switch]$SelectAll) }

    function New-F110Receipt {
        param([string]$Database, [string]$ItemId, [bool]$Succeeded = $true, [bool]$Accepted = $false)
        $command = [pscustomobject]@{ Tool = 'pg_restore.exe'; Arguments = @('-d', $Database); ExitCode = 0; Succeeded = $true; Output = '' }
        if ($Accepted) {
            $command | Add-Member -NotePropertyName AcceptedWarnings -NotePropertyValue 'Finished with a known limitation: 2 links between tables in the game''s own backup could not be made. This is a known problem with that backup. The tables and their rows were restored.'
            $command | Add-Member -NotePropertyName AcceptedConstraintNames -NotePropertyValue @('fk_one', 'fk_two')
        }
        return [pscustomobject]@{
            ItemId = $ItemId; Database = $Database; BackupFile = 'C:\fixture\bundled.backup'; BackupSha256 = 'AA'; RollbackDumpPath = ''
            RollbackDumpSha256 = ''; PreStateExists = $true; Encoding = 'UTF8'; MutationAttempted = $true; CreateOwnedForRollback = $true
            Changed = $true; Succeeded = $Succeeded; FailureStage = $(if ($Succeeded) { $null } else { 'Restore' })
            Error = $(if ($Succeeded) { $null } else { 'pg_restore failed' }); PostFailureState = $null
            FinalVerification = $null; Commands = @($command); DropReceipt = $null; RollbackAttempted = $false; RollbackVerified = $false
            RollbackError = $null; RollbackCommands = @(); RollbackDropReceipt = $null
        }
    }
}

Describe 'FIX110B S-7 a guided rebuild that accepted the known vendor limitation says so' {
    BeforeEach {
        # The real restore takes the machine-wide PostgreSQL lock for up to 2 s; a private name keeps another test process on this PC from failing it.
        $script:PostgresRecoveryLockName = 'Local\TpmFix110BTest-' + [guid]::NewGuid().ToString('N')
        $script:F110Log = New-Object System.Collections.Generic.List[string]
        $script:F110Receipts = @{}
        $script:F110Items = @(
            [pscustomobject]@{ ItemId = 'item-1'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; BackupSha256 = 'AA'; BackupLength = 5; Encoding = 'UTF8' }
        )
        Mock Write-Log { [void]$script:F110Log.Add([string]$msg) }
        Mock Get-PostgresRestoreBackupPlan { [pscustomobject]@{ Valid = $true; Items = @($script:F110Items); SelectedBackupRoot = 'C:\fixture'; FailureCode = $null; Reason = $null } }
        Mock Test-Postgres83RestoreToolSet { [pscustomobject]@{ Verified = $true; Tools = @(); Reason = $null } }
        Mock Test-PostgresPassword { $true }
        Mock Get-TpmFileState { [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $false; Length = 5; Sha256 = 'AA' } }
        Mock Invoke-Postgres83RestoreCommandChecked { [pscustomobject]@{ ExitCode = 0; Succeeded = $true } }
        Mock New-PostgresRestoreEvidenceRoot {
            $path = Join-Path $TestDrive ('evidence-' + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($path)
            $path
        }
        Mock Get-PostgresDatabaseState { [pscustomobject]@{ Verified = $true; Exists = $true } }
        Mock Invoke-Postgres83RestoreDatabase { $script:F110Receipts[[string]$Item.Database] }
        Mock Restore-Postgres83DatabaseFromReceipt { [pscustomobject]@{ RollbackVerified = $true; ItemId = $Receipt.ItemId; Database = $Receipt.Database; RollbackError = $null } }
        Mock ConvertTo-PostgresRedactedText { [string]$Text }
    }

    It 'collects the accepted limitation from the command receipts and ignores receipts without one' {
        # Mutation: ignore AcceptedWarnings (return nothing) or report every command -> the limitation is lost or invented.
        $records = @(Get-PostgresAcceptedRestoreLimitations -Receipts @((New-F110Receipt -Database 'GameDB19' -ItemId 'item-1' -Accepted $true), (New-F110Receipt -Database 'GameDB20' -ItemId 'item-2')))
        $records.Count | Should -Be 1
        $records[0].Database | Should -BeExactly 'GameDB19'
        $records[0].Message | Should -Match 'known limitation'
        @($records[0].ConstraintNames) | Should -Be @('fk_one', 'fk_two')
        @(Get-PostgresAcceptedRestoreLimitations -Receipts @()).Count | Should -Be 0
    }

    It 'puts the limitation in the public result, the evidence and the log when the rebuild is verified' {
        # Mutation: leave -Warnings off the result (the old behavior) -> a verified rebuild looks unqualified.
        $script:F110Receipts['GameDB19'] = New-F110Receipt -Database 'GameDB19' -ItemId 'item-1' -Accepted $true
        $result = Invoke-PostgresRestoreTransaction -BackupFiles @([pscustomobject]@{ BackupFile = 'C:\fixture\one.backup'; Database = 'GameDB19' }) -SuperPasswordPlain 'pw' -AcceptConstraintOnlyRestoreWarnings
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.Warnings).Count | Should -Be 1
        $result.Warnings[0] | Should -Match '^GameDB19: Finished with a known limitation'
        @($result.TechnicalDetails.AcceptedRestoreLimitations).Count | Should -Be 1
        @($result.TechnicalDetails.AcceptedRestoreLimitations[0].ConstraintNames) | Should -Be @('fk_one', 'fk_two')
        (@($script:F110Log) -join "`n") | Should -Match 'accepted a known limitation for database GameDB19 \(constraints: fk_one, fk_two\)'
    }

    It 'adds no warning when nothing was accepted' {
        # Mutation: always add a warning -> every clean rebuild is called limited.
        $script:F110Receipts['GameDB19'] = New-F110Receipt -Database 'GameDB19' -ItemId 'item-1'
        $result = Invoke-PostgresRestoreTransaction -BackupFiles @([pscustomobject]@{ BackupFile = 'C:\fixture\one.backup'; Database = 'GameDB19' }) -SuperPasswordPlain 'pw' -AcceptConstraintOnlyRestoreWarnings
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.Warnings).Count | Should -Be 0
        @($result.TechnicalDetails.AcceptedRestoreLimitations).Count | Should -Be 0
    }

    It 'does not call the limitation part of the final state after a verified rollback, but keeps it in the evidence' {
        # Mutation: attach the warning whatever the outcome -> a rolled-back restore claims a limitation of a state that no longer exists.
        $script:F110Items = @(
            [pscustomobject]@{ ItemId = 'item-1'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; BackupSha256 = 'AA'; BackupLength = 5; Encoding = 'UTF8' }
            [pscustomobject]@{ ItemId = 'item-2'; Database = 'GameDB20'; BackupFile = 'C:\fixture\two.backup'; BackupSha256 = 'AA'; BackupLength = 5; Encoding = 'UTF8' }
        )
        $script:F110Receipts['GameDB19'] = New-F110Receipt -Database 'GameDB19' -ItemId 'item-1' -Accepted $true
        $script:F110Receipts['GameDB20'] = New-F110Receipt -Database 'GameDB20' -ItemId 'item-2' -Succeeded $false
        $files = @([pscustomobject]@{ BackupFile = 'C:\fixture\one.backup'; Database = 'GameDB19' }, [pscustomobject]@{ BackupFile = 'C:\fixture\two.backup'; Database = 'GameDB20' })
        $result = Invoke-PostgresRestoreTransaction -BackupFiles $files -SuperPasswordPlain 'pw' -AcceptConstraintOnlyRestoreWarnings
        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        # FIX128: the Summary of a rolled-back restore is plain. Mutation: the old "...restored the databases to their previous verified state." text.
        $result.Summary | Should -BeExactly 'The restore did not finish. Your old data was put back and checked.'
        @($result.Warnings).Count | Should -Be 0
        @($result.TechnicalDetails.AcceptedRestoreLimitations).Count | Should -Be 1
    }

    It 'writes the accepted limitation into the serialized receipt file' {
        # Mutation: leave AcceptedLimitations out of the receipt rows -> the evidence file cannot show why a "verified" restore had a limitation.
        $folder = Join-Path $TestDrive 'receipt-evidence'
        [void][System.IO.Directory]::CreateDirectory($folder)
        $path = Write-PostgresRestoreReceiptFile -EvidenceRoot $folder -Receipts @((New-F110Receipt -Database 'GameDB19' -ItemId 'item-1' -Accepted $true))
        $rows = @([System.IO.File]::ReadAllText($path) | ConvertFrom-Json)
        @($rows[0].AcceptedLimitations).Count | Should -Be 1
        $rows[0].AcceptedLimitations[0].Database | Should -BeExactly 'GameDB19'
        @($rows[0].AcceptedLimitations[0].ConstraintNames) | Should -Be @('fk_one', 'fk_two')
    }

    It 'carries the limitation into the aggregate reinitialize result and shows it with the success line' {
        # Mutation: build the aggregate result without -Warnings/-TechnicalDetails -> the screen says "rebuilt and checked" with no qualification.
        $backup = Join-Path $TestDrive 'bundled.backup'
        [System.IO.File]::WriteAllText($backup, 'x')
        $planJson = ConvertTo-Json -InputObject @([pscustomobject]@{ Database = 'GameDB19'; BackupFile = $backup; Encoding = 'UTF8' })
        $limitation = [pscustomobject]@{ Database = 'GameDB19'; Message = 'Finished with a known limitation: 2 links between tables could not be made.'; ConstraintNames = @('fk_one') }
        Mock Test-PostgresReinitializePlan { $true }
        Mock Get-PostgresReinitializePlansFromProfiles { @() }
        Mock Reset-PostgresDatabaseFromBackup {
            New-TpmProfileTransactionResult -WorkflowKey 'PostgresRestore' -OperationKey 'ReinitializeDatabase' -Outcome 'SUCCEEDED' -ProductState 'INTENDED' `
                -Summary 'PostgreSQL restore finished and was verified.' -Items @('item-1') -ChangedItems @('item-1') -CompletedItems @('item-1') `
                -MutationStarted $true -MutationCompleted $true -Backup $RecoveryBackup -ReasonCode 'COMPLETED' `
                -TechnicalDetails ([pscustomobject]@{ AcceptedRestoreLimitations = @($limitation) }) -Warnings @('GameDB19: ' + $limitation.Message)
        }
        $recovery = [pscustomobject]@{ Required = $true; Attempted = $true; Created = $true; Verified = $true; Path = (Join-Path $TestDrive 'recovery'); Items = @() }
        $result = Invoke-PostgresReinitializePlan -PlanJson $planJson -PlanHash 'h' -UserProfilesDir (Join-Path $TestDrive 'profiles') -SuperPasswordPlain 'pw' -RecoveryBackup $recovery
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.Warnings).Count | Should -Be 1
        $result.Warnings[0] | Should -Match 'GameDB19: Finished with a known limitation'
        @($result.TechnicalDetails.AcceptedRestoreLimitations).Count | Should -Be 1

        $script:F110Host = New-Object System.Collections.Generic.List[string]
        $script:F110LogLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:F110Host.Add([string]($Object -join ' ')) }
        Mock Write-Log { [void]$script:F110LogLines.Add([string]$msg) }
        Write-PostgresReinitializeSuccess -Result $result
        (@($script:F110Host) -join "`n") | Should -Match 'rebuilt and checked for the selected games'
        (@($script:F110Host) -join "`n") | Should -Match 'harmless warnings from the game''s own backup were skipped'
        # FIX126: the technical note is no longer on the main screen; it stays in the log.
        (@($script:F110Host) -join "`n") | Should -Not -Match 'known limitation'
        (@($script:F110LogLines) -join "`n") | Should -Match 'GameDB19: Finished with a known limitation'
    }

    It 'keeps the plain success line when there is no limitation' {
        # Mutation: always print the limitation heading -> a clean rebuild looks limited.
        $script:F110Host = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:F110Host.Add([string]($Object -join ' ')) }
        Write-PostgresReinitializeSuccess -Result ([pscustomobject]@{ Warnings = @() })
        @($script:F110Host) | Should -Be @('  PostgreSQL data was rebuilt and checked for the selected games.')
    }
}

Describe 'FIX110B S-9 dgVoodoo2 says that a per-game dgVoodoo.conf replaces the old one' {
    BeforeAll {
        function New-F110DgResult {
            param([int]$Overrides = 0, [bool]$NoOp = $false)
            $detail = [pscustomobject]@{ Game = 'GameA'; LegacyApis = @('D3D8'); Files = @('D3D8.dll'); Destination = 'D:\Games\GameA'; Config = 'per-game config' }
            return [pscustomobject]@{ NoOp = $NoOp; DeploymentDetails = @($detail); SkipDetails = @(); MissingPath = 0; MissingDevice = 0; PresetOverrides = $Overrides }
        }
    }

    It 'names the dgVoodoo.conf replacement on the result screen when a preset file was used' {
        # Mutation: keep the unqualified "Existing dgVoodoo2 files were not replaced or removed." -> the screen denies the replacement.
        $view = Get-TpmDgVoodoo2ResultView -Result (New-F110DgResult -Overrides 2)
        $view.NotChanged | Should -Match 'DLL files were not replaced or removed'
        $view.NotChanged | Should -Match 'dgVoodoo\.conf: it was replaced for 2 games with a preset file of their own'
    }

    It 'keeps the short line when no preset file was used, or when nothing was installed' {
        # Mutation: always add the replacement sentence -> a run that replaced no config claims it did.
        (Get-TpmDgVoodoo2ResultView -Result (New-F110DgResult -Overrides 0)).NotChanged | Should -BeExactly 'Existing dgVoodoo2 files were not replaced or removed.'
        (Get-TpmDgVoodoo2ResultView -Result (New-F110DgResult -Overrides 1 -NoOp $true)).NotChanged | Should -BeExactly 'Existing dgVoodoo2 files were not replaced or removed.'
    }

    It 'states the DLL-versus-config distinction in the details' {
        # Mutation: drop the Config file line -> the details deny or omit the replacement.
        $view = Get-TpmDgVoodoo2ResultView -Result (New-F110DgResult -Overrides 1)
        $lines = @($view.DetailBlocks | ForEach-Object { @($_.Lines) }) -join ' '
        $lines | Should -Match 'only added missing compatibility DLLs'
        $lines | Should -Match 'Config file: a game with its own preset file in dgVoodoo2Presets gets that file as its dgVoodoo\.conf\. It replaces the dgVoodoo\.conf that was in the game folder'
    }

    It 'says it before the game choice is asked' {
        # Mutation: remove the pre-consent lines or move them behind the choice -> the user agrees without knowing.
        $text = $script:F110Functions['Invoke-DgVoodoo2Setup'].Extent.Text
        $notice = $text.IndexOf('That REPLACES a dgVoodoo.conf that is already in the game folder.')
        $dllNotice = $text.IndexOf('DLL files that are already there are kept.')
        $choice = $text.IndexOf('Which games should get dgVoodoo2?')
        $notice | Should -BeGreaterThan 0
        $dllNotice | Should -BeGreaterThan 0
        $choice | Should -BeGreaterThan $notice
        $choice | Should -BeGreaterThan $dllNotice
    }
}

Describe 'FIX110B S-10 BepInEx: source-folder reason, no repair-reset, and the result is acknowledged' {
    It 'has plain words for a source-folder refusal instead of the generic failure sentence' {
        # Mutation: remove the SOURCE_COLLECTION entry -> the final screen falls back to "could not be finished".
        $words = @(Get-TpmBepInExSkipWords -Code 'SOURCE_COLLECTION')
        $words.Count | Should -Be 2
        $words[0] | Should -Match 'inside your source folder'
        $words[1] | Should -Match 'inside your source folder'
        $words[0] | Should -Not -Match 'could not be finished'
        (Get-TpmBepInExSkipWords -Code 'SOMETHING_ELSE')[0] | Should -Match 'could not be finished'
    }

    It 'tells the user the real next step for a source-folder refusal (retrying cannot fix it)' {
        # Mutation: keep "Press D to see why, or R to try again." for this reason -> the screen suggests a retry that cannot work.
        $result = [pscustomobject]@{ Updated = 0; Errors = 0; PathReasonCounts = @{ SOURCE_COLLECTION = 1 }; MissingPath = 0; MissingDevice = 0; Mutation = $null; FailureRecords = @() }
        $view = Get-TpmBepInExFailureView -Result $result
        @($view.Needs) | Should -Contain 'This game is inside your source folder, so TeknoParrot Manager left it alone (1 game).'
        $view.Next | Should -Match 'Move the game out of your source folder'
        $view.Next | Should -Not -Match 'try again'
    }

    It 'does not offer repair-reset any more: no R choice, no reset variable, no always-refused throw' {
        # Mutation: bring the R choice back -> the user picks a reset that is refused only after download and staging.
        $text = $script:F110Functions['Invoke-BepInExUpdateCheckLegacy'].Extent.Text
        $text | Should -Match "-Choices @\('Y', 'E', 'B', 'N'\)"
        $text | Should -Not -Match "-Choices @\('Y', 'R'"
        $code = (($text -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
        $code | Should -Not -Match '(?i)repair.?reset|repairReset|RepairRequired'
    }

    It 'waits for one Enter after a successful or no-change BepInEx run, before the menu is drawn again' {
        # Mutation: remove the acknowledgement from either branch -> the menu redraw erases the result.
        $block = $script:F110Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq '$mode -eq "BepInExUpdate"'
        }, $true)
        @($block).Count | Should -Be 1
        $inner = @($block[0].FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            @($n.Clauses | Where-Object { $_.Item1.Extent.Text -match "Outcome -eq 'NO_OP'" }).Count -gt 0
        }, $true))
        $inner.Count | Should -BeGreaterThan 0
        $clauses = @($inner[0].Clauses)
        $noOp = @($clauses | Where-Object { $_.Item1.Extent.Text -match "NO_OP" })[0]
        $succeeded = @($clauses | Where-Object { $_.Item1.Extent.Text -match "'SUCCEEDED'" })[0]
        foreach ($clause in @($noOp, $succeeded)) {
            $clause | Should -Not -BeNullOrEmpty
            $waits = @($clause.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Read-HostSafe' }, $true))
            $waits.Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'FIX110B S-11 the real run after a preview keeps what the preview used' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
    }

    It 'hands the Main selection, the Supplementary selection and the repair scope to the re-entry when Y is chosen' {
        # Mutation: set only pendingApplyMode/pendingApplyForce (the old Y branch) -> the next run starts without the selection and the scope.
        $block = Get-F110TopLevelIf -ConditionText '$applyNow -eq "Y"' -BodyContains 'PreviewMode'
        $out = Invoke-F110Block -Text $block -Variables @{ applyNow = 'Y'; mode = 'AutoSync'; autoSyncTargetGames = @('CodeA'); onlySyncList = @('MainOne'); onlySyncListSupp = @('SuppOne'); pendingApplyMode = $null; pendingApplyForce = $false; pendingAutoSyncGames = $null; pendingAutoSyncSelection = $null } -Outputs @('pendingApplyMode', 'pendingApplyForce', 'pendingAutoSyncGames', 'pendingAutoSyncSelection')
        $out.pendingApplyMode | Should -BeExactly 'AutoSync'
        $out.pendingApplyForce | Should -BeTrue
        @($out.pendingAutoSyncGames) | Should -Be @('CodeA')
        @($out.pendingAutoSyncSelection.Main) | Should -Be @('MainOne')
        @($out.pendingAutoSyncSelection.Supp) | Should -Be @('SuppOne')
    }

    It 'turns the carried selection into the re-entry state and forgets it afterwards' {
        # Mutation: leave pendingAutoSyncSelection set after the re-entry -> a later ordinary run inherits it.
        $block = Get-F110TopLevelIf -ConditionText '$pendingApplyMode' -BodyContains 'autoSyncSelection'
        $selection = [pscustomobject]@{ Main = @('MainOne'); Supp = @('SuppOne') }
        $out = Invoke-F110Block -Text $block -Variables @{ pendingApplyMode = 'AutoSync'; pendingAutoSyncGames = @('CodeA'); pendingAutoSyncSelection = $selection; pendingReShadeAction = 'Select'; pendingApplyForce = $true; autoSyncSelection = $null } -Outputs @('mode', 'autoSyncTargetGames', 'autoSyncSelection', 'pendingAutoSyncSelection', 'forceRealApply')
        $out.mode | Should -BeExactly 'AutoSync'
        @($out.autoSyncTargetGames) | Should -Be @('CodeA')
        @($out.autoSyncSelection.Main) | Should -Be @('MainOne')
        @($out.autoSyncSelection.Supp) | Should -Be @('SuppOne')
        $out.pendingAutoSyncSelection | Should -BeNullOrEmpty
        $out.forceRealApply | Should -BeTrue
    }

    It 'restores the preview selection, and a null Supplementary choice stays null (skipped), not "all"' {
        # Mutation: default a missing Supplementary list to all games on the re-entry -> the real run applies games the preview never showed.
        $restore = Get-F110TopLevelIf -ConditionText '$autoSyncSelection'
        $default = Get-F110TopLevelIf -ConditionText '$suppValid -and -not $combinedPickerRan -and -not $autoSyncSelection -and $null -eq $onlySyncListSupp'
        $selection = [pscustomobject]@{ Main = @('MainOne'); Supp = $null }
        $out = Invoke-F110Block -Text ($restore + "`r`n" + $default) -Variables @{ autoSyncSelection = $selection; suppValid = $true; combinedPickerRan = $false; onlySyncListSupp = $null; onlySyncList = @('StaleChoice'); configuredOnlySyncList = @() } -Outputs @('onlySyncList', 'onlySyncListSupp')
        @($out.onlySyncList) | Should -Be @('MainOne')
        ($null -eq $out.onlySyncListSupp) | Should -BeTrue
        $specific = [pscustomobject]@{ Main = @(); Supp = @('SuppOne') }
        $out = Invoke-F110Block -Text ($restore + "`r`n" + $default) -Variables @{ autoSyncSelection = $specific; suppValid = $true; combinedPickerRan = $false; onlySyncListSupp = $null; onlySyncList = @('StaleChoice'); configuredOnlySyncList = @() } -Outputs @('onlySyncList', 'onlySyncListSupp')
        @($out.onlySyncList).Count | Should -Be 0
        @($out.onlySyncListSupp) | Should -Be @('SuppOne')
    }

    It 'drops a Supplementary selection whose folder is no longer valid' {
        # Mutation: restore the Supplementary list without checking suppValid -> a vanished folder is still processed.
        $restore = Get-F110TopLevelIf -ConditionText '$autoSyncSelection'
        $selection = [pscustomobject]@{ Main = @('MainOne'); Supp = @('SuppOne') }
        $out = Invoke-F110Block -Text $restore -Variables @{ autoSyncSelection = $selection; suppValid = $false; onlySyncListSupp = $null; onlySyncList = @(); configuredOnlySyncList = @() } -Outputs @('onlySyncListSupp')
        ($null -eq $out.onlySyncListSupp) | Should -BeTrue
    }

    It 'starts an ordinary run from the overrides whitelist, not from a choice made in an earlier run' {
        # Mutation: remove the reset (the old behavior) -> an earlier picker answer silently decides the next run and the picker is skipped.
        $restore = Get-F110TopLevelIf -ConditionText '$autoSyncSelection'
        $out = Invoke-F110Block -Text $restore -Variables @{ autoSyncSelection = $null; suppValid = $true; onlySyncListSupp = @('OldSupp'); onlySyncList = @('OldMain'); configuredOnlySyncList = @('FromOverrides') } -Outputs @('onlySyncList')
        @($out.onlySyncList) | Should -Be @('FromOverrides')
    }

    It 'does not run the picker again when the preview selection is carried (even an empty "all" selection)' {
        # Mutation: drop "-not $autoSyncSelection" from the picker guard -> the user is asked again and the choice can differ from the preview.
        $guard = Get-F110TopLevelIf -ConditionText '$onlySyncList.Count -eq 0 -and -not $scopedHealthRepair -and -not $autoSyncSelection'
        $selection = [pscustomobject]@{ Main = @(); Supp = $null }
        $out = Invoke-F110Block -Text $guard -Variables @{ autoSyncSelection = $selection; onlySyncList = @(); scopedHealthRepair = $false; Unattended = $true; suppValid = $false; zipSource = 'x'; gamesInstallFolder = 'y'; datIndex = @{}; userProfilesDir = 'z'; autoSyncTargetGames = $null; combinedPickerRan = $false } -Outputs @('onlySyncList', 'combinedPickerRan')
        @($out.onlySyncList).Count | Should -Be 0
        Should -Invoke Write-Log -Times 0 -Exactly
        $fresh = Invoke-F110Block -Text $guard -Variables @{ autoSyncSelection = $null; onlySyncList = @(); scopedHealthRepair = $false; Unattended = $true; suppValid = $false; zipSource = 'x'; gamesInstallFolder = 'y'; datIndex = @{}; userProfilesDir = 'z'; autoSyncTargetGames = $null; combinedPickerRan = $false } -Outputs @('onlySyncList')
        Should -Invoke Write-Log -Times 1 -Exactly -ParameterFilter { [string]$msg -match 'game selection = all' }
    }

    It 'offers the preview details before the real changes are authorized, shows them once, and then asks Y or N' {
        # Mutation: ask Y/N without the D choice (the old behavior) -> the user authorizes real changes without being able to read the preview details.
        $block = Get-F110TopLevelIf -ConditionText '$dryRunActive -and -not $Unattended' -BodyContains 'PreviewMode'
        $script:F110Choices = New-Object System.Collections.Generic.List[string]
        $script:F110Answers = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in @('D', 'Y')) { $script:F110Answers.Enqueue($answer) }
        $script:F110Shown = 0
        Mock Get-TpmDeferredDetails { @([pscustomobject]@{ Blocks = @(@{ Heading = 'Game A'; Lines = @('x') }); Note = '' }) }
        Mock Show-TpmDeferredDetails { $script:F110Shown++ }
        Mock Read-TpmChoice { [void]$script:F110Choices.Add(($Choices -join ',')); $script:F110Answers.Dequeue() }
        $out = Invoke-F110Block -Text $block -Variables @{ dryRunActive = $true; Unattended = $false; mode = 'AutoSync'; autoSyncTargetGames = $null; onlySyncList = @('MainOne'); onlySyncListSupp = $null; pendingApplyMode = $null; pendingApplyForce = $false; pendingAutoSyncGames = $null; pendingAutoSyncSelection = $null } -Outputs @('pendingApplyMode', 'pendingApplyForce')
        @($script:F110Choices) | Should -Be @('Y,N,D', 'Y,N')
        $script:F110Shown | Should -Be 1
        $out.pendingApplyMode | Should -BeExactly 'AutoSync'
        $out.pendingApplyForce | Should -BeTrue
    }

    It 'does not offer D when the preview kept no details' {
        # Mutation: always offer D -> a choice that shows nothing.
        $block = Get-F110TopLevelIf -ConditionText '$dryRunActive -and -not $Unattended' -BodyContains 'PreviewMode'
        $script:F110Choices = New-Object System.Collections.Generic.List[string]
        Mock Get-TpmDeferredDetails { @() }
        Mock Show-TpmDeferredDetails { throw 'no details were kept' }
        Mock Read-TpmChoice { [void]$script:F110Choices.Add(($Choices -join ',')); 'N' }
        $out = Invoke-F110Block -Text $block -Variables @{ dryRunActive = $true; Unattended = $false; mode = 'AutoSync'; autoSyncTargetGames = $null; onlySyncList = @(); onlySyncListSupp = $null; pendingApplyMode = $null; pendingApplyForce = $false; pendingAutoSyncGames = $null; pendingAutoSyncSelection = $null } -Outputs @('pendingApplyMode')
        @($script:F110Choices) | Should -Be @('Y,N')
        $out.pendingApplyMode | Should -BeNullOrEmpty
    }

    It 'shows the kept details and forgets them' {
        # Mutation: leave the kept details in place -> the final return prompt offers the same details a second time.
        Mock Clear-TpmDeferredDetails { $script:F110Cleared = $true }
        $script:F110Cleared = $false
        $script:F110Blocks = New-Object System.Collections.Generic.List[string]
        Mock Show-TpmDetailBlocks { [void]$script:F110Blocks.Add([string]$Note) }
        Show-TpmDeferredDetails -Entries @([pscustomobject]@{ Blocks = @(@{ Heading = 'A'; Lines = @('x') }); Note = 'Note one.' }, [pscustomobject]@{ Blocks = @(); Note = 'Note two.' })
        $script:F110Cleared | Should -BeTrue
        @($script:F110Blocks) | Should -Be @('Note one.', 'Note two.')
    }
}

Describe 'FIX110B S-20 one place for the TeknoParrotUI troubleshooting file: the managed Reports folder' {
    BeforeAll {
        $script:F110IntakeName = 'TeknoParrot-Manager-TeknoParrotUI-Troubleshooting.txt'
    }

    It 'no longer treats the troubleshooting file beside the script as owned state to move at startup' {
        # Mutation: put the file name back in the legacy list -> a copy beside the script is moved, and a second copy blocks startup as an occupied destination.
        $scriptRoot = Join-Path $TestDrive 'program-folder'
        [void][System.IO.Directory]::CreateDirectory($scriptRoot)
        [System.IO.File]::WriteAllText((Join-Path $scriptRoot $script:F110IntakeName), 'tpui')
        [System.IO.File]::WriteAllText((Join-Path $scriptRoot 'TeknoParrot-Manager-ActionItems.txt'), 'items')
        $names = @(Get-TpmLegacyOwnedItems -ScriptRoot $scriptRoot | ForEach-Object { [string]$_.Name })
        $names | Should -Contain 'TeknoParrot-Manager-ActionItems.txt'
        $names | Should -Not -Contain $script:F110IntakeName
    }

    It 'the support package reads the file from the managed Reports folder only' {
        # Mutation: read it from a second place again -> the instruction, the migration and the package disagree.
        $text = $script:F110Functions['New-TpmSupportPackage'].Extent.Text
        $joins = @([regex]::Matches($text, "Join-Path \`$ScriptRoot '([^']*TeknoParrotUI-Troubleshooting\.txt)'"))
        $joins.Count | Should -Be 1
        $joins[0].Groups[1].Value | Should -BeExactly ('Reports\' + $script:F110IntakeName)
    }

    It 'the support menu steps name the Reports folder, with the exact path when it is known' {
        # Mutation: go back to "in the same folder as TeknoParrot-Manager.ps1" -> the file is saved where the package does not look.
        $withPath = (@(Get-TpmSupportPackageHelpBlocks -ReportsFolder 'D:\TeknoParrot\TeknoParrotManager\Reports') | ForEach-Object { @($_.Lines) }) -join "`n"
        $withPath | Should -Match ([regex]::Escape('Where to save it: D:\TeknoParrot\TeknoParrotManager\Reports'))
        $withPath | Should -Match ([regex]::Escape($script:F110IntakeName))
        $withPath | Should -Not -Match 'same folder as'
        $without = (@(Get-TpmSupportPackageHelpBlocks) | ForEach-Object { @($_.Lines) }) -join "`n"
        $without | Should -Match 'Reports folder inside the TeknoParrotManager folder'
    }

    It 'every product text that names the file also names the Reports folder' {
        # Mutation: reword one product line back to "beside the TPM script" -> that line contradicts the others.
        $strings = @($script:F110Ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -like '*TeknoParrotUI-Troubleshooting.txt*'
        }, $true) | ForEach-Object { [string]$_.Value })
        $strings.Count | Should -BeGreaterThan 2
        foreach ($value in $strings) {
            if ($value -like 'Step 3:*') { continue }
            $value | Should -Match 'Reports' -Because $value
            $value | Should -Not -Match '(?i)beside the (tpm )?script|same folder as'
        }
    }

    It 'the guides say the same, and the developer note no longer has the intake file name' {
        # Mutation: leave one guide saying "beside this script" -> users save the file where the package does not look.
        foreach ($guide in @('TeknoParrot-Manager-README.txt', 'TeknoParrot-Manager-QuickStart.txt', 'docs\USER-GUIDE.md')) {
            $guideText = [System.IO.File]::ReadAllText((Join-Path $script:F110Root $guide))
            $at = $guideText.IndexOf($script:F110IntakeName)
            $at | Should -BeGreaterThan 0 -Because $guide
            $window = $guideText.Substring([Math]::Max(0, $at - 400), [Math]::Min(900, $guideText.Length - [Math]::Max(0, $at - 400)))
            $window | Should -Match 'TeknoParrotManager\\Reports' -Because $guide
            $window | Should -Not -Match '(?i)beside (this|the TeknoParrot Manager) script' -Because $guide
        }
        Test-Path -LiteralPath (Join-Path $script:F110Root $script:F110IntakeName) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:F110Root 'docs\SUPPORT-PACKAGE-UX-CAPTURE-NOTE.txt') | Should -BeTrue
    }
}

Describe 'FIX110B N-1 plain product names in ordinary output' {
    It 'no longer says bare TPM in the changed result sentences' {
        # Mutation: put "TPM" back into one of these sentences -> ordinary output uses the internal abbreviation again.
        $strings = @($script:F110Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { [string]$_.Value })
        foreach ($old in @(
            'TPM may have changed something', 'TPM could not finish cleanup', 'TPM could not prepare', 'TPM found an incomplete previous game',
            'TPM restored the previous manager file', 'TPM could not verify which manager file', 'TPM could not complete all cleanup',
            'TPM stopped at a safety check'
        )) {
            @($strings | Where-Object { $_ -like ('*' + $old + '*') }).Count | Should -Be 0 -Because $old
        }
        @($strings | Where-Object { $_ -like '*TeknoParrot Manager may have changed something, but the final state could not be verified.*' }).Count | Should -Be 1
    }

    It 'says nothing about the PCSX2 contract on the ordinary line and keeps the reason in the log' {
        # Mutation: print the raw reason ("emulator contract ... cursor_path") on the screen again.
        $strings = @($script:F110Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { [string]$_.Value })
        @($strings | Where-Object { $_ -like '*NOTE: Skipping PCSX2.ini cursor_path write*' }).Count | Should -Be 0
        @($strings | Where-Object { $_ -like '*The PCSX2 cursor setting was left alone because PCSX2 manages it itself. The log says why.*' }).Count | Should -Be 1
        $script:F110Functions.Values | Where-Object { $_.Extent.Text -match 'Crosshairs: skipped PCSX2\.ini cursor_path write' } | Should -Not -BeNullOrEmpty
    }

    It 'CPS3 result lines have no raw outcome code, and the code goes to the log' {
        # Mutation: print "({0})" with the outcome again -> ordinary output shows ROLLED_BACK_VERIFIED / CLEANUP_RESIDUE / ACTION_REQUIRED.
        $profiles = Join-Path $TestDrive 'cps-profiles'
        [void][System.IO.Directory]::CreateDirectory($profiles)
        [System.IO.File]::WriteAllText((Join-Path $profiles 'cps_one.xml'), '<GameProfile/>')
        $script:F110Host = New-Object System.Collections.Generic.List[string]
        $script:F110Log = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:F110Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F110Host.Add([string]($Object -join ' ')) }
        Mock Read-TpmYesNo { 'Y' }
        Mock Read-TpmChoice { 'F' }
        Mock Read-PathWithBrowse { 'X:\fixture-source' }
        foreach ($outcome in @('FAILED_BEFORE_MUTATION', 'ROLLED_BACK_VERIFIED', 'CLEANUP_RESIDUE', 'ACTION_REQUIRED')) {
            $script:F110Host.Clear(); $script:F110Log.Clear()
            $script:F110Cps3Result = [pscustomobject]@{ Outcome = $outcome; Summary = 'Fixture summary.'; Conflicts = @(); Installed = @(); Replaced = @(); AlreadyPresent = @(); PreservedExisting = @(); Missing = @(); Extra = @(); Unsafe = @(); Ambiguous = @(); Mismatched = @(); Blocked = @(); Transaction = $null }
            Mock Invoke-TpmProgressGroup { $script:F110Cps3Result }
            [void](Invoke-TpmCps3SupplementaryOffer -TpRoot (Join-Path $TestDrive 'tp') -UserProfilesDir $profiles)
            $shown = @($script:F110Host) -join "`n"
            $shown | Should -Match 'Fixture summary\.' -Because $outcome
            $shown | Should -Not -Match ('(?i)' + [regex]::Escape($outcome)) -Because $outcome
            (@($script:F110Log) -join "`n") | Should -Match ('CPS3 supplementary: outcome=' + $outcome) -Because $outcome
        }
    }
}
