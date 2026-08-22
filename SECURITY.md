# TeknoParrot Manager -- Security Notes

This file documents this project's threat model and the sanitization
invariants that follow from it. It is the canonical reference for "why is
this input treated as untrusted" questions raised in code comments.

Current release state: v1.0 RC7 is the current source candidate (pre-publication; not yet published); v1.0 RC6 is the last published release, and final Version 1.0 remains unpublished.

## Threat model: live-fetched and externally-sourced values are untrusted input

Any value this script did not itself generate -- a GitHub Releases API
`FileName` field, a live-fetched `AutoSetup.cmd` rename target, a
collection-dat `ProfileCode`/`Executable` value, or any other field read
from a third-party file or API response -- is treated as attacker-
controllable, even though in practice it usually comes from a trusted
maintainer's repo. The script never assumes a well-formed value just
because the source is normally trustworthy.

## Download pipeline protections

Live downloads use the shared `Invoke-TpmDownload` pipeline where practical.
That pipeline:

- accepts only URLs that passed the call site's allowlist/validation rules,
- writes to a temporary `.partial` file first,
- validates the completed file size when an expected size is available,
- moves the completed file into place only after validation,
- removes partial files on failure, and
- records method, file size, elapsed time, and average transfer rate in the log.

The preferred transport order is BITS, then streamed `HttpClient`, then
`Invoke-WebRequest` as an emergency fallback. This is a reliability and
integrity-hardening measure; it is not a cryptographic authenticity guarantee.

### Download audit records by artifact

The shared log records each live-fetched artifact's authoritative source URL,
filename, version when known, computed SHA-256, and transfer metrics (method,
size, elapsed time, and average speed). ReShade additionally records the
installer Authenticode signer/subject, status, signer thumbprint, and final
trust result. ReShade's SHA-256 is an audit hash; the implementation does not
compare it to a separately published ReShade digest. BepInEx records its
GitHub release source, filename/version, SHA-256, and validates the release
asset digest when GitHub supplies one, failing closed on mismatch. dgVoodoo2
uses the same digest validation when available. Eggman/RomVault dat,
FFBArcadePlugin, the PostgreSQL/guide package, the TPM update package, and
TeknoParrotUI thumbnail downloads receive source/hash/transfer audit entries;
where no signer or expected digest exists, the log is not an authenticity
claim.

## SHA-256 digest verification (BepInEx and dgVoodoo2 GitHub release assets)

The GitHub Releases API serves a machine-readable `digest` field
(`"digest": "sha256:<64-hex>"`) for release assets, computed by GitHub
itself from the uploaded bytes and served over the same allowlisted
`api.github.com` host already used to discover the download URL. Confirmed
present on real release assets during this feature's design and
independently reconfirmed by a live API call: `dgVoodoo2_87_3.zip` ->
`sha256:6fb954bed55bf70e948c5045a663a9df31ea206faf105e327bafe46c318f867f`
and `BepInEx_win_x64_*.zip` -> a similarly-formed digest. `Get-TpmSha256FromDigestField`
parses this into a bare hex hash; `Invoke-TpmDownload -ExpectedSha256`
(backed by `Test-TpmDownloadedFile -ExpectedSha256`) computes the
downloaded file's own SHA-256 and fails closed on any mismatch -- deletes
the partial file, logs a `SECURITY --` line with both hashes, no
extraction. This is a real cryptographic integrity check (unlike the
"reliability, not authenticity" caveat on the general download pipeline
above), because GitHub itself is the source of the expected digest over an
allowlisted, HTTPS-only API host. It does not, however, prove the asset was
authored by the claimed maintainer -- it only proves the bytes downloaded
match the bytes GitHub currently serves for that release. `Get-BepInExLatestRelease`
and `Get-DgVoodoo2LatestRelease` both extract this field; a missing/absent
digest (older release, or a GitHub API change) degrades gracefully to the
pre-existing size-only validation rather than blocking the download.

