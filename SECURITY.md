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

## Required sweep before every commit/build

See RELEASE-SAFETY-CHECKLIST.md section 1 for the full pre-commit gate
sequence (ASCII/parse check, PSScriptAnalyzer, InjectionHunter, Pester).
InjectionHunter findings in particular must be traced to confirm whether
the flagged input is actually attacker-controlled before being dismissed
as a false positive -- a finding is never dismissed by label alone.
