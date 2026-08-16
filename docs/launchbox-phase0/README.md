# LaunchBox / Big Box Phase 0 feasibility spike

Issue: #242

This directory records the isolated Phase 0 proof of concept for a native
LaunchBox / Big Box plugin. The plugin is a presentation and orchestration
layer only. TeknoParrot Manager remains the source of truth for health-check
logic and future TPM operations.

## Verified host facts

- The current official LaunchBox changelog identifies Version 13.27 as the
  current released version for this investigation (released May 12, 2026):
  https://www.launchbox-app.com/about/changelog
- LaunchBox 13.19 moved the host runtime to .NET 9.0. The native project
  therefore targets `net9.0-windows`, subject to validation against the exact
  LaunchBox installation that will host it:
  https://forums.launchbox-app.com/topic/89418-launchbox-1319-crashing-on-launch-read-this-first/
- Regular plugins are deployed under `LaunchBox\\Plugins`; theme-specific
  plugins use `LaunchBox\\LBThemes\\<Theme Name>\\Plugins`. LaunchBox must be
  restarted after plugin changes:
  https://feedback.launchbox-app.com/en/help/articles/8696961-theme-specific-plugins-and-custom-controls
- The official API documentation defines `ISystemMenuItemPlugin` for the
  LaunchBox Tools menu and Big Box System menu, and `IGameMenuItemPlugin` for
  the LaunchBox right-click menu and Big Box game-details menu:
  https://pluginapi.launchbox-app.com/html/da279d8a-0876-d129-af62-802c559286b6.htm
  https://pluginapi.launchbox-app.com/html/e618f692-8f22-8c58-5a03-7ccc2d8ef31c.htm
- The official API documentation exposes `PluginHelper.DataManager` and
  read/write game, platform, emulator, reload, and save operations. Phase 0
  uses none of the write or save operations:
  https://pluginapi.launchbox-app.com/html/aa57942f-403e-6c11-bfe5-2465f667c66c.htm
- The API documentation pages identify the documentation assembly as
  `Unbroken.LaunchBox.Plugins.dll` version `13.5.0.0`. No LaunchBox installation
  or current API DLL is present in this development environment, so the exact
  13.27 assembly version remains unverified. The official documentation also
  still mentions `LaunchBox\\Metadata`; the official path-change notice moved
  the assembly to `LaunchBox\\Core`, which is the path used by the native
  project and must be checked against the supplied host installation:
  https://forums.launchbox-app.com/topic/57046-path-change-of-unbrokenlaunchboxpluginsdll/

## POC state

- Native global menu source is implemented through `ISystemMenuItemPlugin`.
  It requests both LaunchBox Tools and Big Box System visibility.
- The plugin runs the explicit `-FrontendContractRequestPath` /
  `-FrontendContractResultPath` TPM entry point with `-NoProfile` and
  `-NonInteractive`, validates the result, applies a 60-second timeout, and
  provides a Cancel button.
- The TPM side reuses `Invoke-LibraryHealthCheck`; it does not duplicate
  matching, registration, backup, transaction, controls, ReShade, dgVoodoo2,
  or compatibility logic.
- The selected-game menu is deferred. The LaunchBox API surface is simple,
  but TPM does not yet have a selected-profile diagnostics seam that can be
  proven read-only without guessing how LaunchBox's `ApplicationPath` maps to
  the active TPM install.
- No LaunchBox or Big Box runtime smoke test was possible in this environment.
  The native project intentionally fails closed until the host API assembly is
  supplied.
- The immediately justified host-validation follow-up is tracked in #244 and
  is blocked until a real LaunchBox 13.27 installation/API assembly is
  available.

## Repository placement recommendation

Keep the contract adapter, schema, investigation, and Phase 0 evidence in
this repository because they are TPM-core integration artifacts and must be
reviewed with TPM's no-write guarantees. Put a production distributable
plugin in a separate `TeknoParrot-Manager-LaunchBox-Plugin` repository after
the host-assembly smoke test.

The separate repository would isolate LaunchBox's .NET 9 and API assembly
compatibility, plugin packaging, and host-specific release cadence. Keeping
the Phase 0 source here makes the contract seam auditable and avoids creating
a second TPM implementation or a new repository before the host facts are
confirmed.

## Run the POC adapter directly

Create a request JSON file and an isolated result directory, then run:

```powershell
powershell.exe -NoProfile -NonInteractive -File .\\TeknoParrot-Manager.ps1 `
  -FrontendContractRequestPath .\\request.json `
  -FrontendContractResultPath .\\result.json `
  -FrontendContractCorrelationId <request-correlation-guid>
```

The request contains only `contractVersion`, `operationId`,
`correlationId`, and explicit read-only `paths`. The result contains the
version, operation, correlation ID, status, success/cancelled flags, stable
error code, summary, warnings, numeric health evidence, and sanitized
technical evidence. The result path must be an isolated caller-owned temp
path; it must not be inside the TeknoParrot root or UserProfiles directory.
