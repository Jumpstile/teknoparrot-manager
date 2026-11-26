#Requires -Module Pester

# FIXM2: one test per user-visible audit finding fixed in lane M2 (9, 10, 13, 17, 18, 19). Findings 11, 24, 25 are tested in
# TeknoParrot-Manager.Tests.ps1 and SupportPackage.Tests.ps1; 14 and 15 in Fix112 and Fix110A.
# The production script is parsed and only its function definitions are dot-sourced. Everything lives under TestDrive.
# Each It names the product change that makes it fail.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $script:m2Ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIXM2 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fixm2-functions.ps1'
    ($script:m2Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fixm2.log'
    $script:logWarnShown = $false
    $script:m2FunctionFile = $functionFile

    function New-M2Root {
        param([string]$Name)
        $root = Join-Path $TestDrive ($Name + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory($root)
        return $root
    }
    function Get-M2Text { return (((@($script:m2Rows | ForEach-Object { ([string]$_).Trim() }) -join ' ') -replace '\s+', ' ').Trim()) }
    function New-M2BepLibrary {
        $root = New-M2Root 'bep'
        $profiles = Join-Path $root 'UserProfiles'
        $games = Join-Path $root 'Games'
        $dir = Join-Path $games 'OutsideGame'
        foreach ($folder in @($profiles, $dir)) { [void][System.IO.Directory]::CreateDirectory($folder) }
        $exe = Join-Path $dir 'game.exe'
        [System.IO.File]::WriteAllText($exe, 'MZ-test-game')
        [System.IO.File]::WriteAllText((Join-Path $profiles 'OutsideGame.xml'), ('<GameProfile><GameName>Game</GameName><GamePath>{0}</GamePath></GameProfile>' -f [System.Security.SecurityElement]::Escape($exe)), (New-Object System.Text.UTF8Encoding $false))
        return [pscustomobject]@{ Root = $root; Profiles = $profiles; Cache = (Join-Path $root 'BepCache'); Games = $games; Dir = $dir }
    }
    # The same mocks as the FIX107 update test: a verified update of one game from 5.4.22 to 5.4.23.
    function Install-M2BepMocks {
        param($Library)
        $script:m2StageRoot = New-M2Root 'stage'
        $script:m2BackupDir = Join-Path $Library.Dir ('BepInEx_Backup_' + [guid]::NewGuid().ToString('N'))
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { return 120 }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Test-BepInExGameRootSafe { $true }
        Mock Test-BepInExNoReparsePath { $true }
        Mock Test-BepInExExistingTreeSafe { $true }
        Mock Test-BepInExPackagePathSafe { $true }
        Mock Get-BepInExPeArchitectureEvidence { [pscustomobject]@{ State = 'SUPPORTED'; Architecture = 'x64'; Reason = 'supported fixture' } }
        Mock Get-BepInExLatestRelease { [pscustomobject]@{ Version = '5.4.23'; DownloadUrl = 'https://example.invalid/BepInEx_win_x64_5.4.23.zip'; FileName = 'BepInEx_win_x64_5.4.23.zip'; SizeBytes = 1; ExpectedSha256 = $null } }
        Mock Get-BepInExInstalledVersion { $script:m2Installed }
        Mock Get-BepInExInstallationHealth { [pscustomobject]@{ Installed = $true; Complete = $true; Version = '5.4.22'; Architecture = 'x64'; Reason = 'Complete' } }
        Mock Read-HostSafe { 'Y' }
        Mock Invoke-TpmDownload { Set-Content -LiteralPath $DestinationPath -Value 'verified package' -NoNewline; $true }
        Mock New-TpmStagingDirectory { $dir = Join-Path $script:m2StageRoot ([guid]::NewGuid().ToString('N')); [void][System.IO.Directory]::CreateDirectory($dir); return $dir }
        Mock Expand-ZipFileSafe {}
        Mock Get-BepInExStagedFiles { @('BepInEx\core.dll') }
        Mock New-BepInExUpdateBackup { [void][System.IO.Directory]::CreateDirectory($script:m2BackupDir); Set-Content -LiteralPath (Join-Path $script:m2BackupDir 'inventory.json') -Value '{}'; return $script:m2BackupDir }
        Mock Remove-BepInExStagingDirectory { $true }
    }
    function New-M2HealthResult {
        param([bool]$Unavailable)
        return [pscustomobject]@{
            Outcome = 'ACTION_REQUIRED'; DiscoveryComplete = $true; OptionalCoverageComplete = (-not $Unavailable); OptionalCheckFailed = 0
            PostgresInventoryStatus = 'Complete'; PostgresInventoryErrors = @(); ReadOnly = $true; Registered = 12
            Valid = @(1..12 | ForEach-Object { 'G' + $_ }); Broken = @(); Empty = @()
            GpuFixNeeded = @(); FfbBlasterNeeded = @(); DgVoodoo2Needed = @()
            PostgresNeeded = @(); PostgresConfigured = 0; PostgresAutoCreateProfiles = @()
            PostgresServiceExists = $false; PostgresServiceStatus = 'NotInstalled'
            ReShadeCount = 0; BepInExCount = 0; DetectedGpuVendor = 'Intel'; LogPath = 'C:\M2\TeknoParrot-Manager.log'
            PostgresNeededLabels = @(); PostgresConfiguredLabels = @(); PostgresPsqlStatus = 'Unknown'
            OptionalCoverageUnavailable = $Unavailable; OptionalCoverageError = $(if ($Unavailable) { 'fixture' } else { '' }); LastFullRun = ''
        }
    }
}

Describe 'FIXM2 finding 9 and 10: BepInEx update' {
    BeforeEach {
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        $script:m2Installed = '5.4.22'
    }

    It 'removes the safety copy from the game folder after a verified update (9)' {
        # Mutation: drop the BepInEx_Backup removal after promotion -> one full copy of BepInEx stays in every updated game folder, forever.
        $library = New-M2BepLibrary
        Install-M2BepMocks -Library $library
        Mock Invoke-TpmTransactionalTreePromote { $script:m2Installed = '5.4.23'; $true }
        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $library.Games -ProtectedRoots @()
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.Updated | Should -Be 1
        Test-Path -LiteralPath $script:m2BackupDir | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $library.Dir 'game.exe') | Should -BeTrue
    }

    It 'keeps the safety copy when the update fails (9)' {
        # Mutation: remove the safety copy even when the update failed -> the only copy of the user's old files is lost.
        $library = New-M2BepLibrary
        Install-M2BepMocks -Library $library
        Mock Invoke-TpmTransactionalTreePromote { throw 'forced promotion failure' }
        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $library.Games -ProtectedRoots @()
        $result.Updated | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:m2BackupDir 'inventory.json') | Should -BeTrue
    }

    It 'accepts an installed version written 5.4.23.0 for release 5.4.23 instead of rolling the update back (10)' {
        # Mutation: compare the version text exactly (-eq) -> a correct update is judged wrong, rolled back and the game reported as an error.
        $library = New-M2BepLibrary
        Install-M2BepMocks -Library $library
        $script:m2ValidationResult = $null
        Mock Invoke-TpmTransactionalTreePromote { $script:m2Installed = '5.4.23.0'; $script:m2ValidationResult = [bool](& $ValidationScript); $true }
        $result = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $library.Games -ProtectedRoots @()
        $script:m2ValidationResult | Should -BeTrue
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
    }

    It 'still rejects an installed version older than the release (10)' {
        # Mutation: make the check always true -> a failed update that left the old version is reported as done.
        $library = New-M2BepLibrary
        Install-M2BepMocks -Library $library
        $script:m2ValidationResult = $null
        Mock Invoke-TpmTransactionalTreePromote { $script:m2ValidationResult = [bool](& $ValidationScript); $true }
        $null = Invoke-BepInExUpdateCheck -UserProfilesDir $library.Profiles -CacheDir $library.Cache -ApprovedGamesRoot $library.Games -ProtectedRoots @()
        $script:m2ValidationResult | Should -BeFalse
    }
}

