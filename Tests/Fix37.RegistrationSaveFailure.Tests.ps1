#Requires -Module Pester
# Issue: https://github.com/Jumpstile/teknoparrot-manager/issues/352 (FIX37)
# A registration profile save that throws is a KNOWN failure (FailedItems, so a
# sibling success can still end PARTIAL_APPLIED) only when the target profile is
# proven byte-for-byte what it was before the attempt. Any other state stays
# UNKNOWN / ACTION_REQUIRED. Fixtures live in TestDrive; Save-Xml is mocked.
BeforeAll {
    $tokens = $null; $errors = $null
    $script:fix37Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $wanted = @(
        'Register-Games', 'Open-TpmRegistrationLedgerOperation',
        'Update-TpmRegistrationLedgerUnit', 'Read-TpmRegistrationLedger',
        'Get-TpmSupportLedgerProjection', 'Resolve-TpmRegistrationSaveFailure',
        'Get-TpmProfileWriteFingerprint'
    )
    $boundaries = @('Write-Host', 'Write-Log', 'Write-TpmCompactExtractionProgress',
        'Get-GameFiles', 'Get-TpmRegisteredProfileFilesWithDiscoveryProgress',
        'Get-TpmDirectoryEntriesWithDiscoveryProgress', 'Get-ManagerDisplayVersion',
        'Get-TpmSessionRunId')
    $definitions = @{}
    foreach ($definition in @($script:fix37Ast.FindAll({
        $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true))) { $definitions[$definition.Name] = $definition }
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($name in $wanted) {
        if (-not $definitions.ContainsKey($name)) { throw "Missing function $name" }
        $queue.Enqueue($name)
    }
    $selected = @{}
    while ($queue.Count -gt 0) {
        $name = $queue.Dequeue()
        if ($selected.ContainsKey($name) -or $boundaries -contains $name) { continue }
        $selected[$name] = $definitions[$name]
        foreach ($command in @($definitions[$name].FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst]
        }, $true))) {
            $called = $command.GetCommandName()
            if ($called -and $definitions.ContainsKey($called)) { $queue.Enqueue($called) }
        }
    }
    $functionPath = Join-Path $TestDrive 'fix37-functions.ps1'
    ($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath
    function Write-Log { param($Message) }
    function Write-TpmCompactExtractionProgress {
        param($Phase, $Label, $Current, $Total, $StartedAt, [switch]$Complete, $Outcome)
    }
    function Get-ManagerDisplayVersion { return 'FIX37 fixture' }
    function Get-TpmSessionRunId { return $script:fix37RunId }
    function Get-GameFiles {
        param([string]$folder, [scriptblock]$ProgressScript, [string[]]$ExtraExtensions)
        Get-ChildItem -LiteralPath $folder -File -Filter '*.exe' -Recurse | Sort-Object FullName
    }
    function Get-TpmRegisteredProfileFilesWithDiscoveryProgress {
        param($UserProfilesDir, $ProgressLabel, $EnumerationErrorAction)
        Get-ChildItem -LiteralPath $UserProfilesDir -File -Filter '*.xml'
    }
    function Get-TpmDirectoryEntriesWithDiscoveryProgress {
        param($DirectoryPath, $ProgressLabel, $Filter = '*', $EnumerationErrorAction,
            [switch]$IncludeDirectories, [switch]$Force)
        $entries = @(Get-ChildItem -LiteralPath $DirectoryPath -Filter $Filter -Force:$Force)
        if ($IncludeDirectories) { return $entries }
        return @($entries | Where-Object { -not $_.PSIsContainer })
    }
    function Add-Fix37Game {
        param([string]$Folder, [string]$Code, [string]$ExeName = 'game.exe')
        $directory = Join-Path $script:fix37Games $Folder
        [void][IO.Directory]::CreateDirectory($directory)
        $exe = Join-Path $directory $ExeName
        [IO.File]::WriteAllText($exe, 'fixture executable')
        [IO.File]::WriteAllText((Join-Path $script:fix37Templates ($Code + '.xml')),
            ('<GameProfile><ExecutableName>{0}</ExecutableName><ConfigValues /></GameProfile>' -f $ExeName))
        return [pscustomobject]@{ Code = $Code; TemplatePath = (Join-Path $script:fix37Templates ($Code + '.xml')); Exe = $exe; Folder = $Folder }
    }
    function Open-Fix37SelectedManifest {
        param([string[]]$Folders)
        $opened = Open-TpmRegistrationLedgerOperation -Mode AutoSync -InstallRoot $script:fix37Games `
            -Units @($Folders | ForEach-Object { [pscustomobject]@{ Folder = $_ } })
        if (-not $opened.Opened) { throw $opened.Message }
        foreach ($folder in $Folders) {
            $updated = Update-TpmRegistrationLedgerUnit -OperationId $opened.OperationId `
                -SourceName $folder -Extraction SUCCEEDED -TargetFolder $folder -Publish
            if (-not $updated) { throw "Could not publish fixture extraction for $folder" }
        }
    }
    function Read-Fix37Evidence {
        $script:TpmRegistrationLedger = $null
        $read = Read-TpmRegistrationLedger -Path $script:fix37Ledger
        if ($read.Status -ne 'Ok') { throw $read.Message }
        return (Get-TpmSupportLedgerProjection -Read $read -RunId 'later-session' -UserProfilesDir $script:fix37Profiles)
    }
    function New-Fix37ExistingProfile {
        # An existing profile that still needs its GamePath2 backfilled, so
        # Register-Games takes the Backfill-SecondaryExecutablePath write path.
        param($Game)
        $secondary = Join-Path (Split-Path $Game.Exe -Parent) 'second.exe'
        [IO.File]::WriteAllText($secondary, 'secondary executable')
        $profilePath = Join-Path $script:fix37Profiles ($Game.Code + '.xml')
        $doc = [xml]('<GameProfile><GamePath /><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>second.exe</ExecutableName2></GameProfile>')
        $doc.GameProfile.GamePath = [string]$Game.Exe
        $doc.Save($profilePath)
        return $profilePath
    }
}

