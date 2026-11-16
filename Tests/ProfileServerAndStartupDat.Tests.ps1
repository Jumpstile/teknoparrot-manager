#Requires -Module Pester

# Real user-visible bugs, each with the user it hurts. The production script is parsed; only function definitions
# and cut-out start-up statements are run. Everything lives under TestDrive with synthetic files.
#   1. A game profile that has the local PostgreSQL password but points at another server must be left alone.
#   2. A dat file set only in TeknoParrot-Manager.overrides.json counts as configured before the start-up question.
#   3. The end of a registration run must not say "fix the items under ACTION REQUIRED" after the last item was fixed.

BeforeAll {
    $productionPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null
    $parseErrors = $null
    $script:PsdAst = [System.Management.Automation.Language.Parser]::ParseFile($productionPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'These tests could not parse the production script.' }

    $wanted = @('Get-PostgresProfilePassDecision', 'Get-PostgresFieldValue', 'ConvertTo-XPathStringLiteral', 'Get-RelativePath', 'Get-TpmFullFolderPath', 'Resolve-TpmLaunchBoxRoot', 'Get-EggmanDatRelease', 'Test-EggmanDatReleaseUrl')
    $definitions = @($script:PsdAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    $functionFile = Join-Path $TestDrive 'tpm-psd-functions.ps1'
    [System.IO.File]::WriteAllText($functionFile, (@($definitions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"), (New-Object System.Text.UTF8Encoding $false))
    . $functionFile

    function New-PsdProfile {
        param([string]$Pass = '', [string]$Address = '', [string]$Port = '', [string]$User = '')
        $doc = New-Object System.Xml.XmlDocument
        $fields = foreach ($pair in @(@('Pass', $Pass), @('Address', $Address), @('Port', $Port), @('User', $User))) {
            ('<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>{0}</FieldName><FieldValue>{1}</FieldValue></FieldInformation>' -f $pair[0], $pair[1])
        }
        $doc.LoadXml('<GameProfile><ConfigValues>' + ($fields -join '') + '</ConfigValues></GameProfile>')
        return $doc
    }

    function Get-PsdBlock {
        param([Parameter(Mandatory)][scriptblock]$Match)
        $found = @($script:PsdAst.FindAll($Match, $true))
        if ($found.Count -ne 1) { throw ('Expected exactly one matching statement in the production script, found {0}.' -f $found.Count) }
        return $found[0]
    }
}

Describe 'PostgreSQL setup never repoints a game that uses another server' {
    # Who gets hurt: a user whose game profile uses their own database server (and happens to reuse the local password).
    # Mutation: return 'Same' as soon as the password matches, before the user, address and port are looked at.
    It 'asks about a profile with the local password but <Name>' -ForEach @(
        @{ Name = 'another address'; Address = '192.168.1.50'; Port = '5432'; User = 'postgres'; Reason = "*address '192.168.1.50'*" },
        @{ Name = 'another port'; Address = '127.0.0.1'; Port = '5433'; User = 'postgres'; Reason = '*port 5433*' },
        @{ Name = 'another user'; Address = '127.0.0.1'; Port = '5432'; User = 'admin'; Reason = "*user 'admin'*" }
    ) {
        $doc = New-PsdProfile -Pass 'local-secret' -Address $Address -Port $Port -User $User
        $decision = Get-PostgresProfilePassDecision -Doc $doc -SuperPasswordPlain 'local-secret'
        $decision.Decision | Should -BeExactly 'NeedsApproval'
        ($decision.Reasons -join ' ') | Should -BeLike $Reason
        ($decision.Reasons -join ' ') | Should -Not -Match 'different PostgreSQL password'
    }

    It 'still treats a local profile with the local password as already right' -ForEach @(
        @{ Address = '127.0.0.1'; Port = '5432'; User = 'postgres' },
        @{ Address = 'localhost'; Port = '5432'; User = 'Postgres' },
        @{ Address = ''; Port = ''; User = '' }
    ) {
        (Get-PostgresProfilePassDecision -Doc (New-PsdProfile -Pass 'local-secret' -Address $Address -Port $Port -User $User) -SuperPasswordPlain 'local-secret').Decision | Should -BeExactly 'Same'
    }

    It 'fills a blank password and asks about a different one' {
        (Get-PostgresProfilePassDecision -Doc (New-PsdProfile -Pass '' -Address '127.0.0.1' -Port '5432' -User 'postgres') -SuperPasswordPlain 'local-secret').Decision | Should -BeExactly 'FillBlank'
        $other = Get-PostgresProfilePassDecision -Doc (New-PsdProfile -Pass 'someone-else' -Address '127.0.0.1' -Port '5432' -User 'postgres') -SuperPasswordPlain 'local-secret'
        $other.Decision | Should -BeExactly 'NeedsApproval'
        ($other.Reasons -join ' ') | Should -Match 'different PostgreSQL password'
    }
}

Describe 'A dat file set only in the overrides file is known before the start-up DAT question' {
    BeforeAll {
        $script:PsdEarlyRead = Get-PsdBlock -Match {
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
            $args[0].Clauses[0].Item1.Extent.Text -ceq '-not $datFilePath' -and
            $args[0].Clauses[0].Item2.Extent.Text -match 'overrides\.json'
        }
        function Invoke-PsdEarlyRead {
            param($OverridesJson, [string]$Existing = '')
            $fixtureScriptRoot = Join-Path $TestDrive ('psd-' + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($fixtureScriptRoot)
            if ($null -ne $OverridesJson) { [System.IO.File]::WriteAllText((Join-Path $fixtureScriptRoot 'TeknoParrot-Manager.overrides.json'), $OverridesJson, (New-Object System.Text.UTF8Encoding $false)) }
            $datFilePath = $Existing
            . ([scriptblock]::Create($script:PsdEarlyRead.Extent.Text.Replace('$PSScriptRoot', '$fixtureScriptRoot')))
            return $datFilePath
        }
    }

    It 'uses the dat file named only in the overrides file' {
        # Mutation: remove the early read -> the question is asked every run and the recap says no DAT is set up.
        $realDat = Join-Path $TestDrive 'early-collection.dat'
        [System.IO.File]::WriteAllText($realDat, '<datafile />')
        Invoke-PsdEarlyRead -OverridesJson (@{ datFile = $realDat } | ConvertTo-Json) | Should -BeExactly $realDat
    }

    It 'keeps a dat file that is already configured, and ignores a blank key, a missing file or a damaged file' {
        Invoke-PsdEarlyRead -OverridesJson '{"datFile":"D:\\other.dat"}' -Existing 'C:\saved.dat' | Should -BeExactly 'C:\saved.dat'
        Invoke-PsdEarlyRead -OverridesJson '{"datFile":""}' | Should -BeExactly ''
        Invoke-PsdEarlyRead -OverridesJson '{"datFile":"Z:\\gone\\old.dat"}' | Should -BeExactly ''
        Invoke-PsdEarlyRead -OverridesJson $null | Should -BeExactly ''
        Invoke-PsdEarlyRead -OverridesJson '{ not json' | Should -BeExactly ''
    }

    It 'does not replace a dat file the user just chose with an overrides dat file that is not there' {
        # Who gets hurt: a user whose overrides dat file is gone, who then browses to a good one at start-up; the later overrides step put the missing path back.
        # Mutation: apply $ov.datFile without checking that the file exists.
        $loader = Get-PsdBlock -Match {
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
            $args[0].Clauses[0].Item1.Extent.Text -ceq 'Test-Path -LiteralPath $overridesPath' -and
            $args[0].Clauses[0].Item2.Extent.Text -match 'ConvertFrom-Json'
        }
        $realDat = Join-Path $TestDrive 'real-collection.dat'
        [System.IO.File]::WriteAllText($realDat, '<datafile />')
        foreach ($case in @(
            @{ Dat = (Join-Path $TestDrive 'gone.dat'); Existing = 'C:\chosen.dat'; Expected = 'C:\chosen.dat' },
            @{ Dat = $realDat; Existing = ''; Expected = $realDat }
        )) {
            $overridesPath = Join-Path $TestDrive ('psd-ov-' + [guid]::NewGuid().ToString('N') + '.json')
            [System.IO.File]::WriteAllText($overridesPath, (@{ datFile = $case.Dat } | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))
            $noSyncList = @(); $onlySyncList = @(); $noPropagateList = @(); $forceArchetypeMap = @{}; $familyOverrideMap = @{}
            $canonicalArchetypeMap = @{}; $subFolderMap = @{}; $validFamilies = @('button', 'driving', 'lightgun', 'trackball', 'analog', 'spinner')
            $datFilePath = $case.Existing
            function Write-Log { param($Message) }
            function Show-TpmOverridesNotice { param($Counts, $FilePath) }
            . ([scriptblock]::Create($loader.Extent.Text))
            $datFilePath | Should -BeExactly $case.Expected
        }
    }
}

Describe 'The start-up DAT steps keep a saved ZIP and tell the recap what was chosen' {
    BeforeAll {
        $script:PsdEarlyRead = Get-PsdBlock -Match {
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
            $args[0].Clauses[0].Item1.Extent.Text -ceq '-not $datFilePath' -and
            $args[0].Clauses[0].Item2.Extent.Text -match 'overrides\.json'
        }
        $script:PsdMissingDat = @($script:PsdAst.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
            $args[0].Clauses[0].Item1.Extent.Text -like '*$eggmanDatZip -and -not (Test-Path*' -and $args[0].Clauses[0].Item1.Extent.Text -like '*$datFilePath -and -not (Test-Path*'
        }, $true))[0]
        $script:PsdDatQuestion = @($script:PsdAst.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
            $args[0].Clauses[0].Item1.Extent.Text -like '*-not $eggmanDatZip -and -not $datFilePath*' -and
            @($args[0].FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'Read-TpmChoice' }, $true)).Count -gt 0
        }, $true))[0]
        $script:PsdActionStart = Get-PsdBlock -Match {
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -ceq '$eggmanDatActionThisRun' -and $args[0].Right.Extent.Text -like '*NotConfigured*'
        }
        function Write-Log { param($Message) }
        function Write-TpmText { param($Text, $Color, $Indent, [switch]$BlankBefore, [switch]$BlankAfter) }
        function Test-TpmStartupBlankLineAlreadyWritten { return $false }
        function Get-EggmanDatDataRoot { return 'C:\Eggman' }
        function Get-EggmanDatRelease { return $null }
        function Test-EggmanDatZip { param($Path) return $true }
        function Read-TpmChoice { param($Prompt, $Choices, $Default) return $script:PsdAnswer }
        function Read-TpmYesNo { param($Prompt, $Default) return $script:PsdAnswer }
        function Read-PathWithBrowse { param($Prompt, $Mode, $FileFilter) return $script:PsdBrowse }
        # Runs the early overrides read, the missing-DAT check, the recap value and the DAT question in one scope, as the start-up does.
        function Invoke-PsdStartupDat {
            param([string]$OverridesJson, [string]$Zip = '', [string]$Answer = 'N', [string]$Browse = '', [string]$Dat = '')
            $fixtureScriptRoot = Join-Path $TestDrive ('psd-start-' + [guid]::NewGuid().ToString('N'))
            [void][System.IO.Directory]::CreateDirectory($fixtureScriptRoot)
            if ($OverridesJson) { [System.IO.File]::WriteAllText((Join-Path $fixtureScriptRoot 'TeknoParrot-Manager.overrides.json'), $OverridesJson, (New-Object System.Text.UTF8Encoding $false)) }
            $script:PsdAnswer = $Answer
            $script:PsdBrowse = $Browse
            $eggmanDatZip = $Zip
            $datFilePath = $Dat
            $Unattended = $false
            $isPostgresRecoveryResume = $false
            $tpmPrintedAfterSavedSettings = $false
            . ([scriptblock]::Create($script:PsdEarlyRead.Extent.Text.Replace('$PSScriptRoot', '$fixtureScriptRoot')))
            . ([scriptblock]::Create($script:PsdMissingDat.Extent.Text))
            . ([scriptblock]::Create($script:PsdActionStart.Extent.Text))
            . ([scriptblock]::Create($script:PsdDatQuestion.Extent.Text))
            return [pscustomobject]@{ Zip = $eggmanDatZip; Dat = $datFilePath; Action = $eggmanDatActionThisRun }
        }
    }

    It 'keeps a saved DAT ZIP when the overrides file names a dat file that is gone, and answering N changes nothing' {
        # Who gets hurt: a user with a working saved DAT ZIP and an old overrides dat path lost the ZIP setting at every start.
        # Mutation: read the overrides dat file without checking that it exists.
        $zip = Join-Path $TestDrive 'eggman-saved.zip'
        [System.IO.File]::WriteAllText($zip, 'zip')
        $state = Invoke-PsdStartupDat -OverridesJson '{"datFile":"Z:\\gone\\old.dat"}' -Zip $zip -Answer 'N'
        $state.Zip | Should -BeExactly $zip
        $state.Dat | Should -BeExactly ''
        $state.Action | Should -BeExactly 'Reused'
    }

    It 'tells the recap about a DAT the user browsed to at the start-up question: <Name>' -ForEach @(
        @{ Name = 'ZIP'; File = 'browsed.zip' },
        @{ Name = 'dat file'; File = 'browsed.dat' }
    ) {
        # Who gets hurt: a user who picked a DAT was told at the end that no DAT is set up and sent to register games by hand.
        # Mutation: do not update the recap value in the browse branches.
        $picked = Join-Path $TestDrive $File
        [System.IO.File]::WriteAllText($picked, 'dat')
        $state = Invoke-PsdStartupDat -Answer 'B' -Browse $picked
        $state.Action | Should -BeExactly 'Reused'
        ($state.Zip + $state.Dat) | Should -BeExactly $picked
    }

    It 'still says no DAT is configured when the user skips the question' {
        (Invoke-PsdStartupDat -Answer 'N').Action | Should -BeExactly 'NotConfigured'
    }

    It 'keeps the saved <Kept> when only the <Gone> is missing' -ForEach @(
        @{ Kept = 'DAT file'; Gone = 'ZIP' },
        @{ Kept = 'ZIP'; Gone = 'DAT file' }
    ) {
        # Who gets hurt: a user whose moved DAT ZIP (or DAT file) made the start-up erase the other, working DAT from the saved settings.
        # Mutation: blank both values when either is missing.
        $good = Join-Path $TestDrive ('keep-' + [guid]::NewGuid().ToString('N') + '.dat')
        [System.IO.File]::WriteAllText($good, 'dat')
        $gone = 'Z:\gone\moved.dat'
        $state = if ($Kept -eq 'DAT file') { Invoke-PsdStartupDat -Zip $gone -Dat $good } else { Invoke-PsdStartupDat -Zip $good -Dat $gone }
        if ($Kept -eq 'DAT file') { $state.Dat | Should -BeExactly $good; $state.Zip | Should -BeExactly '' } else { $state.Zip | Should -BeExactly $good; $state.Dat | Should -BeExactly '' }
        $state.Action | Should -BeExactly 'Reused'
    }
}

