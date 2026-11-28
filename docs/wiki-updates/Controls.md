# Controls (menu 4)

Set up your games with your controller layout (Xbox, PlayStation, Nintendo, arcade stick or "My learned arcade controls") and check which games have all their controls. TPM sets up controls only from your controller layout. It does not copy controls from example games. This screen never registers or unpacks games.

AutoSync and Register only use the same controller layout. Their last step is the Controller Layout screen (choice 1 below). Use menu 4 when your games are already registered.

---

## Your choices

Menu 4 says "This sets up your games with your controller layout and checks which games have all their controls." Then it asks "Choose 1, 2, 3, 4 or 5". Pressing Enter picks 3, which changes nothing.

- **1 - Set up games with my controller layout.** The first time, choose a layout once: Xbox, PlayStation, Nintendo, arcade stick or "My learned arcade controls". You can change any single button. Test and Service start empty. Volume Up and Volume Down use the left and right stick clicks (L3 and R3). Then set up one game, all your games at once (one preview, one `Y`), or game by game (a `Y` for each game). A saved copy of your `UserProfiles` is made first. You can put it back with [[Restore Backup]].
- **2 - Choose or change my controller layout.** It is saved in TPM's own settings folder. If you have not saved a layout yet and TPM finds one kind of controller (a standard gamepad or an arcade encoder), it selects that layout for you and says so. Press Enter to use it, or pick another number. The answer is always yours. Your choices are Xbox, PlayStation, Nintendo, arcade stick or **My learned arcade controls**. The last one is for an arcade encoder in keyboard mode. It changes nothing in your games and needs no mode switch. It keeps your learned keys and input type. TPM does not check the mode.
- **3 - Check which games have all their controls.** Every registered game is sorted into every control set up, some, none, or cannot tell. Press `D` for the games and the controls that are still missing. The Library health check shows the same counts on a Controls line. It changes nothing.
- **4 - My controls.** It opens a small menu: 1 = Tell TPM which controls I have, 2 = Learn my arcade buttons, 3 = Show or print the controls of one game, 4 = Tell TPM how a game played, 5 = Show or print my cabinet controls, 6 = Undo my last save (only when a saved copy exists), B = Back. Nothing in your game files changes, except Learn my trackball, and only after you say Y.
  - Choice 1 asks Y/N questions about which controls you own (pad, arcade stick, trackball, spinner, wheel, lightgun, keyboard) and saves your answers. TPM also looks for extra devices such as Wii remotes, guitars, drums and dance pads. If TPM does not know what a device is, you can tell it. It ends with "TPM uses your answers in your control guides and your cabinet summary."
  - Choice 2 asks you to press each control (for example "Press Player 1 Start") and remembers the key it sends. If LEDBlinky is installed it offers its key list first.
  - Before it learns, it checks for a stuck button (2 seconds, hands off) and tells you if a press also sends another key or a button is still down after 3 seconds.
  - It offers the standard arcade keys that MAME and Ultimarc I-PAC boards both use only after you say yes and two buttons you press send those keys.
  - Learn my trackball. After you learn your arcade buttons, TPM can learn a trackball too. You roll it left and right, then up and down, and TPM watches the pointer move. Then it lists the mice and trackballs Windows reports and asks which one is yours. If it cannot read that list, or you pick none, it writes nothing. For games whose own file has a single trackball control, TPM shows "these games will get your trackball" and waits for Y. Only after Y does it save a copy of your game settings, put your trackball in that one control, and read the file back to check it. Then it offers Undo. A trackball a game already has is kept unless you say to replace it. Games with a different trackball layout are left alone and listed so you can set them up by hand in TeknoParrotUI. This has not been verified with a real trackball.
  - Choice 3 shows or prints the controls of one game (it suggests your key only for coin, start, numbered buttons and plain directions, and says "I'm not sure" for the rest). Choice 4 tells TPM a game played well (the game's controls are then called Verified until they or the settings change). TPM can also tell you whether you changed your arcade encoder. The encoder check is a hint only and never changes a saved key or answer.

More in **My controls**: the page for one game starts with plain lines that compare the game with what you told TPM (enough players and buttons, and any device the game needs that you said you do not have, with what can stand in). It only compares and changes nothing. If you saved keys before, learning asks once whether to keep them, then asks only for the controls that have no saved key. Learning buttons first asks if your cabinet has an Exit, Pause or Menu button (Esc counts as a key for these). Choice 6, "Undo my last save", appears when an older copy of your answers exists: it shows what comes back, asks once, and keeps your newest answers as a copy.

**5 - Change one control by hand.** Pick any game, then one control from the list (each line shows what it is set to now), then press `X` to pick a pad button from a list, `C` to clear it, or `K` to press the key your keyboard or arcade encoder sends. `B` or `Esc` changes nothing. A saved copy of your game settings is made first and the file is read back to check it. TPM keeps what you set: setting up games again and Learn my arcade buttons skip those controls and say "Kept your own setting for N controls." `T` puts TPM's choice back. The first line of the list, Input type, keeps a game on its own input type. Triggers and sticks are not changed here.

What a layout setup does and does not do:

- It sets only controls that TeknoParrot's own file for the game lists, and only when your saved settings for the game are the same version as that file. Otherwise the game is left alone, and the screen says why (often: open the game once in TeknoParrotUI).
- It never replaces a controller button that is already set and never touches keyboard or arcade-encoder settings.
- **A clash skips only that control.** If a button the layout wants is already used by another control in that game, only that one control is skipped and named under "Still needs you". The rest of the game is still set up. TPM never writes a pad button that another control already uses. Set the skipped control with choice 5 or in TeknoParrotUI.
- It does not set triggers or analog sticks (steering, aim, throttle). The preview names them so you can set them in TeknoParrotUI.
- PlayStation and Nintendo controllers only work here when something shows them to Windows as an XInput controller. XInput is the standard mode most pads use, including PlayStation and Nintendo pads through Windows. An arcade stick needs its XInput mode only for the arcade stick layout. If your arcade encoder is in keyboard or DirectInput mode, choose **My learned arcade controls**.
- Switching a game to XInput may stop that game from using an arcade encoder. Choose game by game if you are not sure.
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
