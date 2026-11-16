# Certification worker bootstrap specification and invariant inventory

Originally created before source edits, 2026-10-24. Owner 36 is assigned in the
actual PR-321 control board and reconciliation tables. Issue #323; slice
TPM-RC8-CERT-WORKER-BOOTSTRAP-001. Status: SOURCE FIXED; OWNER RUNTIME NEEDED.
Post-implementation correction: CERT-IH-INV-002 was briefly revised to rely on
existing real matcher cases instead of its promised new child-boundary case.
That revision followed the worker edit; it is not inventory-first evidence.
The new boundary regression requirement is retained below. Its late authorship
and pre-fix-backup fixture run must be disclosed, not described as preceding
the candidate edit. Independent review must assess this sequencing deviation.

| ID | Specification / invariant | Existing evidence / required proof |
|---|---|---|
| CERT-JOB-SPEC-001 | Start-Job runs outside the current session; required module state must be initialized in that process. Import-Module with an absolute manifest selects that manifest, not an unrelated same-name search-path module. | Microsoft Start-Job/Import-Module PS5.1 API; real worker probe observes Utility 7.0.0.0 by inheritance versus inbox 3.1.0.0 explicitly |
| CERT-IH-INV-001 | The PS5.1 IH worker loads absolute PSHOME inbox Utility with terminating errors before data-file use. PS7 behavior stays unchanged. | Before: expected real finding exists but manifest import fails; after: same real finding and manifest version 1.0.0 required |
| CERT-IH-INV-002 | Findings, cross-file/occurrence matching, evidence schema, tool version and fail-closed worker failures remain unchanged. Parent import cannot substitute for child provenance. | Three existing real matcher cases; eleven-fact construction; real inventory assertions; new child-boundary regression with real foreign Utility precedence, real analyzer and real module-manifest semantics |
| CERT-JOB-INV-003 | The default 180-second per-file limit and bounded cleanup remain unchanged. Serial timing measures distinguish timeout/load from IH dependency failure. | Original main PSSA timed out; diagnostic isolated main finished in 165.296 seconds. Margin uncertain, not evidence to raise budget |
| CERT-ENV-INV-004 | No global PSModulePath/provider/auth changes, TypeData removal, hidden errors or fake findings. Short private TestDrive avoids harness MAX_PATH contamination without modifying product rules. | Record exact child commands/module paths, exits and scratch identity |

Governing sources:
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/start-job?view=powershell-5.1
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/import-module?view=powershell-5.1

This inventory does not assert successful final aggregate validation, owner-game
acceptance, package identity or release authority.

## Current focused proof -- before final freeze

The current real child-boundary case passes on both native engines; the exact
pre-edit module backup fails on PS5.1 and passes the PS7 control. Original
three matcher cases, unchanged eleven-fact assertions and both full real-
inventory self-scan assertions pass on each engine. Fresh complete IH capture
reports 44 findings/0 unresolved over 21 files on each engine with tool1.0.0.
Configured PS5.1 PSSA loads in 0.196481s and analyzes Main in 166.7142142s
with zero findings; the 180-second per-file bound is unchanged.
Independent scoped source/private-harness reviews pass; the real evidence-
finalization fail-open was reproduced and its repaired negative probes exit1,
retain Pester.xml and publish no misleading result.json.
The late regression chronology above remains a deviation, not retroactive
compliance. Final frozen aggregates, clean handoff and package authority remain
separate; no owner acceptance or certification is claimed.

