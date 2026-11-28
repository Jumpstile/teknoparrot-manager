#Requires -Module Pester

# RC9.5 lane u5: regression cases from a real tester log.
#   Part 1 (issue 511): path repair must never point a game at another game or another version, and two different games must never be
#   pointed at one game folder. Real folders under $TestDrive; an unused drive letter stands for the old drive.
#   Part 2 (issue 509): the ReShade first check counts a game that has only a ReShade.ini as protected, the same way the install step does.
# What this CANNOT prove: a run against a real moved library, or the whole ReShade setup screen end to end.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'RC95U5 bootstrap could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'rc95u5-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    function Write-Log { param([string]$msg) }

    $script:rcOld = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'P', 'O', 'N', 'M' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) }) | Select-Object -First 1
    if (-not $script:rcOld) { throw 'RC95U5 needs one unused drive letter.' }

    # One profile whose saved path is on the old drive.
    function New-RcProfile {
        param([string]$Code, [string]$OldRelative, [string]$ExeName)
        $oldPath = $script:rcOld + ':\Arcade Games\' + $OldRelative
        [System.IO.File]::WriteAllText((Join-Path $script:rcProfiles ($Code + '.xml')), ('<GameProfile><GamePath>{0}</GamePath><ExecutableName>{1}</ExecutableName></GameProfile>' -f $oldPath, $ExeName))
    }
    function New-RcFile {
        param([string]$Relative)
        $path = Join-Path $script:rcGames $Relative
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path))
        [System.IO.File]::WriteAllText($path, 'game')
        return $path
    }
    function Get-RcPlan {
        param([hashtable]$Index = @{})
        return @((Repair-GamePaths -userProfilesDir $script:rcProfiles -installFolder $script:rcGames -profileIndex $Index -DryRun:$true).Reports)
    }
    function Get-RcReport { param([object[]]$Reports, [string]$Code) return @($Reports | Where-Object { [string]$_.Code -ieq $Code })[0] }
    $script:rcDbz = 'Dragon Ball Zenkai Battle Royale (3.26.01)(2017-12-25)[Namco System 357][TP]'
    $script:rcT6 = 'Tekken 6 (2007)[Namco System 357][TP]'
    $script:rcEboot = '\dev_hdd0\game\SCEEXE000\USRDIR\EBOOT.BIN'
    $script:rcEbootIndex = @{ 'eboot.bin' = @('dbzenkai', 'Tekken6') }
    $script:rcSfvExe = '\game\WindowsNoEditor\StreetFighterV\Binaries\Win64\StreetFighterV.exe'
}

