#Requires -Module Pester

# FIX63: the result screen at the end of PostgreSQL setup (menu 13) must be short and
# plain. After setup the owner saw one long technical paragraph per game, repeated
# sentences, and the "Name [Key] (DbName)" triple. The default screen is now a heading,
# one count line, one plain line per game grouped by what happened, and one next
# step. Every technical sentence moved, unchanged, behind the D key (the details view).
#
# The production script is parsed and only its function definitions are dot-sourced;
# no top-level product code runs in this process. Setup runs against one in-memory
# fake of the PostgreSQL 8.3 client tools, so no PostgreSQL server, service, registry
# or user configuration is touched. Every file lives under TestDrive and every profile,
# game folder and backup is a synthetic fixture. Each It names the product mutation
# that makes it fail.

BeforeAll {
    $script:Fix63PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:Fix63PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX63 tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $script:Fix63FunctionFile = Join-Path $TestDrive 'tpm-fix63-functions.ps1'
    [System.IO.File]::WriteAllText($script:Fix63FunctionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $script:Fix63FunctionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    . (Join-Path $PSScriptRoot 'TpmFakePostgresInterpret.ps1')
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][System.IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force

    # Hardware and progress-line access is external to these tests.
    function Get-DetectedGpuVendor { [pscustomobject]@{ Vendor = $null; Name = 'isolated fixture' } }
    function Suspend-TpmProgressLine {}
    function Resume-TpmProgressLine {}

    function New-F63Fixture {
        param([Parameter(Mandatory)][string]$Name)
        $root = Join-Path $TestDrive ('f63-' + $Name + '-' + [guid]::NewGuid().ToString('N'))
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

    # Profile with a Postgres category (Path, Address, Port, DbName, User, Pass and the
    # optional "Automatically create Database"). -AutoCreate '' omits that field, which
    # is "this TeknoParrot build does not say". Path starts blank so setup fills it.
    function New-F63Profile {
        param(
            [Parameter(Mandatory)]$Fixture,
            [Parameter(Mandatory)][string]$ProfileName,
            [AllowEmptyString()][Parameter(Mandatory)][string]$GameName,
            [Parameter(Mandatory)][string]$DbName,
            [string]$Pass = '',
            [string]$AutoCreate = '1',
            [switch]$Backup,
            [switch]$Complete
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
        [void]$fields.Add(@('Path', $(if ($Complete) { 'C:\fixture\pg\bin\' } else { '' })))
        [void]$fields.Add(@('Address', $(if ($Complete) { '127.0.0.1' } else { '' })))
        [void]$fields.Add(@('Port', $(if ($Complete) { '5432' } else { '' })))
        [void]$fields.Add(@('DbName', $DbName))
        [void]$fields.Add(@('User', $(if ($Complete) { 'postgres' } else { '' })))
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

    function New-F63CommandResult {
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
    function Invoke-F63FakeCommand {
        param([string]$ToolName, [string[]]$Arguments)
        $state = $script:F63State
        $database = ''
        for ($i = 0; $i -lt $Arguments.Count - 1; $i++) {
            if ($Arguments[$i] -ceq '-d') { $database = [string]$Arguments[$i + 1] }
        }
        if ($ToolName -in @('createdb.exe', 'dropdb.exe')) { $database = [string]$Arguments[$Arguments.Count - 1] }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -notcontains '--list') { $database = [string]$Arguments[$Arguments.Count - 2] }
        [void]$state.Calls.Add([pscustomobject]@{ Tool = $ToolName; Database = $database; Arguments = @($Arguments) })
        if ($Arguments -contains '--version') {
            return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($ToolName + ' (PostgreSQL) 8.3.23'))
        }
        if ($ToolName -eq 'psql.exe' -and $Arguments -contains '-tAc') {
            $query = [string]$Arguments[$Arguments.Count - 1]
            if ($query -match 'count\(\*\)') { return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output '24') }
            $wanted = ''
            if ($query -match "lower\('([^']+)'\)\s*$") { $wanted = $Matches[1] }
            $names = @($state.Exists.Keys | Where-Object { $state.Exists[$_] -and [string]::Equals($_, $wanted, [System.StringComparison]::OrdinalIgnoreCase) })
            return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0 -Output ($names -join "`n"))
        }
        if ($ToolName -eq 'psql.exe') { return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe' -and $Arguments -contains '--list') { return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0) }
        if ($ToolName -eq 'pg_restore.exe') {
            [void]$state.Events.Add('pg_restore:' + $database)
            return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'createdb.exe') {
            [void]$state.Events.Add('createdb:' + $database)
            $state.Exists[$database] = $true
            return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        if ($ToolName -eq 'dropdb.exe') {
            [void]$state.Events.Add('dropdb:' + $database)
            $state.Exists[$database] = $false
            return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 0)
        }
        return (New-F63CommandResult -ToolName $ToolName -Arguments $Arguments -ExitCode 3 -Output 'unexpected fake tool')
    }

    function Install-F63SetupMocks {
        param([Parameter(Mandatory)]$Fixture)
        $script:F63State = $Fixture.State
        $script:F63Width = 120
        $script:F63Recovery = [pscustomobject]@{ Path = $Fixture.Evidence; ConfigBackups = @(); Verified = $true; ProfileBackups = @() }
        $script:PostgresBinDir = $Fixture.Bin
        $script:PostgresServiceName = 'pgsql-8.3'
        Mock Write-Log { [void]$script:F63State.Log.Add([string]$msg) }
        Mock Write-Host { [void]$script:F63State.Screen.Add(([string]($Object -join ' '))) }
        Mock Get-ConsoleContentWidth { return [int]$script:F63Width }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-Service { [pscustomobject]@{ Status = 'Running' } }
        Mock New-PostgresRecoveryBackup { [void]$script:F63State.Events.Add('backup'); $script:F63Recovery }
        Mock Invoke-Postgres83RestoreCommand {
            param([string]$ToolName, [string[]]$Arguments, [string]$SuperPasswordPlain, [scriptblock]$Interpret, $InterpretContext)
            # FIX129: the fake runs the caller's -Interpret block on its text, like the real runner does.
            Add-FakePostgresInterpretation -Command (Invoke-F63FakeCommand -ToolName $ToolName -Arguments $Arguments) -Interpret $Interpret -InterpretContext $InterpretContext
        }
        Mock Get-PostgresDatabaseState {
            param([string]$DbName, [string]$SuperPasswordPlain)
            $exists = $false
            if ($script:F63State.Exists.ContainsKey($DbName)) { $exists = [bool]$script:F63State.Exists[$DbName] }
            return [pscustomobject]@{ Exists = $exists; Verified = $true }
        }
    }

    # The six-game library from the owner's screenshot: two games that already have a
    # database and four that TPM creates from the game's own backup.
    function New-F63SixGames {
        $fx = New-F63Fixture -Name 'six'
        $fx.State.Exists['GameDBPPL12'] = $true
        $fx.State.Exists['GameDBBags'] = $true
        [void](New-F63Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -Backup)
        [void](New-F63Profile -Fixture $fx -ProfileName 'PowerPuttLive2012' -GameName 'Power Putt Live 2012' -DbName 'GameDBPPL12' -AutoCreate '')
        [void](New-F63Profile -Fixture $fx -ProfileName 'PowerPuttLive2013' -GameName 'Power Putt Live 2013' -DbName 'GameDBPPL13' -AutoCreate '' -Backup)
        [void](New-F63Profile -Fixture $fx -ProfileName 'SilverStrikeBowlingLive' -GameName 'Silver Strike Bowling Live' -DbName 'GameDBSSB' -AutoCreate '0' -Backup)
        [void](New-F63Profile -Fixture $fx -ProfileName 'TargetTossProBags' -GameName 'Target Toss Pro Bags' -DbName 'GameDBBags' -AutoCreate '0')
        [void](New-F63Profile -Fixture $fx -ProfileName 'TargetTossProLawndarts' -GameName 'Target Toss Pro Lawndarts' -DbName 'GameDBLawn' -AutoCreate '0' -Backup)
        return $fx
    }

    function Invoke-F63Setup {
        param([Parameter(Mandatory)]$Fixture)
        $result = Invoke-PostgresGameSetup -UserProfilesDir $Fixture.Profiles -SuperPasswordPlain 'fixture-password'
        $Fixture.State.Screen.Clear()
        return $result
    }

    # Writes the default screen (or the details view) at the given console width and
    # returns the lines that reached Write-Host.
    function Get-F63Screen {
        param([Parameter(Mandatory)]$Fixture, [Parameter(Mandatory)]$Result, [int]$Width = 120, [switch]$Details, [switch]$OfferDetails)
        $script:F63Width = $Width
        $Fixture.State.Screen.Clear()
        if ($Details) { Write-TpmPostgresSetupDetails -Result $Result }
        else { Write-TpmPostgresSetupResult -Result $Result -OfferDetails:$OfferDetails }
        return , ([string[]]$Fixture.State.Screen.ToArray())
    }

    # One string with the indent and the wrapping removed, so a sentence can be found
    # whatever the width broke it into.
    function Join-F63Screen {
        param([string[]]$Lines)
        return ((@($Lines) -join ' ') -replace '\s+', ' ')
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:Fix63PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Value $prior.Value -Scope Script }
        elseif (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue) { Remove-Variable -Name $name -Scope Script }
    }
}

Describe 'FIX63 setup records what happened to each game' {
    # Mutation: classify by the warning text, or treat "database existed" and "created from the backup"
    # as the same outcome -> the outcome map differs from this one.
    It 'names one outcome per game: created from backup or already there' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx

        $result = Invoke-F63Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.DbCreated | Should -Be 4
        $byKey = @{}
        foreach ($game in $result.GameOutcomes) { $byKey[[string]$game.Key] = $game }
        $byKey.Keys.Count | Should -Be 6
        $byKey['GoldenTeeLive2019'].Outcome | Should -BeExactly 'CreatedFromBackup'
        $byKey['PowerPuttLive2012'].Outcome | Should -BeExactly 'AlreadyExisted'
        $byKey['PowerPuttLive2013'].Outcome | Should -BeExactly 'CreatedFromBackup'
        $byKey['SilverStrikeBowlingLive'].Outcome | Should -BeExactly 'CreatedFromBackup'
        $byKey['TargetTossProBags'].Outcome | Should -BeExactly 'AlreadyExisted'
        $byKey['TargetTossProLawndarts'].Outcome | Should -BeExactly 'CreatedFromBackup'
        $byKey['PowerPuttLive2013'].Name | Should -BeExactly 'Power Putt Live 2013'
    }

    # Mutation: bring back the empty database (or the deferral to TeknoParrot) for a game with no backup -> createdb runs,
    # or the run is a clean success and the game is not named as not ready.
    It 'leaves out a game with no backup, creates nothing, and names it as not ready on the screen' {
        $fx = New-F63Fixture -Name 'nobackup'
        [void](New-F63Profile -Fixture $fx -ProfileName 'NoBackupGame' -GameName 'No Backup Game' -DbName 'GameDBNB' -AutoCreate '')
        Install-F63SetupMocks -Fixture $fx

        $result = Invoke-F63Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        @($fx.State.Events | Where-Object { $_ -like 'createdb:*' -or $_ -like 'pg_restore:*' }).Count | Should -Be 0
        $flat = Join-F63Screen -Lines (Get-F63Screen -Fixture $fx -Result $result -Width 120 -OfferDetails)
        $flat | Should -Match ([regex]::Escape('Could NOT be made ready: No Backup Game. No starting database file came with this game, so its database cannot be built.'))
        $flat | Should -Not -Match '(?i)start (it|the game|each game) once|TeknoParrot will ask|Every game database was checked and is ready'
    }
}

Describe 'FIX63 the default result screen is short and plain' {
    # Mutation: print the old per-game "Check:" / "Unverified/follow-up:" paragraphs on the
    # default screen again -> more than 14 lines and the forbidden words appear.
    It 'fits the six-game example in 14 lines or fewer and says each outcome in the exact plain sentence' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 120 -OfferDetails

        $lines.Count | Should -BeLessOrEqual 14
        $lines | Should -Contain '  PostgreSQL setup finished.'
        $lines | Should -Contain ('  Games set up: {0}. Databases created: {1}. Already set up: {2}.' -f $result.Configured, $result.DbCreated, $result.AlreadyConfigured)
        $flat = Join-F63Screen -Lines $lines
        $flat | Should -Match ([regex]::Escape('Ready: Golden Tee Live 2019, Power Putt Live 2013, Silver Strike Bowling Live and Target Toss Pro Lawndarts. The databases were created from the games'' own backups and checked.'))
        $flat | Should -Match ([regex]::Escape('Ready: Power Putt Live 2012 and Target Toss Pro Bags. The databases were already there and were checked.'))
        $lines | Should -Contain '  Next: open TeknoParrot and start any game. Every game database was checked and is ready.'
        $flat | Should -Not -Match '(?i)start (each|the) game once|click yes|TeknoParrot will ask'
        # FIX128: one name for the Details key ("[D] Show details"); it used to read "[D] Show technical details".
        $lines | Should -Contain '  [D] Show details'
    }

    # Mutation: print the profile key and database name next to the game name ("Name [Key]
    # (DbName)"), or add the technical caveats -> one of these forbidden fragments appears.
    It 'never shows the Name [Key] (DbName) triple, the caveats, "reinitialize" or the word TPM' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 120 -OfferDetails
        $text = $lines -join "`n"

        $text | Should -Not -Match '\[GoldenTeeLive2019\]|\(GameDB19\)|\[PowerPuttLive2013\]|\(GameDBPPL13\)'
        $text | Should -Not -Match 'Unverified|follow-up|Check:|does not say whether|catalog|reinitialize|initialization|verify|Fields updated|Profiles unchanged'
        $text | Should -Not -Match '\bTPM\b'
    }

    # Mutation: sort by game name instead of grouping by outcome -> the order of the names below changes.
    It 'groups the games by outcome, one line per outcome, in profile order inside a group' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 200
        $flat = Join-F63Screen -Lines $lines

        $created = $flat.IndexOf('Ready: Golden Tee Live 2019, Power Putt Live 2013, Silver Strike Bowling Live and Target Toss Pro Lawndarts')
        $already = $flat.IndexOf('Ready: Power Putt Live 2012 and Target Toss Pro Bags')
        $created | Should -BeGreaterOrEqual 0
        $already | Should -BeGreaterThan $created
    }

    # Mutation: print "[D] Show details" without checking -OfferDetails -> the protected
    # child (which cannot prompt) would offer a key nobody can press.
    It 'offers the D key only when it was asked to' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $without = Get-F63Screen -Fixture $fx -Result $result -Width 120
        $without -join "`n" | Should -Not -Match '\[D\]'
        $with = Get-F63Screen -Fixture $fx -Result $result -Width 120 -OfferDetails
        $with -join "`n" | Should -Match '\[D\] Show details'
    }

    # Mutation: print the game's Key only, or the DbName, when the profile has no game name ->
    # the line starts with the wrong word.
    It 'falls back to the profile key when the profile has no game name' {
        $fx = New-F63Fixture -Name 'noname'
        $fx.State.Exists['GameDBNN'] = $true
        [void](New-F63Profile -Fixture $fx -ProfileName 'UnnamedGameProfile' -GameName '' -DbName 'GameDBNN' -AutoCreate '0')
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 120

        $lines | Should -Contain '    Ready: UnnamedGameProfile. The database was already there and was checked.'
    }

    # Mutation: leave out the kept-password line -> a game that may not connect gets no hint
    # on the default screen.
    It 'tells that a game kept its own password, and not before' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx
        # The result object is built directly, so this does not depend on how the fake
        # setup treats a profile that already has a Pass value.
        $result | Add-Member -NotePropertyName PassKeptProfiles -NotePropertyValue @('OwnPasswordGame') -Force

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 200 -OfferDetails

        $lines | Should -Contain '  1 game kept its own PostgreSQL password or settings, so TeknoParrot Manager did not change it. Press D to see which.'
        ($lines -join "`n") | Should -Not -Match 'owner-own-password'

        $clean = New-F63SixGames
        Install-F63SetupMocks -Fixture $clean
        $cleanResult = Invoke-F63Setup -Fixture $clean
        (Get-F63Screen -Fixture $clean -Result $cleanResult -Width 120) -join "`n" | Should -Not -Match 'kept its own|kept their own'
    }
}

