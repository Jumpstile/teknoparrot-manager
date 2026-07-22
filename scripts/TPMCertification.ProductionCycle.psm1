Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Reports.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Publication.psm1')
Set-StrictMode -Version 2.0

function Complete-TPMProductionCertificationCycleV1 {
    # Safety invariant (ADR-0155 Section 8.3 vs Section 9): the Section 8.3
    # candidate final-outcome report and the Section 9 dispatcher-issued
    # TPMFinalOutcomeV1 can diverge only when EligibleForCertification=true
    # and the publication attempt does not commit. In every other case their
    # FinalStatus/ExitCode agree, because the candidate's own derivation
    # (EligibleForCertification alone) and the dispatcher's real derivation
    # (EligibleForCertification AND PublicationCommitted) reduce to the same
    # value whenever EligibleForCertification is false, and coincide by
    # definition once PublicationCommitted is true. In the one divergent
    # case, the published bundle is never durably committed -- no valid
    # commit marker exists at the destination -- so per Section 8.2/8.3 the
    # candidate-bearing bundle is non-authoritative and must be ignored by
    # any consumer. This function never lets the candidate drive runtime
    # certification: it is used only while constructing and staging the
    # five-artifact bundle and manifest (steps 2-3 below); the returned
    # Projection is derived exclusively from the genuine, dispatcher-issued
    # TPMFinalOutcomeV1 issued after publication is registered (steps 4-6).
    param(
        [Parameter(Mandatory=$true)]$Authority,
        [Parameter(Mandatory=$true)]$SealedRun,
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot
    )

    # Step 1: issue eligibility through the workflow authority.
    $eligibility=&$Authority IssueEligibility $SealedRun

    # Step 2: build the Section 8.3 candidate final-outcome report from that
    # issued eligibility -- available before any publication attempt exists.
    $finalOutcomeCandidateReport=New-TPMFinalOutcomeCandidateReportV1 -Eligibility $eligibility

    $candidate=&$Authority IssuePublicationCandidate $eligibility

    # Step 3: use the candidate only while constructing and staging the
    # five-artifact publication bundle and manifest.
    $eligibilityReport=New-TPMEligibilityReportV1 -Eligibility $eligibility
    $publicationReport=New-TPMPublicationReportV1 -PublicationCandidate $candidate
    $scorecardReport=New-TPMScorecardReportV1 -Eligibility $eligibility
    $validationReport=New-TPMValidationReportV1 -SealedRun $SealedRun -Eligibility $eligibility
    $manifest=New-TPMManifestReportV1 -Eligibility $eligibility -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport
    $marker=New-TPMCommitMarkerReportV1 -Manifest $manifest

    $commit=New-TPMPublicationCommitV1 -StagingParentRoot $StagingParentRoot -DestinationRoot $DestinationRoot -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport -Manifest $manifest -Marker $marker

    # Step 4: attempt publication and register the real publication
    # observation through the dispatcher -- ManifestSha256/ArtifactSetSha256
    # come from the actual commit result, never a placeholder.
    if($commit.Committed){
        $observation=[ordered]@{ManifestSha256=$commit.ManifestSha256;ArtifactSetSha256=$commit.ArtifactSetSha256;DiagnosticWarnings=@($commit.DiagnosticWarnings)}
        $publicationOutcome=&$Authority RegisterCommittedPublication $observation $candidate
    }else{
        $message=if([string]::IsNullOrWhiteSpace([string]$commit.FailureMessage)){'publication did not complete'}else{[string]$commit.FailureMessage}
        $reasons=@([ordered]@{Code=[string]$commit.FailureCode;Message=$message})
        $publicationOutcome=&$Authority RegisterPublicationFailure $reasons $candidate
    }

    # Step 5: issue the genuine TPMFinalOutcomeV1 only now that the
    # dispatcher has issued TPMPublicationOutcomeV1 -- the dispatcher's own
    # phase machine enforces this ordering (IssueFinalOutcome requires phase
    # PublicationIssued, reachable only from Register* above).
    $finalOutcome=&$Authority IssueFinalOutcome $eligibility $publicationOutcome

    # Step 6: only this genuine final outcome drives runtime console status,
    # exit code, and final projection -- never the Section 8.3 candidate.
    $projection=New-TPMFinalOutcomeProjectionV1 -FinalOutcome $finalOutcome

    return [pscustomobject]@{
        Eligibility=$eligibility
        FinalOutcomeCandidateReport=$finalOutcomeCandidateReport
        PublicationCandidate=$candidate
        Manifest=$manifest
        Marker=$marker
        Commit=$commit
        PublicationOutcome=$publicationOutcome
        FinalOutcome=$finalOutcome
        Projection=$projection
    }
}

Export-ModuleMember -Function Complete-TPMProductionCertificationCycleV1
