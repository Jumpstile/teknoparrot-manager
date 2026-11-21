# Owner test plan: CPS3 first-boot files with the real set (issue 349)

## What is left to prove

The CPS3 copy step is built and its fake-file tests pass. What is still open is proof with the real files you already own: every game gets exactly the right files, nothing already on the cabinet is overwritten, and the games start.

TeknoParrot Manager does not supply, download or point to these files. Use your own copy and keep the original untouched.

## Before you start

- Use the test PC. Close TeknoParrot and any CPS3 game.
- Copy your whole `TeknoCPS` folder somewhere safe. This is your way back.
- Register at least one CPS3 game (Street Fighter III, JoJo, Red Earth or the CPS3 multi-game).
- Pick one `.nv` file that already exists in `TeknoCPS\nvram`. Note its size and date.

## Test

1. Optional check that never touches your real folder. Set `TPM_REAL_SOURCE_TESTS=1` and set `TPM_CPS3_REAL_SOURCE` to your set (folder or `.zip`). Run `Tests\TpmCps3Supplementary.Tests.ps1`. Pass: 34 tests run, none skipped, none failed. The set is only read, and the files go to a throwaway folder.
2. Run TeknoParrot Manager. At the CPS3 question, answer **Y**, then pick your folder or `.zip`.
   - Pass: it says `Copied and verified N file(s)`, where N is 101 minus the `.nv` files you already had.
3. Look at the TeknoParrot folder.
   - `TeknoCPS\cps3-install` holds 18 `.simms` files. The file starting `aeeba2be` is not there.
   - `TeknoCPS\nvram` holds 83 `.nv` files.
   - `README.txt` was not copied into the TeknoParrot folder.
4. Check that the pinned names match what you copied: the 18 `.simms` names are in the table in `Get-TpmCps3SupplementaryManifest`. Pass: every name there is present, and no other `.simms` name was added.
5. Check the `.nv` file you noted in Before you start. Pass: same size, same date, same content.
6. Run the step again. Pass: it says nothing needs to be copied, and no file date changes.
7. Start one game from each family and write down how long the first start takes.
   - Street Fighter III New Generation, 2nd Impact and 3rd Strike (both Europe 990512 and 990608 if you have them).
   - JoJo (Japan 981202 and 990108, Europe 990128, 990913 and 990927).
   - Red Earth (both Europe 961121 entries if your profile list shows two).
   - The CPS3 multi-game (`cps3boot`).
   - Pass: each game reaches its attract screen with no long cache build, and shows no error.
8. Try a damaged set. Make a copy of your set, delete one `.nv` file from the copy, and point TeknoParrot Manager at the copy. Pass: it refuses the whole set and copies nothing.
9. Write the result on issue 349: which games you started, the start times, and any file that did not match.

## Details

- The built-in list has 103 members: 19 `.simms` (18 installed, one held back), 83 `.nv` and `README.txt`. Everything must match name, size and SHA-256 before anything is written.
- `.simms` files go to `TeknoCPS\cps3-install`. A different existing `.simms` is kept unless you confirm the replace question. `.nv` files go to `TeknoCPS\nvram`, only when absent, and a different existing `.nv` is never replaced.
- The guide lists 18 `.simms` names, and the set has 19. The extra one (`aeeba2be...`) is checked but never installed. If a game fails to start and needs it, report that on the issue instead of copying it by hand.
- The fake-file tests in `Tests\TpmCps3Supplementary.Tests.ps1` already cover refusal of a missing, extra, wrong-size and wrong-hash file, keeping an existing `.nv`, rollback, and a second run changing nothing.
