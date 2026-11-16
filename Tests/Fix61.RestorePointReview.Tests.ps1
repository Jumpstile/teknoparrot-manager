#Requires -Module Pester

# FIX61 (issue #348): fixes for every finding of the independent review of the
# FIX58 restore points and the Reset and Restore menu.
#
#  1. The start-up block printed its messages through helpers that were defined
#     later in the script (PowerShell does not hoist), so the first failure lost
#     its reason. The helpers now sit above the block, and the text writer falls
#     back to plain output when they are missing.
#  2. Menu and clean-up used restore points made for another TeknoParrot folder.
#  3. A first restore point whose saved copy was damaged blocked every new one.
#  4. A restore point without game settings was offered and then failed.
#  5. Files were hashed once, long before they were replaced.
#  6. .NET Framework path limits (folders 248, files 260) were not respected.
#  7. A locked file ended the whole program from the menu.
#  8. The ALL question counted only the changed files.
#  9. Links (junctions) inside UserProfiles were deleted by Restore all.
# 10. Headings, prompts, lists and legacy restore lines did not follow the
#     console width.
#
# The production script is parsed. Its function definitions are dot-sourced and
# the start-up block is cut out of the syntax tree and run in a separate
# runspace; no other production code runs. Every file lives under TestDrive.
# TeknoParrot is never started or stopped (Wait-TpmForProcessClose is mocked).
# Each It names the product mutation that makes it fail.

