# Regression Coverage Register

This is the central checklist for bug fixes and their automated coverage.

Rule: every confirmed bug fix needs a regression test and a row in this file.

## Status

- Pending Fix: test exists and currently exposes the bug.
- Covered: test passes and protects the fixed behavior.
- Needs Test: bug is known but coverage has not been added yet.
- Investigation: behavior still needs confirmation.

## Entries

| Area | Risk | Expected behavior | Test file | Status |
|---|---|---|---|---|
| Issue 80 normalization | Board or revision tokens can remain in normalized game keys. | Affected folder names normalize to the same key as their canonical title. | `Tests/KnownBugRegression.Tests.ps1` | Covered |
| Zoids title safety | EX Plus could be collapsed into plain Zoids Infinity. | EX Plus remains distinct from plain Zoids Infinity. | `Tests/KnownBugRegression.Tests.ps1` | Covered |
| Edition title safety | Meaningful parenthetical title text could be stripped. | Meaningful edition text remains distinct. | `Tests/KnownBugRegression.Tests.ps1` | Covered |
| Rev-letter safety | Bare Rev-letter tokens could be stripped too broadly. | Rev-letter tokens remain preserved. | `Tests/KnownBugRegression.Tests.ps1` | Covered |

## Workflow

1. Add or update a regression test.
2. Add or update this register.
3. Implement the fix.
4. Run the validation suite.
5. Mark the entry Covered only after the suite passes.

## Tester command

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\Run-TPM-Tests.ps1 -TeknoParrotRoot "<path to a real TeknoParrot install>"
```
`-TeknoParrotRoot` is mandatory and has no default -- see
`scripts/Run-TPM-Tests.ps1`'s own comment for why a prior default silently
pointed at a location that was never a real TeknoParrot install on any
machine this was run from.
