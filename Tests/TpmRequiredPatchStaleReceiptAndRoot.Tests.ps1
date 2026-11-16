#Requires -Module Pester

# An install that was interrupted before it changed any game file leaves a "Prepared" receipt
# while every game file is still original. That old receipt must not block a new install of a
# recipe in an exclusive group. A game folder typed with a trailing backslash must work the same
# as one without it. The engine is dot-sourced like the other TpmRequiredPatch tests.
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

    function Get-StaleBytesSha256 {
        param([Parameter(Mandatory)][byte[]]$Bytes)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
    }

    # Schema 3 catalog with one ReplaceFile and one CreateFile, in the given exclusive group.
    function New-StaleCase {
        param([Parameter(Mandatory)][string]$Name, [string]$Group = '')
        $root = Join-Path $TestDrive $Name
        $game = Join-Path $root 'g'
        $parent = Join-Path $game 'd'
        $payload = Join-Path $root 'p'
        $recovery = Join-Path $root 'r'
        $protected = Join-Path $root 'x'
        foreach ($directory in @($parent,$payload,$recovery,$protected)) { [void][IO.Directory]::CreateDirectory($directory) }
        $exeBytes = [Text.Encoding]::ASCII.GetBytes('synthetic executable; never run')
        [IO.File]::WriteAllBytes((Join-Path $game 's.exe'), $exeBytes)
        $createBytes = [Text.Encoding]::ASCII.GetBytes('created payload')
        [IO.File]::WriteAllBytes((Join-Path $payload 'c.bin'), $createBytes)
        $createHash = Get-StaleBytesSha256 $createBytes
        $beforeBytes = [Text.Encoding]::ASCII.GetBytes('settings before')
        $afterBytes = [Text.Encoding]::ASCII.GetBytes('settings after')
        [IO.File]::WriteAllBytes((Join-Path $parent 's.ini'), $beforeBytes)
        [IO.File]::WriteAllBytes((Join-Path $payload 's.new'), $afterBytes)
        $beforeHash = Get-StaleBytesSha256 $beforeBytes
        $afterHash = Get-StaleBytesSha256 $afterBytes
        $create = [pscustomobject]@{Type='CreateFile'; Target='d/c.bin'; BeforeState='Absent'; AfterSha256=$createHash; Payload='c.bin'; PayloadSha256=$createHash}
        $replace = [pscustomobject]@{Type='ReplaceFile'; Target='d/s.ini'; BeforeSha256=$beforeHash; AfterSha256=$afterHash; Payload='s.new'; PayloadSha256=$afterHash}
        $entry = [pscustomobject]@{
            Id='stale.prepared.group'; ProfileId='StaleCase'; Executable='s.exe'; ExecutableSha256=(Get-StaleBytesSha256 $exeBytes)
            SourceUrl='https://example.invalid/stale'; SourceRevision=('B' * 40); ExclusiveGroup=$Group; Operations=@($replace,$create)
        }
        $content = [pscustomobject]@{Schema=3; Entries=@($entry)} | ConvertTo-Json -Depth 8
        $inputs = @{
            CatalogContent=$content; CatalogSha256=(Get-TpmPatchTextSha256 $content); PatchId=$entry.Id; ProfileId='StaleCase'
            GameRoot=$game; PayloadRoot=$payload; RecoveryRoot=$recovery; ProtectedRoots=@($protected)
        }
        return [pscustomobject]@{ Inputs=$inputs; Game=$game; SettingsTarget=(Join-Path $parent 's.ini'); CreateTarget=(Join-Path $parent 'c.bin'); AfterHash=$afterHash; BeforeHash=$beforeHash }
    }

    function Set-StaleReceiptState {
        param([Parameter(Mandatory)][string]$Run, [Parameter(Mandatory)][string]$State)
        $path = Join-Path $Run 'receipt.json'
        $text = [IO.File]::ReadAllText($path)
        $changed = [regex]::Replace($text, '"State":\s*"[A-Za-z]+"', ('"State":  "' + $State + '"'))
        [IO.File]::WriteAllText($path, $changed, (New-Object Text.UTF8Encoding($false)))
    }
}

Describe 'A stale Prepared receipt (no game file was changed)' {
    It 'does not block a new install of a recipe in an exclusive group, and keeps the old receipt' {
        $case = New-StaleCase 's1' 'stale.group'
        $inputs = $case.Inputs
        $first = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $oldRun = $first.RecoveryDirectory
        (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $oldRun -Confirm:$false).Status | Should -BeExactly 'Restored'
        Set-StaleReceiptState -Run $oldRun -State 'Prepared'
        $receiptBytes = [IO.File]::ReadAllBytes((Join-Path $oldRun 'receipt.json'))

        $second = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $second.Status | Should -BeExactly 'Applied'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.AfterHash
        [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $oldRun 'receipt.json'))) | Should -BeExactly ([Convert]::ToBase64String($receiptBytes))
    }

    It 'still blocks a new install when the Prepared receipt cannot be matched to the game files' {
        $case = New-StaleCase 's2' 'stale.group'
        $inputs = $case.Inputs
        $first = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $oldRun = $first.RecoveryDirectory
        (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $oldRun -Confirm:$false).Status | Should -BeExactly 'Restored'
        Set-StaleReceiptState -Run $oldRun -State 'Prepared'
        # One file looks promoted and the other original: the engine cannot tell what happened.
        [IO.File]::WriteAllBytes($case.CreateTarget, [Text.Encoding]::ASCII.GetBytes('created payload'))

        { Invoke-TpmCatalogPatch @inputs -Confirm:$false } | Should -Throw
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
    }
}