Describe 'FIX37: registration save failure is known only when the profile is proven unchanged' -Tag 'RC8-Issue' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:fix37Games = Join-Path $root 'Games'
        $script:fix37Profiles = Join-Path $root 'UserProfiles'
        $script:fix37Templates = Join-Path $root 'GameProfiles'
        $state = Join-Path $root 'State'
        foreach ($directory in @($script:fix37Games, $script:fix37Profiles, $script:fix37Templates, $state)) {
            [void][IO.Directory]::CreateDirectory($directory)
        }
        $script:fix37Ledger = Join-Path $state 'TPM-RegistrationLedger.json'
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $state }
        $script:TpmRegistrationLedger = $null; $script:TpmRegistrationLedgerStopLatch = $null
        $script:TpmStartupIdentity = $null; $script:fix37RunId = 'fix37-session'
        $script:RawThrillsPathLimits = @{}; $script:FuzzyAutoThreshold = 0.72; $script:FuzzyTieMargin = 0.1
        $script:TitleTokenStopWords = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    }
    AfterEach {
        $script:TpmRegistrationLedger = $null; $script:TpmRegistrationLedgerStopLatch = $null
        $script:TpmOwnedLayout = $null; $script:TpmStartupIdentity = $null
    }

    # Mutation: make Resolve-TpmRegistrationSaveFailure always return the caller's
    # WriteAttempted ($true) -> BETA lands in UnknownItems, Outcome ACTION_REQUIRED,
    # and this test fails.
    It 'new profile: save throws and no file appears -> known failure (FAILED_BEFORE_MUTATION), not unknown' {
        $game = Add-Fix37Game -Folder B -Code BETA
        Mock Save-Xml { throw 'injected new-file save failure' }
        Open-Fix37SelectedManifest @('B')
        $result = Register-Games -userProfilesDir $script:fix37Profiles -installFolder $script:fix37Games `
            -profileIndex @{ 'game.exe' = @($game) } -gameProfilesDir $script:fix37Templates -GameFolders @('B')
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.Succeeded | Should -BeFalse
        @($result.Mutation.FailedItems) | Should -Contain BETA
        @($result.Mutation.UnknownItems).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:fix37Profiles 'BETA.xml') | Should -BeFalse
        $operation = @((Read-Fix37Evidence).Ledger.Operations)[0]
        $mapping = @($operation.Mappings | Where-Object Code -eq BETA)[0]
        $mapping.State | Should -Not -Be 'VERIFIED'
        $mapping.Reason | Should -Match 'injected new-file save failure'
        $mapping.Reason | Should -Match 'verified unchanged'
        @((Read-Fix37Evidence).Transactions.Operations)[0].Transaction.Outcome | Should -Be $result.Outcome
    }

    # Mutation: drop the SHA-256 comparison in Resolve-TpmRegistrationSaveFailure
    # (treat any existing file as unchanged) -> the changed-bytes case below turns
    # into a known failure and its ACTION_REQUIRED assertion fails; or always return
    # WriteAttempted $true -> this test fails.
    It 'existing profile: save throws before any byte changes -> known failure and the file is byte-identical' {
        $game = Add-Fix37Game -Folder A -Code ALPHA
        $profilePath = New-Fix37ExistingProfile -Game $game
        $before = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
        Mock Save-Xml { throw 'injected pre-change save failure' }
        $result = Register-Games -userProfilesDir $script:fix37Profiles -installFolder $script:fix37Games `
            -profileIndex @{ 'game.exe' = @($game) } -gameProfilesDir $script:fix37Templates
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        @($result.Mutation.FailedItems) | Should -Contain ALPHA
        @($result.Mutation.UnknownItems).Count | Should -Be 0
        @($result.Mutation.ChangedItems).Count | Should -Be 0
        (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash | Should -Be $before
    }

    # Mutation: classify by "file still exists" instead of SHA-256 equality, or
    # always return WriteAttempted $false -> this test fails (item becomes failed,
    # not UNKNOWN / ACTION_REQUIRED).
    It 'existing profile: save throws AFTER the bytes changed -> stays UNKNOWN / ACTION_REQUIRED' {
        $game = Add-Fix37Game -Folder A -Code ALPHA
        $profilePath = New-Fix37ExistingProfile -Game $game
        Mock Save-Xml {
            [IO.File]::WriteAllText($path, '<GameProfile><GamePath>half-written</GamePath></GameProfile>')
            throw 'injected post-change save failure'
        }
        $result = Register-Games -userProfilesDir $script:fix37Profiles -installFolder $script:fix37Games `
            -profileIndex @{ 'game.exe' = @($game) } -gameProfilesDir $script:fix37Templates
        $result.Outcome | Should -Be 'ACTION_REQUIRED'
        @($result.Mutation.UnknownItems) | Should -Contain ALPHA
        @($result.Mutation.FailedItems) | Should -Not -Contain ALPHA
    }

    # Mutation: treat "file absent before" as proof without re-reading after the
    # failure (skip the post-failure fingerprint) -> a file that appeared during the
    # failed save is reported as a known failure and this test fails.
    It 'new profile: save throws after a partial file appeared -> stays UNKNOWN / ACTION_REQUIRED' {
        $game = Add-Fix37Game -Folder B -Code BETA
        Mock Save-Xml {
            [IO.File]::WriteAllText($path, '<GameProfile><GamePath>partial')
            throw 'injected partial-file save failure'
        }
        Open-Fix37SelectedManifest @('B')
        $result = Register-Games -userProfilesDir $script:fix37Profiles -installFolder $script:fix37Games `
            -profileIndex @{ 'game.exe' = @($game) } -gameProfilesDir $script:fix37Templates -GameFolders @('B')
        $result.Outcome | Should -Be 'ACTION_REQUIRED'
        @($result.Mutation.UnknownItems) | Should -Contain BETA
        @($result.Mutation.FailedItems) | Should -Not -Contain BETA
        $mapping = @(@((Read-Fix37Evidence).Ledger.Operations)[0].Mappings | Where-Object Code -eq BETA)[0]
        $mapping.State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
        $mapping.Reason | Should -Match 'injected partial-file save failure'
    }

    # Mutation: restore the old behavior (every caught save exception is
    # WriteAttempted $true) -> both games become UnknownItems and the outcome is
    # ACTION_REQUIRED.
    It 'all writes fail with nothing written: every game is a known failure, no success is claimed' {
        $first = Add-Fix37Game -Folder A -Code ALPHA -ExeName alpha.exe
        $second = Add-Fix37Game -Folder B -Code BETA -ExeName beta.exe
        Mock Save-Xml { throw 'injected all-failed save' }
        Open-Fix37SelectedManifest @('A', 'B')
        $result = Register-Games -userProfilesDir $script:fix37Profiles -installFolder $script:fix37Games `
            -profileIndex @{ 'alpha.exe' = @($first); 'beta.exe' = @($second) } `
            -gameProfilesDir $script:fix37Templates -GameFolders @('A', 'B')
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.Succeeded | Should -BeFalse
        @($result.Registered).Count | Should -Be 0
        @($result.Mutation.FailedItems | Sort-Object) -join ',' | Should -Be 'ALPHA,BETA'
        @($result.Mutation.UnknownItems).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:fix37Profiles -Filter '*.xml').Count | Should -Be 0
        $operation = @((Read-Fix37Evidence).Ledger.Operations)[0]
        @($operation.Mappings | Where-Object State -eq 'VERIFIED').Count | Should -Be 0
        @($operation.Mappings | Where-Object { $_.Reason -notmatch 'injected all-failed save' }).Count | Should -Be 0
        @((Read-Fix37Evidence).Transactions.Operations)[0].Transaction.Outcome | Should -Be $result.Outcome
    }

    # Mutation: same as the first test (old all-unknown behavior) -> Outcome
    # becomes ACTION_REQUIRED instead of PARTIAL_APPLIED.
    It 'mixed A saved and read back, B save throws with no file: PARTIAL_APPLIED, A completed, B failed with the real reason' {
        $first = Add-Fix37Game -Folder A -Code ALPHA -ExeName alpha.exe
        $second = Add-Fix37Game -Folder B -Code BETA -ExeName beta.exe
        $script:fix37RealSave = ${function:Save-Xml}
        Mock Save-Xml {
            if ([IO.Path]::GetFileName($path) -eq 'BETA.xml') { throw 'injected B save failure' }
            & $script:fix37RealSave -doc $doc -path $path
        }
        Open-Fix37SelectedManifest @('A', 'B')
        $result = Register-Games -userProfilesDir $script:fix37Profiles -installFolder $script:fix37Games `
            -profileIndex @{ 'alpha.exe' = @($first); 'beta.exe' = @($second) } `
            -gameProfilesDir $script:fix37Templates -GameFolders @('A', 'B')
        $result.Outcome | Should -Be 'PARTIAL_APPLIED'
        $result.Succeeded | Should -BeFalse
        @($result.Mutation.CompletedItems) | Should -Contain ALPHA
        @($result.Mutation.FailedItems) | Should -Contain BETA
        @($result.Mutation.UnknownItems).Count | Should -Be 0
        [string](Read-Xml (Join-Path $script:fix37Profiles 'ALPHA.xml')).GameProfile.GamePath | Should -Be $first.Exe
        Test-Path -LiteralPath (Join-Path $script:fix37Profiles 'BETA.xml') | Should -BeFalse
        $operation = @((Read-Fix37Evidence).Ledger.Operations)[0]
        $failed = @($operation.Mappings | Where-Object Code -eq BETA)[0]
        $failed.State | Should -Not -Be 'VERIFIED'
        $failed.Reason | Should -Match 'injected B save failure'
        @($operation.Mappings | Where-Object Code -eq ALPHA)[0].State | Should -Be 'VERIFIED'
        @((Read-Fix37Evidence).Transactions.Operations)[0].Transaction.Outcome | Should -Be $result.Outcome
    }

    # Mutation: make Get-TpmProfileWriteFingerprint return Known = $true with an
    # empty hash when ReadAllBytes throws -> the locked file below is wrongly
    # proven unchanged and this test fails.
    It 'a pre-state or post-failure state that cannot be read is never proof of an unchanged profile' {
        $path = Join-Path $script:fix37Profiles 'LOCKED.xml'
        [IO.File]::WriteAllText($path, '<GameProfile />')
        $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            (Get-TpmProfileWriteFingerprint -Path $path).Known | Should -BeFalse
        } finally { $stream.Dispose() }
        $known = Get-TpmProfileWriteFingerprint -Path $path
        $known.Known | Should -BeTrue
        $known.Exists | Should -BeTrue
        # Lock the file only AFTER the pre-state was captured: the post-failure
        # re-read throws, so the failure must stay an attempted (unknown) write.
        $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            $resolved = Resolve-TpmRegistrationSaveFailure -WriteAttempted $true -PreState $known -Message 'boom'
            $resolved.WriteAttempted | Should -BeTrue
            $resolved.Reason | Should -Be 'boom'
        } finally { $stream.Dispose() }
        # No fingerprint at all -> unchanged is not provable.
        (Resolve-TpmRegistrationSaveFailure -WriteAttempted $true -PreState $null -Message 'boom').WriteAttempted | Should -BeTrue
        # Nothing was attempted (dry run / pre-write failure) -> caller value passes through.
        (Resolve-TpmRegistrationSaveFailure -WriteAttempted $false -PreState $known -Message 'boom').WriteAttempted | Should -BeFalse
    }
}
