# TeknoParrot Manager -- Security Notes

This file documents this project's threat model and the sanitization
invariants that follow from it. It is the canonical reference for "why is
this input treated as untrusted" questions raised in code comments.

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

Current limitation: SHA-256 verification against GitHub release-asset digests is
not merged yet. Release ZIPs may include sidecar `.sha256` files and GitHub may
publish asset digests, but this release line still relies on HTTPS, release URL
allowlisting, ZIP/script content validation, backup-before-replace behavior, and
manual confirmation rather than a merged checksum enforcement step.

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
