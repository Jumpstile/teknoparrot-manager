# Phase 0 failure matrix

| Case | Expected stable outcome | Evidence in this spike |
| --- | --- | --- |
| TPM script not found | `TPM_NOT_FOUND` | Core self-test and source-level discovery gate. |
| TeknoParrot root not found | `TEKNOPARROT_NOT_FOUND` | Focused Pester test. |
| Multiple TeknoParrot roots | `TEKNOPARROT_DISCOVERY_AMBIGUOUS` | Core discovery self-test. |
| Unsupported contract version | `CONTRACT_UNSUPPORTED_VERSION` | Focused Pester test and C# validator test. |
| Unsupported operation | `OPERATION_UNSUPPORTED` | TPM adapter validation branch; covered by source review. |
| Malformed or truncated request JSON | `REQUEST_MALFORMED` | Focused Pester test under PowerShell 5.1 and 7. |
| Mismatched request correlation | `CORRELATION_MISMATCH` | Focused Pester test under PowerShell 5.1 and 7. |
| Malformed or unknown-field result JSON | `RESULT_MALFORMED` / `RESULT_SCHEMA_INVALID` | C# core self-test. |
| Missing result file | `RESULT_MISSING` | C# process-runner self-test. |
| TPM executable cannot start | `TPM_PROCESS_FAILED` | C# process-runner self-test with an invalid executable path. |
| Timeout | `TPM_TIMEOUT` | C# process-runner self-test with a sleeping child process. |
| User cancellation | `TPM_CANCELLED` with `cancelled=true` | C# process-runner self-test. |
| Paths containing spaces | success with structured evidence | Focused Pester fixture and manual PowerShell 5.1 smoke. |
| Result path overlaps TeknoParrot/UserProfiles | nonzero exit and no result write | Focused Pester test. |
| LaunchBox/plugin process lacks write permission for isolated temp | `ACCESS_DENIED` | Catch path is implemented; real ACL test is blocked in this environment and remains a host-machine gate. |
| Native API assembly missing | build fails closed | Native project build verified the explicit missing-assembly error. |
| LaunchBox/Big Box callback loading | global menu source is present; runtime callback unverified | No LaunchBox installation is present. |

## No-write evidence

The focused Pester success test snapshots LaunchBox Data, the TeknoParrot
root and UserProfiles, the selected-game folder, and representative TPM state
before and after the child-process call. File SHA-256, length, creation time,
last-write time, attributes, and tree structure remained equivalent. Directory
last-access bookkeeping is not treated as a data mutation because Windows can
update it as a consequence of read enumeration; directory creation time,
attributes, and structure are still checked.
