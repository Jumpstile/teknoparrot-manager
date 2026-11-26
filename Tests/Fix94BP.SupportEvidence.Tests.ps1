#Requires -Module Pester

# Support package evidence (R94BP): PC facts, Windows events, more logs, full game names, games outside the Games folder, redaction.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Support evidence test bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'tpm-support-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'test.log'
    $script:logWarnShown = $false

    function New-SupportFixture {
        $root = Join-Path $TestDrive ('support-' + [guid]::NewGuid().ToString('N'))
        $scriptRoot = Join-Path $root 'Scripts'
        $tpRoot = Join-Path $root 'TeknoParrot'
        $gamesRoot = Join-Path $root 'Games'
        $profiles = Join-Path $tpRoot 'UserProfiles'
        $output = Join-Path $scriptRoot 'SupportPackages'
        New-Item -ItemType Directory -Path $scriptRoot,$tpRoot,$gamesRoot,$profiles,$output -Force | Out-Null
        return [pscustomobject]@{ Root=$root; Script=$scriptRoot; Tp=$tpRoot; Games=$gamesRoot; Profiles=$profiles; Output=$output }
    }
    function Write-SupportText {
        param([string]$Path,[string]$Text)
        $parent = [System.IO.Path]::GetDirectoryName($Path)
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($Path,$Text,(New-Object System.Text.UTF8Encoding($false)))
    }
    function Add-SupportGame {
        param($Fixture,[string]$Code='TMNT')
        $gameRoot = Join-Path $Fixture.Games $Code
        New-Item -ItemType Directory -Path $gameRoot -Force | Out-Null
        $exe = Join-Path $gameRoot ($Code + '.exe')
        [System.IO.File]::WriteAllBytes($exe,[byte[]](1,2,3,4))
        Write-SupportText -Path (Join-Path $Fixture.Profiles ($Code + '.xml')) -Text ('<GameProfile><GamePath>' + $exe + '</GamePath></GameProfile>')
        return $gameRoot
    }
    function Get-SupportZipEntries {
        param([string]$Path)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { return @($zip.Entries | ForEach-Object { $_.FullName -replace '\\','/' }) } finally { $zip.Dispose() }
    }
    function Get-SupportZipText {
        param([string]$Path,[string]$EntryName)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $canonicalEntryName = $EntryName -replace '\\','/'
            $entry = @($zip.Entries | Where-Object { (($_.FullName -replace '\\','/') -eq $canonicalEntryName) }) | Select-Object -First 1
            if (-not $entry) { return $null }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $zip.Dispose() }
    }
    function Get-SupportAllZipText {
        param([string]$Path)
        $all = New-Object System.Text.StringBuilder
        foreach ($name in (Get-SupportZipEntries $Path)) { if ($name -notmatch '/$') { [void]$all.AppendLine($name); [void]$all.AppendLine([string](Get-SupportZipText $Path $name)) } }
        return $all.ToString()
    }
    function New-FakeEvent {
        param([string]$Provider = 'Application Error', [string]$Message, [double]$HoursAgo = 1, [int]$Id = 1000)
        return [pscustomobject]@{ TimeCreated = (Get-Date).AddHours(-$HoursAgo); ProviderName = $Provider; Id = $Id; Message = $Message }
    }
}

