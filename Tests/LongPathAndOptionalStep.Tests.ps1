#Requires -Module Pester
# A game extracted to a path longer than 259 characters (Windows long paths off) must still be found, read and hashed by TeknoParrot Manager.
# Drives the real product functions on a synthetic long folder in the temp folder; nothing touches TeknoParrot, LaunchBox, the registry or the network.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'dsfinal12b-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:logPath = Join-Path $TestDrive 'dsfinal12b.log'
    $script:logWarnShown = $false

    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-longpath-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $deep = $root
    while ($deep.Length -lt 280) { $deep = Join-Path $deep 'a-long-folder-name-for-testing' }
    [void][System.IO.Directory]::CreateDirectory('\\?\' + $deep)
    $script:LongRoot = $root
    $script:LongExe = Join-Path $deep 'game.exe'
    [System.IO.File]::WriteAllBytes('\\?\' + $script:LongExe, [byte[]](77, 90, 1, 2, 3))
}

AfterAll {
    if ($script:LongRoot) { try { [System.IO.Directory]::Delete('\\?\' + $script:LongRoot, $true) } catch { $null = $_ } }
}

Describe 'Game paths over 259 characters' {
    It 'the test path really is longer than 259 characters' {
        $script:LongExe.Length | Should -BeGreaterThan 259
    }
    It 'accepts the game file for changes' {
        # Mutation: check the leaf with plain Test-Path -> GAME_PATH_MISSING for a file TPM extracted itself.
        $r = Test-TpmGameMutationPath -GamePath $script:LongExe -RequireLeaf
        $r.Reason | Should -BeNullOrEmpty
        $r.Valid | Should -BeTrue
        $r.ResolvedPath | Should -BeExactly $script:LongExe
    }
    It 'reads size and hash of the game file' {
        # Mutation: read Length/hash with the plain path -> Readable = $false.
        $state = Get-TpmFileState -Path $script:LongExe
        $state.Error | Should -BeNullOrEmpty
        $state.Readable | Should -BeTrue
        $state.Exists | Should -BeTrue
        $state.Length | Should -Be 5
        $state.Sha256 | Should -Match '^[0-9A-F]{64}$'
    }
    It 'reads the file identity used by rollback checks' {
        # Mutation: open the file with the plain path -> identity $null, so rollback can never prove the file is ours.
        Get-TpmFileIdentityString -Path $script:LongExe | Should -Not -BeNullOrEmpty
    }
    It 'tells PostgreSQL setup whether the game file is found, and whether its path is too long to use' {
        # Mutation: plain Test-Path -> 'Missing' for a game that is there, or 'Available' for a path 5.1 cannot read, so setup builds an empty database instead of stopping.
        $plainPathWorks = Test-Path -LiteralPath $script:LongExe -PathType Leaf
        Get-TpmGameExeAvailability -GamePath $script:LongExe | Should -BeExactly $(if ($plainPathWorks) { 'Available' } else { 'PathTooLong' })
        Get-TpmGameExeAvailability -GamePath ($script:LongExe + '.nope') | Should -BeExactly 'Missing'
        Get-TpmGameExeAvailability -GamePath '' | Should -BeExactly 'Missing'
    }
    It 'finds the game file when choosing its starting database file, says so when its path is too long to read, and treats a path Windows does not allow as not found' {
        # Mutation: plain Test-Path first -> on Windows PowerShell 5.1 with long paths off the selection says "no backup" for a game that is there; no PathTooLong flag -> the user is told the backup file is missing; a long-path check without the catch -> an illegal character in the profile aborts setup.
        Mock Get-PostgresBackupCandidates { @([pscustomobject]@{ Name = '1200.backup'; FullName = 'X:\pg_backup\1200.backup' }) }
        $found = Get-PostgresBackupSelection -GamePath $script:LongExe
        if (Test-Path -LiteralPath $script:LongExe -PathType Leaf) {
            $found.Newest | Should -BeExactly 'X:\pg_backup\1200.backup'
            $found.CandidateCount | Should -Be 1
            $found.PathTooLong | Should -BeFalse
        } else {
            $found.Newest | Should -BeNullOrEmpty
            $found.PathTooLong | Should -BeTrue
        }
        $gone = Get-PostgresBackupSelection -GamePath ($script:LongExe + '.nope')
        $gone.Newest | Should -BeNullOrEmpty
        $gone.PathTooLong | Should -BeFalse
        $illegal = $null
        { $illegal = Get-PostgresBackupSelection -GamePath 'C:\Games\"Quoted"\game.exe' -ErrorAction SilentlyContinue } | Should -Not -Throw
        $illegal.Newest | Should -BeNullOrEmpty
        Get-TpmGameExeAvailability -GamePath 'C:\Games\"Quoted"\game.exe' | Should -BeExactly 'Missing'
    }
}

Describe 'Other flows agree with the game-path check for a path over 259 characters' {
    BeforeAll {
        $script:LpProfiles = Join-Path $TestDrive 'lp-profiles'
        [void][System.IO.Directory]::CreateDirectory($script:LpProfiles)
        [System.IO.File]::WriteAllText((Join-Path $script:LpProfiles 'LongGame.xml'), ('<GameProfile><GamePath>{0}</GamePath><EmulatorType>OpenParrot</EmulatorType></GameProfile>' -f $script:LongExe))
    }
    BeforeEach {
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
    }
    It 'reads the AutoSync source file and folder manifest' {
        # Mutation: Get-Item on the plain path -> Exists/Readable false on Windows PowerShell 5.1 for a game TPM extracted itself.
        (Get-TpmAutoSyncSourceIdentity -Path $script:LongExe).Exists | Should -BeTrue
        $manifest = Get-TpmDirectoryManifest -Path (Split-Path -Parent $script:LongExe)
        $manifest.Readable | Should -BeTrue
        $manifest.Error | Should -BeNullOrEmpty
        $manifest.Exists | Should -BeTrue
    }
    It 'control readiness sees the game as registered' {
        # Mutation: plain Test-Path -> 'Broken' for a game that is really there.
        Get-ControlReadinessRegistrationState -UserProfilesDir $script:LpProfiles -Code 'LongGame' | Should -BeExactly 'Registered'
    }
    It 'the LaunchBox export keeps the game' {
        # Mutation: plain Test-Path -> the game is silently left out of the export.
        $out = Join-Path $TestDrive 'lp-export.xml'
        Export-LaunchBoxXml -userProfilesDir $script:LpProfiles -outputPath $out | Should -Be 1
    }
    It 'the ReShade removal context finds the game' {
        # Mutation: plain Test-Path -> no context, so a ReShade install in that game can never be removed.
        $file = Get-Item -LiteralPath (Join-Path $script:LpProfiles 'LongGame.xml')
        Get-TpmReShadeRemovalContext -ProfileFile $file | Should -Not -BeNullOrEmpty
    }
}

Describe 'Main menu in a short window' {
    It 'shows every option with its name and allows the prompt when the packed layout fits (100x10)' {
        # The 18 options pack into 8 rows plus nothing dropped. A 9-row window cannot hold them, so it gets the resize message instead of a menu with missing options.
        $screen = Render-MainMenuScreen -Tier (Get-ConsoleLayoutTier -Width 100 -Height 10) -Width 100 -Height 10
        $text = ($screen.Rows | ForEach-Object { $_.Text }) -join "`n"
        $screen.PromptAllowed | Should -BeTrue
        $screen.Rows.Count | Should -BeLessOrEqual 8
        foreach ($item in (Get-MainMenuItems)) { $text | Should -Match ([regex]::Escape(("{0}) {1}" -f $item.Number, $item.Label))) }
    }
    It 'still blocks the prompt and says to resize when the named options cannot fit (60x8)' {
        $screen = Render-MainMenuScreen -Tier (Get-ConsoleLayoutTier -Width 60 -Height 8) -Width 60 -Height 8
        $screen.PromptAllowed | Should -BeFalse
        (($screen.Rows | ForEach-Object { $_.Text }) -join "`n") | Should -Match 'Resize the PowerShell window'
    }
}

Describe 'Optional ReShade and dgVoodoo2 steps in the registration run' {
    BeforeAll {
        function New-DsReShadeResult {
            param([string]$Outcome, [string]$ReasonCode = '')
            $r = [pscustomobject]@{ Outcome = $Outcome; ReasonCode = $ReasonCode }
            $r.PSObject.TypeNames.Insert(0, 'TPM.TransactionResult.v1')
            return $r
        }
    }
    It 'a verified ReShade success is done and needs no follow-up' {
        $o = Get-TpmOptionalStepOutcome -Step ReShade -Result (New-DsReShadeResult -Outcome 'SUCCEEDED')
        $o.Done | Should -BeTrue
        $o.FollowUp | Should -BeNullOrEmpty
    }
    It 'a failed ReShade step is not done and gets a follow-up line (so it reaches the results block, ACTION REQUIRED and the report)' {
        # Mutation: set done before the step runs, or drop the follow-up -> the failure is silent and the ReShade tips are shown.
        foreach ($outcome in 'FAILED_BEFORE_MUTATION', 'ACTION_REQUIRED', 'ROLLED_BACK_VERIFIED') {
            $o = Get-TpmOptionalStepOutcome -Step ReShade -Result (New-DsReShadeResult -Outcome $outcome -ReasonCode 'SOMETHING_FAILED')
            $o.Done | Should -BeFalse -Because $outcome
            $o.FollowUp | Should -Match '^ReShade: did not finish'
            if ($outcome -eq 'FAILED_BEFORE_MUTATION') { $o.FollowUp | Should -Match 'Nothing was changed\.' -Because 'the ReShade result screen already says nothing changed' }
            else { $o.FollowUp | Should -Match 'Some game files may already have changed\.' -Because $outcome }
        }
        $none = Get-TpmOptionalStepOutcome -Step ReShade -Result $null
        $none.Done | Should -BeFalse
        $none.FollowUp | Should -Match '^ReShade: did not finish'
    }
    It 'a routine "some games were left alone", a cancel and a no-change result are not failures' {
        # Mutation: flag every result that is not SUCCEEDED -> a normal skip raises a false ACTION REQUIRED item.
        foreach ($case in @(@('PARTIAL_APPLIED', 'SOME_GAMES_NOT_CHANGED'), @('NO_OP', 'NO_CHANGES_NEEDED'), @('NO_OP', 'USER_CANCELLED'))) {
            $o = Get-TpmOptionalStepOutcome -Step ReShade -Result (New-DsReShadeResult -Outcome $case[0] -ReasonCode $case[1])
            $o.Done | Should -BeFalse
            $o.FollowUp | Should -BeNullOrEmpty -Because ($case -join '/')
        }
    }
    It 'dgVoodoo2 is done only after a successful run that deployed files; a failed run gets a follow-up' {
        $ok = Get-TpmOptionalStepOutcome -Step DgVoodoo2 -Result ([pscustomobject]@{ Succeeded = $true; Cancelled = $false; Deployed = 2 })
        $ok.Done | Should -BeTrue
        $ok.FollowUp | Should -BeNullOrEmpty
        $partial = Get-TpmOptionalStepOutcome -Step DgVoodoo2 -Result ([pscustomobject]@{ Succeeded = $false; Cancelled = $false; Deployed = 1 })
        $partial.Done | Should -BeFalse -Because 'a half-finished run must not count as done'
        $partial.FollowUp | Should -Match '^dgVoodoo2: did not finish'
        (Get-TpmOptionalStepOutcome -Step DgVoodoo2 -Result $null).FollowUp | Should -Match '^dgVoodoo2: did not finish'
        (Get-TpmOptionalStepOutcome -Step DgVoodoo2 -Result ([pscustomobject]@{ Succeeded = $false; Cancelled = $true; Deployed = 0 })).FollowUp | Should -BeNullOrEmpty
        (Get-TpmOptionalStepOutcome -Step DgVoodoo2 -Result ([pscustomobject]@{ Succeeded = $true; Cancelled = $false; Deployed = 0 })).FollowUp | Should -BeNullOrEmpty
    }
}

Describe 'Combined ZIP picker with the same game in both sources' {
    BeforeEach {
        $script:DsHost = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:DsHost.Add([string]$Object) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Resolve-ExtractedGameFolder { $null }
        $base = Join-Path $TestDrive ('picker-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:DsMain = Join-Path $base 'main'; $script:DsSupp = Join-Path $base 'supp'; $script:DsInstall = Join-Path $base 'games'
        foreach ($d in $script:DsMain, $script:DsSupp, $script:DsInstall) { [void][System.IO.Directory]::CreateDirectory($d) }
        foreach ($f in @((Join-Path $script:DsMain 'Dup.zip'), (Join-Path $script:DsMain 'Only.zip'), (Join-Path $script:DsSupp 'Dup.zip'))) { [System.IO.File]::WriteAllText($f, 'zip') }
    }
    It 'counts the game once and keeps the supplementary copy as the one used' {
        # Mutation: sort without -Unique -> "3 game(s) available" and Main also lists Dup. Keep Dup in Main -> A and unattended runs extract it twice.
        $r = Select-GamesInteractiveCombined -zipSourceMain $script:DsMain -zipSourceSupp $script:DsSupp -installFolder $script:DsInstall -datIndex @{} -userProfilesDir '' -SelectAll
        @($script:DsHost | Where-Object { $_ -match '^\s*2 game\(s\) available to extract \(1 collection, 1 supplementary \[\+\]\)\.' }).Count | Should -Be 1
        @($r.Supp) | Should -Be @('Dup')
        @($r.Main) | Should -Be @('Only')
    }
    It 'lists the game on one row only, tagged as supplementary' {
        $script:DsAnswers = New-Object System.Collections.Generic.Queue[string]
        foreach ($a in 'L', 'B', 'B') { $script:DsAnswers.Enqueue($a) }
        Mock Read-HostSafe { $script:DsAnswers.Dequeue() }
        $null = Select-GamesInteractiveCombined -zipSourceMain $script:DsMain -zipSourceSupp $script:DsSupp -installFolder $script:DsInstall -datIndex @{} -userProfilesDir ''
        $rows = @($script:DsHost | Where-Object { $_ -match '\bDup$' })
        $rows.Count | Should -Be 1
        $rows[0] | Should -Match '\[\+\]'
    }
}

Describe 'AutoSync UserProfiles backup is only complete when it matches the live profiles' {
    BeforeEach {
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        $base = Join-Path $TestDrive ('bk-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:DsLive = Join-Path $base 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:DsLive)
        [System.IO.File]::WriteAllText((Join-Path $script:DsLive 'GameA.xml'), 'original')
        $script:DsStage = Join-Path $base 'INCOMPLETE_AutoSync_x'
        $script:DsFinal = Join-Path $base 'AutoSync_x'
        [void][System.IO.Directory]::CreateDirectory($script:DsStage)
        $null = Copy-TpmAutoSyncUserProfilesBackup -UserProfilesDir $script:DsLive -BackupPath $script:DsStage
    }
    It 'publishes the backup when nothing changed during the copy' {
        $path = Complete-TpmAutoSyncUserProfilesBackup -UserProfilesDir $script:DsLive -StagingPath $script:DsStage -FinalPath $script:DsFinal
        $path | Should -BeExactly $script:DsFinal
        Test-Path -LiteralPath (Join-Path $script:DsFinal 'TPM-BACKUP-COMPLETE.json') | Should -BeTrue
    }
    It 'refuses to publish when a profile changed after it was copied, and keeps the incomplete name' {
        # Mutation: complete the staged copy without comparing it with the live tree -> a stale backup is offered for restore.
        [System.IO.File]::WriteAllText((Join-Path $script:DsLive 'GameA.xml'), 'saved by TeknoParrotUI during the copy')
        { Complete-TpmAutoSyncUserProfilesBackup -UserProfilesDir $script:DsLive -StagingPath $script:DsStage -FinalPath $script:DsFinal } | Should -Throw '*profiles changed*'
        Test-Path -LiteralPath $script:DsFinal | Should -BeFalse
        Test-Path -LiteralPath $script:DsStage | Should -BeTrue
    }
    It 'refuses when a new profile appeared during the copy' {
        [System.IO.File]::WriteAllText((Join-Path $script:DsLive 'GameB.xml'), 'new')
        { Complete-TpmAutoSyncUserProfilesBackup -UserProfilesDir $script:DsLive -StagingPath $script:DsStage -FinalPath $script:DsFinal } | Should -Throw '*profiles changed*'
        Test-Path -LiteralPath $script:DsFinal | Should -BeFalse
    }
}

Describe 'Support package follow-up when the finished ZIP is gone' {
    It 'tells the user the ZIP is gone instead of saying nothing' {
        # Mutation: return silently when the ZIP is missing or was moved by a security program.
        $script:DsHost = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:DsHost.Add([string]$Object) }
        $root = Join-Path $TestDrive 'SupportPackages'
        [void][System.IO.Directory]::CreateDirectory($root)
        $r = Invoke-TpmSupportPackageFollowUp -PackagePath (Join-Path $root 'gone.zip') -SupportPackagesRoot $root
        $r.Succeeded | Should -BeFalse
        $r.Choice | Should -BeExactly 'B'
        (($script:DsHost) -join ' ') | Should -Match 'support ZIP is no longer in the support package folder'
    }
}

Describe 'ReShade readiness for a game in a path over 259 characters' {
    BeforeAll {
        function New-LpPeBytes([uint16]$Machine) {
            $bytes = New-Object byte[] 128
            $bytes[0] = 0x4D; $bytes[1] = 0x5A; $bytes[0x3C] = 0x40
            $bytes[0x40] = 0x50; $bytes[0x41] = 0x45
            $bytes[0x44] = [byte]($Machine -band 0xFF); $bytes[0x45] = [byte]($Machine -shr 8)
            return $bytes
        }
        $deep = Split-Path -Parent $script:LongExe
        $script:LpFiles = @{ x86 = (Join-Path $deep 'pe32.exe'); x64 = (Join-Path $deep 'pe64.exe'); junk = $script:LongExe }
        [System.IO.File]::WriteAllBytes('\\?\' + $script:LpFiles.x86, (New-LpPeBytes 0x014C))
        [System.IO.File]::WriteAllBytes('\\?\' + $script:LpFiles.x64, (New-LpPeBytes 0x8664))
        $script:LpRsProfiles = Join-Path $TestDrive 'lp-rs-profiles'
        [void][System.IO.Directory]::CreateDirectory($script:LpRsProfiles)
        foreach ($key in $script:LpFiles.Keys) {
            [System.IO.File]::WriteAllText((Join-Path $script:LpRsProfiles ('Lp-' + $key + '.xml')), ('<GameProfile><GamePath>{0}</GamePath></GameProfile>' -f $script:LpFiles[$key]))
        }
        $script:LpRsDll = Join-Path $TestDrive 'lp-ReShade64.dll'
        [System.IO.File]::WriteAllText($script:LpRsDll, 'x64 dll')
    }
    BeforeEach {
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmReShadeGameLabel { [string]$Fallback }
        Mock Get-ReShadeTargetInfo { [pscustomobject]@{ TargetDir = [string]$ExeDir; DllName = 'dxgi.dll' } }
        Mock Get-TpmReShadeOwnershipClassification { [pscustomobject]@{ Status = 'NotInstalled'; Detail = 'fixture' } }
    }
    It 'reads whether the game is 32-bit or 64-bit' {
        # Mutation: open the exe with the plain path -> $null on Windows PowerShell 5.1, so setup treats a readable game as unknown.
        Get-ExeArchitecture -ExePath $script:LpFiles.x86 | Should -BeExactly 'x86'
        Get-ExeArchitecture -ExePath $script:LpFiles.x64 | Should -BeExactly 'x64'
        Get-ExeArchitecture -ExePath $script:LpFiles.junk | Should -BeNullOrEmpty
    }
    It 'counts a game as ready only when the install can really handle it' {
        # Mutation: treat an unknown or 32-bit game as ready -> "N can be changed" counts games the install then refuses.
        $games = @(Get-ChildItem -LiteralPath $script:LpRsProfiles -Filter 'Lp-*.xml' | Sort-Object Name)
        $definition = [pscustomobject]@{ ProfileId = 'Levels'; Effects = @() }
        $summary = Get-TpmReShadeApplyPreflight -SelectedGames $games -ProfileDefinition $definition -SourceDll $script:LpRsDll
        @($summary.Records | Where-Object Game -eq 'Lp-x64')[0].Status | Should -BeExactly 'Ready'
        $x86 = @($summary.Records | Where-Object Game -eq 'Lp-x86')[0]
        $x86.Status | Should -BeExactly 'Unsafe'
        $x86.Detail | Should -BeExactly '32-bit game: the 32-bit ReShade file (ReShade32.dll) was not found.'
        @($summary.Records | Where-Object Game -eq 'Lp-junk')[0].Detail | Should -Match 'could not tell whether this game is 32-bit or 64-bit'
        $summary.Ready | Should -Be 1
    }
}

Describe 'Library Health rows after a game could not be checked fully' {
    It 'does not print OK for GPU fix, force feedback and dgVoodoo2 when a game was left out' {
        # Mutation: print OK whenever the needed list is empty -> a game that threw during the scan is counted as fine.
        $result = [pscustomobject]@{
            DiscoveryComplete = $true; Registered = 3; Valid = @('A', 'B', 'C'); Broken = @(); Empty = @()
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @('B')
            OptionalCoverageUnavailable = $false; OptionalCheckFailed = 1; DetectedGpuVendor = 'NVIDIA'
            PostgresInventoryStatus = 'Complete'; PostgresNeeded = @(); PostgresConfigured = 0
        }
        $rows = @(Get-TpmLibraryHealthRows -Result $result)
        @($rows | Where-Object Area -eq 'GPU fix')[0].Text | Should -Be 'Could not check 1 game'
        @($rows | Where-Object Area -eq 'Force feedback')[0].Text | Should -Be 'Could not check 1 game'
        @($rows | Where-Object Area -eq 'dgVoodoo2')[0].Text | Should -Match '^Needs attention'
        $result.OptionalCheckFailed = 0
        @(Get-TpmLibraryHealthRows -Result $result | Where-Object Area -eq 'GPU fix')[0].Text | Should -Be 'OK'
    }
}

Describe 'PostgreSQL installer lookup tells a refusal from no answer' {
    BeforeEach {
        $script:ScriptVersion = '1.0'
        Mock Write-Log {}
        Mock Start-Sleep {}
    }
    It 'returns no installer link when GitHub answered without a usable .zip, and nothing when it did not answer' {
        # Mutation: return $null for every failure -> the caller cannot say "GitHub answered, but has no installer".
        Mock Invoke-TpmWebRequestSilently { [pscustomobject]@{ Content = '{"assets":[{"name":"guide.pdf","browser_download_url":"https://github.com/x/guide.pdf","size":1}]}' } }
        $noZip = Get-PostgresGuideRelease
        ($null -eq $noZip) | Should -BeFalse
        [string]$noZip.DownloadUrl | Should -BeNullOrEmpty
        Mock Invoke-TpmWebRequestSilently { throw 'The remote server returned an error: (404) Not Found.' }
        $gone = Get-PostgresGuideRelease
        ($null -eq $gone) | Should -BeFalse
        [string]$gone.DownloadUrl | Should -BeNullOrEmpty
        Mock Invoke-TpmWebRequestSilently { throw 'Unable to connect to the remote server' }
        ($null -eq (Get-PostgresGuideRelease)) | Should -BeTrue
        Mock Invoke-TpmWebRequestSilently { [pscustomobject]@{ Content = '{"assets":[{"name":"guide.zip","browser_download_url":"https://github.com/x/guide.zip","size":2048}]}' } }
        (Get-PostgresGuideRelease).DownloadUrl | Should -Be 'https://github.com/x/guide.zip'
    }
}
