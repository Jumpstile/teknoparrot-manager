# RC8 documentation safety and controls invariant inventory

Mapping: TPM-RC8-DOCS-SAFETY-RECONCILIATION-001 / #290 / #255 / #323 / owner IDs 30, 32 where applicable / TPM-TRACE-001 / TPM-EVIDENCE-001 / TPM-TRUTH-001 / TPM-UX-001.

| ID | Required invariant | Source evidence | Planned verification |
|---|---|---|---|
| DOC-1 | Extraction residue is not called clean or automatically removed. | Stale-marker preflight returns ACTION_REQUIRED/UNKNOWN and retains residue. | Source-backed page and guide sweep. |
| DOC-2 | forceArchetype is controls-only, not a registration matching override. | Register functions have no parameter; core propagation consumes the map. | Remove wrong-match pin advice across all four guides and staged pages. |
| DOC-3 | Existing button bindings and possible InputAPI corrections are distinguished. | Bound-button skip and api-fixed/api-fixed-canonical branches. | Explanatory source paragraph and document sweep; independent review. |
| DOC-4 | Standalone propagation describes one approval after reviewing references. | One Read-TpmYesNo before Invoke-ControlPropagation. | Source and staging page review. |
| DOC-5 | Unknown ownership or preserved backup state is not replaced by filename-based deletion instructions. | Backup-before-write and filesystem ownership guards remain unchanged. | Safety wording review. |
| DOC-6 | Documented paths follow actual callers, not an architectural aspiration alone. | Config/log use owned layout; overrides and controls report still use PSScriptRoot. | Trace each changed path claim to source. |
| DOC-7 | Documentation review does not imply runtime, package or release readiness. | #323 workflow and exact-source gates. | Keep explicit remaining-gate record. |