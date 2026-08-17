# Phase 0 system invariant inventory

| ID | Invariant | Enforcement | Evidence required |
| --- | --- | --- | --- |
| INV-001 | The plugin is presentation/orchestration only; TPM remains the source of truth. | Native code calls the explicit TPM contract and contains no TPM matching, registration, backup, transaction, controls, ReShade, dgVoodoo2, or compatibility rules. | Source review and contract tests. |
| INV-002 | Phase 0 reads no LaunchBox data and calls no LaunchBox save/reload/write API. | No `IDataManager` reference is used by the POC. Selected-game work is deferred. | Source scan and no-write snapshot. |
| INV-003 | The read-only operation writes only the caller-owned isolated request/result temp files. | Contract mode bypasses normal startup/logging; result-path overlap with TeknoParrot/UserProfiles is rejected. | Before/after byte and metadata snapshot. |
| INV-004 | No game, profile, configuration, registry, or Windows-global setting is modified. | `Invoke-LibraryHealthCheck -Structured` reuses read-only checks; `Write-Log` is disabled in contract mode. | Fixture and real-install snapshots when available. |
| INV-005 | Discovery never guesses when zero or multiple candidates exist. | `TpmDiscovery` returns `TPM_NOT_FOUND` or `*_DISCOVERY_AMBIGUOUS`. | Core discovery self-test and failure matrix. |
| INV-006 | Incompatible, malformed, truncated, or mismatched contract output is rejected. | `TpmFrontendContractValidator` checks version, exact top-level fields, operation, correlation, status, and flags. | Core self-test and Pester matrix. |
| INV-007 | Long-running or cancelled calls cannot remain unbounded. | `TpmProcessRunner` uses a linked cancellation token, 60-second timeout, and process-tree kill. | Timeout/cancel tests against the runner. |
| INV-008 | Returned diagnostics contain no secrets or unnecessary local paths. | TPM result contains counts and stable codes only; process runner does not return stdout/stderr or request paths. | Contract schema/source review. |
| INV-009 | Existing standalone TPM behavior remains unchanged unless the explicit contract parameters are supplied. | Contract branch is before normal menu/config flow; normal `Write-Log` behavior is unchanged outside contract mode. | Existing full Pester suite and explicit standalone smoke check. |
