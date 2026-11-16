# RC8 Lane H - stale test expectations (decision record)

| # | Test (approx line) | Original target | Decision | New target / reason |
|---|---|---|---|---|
| 1 | renders bounded compact progress (~3608) | regex-extracted Get-TpmCompactProgressText | Deleted | wording-only checks (PadRight, elapsed) on removed helper |
| 2 | truncates, shows elapsed heartbeat (~3614) | Get-TpmCompactProgressText | Retargeted | Format-TpmProgressLine; Length -Be 40 kept; heartbeat at width 200 |
| 3 | renders actual bounded progress bar (~22113) | Get-TpmCompactProgressText | Retargeted | Format-TpmProgressLine; bar/50%/5/10/phase kept; Length -BeLessOrEqual 100 |
| 4 | returns bounded row from actual writer (~3619) | writer | Wording line deleted | writer call and Length -Be 30 kept |

Base: 785647659aff687b7d2fae7518be3ad25a298243. Tests not run (owner hold).