Describe 'Support package system facts (R94BP item 1)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Get-WinEvent { throw [System.Exception]::new('no events here') }
    }
    It 'writes system-facts.json and a plain manifest section from real probes and fake machine answers' {
        Mock Get-CimInstance {
            if ($ClassName -eq 'Win32_VideoController') { return @([pscustomobject]@{ Name = 'Fixture GPU 9000'; DriverVersion = '31.0.1.2' }) }
            if ($ClassName -eq 'Win32_Service') { return @([pscustomobject]@{ Name = 'postgresql-x64-16'; State = 'Running'; PathName = '"C:\Program Files\PostgreSQL\16\bin\pg_ctl.exe" runservice -D "C:\Users\Bob\data" -o secret' }) }
            if ($ClassName -eq 'Win32_PnPEntity') { return @([pscustomobject]@{ Name = 'Fixture Arcade Joystick' }, [pscustomobject]@{ Name = 'Fixture Keyboard Hub' }) }
            return @()
        }
        Mock Get-MpComputerStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $true; AntivirusEnabled = $true } }
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Script 'State\Controls\cabinet.json') '{"Version":1,"Devices":{"XboxStylePad":true},"Players":2,"ButtonsPerPlayer":6,"Keys":{}}'
        Write-SupportText (Join-Path $f.Tp 'Downloaded.exe') 'MZ not a real program'
        Set-Content -LiteralPath (Join-Path $f.Tp 'Downloaded.exe') -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3"
        Write-SupportText (Join-Path $f.Tp 'Clean.dll') 'plain'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $facts = (Get-SupportZipText $r.PackagePath 'metadata/system-facts.json') | ConvertFrom-Json
        $facts.Windows.Is64BitOperatingSystem | Should -Be ([Environment]::Is64BitOperatingSystem)
        $facts.VideoCards.Items[0].Model | Should -Be 'Fixture GPU 9000'
        $facts.VideoCards.Items[0].DriverVersion | Should -Be '31.0.1.2'
        $facts.PostgreSql.Found | Should -BeTrue
        $facts.PostgreSql.Services[0].ServiceName | Should -Be 'postgresql-x64-16'
        $facts.PostgreSql.Services[0].Status | Should -Be 'Running'
        $facts.GameControllers.Names | Should -Contain 'Fixture Arcade Joystick'
        $facts.GameControllers.Names | Should -Not -Contain 'Fixture Keyboard Hub'
        $facts.ControlsChoice.Players | Should -Be 2
        $facts.ControlsChoice.ControllerKinds | Should -Contain 'XboxStylePad'
        $facts.Drives.Games.IsNetworkOrMapped | Should -BeFalse
        $facts.Drives.TeknoParrot.FreeGB | Should -BeGreaterThan 0
        $facts.Drives.Scratch.FreeGB | Should -BeGreaterThan 0
        $facts.WindowsDefender.RealTimeProtectionEnabled | Should -BeTrue
        $facts.DownloadedFileBlocks.BlockedFiles | Should -Be 1
        $facts.DownloadedFileBlocks.AnyBlocked | Should -BeTrue
        $json = Get-SupportZipText $r.PackagePath 'metadata/system-facts.json'
        $json | Should -Not -Match 'Bob'
        $json | Should -Not -Match 'pg_ctl'
        $manifest = Get-SupportZipText $r.PackagePath 'MANIFEST.txt'
        $manifest | Should -Match 'About this PC'
        $manifest | Should -Match 'Video card: Fixture GPU 9000 \(driver 31\.0\.1\.2\)'
        $manifest | Should -Match 'Windows Defender real-time protection on: yes'
    }
    It 'says "not available" with a short reason for a probe that throws, and the package still succeeds' {
        Mock Get-CimInstance { throw 'WMI is broken token=PROBESECRET99' }
        Mock Get-MpComputerStatus { throw 'Defender is not installed' }
        $f = New-SupportFixture
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $facts = (Get-SupportZipText $r.PackagePath 'metadata/system-facts.json') | ConvertFrom-Json
        $facts.VideoCards.Status | Should -Be 'not available'
        $facts.VideoCards.Reason | Should -Match 'WMI is broken'
        $facts.PostgreSql.Status | Should -Be 'not available'
        $facts.WindowsDefender.Status | Should -Be 'not available'
        $facts.Windows.Name | Should -Not -BeNullOrEmpty
        $facts.Drives.Games.Drive | Should -Match '^[A-Z]:$'
        (Get-SupportAllZipText $r.PackagePath) | Should -Not -Match 'PROBESECRET99'
        (Get-SupportZipText $r.PackagePath 'MANIFEST.txt') | Should -Match 'Video card: not available \(WMI is broken'
    }
    It 'reports a network share for the Games folder without reading its free space' {
        Mock Get-CimInstance { return @() }
        Mock Get-MpComputerStatus { [pscustomobject]@{ RealTimeProtectionEnabled = $false; AntivirusEnabled = $false } }
        $f = New-SupportFixture
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -ApprovedGamesRoot '\\fixture-server\games' -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $facts = (Get-SupportZipText $r.PackagePath 'metadata/system-facts.json') | ConvertFrom-Json
        $facts.Drives.Games.IsNetworkOrMapped | Should -BeTrue
        $facts.Drives.Games.DriveType | Should -Be 'network share'
        (Get-SupportAllZipText $r.PackagePath) | Should -Not -Match 'fixture-server'
    }
}