Describe 'Path repair never applies the wrong game or version (real log, issue 511)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:rcRoot = Join-Path $TestDrive ('rc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:rcProfiles = Join-Path $script:rcRoot 'UserProfiles'
        $script:rcGames = Join-Path $script:rcRoot 'Games'
        [void][System.IO.Directory]::CreateDirectory($script:rcProfiles)
        [void][System.IO.Directory]::CreateDirectory($script:rcGames)
    }

    It 'case 1: Dragon Ball Zenkai is not pointed at Tekken 6 just because both use EBOOT.BIN' {
        New-RcProfile -Code 'dbzenkai' -OldRelative ($script:rcDbz + $script:rcEboot) -ExeName 'EBOOT.BIN'
        [void](New-RcFile ($script:rcT6 + $script:rcEboot))
        $before = [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'dbzenkai.xml'))

        $reports = @(Get-RcPlan -Index $script:rcEbootIndex)
        $reports[0].Status | Should -BeExactly 'not-found'
        $reports[0].NewPath | Should -BeNullOrEmpty
        $reports[0].Reason | Should -Match 'not on this drive'
        [void](Repair-GamePaths -userProfilesDir $script:rcProfiles -installFolder $script:rcGames -profileIndex $script:rcEbootIndex -DryRun:$false)
        [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'dbzenkai.xml')) | Should -BeExactly $before
    }

    It 'case 2: Street Fighter V Type Arcade 3.53 is not pointed at the 4.12 folder' {
        $saved = $script:rcOld + ':\Games\Street Fighter V Type Arcade (3.53)(2019)[Taito Type X4][TP]' + $script:rcSfvExe
        [System.IO.File]::WriteAllText((Join-Path $script:rcProfiles 'StreetFighterVTypeArcade353.xml'), ('<GameProfile><GamePath>{0}</GamePath><ExecutableName>StreetFighterV.exe</ExecutableName></GameProfile>' -f $saved))
        [void](New-RcFile ('Street Fighter V Type Arcade (4.12)(2023-04-14)(JPN)[Taito Type X4][TP]' + $script:rcSfvExe))
        $before = [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'StreetFighterVTypeArcade353.xml'))
        $index = @{ 'streetfighterv.exe' = @('StreetFighterVTypeArcade353', 'StreetFighterVTypeArcade412') }

        $reports = @(Get-RcPlan -Index $index)
        $reports[0].Status | Should -BeExactly 'not-found'
        $reports[0].NewPath | Should -BeNullOrEmpty
        [void](Repair-GamePaths -userProfilesDir $script:rcProfiles -installFolder $script:rcGames -profileIndex $index -DryRun:$false)
        [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'StreetFighterVTypeArcade353.xml')) | Should -BeExactly $before
    }

    It 'case 3: Tekken 6 and Dragon Ball Zenkai in one run - only Tekken 6 is applied, and no folder is claimed twice' {
        New-RcProfile -Code 'Tekken6' -OldRelative ($script:rcT6 + $script:rcEboot) -ExeName 'EBOOT.BIN'
        New-RcProfile -Code 'dbzenkai' -OldRelative ($script:rcDbz + $script:rcEboot) -ExeName 'EBOOT.BIN'
        $t6File = New-RcFile ($script:rcT6 + $script:rcEboot)
        $dbzBefore = [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'dbzenkai.xml'))

        $tx = Repair-GamePaths -userProfilesDir $script:rcProfiles -installFolder $script:rcGames -profileIndex $script:rcEbootIndex -DryRun:$false
        (Get-RcReport $tx.Reports 'Tekken6').Status | Should -BeExactly 'fixed'
        (Get-RcReport $tx.Reports 'dbzenkai').Status | Should -BeExactly 'not-found'
        [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'dbzenkai.xml')) | Should -BeExactly $dbzBefore
        [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'Tekken6.xml')) | Should -Match ([regex]::Escape($t6File))
    }

    It 'case 3: two different games that would share one game folder are both left unchanged, with a plain reason' {
        # Both saved paths name the same [TP] folder, so both would be pointed at the one folder on the new drive.
        New-RcProfile -Code 'GameOne' -OldRelative ($script:rcT6 + '\game.bin') -ExeName 'game.bin'
        New-RcProfile -Code 'GameTwo' -OldRelative ($script:rcT6 + '\game.bin') -ExeName 'game.bin'
        [void](New-RcFile ($script:rcT6 + '\game.bin'))
        $oneBefore = [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'GameOne.xml'))
        $twoBefore = [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'GameTwo.xml'))
        $index = @{ 'game.bin' = @('GameOne', 'GameTwo') }

        $plan = @(Get-RcPlan -Index $index)
        foreach ($report in $plan) {
            $report.Status | Should -Not -BeExactly 'candidate'
            $report.Reason | Should -Match 'same game folder'
            $report.Reason | Should -Match 'not a known twin'
        }
        $tx = Repair-GamePaths -userProfilesDir $script:rcProfiles -installFolder $script:rcGames -profileIndex $index -DryRun:$false
        @($tx.Reports | Where-Object Status -eq 'fixed').Count | Should -Be 0
        [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'GameOne.xml')) | Should -BeExactly $oneBefore
        [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'GameTwo.xml')) | Should -BeExactly $twoBefore
    }

    It 'case 3: a known twin pair (TeknoChi and its older profile) may share one game folder' {
        $name = 'OutRun 2 (2006)[Sega Chihiro][TP]'
        New-RcProfile -Code 'or2' -OldRelative ($name + '\outrun2.bin') -ExeName 'outrun2.bin'
        New-RcProfile -Code 'TeknoChiOutRun2' -OldRelative ($name + '\outrun2.bin') -ExeName 'outrun2.bin'
        $new = New-RcFile ($name + '\outrun2.bin')
        $index = @{ 'outrun2.bin' = @('or2', 'TeknoChiOutRun2') }

        $plan = @(Get-RcPlan -Index $index)
        $plan.Count | Should -Be 2
        foreach ($report in $plan) { $report.Status | Should -BeExactly 'candidate'; $report.NewPath | Should -BeExactly $new }
    }

    It 'case 4: the same game and version on a moved drive is still repaired' {
        New-RcProfile -Code 'dbzenkai' -OldRelative ($script:rcDbz + $script:rcEboot) -ExeName 'EBOOT.BIN'
        $new = New-RcFile ($script:rcDbz + $script:rcEboot)
        [void](New-RcFile ($script:rcT6 + $script:rcEboot))

        $reports = @(Get-RcPlan -Index $script:rcEbootIndex)
        $reports[0].Status | Should -BeExactly 'candidate'
        $reports[0].NewPath | Should -BeExactly $new
        $tx = Repair-GamePaths -userProfilesDir $script:rcProfiles -installFolder $script:rcGames -profileIndex $script:rcEbootIndex -DryRun:$false
        (Get-RcReport $tx.Reports 'dbzenkai').Status | Should -BeExactly 'fixed'
    }

    It 'case 4: Street Fighter V Type Arcade 3.53 with a [TP] folder of the same name is still repaired' {
        $name = 'Street Fighter V Type Arcade (3.53)(2019)[Taito Type X4][TP]'
        $saved = $script:rcOld + ':\Games\' + $name + $script:rcSfvExe
        [System.IO.File]::WriteAllText((Join-Path $script:rcProfiles 'StreetFighterVTypeArcade353.xml'), ('<GameProfile><GamePath>{0}</GamePath><ExecutableName>StreetFighterV.exe</ExecutableName></GameProfile>' -f $saved))
        $new = New-RcFile ($name + $script:rcSfvExe)
        [void](New-RcFile ('Street Fighter V Type Arcade (4.12)(2023-04-14)(JPN)[Taito Type X4][TP]' + $script:rcSfvExe))
        $index = @{ 'streetfighterv.exe' = @('StreetFighterVTypeArcade353', 'StreetFighterVTypeArcade412') }

        $reports = @(Get-RcPlan -Index $index)
        $reports[0].Status | Should -BeExactly 'candidate'
        $reports[0].NewPath | Should -BeExactly $new
    }
}

