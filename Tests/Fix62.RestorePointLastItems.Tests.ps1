#Requires -Module Pester

# FIX62 (issue #348): the last review items for the restore points and the
# Reset and Restore menu.
#
#  1. Restore all swapped the settings file in before it checked that no game
#     changed while the safety copy was made, so it had to undo the swap (and
#     could end in ACTION_REQUIRED). It now checks first and changes nothing.
#  2. A restore point file that was in use by another program at start-up was
#     taken for damage and made a new first restore point that could never be
#     removed. Only a missing copy or a proven mismatch counts as damage now.
#  3. A first restore point saved before any game existed blocked Reset all
#     (no games) and made Reset one game say "already matches" forever.
#
# The production script is parsed and only its function definitions are
# dot-sourced. Every file lives under TestDrive. TeknoParrot is never started or
# stopped (Wait-TpmForProcessClose is mocked). Each It names the product
# mutation that makes it fail.

BeforeAll {
    $script:Fix62PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix62PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX62 tests could not parse the production script.' }
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionText = @($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F62FunctionFile = Join-Path $TestDrive 'tpm-fix62-functions.ps1'
    [System.IO.File]::WriteAllText($script:F62FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F62FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    # ---- fixtures -----------------------------------------------------------

    function New-F62Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f62' + $Name + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $profiles = Join-Path $root 'UserProfiles'
        $stateDir = Join-Path $root 'State'
        New-Item -ItemType Directory -Path $profiles, $stateDir -Force | Out-Null
        $state = [pscustomobject]@{
            Log = New-Object System.Collections.Generic.List[string]
            Screen = New-Object System.Collections.Generic.List[string]
            Prompts = New-Object System.Collections.Generic.List[string]
            Answers = New-Object 'System.Collections.Generic.Queue[string]'
        }
        return [pscustomobject]@{
            Root = $root
            Profiles = $profiles
            Points = (Join-Path $root 'RestorePoints')
            Config = (Join-Path $stateDir 'TeknoParrot-Manager.config.json')
            State = $state
        }
    }

    function Set-F62File {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-F62Text {
        param([Parameter(Mandatory)][string]$Path)
        return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-F62Base64 {
        param([Parameter(Mandatory)][string]$Path)
        return [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }

    function Get-F62GameXml {
        param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
        return ('<GameProfile><GameName>{0}</GameName><Value>{1}</Value></GameProfile>' -f $Name, $Value)
    }

    function Get-F62ScreenText {
        param([Parameter(Mandatory)]$Fixture)
        return ((@($Fixture.State.Screen) -join ' ') -replace '\s+', ' ')
    }

    function Get-F62BaselineCount {
        param([Parameter(Mandatory)]$Fixture)
        return @(@(Get-TpmRestorePoints -RestorePointsRoot $Fixture.Points) | Where-Object { $_.Kind -eq 'Baseline' }).Count
    }

    function Get-F62CopyPath {
        param([Parameter(Mandatory)]$RestorePoint, [Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)][string]$RelativePath)
        return (Join-Path (Join-Path (Join-Path $Fixture.Profiles 'FullBackup') ([string]$RestorePoint.Record.UserProfilesBackup)) $RelativePath)
    }

    function Install-F62Mocks {
        param([Parameter(Mandatory)]$Fixture, [string[]]$Answers = @())
        $script:F62State = $Fixture.State
        $script:F62Hook = $null
        foreach ($answer in $Answers) { [void]$Fixture.State.Answers.Enqueue($answer) }
        # A hook runs once, right after a restore point was made and checked: the moment when a file can
        # still change before it is replaced.
        Mock Write-Log {
            [void]$script:F62State.Log.Add([string]$msg)
            if ($null -ne $script:F62Hook -and ([string]$msg) -like '*saved and verified*') {
                $hook = $script:F62Hook
                $script:F62Hook = $null
                & $hook
            }
        }
        Mock Write-Host { [void]$script:F62State.Screen.Add(([string]($Object -join ' '))) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Wait-TpmForProcessClose { return $true }
        Mock Get-ConsoleContentWidth { return 120 }
        Mock Read-HostSafe {
            [void]$script:F62State.Prompts.Add([string]$Prompt)
            if ($script:F62State.Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:F62State.Answers.Dequeue()
        }
    }

    # Two games and a settings file, then the first (Baseline) restore point.
    function New-F62Baseline {
        param([Parameter(Mandatory)]$Fixture)
        Set-F62File -Path (Join-Path $Fixture.Profiles 'GameA.xml') -Text (Get-F62GameXml -Name 'Game A' -Value 'a-old')
        Set-F62File -Path (Join-Path $Fixture.Profiles 'GameB.xml') -Text (Get-F62GameXml -Name 'Game B' -Value 'b-old')
        Set-F62File -Path $Fixture.Config -Text '{"TeknoParrotRoot":"C:\\TP","Marker":"settings-old"}'
        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $Fixture.Profiles -ConfigPath $Fixture.Config -RestorePointsRoot $Fixture.Points
        if (-not $startup.Succeeded) { throw ('Fixture baseline failed: ' + $startup.Reason) }
        return (Read-TpmRestorePoint -Path $startup.Path)
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix62PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Scope Script -Value $prior.Value } else { Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue }
    }
    Remove-Variable -Name TpmConfigRestoreRestartRequired -Scope Script -ErrorAction SilentlyContinue
}

Describe 'FIX62 Restore all stops before the settings file is touched (item 1)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'changes nothing, keeps the settings file byte for byte and asks for no action when a game changed while the safety copy was made' {
        # Mutation: remove the Get-TpmRestoreAllLastMinuteProblem call that sits before the settings file swap in
        # Restore-TpmRestorePointAll -> the settings file is swapped in first, the undo (made to fail here) is needed
        # and the outcome is ACTION_REQUIRED instead of FAILED_BEFORE_MUTATION.
        $fx = New-F62Fixture -Name 'earlygame'
        Install-F62Mocks -Fixture $fx
        $baseline = New-F62Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        $gameB = Join-Path $fx.Profiles 'GameB.xml'
        Set-F62File -Path $gameA -Text (Get-F62GameXml -Name 'Game A' -Value 'a-new')
        Set-F62File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $configNew = Get-F62Base64 -Path $fx.Config
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        $plan.ConfigChange | Should -BeExactly 'Replace'
        $edited = Get-F62GameXml -Name 'Game B' -Value 'b-edited-while-saving'
        $script:F62Hook = { [System.IO.File]::WriteAllText($gameB, $edited) }.GetNewClosure()
        Mock Undo-TpmRestorePointSettingsFile { throw 'The undo must not be needed: the settings file was never changed.' }

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'CHANGED_SINCE_PREVIEW'
        $result.Summary | Should -Match '^Nothing was changed\.'
        $result.RestartRequired | Should -BeFalse
        Get-F62Base64 -Path $fx.Config | Should -BeExactly $configNew
        Get-F62Text -Path $gameB | Should -BeExactly $edited
        Get-F62Text -Path $gameA | Should -Match 'a-new'
        $script:TpmConfigRestoreRestartRequired | Should -BeFalse
        Should -Invoke Undo-TpmRestorePointSettingsFile -Times 0 -Exactly
    }
}

Describe 'FIX62 a file in use is not damage (item 2)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'tells an error from reading a file apart from a file that is missing or wrong' -TestCases @(
        @{ Case = 'file in use (IOException)'; Make = { New-Object System.IO.IOException 'in use' }; Expected = $true }
        @{ Case = 'no access'; Make = { New-Object System.UnauthorizedAccessException 'denied' }; Expected = $true }
        @{ Case = 'in use, wrapped in another error'; Make = { New-Object System.InvalidOperationException 'outer', (New-Object System.IO.IOException 'in use') }; Expected = $true }
        @{ Case = 'file missing'; Make = { New-Object System.IO.FileNotFoundException 'missing' }; Expected = $false }
        @{ Case = 'folder missing'; Make = { New-Object System.IO.DirectoryNotFoundException 'missing' }; Expected = $false }
        @{ Case = 'unrelated error'; Make = { New-Object System.InvalidOperationException 'other' }; Expected = $false }
    ) {
        param($Case, $Make, $Expected)
        # Mutation: return $true for every exception (or $false for every one) in Test-TpmFileAccessException ->
        # a missing file is taken for a file in use (or the reverse), so damage is not told from a lock.
        Test-TpmFileAccessException -Exception (& $Make) | Should -Be $Expected
    }

    It 'makes a new first restore point when the saved copy is proven changed' {
        # Mutation: treat every failed check as "could not check" in Invoke-TpmStartupRestorePoint -> no new first
        # restore point is made for a copy whose bytes no longer match (a Startup point is made instead).
        $fx = New-F62Fixture -Name 'mismatch'
        Install-F62Mocks -Fixture $fx
        $first = New-F62Baseline -Fixture $fx
        Set-F62File -Path (Get-F62CopyPath -RestorePoint $first -Fixture $fx -RelativePath 'GameA.xml') -Text 'tampered bytes'
        $check = Test-TpmRestorePoint -RestorePoint $first -UserProfilesDir $fx.Profiles
        $check.Valid | Should -BeFalse
        $check.CouldNotCheck | Should -BeFalse

        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $startup.Succeeded | Should -BeTrue
        $startup.Created | Should -BeTrue
        $startup.Kind | Should -BeExactly 'Baseline'
        Get-F62BaselineCount -Fixture $fx | Should -Be 2
        Test-Path -LiteralPath $first.Path | Should -BeTrue
    }

    It 'makes no new first restore point and does not block start-up while a saved file is in use' {
        # Mutation: make Test-TpmRestorePoint report a read error as damage (no CouldNotCheck) -> a second Baseline is
        # made while the file is only locked, and it can never be removed.
        $fx = New-F62Fixture -Name 'locked'
        Install-F62Mocks -Fixture $fx
        $first = New-F62Baseline -Fixture $fx
        $lockedPath = Get-F62CopyPath -RestorePoint $first -Fixture $fx -RelativePath 'GameA.xml'
        $stream = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $check = Test-TpmRestorePoint -RestorePoint $first -UserProfilesDir $fx.Profiles
            $check.Valid | Should -BeFalse
            $check.CouldNotCheck | Should -BeTrue

            $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

            $startup.Succeeded | Should -BeTrue
            $startup.Kind | Should -BeExactly 'Startup'
            Get-F62BaselineCount -Fixture $fx | Should -Be 1
            (@($fx.State.Log) -join ' ') | Should -Match 'could not be checked right now'
        } finally {
            $stream.Dispose()
        }
        (Test-TpmRestorePoint -RestorePoint $first -UserProfilesDir $fx.Profiles).Valid | Should -BeTrue
    }
}

