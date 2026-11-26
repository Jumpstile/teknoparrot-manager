#Requires -Module Pester

# GitHub issue 463: after a library moved to a new drive and folder, Game Path Repair left most games unresolved and ended as FAILED.
# The old saved path (its folder names and file name) now helps find ONE clear file in the new library. A tie is never guessed.
# Real folders under $TestDrive; a drive letter that does not exist on this PC stands for the old drive.
# What this CANNOT prove: a run against a real moved library.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX463 bootstrap could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'fix463-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    function Write-Log { param([string]$msg) }

    $script:f463Old = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'P', 'O', 'N', 'M' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) }) | Select-Object -First 1
    if (-not $script:f463Old) { throw 'FIX463 needs one unused drive letter.' }

    function New-F463Game {
        param([string]$Code, [string]$OldRelative, [string]$NewRelative, [string]$ExeName = '', [switch]$NoFile)
        $oldPath = $script:f463Old + ':\Arcade Games\' + $OldRelative
        $exeNode = if ($ExeName) { '<ExecutableName>' + $ExeName + '</ExecutableName>' } else { '' }
        [System.IO.File]::WriteAllText((Join-Path $script:f463Profiles ($Code + '.xml')), ('<GameProfile><GamePath>{0}</GamePath>{1}</GameProfile>' -f $oldPath, $exeNode))
        if ($NewRelative -and -not $NoFile) {
            $newPath = Join-Path $script:f463Games $NewRelative
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($newPath))
            [System.IO.File]::WriteAllText($newPath, 'game')
        }
    }
    function Get-F463Plan {
        param([hashtable]$Index = @{})
        return @((Repair-GamePaths -userProfilesDir $script:f463Profiles -installFolder $script:f463Games -profileIndex $Index -DryRun:$true).Reports)
    }
}

Describe 'Moved library: the old saved path helps find the game (issue 463)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:f463Root = Join-Path $TestDrive ('mv-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:f463Profiles = Join-Path $script:f463Root 'UserProfiles'
        $script:f463Games = Join-Path $script:f463Root 'TP Games Arcade'
        [void][System.IO.Directory]::CreateDirectory($script:f463Profiles)
        [void][System.IO.Directory]::CreateDirectory($script:f463Games)
    }

    It 'a profile with no executable name is repaired from the file and folder names of its old path' {
        New-F463Game -Code 'ArcadeLove' -OldRelative 'Arcade Love\ArcadeLove.exe' -NewRelative 'Arcade Love\ArcadeLove.exe'

        $reports = @(Get-F463Plan)
        $reports.Count | Should -Be 1
        $reports[0].Status | Should -BeExactly 'candidate'
        $reports[0].NewPath | Should -BeExactly (Join-Path $script:f463Games 'Arcade Love\ArcadeLove.exe')
    }

    It 'a profile with no executable name is not guessed when only a generic folder name matches' {
        New-F463Game -Code 'NoName' -OldRelative 'Some Game\bin\run.exe' -NewRelative 'Other Game\bin\run.exe'

        $reports = @(Get-F463Plan)
        $reports[0].Status | Should -BeExactly 'ambiguous'
    }

    It 'two games that share an exe name are told apart by the folder names of their old paths' {
        New-F463Game -Code 'AquaA' -OldRelative 'Aqua A\game.exe' -NewRelative 'Aqua A\game.exe' -ExeName 'game.exe'
        New-F463Game -Code 'AquaB' -OldRelative 'Aqua B\game.exe' -NewRelative 'Aqua B\game.exe' -ExeName 'game.exe'
        $index = @{ 'game.exe' = @('AquaA', 'AquaB') }

        $reports = @(Get-F463Plan -Index $index)
        ($reports | Where-Object Code -eq 'AquaA').NewPath | Should -BeExactly (Join-Path $script:f463Games 'Aqua A\game.exe')
        ($reports | Where-Object Code -eq 'AquaB').NewPath | Should -BeExactly (Join-Path $script:f463Games 'Aqua B\game.exe')
    }

    It 'a game folder that exists twice with the same name is NOT guessed' {
        New-F463Game -Code 'Twin' -OldRelative 'Twin\game.exe' -NewRelative 'Disc 1\Twin\game.exe' -ExeName 'game.exe'
        $second = Join-Path $script:f463Games 'Disc 2\Twin\game.exe'
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($second))
        [System.IO.File]::WriteAllText($second, 'game')
        $index = @{ 'game.exe' = @('Twin', 'Other') }

        $reports = @(Get-F463Plan -Index $index)
        $reports[0].Status | Should -BeExactly 'ambiguous'
        @($reports[0].CandidatePaths).Count | Should -Be 2
        $reports[0].PreviousPath | Should -BeLike ($script:f463Old + ':\*')
    }

    It 'a candidate is applied only after Y, saved with a backup, and the old path is kept in the backup' {
        New-F463Game -Code 'ArcadeLove' -OldRelative 'Arcade Love\ArcadeLove.exe' -NewRelative 'Arcade Love\ArcadeLove.exe'
        $candidates = @(Get-F463Plan | Where-Object Status -eq 'candidate')

        $applied = Repair-GamePaths -userProfilesDir $script:f463Profiles -installFolder $script:f463Games -profileIndex @{} -DryRun:$false -ReviewedCandidates $candidates
        @($applied.Reports)[0].Status | Should -BeExactly 'fixed'
        (Read-Xml -Path (Join-Path $script:f463Profiles 'ArcadeLove.xml')).GameProfile.GamePath | Should -BeExactly (Join-Path $script:f463Games 'Arcade Love\ArcadeLove.exe')
        [string]$applied.Backup.RootPath | Should -Not -BeNullOrEmpty
    }

    It 'with the old drive gone and nothing found, every game is reported as drive not connected, never as a code-name guess' {
        New-F463Game -Code 'VT4' -OldRelative 'Virtua Tennis 4 (2011)[Sega RingEdge][TP]\VT4_RING_r.exe' -NewRelative ''
        New-F463Game -Code 'CoH' -OldRelative 'Cars Of Honor\game.exe' -NewRelative '' -ExeName 'game.exe'

        $reports = @(Get-F463Plan -Index @{ 'game.exe' = @('CoH', 'Other') })
        $reports.Count | Should -Be 2
        @($reports | Where-Object Status -ne 'drive-unavailable').Count | Should -Be 0
    }

    It 'a shared file name is only accepted when exactly one new folder carries the old game folder name' {
        New-F463Game -Code 'ShareA' -OldRelative 'Share A (2011)\game.exe' -NewRelative 'Moved\Share A (2011)\game.exe' -ExeName 'game.exe'
        New-F463Game -Code 'ShareB' -OldRelative 'Share B (2012)\game.exe' -NewRelative 'Moved\Share B (2012)\game.exe' -ExeName 'game.exe'
        $index = @{ 'game.exe' = @('ShareA', 'ShareB', 'ShareC') }

        $reports = @(Get-F463Plan -Index $index)
        ($reports | Where-Object Code -eq 'ShareA').NewPath | Should -BeExactly (Join-Path $script:f463Games 'Moved\Share A (2011)\game.exe')
        ($reports | Where-Object Code -eq 'ShareB').NewPath | Should -BeExactly (Join-Path $script:f463Games 'Moved\Share B (2012)\game.exe')
    }
}

