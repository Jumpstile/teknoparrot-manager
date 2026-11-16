#Requires -Module Pester

# Data-safety and silent-failure findings of the whole-product review. Each It names the product change that makes it fail.
#   - a file already moved into place or removed is always counted as changed, so a failed check rolls back and keeps the recovery copy
#   - "nothing left to extract" processes nothing; A (and an unattended run) means the unextracted games only
#   - a failed or refused ZIP is never a green AutoSync recap
#   - a finished and verified PostgreSQL repair is reported as finished even when the one-shot file cannot be deleted
#   - a failed migration safety backup does not stop every later start; the reason and the next step are shown
#   - a startup update that was rolled back says so
#   - an empty newest pg_backup date folder does not hide an older backup
#   - dgVoodoo2 files are downloaded to the managed Assets folder
# The product is never run: function definitions and named script-body statements are taken from the parsed script (AST) and
# run against synthetic fixtures in $TestDrive. What this CANNOT prove: a real console, a real scanner holding a file, or a real
# elevated PostgreSQL window.

BeforeAll {
    $script:DsScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:DsAst = [System.Management.Automation.Language.Parser]::ParseFile($script:DsScriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The production script could not be parsed.' }
    $script:DsFunctionNodes = @($script:DsAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionText = @($script:DsFunctionNodes | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:DsFunctionFile = Join-Path $TestDrive 'ds-functions.ps1'
    [System.IO.File]::WriteAllText($script:DsFunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:DsFunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    # The real functions, kept so a test can wrap them for one call.
    $script:DsRealGetFileState = ${function:Get-TpmFileState}
    $script:DsRealGetFileIdentity = ${function:Get-TpmFileIdentityString}
    function New-DsUnreadableState {
        param([string]$Path)
        return [pscustomobject]@{ Path = $Path; Exists = $null; Readable = $false; IsDirectory = $null; Length = $null; Sha256 = $null; LastWriteTimeUtc = $null; Attributes = $null; Error = 'The file is in use by another program.' }
    }

    function Write-DsText {
        param([string]$Path, [string]$Text)
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }

    # The one if-statement inside the named function whose first condition starts with $ConditionStart.
    function Get-DsTopLevelIfInFunction {
        param([string]$FunctionName, [string]$ConditionStart)
        $function = @($script:DsFunctionNodes | Where-Object { $_.Name -ceq $FunctionName })
        if ($function.Count -ne 1) { throw ('Expected one function {0}.' -f $FunctionName) }
        $found = @($function[0].FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text.StartsWith($ConditionStart, [System.StringComparison]::Ordinal) }, $true))
        if ($found.Count -ne 1) { throw ('Expected one if-statement starting "{0}", found {1}.' -f $ConditionStart, $found.Count) }
        return $found[0].Extent.Text
    }

    # The one script-body if-statement whose first condition text is $ConditionText.
    function Get-DsTopLevelIf {
        param([string]$ConditionText)
        $found = @($script:DsAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -ceq $ConditionText }, $true))
        if ($found.Count -ne 1) { throw ('Expected one if-statement "{0}", found {1}.' -f $ConditionText, $found.Count) }
        return $found[0].Extent.Text
    }

    # Runs one extracted statement with the given variables, as the script body would, and returns the named variables afterwards.
    function Invoke-DsBlock {
        param([string]$Text, [hashtable]$Variables, [string[]]$Outputs)
        foreach ($key in $Variables.Keys) { Set-Variable -Name $key -Value $Variables[$key] }
        foreach ($once in 1) { . ([scriptblock]::Create($Text)) }
        $result = @{}
        foreach ($name in $Outputs) {
            $variable = Get-Variable -Name $name -ErrorAction SilentlyContinue
            $result[$name] = $null
            if ($variable) { $result[$name] = $variable.Value }
        }
        return $result
    }

    function New-DsBatchFixture {
        param([ValidateSet('ADD', 'REMOVE')][string]$Kind)
        $root = Join-Path $TestDrive ('ds-batch-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $game = Join-Path $root 'game'
        [void][System.IO.Directory]::CreateDirectory($game)
        $operation = [pscustomobject]@{ ItemId = 'plugin'; Operation = $Kind; DestinationPath = (Join-Path $game 'plugin.dll'); RootPath = $game }
        if ($Kind -eq 'ADD') {
            Write-DsText -Path (Join-Path $root 'source\plugin.dll') -Text 'new'
            $operation | Add-Member -NotePropertyName SourcePath -NotePropertyValue (Join-Path $root 'source\plugin.dll')
        } else {
            Write-DsText -Path (Join-Path $game 'plugin.dll') -Text 'old'
            $operation | Add-Member -NotePropertyName SourcePath -NotePropertyValue $null
        }
        return [pscustomobject]@{ Root = $root; Operation = $operation; Plugin = (Join-Path $game 'plugin.dll'); Staging = (Join-Path $root 'staging') }
    }
}

Describe 'A file that is already moved into place or removed is never reported as "nothing changed"' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:DsFlags = @{ Moved = $false; Shown = $false }
    }

    It 'counts an added file as changed (and does not remove what it cannot prove) when a scanner holds the new file for a moment' {
        # Mutation: set Changed/mutationStarted only after the read-back check -> FAILED_BEFORE_MUTATION "Nothing was changed" although the file is now in the game folder.
        $fx = New-DsBatchFixture -Kind ADD
        # The staged file is moved in; the first look at it afterwards is refused (a scanner has it open), later looks work.
        Mock Get-TpmFileIdentityString { if ([string]$Path -like '*plugin.dll') { $script:DsFlags.Moved = $true }; & $script:DsRealGetFileIdentity -Path $Path }
        Mock Get-TpmFileState {
            if ($script:DsFlags.Moved -and -not $script:DsFlags.Shown -and [string]$Path -like '*plugin.dll') { $script:DsFlags.Shown = $true; return (New-DsUnreadableState -Path $Path) }
            & $script:DsRealGetFileState -Path $Path
        }
        $r = Invoke-TpmTransactionalFileBatch -WorkflowKey 'DsTest' -OperationKey 'Add' -Operations @($fx.Operation) -StagingDir $fx.Staging
        $script:DsFlags.Shown | Should -BeTrue
        $r.Outcome | Should -Be 'ACTION_REQUIRED'
        $r.Mutation.Started | Should -BeTrue
        @($r.Mutation.ChangedItems) | Should -Contain 'plugin'
        [System.IO.File]::ReadAllText($fx.Plugin) | Should -BeExactly 'new'
    }

    It 'counts a removed file as changed and puts it back when the check right after the removal fails' {
        # Mutation: set Changed/mutationStarted only after the read-back check -> FAILED_BEFORE_MUTATION, the file stays deleted and the recovery copy is deleted.
        $fx = New-DsBatchFixture -Kind REMOVE
        Mock Get-TpmFileState {
            if (-not $script:DsFlags.Shown -and [string]$Path -like '*plugin.dll' -and -not [System.IO.File]::Exists($Path)) { $script:DsFlags.Shown = $true; return (New-DsUnreadableState -Path $Path) }
            & $script:DsRealGetFileState -Path $Path
        }
        $r = Invoke-TpmTransactionalFileBatch -WorkflowKey 'DsTest' -OperationKey 'Remove' -Operations @($fx.Operation) -StagingDir $fx.Staging
        $script:DsFlags.Shown | Should -BeTrue
        $r.Outcome | Should -Be 'ROLLED_BACK_VERIFIED'
        @($r.Mutation.ChangedItems) | Should -Contain 'plugin'
        [System.IO.File]::ReadAllText($fx.Plugin) | Should -BeExactly 'old'
    }
}

