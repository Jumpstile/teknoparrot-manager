#Requires -Module Pester

# FIX83: screen readability wave 2 (audit items 11, 12, 13, 18, 19).
#
#  11. Library health check: one status per area, only problems are named, everything else under Details and in the log.
#  12. Restore backup (UserProfiles): newest first by the time in the folder name, plain labels, short confirmation, Details.
#  13. Reset and Restore: short list (5 rows and M for more), plain game names, counts instead of long lists, no "Selected :".
#  18. Check for Updates: a version that is newer than the latest release says so instead of two contradicting rows.
#  19. Help: one clause per line, a blank line between the groups.
#
# The production script is parsed and only its function definitions are dot-sourced; no top-level product code runs
# in this process. Every file lives under TestDrive and every profile, backup and restore point is a synthetic fixture.
# Each It names the product mutation that makes it fail.

BeforeAll {
    $script:F83PriorWorkflowState = @{}
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $snapshot = Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue
        $script:F83PriorWorkflowState[$name] = [pscustomobject]@{ Exists = ($null -ne $snapshot); Value = $(if ($null -ne $snapshot) { $snapshot.Value } else { $null }) }
    }
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $source = [System.IO.File]::ReadAllText($productionPath)
    $tokens = $null
    $parseErrors = $null
    $script:F83Ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX83 tests could not parse the production script.' }
    $definitions = @($script:F83Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-fix83-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:DisplayVersion = 'v1.0 RC8'

    function Install-F83Mocks {
        param([int]$Width = 80, [string[]]$Answers = @())
        $script:F83Screen = New-Object System.Collections.Generic.List[object]
        $script:F83Log = New-Object System.Collections.Generic.List[string]
        $script:F83Prompts = New-Object System.Collections.Generic.List[string]
        $script:F83PromptRows = New-Object System.Collections.Generic.List[int]
        $script:F83Answers = New-Object 'System.Collections.Generic.Queue[string]'
        $script:F83Width = $Width
        foreach ($answer in $Answers) { [void]$script:F83Answers.Enqueue($answer) }
        Mock Write-Host { [void]$script:F83Screen.Add([pscustomobject]@{ Text = [string]($Object -join ' '); Color = [string]$ForegroundColor }) }
        Mock Write-Log { [void]$script:F83Log.Add([string]$msg) }
        Mock Get-ConsoleContentWidth { return [int]$script:F83Width }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Read-HostSafe {
            [void]$script:F83Prompts.Add([string]$Prompt)
            [void]$script:F83PromptRows.Add($script:F83Screen.Count)
            if ($script:F83Answers.Count -eq 0) { throw ("UNEXPECTED PROMPT '{0}'" -f $Prompt) }
            $next = $script:F83Answers.Dequeue()
            if ($next -eq '' -and $null -ne $Default) { return $Default }
            return $next
        }
    }

    function Get-F83Lines { return @($script:F83Screen | ForEach-Object { $_.Text }) }
    function Get-F83Text { return ((@(Get-F83Lines) -join ' ') -replace '\s+', ' ') }

    # The most logical lines in a row with no blank row between them. A row that only continues the sentence above it (its
    # first word did not fit, so it was wrapped) belongs to that line. Slack covers the hanging indent. It can only count
    # too few lines, never too many.
    function Get-F83LongestRun {
        param([string[]]$Rows, [int]$Limit, [int]$Slack = 9)
        $longest = 0
        $run = 0
        $previous = ''
        foreach ($row in @($Rows)) {
            if ([string]::IsNullOrWhiteSpace($row)) { $run = 0; $previous = ''; continue }
            $firstWord = ($row.Trim() -split '\s+')[0]
            $continues = ($previous.Length -gt 0 -and ($previous.Length + 1 + $firstWord.Length) -gt ($Limit - $Slack))
            if (-not $continues) { $run++; if ($run -gt $longest) { $longest = $run } }
            $previous = [string]$row
        }
        return $longest
    }

    function Get-F83DetailText {
        param([Parameter(Mandatory)]$Result)
        return ((@(Get-TpmLibraryHealthDetailBlocks -Result $Result) | ForEach-Object { @($_.Lines) }) -join "`n")
    }

    function New-F83HealthResult {
        param([hashtable]$Override = @{})
        $base = [ordered]@{
            Outcome = 'SUCCEEDED'; DiscoveryComplete = $true; OptionalCoverageComplete = $true; OptionalCheckFailed = 0
            PostgresInventoryStatus = 'Complete'; PostgresInventoryErrors = @(); ReadOnly = $true; Registered = 4
            Valid = @('A', 'B', 'C', 'D'); Broken = @(); Empty = @()
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @()
            PostgresNeeded = @(); PostgresConfigured = 0; PostgresAutoCreateProfiles = @()
            PostgresServiceExists = $false; PostgresServiceStatus = 'NotInstalled'
            ReShadeCount = 0; BepInExCount = 0; DetectedGpuVendor = 'Intel'; LogPath = 'C:\Fix83\TeknoParrot-Manager.log'
            PostgresNeededLabels = @(); PostgresConfiguredLabels = @(); PostgresPsqlStatus = 'Unknown'
            OptionalCoverageUnavailable = $false; OptionalCoverageError = ''; LastFullRun = ''
        }
        foreach ($key in $Override.Keys) { $base[$key] = $Override[$key] }
        return [pscustomobject]$base
    }

    function New-F83BackupFixture {
        param([Parameter(Mandatory)][string[]]$Names)
        $root = Join-Path $TestDrive ('f83b-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $profiles = Join-Path $root 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($profiles)
        [System.IO.File]::WriteAllText((Join-Path $profiles 'CURRENT.xml'), '<GameProfile><GameName>Current</GameName></GameProfile>')
        foreach ($name in $Names) {
            $folder = Join-Path (Join-Path $profiles 'FullBackup') $name
            [void][System.IO.Directory]::CreateDirectory($folder)
            [System.IO.File]::WriteAllText((Join-Path $folder 'G.xml'), '<GameProfile><GameName>Backed up</GameName></GameProfile>')
        }
        return $profiles
    }

    function New-F83RestorePoint {
        param([int]$Index = 1, [string]$Kind = 'Startup', [int]$Files = 3, [string]$Folder = 'D:\Other\UserProfiles')
        return [pscustomobject]@{
            Id = ('P{0}' -f $Index); Kind = $Kind; Readable = $true
            CreatedUtc = ([datetime]::new(2026, 11, 3, 10, 0, 0, [System.DateTimeKind]::Utc)).AddMinutes(-$Index)
            Record = [pscustomobject]@{ FileCount = $Files; UserProfilesDir = $Folder; Entries = @(); Config = [pscustomobject]@{ Present = $false; Length = 0 } }
        }
    }

    # A folder with a live and a saved copy of each game, and a plan that changes them.
    function New-F83ResetFixture {
        param([Parameter(Mandatory)][string[]]$Codes, [hashtable]$Names = @{})
        $root = Join-Path $TestDrive ('f83r-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $profiles = Join-Path $root 'UserProfiles'
        $backup = Join-Path $root 'Backup'
        [void][System.IO.Directory]::CreateDirectory($profiles)
        [void][System.IO.Directory]::CreateDirectory($backup)
        foreach ($code in $Codes) {
            $gameName = if ($Names.ContainsKey($code)) { [string]$Names[$code] } else { ('Game {0}' -f $code) }
            $xml = ('<GameProfile><GameName>{0}</GameName></GameProfile>' -f $gameName)
            [System.IO.File]::WriteAllText((Join-Path $profiles ($code + '.xml')), $xml)
            [System.IO.File]::WriteAllText((Join-Path $backup ($code + '.xml')), $xml)
        }
        return [pscustomobject]@{ Profiles = $profiles; Backup = $backup }
    }

    function New-F83Change {
        param([Parameter(Mandatory)][string]$Code, [string]$Change = 'Replace', [bool]$IsGame = $true)
        return [pscustomobject]@{ IsGameProfile = $IsGame; Change = $Change; RelativePath = ($Code + '.xml'); CurrentSha256 = 'ABC123' }
    }

    function New-F83Plan {
        param([object[]]$Changes, [object[]]$FoldersRemoved = @(), [object[]]$FoldersPutBack = @(), [string]$ConfigChange = 'Same')
        return [pscustomobject]@{ Changes = @($Changes); FoldersRemoved = @($FoldersRemoved); FoldersPutBack = @($FoldersPutBack); ConfigChange = $ConfigChange; CurrentStateKey = 'key' }
    }
}

AfterAll {
    foreach ($name in @('ActiveTpmWorkflowStatus', 'TpmWorkflowRendering')) {
        $prior = $script:F83PriorWorkflowState[$name]
        if ($prior.Exists) { Set-Variable -Name $name -Scope Script -Value $prior.Value } else { Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue }
    }
}

Describe 'FIX83 shared helpers' {
    It 'writes a count with the right singular or plural noun' {
        # Mutation: always add the plural noun -> "1 files"; or return the count for 1 without a noun.
        (Format-TpmCountNoun -Count 1 -Singular 'file') | Should -BeExactly '1 file'
        (Format-TpmCountNoun -Count 0 -Singular 'file') | Should -BeExactly '0 files'
        (Format-TpmCountNoun -Count 7 -Singular 'restore point') | Should -BeExactly '7 restore points'
    }

    It 'joins a few names and counts the rest' {
        # Mutation: return the whole list, or drop the count of the rest.
        (Format-TpmNameList -Names @('A', 'B') -Max 3) | Should -BeExactly 'A and B'
        (Format-TpmNameList -Names @('A', 'B', 'C', 'D', 'E', 'F') -Max 3) | Should -BeExactly 'A, B, C and 3 more'
        (Format-TpmNameList -Names @() -Max 3 -WhenEmpty 'none') | Should -BeExactly 'none'
        (Format-TpmNameList -Names @('Only') -Max 3) | Should -BeExactly 'Only'
    }

    It 'writes every detail line of every block to the log' {
        # Mutation: log only the headings, or only the first line of a block.
        Install-F83Mocks
        Write-TpmDetailBlocksLog -Blocks @(@{ Heading = 'Game one'; Lines = @('Database: DB1', 'What happened: It worked.') }, @{ Heading = 'Game two'; Lines = @('Database: DB2') }) -Prefix 'Test detail'
        @($script:F83Log) | Should -Be @('Test detail [Game one]: Database: DB1', 'Test detail [Game one]: What happened: It worked.', 'Test detail [Game two]: Database: DB2')
    }

    It 'shows 5 rows, then the rest after M, and keeps the row numbers' {
        # Mutation: show every row at once, or renumber the rows after M -> row 6 is on the first screen, or the answer 7 picks another row.
        Install-F83Mocks -Answers @('M', '7')
        $picked = Read-TpmNumberedListChoice -Rows @(1..7 | ForEach-Object { 'Row {0}' -f $_ }) -Prompt '  Pick one' -Heading 'The rows:'
        $picked | Should -Be 6
        $firstScreen = @((Get-F83Lines)[0..($script:F83PromptRows[0] - 1)])
        $firstScreen | Should -Contain '    5) Row 5'
        @($firstScreen | Where-Object { $_ -like '*6) Row 6*' }).Count | Should -Be 0
        $firstScreen | Should -Contain '    M) Show 2 more'
        @(Get-F83Lines) | Should -Contain '    7) Row 7'
        $script:F83Prompts.Count | Should -Be 2
    }

    It 'does not accept a hidden row number before M, and Enter goes back' {
        # Mutation: allow every row number from the start -> 6 picks a row that was not shown.
        Install-F83Mocks -Answers @('6', '')
        $picked = Read-TpmNumberedListChoice -Rows @(1..7 | ForEach-Object { 'Row {0}' -f $_ }) -Prompt '  Pick one'
        $picked | Should -Be -1
        @(Get-F83Lines | Where-Object { $_ -like '*Invalid choice*' }).Count | Should -Be 1
    }

    It 'offers Details only when there are details, shows them once per D and asks again' {
        # Mutation: always print the D row, or return after the details.
        Install-F83Mocks -Answers @('D', '2')
        $blocks = @(1..3 | ForEach-Object { @{ Heading = ('Row {0}' -f $_); Lines = @(('Folder: Folder{0}' -f $_)) } })
        $picked = Read-TpmNumberedListChoice -Rows @('Row 1', 'Row 2', 'Row 3') -Prompt '  Pick one' -DetailBlocks $blocks
        $picked | Should -Be 1
        $script:F83Prompts.Count | Should -Be 2
        @(Get-F83Lines | Where-Object { $_ -match '^    Folder:\s+Folder2$' }).Count | Should -Be 1
        @(Get-F83Lines) | Should -Contain '    D) Details'
        Install-F83Mocks -Answers @('1')
        [void](Read-TpmNumberedListChoice -Rows @('Row 1', 'Row 2') -Prompt '  Pick one')
        @(Get-F83Lines | Where-Object { $_ -like '*D) Details*' }).Count | Should -Be 0
    }

    It 'keeps the list screen spaced out and inside the console at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the heading, the rows and the M and D rows without blank lines between them -> 8 lines in a row.
        Install-F83Mocks -Width $Width -Answers @('B')
        $rows = @(1..8 | ForEach-Object { 'Saved at start-up, today 10:00 - {0} files - older copy, cannot be fully checked' -f $_ })
        $blocks = @(1..8 | ForEach-Object { @{ Heading = ('Row {0}' -f $_); Lines = @('Folder: x') } })
        [void](Read-TpmNumberedListChoice -Rows $rows -Prompt '  Pick one' -Heading 'Saved copies of your game settings, newest first:' -DetailBlocks $blocks)
        $lines = @(Get-F83Lines)
        $lines[0] | Should -BeExactly ''
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F83LongestRun -Rows $lines -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        @($lines | Where-Object { $_ -match '^    \d\) ' }).Count | Should -Be 5
    }

    It 'words a moment as today, yesterday, a day this year or a day in another year' {
        # Mutation: always print the date, or compare the UTC date instead of the local one.
        $when = [datetime]::new(2026, 11, 3, 10, 0, 0, [System.DateTimeKind]::Utc)
        $local = $when.ToLocalTime()
        $clock = $local.ToString('HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        (Format-TpmFriendlyTime -WhenUtc $when -Now $local.Date.AddHours(20)) | Should -BeExactly ('today ' + $clock)
        (Format-TpmFriendlyTime -WhenUtc $when -Now $local.Date.AddDays(1).AddHours(8)) | Should -BeExactly ('yesterday ' + $clock)
        (Format-TpmFriendlyTime -WhenUtc $when -Now $local.Date.AddDays(5)) | Should -BeExactly ($local.ToString('d MMM', [System.Globalization.CultureInfo]::InvariantCulture) + ' ' + $clock)
        (Format-TpmFriendlyTime -WhenUtc $when -Now $local.Date.AddDays(400)) | Should -BeExactly ($local.ToString('d MMM yyyy', [System.Globalization.CultureInfo]::InvariantCulture) + ' ' + $clock)
    }
}

Describe 'FIX83 item 11: Library health check default view' {
    It 'gives one status row per area and names no game in the default view' {
        # Mutation: print the names of the games in the rows again (the old per-game lines), or drop them from the details.
        Install-F83Mocks -Width 80
        $result = New-F83HealthResult @{ Broken = @('ZetaBroken', 'EtaBroken'); Valid = @('A', 'B'); GpuFixNeeded = @('ThetaGpu'); DgVoodoo2Needed = @('IotaDg', 'KappaDg') }
        Write-TpmLibraryHealthReport -Result $result
        $lines = @(Get-F83Lines)
        @($lines | Where-Object { $_ -match '^  Game paths:\s+Needs attention - 2 games need a new path$' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match '^  GPU fix:\s+Needs attention - 1 game$' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match '^  Force feedback:\s+Not checked - profiles fine, plugin not looked at$' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match '^  dgVoodoo2:\s+Needs attention - 2 games$' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match 'PostgreSQL:' }).Count | Should -Be 0
        $lines | Should -Contain '  Some things need attention.'
        $lines | Should -Not -Contain '  Everything looks fine.'
        ($lines -join "`n") | Should -Not -Match 'ZetaBroken|EtaBroken|ThetaGpu|IotaDg|KappaDg'
        $details = Get-F83DetailText -Result $result
        $details | Should -Match 'ZetaBroken and EtaBroken'
        $details | Should -Match 'Still needs the fix: ThetaGpu'
        $details | Should -Match 'Still needed: IotaDg and KappaDg'
    }

    It 'keeps the technical lines out of the default view and in the details and the log' {
        # Mutation: print the PostgreSQL service, client and inventory lines, the plugin note or the "0 of 0" counts in the default view again.
        Install-F83Mocks -Width 80
        $result = New-F83HealthResult @{ PostgresConfigured = 2; PostgresConfiguredLabels = @('Golden Tee Live 2020', 'Power Putt Live'); PostgresServiceExists = $true; PostgresServiceStatus = 'Stopped'; PostgresPsqlStatus = 'Found'; Valid = @('A', 'B'); Registered = 2 }
        Write-TpmLibraryHealthReport -Result $result
        ($script:F83Screen | ForEach-Object { $_.Text }) -join "`n" | Should -Not -Match 'service exists|service state|psql\.exe|profile inventory|network access|valid games detected|of 0'
        $details = Get-F83DetailText -Result $result
        $details | Should -Match 'Service exists: found'
        $details | Should -Match 'Service state: stopped'
        $details | Should -Match 'Client psql\.exe: Found'
        $details | Should -Match 'Profile inventory: Complete'
        $details | Should -Match 'Force feedback plugin was not checked because network access is needed\.'
        $details | Should -Match 'Fields filled in for: Golden Tee Live 2020 and Power Putt Live'
        $script:F83Log | Should -Contain 'Library health detail [PostgreSQL]: Service state: stopped'
        $script:F83Log | Should -Contain 'Library health detail [Log]: Technical log: C:\Fix83\TeknoParrot-Manager.log'
    }

    It 'says Everything looks fine only when every check finished and nothing needs attention' -TestCases @(
        @{ Case = 'all fine'; Override = @{}; Fine = $true }
        @{ Case = 'a game could not be read'; Override = @{ OptionalCheckFailed = 2 }; Fine = $false }
        @{ Case = 'the field definitions could not be read'; Override = @{ OptionalCoverageUnavailable = $true; OptionalCoverageError = 'no GameProfiles folder' }; Fine = $false }
        @{ Case = 'the PostgreSQL check is incomplete'; Override = @{ PostgresInventoryStatus = 'Unknown' }; Fine = $false }
        @{ Case = 'the game startup files check failed'; Override = @{ PrerequisiteChecked = $true; PrerequisiteCheckFailed = $true }; Fine = $false }
        @{ Case = 'the game types check could not run'; Override = @{ GameTypeCheckFailed = $true }; Fine = $false }
        @{ Case = 'the controls check could not run'; Override = @{ ControlsCheckFailed = $true }; Fine = $false }
        @{ Case = 'the graphics card was not detected'; Override = @{ DetectedGpuVendor = $null }; Fine = $false }
        @{ Case = 'the PostgreSQL service could not be read'; Override = @{ PostgresConfigured = 1; PostgresServiceExists = $null; PostgresServiceUnverified = $true }; Fine = $false }
    ) {
        param($Case, $Override, $Fine)
        # Mutation: print "Everything looks fine." whenever no area needs attention -> an incomplete check reads as an all-clear.
        Install-F83Mocks
        Write-TpmLibraryHealthReport -Result (New-F83HealthResult $Override)
        $lines = @(Get-F83Lines)
        if ($Fine) {
            $lines | Should -Contain '  Everything looks fine.'
            @($lines | Where-Object { $_ -like '*not an all-clear*' }).Count | Should -Be 0
        } else {
            $lines | Should -Not -Contain '  Everything looks fine.'
            $lines | Should -Contain '  Some checks could not finish, so this is not an all-clear.'
        }
    }

    It 'tells the user why the check is incomplete when the graphics card was not detected, and only then' {
        # Mutation: leave the user with only a vague "some checks could not finish", or print the GPU sentence when the card was found.
        Install-F83Mocks
        Write-TpmLibraryHealthReport -Result (New-F83HealthResult @{ DetectedGpuVendor = $null })
        $lines = @(Get-F83Lines)
        # The console wraps the sentence at the screen width, so compare the text with the line breaks removed.
        (($lines -join ' ') -replace '\s+', ' ') | Should -Match 'Your graphics card was not detected, so the GPU fix check was skipped\. This is normal on a virtual machine\.'
        Install-F83Mocks
        Write-TpmLibraryHealthReport -Result (New-F83HealthResult @{})
        @(Get-F83Lines | Where-Object { $_ -like '*graphics card was not detected*' }).Count | Should -Be 0
    }

    It 'shows the PostgreSQL row only when it matters: <Case>' -TestCases @(
        @{ Case = 'no database game'; Override = @{}; Expected = $null }
        @{ Case = 'set up and running'; Override = @{ PostgresConfigured = 2; PostgresServiceExists = $true; PostgresServiceStatus = 'Running' }; Expected = 'OK' }
        @{ Case = 'one game needs setup'; Override = @{ PostgresNeeded = @('X'); PostgresNeededLabels = @('Game X') }; Expected = 'Needs attention - 1 game needs setup' }
        @{ Case = 'two games need setup'; Override = @{ PostgresNeeded = @('X', 'Y') }; Expected = 'Needs attention - 2 games need setup' }
        @{ Case = 'not installed'; Override = @{ PostgresConfigured = 1; PostgresServiceExists = $false }; Expected = 'Needs attention - PostgreSQL is not installed' }
        @{ Case = 'stopped'; Override = @{ PostgresConfigured = 1; PostgresServiceExists = $true; PostgresServiceStatus = 'Stopped' }; Expected = 'Needs attention - PostgreSQL is stopped' }
        @{ Case = 'service could not be read'; Override = @{ PostgresConfigured = 1; PostgresServiceExists = $null; PostgresServiceUnverified = $true }; Expected = 'Could not check' }
        @{ Case = 'inventory incomplete'; Override = @{ PostgresInventoryStatus = 'Error' }; Expected = 'Could not check' }
    ) {
        param($Case, $Override, $Expected)
        # Mutation: always print a PostgreSQL row, or never flag a missing or stopped service.
        $row = @(Get-TpmLibraryHealthRows -Result (New-F83HealthResult $Override) | Where-Object { $_.Area -eq 'PostgreSQL' })
        if ($null -eq $Expected) { $row.Count | Should -Be 0 } else { $row.Count | Should -Be 1; $row[0].Text | Should -BeExactly $Expected }
    }

    It 'does not claim a clean result for the areas that could not be checked' {
        # Mutation: report GPU, force feedback and dgVoodoo2 as OK when the field definitions could not be read (the old dgVoodoo2 line did).
        $rows = @(Get-TpmLibraryHealthRows -Result (New-F83HealthResult @{ OptionalCoverageUnavailable = $true }))
        foreach ($area in @('GPU fix', 'Force feedback', 'dgVoodoo2')) { @($rows | Where-Object { $_.Area -eq $area })[0].Text | Should -BeExactly 'Could not check' }
        $unknownGpu = @(Get-TpmLibraryHealthRows -Result (New-F83HealthResult @{ DetectedGpuVendor = $null }) | Where-Object { $_.Area -eq 'GPU fix' })
        $unknownGpu[0].Text | Should -BeExactly 'Not checked - GPU not detected'
    }

    It 'says plainly that the game list could not be read and shows no counts' {
        # Mutation: print zero counts for an unreadable list.
        Install-F83Mocks
        Write-TpmLibraryHealthReport -Result (New-F83HealthResult @{ DiscoveryComplete = $false; PostgresInventoryStatus = 'Error'; PostgresInventoryErrors = @('Access to the folder was denied.'); Registered = 0; Valid = @() })
        $text = Get-F83Text
        $text | Should -Match 'TeknoParrot Manager could not read your list of games\. No counts are shown\.'
        $text | Should -Not -Match 'Everything looks fine|games need|OK -'
        (Get-F83DetailText -Result (New-F83HealthResult @{ DiscoveryComplete = $false; PostgresInventoryStatus = 'Error'; PostgresInventoryErrors = @('Access to the folder was denied.') })) | Should -Match 'Problem: Access to the folder was denied\.'
    }

    It 'is spaced out, fits the console and never prints six text lines in a row at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the rows, the verdict and the counters as one block, or write a row without wrapping.
        Install-F83Mocks -Width $Width
        $result = New-F83HealthResult @{ Broken = @('A', 'B'); Empty = @('C'); GpuFixNeeded = @('D'); FfbBlasterNeeded = @('E'); DgVoodoo2Needed = @('F'); PostgresNeeded = @('G'); OptionalCheckFailed = 1 }
        Write-TpmLibraryHealthReport -Result $result
        $lines = @(Get-F83Lines)
        $lines[0] | Should -BeExactly ''
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F83LongestRun -Rows $lines -Limit ($Width - 1)) | Should -BeLessOrEqual 5
    }

    It 'counts a game only where the number means something, in the action menu' {
        # Mutation: print "(0 of 0 valid games detected)" and "(0 game(s) still need it)" again.
        Install-F83Mocks -Answers @('B')
        $none = New-F83HealthResult @{ Valid = @(); Registered = 0 }
        (Show-LibraryHealthNextActions -Result $none) | Should -BeExactly 'B'
        $lines = @(Get-F83Lines)
        $lines | Should -Contain '  [6] ReShade'
        $lines | Should -Contain '  [7] dgVoodoo2'
        $lines | Should -Contain '  [8] GPU Fix'
        $lines | Should -Contain '  [10] BepInEx'
        ((Get-F83Lines) -join "`n") | Should -Not -Match 'of 0|\(s\)'
        Install-F83Mocks -Answers @('B')
        $some = New-F83HealthResult @{ Valid = @(1..10 | ForEach-Object { 'G{0}' -f $_ }); Registered = 10; ReShadeCount = 3; BepInExCount = 0; DgVoodoo2Needed = @('X', 'Y'); GpuFixNeeded = @('Z') }
        [void](Show-LibraryHealthNextActions -Result $some)
        $lines = @(Get-F83Lines)
        $lines | Should -Contain '  [6] ReShade (3 of 10 games have it)'
        $lines | Should -Contain '  [7] dgVoodoo2 (2 games still need it)'
        $lines | Should -Contain '  [8] GPU Fix (1 game still needs it)'
        $lines | Should -Contain '  [9] Force Feedback'
        $lines | Should -Contain '  [10] BepInEx (0 of 10 games have it)'
    }

    It 'shows the whole report as short blocks when D is chosen, then asks again' {
        # Mutation: treat D as another answer, or return after the details.
        Install-F83Mocks -Answers @('D', 'B')
        $result = New-F83HealthResult @{ Broken = @(); PostgresConfigured = 1; PostgresConfiguredLabels = @('Game P'); PostgresServiceExists = $true; PostgresServiceStatus = 'Running' }
        (Show-LibraryHealthNextActions -Result $result) | Should -BeExactly 'B'
        $script:F83Prompts.Count | Should -Be 2
        $lines = @(Get-F83Lines)
        $lines | Should -Contain '  Game paths'
        $lines | Should -Contain '  PostgreSQL'
        @($lines | Where-Object { $_ -match '^    Service state:\s+running$' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -eq '  [B] Back to main menu' }).Count | Should -Be 2
    }

    It 'names at most five broken games and keeps the repair choices' {
        # Mutation: list every broken game, or drop a repair choice.
        Install-F83Mocks -Answers @('B')
        $broken = @(1..8 | ForEach-Object { 'Game{0}' -f $_ })
        $result = New-F83HealthResult @{ Broken = $broken; Valid = @('A'); Registered = 9 }
        (Show-LibraryHealthNextActions -Result $result) | Should -BeExactly 'B'
        $text = Get-F83Text
        $text | Should -Match '8 games cannot be found at the saved path: Game1, Game2, Game3, Game4, Game5 and 3 more\.'
        $text | Should -Not -Match 'Game6'
        foreach ($choice in @('[R] Try automatic path repair', '[M] Let me pick the correct executable manually', '[S] Search another game folder', '[D] Details', '[B] Back to main menu')) {
            @(Get-F83Lines) | Should -Contain ('  ' + $choice)
        }
        $script:F83Prompts[0] | Should -BeLike '*Choose R, M, S, D, or B*'
    }

    It 'hides the PostgreSQL setup choice when the game check was incomplete' {
        # Mutation: offer [P] or leave out the explanation when the inventory is not complete.
        Install-F83Mocks -Answers @('P', 'B')
        $result = New-F83HealthResult @{ PostgresInventoryStatus = 'Unknown'; OptionalCheckFailed = 0 }
        (Show-LibraryHealthNextActions -Result $result) | Should -BeExactly 'B'
        $text = Get-F83Text
        $text | Should -Match 'PostgreSQL setup choices are hidden because the game check was incomplete\.'
        $text | Should -Not -Match '\[P\] Set up'
        $text | Should -Match 'Invalid choice'
    }
}

