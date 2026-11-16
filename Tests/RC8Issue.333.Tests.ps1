#Requires -Module Pester
# Issues: https://github.com/Jumpstile/teknoparrot-manager/issues/333
# https://github.com/Jumpstile/teknoparrot-manager/issues/334
# https://github.com/Jumpstile/teknoparrot-manager/issues/342
# Audit: <audit-folder>/ISSUES-AUDIT-RESULT.md
# Real XML, pool discovery, backup, persistence, transaction and report helpers.
# Only console/progress/log output is intercepted. No product import or launch.
BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $script:rcControlsAst = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Production parse failed: $($errors -join '; ')" }
    $wanted = @(
        'Invoke-ControlPropagation', 'Invoke-ControlPropagationLegacy', 'Build-ArchetypePool',
        'Test-ButtonIsBound', 'Get-ButtonNodes', 'Get-ButtonKey', 'Test-ButtonNameDirectional',
        'Get-ProfileFamily', 'Get-ProfileInputApi', 'Set-ProfileInputApi', 'Get-ProfileDevices',
        'Get-LongestCommonPrefix', 'Get-ConfigFieldMap', 'Set-ConfigField', 'ConvertTo-XPathStringLiteral',
        'Read-Xml', 'Save-Xml', 'Save-XmlMaybe', 'Get-TpmProfileWriteFingerprint', 'Resolve-TpmRegistrationSaveFailure', 'Write-ControlPropagationResults',
        'Get-TpmRegisteredProfileFilesWithDiscoveryProgress', 'Get-TpmDirectoryEntriesWithDiscoveryProgress',
        'New-TpmVerifiedUserProfilesBackup', 'Get-TpmUserProfilesBackupManifest',
        'Get-TpmUserProfilesBackupMarkerName', 'Get-TpmUserProfilesBackupStagingPrefix',
        'Get-TpmUserProfilesBackupStagingPath', 'Get-TpmUserProfilesBackupInventory',
        'Get-TpmUserProfilesBackupInventoryKeys', 'Complete-TpmUserProfilesBackupFolder', 'Move-TpmDirectoryWithRetry',
        'Test-TpmNoReparsePath', 'Assert-TpmNoReparseWriteTarget',
        'ConvertTo-TpmLegacyTransactionResult', 'New-TpmProfileTransactionResult', 'New-TpmTransactionResult',
        'Get-TpmTransactionOutcomeNames', 'Get-TpmTransactionProductStateNames', 'Get-TpmTransactionField',
        'Get-TpmTransactionItemKey', 'Get-TpmTransactionItemKeys', 'Test-TpmTransactionUserSafeSummary',
        'Assert-TpmTransactionItemSets', 'Assert-TpmTransactionResult',
        'New-TpmActionRequiredReportText', 'Get-TpmActionRequiredPlainLines', 'Write-TpmActionRequiredReport', 'Write-TpmAtomicTextFile', 'Invoke-TpmAtomicFileReplace',
        'Write-TpmText', 'Split-TextForMenuWidth', 'Get-TpmResetRestoreLineWidth', 'Write-TpmLabelValue', 'Show-TpmDetailBlocks', 'Write-TpmDetailBlocksLog', 'Write-TpmOutcome', 'Test-TpmInteractiveInput',
        'Format-TpmCountNoun', 'Format-TpmGameCount', 'Format-TpmNameList', 'Join-TpmPostgresSetupNames',
        'Get-TpmControlPropagationSummary', 'Get-TpmControlPropagationReportLine', 'Get-TpmProgressCloseState', 'Get-TpmKeptSaveCopyPath'
    )
    $functions = @($script:rcControlsAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object { $wanted -contains $_.Name })
    foreach ($name in $wanted) {
        if (@($functions | Where-Object Name -eq $name).Count -ne 1) { throw "Expected one production function: $name" }
    }
    $functionPath = Join-Path $TestDrive 'rc8-controls-functions.ps1'
    [System.IO.File]::WriteAllText($functionPath, (($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"))
    . $functionPath
    # Use production's real whitelist rather than inventing copied settings.
    $configAssignment = @($script:rcControlsAst.EndBlock.Statements | Where-Object {
        $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$InputConfigFields'
    })
    if ($configAssignment.Count -ne 1) { throw 'Expected production InputConfigFields assignment.' }
    . ([scriptblock]::Create($configAssignment[0].Extent.Text))
    function Write-Log { param([string]$Message) }
    # The result screen asks "[D] Details" through this helper; a test that presses D mocks it.
    function Read-HostSafe { param([string]$Prompt) return '' }
    function Write-TpmCompactExtractionProgress {
        param([string]$Phase, [string]$Label, [long]$Current, [long]$Total,
              [datetime]$StartedAt = (Get-Date), [switch]$Complete, [switch]$Completed,
              [string]$Outcome = 'Final')
    }
    function New-RcControlsDirectory {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($path)
        return $path
    }
    function New-RcControlsProfile {
        param([string]$Root, [string]$Code, [string]$Api = 'DirectInput',
              [string]$Name = 'P1 Up', [bool]$Bound = $false,
              [string]$Analog = 'None', [string]$Relative = 'False')
        $binding = if ($Bound) { '<DirectInputButton><DevicePath>FixturePad</DevicePath><BindName>FixturePad Up</BindName><Button>1</Button></DirectInputButton>' } else { '' }
        $xml = '<GameProfile><GamePath>fixture.exe</GamePath><ConfigValues><FieldInformation><FieldName>Input API</FieldName><FieldValue>' + $Api + '</FieldValue><FieldOptions><string>DirectInput</string><string>MergedInput</string></FieldOptions></FieldInformation><FieldInformation><FieldName>Use Relative Input</FieldName><FieldValue>' + $Relative + '</FieldValue></FieldInformation></ConfigValues><JoystickButtons><JoystickButtons><ButtonName>' + $Name + '</ButtonName><InputMapping>P1ButtonUp</InputMapping><AnalogType>' + $Analog + '</AnalogType>' + $binding + '</JoystickButtons></JoystickButtons></GameProfile>'
        $path = Join-Path $Root ($Code + '.xml')
        [System.IO.File]::WriteAllText($path, $xml)
        return $path
    }
    function Get-RcControlsHash { param([string]$Path) return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
}

Describe 'RC8 issue #333: canonical correction honors excluded pool members' -Tag 'RC8-Issue' {
    It 'Preconditions: excluded profile is itself a pool/reference member, canonicalArchetype names a different same-family reference, differing valid Input API.' {
        $root = New-RcControlsDirectory
        $excluded = New-RcControlsProfile -Root $root -Code Excluded -Bound $true
        $canonical = New-RcControlsProfile -Root $root -Code Canonical -Api MergedInput -Bound $true
        $ordinary = New-RcControlsProfile -Root $root -Code Ordinary -Name 'P1 Left Punch'
        $before = Get-RcControlsHash $excluded
        $ordinaryBefore = Get-RcControlsHash $ordinary
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        $pool.Count | Should -Be 2
        $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1 -noPropagate @('Excluded', 'Ordinary') -canonicalArchetype @{ button = 'Canonical' }
        (Get-RcControlsHash $excluded) | Should -BeExactly $before
        (Get-RcControlsHash $ordinary) | Should -BeExactly $ordinaryBefore
        (Get-ProfileInputApi (Read-Xml $excluded)) | Should -BeExactly 'DirectInput'
        ($pool | Where-Object Code -eq Excluded).InputApi | Should -BeExactly 'DirectInput'
        $result.Outcome | Should -BeExactly 'NO_OP'
        $result.Mutation.Started | Should -BeFalse
        @($result.Mutation.ChangedItems).Count | Should -Be 0
        $result.Backup.Attempted | Should -BeFalse
    }
    It 'Regression: excluded pool member plus canonical override retains bytes/API/pool state; ordinary excluded target; nonexcluded canonical correction; dry-run.' {
        foreach ($preview in @($false, $true)) {
            $root = New-RcControlsDirectory
            $path = New-RcControlsProfile -Root $root -Code Reference -Bound $true
            $null = New-RcControlsProfile -Root $root -Code Canonical -Api MergedInput -Bound $true
            $before = Get-RcControlsHash $path
            $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
            $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1 -canonicalArchetype @{ button = 'Canonical' } -DryRun $preview
            if ($preview) {
                (Get-RcControlsHash $path) | Should -BeExactly $before
                $result.Outcome | Should -BeExactly 'NO_OP'
                $result.Mutation.Started | Should -BeFalse
                $result.Backup.Attempted | Should -BeFalse
            } else {
                (Get-RcControlsHash $path) | Should -Not -Be $before
                (Get-ProfileInputApi (Read-Xml $path)) | Should -BeExactly 'MergedInput'
                ($pool | Where-Object Code -eq Reference).InputApi | Should -BeExactly 'MergedInput'
                $result.Outcome | Should -BeExactly 'SUCCEEDED'
                $result.Mutation.ChangedItems | Should -Contain Reference
                $result.Backup.Verified | Should -BeTrue
                (Get-RcControlsHash (Join-Path $result.Backup.RootPath 'Reference.xml')) | Should -BeExactly $before
            }
        }
    }
}

Describe 'RC8 issue #334: settings-only persistence is a transaction mutation' -Tag 'RC8-Issue' {
    BeforeEach {
        $script:rcControlsHost = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { param($Object) [void]$script:rcControlsHost.Add([string]$Object) }
    }
    It 'Preconditions: unbound target with matching mapping key but directional/action mismatch, source has different valid API or carried setting.' -TestCases @(
        @{ Mode = 'API'; SourceApi = 'MergedInput'; SourceRelative = 'False' },
        @{ Mode = 'config'; SourceApi = 'DirectInput'; SourceRelative = 'True' }
    ) {
        param($Mode, $SourceApi, $SourceRelative)
        $root = New-RcControlsDirectory
        $null = New-RcControlsProfile -Root $root -Code Reference -Api $SourceApi -Relative $SourceRelative -Bound $true
        $path = New-RcControlsProfile -Root $root -Code Target -Name 'P1 Left Punch'
        $before = Get-RcControlsHash $path
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1
        (Get-RcControlsHash $path) | Should -Not -Be $before
        $doc = Read-Xml $path
        (Get-ProfileInputApi $doc) | Should -BeExactly $SourceApi
        (Get-ConfigFieldMap $doc @('Use Relative Input'))['Use Relative Input'] | Should -BeExactly $SourceRelative
        @(Get-ButtonNodes $doc | Where-Object { Test-ButtonIsBound $_ }).Count | Should -Be 0
        ($result.Reports | Where-Object Code -eq Target).Status | Should -BeExactly 'settings-only'
        ($result.Reports | Where-Object Code -eq Target).Bound | Should -Be 0
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.ProductState | Should -BeExactly 'INTENDED'
        $result.Mutation.Started | Should -BeTrue
        $result.Mutation.MutatedItemCount | Should -Be 1
        $result.Mutation.ChangedItems | Should -Contain Target
        $result.Mutation.AffectedItems | Should -Contain Target
        $result.Mutation.CompletedItems | Should -Contain Target
        $result.Backup.Verified | Should -BeTrue
        (Get-RcControlsHash (Join-Path $result.Backup.RootPath 'Target.xml')) | Should -BeExactly $before
        # The screen is short now; the counts are the old facts behind D. Press D, then read what was shown.
        Mock Test-TpmInteractiveInput { return $true }
        Mock Read-HostSafe { return 'D' }
        $display = Write-ControlPropagationResults -Reports $result.Reports
        $display.ControlsCopiedCount | Should -Be 0
        $display.SettingsOnlyCount | Should -Be 1
        $display.VerifiedPhysicalBindingsCount | Should -Be 0
        (($script:rcControlsHost -join ' ') -replace '\s+', ' ') | Should -Match 'Settings carried only: 1'
    }
    It 'Regression: API-only/config-only with all bindings skipped; identical settings no-op; mixed items; save failure; exact file readback agrees with result and displayed counts.' {
        $root = New-RcControlsDirectory
        $null = New-RcControlsProfile -Root $root -Code Reference -Bound $true
        $path = New-RcControlsProfile -Root $root -Code Target -Name 'P1 Left Punch'
        $before = Get-RcControlsHash $path
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1
        (Get-RcControlsHash $path) | Should -BeExactly $before
        $result.Outcome | Should -BeExactly 'NO_OP'
        $result.Mutation.Started | Should -BeFalse
        $result.Backup.Attempted | Should -BeFalse
        ($result.Reports | Where-Object Code -eq Target).Status | Should -BeExactly 'skipped-unchanged'
        $display = Write-ControlPropagationResults -Reports $result.Reports -Unattended
        $display.SettingsOnlyCount | Should -Be 0
        $display.ControlsCopiedCount | Should -Be 0
    }
    It 'settings-only successful write remains counted when another selected profile save fails' {
        $root = New-RcControlsDirectory
        $null = New-RcControlsProfile -Root $root -Code Reference -Api MergedInput -Bound $true
        $ok = New-RcControlsProfile -Root $root -Code ASettings -Name 'P1 Left Punch'
        $bad = New-RcControlsProfile -Root $root -Code ZFailure -Name 'P1 Left Punch'
        $okBefore = Get-RcControlsHash $ok; $badBefore = Get-RcControlsHash $bad
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        # Inject an OS sharing violation at the file boundary, not a fake saver.
        $lock = [System.IO.File]::Open($bad, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try { $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1 }
        finally { $lock.Dispose() }
        (Get-RcControlsHash $ok) | Should -Not -Be $okBefore
        (Get-RcControlsHash $bad) | Should -BeExactly $badBefore
        (Get-ProfileInputApi (Read-Xml $ok)) | Should -BeExactly 'MergedInput'
        (Get-ProfileInputApi (Read-Xml $bad)) | Should -BeExactly 'DirectInput'
        $result.Outcome | Should -BeExactly 'PARTIAL_APPLIED'
        $result.ProductState | Should -BeExactly 'PARTIAL_KNOWN'
        $result.Mutation.Started | Should -BeTrue
        @($result.Mutation.ChangedItems).Count | Should -Be 1
        $result.Mutation.ChangedItems | Should -Contain ASettings
        $result.Mutation.FailedItems | Should -Contain ZFailure
        $display = Write-ControlPropagationResults -Reports $result.Reports -Unattended
        $display.SettingsOnlyCount | Should -Be 1
        $display.FailedCount | Should -Be 1
        $display.ControlsCopiedCount | Should -Be 0
    }
}

Describe 'RC8 issue #342: family design skips stay honest across success, no-op and failed saves' -Tag 'RC8-Issue' {
    BeforeEach {
        $script:rcControlsHost = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { param($Object) [void]$script:rcControlsHost.Add([string]$Object) }
    }
    It 'Preconditions: a registered game needs control propagation but its family has no bound reference.' -TestCases @(
        @{ Mixed = $false; FailSave = $false; ExpectedOutcome = 'NO_OP' },
        @{ Mixed = $true; FailSave = $false; ExpectedOutcome = 'SUCCEEDED' },
        @{ Mixed = $true; FailSave = $true; ExpectedOutcome = 'PARTIAL_APPLIED' }
    ) {
        param($Mixed, $FailSave, $ExpectedOutcome)
        # Mutation: treat a family without usable user bindings as incomplete, omit its skip count, or hide a real failed save.
        $root = New-RcControlsDirectory
        $waiting = New-RcControlsProfile -Root $root -Code WaitingGun -Analog AnalogJoystick
        $before = Get-RcControlsHash $waiting
        if ($Mixed) {
            $null = New-RcControlsProfile -Root $root -Code Reference -Api MergedInput -Bound $true
            $null = New-RcControlsProfile -Root $root -Code Target -Name 'P1 Up'
        }
        $lock = $null
        if ($FailSave) {
            $bad = New-RcControlsProfile -Root $root -Code ZFailure -Name 'P1 Left Punch'
            $lock = [System.IO.File]::Open($bad, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        }
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        try { $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1 }
        finally { if ($null -ne $lock) { $lock.Dispose() } }
        if ($FailSave) { $result.Mutation.FailedItems | Should -Contain ZFailure }
        $result.Outcome | Should -BeExactly $ExpectedOutcome
        $result.Summary | Should -Match '1 game skipped by design.*no usable reference game'
        $result.Mutation.SkippedItems | Should -Contain WaitingGun
        $result.Mutation.SkippedItemCount | Should -Be 1
        $skip = @($result.Reports | Where-Object Code -eq WaitingGun)
        $skip.Status | Should -BeExactly 'skipped-no-reference'
        $skip.ReasonCode | Should -BeExactly 'NO_USABLE_FAMILY_REFERENCE'
        if ($FailSave) {
            $result.ReasonCode | Should -BeExactly 'PROFILE_SAVE_FAILED'
            Get-TpmProgressCloseState $result | Should -BeExactly 'Error'
        } elseif ($Mixed) {
            $result.ReasonCode | Should -BeExactly 'CONTROLS_PROCESSED'
            Get-TpmProgressCloseState $result | Should -BeExactly 'Final'
        } else {
            $result.ReasonCode | Should -BeExactly 'NO_CHANGES_NEEDED'
            $result.Backup.Attempted | Should -BeFalse
            $result.Mutation.Started | Should -BeFalse
            Get-TpmProgressCloseState $result | Should -BeExactly 'No-op'
        }
        $result.Mutation.ChangedItems | Should -Not -Contain WaitingGun
        (Get-RcControlsHash $waiting) | Should -BeExactly $before
        # The screen is short now; the game and its control type are the old facts behind D. Press D, then read what was shown.
        Mock Test-TpmInteractiveInput { return $true }
        Mock Read-HostSafe { return 'D' }
        $rendered = Write-ControlPropagationResults -Reports $result.Reports
        @($rendered.DesignSkippedItems).Count | Should -Be 1
        $rendered.DesignSkippedItems[0].Code | Should -BeExactly 'WaitingGun'
        $rendered.DesignSkippedItems[0].Family | Should -BeExactly 'lightgun'
        $rendered.SkippedCount | Should -Be 1
        $rendered.ControlsCopiedCount | Should -Be $(if ($Mixed) { 1 } else { 0 })
        $rendered.FailedCount | Should -Be $(if ($FailSave) { 1 } else { 0 })
        $summary = Get-TpmControlPropagationSummary -Reports $result.Reports -Outcome $result.Outcome
        $summary.NotChanged | Should -Match '1 game skipped by design.*no usable reference game'
        if (-not $FailSave) { $summary.Status | Should -BeExactly 'Ok'; @($summary.Needs).Count | Should -Be 0 }
        if (-not $Mixed) { $summary.Title | Should -BeExactly 'No game was changed.' }
        $shown = (($script:rcControlsHost -join ' ') -replace '\s+', ' ')
        $shown | Should -Match "WaitingGun What happened: Skipped by design:.*'lightgun' family"
        $shown | Should -Match 'Add one game of this family with your own controls, then run this again\.'
        # When other work needs an action report, preserve the skip there as information, not a required repair.
        $text = New-TpmActionRequiredReportText -DesignSkippedItems $rendered.DesignSkippedItems -RunId 'rc8-controls'
        $text | Should -Match 'CONTROLS SKIPPED BY DESIGN \(informational; not a failed save\)'
        $text | Should -Match "WaitingGun: Skipped by design:.*'lightgun' family"
        $reportPath = Join-Path $root 'ActionRequired.txt'
        (Write-TpmActionRequiredReport -ActionPath $reportPath -DesignSkippedItems $rendered.DesignSkippedItems -RunId 'rc8-controls' -Quiet) | Should -BeTrue
        $saved = [System.IO.File]::ReadAllText($reportPath)
        $saved | Should -Match "WaitingGun: Skipped by design:.*'lightgun' family"
        $saved | Should -Match 'Add one game of this family with your own controls, then run this again\.'
    }
    It 'FIX108: below-threshold user controls are preserved when the whole family has no usable reference' {
        # Mutation: use barely-bound games as references or supply defaults -> existing partial user bindings are changed.
        $root = New-RcControlsDirectory
        $partial = New-RcControlsProfile -Root $root -Code PartialGun -Analog AnalogJoystick -Bound $true
        $unbound = New-RcControlsProfile -Root $root -Code UnboundGun -Analog AnalogJoystick
        $partialBefore = Get-RcControlsHash $partial; $unboundBefore = Get-RcControlsHash $unbound
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 5)
        $pool.Count | Should -Be 0
        $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 5
        $result.Outcome | Should -BeExactly 'NO_OP'
        $result.Summary | Should -Match 'No game was changed.*2 games skipped by design'
        $result.Mutation.SkippedItemCount | Should -Be 2
        $result.Mutation.FailedItemCount | Should -Be 0
        $result.Backup.Attempted | Should -BeFalse
        (Get-RcControlsHash $partial) | Should -BeExactly $partialBefore
        (Get-RcControlsHash $unbound) | Should -BeExactly $unboundBefore
        @($result.Reports | Where-Object Status -eq 'skipped-no-reference').Count | Should -Be 2
    }

    It 'FIX108: a same-family reference with zero matching controls is skipped without a backup or invented bindings' {
        # Mutation: accept zero overlap or invent fallback controls -> the target changes or falsely reports success.
        $root = New-RcControlsDirectory
        $null = New-RcControlsProfile -Root $root -Code Reference -Bound $true
        $target = New-RcControlsProfile -Root $root -Code NoOverlap
        [xml]$fixture = [System.IO.File]::ReadAllText($target)
        $fixture.SelectSingleNode('/GameProfile/JoystickButtons/JoystickButtons/InputMapping').InnerText = 'P1ButtonStart'
        [System.IO.File]::WriteAllText($target, $fixture.OuterXml)
        $before = Get-RcControlsHash $target
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        $pool.Count | Should -Be 1
        $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1
        $result.Outcome | Should -BeExactly 'NO_OP'
        $result.Mutation.SkippedItems | Should -Contain NoOverlap
        $result.Mutation.FailedItemCount | Should -Be 0
        $result.Backup.Attempted | Should -BeFalse
        (Get-RcControlsHash $target) | Should -BeExactly $before
        @((Get-ButtonNodes (Read-Xml $target)) | Where-Object { Test-ButtonIsBound $_ }).Count | Should -Be 0
        $report = @($result.Reports | Where-Object Code -eq NoOverlap)
        $report.Status | Should -BeExactly 'skipped-no-reference'
        $report.Family | Should -BeExactly 'button'
        $report.ReasonCode | Should -BeExactly 'NO_USABLE_FAMILY_REFERENCE'
    }

    It 'FIX108: an unverified safety backup remains Error beside a family design skip and writes nothing' {
        # Mutation: let a design skip override backup failure or allow saving without verification -> an unsafe write is hidden.
        $root = New-RcControlsDirectory
        $null = New-RcControlsProfile -Root $root -Code Reference -Bound $true
        $target = New-RcControlsProfile -Root $root -Code Target
        $waiting = New-RcControlsProfile -Root $root -Code WaitingGun -Analog AnalogJoystick
        $targetBefore = Get-RcControlsHash $target; $waitingBefore = Get-RcControlsHash $waiting
        Mock New-TpmVerifiedUserProfilesBackup { [pscustomobject]@{ Required = $true; Attempted = $true; Created = $false; Verified = $false; RootPath = $null } }
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'PROFILE_BACKUP_FAILED'
        Get-TpmProgressCloseState $result | Should -BeExactly 'Error'
        $result.Mutation.FailedItems | Should -Contain Target
        $result.Mutation.SkippedItems | Should -Contain WaitingGun
        (Get-RcControlsHash $target) | Should -BeExactly $targetBefore
        (Get-RcControlsHash $waiting) | Should -BeExactly $waitingBefore
        (Get-TpmControlPropagationSummary -Reports $result.Reports -Outcome $result.Outcome).Status | Should -BeExactly 'Problem'
    }

    It 'Regression design skips survive downstream handoff without independently triggering ACTION REQUIRED (structural)' {
        # Mutation: include designSkippedItems in hasAnyAction or drop the shared informational report handoff.
        $assignments = @($script:rcControlsAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $n.Left.Extent.Text -eq '$designSkippedItems' -and
            $n.Right.Extent.Text -match '\$propResult\.DesignSkippedItems'
        }, $true))
        $assignments.Count | Should -Be 2
        $cursor = $assignments[0].Parent
        while ($null -ne $cursor) {
            if ($cursor -is [System.Management.Automation.Language.FunctionDefinitionAst]) { throw 'Expected the normal-flow top-level handoff.' }
            if ($cursor -is [System.Management.Automation.Language.IfStatementAst]) {
                foreach ($clause in $cursor.Clauses) {
                    $clause.Item1.Extent.Text | Should -Not -Match '\$propTransaction\.Outcome'
                }
            }
            $cursor = $cursor.Parent
        }
        $displaySections = @($script:rcControlsAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -eq '$designSkippedItems.Count -gt 0' -and
            $n.Extent.Text -match 'CONTROLS SKIPPED BY DESIGN'
        }, $true))
        $displaySections.Count | Should -Be 1
        $displaySections[0].Extent.Text | Should -Match 'Get-TpmControlPropagationReportLine -Report \$r'
        # The flag is set once and set again after the firmware copy; both use the same list ($testAnyAction), which must leave out designSkippedItems.
        $actionAssignments = @($script:rcControlsAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -in @('$hasAnyAction', '$testAnyAction')
        }, $true))
        $actionAssignments.Count | Should -Be 3
        foreach ($assignment in $actionAssignments) { $assignment.Right.Extent.Text | Should -Not -Match 'designSkippedItems' }
        $emptyPoolBranches = @($script:rcControlsAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$pool.Count -eq 0' -and
            $n.Clauses[0].Item2.Extent.Text -match 'Write-ControlPropagationResults'
        }, $true))
        $emptyPoolBranches.Count | Should -Be 2
        foreach ($branch in $emptyPoolBranches) {
            $branch.Clauses[0].Item2.Extent.Text | Should -Match 'Invoke-ControlPropagation'
        }
        $savedCalls = @($script:rcControlsAst.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.CommandAst] -and
            $n.Extent.Text -match '-DesignSkippedItems\s+\$designSkippedItems\b'
        }, $true))
        $savedCalls.Count | Should -BeGreaterThan 0
        @($savedCalls | Where-Object { $_.Extent.StartOffset -gt $assignments[0].Extent.EndOffset }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Control propagation when a save removed the old profile' -Tag 'RC8-Issue' {
    It 'carries the kept copy from the save failure into the report and the game details' {
        # Mutation: drop the kept-copy capture in Invoke-ControlPropagationLegacy -> the failed game has no KeptCopy, the run is not ACTION_REQUIRED and the details never name the file.
        $root = New-RcControlsDirectory
        $null = New-RcControlsProfile -Root $root -Code Reference -Api MergedInput -Bound $true
        $null = New-RcControlsProfile -Root $root -Code Target -Name 'P1 Up'
        $script:rcTarget = Join-Path $root 'Target.xml'
        $script:rcKeptTmp = $null
        Mock Write-Host {}
        # The product's own test seam: the replace fails part-way, after the old profile was removed. Save-Xml itself words the "kept at" message.
        Mock Invoke-TpmAtomicFileReplace {
            $script:rcKeptTmp = $Source
            [System.IO.File]::Delete($Destination)
            throw (New-Object System.IO.IOException 'simulated ReplaceFile 1176')
        } -ParameterFilter { $Destination -eq $script:rcTarget }
        $pool = @(Build-ArchetypePool -userProfilesDir $root -minBound 1)
        $result = Invoke-ControlPropagation -userProfilesDir $root -pool $pool -minBound 1
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        $script:rcKeptTmp | Should -Not -BeNullOrEmpty
        @($result.Reports | Where-Object Code -eq 'Target')[0].KeptCopy | Should -BeExactly $script:rcKeptTmp
        $summary = Get-TpmControlPropagationSummary -Reports $result.Reports -Outcome $result.Outcome
        $lines = @($summary.Blocks | ForEach-Object { $_.Lines }) -join "`n"
        $lines | Should -Match 'removed while saving'
        $lines | Should -Match ([regex]::Escape([System.IO.Path]::GetFileName($script:rcKeptTmp)))
    }
}
