# Required-patch Schema-1/2 Operation-Shape Specification Inventory

Status: Required, focused inventory for Issue #351 slice TPM-REQUIRED-PATCH-SCHEMA2-CREATEFILE-001. It covers only the schema-1/2 single-operation validator surface affected by the CreateFile precondition check; it does not inventory schema-3 transaction or recipe families.

## Component and boundary

The component is Get-TpmPatchPlan in scripts/TpmRequiredPatchEngine.ps1. Its internal catalog format is defined by the operation validator and the existing schema-1/2 catalog/test fixtures. The finding is that the validator accepts a CreateFile shape without BeforeSha256 but its shared no-op expression reads that absent field. Existing System Invariant Inventory NRP-9 continues to govern schema compatibility; this specification inventory records the relevant operation fields and relation rules.

## Specification Inventory (REQUIRED)

| ID | Rule / source | Status before correction | Implementation pointer | Verification pointer | Trace |
|---|---|---|---|---|---|
| CATOP-SPEC-001 | Schema 1 and 2 entries contain exactly one operation; supported operation types are ReplaceFile and schema-2 CreateFile. | Existing validator guard | Get-TpmPatchPlan operation count and type checks | Existing schema-1/2 compatibility case; not run in this task | Issue #351 / TPM-REQUIRED-PATCH-SCHEMA2-CREATEFILE-001 / TPM-TRACE-001 |
| CATOP-SPEC-002 | ReplaceFile requires exactly Type, Target, BeforeSha256, AfterSha256, Payload, and PayloadSha256. | Existing field validator; no change intended | Assert-TpmPatchFields | TPM-CAT-OP-004 and TPM-CAT-OP-005; not run | Issue #351 / slice / TPM-EVIDENCE-001 |
| CATOP-SPEC-003 | Schema-2 CreateFile requires exactly Type, Target, BeforeState, AfterSha256, Payload, and PayloadSha256; it has no BeforeSha256 field. | Existing field validator; shared comparison is incorrect under strict mode | Assert-TpmPatchFields and the conditional no-op comparison | TPM-CAT-OP-001 and TPM-CAT-OP-002; not run | Issue #351 / slice / TPM-TRACE-001 |
| CATOP-SPEC-004 | CreateFile BeforeState must equal Absent. | Existing explicit state check | Get-TpmPatchPlan | TPM-CAT-OP-002; not run | Issue #351 / slice / TPM-EVIDENCE-001 |
| CATOP-SPEC-005 | Required operation values are strings; executable, after, payload, and replacement-before pins are 64-digit hexadecimal SHA-256 values. | Existing validation; no change intended | Get-TpmPatchPlan content-pin checks | Existing catalog validation coverage; not run in this task | Issue #351 / slice / TPM-TRUTH-001 |
| CATOP-SPEC-006 | AfterSha256 equals PayloadSha256 for both operation types; only ReplaceFile compares BeforeSha256 with AfterSha256 and rejects equal before/after pins. | Existing payload relation guard; no-op guard needs CreateFile-aware access | Get-TpmPatchPlan no-op/content-pin expression | TPM-CAT-OP-003, TPM-CAT-OP-004, and TPM-CAT-OP-005; not run | Issue #351 / slice / TPM-EVIDENCE-001 |
| CATOP-SPEC-007 | CreateFile planning requires the existing target parent and accepts only an absent target or exact after-state; other states fail closed. | Existing planner behavior; no change intended | Get-TpmPatchPlan target-state checks | Existing schema-2 absent-file planner case; not run in this task | Issue #351 / slice / TPM-TRUTH-001 |

## Deliberately out of scope

- Schema-3 multi-operation catalogs, variant resolution, self-executable replacement, receipt composition, and transaction semantics.
- Catalog entries, source ZIP contents, runtime/package verification, and all operation types other than ReplaceFile and schema-2 CreateFile.
- Changes to the existing NRP-3/NRP-9 invariant meanings.

## Review and verification boundary

The inventory identifies the applicable operation-shape rules for this correction and maps each changed behavior to actual-planner regressions. Test execution, parse checks, static analysis, the permanent quality gate, and independent review were not performed in this task. No Review Ready, package, runtime, owner, or release result is claimed.