Describe 'FIX83 item 12: Restore backup list and confirmation' {
    It 'reads the kind and the time from a backup folder name: <Name>' -TestCases @(
        @{ Name = 'PropagateControls_2026-11-03_10-00-49_240_212bcaae'; Kind = 'PropagateControls'; Utc = '2026-11-03T10:00:49.240Z'; Words = 'Before Propagate Controls' }
        @{ Name = 'Startup_2026-11-03_10-00-57_326_c8ae9bbf'; Kind = 'Startup'; Utc = '2026-11-03T10:00:57.326Z'; Words = 'Saved at start-up' }
        @{ Name = 'PropagateControls_2026-07-01_12-00-00'; Kind = 'PropagateControls'; Utc = '2026-07-01T12:00:00.000Z'; Words = 'Before Propagate Controls' }
        @{ Name = 'SomethingNew_2026-01-02_03-04-05_006_deadbeef'; Kind = 'SomethingNew'; Utc = '2026-01-02T03:04:05.006Z'; Words = 'Saved copy' }
    ) {
        param($Name, $Kind, $Utc, $Words)
        # Mutation: take the whole name as the kind, parse the time as local time, or drop the milliseconds.
        $info = Get-TpmUserProfilesBackupInfo -Name $Name
        $info.WhenUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [System.Globalization.CultureInfo]::InvariantCulture) | Should -BeExactly $Utc
        $info.Text | Should -BeLike ($Words + ', *')
    }

    It 'gives a name without a readable time no time and the plain default words' {
        # Mutation: throw, or invent a time, for a folder that is not named by this script.
        $info = Get-TpmUserProfilesBackupInfo -Name 'my old copy'
        $info.WhenUtc | Should -BeNullOrEmpty
        $info.Text | Should -BeExactly 'Saved copy'
    }

    It 'lists the saved copies newest first by the time in the name, with plain labels and no internal names' {
        # Mutation: sort by folder name (Startup_ then PropagateControls_ then GpuFix_), or print the folder name and "file(s)" again.
        $profiles = New-F83BackupFixture -Names @('Startup_2026-11-03_10-00-57_326_c8ae9bbf', 'PropagateControls_2026-11-03_10-00-49_240_212bcaae', 'GpuFix_2026-11-05_08-00-00_000_aaaaaaaa')
        Install-F83Mocks -Width 120 -Answers @('1', 'no')
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $profiles
        $result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        $result.Name | Should -BeExactly 'GpuFix_2026-11-05_08-00-00_000_aaaaaaaa'
        $lines = @(Get-F83Lines)
        @($lines | Where-Object { $_ -match '^    1\) Before the GPU fix, .* - 1 file - older copy, cannot be fully checked$' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match '^    2\) Saved at start-up, ' }).Count | Should -Be 1
        @($lines | Where-Object { $_ -match '^    3\) Before Propagate Controls, ' }).Count | Should -Be 1
        $text = Get-F83Text
        $text | Should -Not -Match '_2026-|file\(s\)|profile\(s\)|most recent first|Selected :|WARNING +: This will OVERWRITE|UNVERIFIED: This backup'
        $text | Should -Match 'You chose: Before the GPU fix, .*\. It has 1 game\.'
        $text | Should -Match 'This copy cannot be checked\. TeknoParrot Manager cannot be sure it is complete\. Games that are missing from it will be removed\.'
        $text | Should -Match 'Warning: this replaces ALL your current game settings with this saved copy\.'
        $script:F83Log | Should -Contain 'Restore: selected backup GpuFix_2026-11-05_08-00-00_000_aaaaaaaa (1 profile(s), 1 file(s) in total).'
    }

    It 'keeps every old fact under Details: folder name, files and the check' {
        # Mutation: leave the folder name or the missing completion record out of the details.
        $profiles = New-F83BackupFixture -Names @('Startup_2026-11-03_10-00-57_326_c8ae9bbf')
        Install-F83Mocks -Answers @('D', '1', 'D', 'no')
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $profiles
        $result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        $lines = @(Get-F83Lines)
        @($lines | Where-Object { $_ -match '^    Folder:\s+Startup_2026-11-03_10-00-57_326_c8ae9bbf$' }).Count | Should -Be 2
        @($lines | Where-Object { $_ -match '^    Files:\s+1$' }).Count | Should -Be 2
        @($lines | Where-Object { $_ -match '^    Games:\s+1$' }).Count | Should -Be 1
        (Get-F83Text) | Should -Match 'It has no completion record\. It was made by an older version of TeknoParrot Manager or by another tool, so TeknoParrot Manager cannot prove it is complete\.'
        $script:F83Prompts.Count | Should -Be 4
    }

    It 'shows 5 saved copies and the rest after M' {
        # Mutation: print every saved copy at once.
        $names = @(1..7 | ForEach-Object { 'Startup_2026-11-0{0}_10-00-00_000_aaaaaaa{0}' -f $_ })
        $profiles = New-F83BackupFixture -Names $names
        Install-F83Mocks -Width 120 -Answers @('M', 'B')
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $profiles
        $result.ReasonCode | Should -BeExactly 'USER_CANCELLED'
        $firstScreen = @((Get-F83Lines)[0..($script:F83PromptRows[0] - 1)])
        @($firstScreen | Where-Object { $_ -match '^    \d\) ' }).Count | Should -Be 5
        $firstScreen | Should -Contain '    M) Show 2 more'
        @(Get-F83Lines | Where-Object { $_ -match '^    \d\) ' }).Count | Should -Be 12
    }

    It 'prints no "Selected" line and no choice screen for the restore that Reset and Restore started' {
        # Mutation: print the "Selected : <folder>" line (or "You chose") when the restore point was already chosen and confirmed.
        $profiles = New-F83BackupFixture -Names @('Startup_2026-11-03_10-00-57_326_c8ae9bbf')
        $folder = Join-Path (Join-Path $profiles 'FullBackup') 'Startup_2026-11-03_10-00-57_326_c8ae9bbf'
        Install-F83Mocks -Answers @('no')
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $profiles -SelectedBackupPath $folder -AlreadyConfirmed
        $result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        $text = Get-F83Text
        $text | Should -Not -Match 'Selected|You chose|Startup_2026|Warning: this replaces'
        $script:F83Log | Should -Contain 'Restore: selected backup Startup_2026-11-03_10-00-57_326_c8ae9bbf (1 profile(s), 1 file(s) in total).'
    }

    It 'does not print its own Restore complete line, because the result screen says it once' {
        # Mutation: print "Restore complete." again in Invoke-RestoreBackupLegacy -> the footer then says it twice.
        $profiles = New-F83BackupFixture -Names @('Startup_2026-11-03_10-00-57_326_c8ae9bbf')
        $folder = Join-Path (Join-Path $profiles 'FullBackup') 'Startup_2026-11-03_10-00-57_326_c8ae9bbf'
        Mock Wait-TpmForProcessClose { return $true }
        Install-F83Mocks -Answers @('UNVERIFIED')
        $result = Invoke-RestoreBackupLegacy -userProfilesDir $profiles -SelectedBackupPath $folder -AlreadyConfirmed
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        (Test-Path -LiteralPath (Join-Path $profiles 'G.xml')) | Should -BeTrue
        @(Get-F83Lines | Where-Object { $_ -like '*Restore complete*' }).Count | Should -Be 0
        $script:F83Log | Should -Contain 'Restore: completed from Startup_2026-11-03_10-00-57_326_c8ae9bbf, no errors.'
    }

    It 'ends the restore menu with a plain Restore complete. and logs the old outcome sentence' {
        # Mutation: put the "Restore completed; outcome: restore transaction reported SUCCEEDED." text back on the screen.
        $assignment = $script:F83Ast.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$restoreDoneSummary' }, $true)
        $assignment | Should -Not -BeNullOrEmpty
        $assignment.Right.ElseClause.Statements[0].PipelineElements[0].Expression.Value | Should -BeExactly 'Restore complete.'
        $line = $script:F83Ast.Find({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$restoreDoneLine' }, $true)
        $line.Right.ElseClause.Statements[0].Extent.Text | Should -BeExactly '$restoreDoneSummary'
        $logCall = @($script:F83Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Write-Log' -and $node.Extent.Text -like '*Restore completed; outcome: *' }, $true))
        $logCall.Count | Should -BeGreaterThan 0
    }
}

Describe 'FIX83 item 13: Reset and Restore' {
    It 'words a restore point row with plain kind text and the right plural' -TestCases @(
        @{ Kind = 'Startup'; Words = 'Saved at start-up'; Files = 1; FilesText = '1 file' }
        @{ Kind = 'Baseline'; Words = 'First saved copy'; Files = 12; FilesText = '12 files' }
        @{ Kind = 'BeforeReset'; Words = 'Saved before a reset or restore'; Files = 0; FilesText = '0 files' }
    ) {
        param($Kind, $Words, $Files, $FilesText)
        # Mutation: bring back "made when TeknoParrot Manager started" and "file(s)", or lose the date.
        Mock Test-TpmRestorePointRecordHasGames { return $true }
        $point = New-F83RestorePoint -Kind $Kind -Files $Files
        $expectedWhen = $point.CreatedUtc.ToLocalTime().ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
        (Format-TpmRestorePointLabel -RestorePoint $point) | Should -BeExactly ('{0} - {1} - {2}' -f $expectedWhen, $Words, $FilesText)
    }

    It 'says when a restore point has no games in it' {
        # Mutation: drop the no-games note.
        Mock Test-TpmRestorePointRecordHasGames { return $false }
        (Format-TpmRestorePointLabel -RestorePoint (New-F83RestorePoint)) | Should -Match ' - 3 files - no games in it$'
    }

    It 'lists 5 restore points, the rest after M, and does not accept a hidden number' {
        # Mutation: list all 8 restore points at once.
        Mock Test-TpmRestorePointRecordHasGames { return $true }
        $points = @(1..8 | ForEach-Object { New-F83RestorePoint -Index $_ })
        Install-F83Mocks -Answers @('7', 'M', '7')
        $picked = Select-TpmRestorePoint -RestorePoints $points
        $picked.Id | Should -BeExactly 'P7'
        @(Get-F83Lines | Where-Object { $_ -like '*Invalid choice*' }).Count | Should -Be 1
        $firstScreen = @((Get-F83Lines)[0..($script:F83PromptRows[0] - 1)])
        @($firstScreen | Where-Object { $_ -match '^    \d\) ' }).Count | Should -Be 5
        $firstScreen | Should -Contain '    M) Show 3 more'
        $firstScreen | Should -Contain '  Restore points, newest first:'
    }

    It 'goes back without a restore point on B' {
        # Mutation: return the first restore point for B.
        Mock Test-TpmRestorePointRecordHasGames { return $true }
        Install-F83Mocks -Answers @('B')
        (Select-TpmRestorePoint -RestorePoints @(New-F83RestorePoint)) | Should -BeNullOrEmpty
    }

    It 'shows game names without the file name, shows the file name under Details, and asks the old questions' {
        # Mutation: print "Game A (GameA)" again, print the file line by default, or ask a different number of questions.
        $fx = New-F83ResetFixture -Codes @('G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7') -Names @{ G1 = 'Alpha'; G2 = 'N20 Stray'; G3 = 'Gamma'; G4 = 'Delta'; G5 = 'Epsilon'; G6 = 'Zeta'; G7 = 'Eta' }
        Mock Restore-TpmRestorePointGame { return [pscustomobject]@{ Outcome = 'SUCCEEDED'; ReasonCode = 'RESTORED'; Summary = 'ok' } }
        $plan = New-F83Plan -Changes @(1..7 | ForEach-Object { New-F83Change -Code ('G{0}' -f $_) })
        $point = New-F83RestorePoint
        Install-F83Mocks -Answers @('2', 'D', 'YES')
        $result = Invoke-TpmResetRestoreOneGame -RestorePoint $point -Plan $plan -UserProfilesDir $fx.Profiles -BackupPath $fx.Backup
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Should -Invoke Restore-TpmRestorePointGame -Times 1 -Exactly -ParameterFilter { $RelativePath -eq 'G2.xml' }
        $script:F83Prompts.Count | Should -Be 3
        $lines = @(Get-F83Lines)
        $lines | Should -Contain '    2) N20 Stray'
        $lines | Should -Contain '    M) Show 2 more'
        $lines | Should -Contain '  Game: N20 Stray'
        $beforeDetails = @($lines[0..($script:F83PromptRows[1] - 1)])
        ($beforeDetails -join "`n") | Should -Not -Match 'G2\.xml|\(G2\)|File:'
        @($lines[$script:F83PromptRows[1]..($lines.Count - 1)] | Where-Object { $_ -match '^    File:\s+UserProfiles\\G2\.xml$' }).Count | Should -Be 1
        (Get-F83Text) | Should -Match 'Its whole settings file goes back to how it was on \d{4}-\d{2}-\d{2} \d{2}:\d{2}\. That includes the game path, controls and every other setting\. Changes you made yourself since then are lost\.'
        $script:F83Prompts[2] | Should -BeLike '*Type YES to put this game back*'
    }

    It 'adds the file name to games that share a name, and words a removed settings file' {
        # Mutation: always show the name only -> two rows read the same; or word a removed file like a changed one.
        $fx = New-F83ResetFixture -Codes @('T1', 'T2', 'U1') -Names @{ T1 = 'Twin'; T2 = 'Twin'; U1 = 'Solo' }
        $plan = New-F83Plan -Changes @((New-F83Change -Code 'T1'), (New-F83Change -Code 'T2'), (New-F83Change -Code 'U1' -Change 'PutBack'))
        Install-F83Mocks -Answers @('B')
        $result = Invoke-TpmResetRestoreOneGame -RestorePoint (New-F83RestorePoint) -Plan $plan -UserProfilesDir $fx.Profiles -BackupPath $fx.Backup
        $result.ReasonCode | Should -BeExactly 'USER_CANCELLED'
        $lines = @(Get-F83Lines)
        $lines | Should -Contain '    1) Twin (T1)'
        $lines | Should -Contain '    2) Twin (T2)'
        $lines | Should -Contain '    3) Solo (its settings file was removed since then)'
    }

    It 'declines on anything but YES and then restores nothing' {
        # Mutation: restore before the YES question, or treat D as YES.
        $fx = New-F83ResetFixture -Codes @('G1')
        Mock Restore-TpmRestorePointGame { throw 'Nothing may be restored without YES.' }
        Install-F83Mocks -Answers @('1', 'no')
        $result = Invoke-TpmResetRestoreOneGame -RestorePoint (New-F83RestorePoint) -Plan (New-F83Plan -Changes @(New-F83Change -Code 'G1')) -UserProfilesDir $fx.Profiles -BackupPath $fx.Backup
        $result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        Should -Invoke Restore-TpmRestorePointGame -Times 0 -Exactly
    }

    It 'keeps the one-game screen short and inside the console at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the description, the file, the safety sentence and the question as one block.
        $fx = New-F83ResetFixture -Codes @('G1', 'G2')
        Install-F83Mocks -Width $Width -Answers @('1', 'no')
        $null = Invoke-TpmResetRestoreOneGame -RestorePoint (New-F83RestorePoint) -Plan (New-F83Plan -Changes @((New-F83Change -Code 'G1'), (New-F83Change -Code 'G2'))) -UserProfilesDir $fx.Profiles -BackupPath $fx.Backup
        $lines = @(Get-F83Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F83LongestRun -Rows $lines -Limit ($Width - 1)) | Should -BeLessOrEqual 5
    }

    It 'previews Restore all in counts, keeps the names under Details and counts the questions right' {
        # Mutation: list every game by default, print "item(s)", "file(s)" or "folder(s)" again, or drop the REMOVED warning.
        $codes = @(1..12 | ForEach-Object { 'R{0}' -f $_ }) + @('P1', 'P2', 'X1')
        $fx = New-F83ResetFixture -Codes $codes
        Mock Get-TpmRestoreAllBlocker { return $null }
        Mock Restore-TpmRestorePointAll { return [pscustomobject]@{ Outcome = 'SUCCEEDED'; ReasonCode = 'RESTORED'; Summary = 'ok'; RestartRequired = $false } }
        $changes = @(1..12 | ForEach-Object { New-F83Change -Code ('R{0}' -f $_) }) + @((New-F83Change -Code 'P1' -Change 'PutBack'), (New-F83Change -Code 'P2' -Change 'PutBack'), (New-F83Change -Code 'X1' -Change 'Remove'))
        $plan = New-F83Plan -Changes $changes -FoldersRemoved @('F1') -FoldersPutBack @('F2', 'F3') -ConfigChange 'Replace'
        Install-F83Mocks -Answers @('D', 'YES')
        $result = Invoke-TpmResetRestoreAllGames -RestorePoint (New-F83RestorePoint) -Plan $plan -UserProfilesDir $fx.Profiles -BackupPath $fx.Backup
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Should -Invoke Restore-TpmRestorePointAll -Times 1 -Exactly
        $lines = @(Get-F83Lines)
        $firstQuestion = @($lines[0..($script:F83PromptRows[0] - 1)])
        $screen = ((@($firstQuestion) -join ' ') -replace '\s+', ' ')
        $screen | Should -Match '- 12 settings files go back to how they were then\.'
        $screen | Should -Match '- 2 settings files were removed since then and are put back\.'
        $screen | Should -Match '- 1 file was added after that restore point and is REMOVED from UserProfiles\. The restore point made first keeps a copy\.'
        $screen | Should -Match '- 3 folders inside UserProfiles are also put back or removed to match\.'
        $screen | Should -Match 'TeknoParrot Manager''s own settings also go back to how they were then\.'
        $screen | Should -Not -Match 'Game R1|Game P1|Game X1|\(s\)'
        @($lines[$script:F83PromptRows[0]..($lines.Count - 1)] | Where-Object { $_ -eq '    Game R1' }).Count | Should -BeGreaterThan 0
        @($lines | Where-Object { $_ -eq '    Game X1' }).Count | Should -BeGreaterThan 0
        $script:F83Prompts[1] | Should -BeLike '*Type YES to put everything back*'
        (Get-F83Text) | Should -Match 'This changes 19 items in total'
        $script:F83Prompts.Count | Should -Be 2
    }

    It 'uses the singular for a count of 1 settings file, 1 folder and 2 items' {
        # Mutation: use the plural noun for a count of 1.
        $fx = New-F83ResetFixture -Codes @('R1')
        Mock Get-TpmRestoreAllBlocker { return $null }
        Mock Restore-TpmRestorePointAll { throw 'Declined: nothing may be restored.' }
        Install-F83Mocks -Answers @('no')
        $plan = New-F83Plan -Changes @(New-F83Change -Code 'R1') -FoldersPutBack @('F1') -ConfigChange 'Same'
        $result = Invoke-TpmResetRestoreAllGames -RestorePoint (New-F83RestorePoint) -Plan $plan -UserProfilesDir $fx.Profiles -BackupPath $fx.Backup
        $result.ReasonCode | Should -BeExactly 'USER_DECLINED'
        $text = Get-F83Text
        $text | Should -Match '- 1 settings file goes back to how it was then\.'
        $text | Should -Match '- 1 folder inside UserProfiles is also put back or removed to match\.'
        $text | Should -Match 'This changes 2 items in total'
        $text | Should -Match 'TeknoParrot Manager''s own settings already match and are not changed\.'
    }

    It 'keeps the Restore all preview short and inside the console at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the groups, the folder and settings lines and the safety sentences without blank lines between them.
        $fx = New-F83ResetFixture -Codes @('R1', 'P1', 'X1')
        Mock Get-TpmRestoreAllBlocker { return $null }
        $changes = @((New-F83Change -Code 'R1'), (New-F83Change -Code 'P1' -Change 'PutBack'), (New-F83Change -Code 'X1' -Change 'Remove'))
        $plan = New-F83Plan -Changes $changes -FoldersRemoved @('F1') -ConfigChange 'Replace'
        Install-F83Mocks -Width $Width -Answers @('no')
        $null = Invoke-TpmResetRestoreAllGames -RestorePoint (New-F83RestorePoint) -Plan $plan -UserProfilesDir $fx.Profiles -BackupPath $fx.Backup
        $lines = @(Get-F83Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F83LongestRun -Rows $lines -Limit ($Width - 1)) | Should -BeLessOrEqual 5
    }

    It 'lists 5 older restore points to remove, the rest under Details, and uses the right plural: <Count>' -TestCases @(
        @{ Count = 1; Summary = '1 older restore point was removed.'; Have = 'You have 4 restore points'; Answers = @('YES') }
        @{ Count = 8; Summary = '8 older restore points were removed.'; Have = 'You have 4 restore points'; Answers = @('D', 'YES') }
    ) {
        param($Count, $Summary, $Have, $Answers)
        # Mutation: list every restore point by default, or print "restore point(s)" again.
        Mock Select-TpmRestorePointsForFolder { return [pscustomobject]@{ Current = @($RestorePoints) } }
        Mock Get-TpmRestorePointKeepCount { return 3 }
        Mock Get-TpmRestorePointRemovalCandidates { return @($script:F83Candidates) }
        Mock Format-TpmRestorePointLabel { return ('Label of ' + $RestorePoint.Id) }
        Mock Remove-TpmRestorePoint { return [pscustomobject]@{ Removed = $true; Reason = $null } }
        $script:F83Candidates = @(1..$Count | ForEach-Object { New-F83RestorePoint -Index $_ })
        Install-F83Mocks -Answers $Answers
        $result = Invoke-TpmRestorePointCleanup -RestorePoints @(1..4 | ForEach-Object { New-F83RestorePoint -Index (20 + $_) }) -UserProfilesDir (Join-Path $TestDrive 'profiles')
        $result.Summary | Should -BeExactly $Summary
        $result.ReasonCode | Should -BeExactly 'REMOVED'
        $lines = @(Get-F83Lines)
        (Get-F83Text) | Should -Match ([regex]::Escape($Have) + ' for this TeknoParrot folder, using about')
        (Get-F83Text) | Should -Not -Match '\(s\)'
        $beforeQuestion = @($lines[0..($script:F83PromptRows[0] - 1)])
        @($beforeQuestion | Where-Object { $_ -like '    - Label of *' }).Count | Should -Be ([Math]::Min(5, $Count))
        if ($Count -gt 5) {
            $beforeQuestion | Should -Contain ('  Older restore points that would be removed (first 5 of {0}):' -f $Count)
            @($lines | Where-Object { $_ -like '    Label of *' }).Count | Should -Be $Count
        } else {
            $beforeQuestion | Should -Contain '  Older restore points that would be removed:'
        }
    }

    It 'keeps the restore points of another folder behind Details and counts them right' {
        # Mutation: print the folders again, or say "restore point(s)".
        Mock Test-TpmRestorePointRecordHasGames { return $true }
        $points = @((New-F83RestorePoint -Index 1 -Folder 'D:\Moved\UserProfiles'), (New-F83RestorePoint -Index 2 -Folder 'E:\Other\UserProfiles'))
        Install-F83Mocks
        Write-TpmRestorePointOtherFolderNote -RestorePoints $points
        $text = Get-F83Text
        $text | Should -Match '2 restore points made for another TeknoParrot folder, not used here\.'
        $text | Should -Not -Match 'D:\\Moved|E:\\Other|\(s\)'
        Install-F83Mocks
        Write-TpmRestorePointOtherFolderNote -RestorePoints @($points[0])
        (Get-F83Text) | Should -Match '1 restore point made for another TeknoParrot folder, not used here\.'
        $blocks = @(Get-TpmRestorePointOtherFolderBlocks -RestorePoints $points)
        $blocks.Count | Should -Be 2
        $blocks[0].Lines[0] | Should -BeExactly 'Made for: D:\Moved\UserProfiles'
        $blocks[1].Lines[0] | Should -BeExactly 'Made for: E:\Other\UserProfiles'
    }
}

