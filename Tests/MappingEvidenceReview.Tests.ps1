#Requires -Module Pester

# Outside mapping evidence review (issue #304).
# What a user sees or loses: an outside controller list is never trusted or applied; a game is held back with a plain reason
# when the list is doubtful (not installed, named twice, unknown button, control the game lacks, two actions on one button);
# every proposal keeps its source line and original text and is tied to the installed profile's revision and hash; the check
# changes no game file; and the same inputs always give the same details file.
# Fixtures are small fake game profiles and a fake list in a temp folder. What this CANNOT prove: that the real outside list
# or real TeknoParrot profiles give the same counts.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Mapping evidence tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $functionFile = Join-Path $TestDrive 'tpm-evidence-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $functionFile
    function Write-Log { param($msg) }

    function script:New-GameProfile {
        param([string]$Dir, [string]$Name, [string[]]$Mappings, [string]$Revision = '7')
        $buttons = foreach ($m in $Mappings) { "<JoystickButtons><ButtonName>$m</ButtonName><InputMapping>$m</InputMapping></JoystickButtons>" }
        $xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><GameProfile><GameProfileRevision>$Revision</GameProfileRevision><JoystickButtons>$(-join $buttons)</JoystickButtons></GameProfile>"
        [System.IO.File]::WriteAllText((Join-Path $Dir ($Name + '.xml')), $xml, (New-Object System.Text.UTF8Encoding $false))
    }
    function script:Get-Entry { param($Review, [string]$Name) return @($Review.Entries | Where-Object Name -eq $Name)[0] }
}

