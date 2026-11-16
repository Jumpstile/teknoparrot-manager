#Requires -Module Pester

# Region choice. The user is asked which region they want; it is set only on games whose own region dropdown(s) offer it.
# Two entry points share the same helpers: the question after registration (never replaces a region the user chose, never
# touches a game that has no automatic choice) and the Region setup menu item (the user picks which games; it may replace an
# earlier choice after a confirmation and a backup). The production script is parsed and only its function definitions are
# loaded; every profile is a synthetic file under TestDrive. Option lists in the fixtures are the real stock lists.
# Each It names the product change that makes it fail.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput([System.IO.File]::ReadAllText($productionPath), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Region choice tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-region37-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    $script:Rg37RealSaveXml = (Get-Command Save-Xml -CommandType Function).ScriptBlock

    function New-Rg37FieldXml {
        param([string]$Name, [string[]]$Options, [string]$Value, [string]$FieldType = 'Dropdown')
        $optionXml = ($Options | ForEach-Object { '<string>' + $_ + '</string>' }) -join ''
        return '<FieldInformation><CategoryName>General</CategoryName><FieldName>' + $Name + '</FieldName><FieldValue>' + $Value + '</FieldValue><FieldType>' + $FieldType + '</FieldType><FieldOptions>' + $optionXml + '</FieldOptions></FieldInformation>'
    }

    # $Second is a second field of the same game, for example @{ Name = 'DongleRegion'; Options = @(...); Value = 'JAPAN' }.
    function New-Rg37Profile {
        param([string]$Dir, [string]$Code, [string[]]$Options = @(), [string]$Value = 'Auto', [string]$FieldName = 'Region', [string]$GameName = '', [string]$FieldType = 'Dropdown', [hashtable]$Second = $null)
        $fields = ''
        if ($Options.Count -gt 0 -or $FieldType -ne 'Dropdown') { $fields += New-Rg37FieldXml -Name $FieldName -Options $Options -Value $Value -FieldType $FieldType }
        if ($null -ne $Second) { $fields += New-Rg37FieldXml -Name $Second.Name -Options $Second.Options -Value $Second.Value }
        $name = if ($GameName) { '<GameName>' + $GameName + '</GameName>' } else { '' }
        $xml = '<?xml version="1.0" encoding="utf-8"?><GameProfile>' + $name + '<GamePath>C:\Games\' + $Code + '\game.exe</GamePath><ConfigValues>' + $fields + '</ConfigValues></GameProfile>'
        [System.IO.File]::WriteAllText((Join-Path $Dir ($Code + '.xml')), $xml, (New-Object System.Text.UTF8Encoding $false))
    }

    function Get-Rg37Value {
        param([string]$Dir, [string]$Code, [string]$FieldName = 'Region')
        $doc = New-Object System.Xml.XmlDocument
        $doc.Load((Join-Path $Dir ($Code + '.xml')))
        return [string]$doc.SelectSingleNode("/GameProfile/ConfigValues/FieldInformation[FieldName='$FieldName']/FieldValue").InnerText
    }

    function Reset-Rg37 {
        param([string]$Answer, [bool]$Interactive = $true)
        $script:Rg37Lines = New-Object System.Collections.Generic.List[string]
        $script:Rg37Asked = 0
        $script:Rg37Answer = $Answer
        $script:Rg37Interactive = $Interactive
        $script:Rg37Outcome = $null
        $script:Rg37Pick = 'A'
        $script:Rg37Inputs = New-Object System.Collections.Generic.Queue[string]
        $script:Rg37Confirm = 'Y'
        $script:Rg37ConfirmAsked = 0
        $script:Rg37Saves = 0
    }

    function Invoke-Rg37 {
        param([string]$Dir, [string[]]$Codes, [string]$Answer, [bool]$Interactive = $true, [bool]$DryRun = $false, [string]$BackupError = $null)
        Reset-Rg37 -Answer $Answer -Interactive $Interactive
        $state = @{ Backup = $null; Done = $true; Error = $(if ($BackupError) { $BackupError } else { $null }) }
        $result = [pscustomobject]@{ TechnicalDetails = [pscustomobject]@{ SafetyBackupState = $state } }
        Invoke-TpmRegionChoice -Codes $Codes -UserProfilesDir $Dir -Result $result -DryRun $DryRun
    }

    # Region setup: $Answer is the region name, 0 (go back) or A (back to automatic); $Pick is A (all) or L (choose games), $Inputs answer the list.
    function Invoke-Rg37Setup {
        param([string]$Dir, [string]$Answer, [string]$Pick = 'A', [string[]]$Inputs = @(), [string]$Confirm = 'Y')
        Reset-Rg37 -Answer $Answer
        $script:Rg37Pick = $Pick
        $script:Rg37Confirm = $Confirm
        foreach ($i in $Inputs) { $script:Rg37Inputs.Enqueue($i) }
        Invoke-TpmRegionSetup -UserProfilesDir $Dir
    }

    function Get-Rg37BackupFolders {
        param([string]$Dir)
        $root = Join-Path $Dir 'FullBackup'
        if (-not (Test-Path -LiteralPath $root)) { return @() }
        return @(Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -like 'RegionSetup_*' })
    }

    Mock Write-Log {}
    Mock Write-TpmText { $script:Rg37Lines.Add([string]$Text) }
    Mock Write-TpmCompactExtractionProgress {}
    Mock Test-TpmInteractiveInput { $script:Rg37Interactive }
    Mock Write-Host { $script:Rg37Lines.Add([string]$Object) }
    Mock Get-TpmRegisteredProfileFilesWithDiscoveryProgress { Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File }
    Mock Read-HostSafe { if ($script:Rg37Inputs.Count -gt 0) { return $script:Rg37Inputs.Dequeue() }; return 'D' }
    Mock Read-TpmYesNo { $script:Rg37ConfirmAsked++; return $script:Rg37Confirm }
    Mock Read-TpmChoice {
        if ([string]$Prompt -like '*Enter A or L*') { return $script:Rg37Pick }
        $script:Rg37Asked++
        if ($script:Rg37Answer -in @('0', 'A')) { return $script:Rg37Answer }
        $line = @($script:Rg37Lines | Where-Object { $_ -match ('^\s+\d+\) ' + [regex]::Escape($script:Rg37Answer) + ' \(') })
        if ($line.Count -ne 1) { throw ('The menu did not list ' + $script:Rg37Answer) }
        return ([regex]::Match($line[0], '^\s+(\d+)\)').Groups[1].Value)
    }
    Mock Write-TpmOutcome { $script:Rg37Outcome = [pscustomobject]@{ Title = $Title; Status = $Status; Blocks = @($DetailBlocks) } }
}

