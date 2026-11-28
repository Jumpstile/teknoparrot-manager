#Requires -Module Pester

# AutoSync registration, two cases a normal user hits:
#   - a profile that exists but has no game file yet (the game was added in TeknoParrot first) is linked to the game, not counted as already set up.
#   - a folder left alone because the other ZIP of its game set is missing is listed as not registered, and does not claim the profile.
# The real Register-GamesLegacy runs on tiny folders under $TestDrive.
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
        'Get-TpmProfileFileExtensions', 'Get-TpmDatNamedProfileCodes', 'Register-TpmDatSecondProfiles', 'Get-TpmTeknoChiTwinTable', 'Register-TpmTeknoChiTwins',
        'Update-TpmProfileToOwnGameFolder'
    )
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $wanted }, $true))
    $found = @($functions | ForEach-Object { $_.Name } | Sort-Object -Unique)
    if ($found.Count -ne $wanted.Count) { throw ("Expected one definition of each of: {0}" -f ($wanted -join ', ')) }
    $functionPath = Join-Path $TestDrive ('blank-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    $script:RawThrillsPathLimits = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Write-Log { param([string]$msg) }
    function Save-Xml { param([System.Xml.XmlDocument]$doc, [string]$path) $doc.Save($path) }
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

    function New-BlankFile {
        param([string]$Path, [string]$Text = 'fixture')
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }
    function New-BlankRoot {
        $root = Join-Path $TestDrive ('blank-' + [guid]::NewGuid().ToString('N'))
        foreach ($name in 'Games', 'UserProfiles', 'GameProfiles', 'TeknoParrot') { [void][System.IO.Directory]::CreateDirectory((Join-Path $root $name)) }
        return $root
    }
}

