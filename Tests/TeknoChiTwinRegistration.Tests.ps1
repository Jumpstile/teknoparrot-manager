#Requires -Module Pester

# A TeknoChi profile names no game file. When the player's game is registered under the older
# Chihiro profile, its TeknoChi twin must get the same game file, and nothing else.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')" }

    $wanted = @(
        'Get-TpmTeknoChiTwinTable', 'Register-TpmTeknoChiTwins', 'Confirm-TpmRegistrationSafetyBackup', 'Set-SecondaryExecutablePath', 'Get-TpmMissingGameSetFiles',
        'Get-TpmGameFileSet', 'Get-ExeAlternatives', 'Test-TpmGameMutationPath', 'Get-TpmTransactionField', 'Read-Xml',
        'Get-PrimaryExecutableName', 'Save-XmlMaybe', 'Get-TpmProfileWriteFingerprint', 'Resolve-TpmRegistrationSaveFailure',
        'Assert-TpmRegisteredGamePath', 'Set-TpmRegistrationGamePath', 'Test-PathInside'
    )
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $wanted }, $true))
    if (@($functions | ForEach-Object { $_.Name } | Sort-Object -Unique).Count -ne $wanted.Count) {
        throw ("Expected one definition of each of: {0}" -f ($wanted -join ', '))
    }
    $functionPath = Join-Path $TestDrive ('teknochi-functions-' + [guid]::NewGuid().ToString('N') + '.ps1')
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionPath -Encoding utf8
    . $functionPath

    function Write-Log { param([string]$msg) }
    # The verified-backup builder has its own tests (Fix21A); here it only has to be called before the write.
    function New-TpmVerifiedUserProfilesBackup { param($UserProfilesDir, $Label) return @{ Verified = $true } }
    function Save-Xml { param([System.Xml.XmlDocument]$doc, [string]$path) $doc.Save($path) }
    function Test-TpmRegistrationLedgerStopped { return $false }
    function Start-TpmRegistrationMapping { param([string]$Folder, [string]$Code, [string]$Match, [string]$IntendedPath, [string]$TemplatePath, [bool]$DryRun = $false) return $null }
    function Complete-TpmRegistrationMapping { param([string]$MappingId, [string]$Outcome, [bool]$WriteAttempted = $false, [string]$Reason = '') }

    function New-TwinScenario {
        $root = Join-Path $TestDrive ('twin-' + [guid]::NewGuid().ToString('N'))
        $s = [pscustomobject]@{
            Root = $root; Templates = (Join-Path $root 'GameProfiles'); Users = (Join-Path $root 'UserProfiles'); Games = (Join-Path $root 'Games')
            Registered = (New-Object System.Collections.ArrayList); Already = (New-Object System.Collections.ArrayList)
            Seen = @{}; Claimed = @{}
            Records = [pscustomobject]@{ Changed = (New-Object System.Collections.ArrayList); Failures = (New-Object System.Collections.ArrayList); Repointed = (New-Object System.Collections.ArrayList) }
        }
        New-Item -ItemType Directory -Path $s.Templates, $s.Users, $s.Games -Force | Out-Null
        foreach ($code in 'TeknoChiOutRun2', 'TeknoChiWanganMidnightMaximumTune2') {
            Set-Content -LiteralPath (Join-Path $s.Templates ($code + '.xml')) -Value '<GameProfile><GamePath></GamePath><ExecutableName></ExecutableName><EmulatorType>TeknoChi</EmulatorType></GameProfile>' -Encoding utf8
        }
        # Player's user profile for an older code (they have the older profile registered already).
        # Games are named by version folder so two versions can sit side by side.
        return $s
    }
    function New-GameFile { param($S, [string]$Folder, [string]$Name)
        $p = Join-Path (Join-Path $S.Games $Folder) $Name
        New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
        Set-Content -LiteralPath $p -Value 'x'
        return $p
    }
    function Invoke-Twins { param($S, [bool]$DryRun = $false, $BackupState = @{ Backup = $null; Done = $false; Error = $null })
        Register-TpmTeknoChiTwins -Registered $S.Registered -Already $S.Already -SeenCodes $S.Seen -ClaimedBy $S.Claimed `
            -GameProfilesDir $S.Templates -UserProfilesDir $S.Users -DryRun $DryRun -MutationRecords $S.Records -BackupState $BackupState
    }
    function Get-SavedGamePath { param($S, [string]$Code) (Read-Xml (Join-Path $S.Users ($Code + '.xml'))).GameProfile.GamePath }
}

Describe 'TeknoChi twin registration' {
    It 'gives the twin the same game file as the older profile just registered' {
        $s = New-TwinScenario
        $exe = New-GameFile $s 'OutRun 2' 'outrun2.xbe'
        [void]$s.Registered.Add([pscustomobject]@{ Code = 'or2'; GamePath = $exe })
        Invoke-Twins $s
        Get-SavedGamePath $s 'TeknoChiOutRun2' | Should -Be $exe
        @($s.Records.Failures).Count | Should -Be 0
    }

    It 'uses the older profile saved in an earlier run' {
        $s = New-TwinScenario
        $exe = New-GameFile $s 'OutRun 2' 'outrun2.xbe'
        Set-Content -LiteralPath (Join-Path $s.Users 'or2.xml') -Value ('<GameProfile><GamePath>{0}</GamePath></GameProfile>' -f $exe) -Encoding utf8
        [void]$s.Already.Add('or2')
        Invoke-Twins $s
        Get-SavedGamePath $s 'TeknoChiOutRun2' | Should -Be $exe
    }

    It 'picks the version the player owns when two older versions share one twin' {
        $s = New-TwinScenario
        $exe = New-GameFile $s 'WMMT2 Japan' 'V322.xbe'
        [void]$s.Registered.Add([pscustomobject]@{ Code = 'WMMT2j'; GamePath = $exe })
        Invoke-Twins $s
        Get-SavedGamePath $s 'TeknoChiWanganMidnightMaximumTune2' | Should -Be $exe
    }

    It 'writes nothing when both versions are registered (unclear) or no older profile is' {
        $s = New-TwinScenario
        Invoke-Twins $s
        @(Get-ChildItem -LiteralPath $s.Users -Filter '*.xml').Count | Should -Be 0
        [void]$s.Registered.Add([pscustomobject]@{ Code = 'WMMT2'; GamePath = (New-GameFile $s 'WMMT2 Export' 'V322.xbe') })
        [void]$s.Registered.Add([pscustomobject]@{ Code = 'WMMT2j'; GamePath = (New-GameFile $s 'WMMT2 Japan' 'V322.xbe') })
        Invoke-Twins $s
        @(Get-ChildItem -LiteralPath $s.Users -Filter '*.xml').Count | Should -Be 0
    }

    It 'keeps a TeknoChi profile the player already set up, byte for byte' {
        $s = New-TwinScenario
        $exe = New-GameFile $s 'OutRun 2' 'outrun2.xbe'
        $mine = Join-Path $s.Users 'TeknoChiOutRun2.xml'
        Set-Content -LiteralPath $mine -Value '<GameProfile><GamePath>D:\my\outrun2.xbe</GamePath></GameProfile>' -Encoding utf8
        $before = (Get-FileHash -LiteralPath $mine).Hash
        [void]$s.Registered.Add([pscustomobject]@{ Code = 'or2'; GamePath = $exe })
        Invoke-Twins $s
        (Get-FileHash -LiteralPath $mine).Hash | Should -Be $before
    }

    It 'makes the safety backup before writing, and writes nothing when no backup state is given' {
        $s = New-TwinScenario
        $exe = New-GameFile $s 'OutRun 2' 'outrun2.xbe'
        [void]$s.Registered.Add([pscustomobject]@{ Code = 'or2'; GamePath = $exe })
        $state = @{ Backup = $null; Done = $false; Error = $null }
        Invoke-Twins $s -BackupState $state
        $state.Done | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $s.Users 'TeknoChiOutRun2.xml') | Should -BeTrue

        $t = New-TwinScenario
        $exe2 = New-GameFile $t 'OutRun 2' 'outrun2.xbe'
        [void]$t.Registered.Add([pscustomobject]@{ Code = 'or2'; GamePath = $exe2 })
        Invoke-Twins $t -BackupState $null 6>$null
        Test-Path -LiteralPath (Join-Path $t.Users 'TeknoChiOutRun2.xml') | Should -BeFalse
        @($t.Records.Failures).Count | Should -Be 1
    }
}