Describe 'Region choice for new games' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('p-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
    }

    It 'sets the region only on games that allow it and leaves the others as they are' {
        # Mutation: set the value without checking the game's own options -> OnlyJapan changes to USA.
        New-Rg37Profile -Dir $script:dir -Code 'ThreeRegions' -Options @('Auto', 'Japan', 'USA', 'Europe')
        New-Rg37Profile -Dir $script:dir -Code 'OnlyJapan' -Options @('Auto', 'Japan')
        Invoke-Rg37 -Dir $script:dir -Codes @('ThreeRegions', 'OnlyJapan') -Answer 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'ThreeRegions' | Should -BeExactly 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'OnlyJapan' | Should -BeExactly 'Auto'
        $script:Rg37Outcome.Title | Should -BeExactly 'Region set to USA for 1 game. 1 game does not offer it and stays as it is.'
        $script:Rg37Outcome.Status | Should -BeExactly 'Ok'
        @($script:Rg37Outcome.Blocks | Where-Object { $_.Heading -like 'Do not offer*' }).Lines | Should -Contain 'OnlyJapan'
    }

    It 'treats Default like Auto: a list that starts on Default is changed too' {
        # Mutation: look only for the word Auto -> the Default game is counted as "already chosen" and stays on Default.
        New-Rg37Profile -Dir $script:dir -Code 'DefaultStyle' -Options @('Default', 'Japan', 'USA', 'Export', 'Australia', 'Korea') -Value 'Default'
        New-Rg37Profile -Dir $script:dir -Code 'AutoStyle' -Options @('Auto', 'Japan', 'USA', 'Export')
        Invoke-Rg37 -Dir $script:dir -Codes @('DefaultStyle', 'AutoStyle') -Answer 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'DefaultStyle' | Should -BeExactly 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'AutoStyle' | Should -BeExactly 'USA'
        $script:Rg37Outcome.Title | Should -BeExactly 'Region set to USA for 2 games.'
    }

    It 'never touches a game that has no automatic choice, and does not call it a chosen region' {
        # Mutation: treat a list without Auto or Default as "on Auto" -> NoNeutral changes from EXPORT, or it is listed as kept.
        New-Rg37Profile -Dir $script:dir -Code 'NoNeutral' -Options @('JAPAN', 'USA', 'EXPORT') -Value 'EXPORT'
        New-Rg37Profile -Dir $script:dir -Code 'PairNoNeutral' -Options @('JAPAN', 'USA', 'JAP2N', 'EXPORT', 'CHINA') -Value 'JAPAN' -FieldName 'PcbRegion' -Second @{ Name = 'DongleRegion'; Options = @('JAPAN', 'USA', 'JAP2N', 'EXPORT', 'CHINA'); Value = 'JAPAN' }
        New-Rg37Profile -Dir $script:dir -Code 'Fresh' -Options @('Auto', 'Japan', 'USA')
        Invoke-Rg37 -Dir $script:dir -Codes @('NoNeutral', 'PairNoNeutral', 'Fresh') -Answer 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'NoNeutral' | Should -BeExactly 'EXPORT'
        Get-Rg37Value -Dir $script:dir -Code 'PairNoNeutral' -FieldName 'PcbRegion' | Should -BeExactly 'JAPAN'
        Get-Rg37Value -Dir $script:dir -Code 'PairNoNeutral' -FieldName 'DongleRegion' | Should -BeExactly 'JAPAN'
        Get-Rg37Value -Dir $script:dir -Code 'Fresh' | Should -BeExactly 'USA'
        $script:Rg37Outcome.Title | Should -BeExactly 'Region set to USA for 1 game.'
        @($script:Rg37Outcome.Blocks | Where-Object { $_.Heading -like 'Already had*' }).Count | Should -Be 0
    }

    It 'writes the exact option text of each game when only the letter case differs' {
        # Mutation: write the text the user picked instead of the option text -> the second game gets USA, not Usa.
        New-Rg37Profile -Dir $script:dir -Code 'UpperGame' -Options @('Auto', 'USA')
        New-Rg37Profile -Dir $script:dir -Code 'MixedGame' -Options @('Auto', 'Usa')
        Invoke-Rg37 -Dir $script:dir -Codes @('UpperGame', 'MixedGame') -Answer 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'UpperGame' | Should -BeExactly 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'MixedGame' | Should -BeExactly 'Usa'
    }

    It 'never overwrites a region the profile already had chosen' {
        # Mutation: drop the automatic-choice check -> the Europe choice is replaced by USA.
        New-Rg37Profile -Dir $script:dir -Code 'Chosen' -Options @('Auto', 'Japan', 'USA', 'Europe') -Value 'Europe'
        New-Rg37Profile -Dir $script:dir -Code 'Fresh' -Options @('Auto', 'Japan', 'USA')
        Invoke-Rg37 -Dir $script:dir -Codes @('Chosen', 'Fresh') -Answer 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'Chosen' | Should -BeExactly 'Europe'
        Get-Rg37Value -Dir $script:dir -Code 'Fresh' | Should -BeExactly 'USA'
        @($script:Rg37Outcome.Blocks | Where-Object { $_.Heading -like 'Already had*' }).Lines | Should -Contain 'Chosen: Europe'
    }

    It 'changes nothing when the user leaves it as is' {
        # Mutation: treat 0 as the first region -> the game is changed.
        New-Rg37Profile -Dir $script:dir -Code 'Game' -Options @('Auto', 'Japan', 'USA')
        Invoke-Rg37 -Dir $script:dir -Codes @('Game') -Answer '0'
        Get-Rg37Value -Dir $script:dir -Code 'Game' | Should -BeExactly 'Auto'
        $script:Rg37Outcome | Should -BeNullOrEmpty
    }

    It 'asks nothing and changes nothing in an unattended run or a preview' {
        # Mutation: ask or write without checking for unattended input or preview -> a prompt is counted or the file changes.
        New-Rg37Profile -Dir $script:dir -Code 'Game' -Options @('Auto', 'Japan', 'USA')
        Invoke-Rg37 -Dir $script:dir -Codes @('Game') -Answer 'USA' -Interactive $false
        $script:Rg37Asked | Should -Be 0
        Get-Rg37Value -Dir $script:dir -Code 'Game' | Should -BeExactly 'Auto'
        Invoke-Rg37 -Dir $script:dir -Codes @('Game') -Answer 'USA' -DryRun $true
        $script:Rg37Asked | Should -Be 0
        Get-Rg37Value -Dir $script:dir -Code 'Game' | Should -BeExactly 'Auto'
    }

    It 'skips the question when no new game has a region dropdown (a free-text Region and a true/false ExportRegion do not count)' {
        # Mutation: ask whenever games were registered, or read a Text or Bool field as a dropdown -> the question is counted.
        New-Rg37Profile -Dir $script:dir -Code 'NoRegion'
        New-Rg37Profile -Dir $script:dir -Code 'TextRegion' -FieldType 'Text' -Value 'auto'
        New-Rg37Profile -Dir $script:dir -Code 'ExportBool' -FieldName 'ExportRegion' -FieldType 'Bool' -Value 'false'
        New-Rg37Profile -Dir $script:dir -Code 'AutoOnly' -Options @('Auto')
        Invoke-Rg37 -Dir $script:dir -Codes @('NoRegion', 'TextRegion', 'ExportBool', 'AutoOnly') -Answer 'USA'
        $script:Rg37Asked | Should -Be 0
        $script:Rg37Outcome | Should -BeNullOrEmpty
    }

    It 'writes nothing and says so when the safety backup is not available' {
        # Mutation: skip the backup check -> the profile is changed without a backup.
        New-Rg37Profile -Dir $script:dir -Code 'Game' -Options @('Auto', 'Japan', 'USA')
        Invoke-Rg37 -Dir $script:dir -Codes @('Game') -Answer 'USA' -BackupError 'backup failed'
        Get-Rg37Value -Dir $script:dir -Code 'Game' | Should -BeExactly 'Auto'
        $script:Rg37Outcome.Status | Should -BeExactly 'Problem'
        @($script:Rg37Outcome.Blocks | Where-Object { $_.Heading -eq 'Could not be changed' }).Lines | Should -Contain 'Game: backup failed'
    }
}

