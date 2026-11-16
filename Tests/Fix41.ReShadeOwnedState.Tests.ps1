#Requires -Module Pester

# FIX41 P05: ReShade profile and ownership state lives in <owned State>\ReShade, and
# the startup owned-state migration plans a script-folder ReShade folder entry by
# entry, so a ReShade deployment no longer stops the next TeknoParrot Manager start.
# Fake folders and files under $TestDrive only: no network, registry, service,
# TeknoParrot, LaunchBox or live game is touched. Each It names the product change
# that makes it fail.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX41 ReShade bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix41-reshade-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    # Exactly one TpmProgress per session: drop a copy an earlier test file left loaded from its removed $TestDrive.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix41-reshade-owned-state.log'
    $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    # Root\program is the script folder, Root\TeknoParrot the TeknoParrot root whose
    # TeknoParrotManager folder is the initialized owned layout. The root folder name is 4 characters on purpose: the longest file
    # the removal writes (the undo receipt of a game, under <owned State>\ReShade\UndoReceipts) must stay below the 260-character
    # path limit of Windows PowerShell 5.1 even when $TestDrive is a long path (the shard harness TEMP is already 49 characters).
    # The guard below keeps that true; the product handles a too-long path safely (New-TpmReShadeUndoReceipt fails the receipt and the game is not changed).
    function New-Fix41ReShadeFixture {
        param([string]$ScriptRoot = '')
        # A long $TestDrive (a long TEMP) would push the undo receipt path past 259 characters; use a short folder on the same drive then.
        $fixtureBase = $TestDrive
        if ($TestDrive.Length -gt 40) {
            # One uniquely named folder per run, created here and the only thing AfterAll deletes; never a shared fixed name.
            if (-not ($script:Fix41ShortBase -and (Test-Path -LiteralPath $script:Fix41ShortBase))) {
                do { $script:Fix41ShortBase = Join-Path ([IO.Path]::GetPathRoot($TestDrive)) ('fx' + [guid]::NewGuid().ToString('N').Substring(0, 6)) } while (Test-Path -LiteralPath $script:Fix41ShortBase)
                [void][IO.Directory]::CreateDirectory($script:Fix41ShortBase)
            }
            $fixtureBase = $script:Fix41ShortBase
        }
        do { $root = Join-Path $fixtureBase ('f' + [guid]::NewGuid().ToString('N').Substring(0, 3)) } while (Test-Path -LiteralPath $root)
        if ([string]::IsNullOrWhiteSpace($ScriptRoot)) { $ScriptRoot = Join-Path $root 'program' }
        $tpRoot = Join-Path $root 'TeknoParrot'
        New-Item -ItemType Directory -Path $ScriptRoot, $tpRoot -Force | Out-Null
        $layout = Initialize-TpmOwnedLayout -Layout (Get-TpmOwnedLayout -TeknoParrotRoot $tpRoot)
        $receiptTail = '\ReShade\UndoReceipts\' + ('0' * 64) + '\' + ('0' * 28) + '\receipt.json.' + ('0' * 32) + '.tmp'
        if (([string]$layout.State).Length + $receiptTail.Length -gt 259) { throw "FIX41 fixture: the undo receipt path would be longer than 259 characters under '$($layout.State)'; shorten `$TestDrive." }
        return [pscustomobject]@{
            Root = $root; ScriptRoot = $ScriptRoot; TeknoParrotRoot = $tpRoot; Layout = $layout
            LegacyReShade = (Join-Path $ScriptRoot 'ReShade')
            LegacyState = (Join-Path $ScriptRoot 'ReShade\TPM-State')
            ManagedState = (Join-Path $layout.State 'ReShade')
            AssetsReShade = (Join-Path $layout.Assets 'ReShade')
        }
    }

    # A registered game 'Flow' whose dxgi.dll hook was deployed by TeknoParrot Manager,
    # built exactly like the ReShade removal tests build their owned game.
    function New-Fix41ReShadeGame {
        param([Parameter(Mandatory)]$Fixture)
        $profilesDir = Join-Path $Fixture.Root 'UserProfiles'
        $gameDir = Join-Path $Fixture.Root 'Games\Flow'
        [IO.Directory]::CreateDirectory($profilesDir) | Out-Null
        [IO.Directory]::CreateDirectory($gameDir) | Out-Null
        $game = Join-Path $gameDir 'game.exe'
        $hook = Join-Path $gameDir 'dxgi.dll'
        [IO.File]::WriteAllText($game, 'game')
        [IO.File]::WriteAllText($hook, 'owned')
        [IO.File]::WriteAllText((Join-Path $profilesDir 'Flow.xml'), '<GameProfile><GamePath>' + $game + '</GamePath><EmulatorType>Default</EmulatorType></GameProfile>')
        $hash = (Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash
        $manifest = [pscustomobject]@{ SchemaVersion=1; EffectId='ReShadeProfile.CleanSharp'; PinnedRevision='TPM-PROFILE'; Files=@([pscustomobject]@{ RelativeSource='dxgi.dll'; DestinationPath=$hook; ExpectedSHA256=$hash; ActualSHA256=$hash; TPMManaged=$true; Kind='ReShadeDll' }) }
        return [pscustomobject]@{ GameId='Flow'; ProfilesDir=$profilesDir; Game=$game; Hook=$hook; Manifest=$manifest }
    }

    function Write-Fix41Bytes {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][byte[]]$Bytes)
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
        [IO.File]::WriteAllBytes($Path, $Bytes)
    }

    function Get-Fix41Base64 {
        param([Parameter(Mandatory)][string]$Path)
        return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
    }

    # Relative path and SHA256 of every file below Path, sorted; '<missing>' when absent.
    function Get-Fix41TreeDigest {
        param([Parameter(Mandatory)][string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '<missing>' }
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        $rows = @(Get-ChildItem -LiteralPath $full -Recurse -Force -File | ForEach-Object {
            $_.FullName.Substring($full.Length + 1) + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        } | Sort-Object)
        return ($rows -join "`n")
    }

    function Assert-Fix41ReShadeRemoved {
        param([Parameter(Mandatory)]$Summary, [Parameter(Mandatory)]$Game, [Parameter(Mandatory)][string]$OwnershipPath)
        $Summary.Succeeded | Should -BeTrue
        $Summary.Cancelled | Should -BeFalse
        $Summary.Removed | Should -Be 1
        $Summary.AlreadyClean | Should -Be 0
        $Summary.MissingPath | Should -Be 0
        $Summary.ProtectedBundled | Should -Be 0
        $Summary.ProtectedAmbiguous | Should -Be 0
        $Summary.Changed | Should -Be 0
        $Summary.MalformedMetadata | Should -Be 0
        $Summary.RolledBack | Should -Be 0
        $Summary.Failed | Should -Be 0
        @($Summary.Results).Count | Should -Be 1
        @($Summary.Results)[0].Status | Should -Be 'Removed'
        [IO.Path]::GetFullPath([string]@($Summary.Scan.Records)[0].OwnershipPath) | Should -Be ([IO.Path]::GetFullPath($OwnershipPath))
        Test-Path -LiteralPath $Game.Hook -PathType Leaf | Should -BeFalse
        Test-Path -LiteralPath $Game.Game -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $OwnershipPath -PathType Leaf | Should -BeFalse
        @(Get-ChildItem -LiteralPath (Join-Path $Game.ProfilesDir 'FullBackup') -Recurse -File -ErrorAction SilentlyContinue).Count | Should -BeGreaterThan 0
    }

    # Migration detail for -Because: a backup or move failure is reported as CLEANUP_RESIDUE or ACTION_REQUIRED, so
    # the outcome alone does not say what stopped it. Never throws.
    function Get-Fix41MigrationDiagnostic {
        param($Result)
        try {
            return ('Outcome={0} Underlying={1} Reason={2} BackupStage={3} BackupFailure={4} Residue={5}' -f
                (Get-TpmTransactionField -Object $Result -Name 'Outcome'),
                (Get-TpmTransactionField -Object $Result -Name 'UnderlyingOutcome'),
                (Get-TpmTransactionField -Object $Result -Name 'ReasonCode'),
                (Get-TpmTransactionField -Object (Get-TpmTransactionField -Object $Result -Name 'Backup') -Name 'FailureStage'),
                (Get-TpmTransactionField -Object (Get-TpmTransactionField -Object $Result -Name 'Backup') -Name 'FailureCode'),
                (@(Get-TpmTransactionField -Object (Get-TpmTransactionField -Object $Result -Name 'Cleanup') -Name 'ResiduePaths' -Default @()) -join ';'))
        } catch { return ('diagnostic unavailable: ' + $_.Exception.Message) }
    }
}

