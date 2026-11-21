# Propagate Controls (menu 3)

Set up the controls for one game of each type, and TeknoParrot Manager copies them to your other games of the same type. This menu item does only that. No game is registered or unzipped.

The same step also runs at the end of [[AutoSync]] and [[Register]]. Use menu 3 when your games are already registered and you just set up a new example game in TeknoParrotUI.

---

## Before you start

1. In TeknoParrotUI, set up every button and axis of one game for each control type you use. The control types are button, driving, lightgun, trackball, analog and spinner.
2. A game counts as an example game when at least five of its controls are set up.
3. Start TeknoParrot Manager and type `3` at the main menu.

---

## What it asks

TeknoParrot Manager first says how many example games you have. Then it asks:

```
Copy controls from N games to your other games of the same type? (Y/N, D = details)
```

Press `D` first. It lists each example game with its control type, the settings that will be copied, and any warning. These settings are copied to every other game of that type, so check them against your real hardware before you answer `Y`.

If a copied setting looks wrong, a yellow `Check first` line appears above the question. The usual warnings are:

- **Driving:** `Use Keyboard/Button For Axis` is True. A real wheel and pedals should have this False.
- **Lightgun:** `Use Relative Input` is True. Most real lightguns need this False.
- **Any type:** a sensitivity value of 0, which turns aiming or the axis off.

A warning does not block the copy. Answer `N`, fix the example game in TeknoParrotUI, then run this again.

---

## What it changes

- A saved copy of your `UserProfiles` is made when you answer `Y`. The folder is shown afterwards. You can put it back with [[Restore Backup]].
- Buttons that are already set up are kept. TeknoParrot Manager may still correct an Input API setting without setting buttons again.
- It copies only to games of the same control type.
- A game with no example game of its type is skipped and reported as `no usable reference game`. Set up one game of that type, then run this again.
- Controls that the example game does not have stay for you to set up in TeknoParrotUI.

A game marked as copied is not proof that its controls work. Start one game and test it before you trust the rest.

---

## Your controller layout and the controls check

Menu 3 first asks which of these you want. Choice 1 is the copy described above.

- **2 - Set up games with my controller layout.** The first time, choose a layout once: Xbox, PlayStation, Nintendo or arcade stick. You can change any single button. Test and Service start empty. Then set up one game, all your games at once (one preview, one `Y`), or game by game (a `Y` for each game).
- **3 - Choose or change my controller layout.** It is saved in the Manager's own settings folder. A connected Xbox-style controller only pre-selects the Xbox choice.
- **4 - Check which games have all their controls.** Every registered game is sorted into every control set up, some, none, or cannot tell. Press `D` for the games and the controls that are still missing. The Library health check shows the same counts on a Controls line. It changes nothing.

What a layout setup does and does not do:

- It sets only controls that TeknoParrot's own file for the game lists, and only when your saved settings for the game are the same version as that file. Otherwise the game is left alone, and the screen says why (often: open the game once in TeknoParrotUI).
- It never replaces an Xbox button that is already set, never touches keyboard or arcade-encoder settings, and leaves a game alone when an Xbox button it wants is already used by another control in that game.
- It does not set triggers or analog sticks (steering, aim, throttle). The preview names them so you can set them in TeknoParrotUI.
- PlayStation and Nintendo controllers only work here when something shows them to Windows as an Xbox controller. An arcade stick must be in its Xbox mode.
- A saved copy of your game settings is made and checked first. Each changed game is read back and compared, and put back exactly if the check fails. You can undo the whole run afterward.

The controls check and the layout setup are not a test. Most game control lists come from TeknoParrot's own game file and no person has checked them. Start one game and test it.

---

## If a game has the wrong control type

TeknoParrot Manager guesses the control type from the game's buttons. It cannot guess `spinner` at all. To fix a wrong or missing guess, add the game to `familyOverride` in `TeknoParrot-Manager.overrides.json` (next to the script):

```json
{ "familyOverride": { "ProfileCode": "spinner" } }
```

Valid values are `button`, `driving`, `lightgun`, `trackball`, `analog` and `spinner`. The override now also counts for the example games, so a game set to `spinner` can be an example game for other spinner games instead of ending up with `no usable reference game`.

<details><summary>Details</summary>

Other settings in the same overrides file:

- `noPropagate` -- profile codes that are never changed by this step.
- `forceArchetype` -- `{ "ProfileCode": "ExampleGameCode" }` copies that game's controls from the example game you name instead of the automatic best match.

After every real run, `TeknoParrot-Manager-controls.txt` in `<your TeknoParrot folder>\TeknoParrotManager\Reports\` lists every registered game, its control type, how many buttons are set, and which example game its controls came from. It is a record of what was copied, not a test of your controls.

</details>

---

## Not sure which game to set up first?

The step after registration also offers a binding plan: it asks which controls you own (pad, arcade stick, trackball, spinner, wheel, lightgun, keyboard) and suggests which game to set up with which device. It reads nothing and changes nothing.
