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
at the composition-fix checkpoint, the separate Cross Raid base-shader recipe
was held outside the catalog; the mapped 62nd-entry slice below supersedes
that status.

The historical local 61-entry checkpoint added three exact Main components
(MaiMai GreeN `freeglut.dll` and `libcurl.dll`, and the Rabbids Hollywood
operator utility), mapped by `TPM-REQUIRED-PATCH-MAIN-EXTRAS-20261015`,
its paired inventory, and corrected boundary note. This candidate does not
change the 58-entry parent checkpoint or establish owner-runtime acceptance.

The separate Cross Raid 1.05 Ver A Main base-shader restoration is mapped by
`TPM-REQUIRED-PATCH-CROSSRAID-BASE-001` and
`TPM-REQUIRED-PATCH-CROSSRAID-BASE-INVENTORY-001`. Its single absent-only Main
entry and portable suite are in the isolated 62-entry candidate; the suite
passed 7/7 under both engines and the central identity case passed 1/1 under
both. Root review and combined gates remain pending. It does not adjudicate
Black Textures, gameplay, or setup completeness.

The separate TMNT 1.59 native Main-component candidate is mapped by
`TPM-REQUIRED-PATCH-TMNT-NATIVE-MAIN-COMPONENTS-001` and its paired inventory.
It covers two independent absent-only repairs; no compatibility or setup claim
is implied.

The user release-package cleanliness and PCSx2x6 source/runtime evidence
boundary are mapped separately in
`TPM-RELEASE-PACKAGE-CLEANLINESS-001`, with
`docs/remediation/inventories/TPM-RELEASE-PACKAGE-ALLOWLIST-001.md`.
Parent-owned Expanded61 ZIP inspection remains outside this local fixture
lane.

Slice 0 current implementation: `TPM-RELEASE-SNAPSHOT-001`.
