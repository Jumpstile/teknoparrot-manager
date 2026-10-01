# TPM Subsystem Ownership Map

| Subsystem | Source regions/functions | Owner IDs | Procedure IDs | Tests | Risk | Extraction recommendation |
|---|---|---|---|---|---|---|
| Prompt/navigation | Read-TpmChoice, Read-TpmYesNo, workflow/menu readers | 20,23,24,25,26,27,32 | TPM-TRACE-001, TPM-OWNER-001 | Prompt contracts | High | Prompt.Core first |
| Progress/status | Compact progress and workflow status helpers | 3-7,31 | TPM-TRACE-002 | Progress/source inventory | Medium | Progress.Core |
| Downloads/web | Invoke-TpmDownload and request wrappers | 2,8 | TPM-SECURITY-001 | Download/error tests | Medium | Download.Core |
| AutoSync | Select-GamesInteractive, Invoke-AutoSync, Register-Games | 4,17,19,22 | TPM-TRACE-002 | AutoSync/scoping tests | High | Keep integrated until prompt/repair contracts |
| Library Health Check/repair | Repair-GamePaths and health flow | 17-21 | TPM-OWNER-001 | Repair matrix | High | Repair.Core after characterization |
| ReShade | Invoke-ReShadeSetup, ownership/result helpers | 1,9-12 | TPM-OWNER-001 | Ownership/result tests | Very high | Extract last among workflows |
| Crosshair | Crosshair setup/browser/preview | 13-15 | TPM-OWNER-001 | Browser contracts | High | Separate after focus tests |
| dgVoodoo2 | Invoke-DgVoodoo2Setup | 31 | TPM-TRACE-002 | dgVoodoo2 tests | Medium | Feature module later |
| GPU Fix | Invoke-GpuFixSetup | 5 | TPM-TRACE-002 | GPU contracts | Medium | Feature module later |
| BepInEx | Invoke-BepInExUpdateCheck | 3,32 | TPM-TRACE-002 | BepInEx tests | Medium | Feature module later |
| FFB | FFB setup and download paths | 3,32 | TPM-TRACE-002 | FFB tests | Medium | Feature module later |
| PostgreSQL | Invoke-PostgresGameSetup and recovery | 16 | TPM-OWNER-001 | Recovery matrix | Very high | Extract after mutation contract |
| LaunchBox | Export/backup/restore functions | 23,24 | TPM-OWNER-001 | LaunchBox tests | High | FrontendExport.Core |
| HyperSpin | Export-HyperSpinJson | 25 | TPM-OWNER-001 | HyperSpin contracts | High | FrontendExport.Core |
| Support packages | New-TpmSupportPackage, manifest helpers | 27-29 | TPM-TRACE-001 | SupportPackage.Tests | Medium | SupportPackage.Core |
| Controls readiness | Controls propagation/result reporting | 30 | TPM-OWNER-001 | Controls matrix | Very high | ControlsReadiness.Core |
| Packaging/release gates | package validation and provenance reports | all runtime statuses | TPM-EVIDENCE-001 | Package/provenance checks | High | Package.Core last |
| Permanent procedure enforcement | Test-TpmPermanentProcedures, Run-TpmQualityGate | all | all applicable | Gate tests | High | Keep small and independently tested |
