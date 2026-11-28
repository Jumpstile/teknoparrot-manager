#Requires -Module Pester
# Controls coverage inventory (issue #305, contract docs/architecture/CONTROLLER_CAPABILITY_CONTRACT.md).
# What a user sees or loses: a game is never called ready because it launched or has some buttons bound. Missing controls are
# named in plain words, unknown and unsupported cases stay explicit, and nothing in a profile is ever changed.
# These tests drive the real functions with small profile fixtures. What this CANNOT prove: real TeknoParrot profiles for games
# other than the one reviewed game, and anything about whether a control works in a game.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Coverage inventory bootstrap could not parse the production script.' }
    $wanted = @(
        'Read-Xml', 'Get-ButtonNodes', 'Test-ButtonIsBound',
        'Get-ControlReadinessKnownRequirements', 'Test-ControlReadinessButtonBindingUsable', 'Test-ControlReadinessAnalogMappingUsable',
        'Get-ControlReadinessDocumentFit', 'Read-ControlReadinessProfileDocument', 'Get-ControlReadinessControlsState',
        'Get-TpmControlCoverageContract', 'Get-TpmControlBindingFacts', 'Get-TpmControlCoverageInventory',
        'Get-TpmControlCoverageLines', 'Get-TpmControlCoverage', 'Get-TpmControlCoverageWhyText', 'Read-TpmGameTemplate', 'Get-TpmTemplateIdentity',
        'Get-TpmDerivedControlContract', 'Get-TpmGameControlContract', 'Get-TpmControlCoverageAudit', 'Get-TpmControlCoverageAuditSummary',
        'Test-TpmMappingInPlayerOneScope', 'Get-TpmProfileFriendlyTitle', 'Get-TpmGameTitle'
    )
    $functionFile = Join-Path $TestDrive 'coverage-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -in $wanted }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function Write-Log { param($msg) }

    $script:allMappings = @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3', 'Analog0', 'Analog2', 'Analog4')

    # A profile shaped like the reviewed game: four buttons and three analog slots. $Bound lists the buttons that carry a
    # real binding; $EmptyAnalogType lists analog slots whose AnalogType is blank; $Omit drops a slot completely.
    function New-AbcProfileXml {
        param(
            [string[]]$Bound = @(),
            [string[]]$Omit = @(),
            [string[]]$EmptyAnalogType = @(),
            [int]$Revision = 22,
            [string]$InputApi = '',
            [string[]]$InputApiOptions = @('DirectInput', 'XInput')
        )
        $slots = foreach ($m in $script:allMappings) {
            if ($Omit -contains $m) { continue }
            if ($m -like 'Analog*') {
                $type = if ($EmptyAnalogType -contains $m) { '' } else { 'SWThrottle' }
                "<JoystickButtons><ButtonName>$m</ButtonName><InputMapping>$m</InputMapping><AnalogType>$type</AnalogType></JoystickButtons>"
            } else {
                $binding = if ($Bound -contains $m) { '<DirectInputButton>1</DirectInputButton>' } else { '' }
                "<JoystickButtons><ButtonName>$m</ButtonName><InputMapping>$m</InputMapping>$binding</JoystickButtons>"
            }
        }
        $apiXml = ''
        if ($InputApi) {
            $options = ($InputApiOptions | ForEach-Object { "<string>$_</string>" }) -join ''
            $apiXml = "<ConfigValues><FieldInformation><FieldName>Input API</FieldName><FieldValue>$InputApi</FieldValue><FieldOptions>$options</FieldOptions></FieldInformation></ConfigValues>"
        }
        return "<GameProfile><ExecutableName>abc</ExecutableName><EmulationProfile>AfterBurnerClimax</EmulationProfile><GameProfileRevision>$Revision</GameProfileRevision>$apiXml<JoystickButtons>$(-join $slots)</JoystickButtons></GameProfile>"
    }
    function Get-Inventory {
        param([string]$Xml)
        $contract = Get-TpmControlCoverageContract -Code 'abc'
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($Xml)
        Get-TpmControlCoverageInventory -Contract $contract -Facts (Get-TpmControlBindingFacts -Doc $doc -Contract $contract -Code 'abc')
    }
}