BeforeAll {
    $script:Fix61PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix61PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX61 tests could not parse the production script.' }
    $script:F61Source = $source
    $script:F61Ast = $ast
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $script:F61Funcs = @{}
    foreach ($definition in $definitions) {
        if (-not $script:F61Funcs.ContainsKey($definition.Name)) { $script:F61Funcs[$definition.Name] = $definition }
    }
    $functionText = @($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:F61FunctionFile = Join-Path $TestDrive 'tpm-fix61-functions.ps1'
    [System.IO.File]::WriteAllText($script:F61FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:F61FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')

    # ---- fixtures -----------------------------------------------------------

    function New-F61Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f61' + $Name + [guid]::NewGuid().ToString('N').Substring(0, 6))
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

    # The same restore point folder and screen, but another UserProfiles folder:
    # what a moved or renamed TeknoParrot folder looks like to the restore points.
    function New-F61MovedFixture {
        param([Parameter(Mandatory)]$Original, [Parameter(Mandatory)][string]$Name)
        $moved = New-F61Fixture -Name $Name
        $moved.Points = $Original.Points
        $moved.State = $Original.State
        return $moved
    }

    function Set-F61File {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyString()][string]$Text)
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-F61Text {
        param([Parameter(Mandatory)][string]$Path)
        return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-F61Sha {
        param([Parameter(Mandatory)][string]$Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    }

    function Get-F61Base64 {
        param([Parameter(Mandatory)][string]$Path)
        return [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($Path))
    }

    function Get-F61GameXml {
        param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value)
        return ('<GameProfile><GameName>{0}</GameName><Value>{1}</Value></GameProfile>' -f $Name, $Value)
    }

    function Get-F61ScreenText {
        param([Parameter(Mandatory)]$Fixture)
        return ((@($Fixture.State.Screen) -join ' ') -replace '\s+', ' ')
    }

    # Relative path of exactly Length characters made of folders of at most 40 characters.
    function New-F61RelPath {
        param([Parameter(Mandatory)][int]$Length)
        $parts = New-Object System.Collections.Generic.List[string]
        $left = $Length
        while ($left -gt 0) {
            $take = [Math]::Min(40, $left)
            if (($left - $take) -eq 1) { $take = $take - 1 }
            [void]$parts.Add(('a' * $take))
            $left = $left - $take
            if ($left -gt 0) { $left = $left - 1 }
        }
        return ($parts -join '\')
    }

    # Length of the staged backup folder New-TpmRestorePoint plans for.
    function Get-F61BackupDirLength {
        param([Parameter(Mandatory)][string]$Profiles, [string]$Kind = 'Baseline')
        return (Join-Path (Join-Path $Profiles 'FullBackup') ((Get-TpmUserProfilesBackupStagingPrefix) + $Kind + '_yyyy-MM-dd_HH-mm-ss_fff_12345678')).Length
    }

    function Install-F61Mocks {
        param([Parameter(Mandatory)]$Fixture, [string[]]$Answers = @(), [int]$Width = 120)
        $script:F61State = $Fixture.State
        $script:F61Width = $Width
        $script:F61Hook = $null
        foreach ($answer in $Answers) { [void]$Fixture.State.Answers.Enqueue($answer) }
        # A hook runs once, right after a restore point was made and checked: the moment the
        # review described, when a file can still change before it is replaced.
        Mock Write-Log {
            [void]$script:F61State.Log.Add([string]$msg)
            if ($null -ne $script:F61Hook -and ([string]$msg) -like '*saved and verified*') {
                $hook = $script:F61Hook
                $script:F61Hook = $null
                & $hook
            }
        }
        Mock Write-Host { [void]$script:F61State.Screen.Add(([string]($Object -join ' '))) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Wait-TpmForProcessClose { return $true }
        Mock Get-ConsoleContentWidth { return [int]$script:F61Width }
        Mock Read-HostSafe {
            [void]$script:F61State.Prompts.Add([string]$Prompt)
            if ($script:F61State.Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            return $script:F61State.Answers.Dequeue()
        }
    }

    # Two games and a settings file, then the first (Baseline) restore point.
    function New-F61Baseline {
        param([Parameter(Mandatory)]$Fixture)
        Set-F61File -Path (Join-Path $Fixture.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-old')
        Set-F61File -Path (Join-Path $Fixture.Profiles 'GameB.xml') -Text (Get-F61GameXml -Name 'Game B' -Value 'b-old')
        Set-F61File -Path $Fixture.Config -Text '{"TeknoParrotRoot":"C:\\TP","Marker":"settings-old"}'
        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $Fixture.Profiles -ConfigPath $Fixture.Config -RestorePointsRoot $Fixture.Points
        if (-not $startup.Succeeded) { throw ('Fixture baseline failed: ' + $startup.Reason) }
        return (Read-TpmRestorePoint -Path $startup.Path)
    }

    function New-F61Junction {
        param([Parameter(Mandatory)][string]$Link, [Parameter(Mandatory)][string]$Target)
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $Target 'keep.txt'), 'target survives', (New-Object System.Text.UTF8Encoding $false))
        $null = & cmd.exe /c mklink /J $Link $Target 2>&1
        if (-not (Test-Path -LiteralPath $Link -PathType Container)) { return $false }
        return (([System.IO.File]::GetAttributes($Link) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    }

    function Remove-F61Junction {
        param([Parameter(Mandatory)][string]$Link)
        # Non-recursive: removes only the link, never the folder it points to.
        if (Test-Path -LiteralPath $Link) { [System.IO.Directory]::Delete($Link) }
    }

    # ---- start-up block, cut out of the production syntax tree --------------

    function Get-F61StartupBlock {
        $assignment = @($script:F61Ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $args[0].Left.Extent.Text -eq '$startupRestorePointFailed' -and
                    $args[0].Right.Extent.Text -eq '$false'
                }, $true)) | Select-Object -First 1
        if ($null -eq $assignment) { throw 'The start-up restore point block was not found.' }
        $statements = @($assignment.Parent.Statements)
        $index = [array]::IndexOf($statements, $assignment)
        $block = @($statements[$index], $statements[$index + 1], $statements[$index + 2])
        $startOffset = $block[0].Extent.StartOffset
        $endOffset = $block[2].Extent.EndOffset
        return [pscustomobject]@{
            StartLine = [int]$assignment.Extent.StartLineNumber
            Statements = $block
            Text = $script:F61Source.Substring($startOffset, $endOffset - $startOffset)
        }
    }

    function Get-F61CommandNames {
        param([Parameter(Mandatory)]$Node)
        return @($Node.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
    }

    # Every function of the script that the given syntax nodes call, directly or through other functions.
    function Get-F61ReachableFunctions {
        param([Parameter(Mandatory)][object[]]$Roots)
        $seen = @{}
        $queue = New-Object System.Collections.Generic.Queue[string]
        foreach ($root in $Roots) {
            foreach ($name in (Get-F61CommandNames -Node $root)) {
                if (-not $seen.ContainsKey($name)) { $seen[$name] = $true; $queue.Enqueue($name) }
            }
        }
        while ($queue.Count -gt 0) {
            $name = $queue.Dequeue()
            if (-not $script:F61Funcs.ContainsKey($name)) { continue }
            foreach ($inner in (Get-F61CommandNames -Node $script:F61Funcs[$name])) {
                if (-not $seen.ContainsKey($inner)) { $seen[$inner] = $true; $queue.Enqueue($inner) }
            }
        }
        return @($seen.Keys | Where-Object { $script:F61Funcs.ContainsKey($_) } | Sort-Object)
    }

    # Runs the real start-up block in a clean runspace with stubs for the heavy parts. Helpers = None leaves
    # Split-TextForMenuWidth and Get-ConsoleContentWidth undefined, like a first launch with the old order.
    function Invoke-F61StartupBlock {
        param(
            [bool]$Unattended = $false,
            [bool]$Resume = $false,
            [bool]$StartupSucceeds = $true,
            [string]$Reason = 'The disk is full.',
            [ValidateSet('None', 'Wrapping')][string]$Helpers = 'Wrapping',
            [int]$Width = 80
        )
        $block = Get-F61StartupBlock
        $parts = New-Object System.Collections.Generic.List[string]
        $prelude = @'
$ErrorActionPreference = 'Stop'
$global:F61Screen = New-Object System.Collections.Generic.List[string]
$global:F61Calls = @{ Startup = 0; Save = 0 }
$global:F61StartupResult = [pscustomobject]@{ Succeeded = __SUCCEEDS__; Created = __SUCCEEDS__; Reused = $false; Kind = 'Baseline'; Path = $null; Reason = '__REASON__'; RemovableCount = 0 }
function Write-Host { param([Parameter(Position = 0)][AllowEmptyString()][object]$Object = '', [object]$ForegroundColor) [void]$global:F61Screen.Add([string]$Object) }
function Write-Log { param([string]$msg) }
function Save-Config { $global:F61Calls.Save++; return $true }
function Invoke-TpmStartupRestorePoint { param($UserProfilesDir, $ConfigPath) $global:F61Calls.Startup++; return $global:F61StartupResult }
$Unattended = __UNATTENDED__
$isPostgresRecoveryResume = __RESUME__
$userProfilesDir = 'C:\Fake\UserProfiles'
$configPath = 'C:\Fake\config.json'
'@
        $prelude = $prelude.Replace('__SUCCEEDS__', $(if ($StartupSucceeds) { '$true' } else { '$false' })).Replace('__REASON__', $Reason.Replace("'", "''")).Replace('__UNATTENDED__', $(if ($Unattended) { '$true' } else { '$false' })).Replace('__RESUME__', $(if ($Resume) { '$true' } else { '$false' }))
        [void]$parts.Add($prelude)
        foreach ($name in @('Get-TpmResetRestoreLineWidth', 'Write-TpmText', 'Write-TpmResetRestoreText', 'Get-TpmRestorePointKeepCount')) { [void]$parts.Add($script:F61Funcs[$name].Extent.Text) }
        if ($Helpers -eq 'Wrapping') {
            [void]$parts.Add($script:F61Funcs['Split-TextForMenuWidth'].Extent.Text)
            [void]$parts.Add(('function Get-ConsoleContentWidth {{ return {0} }}' -f $Width))
        }
        [void]$parts.Add($block.Text)
        [void]$parts.Add('[pscustomobject]@{ Screen = @($global:F61Screen); Startup = $global:F61Calls.Startup; Save = $global:F61Calls.Save }')
        $threw = ''
        $result = $null
        $shell = [powershell]::Create()
        try {
            [void]$shell.AddScript(($parts -join "`r`n"))
            try {
                $output = @($shell.Invoke())
                $result = $output | Select-Object -Last 1
            } catch {
                $threw = $_.Exception.Message
            }
        } finally {
            $shell.Dispose()
        }
        return [pscustomobject]@{
            Threw = $threw
            Screen = $(if ($null -ne $result) { @($result.Screen) } else { @() })
            Startup = $(if ($null -ne $result) { [int]$result.Startup } else { -1 })
            Save = $(if ($null -ne $result) { [int]$result.Save } else { -1 })
        }
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix61PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Scope Script -Value $prior.Value } else { Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue }
    }
    Remove-Variable -Name TpmConfigRestoreRestartRequired -Scope Script -ErrorAction SilentlyContinue
}

Describe 'FIX61 start-up block (finding 1 and the start-up coverage of finding 11)' {
    It 'defines every function the start-up block reaches above the block' {
        # Mutation: move Split-TextForMenuWidth or Get-ConsoleContentWidth back below the start-up block ->
        # the function is defined after the block and is listed as late; the first launch fails to print.
        $block = Get-F61StartupBlock
        $reached = @(Get-F61ReachableFunctions -Roots $block.Statements)
        $reached | Should -Contain 'Write-TpmResetRestoreText'
        $reached | Should -Contain 'Split-TextForMenuWidth'
        $reached | Should -Contain 'Get-ConsoleContentWidth'
        $reached | Should -Contain 'Invoke-TpmStartupRestorePoint'
        $late = @($reached | Where-Object { $script:F61Funcs[$_].Extent.StartLineNumber -gt $block.StartLine })
        ($late -join ', ') | Should -BeExactly ''
    }

    It 'still shows the failure reason when the width helpers do not exist' {
        # Mutation: call Split-TextForMenuWidth in Write-TpmResetRestoreText without the Get-Command guard (the call is no longer
        # inside a try/catch, so the guard is the only protection) -> the run stops with "'Split-TextForMenuWidth' is not recognized" and the reason is lost.
        $run = Invoke-F61StartupBlock -StartupSucceeds $false -Reason 'The disk is full.' -Helpers 'None'
        $run.Threw | Should -BeExactly ''
        $run.Screen | Should -Contain '  Reason: The disk is full.'
        (($run.Screen -join ' ') -replace '\s+', ' ') | Should -Match 'could not save a checked restore point'
        $run.Save | Should -Be 0
    }

    It 'wraps the start-up messages to the console width at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the start-up messages without wrapping -> a line is longer than the console.
        $run = Invoke-F61StartupBlock -StartupSucceeds $false -Reason 'The disk is full and nothing could be written to it.' -Helpers 'Wrapping' -Width $Width
        $run.Threw | Should -BeExactly ''
        $tooLong = @($run.Screen | Where-Object { $_.Length -ge $Width })
        ($tooLong -join "`n") | Should -BeExactly ''
        (($run.Screen -join ' ') -replace '\s+', ' ') | Should -Match 'Reason: The disk is full and nothing could be written to it\.'
    }

    It 'takes no restore point for an unattended run and still saves the settings' {
        # Mutation: drop "-not $Unattended" from the start-up block -> the restore point is made for scheduled runs.
        $run = Invoke-F61StartupBlock -Unattended $true -StartupSucceeds $true
        $run.Threw | Should -BeExactly ''
        $run.Startup | Should -Be 0
        $run.Save | Should -Be 1
    }

    It 'takes no restore point for the protected PostgreSQL resume and still saves the settings' {
        # Mutation: drop "-not $isPostgresRecoveryResume" from the start-up block -> the resume path writes a restore point.
        $run = Invoke-F61StartupBlock -Resume $true -StartupSucceeds $true
        $run.Threw | Should -BeExactly ''
        $run.Startup | Should -Be 0
        $run.Save | Should -Be 1
    }

    It 'skips the start-up settings save and says why when the restore point failed' {
        # Mutation: call Save-Config even when $startupRestorePointFailed is set -> Save is 1.
        $run = Invoke-F61StartupBlock -StartupSucceeds $false -Reason 'There is not enough free disk space.'
        $run.Startup | Should -Be 1
        $run.Save | Should -Be 0
        $text = ($run.Screen -join ' ') -replace '\s+', ' '
        $text | Should -Match 'Reason: There is not enough free disk space\.'
        $text | Should -Match 'Your settings were not saved at start-up'
    }

    It 'saves the settings after a restore point that was made' {
        # Mutation: leave $startupRestorePointFailed set after success -> the settings are never saved.
        $run = Invoke-F61StartupBlock -StartupSucceeds $true
        $run.Startup | Should -Be 1
        $run.Save | Should -Be 1
        (($run.Screen -join ' ') -replace '\s+', ' ') | Should -Match 'Restore point saved and checked'
        (($run.Screen -join ' ') -replace '\s+', ' ') | Should -Not -Match 'Reason:'
    }
}

Describe 'FIX61 restore points follow the current TeknoParrot folder (finding 2)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'resets to the first restore point of this folder, not the older one of the old folder' {
        # Mutation: pick the oldest Baseline across all records in Invoke-TpmResetRestoreMenu ->
        # the old folder's point is used and Reset fails with "made for a different TeknoParrot folder".
        $old = New-F61Fixture -Name 'old'
        Install-F61Mocks -Fixture $old
        $oldBaseline = New-F61Baseline -Fixture $old
        $new = New-F61MovedFixture -Original $old -Name 'new'
        Set-F61File -Path (Join-Path $new.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-moved')
        Set-F61File -Path $new.Config -Text '{"Marker":"moved"}'

        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $new.Profiles -ConfigPath $new.Config -RestorePointsRoot $new.Points
        $startup.Succeeded | Should -BeTrue
        $startup.Created | Should -BeTrue
        $startup.Kind | Should -BeExactly 'Baseline'
        $sets = Select-TpmRestorePointsForFolder -RestorePoints @(Get-TpmRestorePoints -RestorePointsRoot $new.Points) -UserProfilesDir $new.Profiles
        @($sets.Current).Count | Should -Be 1
        @($sets.OtherFolder).Count | Should -Be 1
        $sets.OtherFolder[0].Path | Should -BeExactly $oldBaseline.Path

        Set-F61File -Path (Join-Path $new.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-edited')
        foreach ($answer in @('1', '1', 'YES')) { [void]$new.State.Answers.Enqueue($answer) }
        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $new.Profiles -ConfigPath $new.Config -RestorePointsRoot $new.Points

        $menu.Result.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-F61Text -Path (Join-Path $new.Profiles 'GameA.xml') | Should -Match 'a-moved'
        (Get-F61ScreenText -Fixture $new) | Should -Match 'made for another TeknoParrot folder, not used here'
        Test-Path -LiteralPath $oldBaseline.Path | Should -BeTrue
        Get-F61Text -Path (Join-Path $old.Profiles 'GameA.xml') | Should -Match 'a-old'
    }

    It 'lists only the restore points of this folder when a restore point is chosen' {
        # Mutation: list every readable record in the menu -> the old folder's two points are listed as well.
        $old = New-F61Fixture -Name 'old'
        Install-F61Mocks -Fixture $old
        $null = New-F61Baseline -Fixture $old
        Set-F61File -Path (Join-Path $old.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-second')
        (New-TpmRestorePoint -UserProfilesDir $old.Profiles -ConfigPath $old.Config -Kind 'Startup' -RestorePointsRoot $old.Points).Succeeded | Should -BeTrue
        $new = New-F61MovedFixture -Original $old -Name 'new'
        Set-F61File -Path (Join-Path $new.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-moved')
        (Invoke-TpmStartupRestorePoint -UserProfilesDir $new.Profiles -ConfigPath $new.Config -RestorePointsRoot $new.Points).Succeeded | Should -BeTrue
        foreach ($answer in @('4', 'B', 'B')) { [void]$new.State.Answers.Enqueue($answer) }

        $null = Invoke-TpmResetRestoreMenu -UserProfilesDir $new.Profiles -ConfigPath $new.Config -RestorePointsRoot $new.Points

        $listed = @($new.State.Screen | Where-Object { $_ -match '^\s+\d+\) \d{4}-\d{2}-\d{2} ' })
        $listed.Count | Should -Be 1
        # B in the restore point list goes back to the menu (menu, list, menu), it does not close Reset and Restore.
        $new.State.Prompts.Count | Should -Be 3
        $new.State.Answers.Count | Should -Be 0
    }

    It 'never counts or removes the restore points of another folder' {
        # Mutation: drop the folder filter in Get-TpmRestorePointRemovalCandidates / Invoke-TpmRestorePointCleanup ->
        # the old folder's startup points are counted for this folder, offered for removal and removed.
        $old = New-F61Fixture -Name 'old'
        Install-F61Mocks -Fixture $old
        $oldBaseline = New-F61Baseline -Fixture $old
        $oldMade = @()
        foreach ($value in @('one', 'two', 'three')) {
            Set-F61File -Path (Join-Path $old.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value $value)
            $point = New-TpmRestorePoint -UserProfilesDir $old.Profiles -ConfigPath $old.Config -Kind 'Startup' -RestorePointsRoot $old.Points
            $point.Succeeded | Should -BeTrue
            $oldMade += $point
        }
        $solo = New-F61MovedFixture -Original $old -Name 'solo'
        Set-F61File -Path (Join-Path $solo.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'solo')
        (Invoke-TpmStartupRestorePoint -UserProfilesDir $solo.Profiles -ConfigPath $solo.Config -RestorePointsRoot $solo.Points).Succeeded | Should -BeTrue
        Mock Get-TpmRestorePointKeepCount { return 1 }
        $all = @(Get-TpmRestorePoints -RestorePointsRoot $old.Points)

        @(Get-TpmRestorePointRemovalCandidates -RestorePoints $all -KeepCount 1 -UserProfilesDir $old.Profiles).Count | Should -Be 2
        @(Get-TpmRestorePointRemovalCandidates -RestorePoints $all -KeepCount 1 -UserProfilesDir $solo.Profiles).Count | Should -Be 0

        $result = Invoke-TpmRestorePointCleanup -RestorePoints $all -UserProfilesDir $solo.Profiles

        $result.ReasonCode | Should -BeExactly 'NOTHING_TO_REMOVE'
        Should -Invoke Read-HostSafe -Times 0 -Exactly
        Test-Path -LiteralPath $oldBaseline.Path | Should -BeTrue
        foreach ($point in $oldMade) { Test-Path -LiteralPath $point.Path | Should -BeTrue }
    }
}

Describe 'FIX61 a damaged first restore point (finding 3)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'makes a new first restore point, keeps the damaged record and marks it unusable' {
        # Mutation: count a Baseline that only has a readable record ($hasBaseline) in Invoke-TpmStartupRestorePoint ->
        # no new Baseline is made (a Startup point is made instead) and Reset has nothing to reset to.
        $fx = New-F61Fixture -Name 'damagedbase'
        Install-F61Mocks -Fixture $fx -Answers @('1', '1', 'YES')
        $first = New-F61Baseline -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-mid')
        Remove-Item -LiteralPath (Join-Path (Join-Path $fx.Profiles 'FullBackup') ([string]$first.Record.UserProfilesBackup)) -Recurse -Force

        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $startup.Succeeded | Should -BeTrue
        $startup.Created | Should -BeTrue
        $startup.Kind | Should -BeExactly 'Baseline'
        $points = @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points)
        @($points | Where-Object { $_.Kind -eq 'Baseline' }).Count | Should -Be 2
        Test-Path -LiteralPath $first.Path | Should -BeTrue

        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $menu.Result.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-F61Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -Match 'a-mid'
        (Get-F61ScreenText -Fixture $fx) | Should -Match 'cannot be used \(it is kept, but not offered for Reset\)'
    }
}

Describe 'FIX61 a restore point without game settings (finding 4)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'refuses Reset all up front, before any change or restore point' {
        # Mutation: remove the BACKUP_EMPTY pre-check (Get-TpmRestoreAllBlocker) -> the settings file is changed,
        # the legacy restore stops with BACKUP_EMPTY, and the settings file is changed back again.
        $fx = New-F61Fixture -Name 'emptybase'
        Install-F61Mocks -Fixture $fx -Answers @('3')
        $startup = Invoke-TpmStartupRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $startup.Succeeded | Should -BeTrue
        $startup.Kind | Should -BeExactly 'Baseline'
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-added')
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-added"}'
        $configBefore = Get-F61Base64 -Path $fx.Config

        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $menu.Result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $menu.Result.ReasonCode | Should -BeExactly 'RESTORE_POINT_HAS_NO_GAMES'
        Get-F61Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -Match 'a-added'
        Get-F61Base64 -Path $fx.Config | Should -BeExactly $configBefore
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        $fx.State.Prompts.Count | Should -Be 1
        Should -Invoke Wait-TpmForProcessClose -Times 0 -Exactly
    }
}