Describe 'Support package Windows event summary (R94BP item 2)' {
    BeforeEach { Mock Write-Log {} }
    It 'keeps only the four providers, only events that name TeknoParrot, TPM or a game program, newest 50, cut to 600 characters, redacted' {
        $events = New-Object System.Collections.Generic.List[object]
        $events.Add((New-FakeEvent -Provider 'Application Error' -Message 'Faulting application TeknoParrotUi.exe, password=EVENTSECRET1 at C:\Users\Bob\AppData\x' -HoursAgo 2))
        $events.Add((New-FakeEvent -Provider '.NET Runtime' -Message 'Unhandled exception in TPM script' -HoursAgo 3))
        $events.Add((New-FakeEvent -Provider 'Windows Error Reporting' -Message 'Fault bucket for GameRunner.exe' -HoursAgo 4))
        $events.Add((New-FakeEvent -Provider 'Application Hang' -Message 'The program GameRunner.EXE stopped interacting' -HoursAgo 5))
        $events.Add((New-FakeEvent -Provider 'Other Provider' -Message 'TeknoParrot is mentioned but this is not an allowed provider' -HoursAgo 1))
        $events.Add((New-FakeEvent -Provider 'Application Error' -Message 'Faulting application notepad.exe' -HoursAgo 1))
        $events.Add((New-FakeEvent -Provider 'Application Error' -Message 'TeknoParrot crash from long ago' -HoursAgo (24 * 8)))
        $events.Add((New-FakeEvent -Provider 'Application Error' -Message ('TeknoParrot ' + ('x' * 2000) + 'ENDMARK') -HoursAgo 6))
        $text = (Get-TpmSupportWindowsEventText -Events $events.ToArray() -GameExecutableNames @('GameRunner.exe')).Text
        $text | Should -Match 'Faulting application TeknoParrotUi\.exe'
        $text | Should -Match 'Unhandled exception in TPM script'
        $text | Should -Match 'Fault bucket for GameRunner\.exe'
        $text | Should -Match 'GameRunner\.EXE stopped'
        $text | Should -Not -Match 'not an allowed provider'
        $text | Should -Not -Match 'notepad'
        $text | Should -Not -Match 'long ago'
        $text | Should -Not -Match 'EVENTSECRET1'
        $text | Should -Not -Match 'Bob'
        $text | Should -Not -Match 'ENDMARK'
        $cut = @($text -split "`r?`n" | Where-Object { $_ -match 'TeknoParrot x{20}' })
        $cut.Count | Should -Be 1
        $cut[0].Trim().Length | Should -BeLessOrEqual 600
    }
    It 'writes at most 50 events, newest first' {
        $many = @(1..60 | ForEach-Object { New-FakeEvent -Message ('TeknoParrot problem number {0:D2}' -f $_) -HoursAgo $_ })
        $result = Get-TpmSupportWindowsEventText -Events $many
        $result.Count | Should -Be 50
        $result.Text | Should -Match 'problem number 01'
        $result.Text | Should -Match 'problem number 50'
        $result.Text | Should -Not -Match 'problem number 51'
        $result.Text.IndexOf('problem number 01') | Should -BeLessThan $result.Text.IndexOf('problem number 02')
    }
    It 'puts windows-events.txt in the package for the registered game programs and never adds dumps or report folders' {
        Mock Get-CimInstance { return @() }
        Mock Get-MpComputerStatus { throw 'off' }
        Mock Get-WinEvent { return @((New-FakeEvent -Provider 'Application Error' -Message 'Faulting application TMNT.exe cookie: sid=COOKIESECRET7')) }
        $f = New-SupportFixture
        [void](Add-SupportGame $f)
        Write-SupportText (Join-Path $f.Script 'WER\Report.wer') 'report'
        Write-SupportText (Join-Path $f.Tp 'crash.dmp') 'dump'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $events = Get-SupportZipText $r.PackagePath 'diagnostics/windows-events.txt'
        $events | Should -Match 'Faulting application TMNT\.exe'
        $events | Should -Not -Match 'COOKIESECRET7'
        @(Get-SupportZipEntries $r.PackagePath | Where-Object { $_ -match '\.dmp$|\.wer$|WER' }) | Should -BeNullOrEmpty
        (Get-SupportZipText $r.PackagePath 'MANIFEST.txt') | Should -Match 'Windows:Application events'
    }
    It 'says the event list is not available when Windows refuses it, and the package still succeeds' {
        Mock Get-CimInstance { return @() }
        Mock Get-MpComputerStatus { throw 'off' }
        Mock Get-WinEvent { throw 'The Event Log service is stopped. token=EVENTSECRET3' }
        $f = New-SupportFixture
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $events = Get-SupportZipText $r.PackagePath 'diagnostics/windows-events.txt'
        $events | Should -Match 'Not available'
        (Get-SupportAllZipText $r.PackagePath) | Should -Not -Match 'EVENTSECRET3'
    }
}

