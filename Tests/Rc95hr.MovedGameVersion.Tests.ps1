#Requires -Module Pester

# RC9.5: Library Health repair must point a profile only at the SAME game and version, never at another version that happens
# to hold a file with the same relative path. Real folders under $TestDrive; an unused drive letter stands for the old drive.
# What this CANNOT prove: a run against a real moved library.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'RC95HR bootstrap could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'rc95hr-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    function Write-Log { param([string]$msg) }

    $script:rcOld = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'P', 'O', 'N', 'M' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) }) | Select-Object -First 1
    if (-not $script:rcOld) { throw 'RC95HR needs one unused drive letter.' }

    # One profile whose saved path is on the old drive.
    function New-RcProfile {
        param([string]$Code, [string]$OldRelative, [string]$ExeName)
        $oldPath = $script:rcOld + ':\Arcade Games\' + $OldRelative
        [System.IO.File]::WriteAllText((Join-Path $script:rcProfiles ($Code + '.xml')), ('<GameProfile><GamePath>{0}</GamePath><ExecutableName>{1}</ExecutableName></GameProfile>' -f $oldPath, $ExeName))
    }
    # A file on the new drive (the folder is made when the file is).
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
    $script:rcTekken = 'TekkenGame\Binaries\Win64\TekkenGame-Win64-Shipping.exe'
    $script:rcTekkenIndex = @{ 'tekkengame-win64-shipping.exe' = @('Tekken7', 'Tekken7R2') }
}