Describe 'Controls coverage contract' {
    It 'has a reviewed contract only for a known game' {
        Get-TpmControlCoverageContract -Code 'abc' | Should -Not -BeNullOrEmpty
        Get-TpmControlCoverageContract -Code 'notagame' | Should -BeNullOrEmpty
        Get-TpmControlCoverageContract -Code '..\evil' | Should -BeNullOrEmpty
        Get-TpmControlCoverageContract -Code '' | Should -BeNullOrEmpty
    }

    It 'names every control in plain words and requires all of them' {
        $contract = Get-TpmControlCoverageContract -Code 'abc'
        $contract.SemanticControls.Count | Should -Be 7
        ($contract.SemanticControls | Where-Object { $_.Requirement -ne 'Required' }).Count | Should -Be 0
        ($contract.SemanticControls | Where-Object { $_.Meaning -eq $_.ControlId }).Count | Should -Be 0
    }

    It 'matches the capability schema when the PowerShell version can check it' -Skip:(-not (Get-Command Test-Json -ErrorAction SilentlyContinue | Where-Object { $_.Parameters.ContainsKey('SchemaFile') })) {
        $schemaPath = Join-Path $PSScriptRoot '..\schemas\TpmControllerCapability.v1.schema.json'
        $json = Get-TpmControlCoverageContract -Code 'abc' | ConvertTo-Json -Depth 8
        Test-Json -Json $json -SchemaFile $schemaPath | Should -BeTrue
    }
}