Describe 'Support package log discovery (R94BP item 3)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Get-CimInstance { return @() }
        Mock Get-MpComputerStatus { throw 'off' }
        Mock Get-WinEvent { throw 'none' }
    }
    It 'finds TeknoParrot logs in the root, Logs and TeknoParrotUI\Logs, text only, and never a dump' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Tp 'Logs\Launcher.log') 'launcher line password=LOGSECRET1'
        Write-SupportText (Join-Path $f.Tp 'Logs\notes.txt') 'plain notes'
        Write-SupportText (Join-Path $f.Tp 'TeknoParrotUI\Logs\ui-session.log') 'ui session'
        Write-SupportText (Join-Path $f.Tp 'ReShade.log') 'reshade at root'
        Write-SupportText (Join-Path $f.Tp 'License.txt') 'license text that is not a log'
        Write-SupportText (Join-Path $f.Tp 'Logs\crash.dmp') 'dump bytes'
        Write-SupportText (Join-Path $f.Tp 'TeknoParrotUI\Logs\ui.dmp') 'dump bytes'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $text = Get-SupportAllZipText $r.PackagePath
        $text | Should -Match 'launcher line'
        $text | Should -Match 'plain notes'
        $text | Should -Match 'ui session'
        $text | Should -Match 'reshade at root'
        $text | Should -Not -Match 'license text that is not a log'
        $text | Should -Not -Match 'LOGSECRET1'
        @(Get-SupportZipEntries $r.PackagePath | Where-Object { $_ -match '\.dmp$' }) | Should -BeNullOrEmpty
    }
    It 'finds ReShade, dgVoodoo, BepInEx, Player, output_log, error and crash logs inside a game folder to depth 3, never dumps or configs' {
        $f = New-SupportFixture
        $game = Add-SupportGame $f
        Write-SupportText (Join-Path $game 'ReShade.log') 'reshade game log'
        Write-SupportText (Join-Path $game 'dgVoodoo.log') 'dgvoodoo game log'
        Write-SupportText (Join-Path $game 'dgVoodooDebug.txt') 'dgvoodoo debug log'
        Write-SupportText (Join-Path $game 'dgVoodoo.conf') 'config must not be copied'
        Write-SupportText (Join-Path $game 'BepInEx\LogOutput.log') 'bepinex log'
        Write-SupportText (Join-Path $game 'BepInEx\preloader_20260101.log') 'preloader log'
        Write-SupportText (Join-Path $game 'Data\Logs\Player.log') 'unity player log'
        Write-SupportText (Join-Path $game 'a\b\c\error.log') 'depth three error log'
        Write-SupportText (Join-Path $game 'a\b\c\d\crash.log') 'too deep to be found'
        Write-SupportText (Join-Path $game 'Data\Logs\Game.dmp') 'dump bytes'
        Write-SupportText (Join-Path $game 'crash.dmp') 'dump bytes'
        Write-SupportText (Join-Path $game 'random.log') 'unknown name is not collected'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $text = Get-SupportAllZipText $r.PackagePath
        foreach ($expected in @('reshade game log', 'dgvoodoo game log', 'dgvoodoo debug log', 'bepinex log', 'preloader log', 'unity player log', 'depth three error log')) { $text | Should -Match $expected }
        $text | Should -Not -Match 'config must not be copied'
        $text | Should -Not -Match 'too deep to be found'
        $text | Should -Not -Match 'unknown name is not collected'
        @(Get-SupportZipEntries $r.PackagePath | Where-Object { $_ -match '\.dmp$|\.conf$' }) | Should -BeNullOrEmpty
    }
    It 'only ever offers .log and .txt files, even for a name pattern that matches everything' {
        $root = Join-Path $TestDrive ('cand-' + [guid]::NewGuid().ToString('N'))
        Write-SupportText (Join-Path $root 'one.log') 'a'
        Write-SupportText (Join-Path $root 'two.txt') 'b'
        Write-SupportText (Join-Path $root 'three.dmp') 'c'
        Write-SupportText (Join-Path $root 'four.dll') 'd'
        $found = @(Get-TpmSupportLogCandidates -Root $root -NamePattern '.*')
        ($found | Sort-Object) -join ',' | Should -Be 'one.log,two.txt'
    }
}

