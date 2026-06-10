\# TeknoParrot Manager



PowerShell 5.1 script for managing TeknoParrot arcade game libraries.

Current version: v0.31 BETA



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

