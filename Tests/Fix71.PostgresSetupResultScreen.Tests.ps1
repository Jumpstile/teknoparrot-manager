#Requires -Module Pester

# FIX71: review findings on the PostgreSQL setup result screen (menu 13, FIX63).
#  1. No game database is left for TeknoParrot to create (FIXDB27): every game is made ready
#     by TeknoParrot Manager and checked with the game's own settings; the screen never says
#     "click Yes" or "start the game once".
#  2. The default screen is spaced out (blank lines between the parts), never more
#     than five text lines in a row, and games with the same outcome share one line.
#  3. The details view is one short block per game (Database / What happened /
#     What it means), a common note once, and the three counter lines at the end.
#  4. Everything the shortened screen no longer prints is written to the log.
#  5. The "kept their own password" line uses the right singular or plural.
#
# The production script is parsed and only its function definitions are dot-sourced;
# no top-level product code runs in this process. Setup runs against one in-memory
# fake of the PostgreSQL 8.3 client tools, so no PostgreSQL server, service, registry
# or user configuration is touched. Every file lives under TestDrive and every profile,
# game folder and backup is a synthetic fixture. Each It names the product mutation
# that makes it fail.

BeforeAll {
    $script:Fix71PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix71PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX71 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix71FunctionFile = Join-Path $TestDrive 'tpm-fix71-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix71FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix71FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force

    # Hardware and progress-line access is external to these tests.
    function Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = $null; Name = 'isolated fixture' } }
    function Suspend-TpmProgressLine {}
    function Resume-TpmProgressLine {}

    function New-F71Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f71-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
        $bin = Join-Path $root 'bin'
        $evidence = Join-Path $root 'evidence'
        $profiles = Join-Path $root 'UserProfiles'
        New-Item -ItemType Directory -Path $bin, $evidence, $profiles, (Join-Path $root 'GameProfiles') -Force | Out-Null
        foreach ($tool in @(Get-Postgres83RestoreToolNames)) { New-Item -ItemType File -Path (Join-Path $bin $tool) -Force | Out-Null }
        $state = [pscustomobject]@{
            Exists = New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([System.StringComparer]::Ordinal)
            Calls = New-Object System.Collections.Generic.List[object]
            Events = New-Object System.Collections.Generic.List[string]
            Log = New-Object System.Collections.Generic.List[string]
            Screen = New-Object System.Collections.Generic.List[string]
        }
        return [pscustomobject]@{ Root = $root; Bin = $bin; Evidence = $evidence; Profiles = $profiles; State = $state }
    }

    # Profile with a Postgres category. -AutoCreate '' omits "Automatically create
    # Database", which is "this TeknoParrot build does not say".
    function New-F71Profile {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$ProfileName,
            [AllowEmptyString()][Parameter(Mandatory)][string]$GameName,
            [Parameter(Mandatory)][string]$DbName,
            [string]$Pass = '',
            [string]$AutoCreate = '1',
            [switch]$Backup
        )
        $gameDir = Join-Path $Fixture.Root ('Game-' + $ProfileName)
        New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
        $exe = Join-Path $gameDir 'game.exe'
        New-Item -ItemType File -Path $exe -Force | Out-Null
        if ($Backup) {
            $backupDir = Join-Path $gameDir 'pg_backup'
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $backupDir '0001.backup'), 'synthetic bundled backup', (New-Object System.Text.UTF8Encoding $false))
        }
        $fields = New-Object System.Collections.Generic.List[object]
        [void]$fields.Add(@('Path', ''))
        [void]$fields.Add(@('Address', ''))
        [void]$fields.Add(@('Port', ''))
        [void]$fields.Add(@('DbName', $DbName))
        [void]$fields.Add(@('User', ''))
        [void]$fields.Add(@('Pass', $Pass))
        if ($AutoCreate -ne '') { [void]$fields.Add(@('Automatically create Database', $AutoCreate)) }
        # The game path goes into XML text: escape it so a valid folder name with an ampersand (A&B) still gives well-formed XML.
        $xml = '<GameProfile><GameName>' + $GameName + '</GameName><GamePath>' + [System.Security.SecurityElement]::Escape([string]$exe) + '</GamePath><ConfigValues>'
        foreach ($field in $fields) {
            $xml += '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $field[0] + '</FieldName><FieldValue>' + $field[1] + '</FieldValue></FieldInformation>'
        }
        $xml += '</ConfigValues></GameProfile>'
        $file = Join-Path $Fixture.Profiles ($ProfileName + '.xml')
        [System.IO.File]::WriteAllText($file, $xml, (New-Object System.Text.UTF8Encoding $false))
        return $file
    }

    function New-F71CommandResult {
        param([string]$ToolName, [string[]]$Arguments, [int]$ExitCode, [string]$Output = '')
        return [pscustomobject]@{
            Tool = $ToolName
            Executable = Join-Path $script:PostgresBinDir $ToolName
            Arguments = @($Arguments)
            ExitCode = $ExitCode
            Succeeded = ($ExitCode -eq 0)
            Output = $Output
        }
    }

    # In-memory PostgreSQL 8.3 client: records every call and changes the fake server
    # state the way the real createdb/dropdb/pg_restore would.
    function Invoke-F71FakeCommand {
        param([string]$ToolName, [string[]]$Arguments)
        $state = $script:F71State
        $database = ''
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if ($Arguments[$i] -ceq '-d') { $database = [string]$Arguments[$i + 1] }
        }
        if ($ToolName -in @('createdb.exe', 'dropdb.exe')) { $database = [string]$Arguments[$Arguments.Count - 1] }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -notcontains '--list') { $database = [string]$Arguments[$Arguments.Count - 2] }
        [void]$state.Calls.Add([pscustomobject]@{ Tool = $ToolName; Database = $database; Arguments = @($Arguments) })
        if ($Arguments -contains '--version') {
            return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($ToolName + ' (PostgreSQL) 8.3.23'))
        }
        if ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc') {
            $query = [string]$Arguments[$Arguments.Count - 1]
            if ($query -match 'count\(\*\)') { return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '24') }
            $wanted = ''
            if ($query -match "lower\('([^']+)'\)\s*$") { $wanted = $Matches[1] }
            $names = @($state.Exists.Keys | Where-Object { $state.Exists[$_] -and [string]::Equals($_, $wanted, [System.StringComparison]::OrdinalIgnoreCase) })
            return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($names -join "`n"))
        }
        if ($ToolName -eq 'psql.exe') { return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -contains '--list') { return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe') {
            [void]$state.Events.Add('pg_restore:' + $database)
            return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'createdb.exe') {
            [void]$state.Events.Add('createdb:' + $database)
            $state.Exists[$database] = $true
            return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'dropdb.exe') {
            [void]$state.Events.Add('dropdb:' + $database)
            $state.Exists[$database] = $false
            return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        return (New-F71CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 3 -Output 'unexpected fake tool')
    }

    function Install-F71SetupMocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F71State = $Fixture.State
        $script:F71Width = 120
        $script:F71Recovery = [pscustomobject]@{ Path = $Fixture.Evidence; ConfigBackups = @(); Verified = $true; ProfileBackups = @() }
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log { [void]$script:F71State.Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F71State.Screen.Add(([string]($Object -join ' '))) }
        Mock Get-ConsoleContentWidth { return [int]$script:F71Width }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock New-PostgresRecoveryBackup { [void]$script:F71State.Events.Add('backup'); $script:F71Recovery }
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            # FIX129: the fake runs the caller's -Interpret block on its text, like the real runner does.
            Add-FakePostgresInterpretation -Command (Invoke-F71FakeCommand -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            $exists = $false
            if ($script:F71State.Exists.ContainsKey($DbName)) { $exists = [bool]$script:F71State.Exists[$DbName] }
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
    }

    # Mocks for the tests that build the result object directly (no fake PostgreSQL).
    function Install-F71ScreenMocks {
        $fixture = [pscustomobject]@{ State = [pscustomobject]@{ Log = New-Object System.Collections.Generic.List[string]; Screen = New-Object System.Collections.Generic.List[string] } }
        $script:F71State = $fixture.State
        $script:F71Width = 120
        Mock Write-Log { [void]$script:F71State.Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F71State.Screen.Add(([string]($Object -join ' '))) }
        Mock Get-ConsoleContentWidth { return [int]$script:F71Width }
        return $fixture
    }

    # The six-game library from the owner's screenshot: two games that already have a database
    # and four that Manager creates from the game's own backup.
    function New-F71SixGames {
        $fx = New-F71Fixture -Name 'six'
        $fx.State.Exists['GameDBPPL12'] = $true
        $fx.State.Exists['GameDBBags'] = $true
        [void](New-F71Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -Backup)
        [void](New-F71Profile -Fixture $fx -ProfileName 'PowerPuttLive2012' -GameName 'Power Putt Live 2012' -DbName 'GameDBPPL12' -AutoCreate '')
        [void](New-F71Profile -Fixture $fx -ProfileName 'PowerPuttLive2013' -GameName 'Power Putt Live 2013' -DbName 'GameDBPPL13' -AutoCreate '' -Backup)
        [void](New-F71Profile -Fixture $fx -ProfileName 'SilverStrikeBowlingLive' -GameName 'Silver Strike Bowling Live' -DbName 'GameDBSSB' -AutoCreate '0' -Backup)
        [void](New-F71Profile -Fixture $fx -ProfileName 'TargetTossProBags' -GameName 'Target Toss Pro Bags' -DbName 'GameDBBags' -AutoCreate '0')
        [void](New-F71Profile -Fixture $fx -ProfileName 'TargetTossProLawndarts' -GameName 'Target Toss Pro Lawndarts' -DbName 'GameDBLawn' -AutoCreate '0' -Backup)
        return $fx
    }

    function Invoke-F71Setup {
        param([Parameter(Mandatory)]$Fixture)
        $result = Invoke-PostgresGameSetup -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password'
        $Fixture.State.Screen.Clear()
        $Fixture.State.Log.Clear()
        return $result
    }

    function New-F71Game {
        param([string]$Key, [string]$Name, [string]$DbName = 'GameDBX', [string]$Outcome, [bool]$AutoCreateUnknown = $false)
        return [pscustomobject]@{ Key = $Key; Name = $Name; DbName = $DbName; Outcome = $Outcome; AutoCreateUnknown = $AutoCreateUnknown }
    }

    # A result object with the properties the screen reads, built directly.
    function New-F71Result {
        param([object[]]$Games = @(), [int]$Kept = 0, [int]$Errors = 0, [string[]]$Warnings = @(), [string[]]$Checks = @(), [object[]]$Actions = @())
        return [pscustomobject]@{
            Summary = 'Fixture summary sentence.'
            Configured = 2
            DbCreated = 1
            AlreadyConfigured = 1
            Errors = $Errors
            PassKeptProfiles = @(for ($i = 1; $i -le $Kept; $i++) { 'KeptProfile{0}' -f $i })
            GameOutcomes = @($Games)
            Warnings = @($Warnings)
            FinalVerification = [pscustomobject]@{ Checks = @($Checks) }
            RecoveryActions = @($Actions)
        }
    }

    function Get-F71Screen {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)]$Result, [int]$Width = 120, [switch]$Details, [switch]$OfferDetails)
        $script:F71Width = $Width
        $Fixture.State.Screen.Clear()
        if ($Details) { Write-TpmPostgresSetupDetails -Result $Result }
        else { Write-TpmPostgresSetupResult -Result $Result -OfferDetails:$OfferDetails }
        return , ([string[]]$Fixture.State.Screen.ToArray())
    }

    function Join-F71Screen {
        param([string[]]$Lines)
        return ((@($Lines) -join ' ') -replace '\s+', ' ')
    }

    # Longest stretch of lines in a row that are not blank.
    function Get-F71LongestRun {
        param([string[]]$Lines)
        $longest = 0
        $run = 0
        foreach ($line in @($Lines)) {
            if ([string]::IsNullOrWhiteSpace($line)) { $run = 0 } else { $run++; if ($run -gt $longest) { $longest = $run } }
        }
        return $longest
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix71PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX71 setup records the database name for each game' {
    # Mutation: leave DbName (or AutoCreateUnknown) out of the GameOutcomes record in $finish
    # -> the details view has no Database line and cannot say which build is unsure.
    It 'puts the database name and the "build does not say" flag into every game record' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx

        $result = Invoke-F71Setup -Fixture $fx

        $byKey = @{}
        foreach ($game in $result.GameOutcomes) { $byKey[[string]$game.Key] = $game }
        $byKey.Keys.Count | Should -Be 6
        $byKey['GoldenTeeLive2019'].DbName | Should -BeExactly 'GameDB19'
        $byKey['TargetTossProLawndarts'].DbName | Should -BeExactly 'GameDBLawn'
        $byKey['PowerPuttLive2012'].AutoCreateUnknown | Should -BeTrue
        $byKey['PowerPuttLive2013'].AutoCreateUnknown | Should -BeTrue
        $byKey['GoldenTeeLive2019'].AutoCreateUnknown | Should -BeFalse
        $byKey['SilverStrikeBowlingLive'].AutoCreateUnknown | Should -BeFalse
    }
}

