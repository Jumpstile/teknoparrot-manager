#Requires -Module Pester

# FIX8 regression coverage. Isolated fake files only; run on the test PC by the coordinator.
BeforeAll {
    $sourcePath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX8 bootstrap could not parse TPM.' }
    $functionsPath = Join-Path $TestDrive 'fix8-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionsPath -Encoding utf8
    [void][IO.Directory]::CreateDirectory((Join-Path $TestDrive 'scripts'))
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $TestDrive 'scripts\TpmProgress.psm1')
    . $functionsPath
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'; $script:ScriptVersion = '1.0'; $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null; $script:PostgresRecoveryStatus = $null; $script:PostgresRecoveryResumeState = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix8.log'; $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}; $script:FileVersionPins = @{}; $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72; $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'), [System.StringComparer]::OrdinalIgnoreCase)

    function New-Fix8Fixture {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $fx = [pscustomobject]@{
            Root = $root; Games = (Join-Path $root 'Games'); Profiles = (Join-Path $root 'UserProfiles')
            Templates = (Join-Path $root 'GameProfiles'); Scripts = (Join-Path $root 'Scripts'); State = (Join-Path $root 'Scripts\State')
            Ledger = (Join-Path $root 'Scripts\State\TPM-RegistrationLedger.json')
        }
        New-Item -ItemType Directory -Path $fx.Games, $fx.Profiles, $fx.Templates, $fx.State -Force | Out-Null
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $fx.State }
        $script:TpmRegistrationLedger = $null; $script:TpmSessionRunId = $null; $script:TpmRegistrationLedgerStopLatch = $null
        return $fx
    }
    function Add-Fix8Game {
        param($Fixture, [string]$Code)
        $folder = Join-Path $Fixture.Games $Code
        [void][IO.Directory]::CreateDirectory($folder)
        $exe = Join-Path $folder ($Code.ToLowerInvariant() + '.exe')
        [IO.File]::WriteAllBytes($exe, [byte[]](1, 2, 3))
        [IO.File]::WriteAllText((Join-Path $Fixture.Templates ($Code + '.xml')),
            ('<GameProfile><ExecutableName>{0}.exe</ExecutableName><ConfigValues></ConfigValues></GameProfile>' -f $Code.ToLowerInvariant()))
        return (Get-Item -LiteralPath $exe)
    }
    function Read-Fix8Ledger {
        param($Fixture)
        $read = Read-TpmRegistrationLedger -Path $Fixture.Ledger
        if ($read.Status -ne 'Ok') { throw ('Unexpected ledger status: ' + $read.Status) }
        return $read.Document
    }
    function Reset-Fix8State {
        $script:TpmRegistrationLedger = $null; $script:TpmOwnedLayout = $null
        $script:TpmSessionRunId = $null; $script:TpmRegistrationLedgerStopLatch = $null
    }
}

