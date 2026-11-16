#Requires -Module Pester

# What a player sees or loses: the Library Health "Game support" view, PCSX2x6 games being found by name, and the
# coverage tool's table. Synthetic fixtures under $TestDrive only.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'gamesupport-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding UTF8
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot '..\scripts\New-TpmGameCoverage.ps1')
    $script:productScript = (Resolve-Path $scriptPath).Path

    function New-GsProfile {
        param([string]$Dir, [string]$Code, [string]$Emulator = 'TeknoParrot', [string]$GamePath = '', [switch]$TwoExe, [string]$GamePath2 = '')
        $two = if ($TwoExe) { '<HasTwoExecutables>true</HasTwoExecutables>' } else { '' }
        Set-Content -LiteralPath (Join-Path $Dir "$Code.xml") -Value "<GameProfile><GameName>Game $Code</GameName><EmulatorType>$Emulator</EmulatorType>$two<GamePath>$GamePath</GamePath><GamePath2>$GamePath2</GamePath2></GameProfile>"
    }
}

Describe 'PCSX2x6 game files' {
    It 'finds .acgame files by name next to the other game file types' {
        $dir = Join-Path $TestDrive 'games'
        New-Item -ItemType Directory -Path $dir | Out-Null
        foreach ($n in 'NM00047.acgame', 'game.exe', 'notes.txt') { Set-Content -LiteralPath (Join-Path $dir $n) -Value 'x' }
        $names = @(Get-GameFiles $dir | ForEach-Object { $_.Name })
        $names | Should -Contain 'NM00047.acgame'
        $names | Should -Contain 'game.exe'
        $names | Should -Not -Contain 'notes.txt'
    }
}

Describe 'Library Health game support' {
    BeforeEach { Mock Write-Log {} }

    It 'counts games per emulator and names the ones that need the player' {
        $dir = Join-Path $TestDrive 'up1'
        New-Item -ItemType Directory -Path $dir | Out-Null
        $good = Join-Path $TestDrive 'good.exe'; Set-Content -LiteralPath $good -Value 'x'
        New-GsProfile -Dir $dir -Code 'A' -GamePath $good
        New-GsProfile -Dir $dir -Code 'B' -GamePath (Join-Path $TestDrive 'gone.exe')
        New-GsProfile -Dir $dir -Code 'C' -Emulator 'Lindbergh' -GamePath $good -TwoExe
        New-GsProfile -Dir $dir -Code 'D' -Emulator 'Lindbergh' -GamePath $good
        $guide = @([pscustomobject]@{ profile_name = 'A'; game_name = 'A'; notes = 'Do this first.' })
        $summary = Get-TpmGameSupportSummary -ProfileFiles @(Get-ChildItem -LiteralPath $dir -Filter '*.xml') -ValidCodes @('A', 'C', 'D') -GuideRows $guide
        $tp = @($summary.Rows | Where-Object Emulator -eq 'TeknoParrot')[0]
        $tp.Registered | Should -Be 2
        $tp.FilesFound | Should -Be 1
        $tp.StepsShown | Should -Be 1
        $tp.NeedsYou | Should -Be 1
        $lin = @($summary.Rows | Where-Object Emulator -eq 'Lindbergh')[0]
        $lin.NeedsYou | Should -Be 1   # C needs its second game file; D does not
        @($summary.NeedsYouNames) | Should -Contain 'Game B'
        @($summary.NeedsYouNames) | Should -Contain 'Game C'
        @($summary.NeedsYouNames) | Should -Not -Contain 'Game D'
    }

    It 'says the steps were not counted when there is no saved guide copy' {
        $summary = [pscustomobject]@{ GuideAvailable = $false; Rows = @(); NeedsYouNames = @() }
        (@(Get-TpmGameSupportLines -Summary $summary) -join ' ') | Should -Match 'no saved copy'
    }

    It 'shows a Game support row only when the result has the view, and flags games that need the player' {
        $base = [ordered]@{
            Outcome = 'SUCCEEDED'; DiscoveryComplete = $true; OptionalCoverageComplete = $true; OptionalCheckFailed = 0
            PostgresInventoryStatus = 'Complete'; PostgresInventoryErrors = @(); ReadOnly = $true; Registered = 2
            Valid = @('A', 'B'); Broken = @(); Empty = @(); GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @()
            PostgresNeeded = @(); PostgresConfigured = 0; PostgresAutoCreateProfiles = @()
            PostgresServiceExists = $false; PostgresServiceStatus = 'NotInstalled'
            ReShadeCount = 0; BepInExCount = 0; DetectedGpuVendor = 'Intel'; LogPath = 'x.log'
            PostgresNeededLabels = @(); PostgresConfiguredLabels = @(); PostgresPsqlStatus = 'Unknown'
            OptionalCoverageUnavailable = $false; OptionalCoverageError = ''; LastFullRun = ''
        }
        @(Get-TpmLibraryHealthRows -Result ([pscustomobject]$base) | Where-Object Area -eq 'Game support').Count | Should -Be 0
        $base['GameSupport'] = [pscustomobject]@{ GuideAvailable = $true; Rows = @(); NeedsYouNames = @('Game B') }
        $row = @(Get-TpmLibraryHealthRows -Result ([pscustomobject]$base) | Where-Object Area -eq 'Game support')[0]
        $row.Text | Should -Match '^Needs attention - 1 game needs you'
        $base['GameSupport'] = [pscustomobject]@{ GuideAvailable = $true; Rows = @(); NeedsYouNames = @() }
        $ok = @(Get-TpmLibraryHealthRows -Result ([pscustomobject]$base) | Where-Object Area -eq 'Game support')[0]
        $ok.Text | Should -Match '^OK'
    }
}