## Transactional extraction (staging + rollback-safe promotion)

Added in a P1 remediation pass after an independent review forced a
failure partway through a multi-file extraction and confirmed the first
file was left behind in the live destination folder -- a real violation of
an earlier "no partial deploy" claim in this document, which described the
intent but not yet the actually-enforced behavior. Both `Expand-DgVoodoo2Zip`
and `Expand-ReShadeSelfExtractingArchive` now go through three shared
primitives (defined next to `Test-PathInside`):

- `New-TpmStagingDirectory` creates a fresh, uniquely-named directory under
  a controlled TPM temp location (`%TEMP%\TeknoParrotManagerStaging\`) --
  never directly under `Scripts\ReShade\` or `Scripts\dgVoodoo2\`.
- Every required file is extracted into that staging directory and fully
  validated there (entry presence, sanitized names, containment checks,
  non-zero-length) before the real destination is touched at all.
- `Invoke-TpmTransactionalPromote` performs the actual move into the
  destination, and is itself rollback-safe: any pre-existing destination
  file being replaced is moved aside first; if any file's promotion fails
  partway through, every file already promoted in that same call is
  removed again and every file moved aside is restored to its original
  name and location, so the destination ends up byte-for-byte identical to
  its pre-operation state.

For a recoverable failure -- including a validation, extraction, or promotion
failure for which the original filesystem state remains observable -- the
destination is restored byte-for-byte to its captured pre-operation state.
This includes directory existence, relative paths, file-vs-directory shape,
and file bytes. Rollback and staging evidence is cleaned only after successful
restoration and successful cleanup.

The supported adversarial case where an underlying filesystem mutation makes
a phase-1 source disappear before a valid backup is observable is different:
TPM throws an explicit ROLLBACK FAILED / INCONSISTENT error, preserves the
available recovery evidence, and does not claim exact restoration. If the
destination is restored but cleanup of rollback or staging evidence fails, TPM
throws TRANSACTION CLEANUP FAILED, reports the residue path, and preserves it
for diagnosis. Dedicated tests cover both extractors and both failure classes,
plus clean success and exact pre-state restoration.

## dgVoodoo2 selective extraction (Scripts\dgVoodoo2\)

`Get-DgVoodoo2LatestRelease` fetches the latest release from the official
`github.com/dege-diosg/dgVoodoo2` GitHub Releases channel (same
URL-allowlist pattern as BepInEx: scheme=https, host exactly
`github.com`/`api.github.com`, no userinfo, path under
`/dege-diosg/dgVoodoo2/releases/download/`). `Expand-DgVoodoo2Zip` extracts
only the 6 known files (`MS\x86\D3D8.dll`, `MS\x86\DDraw.dll`,
`MS\x86\D3DImm.dll`, `3Dfx\x86\Glide2x.dll`, `3Dfx\x86\Glide3x.dll`, root
`dgVoodoo.conf` -- verified live against the real ZIP layout during
implementation) at their expected subpaths, sanitizing each destination
name via `[System.IO.Path]::GetFileName()` and a `Test-PathInside`
containment check before writing, the same protection class as
BepInEx/FFBPlugin. Fails closed -- transactionally, per "Transactional
extraction" above -- if any of the 6 expected entries is missing at its
expected subpath: a changed ZIP layout in a future dgVoodoo2 release is a
"stop and tell the user" event, not a best-effort partial extraction, and
the destination is left byte-for-byte unchanged.
`dgVoodoo2\` is never bundled in the release ZIP; TPM always live-fetches it
fresh from the official GitHub release, matching the FFBPlugin/BepInEx
integrity posture: HTTPS + host allowlist + SHA-256 digest verification +
safe extraction, no code-signing trust anchor (dgVoodoo2's official
distribution is unsigned).

## ReShade identity-pinning with rotation (stronger integrity case than BepInEx/dgVoodoo2/FFBPlugin)

Unlike BepInEx, dgVoodoo2, and FFBPlugin (all unsigned community/upstream
builds with no code-signing trust anchor), the ReShade installer
(`ReShade_Setup_<version>.exe`, fetched from `https://reshade.me/downloads/`,
same host-allowlist pattern used elsewhere: scheme=https, host exactly
`reshade.me`, no userinfo, path under `/downloads/`) IS Authenticode-signed
-- just with a self-signed certificate, so Windows can never chain it to a
trusted root (`Get-AuthenticodeSignature` reports `Status = UnknownError`,
not `Valid`, and always will for this cert). Because the cert is
self-signed, gating on `Status -eq 'Valid'` would be permanently
fail-closed and useless.

