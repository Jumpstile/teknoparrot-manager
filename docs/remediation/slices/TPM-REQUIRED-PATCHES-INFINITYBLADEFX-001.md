# Infinity Blade FX Main-component restoration slice contract

## 1. Slice name

- Name: exact Main-source absent-only restorations for Infinity Blade FX 1.02
- Contract ID: `TPM-REQUIRED-PATCHES-INFINITYBLADEFX-001`
- Issue/PR: Issue #351; no numbered PR #321 owner row is assigned.
- Staging base: `3c93d383f0a8091bf5d6890acb176c285816a82f`; staging branch `review/rc8-expanded54-20261015`.
- Current staging aggregate: 58 entries / 22 exact ProfileId/build/executable identities; 50 `CreateFile` / eight `ReplaceFile`. Catalog SHA-256 `F86F09A8BD2749DC9C4531CD1D00A69BF07D85B14A8D281D33767732ED5B720A`; engine SHA-256 `7AFAE497F5EFED0BE5F94497D4A7A5C25C073743485B700A7498B1A34681F6E4` (catalog pin only). This slice contributes two `CreateFile` entries.

## 2. Owner report IDs included

- IDs: Issue #351 owner-authorized request for the two source-backed Main-component restorations. No numbered PR #321 owner report ID is assigned.
- Exact failure: the exact Infinity Blade FX 1.02 Main build may lack `Binaries/Win32/matrix32.dll` and/or `Binaries/Win32/dinput8.dll`; the recipe restores only those missing files. This is not a reproduced gameplay failure.

## 3. Explicit exclusions

- No other game/profile, driver, loader, patcher, configuration change, automatic rename, arbitrary installation path, source download, release/package action, runtime install, game launch, or DLL/payload execution.
- No replacement of `matrix32.dll`, `dinput8.dll`, `matrix32.TEKNOPARROT.dll`, or `TPFIX.ini`.
- The two file-presence prerequisites do not validate file identity, version, TPFIX contents, DLL pairing, or the user's separate first-launch path selection. The authored first-launch step selects the TeknoParrot installation's `TeknoParrot.dll`.
- The two restorations are independent single-file operations, not an atomic pair and not proof of complete installation, compatibility, or gameplay.

## 4. Behavior contract

- Current failure: the current catalog lacks exact absent-only recipes for the two known Main members.
- Expected behavior: add one `CreateFile` recipe per target, bound to profile `InfinityBladeFX`, build `Infinity Blade FX (1.02)(2020)[Adrenaline PC][TP]`, executable `Binaries/Win32/SwordGame.exe` with SHA-256 `8E605C3748C6D3D45832F40316C1FEC35D2507E31E51A5F85DCB3B664DA72D24`, and the exact Main ZIP member size/SHA-1/SHA-256. Each operation requires an absent target, creates only its exact target, treats exact after-state as a no-op, refuses other present states, and retains receipt/object-identity undo guards.
- Prerequisites are presence-only checks for `Binaries/Win32/matrix32.TEKNOPARROT.dll` and `Binaries/Win32/TPFIX.ini`. The recipe does not inspect their bytes or configuration.
- Forbidden regressions: no overwrite, no automatic parent-directory creation, no broad or inferred hardware predicate, no executable self-patch opt-in, no weakening of path/hash/backup/receipt guards, and no claim of full setup or gameplay readiness.

## 5. Source/function ownership

- Files: the required-patch catalog and SHA-256 pin, central catalog assertions, exact fragment and focused test, CI path list, current user/architecture documentation, and this slice/report/inventory.
- Accepted fragment: `tools/required-patches/fragments/support-infinitybladefx-main-components-20261015.json`, SHA-256 `45AA403A5DB320CD31292EC6CA5F0A9F7AB9A6DABC96F76147CEA13E86FB1472`.
- Accepted focused suite: `Tests/TpmRequiredPatchInfinityBladeFxLane.Tests.ps1`, SHA-256 `E9C7C4095B3170A9C2851A37C4D5BB297EE5B83C608E60A556098872999B880F`.
- Engine boundary: catalog SHA-256 pin only; no engine behavior change.
- Owning subsystem: Issue #351 required-patch catalog; no installer or loader framework.

