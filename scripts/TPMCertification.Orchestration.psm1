Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Production.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Reports.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Publication.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Shadow.psm1')
Set-StrictMode -Version 2.0

function Invoke-TPMProductionCertificationV1 {
    # ADR-0155 Phase 3 (ADR155-0309): the single authoritative entry point a
    # real certification harness calls. Runs the full pipeline -- record,
    # seal, issue eligibility, build the Section 8.3 candidate bundle, stage
    # and commit real publication, register the real outcome with the
    # dispatcher, and issue the Section 9 runtime TPMFinalOutcomeV1 -- then
    # projects that (and only that) object into what the caller should show
    # on console and return as an exit code. The candidate bundle written to
    # disk is never treated as authoritative here; FinalOutcome, issued after
    # the real publication attempt is known, is the sole certification
    # authority (New-TPMFinalOutcomeProjectionV1 enforces this by construction
    # -- it only accepts a genuine dispatcher-issued TPMFinalOutcomeV1).
    #
    # Never catches exceptions from the dispatcher pipeline itself: a fact/
    # evidence/schema failure here means the authoritative pipeline could not
    # reach a decision at all, which is not a certifiable state. Callers must
    # not fall back to any other decision source on such a failure -- doing so
    # would reintroduce the "mixed authorities" ambiguity ADR Section 11
    # prohibits.
    param(
        [Parameter(Mandatory=$true)][ValidateSet('Smoke','Unattended')][string]$Mode,
        [Parameter(Mandatory=$true)]$Facts,
        [Parameter(Mandatory=$true)][string]$EvidenceRoot,
        [Parameter(Mandatory=$true)][string]$ReportRoot,
        [Parameter(Mandatory=$true)]$LegacyEvidence,
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][scriptblock]$PngValidator
    )

    $authority = New-TPMProductionWorkflowAuthorityV1 -Mode $Mode -EvidenceRoot $EvidenceRoot -ReportRoot $ReportRoot -PngValidator $PngValidator
    foreach ($fact in @($Facts)) { [void](& $authority 'RecordFact' $fact $null) }

    $legacy = @($LegacyEvidence)
    if ($legacy.Count -ne 9) { throw "EVIDENCE_MANIFEST_INCOMPLETE: expected 9 legacy evidence records, found $($legacy.Count)" }
    $evidenceManifest = Get-TPMEvidenceManifestV1
    for ($i = 0; $i -lt 8; $i++) {
        $record = ConvertTo-TPMShadowEvidenceRecordV1 $legacy[$i] $evidenceManifest[$i] $EvidenceRoot $PngValidator
        [void](& $authority 'RecordEvidence' $record $null)
    }
    $scorePreview = & $authority 'DeriveScorePreview' $null $null
    $finalEvidenceRecord = ConvertTo-TPMShadowEvidenceRecordV1 $legacy[8] $evidenceManifest[8] $EvidenceRoot $PngValidator
    [void](& $authority 'IssueFinalEvidence' $finalEvidenceRecord $scorePreview)

    $sealedRun = & $authority 'Seal' $null $null
    $eligibility = & $authority 'IssueEligibility' $sealedRun $null

    # Section 8.3 candidate bundle -- built from eligibility alone, never from
    # a dispatcher-issued FinalOutcome (none exists yet at this point in the
    # pipeline; that is the entire reason the candidate builder exists).
    $eligibilityReport = New-TPMEligibilityReportV1 -Eligibility $eligibility
    $publicationCandidate = & $authority 'IssuePublicationCandidate' $eligibility $null
    $publicationReport = New-TPMPublicationReportV1 -PublicationCandidate $publicationCandidate
    $finalOutcomeCandidateReport = New-TPMFinalOutcomeCandidateReportV1 -Eligibility $eligibility
    $scorecardReport = New-TPMScorecardReportV1 -Eligibility $eligibility
    $validationReport = New-TPMValidationReportV1 -SealedRun $sealedRun -Eligibility $eligibility
    $manifest = New-TPMManifestReportV1 -Eligibility $eligibility -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport
    $marker = New-TPMCommitMarkerReportV1 -Manifest $manifest

    $commitResult = New-TPMPublicationCommitV1 -StagingParentRoot $StagingParentRoot -DestinationRoot $DestinationRoot -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport -Manifest $manifest -Marker $marker

    if ($commitResult.Committed) {
        $observation = [ordered]@{ManifestSha256=$commitResult.ManifestSha256;ArtifactSetSha256=$commitResult.ArtifactSetSha256;DiagnosticWarnings=@($commitResult.DiagnosticWarnings)}
        $publicationOutcome = & $authority 'RegisterCommittedPublication' $observation $publicationCandidate
    } else {
        $failureCode = if ($commitResult.FailureCode) { [string]$commitResult.FailureCode } else { 'STAGING_FAILED' }
        $failureMessage = if ($commitResult.FailureMessage) { [string]$commitResult.FailureMessage } else { 'publication commit failed with no diagnostic message' }
        $reasons = @([ordered]@{Code=$failureCode;Message=$failureMessage})
        $publicationOutcome = & $authority 'RegisterPublicationFailure' $reasons $publicationCandidate
    }

    # Real, post-commit, dispatcher-issued object -- Section 9's sole
    # certification authority. Distinct from $finalOutcomeCandidateReport
    # above, which is never read again past this point.
    $finalOutcome = & $authority 'IssueFinalOutcome' $eligibility $publicationOutcome
    $projection = New-TPMFinalOutcomeProjectionV1 -FinalOutcome $finalOutcome

    return [pscustomobject]@{
        RunIdentity = & $authority 'GetRunIdentity' $null $null
        Eligibility = $eligibility
        SealedRun = $sealedRun
        PublicationCandidate = $publicationCandidate
        Manifest = $manifest
        Marker = $marker
        CommitResult = $commitResult
        PublicationOutcome = $publicationOutcome
        FinalOutcome = $finalOutcome
        Projection = $projection
    }
}

Export-ModuleMember -Function Invoke-TPMProductionCertificationV1
