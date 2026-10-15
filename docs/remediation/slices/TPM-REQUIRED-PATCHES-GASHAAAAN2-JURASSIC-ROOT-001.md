# Gashaaaan 2 Jurassic root DLL restoration slice

## 1. Slice identity
TPM-REQUIRED-PATCHES-GASHAAAAN2-JURASSIC-ROOT-001. Dedicated branch `feature/rc8-gash-jurassic-restorations-20261015`, base `89cb84217b4cc36f5fcb98f4b8305274a1d57a38`.

## 2. Authorized source and behavior
The unique full-guide record at index 478 is ProfileId `Gashaaaan2`, Main set `Gashaaaan Refill! (2009-02-24)(JPN)[Konami PC][TP]`, executable `IG2/exec_root/gasya.exe`. Existing pinned Other33 receipt establishes the unique executable member SHA256 `67BDEBF22D64E997A59423EC68A36CF234F0060B4FB32BAFBCE6E5A6C2D5FEB6`.

The guide requires DLLs from Jurassic Park copied to `IG2/exec_root`. The unique guide profile `JurassicPark` identifies `Jurassic Park (1.08)(2015)[Raw Thrills Linux PC][TP]`; the cached `jurassic_sound_dll.zip` alias maps to that same canonical 1.08 set. Root authorized this exact source variant and these three root DLL members.

The candidate fragment contains exactly three per-file `CreateFile` operations: `libogg.dll`, `libvorbis.dll`, and `libvorbisfile.dll`, each sourced from the unique same-named Main member, each with `BeforeState: Absent` and exact size/SHA1/SHA256 identities in the inventory. Existing files with unknown bytes are refused by the unchanged engine; no replacement operation.

## 3. Exclusions and claims
- The initial four-file authoring boundary excluded central catalog, engine header, global census, CI, and documentation integration. Root later authorized those specific additions in this dedicated worktree only: append the three entries, update the engine catalog header pin only (no engine body change), update exact catalog census expectations and CI routing/execution for the focused fixture, and add dated status addenda to the PR-321 control board and reconciliation.
- No Walking Dead DLL, other Gashaaaan dependency, arbitrary DLL, generated payload, executable patch, configuration change, ABI assertion, gameplay claim, runtime certification, package, or download. The existing 69 catalog entries remain unchanged and ordered; the integrated candidate contains 72 entries and is untested pending root's focused gate.

## 4. Files owned in this slice
- The original four new files under this dedicated worktree: this slice contract; matching remediation inventory; fragment `tools/required-patches/fragments/gashaaaan2-jurassic-root-dlls-20261015.json`; focused test `Tests/TpmRequiredPatchGashaaaan2MainDependencies.Tests.ps1`.
- Root-authorized integration updates: append to `scripts/TpmRequiredPatchRecipes.json`; pin-only update to `scripts/TpmRequiredPatchEngine.ps1`; census/profile-ID updates to `Tests/TeknoParrot-Manager.Tests.ps1` and `Tests/TpmRequiredPatchMainExtras.Tests.ps1`; CI routing/execution in `.github/workflows/ci.yml`; and dated status addenda in `docs/remediation/PR-321-control-board.md` and `docs/remediation/PR-321-reconciliation.md`. Private raw evidence stays outside Git.


## 5. Required tests and proof
Focused five-case Pester fixture: exact three metadata/source pins; each of the three operations independently synthetic-staged, applied from absent, exact-after idempotent, and receipt-undone to absent; wrong executable and unknown existing target refusal; path-confinement and rollback/refusal behavior without mocked guards; unrelated sibling and foreign receipt identity preservation. Use exact real `Test-PathInside` and `Test-TpmNoReparsePath` helpers from the same-worktree TMNT focused test. Root executes focused tests in both supported PowerShell engines after taking ownership; this authoring task runs syntax parse only.

## 6. Procedure and evidence controls
Private source proof `Drivers-Lane/Gashaaaan2-DLL-Source-Identity-20261015.json` binds exact archive members and source index hashes. The fragment BaseCatalog SHA256 and entry count are the computed 69-entry pre-integration boundary, never a transcribed pin; the integrated candidate catalog and engine header pin identify the 72-entry candidate.

## 7. Stop condition
Freeze the slice and authorized integration files after PowerShell AST parsing reports zero errors, the focused fixture contains five cases, and final SHA256 values are captured. No Pester invocation, build, commit, or push. Root owns focused execution and integration review.
