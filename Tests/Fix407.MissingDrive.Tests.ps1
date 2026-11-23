#Requires -Module Pester

# GitHub issue 401: some saved TeknoParrot profiles point at a drive that is not connected (for example drive L:). While scanning and
# registering games, the run printed "Join-Path : Cannot find drive. A drive with the name 'L' does not exist." again and again.
# Cause: Set-SecondaryExecutablePath built the second game file with Join-Path, which prints that error for every game on the missing
# drive. Now the path is built without Join-Path, each such game is counted once, and ONE plain summary is shown after the scan.
# Real folders under $TestDrive; a drive letter that does not exist on this PC stands for the missing drive.
# What this CANNOT prove: a real run of the full registration scan with a real unplugged drive.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX407 bootstrap could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'fix407-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    function Write-Log { param([string]$msg) }

    # A drive letter that does not exist on this PC.
    $script:f407Missing = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'P', 'O', 'N', 'M' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) }) | Select-Object -First 1
    if (-not $script:f407Missing) { throw 'FIX407 needs one unused drive letter.' }
    $script:f407Log = New-Object System.Collections.Generic.List[string]
    $script:f407Screen = New-Object System.Collections.Generic.List[string]

    function New-F407Doc {
        param([string]$GamePath)
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml(('<GameProfile><GamePath>{0}</GamePath><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>b.exe</ExecutableName2></GameProfile>' -f $GamePath))
        return $doc
    }
}

