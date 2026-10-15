# TPM S1 Update Version Ordering

## 1. Slice name

- Name: S1 manager update release-candidate ordering and identity verification
- Contract ID: TPM-S1-UPDATE-VERSION-ORDERING-001
- Issue/PR: supporting issue #105; PR #321 owner row 81 (startup/update flow) and RC8FullReview finding P1-1
- Permanent procedures: TPM-TRACE-001, TPM-EVIDENCE-001, TPM-OWNER-001

## 2. Owner report IDs included

- ID: PR #321 owner row 81 (startup/update flow)
- Supporting issue #105 covers the older `0.99.x` to `1.0-RC1` boundary and all updater paths. Its recorded equality of final `1.0` with `1.0-RC1` is a narrow historical assumption, superseded by the user-authorized RC8FullReview P1-1 remediation in PR #321 because RC7, RC8, and final 1.0 now need distinct identities.
Exact failure: the manager stores `1.0` in `$ScriptVersion` and `RC8` separately in `$ReleaseCandidateLabel`. Main and standalone updater comparisons previously discarded prerelease identity. Main candidate/install checks used raw-line regexes that match assignment-looking lines inside here-string data; the standalone helper uses a raw regex for local identity and only checks that candidate content contains a matching-looking `$ScriptVersion` line. Its apply path did not compare candidate identity with the release tag before replacement.
- Delta review report `TPM-7D92-DELTA-20261003` reviewed commit `7d92a3f2379038b9c1ba3e3750766e8cf1a5ac42` and found that `AssignmentStatementAst.GetAssignmentTargets()` returns a cast-wrapped `ConvertExpressionAst` for targets such as `[string]$script:ScriptVersion`; the variable-only filters skipped these writes. Both updater identity parsers accepted a typed scoped overwrite without executing the candidate. The before-fix regression evidence is recorded in the reconciliation report.

## 3. Explicit exclusions

- Owner IDs not included: all PR #321 rows other than owner row 81 for this update-version behavior.
- No changes to update retry policy, release discovery, download/backup/rollback safety, prompting, package contents, or unrelated release identifiers.
- Keep the main script self-contained; do not add a runtime import of `tools/TpmAutoUpdate.Core.psm1`.
- No package build, runtime smoke, owner smoke, Arcade, wiki, merge, tag, publication, certification, or release-readiness declaration. A commit and push to PR #321's existing head ref are authorized only after source gates pass, to obtain the requested exact-head CI.

## 4. Behavior contract

- Parse the numeric version base and the optional `RC<n>` label as separate identity components; do not discard the label when deciding update precedence.
- For a shared numeric base, order release candidates by their numeric ordinal, and order every RC below the final release: `1.0-RC7 < 1.0-RC8 < 1.0`. This explicitly supersedes issue #105's earlier final/RC equality assumption. Equal complete identities compare equal. Numeric-base ordering remains primary, so `0.99.99 < 1.0-RC1`.
- Both `Invoke-CheckForUpdates` and `Invoke-StartupUpdateCheck` offer an update only when the release tag is newer than the complete local identity.
- The standalone updater uses the same ordering behavior. Its local-version reader derives identity from unique direct top-level literal declarations, and apply mode requires the extracted candidate identity to equal the release tag before replacement.
- `Invoke-ManagerUpdateInstall` compares the release tag with the complete identity extracted from the candidate script and the complete identity read back from the installed script. An RC7 payload cannot validate as RC8 or final 1.0.
- Exact-equal and older releases remain no-op paths; existing transaction-result, backup, rollback, and user-facing safety behavior remains unchanged.

Forbidden regressions:

- Do not compare the numeric base alone in any update decision or installation identity check.
- Do not change `$ScriptVersion = "1.0"` or `$ReleaseCandidateLabel = "RC8"` to hide the ordering defect.
- Do not offer the same RC as an update, downgrade an RC8 installation to RC7, or treat an RC as newer than final 1.0.
- Do not couple the main script runtime to the standalone updater module.
- Do not weaken update asset, backup, final-hash, rollback, or cleanup validation.

## 5. System Invariant Inventory

