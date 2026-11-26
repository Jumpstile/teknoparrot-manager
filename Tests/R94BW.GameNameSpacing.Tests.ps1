#Requires -Module Pester

# R94BW: a game name shows its spaces ("Golden Tee Live 2019"), and an arcade stick is not told to turn on controllers.
# The production script is parsed and only its function definitions are dot-sourced. Nothing here touches a real install.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'R94BW tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-r94bw-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    function Write-Log { param([Parameter(ValueFromRemainingArguments)]$Ignored) }

    # A TeknoParrot folder that has only the shared catalog (no Metadata folder), and a profile with a run-together GameName.
    $script:R94Root = Join-Path $TestDrive 'TeknoParrot'
    New-Item -ItemType Directory -Path (Join-Path $script:R94Root 'GameProfiles') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $script:R94Root 'Metadata.catalog.json'), '{ "GoldenTeeLive2019": { "game_name": "Golden Tee Live 2019", "release_year": "2019" }, "Other": { "game_name": "Other Game" } }')
    [System.IO.File]::WriteAllText((Join-Path $script:R94Root 'GameProfiles\PowerPuttLive2012.xml'), '<GameProfile><GameName>PowerPuttLive2012</GameName></GameProfile>')
    $script:tpRoot = $script:R94Root
    $script:TpmGameTitleCache = $null
}

Describe 'full game names with spaces' {
    It 'uses the name from the shared TeknoParrot catalog when the game has no file of its own' {
        # Mutation: only read Metadata\<code>.json.
        Get-TpmGameTitle -Code 'GoldenTeeLive2019' | Should -Be 'Golden Tee Live 2019'
    }

    It 'puts a space before a year or number in a run-together name, and leaves joined names alone' {
        Get-TpmGameTitle -Code 'PowerPuttLive2012' | Should -Be 'Power Putt Live 2012'
        Split-TpmRunTogetherGameName -Name 'Golden Tee Live2019' | Should -Be 'Golden Tee Live 2019'
        foreach ($same in 'R-Tuned', '2Spicy', 'Initial D 8', 'Mario Kart GP2') { Split-TpmRunTogetherGameName -Name $same | Should -Be $same }
    }
}

Describe 'arcade stick reminder' {
    It 'does not tell an arcade stick user to turn on controllers' {
        $text = (Get-TpmControllerPowerReminder -Preset 'LearnedArcade') -join ' '
        $text | Should -Be 'Make sure your arcade controls are plugged in.'
        $text | Should -Not -Match 'turn on'
    }
}