Describe 'Coverage tool' {
    BeforeAll {
        $script:tables = [pscustomobject]@{ PathLimits = @('LongPath'); VersionPins = @(); GpuIncompatible = @{ AMD = @() }; FirmwareEmulators = @('pcsx2x6') }
        $script:guide = @(
            [pscustomobject]@{ profile_name = 'Fixed'; game_name = 'Fixed'; tp_loader = 'TeknoParrot' }
            [pscustomobject]@{ profile_name = 'LongPath'; game_name = 'Long'; tp_loader = 'TeknoParrot' }
            [pscustomobject]@{ profile_name = 'Steps'; game_name = 'Steps'; tp_loader = 'TeknoParrot'; notes = 'Do this.' }
            [pscustomobject]@{ profile_name = 'Quiet'; game_name = 'Quiet'; tp_loader = 'TeknoParrot' }
            [pscustomobject]@{ profile_name = 'rom_a'; game_name = 'Rom'; tp_loader = 'TeknoNaomi'; general_issues = 'Select a.zip.'; variants = @([pscustomobject]@{ profile_name = 'rom_a2'; game_name = 'Rom 2' }) }
        )
        $script:catalog = @{ Fixed = $true; LongPath = $true; Steps = $true; Quiet = $true; Extra = $true }
        $script:rows = @(Get-TpmCoverageRows -Guide $guide -CatalogCodes $catalog -RecipeIds @('Fixed') -Tables $tables -ProfileInfo @{})
    }

    It 'gives every game one disposition by the stated order' {
        $by = @{}; foreach ($r in $rows) { $by[$r.ProfileId] = $r.Disposition }
        $by['Fixed'] | Should -Be 'Applied'
        $by['LongPath'] | Should -Be 'Checked'
        $by['Steps'] | Should -Be 'Guided'
        $by['Quiet'] | Should -Be 'Handled'
        $by['rom_a'] | Should -Be 'Gap'
        $by['rom_a2'] | Should -Be 'Gap'
        $by['Extra'] | Should -Be 'Handled'
    }

    It 'names the exact missing data for a game the catalog does not have' {
        (@($rows | Where-Object ProfileId -eq 'rom_a')[0]).OpenItems | Should -Match 'not in the pinned catalog'
    }

    It 'adds up: every row is counted once in the totals and the emulator table' {
        $s = Get-TpmCoverageSummary -Rows $rows
        $s.Totals.Total | Should -Be 7
        ($s.Totals.Applied + $s.Totals.Checked + $s.Totals.Guided + $s.Totals.Handled + $s.Totals.Gap) | Should -Be $s.Totals.Total
        (@($s.Families | ForEach-Object { $_.Total }) | Measure-Object -Sum).Sum | Should -Be $s.Totals.Total
    }

    It 'reads the product check tables as syntax, matching the product' {
        $t = Get-TpmCoverageCheckTables -ProductScriptPath $productScript
        $t.PathLimits | Should -Contain 'BBHPro'
        $t.FirmwareEmulators | Should -Contain 'Pcsx2x6'
        $t.GpuIncompatible.Keys | Should -Contain 'AMD'
    }

    It 'keeps docs\GAME-SUPPORT.md consistent with itself (totals equal the emulator table)' {
        $text = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\docs\GAME-SUPPORT.md'))
        $total = [int][regex]::Match($text, '(\d+) game IDs in all').Groups[1].Value
        $total | Should -BeGreaterThan 0
        $sum = 0
        foreach ($m in [regex]::Matches($text, '(?m)^\| [^|]+ \| (\d+) \| \d+ \| \d+ \| \d+ \| \d+ \| \d+ \| \d+ \|\s*$')) { $sum += [int]$m.Groups[1].Value }
        $sum | Should -Be $total
    }
}
