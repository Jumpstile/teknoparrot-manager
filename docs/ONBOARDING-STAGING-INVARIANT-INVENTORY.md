# Onboarding Staging Invariant Inventory (#217/#250)

Status: Implemented on the focused onboarding branch after the dual-engine
focused matrix passed. Scope is limited to safe staging-folder defaults and
proactive invalid-path prevention.

## Governing boundaries

- The staging folder is the game installation destination for AutoSync.
- The original main and supplementary ZIP collections remain source locations.
- The TPM program/package directory and the TeknoParrot installation are
  protected from extraction.
- The prompt and validator are read-only. A missing staging folder is created
  only after a real AutoSync run is selected, never during Preview/Dry Run.
- This inventory does not cover TeknoParrot first-run coordination (#253),
  dependency diagnostics (#254), Eggman data ownership (#252), or the reported
  recovery crash (#251).

## Invariants

| ID | Invariant | Implementation pointer | Verification pointer | Status |
|----|-----------|------------------------|----------------------|--------|
| STG-001 | A new user receives an environment-derived staging recommendation without a hardcoded drive letter. Enter accepts it; B permits an alternate choice. | Get-TpmSafeStagingFolderDefault; Read-TpmStagingFolder; first-run AutoSync prompt in TeknoParrot-Manager.ps1 | Issue #217/#250 safe staging selection: default-selection and Enter tests; PS5.1 and PS7 | Implemented |
| STG-002 | A staging candidate is canonicalized and rejected when it is a file or overlaps the TeknoParrot installation, main ZIP source, supplementary ZIP source, or TPM program/package directory in either direction. | Test-TpmPathOverlap; Test-TpmStagingFolderCandidate; AutoSync boundary validation and recovery in TeknoParrot-Manager.ps1 | Table-driven exact/child/parent matrix for all four protected locations; invalid browser recovery test; PS5.1 and PS7 | Implemented |
| STG-003 | A missing staging directory is created only after the preview decision and only for a real AutoSync run. | AutoSync staging creation block after dryRunActive is resolved in TeknoParrot-Manager.ps1 | No-create candidate test; source-order assertion; PS5.1 and PS7 | Implemented |
| STG-004 | Preview/Dry Run and path-prompt validation do not create, move, delete, or persist a staging directory; an accepted real-run path is persisted only after validation. | Read-TpmStagingFolder and delayed AutoSync creation/configuration flow in TeknoParrot-Manager.ps1 | Enter/B prompt tests and creation-order assertion; full Pester | Implemented |

## Failure handling

If a typed or browsed candidate fails validation, TPM reports the reason and
keeps the user in the staging-choice flow. If the saved path fails the later
source-aware AutoSync boundary check, recovery returns to the same derived
recommendation and validator. Unattended mode returns to the menu instead of
accepting an unsafe path.

## Out of scope

This focused pass does not configure or mark TeknoParrot first-run state,
probe runtime executables, relocate Eggman recognition data, or change
TeknoParrot files/settings.
