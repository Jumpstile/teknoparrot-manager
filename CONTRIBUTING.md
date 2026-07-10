# Contributing to TeknoParrot Manager

Thanks for taking the time to report an issue, suggest something, or send
a fix. This document covers how work is tracked in this repository; for
what the project actually does and how it's built, start with
`README.md` and `ARCHITECTURE.md`.

## Filing an issue

- **Bug reports**: include what you expected, what actually happened, and
  (if you have it) the exact console output or error message. If it's
  reproducible, say how.
- **Feature requests**: describe the problem you're trying to solve, not
  just the feature you want -- it's easier to evaluate a request against
  its actual goal than against a specific proposed implementation.
- Check `LESSONS_LEARNED.md` and existing closed issues first if your
  report might be a known, already-documented case.
- During a feature freeze (see `CLAUDE.md`), new feature requests are
  still welcome -- they'll be labeled `release:post-1.0` and considered
  once the freeze lifts, rather than declined outright.

## Issue labels

Every issue in this repository is labeled against a fixed taxonomy --
Type, Priority, Component, and (where applicable) Release and Status. You
don't need to apply labels yourself when filing an issue; a maintainer
triages new issues against this taxonomy. If you're curious what the
labels mean, or want to understand how release-blocking issues are
identified, see **`ENGINEERING_GOVERNANCE.md`** -- that's the canonical
reference for the full label taxonomy and how issues move through their
lifecycle from filed to closed.

## Submitting a change

- Read `RELEASE-SAFETY-CHECKLIST.md` section 1 (pre-commit checks) before
  opening a PR -- ASCII purity, parse check, PSScriptAnalyzer, and the
  Pester suite are all required and are what CI checks.
- This project is pure ASCII (`TeknoParrot-Manager.ps1` specifically) --
  see the "Key conventions" section of `CLAUDE.md` for why, and how to
  verify.
- Small, focused changes are easier to review and land faster than large
  ones bundling unrelated work.
- If your change affects documented behavior (menu wording, a prompt, a
  workflow), update the relevant docs in the same change -- see
  `RELEASE-SAFETY-CHECKLIST.md` section 3 for what "the docs" means here
  (it's more than just `README.md`).

## Release governance

This project follows the Jumpstile Release Standard -- see
`RELEASE-SAFETY-CHECKLIST.md` section 0 for the full release order, and
`CONSTITUTION.md` for the governing principle that technical readiness
(passing tests, passing certification) is evidence a release is *ready*,
not authorization to *publish* one. Only the repository owner (Release
Manager) makes that call.

## Questions

Open an issue, or check the [wiki](https://github.com/Jumpstile/teknoparrot-manager/wiki)
for setup and troubleshooting guidance.
