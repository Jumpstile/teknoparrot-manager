# ADR-0242: Phase 0 LaunchBox / Big Box plugin boundary

Status: Accepted for the isolated feasibility spike

Date: 2026-08-16

Issue: #242

## Context

TeknoParrot Manager is a PowerShell-first application with existing
read-only health-check logic and existing direct LaunchBox data integration.
The Phase 0 question is whether a native LaunchBox / Big Box plugin can add a
usable frontend without creating a second TPM implementation or changing
LaunchBox, TeknoParrot, or game data.

The documentation investigation originally used official sources current to
LaunchBox 13.27 and an API documentation artifact identifying assembly version
13.5.0.0. Those are historical/documentation facts, not a substitute for a
host DLL. The actual arcade host is LaunchBox 14.0.0.0 with
`Core\\Unbroken.LaunchBox.Plugins.dll` version 14.0.0.0 and SHA-256
`99342E74EE99AFA28060439E78C6C08EEFFC90F541FBBCC70AE942B8C4AA5944`.
LaunchBox 14.0 is authoritative for host validation; no 13.27 installation
should be sought or installed. Interface-name continuity must not be treated
as binary compatibility until the exact 14.0 assembly builds successfully.

## Decision

Use this boundary:

```text
LaunchBox / Big Box menu
        |
        v
thin native C# plugin
        |
versioned JSON request/result contract v1
        |
explicit non-interactive TPM process entry point
        |
existing TPM read-only health-check logic
```

The Phase 0 operation is `library.health-check`. The TPM side accepts the
contract only when the caller supplies explicit paths, a supported version,
the expected operation, and a valid correlation ID. It writes only an
isolated result file and disables normal TPM logging for that process. The
native side validates every result before displaying it, rejects unknown
fields and mismatched correlations, and enforces timeout/cancellation.

The global menu source implements `ISystemMenuItemPlugin` and requests both
LaunchBox Tools and Big Box System visibility. The selected-game menu is
deferred until a selected-profile diagnostics seam can be proven read-only.
No LaunchBox DataManager write, reload, or save surface is used.

Keep the Phase 0 adapter, schema, inventories, and evidence in this
repository. Recommend a separate `TeknoParrot-Manager-LaunchBox-Plugin`
repository for the eventual distributable plugin after host assembly and
runtime validation. That split isolates LaunchBox compatibility and packaging
from TPM core releases while preserving one reviewed contract.

## Alternatives considered

1. Put all plugin behavior in the PowerShell script. Rejected: LaunchBox
   requires a managed plugin assembly and this would blur the frontend/core
   boundary.
2. Reimplement TPM health, matching, or configuration logic in C#. Rejected:
   it would create drift and violate the source-of-truth rule.
3. Scrape console output from the normal TPM entry point. Rejected: console
   text is not a stable integration contract and the normal entry point can
   load configuration or enter interactive behavior.
4. Create a separate repository immediately. Deferred: host-specific
   compatibility and packaging should remain outside TPM core until the actual
   LaunchBox 14.0 assembly has been compiled against and runtime-validated.

## Consequences

Positive:

- The first native surface is small, read-only, explainable, and testable.
- Existing TPM behavior remains the source of truth.
- Unsupported host/API facts fail closed instead of producing a guessed DLL.
- The contract can be shared if the plugin later moves repositories.

Costs and open risks:

- The native assembly must be built against the actual LaunchBox 14.0 host
  assembly; the historical 13.27 documentation evidence cannot satisfy this
  gate.
- The host-validation work is isolated in follow-up issue #244 and currently
  remains blocked because the arcade machine has no .NET SDK/MSBuild compiler.
- The plugin must resolve TPM paths from host context or explicit local
  settings; ambiguous discovery is surfaced to the user.
- The selected-game action needs a separate read-only TPM seam.
- A real host smoke test must verify LaunchBox and Big Box callback behavior,
  WPF threading, plugin loading, deployment folders, and the exact API version.