**A self-signed certificate's Subject string alone is never a trust
anchor** -- anyone can mint a self-signed certificate with any Subject
text, including `CN=ReShade, E=info@reshade.me`. The actual root of trust
for a self-signed cert is the specific key/certificate itself, identified
by its fingerprint. Design:

- **Hard trust anchor:** the signer certificate's Thumbprint must equal
  `589690208A5E52FB96980C4A6698F50ACD47C49F` (`$Script:ReShadeTrustedCertThumbprint`
  in `TeknoParrot-Manager.ps1`). Source: the fingerprint reshade.me's own
  download page publishes for the currently-shipping certificate
  (user-supplied confirmation), independently reconfirmed live during this
  feature's implementation by downloading `ReShade_Setup_6.8.0.exe` from
  `https://reshade.me/downloads/` and calling `Get-AuthenticodeSignature`
  on it directly: `Status=UnknownError`, `Subject='CN=ReShade,
  E=info@reshade.me'`, `Thumbprint=589690208A5E52FB96980C4A6698F50ACD47C49F`
  -- an exact match. Re-confirmed live again during the P1 #2 remediation
  pass below (same values observed against `ReShade_Setup_6.8.0.exe`).
- **Explicit status policy, evaluated alongside the thumbprint -- not
  ignored (P1 #2 remediation).** An earlier version of
  `Test-ReShadeSetupTrustedSignature` checked only the Thumbprint and
  ignored `.Status` entirely, so a `HashMismatch` signature status (the
  status Windows reports for a file that was modified after signing --
  i.e. a tampered or corrupted download) paired with a
  coincidentally-or-maliciously-matching Thumbprint field would have been
  reported `Trusted = $true`. This was found and fixed by an independent
  review round; it is documented here as a concrete case, not a
  hypothetical one. Trust now requires the signer certificate's Thumbprint
  to match the pinned constant **AND** `.Status` to be on an explicit,
  single-entry accept-list (`$Script:ReShadeAcceptedSignatureStatuses`,
  currently just `@('UnknownError')` -- the one status a genuine, intact,
  self-signed ReShade installer actually produces, per the live observation
  above). This is deny-by-default: every other status --
  `HashMismatch` (tampered/corrupted file), `NotSigned`, `NotTrusted`,
  `NotSupportedFileFormat`, `Incompatible`, the `Error` sentinel from an
  exception, or any status not on the list at all (including a future
  .NET/Windows status this project has never seen) -- fails closed. Adding
  a status to the accept-list requires the same maintainer-only,
  independently-sourced justification as changing the thumbprint itself,
  documented here at the time it is added.
- **Subject match is a secondary sanity check only** (`Test-ReShadeSetupTrustedSignature`
  reports it as `SubjectMatch`), layered on top of the thumbprint+status
  gate, never a substitute for it.
- **Fail closed on any fingerprint mismatch, unaccepted status, missing
  signature, invalid/unparseable signature, or exception.** No "proceed
  anyway with a warning" fallback, and no automatic adoption of a changed
  fingerprint into config (no TOFU-on-change). Both first-install and
  existing-runtime update paths use the same trust gate before extraction.
  An untrusted download is not deployed; TPM keeps the prior runtime and
  returns to the manual or unchanged-runtime path.
- **Rotation:** the trusted fingerprint constant (and, separately, the
  accepted-status list) can only be updated by a maintainer, sourced
  independently from the allowlisted `https://reshade.me` site itself (for
  the fingerprint) or from a live-observed genuine installer (for a status
  change), and shipped in a TPM version bump with the new value and change
  rationale documented here -- the same trust model as updating any other
  pinned identity. TPM itself never auto-updates either value from a live
  response; it only compares against what is shipped.
- **Status, Subject, and Thumbprint are all logged on every run, pass or
  fail** (`Test-ReShadeSetupTrustedSignature` -> `Write-Log`), independent
  of which one gated the outcome, for audit trail.
- `Test-ReShadeDllSignature` (the existing raw `Get-AuthenticodeSignature`
  wrapper, used today for user-supplied DLLs where "informational only" is
  the correct existing behavior) gained an additive `Thumbprint` field but
  its return contract and behavior for existing callers are unchanged.
  `Test-ReShadeSetupTrustedSignature` is a separate function, used only by
  the auto-download path, that adds the fingerprint-match gate on top.
- After a trusted signature, `Expand-ReShadeSelfExtractingArchive` replicates
  the published crosire/reshade installer's own self-extracting-archive
  format (see ARCHITECTURE.md for the source citation and the live-verified
  file offsets). `ReShade\` is never bundled in the release ZIP; TPM always
  live-fetches it fresh from reshade.me, per reshade.me's own
  do-not-redistribute notice.

## Auto-update threat model

The updater is intentionally manual, backup-first, and GitHub-Releases-only.
It must not silently replace files, and it must not execute downloaded code in
the same session. The menu and startup update paths show the proposed version,
ask for confirmation before applying, back up the current script before
replacement, validate the extracted script, then instruct the user to restart.

Update release assets are limited to the Jumpstile TeknoParrot Manager GitHub
release path. The downloaded ZIP is extracted to a temporary location, and the
candidate script is rejected if it is missing, empty, begins with raw ZIP bytes,
does not contain the TeknoParrot Manager marker, or does not contain a
`$ScriptVersion = "..."` assignment.

Current limitation: the TPM menu self-update path computes and logs the ZIP's
SHA-256 but does not currently consume an optional GitHub asset digest as an
expected value. Its safety boundary is therefore HTTPS, release URL
allowlisting, ZIP/script content validation, backup-before-replace behavior,
and manual confirmation. BepInEx and dgVoodoo2 release assets are separate
paths and do enforce their GitHub-provided SHA-256 digest when available.

## Rule: sanitize before joining into a filesystem path

Any externally-sourced value that is joined into a filesystem path for a
write or copy operation must be sanitized first:

- `[System.IO.Path]::GetFileName()` to strip any path components (rejects
  directory traversal segments embedded in a filename).
- A `Test-PathInside` containment check against the intended destination
  folder before the write actually happens.
- For ProfileCode-shaped values specifically, validate against
  `^[\w]+$` before joining (profile codes are purely alphanumeric; see
  `Resolve-RegisteredGameFolder` and `Register-Games`).

Three real path-traversal bugs of exactly this shape were found and fixed
in a v0.91 security sweep: `Invoke-FFBPluginSetup`'s `destDll` (from
`AutoSetup.cmd`), and the BepInEx release `FileName` / Eggman dat release
`FileName` (both from GitHub Releases API responses). None were exploited,
but a crafted upstream response could otherwise have written outside the
intended folder. See LESSONS_LEARNED.md for the full post-mortems.

## Rule: XML reads must disable the XmlResolver (XXE prevention)

All XML reads use a helper (`Read-Xml`) that sets `XmlDocument.XmlResolver = $null`
before any load. Without this, a crafted GameProfile XML could trigger an XML
External Entity (XXE) expansion -- loading a file URI or UNC path chosen by the
document author. Every call site that parses untrusted XML must go through this
helper, never a raw `[xml]` cast or `XmlDocument.Load()` directly.

XML writes use `Save-Xml`/`Save-XmlMaybe` (atomic `.tmp` + `File.Replace`), not a
direct `XmlDocument.Save()` to the live path. The atomic pattern prevents a partial
write from leaving a corrupt file if the process is interrupted mid-save.

## Rule: long-path UNC prefixes must use the UNC form

`Expand-ZipFileSafe`'s `\\?\` long-path prefix must be built via
`\\?\UNC\server\share\...` for UNC destinations, not a naive
`'\\?\' + $destFull` concatenation (which produces an invalid
`\\?\\\server\share\...` for UNC paths). Only matters when a staging/game
folder is a literal UNC path rather than a mapped drive letter; fixed in
v0.91.