Describe 'LaunchBox paths relative to the LaunchBox folder' {
    # Who gets hurt: a user with a % or # in a game or TeknoParrot folder name got a wrong ApplicationPath written into LaunchBox XML
    # (on PowerShell 7 "save%41" came back as "saveA"). Mutation: build the URIs from the raw paths again.
    It 'gives <Expected> for <Name>' -ForEach @(
        @{ Name = 'a % only in the target'; Base = 'C:\LB'; Target = 'C:\LB\save%41\x.xml'; Expected = 'save%41\x.xml' },
        @{ Name = 'a # only in the target'; Base = 'C:\LB'; Target = 'C:\LB\Game #1\x.xml'; Expected = 'Game #1\x.xml' },
        @{ Name = 'a % in the LaunchBox folder'; Base = 'C:\LB 100%41\Root'; Target = 'C:\TP\TeknoParrotUi.exe'; Expected = '..\..\TP\TeknoParrotUi.exe' },
        @{ Name = 'a # in the TeknoParrot folder'; Base = 'C:\LB'; Target = 'C:\TP #3\TeknoParrotUi.exe'; Expected = '..\TP #3\TeknoParrotUi.exe' },
        @{ Name = 'another drive'; Base = 'C:\LB'; Target = 'D:\TP\TeknoParrotUi.exe'; Expected = 'D:\TP\TeknoParrotUi.exe' },
        @{ Name = 'two shares of one server'; Base = '\\nas\launchbox'; Target = '\\nas\tekno\TeknoParrotUi.exe'; Expected = '\\nas\tekno\TeknoParrotUi.exe' },
        @{ Name = 'two folders of one share'; Base = '\\nas\games\LB'; Target = '\\nas\games\TP\TeknoParrotUi.exe'; Expected = '..\TP\TeknoParrotUi.exe' }
    ) {
        Get-RelativePath $Base $Target | Should -BeExactly $Expected
    }
}

