#Requires -Module Pester

# FIX110A / S-17: a grouped (schema 3) required-patch transaction publishes a Prepared
# receipt before promotion and an Applied receipt after it. An interruption between the two
# leaves matching targets and a Prepared receipt. That receipt must be reconciled against the
# recorded hashes and file identities (so Undo stays reachable and install does not claim
# "already installed" while Undo is lost), or reported as ACTION REQUIRED with every receipt
# and backup kept. The engine is dot-sourced like the other TpmRequiredPatch tests; manager
# helpers are extracted from the parsed script.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainScriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $parseTokens = $null
    $parseErrors = $null
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScriptPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Unable to parse manager helper source for receipt tests.' }
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath','Test-TpmPathLengthAllowed','Test-TpmPathOverlap','Assert-TpmNoReparseWriteTarget','New-ManagerUpdateBackup')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)

    function Get-F110BytesSha256 {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
    }

    function Get-F110Identity {
        param([Parameter(Mandatory)][string]$Path)
        $stream = Open-TpmPatchCreationFile $Path
        try { return [TpmSupportNativeMethods]::PatchFileIdentity($stream.SafeFileHandle) } finally { $stream.Dispose() }
    }

    # Schema 3 catalog with one ReplaceFile and one CreateFile, in the given exclusive group.
    function New-F110Case {
        param([Parameter(Mandatory)][string]$Name, [string]$Group = '')
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'
        $parent = Join-Path $game 'd'
        $payload = Join-Path $root 'p'
        $recovery = Join-Path $root 'r'
        $protected = Join-Path $root 'x'
        foreach ($directory in @($parent,$payload,$recovery,$protected)) { [void][IO.Directory]::CreateDirectory($directory) }
        $exeBytes = [Text.Encoding]::ASCII.GetBytes('fix110a synthetic executable; never run')
        [IO.File]::WriteAllBytes((Join-Path $game 's.exe'), $exeBytes)
        $createBytes = [Text.Encoding]::ASCII.GetBytes('fix110a created payload')
        [IO.File]::WriteAllBytes((Join-Path $payload 'c.bin'), $createBytes)
        $createHash = Get-F110BytesSha256 $createBytes
        $beforeBytes = [Text.Encoding]::ASCII.GetBytes('fix110a settings before')
        $afterBytes = [Text.Encoding]::ASCII.GetBytes('fix110a settings after')
        [IO.File]::WriteAllBytes((Join-Path $parent 's.ini'), $beforeBytes)
        [IO.File]::WriteAllBytes((Join-Path $payload 's.new'), $afterBytes)
        $beforeHash = Get-F110BytesSha256 $beforeBytes
        $afterHash = Get-F110BytesSha256 $afterBytes
        $create = [pscustomobject]@{Type='CreateFile'; Target='d/c.bin'; BeforeState='Absent'; AfterSha256=$createHash; Payload='c.bin'; PayloadSha256=$createHash}
        $replace = [pscustomobject]@{Type='ReplaceFile'; Target='d/s.ini'; BeforeSha256=$beforeHash; AfterSha256=$afterHash; Payload='s.new'; PayloadSha256=$afterHash}
        $entry = [pscustomobject]@{
            Id='fix110a.prepared.group'; ProfileId='Fix110A'; Executable='s.exe'; ExecutableSha256=(Get-F110BytesSha256 $exeBytes)
            SourceUrl='https://example.invalid/fix110a'; SourceRevision=('B' * 40); ExclusiveGroup=$Group; Operations=@($replace,$create)
        }
        $content = [pscustomobject]@{Schema=3; Entries=@($entry)} | ConvertTo-Json -Depth 8
        $inputs = @{
            CatalogContent=$content; CatalogSha256=(Get-TpmPatchTextSha256 $content); PatchId=$entry.Id; ProfileId='Fix110A'
            GameRoot=$game; PayloadRoot=$payload; RecoveryRoot=$recovery; ProtectedRoots=@($protected)
        }
        return [pscustomobject]@{
            Inputs=$inputs; Recovery=$recovery; Parent=$parent; CreateTarget=(Join-Path $parent 'c.bin'); CreateHash=$createHash
            SettingsTarget=(Join-Path $parent 's.ini'); BeforeHash=$beforeHash; AfterHash=$afterHash
        }
    }

    # Simulates the interruption: the real transaction wrote its receipt revisions, and the
    # last one (Applied) never reached the disk, so the receipt shows another State.
    function Set-F110ReceiptState {
        param([Parameter(Mandatory)][string]$Run, [Parameter(Mandatory)][string]$State)
        $path = Join-Path $Run 'receipt.json'
        $text = [IO.File]::ReadAllText($path)
        $changed = [regex]::Replace($text, '"State":\s*"[A-Za-z]+"', ('"State":  "' + $State + '"'))
        if ($changed -ceq $text -and $text -cnotmatch ('"State":\s*"' + $State + '"')) { throw 'The receipt State was not found.' }
        [IO.File]::WriteAllText($path, $changed, (New-Object Text.UTF8Encoding($false)))
    }

    function Read-F110Receipt {
        param([Parameter(Mandatory)]$Case, [Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$Run)
        return (Read-TpmCatalogPatchReceipt -Plan $Plan -PatchId $Case.Inputs.PatchId -ProfileId $Case.Inputs.ProfileId -CatalogSha256 $Case.Inputs.CatalogSha256 -RecoveryDirectory $Run)
    }

    # Replaces the settings file with a new file object that holds exactly the same bytes.
    function Copy-F110SettingsToNewObject {
        param([Parameter(Mandatory)]$Case)
        $temp = $Case.SettingsTarget + '.f110.tmp'
        [IO.File]::WriteAllBytes($temp, [IO.File]::ReadAllBytes($Case.SettingsTarget))
        [IO.File]::Delete($Case.SettingsTarget)
        [IO.File]::Move($temp, $Case.SettingsTarget)
    }
}

