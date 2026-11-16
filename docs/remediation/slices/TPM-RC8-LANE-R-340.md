# TPM-RC8-LANE-R-340 -- Health report labels stopped PostgreSQL as running

## Owner issue
GitHub issue #340 (health diagnostic truthfulness), F10.

## Failure (fixed in this slice)
`Test-PostgresInstalled` (TeknoParrot-Manager.ps1 ~14835-14838) checks only that the service
object exists and that psql.exe is present; it never checks service status. The Health
report (~26720-26722) printed "installed and running" for any installed service, including a
stopped one.

## Expected behavior (fixed in this slice)
- Health reports "not installed" when the service is absent.
- Reports "installed and running" only when the service status is Running.
- Reports "installed, not running" when the service exists but is not Running (yellow).
- No service action (start/stop/install) is taken.

## Change
One bounded hunk at the Health PostgreSQL label (~26722): compute the running state from
`Get-Service` and derive the label and color. `Test-PostgresInstalled` is unchanged, so its
install/recovery/setup callers keep their current semantics.

## Not in this slice (CONFIRMED-UNFIXED)
Silent partial profile inventory in Invoke-LibraryHealthCheck (~26570 uses
`-EnumerationErrorAction SilentlyContinue`) with no Complete/Error/Unknown inventory state
and all-clear suppression. That needs a multi-site change across discovery, counts, and
all-clear logic, so it is not one bounded hunk and is left for a separate slice.

## Forbidden regressions
- No change to `Test-PostgresInstalled` return semantics or to install/recovery flows.
- No new service mutation.

## Verification
Owner hold: no tests, gates, or smoke run in this lane. Main agent runs the standard
parser/ASCII, PSScriptAnalyzer and Pester checks after integration.

## Stop condition
Label hunk applied and file remains pure ASCII.
