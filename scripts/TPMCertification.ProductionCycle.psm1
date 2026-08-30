Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Reports.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Publication.psm1')
Set-StrictMode -Version 2.0

function Assert-TPMProductionIdentityGuardV1 {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$IdentityGuard,
        [Parameter(Mandatory=$true)][string]$Stage
    )
    $guardResult=@(& $IdentityGuard -Stage $Stage)
    if($guardResult.Count-ne1-or$guardResult[0]-isnot[bool]-or-not[bool]$guardResult[0]){
        throw "PRODUCTION_IDENTITY_GUARD_REJECTED: stage=$Stage"
    }
}

function Complete-TPMProductionCertificationCycleV1 {
    # Certification-only mode issues the authoritative dispatcher outcome from
    # eligibility and never enters the publication/finalization commit path.
    # Publication remains available only to an explicit caller that passes
    # -Publish.
    param(
        [Parameter(Mandatory=$true)]$Authority,
        [Parameter(Mandatory=$true)]$SealedRun,
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][scriptblock]$IdentityGuard,
        [switch]$Publish
    )

    # The authoritative production caller supplies a guard that snapshots
    # the checkout identity and throws when branch, ref, reflog, or remote
    # identity changes.
    [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'BeforeEligibility')

    $eligibility=&$Authority IssueEligibility $SealedRun

    if(-not$Publish){
        [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'BeforeFinalOutcome')
        $finalOutcome=&$Authority IssueCertificationFinalOutcome $eligibility
        [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'AfterFinalOutcome')
        $projection=New-TPMFinalOutcomeProjectionV1 -FinalOutcome $finalOutcome
        [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'AfterFinalProjection')
        return [pscustomobject]@{
            Eligibility=$eligibility
            FinalOutcomeCandidateReport=(New-TPMFinalOutcomeCandidateReportV1 -Eligibility $eligibility)
            FinalOutcomeReport=(New-TPMFinalOutcomeReportV1 -FinalOutcome $finalOutcome -CertificationOnly)
            PublicationCandidate=$null
            Manifest=$null
            Marker=$null
            Commit=[pscustomobject]@{Committed=$false;Skipped=$true;FailureCode='CERTIFICATION_ONLY';FailureMessage='publication is not part of certification-only execution';DestinationDirectory=$null}
            PublicationOutcome=$null
            FinalOutcome=$finalOutcome
            Projection=$projection
        }
    }

    $candidate=&$Authority IssuePublicationCandidate $eligibility
    $finalOutcomeCandidateReport=New-TPMFinalOutcomeCandidateReportV1 -Eligibility $eligibility
    $eligibilityReport=New-TPMEligibilityReportV1 -Eligibility $eligibility
    $publicationReport=New-TPMPublicationReportV1 -PublicationCandidate $candidate
    $scorecardReport=New-TPMScorecardReportV1 -Eligibility $eligibility
    $validationReport=New-TPMValidationReportV1 -SealedRun $SealedRun -Eligibility $eligibility
    $manifest=New-TPMManifestReportV1 -Eligibility $eligibility -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport
    $marker=New-TPMCommitMarkerReportV1 -Manifest $manifest

    # Explicit publication/finalization path begins here.

    [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'BeforePublicationCommit')
    $commit=New-TPMPublicationCommitV1 -StagingParentRoot $StagingParentRoot -DestinationRoot $DestinationRoot -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport -Manifest $manifest -Marker $marker

    # Step 4: attempt publication and register the real publication
    # observation through the dispatcher -- ManifestSha256/ArtifactSetSha256
    # come from the actual commit result, never a placeholder.
    #
    # Post-commit exception safety: once $commit.Committed is true, a
    # durable, marker-complete bundle already exists on disk at
    # $commit.DestinationDirectory. RegisterCommittedPublication and
    # IssueFinalOutcome (step 5) are pure in-memory dispatcher operations
    # that should never throw when called with correct arguments in the
    # correct phase -- but this function must not ASSUME that; if either
    # one throws for any reason (a future dispatcher change, an unexpected
    # edge case, a bug), a committed bundle would otherwise sit on disk
    # looking authoritative with no genuine TPMFinalOutcomeV1 ever having
    # been issued for it, violating "no authoritative committed bundle
    # without a genuine dispatcher-issued final outcome." The try/catch
    # below exists ONLY to close that window: on any exception after a
    # successful commit, it rolls back the just-published bundle
    # (Remove-TPMPublicationCommitV1 removes the commit marker FIRST, so
    # the durable "committed" signal is broken immediately even if the
    # rest of the cleanup only partially succeeds) and re-throws an
    # honestly-worded exception distinguishing full rollback from a
    # rollback that itself did not fully succeed -- it never reports
    # "nothing published" when that cannot be proven true, and it never
    # fabricates a certification result in place of the missing final
    # outcome.
    if($commit.Committed){
        $observation=[ordered]@{ManifestSha256=$commit.ManifestSha256;ArtifactSetSha256=$commit.ArtifactSetSha256;DiagnosticWarnings=@($commit.DiagnosticWarnings)}
        try{
            [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'AfterPublicationCommit')
            $publicationOutcome=&$Authority RegisterCommittedPublication $observation $candidate
            $finalOutcome=&$Authority IssueFinalOutcome $eligibility $publicationOutcome
            [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'AfterFinalOutcome')
            $projection=New-TPMFinalOutcomeProjectionV1 -FinalOutcome $finalOutcome
            [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'AfterFinalProjection')
        }catch{
            $originalMessage=$_.Exception.Message
            try{
                $rollback=Remove-TPMPublicationCommitV1 -DestinationDirectory $commit.DestinationDirectory -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport -Manifest $manifest -Marker $marker
            }catch{
                throw "POST_COMMIT_ROLLBACK_FAILED: certification finalization failed after publication ($originalMessage); the rollback attempt itself threw an exception ($($_.Exception.Message)) -- the bundle at $($commit.DestinationDirectory) may still be present and requires manual verification."
            }
            if($rollback.FullyRolledBack){
                throw "POST_COMMIT_ROLLBACK_SUCCEEDED: certification finalization failed after publication ($originalMessage); the just-published bundle at $($commit.DestinationDirectory) was fully rolled back (commit marker removed) -- no authoritative bundle remains for this run."
            }else{
                throw "POST_COMMIT_ROLLBACK_FAILED: certification finalization failed after publication ($originalMessage); rollback of the just-published bundle at $($commit.DestinationDirectory) did not fully succeed (MarkerRemoved=$($rollback.MarkerRemoved); remaining files: $($rollback.RemainingFiles -join ', '); errors: $($rollback.Errors -join '; ')) -- this directory may still contain an authoritative-looking bundle and requires manual verification."
            }
        }
    }else{
        $message=if([string]::IsNullOrWhiteSpace([string]$commit.FailureMessage)){'publication did not complete'}else{[string]$commit.FailureMessage}
        $reasons=@([ordered]@{Code=[string]$commit.FailureCode;Message=$message})
        $publicationOutcome=&$Authority RegisterPublicationFailure $reasons $candidate

        # Step 5: issue the genuine TPMFinalOutcomeV1 only now that the
        # dispatcher has issued TPMPublicationOutcomeV1 -- the dispatcher's
        # own phase machine enforces this ordering (IssueFinalOutcome
        # requires phase PublicationIssued, reachable only from Register*
        # above). Nothing was committed in this branch, so an exception
        # here needs no rollback -- "no authoritative bundle" is already
        # true and stays true.
        $finalOutcome=&$Authority IssueFinalOutcome $eligibility $publicationOutcome
        [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'AfterFinalOutcome')
        $projection=New-TPMFinalOutcomeProjectionV1 -FinalOutcome $finalOutcome
        [void](Assert-TPMProductionIdentityGuardV1 -IdentityGuard $IdentityGuard -Stage 'AfterFinalProjection')
    }

    # Step 6: only this genuine final outcome drives runtime console status,
    # exit code, and final projection -- never the Section 8.3 candidate. The
    # final guard is inside the same post-commit rollback boundary, so any
    # identity mutation observed during publication or finalization cannot
    # leave a durable authoritative-looking bundle behind.

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