Describe 'FIXM2 finding 13: AutoSync, two ZIPs for one existing game folder' {
    It 'updates the folder once and skips the second ZIP with a message' {
        # Mutation: drop the claimed-folder check -> both ZIPs are processed for the same folder and replace each other's files.
        $install = New-M2Root 'install'
        $folder = Join-Path $install 'GameA'
        [void][System.IO.Directory]::CreateDirectory($folder)
        Set-Content -LiteralPath (Join-Path $folder 'game.exe') -Value 'x'
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        $script:m2Folder = $folder
        $zips = @(
            [pscustomobject]@{ Name = 'GameA_v1.zip'; FullName = (Join-Path $install 'GameA_v1.zip'); Length = 10; LastWriteTimeUtc = [datetime]::UtcNow }
            [pscustomobject]@{ Name = 'GameA_v2.zip'; FullName = (Join-Path $install 'GameA_v2.zip'); Length = 10; LastWriteTimeUtc = [datetime]::UtcNow }
        )
        $script:m2Zips = $zips
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmTopLevelZipSourceFiles { $script:m2Zips }
        Mock Get-StagingFolderMap { @{} }
        Mock Resolve-ExtractedGameFolder { $script:m2Folder }
        Mock Test-TpmRegistrationLedgerConfigured { $false }
        # Both ZIPs have a stored entry that no longer matches the NAS file, so each one plans a real write ("changed on NAS").
        $script:m2OldState = @{ 'GameA_v1' = @{ NasSize = 99; NasLastModified = 'old' }; 'GameA_v2' = @{ NasSize = 99; NasLastModified = 'old' } }
        Mock Test-TpmAutoSyncStateFile { [pscustomobject]@{ Status = 'Valid'; State = $script:m2OldState; Reason = '' } }
        $result = Invoke-AutoSync -zipSource $install -installFolder $install -syncStatePath (Join-Path $install 'state.json') -DryRun $true -datIndex @{}
        $text = Get-M2Text
        $text | Should -Match 'another ZIP in this run already updates the same game folder'
        @([regex]::Matches($text, 'another ZIP in this run')).Count | Should -Be 1
        $result.Skipped | Should -Be 1
    }
}

