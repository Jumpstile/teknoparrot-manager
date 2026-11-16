# Slice contract: TPM-RC8-FIXTURE-PG-DIAG-001

## Exact failure
The official V3 gate hung on the "unsupported 16-bit application" dialog. Test
`diagnoses the service, client tools, version, and failed database without changing state`
(Tests\TeknoParrot-Manager.Tests.ps1, around line 7351) creates a zero-byte
`pg_dump.exe`. It mocks only `Get-Service` and `Test-Path`. Production
`Get-PostgresBackupRepairDiagnosis` (TeknoParrot-Manager.ps1, around line 14883) then
runs `Invoke-PostgresNativeCommand` on that file, which executes the zero-byte binary.

## Expected behavior
The test never executes a fixture binary. `Invoke-PostgresNativeCommand` is mocked for
the `--version` probe. The existing assertions are unchanged.

## Scope
- Test file only. No product source change. No assertion change.
- Report ID: RC8 gate hang, V3 official gate (fixture hygiene).

## Forbidden regressions
- Do not weaken any `Should` assertion.
- Do not change `scripts\Run-TpmQualityGate.ps1`.

## Tests
- Targeted run of the single It block (process, fresh output name).

## Stop condition
Targeted test passes with no dialog. If the fix requires a product change, stop and report.
