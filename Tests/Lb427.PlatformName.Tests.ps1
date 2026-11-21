#Requires -Module Pester

# Issue #427: the LaunchBox platform the Manager makes is called "TeknoParrot" and is scraped as "Arcade".
# LaunchBox's own game list has no platform called TeknoParrot: its arcade games live under "Arcade". LaunchBox finds names, art and
# details for a platform through ScrapeAs, so a wrong value here means no information for any TeknoParrot game.
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs.
# What this CANNOT prove: a real LaunchBox scraping the platform. The written test plan for that is in docs\TESTER-GUIDE.md (Test 43).

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Platform tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:PlatFile = Join-Path $TestDrive 'tpm-platform-functions.ps1'
    [System.IO.File]::WriteAllText($script:PlatFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:PlatFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
}

Describe 'Issue 427: the LaunchBox platform name' {
    It 'a new platform is named TeknoParrot and scraped as Arcade, and it is not made twice' {
        # Mutation: another platform name or ScrapeAs -> LaunchBox lists the games under the wrong platform or finds no information.
        $doc = [xml]'<LaunchBox></LaunchBox>'
        Get-OrCreateLaunchBoxPlatform -platformsListDoc $doc -platformName 'TeknoParrot' -tpRoot 'C:\TP' -lbRoot 'C:\LaunchBox' | Should -BeTrue
        $platform = $doc.SelectSingleNode('/LaunchBox/Platform')
        $platform.Name | Should -BeExactly 'TeknoParrot'
        $platform.ScrapeAs | Should -BeExactly 'Arcade'
        Get-OrCreateLaunchBoxPlatform -platformsListDoc $doc -platformName 'TeknoParrot' -tpRoot 'C:\TP' -lbRoot 'C:\LaunchBox' | Should -BeFalse
        @($doc.SelectNodes('/LaunchBox/Platform')).Count | Should -Be 1
    }

}
