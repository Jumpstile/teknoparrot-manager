#Requires -Module Pester

# ADR155-0309 Checkpoint B2 focused regression coverage for
# scripts/TPMCertification.ProductionEvidence.psm1 -- the production
# evidence adapter converting one legacy Add-Screenshot ledger record into
# the production authority's evidence schema. Every "composed with the real
# authority" test below feeds the adapter's own output into a real
# New-TPMProductionWorkflowAuthorityV1 (never a mock), proving the actual
# composition seam the harness relies on, not just this file's own output
# shape.

BeforeAll {
    $authorityModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1'
    Import-Module $authorityModulePath -Force
    $productionModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Production.psm1'
    Import-Module $productionModulePath -Force
    $evidenceModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.ProductionEvidence.psm1'
    Import-Module $evidenceModulePath -Force

    function New-TestPngFile([string]$Root, [byte[]]$Bytes) {
        $path = Join-Path $Root ([guid]::NewGuid().ToString('N') + '.png')
        [IO.File]::WriteAllBytes($path, $Bytes)
        return $path
    }

    $script:validPngBytes = [byte[]](137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4)

    function New-ValidatorV1([bool]$Valid = $true, [string]$Reason = 'ok', [int]$Width = 7, [int]$Height = 9, [scriptblock]$Throws = $null) {
        return {
            param($Path)
            if ($Throws) { & $Throws }
            return [pscustomobject]@{ Valid = $Valid; Reason = $Reason; Width = $Width; Height = $Height }
        }.GetNewClosure()
    }

    function New-LegacyRecordV1([string]$Name, [string]$Status = 'Captured', [string]$EvidenceType = 'ScreenCapture', [bool]$Required = $true, [string]$Path = $null, [string]$CaptureScope = 'Window', [string]$Details = $null) {
        return [pscustomobject]@{ Name = $Name; Label = $Name; Path = $Path; Status = $Status; EvidenceType = $EvidenceType; Required = $Required; WorkflowId = 'wf-1'; CaptureScope = $CaptureScope; Details = $Details }
    }

    function New-ExpectedV1([string]$Identifier, [bool]$Required = $true, [string]$EvidenceType = 'ScreenCapture') {
        return [pscustomobject]@{ Identifier = $Identifier; Required = $Required; EvidenceType = $EvidenceType }
    }
}

Describe 'TPMCertification.ProductionEvidence public API surface' {
    It 'exports exactly New-TPMProductionEvidenceRecordV1' {
        $exported = @((Get-Module TPMCertification.ProductionEvidence).ExportedCommands.Keys | Sort-Object)
        $exported | Should -Be @('New-TPMProductionEvidenceRecordV1')
    }
}

