#Requires -Module Pester

# FIX112: fixes from the final whole-product review that live in TeknoParrot-Manager.ps1.
#   B1  an AutoSync run's results are not reused by a later "Register only" pass in the same session
#   B2  a good PostgreSQL restore or reinitialize keeps the saved copy of the data it replaced, and says so
#   B3  a leftover-temp-folder problem after the ReShade files are in place is a success with residue (the undo receipt stays)
#   SF  failed dropdb, rollback encoding, newer-file swap, restore point removal, empty re-read plan,
#       database name check, hidden files in the AutoSync backup, XML save checks, dead ReShade code, redaction, unattended prompts
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# Everything lives under TestDrive with synthetic files. Every external PostgreSQL call is mocked.
# Each It names the product change that makes it fail.
# What this CANNOT prove: a real PostgreSQL server (the encoding query and dropdb are mocked), the menu loop itself (B1 and the
# unattended prompts are checked on the parsed script, because the loop is top-level product code that cannot be dot-sourced),
# and a power loss during Save-Xml (the flush is not observable from a test).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:F112Ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX112 tests could not parse the production script.' }
    $functionText = @($script:F112Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-fix112-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix112.log'
    $script:logWarnShown = $false
    $script:F112Utf8 = New-Object System.Text.UTF8Encoding $false
    $script:F112RealFileState = (Get-Command -Name Get-TpmRestorePointFileState -CommandType Function).ScriptBlock
    $script:F112RealNewReceipt = (Get-Command -Name New-TpmReShadeUndoReceipt -CommandType Function).ScriptBlock

    function New-F112Folder {
        param([string]$Name = 'f112')
        $folder = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($folder)
        return $folder
    }
    function Set-F112Text {
        param([string]$Path, [string]$Text)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text, $script:F112Utf8)
    }
    function Get-F112Bytes {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '<absent>' }
        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }
    function New-F112Receipt {
        param([string]$Database, [string]$ItemId, [bool]$Succeeded = $true)
        return [pscustomobject]@{
            ItemId = $ItemId; Database = $Database; BackupFile = 'C:\fixture\bundled.backup'; BackupSha256 = 'AA'; RollbackDumpPath = ''
            RollbackDumpSha256 = ''; PreStateExists = $true; Encoding = 'UTF8'; MutationAttempted = $true; CreateOwnedForRollback = $true
            Changed = $true; Succeeded = $Succeeded; FailureStage = $(if ($Succeeded) { $null } else { 'Restore' })
            Error = $(if ($Succeeded) { $null } else { 'pg_restore failed' }); PostFailureState = $null
            FinalVerification = $null; Commands = @(); DropReceipt = $null; RollbackAttempted = $false; RollbackVerified = $false
            RollbackError = $null; RollbackCommands = @(); RollbackDropReceipt = $null
        }
    }
    function Invoke-F112Adopt {
        param([string]$FaultStage = '', [switch]$LongFolder)
        $root = Join-Path $script:F112Games 'Adopt'
        # A folder path over 259 characters; made with the \\?\ form so the test itself works with Windows long paths off.
        $io = ''
        if ($LongFolder) { $io = '\\?\'; while ($root.Length -lt 280) { $root = Join-Path $root 'a-long-folder-name-for-testing' } }
        [void][System.IO.Directory]::CreateDirectory($io + $root)
        $gameExe = Join-Path $root 'game.exe'; [System.IO.File]::WriteAllText($io + $gameExe, 'MZ-test-game')
        $sourceDll = Join-Path $script:F112Games 'ReShade64.dll'; [System.IO.File]::WriteAllText($sourceDll, 'MZ-tpm-reshade-runtime')
        $hook = Join-Path $root 'dxgi.dll'; [System.IO.File]::WriteAllBytes($io + $hook, [byte[]](0x4D, 0x5A, 0x00, 0xFF, 0x10, 0x20, 0x7F))
        $script:F112HookBefore = if ($LongFolder) { [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($io + $hook)) } else { Get-F112Bytes $hook }
        $script:F112Hook = $hook
        $script:F112Ownership = Join-Path $script:F112State 'Deployments\adopt.json'
        $request = Get-TpmReShadeSetupUndoRequest -GameId 'Adopt' -GameName 'Adopt Game' -Status 'UnknownUserOwnedConflict' -Manifest $null -ProfileId 'Original'
        $request.StateRoot = $script:F112State
        $arguments = @{
            ProfileDefinition = (Get-TpmReShadeProfile -ProfileId Original); GamePath = $gameExe; Doc = ([xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>')
            SourceDll = $sourceDll; CacheRoot = (Join-Path $root 'cache'); OwnershipPath = $script:F112Ownership; CanonicalPreset = $true
            AllowUserOwnedOverwrite = $true; UndoReceipt = $request
        }
        if ($FaultStage) { $arguments['FaultStage'] = $FaultStage }
        return (Install-TpmReShadeProfileDeployment @arguments)
    }

}

Describe 'FIX112 B1: the menu loop starts every pass without the previous AutoSync results' {
    It 'resets the AutoSync result variables at the top of the menu loop, next to the other per-pass resets' {
        # Mutation: remove the reset of $sync / $syncSupp from the loop top -> a later Register only pass scopes its registration to the last AutoSync run's games.
        $loop = @($script:F112Ast.FindAll({
            $node = $args[0]
            $node -is [System.Management.Automation.Language.WhileStatementAst] -and $node.Condition.Extent.Text -eq '$true' -and
                @($node.Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$autoSyncSelection' }).Count -gt 0
        }, $true))[0]
        $loop | Should -Not -BeNullOrEmpty
        $resets = @($loop.Body.Statements | Where-Object { $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Right.Extent.Text -eq '$null' } | ForEach-Object { $_.Left.Extent.Text })
        $resets | Should -Contain '$sync'
        $resets | Should -Contain '$syncSupp'
    }
}

Describe 'FIX112 B2: a good PostgreSQL restore keeps the saved copy of the data it replaced' {
    BeforeEach {
        # The real restore takes the machine-wide PostgreSQL lock for up to 2 s; a private name keeps another test process on this PC from failing it.
        $script:PostgresRecoveryLockName = 'Local\TpmFix112Test-' + [guid]::NewGuid().ToString('N')
        $script:F112Log = New-Object System.Collections.Generic.List[string]
        $script:F112Screen = New-Object System.Collections.Generic.List[string]
        $script:F112Receipts = @{}
        $script:F112DbExists = $true
        $script:F112Root = $null
        $script:F112Items = @([pscustomobject]@{ ItemId = 'item-1'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; BackupSha256 = 'AA'; BackupLength = 5; Encoding = 'UTF8' })
        Mock Write-Log { [void]$script:F112Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F112Screen.Add([string]$Object) }
        Mock Get-PostgresRestoreBackupPlan { [pscustomobject]@{ Valid = $true; Items = @($script:F112Items); SelectedBackupRoot = 'C:\fixture'; FailureCode = $null; Reason = $null } }
        Mock Test-Postgres83RestoreToolSet { [pscustomobject]@{ Verified = $true; Tools = @(); Reason = $null } }
        Mock Test-PostgresPassword { $true }
        Mock Get-TpmFileState { [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $false; Length = 5; Sha256 = 'AA' } }
        Mock Invoke-Postgres83RestoreCommandChecked {
            if ($ToolName -eq 'pg_dump.exe') {
                $index = [array]::IndexOf(@($Arguments), '-f')
                [System.IO.File]::WriteAllText([string]$Arguments[$index + 1], 'saved copy of the old data')
            }
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true }
        }
        Mock New-PostgresRestoreEvidenceRoot {
            $path = Join-Path $TestDrive ('evidence-' + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($path)
            $script:F112Root = $path
            $path
        }
        Mock Get-PostgresDatabaseState { [pscustomobject]@{ Verified = $true; Exists = $script:F112DbExists } }
        Mock Invoke-Postgres83RestoreDatabase { $script:F112DbExists = $true; $script:F112Receipts[[string]$Item.Database] }
        Mock Restore-Postgres83DatabaseFromReceipt { [pscustomobject]@{ RollbackVerified = $true; ItemId = $Receipt.ItemId; Database = $Receipt.Database; RollbackError = $null } }
        Mock ConvertTo-PostgresRedactedText { [string]$Text }
    }

    It 'leaves the saved copy of the old data in the recovery folder after a verified restore, and reports where' {
        # Mutation: remove the transaction root after SUCCEEDED (the old behavior) -> the dump of the replaced data is deleted and nothing says so.
        $script:F112Receipts['GameDB19'] = New-F112Receipt -Database 'GameDB19' -ItemId 'item-1'
        $result = Invoke-PostgresRestoreTransaction -BackupFiles @([pscustomobject]@{ BackupFile = 'C:\fixture\one.backup'; Database = 'GameDB19' }) -SuperPasswordPlain 'pw'
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $kept = @($result.TechnicalDetails.KeptDatabaseBackups)
        $kept.Count | Should -Be 1
        $kept[0] | Should -BeLike '*GameDB19.current.backup'
        [System.IO.File]::ReadAllText($kept[0]) | Should -BeExactly 'saved copy of the old data'
        (@($script:F112Log) -join "`n") | Should -Match 'kept the saved copy of the replaced data'
        @($result.Cleanup.ResiduePaths).Count | Should -Be 0 -Because 'a copy kept on purpose is not cleanup residue'
    }

    It 'removes the saved copy when the restore is rolled back, because the original data is back in place' {
        # Mutation: keep the root for every outcome -> every failed restore leaves a dump behind.
        $script:F112Items = @(
            [pscustomobject]@{ ItemId = 'item-1'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; BackupSha256 = 'AA'; BackupLength = 5; Encoding = 'UTF8' }
            [pscustomobject]@{ ItemId = 'item-2'; Database = 'GameDB20'; BackupFile = 'C:\fixture\two.backup'; BackupSha256 = 'AA'; BackupLength = 5; Encoding = 'UTF8' }
        )
        $script:F112Receipts['GameDB19'] = New-F112Receipt -Database 'GameDB19' -ItemId 'item-1'
        $script:F112Receipts['GameDB20'] = New-F112Receipt -Database 'GameDB20' -ItemId 'item-2' -Succeeded $false
        $files = @([pscustomobject]@{ BackupFile = 'C:\fixture\one.backup'; Database = 'GameDB19' }, [pscustomobject]@{ BackupFile = 'C:\fixture\two.backup'; Database = 'GameDB20' })
        $result = Invoke-PostgresRestoreTransaction -BackupFiles $files -SuperPasswordPlain 'pw'
        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        $result.Summary | Should -BeExactly 'The restore did not finish. Your old data was put back and checked.'
        @($result.TechnicalDetails.KeptDatabaseBackups).Count | Should -Be 0
        Test-Path -LiteralPath $script:F112Root | Should -BeFalse
    }

    It 'has nothing to keep when the database did not exist before, and removes its working folder' {
        # Mutation: keep the root whenever the restore succeeded -> an empty recovery folder is left for every first-time restore.
        $script:F112DbExists = $false
        $script:F112Receipts['GameDB19'] = New-F112Receipt -Database 'GameDB19' -ItemId 'item-1'
        $result = Invoke-PostgresRestoreTransaction -BackupFiles @([pscustomobject]@{ BackupFile = 'C:\fixture\one.backup'; Database = 'GameDB19' }) -SuperPasswordPlain 'pw'
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($result.TechnicalDetails.KeptDatabaseBackups).Count | Should -Be 0
        Test-Path -LiteralPath $script:F112Root | Should -BeFalse
    }

    It 'tells the user in plain words that the saved copy was kept and where the folder is' {
        # Mutation: leave the notice out of the success screens -> the screen says only "completed" while a copy of the old data sits on disk.
        $path = Join-Path (Join-Path $TestDrive 'Restore-x\CurrentDatabases') 'GameDB19.current.backup'
        Write-PostgresKeptDatabaseBackupNotice -Paths @($path)
        $screen = @($script:F112Screen) -join "`n"
        $screen | Should -Match 'has kept that saved copy'
        $screen | Should -Match 'does not delete it'
        $screen | Should -Match ([regex]::Escape((Split-Path -Parent $path)))
        $script:F112Screen.Clear()
        Write-PostgresKeptDatabaseBackupNotice -Paths @()
        $script:F112Screen.Count | Should -Be 0
    }

    It 'shows the kept-copy notice with the reinitialize success line' {
        # Mutation: Write-PostgresReinitializeSuccess ignores KeptDatabaseBackups -> a reinitialize that discarded nothing says nothing about the saved copy.
        $path = Join-Path (Join-Path $TestDrive 'Restore-y\CurrentDatabases') 'GameDB19.current.backup'
        $result = [pscustomobject]@{ Warnings = @(); TechnicalDetails = [pscustomobject]@{ KeptDatabaseBackups = @($path) } }
        Write-PostgresReinitializeSuccess -Result $result
        $screen = @($script:F112Screen) -join "`n"
        $screen | Should -Match 'rebuilt and checked'
        $screen | Should -Match 'has kept that saved copy'
    }
}

Describe 'FIX112 B3: a cleanup problem after the ReShade files are in place is a success with residue' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        Mock Get-ExeArchitecture { 'x64' }
        $script:F112State = New-F112Folder 'state'
        $script:F112Games = New-F112Folder 'games'
        $script:F112ReceiptFolder = $null
        Mock New-TpmReShadeUndoReceipt {
            param($Request, $Paths, $Roots)
            $made = & $script:F112RealNewReceipt -Request $Request -Paths $Paths -Roots $Roots
            $script:F112ReceiptFolder = [string]$made.Folder
            $made
        }
        # Only the removal of the promote's own backup folder fails; every other delete is the real one.
        Mock Remove-Item {
            param($LiteralPath, $Recurse, $Force, $ErrorAction, $Path)
            if ($LiteralPath -like '*.tpm-rollback-backup') { throw 'simulated rollback-backup cleanup failure' }
            if (Test-Path -LiteralPath $LiteralPath -PathType Container) { [System.IO.Directory]::Delete($LiteralPath, [bool]$Recurse) }
            elseif (Test-Path -LiteralPath $LiteralPath) { [System.IO.File]::Delete($LiteralPath) }
        }
    }

    It 'reports success with the residue and keeps the undo receipt when only the backup folder could not be removed' {
        # Mutation: treat "CLEANUP FAILED" like a rolled-back failure (the old catch) -> Succeeded=$false, State=ROLLED_BACK and the receipt, the only copy of the user's own ReShade files, is deleted.
        $result = Invoke-F112Adopt
        $result.Succeeded | Should -BeTrue -Because ($result | ConvertTo-Json -Depth 3)
        $result.State | Should -BeExactly 'INSTALLED'
        $result.CleanupResidue | Should -Match 'CLEANUP FAILED AFTER VERIFIED PROMOTION'
        (Get-F112Bytes $script:F112Hook) | Should -Not -BeExactly $script:F112HookBefore -Because 'the ReShade files are in place'
        Test-Path -LiteralPath $script:F112Ownership -PathType Leaf | Should -BeTrue
        $result.UndoReceipt | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath ([string]$result.UndoReceipt.Folder) -PathType Container | Should -BeTrue -Because 'the receipt holds the only saved copy of the files as they were'
    }

    It 'still reports a failure and drops the receipt when the promotion was rolled back and its cleanup failed too' {
        # Mutation: treat every "CLEANUP FAILED" as a success -> a rolled-back install is reported as installed.
        $result = Invoke-F112Adopt -FaultStage 'BeforeCommit'
        $result.Succeeded | Should -BeFalse
        $result.State | Should -BeExactly 'ROLLED_BACK'
        (Get-F112Bytes $script:F112Hook) | Should -BeExactly $script:F112HookBefore -Because 'the rollback put the original files back'
        $script:F112ReceiptFolder | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:F112ReceiptFolder | Should -BeFalse -Because 'a verified rollback leaves nothing to undo'
    }

    It 'refuses a game folder over 259 characters in plain words, before it changes anything' {
        # Who gets hurt: a user whose game is in a very deep folder got a technical move error and "may be inconsistent". Mutation: drop the length check in the promote -> the move throws a raw error and the reason is PROFILE_DEPLOYMENT_FAILED.
        try {
            $result = Invoke-F112Adopt -LongFolder
            $result.Succeeded | Should -BeFalse
            $result.Reason | Should -BeExactly 'PATH_TOO_LONG'
            $result.Error | Should -Match 'too long'
            $result.Error | Should -Match 'Nothing was changed'
            $result.Error | Should -Not -Match 'inconsistent'
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes('\\?\' + $script:F112Hook)) | Should -BeExactly $script:F112HookBefore -Because 'the existing file was not touched'
            Test-Path -LiteralPath $script:F112Ownership -PathType Leaf | Should -BeFalse
        } finally {
            # Windows PowerShell 5.1 cannot delete the deep folder through a normal path, so Pester's TestDrive cleanup would fail on it.
            $adoptRoot = '\\?\' + (Join-Path $script:F112Games 'Adopt')
            if ([System.IO.Directory]::Exists($adoptRoot)) { [System.IO.Directory]::Delete($adoptRoot, $true) }
        }
    }

    It 'gives the same plain reason when the game file over 259 characters is not there to be read' {
        # Who gets hurt: on a PC with Windows long paths off, a game in a very deep folder was told "invalid game path" instead of "path too long". Mutation: drop the early length check -> a different reason comes back.
        $root = Join-Path $script:F112Games 'Ghost'
        while ($root.Length -lt 280) { $root = Join-Path $root 'a-long-folder-name-for-testing' }
        $sourceDll = Join-Path $script:F112Games 'ReShade64.dll'; [System.IO.File]::WriteAllText($sourceDll, 'MZ-tpm-reshade-runtime')
        $result = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath (Join-Path $root 'game.exe') -Doc ([xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>') -SourceDll $sourceDll -CacheRoot (Join-Path $root 'cache') -OwnershipPath (Join-Path $script:F112State 'Deployments\ghost.json') -CanonicalPreset
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -BeExactly 'PATH_TOO_LONG'
        $result.Error | Should -Match 'Nothing was changed'
    }

    It 'marks the message of a cleanup after a good promotion differently from the cleanup after a rollback' {
        # Mutation: give both cleanup failures the same text -> the caller cannot tell a changed game from an unchanged one.
        $staging = New-F112Folder 'stage'
        $dest = New-F112Folder 'dest'
        Set-F112Text -Path (Join-Path $dest 'a.txt') -Text 'OLD'
        Set-F112Text -Path (Join-Path $staging 'a.txt') -Text 'NEW'
        $caught = $null
        try { Invoke-TpmTransactionalPromote -StagingDir $staging -DestDir $dest -FileNames @('a.txt') } catch { $caught = $_ }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -Match 'CLEANUP FAILED AFTER VERIFIED PROMOTION'
        [System.IO.File]::ReadAllText((Join-Path $dest 'a.txt')) | Should -BeExactly 'NEW'
    }
}

Describe 'FIX112 SF2 and SF3: a failed dropdb, and the rollback encoding' {
    BeforeEach {
        $script:F112Exists = $true
        $script:F112CreateArgs = $null
        Mock Write-Log {}
        Mock ConvertTo-PostgresRedactedText { [string]$Text }
        Mock Get-PostgresDatabaseState { [pscustomobject]@{ Verified = $true; Exists = $script:F112Exists } }
        Mock Get-TpmFileState { [pscustomobject]@{ Readable = $true; Exists = $true; IsDirectory = $false; Length = 5; Sha256 = 'AA' } }
        Mock Invoke-Postgres83RestoreCommandChecked {
            if ($ToolName -eq 'createdb.exe') { $script:F112CreateArgs = @($Arguments) }
            [pscustomobject]@{ ExitCode = 0; Succeeded = $true }
        }
    }

    It 'does not call a database changed when dropdb failed and the database is still there' {
        # Mutation: set Changed after a failed dropdb (the old line) -> rollback then refuses the untouched database and the run ends ACTION_REQUIRED.
        Mock Invoke-Postgres83DropDatabaseVerified { [pscustomobject]@{ Verified = $false; DropAttempted = $true; Error = 'dropdb failed: database in use' } }
        $item = [pscustomobject]@{ ItemId = 'item-1'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; BackupSha256 = 'AA'; Encoding = 'SQL_ASCII' }
        $preState = [pscustomobject]@{ Exists = $true; RollbackDumpPath = ''; RollbackDumpSha256 = ''; OriginalEncoding = 'LATIN1' }
        $receipt = Invoke-Postgres83RestoreDatabase -Item $item -PreState $preState -SuperPasswordPlain 'pw'
        $receipt.Succeeded | Should -BeFalse
        $receipt.FailureStage | Should -BeExactly 'Drop'
        $receipt.Changed | Should -BeFalse
        $receipt.RollbackEncoding | Should -BeExactly 'LATIN1'
    }

    It 'still calls a database changed when it is gone after a failed drop step' {
        # Mutation: never set Changed in the failure path -> a database that vanished is treated as untouched and never rolled back.
        Mock Invoke-Postgres83DropDatabaseVerified { $script:F112Exists = $false; [pscustomobject]@{ Verified = $false; DropAttempted = $true; Error = 'not verified absent' } }
        $item = [pscustomobject]@{ ItemId = 'item-1'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; BackupSha256 = 'AA'; Encoding = 'SQL_ASCII' }
        $preState = [pscustomobject]@{ Exists = $true; RollbackDumpPath = ''; RollbackDumpSha256 = '' }
        $receipt = Invoke-Postgres83RestoreDatabase -Item $item -PreState $preState -SuperPasswordPlain 'pw'
        $receipt.Changed | Should -BeTrue
    }

    It 'recreates the database with the encoding it had before, not the encoding the restore uses' {
        # Mutation: pass $Receipt.Encoding to createdb in the rollback (the old line) -> a database that was LATIN1 comes back as SQL_ASCII.
        Mock Invoke-Postgres83DropDatabaseVerified { [pscustomobject]@{ Verified = $true } }
        $receipt = New-F112Receipt -Database 'GameDB19' -ItemId 'item-1'
        $receipt.RollbackDumpPath = 'C:\fixture\current.backup'
        $receipt.RollbackDumpSha256 = 'AA'
        $receipt.Encoding = 'SQL_ASCII'
        $receipt | Add-Member -NotePropertyName RollbackEncoding -NotePropertyValue 'LATIN1' -Force
        $rolled = Restore-Postgres83DatabaseFromReceipt -Receipt $receipt -SuperPasswordPlain 'pw'
        $rolled.RollbackVerified | Should -BeTrue -Because ([string]$rolled.RollbackError)
        $script:F112CreateArgs[[array]::IndexOf($script:F112CreateArgs, '-E') + 1] | Should -BeExactly 'LATIN1'
    }

    It 'falls back to the restore encoding only when no original encoding was recorded' {
        # Mutation: fail the rollback when the encoding was not recorded -> receipts from before this change can no longer be rolled back.
        Mock Invoke-Postgres83DropDatabaseVerified { [pscustomobject]@{ Verified = $true } }
        $receipt = New-F112Receipt -Database 'GameDB19' -ItemId 'item-1'
        $receipt.RollbackDumpPath = 'C:\fixture\current.backup'
        $receipt.RollbackDumpSha256 = 'AA'
        $receipt.Encoding = 'SQL_ASCII'
        $rolled = Restore-Postgres83DatabaseFromReceipt -Receipt $receipt -SuperPasswordPlain 'pw'
        $rolled.RollbackVerified | Should -BeTrue
        $script:F112CreateArgs[[array]::IndexOf($script:F112CreateArgs, '-E') + 1] | Should -BeExactly 'SQL_ASCII'
    }

}

Describe 'FIX112 SF3: the encoding of an existing database is read, never guessed' {
    BeforeEach {
        Mock Write-Log {}
        $bin = New-F112Folder 'pgbin'
        Set-F112Text -Path (Join-Path $bin 'psql.exe') -Text 'fake'
        $script:PostgresBinDir = $bin
        $script:F112EncodingAnswer = 'LATIN1'
        Mock Invoke-PostgresNativeCommand {
            # FIX129: the fake runs the caller's -Interpret block on its text, like the real runner does.
            $text = if (($Arguments -join ' ') -match 'pg_encoding_to_char') { $script:F112EncodingAnswer } else { '1' }
            return (Add-FakePostgresInterpretation -Command ([pscustomobject]@{ Output = $text; ExitCode = 0 }) -Interpret $Interpret -InterpretContext $InterpretContext)
        }
    }

    It 'returns the encoding the catalog reports and nothing when the answer is not an encoding name' {
        # Mutation: return a default or the requested name when the query gives nothing usable -> the rollback recreates the database in an invented encoding.
        $state = Get-PostgresDatabaseState -DbName 'GameDB19' -SuperPasswordPlain 'pw'
        $state.Exists | Should -BeTrue
        $state.Verified | Should -BeTrue
        $state.Encoding | Should -BeExactly 'LATIN1'
        $script:F112EncodingAnswer = 'not an encoding; DROP'
        (Get-PostgresDatabaseState -DbName 'GameDB19' -SuperPasswordPlain 'pw').Encoding | Should -BeNullOrEmpty
    }
}

Describe 'FIX112 SF5: the file swap keeps the displaced bytes when it cannot read them' {
    BeforeEach {
        Mock Write-Log {}
        Mock Assert-TpmNoReparseWriteTarget {}
    }

    It 'does not delete the displaced file when reading it for the comparison fails' {
        # Mutation: clear $keepDisplaced before the displaced file is read (the old order) -> the finally block deletes bytes that were never compared and may be a newer save.
        $folder = New-F112Folder 'swap'
        $source = Join-Path $folder 'saved-copy.json'
        $target = Join-Path $folder 'target.json'
        Set-F112Text -Path $source -Text 'restored-bytes'
        Set-F112Text -Path $target -Text 'current-bytes'
        $sourceState = Get-TpmRestorePointFileState -Path $source
        $targetState = Get-TpmRestorePointFileState -Path $target
        Mock Get-TpmRestorePointFileState -ParameterFilter { $Path -like '*.tpm-replace' } { throw 'simulated read failure' }
        $thrown = $null
        Mock Get-TpmRestorePointFileState { & $script:F112RealFileState -Path $Path }
        try { Invoke-TpmVerifiedFileSwap -SourcePath $source -TargetPath $target -ExpectedSha256 ([string]$sourceState.Sha256) -ExpectedLength ([int64]$sourceState.Length) -ExpectedCurrentSha256 ([string]$targetState.Sha256) } catch { $thrown = $_.Exception }
        ($null -ne $thrown) | Should -BeTrue
        $thrown.Message | Should -Match 'simulated read failure'
        $kept = @(Get-ChildItem -LiteralPath $folder -Force | Where-Object { $_.Name -like '*.tpm-replace' })
        $kept.Count | Should -Be 1
        [System.IO.File]::ReadAllText($kept[0].FullName) | Should -BeExactly 'current-bytes'
    }
}

Describe 'FIX112 SF6: removing a restore point' {
    It 'keeps the record while its backup folder could not be removed' {
        # Mutation: remove the record folder before the backup (the old order) -> the restore point disappears from the list while its backup stays and the result says "kept".
        Mock Write-Log {}
        $profiles = New-F112Folder 'profiles'
        $point = New-F112Folder 'point'
        Set-F112Text -Path (Join-Path $point 'record.json') -Text '{}'
        $backup = Join-Path (Join-Path $profiles 'FullBackup') 'Startup_2026'
        Set-F112Text -Path (Join-Path $backup 'Game.xml') -Text '<GameProfile/>'
        $script:F112BackupPath = $backup
        Mock Get-TpmUserProfilesBackupProducer { 'Startup' }
        Mock Remove-Item {
            param($LiteralPath, $Recurse, $Force, $ErrorAction)
            if ($LiteralPath -ieq $script:F112BackupPath) { throw 'simulated: a file is in use' }
            if (Test-Path -LiteralPath $LiteralPath -PathType Container) { [System.IO.Directory]::Delete($LiteralPath, [bool]$Recurse) }
            elseif (Test-Path -LiteralPath $LiteralPath) { [System.IO.File]::Delete($LiteralPath) }
        }
        $restorePoint = [pscustomobject]@{ Readable = $true; Kind = 'Startup'; Path = $point; Id = 'rp-1'; Record = [pscustomobject]@{ Kind = 'Startup'; UserProfilesDir = $profiles; UserProfilesBackup = 'Startup_2026' } }
        $result = Remove-TpmRestorePoint -RestorePoint $restorePoint -UserProfilesDir $profiles
        $result.Removed | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $point 'record.json') | Should -BeTrue
        Test-Path -LiteralPath $backup | Should -BeTrue
    }
}

Describe 'FIX112 SF7: a re-read that finds no plan is PLAN_CHANGED, not a binding error' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
    }

    It 'returns false for an empty current plan' {
        # Mutation: drop [AllowEmptyCollection()] from Test-PostgresReinitializePlan or ConvertTo-PostgresReinitializePlanJson -> a parameter binding error instead of $false.
        $plan = [pscustomobject]@{ GameLabel = 'Game'; ProfileName = 'GameProfile'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; Encoding = 'SQL_ASCII' }
        $json = ConvertTo-PostgresReinitializePlanJson -Plans @($plan)
        $hash = Get-PostgresReinitializePlanHash -PlanJson $json
        { Test-PostgresReinitializePlan -ExpectedPlanJson $json -ExpectedPlanHash $hash -CurrentPlans @() } | Should -Not -Throw
        Test-PostgresReinitializePlan -ExpectedPlanJson $json -ExpectedPlanHash $hash -CurrentPlans @() | Should -BeFalse
        Test-PostgresReinitializePlan -ExpectedPlanJson $json -ExpectedPlanHash $hash -CurrentPlans @($plan) | Should -BeTrue
    }

    It 'stops the reinitialize with PLAN_CHANGED before any database is touched' {
        # Mutation: let the binding error escape Invoke-PostgresReinitializePlan -> the caller shows a raw error instead of the plain PLAN_CHANGED stop.
        $plan = [pscustomobject]@{ GameLabel = 'Game'; ProfileName = 'GameProfile'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; Encoding = 'SQL_ASCII' }
        $json = ConvertTo-PostgresReinitializePlanJson -Plans @($plan)
        $hash = Get-PostgresReinitializePlanHash -PlanJson $json
        Mock Get-PostgresReinitializePlansFromProfiles { @() }
        Mock Reset-PostgresDatabaseFromBackup { throw 'no database may be touched' }
        $recovery = [pscustomobject]@{ Verified = $true; Required = $true; Attempted = $true; Created = $true; Path = (Join-Path $TestDrive 'recovery'); Items = @(); FailureStage = $null; Reason = $null; ResiduePaths = @() }
        $result = Invoke-PostgresReinitializePlan -PlanJson $json -PlanHash $hash -UserProfilesDir (Join-Path $TestDrive 'profiles') -SuperPasswordPlain 'pw' -RecoveryBackup $recovery
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'PLAN_CHANGED'
        Should -Invoke Reset-PostgresDatabaseFromBackup -Times 0 -Exactly
    }

    It 'says Nothing was changed when the profiles cannot be read just before the rebuild' {
        # Mutation: let the read error escape Invoke-PostgresReinitializePlan -> the screen says "Some of your data may have been changed" although no database was touched.
        $plan = [pscustomobject]@{ GameLabel = 'Game'; ProfileName = 'GameProfile'; Database = 'GameDB19'; BackupFile = 'C:\fixture\one.backup'; Encoding = 'SQL_ASCII' }
        $json = ConvertTo-PostgresReinitializePlanJson -Plans @($plan)
        $hash = Get-PostgresReinitializePlanHash -PlanJson $json
        Mock Get-PostgresReinitializePlansFromProfiles { throw 'profile is locked by another program' }
        Mock Reset-PostgresDatabaseFromBackup { throw 'no database may be touched' }
        $recovery = [pscustomobject]@{ Verified = $true; Required = $true; Attempted = $true; Created = $true; Path = (Join-Path $TestDrive 'recovery'); Items = @(); FailureStage = $null; Reason = $null; ResiduePaths = @() }
        $result = Invoke-PostgresReinitializePlan -PlanJson $json -PlanHash $hash -UserProfilesDir (Join-Path $TestDrive 'profiles') -SuperPasswordPlain 'pw' -RecoveryBackup $recovery
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.Summary | Should -Match 'Nothing was changed\.'
        Should -Invoke Reset-PostgresDatabaseFromBackup -Times 0 -Exactly
    }
}

Describe 'FIX112 SF8: the database name check' {
    It 'accepts plain names and refuses a trailing newline and other characters' {
        # Mutation: go back to '^...$' -> "GameDB19`n" passes the only guard before the name is put into SQL and tool arguments.
        Test-SafePostgresDbName 'GameDB19' | Should -BeTrue
        Test-SafePostgresDbName 'game_db_2' | Should -BeTrue
        Test-SafePostgresDbName "GameDB19`n" | Should -BeFalse
        Test-SafePostgresDbName "GameDB19`r`n" | Should -BeFalse
        Test-SafePostgresDbName 'Game DB' | Should -BeFalse
        Test-SafePostgresDbName 'a"; DROP' | Should -BeFalse
        Test-SafePostgresDbName '' | Should -BeFalse
    }
}

Describe 'FIX112 SF9: the AutoSync profile backup includes hidden files' {
    It 'copies a hidden file and a hidden folder along with the visible ones' {
        # Mutation: list the source without -Force -> hidden entries are missing from a backup that is then stamped complete.
        Mock Write-TpmCompactExtractionProgress {}
        $source = New-F112Folder 'ups'
        $destination = New-F112Folder 'ups-backup'
        Set-F112Text -Path (Join-Path $source 'Visible.xml') -Text '<a/>'
        Set-F112Text -Path (Join-Path $source 'Hidden.xml') -Text '<b/>'
        [System.IO.File]::SetAttributes((Join-Path $source 'Hidden.xml'), [System.IO.FileAttributes]::Hidden)
        Set-F112Text -Path (Join-Path $source 'HiddenDir\inner.xml') -Text '<c/>'
        [System.IO.File]::SetAttributes((Join-Path $source 'HiddenDir'), [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::Directory)
        $result = Copy-TpmAutoSyncUserProfilesBackup -UserProfilesDir $source -BackupPath $destination
        $result.Succeeded | Should -BeTrue
        $names = @(Get-ChildItem -LiteralPath $destination -Force -Recurse | ForEach-Object { $_.Name })
        $names | Should -Contain 'Visible.xml'
        $names | Should -Contain 'Hidden.xml'
        $names | Should -Contain 'inner.xml'
    }
}

Describe 'FIX112 SF10: the XML save' {
    It 'writes the document without a byte-order mark, replaces an existing file and leaves no temporary file' {
        # Mutation: break the new stream-based writer (BOM, unflushed or unclosed stream) -> a BOM, a locked or a leftover .tmp file.
        $folder = New-F112Folder 'xml'
        $path = Join-Path $folder 'Game.xml'
        Set-F112Text -Path $path -Text '<old/>'
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<GameProfile><GameName>Fixture</GameName></GameProfile>')
        Save-Xml -doc $doc -path $path
        $bytes = [System.IO.File]::ReadAllBytes($path)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        ([xml][System.IO.File]::ReadAllText($path)).GameProfile.GameName | Should -BeExactly 'Fixture'
        @(Get-ChildItem -LiteralPath $folder -Force | Where-Object { $_.Name -like '*.tmp' }).Count | Should -Be 0
        $second = Join-Path $folder 'New.xml'
        Save-Xml -doc $doc -path $second
        Test-Path -LiteralPath $second -PathType Leaf | Should -BeTrue
    }

    It 'refuses to write through a folder link' {
        # Mutation: remove the reparse check from Save-Xml -> a junction planted at the folder redirects the write.
        $real = New-F112Folder 'real'
        $link = Join-Path (New-F112Folder 'links') 'link'
        New-Item -ItemType Junction -Path $link -Target $real | Out-Null
        try {
            $doc = New-Object System.Xml.XmlDocument
            $doc.LoadXml('<GameProfile/>')
            { Save-Xml -doc $doc -path (Join-Path $link 'Game.xml') } | Should -Throw '*XML save*'
            @(Get-ChildItem -LiteralPath $real -Force).Count | Should -Be 0
        } finally {
            if (Test-Path -LiteralPath $link) { [System.IO.Directory]::Delete($link) }
        }
    }
}

Describe 'FIX112 SF18: no dead code after the return of the ReShade setup function' {
    It 'has no use of the undefined $ExePath variable' {
        # Mutation: put the orphaned Get-GameLegacyApi body back after the return -> the function mentions a variable it never defines.
        $function = @($script:F112Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Invoke-ReShadeSetupLegacy' }, $true))[0]
        $function | Should -Not -BeNullOrEmpty
        $uses = @($function.FindAll({ $args[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and $args[0].VariablePath.UserPath -eq 'ExePath' }, $true))
        $uses.Count | Should -Be 0
    }
}

Describe 'FIX112 SF23: support text redaction' {
    It 'hides a JSON password, a -Password argument and a bare Bearer token' {
        # Mutation: drop the optional closing quote, the single-dash form or the bare Bearer pattern -> the secret stays in the support text.
        $text = '{"password": "hunter2-secret"} start.exe -Password hunter3-secret Authorization header was Bearer abcdefghij0123456789 done'
        $redacted = [string](Redact-TpmSupportText -Text $text).Text
        $redacted | Should -Not -Match 'hunter2-secret'
        $redacted | Should -Not -Match 'hunter3-secret'
        $redacted | Should -Not -Match 'abcdefghij0123456789'
        (Redact-TpmSupportText -Text 'The game is called Super Bowling Live and the user name is Sam').Text | Should -BeExactly 'The game is called Super Bowling Live and the user name is Sam'
    }
    It 'hides a Windows profile path that has a space in a folder name' {
        # Mutation: stop the path pattern at the first space -> the part after the space stays in the support text.
        $redacted = [string](Redact-TpmSupportText -Text 'Could not read C:\Users\John Smith\My Games\tp\a.log today').Text
        $redacted | Should -Not -Match 'Smith'
        $redacted | Should -Not -Match 'My Games'
    }
}

Describe 'FIX112 SF28: an unattended run never waits for typed input' {
    It 'has no Read-Host inside any branch that runs only when Unattended is set' {
        # Mutation: put Read-Host back into an `if ($Unattended)` error branch -> an unattended run stops and waits for Enter.
        $branches = @($script:F112Ast.FindAll({
            $node = $args[0]
            $node -is [System.Management.Automation.Language.IfStatementAst] -and @($node.Clauses | Where-Object { $_.Item1.Extent.Text -eq '$Unattended' }).Count -gt 0
        }, $true))
        $branches.Count | Should -BeGreaterThan 0
        foreach ($branch in $branches) {
            foreach ($clause in @($branch.Clauses | Where-Object { $_.Item1.Extent.Text -eq '$Unattended' })) {
                $reads = @($clause.Item2.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -in @('Read-Host', 'Read-HostSafe') }, $true))
                $reads.Count | Should -Be 0 -Because ('line ' + $clause.Item2.Extent.StartLineNumber)
            }
        }
    }
}