| ID | Invariant | Required evidence |
|---|---|---|
| UVO-01 | Numeric version bases compare before prerelease labels. | `0.99.99` versus `1.0-RC1` comparator test |
| UVO-02 | For one base, RC ordinals compare numerically and final outranks every RC. | RC7/RC8/final ordering matrix |
| UVO-03 | Equal complete identities never produce an update. | Equal RC and equal final comparator/update tests |
| UVO-04 | Main and standalone local/candidate identities include `$ReleaseCandidateLabel`, derived from executable declarations rather than source-looking text; each candidate identity equals its release tag before replacement. | AST extraction, local-reader, candidate/tag rejection, and update-install validation tests |
| UVO-05 | Main menu, startup, and standalone updater paths implement the same precedence. | Focused tests for both comparator implementations and caller decisions |
| UVO-06 | Both script identity parsers never execute content and accept only one direct, unwrapped, unscoped root-level constant-string `=` declaration for `$ScriptVersion` and zero or one equivalent `$ReleaseCandidateLabel`; every other statically identifiable protected write (duplicate, scoped, nested, compound, wrapped, destructured, increment/decrement, foreach target, root parameter, data variable, or member/index lvalue rooted at the identity) fails closed. Parse errors and unsupported declaration shapes fail closed. | Parser-error, here-string decoy, AST-write matrix, validator, local-reader, and no-replacement regressions under both engines |
| UVO-07 | Both extracted-script validators reject bytes above `0x7F` before AST parsing, preserving the BOM-less ASCII source interpretation used by Windows PowerShell 5.1. | Valid-UTF-8 non-ASCII candidate rejection in both validators |

### UVO-08 trace record

| ID | Invariant | Status | Implementation pointer | Verification pointer |
|---|---|---|---|---|
| UVO-08 | Only a bare unwrapped/unscoped protected variable on the `Left` of one root `EndBlock` `Equals` assignment with a direct constant-string RHS can form the unique version declaration or optional label declaration. Resolve protected lvalue roots only through `AttributedExpressionAst.Child` (including casts), a one-command-expression transparent parenthesis, `MemberExpressionAst.Expression`, `IndexExpressionAst.Target`, and explicit `ArrayLiteralAst.Elements` destructuring containers reached through those forms. Reject protected targets found in any other assignment/destructuring, attributed or parenthesized target, member/index target, `++`/`--`, `foreach` variable, root `ParamBlockAst`, or `DataStatementAst.Variable`; do not scan function-local `ParameterAst` names or arbitrary AST descendants. Dynamic/indirect command and data-flow mutation is explicitly outside scope; this is not a sandbox. | Implemented in both parsers with iterative lvalue traversal; focused tests pass 6/6 main and 7/7 core under Windows PowerShell 5.1 and PowerShell 7.6.6. Final reviewer audit found no blocking findings; full suites and source gates remain pending. | `Get-ManagerScriptVersionIdentityFromContent`, `Get-TpmScriptVersionIdentityFromContent`; both parser test files and candidate no-replacement paths |

### Specification Inventory: PowerShell source AST declarations

| Governing source | Applicable contract |
|---|---|
| [Parser.ParseInput API](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.parser.parseinput?view=powershellsdk-7.6.0), [AssignmentStatementAst](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.assignmentstatementast?view=powershellsdk-7.6.0), and [StringConstantExpressionAst](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.stringconstantexpressionast?view=powershellsdk-7.6.0). | Both the self-contained main script and standalone updater module parse source into `ScriptBlockAst` and reject parse errors. Assignment targets are enumerated without invoking or evaluating candidate content. |
| `AssignmentStatementAst.Left`, `.Right`, `.Operator`, and `.GetAssignmentTargets()`; `StringConstantExpressionAst.Value`. | Accept only one direct, unwrapped, unscoped root-level `Equals` assignment whose whole `Left` is the protected `VariableExpressionAst` and whose direct RHS is a constant string AST. Enumerate `GetAssignmentTargets()` for direct `ArrayLiteralAst` destructuring; when a returned target unwraps transparently to `ArrayLiteralAst`, inspect only its `.Elements` iteratively. Never accept array/tuple targets as declarations. Zero or one equivalent label declaration is allowed. Reject every other protected assignment anywhere in the AST. |
| UVO-08 governing sources: [AttributedExpressionAst.Child](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.attributedexpressionast?view=powershellsdk-7.6.0), [ConvertExpressionAst.Child](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.convertexpressionast?view=powershellsdk-7.6.0), and [ParenExpressionAst.Pipeline](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.parenexpressionast.pipeline?view=powershellsdk-7.6.0). | Resolve target identity by unwrapping repeated attributed/cast children and only transparent one-command-expression parentheses. A protected leaf reached through any wrapper is rejected; arbitrary parenthesized pipelines are not searched. |
| [UnaryExpressionAst.Child and TokenKind](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.unaryexpressionast?view=powershellsdk-7.6.0), [ForEachStatementAst.Variable](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.foreachstatementast?view=powershellsdk-7.6.0), and [DataStatementAst.Variable](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.datastatementast?view=powershellsdk-7.6.0). | Reject protected prefix/postfix increment/decrement targets, foreach loop variables, and named data-statement variables. |
| [ParameterAst.Name](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.parameterast?view=powershellsdk-7.6.0), [MemberExpressionAst](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.memberexpressionast?view=powershellsdk-7.6.0), [IndexExpressionAst](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.indexexpressionast?view=powershellsdk-7.6.0), and [ArrayLiteralAst](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.arrayliteralast?view=powershellsdk-7.6.0). | Reject protected names only in root script `ParamBlockAst.Parameters`; function/scriptblock-local parameters do not bind the root identity (the actual manager has local parameters with both names). For member/index assignments, follow only `MemberExpressionAst.Expression` and `IndexExpressionAst.Target` plus transparent wrappers. Parenthesized array assignment is exposed as a transparent `ParenExpressionAst` around `ArrayLiteralAst`; recurse only through the array's lvalue `.Elements`. Never search member/index arguments or arbitrary descendants. |
| Finite static-analysis boundary. | Command/data-flow mutation (`Set-Variable`, variable-provider writes, `-OutVariable`-style parameters, `[ref]`, .NET/session-state APIs, aliases/splatting, dynamic names, dot-sourcing/imports, invoked scriptblocks, and `Invoke-Expression`) is explicitly outside this check; do not claim sandboxing or absence of indirect runtime mutation. |
| PowerShell 5.1 source-encoding rule for BOM-less scripts. | Extracted `.ps1` candidates must be ASCII bytes before source parsing. A UTF-8 decode followed by AST parsing is not accepted for non-ASCII bytes because Windows PowerShell 5.1 interprets BOM-less UTF-8 source through Windows-1252. |
| PowerShell parser representation of source constructs. | Comments and assignment-looking text inside string literals/here-strings are not executable assignment AST nodes and must not affect extracted identity. |