Describe 'The end of a registration run after the missing game startup files were copied' {
    BeforeAll {
        $assignment = Get-PsdBlock -Match {
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and $args[0].Left.Extent.Text -ceq '$testAnyAction'
        }
        $review = Get-PsdBlock -Match {
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and $args[0].Clauses[0].Item1.Extent.Text -ceq '$prerequisiteReview.FixedAny'
        }
        $script:PsdRecheckText = $assignment.Extent.Text + "`r`n" + '$hasAnyAction = [bool](& $testAnyAction)' + "`r`n" + $review.Extent.Text
        function New-PsdWarnings { param([object[]]$BiosMissing = @()) return [pscustomobject]@{ PathTooLong = @(); DllMismatch = @(); GpuIncompatible = @(); BiosMissing = $BiosMissing; ExeMissing = @() } }
        function Get-CompatibilityWarnings { param($UserProfilesDir, $TeknoParrotRoot) return (New-PsdWarnings) }
        function Write-TpmText { param($Text, $Color, [switch]$BlankBefore) }
        function Invoke-PsdRecheck {
            param([bool]$FixedAny)
            $manualRegData = @{}; $amb2 = @(); $nf = @(); $result = [pscustomobject]@{ Unmatched = @() }
            $onboardingFollowUp = @(); $controlReadinessItems = @()
            $userProfilesDir = 'x'; $tpRoot = 'y'
            $compatWarnings = New-PsdWarnings -BiosMissing @('PS2 firmware')
            $prerequisiteReview = [pscustomobject]@{ FixedAny = $FixedAny }
            . ([scriptblock]::Create($script:PsdRecheckText))
            return $hasAnyAction
        }
    }

    It 'has no action left when the copy fixed the only item' {
        # Mutation: remove the $hasAnyAction refresh after the firmware copy -> "Then fix the items under ACTION REQUIRED above." and an empty saved report.
        Invoke-PsdRecheck -FixedAny $true | Should -BeFalse
    }

    It 'still has an action when nothing was copied' {
        Invoke-PsdRecheck -FixedAny $false | Should -BeTrue
    }
}

