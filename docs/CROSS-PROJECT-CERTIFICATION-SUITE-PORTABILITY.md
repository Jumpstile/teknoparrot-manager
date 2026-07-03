# Cross-Project Certification Suite Portability

The TPM Certification Suite should be designed so its core ideas can be reused by other Jumpstile projects, including ChannelForge.

## Goal

Build the suite as a reusable certification pattern, not a one-off TeknoParrot-only harness.

Each project should be able to define its own adapters, datasets, and gates while sharing the same quality philosophy:

- do the human tester's job faster and more consistently,
- perform computer-scale testing humans cannot realistically do,
- produce certification evidence before release,
- preserve every real bug as permanent regression knowledge.

## Portable core concepts

These concepts should be project-agnostic:

- Certification levels: Development, Beta, Release Candidate, Gold.
- Certification scorecard.
- Regression register.
- Golden datasets.
- Human-use simulation scenarios.
- Adversarial testing plan.
- Fuzz testing.
- Mutation testing.
- Chaos testing.
- Performance and scale tracking.
- Structured logs and per-run artifact folders.
- Release-readiness gates.

## Project-specific adapters

Each project should provide adapters for its own domain.

### TeknoParrot Manager examples

- TeknoParrot root discovery.
- GameProfiles/UserProfiles validation.
- Crosshair placement validation.
- Auto-update validation.
- LaunchBox/HyperSpin export validation.

### ChannelForge examples

- Provider playlist validation.
- M3U parsing and normalization.
- EPG/XMLTV parsing and matching.
- Channel rename and alias-drift detection.
- Lineup-diff validation.
- Dispatcharr/IPTVBoss output validation.
- Safe rollback of generated output.
- Large playlist performance testing.
- Human-use simulation for normal setup, update, provider refresh, and troubleshooting workflows.

## Suggested reusable folder model

Future projects should be able to adopt a structure like:

```text
certification/
  project.config.json
  suites/
  adapters/
  reports/
  testdata/
    golden-*.json
    human-use-*.json
    fuzz-*.json
  docs/
    CERTIFICATION-SUITE.md
    REGRESSION-REGISTER.md
```

TPM can keep its current paths for now, but new code should avoid hardcoding TeknoParrot-only assumptions into reusable concepts.

## Design rules

1. Keep project-agnostic logic separate from project-specific checks.
2. Put domain assumptions in adapters or config.
3. Use machine-readable datasets wherever possible.
4. Keep reports consistent across projects.
5. Every project should have a certification scorecard.
6. Every project should have a regression register.
7. Every project should include human-use simulation, not only technical tests.
8. Every project should support scale, fuzz, and chaos testing over time.
9. A non-obvious implementation constraint in the certification suite
   itself (non-obvious, easy to "simplify" incorrectly, and proven by a
   real incident or regression -- not a routine implementation detail) is
   documented in both the relevant architecture document and
   `LESSONS_LEARNED.md` (see `CONSTITUTION.md`, "Documenting non-obvious
   implementation constraints"). A single-project test run passing is not
   sufficient evidence that a portability-sensitive refactor is safe;
   verify against the full test suite before treating such a change as
   validated.

## ChannelForge future certification lanes

When ChannelForge resumes, its certification suite should include:

- Regression Suite
- Human-Use Simulation
- Playlist Validation
- EPG Validation
- Channel Mapping Validation
- Alias Drift Detection
- Provider Change Detection
- Output Safety / Rollback
- Large Playlist Performance
- Fuzzed M3U/XMLTV Inputs
- Chaos Tests for Missing/Corrupt Providers
- Release Certification Scorecard

## Standing decision

Do not let TPM Certification Suite become a dead-end one-project tool. Treat it as the first implementation of a broader Jumpstile certification pattern that ChannelForge and future projects can reuse.
