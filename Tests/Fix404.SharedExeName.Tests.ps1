#Requires -Module Pester

# Issue #404 regression coverage. Many Naomi games ship a generic file name
# (naomigd.zip) that the profile list knows under only ONE profile. Registration
# used to give that profile to every folder holding the file, which produced
# dozens of false "duplicate profile" prompts. When the game list (DAT) names a
# different profile for the folder, the single-name shortcut must not claim it.
# Facts come from the real DAT: folder "Azumanga" -> teknonaomi_azumanga,
# folder "Drive Checker" -> teknonaomi_wccf2chk, shared file naomigd.zip.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $script:Fix404Source = Get-Content -LiteralPath $sourcePath -Raw
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
        'Test-PathInside', 'Get-DatEntryForZipName', 'Get-TpmZipBaseName'
    )
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $wanted }, $true))
    if (@($functions | ForEach-Object { $_.Name } | Sort-Object -Unique).Count -ne $wanted.Count) {
        throw ("Expected one definition of each of: {0}" -f ($wanted -join ', '))
    }
    $functionPath = Join-Path $TestDrive ('fix404-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    $script:RawThrillsPathLimits = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:fix404Log = New-Object System.Collections.Generic.List[string]

    function Write-Log { param([string]$msg) [void]$script:fix404Log.Add($msg) }
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

    function New-Fix404File {
        param([string]$Path, [string]$Text = 'fixture')
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }
    function New-Fix404Template {
        param([string]$Dir, [string]$Code, [string]$ExecutableName)
        $p = Join-Path $Dir ($Code + '.xml')
        New-Fix404File -Path $p -Text ('<GameProfile><GamePath></GamePath><ExecutableName>{0}</ExecutableName></GameProfile>' -f $ExecutableName)
        return $p
    }

    # One games folder with the given sub-folder, holding naomigd.zip (shared) and an optional own file.
    function Invoke-Fix404Registration {
        param([string]$Folder, [string]$OwnFile, [hashtable]$DatEntry)
        $root = Join-Path $TestDrive ('fix404-' + [guid]::NewGuid().ToString('N'))
        $games = Join-Path $root 'Games'; $userProfiles = Join-Path $root 'UserProfiles'
        $gameProfiles = Join-Path $root 'GameProfiles'; $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $games, $userProfiles, $gameProfiles, $tpRoot -Force | Out-Null
        New-Fix404File -Path (Join-Path $games ($Folder + '\naomigd.zip'))
        if ($OwnFile) { New-Fix404File -Path (Join-Path $games ($Folder + '\' + $OwnFile)) }
        $profileIndex = @{}
        $profileIndex['naomigd.zip'] = @([pscustomobject]@{ Code = 'teknonaomi_wccf2chk'; TemplatePath = (New-Fix404Template -Dir $gameProfiles -Code 'teknonaomi_wccf2chk' -ExecutableName 'naomigd.zip') })
        [void](New-Fix404Template -Dir $gameProfiles -Code 'teknonaomi_azumanga' -ExecutableName 'azumanga.zip')
        $datIndex = @{}
        if ($DatEntry) {
            $datIndex[(Get-NormalizedGameKey $Folder)] = [pscustomobject]@{ ProfileCode = $DatEntry.Code; OriginalName = $Folder; Executable = $DatEntry.Exe }
        }
        $output = @(Register-GamesLegacy -userProfilesDir $userProfiles -installFolder $games -profileIndex $profileIndex `
            -gameProfilesDir $gameProfiles -datIndex $datIndex -profileSet $null -tpRootDir $tpRoot -subFolderMap @{} -DryRun $true)
        return $output[0]
    }
}

Describe 'Issue 404 a shared file name must not claim a profile the game list assigns elsewhere' {
    BeforeEach {
        $script:fix404Log = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { }
        Mock Save-XmlMaybe { }
    }

    It 'does not give wccf2chk to the Azumanga folder when the DAT names teknonaomi_azumanga' {
        $r = Invoke-Fix404Registration -Folder 'Azumanga Daioh Puzzle Bobble' -OwnFile 'azumanga.zip' -DatEntry @{ Code = 'teknonaomi_azumanga'; Exe = 'azumanga.zip' }
        $codes = @($r.Registered | ForEach-Object { $_.Code })
        $codes | Should -Not -Contain 'teknonaomi_wccf2chk'
        $codes | Should -Contain 'teknonaomi_azumanga'
        @($r.Ambiguous).Count | Should -Be 0
        ($script:fix404Log -join "`n") | Should -Match 'did not claim teknonaomi_wccf2chk'
    }

    It 'still gives wccf2chk to the folder the DAT names wccf2chk' {
        $r = Invoke-Fix404Registration -Folder 'Wangan Midnight Drive Checker' -DatEntry @{ Code = 'teknonaomi_wccf2chk'; Exe = 'naomigd.zip' }
        (@($r.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly 'teknonaomi_wccf2chk'
    }

    It 'keeps the old behavior when there is no DAT' {
        $r = Invoke-Fix404Registration -Folder 'Wangan Midnight Drive Checker'
        (@($r.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly 'teknonaomi_wccf2chk'
    }

    It 'tells the user that the latest DAT can resolve duplicate conflicts' {
        $script:Fix404Source | Should -Match 'Tip: using the latest DAT can resolve these'
    }
}
