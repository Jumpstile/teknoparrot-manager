# Game rules update

TeknoParrot Manager can learn new game notes and new "does not work on this graphics card" warnings without a new TeknoParrot Manager release. This page says what that does, what it cannot do, and how to turn it off. The last section is for the project owner.

## What it does

When TeknoParrot Manager starts, it asks the project's own GitHub address for a small data file of game rules. If the file is genuine and newer than the rules you already have, TeknoParrot Manager uses it and shows one line: `Game rules updated to version X.`

The file can only do two things:

- Add one plain line per game to your Game Notes file (for example "Not supported" or "Needs an extra archive you must own", with a short reason).
- Add games to the list of games that do not work on your graphics card maker (AMD, Intel or NVIDIA), so the existing warning covers them.

## What it cannot do

- It never runs anything. The file is only text and numbers, checked against a strict list of allowed fields. One unknown or out-of-range value and the whole file is thrown away.
- It never touches your games, your TeknoParrot folder, LaunchBox or any other program. The only files TeknoParrot Manager writes are two copies of the rules in its own data folder (`%LOCALAPPDATA%\TeknoParrotManager\GameRules`) and a one-time notice marker.
- It never removes a protection that came with your release. The rules that shipped with your version always stay; the update only adds to them.
- It cannot be faked. The file carries a digital signature (RSA, SHA-256) that is checked with a public key built into TeknoParrot Manager. A file that is changed, signed by someone else, older than the one in use, too big (over 1 MB), served from another host, or not https is ignored.
- It only talks to one fixed address on this project's own GitHub raw host (https, no redirect to another host, 15-second limit).

If anything goes wrong (no internet, bad signature, bad file), TeknoParrot Manager keeps using the rules it already has, writes the reason in its log, and shows a plain line with Details.

## Turn it off

Open `TeknoParrot-Manager.config.json` and set `GameRulesUpdate` to `false`. TeknoParrot Manager then makes no request for game rules and ignores any saved copy. The default is `true`. TeknoParrot Manager tells you about this once, the first time it checks.

## For the project owner

### One-time: make the key pair

Do this once on your own computer, outside this repository. In Windows PowerShell:

```powershell
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(3072)
$rsa.ToXmlString($true)  | Set-Content -LiteralPath 'D:\private-keys\tpm-game-rules-private.xml' -Encoding ASCII
$rsa.ToXmlString($false) | Set-Content -LiteralPath 'D:\private-keys\tpm-game-rules-public.xml'  -Encoding ASCII
```

- Keep the private file (`...-private.xml`) off GitHub and off any shared drive: on an encrypted drive or a password manager, with an offline backup. Anyone who has it can publish rules that every TeknoParrot Manager will accept. Never put it in the repository, in a workflow or in a GitHub secret.
- Paste the contents of the public file between the quotes of `$TpmGameRulesPublicKeyXml` in `TeknoParrot-Manager.ps1`, and ship that in a release. Until a release carries the public key, TeknoParrot Manager skips the update.
- If the private key is ever lost or leaked, make a new pair and ship a new release with the new public key; older versions of TeknoParrot Manager keep the bundled rules.

### Each update

1. Build the file: `.\scripts\New-TpmGameDataFile.ps1 -Version 2` (the version must be higher than the last one published; the first one is 2 because the bundled rules are version 1). Add `-PreviousPath` to see what was added, changed or removed.
2. Sign it: `.\scripts\Sign-TpmGameData.ps1 -DataPath game-data\TpmGameRules.json -PrivateKeyPath D:\private-keys\tpm-game-rules-private.xml`
3. Commit `game-data\TpmGameRules.json` and `game-data\TpmGameRules.json.sig` (line endings are protected by `.gitattributes`; do not edit the files after signing).
4. On GitHub, open Actions, pick "Game data publish" and choose Run workflow. It checks both files with the public key built into the script and copies them to the `game-data-live` branch, which is the address TeknoParrot Manager reads. The workflow cannot sign and holds no key.
