# Advanced users

TeknoParrot Manager is designed to be beginner-friendly by default.

It is not only a beginner wizard.

Advanced users can use TeknoParrot Manager as a repeatable, evidence-backed operations tool. It works for TeknoParrot libraries, cabinet setups, and frontend workflows.

The goal is to hide unnecessary complexity, not capability.

## Why TeknoParrot Manager still matters when you already know TeknoParrot

Advanced users usually know how to make a single game work.

TeknoParrot Manager makes the larger workflow safer, faster, and easier to audit (check later).

**Safer day-to-day work:**

- repeatable registration and AutoSync workflows instead of one-off manual edits;
- bulk operations with previews, logs, and action summaries;
- backups before supported writes and clear recovery paths;
- read-only warnings for known compatibility problems and missing required components (they report problems but change nothing).

**Clear evidence:**

- separation between detection, registration, launch success, controls readiness, and actual verification;
- contract-backed checks (checks against a written rule) where TeknoParrot Manager has verified evidence;
- technical detail when needed without forcing every user through raw diagnostics.

**Works with the rest of your setup:**

- consistent handling across direct TeknoParrot usage and supported frontend workflows;
- safer foundations for future cabinet, controller, lightgun, LEDBlinky, LaunchBox, Big Box, and RetroBat integration.

## What TeknoParrot Manager gives a power user

TeknoParrot Manager is most valuable when you care about repeatable results and evidence.

It can help answer these questions.

**About one run:**

- What did this run detect?
- What did it change?
- What did it deliberately refuse to change?
- What still needs manual review?

**About the evidence:**

- Which files were backed up before a supported write?
- Which game setup file (profile), path, file fingerprint (hash), contract, or warning produced this result?
- Was a game merely registered, or was launch/control readiness actually verified?
- Who owns this issue: TeknoParrot Manager, TeknoParrot, a frontend, Windows, device software, an emulator, or the user?

That difference matters.

TeknoParrot Manager should not turn expert setups into opaque automation. It should make expert workflows easier to repeat and safer to review.

### More detail

- A "profile" is a game setup file.
- A "hash" is a file fingerprint (SHA-256) that shows a file has not changed.
- A "contract" is a written rule that a check is made against.

## Beginner-first does not mean expert-limited

TeknoParrot Manager's normal wording is plain language, so first-time users do not get lost.

Advanced detail remains important. It stays available through these places:

- logs and summaries;
- dry runs (previews that change nothing);
- evidence sections;
- compatibility notes;
- issue/diagnostic output.

The intended model has three layers:

| Layer | Purpose |
|---|---|
| Default | Tell the user what happened, what matters, and what to do next. |
| Explain | Show the evidence, owner, confidence, and risk behind the recommendation. |
| Inspect | Show exact paths, profile codes, versions, hashes, contract identifiers, logs, backups, and validation details. |

## Check an outside controller list (command line)

If you already have a controller list from somewhere else (for example RetroBat's `teknoparrot.yml`), TeknoParrot Manager can compare it with your installed game profiles. This is read-only.

```powershell
.\TeknoParrot-Manager.ps1 -MappingEvidenceFile "<list>" -ValidationRoot "<TeknoParrot folder>"
```

To also save the details file, add `-ValidationJsonPath`:

```powershell
.\TeknoParrot-Manager.ps1 -MappingEvidenceFile "<list>" -ValidationRoot "<TeknoParrot folder>" -ValidationJsonPath "<details file>"
```

- It prints plain counts: games in the list, games found in your TeknoParrot, games ready for a person to review, games with some controls missing, and games held back.
- Nothing in the list is trusted, applied or bundled. No profile is changed. The only file it writes is the details file you name.
- A game is held back with a plain reason: the game is not in your TeknoParrot, the list names the game twice, the list sets one control twice, the list sets a control the game does not have, the list uses a button name TeknoParrot Manager does not know, or two game actions share one controller button.
- Two more reasons: a label in the list names a different control than the one it is on (Coin, Start, Test or Service on a control of another kind), and the game file's revision or SHA-256 changed since the last details file written for the same list (same list SHA-256). The details file is that record, so keep a copy if you want to compare against an older snapshot.
- `-MappingEvidenceCommit <code>` (7 to 64 hexadecimal characters) saves the commit of the outside list you checked in the details file, so the counts can be matched to one pinned snapshot.
- Five known spelling mistakes in the list are corrected and counted.
- The same inputs give the same details file.

## Boundaries still apply

TeknoParrot Manager is not supposed to guess its way through an advanced setup.

It must not silently change things that belong to someone else. That includes TeknoParrot, emulator, frontend, Windows, driver, firmware, device-software, or user-owned state.

The only exception is a supported change that TeknoParrot Manager owns, with the required safety gates in place.

Future advanced workflows must keep the same rule.

**First, look and plan:**

1. detect the observed state;
2. classify the evidence;
3. identify the owner;
4. preview any supported change;
5. back up first;

**Then, change and check:**

6. request approval when needed;
7. apply only owned, bounded changes;
8. verify the effective result;
9. record the evidence and recovery path.

## Message for final 1.0

For final Version 1.0 messaging, TeknoParrot Manager should be described as useful for both groups:

- beginners who need safe guidance and fewer confusing choices;
- advanced users who want repeatable operations, technical evidence, controlled automation, safer bulk changes, and better release-quality validation.

The product promise is not magic.

The product promise is safer, clearer, repeatable TeknoParrot management.
