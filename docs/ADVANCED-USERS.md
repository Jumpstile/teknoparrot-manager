# Advanced users

TeknoParrot Manager is designed to be beginner-friendly by default, but it is not only a beginner wizard.

Advanced users can use TPM as a repeatable, evidence-backed operations tool for TeknoParrot libraries, cabinet setups, and frontend workflows. The goal is to hide unnecessary complexity, not capability.

## Why TPM still matters when you already know TeknoParrot

Advanced users usually know how to make a single game work. TPM is useful because it makes the larger workflow safer, faster, and easier to audit:

- repeatable registration and AutoSync workflows instead of one-off manual edits;
- bulk operations with previews, logs, and action summaries;
- backups before supported writes and clear recovery paths;
- separation between detection, registration, launch success, controls readiness, and actual verification;
- read-only warnings for known compatibility problems and missing required components;
- contract-backed checks where TPM has verified evidence;
- technical detail when needed without forcing every user through raw diagnostics;
- consistent handling across direct TeknoParrot usage and supported frontend workflows;
- safer foundations for future cabinet, controller, lightgun, LEDBlinky, LaunchBox, Big Box, HyperSpin, and RetroBat integration.

## What TPM gives a power user

TPM is most valuable when you care about repeatability and evidence.

It can help answer questions such as:

- What did this run detect?
- What did it change?
- What did it deliberately refuse to change?
- What still needs manual review?
- Which files were backed up before a supported write?
- Which profile, path, hash, contract, or warning produced this result?
- Was a game merely registered, or was launch/control readiness actually verified?
- Is this issue owned by TPM, TeknoParrot, a frontend, Windows, device software, an emulator, or the user?

That distinction matters. TPM should not turn expert setups into opaque automation. It should make expert workflows easier to repeat and safer to review.

## Beginner-first does not mean expert-limited

TPM's normal wording is plain language so first-time users do not get lost. Advanced detail remains important and should stay available through logs, summaries, dry runs, evidence sections, compatibility notes, and issue/diagnostic output.

The intended model is layered:

| Layer | Purpose |
|---|---|
| Default | Tell the user what happened, what matters, and what to do next. |
| Explain | Show the evidence, owner, confidence, and risk behind the recommendation. |
| Inspect | Show exact paths, profile codes, versions, hashes, contract identifiers, logs, backups, and validation details. |

## Boundaries still apply

TPM is not supposed to guess its way through an advanced setup.

It must not silently change TeknoParrot, emulator, frontend, Windows, driver, firmware, device-software, or user-owned state unless a supported TPM-owned path exists with the required safety gates.

Future advanced workflows must preserve the same rule:

1. detect the observed state;
2. classify the evidence;
3. identify the owner;
4. preview any supported change;
5. back up first;
6. request approval when needed;
7. apply only owned, bounded changes;
8. verify the effective result;
9. record the evidence and recovery path.

## Message for final 1.0

For final Version 1.0 messaging, TPM should be described as useful for both groups:

- beginners who need safe guidance and fewer confusing choices;
- advanced users who want repeatable operations, technical evidence, controlled automation, safer bulk changes, and better release-quality validation.

The product promise is not magic. The product promise is safer, clearer, repeatable TeknoParrot management.