AfterAll {
    $script:TpmOwnedLayout = $null
    if ($script:Fix41ShortBase -and (Test-Path -LiteralPath $script:Fix41ShortBase)) { Remove-Item -LiteralPath $script:Fix41ShortBase -Recurse -Force -ErrorAction SilentlyContinue }
    # The progress module was imported from this file's $TestDrive; do not leave it loaded for the next file.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:TpmProgressModuleImported = $false
    $script:TpmProgressModuleLoadedPath = ''
}

Describe 'FIX41 P05 ReShade state in the owned layout and its startup migration' {
    BeforeEach {
        $script:TpmOwnedLayout = $null
    }
    AfterEach {
        $script:TpmOwnedLayout = $null
    }

    It 'A: keeps default ReShade state under the owned State folder while an explicit state root still wins' {
        # Mutation: revert the owned-layout elseif in Get-TpmReShadeStatePath so the default root stays <script folder>\ReShade\TPM-State.
        $fx = New-Fix41ReShadeFixture
        $managedRoot = [IO.Path]::GetFullPath($fx.ManagedState)

        $script:TpmOwnedLayout = $null
        $fallback = Get-TpmReShadeStatePath
        $fallback.Root | Should -Match '\\ReShade\\TPM-State$'

        $script:TpmOwnedLayout = $fx.Layout
        $paths = Get-TpmReShadeStatePath
        $paths.Root | Should -Be $managedRoot
        $paths.Path | Should -Be (Join-Path $managedRoot 'profiles.json')
        $paths.Root | Should -Not -Be $fallback.Root
        $ownership = Get-TpmReShadeProfileOwnershipPath -GameId 'X'
        [IO.Path]::GetDirectoryName($ownership) | Should -Be (Join-Path $managedRoot 'Deployments')
        [IO.Path]::GetFileName($ownership) | Should -Match '^[0-9a-f]{64}\.json$'

        $explicitRoot = Join-Path $fx.Root 'explicit-state'
        $explicit = Get-TpmReShadeStatePath -StateRoot $explicitRoot
        $explicit.Root | Should -Be ([IO.Path]::GetFullPath($explicitRoot))
        $explicit.Path | Should -Be (Join-Path ([IO.Path]::GetFullPath($explicitRoot)) 'profiles.json')
        [IO.Path]::GetDirectoryName((Get-TpmReShadeProfileOwnershipPath -GameId 'X' -StateRoot $explicitRoot)) | Should -Be (Join-Path ([IO.Path]::GetFullPath($explicitRoot)) 'Deployments')
        [IO.Path]::GetFileName((Get-TpmReShadeProfileOwnershipPath -GameId 'X' -StateRoot $explicitRoot)) | Should -Be ([IO.Path]::GetFileName($ownership))
    }

    Context 'B: deploy, then restart' {
        AfterEach {
            # The fallback script folder of the extracted functions is $TestDrive; a regressed
            # default path would leave ReShade state there, so remove it to keep later tests isolated.
            $leftover = Join-Path $TestDrive 'ReShade'
            if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force }
        }

        It 'B: writes deployment state to the owned layout, so the next start is NO_OP and removal still finds the ownership record' {
            # Mutation: revert Get-TpmReShadeStatePath to always default to $PSScriptRoot\ReShade\TPM-State -> state lands in the extracted script folder ($TestDrive)\ReShade and the restart migration is no longer NO_OP.
            # The script folder the extracted functions fall back to is where a regressed default would write.
            $script:TpmOwnedLayout = $null
            $fallbackRoot = (Get-TpmReShadeStatePath).Root
            $legacyScriptRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($fallbackRoot))
            # Guard: never let this test write outside $TestDrive.
            $legacyScriptRoot.TrimEnd('\') | Should -Be ([IO.Path]::GetFullPath($TestDrive).TrimEnd('\'))
            Test-Path -LiteralPath (Join-Path $legacyScriptRoot 'ReShade') | Should -BeFalse
            @(Get-TpmLegacyOwnedItems -ScriptRoot $legacyScriptRoot).Count | Should -Be 0

            $fx = New-Fix41ReShadeFixture -ScriptRoot $legacyScriptRoot
            # A ReShade download created the managed cache folder.
            $cacheFile = Join-Path $fx.AssetsReShade 'ReShade_Setup_6.3.3.exe'
            $cacheBytes = [byte[]](0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00, 0x04)
            Write-Fix41Bytes -Path $cacheFile -Bytes $cacheBytes
            $game = New-Fix41ReShadeGame -Fixture $fx

            # Deployment writes, through the same default path the deploy callers use (no -StateRoot).
            $script:TpmOwnedLayout = $fx.Layout
            $profileState = [pscustomobject]@{
                Profiles = [pscustomobject]@{ Flow = [pscustomobject]@{ ProfileId='CleanSharp'; VariantId='Default'; DefinitionVersion='1'; EffectIds=@('CleanSharp') } }
                Favorites = @()
                History = [pscustomobject]@{}
            }
            Write-TpmReShadeState -State $profileState | Should -BeTrue
            $ownershipPath = Get-TpmReShadeProfileOwnershipPath -GameId $game.GameId
            Save-TpmReShadeOwnershipManifest -Manifest $game.Manifest -Path $ownershipPath

            $managedRoot = [IO.Path]::GetFullPath($fx.ManagedState)
            [IO.Path]::GetDirectoryName($ownershipPath) | Should -Be (Join-Path $managedRoot 'Deployments')
            Test-Path -LiteralPath $ownershipPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $managedRoot 'profiles.json') -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $fx.LegacyReShade | Should -BeFalse

            # Restart: the startup migration runs against the same script folder.
            Mock Read-TpmYesNo { 'Y' }
            $result = Invoke-TpmOwnedMigration -ScriptRoot $legacyScriptRoot -Layout $fx.Layout

            $result.Outcome | Should -Be 'NO_OP'
            $result.ReasonCode | Should -Be 'NO_LEGACY_STATE'
            Test-TpmOwnedMigrationStartupAllowed -MigrationResult $result | Should -BeTrue
            Test-Path -LiteralPath $fx.LegacyReShade | Should -BeFalse
            Get-Fix41Base64 -Path $cacheFile | Should -BeExactly ([Convert]::ToBase64String($cacheBytes))
            @(Get-ChildItem -LiteralPath $fx.Layout.Backups -Directory -Filter 'LegacyMigration_*').Count | Should -Be 0
            Test-Path -LiteralPath $ownershipPath -PathType Leaf | Should -BeTrue

            # 'A' selects every reviewable game in the chooser, then REMOVE confirms; no -StateRoot.
            $script:fix41RemovalPrompt = 0
            Mock Read-HostSafe { if ($script:fix41RemovalPrompt++ -eq 0) { 'A' } else { 'REMOVE' } }
            $summary = Invoke-TpmReShadeRemoval -UserProfilesDir $game.ProfilesDir -BackupRoot (Join-Path $game.ProfilesDir 'FullBackup')

            Assert-Fix41ReShadeRemoved -Summary $summary -Game $game -OwnershipPath $ownershipPath
        }
    }

    It 'C: moves an upgraded install''s script-folder TPM-State into the owned State folder beside an existing Assets\ReShade cache' {
        # Mutation: restore whole-folder planning of 'ReShade' to <Assets>\ReShade in Invoke-TpmOwnedMigration -> FAILED_BEFORE_MUTATION / DESTINATION_OCCUPIED.
        $fx = New-Fix41ReShadeFixture
        $game = New-Fix41ReShadeGame -Fixture $fx
        $legacyOwnershipPath = Get-TpmReShadeProfileOwnershipPath -GameId $game.GameId -StateRoot $fx.LegacyState
        Save-TpmReShadeOwnershipManifest -Manifest $game.Manifest -Path $legacyOwnershipPath
        $profilesBytes = [Text.Encoding]::UTF8.GetBytes('{"Profiles":{"Flow":{"ProfileId":"CleanSharp","VariantId":"Default"}},"Favorites":[],"History":{}}')
        Write-Fix41Bytes -Path (Join-Path $fx.LegacyState 'profiles.json') -Bytes $profilesBytes
        $deploymentRelative = 'Deployments\' + [IO.Path]::GetFileName($legacyOwnershipPath)
        $deploymentBase64 = Get-Fix41Base64 -Path $legacyOwnershipPath
        $cacheFile = Join-Path $fx.AssetsReShade 'ReShade_Setup_6.3.3.exe'
        $cacheBytes = [byte[]](0x4D, 0x5A, 0x01, 0x02, 0x03, 0x04)
        Write-Fix41Bytes -Path $cacheFile -Bytes $cacheBytes
        $script:TpmOwnedLayout = $fx.Layout

        Mock Read-TpmYesNo { 'Y' }
        $result = Invoke-TpmOwnedMigration -ScriptRoot $fx.ScriptRoot -Layout $fx.Layout

        $result.Outcome | Should -Be 'SUCCEEDED' -Because (Get-Fix41MigrationDiagnostic $result)
        $result.ReasonCode | Should -Be 'MIGRATED'
        Test-TpmOwnedMigrationStartupAllowed -MigrationResult $result | Should -BeTrue
        Get-Fix41Base64 -Path (Join-Path $fx.ManagedState 'profiles.json') | Should -BeExactly ([Convert]::ToBase64String($profilesBytes))
        Get-Fix41Base64 -Path (Join-Path $fx.ManagedState $deploymentRelative) | Should -BeExactly $deploymentBase64
        Test-Path -LiteralPath $fx.LegacyState | Should -BeFalse
        Get-Fix41Base64 -Path $cacheFile | Should -BeExactly ([Convert]::ToBase64String($cacheBytes))
        @(Get-ChildItem -LiteralPath $fx.AssetsReShade -Force).Count | Should -Be 1
        $result.Backup.Verified | Should -BeTrue
        @($result.Backup.Items | ForEach-Object { [string]$_.ItemId }) | Should -Be @('ReShade\TPM-State')
        $backupState = Join-Path ([string]$result.Backup.RootPath) 'ReShade\TPM-State'
        Get-Fix41Base64 -Path (Join-Path $backupState 'profiles.json') | Should -BeExactly ([Convert]::ToBase64String($profilesBytes))
        Get-Fix41Base64 -Path (Join-Path $backupState $deploymentRelative) | Should -BeExactly $deploymentBase64

        $ownershipPath = Get-TpmReShadeProfileOwnershipPath -GameId $game.GameId
        $ownershipPath | Should -Be ([IO.Path]::GetFullPath((Join-Path $fx.ManagedState $deploymentRelative)))
        # 'A' selects every reviewable game in the chooser, then REMOVE confirms; no -StateRoot.
        $script:fix41RemovalPrompt = 0
        Mock Read-HostSafe { if ($script:fix41RemovalPrompt++ -eq 0) { 'A' } else { 'REMOVE' } }
        $summary = Invoke-TpmReShadeRemoval -UserProfilesDir $game.ProfilesDir -BackupRoot (Join-Path $game.ProfilesDir 'FullBackup')

        Assert-Fix41ReShadeRemoved -Summary $summary -Game $game -OwnershipPath $ownershipPath
    }

    It 'D: moves another script-folder ReShade entry into the existing Assets\ReShade cache on its own' {
        # Mutation: plan the whole script-folder ReShade folder to <Assets>\ReShade again (or plan its non-state entries anywhere but <Assets>\ReShade\<entry>) -> DESTINATION_OCCUPIED or a wrong destination.
        $fx = New-Fix41ReShadeFixture
        $legacyDll = Join-Path $fx.LegacyReShade 'ReShade64.dll'
        $dllBytes = [byte[]](0x4D, 0x5A, 0x64, 0x64, 0x6C, 0x6C, 0x01)
        Write-Fix41Bytes -Path $legacyDll -Bytes $dllBytes
        $cacheFile = Join-Path $fx.AssetsReShade 'ReShade_Setup_6.3.3.exe'
        $cacheBytes = [byte[]](0x4D, 0x5A, 0x05, 0x06)
        Write-Fix41Bytes -Path $cacheFile -Bytes $cacheBytes
        $script:TpmOwnedLayout = $fx.Layout

        Mock Read-TpmYesNo { 'Y' }
        $result = Invoke-TpmOwnedMigration -ScriptRoot $fx.ScriptRoot -Layout $fx.Layout

        $result.Outcome | Should -Be 'SUCCEEDED' -Because (Get-Fix41MigrationDiagnostic $result)
        Test-TpmOwnedMigrationStartupAllowed -MigrationResult $result | Should -BeTrue
        Get-Fix41Base64 -Path (Join-Path $fx.AssetsReShade 'ReShade64.dll') | Should -BeExactly ([Convert]::ToBase64String($dllBytes))
        Test-Path -LiteralPath $legacyDll | Should -BeFalse
        Get-Fix41Base64 -Path $cacheFile | Should -BeExactly ([Convert]::ToBase64String($cacheBytes))
        Test-Path -LiteralPath $fx.ManagedState | Should -BeFalse
        $result.Backup.Verified | Should -BeTrue
        @($result.Backup.Items | ForEach-Object { [string]$_.ItemId }) | Should -Be @('ReShade\ReShade64.dll')
        Get-Fix41Base64 -Path (Join-Path ([string]$result.Backup.RootPath) 'ReShade\ReShade64.dll') | Should -BeExactly ([Convert]::ToBase64String($dllBytes))
    }

    It 'D: keeps a same-named script-folder ReShade file in place, never overwrites the managed copy, and lets startup continue' {
        # Mutation: plan a ReShade entry even when its Assets\ReShade destination exists -> FAILED_BEFORE_MUTATION /
        # DESTINATION_OCCUPIED and startup stops (or, with Move-Item -Force, the managed ReShade64.dll is overwritten).
        $fx = New-Fix41ReShadeFixture
        $legacyDll = Join-Path $fx.LegacyReShade 'ReShade64.dll'
        $legacyBytes = [byte[]](0x4D, 0x5A, 0x11, 0x11, 0x11)
        Write-Fix41Bytes -Path $legacyDll -Bytes $legacyBytes
        $managedDll = Join-Path $fx.AssetsReShade 'ReShade64.dll'
        $managedBytes = [byte[]](0x4D, 0x5A, 0x22, 0x22, 0x22, 0x22)
        Write-Fix41Bytes -Path $managedDll -Bytes $managedBytes
        $script:TpmOwnedLayout = $fx.Layout
        $script:fix41MigrationLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:fix41MigrationLog.Add([string]$msg) }

        Mock Read-TpmYesNo { 'Y' }
        $result = Invoke-TpmOwnedMigration -ScriptRoot $fx.ScriptRoot -Layout $fx.Layout

        $result.Outcome | Should -Be 'NO_OP'
        $result.ReasonCode | Should -Be 'NO_LEGACY_STATE'
        Test-TpmOwnedMigrationStartupAllowed -MigrationResult $result | Should -BeTrue
        Get-Fix41Base64 -Path $legacyDll | Should -BeExactly ([Convert]::ToBase64String($legacyBytes))
        Get-Fix41Base64 -Path $managedDll | Should -BeExactly ([Convert]::ToBase64String($managedBytes))
        @(Get-ChildItem -LiteralPath $fx.Layout.Backups -Directory -Filter 'LegacyMigration_*').Count | Should -Be 0
        @($script:fix41MigrationLog | Where-Object { $_.Contains('kept in place') -and $_.Contains($legacyDll) }).Count | Should -Be 1
    }

    Context 'G: declined migration' {
        AfterEach {
            $leftover = Join-Path $TestDrive 'ReShade'
            if (Test-Path -LiteralPath $leftover) { Remove-Item -LiteralPath $leftover -Recurse -Force }
        }

        It 'G: keeps using the script-folder ReShade state until it is migrated, then uses the owned state' {
            # Mutation: drop the legacy fallback in Get-TpmReShadeStatePath (always <owned State>\ReShade once a layout
            # exists) -> after a declined move the earlier ownership record is not found and removal leaves the hook.
            $script:TpmOwnedLayout = $null
            $legacyState = (Get-TpmReShadeStatePath).Root
            $legacyScriptRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($legacyState))
            # Guard: the fallback script folder of the extracted functions must be $TestDrive.
            $legacyScriptRoot.TrimEnd('\') | Should -Be ([IO.Path]::GetFullPath($TestDrive).TrimEnd('\'))
            $fx = New-Fix41ReShadeFixture -ScriptRoot $legacyScriptRoot
            $game = New-Fix41ReShadeGame -Fixture $fx
            $legacyOwnershipPath = Get-TpmReShadeProfileOwnershipPath -GameId $game.GameId -StateRoot $legacyState
            Save-TpmReShadeOwnershipManifest -Manifest $game.Manifest -Path $legacyOwnershipPath
            $script:TpmOwnedLayout = $fx.Layout

            # The move was declined: managed ReShade state does not exist yet.
            Test-Path -LiteralPath $fx.ManagedState | Should -BeFalse
            (Get-TpmReShadeStatePath).Root | Should -Be ([IO.Path]::GetFullPath($legacyState))
            Get-TpmReShadeProfileOwnershipPath -GameId $game.GameId | Should -Be $legacyOwnershipPath

            # Guard: the script folder is $TestDrive itself here, so the legacy inventory must hold only the ReShade folder.
            @(Get-TpmLegacyOwnedItems -ScriptRoot $legacyScriptRoot | ForEach-Object { [string]$_.Name }) | Should -Be @('ReShade')

            Mock Read-TpmYesNo { 'Y' }
            $migration = Invoke-TpmOwnedMigration -ScriptRoot $legacyScriptRoot -Layout $fx.Layout
            $migration.Outcome | Should -Be 'SUCCEEDED' -Because (Get-Fix41MigrationDiagnostic $migration)
            (Get-TpmReShadeStatePath).Root | Should -Be ([IO.Path]::GetFullPath($fx.ManagedState))
            $ownershipPath = Get-TpmReShadeProfileOwnershipPath -GameId $game.GameId
            Test-Path -LiteralPath $ownershipPath -PathType Leaf | Should -BeTrue

            $script:fix41RemovalPrompt = 0
            Mock Read-HostSafe { if ($script:fix41RemovalPrompt++ -eq 0) { 'A' } else { 'REMOVE' } }
            $summary = Invoke-TpmReShadeRemoval -UserProfilesDir $game.ProfilesDir -BackupRoot (Join-Path $game.ProfilesDir 'FullBackup')
            Assert-Fix41ReShadeRemoved -Summary $summary -Game $game -OwnershipPath $ownershipPath
        }
    }

    It 'E: keeps both ReShade state copies untouched and lets startup continue when the owned State ReShade folder already exists' {
        # Mutation: plan the script-folder TPM-State even when <owned State>\ReShade exists -> FAILED_BEFORE_MUTATION / DESTINATION_OCCUPIED and startup stops.
        $fx = New-Fix41ReShadeFixture
        Write-Fix41Bytes -Path (Join-Path $fx.LegacyState 'profiles.json') -Bytes ([Text.Encoding]::UTF8.GetBytes('{"Profiles":{"Old":{}},"Favorites":[],"History":{}}'))
        Write-Fix41Bytes -Path (Join-Path $fx.LegacyState 'Deployments\legacy.json') -Bytes ([byte[]](0x7B, 0x01, 0x7D))
        Write-Fix41Bytes -Path (Join-Path $fx.ManagedState 'profiles.json') -Bytes ([Text.Encoding]::UTF8.GetBytes('{"Profiles":{"New":{}},"Favorites":[],"History":{}}'))
        Write-Fix41Bytes -Path (Join-Path $fx.ManagedState 'Deployments\managed.json') -Bytes ([byte[]](0x7B, 0x02, 0x02, 0x7D))
        $legacyDigest = Get-Fix41TreeDigest -Path $fx.LegacyState
        $managedDigest = Get-Fix41TreeDigest -Path $fx.ManagedState
        $legacyDigest | Should -Not -Be $managedDigest
        $script:TpmOwnedLayout = $fx.Layout
        $script:fix41MigrationLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:fix41MigrationLog.Add([string]$msg) }

        Mock Read-TpmYesNo { 'Y' }
        $result = Invoke-TpmOwnedMigration -ScriptRoot $fx.ScriptRoot -Layout $fx.Layout

        $result.Outcome | Should -Be 'NO_OP'
        $result.ReasonCode | Should -Be 'NO_LEGACY_STATE'
        Test-TpmOwnedMigrationStartupAllowed -MigrationResult $result | Should -BeTrue
        Get-Fix41TreeDigest -Path $fx.LegacyState | Should -BeExactly $legacyDigest
        Get-Fix41TreeDigest -Path $fx.ManagedState | Should -BeExactly $managedDigest
        @(Get-ChildItem -LiteralPath $fx.Layout.Backups -Directory -Filter 'LegacyMigration_*').Count | Should -Be 0
        @($script:fix41MigrationLog | Where-Object { $_.Contains('kept in place') -and $_.Contains($fx.LegacyState) }).Count | Should -Be 1
    }

    It 'F: treats an empty leftover script-folder ReShade folder as NO_OP without prompting' {
        # Mutation: remove the 'destinations.Count -eq 0' NO_OP return in Invoke-TpmOwnedMigration -> the move prompt runs (Read-TpmYesNo throws).
        $fx = New-Fix41ReShadeFixture
        [IO.Directory]::CreateDirectory($fx.LegacyReShade) | Out-Null
        $script:TpmOwnedLayout = $fx.Layout
        Mock Read-TpmYesNo { throw 'must not prompt' }

        $result = Invoke-TpmOwnedMigration -ScriptRoot $fx.ScriptRoot -Layout $fx.Layout

        $result.Outcome | Should -Be 'NO_OP'
        $result.ReasonCode | Should -Be 'NO_LEGACY_STATE'
        Test-TpmOwnedMigrationStartupAllowed -MigrationResult $result | Should -BeTrue
        Should -Invoke Read-TpmYesNo -Times 0 -Exactly
        Test-Path -LiteralPath $fx.LegacyReShade -PathType Container | Should -BeTrue
        @(Get-ChildItem -LiteralPath $fx.Layout.Backups -Directory -Filter 'LegacyMigration_*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $fx.Layout.Reports -Filter 'TPM-migration-*.md' -File).Count | Should -Be 0
    }

    It 'H: finds a ReShade DLL the user put in the script folder, or that the tidy-up moved to the managed folder' {
        # Mutation: look only in the script folder again -> after "Tidy up now?" ReShade setup says the DLL was not found.
        $fx = New-Fix41ReShadeFixture
        $script:TpmOwnedLayout = $fx.Layout
        $scriptFolderDll = Join-Path $TestDrive 'ReShade\ReShade.ini'
        try {
            Get-TpmUserReShadeDll -FileName 'ReShade64.dll' | Should -BeNullOrEmpty
            Write-Fix41Bytes -Path (Join-Path $fx.AssetsReShade 'ReShade64.dll') -Bytes ([byte[]](1, 2))
            Get-TpmUserReShadeDll -FileName 'ReShade64.dll' | Should -BeExactly (Join-Path $fx.AssetsReShade 'ReShade64.dll')
            Write-Fix41Bytes -Path $scriptFolderDll -Bytes ([byte[]](3, 4))
            Get-TpmUserReShadeDll -FileName 'ReShade.ini' | Should -BeExactly $scriptFolderDll
        } finally {
            $script:TpmOwnedLayout = $null
            if (Test-Path -LiteralPath $scriptFolderDll) { Remove-Item -LiteralPath $scriptFolderDll -Force }
        }
    }
}