Describe 'FIX63 a repeat run reports what is there now' {
    # Mutation: fill GameOutcomes only for SUCCEEDED, or keep "created" for a database an
    # earlier run made -> the repeat run has no game lines, or claims a creation it did not do.
    It 'on the NO_OP repeat run says "already there" for databases the first run created' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $first = Invoke-F63Setup -Fixture $fx
        $first.Outcome | Should -BeExactly 'SUCCEEDED'

        $second = Invoke-F63Setup -Fixture $fx

        $second.Outcome | Should -BeExactly 'NO_OP'
        $second.DbCreated | Should -Be 0
        @($second.GameOutcomes).Count | Should -Be 6
        @($second.GameOutcomes | Where-Object { $_.Outcome -eq 'CreatedFromBackup' }).Count | Should -Be 0
        @($second.GameOutcomes | Where-Object { $_.Outcome -eq 'AlreadyExisted' }).Count | Should -Be 6
        $lines = Get-F63Screen -Fixture $fx -Result $second -Width 120 -OfferDetails
        $flat = Join-F63Screen -Lines $lines
        $flat | Should -Match ([regex]::Escape('Ready: Golden Tee Live 2019, Power Putt Live 2012, Power Putt Live 2013, Silver Strike Bowling Live, Target Toss Pro Bags and Target Toss Pro Lawndarts. The databases were already there and were checked.'))
        ($lines -join "`n") | Should -Not -Match 'created from the game'
    }
}