Describe 'FIX61 files are checked again right before they are replaced (finding 5)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'does not overwrite a game file that changed while the safety copy was being saved' {
        # Mutation: remove the re-hash (ExpectedCurrentSha256) in Invoke-TpmVerifiedFileSwap -> the newer file is replaced.
        $fx = New-F61Fixture -Name 'toctougame'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F61File -Path $gameA -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        $newSha = Get-F61Sha -Path $gameA
        $edited = Get-F61GameXml -Name 'Game A' -Value 'a-edited-while-saving'
        $script:F61Hook = { [System.IO.File]::WriteAllText($gameA, $edited) }.GetNewClosure()

        $result = Restore-TpmRestorePointGame -RestorePoint $baseline -UserProfilesDir $fx.Profiles -RelativePath 'GameA.xml' -ExpectedCurrentSha256 $newSha -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'CHANGED_SINCE_PREVIEW'
        Get-F61Text -Path $gameA | Should -BeExactly $edited
        @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.tpm-restore' -Force).Count | Should -Be 0
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 2
    }

    It 'changes nothing in Restore all when a game changed after the safety copy, and puts the settings file back' {
        # Mutation: remove the second Get-TpmRestoreAllLastMinuteProblem call (before Invoke-RestoreBackup) in Restore-TpmRestorePointAll ->
        # the game that was edited after the settings file swap is overwritten. (A change made before the swap is covered by Fix62.)
        $fx = New-F61Fixture -Name 'toctouall'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        $gameB = Join-Path $fx.Profiles 'GameB.xml'
        Set-F61File -Path $gameA -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $configNew = Get-F61Base64 -Path $fx.Config
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        $edited = Get-F61GameXml -Name 'Game B' -Value 'b-edited-while-saving'
        # The edit happens right after the settings file was swapped in, which is after the first final check and before the second.
        $script:F61ConfigPath = $fx.Config
        $script:F61AfterSwap = { [System.IO.File]::WriteAllText($gameB, $edited) }.GetNewClosure()
        Mock Invoke-TpmAtomicFileReplace {
            # Like the real replace, keep the bytes that are replaced at -Backup.
            [System.IO.File]::Replace($Source, $Destination, $(if ($Backup) { $Backup } else { [NullString]::Value }))
            if ($Destination -eq $script:F61ConfigPath) { & $script:F61AfterSwap }
        }

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        $result.ReasonCode | Should -BeExactly 'CHANGED_SINCE_PREVIEW'
        Get-F61Text -Path $gameA | Should -Match 'a-new'
        Get-F61Text -Path $gameB | Should -BeExactly $edited
        Get-F61Base64 -Path $fx.Config | Should -BeExactly $configNew
        $script:TpmConfigRestoreRestartRequired | Should -BeFalse
    }

    It 'does not overwrite the settings file when it changed after the safety copy' {
        # Mutation: drop -ExpectedCurrentSha256 from the settings file swap in Restore-TpmRestorePointAll ->
        # the user's edit of the settings file is replaced.
        $fx = New-F61Fixture -Name 'toctoucfg'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        $plan.ConfigChange | Should -BeExactly 'Replace'
        $configPath = $fx.Config
        $edited = '{"Marker":"user-edit-while-saving"}'
        $script:F61Hook = { [System.IO.File]::WriteAllText($configPath, $edited) }.GetNewClosure()

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'CHANGED_SINCE_PREVIEW'
        Get-F61Text -Path $fx.Config | Should -BeExactly $edited
        $script:TpmConfigRestoreRestartRequired | Should -BeFalse
    }

    It 'puts the old settings back when the settings file has moved since the restore point' {
        # Who gets hurt: a user who tidied up (the settings file moved) and then restores from an older restore point.
        # Mutation: bring back the 'OtherLocation' branch in Get-TpmRestorePointChangePlan -> Restore all says the settings were never saved and leaves them.
        $fx = New-F61Fixture -Name 'movedcfg'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        $movedConfig = Join-Path $fx.Root 'State2\TeknoParrot-Manager.config.json'
        New-Item -ItemType Directory -Path (Split-Path -Parent $movedConfig) -Force | Out-Null
        Set-F61File -Path $movedConfig -Text '{"Marker":"settings-new"}'

        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $movedConfig
        $plan.ConfigChange | Should -BeExactly 'Replace'

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $movedConfig -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-F61Text -Path $movedConfig | Should -Match 'settings-old'
        $script:TpmConfigRestoreRestartRequired = $false
    }
}

