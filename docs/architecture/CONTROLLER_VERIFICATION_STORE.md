# Controller answers, learned keys, play-test evidence and guides

This is how TPM keeps what the player tells it about their controls (issues #201, #267, #307). It is TPM's own data. It is never a TeknoParrot file, and TPM never writes a profile from it.

Related: `CONTROLLER_EVIDENCE_CONTRACT.md` (what detection may say), `CONTROLLER_CAPABILITY_CONTRACT.md` (status words).

## Where it lives

`State\Controls` in TPM's own folder. Two small JSON files, both written by one function (`Save-TpmControlStateFile`), and one small text file, `controller-salt.txt`:

- `cabinet.json`: the survey answers per kind of device (`Has`, `Source`, `AnsweredUtc`), the number of players and buttons, the number of arcade encoders detection could see when the keys were last learned (`EncodersWhenLearned`, `-1` when it could not look), the fingerprints of those encoders (`EncoderFingerprints`, a list of `DeviceClass` and `Fingerprint`; `null` when not saved or when detection could not look, an empty list when none was recognized), and one record per learned arcade control (`Key`, `Source`, `LearnedUtc`).
- `control-evidence.json`: one record per game (`Code`).

Protection rules, the same for both:

1. Reading never writes. A missing file is empty. A file that cannot be parsed is reported as `Unreadable` and counts as "no record".
2. A save of an unreadable file first copies it to `<name>.unreadable-<time>`. If that copy fails, the save stops.
3. A save of a readable file keeps the old one as `<name>.bak`. The new text is parsed back before it replaces anything (atomic write).
4. No serial numbers, device paths, instance ids, vendor or product numbers, machine names or user names are stored. Answers are per kind of device (`XboxStylePad`, `ArcadeEncoder`, `PointerOrTrackball`, `Spinner`, `Wheel`, `LightGun`, `Keyboard`), not per physical device. The one exception is `EncoderFingerprints`: one-way salted hashes of recognized arcade encoders, kept so TPM can notice a changed controller (see `CONTROLLER_EVIDENCE_CONTRACT.md`). `controller-salt.txt` holds the salt (32 hex characters, made once when the player's keys are first saved, never made by detection). Neither file is read into a log, a report, a guide or the support package.

## Survey answers (#201)

A saved answer is the default for that question. When all seven are saved, the survey shows them and asks once. It asks everything again when detection finds a High-confidence device of a kind the player said they do not have. Detection still only suggests: a name-only guess is never an answer.

Learned keys come from, in order: the player pressing the control (`PressedByPlayer`), the key list LEDBlinky keeps in `LEDBlinkyInputMap.xml` after the player confirms it (`LedBlinkyKeyMap`), or the standard arcade keys (`StandardArcadeKeys`). Only LED labels TPM recognizes and MAME key codes it can name are proposed. The standard keys are the ones MAME (docs.mamedev.org/usingmame/defaultkeys.html) and the Ultimarc I-PAC (ultimarc.com, I-PAC2 "Default Keycode Table") both list: coin and start 1 to 4, the player 1 stick and buttons 1 to 8, the player 2 stick and buttons 1 to 4, the player 3 stick and buttons 1 to 3. The two lists differ for player 2 buttons 5 to 8 and for player 4, and neither lists Test or Service, so those are left out. They are used only after the player says the encoder was never changed and presses player 1 Start and player 1 button 1 on the cabinet, and both send the standard key. No other brand's setup file is read: Ultimarc's `.xml` export is not documented (no public table says which pin is which button), and the other brands keep no file or an undocumented one. Pressing the control is the way for every other encoder. A key already given to another control is refused.

While learning, three things are only reported, never decided: keys that arrive during a 2 second hands-off check, other keys that arrive within 80 ms of a press (the first key is kept), and a key still down 3 seconds after the press. Nothing about them is saved.

`EncodersWhenLearned` and `EncoderFingerprints` are written together when the keys are saved. `Get-TpmControllerSetNotice` compares the saved fingerprints with a new observation and gives one line, shown on My controls and the Device Survey: `Same`, `Added`, `Removed`, `Changed`, or `CouldNotCheck` (no data from Windows, no salt, or no recognized encoder on either side). Keys saved before fingerprints existed have only the count, and then the old count hint is used. The line is a note about the past, never evidence about the present. It never changes a saved key or answer and never decides Verified. Only makers TPM recognizes get a fingerprint, so an unrecognized encoder gives "could not check". Moving a board to another USB port keeps its fingerprint; swapping a board for an identical one is not noticed.

## Play-test evidence (#307)

Record fields for a game: `Verification` (`Method`, `ObservedAt`, `Game`, `ProfileRevision`, `ProfileHash`, `ControllerContext`), `FirstRun`, `Calibration` (`Unknown`, `Needed`, `Done`, `NotNeeded`), with `FirstRunAt`, `CalibrationAt`, `CalibrationHash`.

- `Method` is `PlayerReportedPlayTest`. There is one way to create it: the player answers W on "Tell TPM how a game played". A launch, a registration, a bound-button count or a detected device never creates it.
- Profile identity is `GameProfileRevision` plus a SHA-256 of every button's input mapping and its Xbox, DirectInput and RawInput bindings plus the Input API (`Get-TpmControlProfileIdentity`). Settings such as sensitivity are not part of it.
- Status from `Get-TpmControlVerificationState`: `None`, `Current` (revision and hash match), `Stale` (either differs; the reason says which), `Unreadable`.
- Calibration is `Needed` for every game whose controls are not plain buttons (wheel, gun, trackball, other analog) until the player says `Done` for the current controls (`CalibrationHash` must match) or `NotNeeded`. A plain-button game is `NotRequired` unless the player marks it `Needed`.
- First-run Test/Service step: no source says which games need it, so it stays `Unknown` and does not block anything until the player marks it `Needed`.
- `Outstanding` lists steps that are `Needed`. A game with any is not Verified.

Readiness (`Get-ControlReadinessAssessment`): `Controls` is `Verified` only when the status is `Current`, nothing is outstanding, and the reviewed contract state is `NotVerified` or `Unknown`. `Missing` and `Unsupported` are never overridden. `Launch` is `ObservedSuccess` only while the record is `Current` (observed by the player); otherwise `NotTestedByTpm`. The record is attached as `VerificationEvidence`, which `Test-ControlReadinessVerificationEvidence` still checks.

Not covered: a change of TeknoParrot's own build (no reliable source), and per-control proof (the player answers once per game).

## Guides (#267)

`Get-TpmGameControlGuide` lists the controls a profile names (`Get-TpmLedProfileControls`): what each does, the player's key (from `cabinet.json`), and whether the game has a binding. `Get-TpmCabinetGuide` lists the cabinet's learned keys. Both are shown on screen, and one Y/N saves them as an HTML page (all text encoded, no scripts) in `Reports\Control Guides` and opens it for printing.
