# TPM Remediation Slice Contract

## 1. Slice name
- Name: ReShade finite console buffer rendering
- Contract ID: TPM-RC8-RESHADE-CONSOLE-BUFFER-001
- Issue/PR: #323 / PR #321

## 2. Owner report IDs included
- IDs: 1 and 9, verified against the control board.
- Exact owner-visible failures: chooser crashes before Back/Use or synchronized selection when the real console reaches row 30 of a 30-row buffer.

## 3. Explicit exclusions
- Other owner IDs, deployment, effect catalog, HDR eligibility, files/game mutations, input semantics, and release identity authorization are excluded.
- No buffer enlargement, dropped rows, exception suppression, or fake console success.

## 4. Behavior contract
- Current failure: Write-TpmReShadeTerminalLines advances absolute cursor rows without natural scrolling. Native PS5.1 and PS7 unmocked 32-row probes fail at top=30; original aggregate has 17 shared failures.
- Expected behavior: append each logical/wrapped row through natural console scrolling; retain blank lines, all text, colors and actual cursor geometry for later in-place updates. Redirected/unsupported geometry remains append-only. Width changes must not leave a layout falsely addressable.
- Forbidden regressions: partial typed input, latest preview selection, HDR routing, Back/Skip/Use, gallery reopen disposal, narrow wrapping and marker/current-selection synchronization stay unchanged.
- Design boundary: Console.SetCursorPosition requires 0 <= top < BufferHeight and 0 <= left < BufferWidth; ordinary initial output must not depend on unbounded absolute rows. Governing source: https://learn.microsoft.com/en-us/dotnet/api/system.console.setcursorposition ; newline/scroll semantics: https://learn.microsoft.com/en-us/dotnet/api/system.console.writeline . Read governing API details before implementation.

## 5. Source/function ownership
- Files: TeknoParrot-Manager.ps1; Tests/TeknoParrot-Manager.Tests.ps1; focused finite-buffer regression file; relevant inventories, architecture, changelog, board and report.
- Functions: Write-TpmReShadeTerminalLines and necessary layout consumers only.
- Owning subsystem: ReShade terminal chooser.

## 6. Tests required before implementation
- Preserve Next-Qualification-Diagnosis.json/md and original aggregate failures outside source.
- Add and run finite-buffer regressions BEFORE source edit: start/near-bottom/exact-bottom/overflow, blanks/wrap, resize, redirected/unsupported geometry, later in-place update correctness.
- Preserve original chooser/HDR/input/gallery/reopen assertions. No enlarged infinite virtual buffer as boundary proof.

## 7. Tests required after implementation
- Focused finite-buffer regressions and actual visible native PS5.1/PS7 writer/chooser smoke.
- All original 17 shared failure cases; existing virtual-console, input, gallery/HDR and ownership regressions.
- Resize during initial rendering is now characterized before the additional consumer edit: ResizeDuringBefore fails 0 passed/1 failed on both native engines (expected a rebuilt layout, observed only the mixed-width initial block). The input contains partial `1` but no Enter before the gallery change, so no numbered-choice redraw masks the defect. Read-TpmReShadeTerminalProfile must retain pre-render dimensions for layout ownership, update only the self-induced viewport scroll origin, and reject/rebuild a draw whose dimensions changed instead of blessing post-render dimensions.
- The first terminal-fallback fixture mocks Read-HostSafe but originally leaves the native console attached. After the renderer fix it waits in real key polling instead of reaching that mock. Mark only that fixture's input as redirected, retaining all choice/Back assertions; do not alter the product input loop. An owned-window 3/U/B interaction completes the earlier diagnostic run, which is explicitly not hermetic qualification.
- Remove the incidental source-comment/cursor-wording assertion rather than re-pinning prose. Existing real input/backspace/partial-buffer and new finite-buffer post-scroll input assertions remain the behavioral contract; no consumer-visible assertion is removed.
- ASCII/parse, configured PSScriptAnalyzer, traced InjectionHunter, pinned Pester 5.7.1 main and one entire Tests folder per engine; permanent quality gate; independent gpt-6-astra review before final frozen qualification.

## 8. Documentation/report updates required
- Board/report: IDs 1/9, initially SOURCE REMEDIATION REQUIRED; no owner-runtime promotion from tests.
- Hunk classification: #323 / IDs 1,9 / this contract / TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-AUTH-001.
- Update applicable specification/invariant inventories before source edits; architecture and changelog with the final implementation.

## 9. Permanent procedure IDs affected
- TPM-TRACE-001, TPM-TRACE-002, TPM-EVIDENCE-001, TPM-AUTH-001, TPM-OWNER-001, TPM-OWNER-002.

## 10. Runtime smoke checklist
- Visible default and constrained finite-buffer chooser, scroll, gallery change while typing, Use/Back, reopening and HDR routing on disposable copied fixtures only.
- Record exact source manifest, engine, geometry, screenshots, commands and exits. Packaged proof requires separately satisfied package gates.

## 11. Stop condition
- Stop widening after the finite-buffer behavior, retained original assertions, focused native proof and required gates are complete. Keep uncertain package/owner acceptance separate.

## 12. Forbidden actions
- No original checkout or live TeknoParrot writes, real credential reads, provider changes, unrelated cleanup, commit/push, publication, tag/merge or live wiki changes.

## 13. Commit/package authorization status
- Commit authorized: No.
- Package requested: private local RC8 smoke candidate only, still subject to checklist section 4 clean/exact-SHA READY/human gates.
- Release/certification authorized: No.
