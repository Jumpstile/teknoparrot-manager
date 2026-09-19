# TPM Development Operating Model

TPM follows a contract-first remediation workflow. No future TPM source change may begin without a current slice contract unless it is a trivial documentation typo. Every owner report must be traceable through the control board, slice contract, tests, remediation report, and permanent procedure gate.

## Intake

Every owner report receives a stable ID, exact user-visible failure, plain-language expected behavior, subsystem, and runtime-proof requirement.

## Contract

Before code changes, create or update `docs/remediation/slices/<slice>.md` from the slice template. Record included IDs, exclusions, behavior contract, forbidden regressions, source ownership, focused tests, runtime proof, and stop condition.

## Implementation

Use one bounded subsystem or owner-report group per slice. Do not mix broad edits or opportunistic cleanup. Every changed hunk maps to an owner report, permanent procedure ID, issue ID, or slice contract.

## Verification

Run focused tests first, then the full suite after the final edit, static checks after the final edit, and the permanent procedure gate after updating the report. Source/test evidence never becomes packaged-runtime evidence. Runtime proof requires a fresh candidate built from the exact source SHA.

## Status language

Allowed statuses: `NOT FIXED`, `SOURCE FIXED; OWNER RUNTIME NEEDED`, `FIXED + TESTED`, `DEFERRED BY OWNER`, `BLOCKED BY OWNER DESIGN DECISION`, and `BLOCKED BY PACKAGE/RUNTIME PROOF`. The last two are planning blockers and must not replace the four report statuses unless the registry is explicitly extended.

Do not use fixed, done, probably fixed, mostly fixed, should be fixed, addressed, or improved as a status without mapping it to an allowed status.

## Release and package boundary

A stale ZIP is stale evidence. Owner smoke uses a fresh candidate with exact source and package hashes. ARCADE/#323 starts only after an owner-approved package candidate. A passing source suite does not authorize packaging, release, certification, wiki, or runtime claims.

## Beginner-first UX

Every choice screen states available choices, invalid-input behavior, Back behavior, and the next consequence. Free-text, secure input, and exact-token safety confirmations are explicitly labeled as different contracts from enumerated choices.

## Durable records

The control board is canonical owner state. The remediation report is evidence. The slice contract is scope authority. The procedure gate is fail-closed enforcement. The provenance ledger in each report binds source, package, runtime, and timestamps.
