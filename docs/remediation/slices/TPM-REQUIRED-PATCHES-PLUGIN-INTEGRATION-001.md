# TPM Remediation Slice Contract

## 1. Slice name

- Name: Exact-build managed-plugin recipe integration and local source selection label
- Contract ID: `TPM-REQUIRED-PATCHES-PLUGIN-INTEGRATION-001`
- Issue/PR: Issue #351 follow-up; lane contract `TPM-REQUIRED-PATCH-PLUGINS-20261015`

## 2. Owner report IDs included

- IDs: none assigned to this lane; source evidence is in the managed-plugin lane contract and fragment.
- Exact owner-visible failures: two exact-guide managed-plugin restorations are not represented in the central catalog; selecting their local patch ZIP is currently labeled as a Main game ZIP.

## 3. Explicit exclusions

- Owner IDs not included: PR #321 FFB owner report 33 and all unrelated owner reports.
- Features, modules, package, runtime, and release actions excluded: no BepInEx installation, core/plugin execution, operator-pack installation, registry/config utility, user configuration changes, game launch, gameplay, live install, owner smoke, package rebuild, or release.

## 4. Behavior contract

- Current failure: exact Mars Sortie 1.46.9 and Rabbids Hollywood plugin payloads have no central recipe; `UserSelected` source browsing describes the selected package as a Main game ZIP.
- Expected behavior: add two exact-build absent-only plugin `CreateFile` recipes. Each requires `BepInEx/core/BepInEx.dll`, exact executable identity, exact source ZIP/member/size/hash, and the matching target hash. The `UserSelected` browse path must call the selected archive a local patch ZIP and must retain exact-filename and path-containment checks.
- Mars pins: profile `MarsSortie`; build `Mars Sortie (1.46.9)(2018)[UDC PC][TP]`; `Shooter.exe` SHA-256 `08541DCD067D7BB3BBE42BEAF2F1B5224C762FC347B71FC7A7308D7430384372`; source `Mars Sortie (1.46.9) - TPPlugin_v1.2.zip`, member `MSTPPlugin.dll`, size 21,504, SHA-256 `3CCABD105D603EAAA7EE3CD5F7194DEBD179CC30B701113DBC5C6B564FDB1783`; target `BepInEx/plugins/MSTPPlugin.dll`.
- Rabbids pins: profile `RabbidsHollywood`; build `Rabbids Hollywood (2018)[Adrenaline PC][TP]`; `Game.exe` SHA-256 `979F9736A99745454429908227CDD2F48875F193D439CFA33A9E14B4578DA95D`; source `Rabbids Hollywood (2018) - BepInEx Operator Configuration Pack.zip`, member `BepInEx/plugins/UnityPlugin_BepInEx_RHA.dll`, size 15,360, SHA-256 `C3DEDA497E160652A1F0D3D99892A4F534A88D61358DBA5192003FF519D5E8EB`; target `BepInEx/plugins/UnityPlugin_BepInEx_RHA.dll`.
- Forbidden regressions: never overwrite an existing target; exact-after is idempotent; unknown target bytes refuse; receipt undo removes only an unchanged created file; retain source ZIP filename validation, canonical containment, reparse checks, and exact member/hash validation.
- Design boundaries and deliberate exclusions: the Rabbids operator plugin is distinct from the existing trigger/crosshairs assembly recipe. The selected source is a user-provided local patch ZIP, not a Main archive. No engine source format, payload extraction, or trust boundary is broadened.

## 5. Source/function ownership

- Files: `scripts/TpmRequiredPatchRecipes.json`; `scripts/TpmRequiredPatchEngine.ps1` source-label/prompt text only after final engine integration; `Tests/TeknoParrot-Manager.Tests.ps1`; the frozen plugin fragment/test/contract; this slice and the Issue #351 board/report addenda.
- Functions/regions: existing `Resolve-TpmRequiredPatchSourceRoot`, existing catalog loader and transaction engine; no new engine framework.
- Owning subsystem: schema-3 managed-plugin recipe catalog and existing user-selected local source browse path.

## 6. Tests required before implementation

- Focused failing or characterization tests: the frozen plugin lane has six Pester tests passing under PowerShell 7 and Windows PowerShell 5.1 with Pester 5.7.1; these are pre-integration receipts.
- Source/inventory checks: compare the three frozen lane files to the independently checked hashes; compare each of the two central entries exactly to the fragment's `Entries` only; do not copy fragment census metadata.

## 7. Tests required after implementation

- Focused behavior tests: add both IDs to the existing central metadata and per-entry isolated transaction tests; test the `UserSelected` browse path with an exact synthetic patch ZIP and refusal when the selected folder lacks the exact filename; observe the corrected label/prompt through the real function output.
- Regression suite: run the final combined catalog's affected focused tests once the three recipe lanes are frozen. The full Main/Support and canonical quality gate run once for the complete integration snapshot.
- Static and procedure gates: parse touched PowerShell under both engines, run configured analyzer for changed production code, `git diff --check`, and the permanent procedure gate after the final report is refreshed.

## 8. Documentation/report updates required

- Control board row: a separate Issue #351 plugin integration follow-up; preserve the historical PR #353 13-entry gate record.
- Remediation report row: record two added entries, source selection wording fix, exact source hashes, focused receipts, and owner limits.
- Hunk classification: two catalog entries, existing recipe expectation/ID tests, existing resolver label/prompt, and this documentation -> Issue #351 / plugin lane contract / this slice / `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-UX-001`, and `TPM-TRUTH-001`.
- Changelog or user docs, if applicable: synchronize user-facing patch-source instructions after the complete combined recipe scope is frozen.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: exact guide build, executable, prerequisite, source-member, target, and hashes.
- `TPM-EVIDENCE-001`: immutable lane manifest/receipt and focused proof.
- `TPM-UX-001`: accurately label user-selected local patch ZIP browsing.
- `TPM-TRUTH-001`: keep available recipes separate from installed/gameplay readiness.
- `TPM-OWNER-001`: owner install and gameplay acceptance remain pending.

## 10. Runtime smoke checklist

- Exact packaged behavior: not exercised in an owner package; only synthetic local source-selection and transaction fixtures are in scope.
- Required source/package identity: exact profile/executable and payload/member hashes are captured in the frozen plugin lane evidence.
- Evidence artifacts: frozen plugin lane fragment, focused test, contract, and external source receipts.
- Owner/runtime authorization: no live install, plugin execution, game launch, gameplay, hardware interaction, or Arcade run is authorized or claimed.

## 11. Stop condition

Stop this slice after the two central entries are integrated, exact-source and isolated transaction tests pass, the user-selected source label is accurate, and board/report mappings are complete. SB3, MIB, unrelated plugin candidates, native I/O, graphics, audio, and executable recipes remain separate scope.

## 12. Forbidden actions

No live game or collection writes, operator-pack installation, BepInEx installation, plugin/payload execution, registry/config utility, operating-system/tool installation, credential/security change, Arcade execution, package/release, or external GitHub write in this local integration worktree.

## 13. Commit/package authorization status

- Commit authorized: No local commit in this slice.
- Package authorized: No.
- Release/certification authorized: No.