Deliberate boundary: this validates only a finite set of statically identifiable identity declarations and direct write AST forms. It does not execute, sandbox, resolve commands, or perform full data-flow analysis of a candidate. Indirect/runtime mutation through command invocation, dynamic scope, imports, dot-sourcing, scriptblock invocation, or .NET/session-state APIs is not proven absent.

Self-adversarial check: retain comment, ordinary quoted-string, and here-string decoys, repeated top-level assignments, scoped/nested/compound/nonliteral writes, and parser errors. Add sole and duplicate attributed/cast/parenthesized/nested/reordered targets; all four prefix/postfix `++`/`--` forms; scoped and parenthesized increments; foreach variables; root script parameters; named data statements; member/index target roots including nested selectors; direct array destructuring and parenthesized/nested tuple destructuring. Every proof fixture must parse with zero errors under both engines and either preserve only the canonical literal identity or fail closed; no candidate content is executed. Function- and scriptblock-local parameters named `ScriptVersion` or `ReleaseCandidateLabel` remain allowed; function-local names are exercised by the manager's existing identity helper.

## 6. Tests required before implementation

Before either production parser edit, add focused failing-before fixtures to both parser test files for the complete UVO-08 matrix. Include parser-valid direct attribute and parenthesized-attribute targets, both nested-wrapper orders, increment/decrement, foreach, root parameter binding, data-statement variable, member/index-root writes, direct array destructuring and parenthesized/nested array tuples, and existing duplicate/scoped/nested/compound/nonliteral/malformed forms. Each proof fixture must assert zero parser errors in both supported shells before asserting rejection. Include a near-miss member/index read rooted at an unrelated variable and a valid canonical declaration to prevent arbitrary descendant-search false positives.
Preserve the existing standalone reader and `-Apply` no-replacement before evidence. Main-script parser/validator/install before evidence is already recorded in the reconciliation report. Do not start a broad suite for diagnosis.
- Inventory every production use of the current comparators and the standalone updater's local-version parser before changing them.

## 7. Tests required after implementation

Focused tests cover RC7/RC8/final ordering, final update availability from an RC installation, equal full-version no-op behavior, `0.99.99` to `1.0-RC1`, here-string/comment/ordinary quoted-string decoys in both parsers, single-quoted literal identity including a successful main Apply install, and the full UVO-08 write matrix: sole/duplicate/scoped/nested attributed and parenthesized version/label targets; all four increment/decrement operators; foreach variables; root script parameters; data-statement variables; member/index root chains; direct and parenthesized/nested array destructuring; duplicate/scoped/nested/compound/nonliteral assignment rejection; parser errors; valid direct declarations; function- and scriptblock-local parameter plus unrelated member/index-read near-misses; validators; and install/apply no-replacement assertions. Add candidate/tag mismatch rejection in both apply paths, valid-UTF-8 non-ASCII candidate rejection in both validators, installed-version RC mismatch with matching candidate hash (fault-injected readback), successful RC8 installation with complete identity readback, and standalone runner decisions for RC7-to-RC8 and equal RC8.
- Run every `[UVO-08]` parser, validator, and no-replacement test under Windows PowerShell 5.1 and PowerShell 7.6.6. The new proof fixtures must have zero parser errors in both engines; full suite and final permanent procedure gate run only after the final reviewed source/test hashes are stable.
- Verify menu-triggered, startup, and standalone update decisions use complete identities; standalone apply rejects mismatched and non-ASCII candidates before replacement; existing transaction outcomes remain unchanged; source extraction never evaluates candidate content.
- Run the focused version-ordering tests in both test files; run the full required source-quality gates before committing.
- `Tests/TpmAutoUpdate.DestructivePath.Tests.ps1` supplies the expected release identity to its mocked apply-validation harness.


