# TPM-RC8-LANE-R-341 -- Thumbnail writes follow a reparse-point Icons path

## Owner issue
GitHub issue #341 (F11, thumbnail write bypasses child-path safety).

## Failure
`Invoke-ThumbnailDownload` (TeknoParrot-Manager.ps1 ~30867) creates or trusts
`<TeknoParrotRoot>\Icons` and then copies custom PNGs (~30936 Copy-Item) and downloads missing
icons (~30989 Invoke-TpmDownload) into it. Neither write validates the Icons ancestor chain for
junctions or symlinks, so a junction at Icons redirects the write outside the selected runtime.

## Expected behavior
- Before any custom copy or download, the Icons path chain is validated with
  `Test-TpmNoReparsePath` (checks every ancestor from the drive root and the leaf).
- If the chain contains a reparse point, the function prints a clear error, writes a log line,
  and returns with no thumbnail written. No fallback write.
- A normal directory keeps the existing behavior: custom copies and downloads run unchanged,
  and existing icons are preserved.

## Change
One bounded hunk after the Icons folder is created/confirmed (~30881-30885).

## Residual (not closed by this slice)
The check runs once at function entry, not immediately before each individual write. A
directory replaced between this check and a write (TOCTOU) is not covered. Per-write
re-validation is a further hunk and is not claimed here. Reported as partial.

## Forbidden regressions
- No change to profile validation, custom-name rules, or download URLs.
- No change to the existing-leaf "never overwrite" rule.

## Verification
Owner hold: no tests, gates, or smoke run in this lane. Main agent runs the standard
parser/ASCII, PSScriptAnalyzer and Pester checks after integration; the issue's junction
regression needs a real NTFS junction fixture in a later slice.

## Stop condition
Guard applied; file remains pure ASCII; residual TOCTOU stated in the evidence file.