Describe 'FIX110A interrupted Prepared grouped receipt: targets promoted' {
    It 'keeps Undo reachable for <Label>: the Prepared receipt is found and Undo restores the original files' -TestCases @(
        @{ Label = 'a recipe with no exclusive group'; Group = '' }
        @{ Label = 'a recipe in an exclusive group'; Group = 'fix110a.group' }
    ) {
        # Mutation: restore the old Applied-only receipt check (Prepared rejected as 'Grouped receipt identity mismatch.' and
        # silently skipped) -> Undo throws, so the recovery route is lost.
        $case = New-F110Case ('t1' + $Group.Length) $Group
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        $run = $applied.RecoveryDirectory
        Set-F110ReceiptState -Run $run -State 'Prepared'
        ([IO.File]::ReadAllText((Join-Path $run 'receipt.json')) | ConvertFrom-Json).State | Should -BeExactly 'Prepared'

        $plan = Get-TpmPatchPlan @inputs
        $plan.Status | Should -BeExactly 'AlreadyApplied'

        $undone = Undo-TpmCatalogPatch @inputs -RecoveryDirectory $run -Confirm:$false
        $undone.Status | Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        Test-Path -LiteralPath $case.CreateTarget | Should -BeFalse
        ([IO.File]::ReadAllText((Join-Path $run 'receipt.json')) | ConvertFrom-Json).State | Should -BeExactly 'Restored'
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'Ready'
    }

    It 'asks for owner action when a promoted file is a different object with the same bytes, and keeps everything' {
        # Mutation: reconcile a Prepared receipt by hash only (skip the recorded AfterFileIdentity check) -> no ACTION REQUIRED, a foreign object is adopted.
        $case = New-F110Case 't2'
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $run = $applied.RecoveryDirectory
        $plan = Get-TpmPatchPlan @inputs -ForUndo
        Set-F110ReceiptState -Run $run -State 'Prepared'
        $oldIdentity = Get-F110Identity $case.SettingsTarget
        Copy-F110SettingsToNewObject -Case $case
        (Get-F110Identity $case.SettingsTarget) | Should -Not -BeExactly $oldIdentity
        $receiptBytes = [IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))
        $backup = ([IO.File]::ReadAllText((Join-Path $run 'receipt.json')) | ConvertFrom-Json).Operations[0].Backup

        { Read-F110Receipt -Case $case -Plan $plan -Run $run } | Should -Throw -ExpectedMessage 'ACTION REQUIRED:*'
        # The install-time check must not report "already applied" without an undo route.
        $installPlan = Get-TpmPatchPlan @inputs
        $installPlan.Status | Should -BeExactly 'Unavailable'
        $installPlan.Reason | Should -BeLike 'ACTION REQUIRED:*'
        { Undo-TpmCatalogPatch @inputs -RecoveryDirectory $run -Confirm:$false } | Should -Throw -ExpectedMessage 'ACTION REQUIRED:*'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.AfterHash
        Test-Path -LiteralPath $case.CreateTarget | Should -BeTrue
        Test-Path -LiteralPath $backup | Should -BeTrue
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))) | Should -BeExactly ([Convert]::ToBase64String($receiptBytes))
    }

    It 'asks for owner action when a target holds foreign bytes, and never changes the foreign file or the evidence' {
        # Mutation: treat a Prepared receipt as valid without checking the live targets -> Undo would overwrite the foreign file.
        $case = New-F110Case 't3'
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $run = $applied.RecoveryDirectory
        $plan = Get-TpmPatchPlan @inputs -ForUndo
        Set-F110ReceiptState -Run $run -State 'Prepared'
        [IO.File]::WriteAllBytes($case.SettingsTarget, [Text.Encoding]::ASCII.GetBytes('foreign bytes'))
        $foreignHash = (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash
        $receiptBytes = [IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))

        { Read-F110Receipt -Case $case -Plan $plan -Run $run } | Should -Throw -ExpectedMessage 'ACTION REQUIRED:*'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $foreignHash
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))) | Should -BeExactly ([Convert]::ToBase64String($receiptBytes))
    }
}