## ADR-0155 production fact adapter trust boundaries (Checkpoint B1)

`scripts/TPMCertification.ProductionFacts.psm1` introduced several new
process/filesystem/module trust boundaries:

- **External process invocation (parser probe).** Every path handed to
  `powershell.exe`/`pwsh` via `Test-TPMParserCheckV1.ps1` is an internal
  repository file path from the fixed production inventory, never
  user/network input, but it is still passed through
  `ConvertTo-TPMWin32QuotedArgumentV1` (a CommandLineToArgvW-compatible
  quoting function) before reaching `Start-Process -ArgumentList` -- that
  array form does not auto-quote elements containing spaces or Win32
  command-line metacharacters on this environment's build (confirmed by
  direct reproduction; a path could otherwise be silently split into
  multiple argv tokens). Never string-concatenated into a single `-Command`
  argument.
- **Temporary-file handling.** `Invoke-TPMExternalProcessWithTimeoutV1`
  redirects a child process's stdout/stderr to GUID-named files under a
  caller-supplied working directory. If a timed-out child's termination
  cannot be confirmed (`Stop-Process` throws, or `WaitForExit` after
  `Stop-Process` still reports not-exited), those files are neither read
  nor deleted -- a still-writing process and a concurrent read/delete on
  the same file is a real race, and destroying the only diagnostic evidence
  of why the process hung would be counterproductive.
