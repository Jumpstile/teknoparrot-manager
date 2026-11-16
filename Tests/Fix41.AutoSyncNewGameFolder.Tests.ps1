#Requires -Module Pester

# FIX41 P02: first-time AutoSync extraction of a ZIP whose game folder does not
# exist yet. Isolated fake ZIPs and folders under $TestDrive only; run on the test PC
# by the coordinator. Each It names the product change that makes it fail.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX41 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix41-autosync-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    # Exactly one TpmProgress per session: an earlier test file can leave its own copy (from a removed $TestDrive)
    # loaded, so the first real extraction here would start from that foreign module state.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix41-autosync.log'
    $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    # Root\Games is the install folder (as configured), Root\Zips the source,
    # Root\State the owned State folder that enables the registration ledger.
    function New-Fix41Fixture {
        $root = Join-Path $TestDrive ('f41-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $fx = [pscustomobject]@{
            Root = $root; Games = (Join-Path $root 'Games'); Zips = (Join-Path $root 'Zips')
            Profiles = (Join-Path $root 'UserProfiles'); State = (Join-Path $root 'State')
            SyncState = (Join-Path $root 'Games\TeknoParrot-Manager.syncstate.json')
            Ledger = (Join-Path $root 'State\TPM-RegistrationLedger.json')
        }
        New-Item -ItemType Directory -Path $fx.Games, $fx.Zips, $fx.Profiles, $fx.State -Force | Out-Null
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $fx.State }
        $script:TpmRegistrationLedger = $null
        $script:TpmSessionRunId = $null
        $script:TpmRegistrationLedgerStopLatch = $null
        return $fx
    }

    function New-Fix41Zip {
        param([string]$Path, [System.Collections.IDictionary]$Entries)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entries.Keys) {
                    $entry = $archive.CreateEntry([string]$name)
                    $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding($false)))
                    try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
    }

    function New-Fix41GameZip {
        param($Fixture, [string]$Name)
        $zip = Join-Path $Fixture.Zips ($Name + '.zip')
        New-Fix41Zip -Path $zip -Entries ([ordered]@{ 'game.exe' = ('exe of ' + $Name); 'data/level.bin' = ('level of ' + $Name) })
        return $zip
    }

    function Invoke-Fix41AutoSync {
        param($Fixture, [bool]$DryRun = $false, [bool]$RetroBat = $false, [hashtable]$DatIndex = @{})
        return (Invoke-AutoSync -zipSource $Fixture.Zips -installFolder $Fixture.Games -syncStatePath $Fixture.SyncState `
            -DryRun $DryRun -retroBat $RetroBat -datIndex $DatIndex -userProfilesDir $Fixture.Profiles)
    }

    function Get-Fix41TreeDigest {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
        $prefix = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        return ((Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length)
            if ($_.PSIsContainer) { $relative + '|dir' } else { $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }) -join "`n")
    }

    function Get-Fix41Residue {
        param($Fixture)
        return @(Get-ChildItem -LiteralPath $Fixture.Root -Force -Filter '.tpm-autosync-*') +
            @(Get-ChildItem -LiteralPath $Fixture.Games -Force -Filter '*.extracting')
    }

    function Get-Fix41LedgerUnit {
        param($Fixture, [string]$SourceName)
        $read = Read-TpmRegistrationLedger -Path $Fixture.Ledger
        if ($read.Status -ne 'Ok') { throw ('Ledger was {0}' -f $read.Status) }
        $units = @(@($read.Document.Operations)[-1].Units)
        return @($units | Where-Object { [string]$_.Folder -eq $SourceName })[0]
    }

    # Result detail for -Because: shows which refusal or transaction failure produced an unexpected count or
    # outcome. Never throws, so a missing property cannot hide the real result.
    function Get-Fix41Diagnostic {
        param($Result)
        try {
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($name in @('Synced', 'Failed', 'UnsafePathSkipped', 'Skipped', 'UpToDate', 'WouldSync', 'EvidenceRefused', 'EvidenceMessage', 'EvidenceStopped')) {
                if ($Result -is [System.Collections.IDictionary] -and $Result.Contains($name)) { [void]$parts.Add(('{0}={1}' -f $name, $Result[$name])) }
            }
            foreach ($tx in @($Result.TransactionResults)) {
                if ($null -eq $tx) { continue }
                $technical = Get-TpmTransactionField -Object $tx -Name 'TechnicalDetails'
                $cleanup = Get-TpmTransactionField -Object $tx -Name 'Cleanup'
                [void]$parts.Add(('tx: Outcome={0} Reason={1} Stage={2} Error={3} Errors={4} Residue={5}' -f
                    (Get-TpmTransactionField -Object $tx -Name 'Outcome'),
                    (Get-TpmTransactionField -Object $tx -Name 'ReasonCode'),
                    (Get-TpmTransactionField -Object $technical -Name 'Stage'),
                    (Get-TpmTransactionField -Object $technical -Name 'Error'),
                    (@(Get-TpmTransactionField -Object $tx -Name 'Errors' -Default @()) -join ' | '),
                    (@(Get-TpmTransactionField -Object $cleanup -Name 'ResiduePaths' -Default @()) -join ';')))
            }
            return ($parts -join '; ')
        } catch { return ('diagnostic unavailable: ' + $_.Exception.Message) }
    }
}