Describe 'FIX62 a first restore point without games (item 3)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'makes a first restore point with games once games exist, and Reset one game works against it' {
        # Mutation: count a Baseline without top-level *.xml as the first restore point in Invoke-TpmStartupRestorePoint
        # -> no Baseline with games is made; Reset one game then compares against the empty one and finds nothing to put back.
        $fx = New-F62Fixture -Name 'emptyfirst'
        Install-F62Mocks -Fixture $fx -Answers @('1', '1', 'YES')
        $empty = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $empty.Succeeded | Should -BeTrue
        $empty.Kind | Should -BeExactly 'Baseline'
        $again = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $again.Created | Should -BeFalse
        Get-F62BaselineCount -Fixture $fx | Should -Be 1

        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F62File -Path $gameA -Text (Get-F62GameXml -Name 'Game A' -Value 'a-old')
        $second = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $second.Succeeded | Should -BeTrue
        $second.Created | Should -BeTrue
        $second.Kind | Should -BeExactly 'Baseline'
        Get-F62BaselineCount -Fixture $fx | Should -Be 2
        Test-Path -LiteralPath $empty.Path | Should -BeTrue
        $third = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $third.Created | Should -BeFalse
        Get-F62BaselineCount -Fixture $fx | Should -Be 2

        Set-F62File -Path $gameA -Text (Get-F62GameXml -Name 'Game A' -Value 'a-new')
        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $menu.Result.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-F62Text -Path $gameA | Should -Match 'a-old'
    }

    It 'says plainly that the restore point has no games instead of "already matches" when Reset one game is chosen' {
        # Mutation: remove the no-games check in Invoke-TpmResetRestoreOneGame -> the result is NO_OP / ALREADY_MATCHES
        # ("Every game in this restore point already matches it") although the restore point has no games at all.
        $fx = New-F62Fixture -Name 'nogamesone'
        Install-F62Mocks -Fixture $fx -Answers @('1')
        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $startup.Succeeded | Should -BeTrue
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F62File -Path $gameA -Text (Get-F62GameXml -Name 'Game A' -Value 'a-added')

        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $menu.Result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $menu.Result.ReasonCode | Should -BeExactly 'RESTORE_POINT_HAS_NO_GAMES'
        $menu.Result.Summary | Should -Match 'no games to put back'
        $menu.Result.Summary | Should -Not -Match 'already matches'
        (Get-F62ScreenText -Fixture $fx) | Should -Match 'no games to put back'
        Get-F62Text -Path $gameA | Should -Match 'a-added'
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
    }

    It 'lets cleanup remove an empty first restore point only once another one with games exists' {
        # Mutation: keep excluding every Baseline in Get-TpmRestorePointRemovalCandidates (or let Remove-TpmRestorePoint
        # remove a Baseline without -AllowEmptyBaseline, or one that has games) -> the empty one can never be removed,
        # or the first restore point with games can be.
        $fx = New-F62Fixture -Name 'cleanupempty'
        Install-F62Mocks -Fixture $fx
        $empty = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $empty.Succeeded | Should -BeTrue
        @(Get-TpmRestorePointRemovalCandidates -RestorePoints @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points) -KeepCount 0).Count | Should -Be 0

        Set-F62File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F62GameXml -Name 'Game A' -Value 'a-old')
        $withGames = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $withGames.Kind | Should -BeExactly 'Baseline'
        $points = @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points)
        $candidates = @(Get-TpmRestorePointRemovalCandidates -RestorePoints $points -KeepCount 0)
        $candidates.Count | Should -Be 1
        $candidates[0].Path | Should -Be $empty.Path

        (Remove-TpmRestorePoint -RestorePoint $candidates[0] -UserProfilesDir $fx.Profiles).Removed | Should -BeFalse
        Test-Path -LiteralPath $empty.Path | Should -BeTrue
        $gamesPoint = @($points | Where-Object { $_.Path -eq $withGames.Path })[0]
        (Remove-TpmRestorePoint -RestorePoint $gamesPoint -UserProfilesDir $fx.Profiles -AllowEmptyBaseline).Removed | Should -BeFalse
        Test-Path -LiteralPath $withGames.Path | Should -BeTrue

        (Remove-TpmRestorePoint -RestorePoint $candidates[0] -UserProfilesDir $fx.Profiles -AllowEmptyBaseline).Removed | Should -BeTrue
        Test-Path -LiteralPath $empty.Path | Should -BeFalse
        Test-Path -LiteralPath $withGames.Path | Should -BeTrue
    }
}

