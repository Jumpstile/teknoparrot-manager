# Eggman NAS Path Policy Inventory

Status: REQUIRED review artifact for the RC8 destination-path remediation.
Date: 2026-08-23.
Component: `Get-EggmanDatDestinationAssessment`,
`Get-EggmanDatConfiguredPathAssessment`, `Invoke-EggmanDatDownload`, and the
Eggman branch of `Invoke-TpmDownload`.
Related issue: #292, "RC8 package runtime blockers: Eggman destination fallback
and PostgreSQL elevation UX".

This inventory resolves the complete path-role problem class. It is not a
release authorization and does not authorize a package, tag, deployment, or
merge.

## Governing sources

- `SECURITY.md`: untrusted path input, canonical containment, reparse-point
  refusal, partial-file download, validation before replacement, and fail
  closed behavior.
- `ARCHITECTURE.md`: Eggman recognition-data ownership and the shared download
  pipeline.
- `RELEASE-SAFETY-CHECKLIST.md`: pre-commit quality gates, documentation
  parity, review evidence, and release hold rules.
- `SPECIFICATION_DRIVEN_REVIEW_STANDARD.md`: complete problem-class coverage,
  self-adversarial review, and Review Ready evidence.
- `INVENTORY_STANDARDS.md`: stable row identifiers, status markings, and
  separate specification and system-invariant inventories.
- Windows/.NET path contracts used by the implementation: absolute-path
  validation, `System.IO.Path.GetFullPath`, filesystem item attributes, and
  component-boundary comparison.

## Specification inventory

| ID | Rule | Status and implementation evidence |
| --- | --- | --- |
| SP-EGGMAN-PATH-001 | A download destination must be an absolute `.zip` path and must be normalized before role checks. | Implemented by `Get-EggmanDatDestinationAssessment`; covered by the existing malformed, extension, and dot-segment tests. |
| SP-EGGMAN-PATH-002 | Canonical containment must use path components, not a raw string prefix, so sibling names do not count as contained. | Implemented by `Test-PathInside`; covered by the protected-root sibling test and the existing containment tests. |
| SP-EGGMAN-PATH-003 | TeknoParrot installation, TPM program, supplementary ZIP source, and game staging roots are protected write boundaries. | Implemented by the protected-root checks; covered by the protected-root test. The previous existing-file exception under the TeknoParrot root is removed. |
| SP-EGGMAN-PATH-004 | The primary ZIP source is source data, not a protected Eggman destination root. A destination inside it is allowed only when its canonical parent is reachable, non-reparse, and outside every protected root. | Implemented by omitting the primary source from `$protectedRoots`, requiring an existing parent for selected paths, and walking parent attributes; covered by the primary-source and reparse tests. |
| SP-EGGMAN-PATH-005 | A missing or unavailable selected mapped-drive or UNC parent must fail closed rather than being created by the download path. | Implemented by `-RequireExistingParent`; covered by mapped-drive/UNC unavailable-share tests. |
| SP-EGGMAN-PATH-006 | A reparse-backed destination or any existing reparse-backed parent must be rejected. | Implemented by destination and parent attribute checks; covered by the junction test and existing reparse coverage. |

## System invariant inventory

| ID | Invariant | Status and verification |
| --- | --- | --- |
| SII-EGGMAN-DEST-001 | No protected-root destination reaches the downloader. | Implemented by the read-only assessment before `Invoke-TpmDownload`; covered by the protected-root and direct preflight tests. |
| SII-EGGMAN-DEST-002 | A valid external primary-source destination can be used without weakening install, supplementary, staging, or reparse boundaries. | Implemented and covered by the primary-source, sibling-prefix, protected-root, and reparse tests. |
| SII-EGGMAN-DEST-003 | A preferred path that is missing, unavailable, invalid, or unsafe falls back to a TPM-owned location when possible and offers a browse retry on update flows. | Implemented by `Invoke-EggmanDatDownloadInteractive`; covered by the protected-root fallback and unavailable mapped/UNC retry tests. |
| SII-EGGMAN-DEST-004 | The exact canonical destination is revalidated immediately before any existing destination is removed or the partial file is moved into place. | Implemented by `DestinationValidationScript` in `Invoke-TpmDownload`; covered by the final-revalidation test. |
| SII-EGGMAN-DEST-005 | A failed destination or archive validation leaves the existing destination unchanged and removes the partial file. | Existing shared-download invariant preserved; covered by the existing invalid-archive cleanup test. |
| SII-EGGMAN-DEST-006 | Destination assessment remains read-only. | Preserved by the AST guard for all read-only Eggman helpers. |

## Focused test matrix

| Input class | Expected result |
| --- | --- |
| Existing local primary ZIP directory outside protected roots | Allowed when the parent is canonical, reachable, writable, and non-reparse. |
| Primary source path under TeknoParrot, supplementary, staging, or TPM program roots | Rejected as `ProtectedLocation`. |
| Sibling-prefix path such as `SupplementaryGameZips-archive` | Not treated as contained by `SupplementaryGameZips`. |
| Dot-segment alias into a protected root | Rejected after `GetFullPath` normalization. |
| Mapped-drive-shaped path such as `W:\Unavailable\...` with no reachable parent | Rejected as unavailable; update flow offers retry/fallback. |
| UNC-shaped path such as `\\OMVNAS\...` with no reachable parent | Rejected as unavailable; update flow offers retry/fallback. |
| Junction/reparse parent | Rejected before the downloader or final move. |
| Existing DAT under the TeknoParrot installation | Remains protected; it is not an update write anchor. |

## Deliberately out of scope

- SMB credentials, drive mapping, share uptime, or repairing a NAS.
- Deleting, cleaning, moving, rewriting, or redeploying any existing NAS data
  or checkout.
- AutoSync's separate game-extraction staging transaction; its existing
  staging validator remains its owning boundary.
- PostgreSQL setup, release packaging, version identity, tags, and deployment.
- A claim that a path remains safe against every possible concurrent filesystem
  mutation; the final revalidation narrows the window but does not provide a
  kernel handle-based transaction.

The current Desktop process cannot inspect the named NAS paths because mapped
and UNC access is denied. That is recorded as unavailable evidence, not as
proof that those paths are absent or clean.
