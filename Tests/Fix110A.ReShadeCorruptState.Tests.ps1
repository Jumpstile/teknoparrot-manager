#Requires -Module Pester

# FIX110A (S-12): a ReShade state file (profiles.json: remembered profiles, favorites, history) that cannot be read.
#   Read-TpmReShadeState marks such a file with a Corrupt flag. Before, every writer saved that flag over the unreadable original, so the
#   original was lost and the flag stayed in the new file: later readers refused every favorite and every history entry, including new ones.
#   Now Write-TpmReShadeState keeps a checked copy of an unreadable original before replacing it (and leaves it alone if no checked copy can be made),
#   never saves the flag, and the "empty" placeholder lists are real objects that can be extended and saved.
# These tests drive the real functions with synthetic state folders in $TestDrive; nothing outside $TestDrive is touched.
# What this CANNOT prove: how the menus show the result of a failed save (the screens are script body).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:f110aAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX110A bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix110a-rs-functions.ps1'
    ($script:f110aAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:logPath = Join-Path $TestDrive 'fix110a-rs.log'
    $script:logWarnShown = $false

    function New-F110aStateRoot {
        $root = Join-Path $TestDrive ('state-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($root)
        return $root
    }
    # A state file that cannot be parsed, with bytes that are easy to compare.
    function New-F110aUnreadableState {
        param([string]$Root)
        $bytes = [byte[]](0x7B, 0x20, 0x6E, 0x6F, 0x74, 0x20, 0x6A, 0x73, 0x6F, 0x6E, 0x20, 0x01, 0x02)
        [System.IO.File]::WriteAllBytes((Join-Path $Root 'profiles.json'), $bytes)
        return $bytes
    }
    function Get-F110aSidecars {
        param([string]$Root)
        return @(Get-ChildItem -LiteralPath $Root -Force -File | Where-Object { $_.Name -like 'profiles.json.unreadable-*' })
    }
    function Save-F110aHistory {
        param([string]$Root)
        Add-TpmReShadeProfileHistory -GameId 'game-1' -ProfileDefinition (Get-TpmReShadeProfile -ProfileId 'Levels') -StateRoot $Root
    }
}

Describe 'FIX110A S-12 an unreadable ReShade state is kept, and the flag is never saved' {
    BeforeEach {
        $script:f110aLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:f110aLog.Add([string]$msg) }
    }

    It 'keeps a checked copy of the unreadable file before a history entry is saved' {
        # Mutation: drop the preserve step in Write-TpmReShadeState (or copy after the replace) -> the unreadable original is overwritten and no sidecar exists.
        $root = New-F110aStateRoot
        $original = New-F110aUnreadableState -Root $root
        (Read-TpmReShadeState -StateRoot $root).Corrupt | Should -BeTrue
        Save-F110aHistory -Root $root
        $copies = @(Get-F110aSidecars -Root $root)
        $copies.Count | Should -Be 1
        [System.IO.File]::ReadAllBytes($copies[0].FullName) | Should -Be $original
        ($script:f110aLog -join "`n") | Should -Match 'A copy was kept as profiles\.json\.unreadable-'
    }

    It 'reads a remembered game name with a non-ASCII letter back unchanged' {
        # Mutation: drop -Encoding UTF8 from Read-TpmReShadeState -> on Windows PowerShell 5.1 the name comes back garbled and the remembered profile is lost.
        $root = New-F110aStateRoot
        $name = 'Game' + [char]0xE4 + 'X'
        $json = '{"Profiles":{"' + $name + '":{"ProfileId":"Levels"}},"Favorites":[],"History":{}}'
        [System.IO.File]::WriteAllText((Join-Path $root 'profiles.json'), $json, (New-Object System.Text.UTF8Encoding $false))
        $state = Read-TpmReShadeState -StateRoot $root
        @($state.Profiles.PSObject.Properties.Name) | Should -Contain $name
    }

    It 'does not save the Corrupt flag, so a new history entry is readable' {
        # Mutation: serialize the whole state object again (no -ExcludeProperty Corrupt) -> the new file still says Corrupt and every later reader refuses the saved history.
        $root = New-F110aStateRoot
        [void](New-F110aUnreadableState -Root $root)
        Save-F110aHistory -Root $root
        $saved = Read-TpmReShadeState -StateRoot $root
        $saved.PSObject.Properties['Corrupt'] | Should -BeNullOrEmpty
        @($saved.History.PSObject.Properties.Name) | Should -Contain 'game-1'
        (Get-Content -LiteralPath (Join-Path $root 'profiles.json') -Raw) | Should -Not -Match 'Corrupt'
    }

    It 'saves a new history entry after an unreadable file and offers it as a restore candidate' {
        # Mutation: keep the Corrupt flag in the saved file -> Get-TpmReShadeRestoreCandidate answers CORRUPT_HISTORY for the entry that was just saved.
        $root = New-F110aStateRoot
        [void](New-F110aUnreadableState -Root $root)
        $definition = Get-TpmReShadeProfile -ProfileId 'Levels'
        Add-TpmReShadeProfileHistory -GameId 'game-1' -ProfileDefinition $definition -StateRoot $root
        @(Get-F110aSidecars -Root $root).Count | Should -Be 1
        $candidate = Get-TpmReShadeRestoreCandidate -GameId 'game-1' -StateRoot $root
        $candidate.Found | Should -BeTrue
        $candidate.Valid | Should -BeTrue
        $candidate.Profile.ProfileId | Should -BeExactly 'Levels'
    }

    It 'leaves the unreadable file alone and saves nothing when the copy cannot be checked' {
        # Mutation: replace the original even when the kept copy does not match (or skip the comparison) -> the unreadable original is overwritten without a verified copy.
        $root = New-F110aStateRoot
        $original = New-F110aUnreadableState -Root $root
        $script:f110aHashCalls = 0
        Mock Get-FileHash { $script:f110aHashCalls++; [pscustomobject]@{ Hash = ([guid]::NewGuid().ToString('N')) } }
        { Save-F110aHistory -Root $root } | Should -Throw '*could not be copied and checked*'
        [System.IO.File]::ReadAllBytes((Join-Path $root 'profiles.json')) | Should -Be $original
        @(Get-F110aSidecars -Root $root).Count | Should -Be 0
        $script:f110aHashCalls | Should -BeGreaterThan 1
    }

    It 'makes no extra copy when the state file was readable' {
        # Mutation: always keep a copy, even of a readable state -> a sidecar appears after an ordinary save.
        $root = New-F110aStateRoot
        Save-F110aHistory -Root $root
        Save-F110aHistory -Root $root
        @(Get-F110aSidecars -Root $root).Count | Should -Be 0
        (@(Get-ChildItem -LiteralPath $root -Force | ForEach-Object Name) -join '|') | Should -BeExactly 'profiles.json'
    }

    It 'a second unreadable file makes a second, separate copy and never overwrites the first' {
        # Mutation: use a fixed sidecar name -> the second unreadable original replaces the first kept copy.
        $root = New-F110aStateRoot
        $first = New-F110aUnreadableState -Root $root
        Save-F110aHistory -Root $root
        $second = [byte[]](0x5B, 0x5B, 0x5B)
        [System.IO.File]::WriteAllBytes((Join-Path $root 'profiles.json'), $second)
        Save-F110aHistory -Root $root
        $copies = @(Get-F110aSidecars -Root $root)
        $copies.Count | Should -Be 2
        $contents = @($copies | ForEach-Object { [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($_.FullName)) })
        $contents | Should -Contain ([System.Convert]::ToBase64String($first))
        $contents | Should -Contain ([System.Convert]::ToBase64String($second))
    }
}