AfterAll {
    $script:TpmOwnedLayout = $null
    $script:TpmRegistrationLedger = $null
    $script:TpmRegistrationLedgerStopLatch = $null
    # The progress module was imported from this file's $TestDrive; do not leave it loaded for the next file.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:TpmProgressModuleImported = $false
    $script:TpmProgressModuleLoadedPath = ''
}

Describe 'FIX41 P02 AutoSync first-time extraction into a new game folder' {
    AfterEach {
        $script:TpmOwnedLayout = $null
        $script:TpmRegistrationLedger = $null
        $script:TpmRegistrationLedgerStopLatch = $null
    }

    It 'extracts a ZIP with no existing folder into a new verified folder, records it, and is up to date on the next run' {
        # Mutation: restore the refusal "no existing folder or profile identity confirms the extraction root"
        # whenever Resolve-ExtractedGameFolder returns nothing (Invoke-AutoSync) -> Synced 0, UnsafePathSkipped 1.
        $fx = New-Fix41Fixture
        $name = 'Alpha Game (1.00)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $target = Join-Path $fx.Games $name

        $first = Invoke-Fix41AutoSync -Fixture $fx

        $first.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $first)
        $first.Failed | Should -Be 0
        $first.UnsafePathSkipped | Should -Be 0
        @($first.SyncedNames) | Should -Be @($name)
        @($first.TransactionResults)[0].Outcome | Should -Be 'SUCCEEDED'
        [IO.File]::ReadAllText((Join-Path $target 'game.exe')) | Should -BeExactly ('exe of ' + $name)
        [IO.File]::ReadAllText((Join-Path $target 'data\level.bin')) | Should -BeExactly ('level of ' + $name)
        @(Get-ChildItem -LiteralPath $target -Recurse -File).Count | Should -Be 2
        $state = Get-Content -LiteralPath $fx.SyncState -Raw | ConvertFrom-Json
        [IO.Path]::GetFullPath([string]$state.$name.LocalPath) | Should -Be ([IO.Path]::GetFullPath($target))
        @(Get-Fix41Residue $fx).Count | Should -Be 0
        $unit = Get-Fix41LedgerUnit -Fixture $fx -SourceName $name
        [string]$unit.Extraction | Should -Be 'SUCCEEDED'
        [string]$unit.TargetFolder | Should -Be $name

        $digest = Get-Fix41TreeDigest $target
        $second = Invoke-Fix41AutoSync -Fixture $fx
        $second.Synced | Should -Be 0
        $second.UpToDate | Should -Be 1
        $second.UnsafePathSkipped | Should -Be 0
        Get-Fix41TreeDigest $target | Should -Be $digest
    }

    It 'previews a new ZIP as Would extract (new) and writes nothing' {
        # Mutation: same restored refusal in Invoke-AutoSync -> WouldSync 0 and a refusal line instead.
        $fx = New-Fix41Fixture
        $name = 'Bravo Game (2.00)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $before = Get-Fix41TreeDigest $fx.Root
        $script:fix41Host = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { $script:fix41Host.Add([string]$Object) }

        $preview = Invoke-Fix41AutoSync -Fixture $fx -DryRun $true

        $preview.WouldSync | Should -Be 1
        $preview.UnsafePathSkipped | Should -Be 0
        @($script:fix41Host | Where-Object { $_ -like '*Would extract (new) : Bravo Game (2.00)`[TP`]*' }).Count | Should -Be 1
        Get-Fix41TreeDigest $fx.Root | Should -Be $before
    }

    It 'creates a RetroBat-suffixed new folder that the next run recognizes' {
        # Mutation: name the new folder from the raw ZIP name without the RetroBat suffix
        # (FolderName = $rawName) -> the folder is not '<name>.teknoparrot'.
        $fx = New-Fix41Fixture
        $name = 'Charlie Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)

        $first = Invoke-Fix41AutoSync -Fixture $fx -RetroBat $true

        $first.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $first)
        Test-Path -LiteralPath (Join-Path $fx.Games ($name + '.teknoparrot\game.exe')) -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fx.Games $name) | Should -BeFalse
        $second = Invoke-Fix41AutoSync -Fixture $fx -RetroBat $true
        $second.UpToDate | Should -Be 1
        $second.Synced | Should -Be 0
    }

    It 'uses an empty pre-created folder with the ZIP name' {
        # Mutation: make Resolve-TpmAutoSyncNewGameFolder refuse every existing directory -> UnsafePathSkipped 1.
        $fx = New-Fix41Fixture
        $name = 'Delta Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        [void][IO.Directory]::CreateDirectory((Join-Path $fx.Games $name))

        $result = Invoke-Fix41AutoSync -Fixture $fx

        $result.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $result)
        $result.UnsafePathSkipped | Should -Be 0
        Test-Path -LiteralPath (Join-Path $fx.Games ($name + '\game.exe')) -PathType Leaf | Should -BeTrue
        @(Get-Fix41Residue $fx).Count | Should -Be 0
    }

    It 'never merges into an existing non-empty folder that no identity confirmed' {
        # Mutation: drop the folder-map and non-empty checks in Resolve-TpmAutoSyncNewGameFolder
        # together with the -NewTarget guard in Invoke-TpmAutoSyncDirectoryTransaction -> the user folder is replaced.
        $fx = New-Fix41Fixture
        $name = 'Echo Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $userFolder = Join-Path $fx.Games $name
        [void][IO.Directory]::CreateDirectory($userFolder)
        [IO.File]::WriteAllText((Join-Path $userFolder 'user-notes.txt'), 'keep me')
        Mock Resolve-ExtractedGameFolder { $null }
        $before = Get-Fix41TreeDigest $fx.Games

        $result = Invoke-Fix41AutoSync -Fixture $fx

        $result.Synced | Should -Be 0
        $result.UnsafePathSkipped | Should -Be 1
        Get-Fix41TreeDigest $fx.Games | Should -Be $before
        [string](Get-Fix41LedgerUnit -Fixture $fx -SourceName $name).Reason | Should -Be 'UNPROVEN_EXTRACTION_ROOT'
    }

    It 'refuses a new folder name that an ambiguous existing alias answers to' {
        # Mutation: treat a $null (ambiguous) folder-map entry as "no folder" in Resolve-TpmAutoSyncNewGameFolder.
        $install = Join-Path $TestDrive ('f41-alias-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][IO.Directory]::CreateDirectory($install)
        $plan = Resolve-TpmAutoSyncNewGameFolder -RawZipName 'Foxtrot Game' -FolderName 'Foxtrot Game' -InstallFolder $install -FolderMap @{ 'Foxtrot Game' = $null }
        $plan.Path | Should -BeNullOrEmpty
        $plan.Reason | Should -Not -BeNullOrEmpty

        $clean = Resolve-TpmAutoSyncNewGameFolder -RawZipName 'Foxtrot Game' -FolderName 'Foxtrot Game' -InstallFolder $install -FolderMap @{}
        $clean.Reason | Should -BeNullOrEmpty
        $clean.Path | Should -Be ([IO.Path]::GetFullPath((Join-Path $install 'Foxtrot Game')))
    }

    It 'refuses folder names that Windows would alter or that are device names: <Name>' -ForEach @(
        @{ Name = 'Game.'; Expected = $false }
        @{ Name = 'Game '; Expected = $false }
        @{ Name = 'CON'; Expected = $false }
        @{ Name = 'nul.teknoparrot'; Expected = $false }
        @{ Name = 'LPT1'; Expected = $false }
        @{ Name = '..'; Expected = $false }
        @{ Name = 'a:b'; Expected = $false }
        @{ Name = 'Golf Game (1.0)[TP]'; Expected = $true }
        @{ Name = 'Console Classics'; Expected = $true }
    ) {
        # Mutation: drop the ConvertTo-SafeZipEntryRelativePath call (or its trailing dot/space or reserved-name
        # checks) from Test-TpmAutoSyncNewFolderName -> 'Game.' or 'CON' is accepted.
        Test-TpmAutoSyncNewFolderName -Name $Name | Should -Be $Expected
    }

    It 'leaves no half folder when extraction fails and a later run extracts the game cleanly' {
        # Mutation: extract straight into the target folder instead of the transaction staging folder
        # (Invoke-TpmAutoSyncDirectoryTransaction) -> the partial file remains in the games folder.
        $fx = New-Fix41Fixture
        $name = 'Hotel Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $script:fix41RealExpand = ${function:Expand-ZipFileSafe}
        $script:fix41FailExtraction = $true
        $script:fix41ExpandCalled = $false
        Mock Expand-ZipFileSafe {
            param([string]$ZipPath, [string]$DestDir, [string]$GameName, [hashtable]$EntryHashes)
            $script:fix41ExpandCalled = $true
            if (-not $script:fix41FailExtraction) { return (& $script:fix41RealExpand -ZipPath $ZipPath -DestDir $DestDir -GameName $GameName -EntryHashes $EntryHashes) }
            [IO.File]::WriteAllText((Join-Path $DestDir 'partial.bin'), 'half written')
            throw 'injected extraction failure'
        }

        $failed = Invoke-Fix41AutoSync -Fixture $fx

        # The test must exercise the injected staging failure, not an earlier unrelated failure.
        $script:fix41ExpandCalled | Should -BeTrue -Because ('the injected extraction failure was never reached: ' + (Get-Fix41Diagnostic $failed))
        $failed.Synced | Should -Be 0
        $failed.Failed | Should -Be 1
        @($failed.TransactionResults)[0].Outcome | Should -Be 'FAILED_BEFORE_MUTATION' -Because (Get-Fix41Diagnostic $failed)
        @($failed.TransactionResults)[0].ReasonCode | Should -Be 'STAGING_FAILED' -Because (Get-Fix41Diagnostic $failed)
        Test-Path -LiteralPath (Join-Path $fx.Games $name) | Should -BeFalse
        Test-Path -LiteralPath $fx.SyncState | Should -BeFalse
        @(Get-Fix41Residue $fx).Count | Should -Be 0
        [string](Get-Fix41LedgerUnit -Fixture $fx -SourceName $name).State | Should -Be 'FAILED_BEFORE_WRITE'

        $script:TpmRegistrationLedger = $null
        $script:TpmRegistrationLedgerStopLatch = $null
        $script:fix41FailExtraction = $false
        $retry = Invoke-Fix41AutoSync -Fixture $fx
        $retry.Synced | Should -Be 1
        $retry.UnsafePathSkipped | Should -Be 0
        Test-Path -LiteralPath (Join-Path $fx.Games ($name + '\game.exe')) -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $fx.Games ($name + '\partial.bin')) | Should -BeFalse
    }

    It 'refuses a ZIP-slip entry for a new game and creates nothing' {
        # Mutation: remove the parent-traversal refusal in ConvertTo-SafeZipEntryRelativePath -> evil.txt escapes the games folder.
        $fx = New-Fix41Fixture
        $name = 'India Game (1.0)[TP]'
        New-Fix41Zip -Path (Join-Path $fx.Zips ($name + '.zip')) -Entries ([ordered]@{ 'game.exe' = 'exe'; '../evil.txt' = 'escape' })

        $result = Invoke-Fix41AutoSync -Fixture $fx

        $result.Synced | Should -Be 0
        $result.Failed | Should -Be 1
        Test-Path -LiteralPath (Join-Path $fx.Games $name) | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Games 'evil.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $fx.Root 'evil.txt') | Should -BeFalse
        @(Get-Fix41Residue $fx).Count | Should -Be 0
    }

    It 'refuses a new folder when the transaction finds content that appeared after planning' {
        # Mutation: remove the -NewTarget content guard in Invoke-TpmAutoSyncDirectoryTransaction -> the folder is replaced.
        $fx = New-Fix41Fixture
        $name = 'Juliet Game (1.0)[TP]'
        $zip = New-Fix41GameZip -Fixture $fx -Name $name
        $target = Join-Path $fx.Games $name
        [void][IO.Directory]::CreateDirectory($target)
        [IO.File]::WriteAllText((Join-Path $target 'late-user-file.txt'), 'appeared later')
        $before = Get-Fix41TreeDigest $fx.Games

        $tx = Invoke-TpmAutoSyncDirectoryTransaction -ZipPath $zip -InstallFolder $fx.Games -TargetDir $target `
            -RawName $name -SyncStatePath $fx.SyncState -SyncState @{} -NewTarget

        $tx.TransactionResult.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $tx.TransactionResult.ReasonCode | Should -Be 'AMBIGUOUS_EXTRACTION_ROOT'
        $tx.FilesystemChanged | Should -BeFalse
        Get-Fix41TreeDigest $fx.Games | Should -Be $before
        Test-Path -LiteralPath $fx.SyncState | Should -BeFalse
    }

    It 'reports a failure before the pre-state capture as unchanged, not as an unknown product state' {
        # Mutation: compare the (still null) pre-state values in the transaction's failure branch without the
        # captured-state guard -> the comparison throws and the result is ACTION_REQUIRED / PRESTATE_CHANGED.
        $fx = New-Fix41Fixture
        $name = 'November Game (1.0)[TP]'
        $zip = New-Fix41GameZip -Fixture $fx -Name $name
        $target = Join-Path $fx.Games $name
        Mock Get-TpmAutoSyncSourceIdentity { throw 'injected preflight failure' }
        $before = Get-Fix41TreeDigest $fx.Root

        $tx = Invoke-TpmAutoSyncDirectoryTransaction -ZipPath $zip -InstallFolder $fx.Games -TargetDir $target `
            -RawName $name -SyncStatePath $fx.SyncState -SyncState @{} -NewTarget

        $tx.TransactionResult.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $tx.TransactionResult.ProductState | Should -Be 'UNCHANGED'
        $tx.FilesystemChanged | Should -BeFalse
        Get-Fix41TreeDigest $fx.Root | Should -Be $before
    }

    It 'restores a registered game whose folder is gone into a new folder, binding the registered executable' {
        # Mutation: keep throwing 'Registered executable path could not be verified.' for a missing registered
        # executable inside the new folder (Invoke-AutoSync registered-profile block) -> UnsafePathSkipped 1.
        $fx = New-Fix41Fixture
        $name = 'Kilo Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $dat = @{ (Get-NormalizedGameKey $name) = [pscustomobject]@{ ProfileCode = 'KILO'; OriginalName = $name; Executable = 'game.exe' } }
        $missingExe = Join-Path (Join-Path $fx.Games $name) 'game.exe'
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'KILO.xml'), ('<GameProfile><GamePath>' + $missingExe + '</GamePath></GameProfile>'), (New-Object Text.UTF8Encoding($false)))

        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $result)
        $result.UnsafePathSkipped | Should -Be 0
        Test-Path -LiteralPath $missingExe -PathType Leaf | Should -BeTrue
    }

    It 'refuses a new folder when the game is registered at an existing executable elsewhere' {
        # Mutation: remove the "registered outside the new game folder" refusal in Invoke-AutoSync -> the
        # transaction is invoked (Failed 1 instead of an early refusal) or a duplicate copy is created.
        $fx = New-Fix41Fixture
        $name = 'Lima Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $elsewhere = Join-Path $fx.Root 'Elsewhere\Lima'
        [void][IO.Directory]::CreateDirectory($elsewhere)
        $existingExe = Join-Path $elsewhere 'game.exe'
        [IO.File]::WriteAllText($existingExe, 'installed elsewhere')
        $dat = @{ (Get-NormalizedGameKey $name) = [pscustomobject]@{ ProfileCode = 'LIMA'; OriginalName = $name; Executable = 'game.exe' } }
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'LIMA.xml'), ('<GameProfile><GamePath>' + $existingExe + '</GamePath></GameProfile>'), (New-Object Text.UTF8Encoding($false)))

        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 0
        $result.Failed | Should -Be 0
        $result.UnsafePathSkipped | Should -Be 1
        @($result.TransactionResults).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $fx.Games $name) | Should -BeFalse
        [IO.File]::ReadAllText($existingExe) | Should -BeExactly 'installed elsewhere'
    }

    It 'creates only one new folder when two ZIPs of the same game arrive in one run, in preview and for real' {
        # Mutation: drop the ClaimedKeys check in Resolve-TpmAutoSyncNewGameFolder (or never add claimed keys in
        # Invoke-AutoSync) -> both ZIPs create a folder for the same profile code in one run.
        $names = @('Mike Game (JPN)[TP]', 'Mike Game (USA)[TP]')
        $dat = @{}
        foreach ($n in $names) { $dat[(Get-NormalizedGameKey $n)] = [pscustomobject]@{ ProfileCode = 'MIKE'; OriginalName = $n; Executable = 'game.exe' } }

        $previewFx = New-Fix41Fixture
        foreach ($n in $names) { [void](New-Fix41GameZip -Fixture $previewFx -Name $n) }
        $preview = Invoke-Fix41AutoSync -Fixture $previewFx -DryRun $true -DatIndex $dat
        $preview.WouldSync | Should -Be 1
        $preview.UnsafePathSkipped | Should -Be 1

        $script:TpmOwnedLayout = $null
        $fx = New-Fix41Fixture
        foreach ($n in $names) { [void](New-Fix41GameZip -Fixture $fx -Name $n) }
        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $result)
        $result.UnsafePathSkipped | Should -Be 1
        @(Get-ChildItem -LiteralPath $fx.Games -Directory).Count | Should -Be 1
    }

    It 'leaves a played game folder alone when the ZIP did not change' {
        # Mutation: remove the "-not $needsSync" skip in Invoke-AutoSync -> the folder is swapped for a fresh copy and the player's save and changed settings are gone.
        $fx = New-Fix41Fixture
        $name = 'November Game (1.00)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $target = Join-Path $fx.Games $name
        (Invoke-Fix41AutoSync -Fixture $fx).Synced | Should -Be 1
        [IO.File]::WriteAllText((Join-Path $target 'save.dat'), 'my-save')
        [IO.File]::WriteAllText((Join-Path $target 'game.exe'), 'my-changed-settings')
        $digest = Get-Fix41TreeDigest $target

        $second = Invoke-Fix41AutoSync -Fixture $fx

        $second.UpToDate | Should -Be 1
        $second.Synced | Should -Be 0
        Get-Fix41TreeDigest $target | Should -Be $digest
    }
}
