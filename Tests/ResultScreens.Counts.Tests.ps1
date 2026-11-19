#Requires -Module Pester

# Result screens of the setup steps: the counts add up to the games selected, every selected game is named, the backup folder is
# shown, the Action Required list is grouped, the BepInEx picker takes A / numbers / ranges, Library health check lists games that
# need BepInEx, and an unreadable game file is told apart from a game whose 32-bit or 64-bit type is unknown.
#
# The production script is parsed and only its function definitions are dot-sourced (plus the required-patch engine). Every file
# lives under TestDrive. Each It names the product change that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'The production script could not be parsed.' }
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'result-screens-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')

    function Install-ScreenMocks {
        param([string[]]$Answers = @())
        $script:Screen = New-Object System.Collections.Generic.List[string]
        $script:Queue = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($answer in $Answers) { [void]$script:Queue.Enqueue($answer) }
        Mock Write-Host { [void]$script:Screen.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { return 100 }
        Mock Read-HostSafe {
            if ($script:Queue.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:Queue.Dequeue()
        }
    }
    function Get-ScreenText { return ((@($script:Screen) -join ' ') -replace '\s+', ' ') }
}

Describe 'The counts line adds up to the games selected' {
    It 'shows only the counts that apply' {
        Get-TpmStepCountsLine -Picked 4 -Changed 3 -Skipped 1 | Should -BeExactly 'You selected 4 games: 3 changed, 1 skipped.'
    }
    It 'shows a game that is in no count as not finished, so nothing disappears' {
        Get-TpmStepCountsLine -Picked 5 -Changed 2 -AlreadySetUp 1 -Failed 1 | Should -BeExactly 'You selected 5 games: 2 changed, 1 already set up, 1 failed, 1 not finished.'
    }
    It 'counts each game once from the item lists of a result' {
        $result = [pscustomobject]@{ ChangedItems = @('a', 'b'); SkippedItems = @('c'); FailedItems = @('d'); UnknownItems = @(); CompletedItems = @('a', 'e') }
        Get-TpmResultCountsLine -Result $result -Picked @('a', 'b', 'c', 'd', 'e') | Should -BeExactly 'You selected 5 games: 2 changed, 1 already set up, 1 skipped, 1 failed.'
    }
}

Describe 'dgVoodoo2 names every selected game' {
    It 'explains 4 selected and 3 changed: the fourth is skipped, named, and the drive line points to Library health check 13' {
        $result = [pscustomobject]@{
            NoOp = $false; Deployed = 3; PresetOverrides = 0; AlreadyConfigured = @()
            PickedGames = @('g1', 'g2', 'g3', 'g4')
            DeploymentDetails = @([pscustomobject]@{ Game = 'g1' }, [pscustomobject]@{ Game = 'g2' }, [pscustomobject]@{ Game = 'g3' })
            SkipDetails = @([pscustomobject]@{ Game = 'g4'; ReasonCode = 'DEVICE_UNAVAILABLE'; Reason = 'The saved game drive or device is unavailable.' })
            FailedDetails = @()
        }
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        $view.Done[0] | Should -BeExactly 'You selected 4 games: 3 changed, 1 skipped.'
        ($view.Needs -join ' ') | Should -Match 'g4'
        $view.Next | Should -Match '13 \(Library health check\)'
    }
    It 'lists a failed game with its reason and never calls the step done' {
        $result = [pscustomobject]@{
            NoOp = $false; Deployed = 0; PresetOverrides = 0; AlreadyConfigured = @()
            PickedGames = @('g1', 'g2')
            DeploymentDetails = @(); SkipDetails = @()
            FailedDetails = @([pscustomobject]@{ Game = 'g1'; Reason = 'Something went wrong while checking this game, so it was not changed.' })
        }
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        $view.Status | Should -Be 'Problem'
        $view.Done[0] | Should -BeExactly 'You selected 2 games: 1 failed, 1 not finished.'
        ($view.Needs -join ' ') | Should -Match 'g1'
        ($view.Needs -join ' ') | Should -Match 'g2'
    }
    It 'shows where the backup is when the file step made one' {
        $result = [pscustomobject]@{
            NoOp = $false; Deployed = 1; PresetOverrides = 1; AlreadyConfigured = @(); PickedGames = @('g1')
            DeploymentDetails = @([pscustomobject]@{ Game = 'g1' }); SkipDetails = @(); FailedDetails = @()
            TransactionResult = [pscustomobject]@{ Backup = [pscustomobject]@{ RootPath = 'D:\TPM\Backups\dgv-1' } }
        }
        (Get-TpmDgVoodoo2ResultView -Result $result).Done -join ' ' | Should -Match 'D:\\TPM\\Backups\\dgv-1'
    }
}

Describe 'The backup line' {
    It 'gives the full folder, and claims nothing when there is no backup' {
        Get-TpmBackupFolderLine -ExtraPaths @('C:\Saved\one') -What 'your game settings' | Should -BeExactly 'A backup of your game settings is saved in this folder: C:\Saved\one'
        Get-TpmBackupFolderLine -Result ([pscustomobject]@{ Backup = $null }) | Should -BeExactly ''
    }
}

Describe 'The Action Required list is grouped by feature' {
    It 'puts each line under its feature and keeps a numbered list with its opening line' {
        $lines = @(
            'ReShade: did not finish as a verified success.',
            'Drive not connected: the GPU fix skipped games. Connect the drive.',
            'TeknoParrot has its own first-time setup, and it is not finished yet.',
            'Before you start a game, open TeknoParrot and finish it:',
            '  1. Open this file: C:\TP\TeknoParrotUi.exe',
            'dgVoodoo2: did not finish as a verified success.'
        )
        $groups = @(Get-TpmActionRequiredGroups -Lines $lines)
        @($groups | ForEach-Object { $_.Heading }) | Should -Be @('Drive not connected', 'dgVoodoo2', 'ReShade', 'TeknoParrot first-time setup')
        @($groups | Where-Object { $_.Heading -eq 'TeknoParrot first-time setup' })[0].Lines.Count | Should -Be 3
    }
}

Describe 'The BepInEx game picker' {
    BeforeEach { Install-ScreenMocks }
    It 'takes A for every game' {
        $script:Queue.Enqueue('a')
        @(Read-TpmMultiGameChoice -Rows @('one', 'two', 'three')) | Should -Be @(0, 1, 2)
    }
    It 'still takes typed numbers and ranges' {
        $script:Queue.Enqueue('1,3')
        @(Read-TpmMultiGameChoice -Rows @('one', 'two', 'three', 'four')) | Should -Be @(0, 2)
        $script:Queue.Enqueue('2-4')
        @(Read-TpmMultiGameChoice -Rows @('one', 'two', 'three', 'four')) | Should -Be @(1, 2, 3)
    }
    It 'asks again after an answer it cannot use, and B picks nothing' {
        $script:Queue.Enqueue('9'); $script:Queue.Enqueue('b')
        @(Read-TpmMultiGameChoice -Rows @('one', 'two')).Count | Should -Be 0
        Get-ScreenText | Should -Match 'not a number in the list'
    }
}

Describe 'BepInEx tells an unreadable game file from an unknown 32-bit or 64-bit type' {
    It 'uses two different codes and two different plain reasons' {
        $unreadable = Get-BepInExInspectionFailure -ErrorRecord ([System.Exception]::new('x')) -ArchitectureState 'UNREADABLE'
        $unknown = Get-BepInExInspectionFailure -ErrorRecord ([System.Exception]::new('x')) -ArchitectureState 'UNKNOWN'
        $unreadable.Code | Should -Be 'UNREADABLE_FILE'
        $unknown.Code | Should -Be 'UNKNOWN_ARCHITECTURE'
        (Get-TpmBepInExSkipWords -Code 'UNREADABLE_FILE')[0] | Should -Not -Be (Get-TpmBepInExSkipWords -Code 'UNKNOWN_ARCHITECTURE')[0]
    }
    It 'calls a missing file unreadable and a file with no PE header unknown' {
        (Get-BepInExPeArchitectureEvidence -Path (Join-Path $TestDrive 'missing.exe')).State | Should -Be 'UNREADABLE'
        $junk = Join-Path $TestDrive 'junk.exe'
        [System.IO.File]::WriteAllBytes($junk, (New-Object byte[] 200))
        (Get-BepInExPeArchitectureEvidence -Path $junk).State | Should -Be 'UNKNOWN'
    }
    It 'counts the selected games in the BepInEx result screen and names where a kept backup is' {
        $result = [pscustomobject]@{
            Updated = 1; Errors = 1; MissingDevice = 0; MissingPath = 0; Protected = 0; Skipped = 0
            PickedItems = @('a', 'b'); SelectedItems = @('a', 'b', 'c'); ChangedItems = @('a'); FailedItems = @('b'); SkippedItems = @(); CompletedItems = @('a'); UnattemptedItems = @()
            PathReasonCounts = @{}; FailureRecords = @([pscustomobject]@{ Game = 'b'; BackupPath = 'E:\Games\b\BepInEx_Backup_1'; ReasonKey = 'UPDATE_FAILED|x' })
            Mutation = [pscustomobject]@{ FailedItemCount = 1; UnattemptedItemCount = 0 }; ReasonCode = 'PARTIAL_UPDATE'
        }
        $done = @(Get-TpmBepInExDoneLines -Result $result)
        $done[0] | Should -BeExactly 'You selected 2 games: 1 changed, 1 failed.'
        $done[1] | Should -Match 'E:\\Games\\b\\BepInEx_Backup_1'
    }
}

Describe 'Library health check lists games that need BepInEx' {
    It 'shows a row and a detail line in plain words, and nothing when no game needs it' {
        $base = [ordered]@{
            Outcome = 'SUCCEEDED'; DiscoveryComplete = $true; OptionalCoverageComplete = $true; OptionalCheckFailed = 0
            PostgresInventoryStatus = 'Complete'; PostgresInventoryErrors = @(); ReadOnly = $true; Registered = 2
            Valid = @('A', 'B'); Broken = @(); Empty = @()
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @()
            PostgresNeeded = @(); PostgresConfigured = 0; PostgresAutoCreateProfiles = @()
            PostgresServiceExists = $false; PostgresServiceStatus = 'NotInstalled'
            ReShadeCount = 0; BepInExCount = 0; DetectedGpuVendor = 'Intel'; LogPath = 'C:\Logs\TeknoParrot-Manager.log'
            PostgresNeededLabels = @(); PostgresConfiguredLabels = @(); PostgresPsqlStatus = 'Unknown'
            OptionalCoverageUnavailable = $false; OptionalCoverageError = ''; LastFullRun = ''
        }
        $without = [pscustomobject]$base
        @(Get-TpmLibraryHealthRows -Result $without | Where-Object { $_.Area -eq 'BepInEx' }).Count | Should -Be 0
        $with = [pscustomobject]($base + @{ BepInExNeeded = @('Big Game One', 'Big Game Two') })
        $row = @(Get-TpmLibraryHealthRows -Result $with | Where-Object { $_.Area -eq 'BepInEx' })
        $row.Count | Should -Be 1
        $row[0].Text | Should -Match '2 games need BepInEx'
        $details = (@(Get-TpmLibraryHealthDetailBlocks -Result $with | ForEach-Object { @($_.Lines) }) -join "`n")
        $details | Should -Match 'Games that need BepInEx and do not have it set up: Big Game One and Big Game Two'
    }
}

Describe 'The patch step summary' {
    BeforeEach { Install-ScreenMocks }
    It 'counts each game once, shows the backup folder and points to Library health check for a game on a missing drive' {
        function New-PatchResult { param($Build, $Status, $Reason = '', $Receipt = '') [pscustomobject]@{ Entry = [pscustomobject]@{ Id = $Build; BuildName = $Build }; Status = $Status; Reason = $Reason; Receipt = $Receipt; Registered = $true } }
        $results = @(
            (New-PatchResult 'Game One' 'INSTALLED' 'Installed.' 'D:\TPM\Undo\game-one'),
            (New-PatchResult 'Game One' 'OTHER_VARIANT' 'Another variant.'),
            (New-PatchResult 'Game Two' 'ALREADY_APPLIED'),
            (New-PatchResult 'Game Three' 'BLOCKED' 'The drive L: is not connected.'),
            (New-PatchResult 'Game Four' 'FAILED' 'Something broke.')
        )
        Write-TpmRequiredPatchSummary -Results $results
        $text = Get-ScreenText
        $text | Should -Match 'You selected 4 games: 1 changed, 1 already set up, 1 skipped, 1 failed\.'
        $text | Should -Match 'D:\\TPM\\Undo\\game-one'
        $text | Should -Match '13 \(Library health check\)'
    }
}

Describe 'The GPU fix result' {
    It 'counts the selected games, shows where the backup is and points to Library health check when a drive is missing' {
        $result = [pscustomobject]@{
            Outcome = 'PARTIAL_APPLIED'; Cancelled = $false; GpuVendor = 'Intel'; Updated = 2; Unchanged = 0; NotApplicable = 0; Skipped = 1; Errors = 0; MissingPath = 0; MissingDevice = 1
            SkipDetails = @([pscustomobject]@{ Game = 'g3'; Reason = 'The saved game drive or device is unavailable.' }); FailureRecords = @(); Reason = ''
            Backup = [pscustomobject]@{ RootPath = 'D:\TP\bk' }
            SelectedItems = @('g1', 'g2', 'g3'); ChangedItems = @('g1', 'g2'); SkippedItems = @('g3'); FailedItems = @(); UnknownItems = @(); CompletedItems = @('g1', 'g2')
            Mutation = [pscustomobject]@{ ChangedItems = @('g1', 'g2'); FailedItems = @(); UnknownItems = @(); SkippedItems = @('g3'); UnattemptedItems = @(); FailedItemCount = 0; UnknownItemCount = 0; UnattemptedItemCount = 0 }
        }
        $view = Get-TpmGpuFixResultView -Result $result
        $view.Done[0] | Should -BeExactly 'You selected 3 games: 2 changed, 1 skipped.'
        $view.Done[1] | Should -Match 'D:\\TP\\bk'
        $view.Next | Should -Match '13 \(Library health check\)'
    }
}
