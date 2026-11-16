# TPM-RC8-LANE-R-331 -- Startup migration continues past DESTINATION_OCCUPIED

## Owner issue
GitHub issue #331 (owned-state migration at startup).

## Failure
`Test-TpmOwnedMigrationStartupAllowed` (TeknoParrot-Manager.ps1 ~583-595) allows startup for any
migration result except Outcome `ACTION_REQUIRED` or ProductState `UNKNOWN`. A
`DESTINATION_OCCUPIED` result (FAILED_BEFORE_MUTATION / UNCHANGED, emitted ~503) passes. Startup
then switches `$script:TpmOwnedLayout.ConfigPath` (~32383) to the managed config and runs
the unconditional `Save-Config` (~32419), overwriting a distinct managed config that the migration
refused to replace.

## Expected behavior
- `DESTINATION_OCCUPIED` blocks startup: the existing exit path at ~32370-32374 runs before path
  reassignment or `Save-Config`.
- All other migration outcomes keep their current behavior.

## Change
One bounded hunk in `Test-TpmOwnedMigrationStartupAllowed`: add
`-and [string]$MigrationResult.ReasonCode -ne 'DESTINATION_OCCUPIED'` to the predicate.

## Forbidden regressions
- No change to migration copy/move logic or to the DESTINATION_OCCUPIED detection itself.
- No new fallback path that silently uses the legacy config.

## Verification
Owner hold: no tests, gates, or smoke run in this lane. Main agent runs the standard
parser/ASCII, PSScriptAnalyzer and Pester checks after integration.

## Stop condition
Predicate hunk applied; file remains pure ASCII. Destination-verification hardening beyond the
predicate is out of scope for this slice.
