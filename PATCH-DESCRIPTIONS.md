# What every patch recipe does, in plain words

Last updated: 2026-11-07 (round 2). This file covers all 124 recipes in `scripts/TpmRequiredPatchRecipes.json` (58 game profiles).

Three kinds of recipe:

- **Repair** - TPM puts back a file the game should already have. If the right file is already there, TPM does nothing and says so. Most of these come from the game's own ZIP; a few need a separate patch ZIP that you provide.
- **Change** - TPM replaces one exact file with a different one (a fix or a mod). It only acts if the file on disk is the exact version listed, so it never touches a version it does not know.
- **Setting change** - TPM changes one line (or a few lines) in a game's own settings file, such as a `.ini` or `.cfg` file. It checks that exactly the expected line is there, saves a full copy of the file first, and can put it back. Nothing is downloaded.

Nothing here is downloaded and nothing is installed without asking. The patch ZIPs are yours and stay yours.

Where the patch file comes from: TeknoParrot Manager never downloads one. For the "APM3 Component" rows below (Dead or Alive 6, Goonya Fighter APM3 Edition, Otoshu DX, Puyo Puyo e-Sports, Blade Strangers, Blazblue Cross Tag Battle, Rolling Gunner, Senxin Aleste, Koihime Enbu RyoRaiRai Version 3), the same `apm.dll` or `apm_x86.dll` is also inside the game's own ZIP (named like the game build, for example `Otoshu DX (1.00.00)(2020-02-15)(JPN)[Sega ALLS][TP].zip`; Goonya Fighter keeps it in the `game` folder). TeknoParrot Manager accepts either that ZIP or a separate `... - APM3 Component.zip`, and checks the file inside it exactly the same way. The two "APM3 File" rows (Guilty Gear Strive, Guilty Gear Xrd Rev2) and the other separate patch ZIPs are separate downloads that TeknoParrot Manager does not provide.

Words used below: a "shader" is a small file that tells your graphics card how to draw the picture, "BepInEx" is a free add-on loader some Unity games need, and "APM3" is the helper file that lets a game talk to the ALLS arcade board.

