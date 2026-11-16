# FFB Setup

Force feedback makes a wheel or stick push back and rumble like in the game: road bumps, recoil, crashes. It is main menu item 8, **Force feedback (FFB) setup**.

There are two ways to get it. You can use one or both. They cover different games, and some games are covered by both.

1. **FFB Blaster** is built into TeknoParrot. It needs a paid TeknoParrot membership.
2. **The FFB plugin** is a free add-on for other games. It needs no membership.

---

## Quick steps

1. Start TeknoParrot Manager. At `Enter 1-17:` type `8` and press Enter.
2. You are asked `Do you have a paid TeknoParrot membership?` Press `Y` to turn on FFB Blaster. Press `N` to skip it.
3. You are asked whether to set up the free plugin: `[Y] Set up the free third-party FFB plugin` or `[N] Skip the optional plugin`. The default is `N`.
4. If a game is covered by both, you are asked which one to use (see below).
5. Read the result. Start a game to try it.

---

## FFB Blaster (needs a membership)

TeknoParrot Manager cannot check your membership, so it asks. If you answer `N`, FFB Blaster is skipped and nothing is changed.

If you answer `Y`, it finds every registered game that has the FFB Blaster setting and turns it on. New games are covered automatically. A copy of your UserProfiles is saved first. Join at teknoparrot.com/en/Home/Subscription.

---

## The free FFB plugin

The plugin comes from [mightymikem/FFBArcadePlugin](https://github.com/mightymikem/FFBArcadePlugin) on GitHub. TeknoParrot Manager does not ship it. It downloads the current list of supported games and the plugin files each time, and checks them before use. You need to be online.

For each supported game it puts the plugin file in the game's folder. It uses the 64-bit plugin for a 64-bit game and the 32-bit plugin for a 32-bit game. If it cannot read whether a game is 32-bit or 64-bit, that game is skipped and no plugin file is placed.

A game is skipped, and its existing file is not overwritten, when a file with the same name is already there (for example ReShade's `d3d9.dll`). A file TeknoParrot Manager did not put there is never overwritten. A plugin you installed earlier with TeknoParrot Manager is updated.

---

## When a game is covered by both

TeknoParrot Manager lists the games covered by both. Then you answer once for all of them:

- `Y` -- keep native FFB Blaster (recommended, the default)
- `N` -- use the plugin instead. FFB Blaster is turned off on those games first.

---

## Undo

- **FFB Blaster:** set the field back to `0` in the game's `UserProfiles\*.xml`, or use [[Restore Backup]] to go back to the saved copy. A restore also puts back anything else changed after that copy was made.
- **Plugin:** delete the plugin file TeknoParrot Manager placed in that game's folder. TeknoParrot Manager only ever removes plugin files it recorded as its own. If you are not sure a file is the plugin, leave it.

[[Health Check]] shows which registered games could use FFB Blaster but do not have it on yet. It does not check the plugin, because that needs a live download.

<details>
<summary>Details: if setup skips games</summary>

The result lists how many games were installed, kept on native FFB, skipped because a file already exists, skipped because the plugin does not support them, or skipped because the plugin file or the game type was unavailable. Games whose saved path or drive cannot be found are named. Fix them with [[Health Check]] (menu 13), then run setup again.

If GitHub cannot be reached, or does not return a usable list, nothing is changed and you can try again.

</details>