Describe 'Support package full game names (R94BP item 4)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Get-CimInstance { return @() }
        Mock Get-MpComputerStatus { throw 'off' }
        Mock Get-WinEvent { throw 'none' }
        Mock Get-TpmGameTitle { if ($Code -eq 'TC4') { 'Time Crisis 4' } elseif ($Code -eq 'GT') { 'Golden Tee: Live 2026' } else { $Code } }
    }
    It 'uses the full game name with the id in brackets in the manifest and in snapshot, inventory and log file names' {
        $f = New-SupportFixture
        $game = Add-SupportGame $f 'TC4'
        New-Item -ItemType Directory -Path (Join-Path $game 'BepInEx\plugins') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $game 'BepInEx\plugins\Plug.dll'), [byte[]](1, 2, 3))
        Write-SupportText (Join-Path $game 'BepInEx\LogOutput.log') 'tc4 bepinex log'
        [void](Add-SupportGame $f 'NOTITLE')
        [void](Add-SupportGame $f 'GT')
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $entries = Get-SupportZipEntries $r.PackagePath
        $entries | Should -Contain 'metadata/profile-Time Crisis 4 (TC4).txt'
        $entries | Should -Contain 'metadata/inventory-Time Crisis 4 (TC4).tsv'
        $entries | Should -Contain 'diagnostics/game-Time Crisis 4 (TC4)-BepInEx_LogOutput.log'
        $entries | Should -Contain 'metadata/profile-Golden Tee_ Live 2026 (GT).txt'
        $entries | Should -Contain 'metadata/profile-NOTITLE.txt'
        (Get-SupportZipText $r.PackagePath 'metadata/inventory-Time Crisis 4 (TC4).tsv') | Should -Match '(?m)^# Game: Time Crisis 4 \(TC4\)'
        (Get-SupportZipText $r.PackagePath 'metadata/profile-Time Crisis 4 (TC4).txt') | Should -Match 'Game: Time Crisis 4 \(TC4\)'
        $manifest = Get-SupportZipText $r.PackagePath 'MANIFEST.txt'
        $manifest | Should -Match 'Game: Time Crisis 4 \(TC4\):plugin inventory'
        $manifest | Should -Match 'Game: Time Crisis 4 \(TC4\):BepInEx\\LogOutput\.log'
        $manifest | Should -Match 'Game:NOTITLE:redacted profile snapshot'
        $inventory = (Get-SupportZipText $r.PackagePath 'metadata/profile-inventory.json') | ConvertFrom-Json
        $row = @($inventory.Profiles | Where-Object { $_.Code -eq 'TC4' })[0]
        $row.GameName | Should -Be 'Time Crisis 4 (TC4)'
        (Get-SupportZipText $r.PackagePath 'README.txt') | Should -Match 'full game name'
    }
}