Describe 'A game saved on a drive that is not connected (issue 401)' {
    BeforeEach {
        $script:f407Log.Clear()
        $script:f407Screen.Clear()
        if (Get-Variable -Name TpmUnavailableDriveGames -Scope Script -ErrorAction SilentlyContinue) { $script:TpmUnavailableDriveGames.Clear() }
        Mock Write-Log { [void]$script:f407Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:f407Screen.Add([string]$Object) }
    }

    It 'building the second game file prints no PowerShell error and changes nothing' {
        $doc = New-F407Doc -GamePath ($script:f407Missing + ':\Games\One\a.exe')
        $out = & { Set-SecondaryExecutablePath $doc ($script:f407Missing + ':\Games\One\a.exe') } 2>&1
        @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        $out | Should -Not -Contain $true
        $doc.GameProfile.SelectSingleNode('GamePath2') | Should -BeNullOrEmpty
    }

    It 'a game on a drive that is available is still processed' {
        $folder = Join-Path $TestDrive 'good-game'
        [void][System.IO.Directory]::CreateDirectory($folder)
        [System.IO.File]::WriteAllText((Join-Path $folder 'a.exe'), 'one')
        [System.IO.File]::WriteAllText((Join-Path $folder 'b.exe'), 'two')
        $doc = New-F407Doc -GamePath (Join-Path $folder 'a.exe')

        (Set-SecondaryExecutablePath $doc (Join-Path $folder 'a.exe')) | Should -BeTrue
        $doc.GameProfile.GamePath2 | Should -BeExactly (Join-Path $folder 'b.exe')
    }

    It 'the registration scan step counts the game once, logs it, and prints no error' {
        $profiles = Join-Path $TestDrive 'profiles'
        [void][System.IO.Directory]::CreateDirectory($profiles)
        $profilePath = Join-Path $profiles 'LostGame.xml'
        [System.IO.File]::WriteAllText($profilePath, ('<GameProfile><GamePath>{0}:\Games\Lost\a.exe</GamePath><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>b.exe</ExecutableName2></GameProfile>' -f $script:f407Missing))
        $before = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash

        # The same game is met again (the scan reaches it from several branches): still one entry, one log line.
        $out = & {
            Backfill-SecondaryExecutablePath -UserProfilePath $profilePath -DryRun $false
            Backfill-SecondaryExecutablePath -UserProfilePath $profilePath -DryRun $false
        } 2>&1

        @($out | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
        $script:TpmUnavailableDriveGames.Count | Should -Be 1
        @($script:f407Log | Where-Object { $_ -like '*LostGame*' -and $_ -like ('*' + $script:f407Missing + ':*') }).Count | Should -Be 1
        (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash | Should -BeExactly $before
    }

    It 'shows ONE plain summary for the drive, names the games under Details, and starts the next scan empty' {
        foreach ($code in @('GameC', 'GameA', 'GameB')) { Add-TpmUnavailableDriveGame -Code $code -Path ($script:f407Missing + ':\Games\' + $code + '\x.exe') }
        Add-TpmUnavailableDriveGame -Code 'GameA' -Path ($script:f407Missing + ':\Games\GameA\x.exe')

        Write-TpmUnavailableDriveSummary

        $screen = $script:f407Screen -join "`n"
        $screen | Should -Match ('3 games point to drive {0}:, which is not connected, so they were skipped\.' -f $script:f407Missing)
        $screen | Should -Match 'Connect the drive, or run 13\) Library health check and choose R or S to point the games at the new folder\.'
        $screen | Should -Match 'Details: GameA, GameB, GameC'
        # One log line per game, not four.
        @($script:f407Log | Where-Object { $_ -like 'Drive not connected*' }).Count | Should -Be 3
        # Nothing technical on the main lines.
        ($script:f407Screen | Where-Object { $_ -notlike '*Details:*' }) -join "`n" | Should -Not -Match 'GameA|Join-Path|DEVICE_UNAVAILABLE'

        $script:f407Screen.Clear()
        Write-TpmUnavailableDriveSummary
        $script:f407Screen.Count | Should -Be 0
    }
}

# ---- Round 2: a game on a missing drive can be pointed at a new folder, and is never told "extract this game first" ----

Describe 'Library health check offers repair for games on a drive that is not connected (issue 401, round 2)' {
    BeforeAll {
        function New-F407HealthResult {
            param([hashtable]$Override = @{})
            $base = [ordered]@{
                Outcome = 'SUCCEEDED'; DiscoveryComplete = $true; OptionalCoverageComplete = $true; OptionalCheckFailed = 0
                PostgresInventoryStatus = 'Complete'; PostgresInventoryErrors = @(); ReadOnly = $true; Registered = 4
                Valid = @('A', 'B', 'C'); Broken = @(); Empty = @(); DriveUnavailable = @()
                GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @()
                PostgresNeeded = @(); PostgresConfigured = 0; PostgresAutoCreateProfiles = @()
                ReShadeCount = 0; BepInExCount = 0; PostgresNeededLabels = @(); PostgresConfiguredLabels = @()
                OptionalCoverageUnavailable = $false
            }
            foreach ($key in $Override.Keys) { $base[$key] = $Override[$key] }
            return [pscustomobject]$base
        }
    }
    BeforeEach {
        $script:f407Screen.Clear()
        $script:f407Choices = $null
        Mock Write-Log {}
        Mock Write-Host { [void]$script:f407Screen.Add([string]($Object -join ' ')) }
        Mock Get-ConsoleContentWidth { return 100 }
        Mock Get-TpmLibraryHealthDetailBlocks { return @() }
        Mock Read-TpmChoice { $script:f407Choices = @($Choices); return 'B' }
    }

    It 'offers R and S for games on a missing drive, and says what happens before anything changes' {
        $result = New-F407HealthResult @{ DriveUnavailable = @('LostGame') }

        (Show-LibraryHealthNextActions -Result $result) | Should -BeExactly 'B'

        $script:f407Choices | Should -Contain 'R'
        $script:f407Choices | Should -Contain 'S'
        $text = ($script:f407Screen -join ' ') -replace '\s+', ' '
        $text | Should -Match '1 game is on a drive that is not connected: LostGame\.'
        $text | Should -Match 'only if its game file is found there'
        $text | Should -Match 'preview, answer Y, and a safety backup is made before anything is saved'
        $text | Should -Match 'If the drive is only unplugged, connect it and choose B\. Nothing is changed\.'
        $text | Should -Match '\[R\] Search the game folder for these games'
    }

    It 'does not offer R or S when no game is on a missing drive and none is broken' {
        (Show-LibraryHealthNextActions -Result (New-F407HealthResult)) | Should -BeExactly 'B'
        $script:f407Choices | Should -Not -Contain 'R'
        $script:f407Choices | Should -Not -Contain 'S'
    }

    It 'with broken games too, the same R and S choices say the missing-drive games are included' {
        $result = New-F407HealthResult @{ Broken = @('BrokenGame'); DriveUnavailable = @('LostGame') }

        (Show-LibraryHealthNextActions -Result $result) | Should -BeExactly 'B'

        $script:f407Choices | Should -Contain 'R'
        $script:f407Choices | Should -Contain 'M'
        $text = ($script:f407Screen -join ' ') -replace '\s+', ' '
        $text | Should -Match 'BrokenGame'
        $text | Should -Match 'LostGame'
        $text | Should -Match 'only if its game file is found there'
    }

    It 'the report row and the details line no longer say only "reconnect"; they name the repair choice' {
        $result = New-F407HealthResult @{ DriveUnavailable = @('LostGame') }
        $row = @(Get-TpmLibraryHealthRows -Result $result | Where-Object { $_.Area -eq 'Game drive' })
        $row.Count | Should -Be 1
        $row[0].Text | Should -BeExactly 'Needs attention - 1 game is on a drive that is not connected. Reconnect the drive. Or choose a new folder for it with R or S'
        $source = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $source | Should -Match ', or choose R or S to point these games at a new folder'
        $source | Should -Match 'the saved paths were not judged\.'
        $source | Should -Not -Match 'Reconnect it and run (this|the) check again'
    }
}

Describe 'Repairing games that were on a missing drive (issue 401, round 2)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:f407Root = Join-Path $TestDrive ('rep-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:f407Profiles = Join-Path $script:f407Root 'UserProfiles'
        $script:f407Games = Join-Path $script:f407Root 'Games'
        [void][System.IO.Directory]::CreateDirectory($script:f407Profiles)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:f407Games 'Lost'))
        $script:f407Exe = Join-Path $script:f407Games 'Lost\lostgame.exe'
        [System.IO.File]::WriteAllText($script:f407Exe, 'game')
        $script:f407ProfilePath = Join-Path $script:f407Profiles 'LOSTGAME.xml'
        $script:f407Original = ('<GameProfile><GamePath>{0}:\Old\Lost\lostgame.exe</GamePath><ExecutableName>lostgame.exe</ExecutableName></GameProfile>' -f $script:f407Missing)
        [System.IO.File]::WriteAllText($script:f407ProfilePath, $script:f407Original)
        $script:f407Index = @{ 'lostgame.exe' = @('LOSTGAME') }
    }

    It 'a game whose file is found in the new folder is offered as a candidate; saying N changes nothing' {
        $plan = Repair-GamePaths -userProfilesDir $script:f407Profiles -installFolder $script:f407Games -profileIndex $script:f407Index -DryRun:$true -OnlyGames @('LOSTGAME')

        $report = @($plan.Reports)[0]
        $report.Status | Should -BeExactly 'candidate'
        $report.PreviousPath | Should -BeLike ($script:f407Missing + ':\Old\*')
        $report.NewPath | Should -BeExactly ([System.IO.Path]::GetFullPath($script:f407Exe))
        # The preview is all the user has seen; nothing was written, not even a backup folder.
        [System.IO.File]::ReadAllText($script:f407ProfilePath) | Should -BeExactly $script:f407Original
        @(Get-ChildItem -LiteralPath $script:f407Profiles -Directory -Force).Count | Should -Be 0
    }

    It 'after Y the profile is pointed at the new folder with a verified backup of the old profile' {
        $plan = Repair-GamePaths -userProfilesDir $script:f407Profiles -installFolder $script:f407Games -profileIndex $script:f407Index -DryRun:$true -OnlyGames @('LOSTGAME')
        $candidates = @($plan.Reports | Where-Object { $_.Status -eq 'candidate' })

        $applied = Repair-GamePaths -userProfilesDir $script:f407Profiles -installFolder $script:f407Games -profileIndex $script:f407Index -DryRun:$false -ReviewedCandidates $candidates -OnlyGames @('LOSTGAME')

        $report = @($applied.Reports)[0]
        $report.Status | Should -BeExactly 'fixed'
        $report.Verified | Should -BeTrue
        (Read-Xml -Path $script:f407ProfilePath).GameProfile.GamePath | Should -BeExactly ([System.IO.Path]::GetFullPath($script:f407Exe))
        $backup = [string]$applied.Backup.RootPath
        $backup | Should -Not -BeNullOrEmpty
        $savedCopy = @(Get-ChildItem -LiteralPath $backup -Recurse -File -Filter 'LOSTGAME.xml')
        $savedCopy.Count | Should -BeGreaterOrEqual 1
        [System.IO.File]::ReadAllText($savedCopy[0].FullName) | Should -BeExactly $script:f407Original
    }

    It 'a game that is NOT found stays untouched and is reported as "drive not connected", not "extract this game first"' {
        [System.IO.File]::Delete($script:f407Exe)
        $plainProfile = Join-Path $script:f407Profiles 'PLAINGAME.xml'
        [System.IO.File]::WriteAllText($plainProfile, ('<GameProfile><GamePath>{0}</GamePath><ExecutableName>plaingame.exe</ExecutableName></GameProfile>' -f (Join-Path $script:f407Root 'Gone\plaingame.exe')))
        $index = @{ 'lostgame.exe' = @('LOSTGAME'); 'plaingame.exe' = @('PLAINGAME') }

        $reports = @((Repair-GamePaths -userProfilesDir $script:f407Profiles -installFolder $script:f407Games -profileIndex $index -DryRun:$true).Reports)

        ($reports | Where-Object { $_.Code -eq 'LOSTGAME' }).Status | Should -BeExactly 'drive-unavailable'
        ($reports | Where-Object { $_.Code -eq 'LOSTGAME' }).Reason | Should -Match 'drive is not connected'
        # The "extract these games first" list is built from the not-found status only: the missing-drive game is not in it.
        @($reports | Where-Object { $_.Status -eq 'not-found' } | ForEach-Object { $_.Code }) | Should -Be @('PLAINGAME')
        [System.IO.File]::ReadAllText($script:f407ProfilePath) | Should -BeExactly $script:f407Original
        $source = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'))
        $source | Should -Match '\$nf\s+=\s+@\(\$repair \| Where-Object \{ \$_\.Status -eq "not-found" \}\)'
    }
}