Describe 'Region setup menu item' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('s-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
        New-Rg37Profile -Dir $script:dir -Code 'Alpha' -GameName 'Alpha Game' -Options @('Auto', 'Japan', 'USA')
        New-Rg37Profile -Dir $script:dir -Code 'Beta' -GameName 'Beta Game' -Options @('Auto', 'Japan', 'USA', 'Europe') -Value 'Europe'
        New-Rg37Profile -Dir $script:dir -Code 'Gamma' -GameName 'Gamma Game' -Options @('Auto', 'Japan')
    }

    It 'changes every game that offers the region when the user takes all of them, even one that had another region' {
        # Mutation: skip games that are not on Auto, or touch games that do not offer the region -> Beta stays Europe or Gamma changes.
        Invoke-Rg37Setup -Dir $script:dir -Answer 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'Alpha' | Should -BeExactly 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'Beta' | Should -BeExactly 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'Gamma' | Should -BeExactly 'Auto'
        @($script:Rg37Lines | Where-Object { $_ -like '2 games will be changed to USA.*stay as they are: 1.*already have it: 0.' }).Count | Should -Be 1
        $script:Rg37Outcome.Title | Should -BeExactly 'Region set to USA for 2 games. 1 game does not offer it and stays as it is.'
        @($script:Rg37Outcome.Blocks | Where-Object { $_.Heading -like 'Region set to*' }).Lines | Should -Contain 'Beta Game (Europe -> USA)'
    }

    It 'lists the games that offer the region by name with their current region, and changes only the ones picked' {
        # Mutation: ignore the picked games and change all -> Alpha changes too; or leave the current region off the list.
        Invoke-Rg37Setup -Dir $script:dir -Answer 'USA' -Pick 'L' -Inputs @('2', 'D')
        @($script:Rg37Lines | Where-Object { $_ -like '*Alpha Game (now: Auto)' }).Count | Should -BeGreaterThan 0
        @($script:Rg37Lines | Where-Object { $_ -like '*Beta Game (now: Europe)' }).Count | Should -BeGreaterThan 0
        @($script:Rg37Lines | Where-Object { $_ -like '*Gamma Game*' }).Count | Should -Be 0
        Get-Rg37Value -Dir $script:dir -Code 'Alpha' | Should -BeExactly 'Auto'
        Get-Rg37Value -Dir $script:dir -Code 'Beta' | Should -BeExactly 'USA'
        Get-Rg37Value -Dir $script:dir -Code 'Gamma' | Should -BeExactly 'Auto'
    }

    It 'changes nothing, asks nothing and makes no backup when no game is picked' {
        # Mutation: treat an empty selection as all games -> both games change.
        Invoke-Rg37Setup -Dir $script:dir -Answer 'USA' -Pick 'L' -Inputs @('D')
        Get-Rg37Value -Dir $script:dir -Code 'Alpha' | Should -BeExactly 'Auto'
        Get-Rg37Value -Dir $script:dir -Code 'Beta' | Should -BeExactly 'Europe'
        $script:Rg37ConfirmAsked | Should -Be 0
        @(Get-Rg37BackupFolders -Dir $script:dir).Count | Should -Be 0
    }

    It 'changes nothing and makes no backup when the user answers N to the confirmation' {
        # Mutation: write before the confirmation or ignore the answer -> a game changes or a backup folder appears.
        Invoke-Rg37Setup -Dir $script:dir -Answer 'USA' -Confirm 'N'
        Get-Rg37Value -Dir $script:dir -Code 'Alpha' | Should -BeExactly 'Auto'
        Get-Rg37Value -Dir $script:dir -Code 'Beta' | Should -BeExactly 'Europe'
        $script:Rg37ConfirmAsked | Should -Be 1
        @(Get-Rg37BackupFolders -Dir $script:dir).Count | Should -Be 0
    }

    It 'changes nothing when the user goes back' {
        # Mutation: treat 0 as the first region -> a game changes.
        Invoke-Rg37Setup -Dir $script:dir -Answer '0'
        Get-Rg37Value -Dir $script:dir -Code 'Alpha' | Should -BeExactly 'Auto'
        $script:Rg37ConfirmAsked | Should -Be 0
        $script:Rg37Outcome | Should -BeNullOrEmpty
    }

    It 'saves a restore point with the old values before it changes anything' {
        # Mutation: write the profiles without calling the verified backup -> no RegionSetup folder exists.
        Invoke-Rg37Setup -Dir $script:dir -Answer 'USA'
        $folders = @(Get-Rg37BackupFolders -Dir $script:dir)
        $folders.Count | Should -Be 1
        Get-Rg37Value -Dir $folders[0].FullName -Code 'Alpha' | Should -BeExactly 'Auto'
        Get-Rg37Value -Dir $folders[0].FullName -Code 'Beta' | Should -BeExactly 'Europe'
        Get-Rg37Value -Dir $script:dir -Code 'Alpha' | Should -BeExactly 'USA'
    }

    It 'puts games back to automatic, lists only games that are not on it, and leaves the others alone' {
        # Mutation: offer games already on Auto in the list or change them -> Alpha is listed or counted.
        Invoke-Rg37Setup -Dir $script:dir -Answer 'A' -Pick 'L' -Inputs @('1', 'D')
        @($script:Rg37Lines | Where-Object { $_ -like '*Beta Game (now: Europe)' }).Count | Should -BeGreaterThan 0
        @($script:Rg37Lines | Where-Object { $_ -like '*Alpha Game (now:*' }).Count | Should -Be 0
        Get-Rg37Value -Dir $script:dir -Code 'Beta' | Should -BeExactly 'Auto'
        Get-Rg37Value -Dir $script:dir -Code 'Alpha' | Should -BeExactly 'Auto'
        $script:Rg37Outcome.Title | Should -BeExactly 'Region put back to the automatic choice for 1 game.'
    }
}