Describe 'FIX71 no game database is left for TeknoParrot to create' {
    # Mutation: bring back the "TeknoParrot will ask ... Click Yes" or "start each game once" sentence -> the user is
    # told to do something TeknoParrot Manager already did and checked.
    It 'shows every game as ready and never tells the user to click Yes or to start the game once' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 120 -OfferDetails
        $flat = Join-F71Screen -Lines $lines

        $flat | Should -Match ([regex]::Escape('Ready: Golden Tee Live 2019, Power Putt Live 2013, Silver Strike Bowling Live and Target Toss Pro Lawndarts'))
        $flat | Should -Not -Match '(?i)click yes|TeknoParrot will ask|start (each|the) game once|start it once|not verified|unverified'
        $flat | Should -Not -Match 'GoldenTeeLive2019|GameDB19'
    }
}

Describe 'FIX71 the default screen is spaced out and short' {
    # Mutation: leave out a blank line (after the count line, before Next, or before [D])
    # -> one of the index checks below finds text where a blank line must be.
    It 'puts a blank line after the count line, before Next and before [D], in 14 lines or fewer, at width 120' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 120 -OfferDetails

        $lines.Count | Should -BeLessOrEqual 14
        $lines[0] | Should -BeExactly ''
        $count = [array]::IndexOf($lines, ('  Games set up: {0}. Databases created: {1}. Already set up: {2}.' -f $result.Configured, $result.DbCreated, $result.AlreadyConfigured))
        $count | Should -BeGreaterThan 0
        $lines[$count - 1] | Should -BeExactly '  PostgreSQL setup finished.'
        $lines[$count + 1] | Should -BeExactly ''
        $next = [array]::IndexOf($lines, '  Next: open TeknoParrot and start any game. Every game database was checked and is ready.')
        $next | Should -BeGreaterThan ($count + 1)
        $lines[$next - 1] | Should -BeExactly ''
        $lines[$next + 1] | Should -BeExactly ''
        $lines[$next + 2] | Should -BeExactly '  [D] Show details'
    }

    # Mutation: write the game lines back to back without the "never more than 5 lines in a
    # row" rule -> at 40 and 60 columns six or more lines follow each other.
    It 'never shows six or more text lines in a row and never a line wider than the console at width <Width>' -ForEach @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width $Width -OfferDetails

        (Get-F71LongestRun -Lines $lines) | Should -BeLessOrEqual 5
        $longest = ($lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        $longest | Should -BeLessOrEqual $Width
        $flat = Join-F71Screen -Lines $lines
        $flat | Should -Match ([regex]::Escape('Ready: Golden Tee Live 2019, Power Putt Live 2013, Silver Strike Bowling Live and Target Toss Pro Lawndarts'))
    }
}

