#Requires -Module Pester

# FIX21A R4 regression coverage. The REAL Register-GamesLegacy,
# Backfill-SecondaryExecutablePath and Confirm-TpmRegistrationSafetyBackup
# (plus the pure matching/XML helpers they use) are extracted from the parsed
# manager. Every non-preview profile save must be preceded by a verified
# safety backup, and a missing backup state must fail that game instead of
# writing an unprotected profile. Only the backup creator, the save, the
# read-back, logging/progress and the registration ledger are faked; all
# fixtures are tiny files under $TestDrive.
#
# Save sites covered (one fixture shape per site):
#   ExeFuzzy     - shared exe name, confident folder-name fuzzy match (exe-fuzzy)
#   ExeDat       - shared exe name, no confident fuzzy match, dat entry (dat-exact)
#   ExeSingle    - exe name owned by exactly one profile (exe-single)
#   DatPass2     - exe name unknown, dat entry for the folder (dat-pass2)
#   CodePass3    - exe name unknown, no dat, folder fuzzy-matches a profile code (code-pass3)
#   SubFolderMap - subFolderMap entry under the TeknoParrot root (subfolder-map)
#   Backfill     - existing profile that only needs GamePath2 (Backfill-SecondaryExecutablePath)
BeforeDiscovery {
    $fix21aSites = @(
        @{ Site = 'ExeFuzzy'; Code = 'AlphaRacer' }
        @{ Site = 'ExeDat'; Code = 'ZetaQuest' }
        @{ Site = 'ExeSingle'; Code = 'SoloRun' }
        @{ Site = 'DatPass2'; Code = 'NeonHarbor' }
        @{ Site = 'CodePass3'; Code = 'CobaltStrike' }
        @{ Site = 'SubFolderMap'; Code = 'WiiTitle' }
        @{ Site = 'Backfill'; Code = 'TwinDrive' }
    )
}

BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }

    $fix21aWanted = @(
        'Register-GamesLegacy',
        'Backfill-SecondaryExecutablePath',
        'Confirm-TpmRegistrationSafetyBackup',
        'Set-SecondaryExecutablePath', 'Get-TpmMissingGameSetFiles', 'Get-TpmGameFileSet', 'Get-ExeAlternatives',
        'Test-TpmGameMutationPath',
        'Add-TpmUnavailableDriveGame',
        'Get-TpmTransactionField',
        'Read-Xml',
        'Get-PrimaryExecutableName',
        'Get-NormalizedGameKey',
        'Get-DiceSimilarity',
        'Get-TpmBaseTitleKey', 'Resolve-BestFuzzyMatch', 'Get-TpmTeknoParrotNamesForCodes', 'Get-TpmTeknoParrotGameName', 'Get-TpmTeknoParrotMetadataFacts',
        'Resolve-ProfileCode',
        'Get-GameFiles',
        'Save-XmlMaybe', 'Get-TpmProfileWriteFingerprint', 'Resolve-TpmRegistrationSaveFailure',
        'New-TpmVerifiedUserProfilesBackup',
        'Assert-TpmRegisteredGamePath',
        'Set-TpmRegistrationGamePath', 'Get-DatEntryForZipName', 'Get-TpmZipBaseName',
        'Get-TpmProfileFileExtensions', 'Get-TpmDatNamedProfileCodes', 'Register-TpmDatSecondProfiles'
    )
    $functions = @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -in $fix21aWanted
        }, $true)
    )
    $foundNames = @($functions | ForEach-Object { $_.Name } | Sort-Object -Unique)
    if ($functions.Count -ne $fix21aWanted.Count -or $foundNames.Count -ne $fix21aWanted.Count) {
        throw ("Expected exactly one definition of each of: {0}. Found: {1}" -f ($fix21aWanted -join ', '), (($functions | ForEach-Object { $_.Name }) -join ', '))
    }
    $functionPath = Join-Path $TestDrive ('fix21a-register-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    # Top-level production constants that AST function extraction never sees.
    $script:RawThrillsPathLimits = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1

    $script:fix21aLog = New-Object System.Collections.Generic.List[string]
    $script:fix21aHost = New-Object System.Collections.Generic.List[string]
    $script:fix21aEvents = New-Object System.Collections.Generic.List[string]

    # Logging, compact progress and the registration evidence ledger are outside
    # this backup-gate test: keep them inert (no ledger configured, never stopped).
    function Write-Log {
        param([string]$msg)
        [void]$script:fix21aLog.Add($msg)
    }
    function Write-TpmCompactExtractionProgress {
        param([string]$Phase, [string]$Label, [int]$Current, [int]$Total, [datetime]$StartedAt, [switch]$Complete, [string]$Outcome = 'Final')
    }
    function Get-TpmRegisteredProfileFilesWithDiscoveryProgress {
        param([string]$UserProfilesDir, [string]$ProgressLabel, [string]$EnumerationErrorAction)
        return @(Get-ChildItem -LiteralPath $UserProfilesDir -Filter '*.xml' -File -ErrorAction SilentlyContinue)
    }
    function Test-TpmRegistrationLedgerConfigured { return $false }
    function Test-TpmRegistrationLedgerStopped { return $false }
    function Start-TpmRegistrationMapping {
        param([string]$Folder, [string]$Code, [string]$Match, [string]$IntendedPath, [string]$TemplatePath, [bool]$DryRun = $false)
        return $null
    }
    function Complete-TpmRegistrationMapping {
        param([string]$MappingId, [string]$Outcome, [bool]$WriteAttempted = $false, [string]$Reason = '')
    }
    function Add-TpmRegistrationMappingFailure {
        param([string]$Folder, [string]$Code, [string]$Match, [string]$Reason, [string]$TemplatePath = '', [bool]$DryRun = $false)
    }

    function New-Fix21AFile {
        param([Parameter(Mandatory)][string]$Path, [string]$Text = 'fixture')
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
        return $Path
    }
    function New-Fix21ATemplate {
        param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Code, [string]$ExecutableName = '')
        $path = Join-Path $Dir ($Code + '.xml')
        [void](New-Fix21AFile -Path $path -Text ('<GameProfile><GamePath></GamePath><ExecutableName>{0}</ExecutableName></GameProfile>' -f $ExecutableName))
        return $path
    }

    # Builds the smallest fixture that drives Register-GamesLegacy to exactly one
    # profile save site and returns the arguments plus the expected save target.
    function New-Fix21AScenario {
        param([Parameter(Mandatory)][string]$Site)
        $root = Join-Path $TestDrive ('fix21a-' + $Site + '-' + [guid]::NewGuid().ToString('N'))
        $games = Join-Path $root 'Games'
        $userProfiles = Join-Path $root 'UserProfiles'
        $gameProfiles = Join-Path $root 'GameProfiles'
        $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $games, $userProfiles, $gameProfiles, $tpRoot -Force | Out-Null
        $profileIndex = @{}
        $datIndex = @{}
        $profileSet = $null
        $subFolderMap = @{}
        $kind = 'Register'
        $code = $null
        switch ($Site) {
            'ExeFuzzy' {
                # game.exe is shared by two profiles; folder 'AlphaRacer' scores 1.0
                # against AlphaRacer and 0 against ZetaQuest -> confident exe-fuzzy save.
                $code = 'AlphaRacer'
                [void](New-Fix21AFile -Path (Join-Path $games 'AlphaRacer\game.exe'))
                $profileIndex['game.exe'] = @(
                    [pscustomobject]@{ Code = 'AlphaRacer'; TemplatePath = (New-Fix21ATemplate -Dir $gameProfiles -Code 'AlphaRacer' -ExecutableName 'game.exe') }
                    [pscustomobject]@{ Code = 'ZetaQuest'; TemplatePath = (New-Fix21ATemplate -Dir $gameProfiles -Code 'ZetaQuest' -ExecutableName 'game.exe') }
                )
            }
            'ExeDat' {
                # Same shared game.exe, but folder 'Moonlight Drift' shares no bigram
                # with either code, so the dat entry decides -> dat-exact save of ZetaQuest.
                $code = 'ZetaQuest'
                [void](New-Fix21AFile -Path (Join-Path $games 'Moonlight Drift\game.exe'))
                $profileIndex['game.exe'] = @(
                    [pscustomobject]@{ Code = 'AlphaRacer'; TemplatePath = (New-Fix21ATemplate -Dir $gameProfiles -Code 'AlphaRacer' -ExecutableName 'game.exe') }
                    [pscustomobject]@{ Code = 'ZetaQuest'; TemplatePath = (New-Fix21ATemplate -Dir $gameProfiles -Code 'ZetaQuest' -ExecutableName 'game.exe') }
                )
                $datIndex[(Get-NormalizedGameKey 'Moonlight Drift')] = [pscustomobject]@{ ProfileCode = 'ZetaQuest'; OriginalName = 'Moonlight Drift'; Executable = '' }
            }
            'ExeSingle' {
                $code = 'SoloRun'
                [void](New-Fix21AFile -Path (Join-Path $games 'SoloRun\solo.exe'))
                $profileIndex['solo.exe'] = @(
                    [pscustomobject]@{ Code = 'SoloRun'; TemplatePath = (New-Fix21ATemplate -Dir $gameProfiles -Code 'SoloRun' -ExecutableName 'solo.exe') }
                )
            }
            'DatPass2' {
                # neon.exe is in no profile index; pass 2 resolves the folder by its dat entry.
                $code = 'NeonHarbor'
                [void](New-Fix21AFile -Path (Join-Path $games 'Neon Harbor\neon.exe'))
                [void](New-Fix21ATemplate -Dir $gameProfiles -Code 'NeonHarbor' -ExecutableName 'neon.exe')
                $datIndex[(Get-NormalizedGameKey 'Neon Harbor')] = [pscustomobject]@{ ProfileCode = 'NeonHarbor'; OriginalName = 'Neon Harbor'; Executable = '' }
            }
            'CodePass3' {
                # No exe-index or dat match; pass 3 fuzzy-matches the folder to a profile code.
                $code = 'CobaltStrike'
                [void](New-Fix21AFile -Path (Join-Path $games 'Cobalt Strike\cobalt.exe'))
                [void](New-Fix21ATemplate -Dir $gameProfiles -Code 'CobaltStrike' -ExecutableName '')
                $profileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                [void]$profileSet.Add('CobaltStrike')
            }
            'SubFolderMap' {
                # Nothing in the install folder; pass 4 finds the exe under the TeknoParrot root.
                $code = 'WiiTitle'
                [void](New-Fix21ATemplate -Dir $gameProfiles -Code 'WiiTitle' -ExecutableName 'wiigame.exe')
                [void](New-Fix21AFile -Path (Join-Path $tpRoot 'Emu\User\Wii\wiigame.exe'))
                $subFolderMap['WiiTitle'] = 'Emu\User\Wii'
            }
            'Backfill' {
                # The profile already exists and points at twin.exe; its second
                # executable twin2.exe sits next to it, so only GamePath2 is written.
                $code = 'TwinDrive'
                $kind = 'Backfill'
                $primary = New-Fix21AFile -Path (Join-Path $games 'TwinDrive\twin.exe')
                [void](New-Fix21AFile -Path (Join-Path $games 'TwinDrive\twin2.exe'))
                $profileIndex['twin.exe'] = @(
                    [pscustomobject]@{ Code = 'TwinDrive'; TemplatePath = (New-Fix21ATemplate -Dir $gameProfiles -Code 'TwinDrive' -ExecutableName 'twin.exe') }
                )
                [void](New-Fix21AFile -Path (Join-Path $userProfiles 'TwinDrive.xml') -Text ('<GameProfile><GamePath>{0}</GamePath><HasTwoExecutables>true</HasTwoExecutables><ExecutableName>twin.exe</ExecutableName><ExecutableName2>twin2.exe</ExecutableName2></GameProfile>' -f [System.Security.SecurityElement]::Escape($primary)))
            }
            default { throw "Unknown FIX21A save site '$Site'." }
        }
        $profilePath = Join-Path $userProfiles ($code + '.xml')
        $failureChannel = 'Host'
        $failurePrefix = '  FAILED to register {0} : ' -f $code
        $failureReason = 'REGISTRATION_NOT_VERIFIED'
        if ($Site -eq 'SubFolderMap') { $failurePrefix = '  FAILED to register {0} (subFolderMap) : ' -f $code }
        if ($kind -eq 'Backfill') {
            $failureChannel = 'Log'
            $failurePrefix = "Backfill-SecondaryExecutablePath: could not check/update '{0}' -- " -f $profilePath
            $failureReason = 'PROFILE_BACKFILL_NOT_VERIFIED'
        }
        return [pscustomobject]@{
            Site = $Site
            Kind = $kind
            Code = $code
            UserProfiles = $userProfiles
            ProfilePath = $profilePath
            PreExistingProfileCount = @(Get-ChildItem -LiteralPath $userProfiles -Filter '*.xml' -File).Count
            FailureChannel = $failureChannel
            FailurePrefix = $failurePrefix
            FailureReason = $failureReason
            Params = @{
                userProfilesDir = $userProfiles
                installFolder = $games
                profileIndex = $profileIndex
                gameProfilesDir = $gameProfiles
                datIndex = $datIndex
                profileSet = $profileSet
                tpRootDir = $tpRoot
                subFolderMap = $subFolderMap
            }
        }
    }

    function Invoke-Fix21ARegistration {
        param([Parameter(Mandatory)]$Scenario, [bool]$DryRun, [hashtable]$BackupState, [switch]$OmitBackupState)
        $arguments = $Scenario.Params.Clone()
        $arguments['DryRun'] = $DryRun
        if (-not $OmitBackupState) { $arguments['BackupState'] = $BackupState }
        $output = @(Register-GamesLegacy @arguments)
        if ($output.Count -ne 1) { throw ("Register-GamesLegacy returned {0} objects instead of exactly one result." -f $output.Count) }
        return $output[0]
    }

    function New-Fix21ABackupState {
        return @{ Backup = $null; Done = $false; Error = $null }
    }

    # The game is reported exactly as Register-GamesLegacy/Backfill report a
    # pre-write failure: one Failures record (WriteAttempted false), no
    # Registered/Changed entry, the reason shown to the user, nothing on disk.
    function Assert-Fix21AFailedGame {
        param([Parameter(Mandatory)]$Scenario, [Parameter(Mandatory)]$Result, [Parameter(Mandatory)][string]$MessageLike)
        $failures = @($Result.MutationRecords.Failures)
        $failures.Count | Should -Be 1
        $failures[0].Code | Should -BeExactly $Scenario.Code
        $failures[0].WriteAttempted | Should -BeFalse
        $failures[0].Reason | Should -BeExactly $Scenario.FailureReason
        (@($Result.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly ''
        (@($Result.MutationRecords.Changed) -join ',') | Should -BeExactly ''
        $expectedAlready = ''
        if ($Scenario.Kind -eq 'Backfill') { $expectedAlready = $Scenario.Code }
        (@($Result.Already) -join ',') | Should -BeExactly $expectedAlready
        $pattern = [System.Management.Automation.WildcardPattern]::Escape($Scenario.FailurePrefix) + $MessageLike
        $channel = if ($Scenario.FailureChannel -eq 'Host') { @($script:fix21aHost) } else { @($script:fix21aLog) }
        @($channel | Where-Object { $_ -like $pattern }).Count | Should -Be 1
        @(Get-ChildItem -LiteralPath $Scenario.UserProfiles -Filter '*.xml' -File).Count | Should -Be $Scenario.PreExistingProfileCount
    }
}

Describe 'FIX21A R4 Register-GamesLegacy requires a verified backup before every real profile save' {
    BeforeEach {
        $script:fix21aEvents = New-Object System.Collections.Generic.List[string]
        $script:fix21aHost = New-Object System.Collections.Generic.List[string]
        $script:fix21aLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:fix21aHost.Add([string]$Object) }
        Mock Save-XmlMaybe { [void]$script:fix21aEvents.Add(('save {0} dry={1}' -f $path, $DryRun)) }
        Mock Assert-TpmRegisteredGamePath { [void]$script:fix21aEvents.Add(('assert {0}' -f $ProfilePath)) }
    }

    It 'creates the verified backup before the <Site> save of <Code> on a real run' -ForEach $fix21aSites {
        $scenario = New-Fix21AScenario -Site $Site
        Mock New-TpmVerifiedUserProfilesBackup {
            [void]$script:fix21aEvents.Add(('backup {0} {1}' -f $Label, $UserProfilesDir))
            [pscustomobject]@{ Required = $true; Attempted = $true; Created = $true; Succeeded = $true; Verified = $true; Path = 'fixture-verified-backup'; Reason = $null; Manifest = @() }
        }
        $state = New-Fix21ABackupState

        $result = Invoke-Fix21ARegistration -Scenario $scenario -DryRun $false -BackupState $state

        $expectedEvents = @(
            ('backup RegisterGames {0}' -f $scenario.UserProfiles)
            ('save {0} dry=False' -f $scenario.ProfilePath)
            ('assert {0}' -f $scenario.ProfilePath)
        ) -join "`n"
        ($script:fix21aEvents -join "`n") | Should -BeExactly $expectedEvents
        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 1 -Exactly
        Should -Invoke Save-XmlMaybe -Times 1 -Exactly
        $state['Done'] | Should -BeTrue
        $state['Error'] | Should -BeNullOrEmpty
        $state['Backup'].Path | Should -BeExactly 'fixture-verified-backup'
        @($result.MutationRecords.Failures).Count | Should -Be 0
        if ($scenario.Kind -eq 'Backfill') {
            (@($result.MutationRecords.Changed) -join ',') | Should -BeExactly $Code
            (@($result.Already) -join ',') | Should -BeExactly $Code
            (@($result.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly ''
        } else {
            (@($result.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly $Code
            (@($result.Already) -join ',') | Should -BeExactly ''
        }
    }

    It 'never saves <Code> at the <Site> site and records it as failed when the backup is not verified' -ForEach $fix21aSites {
        $scenario = New-Fix21AScenario -Site $Site
        Mock New-TpmVerifiedUserProfilesBackup {
            [void]$script:fix21aEvents.Add(('backup {0} {1}' -f $Label, $UserProfilesDir))
            [pscustomobject]@{ Required = $true; Attempted = $true; Created = $true; Succeeded = $false; Verified = $false; Path = 'fixture-unverified-backup'; Reason = 'fixture verification mismatch'; Manifest = @() }
        }
        $state = New-Fix21ABackupState
        $expectedMessage = 'Game registration stopped before changing profiles because its safety backup could not be verified.'

        $result = Invoke-Fix21ARegistration -Scenario $scenario -DryRun $false -BackupState $state

        ($script:fix21aEvents -join "`n") | Should -BeExactly ('backup RegisterGames {0}' -f $scenario.UserProfiles)
        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 1 -Exactly
        Should -Invoke Save-XmlMaybe -Times 0 -Exactly
        Should -Invoke Assert-TpmRegisteredGamePath -Times 0 -Exactly
        $state['Done'] | Should -BeFalse
        $state['Error'] | Should -BeExactly $expectedMessage
        Assert-Fix21AFailedGame -Scenario $scenario -Result $result -MessageLike ([System.Management.Automation.WildcardPattern]::Escape($expectedMessage))
    }

    It 'never saves <Code> at the <Site> site and records it as failed when creating the backup throws' -ForEach $fix21aSites {
        $scenario = New-Fix21AScenario -Site $Site
        Mock New-TpmVerifiedUserProfilesBackup {
            [void]$script:fix21aEvents.Add(('backup {0} {1}' -f $Label, $UserProfilesDir))
            throw [System.IO.IOException]::new('fixture backup volume is full')
        }
        $state = New-Fix21ABackupState

        $result = Invoke-Fix21ARegistration -Scenario $scenario -DryRun $false -BackupState $state

        ($script:fix21aEvents -join "`n") | Should -BeExactly ('backup RegisterGames {0}' -f $scenario.UserProfiles)
        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 1 -Exactly
        Should -Invoke Save-XmlMaybe -Times 0 -Exactly
        Should -Invoke Assert-TpmRegisteredGamePath -Times 0 -Exactly
        $state['Done'] | Should -BeFalse
        $state['Error'] | Should -BeLike '*fixture backup volume is full*'
        Assert-Fix21AFailedGame -Scenario $scenario -Result $result -MessageLike '*fixture backup volume is full*'
    }

    It 'refuses the <Site> save of <Code> with the missing-backup message when BackupState is omitted on a real run' -ForEach $fix21aSites {
        $scenario = New-Fix21AScenario -Site $Site
        Mock New-TpmVerifiedUserProfilesBackup {
            [void]$script:fix21aEvents.Add(('backup {0} {1}' -f $Label, $UserProfilesDir))
            throw 'No backup may be created without a backup state.'
        }
        $expectedMessage = 'A verified profile backup is required before registration writes a profile, but no backup state was provided.'

        $result = Invoke-Fix21ARegistration -Scenario $scenario -DryRun $false -OmitBackupState

        ($script:fix21aEvents -join "`n") | Should -BeExactly ''
        Should -Invoke Save-XmlMaybe -Times 0 -Exactly
        Should -Invoke Assert-TpmRegisteredGamePath -Times 0 -Exactly
        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 0 -Exactly
        Assert-Fix21AFailedGame -Scenario $scenario -Result $result -MessageLike ([System.Management.Automation.WildcardPattern]::Escape($expectedMessage))
    }

    It 'previews the <Site> save of <Code> without a backup when a dry run has no BackupState' -ForEach $fix21aSites {
        $scenario = New-Fix21AScenario -Site $Site
        Mock New-TpmVerifiedUserProfilesBackup {
            [void]$script:fix21aEvents.Add(('backup {0} {1}' -f $Label, $UserProfilesDir))
            throw 'A preview must never create a backup.'
        }

        $result = Invoke-Fix21ARegistration -Scenario $scenario -DryRun $true -OmitBackupState

        ($script:fix21aEvents -join "`n") | Should -BeExactly ('save {0} dry=True' -f $scenario.ProfilePath)
        Should -Invoke Save-XmlMaybe -Times 1 -Exactly -ParameterFilter { $DryRun -eq $true }
        Should -Invoke New-TpmVerifiedUserProfilesBackup -Times 0 -Exactly
        Should -Invoke Assert-TpmRegisteredGamePath -Times 0 -Exactly
        @($result.MutationRecords.Failures).Count | Should -Be 0
        (@($result.MutationRecords.Changed) -join ',') | Should -BeExactly ''
        if ($scenario.Kind -eq 'Backfill') {
            (@($result.Already) -join ',') | Should -BeExactly $Code
            (@($result.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly ''
        } else {
            (@($result.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly $Code
            (@($result.Already) -join ',') | Should -BeExactly ''
        }
        @(Get-ChildItem -LiteralPath $scenario.UserProfiles -Filter '*.xml' -File).Count | Should -Be $scenario.PreExistingProfileCount
    }

    It 'logs the match type when a folder name matches the DAT exactly' {
        # Who gets hurt: a user following the guide ("the log names dat/exact or dat/fuzzy") could not confirm the match type of a normal exact match.
        # Mutation: log only "Registered (dat)" on the first pass.
        $scenario = New-Fix21AScenario -Site 'ExeDat'
        $null = Invoke-Fix21ARegistration -Scenario $scenario -DryRun $true -OmitBackupState
        ($script:fix21aLog -join "`n") | Should -Match 'Registered \(dat/exact\) ZetaQuest -> '
    }
}
