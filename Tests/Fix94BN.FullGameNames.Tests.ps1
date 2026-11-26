#Requires -Module Pester

# RC9.4 lane BN: a player reads the full game title, never a profile code such as "stv_batmanfr".
# Only function definitions of the production script are loaded. Everything lives under TestDrive.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Fix94BN bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix94bn-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function Write-Log { param($msg) }

    $script:tpRoot = Join-Path $TestDrive 'TeknoParrot'
    $script:userDir = Join-Path $TestDrive 'UserProfiles'
    foreach ($dir in @('Metadata', 'GameProfiles')) { New-Item -ItemType Directory -Force -Path (Join-Path $script:tpRoot $dir) | Out-Null }
    New-Item -ItemType Directory -Force -Path $script:userDir | Out-Null
    Set-Content -LiteralPath (Join-Path $script:tpRoot 'Metadata\stv_batmanfr.json') -Value '{"game_name":"Batman Forever"}' -Encoding ascii
    # TeknoParrot's own profile and the user's copy both carry only the code as GameName.
    $profileXml = '<GameProfile><GameName>stv_batmanfr</GameName></GameProfile>'
    Set-Content -LiteralPath (Join-Path $script:tpRoot 'GameProfiles\stv_batmanfr.xml') -Value $profileXml -Encoding ascii
    Set-Content -LiteralPath (Join-Path $script:userDir 'stv_batmanfr.xml') -Value $profileXml -Encoding ascii
    Set-Content -LiteralPath (Join-Path $script:userDir 'nometa_game.xml') -Value '<GameProfile><GameName>Plain Name</GameName></GameProfile>' -Encoding ascii
}

Describe 'Full game names' {
    It 'the profile label is the full title when the profile GameName is only the code' {
        Get-TpmGameDisplayLabel -ProfilePath (Join-Path $script:userDir 'stv_batmanfr.xml') -Fallback 'stv_batmanfr' | Should -Be 'Batman Forever'
    }

    It 'a game with no title list entry keeps the name written in its own profile' {
        Get-TpmGameDisplayLabel -ProfilePath (Join-Path $script:userDir 'nometa_game.xml') -Fallback 'nometa_game' | Should -Be 'Plain Name'
    }

    It 'the game list under Browse and select specific games shows the title with its current region' {
        $script:rows = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:rows.Add([string]($Object -join ' ')) }
        Mock Read-TpmChoice { 'L' }
        Mock Read-HostSafe { 'D' }
        $file = Get-Item -LiteralPath (Join-Path $script:userDir 'stv_batmanfr.xml')
        [void](Select-RegisteredGamesInteractive -UserProfilesDir $script:userDir -Profiles @($file) -LabelSuffix @{ $file.FullName = ' (now: Auto)' })
        $text = $script:rows -join "`n"
        $text | Should -Match 'Batman Forever \(now: Auto\)'
        $text | Should -Not -Match 'stv_batmanfr'
    }

    It 'a result screen item that is a profile code shows the title' {
        Get-TpmTransactionPresentationItemLabel -Item 'stv_batmanfr' | Should -Be 'Batman Forever'
    }

    It 'the Controls search finds a game by a word that is only in the full title, and still by the file name' {
        Test-TpmGameNameContains -Code 'stv_batmanfr' -Needle 'batman' | Should -BeTrue
        Test-TpmGameNameContains -Code 'stv_batmanfr' -Needle 'batmanforever' | Should -BeTrue
        Test-TpmGameNameContains -Code 'stv_batmanfr' -Needle 'stv_bat' | Should -BeTrue
        Test-TpmGameNameContains -Code 'stv_batmanfr' -Needle 'zelda' | Should -BeFalse
    }

    It 'Find-TpmBaselineProfiles returns the game for a title word' {
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { Get-ChildItem -LiteralPath $script:userDir -Filter '*.xml' }
        @(Find-TpmBaselineProfiles -UserProfilesDir $script:userDir -Text 'forever').BaseName | Should -Be @('stv_batmanfr')
    }
}
