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

    It 'flags a game whose BIOS ZIP the guide says to keep beside it is not in the game folder' {
        $dir = Join-Path $TestDrive 'up2'
        $games = Join-Path $TestDrive 'roms'
        New-Item -ItemType Directory -Path $dir, $games | Out-Null
        $with = Join-Path $games 'withbios.zip'; $without = Join-Path $games 'nobios.zip'
        Set-Content -LiteralPath $with -Value 'x'; Set-Content -LiteralPath $without -Value 'x'
        Set-Content -LiteralPath (Join-Path $games 'qsound.zip') -Value 'x'
        New-GsProfile -Dir $dir -Code 'HasBios' -Emulator 'TeknoCPS' -GamePath $with
        $other = Join-Path $TestDrive 'other'; New-Item -ItemType Directory -Path $other | Out-Null
        $lone = Join-Path $other 'nobios.zip'; Set-Content -LiteralPath $lone -Value 'x'
        New-GsProfile -Dir $dir -Code 'LacksBios' -Emulator 'TeknoCPS' -GamePath $lone
        $guide = @(
            [pscustomobject]@{ profile_name = 'HasBios'; game_name = 'Has Bios'; general_issues = 'Select withbios.zip. Keep qsound.zip in the same folder.' }
            [pscustomobject]@{ profile_name = 'LacksBios'; game_name = 'Lacks Bios'; general_issues = 'Select nobios.zip. Keep qsound.zip in the same folder.' }
        )
        $summary = Get-TpmGameSupportSummary -ProfileFiles @(Get-ChildItem -LiteralPath $dir -Filter '*.xml') -ValidCodes @('HasBios', 'LacksBios') -GuideRows $guide
        @($summary.NeedsYouNames) | Should -Contain 'Game LacksBios'
        @($summary.NeedsYouNames) | Should -Not -Contain 'Game HasBios'
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

Describe 'Coverage tool guide steps' {
    It 'keeps Guided only for a step the player must do, not for the ZIP pick, a BIOS ZIP beside it, or information' {
        $tables = [pscustomobject]@{ PathLimits = @(); VersionPins = @(); GpuIncompatible = @{}; FirmwareEmulators = @() }
        $guide = @(
            [pscustomobject]@{ profile_name = 'zip_only'; game_name = 'Zip Only'; tp_loader = 'TeknoCPS'; general_issues = 'Select zip_only.zip.' }
            [pscustomobject]@{ profile_name = 'with_bios'; game_name = 'With Bios'; tp_loader = 'TeknoCPS'; general_issues = 'Select with_bios.zip. Keep qsound.zip in the same folder.' }
            [pscustomobject]@{ profile_name = 'info_only'; game_name = 'Info Only'; tp_loader = 'TeknoParrot'; notes = 'Game starts with a Call Attendant message.' }
            [pscustomobject]@{ profile_name = 'has_step'; game_name = 'Has Step'; tp_loader = 'TeknoParrot'; notes = "Game starts.`nSet the Ip option to your computer address." }
            [pscustomobject]@{ profile_name = 'controls_only'; game_name = 'Controls Only'; tp_loader = 'TeknoCPS'; general_issues = 'Select a merged ROM ZIP and, where requested, a CHD from the game disc directory. Controls: Select Down and Select Up are operator buttons.' }
        )
        $catalog = @{ zip_only = $true; with_bios = $true; info_only = $true; has_step = $true; controls_only = $true }
        $by = @{}; foreach ($r in @(Get-TpmCoverageRows -Guide $guide -CatalogCodes $catalog -RecipeIds @() -Tables $tables -ProfileInfo @{})) { $by[$r.ProfileId] = $r.Disposition }
        $by['zip_only'] | Should -Be 'Handled'
        $by['with_bios'] | Should -Be 'Checked'
        $by['info_only'] | Should -Be 'Handled'
        $by['has_step'] | Should -Be 'Guided'
        $by['controls_only'] | Should -Be 'Handled'
    }
}

Describe 'Coverage tool steps TeknoParrot Manager now does' {
    It 'does not call the game revision, CD image folder or CHD root sentence a step for the player' {
        $tables = [pscustomobject]@{ PathLimits = @(); VersionPins = @(); GpuIncompatible = @{}; FirmwareEmulators = @() }
        $guide = @(
            [pscustomobject]@{ profile_name = 'rev'; game_name = 'Rev'; tp_loader = 'TeknoNaomi'; general_issues = 'Select rev.zip. Select the exact set in Game Revision; merged archives must contain that revision.' }
            [pscustomobject]@{ profile_name = 'cd'; game_name = 'Cd'; tp_loader = 'TeknoCPS'; general_issues = 'Select cd.zip. CD image: cap-x-1.chd. Set CD Image Folder if stored elsewhere.' }
            [pscustomobject]@{ profile_name = 'chd'; game_name = 'Chd'; tp_loader = 'TeknoNaomi'; general_issues = 'Select chd.zip. Required CHD: gds-1.chd. Select CHD Root below the ROM ZIP; disks may be in the set/parent subfolder or directly in that folder.' }
            [pscustomobject]@{ profile_name = 'net'; game_name = 'Net'; tp_loader = 'TeknoParrot'; general_issues = 'Set the Ip option to your computer address.' }
        )
        $catalog = @{ rev = $true; cd = $true; chd = $true; net = $true }
        $by = @{}; foreach ($r in @(Get-TpmCoverageRows -Guide $guide -CatalogCodes $catalog -RecipeIds @() -Tables $tables -ProfileInfo @{})) { $by[$r.ProfileId] = $r.Disposition }
        $by['rev'] | Should -Be 'Handled'
        $by['cd'] | Should -Be 'Handled'
        $by['chd'] | Should -Be 'Checked'
        $by['net'] | Should -Be 'Guided'
    }
}

Describe 'CD Image Folder and CHD below the ZIP' {
    BeforeAll {
        function New-CdProfile {
            param([string]$Path, [string]$Value = '')
            Set-Content -LiteralPath $Path -Value ('<GameProfile><ConfigValues><FieldInformation><FieldName>CD Image Folder</FieldName><FieldValue>{0}</FieldValue><FieldType>Text</FieldType></FieldInformation></ConfigValues></GameProfile>' -f $Value)
        }
    }
    BeforeEach { Mock Write-Log {} }

    It 'finds the folder only when exactly one matching CHD exists' {
        $root = Join-Path $TestDrive 'lib'
        New-Item -ItemType Directory -Path (Join-Path $root 'a\disc'), (Join-Path $root 'b') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'a\disc\one.chd') -Value 'x'
        Find-TpmCdImageFolder -InstallFolder $root -CdImage 'one.chd' | Should -Be (Join-Path $root 'a\disc')
        Find-TpmCdImageFolder -InstallFolder $root -CdImage 'missing.chd' | Should -Be ''
        Set-Content -LiteralPath (Join-Path $root 'b\one.chd') -Value 'x'
        Find-TpmCdImageFolder -InstallFolder $root -CdImage 'one.chd' | Should -Be ''
    }

    It 'gives the folder above the game folder for a "folder/name.chd" image' {
        $root = Join-Path $TestDrive 'lib2'
        New-Item -ItemType Directory -Path (Join-Path $root 'cds\kokoro') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'cds\kokoro\cdp-1.chd') -Value 'x'
        Find-TpmCdImageFolder -InstallFolder $root -CdImage 'kokoro/cdp-1.chd' | Should -Be (Join-Path $root 'cds')
    }

    It 'sets an empty CD Image Folder, reads it back, and never replaces a folder the player chose' {
        $empty = Join-Path $TestDrive 'empty.xml'; New-CdProfile -Path $empty
        $chosen = Join-Path $TestDrive 'chosen.xml'; New-CdProfile -Path $chosen -Value 'D:\mine'
        $folder = Join-Path $TestDrive 'cds'; New-Item -ItemType Directory -Path $folder | Out-Null
        $r = Set-TpmProfileCdImageFolders -Items @(
            [pscustomobject]@{ Path = $empty; Label = 'Empty'; Folder = $folder },
            [pscustomobject]@{ Path = $chosen; Label = 'Chosen'; Folder = $folder })
        $r.Changed.Count | Should -Be 1
        $r.Failed.Count | Should -Be 1
        ([xml](Get-Content -LiteralPath $empty -Raw)).GameProfile.ConfigValues.FieldInformation.FieldValue | Should -Be $folder
        ([xml](Get-Content -LiteralPath $chosen -Raw)).GameProfile.ConfigValues.FieldInformation.FieldValue | Should -Be 'D:\mine'
    }

    It 'writes nothing when the safety backup failed' {
        $p = Join-Path $TestDrive 'nb.xml'; New-CdProfile -Path $p
        $r = Set-TpmProfileCdImageFolders -Items @([pscustomobject]@{ Path = $p; Label = 'G'; Folder = $TestDrive }) -BackupError 'no backup'
        $r.Changed.Count | Should -Be 0
        ([xml](Get-Content -LiteralPath $p -Raw)).GameProfile.ConfigValues.FieldInformation.FieldValue | Should -Be ''
    }

    It 'finds a second-file CHD in a folder named after the game below the ZIP, and not when two match' {
        $dir = Join-Path $TestDrive 'naomi'
        New-Item -ItemType Directory -Path (Join-Path $dir 'azumanga') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'azumanga.zip') -Value 'x'
        Set-Content -LiteralPath (Join-Path $dir 'azumanga\gdl-0018.chd') -Value 'x'
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml('<GameProfile><ExecutableName>azumanga.zip</ExecutableName><ExecutableName2>gdl-0018.chd</ExecutableName2><HasTwoExecutables>true</HasTwoExecutables><GamePath2 /></GameProfile>')
        Set-SecondaryExecutablePath $doc (Join-Path $dir 'azumanga.zip') -ProfileCode 'teknonaomi_azumanga' | Should -BeTrue
        $doc.GameProfile.GamePath2 | Should -Be (Join-Path $dir 'azumanga\gdl-0018.chd')
        New-Item -ItemType Directory -Path (Join-Path $dir 'teknonaomi_azumanga') | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'teknonaomi_azumanga\gdl-0018.chd') -Value 'x'
        $doc2 = New-Object System.Xml.XmlDocument
        $doc2.LoadXml('<GameProfile><ExecutableName>azumanga.zip</ExecutableName><ExecutableName2>gdl-0018.chd</ExecutableName2><HasTwoExecutables>true</HasTwoExecutables><GamePath2 /></GameProfile>')
        Set-SecondaryExecutablePath $doc2 (Join-Path $dir 'azumanga.zip') -ProfileCode 'teknonaomi_azumanga' | Should -BeFalse
    }
}
