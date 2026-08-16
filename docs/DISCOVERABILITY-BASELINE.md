# Discoverability and Canonical Identity Audit

This is the evidence record for issue #238. It is an audit artifact, not
current-release installation guidance. The source-controlled contract is
`.github/repository-metadata.json`; live GitHub repository settings must be
checked against it during release preparation and after publication under
`RELEASE-SAFETY-CHECKLIST.md` and issue #237.

## Baseline: 2026-08-16, before #238

### Repository and GitHub state

- Repository: `Jumpstile/teknoparrot-manager`
- Visibility: public (`private: false`, `visibility: public`)
- Default branch: `main`
- Verified live `main` commit: `addcfe303cd8027d953382b59c7e2f95d7ae098e`
- Unauthenticated repository page: HTTP 200, with the public repository marker.
- Unauthenticated Releases page: HTTP 200, with the public page marker.
- Open pull requests at the baseline check: none returned by the GitHub REST
  `/pulls?state=open` endpoint. The in-progress #42/#196 work was not touched.

### Stale live metadata

The live GitHub repository API returned:

- Description: `TeknoParrot Manager v1.0 RC3 -- Windows PowerShell arcade-library manager for TeknoParrot: game registration, controls, lightgun crosshairs, compatibility fixes, LaunchBox, and HyperSpin. Personal/non-commercial.`
- Homepage: `https://github.com/Jumpstile/teknoparrot-manager/releases/tag/v1.0-RC3`
- Topics: `arcade-emulation`, `arcade-game-library`, `crosshairs`,
  `game-library-manager`, `hyperspin`, `launchbox`, `powershell`,
  `teknoparrot`, `teknoparrot-manager`, `windows`

The repository page also exposed the RC3 description in its unauthenticated
page metadata. This is stale version-specific identity, not a search-ranking
claim.

### GitHub and web-search baseline

- GitHub repository search for `TeknoParrot Manager` returned
  `Jumpstile/teknoparrot-manager` as the canonical repository.
- GitHub repository search for `teknoparrot-manager` returned the same
  canonical repository.
- Direct Google and Bing query pages for both `"TeknoParrot Manager"` and
  `teknoparrot-manager` returned HTTP 200. A raw-page probe did not find the
  literal canonical repository URL in those responses; this is an
  environment-specific evidence point, not proof that no result was rendered.
- The available general search result for the exact product name returned the
  LaunchBox beta/testing thread before the canonical GitHub repository. The
  thread already links to the GitHub repository, issue tracker, and Releases
  page.

Search-engine indexing and ranking are asynchronous observations. They are
not a synchronous release gate and no Google or Bing ranking guarantee is
claimed.

## #238 implementation contract

- `.github/repository-metadata.json` is the reviewable, version-agnostic
  description/homepage/topic contract.
- `Tests/QualitySystem.Tests.ps1` validates the contract, the supported topic
  set, and the README's canonical top-of-page identity and links.
- `RELEASE-SAFETY-CHECKLIST.md` requires a live GitHub metadata comparison
  before tagging and after publication, which is the #237 integration point.
- No runtime or product code is changed by this task.

## External reference follow-up (not posted)

The LaunchBox thread is a legitimate, user-controlled reference and already
points readers to the canonical repository and Releases page. If its opening
text is refreshed, use this exact concise update rather than adding a backlink:

> TeknoParrot Manager is a Windows PowerShell tool for managing TeknoParrot
> arcade libraries, including game registration, controls, lightgun crosshairs,
> ReShade/dgVoodoo2 compatibility setup, and LaunchBox or HyperSpin exports.
> Canonical project: https://github.com/Jumpstile/teknoparrot-manager
> Current downloads: https://github.com/Jumpstile/teknoparrot-manager/releases

No external post or artificial backlink was created by this task.

## Post-change verification: 2026-08-16T18:07:32.7064978Z

The live settings were reconciled after the source-side implementation reached
`main`. The verification used exact main commit
`3e8e5ce0730a6b10f1e7308d00bf8ea1f22015f6` and the contract committed at that
SHA.

### Live repository state

- Description exactly matches the contract: `TeknoParrot Manager - Windows PowerShell tool for managing TeknoParrot arcade libraries, controls, crosshairs, compatibility fixes, LaunchBox, and HyperSpin.`
- Homepage exactly matches the contract:
  `https://github.com/Jumpstile/teknoparrot-manager/releases`
- Topics exactly match the contract as a normalized set (the GitHub API may
  return them in a different order): `arcade`, `arcade-game-library`,
  `arcade-games`, `crosshair`, `dgvoodoo2`, `game-manager`, `hyperspin`,
  `launchbox`, `lightgun`, `powershell`, `reshade`, `teknoparrot`,
  `teknoparrot-manager`, `windows`
- Visibility remains public: `private: false`, `visibility: public`.
- Unauthenticated repository page: HTTP 200.
- Unauthenticated Releases page: HTTP 200.

### GitHub repository search

- Query `TeknoParrot Manager`: canonical match found for
  `Jumpstile/teknoparrot-manager`; 3 total repository results were returned.
- Query `teknoparrot-manager`: canonical match found for
  `Jumpstile/teknoparrot-manager`; 2 total repository results were returned.

The description, homepage, topic set, public state, page accessibility, and
GitHub-search checks all passed at this timestamp. Google/Bing indexing and
ranking remain asynchronous observations; repeat the web-search observation
after indexing time has elapsed, and do not treat a delayed result as a code
failure or claim a ranking guarantee.
