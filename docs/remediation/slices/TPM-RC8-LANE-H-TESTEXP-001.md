# TPM-RC8-LANE-H-TESTEXP-001 (slice contract)

Owner report IDs: none (test expectation hygiene caused by the progress-text helper change).
Scope: Tests\TeknoParrot-Manager.Tests.ps1 only. No product source change.

Failure: three It blocks extract or call `Get-TpmCompactProgressText`, which no longer exists.
Expected behavior: each assertion targets the live formatter `Format-TpmProgressLine` (scripts\TpmProgress.psm1) or is removed when it only checks wording.

Changes:
1. ~3608 "renders bounded compact progress": deleted (wording-only checks on removed helper).
2. ~3614 "truncates ... elapsed heartbeat": retargeted to Format-TpmProgressLine; Length -Be 40 kept; heartbeat check moved to an untruncated width-200 render.
3. ~22113 "renders an actual bounded progress bar": retargeted; bar, 50%, 5/10, phase label kept; Length -Be 100 became -BeLessOrEqual 100.
4. ~3619 "returns the bounded row from the actual writer": deleted the wording-only `Should -Match 'elapsed'` line; writer call and Length -Be 30 kept.

Forbidden regressions: no other assertion changed; no test weakened beyond the list above.
Tests: owner-gated. Not run. Expected to pass after the test run is authorized.
Stop condition: any retargeted block fails on Format-TpmProgressLine behavior, not wording.
