#Requires -Module Pester

# Issue #404, no game list (DAT) loaded. Several Naomi folders each hold the shared file
# naomigd.zip, which the profile list knows under only ONE profile. The first folder keeps
# that profile. Every later folder used to be shown as a "duplicate profile" question whose
# only choice was the wrong game. Now those folders get no false question: a folder whose
# name matches a profile registers by name, any other is listed as one we could not identify.
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
        'Test-PathInside'
    )
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $wanted }, $true))
    if (@($functions | ForEach-Object { $_.Name } | Sort-Object -Unique).Count -ne $wanted.Count) {
        throw ("Expected one definition of each of: {0}" -f ($wanted -join ', '))
    }
    $functionPath = Join-Path $TestDrive ('fix404zip-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    $script:RawThrillsPathLimits = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1

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

    function New-Fix404ZipFile {
        param([string]$Path, [string]$Text = 'fixture')
        [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($Path))
        [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
    }
    function New-Fix404ZipTemplate {
        param([string]$Dir, [string]$Code, [string]$ExecutableName)
        $p = Join-Path $Dir ($Code + '.xml')
        New-Fix404ZipFile -Path $p -Text ('<GameProfile><GamePath></GamePath><ExecutableName>{0}</ExecutableName></GameProfile>' -f $ExecutableName)
        return $p
    }

    # Every folder holds naomigd.zip. No DAT. Profile names are known to the name-matching pass.
    function Invoke-Fix404ZipRegistration {
        param([string[]]$Folders, [string[]]$ExtraProfiles = @())
        $root = Join-Path $TestDrive ('fix404zip-' + [guid]::NewGuid().ToString('N'))
        $games = Join-Path $root 'Games'; $userProfiles = Join-Path $root 'UserProfiles'
        $gameProfiles = Join-Path $root 'GameProfiles'; $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $games, $userProfiles, $gameProfiles, $tpRoot -Force | Out-Null
        foreach ($f in $Folders) { New-Fix404ZipFile -Path (Join-Path $games ($f + '\naomigd.zip')) }
        $profileIndex = @{}
        $profileIndex['naomigd.zip'] = @([pscustomobject]@{ Code = 'teknonaomi_wccf2chk'; TemplatePath = (New-Fix404ZipTemplate -Dir $gameProfiles -Code 'teknonaomi_wccf2chk' -ExecutableName 'naomigd.zip') })
        foreach ($c in $ExtraProfiles) { [void](New-Fix404ZipTemplate -Dir $gameProfiles -Code $c -ExecutableName '') }
        $profileSet = @('teknonaomi_wccf2chk') + $ExtraProfiles
        $output = @(Register-GamesLegacy -userProfilesDir $userProfiles -installFolder $games -profileIndex $profileIndex `
            -gameProfilesDir $gameProfiles -datIndex @{} -profileSet $profileSet -tpRootDir $tpRoot -subFolderMap @{} -DryRun $true)
        return $output[0]
    }
}

Describe 'Issue 404 without a game list, a shared zip does not cause false duplicate questions' {
    BeforeEach {
        Mock Write-Host { }
        Mock Save-XmlMaybe { }
    }

    It 'asks no duplicate question and lists the other folders as not identified' {
        $r = Invoke-Fix404ZipRegistration -Folders @('Aaa Drive Checker', 'Border Down', 'Zzz Unknown Game')
        @($r.Ambiguous).Count | Should -Be 0
        (@($r.Registered | ForEach-Object { $_.Code }) -join ',') | Should -BeExactly 'teknonaomi_wccf2chk'
        (@($r.Unmatched) -join ',') | Should -BeExactly 'Border Down,Zzz Unknown Game'
    }

    It 'registers a later folder by its own name when a profile matches it' {
        $r = Invoke-Fix404ZipRegistration -Folders @('Aaa Drive Checker', 'Border Down') -ExtraProfiles @('borderdown')
        @($r.Ambiguous).Count | Should -Be 0
        (@($r.Registered | ForEach-Object { $_.Code } | Sort-Object) -join ',') | Should -BeExactly 'borderdown,teknonaomi_wccf2chk'
        @($r.Unmatched).Count | Should -Be 0
    }
}