Describe 'Support package games outside the Games folder (R94BP item 5)' {
    BeforeEach {
        Mock Write-Log {}
        Mock Get-CimInstance { return @() }
        Mock Get-MpComputerStatus { throw 'off' }
        Mock Get-WinEvent { throw 'none' }
        Mock Get-TpmGameTitle { if ($Code -eq 'OUT1') { 'Outside Racer' } else { $Code } }
    }
    It 'counts them in plain words, adds a redacted registration snapshot and copies nothing from their folders' {
        $f = New-SupportFixture
        [void](Add-SupportGame $f 'INSIDE')
        $outside = Join-Path $f.Root 'Elsewhere\OUT1'
        Write-SupportText (Join-Path $outside 'BepInEx\LogOutput.log') 'OUTSIDE FOLDER SECRET LOG'
        Write-SupportText (Join-Path $f.Profiles 'OUT1.xml') ('<GameProfile><GamePath>' + (Join-Path $outside 'game.exe') + '</GamePath><JoystickButtons><JoystickButtons><ButtonName>Fire</ButtonName><InputMapping>Button1</InputMapping></JoystickButtons><JoystickButtons><ButtonName>Start</ButtonName><InputMapping></InputMapping></JoystickButtons></JoystickButtons></GameProfile>')
        Write-SupportText (Join-Path $f.Profiles 'OUT2.xml') '<GameProfile><GamePath>C:\Users\Bob\Games\Gone\game.exe</GamePath></GameProfile>'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $manifest = Get-SupportZipText $r.PackagePath 'MANIFEST.txt'
        $manifest | Should -Match '3 registered games; 2 have game folders outside the Games folder, so their log files were not collected, but their registration details are included\.'
        $manifest | Should -Match 'Games considered: 1 of 3 registered games'
        $manifest | Should -Not -Match 'Intentional exclusions|Games considered: 0 /'
        $snapshot = Get-SupportZipText $r.PackagePath 'metadata/games-outside-games-folder.txt'
        $snapshot | Should -Match 'Game: Outside Racer \(OUT1\)'
        $snapshot | Should -Match 'Id: OUT1'
        $snapshot | Should -Match 'Id: OUT2'
        $snapshot | Should -Match 'Game folder exists: yes'
        $snapshot | Should -Match 'Game folder exists: no'
        $snapshot | Should -Match 'Drive type: local disk'
        $snapshot | Should -Match '1 of 2 controls have a button set'
        $snapshot | Should -Match '<user-profile>'
        $snapshot | Should -Not -Match 'Bob'
        (Get-SupportAllZipText $r.PackagePath) | Should -Not -Match 'OUTSIDE FOLDER SECRET LOG'
        @($r.Records | Where-Object { $_.Source -eq 'Game: Outside Racer (OUT1)' -and $_.Status -eq 'IntentionallyExcluded' }).Count | Should -Be 1
    }
    It 'is not nearly empty when every game is outside the Games folder' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Profiles 'OUT1.xml') ('<GameProfile><GamePath>' + (Join-Path $f.Root 'Elsewhere\OUT1\game.exe') + '</GamePath></GameProfile>')
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $manifest = Get-SupportZipText $r.PackagePath 'MANIFEST.txt'
        $manifest | Should -Match 'Games considered: 0 of 1 registered games'
        $manifest | Should -Match '1 registered games; 1 have game folders outside the Games folder'
        (Get-SupportZipText $r.PackagePath 'metadata/games-outside-games-folder.txt') | Should -Match 'Outside Racer \(OUT1\)'
    }
    It 'adds no snapshot when no game is outside the Games folder' {
        $f = New-SupportFixture
        [void](Add-SupportGame $f 'INSIDE')
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        (Get-SupportZipEntries $r.PackagePath) | Should -Not -Contain 'metadata/games-outside-games-folder.txt'
        (Get-SupportZipText $r.PackagePath 'MANIFEST.txt') | Should -Match '1 registered games; none have game folders outside the Games folder'
    }
}

