# Compatibility Checklist

This is a lightweight pre-1.0 checklist. Use it for tester notes and release-readiness decisions.

Keep it short.

Detailed per-game behavior belongs in GitHub issues or tester reports.

## Release-blocking checks

These checks must pass before the final release.

- [ ] FATF Drift duplicate wheel mapping behavior confirmed by a real tester (issue #53).
- [ ] AutoSync/Register smoke test (a quick basic test) completes on a representative library.
- [ ] Crosshair setup smoke test confirms the owned preview window and deployed cursor files.
- [ ] Restore backup flow verified for `UserProfiles` (TeknoParrot's saved game settings folder), PostgreSQL, and LaunchBox backups.
- [ ] Library health check remains read-only. This means it only looks and never changes anything.

## Known compatibility watchlist

These are the known trouble spots to watch for.

- RawInput wheel/pedal profiles with duplicate or overlapping mapping keys.
- Games with RawInput trackball or uncommon analog layouts.
- Long install paths for Raw Thrills titles and Yu-Gi-Oh! Duel Terminal 6.
- Pinned-file-version requirements for known iDmac/EBOOT cases.
- AMD/Intel GPU-specific compatibility warnings.

### More detail

- RawInput is a Windows way for games to read wheels, pedals, and trackballs.
- A "profile" is a game setup file.
- A "mapping key" is the button or axis that a control is tied to.
- A "long install path" is a folder path with so many characters that Windows has trouble with it.
- "Pinned-file-version" means a game needs one exact version of a file.

## Documentation follow-up

Do these three things with tester reports.

- Link confirmed tester reports back to the related issue.
- Convert repeated tester findings into README troubleshooting notes only when they are stable.
- Do not block 1.0 on broad compatibility documentation unless a release-blocking issue needs it.
