# Adversarial Testing Plan

This plan moves the TPM tester beyond normal regression testing toward an automated QA engine that is faster and broader than manual testing.

## Goal

The tester should not only prove that expected behavior works. It should actively try to break TPM in controlled, repeatable ways.

## Testing layers

### 1. Mutation testing

Intentionally alter small pieces of logic and verify that the test suite fails.

Examples:

- Remove a normalization rule.
- Invert a path-safety condition.
- Disable a backup-before-write guard.
- Weaken GitHub asset URL validation.
- Remove a ZIP traversal guard.
- Lower or raise a fuzzy-match threshold.

If a mutation survives, it means the tests did not detect a real class of bug.

### 2. Fuzz testing

Generate large numbers of synthetic inputs and verify invariants.

Initial targets:

- folder names
- DAT names
- profile names
- GitHub release asset names
- ZIP entry paths
- LaunchBox export paths
- HyperSpin export paths

### 3. Property-based tests

Instead of testing only examples, verify rules that should always hold.

Examples:

- Normalization is deterministic.
- Normalization is idempotent.
- Path validation never allows escape from the intended root.
- Backup path creation never points inside a source file.
- Update installation never overwrites before backup creation.
- Release asset selection never accepts non-GitHub-release URLs.

### 4. Synthetic library scale tests

Generate fake libraries at different sizes:

- 100 games
- 1,000 games
- 10,000 games
- 50,000 games

Track runtime, memory, file counts, and warnings.

### 5. Chaos tests

Inject controlled failures:

- network failures
- corrupt ZIP files
- locked files
- read-only files
- malformed XML
- missing GameProfiles
- missing UserProfiles
- partial downloads
- invalid JSON
- access denied errors

TPM should fail safely with clear logs and no partial destructive changes.

## Reporting

Adversarial tests should produce their own report section:

- mutations tried
- mutations killed
- mutations survived
- fuzz cases generated
- fuzz failures
- chaos scenarios passed
- performance thresholds

## Certification integration

A release should eventually require:

- all standard regression tests passing
- no known uncovered bugfixes
- no surviving critical mutations
- no high-severity fuzz failures
- no unsafe chaos-test failures
- no performance regression beyond an approved threshold

## First implementation targets

1. Add deterministic fuzz tests for normalization.
2. Add property tests for path validation.
3. Add mutation checks for the updater URL guard and backup-before-overwrite behavior.
4. Add synthetic library smoke generation for 100 and 1,000 fake games.