Describe 'New-TPMProductionEvidenceRecordV1 conversion behavior' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
    }

    It 'converts a captured ScreenCapture record, mapping CaptureScope Window to ConsoleWindow' {
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name 'final-certification-result' -Path $path -EvidenceType 'ScreenCapture' -CaptureScope 'Window'
        $expected = New-ExpectedV1 -Identifier 'final-certification-result'
        $validator = New-ValidatorV1
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator $validator
        $r.Status | Should -Be 'Captured'
        $r.EvidenceType | Should -Be 'ScreenCapture'
        $r.CaptureScope | Should -Be 'ConsoleWindow'
        $r.FailureCode | Should -BeNullOrEmpty
        $r.FailureMessage | Should -BeNullOrEmpty
    }

    It 'converts a captured DeterministicRender record, always mapping CaptureScope to Deterministic regardless of legacy value' {
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name 'smoke-file-safety-evidence' -Path $path -EvidenceType 'DeterministicRender' -CaptureScope 'AnythingAtAll'
        $expected = New-ExpectedV1 -Identifier 'smoke-file-safety-evidence' -EvidenceType 'DeterministicRender'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.Status | Should -Be 'Captured'
        $r.EvidenceType | Should -Be 'DeterministicRender'
        $r.CaptureScope | Should -Be 'Deterministic'
    }

    It 'passes through a raw ScreenCapture CaptureScope value that is not "Window" unmodified' {
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name 'certification-suite-running' -Path $path -EvidenceType 'ScreenCapture' -CaptureScope 'FullDesktop'
        $expected = New-ExpectedV1 -Identifier 'certification-suite-running'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.CaptureScope | Should -Be 'FullDesktop'
    }

    It 'converts an optional skipped record without requiring a capture' {
        $legacy = New-LegacyRecordV1 -Name 'live-thumbnail-evidence' -Status 'Skipped' -Required $false -Details 'not displayed'
        $expected = New-ExpectedV1 -Identifier 'live-thumbnail-evidence' -Required $false -EvidenceType $null
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.Status | Should -Be 'Skipped'
        $r.Required | Should -Be $false
        $r.FailureCode | Should -Be 'EVIDENCE_SKIPPED'
        $r.FailureMessage | Should -Be 'not displayed'
        $r.Path | Should -BeNullOrEmpty
    }

    It 'still converts a Skipped status to Status=Skipped even when Expected marks the slot Required (does not silently upgrade or hide the mismatch)' {
        $legacy = New-LegacyRecordV1 -Name 'adaptive-menu-normal' -Status 'Skipped' -Required $true -Details 'unexpectedly skipped'
        $expected = New-ExpectedV1 -Identifier 'adaptive-menu-normal' -Required $true -EvidenceType 'DeterministicRender'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.Status | Should -Be 'Skipped'
        $r.Required | Should -Be $true
    }

    It 'composed with the real authority: attempting to RecordEvidence a required-but-skipped evidence record is rejected immediately as EVIDENCE_REQUIRED_SKIPPED, proving the adapter never silently satisfies a required slot' {
        $expected = (Get-TPMEvidenceManifestV1)[0]
        $legacy = New-LegacyRecordV1 -Name $expected.Identifier -Status 'Skipped' -Required $expected.Required -Details 'incorrectly skipped'
        $record = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $record.Status | Should -Be 'Skipped'
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        { & $authority RecordEvidence $record } | Should -Throw '*EVIDENCE_REQUIRED_SKIPPED*'
    }

    It 'converts a failed capture, carrying the legacy Details through as FailureMessage' {
        $legacy = New-LegacyRecordV1 -Name 'requested-effective-root-evidence' -Status 'Failed' -Details 'capture threw: access denied'
        $expected = New-ExpectedV1 -Identifier 'requested-effective-root-evidence'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.Status | Should -Be 'Failed'
        $r.FailureCode | Should -Be 'EVIDENCE_CAPTURE_EXCEPTION'
        $r.FailureMessage | Should -Be 'capture threw: access denied'
    }

    It 'converts a failed capture with no Details to a generic message' {
        $legacy = New-LegacyRecordV1 -Name 'requested-effective-root-evidence' -Status 'Failed' -Details $null
        $expected = New-ExpectedV1 -Identifier 'requested-effective-root-evidence'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.FailureMessage | Should -Match "status was 'Failed'"
    }

    It 'rejects a wrong identifier/order as EVIDENCE_ORDER_INVALID, quoting the actual harness-issued name' {
        $legacy = New-LegacyRecordV1 -Name 'live-controls-evidence'
        $expected = New-ExpectedV1 -Identifier 'requested-effective-root-evidence'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.Status | Should -Be 'Failed'
        $r.FailureCode | Should -Be 'EVIDENCE_ORDER_INVALID'
        $r.FailureMessage | Should -Match "'live-controls-evidence'"
    }

    It 'rejects a null legacy record (harness never issued this identifier) as EVIDENCE_IDENTIFIER_INVALID' {
        $expected = New-ExpectedV1 -Identifier 'final-certification-result'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $null -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $r.Status | Should -Be 'Failed'
        $r.FailureCode | Should -Be 'EVIDENCE_IDENTIFIER_INVALID'
    }

    It 'converts a missing evidence file (validator throws FileNotFound) to EVIDENCE_PNG_INVALID with a generic reason' {
        $missing = Join-Path $root 'does-not-exist.png'
        $legacy = New-LegacyRecordV1 -Name 'final-certification-result' -Path $missing
        $expected = New-ExpectedV1 -Identifier 'final-certification-result'
        $validator = New-ValidatorV1 -Throws { throw [IO.FileNotFoundException]::new('missing') }
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator $validator
        $r.Status | Should -Be 'Failed'
        $r.FailureCode | Should -Be 'EVIDENCE_PNG_INVALID'
        $r.FailureMessage | Should -Be 'PNG validation failed'
    }

    It 'converts an empty evidence file (validator reports Valid=false) to EVIDENCE_PNG_INVALID with the validator''s own reason' {
        $path = New-TestPngFile $root ([byte[]]@())
        $legacy = New-LegacyRecordV1 -Name 'final-certification-result' -Path $path
        $expected = New-ExpectedV1 -Identifier 'final-certification-result'
        $validator = New-ValidatorV1 -Valid $false -Reason 'file is empty'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator $validator
        $r.FailureCode | Should -Be 'EVIDENCE_PNG_INVALID'
        $r.FailureMessage | Should -Be 'file is empty'
    }

    It 'converts a malformed evidence file (validator reports Valid=false) to EVIDENCE_PNG_INVALID with the validator''s own reason' {
        $path = New-TestPngFile $root ([byte[]](1, 2, 3))
        $legacy = New-LegacyRecordV1 -Name 'final-certification-result' -Path $path
        $expected = New-ExpectedV1 -Identifier 'final-certification-result'
        $validator = New-ValidatorV1 -Valid $false -Reason 'malformed PNG header'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator $validator
        $r.FailureMessage | Should -Be 'malformed PNG header'
    }

    It 'converts a PNG-validator exception (not merely Valid=false) to a controlled Failed result rather than propagating' {
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name 'final-certification-result' -Path $path
        $expected = New-ExpectedV1 -Identifier 'final-certification-result'
        $validator = New-ValidatorV1 -Throws { throw 'unexpected validator crash' }
        { $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator $validator } | Should -Not -Throw
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator $validator
        $r.Status | Should -Be 'Failed'
        $r.FailureCode | Should -Be 'EVIDENCE_PNG_INVALID'
    }

    It 'records the exact SHA-256 and dimensions the validator reported' {
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name 'final-certification-result' -Path $path
        $expected = New-ExpectedV1 -Identifier 'final-certification-result'
        $r = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1 -Width 42 -Height 24)
        $r.FileSha256 | Should -Be (Get-TPMSha256HexV1 -Bytes $validPngBytes)
        $r.Width | Should -Be 42
        $r.Height | Should -Be 24
    }

    It 'converts an EvidenceType mismatch (legacy type disagrees with Expected) without rejecting it itself -- composed with the real authority, this is rejected as EVIDENCE_TYPE_INVALID' {
        $expected = (Get-TPMEvidenceManifestV1)[0]
        $expected.EvidenceType | Should -Be 'ScreenCapture'
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name $expected.Identifier -Path $path -EvidenceType 'DeterministicRender' -CaptureScope 'Deterministic'
        $record = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $record.EvidenceType | Should -Be 'DeterministicRender'
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        { & $authority RecordEvidence $record } | Should -Throw '*EVIDENCE_TYPE_INVALID*'
    }

    It 'converts an invalid raw CaptureScope value without rejecting it itself -- composed with the real authority, this is rejected as EVIDENCE_METADATA_INVALID' {
        $expected = (Get-TPMEvidenceManifestV1)[0]
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name $expected.Identifier -Path $path -EvidenceType 'ScreenCapture' -CaptureScope 'NotARealScope'
        $record = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $record.CaptureScope | Should -Be 'NotARealScope'
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        { & $authority RecordEvidence $record } | Should -Throw '*EVIDENCE_METADATA_INVALID*'
    }

    It 'converts a path outside EvidenceRoot without rejecting it itself -- composed with the real authority, this is rejected as EVIDENCE_PATH_OUTSIDE_ROOT' {
        $expected = (Get-TPMEvidenceManifestV1)[0]
        $outsideRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '-outside')
        New-Item -ItemType Directory -Path $outsideRoot | Out-Null
        $path = New-TestPngFile $outsideRoot $validPngBytes
        $legacy = New-LegacyRecordV1 -Name $expected.Identifier -Path $path
        $record = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $record.Path | Should -Be ([IO.Path]::GetFullPath($path))
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        { & $authority RecordEvidence $record } | Should -Throw '*EVIDENCE_PATH_OUTSIDE_ROOT*'
    }

    It 'converts a path inside EvidenceRoot that the real authority genuinely accepts (positive containment proof)' {
        $expected = (Get-TPMEvidenceManifestV1)[0]
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name $expected.Identifier -Path $path
        $record = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        { & $authority RecordEvidence $record } | Should -Not -Throw
    }

    It 'converts two records pointing at the same on-disk file without rejecting it itself -- composed with the real authority, the second occurrence is rejected as EVIDENCE_PATH_DUPLICATE' {
        $path = New-TestPngFile $root $validPngBytes
        $manifest = Get-TPMEvidenceManifestV1
        $legacy1 = New-LegacyRecordV1 -Name $manifest[0].Identifier -Path $path -EvidenceType $manifest[0].EvidenceType
        $legacy2 = New-LegacyRecordV1 -Name $manifest[1].Identifier -Path $path -EvidenceType $manifest[1].EvidenceType
        $record1 = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy1 -Expected $manifest[0] -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $record2 = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy2 -Expected $manifest[1] -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        & $authority RecordEvidence $record1
        { & $authority RecordEvidence $record2 } | Should -Throw '*EVIDENCE_PATH_DUPLICATE*'
    }

    It 'a file changed on disk after the adapter hashed it is rejected by the real authority as EVIDENCE_HASH_FAILED (TOCTOU protection lives at the authority, not the adapter)' {
        $expected = (Get-TPMEvidenceManifestV1)[0]
        $path = New-TestPngFile $root $validPngBytes
        $legacy = New-LegacyRecordV1 -Name $expected.Identifier -Path $path
        $record = New-TPMProductionEvidenceRecordV1 -LegacyRecord $legacy -Expected $expected -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        [IO.File]::WriteAllBytes($path, [byte[]](137, 80, 78, 71, 13, 10, 26, 10, 99, 99, 99, 99, 99))
        $authority = New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $root -PngValidator (New-ValidatorV1)
        { & $authority RecordEvidence $record } | Should -Throw '*EVIDENCE_HASH_FAILED*'
    }
}
