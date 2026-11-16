# TPM-RC8-LANE-R-334 -- Control propagation reports settings-only writes as unchanged

## Owner issue
GitHub issue #334 (control propagation transaction result).

## Failure
`Invoke-ControlPropagation` (TeknoParrot-Manager.ps1 ~27665) derives `$changed` only from
statuses `bound`, `api-fixed`, `api-fixed-canonical`. A profile whose status is
`settings-only` is written to disk by `Save-XmlMaybe` (Invoke-ControlPropagationLegacy ~27933)
but is absent from `$changed`. When every written profile is `settings-only`, the outcome
becomes `FAILED_BEFORE_MUTATION` with `ProductState UNCHANGED` and `MutationStarted` false,
although profile files changed.

## Expected behavior
- `settings-only` profiles count as written: outcome, ChangedItems, CompletedItems,
  MutationStarted and ReasonCode treat them as changed.
- `BoundCount` continues to count only bound/api-fixed games (control bindings), so the
  reported bound count does not inflate.
- DryRun still yields NO_OP with no changed items.

## Change
One bounded hunk in `Invoke-ControlPropagation`: add `$written` (bound, api-fixed,
api-fixed-canonical, settings-only) and use it in the outcome and transaction call.

## Forbidden regressions
- No change to per-profile bind/copy logic or to `Write-ControlPropagationResults` output text.
- No change to backup creation or to `BoundCount`.

## Verification
Owner hold: no tests, gates, or smoke run in this lane. Main agent runs the standard
parser/ASCII, PSScriptAnalyzer and Pester checks after integration.

## Stop condition
Hunk applied and file remains pure ASCII; any further control-propagation redesign is out of scope.