- **Module discovery (`Find-TPMInjectionHunterModuleV1`).** Falls back to
  probing the sibling `WindowsPowerShell\Modules`/`PowerShell\Modules`
  convention when the current engine's own `Get-Module -ListAvailable` finds
  nothing (a genuine Windows PowerShell 5.1 vs. pwsh `$env:PSModulePath`
  gap, not a security relaxation) -- it still only resolves modules already
  installed under the user's own module-root conventions, never a
  caller-supplied or externally-sourced path.
- **Recursive cleanup ownership (`New-`/`Remove-TPMOwnedScratchDirectoryV1`).**
  `Test-TPMProductionPackagePreflightV1` no longer recursively deletes a
  caller-supplied scratch root directly. It creates and owns exactly one
  GUID-named child beneath a validated parent (rejecting a pre-existing
  child name, an out-of-root child path, or a reparse point), and only ever
  recursively removes that exact owned child -- re-verified as
  still-contained and still-not-a-reparse-point immediately before
  deletion. A caller-supplied parent directory, and any pre-existing
  content in it, is never touched.

## ADR-0155 production harness cutover trust boundaries (Checkpoint B2)

`scripts/Invoke-TPM-RealInstanceSmoke.ps1`'s rewiring onto the production
authority, and the new `scripts/TPMCertification.ProductionEvidence.psm1`
adapter, introduce no new trust boundary beyond what Checkpoint B1 already
covers -- the same fixed, internal-file-only invocation surface applies --
but the cutover itself has security-relevant properties worth stating
explicitly:

- **No legacy fallback on failure.** The removal of
  `Complete-TPMCertificationTransaction`/`Publish-TPMCertificationArtifacts`/
  `Get-TPMCertificationScoreFromItems` means there is no remaining code path
  an exception (or a future defect) could silently fall back to. An
  exception anywhere between authority construction and cycle completion
  always produces the explicit "CERTIFICATION PIPELINE ABORTED" diagnostic
  and a nonzero exit, never a fabricated `CERTIFIED`/`NOT CERTIFIED` result.
- **Evidence adaptation never trusts the legacy ledger's own field values
  for identity.** `New-TPMProductionEvidenceRecordV1` re-derives `Status`/
  `EvidenceType`/`CaptureScope` from the legacy record's own fields under
  strict equality checks (`-ceq`/`-cne`) rather than assuming the ledger
  entry at a given array position is genuinely the evidence the production
  authority expects there -- a reordered, substituted, or replayed ledger
  entry surfaces as `EVIDENCE_ORDER_INVALID`/`EVIDENCE_IDENTIFIER_INVALID`,
  not a silently-accepted mismatch.
- **PNG validation happens before any evidence record is trusted as
  `Captured`.** The same `$productionPngValidator` (real PNG-header/
  dimension validation via `Test-TPMScreenshotFileValid` plus
  `System.Drawing.Image`) gates every evidence path before its hash/
  dimensions are recorded; a validation failure or exception inside the
  validator degrades that evidence to `Failed`, never `Captured`.

## ADR155-0309 redirected-cleanup and HarnessRoot bootstrap invariants (follow-up round)

Two invariants are now proven with real NTFS reparse points against the
actual production code paths, not merely asserted by design:

- **Cleanup never follows a reparse point.** `Remove-TPMOwnedScratchDirectoryV1`
  revalidates the entire ParentRoot-to-Path chain (`Resolve-TPMContainedPathV1`)
  and the target's own attributes immediately before every recursive delete.
  A junction substituted anywhere in that chain -- at the root, at an
  intermediate level, or at the leaf -- causes cleanup to refuse and return
  `$false`; it never traverses through the junction, and foreign content
  behind it is left byte-identical. This holds even when cleanup is invoked
  after an uncertain (crashed/killed/timed-out) child-process termination --
  there is no special-cased "trust it, the child probably finished cleanly"
  path.
- **HarnessRoot bootstrap fails closed on every reparse/traversal
  substitution.** The real `Run-TPM-Tests.ps1` entry point, invoked as an
  actual child process, refuses to proceed (nonzero exit, no marker/artifact
  written, never observable as a `CERTIFIED`/`NOT CERTIFIED` verdict) when
  HarnessRoot's parent is a junction, HarnessRoot itself is a junction, an
  intermediate component (`Reports`) is a junction, the parent is missing,
  or a directory-creation step is blocked by a pre-existing file of the same
  name. A dot-segment traversal value in `-HarnessRoot` canonicalizes to its
  real resolved location (via `[IO.Path]::GetFullPath`) and never touches an
  unrelated decoy sibling merely because it happens to be reachable through
  the literal ".." text.

Path/file identifiers written to `Write-Warning` diagnostics (e.g.
`INJECTIONHUNTER_MANIFEST_READ_FAILED`, `PRODUCTION_ENCODING_READ_FAILED`)
are sanitized through `ConvertTo-TPMSafeTechnicalTextV1` for consistency with
the exception-message text on the same line, even though these paths
originate from this module's own file-system enumeration rather than
attacker-controlled input.

## ADR155-0309 infrastructure-abort containment

Collection and production finalization are separate trust phases. The harness
initializes collection state and install-health adapter inputs before entering
collection, retains the first initiating `ErrorRecord`, and permits production
authority construction only after collection reaches its explicit completion
point. An early exception therefore cannot be replaced by a strict-mode member
access in `finally`, and cannot produce a certification outcome or publication.