Describe 'FIX63 the screen reflows to the console width' {
    # Mutation: write the lines with Write-Host directly instead of Write-TpmText ->
    # the long game lines are longer than the console at 40 and 60 columns.
    It 'never writes a default-screen line longer than the console at width <Width>' -ForEach @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width $Width -OfferDetails

        $longest = ($lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        $longest | Should -BeLessOrEqual $Width
        $flat = Join-F63Screen -Lines $lines
        $flat | Should -Match ([regex]::Escape('Ready: Golden Tee Live 2019, Power Putt Live 2013, Silver Strike Bowling Live and Target Toss Pro Lawndarts. The databases were created from the games'' own backups and checked.'))
        $flat | Should -Match ([regex]::Escape('Ready: Power Putt Live 2012 and Target Toss Pro Bags. The databases were already there and were checked.'))
        if ($Width -le 60) { $lines.Count | Should -BeGreaterThan 14 -Because 'a narrow console wraps the lines, it does not cut them' }
    }

    # Mutation: write the details lines unwrapped -> long sentences exceed the width at 40 and 60.
    It 'never writes a details-view line longer than the console at width <Width>' -ForEach @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width $Width -Details

        $longest = ($lines | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        $longest | Should -BeLessOrEqual $Width
    }
}

Describe 'FIX63 the details view keeps every technical sentence' {
    # Mutation: leave a sentence out of the details view (for example the catalog note or the
    # "does not say whether" note) -> that sentence is missing below.
    It 'holds the verification notes, the per-game sentences, the advice and the old counter lines' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 120 -Details
        $flat = Join-F63Screen -Lines $lines

        $flat | Should -Match ([regex]::Escape('Golden Tee Live 2019'))
        $flat | Should -Match ([regex]::Escape('The database was already there. TeknoParrot Manager left it untouched.'))
        $flat | Should -Match ([regex]::Escape('This TeknoParrot build does not say whether it creates the database automatically.'))
        $flat | Should -Match ([regex]::Escape('The database did not exist. TeknoParrot Manager created it and restored the backup that comes with the game.'))
        $flat | Should -Match ([regex]::Escape('Setup connected to each game''s database with the settings saved in that game''s profile and counted its tables.'))
        $flat | Should -Match ([regex]::Escape('connected with the game''s own settings and found 24 tables. The game is ready.'))
        $flat | Should -Match ('Fields updated : {0} ' -f $result.Configured)
        $flat | Should -Match ('Databases created : {0} ' -f $result.DbCreated)
        $flat | Should -Match ('Profiles unchanged : {0}' -f $result.AlreadyConfigured)
    }

    # Mutation: print the old counters with a different label or drop the unchanged count -> the
    # exact label text the smoke harness reads is gone.
    It 'prints the counters with the exact labels and padding the smoke harness reads' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $result = Invoke-F63Setup -Fixture $fx

        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 120 -Details

        # FIX128 (N9): the Details total also carries the name the first screen uses ("Games set up"), with the same number.
        # Mutation: drop the line, or print a different number under that name.
        $lines | Should -Contain ('    Games set up           : {0}' -f $result.Configured)
        $lines | Should -Contain ('    Fields updated         : {0}' -f $result.Configured)
        $lines | Should -Contain ('    Databases created      : {0}' -f $result.DbCreated)
        $lines | Should -Contain ('    Profiles unchanged     : {0}' -f $result.AlreadyConfigured)
    }
}

