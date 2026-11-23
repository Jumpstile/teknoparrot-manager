#Requires -Module Pester

# A game folder that differs from a known game only by a sequel number ("Time Crisis 5" next to "Time Crisis 4")
# is a different game. Registration must leave it for the user to choose; it must not write the older game's profile
# with the path of the newer game. Names that agree, including a Roman numeral against a number, still register.
# The real Register-GamesLegacy runs in preview mode on tiny folders under $TestDrive.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')" }

    $wanted = @(
        'Register-GamesLegacy', 'Backfill-SecondaryExecutablePath', 'Confirm-TpmRegistrationSafetyBackup',
        'Set-SecondaryExecutablePath', 'Get-TpmMissingGameSetFiles', 'Get-TpmGameFileSet', 'Get-ExeAlternatives', 'Test-TpmGameMutationPath', 'Add-TpmUnavailableDriveGame',
        'Get-TpmTransactionField', 'Read-Xml', 'Get-PrimaryExecutableName', 'Get-NormalizedGameKey',
        'Get-DiceSimilarity', 'Get-TpmBaseTitleKey', 'Resolve-BestFuzzyMatch', 'Resolve-ProfileCode', 'Get-GameFiles',
        'Save-XmlMaybe', 'Get-TpmProfileWriteFingerprint', 'Resolve-TpmRegistrationSaveFailure',
        'New-TpmVerifiedUserProfilesBackup', 'Assert-TpmRegisteredGamePath', 'Set-TpmRegistrationGamePath',
        'Test-PathInside', 'Get-DatEntryForZipName', 'Get-TpmZipBaseName', 'Get-TpmBezelNumberText', 'Get-MeaningfulTitleTokens',
        'Get-TpmProfileFileExtensions', 'Get-TpmDatNamedProfileCodes', 'Register-TpmDatSecondProfiles',
        'Update-TpmProfileToOwnGameFolder'
    )
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $wanted }, $true))
    if (@($functions | ForEach-Object { $_.Name } | Sort-Object -Unique).Count -ne $wanted.Count) {
        throw ("Expected one definition of each of: {0}" -f ($wanted -join ', '))
    }
    $functionPath = Join-Path $TestDrive ('sequel-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    $script:RawThrillsPathLimits = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Write-Log { param([string]$msg) }
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
    function Complete-TpmRegistrationMapping { param([string]$MappingId, [string]$Outcome, [bool]$WriteAttempted = $false, [string]$Reason = '') }
    function Add-TpmRegistrationMappingFailure { param([string]$Folder, [string]$Code, [string]$Match, [string]$Reason, [string]$TemplatePath = '', [bool]$DryRun = $false) }

    function New-SequelFile {
        param([string]$Path, [string]$Text = 'fixture')
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }

    # One game folder holding game.exe, no profile owns game.exe. The profile codes only exist as templates (pass 3),
    # and the game list (DAT) holds the given entries (pass 2).
    function Invoke-SequelRegistration {
        param([string]$Folder, [string[]]$ProfileCodes = @(), [hashtable]$DatIndex = @{})
        $root = Join-Path $TestDrive ('sequel-' + [guid]::NewGuid().ToString('N'))
        $games = Join-Path $root 'Games'; $userProfiles = Join-Path $root 'UserProfiles'
        $gameProfiles = Join-Path $root 'GameProfiles'; $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $games, $userProfiles, $gameProfiles, $tpRoot -Force | Out-Null
        New-SequelFile -Path (Join-Path $games ($Folder + '\game.exe'))
        $profileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($code in $ProfileCodes) {
            New-SequelFile -Path (Join-Path $gameProfiles ($code + '.xml')) -Text '<GameProfile><GamePath></GamePath><ExecutableName></ExecutableName></GameProfile>'
            [void]$profileSet.Add($code)
        }
        $output = @(Register-GamesLegacy -userProfilesDir $userProfiles -installFolder $games -profileIndex @{} `
            -gameProfilesDir $gameProfiles -datIndex $DatIndex -profileSet $profileSet -tpRootDir $tpRoot -subFolderMap @{} -DryRun $true)
        return $output[0]
    }
}

Describe 'Registration does not give a sequel the profile of the game before it' {
    BeforeEach {
        Mock Write-Host { }
        Mock Save-XmlMaybe { }
    }

    It 'leaves a folder unmatched when only the sequel number differs from a profile name' {
        # Mutation: remove the sequel-number check after the score in the profile-name pass -> "Time Crisis 5" is registered as TimeCrisis4.
        $r = Invoke-SequelRegistration -Folder 'Time Crisis 5' -ProfileCodes @('TimeCrisis4')
        @($r.Registered | ForEach-Object { $_.Code }) | Should -Not -Contain 'TimeCrisis4'
        @($r.Unmatched) | Should -Contain 'Time Crisis 5'
    }

    It 'leaves a folder unmatched when only the sequel number differs from a game list name' {
        # Mutation: remove the sequel-number check in the game-list pass -> "Time Crisis 5" is registered as TimeCrisis4.
        $dat = @{ (Get-NormalizedGameKey 'Time Crisis 4') = [pscustomobject]@{ ProfileCode = 'TimeCrisis4'; OriginalName = 'Time Crisis 4'; Executable = '' } }
        $r = Invoke-SequelRegistration -Folder 'Time Crisis 5' -ProfileCodes @('TimeCrisis4') -DatIndex $dat
        @($r.Registered | ForEach-Object { $_.Code }) | Should -Not -Contain 'TimeCrisis4'
        @($r.Unmatched) | Should -Contain 'Time Crisis 5'
    }

    It 'still registers a folder whose number or Roman numeral agrees with the profile name' -ForEach @(
        @{ Folder = 'Time Crisis 4'; Code = 'TimeCrisis4' }
        @{ Folder = 'Raiden IV'; Code = 'RaidenIV' }
    ) {
        # Mutation: compare the raw text of the numbers instead of the number each Roman numeral stands for -> a correct match is refused.
        $r = Invoke-SequelRegistration -Folder $Folder -ProfileCodes @($Code)
        @($r.Registered | ForEach-Object { $_.Code }) | Should -Contain $Code
    }
}
