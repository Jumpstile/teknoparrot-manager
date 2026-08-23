# TeknoParrot Manager Product Evolution Roadmap

## Purpose and status

This is the canonical product evolution roadmap for TeknoParrot Manager (TPM).
It records the intended post-1.0 sequence, architectural constraints, and
product boundaries. It is a planning record, not an implementation
specification or a release commitment.

The sequence is deliberate:

TPM 1.0 completion
-> modularization-first foundations
-> human-first GUI platform
-> Configuration Intelligence Platform (CIP)
-> EPIC Hardware Intelligence Platform (HIP) consumption
-> deterministic configuration profiles
-> compatibility intelligence
-> recovery and knowledge systems
-> safe automation

The roadmap follows the rule:

> Build the platform foundations first. Add intelligence second. Add automation last.

No item in this document authorizes product code, UI implementation, tests,
issue creation or updates, updater work, release-package changes, or an RC7
or Version 1.0 scope change.

## TPM 1.0 completion boundary

The current commitment is to complete and support the existing TPM 1.0 release
path. v1.0 RC7 is the current published release; v1.0 RC6 is the previous
published release (historical), and final Version 1.0 remains unpublished.
Release safety,
certification, and any remaining work required for the existing feature set
take precedence over every phase in this document.

TPM 1.0 is the boundary between the current product and the post-1.0
evolution roadmap. No post-1.0 capability should enter implementation until:

1. The RC7 stabilization, validation, and release-safety path is complete.
2. The TPM 1.0 release decision is explicitly authorized.
3. The current baseline is recorded so future work can be compared against a
   known release state.
4. A future phase has a separately authorized scope, ownership boundary,
   acceptance criteria, and review path.


This boundary does not redefine the RC7 release criteria and does not authorize
new features during the active freeze.

## Version 1.0 backlog before final release

The following item remains an explicit pre-1.0 backlog item and is not complete:

