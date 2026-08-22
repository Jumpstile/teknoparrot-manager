# ReShade / dgVoodoo2 Auto-Download Specification Inventory
Release context: this inventory documents the v1.0 RC7 source candidate (pre-publication; not yet published). The v1.0 RC6 release is the last published release; final Version 1.0 remains unpublished.

Governing sources (multiple, one per external contract this component
conforms to -- see "In scope" below for which rule family cites which
source): the GitHub Releases API (`api.github.com`, both the release-list
and release-asset JSON shapes, including the asset `digest` field),
reshade.me's own download page and installer distribution
(`https://reshade.me/downloads/ReShade_Setup_<version>.exe`), the
published open-source crosire/reshade installer source
(`setup/MainWindow.xaml.cs`, `InstallStep_InstallReShadeModule`, BSD-3/MIT)
for the self-extracting-archive format, the dege-diosg/dgVoodoo2 GitHub
Releases channel and its release ZIP's internal layout, and the .NET
`X509Certificate2`/Authenticode signature model as exposed by
`Get-AuthenticodeSignature`. This inventory defines the complete intended
scope of `Get-ReShadeSetupDownloadUrl`, `Test-ReShadeSetupTrustedSignature`,
`Expand-ReShadeSelfExtractingArchive`, `Get-DgVoodoo2LatestRelease`,
`Expand-DgVoodoo2Zip`, and the shared SHA-256 digest verification path
(`Get-TpmSha256FromDigestField`, `Test-TpmDownloadedFile -ExpectedSha256`,
`Invoke-TpmDownload -ExpectedSha256`) in `TeknoParrot-Manager.ps1`.

## In scope

### RESHADE-URL-001 -- ReShade download source and URL contract
- Download host is exactly `reshade.me`; scheme must be `https`; no
  userinfo component; path must start with `/downloads/`
  (`Get-ReShadeSetupDownloadUrl`).
- Version string is sourced by scraping `https://reshade.me` for the
  `ReShade_Setup_(\d+\.\d+\.\d+(?:\.\d+)?)` pattern
  (`Get-ReShadeLatestVersion`) -- reshade.me publishes no structured API
  for this, so a version-string regex against the live homepage is the
  only available mechanism. A version string that does not match
  `^\d+\.\d+\.\d+(\.\d+)?$` is rejected before it is ever interpolated
  into a URL.