## 8. Documentation and report updates required

- Update the RC8 candidate changelog, `ARCHITECTURE.md`, `SECURITY.md`, `docs/AUTO_UPDATE.md`, `README.md`, and `TeknoParrot-Manager-README.txt` with the exact release-candidate ordering and identity-validation invariant.
- Update `docs/remediation/PR-321-control-board.md`, `docs/remediation/PR-321-reconciliation.md`, and `docs/remediation/slices/PR-321-current-slice.md` with the owner mapping, exact hunk classification, test evidence, exact source identity, and non-actions.
- Hunk mapping: owner row 81; PR #321 review finding P1-1; issue #105 is supporting context only, and its old final/RC equality assumption is superseded; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`. Behavioral test hunks additionally map to `TPM-EVIDENCE-001`. Owner-runtime evidence remains governed by `TPM-OWNER-001` and must not be inferred from source or CI tests.
- Delta source and test hunk mapping: review report `TPM-7D92-DELTA-20261003`; PR #321 owner row 81; supporting issue #105; PR #321; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`; behavioral regressions `TPM-EVIDENCE-001`. Owner-runtime proof remains governed by `TPM-OWNER-001` and is not established by these source tests.

- Delta documentation hunk mapping: report `TPM-7D92-DELTA-20261003`; PR #321 owner row 81; supporting issue #105; PR #321; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`. Files: `ARCHITECTURE.md`, `SECURITY.md`, `docs/AUTO_UPDATE.md`, `docs/wiki-updates/Check-for-Updates.md`, `README.md`, `TeknoParrot-Manager-README.txt`, `TeknoParrot-Manager-CHANGELOG.txt`, control board, reconciliation report, and current-slice pointer.

## 9. Runtime proof checklist

- This source-only task does not authorize a package or owner/runtime smoke. No packaged-runtime claim may be made.
- Required source proof: focused behavior tests, full source-quality gate, exact source SHA, and fresh CI checked out at that exact SHA.
- Owner/runtime proof remains paused and requires separate authorization and an exact package identity.


## 10. Stop condition

Stop after every in-scope updater path compares complete identities, candidate and installed validation include the RC label, focused and required source gates pass, the remediation report validates, the exact PR-head SHA is recorded, and CI proves that exact source tree. Stop on any unmatched source hunk, version identity mismatch, or failed quality gate. Do not claim release readiness.

## 11. Hunk classification

- `TeknoParrot-Manager.ps1` version parser/comparator, local identity, candidate identity, installed identity, and update callsites: owner row 81; PR #321 review finding P1-1; supporting issue #105 with its prior final/RC equality assumption superseded; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`.
- `tools/TpmAutoUpdate.Core.psm1`, `tools/Invoke-TpmAutoUpdate.ps1`, and standalone updater tests: owner row 81; PR #321 review finding P1-1; supporting issue #105 with its prior final/RC equality assumption superseded; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`; behavioral test changes also map to `TPM-EVIDENCE-001`.
- Architecture, security, updater design docs, user readmes, changelog, board, report, and current-slice pointer changes: owner row 81; PR #321 review finding P1-1; supporting issue #105 with its prior final/RC equality assumption superseded; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`.
- `scripts/InjectionHunterDispositions.psd1`: owner row 81; PR #321 review finding P1-1; `TPM-S1-UPDATE-VERSION-ORDERING-001`; `TPM-TRACE-001`. Remove obsolete fixed-literal regex dispositions for the replaced main comparator and standalone release-tag stripping; relocate the single remaining formatting-expression disposition to its current source line. No new scan finding is given a disposition.

## 12. Authorization status

- Source and deterministic test changes: authorized for this slice.
- Commit/push: authorized only to update PR #321's existing head ref after required source gates pass, to obtain exact-head CI.
- Package, runtime owner smoke, merge, tag, release, certification, wiki, and publication: not authorized.