Describe 'FIXM2B finding 13: AutoSync claims a game folder only when a ZIP writes to it' {
    BeforeEach {
        $script:m2Install = New-M2Root 'install'
        $script:m2Folder = Join-Path $script:m2Install 'GameA'
        [void][System.IO.Directory]::CreateDirectory($script:m2Folder)
        Set-Content -LiteralPath (Join-Path $script:m2Folder 'game.exe') -Value 'x'
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        $script:m2Stamp = [datetime]::UtcNow
        $script:m2Zips = @(
            [pscustomobject]@{ Name = 'GameA_v1.zip'; FullName = (Join-Path $script:m2Install 'GameA_v1.zip'); Length = 10; LastWriteTimeUtc = $script:m2Stamp }
            [pscustomobject]@{ Name = 'GameA_v2.zip'; FullName = (Join-Path $script:m2Install 'GameA_v2.zip'); Length = 10; LastWriteTimeUtc = $script:m2Stamp }
        )
        $script:m2State = @{}
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Get-TpmTopLevelZipSourceFiles { $script:m2Zips }
        Mock Get-StagingFolderMap { @{} }
        Mock Resolve-ExtractedGameFolder { $script:m2Folder }
        Mock Test-TpmRegistrationLedgerConfigured { $false }
        Mock Test-TpmAutoSyncStateFile { [pscustomobject]@{ Status = 'Valid'; State = $script:m2State; Reason = '' } }
    }

    It 'applies a newer ZIP when an older ZIP for the same folder is already extracted (a)' {
        # Mutation: claim the folder before $needsSync is known -> the up-to-date older ZIP blocks the newer version, which is skipped with a false message.
        $script:m2State = @{ 'GameA_v1' = @{ NasSize = 10; NasLastModified = $script:m2Stamp.ToString('o') } }
        $result = Invoke-AutoSync -zipSource $script:m2Install -installFolder $script:m2Install -syncStatePath (Join-Path $script:m2Install 'state.json') -DryRun $true -datIndex @{}
        $result.UpToDate | Should -Be 1
        $result.WouldSync | Should -Be 1
        $result.Skipped | Should -Be 0
        Get-M2Text | Should -Not -Match 'another ZIP in this run'
    }

    It 'still tries the second ZIP when the first one failed without changing the folder (b)' {
        # Mutation: claim the folder before the transaction -> a failed first ZIP blocks the second, and the game stays on the old version.
        $script:m2Tx = {
            [pscustomobject]@{
                TransactionResult = [pscustomobject]@{ Outcome = 'FAILED_BEFORE_MUTATION'; ProductState = 'UNCHANGED'; ReasonCode = 'EXTRACT_FAILED'; Summary = 'could not extract' }
                FilesystemChanged = $false; StateChanged = $false; RegistrationEligible = $false; TargetPath = $script:m2Folder
            }
        }
        Mock Invoke-TpmAutoSyncDirectoryTransaction $script:m2Tx
        $result = Invoke-AutoSync -zipSource $script:m2Install -installFolder $script:m2Install -syncStatePath (Join-Path $script:m2Install 'state.json') -DryRun $false -datIndex @{}
        Should -Invoke Invoke-TpmAutoSyncDirectoryTransaction -Times 2 -Exactly
        $result.Failed | Should -Be 2
        $result.Skipped | Should -Be 0
    }

    It 'skips the second ZIP after the first one wrote to the folder in a real run (c)' {
        # Mutation: never claim after a write -> both ZIPs extract into the same folder and replace each other's files.
        Mock Invoke-TpmAutoSyncDirectoryTransaction {
            [pscustomobject]@{
                TransactionResult = [pscustomobject]@{ Outcome = 'SUCCEEDED'; ProductState = 'INTENDED'; ReasonCode = 'OK'; Summary = 'done'; TechnicalDetails = [pscustomobject]@{ ExtraFileCount = 0; ExtraFilesSavedTo = '' } }
                FilesystemChanged = $true; StateChanged = $true; RegistrationEligible = $true; TargetPath = $script:m2Folder
            }
        }
        $result = Invoke-AutoSync -zipSource $script:m2Install -installFolder $script:m2Install -syncStatePath (Join-Path $script:m2Install 'state.json') -DryRun $false -datIndex @{}
        Should -Invoke Invoke-TpmAutoSyncDirectoryTransaction -Times 1 -Exactly
        $result.Synced | Should -Be 1
        $result.Skipped | Should -Be 1
        Get-M2Text | Should -Match 'another ZIP in this run already updates the same game folder'
    }

    It 'does not skip the second ZIP in a dry run when the first only verifies an existing folder (dry run matches real run)' {
        # Mutation: claim for every planned write in a dry run -> the dry run says the second ZIP is skipped, but a real run (state-only repair writes no game files) would process it.
        $result = Invoke-AutoSync -zipSource $script:m2Install -installFolder $script:m2Install -syncStatePath (Join-Path $script:m2Install 'state.json') -DryRun $true -datIndex @{}
        $result.WouldSync | Should -Be 2
        $result.Skipped | Should -Be 0
        Get-M2Text | Should -Not -Match 'another ZIP in this run'
    }
}