Describe 'FIX61 .NET Framework path limits (finding 6)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'allows folder paths up to 247 and file paths up to 259 characters' -TestCases @(
        @{ Length = 247; Directory = $true; Expected = $true }, @{ Length = 248; Directory = $true; Expected = $false },
        @{ Length = 259; Directory = $false; Expected = $true }, @{ Length = 260; Directory = $false; Expected = $false }
    ) {
        param($Length, $Directory, $Expected)
        # Mutation: change either limit in Test-TpmPathLengthAllowed (for example one limit for both) -> a boundary case flips.
        (Test-TpmPathLengthAllowed -Length $Length -Directory:$Directory) | Should -Be $Expected
    }

    It 'refuses a folder whose backup copy would be 248 characters and accepts 247' {
        # Mutation: apply the 259-character file limit to folders in New-TpmRestorePoint ->
        # 248 is refused only by Windows later, or drop the check -> the 248 case is not refused.
        # The longest folder is reported by a mocked footprint, so no deep folder is created.
        $fx = New-F61Fixture -Name 'dirlen'
        Install-F61Mocks -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a')
        $backupDir = Get-F61BackupDirLength -Profiles $fx.Profiles
        $script:F61Longest = 247 - $backupDir - 1
        if ($script:F61Longest -lt 3) { Set-ItResult -Skipped -Because 'the test folder is too deep to build this case'; return }
        Mock Get-TpmUserProfilesFootprint { [pscustomobject]@{ Bytes = [int64]100; LongestFileLength = 9; LongestDirectoryLength = $script:F61Longest + 1; ReparsePoints = @() } }

        $refused = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Baseline' -RestorePointsRoot $fx.Points

        $refused.Succeeded | Should -BeFalse
        $refused.Reason | Should -Match 'too long for Windows'
        Test-Path -LiteralPath (Join-Path $fx.Profiles 'FullBackup') | Should -BeFalse
        Test-Path -LiteralPath $fx.Points | Should -BeFalse

        Mock Get-TpmUserProfilesFootprint { [pscustomobject]@{ Bytes = [int64]100; LongestFileLength = 9; LongestDirectoryLength = $script:F61Longest; ReparsePoints = @() } }
        $accepted = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Baseline' -RestorePointsRoot $fx.Points
        $accepted.Succeeded | Should -BeTrue
    }

    It 'refuses a file whose backup copy would be 260 characters and accepts 259' {
        # Mutation: change the file limit in New-TpmRestorePoint -> 259 is refused or 260 is accepted.
        # The longest file is reported by a mocked footprint, so no long file name is created.
        $fx = New-F61Fixture -Name 'filelen'
        Install-F61Mocks -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a')
        $backupDir = Get-F61BackupDirLength -Profiles $fx.Profiles
        $script:F61Longest = 259 - $backupDir - 1
        if ($script:F61Longest -lt 9) { Set-ItResult -Skipped -Because 'the test folder is too deep to build this case'; return }
        Mock Get-TpmUserProfilesFootprint { [pscustomobject]@{ Bytes = [int64]100; LongestFileLength = $script:F61Longest + 1; LongestDirectoryLength = 0; ReparsePoints = @() } }

        $refused = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Baseline' -RestorePointsRoot $fx.Points

        $refused.Succeeded | Should -BeFalse
        $refused.Reason | Should -Match 'too long for Windows'
        Test-Path -LiteralPath (Join-Path $fx.Profiles 'FullBackup') | Should -BeFalse

        Mock Get-TpmUserProfilesFootprint { [pscustomobject]@{ Bytes = [int64]100; LongestFileLength = $script:F61Longest; LongestDirectoryLength = 0; ReparsePoints = @() } }
        $accepted = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Baseline' -RestorePointsRoot $fx.Points
        $accepted.Succeeded | Should -BeTrue
    }

    It 'checks the restore point folder including the temporary record name' {
        # Mutation: drop the +37 (temporary record name) from the restore point folder check ->
        # a root that is one character too long is accepted and the record cannot be written.
        $fx = New-F61Fixture -Name 'rootlen'
        Install-F61Mocks -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a')
        $base = Join-Path $TestDrive ('f61root' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        # Restore point root of 164 characters: staging folder 203, record 222, temporary record name 259.
        $fillerLength = 164 - $base.Length - 1
        if ($fillerLength -lt 3) { Set-ItResult -Skipped -Because 'the test folder is too deep to build this case'; return }

        $refused = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Baseline' -RestorePointsRoot (Join-Path $base (New-F61RelPath -Length ($fillerLength + 1)))

        $refused.Succeeded | Should -BeFalse
        $refused.Reason | Should -Match 'restore point folder path would be too long'
        Test-Path -LiteralPath $base | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Profiles 'FullBackup') | Should -BeFalse

        $accepted = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Baseline' -RestorePointsRoot (Join-Path $base (New-F61RelPath -Length $fillerLength))
        $accepted.Succeeded | Should -BeTrue
    }

    It 'stages a file next to a 238-character target and refuses a 239-character one without changing it' {
        # Mutation: leave the stage path out of the length check in Invoke-TpmVerifiedFileSwap ->
        # the 239-character target fails inside Windows instead of being refused with PATH_TOO_LONG.
        $fx = New-F61Fixture -Name 'swaplen'
        Install-F61Mocks -Fixture $fx
        $leaf = 'target.bin'
        $base = Join-Path $TestDrive ('f61swap' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $fillerLength = (238 - 1 - $leaf.Length) - $base.Length - 1
        if ($fillerLength -lt 3) { Set-ItResult -Skipped -Because 'the test folder is too deep to build this case'; return }
        $dir = Join-Path $base (New-F61RelPath -Length $fillerLength)
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $source = Join-Path $fx.Root 'source.bin'
        Set-F61File -Path $source -Text 'new-bytes'
        $sourceSha = Get-F61Sha -Path $source
        $target = Join-Path $dir $leaf
        Set-F61File -Path $target -Text 'old-bytes'
        (New-TpmVerifiedFileSwapStagePath -TargetPath $target).Length | Should -Be 259

        Invoke-TpmVerifiedFileSwap -SourcePath $source -TargetPath $target -ExpectedSha256 $sourceSha -ExpectedLength 9

        Get-F61Text -Path $target | Should -BeExactly 'new-bytes'
        $tooLongTarget = Join-Path $dir ($leaf + 'x')
        Set-F61File -Path $tooLongTarget -Text 'old-bytes'
        (New-TpmVerifiedFileSwapStagePath -TargetPath $tooLongTarget).Length | Should -Be 260
        $thrown = $null
        try { Invoke-TpmVerifiedFileSwap -SourcePath $source -TargetPath $tooLongTarget -ExpectedSha256 $sourceSha -ExpectedLength 9 } catch { $thrown = $_.Exception }
        ($null -ne $thrown) | Should -BeTrue
        $thrown.Data['TpmNoChange'] | Should -BeExactly 'PATH_TOO_LONG'
        Get-F61Text -Path $tooLongTarget | Should -BeExactly 'old-bytes'
        @(Get-ChildItem -LiteralPath $dir -Filter '*.tpm-restore' -Force).Count | Should -Be 0
    }

    It 'refuses one game before saving anything when its staged copy would be too long' {
        # Mutation: remove the stage path pre-check in Restore-TpmRestorePointGame -> the failure is no longer found before saving anything:
        # a BeforeReset restore point is made (restore point count 2 instead of 1) and Wait-TpmForProcessClose is called once.
        # (The result stays FAILED_BEFORE_MUTATION / PATH_TOO_LONG, because Invoke-TpmVerifiedFileSwap refuses the long path too.)
        $fx = New-F61Fixture -Name 'gamelen'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F61File -Path $gameA -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        $newSha = Get-F61Sha -Path $gameA
        Mock New-TpmVerifiedFileSwapStagePath { return ('x' * 300) }

        $result = Restore-TpmRestorePointGame -RestorePoint $baseline -UserProfilesDir $fx.Profiles -RelativePath 'GameA.xml' -ExpectedCurrentSha256 $newSha -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'PATH_TOO_LONG'
        Get-F61Text -Path $gameA | Should -Match 'a-new'
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        Should -Invoke Wait-TpmForProcessClose -Times 0 -Exactly
    }

    It 'refuses Restore all when the temporary safety copy needs a 248-character folder and goes ahead at 247' {
        # Mutation: remove the temporary snapshot path check in Get-TpmRestoreAllBlocker -> the settings file is changed
        # and changed back after the UserProfiles restore fails to make its snapshot.
        $fx = New-F61Fixture -Name 'snaplen'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        Mock Get-TpmLegacyRestoreRollbackPathLength { return 240 }
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $configNew = Get-F61Base64 -Path $fx.Config
        New-Item -ItemType Directory -Path (Join-Path $fx.Profiles 'abcdefg') -Force | Out-Null
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config

        $refused = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $refused.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $refused.ReasonCode | Should -BeExactly 'PATH_TOO_LONG'
        Get-F61Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -Match 'a-new'
        Get-F61Base64 -Path $fx.Config | Should -BeExactly $configNew
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        Should -Invoke Wait-TpmForProcessClose -Times 0 -Exactly

        Remove-Item -LiteralPath (Join-Path $fx.Profiles 'abcdefg') -Force
        New-Item -ItemType Directory -Path (Join-Path $fx.Profiles 'abcdef') -Force | Out-Null
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        $accepted = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points
        $accepted.Outcome | Should -BeExactly 'SUCCEEDED'
    }
}