Describe 'FIX8 evidence-stop registration outcomes' {
    AfterEach { Reset-Fix8State }
    It 'reports <Name> without losing verified product facts or attempting later folders' -ForEach @(
        @{ Name = 'persistent completion failure'; FailAt = 3; Persistent = $true; Pass = 'Exe'; Writes = 1; ExpectedOutcome = 'PARTIAL_APPLIED'; Remaining = 'BETA' }
        @{ Name = 'one-time completion failure'; FailAt = 3; Persistent = $false; Pass = 'Exe'; Writes = 1; ExpectedOutcome = 'PARTIAL_APPLIED'; Remaining = 'BETA' }
        @{ Name = 'first pre-write failure'; FailAt = 2; Persistent = $true; Pass = 'Exe'; Writes = 0; ExpectedOutcome = 'ACTION_REQUIRED'; Remaining = 'BETA' }
        @{ Name = 'final close failure'; FailAt = 6; Persistent = $true; Pass = 'Exe'; Writes = 2; ExpectedOutcome = 'PARTIAL_APPLIED'; Remaining = '' }
        @{ Name = 'dat-pass completion failure'; FailAt = 3; Persistent = $false; Pass = 'Dat'; Writes = 1; ExpectedOutcome = 'PARTIAL_APPLIED'; Remaining = '*' }
        @{ Name = 'fuzzy-pass completion failure'; FailAt = 3; Persistent = $false; Pass = 'Fuzzy'; Writes = 1; ExpectedOutcome = 'PARTIAL_APPLIED'; Remaining = '*' }
    ) {
        $fx = New-Fix8Fixture
        $script:fix8ExeFiles = @((Add-Fix8Game $fx 'ALPHA'), (Add-Fix8Game $fx 'BETA'))
        Mock Get-GameFiles { $script:fix8ExeFiles }
        $profileIndex = if ($Pass -eq 'Exe') { Build-ProfileIndex -gameProfilesDir $fx.Templates } else { @{} }
        $dat = @{}
        if ($Pass -eq 'Dat') {
            $dat[(Get-NormalizedGameKey 'ALPHA')] = [pscustomobject]@{ ProfileCode = 'ALPHA'; OriginalName = 'ALPHA'; Executable = 'alpha.exe' }
            $dat[(Get-NormalizedGameKey 'BETA')] = [pscustomobject]@{ ProfileCode = 'BETA'; OriginalName = 'BETA'; Executable = 'beta.exe' }
        }
        $profileSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($Pass -eq 'Fuzzy') { [void]$profileSet.Add('ALPHA'); [void]$profileSet.Add('BETA') }
        $script:fix8RealPublish = ${function:Publish-TpmRegistrationLedgerDocument}
        $script:fix8PublishCount = 0; $script:fix8FailAt = $FailAt; $script:fix8Persistent = $Persistent
        Mock Publish-TpmRegistrationLedgerDocument {
            $script:fix8PublishCount++
            if ($script:fix8PublishCount -eq $script:fix8FailAt -or ($script:fix8Persistent -and $script:fix8PublishCount -gt $script:fix8FailAt)) {
                return [pscustomobject]@{ Published = $false; Reason = 'injected FIX8 publication failure'; Bytes = 0 }
            }
            & $script:fix8RealPublish -Path $Path -Document $Document -MaximumBytes $MaximumBytes
        }
        $result = Register-Games -userProfilesDir $fx.Profiles -installFolder $fx.Games -profileIndex $profileIndex -gameProfilesDir $fx.Templates -datIndex $dat -profileSet $profileSet
        $result.Outcome | Should -Be $ExpectedOutcome
        $result.Succeeded | Should -BeFalse
        $result.Mutation.Completed | Should -BeFalse
        $result.ReasonCode | Should -Be 'REGISTRATION_EVIDENCE_PUBLICATION_FAILED'
        $result.LedgerEvidence.Status | Should -Be 'UNCERTAIN'
        $result.LedgerEvidence.Stopped | Should -BeTrue
        @($result.Warnings) -join ' ' | Should -Match 'could not be published'
        Get-TpmProgressCloseState -Result $result | Should -Be 'Error'
        @($result.Registered).Count | Should -Be $Writes
        $profiles = @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.xml' -File)
        $profiles.Count | Should -Be $Writes
        foreach ($profile in $profiles) {
            $expectedPath = Join-Path (Join-Path $fx.Games $profile.BaseName) ($profile.BaseName.ToLowerInvariant() + '.exe')
            ([xml](Get-Content -LiteralPath $profile.FullName -Raw)).GameProfile.GamePath | Should -Be $expectedPath
            @($result.Mutation.CompletedItems) | Should -Contain $profile.BaseName
            @($result.Mutation.FailedItems) | Should -Not -Contain $profile.BaseName
            @($result.Mutation.UnknownItems) | Should -Not -Contain $profile.BaseName
        }
        if ($Remaining) {
            $remainingFolder = if ($Remaining -eq '*') { @('ALPHA', 'BETA' | Where-Object { $_ -notin @($result.Registered | ForEach-Object Code) })[0] } else { $Remaining }
            $result.Mutation.UnattemptedItemCount | Should -Be 1
            @($result.Mutation.UnattemptedItems) | Should -Contain $remainingFolder
            Test-Path -LiteralPath (Join-Path $fx.Profiles ($remainingFolder + '.xml')) | Should -BeFalse
        } else { $result.Mutation.UnattemptedItemCount | Should -Be 0 }
        $rebuilt = ConvertTo-TpmRegistrationResult -Legacy $result.TechnicalDetails -Backup $result.Backup -DryRun $false
        $rebuilt.Outcome | Should -Be $ExpectedOutcome
        $rebuilt.Mutation.Completed | Should -BeFalse
        $op = @((Read-Fix8Ledger $fx).Operations)[0]
        if ($Persistent) {
            $op.State | Should -Be 'PENDING'
            if ($FailAt -eq 3) {
                @($op.Mappings | Where-Object State -eq 'WRITE_ATTEMPTED_UNVERIFIED').Count | Should -Be 1
            } elseif ($FailAt -eq 6) {
                @($op.Mappings | Where-Object State -eq 'VERIFIED').Count | Should -Be 2
                @($op.Mappings | Where-Object State -eq 'WRITE_ATTEMPTED_UNVERIFIED').Count | Should -Be 0
            }
        } else {
            $op.Transaction.Outcome | Should -Be 'PARTIAL_APPLIED'
            $op.EvidenceStatus | Should -Be 'UNCERTAIN'
            @($op.Mappings | Where-Object State -eq 'VERIFIED').Count | Should -Be 1
            $stoppedUnit = @($op.Units | Where-Object Folder -eq $remainingFolder)[0]
            $stoppedUnit.State | Should -Be 'SKIPPED'
            $stoppedUnit.Reason | Should -Be 'STOPPED_AFTER_EVIDENCE_PUBLICATION_FAILURE'
        }
    }
}