Describe 'FIX71 games with the same outcome share one line' {
    # Mutation: one line per game again -> the three names are no longer joined by commas and "and".
    It 'joins the names of one outcome into one sentence and uses names, not keys' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 200 -OfferDetails

        $lines | Should -Contain '    Ready: Golden Tee Live 2019, Power Putt Live 2013, Silver Strike Bowling Live and Target Toss Pro Lawndarts. The databases were created from the games'' own backups and checked.'
        $lines | Should -Contain '    Ready: Power Putt Live 2012 and Target Toss Pro Bags. The databases were already there and were checked.'
        (@($lines | Where-Object { $_ -match '^    Ready:' })).Count | Should -Be 2
        ($lines -join "`n") | Should -Not -Match '\[(GoldenTee|PowerPutt|SilverStrike|TargetToss)|\(GameDB'
    }

    # Mutation: use the plural wording for a single game -> "databases ... games' own backups".
    It 'uses the singular wording for one game' {
        $fx = Install-F71ScreenMocks
        $result = New-F71Result -Games @((New-F71Game -Key 'Solo' -Name 'Solo Game' -Outcome 'CreatedFromBackup'))

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 200

        $lines | Should -Contain '    Ready: Solo Game. The database was created from the game''s own backup and checked.'
    }
}