- Only the plain (non-`_Addon`) installer build is ever requested,
  matching the existing manual-instructions parity and minimizing trust
  surface -- deliberate, not an oversight (see "Deliberately out of
  scope" below).
- Implemented. Verification: `Get-ReShadeSetupDownloadUrl` unit tests
  (Tests\TeknoParrot-Manager.Tests.ps1, `Describe` block for that
  function) plus live confirmation during implementation (real fetch of
  `https://reshade.me/downloads/ReShade_Setup_6.8.0.exe`, HTTP 200,
  correct bytes).

### RESHADE-TRUST-002 -- ReShade signing/fingerprint/status trust contract
- Hard trust anchor: the signer certificate's `Thumbprint` must equal
  `589690208A5E52FB96980C4A6698F50ACD47C49F`
  (`$Script:ReShadeTrustedCertThumbprint`). A self-signed certificate's
  Subject string is never sufficient on its own -- anyone can mint a
  self-signed certificate with any Subject text.
- Explicit accept-list for `Get-AuthenticodeSignature.Status`
  (`$Script:ReShadeAcceptedSignatureStatuses`), currently exactly
  `@('UnknownError')` -- the one status a genuine, intact, self-signed
  ReShade installer actually produces, confirmed live twice
  (implementation and the P1 #2 remediation pass) against real downloaded
  installers (`ReShade_Setup_6.8.0.exe`). This is deny-by-default: every
  other status (`HashMismatch`, `NotSigned`, `NotTrusted`,
  `NotSupportedFileFormat`, `Incompatible`, the `Error` exception
  sentinel, or any status not on the list) fails closed, never
  allow-by-default.
- Trust requires BOTH the thumbprint match AND the status accept-list
  match. Neither gate alone is sufficient -- a matching thumbprint on a
  `HashMismatch`-status file must fail closed (this was a real, found
  defect, not a hypothetical one; see P1 #2 in the System Invariant
  Inventory below).
- Subject match (`CN=ReShade, E=info@reshade.me`) is evaluated and
  reported (`SubjectMatch`) but is a secondary sanity check only, never a
  substitute for either gate above.
- Rotation: the thumbprint and the accepted-status list can each only be
  changed by a maintainer, sourced independently (thumbprint: the
  allowlisted reshade.me site itself; status: a live-observed genuine
  installer), and shipped in a version bump with the change documented in
  SECURITY.md.
- Implemented. Verification: `Test-ReShadeSetupTrustedSignature` table-driven
  Pester tests (Tests\TeknoParrot-Manager.Tests.ps1, "Table-driven status x
  thumbprint trust matrix" `Context` block) covering every status TPM
  intentionally accepts or rejects, plus the dedicated
  "REJECTS a HashMismatch signature even with the exact pinned thumbprint"
  regression test.

### RESHADE-ARCHIVE-003 -- ReShade self-extracting archive structure
- `ReShade_Setup_<version>.exe` is a PE stub with a standard ZIP archive
  appended at the end of the file (self-extracting-archive format),
  confirmed by reading crosire/reshade's own published installer source.
- Format detection: scan the file for every occurrence of the ZIP
  local-file-header signature (`PK\x03\x04`, i.e. bytes `0x50 0x4B 0x03
  0x04`), and try each candidate offset, in file order, as the start of a
  ZIP archive.
- A candidate qualifies only if it opens as a valid `ZipArchive` AND
  contains entries named exactly `ReShade32.dll` and `ReShade64.dll`. The
  first raw `PK\x03\x04` match is NOT assumed to be the real archive start
  -- confirmed live during implementation that the PE stub's own
  icon/resource data can independently produce an earlier
  `PK\x03\x04`-prefixed region that opens as a technically-valid but empty
  `ZipArchive` (observed at file offset 127840 in `ReShade_Setup_6.8.0.exe`,
  with the real archive's required entries actually starting at offset
  152576).
- No PK signature anywhere in the file, or no candidate containing both
  required entries, fails closed.
- Shader/effect-package files (`ReShade32.json`/`ReShade64.json` and
  similar) are present in the real archive but are never required or
  extracted -- out of scope, see below.
- The implementation explicitly loads `System.IO.Compression` before
  referencing `ZipArchive`/`ZipArchiveMode` and retains the separate
  `System.IO.Compression.FileSystem` load for `ZipFile` APIs; this is
  required by the Windows PowerShell 5.1 runtime model.

- The startup bootstrap explicitly imports `Microsoft.PowerShell.Security`, `Microsoft.PowerShell.Management`,
  and `Microsoft.PowerShell.Utility` before any trust or digest call, because
  a packaged Windows PowerShell 5.1 host may have module autoloading disabled.
  This makes `Get-AuthenticodeSignature` and `Get-FileHash` deterministic
  dependencies without changing either fail-closed verification rule.
- Implemented. Verification: `Expand-ReShadeSelfExtractingArchive` Pester
  tests (valid archive, decoy-signature-skip, missing-required-entries,
  no-PK-signature-at-all) plus live confirmation against the real
  `ReShade_Setup_6.8.0.exe` during implementation.

### DGVOODOO2-API-004 -- dgVoodoo2 GitHub Releases API/asset-selection contract
- Query endpoint:
  `https://api.github.com/repos/dege-diosg/dgVoodoo2/releases/latest`.
- URL-allowlist for the selected asset's `browser_download_url`:
  scheme=`https`, host exactly `github.com` (not `api.github.com` --
  that is the query host; the asset download host is plain `github.com`),
  no userinfo, path starting with
  `/dege-diosg/dgVoodoo2/releases/download/`.
- Asset-name pattern: `^dgVoodoo2[_0-9.]*\.zip$` -- selects the main
  release ZIP (e.g. `dgVoodoo2_87_3.zip`) and, by construction of the
  character class (letters are not in `[_0-9.]`), excludes the dev and
  debug variant assets (`dgVoodoo2_87_3_dev64.zip`,
  `dgVoodoo2_87_3_dbg.zip`) without needing a separate negative-match
  rule -- confirmed live against the real release's actual asset list
  during implementation (5 assets total: main, `_dbg`, `_dev64`,
  `dgVoodooAPI_*`, `WinMM.zip`; only the main one matches).
- 3-attempt retry/backoff, with a definitive 4xx response short-circuiting
  further retries (same shape as `Get-BepInExLatestRelease` /
  `Get-EggmanDatRelease`).
- Implemented. Verification: `Get-DgVoodoo2LatestRelease` Pester tests
  (well-formed release accepted, dev/debug variant never selected, wrong
  host rejected, missing-digest degrades gracefully) plus live
  confirmation during implementation (real query returned `v2.87.3`,
  `dgVoodoo2_87_3.zip`, matching digest).

### DIGEST-005 -- GitHub release digest/SHA-256 contract
- The GitHub Releases API serves a `digest` field on each asset object,
  shaped `"sha256:<64-hex-lowercase-or-uppercase>"`.
- `Get-TpmSha256FromDigestField` accepts only this exact shape (regex
  `^sha256:([0-9a-fA-F]{64})$`); any other algorithm prefix, malformed
  hex, or wrong length returns `$null` (graceful degrade to size-only
  validation, not a hard failure of the caller).
- When present, the downloaded file's own SHA-256
  (`Get-FileHash -Algorithm SHA256`) must match the extracted digest
  case-insensitively; a mismatch is a `SECURITY --`-logged fail-closed
  condition inside `Test-TpmDownloadedFile`, which propagates to
  `Invoke-TpmDownload` deleting the partial file and returning failure.
  Applies to both the dgVoodoo2 ZIP and (shared hardening, same round)
  the existing BepInEx update ZIP.
- Implemented. Verification: `Get-TpmSha256FromDigestField` and
  `Test-TpmDownloadedFile -ExpectedSha256` Pester tests (match, mismatch,
  case-insensitivity, malformed digest, absent digest) plus live
  confirmation: the real `dgVoodoo2_87_3.zip` download's computed SHA-256
  matched the GitHub API's published digest exactly
  (`6FB954BED55BF70E948C5045A663A9DF31EA206FAF105E327BAFE46C318F867F`).

### DGVOODOO2-LAYOUT-006 -- dgVoodoo2 expected archive layout and required entries
- Exactly 6 required entries, at these exact subpaths within the release
  ZIP (forward or back slash, normalized before comparison):
  `MS\x86\D3D8.dll`, `MS\x86\DDraw.dll`, `MS\x86\D3DImm.dll`,
  `3Dfx\x86\Glide2x.dll`, `3Dfx\x86\Glide3x.dll`, and root `dgVoodoo.conf`
  -- verified live against the real `dgVoodoo2_87_3.zip` release during
  implementation (an earlier draft of this mapping placed DDraw.dll,
  D3DImm.dll, and Glide3x.dll at the ZIP root instead of their real
  subfolders; corrected after live verification caught the mismatch).
- Destination file names are fixed literals (`D3D8.dll`, `DDraw.dll`,
  `D3DImm.dll`, `Glide2x.dll`, `Glide3x.dll`, `dgVoodoo.conf`), not
  derived from the ZIP entry name -- sanitized via
  `[System.IO.Path]::GetFileName()` as defense in depth even though they
  are literals, and containment-checked via `Test-PathInside` before any
  write.
- Any of the 6 expected entries missing at its expected subpath is a
  layout-drift event: fails closed, no partial extraction.
- Files present in the real ZIP but not in this list (e.g. ARM64/ARM64EC
  variants, `Cpl\`, `Doc\`, `dgVoodooCpl.exe`) are deliberately never
  extracted -- out of scope, see below.
- Implemented. Verification: `Expand-DgVoodoo2Zip` Pester tests (valid
  6-file extraction, missing-entry layout-drift) plus live confirmation:
  real extraction against the actual `dgVoodoo2_87_3.zip` produced all 6
  files with correct byte sizes.

### RESHADE-RUNTIME-007 -- Existing-runtime update contract
- When an existing ReShade DLL has a readable older file version than the
  current version reported by reshade.me, mode 5 offers an explicit Y/N update.
- An approved update uses the same authoritative URL construction, shared
  download audit, pinned Authenticode status/thumbprint gate, self-extracting
  archive validation, and transactional cache promotion as first acquisition.
- A declined, unavailable, unclassifiable, untrusted, or failed update never
  replaces the existing source DLL and does not weaken the manual path.
- Implemented. Verification: Get-ReShadeDllVersion,
  Get-ReShadeDllUpdateStatus, Get-ReShadeRuntimeState, and
  Invoke-ReShadeRuntimeUpdate tests in
  Tests\TeknoParrot-Manager.Tests.ps1; setup-flow wiring is source-checked.
## Deliberately out of scope

- **ReShade `_Addon` installer variant.** TPM only ever requests the
  plain build. Belongs to a different trust/feature surface (addon
  support) this project has never offered even in the manual-instructions
  path.
- **ReShade shader/effect-package auto-download.** TPM still does not manage
  shader packages, presets, executable add-ons, or arbitrary repositories.
  The curated research-first boundary and candidate evaluation are documented
  in docs/RESHADE-VISUAL-EFFECTS-RESEARCH.md; this runtime round does not
  expand the trusted download boundary. The self-extracting archive may contain
  effect metadata, but Expand-ReShadeSelfExtractingArchive never reads or
  requires it.
- **Revocation checking for the ReShade certificate.** The certificate is
  self-signed with no CA chain; there is no revocation authority to check
  against. Not a gap -- there is nothing to check.
- **dgVoodoo2 ARM64/ARM64EC variant DLLs, `Cpl\` control panel tooling,
  `Doc\` readme files, and the root `dgVoodooCpl.exe`.** TPM's deployment
  model only ever needed the 6 files documented in `DGVOODOO2-LAYOUT-006`
  (matching this project's own pre-existing manual-install instructions,
  which predate this auto-download feature). Extracting additional files
  would silently expand what TPM manages without a corresponding
  deployment/health-check path for them.
- **GitHub API rate limiting and authentication.** Both `Get-DgVoodoo2LatestRelease`
  and the existing `Get-BepInExLatestRelease`/`Get-EggmanDatRelease` use
  unauthenticated API calls, matching the existing pattern's already-accepted
  posture (a different problem than this round's scope; a future round
  could add authenticated calls project-wide if rate limiting becomes a
  real issue).

## Layering note

Every download in this family goes through the shared `Invoke-TpmDownload`
pipeline (allowlisted URL, `.partial` staging, size validation, optional
SHA-256 validation) before any extraction is even attempted. Extraction
itself is layered again behind the transactional staging/promotion
guarantee documented in the companion System Invariant Inventory
(`docs\RESHADE-DGVOODOO2-AUTODOWNLOAD-INVARIANT-INVENTORY.md`). For
recoverable failures, that guarantee includes exact pre-state restoration;
if an underlying filesystem mutation makes exact restoration impossible,
the transaction reports `ROLLBACK FAILED` / `INCONSISTENT` and preserves
evidence instead of claiming restoration. A download passing every check
in this Specification Inventory is a
necessary but not sufficient condition for a successful deploy; the
System Invariant Inventory's transactional-extraction and download-trust
invariants are the layer that governs what happens between "download
verified" and "files live in the real destination folder."
