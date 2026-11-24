#Requires -Module Pester

# What a user sees or loses: the read-only validation report (exit code, what it says, that it writes nothing),
# the RawInput supported / unsupported / unknown reading, and the PostgreSQL offer after a game is registered.
# Isolated fixtures under $TestDrive only.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'report-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding UTF8
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC9.3'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC9.3'
    $script:logPath = Join-Path $TestDrive 'must-not-exist.log'
    $script:logWarnShown = $false
    $script:productRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:productScript = (Resolve-Path $scriptPath).Path

    function New-ProfileXml {
        param([string]$GamePath = '', [string[]]$ApiOptions = @(), [switch]$RawButton, [switch]$Postgres, [switch]$PostgresComplete, [string]$Extra = '', [string]$Storage = '')
        $api = if ($ApiOptions.Count -gt 0) { '<FieldInformation><FieldName>Input API</FieldName><FieldValue>XInput</FieldValue><FieldOptions>' + (($ApiOptions | ForEach-Object { "<string>$_</string>" }) -join '') + '</FieldOptions></FieldInformation>' } else { '' }
        $pg = ''
        if ($Storage -ne '') { $pg += "<FieldInformation><CategoryName>Database</CategoryName><FieldName>Storage</FieldName><FieldValue>$Storage</FieldValue></FieldInformation>" }
        if ($Postgres) {
            foreach ($n in 'DbName', 'Path', 'Address', 'Port', 'User', 'Pass') {
                $v = if ($PostgresComplete) { 'x' } else { '' }
                $pg += "<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>$n</FieldName><FieldValue>$v</FieldValue></FieldInformation>"
            }
        }
        $btn = if ($RawButton) { '<JoystickButtons><ButtonName>Test</ButtonName><RawInputButton><DeviceName>pad</DeviceName></RawInputButton></JoystickButtons>' } else { '<JoystickButtons><ButtonName>Test</ButtonName></JoystickButtons>' }
        $x = New-Object System.Xml.XmlDocument
        $x.LoadXml("<GameProfile><GameName>Game $GamePath</GameName><GamePath>$GamePath</GamePath><ConfigValues>$api$pg</ConfigValues><JoystickButtons>$btn</JoystickButtons>$Extra</GameProfile>")
        return $x
    }

    function New-TpFixture {
        $root = Join-Path $TestDrive ('tp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $root 'GameProfiles'), (Join-Path $root 'UserProfiles') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'TeknoParrotUi.exe') -Value 'x'
        Set-Content -LiteralPath (Join-Path $root 'ParrotData.xml') -Value '<ParrotData><FirstTimeSetupComplete>true</FirstTimeSetupComplete></ParrotData>'
        Set-Content -LiteralPath (Join-Path $root 'GameProfiles\Game1.xml') -Value '<GameProfile/>'
        return $root
    }

    function Save-Profile {
        param([string]$Root, [string]$Code, $Doc)
        $Doc.Save((Join-Path $Root "UserProfiles\$Code.xml"))
    }

    function Save-Settings {
        param([string]$Root)
        $cfg = Get-TpmOwnedConfigPathForRoot -TeknoParrotRoot $Root
        New-Item -ItemType Directory -Path (Split-Path -Parent $cfg) -Force | Out-Null
        Set-Content -LiteralPath $cfg -Value ('{"TeknoParrotRoot":"' + ($Root -replace '\\', '\\') + '","GamesInstallFolder":"x","PostgresSuperPasswordEncrypted":"SECRET-BLOB"}')
    }

    function Get-Snapshot {
        param([string]$Path)
        # Files: name, size and write time. Folders: name only (Windows may update a folder's own time late, which is not a change by the report).
        @(Get-ChildItem -LiteralPath $Path -Recurse -Force | ForEach-Object { if ($_.PSIsContainer) { 'D|{0}' -f $_.FullName } else { 'F|{0}|{1}|{2}' -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks } }) -join "`n"
    }
}

Describe 'RawInput / RawInputTrackball support reading' {
    It 'says Supported when a button already uses RawInput' {
        (Get-ProfileRawInputCapability -Doc (New-ProfileXml -RawButton)).RawInput | Should -Be 'Supported'
    }
    It 'says Supported when the Input API lists RawInput, Unsupported when it lists other options only' {
        (Get-ProfileRawInputCapability -Doc (New-ProfileXml -ApiOptions 'XInput', 'RawInput')).RawInput | Should -Be 'Supported'
        $other = Get-ProfileRawInputCapability -Doc (New-ProfileXml -ApiOptions 'XInput', 'DirectInput')
        $other.RawInput | Should -Be 'Unsupported'
        $other.RawInputTrackball | Should -Be 'Unsupported'
    }
    It 'says Unknown for an older profile with no Input API field' {
        $old = Get-ProfileRawInputCapability -Doc (New-ProfileXml)
        $old.RawInput | Should -Be 'Unknown'
        $old.RawInputTrackball | Should -Be 'Unknown'
    }
    It 'says RawInputTrackball Supported only when the profile names it exactly' {
        (Get-ProfileRawInputCapability -Doc (New-ProfileXml -ApiOptions 'XInput', 'RawInput' -Extra '<RawInputTrackball/>')).RawInputTrackball | Should -Be 'Supported'
        (Get-ProfileRawInputCapability -Doc (New-ProfileXml -ApiOptions 'XInput', 'RawInput' -Extra '<RawInputTrackballButtonV2/>')).RawInputTrackball | Should -Be 'Unknown'
    }
}