Describe 'ReShade first check agrees with the install step (real log, issue 509)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmReShadeGameLabel { [string]$Fallback }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-ReShadeTargetInfo { [pscustomobject]@{ TargetDir = [string]$ExeDir; DllName = 'dxgi.dll' } }
        $root = Join-Path $TestDrive ('rs-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $profiles = Join-Path $root 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($profiles)
        $script:rsFiles = @()
        foreach ($code in @('Clean', 'IniOnly', 'HookOnly')) {
            $dir = Join-Path $root $code
            [void][System.IO.Directory]::CreateDirectory($dir)
            $exe = Join-Path $dir 'game.exe'
            [System.IO.File]::WriteAllText($exe, 'MZ-test-game')
            if ($code -eq 'IniOnly') { [System.IO.File]::WriteAllText((Join-Path $dir 'ReShade.ini'), '[GENERAL]') }
            if ($code -eq 'HookOnly') { [System.IO.File]::WriteAllText((Join-Path $dir 'dxgi.dll'), 'hook') }
            $profile = Join-Path $profiles ($code + '.xml')
            [System.IO.File]::WriteAllText($profile, ('<GameProfile><GamePath>{0}</GamePath></GameProfile>' -f [System.Security.SecurityElement]::Escape($exe)), (New-Object System.Text.UTF8Encoding $false))
            $script:rsFiles += Get-Item -LiteralPath $profile
        }
        $script:rsDefinition = [pscustomobject]@{ ProfileId = 'Levels'; Effects = @() }
    }

    It 'counts a game that has only ReShade.ini as protected at the first check, not ready' {
        $summary = Get-TpmReShadeApplyPreflight -SelectedGames $script:rsFiles -ProfileDefinition $script:rsDefinition -SourceDll ''
        @($summary.Records | Where-Object Game -eq 'IniOnly')[0].Status | Should -BeExactly 'Protected'
        @($summary.Records | Where-Object Game -eq 'Clean')[0].Status | Should -BeExactly 'Ready'
        $summary.Ready | Should -Be 1
        $summary.Protected | Should -Be 2
    }

    It 'the install step puts every game in the same group the first check did, so the totals do not change' {
        $summary = Get-TpmReShadeApplyPreflight -SelectedGames $script:rsFiles -ProfileDefinition $script:rsDefinition -SourceDll ''
        $atInstall = @{ Ready = 0; Protected = 0 }
        foreach ($file in $script:rsFiles) {
            $dir = Split-Path -Parent ([string](([xml](Get-Content -LiteralPath $file.FullName -Raw)).GameProfile.GamePath))
            # The same call the install loop makes: same hook path, same target folder, no ownership record.
            $classification = Get-TpmReShadeOwnershipClassification -HookPath (Join-Path $dir 'dxgi.dll') -TargetRoot $dir -ProfileDefinition $script:rsDefinition -Manifest $null
            $bucket = if ($classification.Status -in @('UnknownUserOwnedConflict', 'BundledPreinstalledProtected')) { 'Protected' } else { 'Ready' }
            $atInstall[$bucket]++
            @($summary.Records | Where-Object Game -eq $file.BaseName)[0].Status | Should -BeExactly $bucket
        }
        $atInstall.Ready | Should -Be $summary.Ready
        $atInstall.Protected | Should -Be $summary.Protected
    }
}