| Game (versions) | Patch name in the patch folder | What it does, and what you must know |
|---|---|---|
| Family Guy Bowling (1.15) | TP Plugin v1.7 | Puts back the small plugin that lets TeknoParrot's controls and settings work. BepInEx must already be set up for the game. |
| Shining Force Cross Elysion (2.06.00 Ver C) | AMD Shader Fix / NVIDIA Shader Fix | Puts in the shader files that match your graphics card. Without the right set the game renders badly or crashes. Pick the one for your card. |
| Shining Force Cross Raid (1.05, 1.05 Ver A) | AMD Shader Fix / NVIDIA Shader Fix / original shader restore | Same idea: the shader set for your card, plus a way to put the shipped shader back if you want to start over. |
| Virtua Fighter 5 R (1.001) | AMD Shader Fix / NVIDIA Shader Fix | Swaps in the shader pack that matches your graphics card. Without it the game shows broken or missing 3D graphics. Pick the one for your card; only applies to the exact shipped file. |
| Virtua Fighter 5 Final Showdown (4.000 Rev 1) | AMD Shader Fix Components | The game ships the NVIDIA shader pack; this swaps in the AMD pack for AMD cards. Only use it if you have an AMD GPU - otherwise leave the game as it is. |
| BlazBlue Continuum Shift (2009), Continuum Shift II, Cross Tag Battle (1.04.00, 2.01.00), Central Fiction, Chronophantasma (2.03) | iDmacDrv32 Driver / Fix iDmacDrv32 | Puts back the small driver the game uses to read the card reader and buttons. Without it the game will not start. Chronophantasma's recipe puts the older driver back because the shipped one is too new for OpenParrot. |
| Rabbids Hollywood (2018) | Arcade TP trigger & crosshairs fix; BepInEx Operator Configuration Pack | The first puts the shipped script file back (the game breaks if it is missing). The second adds the plugin that makes the arcade trigger and crosshairs behave like the real cabinet. BepInEx must be installed. |
| NERF Arcade (1.55) | TPPlugin v1.0 | Puts back the TeknoParrot plugin so controls and settings work. BepInEx must already be set up for the game. |
| Rainbow BomberGirl (2022-12-15) | BBGTPPlugin v1.9 | Puts back the TeknoParrot plugin so controls and settings work. |
| Teenage Mutant Ninja Turtles (1.59) | TPPlugin v1.2; OrenVid / PK-UnityPlugin restores | Puts back the TeknoParrot plugin and the two helper DLLs the game came with. Use it if a cleanup tool or antivirus removed them. |
| Silent Hill The Arcade (2007-12-20) | Fix IndirectSound_0_20 | Puts back the sound wrapper DLL the game needs. Without it there is no audio or the game fails on start. |
| Taisen Hot Gimmick 5 (2.04) | game ZIP only (no separate patch) | Restores the small Taito Type X monitor, config and loader files the game needs to launch and to be displayed correctly. |
| Mars Sortie (1.46.9) | TPPlugin_v1.2 | Puts back the TeknoParrot plugin so the game takes TeknoParrot's controls. |
| Super Bikes 3 (1.91 x64) | TPPlugin_v1.09 x64; Unity Fmod x64 v1.10.10 | Restores the TeknoParrot plugin and the two FMOD sound DLLs the game loads. Missing sound DLLs mean no audio or a crash on start. |
| Sonic Dash Extreme (2015) | 60fps 60Hz Original and Patched Executables | Swaps the game executable for the version that runs at 60 frames per second and 60 Hz instead of the default. Only acts on the exact original executable. |
| Hummer (1.0), Hummer Extreme Edition (1.0) | game ZIP only (no separate patch) | Restores the 14 shader files that stop the picture flickering on modern graphics cards. Use it if a "shader fix" was partly applied or deleted. |
| Primeval Hunt (1.0) | NVIDIA and Intel Shader Fix | Restores the two shader files that make the game render on NVIDIA and Intel cards. |
| Infinity Blade FX (1.02) | TP Infinity Blade FIX v2 / infinityblade.FIX.v1 | Puts back the DLL files (small program parts) the fix needs. It assumes the game's original DLL backup and `TPFIX.ini` (the fix's settings file) are already in place. |
| maimai GreeN (2013) | game ZIP only (no separate patch) | Restores `freeglut.dll` and `libcurl.dll` into the installed game folder, using the copies inside the game's own ZIP. The game needs both to start. |
| King of Fighters Maximum Impact Regulation A (2007) | game ZIP only (no separate patch) | Restores the four old graphics wrapper DLLs (`d3d8`, `d3d9`, `ddraw`, `wined3d`) that the game needs to draw anything. |
| Mario Kart Arcade GP DX (1.06.35-OF USA) | D3D11Ref x64 | Restores the shipped graphics helper DLL. Without it this build shows a black screen. |
| Gashaaaan Refill! (2009-02-24) | Jurassic Park ZIP as the source | Restores the three OGG/Vorbis sound DLLs. They are byte-identical to the ones in the Jurassic Park package, so that ZIP is used as the donor when the game folder lost them. |
| Dead or Alive 6 (1.00.00 to 1.04.00, and 1.06.00) | APM3 Component | Adds `apm.dll`, the file that lets the game talk to the ALLS arcade board. Without it the game does not start. One recipe per version. |
| Goonya Fighter APM3 Edition (1.00.00 to 1.03.00) | APM3 Component | Adds `apm.dll` in the `game` folder so the game can start. One recipe per version. |
| Otoshu DX (1.00.00), Puyo Puyo e-Sports (1.00.01) | APM3 Component | Add `apm.dll` so the game can start. |
| Blade Strangers (2.01.00), Blazblue Cross Tag Battle (four builds), Rolling Gunner (2.00.00, 2.01.00), Senxin Aleste (1.00.00, 1.01.00), Koihime Enbu RyoRaiRai Ver 3 (four builds) | APM3 Component | Add `apm_x86.dll`, the 32-bit version of the same arcade helper file, so the game can start. |
| Guilty Gear Strive (2021) | APM3 File | Adds `apm.dll` in the game's `WindowsNoEditor` binary folder so the game can start. |
| Guilty Gear Xrd Rev2 (APM3) (2.10) | APM3 File | Adds `apm_x86.dll` so the game can start. |
| Street Fighter V Type Arcade (3.53) | FTD2XX DLL Fix | Adds `ftd2xx.dll`, a USB helper the game needs to talk to its I/O board. |
| 3D Cosplay Mahjong (1.00) | 3D Mahjong Crash Fix | Adds `dsound.dll`, which stops the game crashing at start on modern Windows. |
| Blazing Angels Squadrons of WWII (1.00 b1892) | Launch Fix | Adds `bin/MSVCP71.dll`, an old Microsoft runtime file the game cannot launch without. |
| Music GunGun! 2 (1.01) | missing DLL | Adds `msvcr71.dll`, an old Microsoft runtime file the game cannot run without. |
| P4UU Persona 4 The Ultimax (2013) | Fix iDmacDrv32 | Adds the card-reader driver the game needs for buttons and cards. |
| Injustice Arcade (1.74) | TPVirtualCards v1.2 | Adds `TPVirtualCards.dll`, which makes the card reader work. |
| Chase Chase Joker (2023-10-03) | PLUGIN_v1.1 (TP) | Adds a BepInEx plugin so TeknoParrot controls and settings work in the game. BepInEx must already be installed. |
| Need for Speed Heat TakeDown (2023) | NFSHTTPPlugin_v1.5 | Adds a BepInEx plugin so TeknoParrot controls and settings work. BepInEx must already be installed. |
| Wild West Shootout (3.3.2103.T) | TPPlugin_v1.4 | Adds a BepInEx plugin so TeknoParrot controls work. BepInEx must already be installed. |
| ReVolt (2004) | Tsunami_ddrawDLLfix | Restores `Tsunami/ddraw.dll` so the old graphics layer starts on Windows 10 and 11. |
| Arctic Thunder (1.002) | Glide3x wrapper dll for Arctic Thunder | Puts back the Glide wrapper DLL next to `snow.exe`. Without it the game cannot draw its 3D graphics. |
| Go Go Strike (2007) | DLLFix | Puts back `alleg40.dll`, the Allegro library the game was built with. Missing means no start. |
| NERF Arcade (1.55) | PK-UnityPlugin | Puts back the large Unity helper DLL under `Nerf_Data/Plugins`. The game will not start without it. |
| Super Bikes 2 (1.5.5) | Game api Dll | Puts back `ewfapi.dll`, a small engine file the game needs. (The separate 142 MB exe fix has no recipe yet.) |
| Walking Dead, The (01.05) | WD105_DLLfix | Puts back three helper DLLs (`libeay32`, `ssleay32`, `zlib1`) in the game's `pm` folder. They are the same files the game came with. |
| Virtua Fighter 5 (1.001 Ver B) | NVIDIA Shader Fix | Swaps in the shader pack that runs on NVIDIA cards. Only applies to the exact shipped file; use it if the game shows broken or missing graphics. |
| Virtua Fighter 5 (6.001 Ver C) | AMD Shader Fix | Swaps in the shader pack that runs on AMD cards (the shipped pack is the NVIDIA one). Pick the set that matches your card. |
| Taiko no Tatsujin Nijiro Version (March 2020) | Freeze Song Selection Timer | A small mod that stops the song-select countdown so you can choose without rushing. It is a change, not a repair; the game runs fine without it. |