Describe 'Health repair never points a game at another version (RC9.5)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        $script:rcRoot = Join-Path $TestDrive ('rc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:rcProfiles = Join-Path $script:rcRoot 'UserProfiles'
        $script:rcGames = Join-Path $script:rcRoot 'TP Games Arcade'
        [void][System.IO.Directory]::CreateDirectory($script:rcProfiles)
        [void][System.IO.Directory]::CreateDirectory($script:rcGames)
    }

    It 'the same game folder on the new drive is pointed at (Tekken 6 style)' {
        $name = 'Tekken 6 (2007)[Namco System 357][TP]'
        New-RcProfile -Code 'Tekken6' -OldRelative ($name + '\dev_hdd0\game\SCEEXE000\USRDIR\EBOOT.BIN') -ExeName 'EBOOT.BIN'
        $new = New-RcFile ($name + '\dev_hdd0\game\SCEEXE000\USRDIR\EBOOT.BIN')

        $reports = @(Get-RcPlan)
        $reports[0].Status | Should -BeExactly 'candidate'
        $reports[0].NewPath | Should -BeExactly $new
    }

    It 'a different version with the same relative exe path is refused and the profile stays unchanged' {
        New-RcProfile -Code 'Tekken7' -OldRelative ('Tekken 7 Fated Retribution (1.06.00)(2016)[Namco ES3X][TP]\' + $script:rcTekken) -ExeName 'TekkenGame-Win64-Shipping.exe'
        [void](New-RcFile ('Tekken 7 Fated Retribution Round 2 (4.20, TR2 15.01)(2019)[Namco ES3X][TP]\' + $script:rcTekken))
        $before = [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'Tekken7.xml'))

        $reports = @(Get-RcPlan -Index $script:rcTekkenIndex)
        $reports[0].Status | Should -BeExactly 'not-found'
        $reports[0].NewPath | Should -BeNullOrEmpty
        $reports[0].Reason | Should -Match 'not on this drive'
        $applied = Repair-GamePaths -userProfilesDir $script:rcProfiles -installFolder $script:rcGames -profileIndex $script:rcTekkenIndex -DryRun:$false -ReviewedCandidates @($reports | Where-Object Status -eq 'candidate')
        [System.IO.File]::ReadAllText((Join-Path $script:rcProfiles 'Tekken7.xml')) | Should -BeExactly $before
    }

    It 'when two version folders hold the exe, the one with the matching identity wins' {
        $old = 'Tekken 7 Fated Retribution (1.06.00)(2016)[Namco ES3X][TP]'
        New-RcProfile -Code 'Tekken7' -OldRelative ($old + '\' + $script:rcTekken) -ExeName 'TekkenGame-Win64-Shipping.exe'
        [void](New-RcFile ('Tekken 7 Fated Retribution Round 2 (4.20, TR2 15.01)(2019)[Namco ES3X][TP]\' + $script:rcTekken))
        $right = New-RcFile ($old + '\' + $script:rcTekken)

        $reports = @(Get-RcPlan -Index $script:rcTekkenIndex)
        $reports[0].Status | Should -BeExactly 'candidate'
        $reports[0].NewPath | Should -BeExactly $right
    }

    It 'a version that is not on the drive at all is reported as not on this drive' {
        New-RcProfile -Code 'Tekken7R2' -OldRelative ('Tekken 7 Fated Retribution Round 2 (1.08.00)(2019)[Namco ES3A][TP]\' + $script:rcTekken) -ExeName 'TekkenGame-Win64-Shipping.exe'
        [void](New-RcFile ('Tekken 7 Fated Retribution Round 2 (4.20, TR2 15.01)(2019)[Namco ES3X][TP]\' + $script:rcTekken))

        $reports = @(Get-RcPlan -Index $script:rcTekkenIndex)
        $reports[0].Status | Should -BeExactly 'not-found'
        $reports[0].Reason | Should -Match 'not on this drive'
    }

    It 'Silver Strike style: game.bin inside the same-named folder is found' {
        $name = 'Silver Strike Bowling Live (3.02.07)(2017-05-10)(USA)[IT Nighthawk][TP]'
        New-RcProfile -Code 'SilverStrikeBowlingLive' -OldRelative ($name + '\game.bin') -ExeName 'game.bin'
        $new = New-RcFile ($name + '\game.bin')
        [void](New-RcFile 'Other Game (2010)[TP]\game.bin')

        foreach ($index in @(@{}, @{ 'game.bin' = @('SilverStrikeBowlingLive', 'OtherGame') })) {
            $reports = @(Get-RcPlan -Index $index)
            $reports[0].Status | Should -BeExactly 'candidate'
            $reports[0].NewPath | Should -BeExactly $new
        }
    }

    It 'Silver Strike style: the folder exists but game.bin is not inside it, and the screen says so' {
        $name = 'Silver Strike Bowling Live (3.02.07)(2017-05-10)(USA)[IT Nighthawk][TP]'
        New-RcProfile -Code 'SilverStrikeBowlingLive' -OldRelative ($name + '\game.bin') -ExeName 'game.bin'
        [void](New-RcFile ($name + '\readme.txt'))
        [void](New-RcFile 'Other Game (2010)[TP]\game.bin')

        $reports = @(Get-RcPlan -Index @{ 'game.bin' = @('SilverStrikeBowlingLive', 'OtherGame') })
        $reports[0].Status | Should -BeExactly 'not-found'
        $reports[0].Reason | Should -Match 'Found the folder, but game\.bin is not inside it'
    }

    It 'Silver Strike style: game.bin one folder deeper in the same-named folder is still found' {
        $name = 'Silver Strike Bowling Live (3.02.07)(2017-05-10)(USA)[IT Nighthawk][TP]'
        New-RcProfile -Code 'SilverStrikeBowlingLive' -OldRelative ($name + '\game.bin') -ExeName 'game.bin'
        $new = New-RcFile ($name + '\data\game.bin')
        [void](New-RcFile 'Other Game (2010)[TP]\game.bin')

        $reports = @(Get-RcPlan -Index @{ 'game.bin' = @('SilverStrikeBowlingLive', 'OtherGame') })
        $reports[0].Status | Should -BeExactly 'candidate'
        $reports[0].NewPath | Should -BeExactly $new
    }

    It 'two exe files inside the same game folder are reported as ambiguous, not guessed' {
        $name = 'Some Game (2012)[TP]'
        New-RcProfile -Code 'SomeGame' -OldRelative ($name + '\game.bin') -ExeName 'game.bin'
        [void](New-RcFile ($name + '\a\game.bin'))
        [void](New-RcFile ($name + '\b\game.bin'))

        $reports = @(Get-RcPlan -Index @{ 'game.bin' = @('SomeGame', 'OtherGame') })
        $reports[0].Status | Should -BeExactly 'ambiguous'
    }
}
