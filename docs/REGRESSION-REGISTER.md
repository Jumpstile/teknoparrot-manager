# Regression Coverage Register

This file's content moved to `docs/REGRESSION_MATRIX.md` (Documentation
Certification pass, v0.99.45 BETA) -- the two files tracked the same "every
confirmed bug fix needs a regression test and a row" goal under two
independently-drifting tables, which meant a reader had no way to know which
one to check. `REGRESSION_MATRIX.md` is now the single canonical regression
tracking document; this file is kept only because `Tests/QualitySystem.Tests.ps1`
asserts it exists.

## Workflow

1. Add or update a regression test.
2. Add or update `docs/REGRESSION_MATRIX.md`.
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