Describe 'Nothing left to extract means nothing is processed' {
    BeforeEach {
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:DsZips = Join-Path $TestDrive ('zips-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:DsSupp = Join-Path $TestDrive ('supp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:DsInstall = Join-Path $TestDrive ('games-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        foreach ($dir in @($script:DsZips, $script:DsSupp, $script:DsInstall)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    }

    It 'returns $null (skip), not an empty "extract everything" list, when every ZIP is already extracted' {
        # Mutation: return ,@() after "Nothing left to extract" -> the caller extracts every ZIP again.
        foreach ($name in @('Done1', 'Done2')) { Write-DsText -Path (Join-Path $script:DsZips ($name + '.zip')) -Text 'zip' }
        Mock Resolve-ExtractedGameFolder { 'already-there' }
        $result = Select-GamesInteractive -zipSource $script:DsZips -installFolder $script:DsInstall -datIndex @{} -userProfilesDir ''
        ($null -eq $result) | Should -BeTrue
        $combined = Select-GamesInteractiveCombined -zipSourceMain $script:DsZips -zipSourceSupp $script:DsSupp -installFolder $script:DsInstall -datIndex @{} -userProfilesDir ''
        ($null -eq $combined.Main) | Should -BeTrue
        ($null -eq $combined.Supp) | Should -BeTrue
    }

    It 'A returns only the unextracted games, never an empty "extract everything" list' {
        # Mutation: return ,@() for A -> already extracted games are processed (and their folders replaced) too.
        foreach ($name in @('Done1', 'New1', 'New2')) { Write-DsText -Path (Join-Path $script:DsZips ($name + '.zip')) -Text 'zip' }
        Mock Resolve-ExtractedGameFolder { if ($RawZipName -eq 'Done1') { 'already-there' } else { $null } }
        Mock Read-HostSafe { 'A' }
        $result = Select-GamesInteractive -zipSource $script:DsZips -installFolder $script:DsInstall -datIndex @{} -userProfilesDir ''
        @($result) | Should -Be @('New1', 'New2')
    }

    It 'an unattended run (-SelectAll) asks nothing and also returns only the unextracted games' {
        # Mutation: unattended runs skip the picker and pass an empty list -> every ZIP is processed.
        foreach ($name in @('Done1', 'New1')) { Write-DsText -Path (Join-Path $script:DsZips ($name + '.zip')) -Text 'zip' }
        Mock Resolve-ExtractedGameFolder { if ($RawZipName -eq 'Done1') { 'already-there' } else { $null } }
        Mock Read-HostSafe { throw 'an unattended run must not ask' }
        $result = Select-GamesInteractive -zipSource $script:DsZips -installFolder $script:DsInstall -datIndex @{} -userProfilesDir '' -SelectAll
        @($result) | Should -Be @('New1')
        Write-DsText -Path (Join-Path $script:DsSupp 'SuppNew.zip') -Text 'zip'
        $combined = Select-GamesInteractiveCombined -zipSourceMain $script:DsZips -zipSourceSupp $script:DsSupp -installFolder $script:DsInstall -datIndex @{} -userProfilesDir '' -SelectAll
        @($combined.Main) | Should -Be @('New1')
        @($combined.Supp) | Should -Be @('SuppNew')
    }

    It 'a source with nothing to extract is skipped ($null) when the other source has games' {
        # Mutation: an empty source list becomes @() -> that whole source (all of its ZIPs) is extracted.
        Write-DsText -Path (Join-Path $script:DsSupp 'SuppNew.zip') -Text 'zip'
        Write-DsText -Path (Join-Path $script:DsZips 'Done1.zip') -Text 'zip'
        Mock Resolve-ExtractedGameFolder { if ($RawZipName -eq 'Done1') { 'already-there' } else { $null } }
        Mock Read-HostSafe { 'A' }
        $combined = Select-GamesInteractiveCombined -zipSourceMain $script:DsZips -zipSourceSupp $script:DsSupp -installFolder $script:DsInstall -datIndex @{} -userProfilesDir ''
        ($null -eq $combined.Main) | Should -BeTrue
        @($combined.Supp) | Should -Be @('SuppNew')
    }
}

Describe 'A ZIP that failed or was refused is never a green AutoSync recap' {
    BeforeEach {
        Mock Write-Host {}
        Mock Write-Log {}
        # The script-body statements that count the problems and add the ACTION REQUIRED line, as the script runs them.
        $first = @($script:DsAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$extractionProblems' -and $n.Right.Extent.Text -eq '0' }, $true))
        if ($first.Count -ne 1) { throw 'The extraction problem statements were not found.' }
        $statements = @($first[0].Parent.Statements)
        $start = [array]::IndexOf($statements, $first[0])
        $end = -1
        for ($i = $start; $i -lt $statements.Count; $i++) {
            if ($statements[$i] -is [System.Management.Automation.Language.ForEachStatementAst] -and $statements[$i].Variable.Extent.Text -ceq '$registrationMessage') { $end = $i; break }
        }
        if ($start -lt 0 -or $end -lt $start) { throw 'The extraction problem statements were not found.' }
        $script:DsProblemBlock = (($statements[$start..$end] | ForEach-Object { $_.Extent.Text }) -join "`n")
    }

    It 'lists a failed ZIP and a refused ZIP in the same ACTION REQUIRED list the run saves' {
        # Mutation: leave Failed/UnsafePathSkipped out of the follow-up list -> the recap is green and the list is empty.
        $followUp = New-Object System.Collections.Generic.List[string]
        $out = Invoke-DsBlock -Text $script:DsProblemBlock -Variables @{
            sync = @{ Synced = 3; Failed = 1; UnsafePathSkipped = 0 }; syncSupp = @{ Synced = 0; Failed = 0; UnsafePathSkipped = 1 }
            mode = 'AutoSync'; syncGroup = $null; suppGroup = $null; registrationFollowUp = $followUp
        } -Outputs @('extractionProblems')
        $out.extractionProblems | Should -Be 2
        $followUp.Count | Should -Be 1
        $followUp[0] | Should -Match '2 ZIP files could not be unpacked'
    }

    It 'an invalid sync-state file is not counted as a ZIP that failed to unpack, and never says run it again' {
        # Mutation: count Failed=1 from the refused run -> "1 ZIP file could not be unpacked" right after "nothing was extracted".
        foreach ($dry in @($false, $true)) {
            $followUp = New-Object System.Collections.Generic.List[string]
            $out = Invoke-DsBlock -Text $script:DsProblemBlock -Variables @{
                sync = @{ Synced = 0; Failed = 1; UnsafePathSkipped = 0; StateRefused = $true }; syncSupp = $null
                mode = 'AutoSync'; syncGroup = $null; suppGroup = $null; registrationFollowUp = $followUp; dryRunActive = $dry
            } -Outputs @('extractionProblems', 'runStopMessages')
            $out.extractionProblems | Should -Be 0
            $followUp.Count | Should -Be 1
            $followUp[0] | Should -Match 'sync-state file could not be read'
            $followUp[0] | Should -Not -Match 'unpacked, so those|run AutoSync again'
            if ($dry) { $followUp[0] | Should -Match '^AutoSync preview' } else { $followUp[0] | Should -Match 'nothing was unpacked' }
        }
    }

    It 'a real ZIP failure plus a registration record problem counts one ZIP and gives the record its own message' {
        # Mutation: add the evidence flag to the ZIP count -> "2 ZIP files could not be unpacked".
        $followUp = New-Object System.Collections.Generic.List[string]
        $out = Invoke-DsBlock -Text $script:DsProblemBlock -Variables @{
            sync = @{ Synced = 1; Failed = 1; UnsafePathSkipped = 0; EvidenceStopped = $true }; syncSupp = @{ Synced = 0; Failed = 0; UnsafePathSkipped = 0; EvidenceRefused = $true }
            mode = 'AutoSync'; syncGroup = $null; suppGroup = $null; registrationFollowUp = $followUp; dryRunActive = $false
        } -Outputs @('extractionProblems')
        $out.extractionProblems | Should -Be 1
        $followUp.Count | Should -Be 2
        @($followUp | Where-Object { $_ -match '^AutoSync: 1 ZIP file could not be unpacked' }).Count | Should -Be 1
        @($followUp | Where-Object { $_ -match 'registration record' -and $_ -notmatch 'run AutoSync again' }).Count | Should -Be 1
    }

    It 'the recap lists a run-level stop under what needs attention without calling it a ZIP' {
        # Mutation: leave RunProblems out of the recap -> a refused run ends with a green recap.
        $recap = Get-TpmRegistrationRecap -AutoSyncRan $true -ZipsExtracted 0 -RunProblems @('AutoSync: the sync-state file could not be read, so nothing was unpacked.')
        $recap.Status | Should -Be 'Attention'
        @($recap.Needs) | Should -Contain 'AutoSync: the sync-state file could not be read, so nothing was unpacked.'
        (@($recap.Needs) -join ' ') | Should -Not -Match 'ZIP file'
    }

    It 'adds nothing when every selected ZIP was unpacked' {
        $followUp = New-Object System.Collections.Generic.List[string]
        $out = Invoke-DsBlock -Text $script:DsProblemBlock -Variables @{
            sync = @{ Synced = 3; Failed = 0; UnsafePathSkipped = 0 }; syncSupp = $null
            mode = 'AutoSync'; syncGroup = [pscustomobject]@{}; suppGroup = $null; registrationFollowUp = $followUp
        } -Outputs @('extractionProblems')
        $out.extractionProblems | Should -Be 0
        $followUp.Count | Should -Be 0
    }

    It 'counts a run whose result is missing (crashed extraction) as a problem' {
        # Mutation: ignore a missing result -> a crashed extraction step looks like "nothing to do".
        $followUp = New-Object System.Collections.Generic.List[string]
        $out = Invoke-DsBlock -Text $script:DsProblemBlock -Variables @{
            sync = $null; syncSupp = $null; mode = 'AutoSync'; syncGroup = [pscustomobject]@{ Outcome = 'ACTION_REQUIRED'; Result = $null }; suppGroup = $null; registrationFollowUp = $followUp
        } -Outputs @('extractionProblems')
        $out.extractionProblems | Should -Be 1
    }

    It 'the recap says Attention and names the ZIPs that were not unpacked' {
        # Mutation: no ExtractionProblems input -> Status stays Ok.
        $ok = Get-TpmRegistrationRecap -AutoSyncRan $true -ZipsExtracted 3 -NewlyRegistered 3
        $ok.Status | Should -Be 'Ok'
        $bad = Get-TpmRegistrationRecap -AutoSyncRan $true -ZipsExtracted 3 -NewlyRegistered 3 -ExtractionProblems 2
        $bad.Status | Should -Be 'Attention'
        @($bad.Needs) | Should -Contain '2 ZIP files could not be unpacked, so those games are not set up. The log has the reason.'
    }
}

Describe 'A finished and verified PostgreSQL repair is reported as finished' {
    It 'the administrator window still reports Completed (exit 0) when its one-shot file cannot be deleted' {
        # Mutation: stop with "could not remove its temporary repair file" -> the original window prints "did not finish ... may already be reinitialized".
        $names = @('Exit-PostgresRecoveryResumeSuccess', 'New-PostgresRecoveryHandoffResult')
        $functions = @($script:DsFunctionNodes | Where-Object { $names -contains $_.Name } | ForEach-Object { $_.Extent.Text }) -join "`r`n"
        $child = Join-Path $TestDrive 'pg-child.ps1'
        $lines = @(
            $functions,
            'function Remove-PostgresRecoveryState { param($Path, $ClaimPath) $false }',
            'function Write-PostgresRecoveryHandoffResult { param($StatePath, $Result) [Console]::Out.WriteLine("RESULT:" + $Result.Outcome); $true }',
            'function Write-Log { param($msg) }',
            'function Exit-PostgresRecoveryResume { param($Message) [Console]::Out.WriteLine("STOPPED:" + $Message); exit 1 }',
            '$state = [pscustomobject]@{ Path = "C:\x\.tpm-postgres-recovery-00000000000000000000000000000000.json"; ClaimPath = "C:\x\claim"; Operation = "Recovery"; DatabaseBackupSucceeded = $true }',
            'Exit-PostgresRecoveryResumeSuccess -ResumeState $state'
        )
        [System.IO.File]::WriteAllText($child, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding $false))
        $hostExe = (Get-Process -Id $PID).Path
        $output = @(& $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $child 2>&1 | ForEach-Object { [string]$_ })
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        ($output -join "`n") | Should -Match 'RESULT:Completed'
        ($output -join "`n") | Should -Not -Match 'STOPPED:'
    }

    It 'the original window returns success and names the leftover file when it cannot delete it either' {
        # Mutation: print "could not clean its one-time recovery record" and return $false -> a finished repair is reported as failed.
        $ifText = Get-DsTopLevelIfInFunction -FunctionName 'Start-PostgresRecoveryAsAdministrator' -ConditionStart '$childExit -eq 0 -and [bool]$childRun.Succeeded'
        $statePath = Join-Path $TestDrive '.tpm-postgres-recovery-00000000000000000000000000000000.json'
        Write-DsText -Path $statePath -Text '{}'
        $script:DsShown = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { param($Object) [void]$script:DsShown.Add([string]$Object) }
        Mock Write-Log {}
        Mock Remove-PostgresRecoveryHandoffResult { $true }
        Mock Remove-PostgresRecoveryState { $false }
        $childExit = 0
        $childRun = [pscustomobject]@{ Succeeded = $true }
        $handoff = [pscustomobject]@{ Valid = $true; Result = [pscustomobject]@{ Outcome = 'Completed' } }
        $returned = & ([scriptblock]::Create($ifText))
        $returned | Should -BeTrue
        ($script:DsShown -join "`n") | Should -Match 'PostgreSQL setup finished'
        ($script:DsShown -join "`n") | Should -Match ([regex]::Escape($statePath))
    }
}

Describe 'A failed migration safety backup does not stop every later start' {
    BeforeEach { Mock Write-Log {} }

    It 'says what happened, what to do next, and where the unfinished copy is' {
        # Mutation: no message for BACKUP_FAILED -> the user sees only "could not move its own files yet" with no cause or next step.
        $text = Get-DsTopLevelIf -ConditionText '$migration.Outcome -eq ''FAILED_BEFORE_MUTATION'''
        $script:DsLines = New-Object System.Collections.Generic.List[string]
        Mock Write-TpmText { param($Text) [void]$script:DsLines.Add([string]$Text) }
        $migration = [pscustomobject]@{
            Outcome = 'FAILED_BEFORE_MUTATION'; ReasonCode = 'BACKUP_FAILED'
            Backup = [pscustomobject]@{ FailureCode = 'The file is in use.' }
            Cleanup = [pscustomobject]@{ ResiduePaths = @('D:\TeknoParrot\TeknoParrotManager\Backups\LegacyMigration_x') }
        }
        $null = Invoke-DsBlock -Text $text -Variables @{ migration = $migration } -Outputs @()
        $joined = $script:DsLines -join "`n"
        $joined | Should -Match 'Nothing was changed'
        $joined | Should -Match 'could not make a safety copy'
        $joined | Should -Match 'start TeknoParrot Manager again'
        $joined | Should -Match ([regex]::Escape('D:\TeknoParrot\TeknoParrotManager\Backups\LegacyMigration_x'))
    }
}

Describe 'A startup update that was rolled back says so' {
    It 'tells the user the update did not install and the old version is still in place' {
        # Mutation: leave ROLLED_BACK_VERIFIED out of the message branch -> nothing is printed and the update looks pending.
        $text = (Get-DsTopLevelIf -ConditionText '$checkForUpdatesOnStartup -and -not $Unattended -and -not $isPostgresRecoveryResume').Replace('$PSScriptRoot', '$dsScriptRoot')
        $script:DsShown = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { param($Object) [void]$script:DsShown.Add([string]$Object) }
        Mock Write-Log {}
        Mock Invoke-StartupUpdateCheck { [pscustomobject]@{ Outcome = 'ROLLED_BACK_VERIFIED'; Summary = 'The update was not installed.'; ReasonCode = 'UPDATE_ROLLED_BACK' } }
        Mock Test-TpmTransactionResult { $true }
        $null = Invoke-DsBlock -Text $text -Variables @{ checkForUpdatesOnStartup = $true; Unattended = $false; isPostgresRecoveryResume = $false; tpmPrintedAfterSavedSettings = $false; dsScriptRoot = $TestDrive } -Outputs @()
        ($script:DsShown -join "`n") | Should -Match 'The update did not install'
        ($script:DsShown -join "`n") | Should -Match 'old version of TeknoParrot Manager is still in place'
    }
}

Describe 'An empty newest pg_backup date folder does not hide an older backup' {
    It 'uses the newest date folder that has files' {
        # Mutation: take the newest date folder even when it is empty -> "no backup of its own" and an empty database is created.
        Mock Write-TpmCompactExtractionProgress {}
        $game = Join-Path $TestDrive 'pg-game'
        Write-DsText -Path (Join-Path $game 'pg_backup\2026-01-05\game.backup') -Text 'dump'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $game 'pg_backup\2026-02-09'))
        @(Get-PostgresBackupCandidates -GameFolder $game | ForEach-Object Name) | Should -Be @('game.backup')
    }

    It 'still returns nothing when every date folder is empty' {
        Mock Write-TpmCompactExtractionProgress {}
        $game = Join-Path $TestDrive 'pg-game-empty'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $game 'pg_backup\2026-02-09'))
        @(Get-PostgresBackupCandidates -GameFolder $game).Count | Should -Be 0
    }

    It 'uses the files directly inside pg_backup when the only date folder is empty' {
        # Mutation: look in pg_backup itself only when no date folder exists -> one stray empty date folder hides the real backup.
        Mock Write-TpmCompactExtractionProgress {}
        $game = Join-Path $TestDrive 'pg-game-root-files'
        Write-DsText -Path (Join-Path $game 'pg_backup\game.backup') -Text 'dump'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $game 'pg_backup\2026-02-09'))
        @(Get-PostgresBackupCandidates -GameFolder $game | ForEach-Object Name) | Should -Be @('game.backup')
    }

    It 'skips a newer date folder that holds only a note and uses the older real backup' {
        # Mutation: take the newest date folder with any file -> the note hides the real backup and an empty database is created.
        Mock Write-TpmCompactExtractionProgress {}
        $game = Join-Path $TestDrive 'pg-game-note-folder'
        Write-DsText -Path (Join-Path $game 'game.exe') -Text 'exe'
        Write-DsText -Path (Join-Path $game 'pg_backup\2026-05-01\1850.backup') -Text 'dump'
        Write-DsText -Path (Join-Path $game 'pg_backup\2026-06-02\readme.txt') -Text 'note'
        $selection = Get-PostgresBackupSelection -GamePath (Join-Path $game 'game.exe')
        $selection.Newest | Should -BeLike '*2026-05-01*1850.backup'
        $selection.CandidateCount | Should -Be 1
    }

    It 'finds the dump in alternate backups when pg_backup holds only a note' {
        # Mutation: decide from the unfiltered pg_backup files -> the note hides the real dump, "no starting database file" is shown or an empty database is made.
        Mock Write-TpmCompactExtractionProgress {}
        $game = Join-Path $TestDrive 'pg-game-note-root'
        Write-DsText -Path (Join-Path $game 'game.exe') -Text 'exe'
        Write-DsText -Path (Join-Path $game 'pg_backup\notes.txt') -Text 'note'
        Write-DsText -Path (Join-Path $game 'pg_backup\alternate backups\1850.backup') -Text 'dump'
        $selection = Get-PostgresBackupSelection -GamePath (Join-Path $game 'game.exe') -IncludeAlternate
        $selection.Newest | Should -BeLike '*alternate backups*1850.backup'
        $selection.CandidateCount | Should -Be 1
    }
}

