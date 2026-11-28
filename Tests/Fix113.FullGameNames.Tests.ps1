#Requires -Module Pester

# FIX113: games without pictures are shown by their full title, never by the short profile code.
#
#  Item 1  Get-TpmGameTitle turns a profile code into the full title; a code with no title (or text that is not a code) comes back unchanged.
#  Item 2  Name lists (Format-TpmNameList) show titles.
#
# The production script is parsed and only its function definitions are dot-sourced. Nothing here touches a real install,
# the registry or the network. Each It names the product mutation that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX113 tests could not parse the production script.' }
    $definitions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix113-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile

    # A small TeknoParrot folder: one game with a metadata title, one with only a profile title, one with neither.
    $script:F113Root = Join-Path $TestDrive 'TeknoParrot'
    New-Item -ItemType Directory -Path (Join-Path $script:F113Root 'Metadata') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:F113Root 'GameProfiles') -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $script:F113Root 'Metadata\tekno3do_md23do.json'), '{ "game_name": "Tekken 2" }')
    [System.IO.File]::WriteAllText((Join-Path $script:F113Root 'GameProfiles\profileonly.xml'), '<GameProfile><GameName>Profile Only Game</GameName></GameProfile>')
    $script:tpRoot = $script:F113Root
    $script:TpmGameTitleCache = $null
}

Describe 'full game title helper' {
    It 'turns a known profile code into the full title' {
        # Mutation: return the code, or read a different Metadata field.
        Get-TpmGameTitle -Code 'tekno3do_md23do' | Should -Be 'Tekken 2'
    }

    It 'uses the profile GameName when there is no metadata file' {
        # Mutation: drop the GameProfiles fallback.
        Get-TpmGameTitle -Code 'profileonly' | Should -Be 'Profile Only Game'
    }

    It 'shows the full profile name of a TeknoChi game even though its profile says development only' {
        # Mutation: skip a profile whose DevOnly is true, so the game shows by its short code.
        [System.IO.File]::WriteAllText((Join-Path $script:F113Root 'GameProfiles\TeknoChiTestGame.xml'), '<GameProfile><GameName>Chihiro Test Game</GameName><EmulatorType>TeknoChi</EmulatorType><DevOnly>true</DevOnly></GameProfile>')
        $script:TpmGameTitleCache = $null
        Get-TpmGameTitle -Code 'TeknoChiTestGame' | Should -Be 'Chihiro Test Game'
        Format-TpmNameList -Names @('TeknoChiTestGame') | Should -Be 'Chihiro Test Game'
    }

    It 'falls back to the short name, never blank, for an unknown code or non-code text' {
        # Mutation: return an empty string for an unknown code, or probe a path-like name.
        Get-TpmGameTitle -Code 'nosuchgame' | Should -Be 'nosuchgame'
        Get-TpmGameTitle -Code 'D:' | Should -Be 'D:'
        Get-TpmGameTitle -Code '..\x' | Should -Be '..\x'
    }

    It 'puts the title first and the code after it for a Details heading' {
        # Mutation: put the code first or drop the title.
        Get-TpmGameTitleWithCode -Code 'tekno3do_md23do' | Should -Be 'Tekken 2 (tekno3do_md23do)'
        Get-TpmGameTitleWithCode -Code 'nosuchgame' | Should -Be 'nosuchgame'
    }
}

Describe 'screens show full titles' {
    It 'name lists show titles and keep unknown names' {
        # Mutation: join the raw codes.
        Format-TpmNameList -Names @('tekno3do_md23do', 'nosuchgame') | Should -Be 'Tekken 2 and nosuchgame'
    }
}

