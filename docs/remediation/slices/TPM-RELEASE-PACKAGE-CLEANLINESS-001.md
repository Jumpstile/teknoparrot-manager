# Release package cleanliness slice contract

## 1. Slice name

- Name: exact RC8 user-package allowlist and ECVF narrative/runtime split
- Contract ID: `TPM-RELEASE-PACKAGE-CLEANLINESS-001`
- Issue/PR: Issue #351; no PR #321 owner row is assigned. Local branch only.

## 2. Owner report IDs included

- IDs: Issue #351 package-cleanliness request (no numbered PR #321 owner-report ID).
- Exact owner-visible failures: the ZIP validator checks required entries and a partial forbidden list, so unrelated additions can pass; its current ECVF list also packages `_schema` JSON plus `evidence.md` and `experiments.md`.

## 3. Explicit exclusions

- Owner IDs not included: all numbered PR #321 owner reports; their statuses remain unchanged.
- Features, modules, package, runtime, and release actions excluded: no gameplay/product feature, final owner ZIP, release build/publication, tag, merge, commit or push; no ARCADE work, live install, game launch, payload execution, credentials, security settings, or unrelated cleanup. Parent owns final Expanded61 package/recommendation. Only isolated local synthetic package fixtures are permitted for proof.

## 4. Behavior contract

- Current failure: `Tests/Test-ReleasePackage.ps1` verifies required entries, selected forbidden entries, and 321 crosshairs, but does not reject every unlisted ZIP entry. The current package requirements include developer schema JSON and narrative evidence Markdown.
- Expected behavior: an exact explicit user-package allowlist covers only required application/runtime files, assets, applicable license, and end-user instructions; every file and explicit directory entry must match the source mapping, unknown/case-colliding/rooted/traversal paths fail, and file bytes match the mapped source. Crosshairs must be exactly the verified source names `000.png` through `320.png`.
- ECVF boundary: keep the maintainer registry at `contracts/pcsx2x6/contract.json` with `evidence.md`, `experiments.md`, and `_schema` retained in source. The ZIP places only the runtime `contract.json` and `runtime-evidence-index.json` under `scripts/resources/contracts/pcsx2x6/`; the user-facing root has no `contracts/` tree.
  All registry/load/observation APIs require explicit `ValidationMode=Source|Runtime`; mode is never inferred from Markdown presence. `Source` resolves maintainer `contracts/`, reads actual referenced Markdown, checks exact locator headings and hashes, and requires the adjacent deterministic index bytes to match that source projection. `Runtime` resolves only `scripts/resources/contracts/`, checks actual unchanged contract SHA-256 and complete strict index mappings, and does not claim omitted Markdown was read. Main always passes Runtime; missing packaged resources fail closed and never switch to Source. Source mode is explicit only in source/build and certification callers. Missing selected roots fail closed without fallback.
  The source/build package validator independently requires the actual source contract and documents, recomputes the projection, and compares exact ZIP index bytes. No unsigned authenticity claim is made; prose is not copied or paraphrased into the ZIP.
- Schema boundary: the bundled ECVF loader validates `contract.json` using inline PowerShell validators; the `_schema` JSON files are reference/development schemas, not runtime-loaded assets. Retain them in source.
- Forbidden regressions: weakening source/runtime mode separation or `Test-TPMContractRegistryIntegrityV1`, accepting missing/renamed source Markdown because a stale index exists, treating absent runtime index as valid, allowing unknown ZIP entries, shipping developer tests/governance/reports/schemas, or changing existing contract ownership/capability decisions. Preserve Main user-facing behavior and the unconditional `TPMCertification.Authority.psm1` dependency.

## 5. Source/function ownership

- Files: `Tests/Test-ReleasePackage.ps1`; `scripts/TPMCertification.Contracts.psm1`; new source `contracts/pcsx2x6/runtime-evidence-index.json` and ZIP destination `scripts/resources/contracts/pcsx2x6/`; focused package/contract tests and their CI route; `TeknoParrot-Manager.ps1` contract-root call site; package facts inventory and the production certification-source inventory/test; `AGENTS.md`; `RELEASE-SAFETY-CHECKLIST.md`; `ARCHITECTURE.md`; this slice and paired inventory; `docs/remediation/PR-321-control-board.md`; `docs/remediation/PR-321-reconciliation.md`; `docs/remediation/slices/README.md`.
- Functions/regions: `Assert-TPMContractLocatorsResolveV1`, `Test-TPMContractRegistryIntegrityV1`, `Get-TPMEmulatorContractObservationsV1`; release ZIP entry/path validation in `Tests/Test-ReleasePackage.ps1`. Main runtime consumers remain `Get-ContractBackedMissingComponents`, `Get-Pcsx2CrosshairPrerequisiteState`, and `Set-Pcsx2CursorPaths`.
- Owning subsystem: release-package validation and ECVF runtime contract integrity.