Describe 'Repair result wording (issue 463)' {
    BeforeEach {
        $script:f463Screen = New-Object System.Collections.Generic.List[string]
        Mock Write-Log {}
        Mock Write-TpmText { [void]$script:f463Screen.Add([string]$Text) }
    }

    It 'some repaired and some left for the user reads as "Partly done", not FAILED' {
        $reports = @(
            [pscustomobject]@{ Code = 'nbaatw'; Status = 'fixed'; PreviousPath = 'Q:\a'; NewPath = 'G:\a' },
            [pscustomobject]@{ Code = 'A1'; Status = 'ambiguous'; PreviousPath = 'Q:\b'; Reason = 'several game files fit' },
            [pscustomobject]@{ Code = 'A2'; Status = 'no-exe-name'; PreviousPath = 'Q:\c'; Reason = 'profile has no executable name' }
        )
        $counts = Write-TpmRepairOutcomeSummary -Reports $reports

        $counts.Fixed | Should -Be 1
        $counts.NeedHelp | Should -Be 2
        ($script:f463Screen -join "`n") | Should -Match 'Partly done: 1 repaired, 2 still need your help\.'
        ($script:f463Screen -join "`n") | Should -Not -Match 'FAILED'
        (Get-TpmProgressCloseState -Result ([pscustomobject]@{ Outcome = 'ACTION_REQUIRED'; ReasonCode = 'REPAIR_NEEDS_YOUR_HELP' })) | Should -BeExactly 'Incomplete'
    }

    It 'a game that could not be saved is still counted as a problem, not as needing help' {
        $reports = @([pscustomobject]@{ Code = 'S1'; Status = 'save-failed'; PreviousPath = 'Q:\a'; Reason = 'profile save or verification failed' })
        $counts = Write-TpmRepairOutcomeSummary -Reports $reports

        $counts.Problems | Should -Be 1
        ($script:f463Screen -join "`n") | Should -Match 'Nothing was repaired: 1 could not be saved or checked\.'
    }

    It 'many games on a drive that is not connected are grouped into a few lines, not one line each' {
        $reports = @(1..142 | ForEach-Object { [pscustomobject]@{ Code = ('G' + $_); Status = 'drive-unavailable'; PreviousPath = 'L:\Arcade Games\G\a.exe'; Reason = 'the saved drive is not connected and the game was not found in the folder searched' } })
        $counts = Write-TpmRepairOutcomeSummary -Reports $reports

        $counts.NeedHelp | Should -Be 142
        $script:f463Screen.Count | Should -BeLessThan 5
    }
}