Describe 'Outside mapping evidence review' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ('tp-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
        $script:Profiles = Join-Path $script:Root 'GameProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:Profiles)
        New-GameProfile -Dir $script:Profiles -Name 'goodgame' -Mappings @('Test', 'Service1', 'Coin1', 'Coin2', 'P1ButtonStart', 'P1Button1')
        New-GameProfile -Dir $script:Profiles -Name 'wheelgame' -Mappings @('Coin1', 'P1ButtonStart', 'Analog0', 'Analog2', 'Analog4')
        New-GameProfile -Dir $script:Profiles -Name 'gunner' -Mappings @('Coin1', 'P1ButtonStart', 'P1Button1')
        New-GameProfile -Dir $script:Profiles -Name 'twice' -Mappings @('Coin1')
        New-GameProfile -Dir $script:Profiles -Name 'partialgame' -Mappings @('Coin1', 'P1ButtonStart', 'P1Button1', 'P1Button2')
        $script:ListPath = Join-Path $script:Root 'list.yml'
        $list = @"
# comment
goodgame:
  Test: l3 # Test
  Service1: r3 # Service
  Coin1: select # Coin 1
  Coin2: select # Coin 2
  P1ButtonStart: start # Start
  P1Button1: south # Shoot

notinstalled:
  Coin1: select # Coin

twice:
  Coin1: select # Coin
twice:
  Coin1: start # Coin

wheelgame:
  Coin1: select # Coin
  P1ButtonStart: start # Start
  Analog0: rightstickleft # P1 Wheel
  Analog2: rightstickleft # P1 Brake
  Analog4: leftstickleft # P2 Wheel

gunner:
  Coin1: select # Coin
  P1ButtonStart: start # Start
  P1Button1: rigthstickup # Shoot
  P1Button2: south # Not in this game
  P1Button3: banana # Not a button

gunner_gun:
  mouseleft_1: P1Button1 # Trigger

partialgame:
  Coin1: select # Coin
  P1ButtonStart: start # Start
  P1Button1: south # A
  P1Button2:   # not mapped
"@
        [System.IO.File]::WriteAllText($script:ListPath, $list, (New-Object System.Text.UTF8Encoding $false))
        $script:Review = Get-TpmMappingEvidenceReview -Evidence (Read-TpmMappingEvidenceFile -Path $script:ListPath) -GameProfilesDir $script:Profiles
    }

    It 'keeps a clean game for review, with its source line, original text and installed profile identity' {
        $e = Get-Entry $script:Review 'goodgame'
        $e.Status | Should -Be 'ReadyForReview'
        $p = @($e.Proposals | Where-Object Mapping -eq 'Coin1')[0]
        $p.Target | Should -Be 'select'
        $p.SourceValue | Should -Be 'select'
        $p.SourceLine | Should -BeGreaterThan 0
        $e.Identity.GameProfileRevision | Should -Be '7'
        $e.Identity.GameProfileSha256 | Should -Be (Get-FileHash -LiteralPath (Join-Path $script:Profiles 'goodgame.xml') -Algorithm SHA256).Hash
        $script:Review.Trust | Should -Be 'NonAuthoritative'
        $script:Review.Source.Sha256 | Should -Be (Get-FileHash -LiteralPath $script:ListPath -Algorithm SHA256).Hash
    }

    It 'holds back a game that is not installed and a game the list names twice' {
        (Get-Entry $script:Review 'notinstalled').Reasons | Should -Contain 'NotInstalled'
        $twice = @($script:Review.Entries | Where-Object Name -eq 'twice')
        $twice.Count | Should -Be 2
        foreach ($t in $twice) { $t.Status | Should -Be 'Withheld'; $t.Reasons | Should -Contain 'DuplicateEntry' }
    }

    It 'holds back two actions on one button but not Coin 1 and Coin 2, and not another player''s axis' {
        $wheel = Get-Entry $script:Review 'wheelgame'
        $wheel.Status | Should -Be 'Withheld'
        $wheel.Reasons | Should -Be @('Collision')
        $wheel.Problems[0].Field | Should -Be 'Analog0 + Analog2'
        (Get-Entry $script:Review 'goodgame').Reasons | Should -Not -Contain 'Collision'
    }

    It 'names a control the game lacks and a button TPM does not know, and corrects a known spelling mistake' {
        $g = Get-Entry $script:Review 'gunner'
        $g.Status | Should -Be 'Withheld'
        $g.Reasons | Should -Contain 'FieldNotInGame'
        $g.Reasons | Should -Contain 'UnknownTarget'
        $g.Normalized[0].Written | Should -Be 'rigthstickup'
        $g.Normalized[0].Used | Should -Be 'rightstickup'
    }

    It 'reads a gun layout (mouse button as the key) against the game it belongs to' {
        $v = Get-Entry $script:Review 'gunner_gun'
        $v.Profile | Should -Be 'gunner'
        $v.Variant | Should -Be 'gun'
        $v.Status | Should -Be 'ReadyForReview'
        $v.Proposals[0].Mapping | Should -Be 'P1Button1'
        $v.Proposals[0].Target | Should -Be 'mouseleft_1'
    }

    It 'marks a game Partial, not ready, when the list leaves one of its controls unmapped' {
        $e = Get-Entry $script:Review 'partialgame'
        $e.Status | Should -Be 'Partial'
        $e.MissingFromList | Should -Be @('P1Button2')
    }

    It 'prints plain counts and says the list is not trusted' {
        $text = (Get-TpmMappingEvidenceReviewLines -Review $script:Review) -join "`n"
        $text | Should -Match 'Nothing was changed'
        $text | Should -Match 'does not trust it'
        $text | Should -Match 'Held back, the game is not in your TeknoParrot: 1'
        $text | Should -Not -Match '(?i)collision|InputMapping|XInput'
    }

    It 'changes no game file, writes only the details file, and gives the same file every time' {
        $before = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash })
        $json1 = Join-Path $script:Root 'out1.json'
        $json2 = Join-Path $script:Root 'out2.json'
        (Invoke-TpmMappingEvidenceReport -EvidencePath $script:ListPath -TeknoParrotRoot $script:Root -JsonPath $json1 6>$null) | Should -Be 0
        (Invoke-TpmMappingEvidenceReport -EvidencePath $script:ListPath -TeknoParrotRoot $script:Root -JsonPath $json2 6>$null) | Should -Be 0
        (Get-FileHash -LiteralPath $json1).Hash | Should -Be (Get-FileHash -LiteralPath $json2).Hash
        $after = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File | Where-Object { $_.Name -notlike 'out*.json' } | ForEach-Object { $_.FullName + ':' + (Get-FileHash -LiteralPath $_.FullName).Hash })
        $after | Should -Be $before
        (Get-Content -LiteralPath $json1 -Raw) | Should -Match 'TPM\.MappingEvidenceReview\.v1'
    }

    It 'refuses to overwrite a file that is not one of its own reports' {
        $other = Join-Path $script:Root 'notes.json'
        Set-Content -LiteralPath $other -Value 'my own notes'
        (Invoke-TpmMappingEvidenceReport -EvidencePath $script:ListPath -TeknoParrotRoot $script:Root -JsonPath $other 6>$null) | Should -Be 1
        (Get-Content -LiteralPath $other -Raw).Trim() | Should -Be 'my own notes'
    }

    It 'holds back a control whose label names a different cabinet role, and keeps a matching label' {
        New-GameProfile -Dir $script:Profiles -Name 'labelgame' -Mappings @('Coin1', 'P1ButtonStart', 'P1Button1')
        $path = Join-Path $script:Root 'labels.yml'
        [System.IO.File]::WriteAllText($path, "labelgame:`n  Coin1: start # Coin 1`n  P1ButtonStart: select # Coin`n  P1Button1: south # Shoot`n", (New-Object System.Text.UTF8Encoding $false))
        $review = Get-TpmMappingEvidenceReview -Evidence (Read-TpmMappingEvidenceFile -Path $path) -GameProfilesDir $script:Profiles
        $e = Get-Entry $review 'labelgame'
        $e.Status | Should -Be 'Withheld'
        $e.Reasons | Should -Be @('SemanticDisagreement')
        @($e.Problems).Count | Should -Be 1
        $e.Problems[0].Field | Should -Be 'P1ButtonStart'
    }

    It 'records the pinned source commit and holds back a game file that changed since the last check of the same list' {
        $json = Join-Path $script:Root 'pinned.json'
        (Invoke-TpmMappingEvidenceReport -EvidencePath $script:ListPath -TeknoParrotRoot $script:Root -JsonPath $json -SourceCommit '981052e87fa5b6a8f7fc4b29691194c34cfe96f4' 6>$null) | Should -Be 0
        $first = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $first.Source.Commit | Should -Be '981052e87fa5b6a8f7fc4b29691194c34cfe96f4'
        (Get-Entry $first 'goodgame').Status | Should -Be 'ReadyForReview'
        New-GameProfile -Dir $script:Profiles -Name 'goodgame' -Mappings @('Test', 'Service1', 'Coin1', 'Coin2', 'P1ButtonStart', 'P1Button1') -Revision '8'
        (Invoke-TpmMappingEvidenceReport -EvidencePath $script:ListPath -TeknoParrotRoot $script:Root -JsonPath $json 6>$null) | Should -Be 0
        $second = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $stale = Get-Entry $second 'goodgame'
        $stale.Status | Should -Be 'Withheld'
        $stale.Reasons | Should -Contain 'StaleIdentity'
        (Get-Entry $second 'partialgame').Reasons | Should -Not -Contain 'StaleIdentity'
    }

    It 'refuses a source commit that is not hexadecimal and writes nothing' {
        $json = Join-Path $script:Root 'bad.json'
        (Invoke-TpmMappingEvidenceReport -EvidencePath $script:ListPath -TeknoParrotRoot $script:Root -JsonPath $json -SourceCommit 'not a commit' 6>$null) | Should -Be 1
        Test-Path -LiteralPath $json | Should -BeFalse
    }
}
