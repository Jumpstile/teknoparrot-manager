# TPM Remediation Slice Contract

## 1. Slice name
- Name: Preserve Windows Terminal character viewport at startup.
- Contract ID: TPM-WT-VIEWPORT-PRESERVATION-001.
- Issue/PR: #323 / ARC-UX-S01; #290 genuine menu image dependency.

## 2. Owner report IDs included
- ARC-UX-S01: giant empty frame and lost/clipped menu after startup.
- Actual owned Windows Terminal launches requested 120x40 but main resized the native viewport to 1904x993 before the menu. A separate getter-only probe observed Window/Buffer 120x40, MaxPhysical 1904x993, MaxWindow 120x40 and WT_SESSION present.

## 3. Explicit exclusions
- No other owner IDs, menu action changes, game launches, live runtime writes, original checkout writes, release, tag, commit or public publication.
- Controls explanation correction belongs separately to TPM-RC8-DOCS-SAFETY-RECONCILIATION-001 / owner 30,32 / #290,#255,#323.

## 4. Behavior contract
- Current failure: startup treats Windows Terminal MaxPhysicalWindowSize as an instruction to enlarge its character viewport.
- Expected: when WT_SESSION identifies Windows Terminal, preserve its terminal-managed viewport and buffer. For legacy ConHost retain best-effort grow-buffer-before-window, once-only guard and logged exception behavior.
- Forbidden regressions: changing Windows Terminal dimensions, lost choices/prompt, repeated cosmetic resize, removed legacy resizing, swallowed new errors, public configuration or feature additions.
- Optional nullable internal TerminalManaged parameter exists only to exercise both branches independently of the test runner terminal. Omitted uses WT_SESSION presence. This is cosmetic host identity, never security authority.

## 5. Source/function ownership
- TeknoParrot-Manager.ps1: Set-ConsoleMaximizedIfSupported only.
- Tests/TpmConsoleViewport.Tests.ps1 and existing legacy resize test call in Tests/TeknoParrot-Manager.Tests.ps1.

## 6. Tests required before implementation
- Default WT_SESSION detection must fail against baseline41BB with inflated fake 1904x993 maximum; explicit terminal-managed branch also must fail.
- Characterize legacy ordering, once guard, invalid maximum and exception logging; preserve existing central assertions.

## 7. Tests required after implementation
- Focused tests on PS5.1 and PS7; existing central resize case explicitly legacy.
- Parent runs full folder once final source and genuine image are frozen; ASCII, parse, project analyzer, InjectionHunter and procedure gate remain required.

## 8. Documentation/report updates required
- Documentation agent serializes board/report/architecture mapping for ARC-UX-S01 / #323 / this contract; captured evidence is separated from final package certification.

## 9. Permanent procedure IDs affected
- TPM-UX-001, TPM-TRACE-001, TPM-EVIDENCE-001, TPM-OWNER-001, TPM-OWNER-002, TPM-OWNER-003.

## 10. Runtime smoke checklist
- Run exact unchanged full staged main with controlled real TP marker/profile fixture; capture real default120x40 and constrained100x25 console/window after source review.
- Record source/script/engine/stage/image hashes and actual dimensions. Bootstrap capture is not final package proof; final ZIP byte/extraction equality and other #323 branches remain separate.
- User authorized isolated candidate fixes/tests and controlled own runtime evidence; live installation is read-only.

## 11. Stop condition
- Stop after focused green, independent review, actual unchanged viewport evidence and genuine menu image; parent owns broader gates.

## 12. Forbidden actions
- No original/live writes, real game execution, unrelated window closure, policy bypass, release/tag/commit/push, general terminal fallback or unrelated behavior.

## 13. Commit/package authorization status
- Local fix/test/capture authorized. No commit, release, tag or publication authorization.

## Specification inventory
| ID | Primary source / fact | Requirement | Application |
| --- | --- | --- | --- |
| SPEC-WT-01 | https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.host.pshostrawuserinterface | WindowSize is character cells; MaxPhysical ignores buffer dimensions | Do not use hardware maximum as WT viewport intent |
| SPEC-WT-02 | https://github.com/microsoft/terminal/blob/main/doc/specs/%235000%20-%20Process%20Model%202.0/%234472%20-%20Windows%20Terminal%20Session%20Management.md | WT_SESSION represents a Windows Terminal session | Narrow WT cosmetic resize exception |
| SPEC-WT-03 | rawui-owned-terminal-probe.json and two failed full-main stages | Actual WT120x40 exposes MaxPhysical1904x993 and main consumes it | Regression fixture uses actual observed values |

## System invariant inventory
| ID | Invariant | Proof |
| --- | --- | --- |
| INV-WT-01 | Terminal-managed buffer/window remain unchanged | default detection and explicit branch tests; actual full main capture |
| INV-WT-02 | Legacy buffer grows before window and only once | setter-order test and preserved central assertions |
| INV-WT-03 | Invalid/throwing legacy host remains best effort | no-setter invalid case; logged exception case |
| INV-WT-04 | No runtime menu/function mocking in screenshot | unchanged full main hash; real native console buffer and foreground HWND screenshot |
