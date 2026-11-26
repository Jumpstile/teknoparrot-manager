#Requires -Module Pester

# A TeknoParrot update adds games and changes many profiles (new fields such as HideCursor, an Outputs dropdown with VisibleWhen, higher
# GameProfileRevision numbers). TeknoParrot Manager must handle all of it with no change of its own. These tests build a TeknoParrot folder in
# TestDrive from the 70 real profiles of testdata\teknoparrot-new-profiles-facts.json (code, EmulatorType, ExecutableName and revision exactly as
# TeknoParrot 1.0.0.2337 wrote them; the profile settings are only a stand-in) with a matching game file for each, and run the real registration,
# the real Game Notes builder and the real update check.
# What this CANNOT prove: that a game starts, or how the real console paints the notice.

BeforeAll {
    $sourcePath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')" }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionPath = Join-Path $TestDrive 'fix431-functions.ps1'
    [System.IO.File]::WriteAllText($functionPath, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionPath

    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:RawThrillsPathLimits = @{}
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'), [System.StringComparer]::OrdinalIgnoreCase)
    $script:fix431Log = New-Object System.Collections.Generic.List[string]
    function Write-Log { param([string]$msg) [void]$script:fix431Log.Add($msg) }
    function Write-Host { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Test-TpmRegistrationLedgerConfigured { return $false }
    function Test-TpmRegistrationLedgerStopped { return $false }
    function Start-TpmRegistrationMapping { param([Parameter(ValueFromRemainingArguments)]$Ignored) return $null }
    function Complete-TpmRegistrationMapping { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Add-TpmRegistrationMappingFailure { param([Parameter(ValueFromRemainingArguments)]$Ignored) }
    function Get-TpmRegisteredProfileFilesWithDiscoveryProgress {
        param([string]$UserProfilesDir, [string]$ProgressLabel, [string]$EnumerationErrorAction)
        return @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    }

    $script:fix431Facts = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\testdata\teknoparrot-new-profiles-facts.json') -Raw | ConvertFrom-Json
    # Builds a TeknoParrot folder with one profile per real row (EmulatorType, ExecutableName and revision exactly as TeknoParrot wrote them) and a
    # games folder with one folder per profile code holding one file named by the profile. A name with several alternatives ("game|game.bin",
    # "hydro.chd;hydro_101b.chd") gets the alternative at $Alt, so both ways to name the file are run through the real registration.
    function Invoke-Fix431Registration {
        param([string]$Name, [int]$Alt)
        $root = Join-Path $TestDrive $Name
        $run = @{ Tp = (Join-Path $root 'TeknoParrot'); Games = (Join-Path $root 'Games'); Files = @{} }
        $run.GameProfiles = Join-Path $run.Tp 'GameProfiles'
        $run.UserProfiles = Join-Path $run.Tp 'UserProfiles'
        $run.Metadata = Join-Path $run.Tp 'Metadata'
        New-Item -ItemType Directory -Path $run.GameProfiles, $run.UserProfiles, $run.Metadata, $run.Games -Force | Out-Null
        $profileSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($profile in $script:fix431Facts.Profiles) {
            # The newer profile shape: HideCursor and an Outputs dropdown that is only visible for one setting, and a higher revision number.
            $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile><GameName>{0}</GameName><GamePath></GamePath><EmulatorType>{1}</EmulatorType><ExecutableName>{2}</ExecutableName><GameProfileRevision>{3}</GameProfileRevision>' -f $profile.Code, $profile.EmulatorType, $profile.ExecutableName, $profile.GameProfileRevision
            $xml += '<ConfigValues>'
            $xml += '<FieldInformation><CategoryName>General</CategoryName><FieldName>HideCursor</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>'
            $xml += '<FieldInformation><CategoryName>General</CategoryName><FieldName>Outputs</FieldName><FieldType>Dropdown</FieldType><FieldValue>None</FieldValue><FieldOptions><string>None</string><string>Network</string></FieldOptions><VisibleWhen>HideCursor=1</VisibleWhen></FieldInformation>'
            $xml += '</ConfigValues><JoystickButtons><JoystickButtons><ButtonName>Start</ButtonName><InputMapping>P1ButtonStart</InputMapping><AnalogType>None</AnalogType><VisibleWhen>Outputs=Network</VisibleWhen></JoystickButtons></JoystickButtons></GameProfile>'
            [System.IO.File]::WriteAllText((Join-Path $run.GameProfiles ($profile.Code + '.xml')), $xml)
            [void]$profileSet.Add($profile.Code)
            $names = @($profile.ExecutableName -split '[;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
            $gameFile = Join-Path (Join-Path $run.Games $profile.Code) $names[[Math]::Min($Alt, $names.Count - 1)]
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($gameFile))
            [System.IO.File]::WriteAllText($gameFile, 'x')
            $run.Files[$profile.Code] = $gameFile
        }
        $profileIndex = Build-ProfileIndex $run.GameProfiles
        # No DAT entry for any of these games: only the game file name and the profile list decide.
        $run.Result = Register-GamesLegacy -userProfilesDir $run.UserProfiles -installFolder $run.Games -profileIndex $profileIndex -gameProfilesDir $run.GameProfiles `
            -datIndex @{} -profileSet $profileSet -DryRun $false -tpRootDir $run.Tp -subFolderMap @{} -BackupState @{ Backup = $null; Done = $true; Error = $null }
        return $run
    }
    $script:fix431Run0 = Invoke-Fix431Registration -Name 'fix431' -Alt 0
    $script:fix431Run1 = Invoke-Fix431Registration -Name 'fix431b' -Alt 1
    $script:fix431Tp = $script:fix431Run0.Tp
    $script:fix431GameProfiles = $script:fix431Run0.GameProfiles
    $script:fix431UserProfiles = $script:fix431Run0.UserProfiles
    $script:fix431Metadata = $script:fix431Run0.Metadata
    $script:fix431Result = $script:fix431Run0.Result
}

Describe 'Games TeknoParrot adds later register and get notes with no TeknoParrot Manager change' {
    It 'registers every one of the 70 real profiles from its game file name and a folder named after the profile code, whichever alternative of the name the file uses, and keeps the profile as TeknoParrot wrote it' {
        @($script:fix431Facts.Profiles).Count | Should -Be 70
        foreach ($run in @($script:fix431Run0, $script:fix431Run1)) {
            $registered = @{}
            foreach ($item in @($run.Result.Registered)) { $registered[[string]$item.Code] = [string]$item.GamePath }
            $missing = @($script:fix431Facts.Profiles | Where-Object { -not $registered.ContainsKey([string]$_.Code) } | ForEach-Object { [string]$_.Code })
            ($missing -join ',') | Should -BeExactly ''
            $wrong = @($script:fix431Facts.Profiles | Where-Object { $registered[[string]$_.Code] -ne $run.Files[[string]$_.Code] } | ForEach-Object { [string]$_.Code })
            ($wrong -join ',') | Should -BeExactly ''
            $registered.Count | Should -Be 70
            @($run.Result.MutationRecords.Failures).Count | Should -Be 0
            foreach ($profile in $script:fix431Facts.Profiles) {
                $doc = New-Object System.Xml.XmlDocument
                $doc.Load((Join-Path $run.UserProfiles ($profile.Code + '.xml')))
                [string]$doc.GameProfile.EmulatorType | Should -BeExactly ([string]$profile.EmulatorType)
                [string]$doc.GameProfile.ExecutableName | Should -BeExactly ([string]$profile.ExecutableName)
                [string]$doc.GameProfile.GameProfileRevision | Should -BeExactly ([string]$profile.GameProfileRevision)
                [string]$doc.GameProfile.GamePath | Should -BeExactly $run.Files[[string]$profile.Code]
            }
        }
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load((Join-Path $script:fix431UserProfiles 'GoldenTeeLive2026.xml'))
        $doc.SelectSingleNode('/GameProfile/ConfigValues/FieldInformation[FieldName="Outputs"]/VisibleWhen').InnerText | Should -Be 'HideCursor=1'
        $doc.SelectSingleNode('/GameProfile/JoystickButtons/JoystickButtons/VisibleWhen').InnerText | Should -Be 'Outputs=Network'
    }

    It 'copies only the named input settings between games and leaves the new fields alone' {
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load((Join-Path $script:fix431UserProfiles 'IgsSpeedRider.xml'))
        (Set-ConfigField $doc 'HideCursor' '1') | Should -BeTrue
        (Set-ConfigField $doc 'NoSuchField' '1') | Should -BeFalse
        $doc.SelectSingleNode('/GameProfile/ConfigValues/FieldInformation[FieldName="HideCursor"]/FieldValue').InnerText | Should -Be '1'
        $doc.SelectSingleNode('/GameProfile/ConfigValues/FieldInformation[FieldName="Outputs"]/FieldValue').InnerText | Should -Be 'None'
        $doc.SelectSingleNode('/GameProfile/ConfigValues/FieldInformation[FieldName="Outputs"]/VisibleWhen').InnerText | Should -Be 'HideCursor=1'
        (Get-ProfileFamily $doc) | Should -Be 'button'
    }

    It 'gives a registered game with no recorded notes a plain entry, and shows TeknoParrot''s own text for it (marked as TeknoParrot''s)' {
        Set-Content -LiteralPath (Join-Path $script:fix431Metadata 'GoldenTeeLive2026.json') -Value '{"game_name":"Golden Tee Live 2026","platform":"PC","release_year":"2026","general_issues":"Needs a trackball.\nRun as administrator."}'
        Set-Content -LiteralPath (Join-Path $script:fix431Metadata 'IgsSpeedRider.json') -Value '{ this is not json'
        [System.IO.File]::WriteAllText((Join-Path $script:fix431Metadata 'IgsSpeedRider2.json'), ('{"general_issues":"' + ('x' * 300000) + '"}'))
        function Get-EggmanGameData { return @([pscustomobject]@{ profile_name = 'SomeOtherGame'; game_name = 'Some Other Game'; setup_exe = 'o.exe'; notes = 'Other.' }) }
        $notes = @(Get-GameSetupNotes -UserProfilesDir $script:fix431UserProfiles -TeknoParrotRoot $script:fix431Tp)
        @($notes).Count | Should -Be @($script:fix431Facts.Profiles).Count
        $known = $notes | Where-Object { $_.Code -eq 'GoldenTeeLive2026' }
        $known.Generic | Should -BeTrue
        $known.GameName | Should -Be 'Golden Tee Live 2026'
        $known.TeknoParrotInfo | Should -Match 'Platform: PC'
        $known.TeknoParrotInfo | Should -Match 'Release year: 2026'
        $plain = $notes | Where-Object { $_.Code -eq 'IgsSpeedDriver2' }
        $plain.Generic | Should -BeTrue
        $plain.TeknoParrotInfo | Should -BeExactly ''
        ($notes | Where-Object { $_.Code -eq 'IgsSpeedRider' }).TeknoParrotInfo | Should -BeExactly ''
        ($notes | Where-Object { $_.Code -eq 'IgsSpeedRider2' }).TeknoParrotInfo | Should -BeExactly ''
        $text = New-TpmGameNotesReportText -SetupNotes $notes
        $text | Should -Match 'Game: GoldenTeeLive2026 \(Golden Tee Live 2026\)'
        $text | Should -Match 'From TeknoParrot \(its own text about this game, not written by TeknoParrot Manager\):'
        $text | Should -Match 'Needs a trackball\.'
        $text | Should -Match 'No setup steps are recorded for this game\.'
        foreach ($profile in $script:fix431Facts.Profiles) { $text | Should -Match ('Game: ' + [regex]::Escape([string]$profile.Code) + ' \(') }
    }
}

Describe 'TeknoParrot update notice' {
    It 'stays silent on the first run, then says how many games are new or changed and names a profile that does not load' {
        $tp = Join-Path $TestDrive 'update-tp'
        $profiles = Join-Path $tp 'GameProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        $state = Join-Path $TestDrive 'update-state.json'
        $writeProfile = { param($code, $revision) [System.IO.File]::WriteAllText((Join-Path $profiles ($code + '.xml')), ('<GameProfile><EmulatorType>TeknoTJC</EmulatorType><ExecutableName>{0}.zip</ExecutableName><GameProfileRevision>{1}</GameProfileRevision></GameProfile>' -f $code, $revision)) }
        & $writeProfile 'OldGame' 1
        & $writeProfile 'ChangedGame' 1
        function Get-TpmInstalledTeknoParrotVersion { param($TeknoParrotRoot) return $script:fix431Version }

        $script:fix431Version = '1.0.0.2312'
        $first = Invoke-TpmTeknoParrotUpdateCheck -TeknoParrotRoot $tp -GameProfilesDir $profiles -StatePath $state
        $first.Status | Should -Be 'FirstRun'
        (Get-Content -LiteralPath $state -Raw) | Should -Not -Match 'GamePath|ExecutableName'

        $script:fix431Version = '1.0.0.2312'
        (Invoke-TpmTeknoParrotUpdateCheck -TeknoParrotRoot $tp -GameProfilesDir $profiles -StatePath $state).Status | Should -Be 'Unchanged'

        & $writeProfile 'ChangedGame' 2
        foreach ($profileFile in @(Get-ChildItem -LiteralPath $script:fix431GameProfiles -Filter '*.xml' -File)) { Copy-Item -LiteralPath $profileFile.FullName -Destination $profiles }
        [System.IO.File]::WriteAllText((Join-Path $profiles 'BrokenGame.xml'), '<GameProfile><EmulatorType>')
        $script:fix431Version = '1.0.0.2337'
        $second = Invoke-TpmTeknoParrotUpdateCheck -TeknoParrotRoot $tp -GameProfilesDir $profiles -StatePath $state
        $second.Status | Should -Be 'Updated'
        @($second.NewCodes).Count | Should -Be 71
        $newSet = @($second.NewCodes)
        @($script:fix431Facts.Profiles | Where-Object { $newSet -notcontains [string]$_.Code }).Count | Should -Be 0
        @($second.ChangedCodes) -join ',' | Should -Be 'ChangedGame'
        @($second.Problems).Count | Should -Be 1
        $second.Problems[0].Code | Should -Be 'BrokenGame'

        $script:fix431Out = New-Object System.Collections.Generic.List[string]
        function Write-Host { param($Object, [Parameter(ValueFromRemainingArguments)]$Ignored) [void]$script:fix431Out.Add([string]$Object) }
        Show-TpmTeknoParrotUpdateNotice -Result $second -Interactive $false
        $script:fix431Out -join "`n" | Should -Match 'TeknoParrot was updated\. 71 new games, 1 game changed\.'
        $script:fix431Out -join "`n" | Should -Match 'could not read 1 of them'
        (Invoke-TpmTeknoParrotUpdateCheck -TeknoParrotRoot $tp -GameProfilesDir $profiles -StatePath $state).Status | Should -Be 'Unchanged'
    }
}
