# Compatibility Checklist

This is a lightweight pre-1.0 checklist for tester notes and release-readiness decisions. Keep it short; detailed per-game behavior belongs in GitHub issues or tester reports.

## Release-blocking checks

- [ ] FATF Drift duplicate wheel mapping behavior confirmed by a real tester (issue #53).
- [ ] AutoSync/Register smoke test completes on a representative library.
- [ ] Crosshair setup smoke test confirms generated HTML preview and deployed cursor files.
- [ ] Restore backup flow verified for `UserProfiles`.
- [ ] Library health check remains read-only.

## Known compatibility watchlist

- RawInput wheel/pedal profiles with duplicate or overlapping mapping keys.
- Games with RawInput trackball or uncommon analog layouts.
- Long install paths for Raw Thrills titles and Yu-Gi-Oh! Duel Terminal 6.
- Pinned-file-version requirements for known iDmac/EBOOT cases.
- AMD/Intel GPU-specific compatibility warnings.
- [ParrotOrganizer](https://github.com/natemac/ParrotOrganizer): TeknoParrot-adjacent organizer/launcher; watch releases/tags, curated database revisions, profile/install/launch behavior, metadata-model changes, controls/settings editor behavior, gamepad navigation, and compatibility data that may inform future TPM issues.

## Documentation follow-up

- Link confirmed tester reports back to the related issue.
- Convert repeated tester findings into README troubleshooting notes only when they are stable.
- Do not block 1.0 on broad compatibility documentation unless a release-blocking issue needs it.