Describe 'FIX61 a file that cannot be read (finding 7)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'gives a plain message naming the locked file and stays in the menu for option <Option>' -TestCases @(
        @{ Option = '1' }, @{ Option = '3' }
    ) {
        param($Option)
        # Mutation: remove the try/catch around Get-TpmRestorePointChangePlan in Invoke-TpmResetRestoreMenu ->
        # the file lock error leaves the menu (and ends the program).
        $fx = New-F61Fixture -Name 'locked'
        Install-F61Mocks -Fixture $fx -Answers @($Option)
        $null = New-F61Baseline -Fixture $fx
        $gameA = Join-Path $fx.Profiles 'GameA.xml'
        Set-F61File -Path $gameA -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        $stream = [System.IO.File]::Open($gameA, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        $script:F61Menu = $null
        try {
            { $script:F61Menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points } | Should -Not -Throw
        } finally {
            $stream.Dispose()
        }

        $script:F61Menu.Result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $script:F61Menu.Result.ReasonCode | Should -BeExactly 'CANNOT_READ_SETTINGS'
        $script:F61Menu.Result.Summary | Should -Match "could not read 'GameA\.xml'"
        (Get-F61ScreenText -Fixture $fx) | Should -Match 'GameA\.xml'
        Get-F61Text -Path $gameA | Should -Match 'a-new'
        @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
        $fx.State.Prompts.Count | Should -Be 1
    }
}

