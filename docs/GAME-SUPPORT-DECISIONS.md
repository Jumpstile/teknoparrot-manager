# Game support decisions (non-ROM loaders)

`scripts\TpmGameSupportDecisions.json` records one decision for each game in the community guide (eggmansworld.github.io/TeknoParrot) whose loader runs a program: TeknoParrot, ElfLdr2, Lindbergh, cxbxr, pcsx2x6, RPCS3, Dolphin, Model 1/2/3, Play!, and the few single-game loaders. ROM-set loaders (Naomi, S11, MVS, CPS, STV and similar) are listed under `Scope.ExcludedLoaders` and have their own decisions.

Neither TeknoParrot Manager nor the coverage tool (`scripts\New-TpmGameCoverage.ps1`) reads this file. Only the test `Tests\Fix412.GameSupportDecisions.Tests.ps1` checks it, and it is not in the release ZIP.

## What a decision means

Each row in `Profiles` has one `Disposition`. It is the first rule that applies, in this order:

| Disposition | What TPM does |
|---|---|
| `not-supported` | The guide marks the game unsupported, broken or no longer used. The reason is listed. TPM cannot make it work. Game Notes says "Guide status: Broken" for a registered game. |
| `tpm-applies-patch` | A reviewed patch is in `scripts\TpmRequiredPatchRecipes.json`. It is applied only on an exact match, with a backup and a receipt. |
| `tpm-checks-files` | TPM checks the emulator startup files (PCSX2x6, Chihiro/CxbxR, RPCS3, Play!) and copies them only from the player's own archive. |
| `needs-own-archive` | The guide names extra archives. Game Notes lists them. The player brings their own copy. Nothing is downloaded. |
| `tpm-warns` | TPM already warns: a graphics card the game does not work on, a path length limit, or a required file version. |
| `guided` | Game Notes shows the guide text (notes, setup steps, second file, test program, linked profile, graphics card notes). |
| `register-only` | The guide lists nothing beyond registration. |

`Also` lists the other dispositions that apply. `Signals` are the facts the rules use. `Reason` is a plain sentence.

## Graphics cards

`Graphics` has one row for each guide graphics note and each "does not work" status. `Action` is:

- `upstream-automatic`: TeknoParrot applies the fix by itself.
- `generic-fix-field`: the existing GPU Fix setup sets the profile field named in `Field`. Only the exact text "Select AMD Fix in settings" is used for this.
- `guided`: Game Notes shows the text. TPM changes nothing.
- `warning`: TPM warns, or Game Notes shows the text.
- `not-applicable`: the entry is no longer used.

`NotGpuConditions` lists notes that say "Intel" but mean the processor, or do not say which. They never become a graphics card warning.

## Guided games and third-party items

The `Reason` of each `guided` row says what TPM does for that game: the shipped profile already sets it, TPM fixes a profile setting, TPM changes one line in a game file (with a backup and an undo), the player needs a step in the game or on the PC, or the player needs files from their own copy. Rows that depend on other work (profile fixes, one-line file edits) say so only after that work is in.

`scripts\TpmThirdPartyChecks.json` covers the 15 games that need something from a third party (a frame limiter, a codec, a patched exe, a Windows component). For each game it has the plain message shown to the player and, where the guide names a file in the game folder, a `File` check in the same shape as the `Prerequisites` of the patch recipes. Where TPM cannot see the item, `CanCheck` is false and the message stays a shown step. TPM never downloads anything and never runs an installer. A `GuideLink` is only there when the guide itself gives it, and the player opens it themselves.

## Keeping it right

`Tests\Fix412.GameSupportDecisions.Tests.ps1` re-applies the rules to the signals, checks that the patch catalog and the graphics card warning table agree with this file, and checks that no CPU wording became a graphics card warning. Rebuild the file from the current guide at the release freeze.