The production fact adapter also treats a no-error install-health value as
untrusted schema input: it must be a `PSCustomObject` with a present, non-null,
non-empty collection-valued `Checks` property. Before reading entry values, the
adapter proves each entry is a non-null `PSCustomObject`, proves `Name` and
`Passed` exist, requires a nonblank string name and strict Boolean result, and
rejects nested collections, malformed extra entries, missing required names,
and duplicate required names with a stable
`PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID` prefix. An explicit load error remains
the only route by which absent or invalid JSON becomes a valid fail-closed
`Missing`/`InvalidJson` fact; no missing member is synthesized.

Behavioral abort tests do not expose a production failure-injection surface.
They copy the harness/modules into a temporary synthetic repository, instrument
only those copies to record attempted composition, and inject failures only in
the copied source. Production has no test switch, environment bypass, or public
callback capable of skipping collection or entering finalization early.

## Required sweep before every commit/build

See RELEASE-SAFETY-CHECKLIST.md section 1 for the full pre-commit gate
sequence (ASCII/parse check, PSScriptAnalyzer, InjectionHunter, Pester).
InjectionHunter findings in particular must be traced to confirm whether
the flagged input is actually attacker-controlled before being dismissed
as a false positive -- a finding is never dismissed by label alone.

### Noninteractive certification boundary

After the operator confirms target paths, certification closes child stdin and passes `-NoProfile -NonInteractive` to every PowerShell child. A prompt is therefore an infrastructure defect and must fail closed; automation must not suppress confirmation globally or answer a prompt. Dependency preflight is discovery-only: it must not install modules/providers, register repositories, change repository trust, alter execution policy, or contact Git remotes. Child stdout and stderr are captured separately, control/ANSI sequences are sanitized in technical logs, process identity and termination are recorded, and a missing or contradictory structured Pester result cannot become a certification decision.

No script or test under `scripts/` or `Tests/` may set
`$PSDefaultParameterValues['*:Confirm']=$false` or any other blanket
confirmation-suppression override; a repository-wide regression test enforces
this (`Tests/TPMCertification.OperatorExperience.Tests.ps1`). Real, bounded
child-process probes (same file) prove that `Read-Host`,
`$Host.UI.PromptForChoice`, a `-Confirm`-triggering `ShouldProcess` call, and
a missing-mandatory-parameter cmdlet call all terminate promptly with a
nonzero exit and no hang under closed stdin and `-NonInteractive`, on both
PowerShell engines.

Process metadata captured for every certification child
(`<prefix>-process.json`, written by `Invoke-TPMIsolatedProcessV1` in
`scripts/TPMCertification.Execution.psm1`) logs executable identity by
filename only, a phase identity, PID, timing, exit code, and argument
*count* -- never argument content -- by default. There is currently no code
path in this pipeline that logs raw argument values; if one is ever added for
diagnostics, it must implement an explicit redaction contract (a documented
list of argument names/patterns treated as sensitive) with tests proving
password/token/credential-shaped values are redacted before any such change
merges.