Describe 'Support package redaction in every text channel (R94BP item 6)' {
    BeforeEach { Mock Write-Log {} }
    It 'removes the secret from <Name>' -ForEach @(
        @{ Name = 'a cookie header'; Text = 'Cookie: session=SECRETVALUE1; theme=dark'; Secret = 'SECRETVALUE1' }
        @{ Name = 'a set-cookie header'; Text = 'Set-Cookie: sid=SECRETVALUE2; Path=/; HttpOnly'; Secret = 'SECRETVALUE2' }
        @{ Name = 'an API key header'; Text = 'X-Api-Key: SECRETVALUE3'; Secret = 'SECRETVALUE3' }
        @{ Name = 'an api_key setting'; Text = 'api_key=SECRETVALUE4&other=1'; Secret = 'SECRETVALUE4' }
        @{ Name = 'a bearer token'; Text = 'Authorization: Bearer SECRETVALUE5.abc.def'; Secret = 'SECRETVALUE5' }
        @{ Name = 'a bare bearer token'; Text = 'sent bearer SECRETVALUE6abcdef to the server'; Secret = 'SECRETVALUE6' }
        @{ Name = 'a PostgreSQL password setting'; Text = 'Host=localhost;Port=5432;Password=SECRETVALUE7;Database=tpm'; Secret = 'SECRETVALUE7' }
        @{ Name = 'PGPASSWORD'; Text = 'set PGPASSWORD=SECRETVALUE8'; Secret = 'SECRETVALUE8' }
        @{ Name = 'a PostgreSQL URI'; Text = 'postgresql://tpm:SECRETVALUE9@localhost:5432/tpm'; Secret = 'SECRETVALUE9' }
        @{ Name = 'a .pgpass line'; Text = "localhost:5432:*:postgres:SECRETVALUE10`r`n"; Secret = 'SECRETVALUE10' }
        @{ Name = 'a .pgpass line with an address'; Text = "# my file`n127.0.0.1:5433:tpm:tpmuser:SECRETVALUE11`n"; Secret = 'SECRETVALUE11' }
        @{ Name = 'a session id'; Text = 'JSESSIONID=SECRETVALUE12; Path=/'; Secret = 'SECRETVALUE12' }
    ) {
        $redacted = (Redact-TpmSupportText -Text $Text).Text
        $redacted | Should -Not -Match $Secret
    }
    It 'leaves ordinary lines with colons alone' {
        (Redact-TpmSupportText -Text 'Started at 12:30:45 on port 5432: all good').Text | Should -Be 'Started at 12:30:45 on port 5432: all good'
    }
    It 'keeps every secret out of the log, game log, event, error, path and probe channels of one package' {
        Mock Get-CimInstance { throw 'WMI failed cookie: sid=SECRETCHAN1' }
        Mock Get-MpComputerStatus { throw 'Defender failed api_key=SECRETCHAN2' }
        Mock Get-WinEvent { return @((New-FakeEvent -Message 'Faulting application TMNT.exe pgpass localhost:5432:*:postgres:SECRETCHAN3')) }
        $f = New-SupportFixture
        $game = Add-SupportGame $f
        Write-SupportText (Join-Path $f.Script 'TeknoParrot-Manager.log') "TPM log Cookie: a=SECRETCHAN4`r`nlocalhost:5432:tpm:tpmuser:SECRETCHAN5`r`n"
        Write-SupportText (Join-Path $f.Tp 'Logs\ui.log') 'ui log Authorization: Bearer SECRETCHAN6abcdef'
        Write-SupportText (Join-Path $game 'Player.log') 'game log postgresql://u:SECRETCHAN7@localhost/db'
        Write-SupportText (Join-Path $game 'BepInEx\LogOutput.log') 'path C:\Users\SECRETCHAN8\AppData\Local\x password=SECRETCHAN9'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output -AffectedGameSummary 'api_key=SECRETCHAN10'
        $r.Succeeded | Should -BeTrue
        $all = Get-SupportAllZipText $r.PackagePath
        foreach ($n in 1..10) { $all | Should -Not -Match ('SECRETCHAN' + $n + '(?!\d)') }
        ($r.Errors -join ' ') | Should -Not -Match 'SECRETCHAN'
    }
}