Describe 'FIXM2 finding 17: ReShade setup when the chosen profile cannot be prepared' {
    It 'stops with nothing changed instead of continuing as Original' {
        Mock Read-TpmChoice { 'Y' }
        Mock Read-TpmYesNo { 'Y' }
        # Mutation: go back to "Continuing with Original" -> the old preset is silently reused while the screen says the chosen profile was applied.
        $profiles = New-M2Root 'rs-profiles'
        $root = New-M2Root 'rs-game'
        $gamePath = Join-Path $root 'Game.exe'
        $profilePath = Join-Path $profiles 'Game.xml'
        Set-Content -LiteralPath $gamePath -Value 'game'
        Set-Content -LiteralPath $profilePath -Value ("<GameProfile><GamePath>{0}</GamePath></GameProfile>" -f $gamePath)
        $sourceDll = Join-Path $TestDrive 'm2-ReShade64.dll'
        Set-Content -LiteralPath $sourceDll -Value 'source'
        $script:m2Profile = [pscustomobject]@{ ProfileId = 'Levels'; FriendlyName = 'Levels'; Description = 'test'; BaseName = 'Game' }
        $script:m2ProfilePath = $profilePath
        $script:m2Root = $root
        $script:m2GamePath = $gamePath
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Invoke-ReShadeUpdateIfAvailable { [pscustomobject]@{ Updated = $false; SourceDll = $sourceDll } }
        Mock Test-ReShadeDllSignature { [pscustomobject]@{ Status = 'Unknown'; Signer = $null } }
        Mock Get-TpmReShadeProfiles { @($script:m2Profile) }
        Mock Get-TpmReShadeProfile { $script:m2Profile }
        Mock Read-TpmReShadeState { [pscustomobject]@{ Profiles = [pscustomobject]@{}; Favorites = @(); History = [pscustomobject]@{} } }
        Mock Show-TpmReShadeProfileGalleryWindow { [pscustomobject]@{ Available = $false; Session = $null; Reason = 'test' } }
        Mock Close-TpmReShadeProfileGallerySession {}
        Mock Read-TpmReShadeTerminalProfile { [pscustomobject]@{ Cancelled = $false; SelectedProfile = $script:m2Profile } }
        Mock Read-HostSafe { 'Y' }
        Mock Select-RegisteredGamesInteractive { @(Get-Item -LiteralPath $script:m2ProfilePath) }
        Mock Get-TpmReShadeProfileOwnershipPath { Join-Path $script:m2Root 'ownership.json' }
        Mock Get-ReShadeTargetInfo { [pscustomobject]@{ TargetDir = $script:m2Root; DllName = 'dxgi.dll'; ApiDetected = $true } }
        Mock Get-ExeArchitecture { 'x64' }
        Mock Get-TpmReShadeOwnershipClassification { [pscustomobject]@{ Status = 'Absent'; Detail = 'none' } }
        Mock Test-TpmGameMutationPath { [pscustomobject]@{ Valid = $true; ResolvedPath = $script:m2GamePath; GameDirectory = $script:m2Root } }
        Mock New-TpmReShadePresetContent { throw 'forced preset failure' }
        Mock Install-TpmReShadeProfileDeployment { throw 'nothing may be installed when the preset could not be made' }
        $result = Invoke-ReShadeSetupLegacy -UserProfilesDir $profiles -SourceDll $sourceDll -ConfigPath '' -TpRoot '' -Mode '' -ZipSource '' -GamesInstallFolder '' -RetroBat $false
        $result.Succeeded | Should -BeFalse
        $result.Reason | Should -BeExactly 'PRESET_GENERATION_FAILED'
        $result.Deployed | Should -Be 0
        Should -Invoke Install-TpmReShadeProfileDeployment -Times 0
        (Get-M2Text) | Should -Match 'No files were changed'
        (Get-M2Text) | Should -Not -Match 'Continuing with Original'
    }
}