Describe 'Region setup with the real stock option lists' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ('r-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:dir -Force | Out-Null
    }

    It 'puts a Default-style game back to Default, and lists a game with no automatic choice instead of changing it' {
        # Mutation: write the word Auto, or change a JAPAN/USA/EXPORT-only game -> DefGame gets Auto, or NoNeutral leaves EXPORT.
        New-Rg37Profile -Dir $script:dir -Code 'DefGame' -Options @('Default', 'Japan', 'USA', 'Export') -Value 'USA'
        New-Rg37Profile -Dir $script:dir -Code 'NoNeutral' -Options @('JAPAN', 'USA', 'EXPORT') -Value 'EXPORT'
        Invoke-Rg37Setup -Dir $script:dir -Answer 'A'
        Get-Rg37Value -Dir $script:dir -Code 'DefGame' | Should -BeExactly 'Default'
        Get-Rg37Value -Dir $script:dir -Code 'NoNeutral' | Should -BeExactly 'EXPORT'
        $script:Rg37Outcome.Title | Should -BeExactly 'Region put back to the automatic choice for 1 game. 1 game has no automatic choice and stays as it is.'
        @($script:Rg37Outcome.Blocks | Where-Object { $_.Heading -like 'Have no automatic choice*' }).Lines | Should -Contain 'NoNeutral'
    }

    It 'writes the profile''s own spelling when JAPAN and Japan differ' {
        # Mutation: write the text of the first game to every game -> MixedJ gets JAPAN, or UpperJ gets Japan.
        New-Rg37Profile -Dir $script:dir -Code 'UpperJ' -Options @('JAPAN', 'USA', 'EXPORT') -Value 'EXPORT'
        New-Rg37Profile -Dir $script:dir -Code 'MixedJ' -Options @('Auto', 'Japan', 'USA', 'Export')
        Invoke-Rg37Setup -Dir $script:dir -Answer 'Japan'
        Get-Rg37Value -Dir $script:dir -Code 'UpperJ' | Should -BeExactly 'JAPAN'
        Get-Rg37Value -Dir $script:dir -Code 'MixedJ' | Should -BeExactly 'Japan'
    }

    It 'writes PcbRegion and DongleRegion together in one save and reads both back, and does not offer a value one of them lacks' {
        # Mutation: write only the first field, save twice, or offer a value only one field has -> a field stays JAPAN, two saves are counted, or PairPartial changes.
        $all = @('JAPAN', 'USA', 'JAP2N', 'EXPORT', 'CHINA')
        New-Rg37Profile -Dir $script:dir -Code 'PairFull' -Options $all -Value 'JAPAN' -FieldName 'PcbRegion' -Second @{ Name = 'DongleRegion'; Options = $all; Value = 'JAPAN' }
        New-Rg37Profile -Dir $script:dir -Code 'PairPartial' -Options $all -Value 'JAPAN' -FieldName 'PcbRegion' -Second @{ Name = 'DongleRegion'; Options = @('JAPAN', 'USA', 'EXPORT'); Value = 'JAPAN' }
        Mock Save-Xml { $script:Rg37Saves++; & $script:Rg37RealSaveXml $doc $path }
        Invoke-Rg37Setup -Dir $script:dir -Answer 'CHINA'
        Get-Rg37Value -Dir $script:dir -Code 'PairFull' -FieldName 'PcbRegion' | Should -BeExactly 'CHINA'
        Get-Rg37Value -Dir $script:dir -Code 'PairFull' -FieldName 'DongleRegion' | Should -BeExactly 'CHINA'
        $script:Rg37Saves | Should -Be 1
        Get-Rg37Value -Dir $script:dir -Code 'PairPartial' -FieldName 'PcbRegion' | Should -BeExactly 'JAPAN'
        Get-Rg37Value -Dir $script:dir -Code 'PairPartial' -FieldName 'DongleRegion' | Should -BeExactly 'JAPAN'
        $script:Rg37Outcome.Title | Should -BeExactly 'Region set to CHINA for 1 game. 1 game does not offer it and stays as it is.'
    }
}