Describe 'dgVoodoo2 files are downloaded to the managed Assets folder' {
    BeforeEach { $script:TpmOwnedLayout = $null }
    AfterEach { $script:TpmOwnedLayout = $null }

    It 'finds a managed copy first and a folder beside the script otherwise' {
        # Mutation: look only beside the script -> a downloaded managed copy is never found again.
        $assets = Join-Path $TestDrive 'ds-assets'
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = $assets }
        (Get-TpmBundledDgVoodoo2Folder) | Should -BeLike '*dgVoodoo2'
        (Get-TpmBundledDgVoodoo2Folder) | Should -Not -BeLike ($assets + '*')
        Write-DsText -Path (Join-Path $assets 'dgVoodoo2\D3D8.dll') -Text 'dll'
        (Get-TpmBundledDgVoodoo2Folder) | Should -Be (Join-Path $assets 'dgVoodoo2')
    }

    It 'the automatic download extracts into the managed Assets folder' {
        # Mutation: extract beside the script -> a program folder that is not writable makes the automatic download fail.
        $assignment = @($script:DsAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$dgCacheDir' }, $true))
        $assignment.Count | Should -Be 1
        $assets = Join-Path $TestDrive 'ds-assets-download'
        $script:TpmOwnedLayout = [pscustomobject]@{ Assets = $assets }
        $out = Invoke-DsBlock -Text $assignment[0].Extent.Text -Variables @{} -Outputs @('dgCacheDir')
        $out.dgCacheDir | Should -Be (Join-Path $assets 'dgVoodoo2')
    }
}
