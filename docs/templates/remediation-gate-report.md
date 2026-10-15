# Remediation Gate Report

- Repository root:
- Branch:
- HEAD:
- Report generated UTC:
- Source/test last-edit UTC:
- Candidate/package identity:
- Remediation scope:

## Provenance

- Git status:
- Changed files:
- Numstat:
- Candidate SHA-256:
- Source SHA:

Before product behavior changes, reference the current control board and slice
contract. The report is not complete without focused owner-behavior test names,
source/package/runtime provenance, and a hunk classification mapping each
change to an owner ID, procedure ID, issue ID, or slice ID.
## Owner report mapping table

Use every owner report ID. Status must exactly match a value in
`quality/permanent-procedures.json`: `NOT FIXED`,
`SOURCE FIXED; OWNER RUNTIME NEEDED`, `FIXED + TESTED`, `DEFERRED BY OWNER`,
`SOURCE CLAIM REQUIRES RE-AUDIT`, `SOURCE CLAIM INVALID / RE-AUDIT REQUIRED`,
or `SOURCE REMEDIATION REQUIRED`.
The four unresolved statuses (`NOT FIXED`, `SOURCE REMEDIATION REQUIRED`, and
the two `SOURCE CLAIM` re-audit statuses) block the source gate. Owner-runtime
pending remains distinct from source eligibility; certification mode requires
fresh package/runtime proof.

| ID | Owner report | Status | Files/functions | Exact test names | Runtime proof still needed |
|---:|---|---|---|---|---|
| 1 | | | | | |


## Canonical owner-ID status table -- release decisions

This table is the sole release-decision status source. Keep the historical
owner-mapping table above for function/file mapping and exact focused test
names; do not copy its status cells into this table without re-auditing them.
The `Corrected status` column must exactly match a registered value.

| ID | Owner report | Finding | Corrected status | Decision evidence |
|---:|---|---|---|---|
| 1 | | | | |

## SCRIPT-WIDE UNIVERSAL PROGRESS BAR AUDIT

| Path | Function/call site | Current behavior | Disposition | Test |
|---|---|---|---|---|
| AutoSync scan | | | | |

Allowed dispositions:
- `CONVERTED TO UNIVERSAL TPM PROGRESS`
- `NO PROGRESS NEEDED / INSTANT`
- `EXCLUDED BY OWNER APPROVAL`

## Prompt/gate/back-routing consistency audit

| Pattern | Locations audited | Converted | Excluded with reason | Tests |
|---|---|---|---|---|
| Y/N | | | | |
| Invalid input | | | | |
| Back | | | | |
| Skip | | | | |
| Cancel | | | | |
| Preview/Run | | | | |
| Mutation confirmation | | | | |
| Optional setup gates | | | | |
| Support package prompts | | | | |

## Affected-games repair-flow scoping audit

Record one-game, multiple-game, zero-game, no-candidate, Back, and forbidden
optional-flow evidence. Confirm there is no BBHWorld hardcode.

## Support package/fatal surfacing audit

Record fatal fallback, newest Action Required selection, stale labeling, and
support final-prompt evidence.

## Tests with exact counts and timestamps

| Gate/test | Exact command | Count/result | Started UTC | Finished UTC | Engine/version |
|---|---|---|---|---|---|
| Main Pester | | | | | |
| SupportPackage.Tests | | | | | |

## Static gates

Record parse, ASCII, PSScriptAnalyzer, `git diff --check`, source audits, and
InjectionHunter. If InjectionHunter is unavailable, use exactly:
`InjectionHunter unavailable in this environment; no InjectionHunter result claimed.`

## Hunk classification

| File | Hunk/range | Procedure ID, owner report ID, issue, or authorization | Evidence |
|---|---|---|---|
| | | | |

## Permanent procedure compliance

List every applicable procedure ID and its evidence. Do not use vague statuses
such as addressed, improved, mostly, done-ish, should be fixed, or probably.

## Non-actions

Explicitly state whether commit, push, package, wiki, release, certification,
and ARCADE work were not performed. State whether monitor-pipeline files were
untouched and whether generated artifacts remain.

## Runtime owner-smoke checklist

List exact owner-visible behaviors requiring packaged-runtime proof. Do not
convert source/test evidence into runtime evidence.