## 6. Tests required before implementation

- Root-accepted exact Main source proof for the two fragment rows; source artifacts and private provenance remain outside the repository.
- Preserve the accepted fragment/test bytes; do not regenerate or broaden their source facts.

## 7. Tests required after implementation

- Run the standalone two-case suite under explicit Pester 5.7.1 on PowerShell 7 and Windows PowerShell 5.1 against the integrated catalog.
- Run the central 58-entry count/pin/ID assertion and verify 22 identities, 50 `CreateFile` operations, and eight `ReplaceFile` operations.
- Run bounded JSON/catalog import, PowerShell parse/ASCII/privacy, catalog line-ending/blob-pin, and engine-pin-only checks. Root owns the later full canonical gate.
- The Infinity suite asserts metadata and synthetic prerequisite/lifecycle behavior; it does not exercise ZIP payload staging. Do not describe it as a staging test.

## 8. Documentation/report updates required

- Control board and reconciliation: record the 58-entry staging checkpoint and exact focused receipts; preserve the historical frozen24 and prior56 checkpoints.
- User/architecture docs: distinguish two absent-only component restorations from the separate first-run path selection and any full setup procedure.
- Hunk mapping: the two catalog rows, catalog count/ID assertions, CI inclusion, docs, slice, and inventory map to Issue #351 / this contract / `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, and `TPM-OWNER-003`; user wording also maps to `TPM-UX-001` and `TPM-UX-002`.
- Changelog describes the current RC8 candidate only; no release version, tag, or publication is authorized.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map every integration hunk to Issue #351, this contract, and the relevant procedure.
- `TPM-EVIDENCE-001`: verify exact metadata and focused synthetic lifecycle behavior.
- `TPM-TRUTH-001`, `TPM-OWNER-001`, `TPM-OWNER-002`, `TPM-OWNER-003`: keep source/test evidence distinct from owner runtime, configuration, compatibility, and readiness.
- `TPM-UX-001`, `TPM-UX-002`: keep user-facing absent-component and limitation wording accurate.
- `TPM-AUTH-001`: this staging lane did not commit, push, package, tag, release, update the live wiki, or run owner runtime. Root owns final gates and may commit/push a scoped review PR after gates; this does not authorize release, tag, main merge, or runtime activity.

## 10. Runtime smoke checklist

- Exact packaged behavior: owner must validate the exact supported game build after optional absent-only restoration.
- Required source/package identity: the exact executable, local Main ZIP name, and two recipe member pins.
- Required separate setup evidence: verify the authored preservation of the original `matrix32.dll` as `matrix32.TEKNOPARROT.dll`, the presence/appropriateness of `TPFIX.ini`, and the first-launch selection of the TeknoParrot installation's `TeknoParrot.dll`; this recipe performs none of those setup actions.
- Evidence artifacts: owner-run receipt, installed target readback, setup-state record, and any visual/gameplay observations.
- Owner/runtime authorization: pending; this staging work executes no game or payload.

## 11. Stop condition

Stop after the two entries are integrated into the authorized staging tree, focused tests pass, documentation and mappings are synchronized, and the staging diff is reviewable. Owner runtime, release, and merge gates remain separate.

## 12. Forbidden actions

This staging lane does not run the full canonical suite or commit, push, merge, package, tag, release, live wiki update, arbitrary installation mutation, or owner-runtime test. Root owns final quality gates and may commit/push a scoped review PR after gates. Release/tag/main-merge and owner-runtime authorization remain separate.

## 13. Commit/package authorization status

- This staging lane may not commit or publish; root may authorize source commit/push/scoped review PR after final gates.
- Package authorized: No.
- Release/certification authorized: No.