Describe 'FIX71 the kept-password line uses the right plural' {
    # Mutation: print "game profile(s)" again, or the plural form for one game.
    It 'says <Expected> for <Kept> kept game(s) and says where to look' -ForEach @(
        @{ Kept = 1; Expected = '1 game kept its own PostgreSQL password or settings, so TeknoParrot Manager did not change it. Press D to see which.' },
        @{ Kept = 2; Expected = '2 games kept their own PostgreSQL password or settings, so TeknoParrot Manager did not change them. Press D to see which.' }
    ) {
        $fx = Install-F71ScreenMocks
        $result = New-F71Result -Kept $Kept

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 200 -OfferDetails

        $lines | Should -Contain ('  ' + $Expected)
        ($lines -join "`n") | Should -Not -Match '\(s\)'
    }

    # Mutation: send the child (no D key) to a key that does not exist.
    It 'does not point to the D key when the screen offers none' {
        $fx = Install-F71ScreenMocks
        $result = New-F71Result -Kept 1

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 200

        $lines | Should -Contain '  1 game kept its own PostgreSQL password or settings, so TeknoParrot Manager did not change it. The log says which.'
        ($lines -join "`n") | Should -Not -Match 'Press D'
    }
}

Describe 'FIX71 the details view is one short block per game' {
    # Mutation: print the note once per game, or leave it out -> the count is not 1.
    It 'says once, at the top, that no game was started' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 120 -Details
        $flat = Join-F71Screen -Lines $lines

        ([regex]::Matches($flat, [regex]::Escape('TeknoParrot Manager checked each database by connecting to it with the game''s own settings. It did not start any game.'))).Count | Should -Be 1
        $flat.IndexOf('did not start any game') | Should -BeLessThan $flat.IndexOf('Golden Tee Live 2019')
        ([regex]::Matches($flat, [regex]::Escape('connected with the game''s own settings and found 24 tables. The game is ready.'))).Count | Should -Be 6
    }

    # Mutation: a flat dump again -> the heading is not alone on its line, is not preceded by a blank line,
    # or the labeled lines are missing.
    It 'gives every game a heading, a blank line before it, and Database / Profile / What happened / What it means lines' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 120 -Details

        $expected = @(
            @{ Name = 'Golden Tee Live 2019'; Key = 'GoldenTeeLive2019'; Db = 'GameDB19' },
            @{ Name = 'Power Putt Live 2012'; Key = 'PowerPuttLive2012'; Db = 'GameDBPPL12' },
            @{ Name = 'Power Putt Live 2013'; Key = 'PowerPuttLive2013'; Db = 'GameDBPPL13' },
            @{ Name = 'Silver Strike Bowling Live'; Key = 'SilverStrikeBowlingLive'; Db = 'GameDBSSB' },
            @{ Name = 'Target Toss Pro Bags'; Key = 'TargetTossProBags'; Db = 'GameDBBags' },
            @{ Name = 'Target Toss Pro Lawndarts'; Key = 'TargetTossProLawndarts'; Db = 'GameDBLawn' }
        )
        foreach ($game in $expected) {
            $at = [array]::IndexOf($lines, ('  ' + $game.Name))
            $at | Should -BeGreaterThan 0 -Because ('the heading line for ' + $game.Name)
            $lines[$at - 1] | Should -BeExactly ''
            $lines[$at + 1] | Should -Match ('^\s{4}Database:\s+' + [regex]::Escape($game.Db) + '$')
            $lines[$at + 2] | Should -Match ('^\s{4}Profile:\s+' + [regex]::Escape($game.Key) + '$')
            $lines[$at + 3] | Should -Match '^\s{4}What happened:\s+\S'
            $block = New-Object System.Collections.Generic.List[string]
            for ($i = $at + 1; $i -lt $lines.Count -and -not [string]::IsNullOrWhiteSpace($lines[$i]); $i++) { [void]$block.Add($lines[$i]) }
            (@($block | Where-Object { $_ -match '^\s{4}What it means:\s+\S' })).Count | Should -Be 1
        }
    }

    # Mutation: print the "does not say whether" sentence for every game -> the count is 6, not 2.
    It 'says the build does not announce automatic creation only for the two games where that is true' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $flat = Join-F71Screen -Lines (Get-F71Screen -Fixture $fx -Result $result -Width 120 -Details)

        ([regex]::Matches($flat, [regex]::Escape('This TeknoParrot build does not say whether it creates the database automatically.'))).Count | Should -Be 2
    }

    # Mutation: print the three counters with other labels or padding, move them before the game
    # blocks, or print the Errors line for 0 -> the exact trailing lines differ.
    It 'ends with the three counter lines exactly, and has no Errors line when there are none' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 120 -Details
        $nonBlank = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

        $nonBlank[-4] | Should -BeExactly ('    Games set up           : {0}' -f $result.Configured)
        $nonBlank[-3] | Should -BeExactly ('    Fields updated         : {0}' -f $result.Configured)
        $nonBlank[-2] | Should -BeExactly ('    Databases created      : {0}' -f $result.DbCreated)
        $nonBlank[-1] | Should -BeExactly ('    Profiles unchanged     : {0}' -f $result.AlreadyConfigured)
        ($lines -join "`n") | Should -Not -Match '(?m)^\s+Errors:'
    }

    # Mutation: drop the Errors line -> a result with errors shows none.
    It 'shows the Errors line when there are errors' {
        $fx = Install-F71ScreenMocks
        $result = New-F71Result -Errors 2

        $lines = Get-F71Screen -Fixture $fx -Result $result -Width 120 -Details

        $lines | Should -Contain '    Errors: 2 (see TeknoParrot-Manager.log)'
    }

    # Mutation: leave out the "other notes" and "what to do next" blocks -> a warning that belongs
    # to no single game, or the advice, is lost from every screen.
    It 'keeps notes that belong to no single game and the advice, word for word' {
        $fx = Install-F71ScreenMocks
        $game = New-F71Game -Key 'GameA' -Name 'Game Alpha' -DbName 'DbAlpha' -Outcome 'AlreadyExisted'
        $result = New-F71Result -Games @($game) `
            -Warnings @('Game Alpha [GameA] (DbAlpha): this TeknoParrot build does not say whether it creates the database automatically. The database already existed and was left untouched.', 'Kept the existing PostgreSQL password or connection settings in 1 profile(s) because replacing them was not approved: OwnPasswordGame.') `
            -Checks @('Game Alpha [GameA] (DbAlpha): ready. Connected with the game''s own profile settings and found 24 tables.', 'A check that belongs to no game.') `
            -Actions @(@{ Id = 'Review'; Label = 'Open Details, fix the problem it names, then run PostgreSQL setup again.' })

        $flat = Join-F71Screen -Lines (Get-F71Screen -Fixture $fx -Result $result -Width 120 -Details)

        $flat | Should -Match ([regex]::Escape('Kept the existing PostgreSQL password or connection settings in 1 profile(s) because replacing them was not approved: OwnPasswordGame.'))
        $flat | Should -Match ([regex]::Escape('A check that belongs to no game.'))
        $flat | Should -Match ([regex]::Escape('Open Details, fix the problem it names, then run PostgreSQL setup again.'))
        $flat | Should -Not -Match ([regex]::Escape('Game Alpha [GameA] (DbAlpha): ready.'))
    }
}

Describe 'FIX71 the log holds everything the default screen no longer prints' {
    # Mutation: remove the Write-TpmPostgresSetupResultLog call from Write-TpmPostgresSetupResult ->
    # the protected resume child (no Details key) shows and logs none of the warnings, checks or advice.
    It 'writes one log line for every warning, check and advice item, with no Details key offered' {
        $fx = New-F71SixGames
        Install-F71SetupMocks -Fixture $fx
        $result = Invoke-F71Setup -Fixture $fx
        $warnings = @($result.Warnings)
        $checks = @($result.FinalVerification.Checks)
        $actions = @($result.RecoveryActions)
        $warnings.Count | Should -BeGreaterThan 0
        $checks.Count | Should -BeGreaterThan 0

        [void](Get-F71Screen -Fixture $fx -Result $result -Width 120)

        $log = @($fx.State.Log.ToArray())
        foreach ($warning in $warnings) { $log | Should -Contain ('Postgres setup note: ' + $warning) }
        foreach ($check in $checks) { $log | Should -Contain ('Postgres setup check: ' + $check) }
        foreach ($action in $actions) { $log | Should -Contain ('Postgres setup next step: ' + $action.Label) }
        $log | Should -Contain 'Postgres setup result: Golden Tee Live 2019 [GoldenTeeLive2019] (GameDB19): CreatedFromBackup.'
        (@($log | Where-Object { $_ -like 'Postgres setup note:*' })).Count | Should -Be $warnings.Count
    }
}