Describe 'FIX8 same-name source attribution' {
    AfterEach { Reset-Fix8State }
    It 'keeps main and supplementary outcomes on their own immutable units' {
        $fx = New-Fix8Fixture
        $main = Join-Path $fx.Root 'Main'; $supplementary = Join-Path $fx.Root 'Supplementary'
        New-Item -ItemType Directory -Path $main, $supplementary -Force | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $main 'Shared.zip'), [byte[]](1, 2, 3))
        [IO.File]::WriteAllBytes((Join-Path $supplementary 'Shared.zip'), [byte[]](4, 5, 6))
        $script:fix8ResolvedFolder = $null
        # FIX41: a ZIP with no folder at all is now extracted into a new folder. Keep the main pass on a
        # refused root: an existing non-empty 'Shared' folder that the resolver did not confirm.
        [void][IO.Directory]::CreateDirectory((Join-Path $fx.Games 'Shared'))
        [IO.File]::WriteAllBytes((Join-Path $fx.Games 'Shared\user-file.bin'), [byte[]](7, 8, 9))
        Mock Resolve-ExtractedGameFolder { $script:fix8ResolvedFolder }
        Mock Invoke-TpmAutoSyncDirectoryTransaction { throw 'refused roots must not mutate' }
        [void](Invoke-AutoSync -zipSource $main -installFolder $fx.Games -syncStatePath (Join-Path $fx.Root 'main.json') -datIndex @{})
        $first = @((Read-Fix8Ledger $fx).Operations)[0]
        $firstId = [string]$first.OperationId
        $firstUnitJson = @($first.Units)[0] | ConvertTo-Json -Compress
        $script:fix8ResolvedFolder = Join-Path $fx.Games 'Nested\Shared'
        [void][IO.Directory]::CreateDirectory($script:fix8ResolvedFolder)
        [void](Invoke-AutoSync -zipSource $supplementary -installFolder $fx.Games -syncStatePath (Join-Path $fx.Root 'supp.json') -datIndex @{})
        $ops = @((Read-Fix8Ledger $fx).Operations)
        $ops.Count | Should -Be 2
        $mainOp = @($ops | Where-Object OperationId -eq $firstId)[0]
        $suppOp = @($ops | Where-Object OperationId -ne $firstId)[0]
        (@($mainOp.Units)[0] | ConvertTo-Json -Compress) | Should -Be $firstUnitJson
        @($mainOp.Units)[0].Reason | Should -Be 'UNPROVEN_EXTRACTION_ROOT'
        @($suppOp.Units)[0].Folder | Should -Be 'Shared'
        @($suppOp.Units)[0].State | Should -Be 'SKIPPED'
        @($suppOp.Units)[0].Reason | Should -Be 'NESTED_TARGET_REFUSED'
        Should -Invoke Invoke-TpmAutoSyncDirectoryTransaction -Times 0
        $before = (Get-FileHash -LiteralPath $fx.Ledger -Algorithm SHA256).Hash
        Update-TpmRegistrationLedgerUnit -OperationId 'not-active' -SourceName 'Shared' -State VERIFIED -Publish | Should -BeFalse
        (Get-FileHash -LiteralPath $fx.Ledger -Algorithm SHA256).Hash | Should -Be $before
    }
}

