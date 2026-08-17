# LaunchBox / Big Box Phase 0 feasibility spike

Issue: #242

This directory records the isolated Phase 0 proof of concept for a native
LaunchBox / Big Box plugin. The plugin is a presentation and orchestration
layer only. TeknoParrot Manager remains the source of truth for health-check
logic and future TPM operations.

## Documentation evidence versus host evidence

- The documentation investigation originally used the official LaunchBox
  changelog identifying Version 13.27 as the current released version at the
  time of the spike (released May 12, 2026). That is documentation evidence,
  not the installed host version:
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
  `Unbroken.LaunchBox.Plugins.dll` version `13.5.0.0`. This is a documentation
  artifact and must not be substituted for the installed host assembly. The
  official documentation also still mentions `LaunchBox\\Metadata`; the
  official path-change notice moved the assembly to `LaunchBox\\Core`:
  https://forums.launchbox-app.com/topic/57046-path-change-of-unbrokenlaunchboxpluginsdll/

## Actual arcade host evidence

The authoritative host for issue #244 validation is the installed arcade
environment, not the historical 13.27 documentation snapshot:

- LaunchBox: `C:\\Users\\EliSi\\LaunchBox\\Core\\LaunchBox.exe`, version
  `14.0.0.0`.
- Big Box: `C:\\Users\\EliSi\\LaunchBox\\Core\\BigBox.exe`, version `14.0.0.0`.
- API assembly: `C:\\Users\\EliSi\\LaunchBox\\Core\\Unbroken.LaunchBox.Plugins.dll`.
- API file and assembly version: `14.0.0.0`.
- API SHA-256:
  `99342E74EE99AFA28060439E78C6C08EEFFC90F541FBBCC70AE942B8C4AA5944`.
- Regular plugin directory: `C:\\Users\\EliSi\\LaunchBox\\Plugins`.

No LaunchBox 13.27 installation is required or should be installed for this
validation. Interface names appearing in documentation are not treated as
proof of binary compatibility; the exact 14.0 assembly must be compiled
against and inspected before installation.

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
- The real host/API assembly is now available, but native host validation has
  not yet started: this machine has the .NET 9 runtime but no .NET SDK or
  MSBuild compiler, so the required 14.0 API build cannot run. The project
  continues to fail closed until the exact host assembly can be compiled
  against.
- Issue #244 is therefore blocked on compiler availability, not on obtaining
  LaunchBox 13.27. Do not infer API compatibility from unchanged interface
  names alone.

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