Describe 'FIX62 Windows PowerShell 5.1 reports a file in use only through the error record' {
    It 'recognizes a file that is open elsewhere (Get-FileHash throws a bare WriteErrorException) and not a missing file' {
        # Mutation: ignore the ErrorRecord in Test-TpmFileAccessException -> a locked file is not recognized, a second
        # restore point is made while the file is only in use (the FIX62 item 2 failure seen on the first test-PC run).
        $dir = Join-Path $TestDrive ('f62-lock-' + [guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($dir)
        $path = Join-Path $dir 'a.xml'
        [System.IO.File]::WriteAllText($path, '<x/>')
        $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $locked = $null
            try { $null = Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop } catch { $locked = $_ }
            $locked | Should -Not -BeNullOrEmpty
            Test-TpmFileAccessException -Exception $locked.Exception -ErrorRecord $locked | Should -BeTrue
        } finally {
            $stream.Dispose()
        }
        $missing = $null
        try { $null = Get-FileHash -LiteralPath (Join-Path $dir 'nope.xml') -Algorithm SHA256 -ErrorAction Stop } catch { $missing = $_ }
        $missing | Should -Not -BeNullOrEmpty
        Test-TpmFileAccessException -Exception $missing.Exception -ErrorRecord $missing | Should -BeFalse
    }
}