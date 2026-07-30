Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Set-StrictMode -Version 2.0

# ADR-0155 Section 5.4 production evidence adapter (ADR155-0309 Checkpoint
# B2). Converts one legacy harness evidence-ledger record (the shape
# Add-Screenshot in Invoke-TPM-RealInstanceSmoke.ps1 produces: Name, Label,
# Path, Status, EvidenceType, Required, WorkflowId, CaptureScope, Details)
# into the production authority's evidence record schema (Authority.psm1's
# Assert-TPMEvidenceRecordV1: Identifier, Status, EvidenceType, Required,
# Path, CaptureScope, FileSha256, Width, Height, FailureCode, FailureMessage).
#
# This module deliberately does not import or call
# TPMCertification.Shadow.psm1 -- it is a fresh, independent implementation
# against the authoritative schema Authority.psm1 defines, not a reuse of
# Shadow's Phase 2 shadow-only adapter. Its public surface is exactly one
# function.

function New-TPMProductionEvidenceRecordV1 {
    param(
        # AllowNull is required: a legacy evidence ledger that omits an
        # identifier entirely (as opposed to issuing one with the wrong
        # name) surfaces here as a genuine $null, and this function's own
        # EVIDENCE_IDENTIFIER_INVALID branch below exists specifically to
        # turn that into a controlled Failed result -- without AllowNull,
        # PowerShell's own Mandatory-parameter binding rejects a $null
        # argument with a ParameterBindingValidationException before this
        # function body ever runs, and that branch can never execute.
        [Parameter(Mandatory=$true)][AllowNull()]$LegacyRecord,
        [Parameter(Mandatory=$true)]$Expected,
        [Parameter(Mandatory=$true)][string]$EvidenceRoot,
        [Parameter(Mandatory=$true)][scriptblock]$PngValidator
    )
    $identifier=[string]$Expected.Identifier
    if($null-eq$LegacyRecord){
        return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_IDENTIFIER_INVALID';FailureMessage='harness did not issue this evidence identifier'}
    }
    $name=if($LegacyRecord.PSObject.Properties.Name-contains'Name'){[string]$LegacyRecord.Name}else{''}
    if($name-cne$identifier){
        return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_ORDER_INVALID';FailureMessage=("harness evidence at this position was '{0}'"-f$name)}
    }
    $status=[string]$LegacyRecord.Status
    if($status-ceq'Skipped'){
        return [ordered]@{Identifier=$identifier;Status='Skipped';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_SKIPPED';FailureMessage=$(if($LegacyRecord.Details){[string]$LegacyRecord.Details}else{'harness skipped this optional evidence'})}
    }
    if($status-cne'Captured'){
        return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_CAPTURE_EXCEPTION';FailureMessage=$(if($LegacyRecord.Details){[string]$LegacyRecord.Details}else{"harness evidence status was '$status'"})}
    }
    $path=[IO.Path]::GetFullPath([string]$LegacyRecord.Path)
    $validation=try{&$PngValidator $path}catch{$null}
    if(-not$validation-or-not$validation.Valid){
        $reason=if($validation-and$validation.Reason){[string]$validation.Reason}else{'PNG validation failed'}
        return [ordered]@{Identifier=$identifier;Status='Failed';EvidenceType=$null;Required=[bool]$Expected.Required;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_PNG_INVALID';FailureMessage=$reason}
    }
    $bytes=[IO.File]::ReadAllBytes($path)
    $legacyType=[string]$LegacyRecord.EvidenceType
    $scope=if($legacyType-ceq'DeterministicRender'){'Deterministic'}elseif([string]$LegacyRecord.CaptureScope-ceq'Window'){'ConsoleWindow'}else{[string]$LegacyRecord.CaptureScope}
    return [ordered]@{Identifier=$identifier;Status='Captured';EvidenceType=$legacyType;Required=[bool]$Expected.Required;Path=$path;CaptureScope=$scope;FileSha256=(Get-TPMSha256HexV1 -Bytes $bytes);Width=[int]$validation.Width;Height=[int]$validation.Height;FailureCode=$null;FailureMessage=$null}
}

Export-ModuleMember -Function New-TPMProductionEvidenceRecordV1