Describe 'FIXM2 finding 18: Crosshair setup while PCSX2 is still open' {
    It 'does not say nothing was deployed while the other lightgun games still get their crosshairs' {
        # Mutation: restore "canceled without changes ... not deployed" -> the screen contradicts the ElfLdr2 crosshairs that are installed anyway.
        $tp = New-M2Root 'cross-tp'
        $profiles = New-M2Root 'cross-profiles'
        $elf = Join-Path $tp 'ElfLdr2'
        $pcsx2 = Join-Path $tp 'Pcsx2x6'
        foreach ($d in @($elf, $pcsx2)) { [void][System.IO.Directory]::CreateDirectory($d) }
        Set-Content -LiteralPath (Join-Path $profiles 'ElfGun.xml') -Value '<GameProfile><GameName>Elf Gun</GameName><GunGame>true</GunGame><EmulatorType>ElfLdr2</EmulatorType></GameProfile>'
        Set-Content -LiteralPath (Join-Path $profiles 'PsGun.xml') -Value '<GameProfile><GameName>Ps Gun</GameName><GunGame>true</GunGame><EmulatorType>Pcsx2x6</EmulatorType></GameProfile>'
        $crosshairs = Join-Path (Split-Path -Parent $script:m2FunctionFile) 'Crosshairs'
        [void][System.IO.Directory]::CreateDirectory($crosshairs)
        Set-Content -LiteralPath (Join-Path $crosshairs '000.png') -Value 'png'
        Set-Content -LiteralPath (Join-Path $crosshairs '001.png') -Value 'png'
        $script:m2Pcsx2 = $pcsx2
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        $script:m2Targets = $null
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-TpmText { [void]$script:m2Rows.Add([string]$Text) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Test-PngFile { $true }
        Mock Show-TpmCrosshairPreviewWindow { [pscustomobject]@{ Available = $true; Cancelled = $false; P1Index = 0; P2Index = 1; TimedOut = $false } }
        Mock Read-TpmCrosshairYesNo { 'Y' }
        Mock Read-TpmYesNo { if ($Prompt -match 'Configure Automatically') { 'Y' } else { 'N' } }
        Mock Resolve-Pcsx2Directory { $script:m2Pcsx2 }
        Mock Get-Pcsx2CrosshairPrerequisiteState { [pscustomobject]@{ State = 'StockUninitialized'; Reason = 'fixture'; DataRoot = ''; IniPath = '' } }
        Mock Wait-TpmForProcessClose { $false }
        Mock Invoke-Pcsx2FirstRunSetup { throw 'first-run setup must not start while PCSX2 is open' }
        Mock Invoke-TpmCrosshairAssetTransaction { $script:m2Targets = @($Targets); New-TpmFileBatchResult -WorkflowKey 'CrosshairSetup' -OperationKey 'P1P2' -Outcome 'NO_OP' -ProductState 'UNCHANGED' -Summary 'fixture' -ReasonCode 'FIXTURE' -FinalAttempted $true -FinalPassed $true -FinalChecks @('fixture') }
        $result = Invoke-CrosshairSetup -UserProfilesDir $profiles -TpRoot $tp
        @($script:m2Targets | ForEach-Object { $_.ItemId }) | Should -Contain 'ElfLdr2'
        @($script:m2Targets | ForEach-Object { $_.ItemId }) | Should -Not -Contain 'Pcsx2x6'
        $text = Get-M2Text
        $text | Should -Match 'PCSX2 crosshairs were skipped because PCSX2 is still open'
        $text | Should -Not -Match 'not deployed|canceled without changes'
    }

    It 'asks the PCSX2 first-run question once and logs the name of every skipped game' {
        $tp = New-M2Root 'cross-once-tp'
        $profiles = New-M2Root 'cross-once-profiles'
        $pcsx2 = Join-Path $tp 'Pcsx2x6'
        [void][System.IO.Directory]::CreateDirectory($pcsx2)
        Set-Content -LiteralPath (Join-Path $profiles 'PsGunOne.xml') -Value '<GameProfile><GameName>Ps Gun One</GameName><GunGame>true</GunGame><EmulatorType>Pcsx2x6</EmulatorType></GameProfile>'
        Set-Content -LiteralPath (Join-Path $profiles 'PsGunTwo.xml') -Value '<GameProfile><GameName>Ps Gun Two</GameName><GunGame>true</GunGame><EmulatorType>Pcsx2x6</EmulatorType></GameProfile>'
        Set-Content -LiteralPath (Join-Path $profiles 'NoPath.xml') -Value '<GameProfile><GameName>No Path Gun</GameName><GunGame>true</GunGame><GamePath /></GameProfile>'
        $crosshairs = Join-Path (Split-Path -Parent $script:m2FunctionFile) 'Crosshairs'
        [void][System.IO.Directory]::CreateDirectory($crosshairs)
        Set-Content -LiteralPath (Join-Path $crosshairs '000.png') -Value 'png'
        Set-Content -LiteralPath (Join-Path $crosshairs '001.png') -Value 'png'
        $script:m2Pcsx2 = $pcsx2
        $script:m2Asked = 0
        $script:m2Log = New-Object System.Collections.Generic.List[string]
        Mock Write-Host {}
        Mock Write-TpmText {}
        Mock Write-Log { [void]$script:m2Log.Add([string]$msg) }
        Mock Write-TpmCompactExtractionProgress {}
        Mock Test-PngFile { $true }
        Mock Show-TpmCrosshairPreviewWindow { [pscustomobject]@{ Available = $true; Cancelled = $false; P1Index = 0; P2Index = 1; TimedOut = $false } }
        Mock Read-TpmCrosshairYesNo { 'Y' }
        Mock Read-TpmYesNo { if ($Prompt -match 'Configure Automatically') { $script:m2Asked++ }; 'N' }
        Mock Resolve-Pcsx2Directory { $script:m2Pcsx2 }
        Mock Get-Pcsx2CrosshairPrerequisiteState { [pscustomobject]@{ State = 'StockUninitialized'; Reason = 'fixture'; DataRoot = ''; IniPath = '' } }
        Mock Invoke-Pcsx2FirstRunSetup { throw 'first-run setup must not start after the user said N' }
        Mock Invoke-TpmCrosshairAssetTransaction { New-TpmFileBatchResult -WorkflowKey 'CrosshairSetup' -OperationKey 'P1P2' -Outcome 'NO_OP' -ProductState 'UNCHANGED' -Summary 'fixture' -ReasonCode 'FIXTURE' -FinalAttempted $true -FinalPassed $true -FinalChecks @('fixture') }
        $result = Invoke-CrosshairSetup -UserProfilesDir $profiles -TpRoot $tp
        @($result.SkippedGames | Where-Object { $_ -like 'Ps Gun One: PCSX2 - *' }).Count | Should -Be 1
        @($result.SkippedGames | Where-Object { $_ -like 'Ps Gun Two: PCSX2 - *' }).Count | Should -Be 1
        @($result.SkippedGames | Where-Object { $_ -eq 'No Path Gun: the profile has no game path' }).Count | Should -Be 1
        $script:m2Asked | Should -Be 1
        $logText = $script:m2Log -join "`n"
        $logText | Should -Match 'skipped Ps Gun One'
        $logText | Should -Match 'skipped Ps Gun Two'
        $logText | Should -Match 'skipped No Path Gun'
    }

    It 'does not copy ElfLdr2 crosshairs into the TeknoParrot folder when the loader folder is missing' {
        # Mutation: fall back to the TeknoParrot root again -> P1.png and P2.png land where the loader never reads them and are reported as deployed.
        $tp = New-M2Root 'cross-noelf-tp'
        $profiles = New-M2Root 'cross-noelf-profiles'
        Set-Content -LiteralPath (Join-Path $profiles 'ElfGun.xml') -Value '<GameProfile><GameName>Elf Gun</GameName><GunGame>true</GunGame><EmulatorType>ElfLdr2</EmulatorType></GameProfile>'
        $crosshairs = Join-Path (Split-Path -Parent $script:m2FunctionFile) 'Crosshairs'
        [void][System.IO.Directory]::CreateDirectory($crosshairs)
        Set-Content -LiteralPath (Join-Path $crosshairs '000.png') -Value 'png'
        Set-Content -LiteralPath (Join-Path $crosshairs '001.png') -Value 'png'
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        $script:m2Targets = $null
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-TpmText { [void]$script:m2Rows.Add([string]$Text) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Test-PngFile { $true }
        Mock Show-TpmCrosshairPreviewWindow { [pscustomobject]@{ Available = $true; Cancelled = $false; P1Index = 0; P2Index = 1; TimedOut = $false } }
        Mock Read-TpmCrosshairYesNo { 'Y' }
        Mock Read-TpmYesNo { 'N' }
        Mock Invoke-TpmCrosshairAssetTransaction { $script:m2Targets = @($Targets); New-TpmFileBatchResult -WorkflowKey 'CrosshairSetup' -OperationKey 'P1P2' -Outcome 'NO_OP' -ProductState 'UNCHANGED' -Summary 'fixture' -ReasonCode 'FIXTURE' -FinalAttempted $true -FinalPassed $true -FinalChecks @('fixture') }
        $null = Invoke-CrosshairSetup -UserProfilesDir $profiles -TpRoot $tp
        @($script:m2Targets).Count | Should -Be 0
        (Get-M2Text) | Should -Match 'ElfLdr2: loader folder not found'
    }

    It 'does not write crosshairs into a folder that only has "elf" in its name, and lists the game as skipped' {
        # Mutation: match any folder containing "elf" again -> P1.png and P2.png land in an unrelated folder and the game is reported as deployed.
        $tp = New-M2Root 'cross-lookalike-tp'
        $lookalike = Join-Path $tp 'MyShelfBackup'
        [void][System.IO.Directory]::CreateDirectory($lookalike)
        $profiles = New-M2Root 'cross-lookalike-profiles'
        Set-Content -LiteralPath (Join-Path $profiles 'ElfGun.xml') -Value '<GameProfile><GameName>Elf Gun</GameName><GunGame>true</GunGame><EmulatorType>ElfLdr2</EmulatorType></GameProfile>'
        $crosshairs = Join-Path (Split-Path -Parent $script:m2FunctionFile) 'Crosshairs'
        [void][System.IO.Directory]::CreateDirectory($crosshairs)
        Set-Content -LiteralPath (Join-Path $crosshairs '000.png') -Value 'png'
        Set-Content -LiteralPath (Join-Path $crosshairs '001.png') -Value 'png'
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        $script:m2Targets = $null
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-TpmText { [void]$script:m2Rows.Add([string]$Text) }
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Test-PngFile { $true }
        Mock Show-TpmCrosshairPreviewWindow { [pscustomobject]@{ Available = $true; Cancelled = $false; P1Index = 0; P2Index = 1; TimedOut = $false } }
        Mock Read-TpmCrosshairYesNo { 'Y' }
        Mock Read-TpmYesNo { 'N' }
        Mock Invoke-TpmCrosshairAssetTransaction { $script:m2Targets = @($Targets); New-TpmFileBatchResult -WorkflowKey 'CrosshairSetup' -OperationKey 'P1P2' -Outcome 'NO_OP' -ProductState 'UNCHANGED' -Summary 'fixture' -ReasonCode 'FIXTURE' -FinalAttempted $true -FinalPassed $true -FinalChecks @('fixture') }
        $result = Invoke-CrosshairSetup -UserProfilesDir $profiles -TpRoot $tp
        @($script:m2Targets).Count | Should -Be 0
        @($result.DeployedGames).Count | Should -Be 0
        @($result.SkippedGames | Where-Object { $_ -like 'Elf Gun: the ElfLdr2 loader folder was not found*' }).Count | Should -Be 1
    }
}

Describe 'FIXM2 finding 19: Health Check when the optional areas were not scanned' {
    BeforeEach {
        $script:m2Rows = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:m2Rows.Add([string]($Object -join ' ')) }
        Mock Write-Log {}
        Mock Get-ConsoleContentWidth { return 100 }
    }
    It 'does not report 0 installs for ReShade and BepInEx in Details or in the action menu' {
        # Mutation: print the counts even when the areas were never scanned -> "ReShade installed: 0 of 12" for games nobody looked at.
        $result = New-M2HealthResult -Unavailable $true
        $details = (@(Get-TpmLibraryHealthDetailBlocks -Result $result | ForEach-Object { @($_.Lines) }) -join "`n")
        $details | Should -Match 'ReShade installed: not checked'
        $details | Should -Match 'BepInEx installed: not checked'
        $details | Should -Not -Match 'installed: 0 of'
        Write-TpmLibraryHealthActionMenu -Result $result
        (Get-M2Text) | Should -Not -Match 'have it'
    }

    It 'still reports the real counts when the areas were scanned' {
        # Mutation: always hide the counts -> a user whose scan worked never sees how many games have ReShade or BepInEx.
        $result = New-M2HealthResult -Unavailable $false
        $details = (@(Get-TpmLibraryHealthDetailBlocks -Result $result | ForEach-Object { @($_.Lines) }) -join "`n")
        $details | Should -Match 'ReShade installed: 0 of 12'
        Write-TpmLibraryHealthActionMenu -Result $result
        (Get-M2Text) | Should -Match '0 of 12 games have it'
    }
}
