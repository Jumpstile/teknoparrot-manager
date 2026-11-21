# Owner test plan: extraction progress leftover (issue 243)

## What was reported

After AutoSync extracted games, a thin blue row from the extraction progress stayed on screen above the "Scanning game library" progress.

## Where it stands

The old code used one shared Windows progress slot for both steps. That code is gone. Extraction and registration now each draw their own TeknoParrot Manager progress bar, and each bar is closed before the next one starts. No code change was needed, so none was made.

Only your screen can show whether a row is still left behind, so please run the check below.

## Test

You need: the test PC, a few small games that are not extracted yet, and a real console window (not a log file).

1. Start TeknoParrot Manager and choose **AutoSync**.
2. Pick at least two small games that are not extracted yet. Let AutoSync extract them.
3. Watch the screen when extraction ends and registration ("Register games") begins.
   - Pass: the extraction bar ends as done, then a new bar starts for registration. No thin blue row is left above it.
   - Fail: a leftover extraction row stays above the registration bar.
4. Run AutoSync again with every game already up to date (nothing to extract). Pass: registration starts with no leftover row.
5. Repeat step 2 once in Windows Terminal and once in the classic console window.
6. Write the result on issue 243. For a fail, add a screenshot and the log file `TeknoParrot-Manager.log`.

## Details

- Extraction runs inside the "AutoSync extraction" progress group, and the registration step runs inside "Register games" (`TeknoParrot-Manager.ps1`, section "AutoSync", and the `Register-Games` call).
- `Expand-ZipFileSafe` reports through `Write-TpmCompactExtractionProgress` and closes its step in a `finally` block, so it ends on success, failure and cancel.
- The script no longer calls `Write-Progress`, and `$ProgressPreference` is `SilentlyContinue`. A check with the progress module alone showed an extraction step ending (no step active), then a scan step starting and ending cleanly.
- The existing test "uses compact TPM progress and preserves cleanup instead of a PowerShell progress panel" covers the old code path.