Describe 'FIX110A interrupted Prepared grouped receipt: targets not promoted' {
    It 'is not an undo record when every target still holds its original state, and the receipt and backup are kept' {
        # Mutation: accept a Prepared receipt without looking at the targets -> a transaction that never promoted becomes an undo record.
        $case = New-F110Case 't4'
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $run = $applied.RecoveryDirectory
        $undone = Undo-TpmCatalogPatch @inputs -RecoveryDirectory $run -Confirm:$false
        $undone.Status | Should -BeExactly 'Restored'
        Set-F110ReceiptState -Run $run -State 'Prepared'
        $plan = Get-TpmPatchPlan @inputs -ForUndo
        $plan.Status | Should -BeExactly 'Ready'
        $receiptBytes = [IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))
        $backup = ([IO.File]::ReadAllText((Join-Path $run 'receipt.json')) | ConvertFrom-Json).Operations[0].Backup

        $failure = $null
        try { [void](Read-F110Receipt -Case $case -Plan $plan -Run $run) } catch { $failure = $_.Exception.Message }
        $failure | Should -BeLike '*is not applied (targets still original)*'
        $failure | Should -Not -BeLike 'ACTION REQUIRED:*'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        Test-Path -LiteralPath $case.CreateTarget | Should -BeFalse
        Test-Path -LiteralPath $backup | Should -BeTrue
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $run 'receipt.json'))) | Should -BeExactly ([Convert]::ToBase64String($receiptBytes))
    }
}

Describe 'FIX110A Applied grouped receipts keep their strict identity check' {
    It 'still rejects an Applied receipt whose promoted file is a different object, without ACTION REQUIRED' {
        # Mutation: apply the Prepared reconciliation wording to Applied receipts -> the message changes and an Applied receipt is treated as interrupted.
        $case = New-F110Case 't5'
        $inputs = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $run = $applied.RecoveryDirectory
        $plan = Get-TpmPatchPlan @inputs -ForUndo
        Copy-F110SettingsToNewObject -Case $case
        { Read-F110Receipt -Case $case -Plan $plan -Run $run } | Should -Throw -ExpectedMessage 'Grouped target object identity changed.'
    }
}

Describe 'Required patch: a game folder typed with a trailing backslash' {
    It 'finds the undo record of an installed patch when the game folder is typed with a trailing backslash' {
        # Mutation: remove the trailing-separator trim from Get-TpmManualPatchContext -> the typed folder never matches the stored receipt, so Undo looks unavailable.
        $case = New-F110Case 'slash-case' 'fix110a.group'
        $entry = @(($case.Inputs.CatalogContent | ConvertFrom-Json).Entries)[0]
        $tp = Join-Path $TestDrive 'slash-tp'
        $manager = Join-Path $TestDrive 'slash-manager'
        foreach ($directory in @($tp, (Join-Path $tp 'UserProfiles'), (Join-Path $tp 'GameProfiles'), (Join-Path $manager 'UpdateBackups\GamePatches'))) { [void][IO.Directory]::CreateDirectory($directory) }
        [IO.File]::WriteAllText((Join-Path $tp 'TeknoParrotUi.exe'), 'fix110a synthetic')
        [IO.File]::WriteAllText((Join-Path $tp 'GameProfiles\Fix110A.xml'), '<GameProfile />')
        $game = $case.Inputs.GameRoot
        $plain = Get-TpmManualPatchContext -Entry $entry -TpRoot $tp -UserProfilesDir (Join-Path $tp 'UserProfiles') -ManagerRoot $manager -GameRoot $game
        $typed = Get-TpmManualPatchContext -Entry $entry -TpRoot $tp -UserProfilesDir (Join-Path $tp 'UserProfiles') -ManagerRoot $manager -GameRoot ($game + '\')
        $inputs = $case.Inputs.Clone()
        $inputs.GameRoot = $plain.GameRoot
        $inputs.RecoveryRoot = $plain.RecoveryRoot
        $inputs.ProtectedRoots = @($plain.ProtectedRoots)
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false

        $typed.GameRoot | Should -BeExactly $plain.GameRoot
        @(Get-TpmPatchRecoveryDirectories -Request ([pscustomobject]@{ Context = $typed }) -PatchId $entry.Id) | Should -Be @($applied.RecoveryDirectory)
    }
}

Describe 'Required patch: the old copy of a replaced file cannot be removed after the change is done' {
    It 'reports the patch as installed and names the leftover copy instead of failing' {
        # Mutation: throw again when only the cleanup of the owned old copy fails -> the screen says FAILED for a game file that was changed and checked.
        $case = New-F110Case 'leftover-case' ''
        $inputs = $case.Inputs
        Mock Remove-TpmSupportHandle { throw 'the old copy is locked' }
        $result = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $result.Status | Should -BeExactly 'Applied'
        # The note must name the leftover file beside the game file, not the undo receipt folder (deleting that loses undo).
        $result.LeftoverNote | Should -Match ([regex]::Escape((Split-Path -Parent $case.SettingsTarget)) + '\\\.tpm-aside-[0-9a-f]{32}\.tmp')
        $result.LeftoverNote | Should -Not -Match ([regex]::Escape([string]$result.RecoveryDirectory))
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.AfterHash
    }
}
