# Test Data

This folder contains golden datasets used by TPM validation tests.

Golden datasets are machine-readable examples of real-world behavior. They should grow whenever tester reports, bug fixes, or release reviews reveal a case that TPM must remember forever.

## Current datasets

| File | Purpose |
|---|---|
| `golden-normalization-cases.json` | Folder-name normalization and safety cases. |

## Dataset entry expectations

Each entry should include:

- `id`: stable identifier for the case.
- `source`: input value being tested.
- `expectedKey` or equivalent expected output.
- `caseType`: positive case, negative case, or safety guard.
- `status`: covered, pending-fix, needs-test, or investigation.
- `issue`: related issue number when applicable.
- `note`: short explanation of why the case exists.

## Rule

When a real bug is confirmed and the behavior is suitable for a dataset, add the case here before closing the bug.

The goal is that TPM learns from every real-world failure instead of relying only on hand-written one-off tests.