Describe 'FIX63 sweep: a database made from the bundled backup is counted and described truthfully' {
    # A database this run built is counted under "Databases created", never as "Already set up" (only the games whose database was already there are).
    # Mutation: count every unchanged profile as already set up -> a rerun that rebuilds four databases prints "Already set up: 6".
    It 'counts a game whose profile was already right but whose database was made from the backup as created, not already set up' {
        $fx = New-F63SixGames
        Install-F63SetupMocks -Fixture $fx
        $null = Invoke-F63Setup -Fixture $fx
        foreach ($db in @('GameDB19', 'GameDBPPL13', 'GameDBSSB', 'GameDBLawn')) { $fx.State.Exists[$db] = $false }

        $result = Invoke-F63Setup -Fixture $fx

        $result.DbCreated | Should -Be 4
        $result.Configured | Should -Be 0
        $result.AlreadyConfigured | Should -Be 2
        $lines = Get-F63Screen -Fixture $fx -Result $result -Width 120 -OfferDetails
        $lines | Should -Contain '  Games set up: 0. Databases created: 4. Already set up: 2.'
    }

    # Mutation: keep the "did not exist" sentence for an empty database -> the Details say it did not exist.
    It 'says an existing but empty database was empty and the backup was restored into it' {
        $fx = New-F63Fixture -Name 'emptydb'
        $fx.State.Exists['GameDB19'] = $true
        [void](New-F63Profile -Fixture $fx -ProfileName 'GoldenTeeLive2019' -GameName 'Golden Tee Live 2019' -DbName 'GameDB19' -AutoCreate '1' -Backup)
        Install-F63SetupMocks -Fixture $fx
        Mock Get-PostgresUserTableCount {
            $restored = @($script:F63State.Events | Where-Object { $_ -eq 'pg_restore:GameDB19' }).Count -gt 0
            [pscustomobject]@{ Count = $(if ($restored) { 24 } else { 0 }); Error = $null }
        }

        $result = Invoke-F63Setup -Fixture $fx

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        @($fx.State.Events | Where-Object { $_ -eq 'pg_restore:GameDB19' }).Count | Should -Be 1
        $flat = Join-F63Screen -Lines (Get-F63Screen -Fixture $fx -Result $result -Width 120 -Details)
        $flat | Should -Not -Match 'did not exist'
        $flat | Should -Match ([regex]::Escape('The database was there but empty. TeknoParrot Manager restored the backup that comes with the game into it.'))
        (@($result.Warnings) -join ' ') | Should -Not -Match 'did not exist'
    }
}