## 6. Tests required before implementation

- Characterization: demonstrate current validator accepts an otherwise well-formed ZIP with an unlisted entry; characterize source-tree ECVF locator checks against actual docs and exact headings.
- Fixture source inventory: map every current allowed file and all 321 generated Crosshairs paths; parent-provided owner ZIP is not read or duplicated.

## 7. Tests required after implementation

- Focused Pester: full exact source-mapped allowlist passes; each omitted required file, unknown root/nested file or directory, duplicate/case-colliding entry, malformed/rooted/traversal path, non-source-matching bytes, malformed Crosshairs entry/count, `_schema`, debug helper, narrative Markdown, tests and developer doc is rejected.
- ECVF tests separate source/build validation (requires actual maintainer contract and both Markdown docs; recomputes all hashes/headings/index and byte-compares the ZIP projection) from runtime-projection validation (checks exact contract SHA-256, strict index shape, and one-to-one EvidenceId/Locator/file/heading mapping only). Source-doc absence, stale source hash, forged/tampered index, stale contract hash, missing/duplicate IDs, and wrong headings fail at their proper boundary. Extract the synthetic ZIP into a private path containing spaces and brackets; import the packaged loader and invoke registry integrity plus read-only observations against an empty synthetic root. Assert the runtime reads only `scripts/resources/contracts` and does not need narrative Markdown or schema JSON.
- Route the focused Pester files in `.github/workflows/ci.yml`; do not run the full Main/Support/canonical suites in this lane.
- Procedure/static gates are owned by root; do not report them as run here.

## 8. Documentation/report updates required

- Control board row: append a distinct Issue #351 package-cleanliness checkpoint; preserve prior #321 and expanded58/61 history.
- Remediation report row: map package allowlist, ECVF index, tests, and docs to this contract and `TPM-TRACE-001`, `TPM-EVIDENCE-001`, `TPM-UX-001`, `TPM-TRUTH-001`; no numbered PR #321 owner status changes.
- Hunk classification: release validator/test route, runtime locator integrity/index, explicit user ZIP allowlist, architecture and engineering evidence.
- Changelog or user docs, if applicable: no runtime feature or user-facing workflow change; package instructions/checklist and support boundary remain exact. No version bump, release package, or publication authorization is assumed.

## 9. Permanent procedure IDs affected

- `TPM-TRACE-001`: map each allowlist, validator, ECVF and test hunk to Issue #351 and this contract.
- `TPM-EVIDENCE-001`: verify every permitted archive path, source document hash, contract locator, index binding, and packaged runtime load path.
- `TPM-UX-001`: define only the intended end-user files and reject developer material.
- `TPM-TRUTH-001`: distinguish local source/index and synthetic-package proof from parent-owned final package and owner-runtime acceptance.

## 10. Runtime smoke checklist

- Exact packaged behavior: extracted synthetic package loads `pcsx2x6/contract.json`, validates the machine-readable locator index and returns registry observations without narrative Markdown or schema JSON.
- Required source/package identity: local worktree based on `b9ac73b2fbae847c1e385a19e66c4fe8fad515a6`; synthetic fixture only.
- Evidence artifacts: focused test output and exact input identities stored outside the repository if receipts are retained.
- Owner/runtime authorization: parent owns the actual Expanded61 package and final recommendation; this lane makes no owner-runtime claim.

## 11. Stop condition

Stop after the exact allowlist and ECVF package/source boundary are covered by focused tests, the paired inventory/report/control-board mapping is current, and the parent receives the exact changed files and limitations. Any failure to preserve equivalent locator integrity blocks exclusion of the Markdown files.

## 12. Forbidden actions

No final owner ZIP, binary payload, game execution, live write, security/credential change, broad cleanup, full Main/Support/canonical suite, ARCADE operation, commit, push, PR, merge, tag, release, or claim of owner acceptance.

## 13. Commit/package authorization status

- Commit authorized: No; root review and gates are required.
- Package authorized: Local private synthetic fixture only; final owner ZIP is not authorized in this lane.
- Release/certification authorized: No.

## Clean 62-entry candidate local verification checkpoint

Local verification completed through2026-10-15T14:16:13Z. The complete evidence record and preserved failures are in docs/remediation/PR-321-reconciliation.md under this heading: Main1488 and Support42 passed per engine; corrected MainExtras/Shadow23 and package116 passed per engine with actual exits0. Source/package proofs do not establish owner runtime or release acceptance. Exact-head CI/integration and owner/ARCADE gates remain separate.