## Not included, and why

| Game / package | Why there is no recipe |
|---|---|
| Galaga Assault "TPdllFix" (`SDL2.dll`) | The patch file is byte-identical to the game's own `SDL2.dll.old` backup, so it would put the older file back. Removed in review; re-add only with proof that a real install needs it. |
| Castlevania The Arcade "The Arcade Fix" (`HCV_APP/d3d9.dll`) | Same pattern: identical to the shipped `d3d9.dll.original`, i.e. it undoes the fix. |
| Doodle Jump Arcade "DoodleJump_DLLFix" (`soil.dll`) | The game ZIP here has no matching TeknoParrot profile, so the recipe could never run. The file is already in the game ZIP anyway. |
| X-Games Snowboarder "D3D8 Wrapper" and "Missing DLL Restoration" | The game ships both `sdaemon_x64.exe` and `sdaemon_x86.exe`, the profile names neither, and the two are different builds. A recipe would refuse to run for one of the two users. Needs a decision on which exe TPM uses. |
| Virtua Fighter eSports (2021) "APM3 Files" | The patch uses a `runtime/media/...` layout that does not exist in the game ZIP here, and all three payloads are byte-identical to files the game already has. |
| Walking Dead "105_ELFfix" (`gamed`) | The payload is byte-identical to the game's own `pm/game`; nobody can show which path the loader wants. Writing a duplicate file would not fix anything. |
| Super Bikes 2 "Fix exe" (142 MB), Spider-Man "Spiderman Fix" (175 MB) | No recipe has been written for them yet. |
| Resolution-variant packs, bezels, configs, installers, translation installers, `.reg` files | Not game-file repairs or swaps; they are choices or tools, so they are not "required" recipes. |
| Lady Luck (2.00.01) | I/O board COM port off | Sets one line in the game script file `game_conf.lua` so the game does not look for an I/O board COM port. TPM saves a copy first and can undo it. |
| Lost Land Adventure (1.00) | Shader reload off (optional) | Sets one line in `BaseEngine.ini` (automatic shader reload off). Only use it if the game crashes. |
| SiN (2001) | Fullscreen on | Sets the fullscreen line in `config.cfg` to 1 so the game starts full screen. |
| America's Army Arcade (1.01.082) | Display and gore settings | Sets seven lines in `ArmyOps.ini`: the window, full screen and menu sizes to 640 by 480, and the gore level to 1. All seven change together or none do. |