Describe 'Controls game picker shows full titles' {
    BeforeAll {
        $script:F113Users = Join-Path $TestDrive 'UserProfiles'
        New-Item -ItemType Directory -Path $script:F113Users -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:F113Root 'Metadata\stv_batmanfr.json'), '{ "game_name": "Batman Forever" }')
        # No GameName and no Description element: the player must still see the full title, not the file name.
        [System.IO.File]::WriteAllText((Join-Path $script:F113Users 'stv_batmanfr.xml'), '<GameProfile><GamePath>C:\Games\batman.exe</GamePath></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $script:F113Users 'Batman.xml'), '<GameProfile><GameName>Batman</GameName></GameProfile>')
    }

    It 'lists the full game name for a profile that has no GameName element' {
        # Mutation: show the profile file name (stv_batmanfr) in the picker.
        $script:F113Rows = $null
        Mock Read-HostSafe { 'Batman' }
        Mock Write-TpmText { }
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { Get-ChildItem -LiteralPath $script:F113Users -Filter '*.xml' }
        Mock Read-TpmNumberedListChoice { $script:F113Rows = @($Rows); return 0 }
        $game = Read-TpmControlsGamePick -UserProfilesDir $script:F113Users
        @($script:F113Rows) | Should -Contain 'Batman Forever'
        @($script:F113Rows) | Should -Not -Contain 'stv_batmanfr'
        $game.Code | Should -Be 'Batman'
    }
}

Describe 'Controls game picker with a run-together profile name' {
    BeforeAll {
        $script:F94Users = Join-Path $TestDrive 'UserProfilesGt'
        New-Item -ItemType Directory -Path $script:F94Users -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $script:F94Users 'GoldenTeeLive2019.xml'), '<GameProfile><GameName>GoldenTeeLive2019</GameName></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $script:F113Root 'GameProfiles\GoldenTeeLive2019.xml'), '<GameProfile><GameName>GoldenTeeLive2019</GameName></GameProfile>')
        Mock Write-TpmText { }
        Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { Get-ChildItem -LiteralPath $script:F94Users -Filter '*.xml' }
        Mock Read-TpmNumberedListChoice { $script:F94Rows = @($Rows); return 0 }
    }

    It 'shows Golden Tee Live 2019 from the TeknoParrot metadata name, found by either spelling' {
        [System.IO.File]::WriteAllText((Join-Path $script:F113Root 'Metadata\GoldenTeeLive2019.json'), '{ "game_name": "Golden Tee Live 2019" }')
        $script:TpmGameTitleCache = $null
        foreach ($typed in @('golden tee live 2019', 'goldenteelive2019')) {
            $script:F94Rows = $null
            $script:F94Typed = $typed
            Mock Read-HostSafe { $script:F94Typed }
            $game = Read-TpmControlsGamePick -UserProfilesDir $script:F94Users
            @($script:F94Rows) | Should -Contain 'Golden Tee Live 2019'
            $game.Title | Should -Be 'Golden Tee Live 2019'
        }
    }

    It 'still shows Golden Tee Live 2019 when the metadata file is missing' {
        Remove-Item -LiteralPath (Join-Path $script:F113Root 'Metadata\GoldenTeeLive2019.json') -Force
        $script:TpmGameTitleCache = $null
        Mock Read-HostSafe { 'goldenteelive2019' }
        $game = Read-TpmControlsGamePick -UserProfilesDir $script:F94Users
        $game.Title | Should -Be 'Golden Tee Live 2019'
    }
}

Describe 'profile names text for a screen line' {
    It 'shows each game by its full name, never by its profile code' {
        # Mutation: join the file base names (the old shared-database message did this).
        $dir = Join-Path $TestDrive 'users113'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir 'profileonly.xml'), '<GameProfile><GameName>Profile Only Game</GameName></GameProfile>')
        [System.IO.File]::WriteAllText((Join-Path $dir 'nameless_code.xml'), '<GameProfile></GameProfile>')
        $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.xml' | Sort-Object Name)
        Get-TpmProfileNamesText -ProfileFiles $files | Should -Be 'nameless_code, Profile Only Game'
    }
}
