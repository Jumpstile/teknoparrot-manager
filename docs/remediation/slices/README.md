# TPM Remediation Slices

Every product remediation slice requires a contract based on `docs/templates/tpm-slice-contract.md`, a control-board mapping, focused tests, a stop condition, and a permanent-gate result.

## Rules

- One bounded subsystem or owner-report group per slice.
- Explicit exclusions are mandatory.
- Source, package, and runtime evidence remain separate.
- Do not call an owner report fixed without behavior proof.
- No slice may silently widen scope.

## Priority queue

1. Prompt.Core / global prompt consistency: IDs 24, 25, 26, 27, part of 32.
2. Progress.Core / universal progress completion: IDs 3, 4, 5, 6, part of 32.
3. Repair.Core / affected-games repair: IDs 17-22.
4. ReShade.Core / ownership and accounting: IDs 1, 9-12.
5. SupportPackage.Core: IDs 27-29.
6. ControlsReadiness.Core: ID 30.
7. PostgreSQL recovery: ID 16.

Current slice: `PR-321-current-slice.md`.