The structured Pester result (`Read-TPMPesterResultV1`) is validated as a
closed contract before any field is consumed: exact field sets at every
level, strictly typed and bounded numeric fields, and cross-field
reconciliation (discovered/passed/failed/skipped/not-run totals, container
totals, Virtual Beta Tester category totals, and the failure-entry count
against `Failed`). Every malformed state throws the single
`PESTER_RESULT_SCHEMA_INVALID:` error family -- never a raw
`PropertyNotFoundException` or JSON conversion exception -- which the
harness's collection-abort gate turns into a full infrastructure abort with
no authority, facts, evidence, marker, or bundle produced. See
`docs/adr/ADR-0155-IMPLEMENTATION-CHECKLIST.md` ("ADR155-0309 certification
isolation and result-validation hardening") for the full schema and the
adversarial test inventory.

### Log sanitization and owned-path validation fail closed (PR #155 correction)

Two invariants in `scripts/TPMCertification.Execution.psm1` that previously
failed open now fail closed:

- **Sanitizing a just-exited child's captured stdout/stderr is a safety
  invariant, not a best-effort convenience.** `Write-TPMSafeTechnicalFileV1`
  retries only the exact transient Win32 errors the just-exited-child
  handle-release race produces (`ERROR_SHARING_VIOLATION` /
  `ERROR_LOCK_VIOLATION`, `IOException.HResult` `0x80070020` /
  `0x80070021`) for a bounded 20 attempts / ~2 seconds; every other
  exception (disk-full, a bad path, `UnauthorizedAccessException`, etc.)
  throws immediately with no retry. On retry exhaustion it throws a
  distinctly tagged exception (`SANITIZATION_RETRY_EXHAUSTED:` ...) instead
  of silently returning -- neither the read half nor the write half can
  look like it succeeded when it did not. The unsanitized evidence file is
  never deleted or overwritten on failure, and no unsanitized content is
  ever written to the operator console, including in this failure path.
- **Every existing component of an owned directory's path, from a
  CALLER-SUPPLIED trusted root through the target, is checked individually
  for the `ReparsePoint` attribute** (`Assert-TPMNoReparseInChainV1`) --
  not just the final leaf's own attributes, since a reparse point on any
  ancestor can silently redirect the effective location. The trusted root
  itself is never inferred or guessed: `Assert-TPMOwnedDirectoryV1 -Root
  <trustedRoot> -Path <target>` takes it as a distinct, mandatory
  parameter, validates the root on its own (must exist, be stat-able, and
  not itself be a reparse point) before anything else happens, and rejects
  a drive/path-root-qualifier mismatch between root and target. Root and
  target being identical is a deliberately supported case (e.g. a caller's
  own already-established top-level directory), not an accidental default
  -- see ARCHITECTURE.md's "Trusted-root wiring correction (ADR155-0309
  round 3)" for the earlier defect this replaced, where the root was
  always silently collapsed onto the target, so only the leaf was ever
  actually inspected. Containment is a component-boundary comparison, not
  a string-prefix check, so a sibling directory that merely shares a text
  prefix (e.g. `C:\Owned-Evil` against `C:\Owned`) is never treated as
  contained. Directory creation (`Assert-TPMOwnedDirectoryV1
  -CreateIfMissing`) creates only a single authorized missing leaf (a
  multi-level bring-up goes through `New-TPMOwnedDirectoryChainV1`, one
  authorized level at a time), uses plain `New-Item` (never `-Force`,
  which would silently no-op on an existing, possibly attacker-planted,
  entry), and revalidates the entire chain again after creation, narrowing
  the TOCTOU window between the pre-creation check and the directory
  actually coming into existence. File creation (`New-TPMCreateNewFileV1
  -Root <trustedRoot> -Parent <parent> -Name <name>`) continues to use
  `FileMode.CreateNew` so it fails closed rather than silently reusing or
  overwriting an existing file, and revalidates the full chain a SECOND
  time immediately before the underlying file handle is actually opened --
  a second, closer-to-use narrowing point, distinct from the post-creation
  revalidation. **This narrows, but does not eliminate, the residual
  TOCTOU race** -- a substitution landing strictly between the final
  pre-use revalidation and the actual open/create call remains possible in
  principle on this OS; the code fails closed (throws) if a substitution
  is ever observed at any validation point, but no claim is made anywhere
  in this codebase that the race is eliminated, nor that every possible
  filesystem race in the certification pipeline is eliminated in general.

See `docs/adr/ADR-0155-IMPLEMENTATION-CHECKLIST.md` and
`Tests/TPMCertification.OperatorExperience.Tests.ps1` ("log sanitization
fails closed on persistent retry exhaustion" / "owned-directory
reparse-chain and component-boundary containment") for the full test
inventory, including the genuine OS-level file-lock and NTFS-junction
reproductions used to prove both invariants.
