# FFB Setup

Force feedback makes a wheel or stick push back and rumble like in the game: road bumps, recoil, crashes. It is main menu item 9, **Force feedback (FFB) setup**.

There are two ways to get it. You can use one or both. They cover different games, and some games are covered by both.

1. **FFB Blaster** is built into TeknoParrot. It needs a paid TeknoParrot membership.
2. **The FFB plugin** is a free add-on for other games. It needs no membership.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-18:` type `9` and press Enter.
2. You are asked `Do you have a paid TeknoParrot membership?` Press `Y` to turn on FFB Blaster. Press `N` to skip it.
3. You are asked whether to set up the free plugin: `[Y] Set up the free FFB plugin (the newest version; each game gets its own settings file)` or `[N] Skip the optional plugin`. The default is `N`.
4. If you said `Y`, you are asked about your wheel. Pick it from the list of game controllers, or skip (see "Your wheel" below).
5. If a game is covered by both, you are asked which one to use (see below).
6. If you chose the plugin, you see what will be installed or updated and are asked `Go ahead?` The plugin is not installed until you say `Y`. The FFB Blaster step (step 2) is already finished by then.
7. Read the result. Start a game to try it.

---

## FFB Blaster (needs a membership)

TeknoParrot Manager cannot check your membership, so it asks. If you answer `N`, FFB Blaster is skipped and nothing is changed.

If you answer `Y`, it finds every registered game that has the FFB Blaster setting and turns it on. New games are covered automatically. A copy of your UserProfiles is saved first. Join at teknoparrot.com/en/Home/Subscription.

---

## The free FFB plugin

The plugin comes from [mightymikem/FFBArcadePlugin](https://github.com/mightymikem/FFBArcadePlugin) on GitHub. TeknoParrot Manager does not ship it. Each time, it finds the **newest release** and tells you which one it is using, for example `Using FFB Arcade Plugin v.2.0.0.51`. The release is about 93 MB. It is downloaded once, saved, and downloaded again only when a newer release comes out. You need to be online. If you are not, and a saved copy that passed its check is on your PC, you are asked whether to use it. It may not be the newest one.

For each supported game, TeknoParrot Manager puts three files in the game's folder:

- the plugin, renamed to the file name that game loads (for example `d3d9.dll`)
- that game's own `FFBPlugin.ini` settings file
- `SDL2.dll`, but only if the game does not already have one. A game's own `SDL2.dll` is never replaced.

If TeknoParrot Manager cannot tell that the plugin file and the game are both 32-bit or both 64-bit, that game is skipped and nothing is placed. If the plugin does not tell which file name a game loads, the game is skipped and the screen says so.

A game is skipped, and nothing is overwritten, when a file with the same name is already there and TeknoParrot Manager did not put it there (for example ReShade's `d3d9.dll`, or your own `FFBPlugin.ini`). The one exception is an old plugin file: TeknoParrot Manager recognizes it by its fingerprint (SHA-256), says so before it changes anything, backs it up, and replaces it. A file that does not match is never touched.

### Your wheel

Before it installs, TeknoParrot Manager lists the game controllers Windows can see, by name: wheels, joysticks, gamepads, and Xbox and PlayStation controllers. Type the number of your controller, or `S` to skip. A wheel is written into every settings file it installs. A controller with no USB numbers can be picked, but no wheel is written; the plugin is still installed and each game's rumble settings are left as the plugin ships them. If no controller is found, you can go on without one and run Force feedback again later. Type `D` to see the technical numbers.

### Updating

Run Force feedback again after a newer release. You see what will change and are asked first. Files TeknoParrot Manager installed earlier and you have not changed are backed up and replaced. If you changed a game's `FFBPlugin.ini`, you are asked, and the default is to keep your file. To change your wheel, run it again and pick another one. Games that only have the old single plugin file from an earlier version of TeknoParrot Manager are upgraded the same way, with a backup.

---

## When a game is covered by both

TeknoParrot Manager lists the games covered by both. Then you answer once for all of them:

- `Y` -- keep native FFB Blaster (recommended, the default)
- `N` -- use the plugin instead. FFB Blaster is turned off on those games first.

---

## Undo

- **FFB Blaster:** set the field back to `0` in the game's `UserProfiles\*.xml`, or use [[Restore Backup]] to go back to the saved copy. A restore also puts back anything else changed after that copy was made.
- **Plugin:** to start the undo, open main menu item 9 (**Force feedback (FFB) setup**). Answer `Y` to the membership question, and `Y` to setting up the free plugin (the default is `N`; with `N` you never reach the next question). When asked about games covered by both, answer `Y` (keep native FFB Blaster). TeknoParrot Manager then backs up and removes only plugin files it recorded as its own (the plugin, the settings file and `SDL2.dll`), and only if they are unchanged. This works for games covered by both. For a game only the plugin covers, there is no menu choice to remove it. If you are not sure a file is part of the plugin, leave it.

[[Health Check]] shows which registered games could use FFB Blaster but do not have it on yet. It does not check the plugin, because that needs a look at the newest release online.

<details>
<summary>Details: if setup skips games</summary>

The result lists how many games were installed, already up to date, kept on native FFB, skipped because a file already exists, skipped because the plugin does not support them, skipped because the plugin file name is not known, or skipped because the plugin file does not fit the game. Games whose saved path or drive cannot be found are named. Fix them with [[Health Check]] (menu 14), then run setup again.

If GitHub cannot be reached, or does not return a usable release, the plugin is not installed or changed and you can try again (if a saved copy is on your PC, you are asked whether to use it). A download is also refused, with the plugin left as it was, if it does not match the checksum GitHub published for it or if its contents do not pass the safety checks. If GitHub publishes no checksum, the screen says so. There is no publisher signature check.

</details>