Describe 'FIX83 item 18: Check for Updates' {
    BeforeEach {
        $script:F83UpdatePath = Join-Path $TestDrive ('update-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.ps1')
        Set-Content -LiteralPath $script:F83UpdatePath -Value ('$ScriptVersion = "1.0"' + "`n" + '$ReleaseCandidateLabel = "RC8"') -Encoding ascii
    }

    It 'says "You have the newest version" for a version that is newer than the latest release' {
        # Mutation: print the two version rows and "You're already running the latest version" again -> RC8 and RC7 look contradictory.
        Install-F83Mocks
        Mock Get-ManagerUpdateRelease { return [pscustomobject]@{ TagName = 'v1.0-RC7'; Name = 'v1.0 RC7'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.0-RC7/x.zip'; SizeBytes = 1; Digest = ('sha256:' + ('0' * 64)) } }
        Mock Read-Host { throw 'No question may be asked when no update is needed.' }
        $result = Invoke-CheckForUpdates -ScriptPath $script:F83UpdatePath
        $result.Outcome | Should -BeExactly 'NO_OP'
        $result.ReasonCode | Should -BeExactly 'UPDATE_ALREADY_CURRENT'
        $lines = @(Get-F83Lines)
        $lines | Should -Contain '  You have the newest version (v1.0 RC8).'
        $lines | Should -Contain '  No update needed.'
        $lines | Should -Contain '  The latest public release is v1.0 RC7, which is older.'
        (Get-F83Text) | Should -Not -Match 'Current version|Latest version|already running'
        $script:F83Log | Should -Contain 'CheckForUpdates: current v1.0 RC8, latest v1.0 RC7, comparison 1.'
    }

    It 'says only that you have the newest version when the versions are the same' {
        # Mutation: always print the line about an older public release.
        Install-F83Mocks
        Mock Get-ManagerUpdateRelease { return [pscustomobject]@{ TagName = 'v1.0-RC8'; Name = 'v1.0 RC8'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.0-RC8/x.zip'; SizeBytes = 1; Digest = ('sha256:' + ('0' * 64)) } }
        Mock Read-Host { throw 'No question may be asked when no update is needed.' }
        $result = Invoke-CheckForUpdates -ScriptPath $script:F83UpdatePath
        $result.ReasonCode | Should -BeExactly 'UPDATE_ALREADY_CURRENT'
        $lines = @(Get-F83Lines)
        $lines | Should -Contain '  You have the newest version (v1.0 RC8).'
        @($lines | Where-Object { $_ -like '*older*' }).Count | Should -Be 0
    }

    It 'still offers an update when a newer release exists and does not call it the newest version' {
        # Mutation: treat every release as not newer.
        Install-F83Mocks -Answers @('N')
        Mock Get-ManagerUpdateRelease { return [pscustomobject]@{ TagName = 'v1.0-RC9'; Name = 'v1.0 RC9'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v1.0-RC9/x.zip'; SizeBytes = 1; Digest = ('sha256:' + ('0' * 64)) } }
        $result = Invoke-CheckForUpdates -ScriptPath $script:F83UpdatePath
        $result.ReasonCode | Should -BeExactly 'UPDATE_DECLINED'
        (Get-F83Text) | Should -Match 'An update is available: v1\.0 RC8 -> v1\.0 RC9'
        (Get-F83Text) | Should -Not -Match 'You have the newest version'
    }
}

Describe 'FIX83 item 19: Help' {
    It 'puts one clause on each line, groups the lines and keeps the two facts about Administrator approval' {
        # Mutation: put the 108 character Administrator approval sentence back on one line, or drop the blank lines between the groups.
        $lines = @(Get-MainMenuHelpLines)
        ($lines -join "`n") | Should -Not -Match 'it does not confirm that installation or repair succeeded'
        $lines | Should -Contain '     Administrator approval lets setup try to continue.'
        $lines | Should -Contain '     It does not mean the setup worked.'
        @($lines | Where-Object { $_ -eq '' }).Count | Should -BeGreaterOrEqual 3
        (Get-F83LongestRun -Rows $lines -Limit 100) | Should -BeLessOrEqual 5
        foreach ($line in @($lines | Where-Object { $_ -ne '' })) { (($line.Trim() -split '\s+').Count) | Should -BeLessOrEqual 15 -Because $line }
    }

    It 'prints the Help screen wrapped, with the text of a numbered line under its own text at <Width> columns' -TestCases @(
        @{ Width = 40 }, @{ Width = 60 }, @{ Width = 120 }
    ) {
        param($Width)
        # Mutation: print the lines with Write-Host as they are -> a line is wider than the console and a wrapped line starts under its number.
        Mock Clear-ConsoleForFreshRender {}
        Install-F83Mocks -Width $Width -Answers @('')
        Show-MainMenuHelp
        $lines = @(Get-F83Lines)
        @($lines | Where-Object { $_.Length -ge $Width }).Count | Should -Be 0
        (Get-F83LongestRun -Rows $lines -Limit ($Width - 1)) | Should -BeLessOrEqual 5
        $script:F83Prompts.Count | Should -Be 1
        $script:F83Prompts[0] | Should -BeLike '*Press Enter to return*'
        $lines | Should -Contain 'TeknoParrot Manager Help'
        $text = Get-F83Text
        $text | Should -Not -Match 'Press Enter to return to the main menu'
        $text | Should -Match '1 AutoSync: extract your game ZIPs, then register the games\.'
        $wrapped = @($lines | Where-Object { $_ -match '^  1 AutoSync' })
        $wrapped.Count | Should -Be 1
        if ($Width -le 60) {
            $index = [array]::IndexOf($lines, $wrapped[0])
            $lines[$index + 1] | Should -Match '^    \S'
        }
    }
}
