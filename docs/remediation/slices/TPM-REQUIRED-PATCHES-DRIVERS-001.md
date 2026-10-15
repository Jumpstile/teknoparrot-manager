# TPM Remediation Slice Contract

## 1. Slice name

- Name: Taisen Hot Gimmick 5 TTX/JVS component restoration
- Contract ID: `TPM-REQUIRED-PATCHES-DRIVERS-001`
- Issue/PR: Issue #351; follow-up to PR #353 candidate `046a114`

## 2. Owner report IDs included

- IDs: `DRIVERS-LANE-RC8`
- Exact owner-visible failures: the cached full guide names a TTX-Monitor+ JVS-to-keyboard setup for the exact Taisen Hot Gimmick 5 2.04 build; the required TTX files are not represented by the existing recipe catalog.

## 3. Explicit exclusions

- Owner IDs not included: all non-driver family reports; Dragon Dance and Primevil are held in the driver lane inventory and are not enabled here.
- Features, modules, package, runtime, and release actions excluded: no keyboard configuration, generated `monitor_input.bin` or `monitor_misc.bin`, loader invocation, DirectInput deployment, game launch, gameplay, live install, owner smoke, package rebuild, or release.

## 4. Behavior contract

- Current failure: the exact-guide Taisen build has no recipes for its three bundled TTX files.
- Expected behavior: separate schema-3 `CreateFile` recipes may create only an absent `TTX-Monitor.dll`, `TTX-Config.exe`, or `TTX-Loader.exe`, bound to profile `TaisenHotGimmick5`, Main build `Taisen Hot Gimmick 5 - Mirai Eigou (2.04)(2005-12-08)(JPN)[Taito Type X][TP]`, and executable SHA-256 `144875cc9d0dc66887cd6292dcb949c0575afb654b0da8bf173fef7047c7d86a`.
- Payload identities: `TTX-Monitor.dll` SHA-256 `a706a9dbebb3e6d4511d47341d4a46d1f9965874adba4354a127797855fdfa44`; `TTX-Config.exe` SHA-256 `f6979167410af3c6ece2420e15205c54eb86663b74c27aa2e1cd05287efb8b64`; `TTX-Loader.exe` SHA-256 `2e270dde1ff0f86326a4bfcc84eb359a0231118dc03d9130526750e3d175ca3c`.
- Forbidden regressions: do not overwrite any existing target; exact-after is idempotent; unknown existing bytes refuse; receipt-bound undo removes only an unchanged created file; keep the three target paths isolated and never alter user key configuration.
- Design boundaries and deliberate exclusions: these recipes restore bundled files only. The operator still configures keys with TTX-Config and runs the loader; no gameplay claim follows from file identity or synthetic engine tests.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchRecipes.json`; `Tests/TeknoParrot-Manager.Tests.ps1`; `docs/remediation/recipe-lanes/drivers/*`; this contract; the PR #321 control board and reconciliation addenda.
- Functions/regions: existing catalog loader, planner, apply and receipt-undo paths; no production engine function changes.
- Owning subsystem: schema-3 required-patch catalog and its existing transaction engine.

## 6. Tests required before implementation

- Focused failing or characterization tests: the frozen driver lane test exercises the fragment with exact Main members and synthetic apply/skip/undo/wrong-executable/unknown-state/tamper refusal under both PowerShell engines; receipts are recorded separately in the owner evidence store.
- Source/inventory checks: compare all six frozen lane files against `DRIVER-LANE-FILES.sha256`; confirm three unique IDs, exact Main executable/member pins, absent-only operations, and no collision with the 13-entry catalog.

## 7. Tests required after implementation

- Focused behavior tests: run the existing `restores only absent exact single-file recipes with skip, receipt undo/reapply, wrong-executable and unknown-state refusal` Pester case under PowerShell 7 and Windows PowerShell 5.1 with Pester 5.7.1; it must cover all three new IDs in distinct game roots.
- Regression suite: the full Main/Support and canonical integration gates are required once the complete recipe expansion snapshot is frozen; do not rerun them for this isolated lane merge.
- Static and procedure gates: parse the changed test file under both engines, check `git diff --check`, and run the applicable permanent procedure gate after the control-board/report records are final.

## 8. Documentation/report updates required

- Control board row: add a distinct Issue #351 driver follow-up without rewriting the historical PR #353 13-entry gate record.
- Remediation report row: record three Taisen recipes, focused results, source evidence, and owner/runtime limits.
- Hunk classification: catalog entries, the existing recipe-ID test list, lane evidence files, and the two report addenda map to Issue #351 / `DRIVERS-LANE-RC8` / this contract / the procedures below.
- Changelog or user docs, if applicable: no gameplay or user-facing capability beyond these exact source restorations is claimed; sync product docs only if the final combined recipe scope changes published instructions.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: exact guide build, executable, source-member and target identity trace.
- `TPM-EVIDENCE-001`: retained source hashes, lane manifest, and focused receipts.
- `TPM-TRUTH-001`: keep owner setup/gameplay and release readiness separate from recipe availability.
- `TPM-OWNER-001`: owner install and gameplay acceptance remain pending; no runtime result is claimed.

## 10. Runtime smoke checklist

- Exact packaged behavior: not exercised in an owner package; the production engine was tested with exact source members and disposable synthetic destinations only.
- Required source/package identity: the Taisen 2.04 Main archive identity and exact member pins are recorded in `DRIVER-LANE-EVIDENCE.md`; no payload is executed or included in source control.
- Evidence artifacts: frozen lane manifest, contract, inventory, recipe fragment, and both-engine lane receipts in the local evidence store.
- Owner/runtime authorization: no live install, game launch, hardware interaction, gameplay, or Arcade run is authorized or claimed.

## 11. Stop condition

Stop this slice after the three catalog entries are integrated, the existing behavior test passes under both engines, and the board/report hunk mapping is updated. Dragon Dance, Primevil, plugin, graphics, audio, and executable recipes remain separate scope.

## 12. Forbidden actions

No live game or collection writes, payload execution, operating-system/tool installation, driver registration, credential/security change, Arcade execution, package/release, or external GitHub write in this local integration worktree.

## 13. Commit/package authorization status

- Commit authorized: No local commit in this slice.
- Package authorized: No.
- Release/certification authorized: No.