Describe 'LaunchBox folder prompt' {
    # Who gets hurt: a user who pastes the LaunchBox folder with Explorer's "Copy as path" (quotes included) was refused although the folder was right.
    # Mutation: go back to resolving the raw text, quotes and all.
    It 'accepts a folder pasted with quotes and spaces around it' {
        $dir = Join-Path $TestDrive 'Launch Box'
        [void][System.IO.Directory]::CreateDirectory($dir)
        Resolve-TpmLaunchBoxRoot ('  "' + $dir + '"  ') | Should -BeExactly $dir
        Resolve-TpmLaunchBoxRoot ($dir + '\') | Should -BeExactly $dir
    }

    It 'still refuses an empty answer' {
        { Resolve-TpmLaunchBoxRoot '  ' } | Should -Throw 'Choose a safe existing LaunchBox root.'
    }
}

Describe 'Eggman DAT release lookup tells "no file" from "could not reach GitHub"' {
    # Who gets hurt: when the release page changes, every user would be told to fix their internet. Mutation: return $null for a release without the DAT ZIP.
    BeforeAll {
        function Write-Log { param($Message) }
        function Get-TpmHttpStatusCodeFromError { param($ErrorRecord) return 404 }
        function Invoke-TpmWebRequestSilently { param($Uri, [switch]$UseBasicParsing, $TimeoutSec, $Headers) if ($script:PsdRelease -is [string]) { return [pscustomobject]@{ Content = $script:PsdRelease } } throw 'simulated GitHub failure' }
    }

    It 'says GitHub answered but has no DAT file' {
        $script:PsdRelease = '{"assets":[{"name":"notes.txt","browser_download_url":"https://github.com/Eggmansworld/TeknoParrot/releases/download/x/notes.txt","size":10}]}'
        $release = Get-EggmanDatRelease
        $release | Should -Not -BeNullOrEmpty
        $release.DownloadUrl | Should -BeExactly ''
    }

    It 'says it could not reach GitHub when the request fails' {
        $script:PsdRelease = $null
        Get-EggmanDatRelease | Should -BeNullOrEmpty
    }
}
