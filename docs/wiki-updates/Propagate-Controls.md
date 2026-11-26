# Propagate Controls (menu 4)

Menu 4 sets up your games with your controller layout, checks which games have all their controls, holds your own arcade buttons, and lets you change one control by hand. This menu item never registers or unpacks a game.

AutoSync and Register end with the controller layout screen, the same as choice 1 below. By default choice 1 sets up all your registered games with the layout you chose in choice 2. Use menu 4, choice 1, when your games are already registered.

---

## Your controller layout and the controls check

Menu 4 asks which of these you want (1 to 5):

- **1 - Set up games with my controller layout.** The first time, choose a layout once: Xbox, PlayStation, Nintendo or arcade stick. You can change any single button. Test and Service start empty. Then set up one game, all your games at once (one preview, one `Y`), or game by game (a `Y` for each game).
- **2 - Choose or change my controller layout.** It is saved in TPM's own settings folder. A connected gamepad only pre-selects the Xbox controller layout.
- **3 - Check which games have all their controls.** Every registered game is sorted into every control set up, some, none, or cannot tell. Press `D` for the games and the controls that are still missing. The Library health check shows the same counts on a Controls line. It changes nothing.
- **4 - My controls.** Teach TPM your arcade buttons. Nothing in your game files changes.
  - It asks you to press each control (for example "Press Player 1 Start") and remembers the key it sends. If LEDBlinky is installed it offers its key list first.
  - Before it learns, it checks for a stuck button (2 seconds, hands off) and tells you if a press also sends another key or a button is still down after 3 seconds.
  - It offers the standard arcade keys that MAME and Ultimarc I-PAC boards both use only after you say yes and two buttons you press send those keys.
  - From here you can also show or print the controls of one game (it suggests your key only for coin, start, numbered buttons and plain directions, and says "I'm not sure" for the rest), tell TPM a game played well (the game's controls are then called Verified until they or the settings change), and see whether you changed your arcade encoder. The encoder check is a hint only and never changes a saved key or answer.
- **5 - Change one control by hand.** Pick a game, then one control, then the button or key you want. TPM remembers it as your own choice and keeps it when you set up games again. A saved copy of your game settings is made first.

More in **My controls**: the page for one game starts with plain lines that compare the game with what you told TPM (enough players and buttons, and any device the game needs that you said you do not have, with what can stand in). It only compares and changes nothing. Learning buttons first asks if your cabinet has an Exit, Pause or Menu button (Esc counts as a key for these). Choice 6, "Undo my last save", appears when an older copy of your answers exists: it shows what comes back, asks once, and keeps your newest answers as a copy.

What a layout setup does and does not do:

- It sets only controls that TeknoParrot's own file for the game lists, and only when your saved settings for the game are the same version as that file. Otherwise the game is left alone, and the screen says why (often: open the game once in TeknoParrotUI).
- It never replaces a controller button that is already set, never touches keyboard or arcade-encoder settings, and leaves a game alone when a button it wants is already used by another control in that game.
- It does not set triggers or analog sticks (steering, aim, throttle). The preview names them so you can set them in TeknoParrotUI.
- PlayStation and Nintendo controllers only work here when something shows them to Windows as an XInput controller. XInput is the standard mode most pads use, including PlayStation and Nintendo pads through Windows. An arcade stick must be in its XInput mode.
- A saved copy of your game settings is made and checked first. Each changed game is read back and compared, and put back exactly if the check fails. You can undo the whole run afterward.

The controls check and the layout setup are not a test. Most game control lists come from TeknoParrot's own game file and no person has checked them. Start one game and test it.

---

## The controls report

<details><summary>Details</summary>

After every real run, `TeknoParrot-Manager-controls.txt` in `<your TeknoParrot folder>\TeknoParrotManager\Reports\` lists every registered game with `N/M bound` (how many of its controls are set), its status (bound, partial or no controls), and the buttons you still have to set by hand (`manual:`). It is a record of what is set, not a test of your controls.

**Check an outside controller list (command line).** If you already have a controller list from somewhere else (for example RetroBat's `teknoparrot.yml`), you can compare it with your installed game profiles. Run:

```
.\TeknoParrot-Manager.ps1 -MappingEvidenceFile "<list>" -ValidationRoot "<TeknoParrot folder>" [-ValidationJsonPath "<details file>"]
```

It only reads. It prints plain counts: how many games are in the list, how many are found in your TeknoParrot, how many are ready for a person to review, and how many are held back. Nothing in the list is trusted or applied, and no profile is changed. The only file it writes is the details file you name. A game is held back with a plain reason: the game is not in your TeknoParrot, the list names the game twice, the list sets one control twice, the list sets a control the game does not have, the list uses a button name TeknoParrot Manager does not know, or two game actions share one controller button. Five known spelling mistakes in the list are corrected and counted. The same inputs give the same details file.

</details>

---

## Not sure which game to set up first?

The binding plan is under choice 4, then 1 (`Tell TPM which controls I have`). It asks which controls you own (pad, arcade stick, trackball, spinner, wheel, lightgun, keyboard) and suggests which game to set up with which device. It reads nothing and changes nothing. Choosing a device in the plan does not set up a game. You still set up the game in TeknoParrotUI.
