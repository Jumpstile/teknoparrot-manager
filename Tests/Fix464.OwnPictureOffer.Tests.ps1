#Requires -Module Pester

# After the picture download, games still without a picture are named and the user may pick own pictures for some of them.
# Real folders and files under $TestDrive; the Y/N question, the game picker and the file window are replaced.
# What this CANNOT prove: the real file window or a real console run.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX464 bootstrap could not parse the production script.' }
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'fix464-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    function Write-Log { param([string]$msg) }
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Rest) }
}

Describe 'Own pictures after the picture download' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:profiles = Join-Path $script:root 'UserProfiles'
        $script:tp = Join-Path $script:root 'TP'
        $script:icons = Join-Path $script:tp 'Icons'
        $script:pics = Join-Path $script:root 'MyPics'
        foreach ($d in @($script:profiles, $script:icons, $script:pics)) { [void][System.IO.Directory]::CreateDirectory($d) }
        foreach ($code in @('Alpha', 'Bravo', 'Charlie')) {
            [System.IO.File]::WriteAllText((Join-Path $script:profiles ($code + '.xml')), ('<GameProfile><GameName>{0} Game</GameName></GameProfile>' -f $code))
        }
        $script:asked = 0
        function Read-TpmYesNo { param($Prompt, $Default, $WorkflowContext, $DetailsAction) $script:asked++; return $script:answer }
        function Select-RegisteredGamesInteractive { param($UserProfilesDir, $Profiles, $LabelSuffix, [switch]$DefaultAll) $script:pickerSaw = @($Profiles | ForEach-Object { $_.BaseName }); return @($Profiles | Where-Object { $script:chosenCodes -contains $_.BaseName }) }
        function Read-PathWithBrowse { param($Prompt, $Mode, $FileFilter) $script:browseCalls++; foreach ($k in $script:browseAnswers.Keys) { if ($Prompt -like "*$k*") { return $script:browseAnswers[$k] } }; return '' }
        $script:answer = 'Y'; $script:pickerSaw = @(); $script:browseCalls = 0
    }

    It 'lists only the games without a picture' {
        [System.IO.File]::WriteAllText((Join-Path $script:icons 'Bravo.png'), 'x')
        $names = @(Get-TpmGamesWithoutPicture -UserProfilesDir $script:profiles -TpRoot $script:tp | ForEach-Object { $_.BaseName })
        $names | Should -Be @('Alpha', 'Charlie')
    }

    It 'shows nothing and asks nothing when every game has a picture' {
        foreach ($code in @('Alpha', 'Bravo', 'Charlie')) { [System.IO.File]::WriteAllText((Join-Path $script:icons ($code + '.png')), 'x') }
        $out = Invoke-TpmOwnPictureOffer -UserProfilesDir $script:profiles -TpRoot $script:tp 6>&1
        @($out | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }).Count | Should -Be 0
        $script:asked | Should -Be 0
    }

    It 'changes nothing when the user answers N' {
        $script:answer = 'N'
        $result = Invoke-TpmOwnPictureOffer -UserProfilesDir $script:profiles -TpRoot $script:tp 6>$null
        $result.Added | Should -Be 0
        $script:browseCalls | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:icons).Count | Should -Be 0
    }

    It 'skips a canceled game and still adds the others, each from its own folder' {
        $other = Join-Path $script:root 'Elsewhere'
        [void][System.IO.Directory]::CreateDirectory($other)
        $a = Join-Path $script:pics 'a.png'; $c = Join-Path $other 'c.png'
        [System.IO.File]::WriteAllText($a, 'a'); [System.IO.File]::WriteAllText($c, 'c')
        $script:chosenCodes = @('Alpha', 'Bravo', 'Charlie')
        $script:browseAnswers = @{ 'Alpha Game' = $a; 'Bravo Game' = ''; 'Charlie Game' = $c }
        $text = (Invoke-TpmOwnPictureOffer -UserProfilesDir $script:profiles -TpRoot $script:tp 6>&1 | Out-String)
        $script:pickerSaw | Should -Be @('Alpha', 'Bravo', 'Charlie')
        $text | Should -Match 'No picture chosen for Bravo Game\. Skipped\.'
        Test-Path -LiteralPath (Join-Path $script:icons 'Alpha.png') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $script:icons 'Bravo.png') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:icons 'Charlie.png') | Should -BeTrue
    }
}