Describe 'FIX8 bounded history growth' {
    AfterEach { Reset-Fix8State }
    # Mutation: remove the pruning of the oldest COMPLETED runs from Publish-TpmRegistrationLedgerDocument -> run 4 or so is refused, and AutoSync and Register stop for good.
    It 'drops the oldest finished runs and keeps publishing when repeated full-library history reaches the cap' {
        $fx = New-Fix8Fixture
        $document = New-TpmRegistrationLedgerDocument
        $dropped = $false
        for ($run = 1; $run -le 12; $run++) {
            $units = @(1..1000 | ForEach-Object {
                [pscustomobject][ordered]@{
                    UnitId = ('U{0:D4}' -f $_); Folder = ('Synthetic Game {0:D4} forty-character-name' -f $_)
                    State = $(if ($run -eq 1) { 'VERIFIED' } else { 'SKIPPED' })
                    Reason = $(if ($run -eq 1) { 'Saved profile read back' } else { 'UP_TO_DATE_NOT_REGISTERED_THIS_RUN' })
                    Extraction = 'NO_OP'; Rollback = 'NOT_ATTEMPTED'
                }
            })
            $mappings = @()
            if ($run -eq 1) {
                $mappings = @(1..1000 | ForEach-Object {
                    [pscustomobject][ordered]@{
                        MappingId = ('mapping{0:D5}' -f $_); UnitId = ('U{0:D4}' -f $_); Code = ('GAME{0:D4}' -f $_)
                        Template = ('GAME{0:D4}.xml' -f $_); Match = 'exe-single'; PathBase = 'InstallRoot'
                        IntendedPath = ($units[$_ - 1].Folder + '\game.exe'); State = 'VERIFIED'
                        Reason = 'Saved profile GamePath and executable were read back and matched the intended mapping.'
                        Readback = $true; AttemptUtc = '20261031T000000.000Z'
                    }
                })
            }
            $operation = [pscustomobject][ordered]@{
                OperationId = ('operation{0:D4}' -f $run); RunId = ('run{0:D4}' -f $run); Mode = 'AutoSync'
                State = 'COMPLETED'; EvidenceStatus = 'CURRENT'; StartedUtc = '20261031T000000.000Z'; CompletedUtc = '20261031T000001.000Z'
                Source = [pscustomobject]@{ ManagerVersion = 'v1.0 RC8'; ScriptSha256 = ('A' * 64) }
                InstallRoot = $fx.Games; Units = $units; Mappings = $mappings; Transaction = $null
            }
            $document.Operations = @($document.Operations) + $operation
            $publication = Publish-TpmRegistrationLedgerDocument -Path $fx.Ledger -Document $document
            $publication.Published | Should -BeTrue
            (Get-Item -LiteralPath $fx.Ledger).Length | Should -BeLessOrEqual 1048576
            $retained = Read-Fix8Ledger $fx
            @($retained.Operations | ForEach-Object { [string]$_.OperationId }) | Should -Contain ('operation{0:D4}' -f $run)
            if (@($retained.Operations).Count -lt $run) { $dropped = $true }
            foreach ($prior in @($retained.Operations)) {
                @($prior.Units).Count | Should -Be 1000
            }
        }
        $dropped | Should -BeTrue
        # The loss is visible in the file: every dropped run is counted.
        $final = Read-Fix8Ledger $fx
        [int64]$final.TrimmedOperations | Should -Be (12 - @($final.Operations).Count)
    }
}

Describe 'FIX8 support identity privacy' {
    AfterEach { Reset-Fix8State }
    It 'exports only the script leaf for <PathKind> without losing artifact identity' -ForEach @(
        @{ PathKind = 'non-user drive'; StartupPath = 'D:\Arcade\Private\TeknoParrot-Manager.ps1' }
        @{ PathKind = 'user drive'; StartupPath = 'C:\Users\Example\Private\TeknoParrot-Manager.ps1' }
        @{ PathKind = 'UNC'; StartupPath = '\\example-server\private\TeknoParrot-Manager.ps1' }
    ) {
        $fx = New-Fix8Fixture
        $identity = Get-TpmRuntimeArtifactIdentity -ScriptPath ''
        $identity.ScriptPath = $StartupPath; $identity.ScriptSha256 = ('B' * 64); $identity.ScriptLength = 123
        # New-TpmSupportPackage only writes into <ScriptRoot>\SupportPackages and refuses any other destination.
        $package = New-TpmSupportPackage -ScriptRoot $fx.Scripts -OutputRoot (Join-Path $fx.Scripts 'SupportPackages') -UserProfilesDir $fx.Profiles -ApprovedGamesRoot $fx.Games -RuntimeIdentity $identity
        $package.PackagePath | Should -Not -BeNullOrEmpty -Because ('the support package must be created: ' + (@($package.Errors) -join '; '))
        $zip = [System.IO.Compression.ZipFile]::OpenRead($package.PackagePath)
        try {
            $entry = @($zip.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq 'metadata/runtime-identity.json' })[0]
            $reader = New-Object IO.StreamReader($entry.Open())
            try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $projection = $json | ConvertFrom-Json
            $projection.ScriptStartupPath | Should -Be 'TeknoParrot-Manager.ps1'
            $projection.ScriptSha256 | Should -Be $identity.ScriptSha256
            $projection.ScriptLength | Should -Be 123
            $json | Should -Not -Match ([regex]::Escape($StartupPath))
            $json | Should -Not -Match 'Private|example-server|Example'
        } finally { $zip.Dispose() }
        (Get-TpmSupportIdentityProjection -Identity (Get-TpmRuntimeArtifactIdentity -ScriptPath '')).ScriptStartupPath | Should -Be 'unavailable'
    }
}
