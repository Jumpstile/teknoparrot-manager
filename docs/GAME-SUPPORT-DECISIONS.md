# Game support decisions (non-ROM loaders)

`scripts\TpmGameSupportDecisions.json` records one decision for each game in the community guide (eggmansworld.github.io/TeknoParrot) whose loader runs a program: TeknoParrot, ElfLdr2, Lindbergh, cxbxr, pcsx2x6, RPCS3, Dolphin, Model 1/2/3, Play!, and the few single-game loaders. ROM-set loaders (Naomi, S11, MVS, CPS, STV and similar) are listed under `Scope.ExcludedLoaders` and have their own decisions.

The coverage tool reads this file. TeknoParrot Manager does not read it while it runs, and it is not in the release ZIP.

## What a decision means

Each row in `Profiles` has one `Disposition`. It is the first rule that applies, in this order:

| Disposition | What the Manager does |
|---|---|
| `not-supported` | The guide marks the game unsupported, broken or no longer used. The reason is listed. The Manager cannot make it work. Game Notes says "Guide status: Broken" for a registered game. |
| `tpm-applies-patch` | A reviewed patch is in `scripts\TpmRequiredPatchRecipes.json`. It is applied only on an exact match, with a backup and a receipt. |
| `tpm-checks-files` | The Manager checks the emulator startup files (PCSX2x6, Chihiro/CxbxR, RPCS3, Play!) and copies them only from the player's own archive. |
| `needs-own-archive` | The guide names extra archives. Game Notes lists them. The player brings their own copy. Nothing is downloaded. |
| `tpm-warns` | The Manager already warns: a graphics card the game does not work on, a path length limit, or a required file version. |
| `guided` | Game Notes shows the guide text (notes, setup steps, second file, test program, linked profile, graphics card notes). |
| `register-only` | The guide lists nothing beyond registration. |

`Also` lists the other dispositions that apply. `Signals` are the facts the rules use. `Reason` is a plain sentence.

## Graphics cards

`Graphics` has one row for each guide graphics note and each "does not work" status. `Action` is:

- `upstream-automatic`: TeknoParrot applies the fix by itself.
- `generic-fix-field`: the existing GPU Fix setup sets the profile field named in `Field`. Only the exact text "Select AMD Fix in settings" is used for this.
- `guided`: Game Notes shows the text. The Manager changes nothing.
- `warning`: the Manager warns, or Game Notes shows the text.
- `not-applicable`: the entry is no longer used.

`NotGpuConditions` lists notes that say "Intel" but mean the processor, or do not say which. They never become a graphics card warning.

## Keeping it right

`Tests\Fix412.GameSupportDecisions.Tests.ps1` re-applies the rules to the signals, checks that the patch catalog and the graphics card warning table agree with this file, and checks that no CPU wording became a graphics card warning. Rebuild the file from the current guide at the release freeze.
