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