Describe 'A game folder with a trailing backslash' {
    It 'installs and undoes the same as one without it, and the receipt stores the plain folder' {
        $case = New-StaleCase 'r1'
        $inputs = $case.Inputs
        $inputs.GameRoot = $case.Game + '\'
        $applied = Invoke-TpmCatalogPatch @inputs -Confirm:$false
        $applied.Status | Should -BeExactly 'Applied'
        ([IO.File]::ReadAllText((Join-Path $applied.RecoveryDirectory 'receipt.json')) | ConvertFrom-Json).GameRoot | Should -BeExactly $case.Game
        (Get-TpmPatchPlan @inputs).Status | Should -BeExactly 'AlreadyApplied'
        (Undo-TpmCatalogPatch @inputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
    }
}

Describe 'Undo after the patch list changed (the install was made with an older list)' {
    BeforeAll {
        # Same game and patch, but the list now has one more entry, so its hash differs.
        function Use-NewerList {
            param([Parameter(Mandatory)]$Case, [switch]$ChangePatch)
            $list = $Case.Inputs.CatalogContent | ConvertFrom-Json
            $extra = $list.Entries[0].PSObject.Copy()
            $extra.Id = 'another.patch'
            $extra.ProfileId = 'AnotherGame'
            if ($ChangePatch) { $list.Entries[0].Operations[0].BeforeSha256 = ('A' * 64) }
            $content = [pscustomobject]@{Schema=3; Entries=@($list.Entries[0], $extra)} | ConvertTo-Json -Depth 8
            $newer = @{} + $Case.Inputs
            $newer.CatalogContent = $content
            $newer.CatalogSha256 = Get-TpmPatchTextSha256 $content
            return $newer
        }
    }

    It 'still undoes the patch and puts the original files back' {
        $case = New-StaleCase 'u1'
        $original = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @original -Confirm:$false
        $newer = Use-NewerList $case
        $newer.CatalogSha256 | Should -Not -BeExactly $case.Inputs.CatalogSha256
        $found = @(Get-TpmPatchRecoveryDirectories -Request ([pscustomobject]@{Context=[pscustomobject]@{RecoveryRoot=$newer.RecoveryRoot; ProfileId='StaleCase'; GameRoot=$case.Game}}) -PatchId 'stale.prepared.group')
        $found | Should -HaveCount 1
        (Undo-TpmCatalogPatch @newer -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
        Test-Path -LiteralPath $case.CreateTarget | Should -BeFalse
    }

    It 'refuses and changes nothing when the game file was changed after the install' {
        $case = New-StaleCase 'u2'
        $original = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @original -Confirm:$false
        $newer = Use-NewerList $case
        [IO.File]::WriteAllText($case.SettingsTarget, 'changed by the user')
        $failure = $null
        try { [void](Undo-TpmCatalogPatch @newer -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false) } catch { $failure = $_.Exception.Message }
        $failure | Should -Not -BeNullOrEmpty
        $plain = Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $failure
        $plain | Should -BeExactly 'A file in the game folder is different from what the patch expects. It was left alone.'
        $plain | Should -Not -BeLike '*older patch list*'
        $failure | Should -BeLike '*target conflict*'
        [IO.File]::ReadAllText($case.SettingsTarget) | Should -BeExactly 'changed by the user'
        Test-Path -LiteralPath $case.CreateTarget | Should -BeTrue
    }

    It 'keeps the real reason when a game file cannot be read, even though the list changed' {
        $case = New-StaleCase 'u6'
        $original = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @original -Confirm:$false
        $newer = Use-NewerList $case
        $lock = New-Object IO.FileStream($case.SettingsTarget, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        $failure = $null
        try { try { [void](Undo-TpmCatalogPatch @newer -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false) } catch { $failure = $_.Exception.Message } } finally { $lock.Dispose() }
        $failure | Should -Not -BeNullOrEmpty
        $failure | Should -Not -BeLike '*older patch list*'
        $plain = Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $failure
        $plain | Should -Not -BeLike '*older patch list*'
        [IO.File]::ReadAllText($case.SettingsTarget) | Should -BeExactly 'settings after'
    }

    It 'keeps the real reason for a half-done state (one file back, one not), even though the list changed' {
        $case = New-StaleCase 'u7'
        $original = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @original -Confirm:$false
        $newer = Use-NewerList $case
        Remove-Item -LiteralPath $case.CreateTarget
        $failure = $null
        try { [void](Undo-TpmCatalogPatch @newer -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false) } catch { $failure = $_.Exception.Message }
        $failure | Should -BeLike '*Mixed/partially*'
        (Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $failure) | Should -BeExactly 'A file in the game folder is different from what the patch expects. It was left alone.'
        [IO.File]::ReadAllText($case.SettingsTarget) | Should -BeExactly 'settings after'
    }

    It 'says the saved copy came from an older patch list when this patch itself was changed' {
        $case = New-StaleCase 'u3'
        $original = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @original -Confirm:$false
        $newer = Use-NewerList $case -ChangePatch
        $failure = $null
        try { [void](Undo-TpmCatalogPatch @newer -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false) } catch { $failure = $_.Exception.Message }
        Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $failure | Should -BeExactly 'This saved copy was made by an older patch list. Nothing was changed.'
        [IO.File]::ReadAllText($case.SettingsTarget) | Should -BeExactly 'settings after'
    }

    It 'says the saved copy came from an older patch list when the new list changed the after-file, and changes nothing' {
        $case = New-StaleCase 'u5'
        $original = $case.Inputs
        $applied = Invoke-TpmCatalogPatch @original -Confirm:$false
        $list = $case.Inputs.CatalogContent | ConvertFrom-Json
        $list.Entries[0].Operations[0].AfterSha256 = ('A' * 64)
        $list.Entries[0].Operations[0].PayloadSha256 = ('A' * 64)
        $content = [pscustomobject]@{Schema=3; Entries=@($list.Entries[0])} | ConvertTo-Json -Depth 8
        $newer = @{} + $case.Inputs
        $newer.CatalogContent = $content
        $newer.CatalogSha256 = Get-TpmPatchTextSha256 $content
        $failure = $null
        try { [void](Undo-TpmCatalogPatch @newer -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false) } catch { $failure = $_.Exception.Message }
        $failure | Should -Not -BeNullOrEmpty
        Get-TpmRequiredPatchPlainReason -Status 'BLOCKED' -Reason $failure | Should -BeExactly 'This saved copy was made by an older patch list. Nothing was changed.'
        [IO.File]::ReadAllText($case.SettingsTarget) | Should -BeExactly 'settings after'
        Test-Path -LiteralPath $case.CreateTarget | Should -BeTrue
    }

    It 'in an exclusive group: undoes its own patch after a list change, but a different variant stays blocked' {
        $case = New-StaleCase 'u4' 'stale.group'
        function New-Gpu([string]$Name) { [pscustomobject]@{Adapters=@([pscustomobject]@{Name=$Name}); MultiGpuAmbiguous=$false; ActiveGpuConfidence='INFERRED'; ActiveAdapterIndex=0; ActiveAdapterName=$Name} }
        function Get-DetectedGpuVendor { param($HardwareEvidence, [switch]$RequireUnambiguous) $n = [string]$HardwareEvidence.ActiveAdapterName; [pscustomobject]@{State='KNOWN'; Vendor=$(if ($n -like 'AMD*') {'AMD'} else {'NVIDIA'}); Name=$n; Reason=''} }
        $list = $case.Inputs.CatalogContent | ConvertFrom-Json
        $list.Entries[0] | Add-Member -NotePropertyName HardwarePredicate -NotePropertyValue ([pscustomobject]@{Vendor='AMD'})
        $content = [pscustomobject]@{Schema=3; Entries=@($list.Entries[0])} | ConvertTo-Json -Depth 8
        $original = @{} + $case.Inputs
        $original.CatalogContent = $content
        $original.CatalogSha256 = Get-TpmPatchTextSha256 $content
        $original.HardwareEvidence = New-Gpu 'AMD Radeon fixture'
        $applied = Invoke-TpmCatalogPatch @original -Confirm:$false
        $variant = $list.Entries[0].PSObject.Copy()
        $variant.Id = 'stale.variant.b'
        $variant.HardwarePredicate = [pscustomobject]@{Vendor='NVIDIA'}
        $variant.Operations = @($list.Entries[0].Operations[1].PSObject.Copy())
        $variant.Operations[0].Target = 'd/b.bin'
        $content = [pscustomobject]@{Schema=3; Entries=@($list.Entries[0], $variant)} | ConvertTo-Json -Depth 8
        $newer = @{} + $original
        $newer.CatalogContent = $content
        $newer.CatalogSha256 = Get-TpmPatchTextSha256 $content
        $other = @{} + $newer
        $other.PatchId = 'stale.variant.b'
        $other.HardwareEvidence = New-Gpu 'NVIDIA GeForce fixture'
        { Invoke-TpmCatalogPatch @other -Confirm:$false } | Should -Throw -ExpectedMessage 'An exclusive recipe is active; undo it before selecting another variant.'
        Test-Path -LiteralPath (Join-Path (Split-Path $case.CreateTarget) 'b.bin') | Should -BeFalse
        (Undo-TpmCatalogPatch @newer -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status | Should -BeExactly 'Restored'
        (Get-FileHash -LiteralPath $case.SettingsTarget -Algorithm SHA256).Hash | Should -BeExactly $case.BeforeHash
    }
}