Describe 'Validation report' {
    BeforeEach {
        Mock Find-TpmSavedConfigPath { Join-Path $TestDrive 'no-such-settings.json' }
        Mock Get-CompatibilityWarnings { [pscustomobject]@{ PathTooLong = @(); DllMismatch = @(); GpuIncompatible = @(); BiosMissing = @(); ExeMissing = @() } }
        Mock Write-Host {}
    }
    AfterEach { $script:TpmValidationReportActive = $false }

    It 'passes with exit code 0 for a healthy folder and never shows the saved password' {
        $root = New-TpFixture
        Save-Settings -Root $root
        $good = Join-Path $root 'Games\a.exe'
        New-Item -ItemType Directory -Path (Split-Path $good) -Force | Out-Null
        Set-Content -LiteralPath $good -Value 'x'
        Save-Profile -Root $root -Code 'Game1' -Doc (New-ProfileXml -GamePath $good -ApiOptions 'XInput', 'RawInput')
        $json = Join-Path $TestDrive 'report.json'
        $code = Invoke-TpmValidationReport -ScriptPath $productScript -ScriptRoot $productRoot -TeknoParrotRoot $root -JsonPath $json
        $code | Should -Be 0
        $report = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $report.Result | Should -Be 'Pass'
        $report.Library.Registered | Should -Be 1
        $report.RawInput.RawInput.Supported | Should -Be 1
        $report.Settings.SavedPostgresPassword | Should -BeTrue
        (Get-Content -LiteralPath $json -Raw) | Should -Not -Match 'SECRET-BLOB'
        $report.Manager.ScriptSha256 | Should -Be (Get-FileHash -LiteralPath $productScript -Algorithm SHA256).Hash
    }

    It 'fails with exit code 4 when the TeknoParrot folder is missing' {
        (Invoke-TpmValidationReport -ScriptPath $productScript -ScriptRoot $productRoot -TeknoParrotRoot (Join-Path $TestDrive 'nowhere')) | Should -Be 4
    }

    It 'asks for action (exit code 3) for a missing game file, a game without PostgreSQL settings and no saved settings' {
        $root = New-TpFixture
        Save-Profile -Root $root -Code 'Game1' -Doc (New-ProfileXml -GamePath (Join-Path $TestDrive 'gone.exe') -Postgres)
        $json = Join-Path $TestDrive 'action.json'
        (Invoke-TpmValidationReport -ScriptPath $productScript -ScriptRoot $productRoot -TeknoParrotRoot $root -JsonPath $json) | Should -Be 3
        $report = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $report.Library.NoGameFile | Should -Be 1
        $report.Library.PostgresNotSetUp | Should -Be 1
        $report.Settings.State | Should -Be 'None'
    }

    It 'changes nothing in the TeknoParrot folder and writes no log' {
        $root = New-TpFixture
        Save-Profile -Root $root -Code 'Game1' -Doc (New-ProfileXml -GamePath 'x' -Postgres)
        $before = Get-Snapshot -Path $root
        [void](Invoke-TpmValidationReport -ScriptPath $productScript -ScriptRoot $productRoot -TeknoParrotRoot $root)
        Write-Log 'must not be written'
        (Get-Snapshot -Path $root) | Should -Be $before
        Test-Path -LiteralPath $script:logPath | Should -BeFalse
    }

    It 'leaves a file that is not a validation report alone and reports exit code 1' {
        $root = New-TpFixture
        $foreign = Join-Path $TestDrive 'notes.json'
        Set-Content -LiteralPath $foreign -Value 'my notes'
        (Invoke-TpmValidationReport -ScriptPath $productScript -ScriptRoot $productRoot -TeknoParrotRoot $root -JsonPath $foreign) | Should -Be 1
        (Get-Content -LiteralPath $foreign -Raw).Trim() | Should -Be 'my notes'
    }
}