Describe 'FIX61 the ALL question counts every change (finding 8)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'counts the settings file and the folders, not only the changed files' {
        # Mutation: count only $changes.Count in Invoke-TpmResetRestoreAllGames -> "0 items" when only the settings
        # file differs and "1 item" in the second case.
        $fx = New-F61Fixture -Name 'allcount'
        Install-F61Mocks -Fixture $fx -Answers @('3', 'YES', 'no')
        $null = New-F61Baseline -Fixture $fx
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'

        $first = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $first.Result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        (Get-F61ScreenText -Fixture $fx) | Should -Match 'This changes 1 item in total'

        $fx.State.Screen.Clear()
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        New-Item -ItemType Directory -Path (Join-Path $fx.Profiles 'AddedFolder') -Force | Out-Null
        foreach ($answer in @('3', 'YES', 'no')) { [void]$fx.State.Answers.Enqueue($answer) }

        $second = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $second.Result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        (Get-F61ScreenText -Fixture $fx) | Should -Match 'This changes 3 items in total'
    }
}

Describe 'FIX61 links inside UserProfiles (finding 9)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'refuses Restore all while a junction exists, names it and changes nothing' {
        # Mutation: remove the link check in Get-TpmRestoreAllBlocker -> Restore all deletes the junction and
        # leaves an empty folder in its place.
        $fx = New-F61Fixture -Name 'junction'
        Install-F61Mocks -Fixture $fx -Answers @('3')
        $null = New-F61Baseline -Fixture $fx
        $link = Join-Path $fx.Profiles 'LinkDir'
        $target = Join-Path $fx.Root 'LinkTarget'
        if (-not (New-F61Junction -Link $link -Target $target)) { Set-ItResult -Skipped -Because 'a junction could not be created here'; return }
        try {
            Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
            Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
            $configNew = Get-F61Base64 -Path $fx.Config

            $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

            $menu.Result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
            $menu.Result.ReasonCode | Should -BeExactly 'LINK_INSIDE_USERPROFILES'
            $menu.Result.Summary | Should -Match 'LinkDir'
            Get-F61Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -Match 'a-new'
            Get-F61Base64 -Path $fx.Config | Should -BeExactly $configNew
            Test-Path -LiteralPath (Join-Path $target 'keep.txt') | Should -BeTrue
            ([System.IO.File]::GetAttributes($link) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 | Should -BeTrue
            @(Get-TpmRestorePoints -RestorePointsRoot $fx.Points).Count | Should -Be 1
            $fx.State.Prompts.Count | Should -Be 1
            Should -Invoke Wait-TpmForProcessClose -Times 0 -Exactly
        } finally {
            Remove-F61Junction -Link $link
        }
    }

    It 'records the links that exist when a restore point is made' {
        # Mutation: drop ReparsePoints from the restore point record in New-TpmRestorePoint -> the record lists no link.
        $fx = New-F61Fixture -Name 'junctionrec'
        Install-F61Mocks -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a')
        $link = Join-Path $fx.Profiles 'LinkDir'
        if (-not (New-F61Junction -Link $link -Target (Join-Path $fx.Root 'LinkTarget'))) { Set-ItResult -Skipped -Because 'a junction could not be created here'; return }
        try {
            $made = New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Baseline' -RestorePointsRoot $fx.Points

            $made.Succeeded | Should -BeTrue
            $made.RestorePoint.Record.ReparsePoints | Should -Contain 'LinkDir'
            @((Get-TpmUserProfilesFootprint -UserProfilesDir $fx.Profiles).ReparsePoints) | Should -Contain 'LinkDir'
        } finally {
            Remove-F61Junction -Link $link
        }
    }
}

