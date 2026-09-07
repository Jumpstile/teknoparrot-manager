# PR-321 Current Slice: Prompt.Core and Navigation Consistency

- Slice ID: TPM-PROMPT-001
- Slice name: Prompt.Core centralized enumerated-choice validation and prompt inventory
- Included owner-report IDs: 24, 25, 26, 27, and the prompt/navigation portion of 32.
- Explicit exclusions: ReShade protected ownership and accounting (11, 12), universal progress (3), controls truthfulness (30), packaging, release, certification, owner-runtime smoke, ARCADE/#323, wiki, commit, and push.

## Contract

- `Read-TpmYesNo` owns ordinary Y/N decisions.
- `Read-TpmChoice` owns finite enumerated choices. It normalizes case, applies an allowed default, and keeps invalid input on the same prompt until an allowed value is entered.
- Enumerated Back, Skip, Cancel, Preview, Run, Details, retry, and optional-setup routes use the centralized reader where the route has a finite contract.
- Exact-token confirmations (`YES`, `REMOVE`), free text, secure password input, paths, search terms, numeric ranges, and renderer-aware keyboard input remain explicit contracts rather than being forced through a one-letter reader.
- Back, Skip, Cancel, and Preview do not mutate state before their route is selected. Support `O` opens the generated package folder; `B` returns without opening it.
- HyperSpin missing-emulator-ID handling accepts only `G` (guidance) or `S` (skip) and never synthesizes an emulator ID.

## Prompt inventory and classification

The inventory below covers every user-facing prompt in `TeknoParrot-Manager.ps1`, including prompts that intentionally remain outside `Read-TpmChoice`.

### Centralized finite choices in this slice

- LaunchBox: `P/A/F/B` top-level action, detected-root number or `N`, and platform `1-4`.
- HyperSpin: missing emulator ID `G/S`.
- Support: main `1-3` and final package action `O/B`.
- AutoSync and setup gates: preview `P/R/B`; Eggman DAT `D/B/N`; maintenance `N/A/B`; startup update `Y/N/V`; BepInEx approval `Y/R/N`; ReShade custom preset `Y/S/B`, bulk `Y/S/B/D`, conflict `A/K/S/B/D`, and result actions; dgVoodoo2 acquisition/result actions; GPU result actions; FFB membership `Y/N` and missing-path `H/B`.
- Repair and recovery: Health Check finite action menus, scoped recopy choices, PostgreSQL backup/recovery choices, password reset `Y/B`, password-mismatch `T/B`, staging boundary `R/Q` and `R/Z/Q`, restore `1-3`, preview apply `Y/N`, and conflict resolution `K/S/Q`.
- Retry/result menus use dynamic allowed arrays when a path issue or detected root changes the available choices. The helper remains the single validation path.

### Free-text, path, secure-input, and numeric contracts

- `Read-PathWithBrowse` and `Read-TpmStagingFolder`: folders/files, browse fallback, Enter defaults, and path safety validation.
- Search keyword, game-folder search root, custom LaunchBox platform name, GPU vendor, ReShade preset path, DAT import path, and other operator-supplied names.
- PostgreSQL passwords and other secret-bearing fields use their secure/password-specific input path.
- Crosshair P1/P2 indices, profile-number repair selection, backup restore numbers, and game-number lists carry range or blank semantics and retain specialized validation.
- AutoSync selection numbers and combined selections allow number lists, ranges, search-again, and stateful selection; they are not one-letter choices.

### Exact-token safety contracts

- ReShade removal requires the exact `REMOVE` token.
- PostgreSQL reinitialization and restore destructive actions require exact `YES`.
- These prompts are intentionally not treated as casual enumerated choices.

### Runtime-only or renderer-aware input

- `Read-MainMenuChoiceResponsive` uses keyboard polling, redirected-input fallback, and menu redraw state.
- ReShade terminal profile selection and preview use terminal key handling and custom redraw behavior.
- Enter-only acknowledgement/return prompts, Enter-or-N wait/retry prompts, browser/process wait prompts, and window-resize prompts are runtime navigation controls, not finite business decisions.

### Design boundaries retained for follow-up

- AutoSync page/search pickers (`Select-GamesInteractive`, `Select-GamesForAutoSync`, and combined selection) retain command keys plus free-text search and number-list input.
- Crosshair preview/browser interaction and the ReShade terminal selector retain their renderer-aware input contracts.
- Path/vendor/password and exact-token prompts retain their specialized safety semantics.
- Every remaining raw `Read-HostSafe` call is in one of the free-text, exact-token, runtime-only, or stateful-picker categories above; no unclassified finite choice is being silently treated as fixed.

## Files allowed to change

- `TeknoParrot-Manager.ps1`: `Read-TpmChoice` and finite-choice call sites only.
- `Tests/TeknoParrot-Manager.Tests.ps1`: helper behavior and prompt-route contract coverage.
- `ARCHITECTURE.md`: Prompt.Core finite-choice invariant and deliberate boundaries.
- `README.md`, `QUICKSTART.md`, `TeknoParrot-Manager-README.txt`, `TeknoParrot-Manager-QuickStart.txt`: corrected frontend prompt instructions.
- `docs/remediation/PR-321-control-board.md`
- `docs/remediation/PR-321-reconciliation.md`
- this slice contract and the permanent procedure gate only where needed to enforce this slice ID.

No ReShade ownership/accounting, controls, package, release, or runtime-evidence files are in scope.

## Tests required

- Focused `Read-TpmChoice` and prompt-route Pester tests.
- Main Pester suite, SupportPackage.Tests, production/test parse, ASCII, PSScriptAnalyzer with `PSScriptAnalyzerSettings.psd1`, `git diff --check`, and the permanent procedure gate.
- The gate must continue to fail closed for unresolved owner IDs, stale candidate identity, and missing owner-runtime evidence.

## Runtime proof required

None authorized in this slice. Owner runtime proof still requires a freshly built package tied to an exact source SHA and a checklist covering LaunchBox Back, HyperSpin normal completion, invalid choice reprompting, and Support `O/B`.

## Stop condition

Stop after the finite-choice helper, feasible finite-choice routes, exhaustive prompt classification, focused source/behavior tests, control-board mapping, reconciliation hunk mapping, and expected-fail gate evidence are current. Do not claim global ID 32 closed while stateful picker and owner-runtime evidence remain outstanding.

## Forbidden actions

No commit, push, package, release, certification, wiki, owner smoke, ReShade ownership/accounting work, controls work, ARCADE/#323 work, or broad picker redesign.

## Gate expectations

The gate must pass the new slice-ID and prompt-contract checks while failing closed for unresolved `NOT FIXED` rows, `SOURCE FIXED; OWNER RUNTIME NEEDED` rows, stale candidate identity, and absent owner-runtime proof.
