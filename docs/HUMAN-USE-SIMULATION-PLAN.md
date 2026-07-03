# Human-Use Simulation Testing Plan

The TPM tester must catch bugs that a normal human tester would catch during everyday use, not only adversarial or edge-case bugs.

## Goal

Simulate common user workflows and verify that TPM feels safe, clear, predictable, and usable.

This lane complements regression, fuzz, mutation, and chaos testing.

## What this catches

Human-use simulation should catch issues like:

- confusing prompts
- missing back/cancel options
- unsafe defaults
- unclear warnings
- menus that do not match documentation
- unexpected scary output during normal use
- repeated prompts that should be remembered
- workflows that complete but leave the user unsure what happened
- reports that do not explain next steps
- first-run setup mistakes
- bad option handling
- output that is too noisy for normal users
- failure messages that do not tell the user how to recover

## Core user journeys

### First run

- Launch TPM with no existing config.
- Confirm startup guidance is understandable.
- Confirm required paths are requested clearly.
- Confirm default answers are safe.
- Confirm user can cancel without changes.
- Confirm created config is valid.

### Main menu

- Menu options are present and numbered correctly.
- Invalid option gives a clear retry message.
- Exit works.
- Back/cancel works from nested flows.
- Update option is visible and understandable.

### AutoSync normal path

- User selects AutoSync.
- User confirms source and target paths.
- TPM summarizes planned work before state-changing actions.
- Backup is created before modifications.
- Final report tells the user what changed and what needs attention.

### Register-only normal path

- User selects register-only mode.
- Existing extracted games are detected.
- Already-registered games are not scary.
- Missing matches are listed clearly.

### Update check

- Already-current state is calm and clear.
- Update-available state explains backup, download, validation, install, and restart.
- Decline/remind-later path is clear.
- Read-only failure explains exact recovery steps.

### Crosshair setup

- Preview generation is clear.
- User understands P1/P2 selection.
- Bad choices are handled safely.
- Final summary shows installed files and rollback/undo guidance where applicable.

### Restore backup

- Backup list is understandable.
- User can cancel safely.
- Restore warns before overwriting.
- Restore confirms final state.

## Certification gate

Add a future certification gate named `Human-Use Simulation`.

This gate should pass only when:

- scripted everyday journeys complete successfully,
- output contains required friendly guidance,
- output does not contain known confusing or scary wording outside expected failure cases,
- cancel paths make no changes,
- final reports give clear next steps.

## Test data

Human-use cases should be stored in machine-readable datasets where possible.

Suggested future files:

- `testdata/human-use-main-menu.json`
- `testdata/human-use-first-run.json`
- `testdata/human-use-update-check.json`
- `testdata/human-use-autosync.json`
- `testdata/human-use-restore.json`

## First implementation targets

1. Add metadata tests proving human-use datasets exist and are parseable.
2. Add transcript-based tests for main menu wording.
3. Add transcript-based tests for update check wording.
4. Add cancel-path no-change checks.
5. Add a `Human-Use Simulation` line to the certification scorecard.