Describe 'PostgreSQL offer after registration' {
    BeforeEach {
        Mock Write-Host {}
        Mock Write-Log {}
        Mock Test-PostgresInstalled { $true }
        Mock Read-TpmYesNo { 'Y' }
    }

    It 'offers setup for a newly registered game that has no PostgreSQL settings, and says yes' {
        $root = New-TpFixture
        Save-Profile -Root $root -Code 'GameA' -Doc (New-ProfileXml -GamePath 'a' -Postgres)
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir (Join-Path $root 'UserProfiles') -RegisteredCodes @('GameA')) | Should -BeTrue
        Should -Invoke Read-TpmYesNo -Times 1 -Exactly
    }

    It 'returns false and tells the user nothing changed when they say no' {
        Mock Read-TpmYesNo { 'N' }
        $root = New-TpFixture
        Save-Profile -Root $root -Code 'GameA' -Doc (New-ProfileXml -GamePath 'a' -Postgres)
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir (Join-Path $root 'UserProfiles') -RegisteredCodes @('GameA')) | Should -BeFalse
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Nothing was changed*' } -Times 1
    }

    It 'does not ask when the new game does not need PostgreSQL, is already set up, was not just registered, or the run is unattended or a preview' {
        $root = New-TpFixture
        $profiles = Join-Path $root 'UserProfiles'
        Save-Profile -Root $root -Code 'Plain' -Doc (New-ProfileXml -GamePath 'p')
        Save-Profile -Root $root -Code 'Done' -Doc (New-ProfileXml -GamePath 'd' -Postgres -PostgresComplete)
        Save-Profile -Root $root -Code 'Old' -Doc (New-ProfileXml -GamePath 'o' -Postgres)
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir $profiles -RegisteredCodes @('Plain', 'Done')) | Should -BeFalse
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir $profiles -RegisteredCodes @('Old') -Unattended) | Should -BeFalse
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir $profiles -RegisteredCodes @('Old') -DryRun) | Should -BeFalse
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
    }

    # Mutation: ignore Storage -> a game set to Internal is offered a PostgreSQL install it does not need.
    It 'does not offer PostgreSQL for a new Internal game, and says plainly that no database install is needed' {
        $root = New-TpFixture
        Save-Profile -Root $root -Code 'GameA' -Doc (New-ProfileXml -GamePath 'a' -Postgres -Storage 'Internal')
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir (Join-Path $root 'UserProfiles') -RegisteredCodes @('GameA')) | Should -BeFalse
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*no database install is needed*started once*' } -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Existing PostgreSQL is for keeping an existing PostgreSQL server and its saved progress*' } -Times 1
    }

    # Mutation: skip every game that has a Storage field -> a game set to Existing PostgreSQL is no longer offered setup.
    It 'still offers setup for a new game set to Existing PostgreSQL, and says nothing is switched for the user' {
        $root = New-TpFixture
        Save-Profile -Root $root -Code 'GameA' -Doc (New-ProfileXml -GamePath 'a' -Postgres -Storage 'Existing PostgreSQL')
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir (Join-Path $root 'UserProfiles') -RegisteredCodes @('GameA')) | Should -BeTrue
        Should -Invoke Read-TpmYesNo -Times 1 -Exactly
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Internal, needs no database install; nothing is switched for you*' } -Times 1
    }

    It 'says PostgreSQL is already on this PC when it is, and offers to install it when it is not' {
        $root = New-TpFixture
        Save-Profile -Root $root -Code 'GameA' -Doc (New-ProfileXml -GamePath 'a' -Postgres)
        $profiles = Join-Path $root 'UserProfiles'
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir $profiles -RegisteredCodes @('GameA')) | Should -BeTrue
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*PostgreSQL is already on this PC*' } -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*is not on this PC yet*' } -Times 0
        Mock Test-PostgresInstalled { $false }
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir $profiles -RegisteredCodes @('GameA')) | Should -BeTrue
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*is not on this PC yet*' } -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*can install it and set up the game now*' } -Times 1
    }

    It 'counts the other games that still need settings, says the finished ones are left alone, and never changes a profile when declined' {
        Mock Read-TpmYesNo { 'N' }
        $root = New-TpFixture
        $profiles = Join-Path $root 'UserProfiles'
        Save-Profile -Root $root -Code 'GameA' -Doc (New-ProfileXml -GamePath 'a' -Postgres)
        Save-Profile -Root $root -Code 'GameB' -Doc (New-ProfileXml -GamePath 'b' -Postgres)
        Save-Profile -Root $root -Code 'GameC' -Doc (New-ProfileXml -GamePath 'c' -Postgres -PostgresComplete)
        $before = Get-Snapshot -Path $profiles
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir $profiles -RegisteredCodes @('GameA')) | Should -BeFalse
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*1 other game(s) already registered also still need PostgreSQL settings*' } -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*1 game(s) are already set up and will not be touched*' } -Times 1
        Get-Snapshot -Path $profiles | Should -Be $before
    }

    It 'in a preview says which games would need PostgreSQL and a password, asks nothing and writes nothing' {
        $root = New-TpFixture
        $profiles = Join-Path $root 'UserProfiles'
        $templates = Join-Path $root 'GameProfiles'
        (New-ProfileXml -GamePath 'a' -Postgres).Save((Join-Path $templates 'GameA.xml'))
        $before = Get-Snapshot -Path $root
        (Invoke-TpmPostgresRegistrationOffer -UserProfilesDir $profiles -RegisteredCodes @('GameA') -GameProfilesDir $templates -DryRun) | Should -BeFalse
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*[[]Preview] 1 game(s) would need PostgreSQL setup: Game a*' } -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*password would be needed*' } -Times 1
        Get-Snapshot -Path $root | Should -Be $before
    }
}