Describe 'AutoSync registration of profiles with no game file and of incomplete game sets' {
    BeforeEach {
        Mock Write-Host { }
        Mock New-TpmVerifiedUserProfilesBackup { [pscustomobject]@{ Verified = $true; Path = (Join-Path $TestDrive "backup") } }
    }

    It 'links an existing profile with an empty game file to the game and keeps its other settings' {
        # Mutation: count any existing profile as already set up -> the profile keeps an empty GamePath and the game never starts.
        $root = New-BlankRoot
        $exe = Join-Path $root 'Games\My Game\game.exe'
        New-BlankFile -Path $exe
        $template = Join-Path $root 'GameProfiles\MYGAME.xml'
        New-BlankFile -Path $template -Text '<GameProfile><GamePath></GamePath><ExecutableName>game.exe</ExecutableName></GameProfile>'
        $userProfile = Join-Path $root 'UserProfiles\MYGAME.xml'
        New-BlankFile -Path $userProfile -Text '<GameProfile><GamePath></GamePath><ExecutableName>game.exe</ExecutableName><MySetting>keep me</MySetting></GameProfile>'
        $profileIndex = @{ 'game.exe' = @([pscustomobject]@{ Code = 'MYGAME'; TemplatePath = $template; ExeName = 'game.exe' }) }
        $profileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase); [void]$profileSet.Add('MYGAME')
        $r = @(Register-GamesLegacy -userProfilesDir (Join-Path $root 'UserProfiles') -installFolder (Join-Path $root 'Games') -profileIndex $profileIndex `
            -gameProfilesDir (Join-Path $root 'GameProfiles') -datIndex @{} -profileSet $profileSet -tpRootDir (Join-Path $root 'TeknoParrot') -subFolderMap @{} -DryRun $false -BackupState @{})[0]
        $saved = [xml][System.IO.File]::ReadAllText($userProfile)
        $saved.GameProfile.GamePath | Should -BeExactly $exe
        $saved.GameProfile.MySetting | Should -BeExactly 'keep me'
        @($r.Already) | Should -Not -Contain 'MYGAME'
    }

    It 'lists a folder as not registered when the other ZIP of its game set is missing' {
        # Mutation: keep the folder marked as matched and the profile claimed before the skip -> it is in no list and the run says it registered it.
        $root = New-BlankRoot
        New-BlankFile -Path (Join-Path $root 'Games\Child Game\game.exe')
        New-BlankFile -Path (Join-Path $root 'GameProfiles\CHILDSET.xml') -Text '<GameProfile><GamePath></GamePath><ExecutableName>child.zip;parent.zip</ExecutableName></GameProfile>'
        $profileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase); [void]$profileSet.Add('CHILDSET')
        $dat = @{ (Get-NormalizedGameKey 'Child Game') = [pscustomobject]@{ ProfileCode = 'CHILDSET'; OriginalName = 'Child Game'; Executable = '' } }
        $r = @(Register-GamesLegacy -userProfilesDir (Join-Path $root 'UserProfiles') -installFolder (Join-Path $root 'Games') -profileIndex @{} `
            -gameProfilesDir (Join-Path $root 'GameProfiles') -datIndex $dat -profileSet $profileSet -tpRootDir (Join-Path $root 'TeknoParrot') -subFolderMap @{} -DryRun $true)[0]
        @($r.Registered | ForEach-Object { $_.Code }) | Should -Not -Contain 'CHILDSET'
        @($r.Unmatched) | Should -Contain 'Child Game'
    }

    It 'does not report a second folder as a duplicate of a game that had no profile to register' {
        # Mutation: keep the claim after the missing-template skip -> the second folder is reported as a duplicate "claimed by" a folder that was never registered.
        $root = New-BlankRoot
        New-BlankFile -Path (Join-Path $root 'Games\Rev Game A\game.exe')
        New-BlankFile -Path (Join-Path $root 'Games\Rev Game B\game.exe')
        $profileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $dat = @{
            (Get-NormalizedGameKey 'Rev Game A') = [pscustomobject]@{ ProfileCode = 'NOPROFILE'; OriginalName = 'Rev Game A'; Executable = '' }
            (Get-NormalizedGameKey 'Rev Game B') = [pscustomobject]@{ ProfileCode = 'NOPROFILE'; OriginalName = 'Rev Game B'; Executable = '' }
        }
        $r = @(Register-GamesLegacy -userProfilesDir (Join-Path $root 'UserProfiles') -installFolder (Join-Path $root 'Games') -profileIndex @{} `
            -gameProfilesDir (Join-Path $root 'GameProfiles') -datIndex $dat -profileSet $profileSet -tpRootDir (Join-Path $root 'TeknoParrot') -subFolderMap @{} -DryRun $true)[0]
        @($r.Ambiguous | Where-Object { $_.Reason -eq 'duplicate' }).Count | Should -Be 0
    }

    It 'does not register a subFolderMap entry that points outside the TeknoParrot folder' {
        # Mutation: skip the containment check -> a typo such as ..\Elsewhere in overrides.json writes a profile for a game outside the TeknoParrot folder.
        $root = New-BlankRoot
        New-BlankFile -Path (Join-Path $root 'Outside\game.exe')
        New-BlankFile -Path (Join-Path $root 'TeknoParrot\Inside\game.exe')
        New-BlankFile -Path (Join-Path $root 'GameProfiles\OUTGAME.xml') -Text '<GameProfile><GamePath></GamePath><ExecutableName>game.exe</ExecutableName></GameProfile>'
        New-BlankFile -Path (Join-Path $root 'GameProfiles\INGAME.xml') -Text '<GameProfile><GamePath></GamePath><ExecutableName>game.exe</ExecutableName></GameProfile>'
        $profileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $r = @(Register-GamesLegacy -userProfilesDir (Join-Path $root 'UserProfiles') -installFolder (Join-Path $root 'Games') -profileIndex @{} `
            -gameProfilesDir (Join-Path $root 'GameProfiles') -datIndex @{} -profileSet $profileSet -tpRootDir (Join-Path $root 'TeknoParrot') -subFolderMap @{ OUTGAME = '..\Outside'; INGAME = 'Inside' } -DryRun $true)[0]
        $codes = @($r.Registered | ForEach-Object { $_.Code })
        $codes | Should -Not -Contain 'OUTGAME'
        $codes | Should -Contain 'INGAME'
    }
}
