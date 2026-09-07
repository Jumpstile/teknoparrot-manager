# TPM Permanent Procedure Registry

The canonical machine-readable registry is `quality/permanent-procedures.json`.
This document explains the enforcement contract. The executable gate is
`scripts/Test-TpmPermanentProcedures.ps1`; the combined local command is
`scripts/Run-TpmQualityGate.ps1`.

## Enforcement contract

A remediation report is evidence, not authorization. The report must identify
its exact source identity, enumerate every owner report, classify every required
progress and prompt path, record exact validation counts and timestamps, map
every changed hunk, and state all prohibited actions.

The gate fails closed when the report is missing, a required section is absent,
a status is outside the registry status set, evidence is stale, a required path
is unclassified, a banned production pattern is found, or hunk ownership is
not recorded.

Owner-runtime evidence remains distinct from source and test evidence. A source
or test result cannot silently become packaged-runtime proof.

## Required workflow

1. Create a remediation report from `docs/templates/remediation-gate-report.md`.
2. Run `scripts/Run-TpmQualityGate.ps1` from the authorized local worktree.
3. Resolve every gate failure or explicitly record the report item as `NOT FIXED`.
4. Obtain the required owner-runtime evidence where the report identifies it.
5. Obtain explicit authorization before commit, push, package, release,
   certification, wiki, or ARCADE work.

The gate does not authorize any of those actions. A passing gate is evidence of
procedure compliance only.
## TPM contract-first rule

TPM follows the contract-first remediation workflow. No future TPM source
change may begin without a current slice contract unless it is a trivial
documentation typo. Every owner report must be traceable through the control
board, slice contract, tests, remediation report, and permanent procedure gate.
Source, package, and runtime evidence remain separate.

## Registry maintenance

Add a stable procedure ID before adding a new standing rule. Do not delete or
rename an existing ID without documenting the migration. Every procedure entry
must retain a plain-English rule, enforcement type, required evidence, and a
failure message.
