# TPM Subsystem Extraction Roadmap

This roadmap reduces the risk of `TeknoParrot-Manager.ps1` without destabilizing RC8. Each extraction is a separate contract-first slice with characterization tests, compatibility proof, exact source identity, and rollback conditions.

## Phase 0 - contract and gate stabilization

Current work. Establish the operating model, control board, slice contracts, provenance ledger, UX/behavior contracts, and fail-closed procedure gate. No broad extraction.

## Phase 1 - pure helper modules

- `TPM.Prompt.Core.psm1`: extract Read-TpmChoice, Read-TpmYesNo, and workflow input after a complete prompt inventory. Risk: interaction regressions. Stop if any caller loses invalid-input, Back, or exact-token semantics.
- `TPM.Progress.Core.psm1`: extract compact progress and workflow status helpers. Risk: output width/redirected-console regressions. Stop if any long-running path loses bounded status.
- `TPM.Download.Core.psm1`: extract download/request wrappers. Risk: error policy, fallback, cleanup, and path safety. Stop if backup/download failures change semantics.

## Phase 2 - evidence/reporting modules

- `TPM.SupportPackage.Core.psm1`: extract manifest and package collection after SupportPackage.Tests cover fatal, newest Action Required, and stale labeling.
- `TPM.ControlsReadiness.Core.psm1`: extract result accounting only after zero/mixed/failure truthfulness contracts are complete. No physical readiness claim may be introduced.

## Phase 3 - workflow modules

- `TPM.Repair.Core.psm1`: extract affected-game collection and repair handoff after one/multiple/zero/no-candidate tests.
- `TPM.FrontendExport.Core.psm1`: extract LaunchBox and HyperSpin export after prompt and output-accounting contracts.
- `TPM.PostgreSQL.Core.psm1`: extract setup/recovery only after backup, retry, exact confirmation, and rollback tests.

## Phase 4 - high-risk feature modules

- `TPM.ReShade.Core.psm1`: ownership, preview, and all-games accounting; highest file-safety risk.
- `TPM.Crosshair.Core.psm1`: browser lifecycle and focus; requires constrained-terminal evidence.
- `TPM.GpuFix.Core.psm1`: GPU detection and repair workflow.
- `TPM.DgVoodoo2.Core.psm1`: detection, download, deployment, and result reporting.
- `TPM.BepInEx.Core.psm1`: package/version/deployment workflow.
- `TPM.FFB.Core.psm1`: network, overlap selection, ownership, and deployment.

## Preconditions and stop rules

Before any extraction: current slice contract, owner-board mapping, focused characterization tests, source/package/runtime provenance, and a reversible integration seam. Stop on changed user-visible prompts, changed mutation scope, changed error semantics, or any test that only passes because assertions were weakened.

No module is extracted in the organization/reset slice.