Describe 'FIX61 screens follow the console width (finding 10)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'wraps the header, notes and lists at <Width> columns and keeps the hanging indent' -TestCases @(
        @{ Width = 40; Wraps = $true }, @{ Width = 50; Wraps = $true }, @{ Width = 120; Wraps = $false }
    ) {
        param($Width, $Wraps)
        # Mutation: print the header with fixed 44-dash lines, or list items without HangingIndent ->
        # a line is wider than the console, or a wrapped list line starts at the wrong column.
        $fx = New-F61Fixture -Name 'width'
        Install-F61Mocks -Fixture $fx -Answers @('4', 'B', 'B') -Width $Width
        $null = New-F61Baseline -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        (New-TpmRestorePoint -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -Kind 'Startup' -RestorePointsRoot $fx.Points).Succeeded | Should -BeTrue
        $fx.State.Screen.Clear()

        $null = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $lines = @($fx.State.Screen)
        $tooWide = @($lines | Where-Object { $_.Length -ge $Width })
        ($tooWide -join "`n") | Should -BeExactly ''
        $rule = @($lines | Where-Object { $_ -match '^-+$' })
        $rule.Count | Should -Be 2
        $rule[0].Length | Should -Be ([Math]::Min(44, $Width - 1))
        $itemIndex = -1
        for ($index = 0; $index -lt $lines.Count; $index++) { if ($lines[$index] -match '^ {4}1\) \d{4}-\d{2}-\d{2} ') { $itemIndex = $index; break } }
        $itemIndex | Should -BeGreaterThan -1
        if ($Wraps) {
            $lines[$itemIndex + 1] | Should -Match '^ {7}\S'
        } else {
            $lines[$itemIndex + 1] | Should -Not -Match '^ {7}\S'
        }
    }

    It 'asks short questions and explains them in wrapped lines at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: ask the old 70-character questions in one Read-HostSafe prompt ->
        # a prompt is longer than the console and wraps in the middle of the question.
        $fx = New-F61Fixture -Name 'prompts'
        Install-F61Mocks -Fixture $fx -Answers @('3', 'YES', 'no') -Width $Width
        $null = New-F61Baseline -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $fx.State.Screen.Clear()

        $menu = Invoke-TpmResetRestoreMenu -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $menu.Result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        $fx.State.Prompts.Count | Should -Be 3
        $longPrompts = @($fx.State.Prompts | Where-Object { ($_.Length + 2) -gt $Width })
        ($longPrompts -join "`n") | Should -BeExactly ''
        $tooWide = @($fx.State.Screen | Where-Object { $_.Length -ge $Width })
        ($tooWide -join "`n") | Should -BeExactly ''
        (Get-F61ScreenText -Fixture $fx) | Should -Match 'Any answer other than YES cancels'
        (Get-F61ScreenText -Fixture $fx) | Should -Match 'This changes 2 items in total'
        @($fx.State.Prompts | Where-Object { $_ -like '*Type ALL*' }).Count | Should -Be 1
    }

    It 'wraps the restore lines printed during Restore all at <Width> columns and leaves the ordinary restore alone' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: wrap in Write-TpmRestoreStatusLine without -Wrap, or never wrap ->
        # the ordinary restore text changes, or the Restore all text is wider than the console.
        $fx = New-F61Fixture -Name 'legacy'
        Install-F61Mocks -Fixture $fx -Width $Width
        $null = New-F61Baseline -Fixture $fx
        $outside = Join-Path $fx.Root 'Outside'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $fx.State.Screen.Clear()

        $wrapped = Invoke-RestoreBackupLegacy -userProfilesDir $fx.Profiles -SelectedBackupPath $outside -AlreadyConfirmed

        $wrapped.ReasonCode | Should -BeExactly 'BACKUP_UNAVAILABLE'
        $tooWide = @($fx.State.Screen | Where-Object { $_.Length -ge $Width })
        ($tooWide -join "`n") | Should -BeExactly ''
        (Get-F61ScreenText -Fixture $fx) | Should -Match 'ERROR: The chosen backup is not available -- restore aborted\. Nothing was changed\.'

        $fx.State.Screen.Clear()
        $plain = Invoke-RestoreBackupLegacy -userProfilesDir $fx.Profiles -SelectedBackupPath $outside

        $plain.ReasonCode | Should -BeExactly 'BACKUP_UNAVAILABLE'
        $fx.State.Screen | Should -Contain '  ERROR: The chosen backup is not available -- restore aborted. Nothing was changed.'
    }
}