Describe 'Controls coverage inventory' {
    It 'is Complete but still NotVerified when every required control is usable' {
        $inv = Get-Inventory (New-AbcProfileXml -Bound @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3'))
        $inv.Structural | Should -Be 'Complete'
        $inv.Verification | Should -Be 'NotVerified'
        $inv.MissingControls.Count | Should -Be 0
        ($inv.Controls | Where-Object { $_.Verification -ne 'NotVerified' }).Count | Should -Be 0
    }

    It 'is Partial and names the missing controls in plain words' {
        $inv = Get-Inventory (New-AbcProfileXml -Bound @('P1Button2', 'P1Button3'))
        $inv.Structural | Should -Be 'Partial'
        ($inv.MissingControls -join '|') | Should -Be 'Start button|Gun trigger'
    }

    It 'is Partial when only the analog slots are usable and no button is bound' {
        $inv = Get-Inventory (New-AbcProfileXml -Bound @())
        $inv.Structural | Should -Be 'Partial'
        $inv.MissingControls.Count | Should -Be 4
    }

    It 'is Missing when none of the controls the game needs is usable' {
        $inv = Get-Inventory (New-AbcProfileXml -Bound @() -Omit @('Analog0', 'Analog2', 'Analog4'))
        $inv.Structural | Should -Be 'Missing'
        $inv.MissingControls.Count | Should -Be 7
    }

    It 'treats an empty binding as not usable' {
        $xml = (New-AbcProfileXml -Bound @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3')).Replace('<DirectInputButton>1</DirectInputButton><', '<DirectInputButton></DirectInputButton><')
        (Get-Inventory $xml).Structural | Should -Not -Be 'Complete'
    }

    It 'treats an analog slot with no type as missing, and a dropped slot as missing' {
        $all = @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3')
        $inv1 = Get-Inventory (New-AbcProfileXml -Bound $all -EmptyAnalogType @('Analog4'))
        $inv1.Structural | Should -Be 'Partial'
        ($inv1.MissingControls -join '|') | Should -Be 'Throttle lever'
        $inv2 = Get-Inventory (New-AbcProfileXml -Bound $all -Omit @('Analog0'))
        ($inv2.MissingControls -join '|') | Should -Be 'Joystick left and right'
    }

    It 'is Unknown, never Complete, when the profile is not the reviewed revision' {
        $inv = Get-Inventory (New-AbcProfileXml -Bound @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3') -Revision 23)
        $inv.Structural | Should -Be 'Unknown'
        ($inv.Controls | Where-Object { $_.Structural -eq 'Complete' }).Count | Should -Be 0
        $inv.MissingControls.Count | Should -Be 0
    }

    It 'is Unsupported when the selected input type is outside the profile own options' {
        $inv = Get-Inventory (New-AbcProfileXml -Bound @('P1ButtonStart') -InputApi 'RawInput')
        $inv.Structural | Should -Be 'Unsupported'
    }

    It 'is Unknown when there is no profile to read' {
        $contract = Get-TpmControlCoverageContract -Code 'abc'
        $inv = Get-TpmControlCoverageInventory -Contract $contract -Facts (Get-TpmControlBindingFacts -Doc $null -Contract $contract -Code 'abc')
        $inv.Structural | Should -Be 'Unknown'
    }

    It 'gives identical output for identical input' {
        $xml = New-AbcProfileXml -Bound @('P1Button1')
        ((Get-Inventory $xml) | ConvertTo-Json -Depth 6) | Should -Be ((Get-Inventory $xml) | ConvertTo-Json -Depth 6)
    }

    It 'reports the setup state a contract asks for and Unknown otherwise' {
        $contract = Get-TpmControlCoverageContract -Code 'abc'
        $facts = [pscustomobject]@{ Fit = 'Ok'; UsableControlIds = @() }
        (Get-TpmControlCoverageInventory -Contract $contract -Facts $facts).Setup | Should -Be 'Unknown'
        $contract.SemanticControls[4] | Add-Member -NotePropertyName SetupRequirement -NotePropertyValue 'CalibrationRequired'
        $inv = Get-TpmControlCoverageInventory -Contract $contract -Facts $facts
        $inv.Setup | Should -Be 'CalibrationRequired'
        ($inv.Controls | Where-Object { $_.ControlId -eq 'Analog0' }).Setup | Should -Be 'CalibrationRequired'
    }
}

Describe 'Controls coverage text and reading' {
    It 'names what is still needed and never calls the game ready' {
        $inv = Get-Inventory (New-AbcProfileXml -Bound @('P1Button2'))
        $text = (Get-TpmControlCoverageLines -Inventory $inv) -join ' '
        $text | Should -Match 'Still needed: Start button, Gun trigger'
        $text | Should -Match 'cannot say the game is ready'
        $text | Should -Not -Match '(?i)\bverified\b'
    }

    It 'keeps the older controls state words for the existing readiness report' {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml((New-AbcProfileXml -Bound @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3')))
        Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'NotVerified'
        $doc.LoadXml((New-AbcProfileXml -Bound @('P1Button1')))
        Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Missing'
        $doc.LoadXml((New-AbcProfileXml -Bound @() -Revision 23))
        Get-ControlReadinessControlsState $doc 'abc' | Should -Be 'Unknown'
        Get-ControlReadinessControlsState $doc 'notagame' | Should -Be 'Unknown'
    }

    It 'reads the profile files and changes none of them' {
        $user = Join-Path $TestDrive 'UserProfiles'
        $game = Join-Path $TestDrive 'GameProfiles'
        New-Item -ItemType Directory -Path $user, $game -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $user 'abc.xml') -Value (New-AbcProfileXml -Bound @('P1ButtonStart')) -Encoding utf8
        Set-Content -LiteralPath (Join-Path $game 'abc.xml') -Value (New-AbcProfileXml -Bound @()) -Encoding utf8
        $before = Get-ChildItem -Path $TestDrive -Recurse -File | Get-FileHash | ForEach-Object { $_.Path + $_.Hash }
        $inv = Get-TpmControlCoverage -Code 'abc' -UserProfilesDir $user -GameProfilesDir $game
        $after = Get-ChildItem -Path $TestDrive -Recurse -File | Get-FileHash | ForEach-Object { $_.Path + $_.Hash }
        $inv.Structural | Should -Be 'Partial'
        $inv.ReadOnly | Should -BeTrue
        ($after -join '|') | Should -Be ($before -join '|')
        Get-TpmControlCoverage -Code 'notagame' -UserProfilesDir $user | Should -BeNullOrEmpty
    }

    It 'falls back to the game template when the game is not registered' {
        $user = Join-Path $TestDrive 'UserEmpty'
        $game = Join-Path $TestDrive 'GameOnly'
        New-Item -ItemType Directory -Path $user, $game -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $game 'abc.xml') -Value (New-AbcProfileXml -Bound @() -Omit @('Analog0', 'Analog2', 'Analog4')) -Encoding utf8
        (Get-TpmControlCoverage -Code 'abc' -UserProfilesDir $user -GameProfilesDir $game).Structural | Should -Be 'Missing'
        (Get-TpmControlCoverage -Code 'abc' -UserProfilesDir $user).Structural | Should -Be 'Unknown'
    }
}

# Contracts read from TeknoParrot's own game file (issue #305): every game can be checked, with honest confidence.
Describe 'Controls coverage from the game''s own file' {
    BeforeAll {
        # Slots: Name, Mapping, Analog type, Bound (a DirectInput binding), VisibleWhen (shown only when another setting asks).
        function New-OwnGameXml {
            param([object[]]$Slots, [int]$Revision = 7, [switch]$Template)
            $buttons = foreach ($s in $Slots) {
                $binding = if ($s.Bound -and -not $Template) { '<DirectInputButton><Button>1</Button></DirectInputButton>' } else { '' }
                $analog = if ($s.Analog) { "<AnalogType>$($s.Analog)</AnalogType>" } else { '' }
                $visible = if ($s.Visible) { '<VisibleWhen>Some Setting</VisibleWhen>' } else { '' }
                "<JoystickButtons><ButtonName>$($s.Name)</ButtonName><InputMapping>$($s.Mapping)</InputMapping>$visible$analog$binding</JoystickButtons>"
            }
            return "<GameProfile><ExecutableName>owngame</ExecutableName><EmulationProfile>OwnEmu</EmulationProfile><GameProfileRevision>$Revision</GameProfileRevision><JoystickButtons>$(-join $buttons)</JoystickButtons></GameProfile>"
        }
        function New-OwnSlots {
            param([string[]]$Bound = @())
            @(
                @{ Name = 'Test'; Mapping = 'Test' }, @{ Name = 'Coin 1'; Mapping = 'Coin1' }, @{ Name = 'Start'; Mapping = 'P1ButtonStart' },
                @{ Name = 'Gun Trigger'; Mapping = 'P1Button1' }, @{ Name = 'Missile'; Mapping = 'P1Button2' },
                @{ Name = 'Bonus Button'; Mapping = 'P1Button3'; Visible = $true },
                @{ Name = 'P2 Start'; Mapping = 'P2ButtonStart' },
                @{ Name = 'Stick X'; Mapping = 'Analog0'; Analog = 'AnalogJoystick' }, @{ Name = 'Stick X Left'; Mapping = 'Analog0'; Analog = 'AnalogJoystick' }
            ) | ForEach-Object { $_.Bound = ($Bound -contains $_.Name); [pscustomobject]$_ }
        }
        function New-OwnFiles {
            param([string]$Name, [string[]]$Bound = @(), [int]$UserRevision = 7, [int]$TemplateRevision = 7, [switch]$NoTemplate, [switch]$NoUser)
            $unique = [guid]::NewGuid().ToString('N').Substring(0, 6)
            $user = Join-Path $TestDrive "own-user-$unique"; $game = Join-Path $TestDrive "own-game-$unique"
            New-Item -ItemType Directory -Path $user, $game -Force | Out-Null
            if (-not $NoUser) { Set-Content -LiteralPath (Join-Path $user "$Name.xml") -Value (New-OwnGameXml -Slots (New-OwnSlots -Bound $Bound) -Revision $UserRevision) -Encoding utf8 }
            if (-not $NoTemplate) { Set-Content -LiteralPath (Join-Path $game "$Name.xml") -Value (New-OwnGameXml -Slots (New-OwnSlots) -Revision $TemplateRevision -Template) -Encoding utf8 }
            return [pscustomobject]@{ User = $user; Game = $game }
        }
        $script:allBound = @('Start', 'Gun Trigger', 'Missile', 'Stick X')
    }

    It 'names controls by the game''s own button names, leaves out other players, and does not require Test, Coin or conditional controls' {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml((New-OwnGameXml -Slots (New-OwnSlots) -Template))
        $contract = Get-TpmDerivedControlContract -Code 'owngame' -TemplateDoc $doc -TemplateSha256 ('a' * 64)
        @($contract.SemanticControls | Where-Object Requirement -eq 'Required' | ForEach-Object Meaning) | Should -Be @('Start', 'Gun Trigger', 'Missile', 'Stick X')
        @($contract.SemanticControls | Where-Object Requirement -eq 'Optional' | ForEach-Object Meaning) | Should -Be @('Test', 'Coin 1', 'Bonus Button')
        @($contract.SemanticControls | Where-Object ControlId -eq 'P2ButtonStart').Count | Should -Be 0
        @($contract.SemanticControls | Where-Object ControlId -eq 'Analog0').Count | Should -Be 1
        $contract.Evidence.ReviewState | Should -Be 'PendingReview'
        $contract.GameContracts[0].ContractRevision | Should -Be 7
        $contract.GameContracts[0].GameProfileHash | Should -Be ('a' * 64)
    }

    It 'matches the capability schema when the PowerShell version can check it' -Skip:(-not (Get-Command Test-Json -ErrorAction SilentlyContinue | Where-Object { $_.Parameters.ContainsKey('SchemaFile') })) {
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml((New-OwnGameXml -Slots (New-OwnSlots) -Template))
        $json = Get-TpmDerivedControlContract -Code 'owngame' -TemplateDoc $doc -TemplateSha256 ('a' * 64) | ConvertTo-Json -Depth 8
        Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '..\schemas\TpmControllerCapability.v1.schema.json') | Should -BeTrue
    }

    It 'is Complete but Medium confidence and never ready when every control the game lists is bound' {
        $f = New-OwnFiles -Name 'owngame' -Bound $script:allBound
        $inv = Get-TpmControlCoverage -Code 'owngame' -UserProfilesDir $f.User -GameProfilesDir $f.Game
        $inv.Structural | Should -Be 'Complete'
        $inv.Confidence | Should -Be 'Medium'
        $inv.Verification | Should -Be 'NotVerified'
        $text = (Get-TpmControlCoverageLines -Inventory $inv) -join ' '
        $text | Should -Match 'A person has not checked it'
        $text | Should -Match 'cannot say the game is ready'
        $text | Should -Not -Match '(?i)\bverified\b'
    }

    It 'is Partial, names what is missing, and mentions Test separately because TPM cannot tell if the game needs it' {
        $f = New-OwnFiles -Name 'owngame' -Bound @('Start', 'Stick X')
        $inv = Get-TpmControlCoverage -Code 'owngame' -UserProfilesDir $f.User -GameProfilesDir $f.Game
        $inv.Structural | Should -Be 'Partial'
        ($inv.MissingControls -join '|') | Should -Be 'Gun Trigger|Missile'
        $text = (Get-TpmControlCoverageLines -Inventory $inv) -join ' '
        $text | Should -Match 'Still needed: Gun Trigger, Missile'
        $text | Should -Match 'cannot tell if the game needs them: Test, Coin 1, Bonus Button'
    }

    It 'is Missing when nothing is bound, and an analog control needs a real binding, not just a declared type' {
        $f = New-OwnFiles -Name 'owngame' -Bound @()
        $inv = Get-TpmControlCoverage -Code 'owngame' -UserProfilesDir $f.User -GameProfilesDir $f.Game
        $inv.Structural | Should -Be 'Missing'
        $inv.MissingControls | Should -Contain 'Stick X'
    }

    It 'reads a game whose profile name has a hyphen (for example R-Tuned)' {
        $f = New-OwnFiles -Name 'own-game' -Bound $script:allBound
        (Get-TpmControlCoverage -Code 'own-game' -UserProfilesDir $f.User -GameProfilesDir $f.Game).Structural | Should -Be 'Complete'
    }

    It 'counts a control as set up when any of its buttons is bound (an axis and its keyboard halves)' {
        $f = New-OwnFiles -Name 'owngame' -Bound @('Start', 'Gun Trigger', 'Missile', 'Stick X Left')
        (Get-TpmControlCoverage -Code 'owngame' -UserProfilesDir $f.User -GameProfilesDir $f.Game).Structural | Should -Be 'Complete'
    }

    It 'is Unknown, never Complete, when the saved settings are another revision than the game file' {
        $f = New-OwnFiles -Name 'owngame' -Bound $script:allBound -UserRevision 6 -TemplateRevision 7
        $inv = Get-TpmControlCoverage -Code 'owngame' -UserProfilesDir $f.User -GameProfilesDir $f.Game
        $inv.Structural | Should -Be 'Unknown'
        $inv.Why | Should -Be 'DifferentVersion'
        (Get-TpmControlCoverageLines -Inventory $inv) -join ' ' | Should -Match 'Open it once in TeknoParrotUI'
    }

    It 'has nothing to say about a game with no game file, and the audit says why' {
        $f = New-OwnFiles -Name 'owngame' -Bound $script:allBound -NoTemplate
        Get-TpmControlCoverage -Code 'owngame' -UserProfilesDir $f.User -GameProfilesDir $f.Game | Should -BeNullOrEmpty
        $audit = Get-TpmControlCoverageAudit -Profiles @(Get-ChildItem -LiteralPath $f.User -Filter '*.xml') -GameProfilesDir $f.Game
        $audit.Rows[0].Structural | Should -Be 'Unknown'
        $audit.Rows[0].Why | Should -Be 'NoGameFile'
    }

    It 'is Unknown when the game file lists no player controls' {
        $user = Join-Path $TestDrive 'own-user-none'; $game = Join-Path $TestDrive 'own-game-none'
        New-Item -ItemType Directory -Path $user, $game -Force | Out-Null
        $only = @([pscustomobject]@{ Name = 'Coin 1'; Mapping = 'Coin1' })
        Set-Content -LiteralPath (Join-Path $game 'nothing.xml') -Value (New-OwnGameXml -Slots $only -Template) -Encoding utf8
        Set-Content -LiteralPath (Join-Path $user 'nothing.xml') -Value (New-OwnGameXml -Slots $only) -Encoding utf8
        $audit = Get-TpmControlCoverageAudit -Profiles @(Get-ChildItem -LiteralPath $user -Filter '*.xml') -GameProfilesDir $game
        $audit.Rows[0].Why | Should -Be 'NoControls'
    }

    It 'the reviewed contract still wins for the reviewed revision, and a newer revision falls back to the game file' {
        $user = Join-Path $TestDrive 'own-user-abc'; $game = Join-Path $TestDrive 'own-game-abc'
        New-Item -ItemType Directory -Path $user, $game -Force | Out-Null
        $reviewed = New-AbcProfileXml -Bound @('P1ButtonStart', 'P1Button1', 'P1Button2', 'P1Button3')
        Set-Content -LiteralPath (Join-Path $user 'abc.xml') -Value $reviewed -Encoding utf8
        (Get-TpmControlCoverage -Code 'abc' -UserProfilesDir $user -GameProfilesDir $game).Confidence | Should -Be 'High'
        Set-Content -LiteralPath (Join-Path $user 'abc.xml') -Value (New-AbcProfileXml -Bound @('P1ButtonStart') -Revision 25) -Encoding utf8
        Set-Content -LiteralPath (Join-Path $game 'abc.xml') -Value (New-AbcProfileXml -Bound @() -Revision 25) -Encoding utf8
        $inv = Get-TpmControlCoverage -Code 'abc' -UserProfilesDir $user -GameProfilesDir $game
        $inv.Confidence | Should -Be 'Medium'
        $inv.Structural | Should -Be 'Partial'
    }

    It 'audits a TeknoChi game whose profile says development only like any other game' {
        # Mutation: leave out profiles that say DevOnly, so the TeknoChi game is missing from the count.
        $user = Join-Path $TestDrive 'own-user-chi'; $game = Join-Path $TestDrive 'own-game-chi'
        New-Item -ItemType Directory -Path $user, $game -Force | Out-Null
        $tag = '<GameProfile><EmulatorType>TeknoChi</EmulatorType><DevOnly>true</DevOnly>'
        Set-Content -LiteralPath (Join-Path $user 'TeknoChiTest.xml') -Value ((New-OwnGameXml -Slots (New-OwnSlots -Bound $script:allBound)) -replace '<GameProfile>', $tag) -Encoding utf8
        Set-Content -LiteralPath (Join-Path $game 'TeknoChiTest.xml') -Value ((New-OwnGameXml -Slots (New-OwnSlots) -Template) -replace '<GameProfile>', $tag) -Encoding utf8
        $audit = Get-TpmControlCoverageAudit -Profiles @(Get-ChildItem -LiteralPath $user -Filter '*.xml') -GameProfilesDir $game
        $audit.Total | Should -Be 1
        $audit.Complete | Should -Be 1
    }

    It 'audits every registered game, counts them, names the games behind Details, and changes no file' {
        $user = Join-Path $TestDrive 'own-user-audit'; $game = Join-Path $TestDrive 'own-game-audit'
        New-Item -ItemType Directory -Path $user, $game -Force | Out-Null
        $cases = @{ full = $script:allBound; some = @('Start'); none = @() }
        foreach ($name in $cases.Keys) {
            Set-Content -LiteralPath (Join-Path $user "$name.xml") -Value (New-OwnGameXml -Slots (New-OwnSlots -Bound $cases[$name])) -Encoding utf8
            Set-Content -LiteralPath (Join-Path $game "$name.xml") -Value (New-OwnGameXml -Slots (New-OwnSlots) -Template) -Encoding utf8
        }
        Set-Content -LiteralPath (Join-Path $user 'nofile.xml') -Value (New-OwnGameXml -Slots (New-OwnSlots)) -Encoding utf8
        $before = Get-ChildItem -Path $user, $game -Recurse -File | Get-FileHash | ForEach-Object { $_.Path + $_.Hash }
        $audit = Get-TpmControlCoverageAudit -Profiles @(Get-ChildItem -LiteralPath $user -Filter '*.xml') -GameProfilesDir $game
        $after = Get-ChildItem -Path $user, $game -Recurse -File | Get-FileHash | ForEach-Object { $_.Path + $_.Hash }
        ($after -join '|') | Should -Be ($before -join '|')
        $audit.Total | Should -Be 4
        $audit.Complete | Should -Be 1
        $audit.Partial | Should -Be 1
        $audit.Missing | Should -Be 1
        $audit.Unknown | Should -Be 1
        $summary = Get-TpmControlCoverageAuditSummary -Audit $audit
        $summary.Status | Should -Be 'Attention'
        ($summary.Done -join ' ') | Should -Match 'Games with every required control the game lists set up: 1 of 4'
        $detail = ($summary.Blocks | ForEach-Object { $_.Lines }) -join ' '
        $detail | Should -Match 'some: still needed|some.*Gun Trigger'
        ($summary.Done + $summary.Needs + $summary.Note) -join ' ' | Should -Not -Match '(?i)\bready\b|\bverified\b'
        $summary.Note | Should -Match 'not tested any game with a real controller'
    }
}
