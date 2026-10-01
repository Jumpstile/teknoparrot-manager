# TPM-RELEASE-SNAPSHOT-001

## 1. Slice name

- Name: Immutable current-release catalog snapshot
- Contract ID: `TPM_RELEASE_SNAPSHOT_001`
- Issue/PR: PR #321

## 2. Owner report IDs included

- IDs: `TPM_RELEASE_SNAPSHOT_001`
- Exact owner-visible failures: the mutable TeknoParrotUI release asset is not a sufficient historical catalog identity; release tag and target-commit metadata report stale profile counts; current-release delta lists require machine generation rather than hand-maintained copies.

## 3. Explicit exclusions

- Owner IDs not included: all runtime, package, owner-smoke, Arcade, ReShade, PostgreSQL, controls, FFB, GPU, prerequisite-install, and beginner-workflow findings.
- Excluded actions: product behavior changes, catalog contract migration, package build, owner smoke, Arcade testing, merge, tag, publish, certification, release, live wiki update, and runtime joystick/FFB changes.
- Excluded data: full TeknoParrot binary release ZIP and unlicensed third-party binary redistribution.

## 4. Behavior contract

- Current failure: the stable release locator can be republished in place and cannot establish immutable catalog content; the old 695-profile corpus is insufficient for the accepted current-release scope.
- Expected behavior: an immutable TPM-controlled manifest identifies the captured stable asset, records release/source discrepancies, inventories every catalog file with SHA-256, records semantic source-proof equality, and regenerates exact old/current delta lists.
- Forbidden regressions: no live mutable URL is required for deterministic validation; no historical snapshot is overwritten; no product runtime behavior changes; no ambient machine state enters generated output; no path traversal, absolute path, duplicate path, duplicate profile, missing file, or hash mismatch is accepted.
- Design boundaries: the exact catalog bytes are not vendored into the repository; the immutable source-proof commit is the approved reproducibility backing after semantic equality is proven. The asset SHA remains release evidence and is not relabeled as official source provenance.

## 5. Source/function ownership

- Files: `scripts/New-TpmReleaseCatalogSnapshot.ps1`, `scripts/Test-TpmReleaseCatalogSnapshot.ps1`, `scripts/Test-TpmReleaseCatalogDrift.ps1`, `contracts/snapshots/`, `Tests/TpmReleaseCatalogSnapshot.Tests.ps1`, and Slice 0 evidence/remediation documents.
- Functions/regions: snapshot manifest generation, canonical catalog inventory, XML/JSON semantic hashing, source-proof comparison, delta generation, path/hash validation, and drift-watch reporting.
- Owning subsystem: release evidence and catalog provenance; no product runtime subsystem.

## 6. Tests required before implementation

- Characterization: verified asset counts `925/383/923`, asset SHA-256, current proof commit, old count `695`, and semantic delta counts `230/0/38/657`.
- Source/inventory checks: current and historical roots contain only expected catalog files; current asset and proof commit have matching catalog name sets; existing historical contracts remain untouched.

## 7. Tests required after implementation

- Focused tests: manifest schema, content-addressed ID, exact metadata, per-file inventory and hashes, duplicate/path safety, proof-commit semantic equality, changed-proof rejection, delta regeneration, and no ambient state.
- Regression: `Tests/TPMGameSupport.Contracts.Tests.ps1`, `Tests/TPMGameSupport.Assessments.Tests.ps1`, `Tests/SupportPostureCorpus.Tests.ps1`, and the required main suite where the changed scripts are loaded.
- Static/procedure gates: ASCII, PowerShell parse, PSScriptAnalyzer with repository settings, Pester, `git diff --check`, and release quality gate report validation.

## 8. Documentation/report updates required

- Control board row: add Slice 0 immutable snapshot status and source-identity stop conditions.
- Remediation report row: record the exact asset, source-proof commit, semantic comparison, and machine-generated delta artifacts.
- Hunk classification: release evidence/generator/tests/docs only; no product runtime behavior.
- Changelog/user docs: no user-facing behavior change; no product version bump.

## 9. Permanent procedure IDs affected

- `TPM_RELEASE_SNAPSHOT_001`: immutable source snapshot and drift-watch procedure.
- Existing contract-generation procedures remain unchanged and are not migrated in this slice.

## 10. Runtime smoke checklist

- Exact packaged behavior: none; runtime smoke is explicitly excluded.
- Required source/package identity: no package is authorized.
- Evidence artifacts: manifest, per-file hash inventory, release API evidence, source-proof record, semantic comparison, delta manifest, validation output.
- Owner/runtime authorization: not authorized.

## 11. Stop condition

Stop if the asset hash, counts, proof comparison, file inventory, delta counts, path safety, schema validation, or historical preservation check fails. Do not widen scope into Slice 1 or runtime remediation.

## 12. Forbidden actions

No product behavior change, catalog contract migration, package, owner smoke, Arcade work, merge, push, tag, publish, certification, release, wiki update, or unrelated cleanup.

## 13. Commit/package authorization status

- Commit authorized: No; explicit review authorization required.
- Package authorized: No.
- Release/certification authorized: No.