Describe 'FIX61 Restore all failure paths (finding 11)' {
    BeforeEach { $script:TpmConfigRestoreRestartRequired = $false }

    It 'puts the settings file back when the UserProfiles restore does not finish' {
        # Mutation: remove Undo-TpmRestorePointSettingsFile from the profiles failure path in Restore-TpmRestorePointAll ->
        # the settings file stays on the restore point's version although the game settings were not restored.
        $fx = New-F61Fixture -Name 'undoafter'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $configNew = Get-F61Base64 -Path $fx.Config
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        Mock Invoke-RestoreBackup { return [pscustomobject]@{ Outcome = 'ROLLED_BACK_VERIFIED'; ReasonCode = 'RESTORE_COPY_FAILED_ROLLED_BACK'; Summary = 'The copy failed.' } }

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        $result.ReasonCode | Should -BeExactly 'PROFILES_RESTORE_NOT_COMPLETED'
        $result.RestartRequired | Should -BeFalse
        $script:TpmConfigRestoreRestartRequired | Should -BeFalse
        Get-F61Base64 -Path $fx.Config | Should -BeExactly $configNew
        Get-F61Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -Match 'a-new'
        Should -Invoke Invoke-RestoreBackup -Times 1 -Exactly
    }

    It 'asks for attention and blocks saving stale settings when the UserProfiles restore fails and the undo also fails' {
        # Mutation: do not set the restart latch when the settings undo fails ->
        # Save-Config writes the stale in-memory settings over the restored file.
        $fx = New-F61Fixture -Name 'undofail'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        Mock Invoke-RestoreBackup { return [pscustomobject]@{ Outcome = 'ACTION_REQUIRED'; ReasonCode = 'RESTORE_VERIFICATION_FAILED'; Summary = 'The restored profiles do not match.' } }
        Mock Undo-TpmRestorePointSettingsFile { throw 'the undo failed' }

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $result.ReasonCode | Should -BeExactly 'PROFILES_RESTORE_NEEDS_ATTENTION'
        $result.RestartRequired | Should -BeTrue
        $script:TpmConfigRestoreRestartRequired | Should -BeTrue
        $configPath = $fx.Config
        Save-Config | Should -BeFalse
        Get-F61Text -Path $fx.Config | Should -Match 'settings-old'
    }

    It 'sets the restart latch when the settings file cannot be put back and cannot be undone' {
        # Mutation: drop "$script:TpmConfigRestoreRestartRequired = $true" from the SETTINGS_ROLLBACK_FAILED path ->
        # the latch stays off and RestartRequired is false.
        $fx = New-F61Fixture -Name 'cfgfail'
        Install-F61Mocks -Fixture $fx
        $baseline = New-F61Baseline -Fixture $fx
        Set-F61File -Path (Join-Path $fx.Profiles 'GameA.xml') -Text (Get-F61GameXml -Name 'Game A' -Value 'a-new')
        Set-F61File -Path $fx.Config -Text '{"Marker":"settings-new"}'
        $plan = Get-TpmRestorePointChangePlan -RestorePoint $baseline -UserProfilesDir $fx.Profiles -ConfigPath $fx.Config
        Mock Restore-TpmRestorePointSettingsFile { throw 'the settings swap failed' }
        Mock Invoke-RestoreBackup { throw 'the game settings restore must not run' }

        $result = Restore-TpmRestorePointAll -RestorePoint $baseline -UserProfilesDir $fx.Profiles -Plan $plan -ConfigPath $fx.Config -RestorePointsRoot $fx.Points

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $result.ReasonCode | Should -BeExactly 'SETTINGS_ROLLBACK_FAILED'
        $result.RestartRequired | Should -BeTrue
        $script:TpmConfigRestoreRestartRequired | Should -BeTrue
        Get-F61Text -Path (Join-Path $fx.Profiles 'GameA.xml') | Should -Match 'a-new'
        Should -Invoke Invoke-RestoreBackup -Times 0 -Exactly
    }
}
