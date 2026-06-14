\# TeknoParrot Manager



PowerShell 5.1 script for managing TeknoParrot arcade game libraries.

Current version: v0.58 BETA



\## Files

\- TeknoParrot-Manager.ps1        — main script

\- TeknoParrot-Manager-README.txt

\- TeknoParrot-Manager-QuickStart.txt

\- TeknoParrot-Manager-CHANGELOG.txt — update on every version bump



\## Key conventions

\- Version bump required on every meaningful change set

\- All file writes use WriteAllText with BOM-less UTF8:

&#x20; (New-Object System.Text.UTF8Encoding $false)

\- All Get-ChildItem uses -LiteralPath

\- Backup before every destructive operation

\- Safety over convenience — never guess, never silently swallow errors

\- Numbered step-by-step output for every user-facing action



\## Paths on this machine

\- Scripts folder    : W:\\Emulators\\TeknoParrot\\Scripts

\- TeknoParrot root  : C:\\Users\\EliSi\\LaunchBox\\Emulators\\TeknoParrot

\- Games staging     : E:\\Games\\TeknoParrot Games

\- ZIP source (NAS)  : W:\\ROMS\\TeknoParrot Collection

\- ReShade DLLs      : Scripts\\ReShade\\ReShade64.dll (x64) and ReShade32.dll (x86, optional)

&#x20; Run ReShade installer on any game exe to get the DLL, then copy/rename here for distribution

\- Crosshairs folder : Scripts\\Crosshairs\\ (321 PNGs, 000.png–320.png)

\## ReShade bundling notes

\- Bundle ReShade64.dll at Scripts\\ReShade\\ReShade64.dll for distribution (required)

\- Bundle ReShade32.dll at Scripts\\ReShade\\ReShade32.dll for 32-bit game support (optional)

\- The script auto-detects both bundled DLLs; version checked via FileVersionInfo vs reshade.me

\- Per-game arch detection: x86 → ReShade32.dll; x64 → ReShade64.dll; unknown → ReShade64.dll

\- To update bundled version: obtain new DLL(s), replace, bump script version

\- BudgieLoader games → renamed to opengl32.dll

\- OpenParrot games → deployed to openparrot\\ subfolder if it exists

\- API detection scans first 2 MB of game exe for DX/GL import strings

\## dgVoodoo2 bundling notes

\- Bundle DLLs at Scripts\\dgVoodoo2\\ (not included in repo; user provides)

\- Required DLLs from dgVoodoo2 ZIP: MS\\x86\\D3D8.dll, DDraw.dll, D3DImm.dll + 3Dfx\\x86\\Glide2x.dll, Glide3x.dll + root dgVoodoo.conf

\- dgVoodoo.conf (optional config) also copied if present

\- API detection: Get-GameLegacyApi scans first 2 MB for D3D8/DDraw/Glide2x/Glide3x imports

\- DLL mapping: D3D8→D3D8.dll+D3DImm, DDraw→DDraw.dll+D3DImm, Glide2x→Glide2x.dll, Glide3x→Glide3x.dll

\- Bug/vulnerability sweep required before every version build

\- Script must be pure ASCII (no Unicode characters anywhere). PS 5.1 reads
&#x20; BOM-less UTF-8 as Windows-1252; the last byte of U+2014 (em dash, E2 80 94)
&#x20; is 0x94 which Windows-1252 maps to U+201D (right double-quote, a string
&#x20; delimiter), causing parse errors. Use -- for em dashes, -> for arrows.
&#x20; Verify with: ($bytes=[System.IO.File]::ReadAllBytes($f); ($bytes | Where-Object { $_ -gt 127 }).Count)

