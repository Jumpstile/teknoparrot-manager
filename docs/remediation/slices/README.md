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
4. ReShade.Core / ownership, accounting, and authorized ten-effect selection: IDs 1, 9-12.
5. SupportPackage.Core: IDs 27-29.
6. ControlsReadiness.Core: ID 30.
7. PostgreSQL recovery: ID 16.

Current slice: `PR-321-current-slice.md`.

The current pointer also carries bounded supplemental behavior contracts for Library Health transaction outcomes, owner-status gate semantics, and the authorized ReShade ten-effect selector. See `PR-321-current-slice.md` for exact owner, procedure, test, and runtime-proof mappings.

Issue #351's required-patch integration is tracked separately in
`TPM-REQUIRED-PATCHES-REVIEW-001.md`; its source/test evidence does not change
PR #321 owner-report status or imply owner-runtime acceptance. The current
Main-component, SB3 FMOD, and Infinity Blade FX additions are mapped by
`TPM-REQUIRED-PATCHES-MAIN-COMPONENTS-001`,
`TPM-REQUIRED-PATCHES-SB3-FMOD-001`, and
`TPM-REQUIRED-PATCHES-INFINITYBLADEFX-001`, with paired inventories under
`docs/remediation/inventories/`.

The isolated Cross Raid receipt-composition correctness fix is mapped by
`TPM-CROSSRAID-COMPOSITION-001` and
`TPM-CROSSRAID-COMPOSITION-INVARIANTS-001`. It changes receipt validation only;
the separately held Cross Raid base-shader recipe remains outside the catalog.

The separate local 61-entry follow-up adds three exact Main components
(MaiMai GreeN `freeglut.dll` and `libcurl.dll`, and the Rabbids Hollywood
operator utility), mapped by `TPM-REQUIRED-PATCH-MAIN-EXTRAS-20261015`,
its paired inventory, and corrected boundary note. This candidate does not
change the 58-entry parent checkpoint or establish owner-runtime acceptance.

Slice 0 current implementation: `TPM-RELEASE-SNAPSHOT-001`.