- [#59 -- Rebind controls](https://github.com/Jumpstile/teknoparrot-manager/issues/59)
  remains open and is tracked for Version 1.0. It should be implemented as soon
  as practical before the final Version 1.0 release, subject to separately
  authorized scope, implementation, and validation evidence. The roadmap does
  not claim #59 is complete.

## Product evolution principles

### Foundations before intelligence

Modular boundaries, a stable user experience, evidence, ownership, and
recovery must exist before TPM takes on intelligence or automation.

### Integrate before rebuild

TPM should consume authoritative capabilities from TeknoParrot, emulators,
HIP, and other approved providers where they already own the relevant
knowledge. TPM should aggregate and explain that knowledge without becoming a
second emulator, hardware database, player, runtime service, or provider
replacement.

### Detect, classify, own, approve, verify

Future workflows follow this lifecycle:

1. Detect the observed state.
2. Classify the observation.
3. Determine the authoritative owner.
4. Explain the evidence, confidence, impact, and risk.
5. Request approval when required.
6. Modify only explicitly owned state.
7. Verify the effective result.
8. Record evidence and recovery information.

Unknown, unsupported, ambiguous, stale, or conflicting states fail closed.

### Local-first and explainable

The installed TPM runtime remains local-first, deterministic, and explainable.
Development-side research and external knowledge maintenance remain separate
from runtime behavior. TPM must not silently crawl sources, rewrite itself, or
invent a configuration value from missing evidence.

## Phase 1 -- Modularization-first foundations

This phase establishes logical boundaries before significant new capability is
added. Physical file or process separation is justified only after the
contracts and ownership boundaries are understood.

The target logical areas are:

- Configuration and persistence.
- Environment discovery and detection.
- Hardware capability adapters.
- Emulator and runtime contracts.
- Configuration profiles and policy evaluation.
- Validation and evidence.
- Recovery and transaction handling.
- User interface and presentation.
- External provider and HIP adapters.

Each boundary must eventually define its owner, inputs, outputs, dependencies,
failure states, and verification responsibilities. Shared behavior belongs
behind stable contracts rather than being reimplemented at each call site.

Modularization is not permission to rewrite the product during the RC7-era
completion path. The work begins only after the TPM 1.0 completion boundary and
is staged so every intermediate state remains understandable and recoverable.

## Phase 2 -- Human-first GUI platform

TPM needs a proper GUI platform after its logical foundations are established.
The platform decision remains open; this roadmap does not select a framework,
hosting model, layout system, or implementation technology.

The GUI must implement the approved Human-First Explainable Automation UI
Contract.

### LaunchBox and Big Box native plugin track

A native LaunchBox / Big Box plugin is a desired post-1.0 front-end
integration direction. It must keep TPM core as the source of truth rather than
reimplementing profile, compatibility, backup, transaction, or verification
logic in the plugin.

PR #245 is Phase 0 feasibility evidence only. It is not a merge-ready
implementation and must not be merged as-is. Any future implementation starts
only after the Version 1.0 boundary and after revalidation against current
`main`.

The intended architecture is:

```text
LaunchBox / Big Box plugin
        -> versioned JSON request/result contract
        -> explicit non-interactive TPM entry point
        -> existing TPM logic
```

Read-only health and status workflows come first. Write-capable or per-game
actions require separate ownership definition, backup, preview, explicit
approval, and effective-result verification before they can be implemented.
The plugin must not bypass those gates or silently mutate LaunchBox, Big Box,
TeknoParrot, or TPM-owned state.

This roadmap entry is planning guidance only. It does not authorize merging
PR #245, changing RC7 or final Version 1.0 scope, changing a package or tag,
publishing a release, or publishing wiki changes.

### Glanceable first

The default view must let a user answer at a glance:

1. What TPM is doing right now.
2. Why TPM is doing it.
3. What TPM will do next.
4. Who owns the decision or state.
5. Whether TPM needs the user's action.

The default view is not a log viewer. Raw diagnostics, repetitive events,
implementation terms, confidence numbers, and evidence dumps must not obscure
the current state. Technical details remain available when they help review a
decision, but they do not overwhelm the normal user experience.

The default state exposes, in plain language:

- current status;
- the named active operation, or that nothing is running;
- the short reason;
- the next action, or that no action is needed;
- the state owner; and
- material risk and recovery availability.

A status must never imply success before effective-result verification. Missing,
stale, conflicting, or unsupported evidence must be shown as an investigation
state rather than a confident fix.

### Progressive disclosure

Information is layered:

| Layer | Required content |
|---|---|
| Default | Current state, current operation, reason, next action, owner, and material risk. |
| Explain | Observed facts, evidence summary, confidence explanation, ownership boundary, and expected result. |
| Inspect | Exact sources, paths, versions, contract or ruleset revisions, timestamps, attempted changes, verification details, rollback information, and raw diagnostics when needed. |

Deeper layers explain the current state; they do not replace the glanceable
view. Numeric scores, internal identifiers, raw exceptions, and
implementation-specific details belong in the explain or inspect layers unless
they are the immediate user action.

### Visible automation

Automation is visible before, during, and after any operation that can affect
user state:

- Before: show the proposed action, target, reason, owner, expected result,
  approval requirement, and material risk.
- During: show the named operation, current step, meaningful progress or an
  honest indeterminate state, and whether user intervention is required. A
  generic spinner is not sufficient.
- After: show the verified outcome as Applied, Not applied, Failed, Rolled
  back, or Needs attention, with the next step and remaining risk.

No background automation may be presented as unexplained magic. Visibility does
not grant permission; ownership, approval, mutation, backup, and verification
gates still apply.

### Ownership transparency

Every recommendation and automated action identifies the authority that owns
the relevant state:

| Ownership | User-facing meaning |
|---|---|
| TPM-owned | TPM may propose or apply a bounded change after the applicable gates. |
| Emulator or runtime-owned | TPM may explain and verify; the authoritative owner performs initialization or mutation. |
| User-owned | TPM preserves the state and requests explicit approval before a supported change. |
| Provider or HIP-owned | TPM consumes the authoritative, versioned result and does not silently amend it. |
| Unknown or unsupported | TPM reports the unresolved boundary and does not guess or mutate. |

The GUI must distinguish "TPM recommends this" from "TPM can safely apply
this" and from "this must be changed in the owning system."

### Evidence, confidence, and risk

Recommendations and health states expose:

- the short evidence summary;
- source, freshness, and applicable contract or ruleset revision;
- what is known, unknown, conflicting, or not applicable;
- confidence in plain language before numeric detail;
- expected benefit, cost, and maintenance impact;
- what may change and who owns it;
- expected disruption and whether backup or rollback exists; and
- the consequence of declining or postponing the action.

Confidence describes evidence strength. It never authorizes a forbidden
mutation, overrides ownership, or replaces required approval. Risks that could
change the user's choice remain visible in the default or approval view.

## Phase 3 -- Configuration Intelligence Platform (CIP)

CIP is the environment-intelligence foundation for TPM. It gives TPM a
structured, evidence-backed understanding of the cabinet without taking
ownership of every system it observes.

The first CIP capability is read-only inventory and Cabinet Health reporting.
Candidate observations include:

- CPU, GPU, memory, storage, and operating-system identity;
- display topology, resolution, routing, and audio devices;
- wheels, pedals, light guns, joysticks, buttons, trackballs, spinners, and
  encoders through approved capability boundaries;
- TeknoParrot, emulator, runtime, dependency, and required-component versions;
  and
- installed roots, required folders, permissions, and broken-path signals.

The user-facing result uses explicit states such as Ready, Attention required,
Investigation required, Unsupported, and Not applicable. An absence of evidence
must not become a confident recommendation.

CIP health and recommendation results retain the observed facts, sources,
timestamps, versions, applicable ruleset, ownership decision, confidence,
expected benefit, cost, maintenance impact, and unresolved risk. The same
evidence must produce the same result for the same ruleset.

### Arcade light-gun controller calibration and validation

[#273 -- Plan full lightgun calibration and validation workflow](https://github.com/Jumpstile/teknoparrot-manager/issues/273)
tracks post-1.0 design for a full arcade light-gun controller calibration and
validation workflow. It depends on the CIP evidence model because it must
separate physical/device evidence, device software readiness, TeknoParrot
profile capability, UserProfile binding state, direct TeknoParrot launch,
frontend launch behavior, game/operator-menu calibration, and actual in-game
verification.

The first acceptable slice is read-only evidence and guided user instruction:
TPM may identify likely shooter profiles, inspect current input API and binding
state, explain ownership boundaries, compare direct TeknoParrot launch against
frontend launch where the user tests both, and record sanitized evidence. TPM
must not claim calibration from launch success or crosshair presence alone.

Write-capable correction is later work. It requires a separately approved
ownership contract, preview, backup, explicit approval, containment checks, and
effective-result verification. TPM must not automatically change Windows mouse
settings, display scaling, device drivers, firmware, third-party device
software, or TeknoParrot profiles based on generic advice or community-reported
settings.

## Phase 4 -- EPIC Hardware Intelligence Platform (HIP)

TPM should consume HIP as the authoritative hardware capability source rather
than creating a second hardware intelligence database.

HIP integration should provide versioned, provenance-bearing capabilities for
controllers and cabinet hardware, including controller mapping where that
authority exists. TPM presents those capabilities in its own context and
applies only TPM-owned configuration.

A cabinet profile may describe detected controls, displays, GPU identity, and
supported capability classes. It is an evidence view, not permission to change
firmware, drivers, licenses, calibration, or other hardware-owned state.
Hardware-sensitive claims remain evidence-assisted until separately authorized
validation establishes otherwise.

### Post-1.0 cabinet-control design anchor

[#267 -- Post-1.0 cabinet control inventory, visual guides, and LEDBlinky
export](https://github.com/Jumpstile/teknoparrot-manager/issues/267) remains a
post-1.0 design/research item. Any LEDBlinky integration depends on identity
mapping research and front-end-specific behavior across the supported browsing
and launch ecosystems. It is not RC7 or final Version 1.0 release scope.

## Phase 5 -- Deterministic configuration profiles

Profiles relate the observed environment to a supported game and its
emulator/runtime contract:

- Game.
- Hardware capability.
- Display.
- Input.
- Emulator or runtime contract.

Profile evaluation is deterministic and reviewable. A supported profile may
show observed facts, expected benefit, confidence, affected state, and recovery
path. The normal progression is:

1. Observe the current state.
2. Report drift or an unsupported condition.
3. Recommend a bounded profile.
4. Prepare a reviewable change plan.
5. Apply only after the required approval.
6. Verify the effective result.

Applying a profile is permitted only for contract-declared TPM-owned state.
Emulator, runtime, user, hardware, provider, and HIP-owned settings remain
verify-only unless their authoritative owner provides an approved mutation
path.

## Phase 6 -- Compatibility intelligence

Compatibility intelligence may consume a reviewed knowledge base, while the
shipped runtime remains local-first.

Evidence is considered in an explicit authority order:

1. Official TeknoParrot information.
2. Emulator maintainer information.
3. Verified community data.
4. User-submitted evidence.
5. Anonymous opt-in telemetry only if separately authorized, minimized, and
   governed.

Every recommendation exposes evidence, provenance, freshness, confidence, and
unresolved limitations. A low-confidence or unknown result is an
investigation state, not a reason to guess.

Development-side upstream monitoring remains separate from the installed
runtime. The runtime does not crawl sources, install findings, rewrite its own
code, or silently mutate configuration based on external research.

## Phase 7 -- Recovery and knowledge systems

Recovery is a prerequisite for meaningful automation. Every approved
TPM-owned change is designed as a recoverable transaction:

1. Back up the current state.
2. Create a recovery point.
3. Apply the owned change.
4. Verify the effective result.
5. Commit the evidence record.
6. Restore the last known-good state if application or verification fails.

The workflow must not blindly overwrite unknown files, destroy unrelated user
state, or claim success from an exit code alone.

Knowledge systems preserve explainable history, not autonomous authority. A
record may contain:

- observed facts and their sources;
- installed versions, contract and ruleset revisions, and timestamps;
- ownership and authority decisions;
- confidence and applicability;
- user approval and preference where relevant;
- exact changes attempted and verification result;
- rollback location; and
- unresolved risks and follow-up evidence needs.

Knowledge records are provenance-bearing and deterministic. They do not permit
TPM to rewrite its own code, invent facts, bypass an ownership boundary, or
treat stale evidence as current.

## Post-1.0 / 1.1 -- Complex-game workflows, sessions, and readiness

The product input recorded in issues #279, #280, and #281 points to a
post-1.0 gap beyond ordinary single-game setup: users want safe, reproducible
support for complex workflows, ready-made profile inputs, emulator coverage,
and clearer evidence of what is actually ready. The following issue-backed
work is a planning group for that gap. It is not an RC8 scope expansion.

### Workflow and environment foundations

- [#282 Workflow Profiles for Complex Games](https://github.com/Jumpstile/teknoparrot-manager/issues/282)
  defines declarative, deterministic workflows for prerequisites, ordered
  processes, placement, recovery, and post-launch verification.
- [#284 Environment Orchestration Framework](https://github.com/Jumpstile/teknoparrot-manager/issues/284)
  provides reusable process, window, monitor, launch-order, and optional audio
  coordination without emulator-specific hardcoding.
- [#288 Complex Game Readiness Reports](https://github.com/Jumpstile/teknoparrot-manager/issues/288)
  turns observed results into evidence-based reports with satisfied and
  missing prerequisites, manual actions, confidence, evidence, and the next
  safe action.

### Game-specific and session workflows

- [#285 The Key of Avalon Guided Setup](https://github.com/Jumpstile/teknoparrot-manager/issues/285)
  depends on #282 and uses the orchestration/reporting foundations for all
  supported revisions, server/client setup, prerequisite validation, monitor
  guidance, controller guidance, and readiness evidence. It must not modify
  Dolphin or TeknoParrot.
- [#283 Network Session Manager](https://github.com/Jumpstile/teknoparrot-manager/issues/283)
  defines roles, host/client workflows, readiness validation, launch
  orchestration, and diagnostics for LAN and user-owned remote sessions.
- [#286 LAN Session Validation and Diagnostics](https://github.com/Jumpstile/teknoparrot-manager/issues/286)
  is the validation child of #283 for revisions, emulator/plugin versions,
  required files, ports, firewall state, cabinet IDs, peer connectivity, and
  evidence-based readiness.
- [#287 Remote Session Support via User-Owned Networks](https://github.com/Jumpstile/teknoparrot-manager/issues/287)
  is the user-owned-network child of #283 for Tailscale, ZeroTier, and
  WireGuard. Matchmaking, relay servers, and hosted networking services are
  explicitly excluded.

### Planning relationships and boundaries

- #279 remains the safe, approval-gated UserProfiles preset-pack track; an
  imported profile is a candidate, not authoritative state, and controls are
  never marked Verified without bounded evidence.
- #280 remains the prebuild-parity analysis track, translating known-good
  profiles, frontend expectations, emulator coverage, control presets, media,
  and reduced first-run decisions into safe TPM-managed capabilities.
- #281 remains the post-1.0 PCSX2x6 investigation track, including .acgame,
  arcade BIOS, and System 246/System 256 considerations.
- #200 broad automatic device/context-aware control mapping remains deferred;
  this roadmap group must not use workflow or profile language to bypass that
  boundary.
- All seven issues are assigned to the Post-1.0 / 1.1 milestone. None is part
  of RC8. Any future implementation still requires an authorized design,
  ownership contract, explicit approval policy, backup/rollback, redaction,
  effective-result verification, and fail-closed behavior.

## Phase 8 -- Safe automation

Safe automation is the final adoption phase because it depends on the GUI,
modular contracts, CIP evidence, HIP authority, profiles, compatibility
provenance, and recovery systems.

Automation levels are assigned per action:

| Level | Meaning |
|---|---|
| 0 | Observe only. No recommendation or write. |
| 1 | Recommend. Explain evidence, confidence, impact, cost, and risk. |
| 2 | Prepare a reviewable plan and recovery point; do not apply. |
| 3 | Apply after approval using only the approved, contract-bounded plan. |
| 4 | Fully automatic only for repeatable, reversible, TPM-owned safe operations with a proven contract. |

The level is not assigned to an entire subsystem. A subsystem may observe a
hardware condition while remaining forbidden to mutate it.

No operation reaches an automatic level unless the ownership contract,
evidence semantics, approval policy, backup and rollback behavior, containment
checks, and post-action verification are already established. Unknown,
ambiguous, stale, conflicting, or out-of-contract conditions stop the affected
action and explain why.

## Preconditions for any implementation

Before a phase leaves roadmap status, its separately authorized design must
establish:

1. The authoritative provider, emulator, HIP, or local evidence source.
2. Version-pinned ownership and capability contracts.
3. Explicit unknown, unsupported, conflicting, and not-applicable semantics.
4. Backup, rollback, containment, and effective-result verification.
5. Security, privacy, licensing, and creator-rights boundaries.
6. A glanceable, explainable user experience that keeps technical detail
   available without making it the default.
7. Independent review and release certification appropriate to the change.

## Explicit non-goals and current boundaries

This roadmap does not authorize:

- product-code, UI implementation, schema, menu, configuration, or test changes;
- issue creation, issue updates, or tracker churn;
- updater expansion or updater implementation;
- RC7 scope changes or release-package changes;
- silent writes to emulator, runtime, user, hardware, provider, or HIP-owned
  state;
- firmware, driver, licensing, calibration, third-party device-software, or
  Windows-global input/display changes; or
- autonomous runtime internet research, self-modifying compatibility logic, or
  ungoverned telemetry.

The canonical roadmap may evolve after TPM 1.0 through separately authorized
architecture and product decisions. Until then, it is a record of direction
only.
