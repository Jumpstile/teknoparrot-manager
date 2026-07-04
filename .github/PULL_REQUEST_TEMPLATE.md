## Summary

<!-- What changed and why. -->

## Test tier run (issue #109 -- cost-aware testing)

<!-- State which tier you ran and why. See RELEASE-SAFETY-CHECKLIST.md
     section 1, "Cost-aware test selection," for the tier table. -->

- [ ] Docs-only -- no test run required
- [ ] Menu/UI wording or layout -- parse check + targeted menu tests
- [ ] Version parser or updater logic -- targeted parser/updater regression tests
- [ ] Shared utility function -- affected-area tests, then one full suite before PR-ready
- [ ] Release-candidate or release change -- full suite + release packaging checks
- [ ] Hardware/environment-dependent behavior -- validated locally

Tier run: <!-- name it -->
Why: <!-- one line -->

## Certification

- [ ] Full suite run at least once before this PR was marked ready (not necessarily every commit)
- [ ] Every real defect fixed in this PR has a permanent regression test
- [ ] No version identity changes without explicit Release Manager authorization
