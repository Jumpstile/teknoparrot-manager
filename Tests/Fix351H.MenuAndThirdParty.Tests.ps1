#Requires -Module Pester

# #351: what a player sees for third-party items (Game Notes) and for the one-line game file edits in the patch menu.
# Everything is synthetic under TestDrive.

BeforeAll {
    $root = Split-Path -Parent $PSScriptRoot
    $text = foreach ($file in @('TeknoParrot-Manager.ps1', 'scripts\TpmRequiredPatchEngine.ps1')) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText((Join-Path $root $file)), [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { throw "Could not parse $file." }
        @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    }
    $functionFile = Join-Path $TestDrive 'tpm-351h-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, ($text -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    $script:H351Checks = Join-Path $root 'scripts\TpmThirdPartyChecks.json'
    Mock Write-Log {}

    function New-H351Profile {
        param([string]$Dir, [string]$Code, [string]$GameExe)
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><GamePath>' + $GameExe + '</GamePath></GameProfile>'
        [System.IO.File]::WriteAllText((Join-Path $Dir ($Code + '.xml')), $xml, (New-Object System.Text.UTF8Encoding $false))
    }
}

Describe 'Third-party items in the Game Notes' {
    BeforeEach {
        $script:up = Join-Path $TestDrive ('up-' + [guid]::NewGuid().ToString('N'))
        $script:game = Join-Path $TestDrive ('game-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:up, $script:game -Force | Out-Null
        New-H351Profile -Dir $script:up -Code 'DragonDanceNesica' -GameExe (Join-Path $script:game 'game.exe')
    }

    It 'tells the player what is missing in the game folder' {
        # Mutation: skip the check -> the player is never told the files are missing.
        $lines = @(Get-TpmThirdPartyNoteLines -Code 'DragonDanceNesica' -UserProfilesDir $script:up -DefinitionPath $script:H351Checks)
        ($lines -join ' ') | Should -Match 'did not find it'
        ($lines -join ' ') | Should -Match 'Game_liong.exe'
    }

    It 'says it found the files when both are there' {
        # Mutation: always report missing -> a player who did everything is told to start over.
        Set-Content -LiteralPath (Join-Path $script:game 'Game_liong.exe') -Value 'x'
        Set-Content -LiteralPath (Join-Path $script:game 'ddraw.dll') -Value 'x'
        $lines = @(Get-TpmThirdPartyNoteLines -Code 'DragonDanceNesica' -UserProfilesDir $script:up -DefinitionPath $script:H351Checks)
        ($lines -join ' ') | Should -Match 'found it'
        ($lines -join ' ') | Should -Not -Match 'did not find'
    }

    It 'shows a guide link as text only and has nothing for a game that is not in the list' {
        # Mutation: open the link -> Start-Process is called.
        Mock Start-Process {}
        $lines = @(Get-TpmThirdPartyNoteLines -Code 'FarCryParadiseLost' -UserProfilesDir $script:up -DefinitionPath $script:H351Checks)
        ($lines -join ' ') | Should -Match 'TPM does not open it'
        Should -Invoke Start-Process -Times 0
        @(Get-TpmThirdPartyNoteLines -Code 'NoSuchGame' -UserProfilesDir $script:up -DefinitionPath $script:H351Checks).Count | Should -Be 0
    }
}

Describe 'Settings-line edits in the patch menu' {
    It 'tells edit-only recipes from file patches, and treats the Lost Land edit as optional' {
        # Mutation: treat every recipe as edit-only -> a ZIP patch would skip its ZIP.
        $edit = [pscustomobject]@{ Id = 'lost-land-adventure-shader-reload-off'; ExecutableSha256 = ''; Operations = @([pscustomobject]@{ Type = 'SetIniValue' }) }
        $zip = [pscustomobject]@{ Id = 'other'; ExecutableSha256 = ('A' * 64); Operations = @([pscustomobject]@{ Type = 'ReplaceFile' }) }
        Test-TpmRequiredPatchEditOnly -Entry $edit | Should -BeTrue
        Test-TpmRequiredPatchEditOnly -Entry $zip | Should -BeFalse
        Test-TpmRequiredPatchOptional -Entry $edit | Should -BeTrue
        Test-TpmRequiredPatchOptional -Entry $zip | Should -BeFalse
    }

    It 'does not ask for a program hash when an edit-only recipe has none, but still requires one for a file patch' {
        # Mutation: skip the hash check for every recipe -> a wrong game build is accepted.
        $results = New-Object System.Collections.Generic.List[object]
        $exe = Join-Path $TestDrive 'g.exe'; Set-Content -LiteralPath $exe -Value 'x'
        $edit = [pscustomobject]@{ Id = 'e'; ProfileId = 'P'; ExecutableSha256 = ''; Operations = @([pscustomobject]@{ Type = 'SetIniValue' }) }
        $zip = [pscustomobject]@{ Id = 'z'; ProfileId = 'P'; ExecutableSha256 = ('A' * 64); Operations = @([pscustomobject]@{ Type = 'ReplaceFile'; AfterSha256 = ('B' * 64) }) }
        Test-TpmRequiredPatchBuild -Entry $edit -GamePath $exe -Entries @($edit) -Results $results | Should -BeTrue
        Test-TpmRequiredPatchBuild -Entry $zip -GamePath $exe -Entries @($zip) -Results $results | Should -BeFalse
    }
}
