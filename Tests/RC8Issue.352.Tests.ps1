#Requires -Module Pester
# Issue: https://github.com/Jumpstile/teknoparrot-manager/issues/352
# Audit: ISSUES-AUDIT-RESULT.md, issue #352 (2026-11-01).
# Completed extraction manifests are TestDrive fixtures, not proof of registration.
BeforeAll {
    $tokens = $null; $errors = $null
    $script:issue352Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $wanted = @(
        'Register-Games', 'Get-TpmProfileWriteFingerprint', 'Resolve-TpmRegistrationSaveFailure', 'Open-TpmRegistrationLedgerOperation',
        'Update-TpmRegistrationLedgerUnit', 'Read-TpmRegistrationLedger',
        'Get-TpmSupportLedgerProjection'
    )
    # Include the real transitive helpers of these roots, but not the production
    # host renderer, logging, identity or discovery boundaries. No top-level code.
    $boundaries = @('Write-Host', 'Write-Log', 'Write-TpmCompactExtractionProgress',
        'Get-GameFiles', 'Get-TpmRegisteredProfileFilesWithDiscoveryProgress',
        'Get-TpmDirectoryEntriesWithDiscoveryProgress', 'Get-ManagerDisplayVersion',
        'Get-TpmSessionRunId')
    $definitions = @{}
    foreach ($definition in @($script:issue352Ast.FindAll({
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
    $functionPath = Join-Path $TestDrive 'issue352-functions.ps1'
    ($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" |
        Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath
    function Write-Log { param($Message) }
    function Write-TpmCompactExtractionProgress {
        param($Phase, $Label, $Current, $Total, $StartedAt, [switch]$Complete, $Outcome)
    }
    function Get-ManagerDisplayVersion { return 'RC8 issue352 fixture' }
    function Get-TpmSessionRunId { return $script:issue352RunId }
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
    function Add-Issue352Game {
        param([string]$Folder, [string]$Code, [string]$ExeName = 'game.exe', [switch]$NoTemplate)
        $directory = Join-Path $script:issue352Games $Folder
        [void][IO.Directory]::CreateDirectory($directory)
        $exe = Join-Path $directory $ExeName
        [IO.File]::WriteAllText($exe, 'fixture executable')
        $template = Join-Path $script:issue352Templates ($Code + '.xml')
        if (-not $NoTemplate) {
            [IO.File]::WriteAllText($template,
                ('<GameProfile><ExecutableName>{0}</ExecutableName><ConfigValues /></GameProfile>' -f $ExeName))
        }
        return [pscustomobject]@{ Code = $Code; TemplatePath = $template; Exe = $exe; Folder = $Folder }
    }
    function Open-Issue352SelectedManifest {
        param([string[]]$Folders, [switch]$NotExtracted)
        $opened = Open-TpmRegistrationLedgerOperation -Mode AutoSync -InstallRoot $script:issue352Games `
            -Units @($Folders | ForEach-Object { [pscustomobject]@{ Folder = $_ } })
        if (-not $opened.Opened) { throw $opened.Message }
        if (-not $NotExtracted) {
            foreach ($folder in $Folders) {
                $updated = Update-TpmRegistrationLedgerUnit -OperationId $opened.OperationId `
                    -SourceName $folder -Extraction SUCCEEDED -TargetFolder $folder -Publish
                if (-not $updated) { throw "Could not publish fixture extraction for $folder" }
            }
        }
    }
    function Read-Issue352Evidence {
        # Lose process-local context, retaining only on-disk evidence as on restart.
        $script:TpmRegistrationLedger = $null
        $read = Read-TpmRegistrationLedger -Path $script:issue352Ledger
        if ($read.Status -ne 'Ok') { throw $read.Message }
        return (Get-TpmSupportLedgerProjection -Read $read -RunId 'later-session' -UserProfilesDir $script:issue352Profiles)
    }
}

Describe 'RC8 issue #352: selected new-game extractions reconcile to saved profiles and durable failures' -Tag 'RC8-Issue' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:issue352Games = Join-Path $root 'Games'
        $script:issue352Profiles = Join-Path $root 'UserProfiles'
        $script:issue352Templates = Join-Path $root 'GameProfiles'
        $state = Join-Path $root 'State'
        foreach ($directory in @($script:issue352Games, $script:issue352Profiles, $script:issue352Templates, $state)) {
            [void][IO.Directory]::CreateDirectory($directory)
        }
        $script:issue352Ledger = Join-Path $state 'TPM-RegistrationLedger.json'
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $state }
        $script:TpmRegistrationLedger = $null; $script:TpmRegistrationLedgerStopLatch = $null
        $script:TpmStartupIdentity = $null; $script:issue352RunId = 'selected-new-game-session'
        $script:RawThrillsPathLimits = @{}; $script:FuzzyAutoThreshold = 0.72; $script:FuzzyTieMargin = 0.1
        $script:TitleTokenStopWords = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    }
    AfterEach {
        $script:TpmRegistrationLedger = $null; $script:TpmRegistrationLedgerStopLatch = $null
        $script:TpmOwnedLayout = $null; $script:TpmStartupIdentity = $null
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: new WLP and another new game have saved mappings and matching restart/support evidence' {
        $wlp = Add-Issue352Game -Folder 'WorldsLargestPacMan' -Code WLP -ExeName wlp.exe
        $other = Add-Issue352Game -Folder 'AnotherNewGame' -Code ALPHA -ExeName alpha.exe
        Open-Issue352SelectedManifest @($wlp.Folder, $other.Folder)
        $result = Register-Games -userProfilesDir $script:issue352Profiles -installFolder $script:issue352Games `
            -profileIndex @{ 'wlp.exe' = @($wlp); 'alpha.exe' = @($other) } `
            -gameProfilesDir $script:issue352Templates -GameFolders @($wlp.Folder, $other.Folder)
        $result.Outcome | Should -Be 'SUCCEEDED'
        @($result.Mutation.CompletedItems | Sort-Object) -join ',' | Should -Be 'ALPHA,WLP'
        foreach ($game in @($wlp, $other)) {
            $profile = Read-Xml (Join-Path $script:issue352Profiles ($game.Code + '.xml'))
            [string]$profile.GameProfile.GamePath | Should -Be $game.Exe
        }
        $evidence = Read-Issue352Evidence
        $operation = @($evidence.Ledger.Operations)[0]
        @($operation.Units | Where-Object State -ne VERIFIED).Count | Should -Be 0
        foreach ($game in @($wlp, $other)) {
            $mapping = @($operation.Mappings | Where-Object Code -eq $game.Code)
            $mapping.Count | Should -Be 1
            $mapping[0].State | Should -Be 'VERIFIED'
            $mapping[0].SavedProfileCheck | Should -Be 'MATCHES_INTENT'
        }
        @($evidence.Transactions.Operations)[0].Transaction.Outcome | Should -Be $result.Outcome
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: two new directories sharing one executable/profile retain the second as a durable duplicate warning' {
        $first = Add-Issue352Game -Folder 'RevisionA' -Code SHARED
        $second = Add-Issue352Game -Folder 'RevisionB' -Code SHARED
        Open-Issue352SelectedManifest @($first.Folder, $second.Folder)
        $result = Register-Games -userProfilesDir $script:issue352Profiles -installFolder $script:issue352Games `
            -profileIndex @{ 'game.exe' = @($first) } -gameProfilesDir $script:issue352Templates `
            -GameFolders @($first.Folder, $second.Folder)
        $result.Outcome | Should -Be 'PARTIAL_APPLIED'
        $result.Succeeded | Should -BeFalse
        @($result.Ambiguous | Where-Object { $_.Reason -eq 'duplicate' -and $_.Exe -eq $second.Exe }).Count | Should -Be 1
        [string](Read-Xml (Join-Path $script:issue352Profiles 'SHARED.xml')).GameProfile.GamePath | Should -Be $first.Exe
        $operation = @( (Read-Issue352Evidence).Ledger.Operations )[0]
        $duplicate = @($operation.Units | Where-Object Folder -eq $second.Folder)[0]
        $duplicate.State | Should -Be 'SKIPPED'
        @($operation.Mappings | Where-Object { $_.UnitId -eq $duplicate.UnitId })[0].Reason | Should -Match 'DUPLICATE_PROFILE_CLAIM'
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: missing GameProfiles templates remain explicit failures instead of Registered=0/Unmatched=0 all-clear' {
        $game = Add-Issue352Game -Folder 'MissingTemplate' -Code MISSING -NoTemplate
        Open-Issue352SelectedManifest @($game.Folder)
        $result = Register-Games -userProfilesDir $script:issue352Profiles -installFolder $script:issue352Games `
            -profileIndex @{ 'game.exe' = @($game) } -gameProfilesDir $script:issue352Templates -GameFolders @($game.Folder)
        $result.Succeeded | Should -BeFalse
        @($result.Mutation.FailedItems) | Should -Contain MISSING
        Test-Path -LiteralPath (Join-Path $script:issue352Profiles 'MISSING.xml') | Should -BeFalse
        $operation = @((Read-Issue352Evidence).Ledger.Operations)[0]
        @($operation.Units)[0].State | Should -Be 'FAILED_BEFORE_WRITE'
        @($operation.Mappings)[0].Reason | Should -Not -BeNullOrEmpty
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: mixed A success/B Save failure reports PARTIAL_APPLIED, preserves A, and includes B and reason' {
        $first = Add-Issue352Game -Folder A -Code ALPHA -ExeName alpha.exe
        $second = Add-Issue352Game -Folder B -Code BETA -ExeName beta.exe
        $script:issue352RealSave = ${function:Save-Xml}
        Mock Save-Xml {
            if ([IO.Path]::GetFileName($path) -eq 'BETA.xml') { throw 'injected B save failure' }
            & $script:issue352RealSave -doc $doc -path $path
        }
        Open-Issue352SelectedManifest @('A', 'B')
        $result = Register-Games -userProfilesDir $script:issue352Profiles -installFolder $script:issue352Games `
            -profileIndex @{ 'alpha.exe' = @($first); 'beta.exe' = @($second) } `
            -gameProfilesDir $script:issue352Templates -GameFolders @('A', 'B')
        # The issue explicitly requires PARTIAL_APPLIED. Do not weaken this to
        # ACTION_REQUIRED merely because current code treats every Save throw as unknown.
        $result.Outcome | Should -Be 'PARTIAL_APPLIED'
        $result.Succeeded | Should -BeFalse
        @($result.Mutation.CompletedItems) | Should -Contain ALPHA
        @($result.Mutation.FailedItems) + @($result.Mutation.UnknownItems) | Should -Contain BETA
        [string](Read-Xml (Join-Path $script:issue352Profiles 'ALPHA.xml')).GameProfile.GamePath | Should -Be $first.Exe
        Test-Path -LiteralPath (Join-Path $script:issue352Profiles 'BETA.xml') | Should -BeFalse
        $operation = @((Read-Issue352Evidence).Ledger.Operations)[0]
        $failed = @($operation.Mappings | Where-Object Code -eq BETA)[0]
        $failed.State | Should -Not -Be VERIFIED
        $failed.Reason | Should -Match 'injected B save failure'
        @((Read-Issue352Evidence).Transactions.Operations)[0].Transaction.Outcome | Should -Be $result.Outcome
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: all-failed writes retain failures rather than full success' {
        $game = Add-Issue352Game -Folder B -Code BETA
        Mock Save-Xml { throw 'injected all-failed save' }
        Open-Issue352SelectedManifest @('B')
        $result = Register-Games -userProfilesDir $script:issue352Profiles -installFolder $script:issue352Games `
            -profileIndex @{ 'game.exe' = @($game) } -gameProfilesDir $script:issue352Templates -GameFolders @('B')
        $result.Succeeded | Should -BeFalse
        @($result.Registered).Count | Should -Be 0
        @($result.Mutation.FailedItems) + @($result.Mutation.UnknownItems) | Should -Contain BETA
        Test-Path -LiteralPath (Join-Path $script:issue352Profiles 'BETA.xml') | Should -BeFalse
        $operation = @((Read-Issue352Evidence).Ledger.Operations)[0]
        @($operation.Mappings)[0].Reason | Should -Match 'injected all-failed save'
        @($operation.Units)[0].State | Should -Not -Be VERIFIED
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: all-skipped candidates retain a per-folder reason after restart' {
        $game = Add-Issue352Game -Folder Unmatched -Code UNUSED
        Open-Issue352SelectedManifest @($game.Folder)
        $result = Register-Games -userProfilesDir $script:issue352Profiles -installFolder $script:issue352Games `
            -profileIndex @{} -gameProfilesDir $script:issue352Templates -GameFolders @($game.Folder)
        $result.Outcome | Should -Be 'ACTION_REQUIRED'
        @($result.Mutation.SkippedItems) | Should -Contain Unmatched
        $operation = @((Read-Issue352Evidence).Ledger.Operations)[0]
        @($operation.Units)[0].State | Should -Be SKIPPED
        @($operation.Units)[0].Reason | Should -Be 'NO_PROFILE_MATCH'
        @($operation.Mappings).Count | Should -Be 0
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: secondary-only repair is a verified change and repeat existing-only registration is NO_OP' {
        $game = Add-Issue352Game -Folder A -Code ALPHA
        $secondary = Join-Path (Split-Path $game.Exe -Parent) 'second.exe'
        [IO.File]::WriteAllText($secondary, 'secondary executable')
        $profilePath = Join-Path $script:issue352Profiles 'ALPHA.xml'
        $doc = [xml]('<GameProfile><GamePath /><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>second.exe</ExecutableName2></GameProfile>')
        $doc.GameProfile.GamePath = [string]$game.Exe
        $doc.Save($profilePath)
        $parameters = @{ userProfilesDir = $script:issue352Profiles; installFolder = $script:issue352Games
            profileIndex = @{ 'game.exe' = @($game) }; gameProfilesDir = $script:issue352Templates }
        $changed = Register-Games @parameters
        $changed.Outcome | Should -Be SUCCEEDED
        $changed.ProductState | Should -Be INTENDED
        $changed.Mutation.Started | Should -BeTrue
        @($changed.Mutation.ChangedItems) | Should -Contain ALPHA
        [string](Read-Xml $profilePath).GameProfile.GamePath2 | Should -Be $secondary
        $beforeRepeat = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
        $repeat = Register-Games @parameters
        $repeat.Outcome | Should -Be NO_OP
        $repeat.Mutation.Started | Should -BeFalse
        (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash | Should -Be $beforeRepeat
    }

    It 'choose option 1, and then go through all steps to extract all files, and then open TP to look for games to be added: empty SyncedNames cannot fall back to an existing-only scan (structural)' {
        $assignments = @($script:issue352Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $args[0].Left.Extent.Text -eq '$skipAutoSyncRegistration'
        }, $true))
        $assignments.Count | Should -Be 1
        $conditionVariables = @($assignments[0].Right.FindAll({
            $args[0] -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true) | ForEach-Object { $_.VariablePath.UserPath })
        $conditionVariables | Should -Contain mode
        $conditionVariables | Should -Contain registrationFolders
        $assignments[0].Right.Extent.Text | Should -Match "-eq\s+'AutoSync'"
        $assignments[0].Right.Extent.Text | Should -Match '\.Count\s+-eq\s+0'
        $guard = @($script:issue352Ast.FindAll({
            $args[0] -is [System.Management.Automation.Language.IfStatementAst] -and
            $args[0].Clauses[0].Item1.Extent.Text -eq '$skipAutoSyncRegistration' -and
            $args[0].Clauses[0].Item2.Extent.Text -match 'NEW_REGISTRATION_TARGETS_UNVERIFIED'
        }, $true))
        $guard.Count | Should -Be 1
        $refusalCalls = @($guard[0].Clauses[0].Item2.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].GetCommandName() -eq 'Register-Games'
        }, $true))
        $refusalCalls.Count | Should -Be 0
        $registrationCalls = @($guard[0].ElseClause.FindAll({
            $args[0] -is [System.Management.Automation.Language.CommandAst] -and
            $args[0].GetCommandName() -eq 'Register-Games'
        }, $true))
        $registrationCalls.Count | Should -Be 1
        @($registrationCalls[0].CommandElements | Where-Object {
            $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'GameFolders'
        }).Count | Should -Be 1
    }
}
