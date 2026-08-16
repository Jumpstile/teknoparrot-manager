# Native LaunchBox / Big Box Phase 0 plugin

This is the isolated native plugin proof of concept for issue #242.

## Projects

- `Core`: host-independent contract, discovery, process, and validation code.
- `Core.Tests`: dependency-free executable self-test for contract failures,
  discovery ambiguity, missing/malformed results, process start failure,
  timeout, cancellation, and path spaces.
- `Native`: LaunchBox API-facing plugin source. It implements
  `ISystemMenuItemPlugin` and requests both LaunchBox Tools and Big Box System
  visibility. It intentionally requires the current host API assembly.

## Native build

The current LaunchBox API assembly is not installed in this environment. Once
a real LaunchBox installation is supplied, build with:

```powershell
dotnet build .\\src\\LaunchBoxPlugin\\Native\\TeknoParrotManager.LaunchBoxPlugin.csproj `
  -p:LaunchBoxRoot='C:\\Path\\To\\LaunchBox'
```

The project expects:

```text
<LaunchBoxRoot>\\Core\\Unbroken.LaunchBox.Plugins.dll
```

An explicit `-p:LaunchBoxApiAssemblyPath=...` can be used when the host uses a
different verified path. The project fails closed when the assembly is absent;
it does not compile against a locally invented interface shim.

## Deployment

After a successful host build, copy the plugin DLL to the regular
`LaunchBox\\Plugins` folder. Big Box theme-specific deployment belongs under
`LaunchBox\\LBThemes\\<Theme Name>\\Plugins` only when the plugin is packaged
as a theme-specific plugin. Restart LaunchBox/Big Box after changing plugin
files.

The plugin reads an optional, user-authored
`TeknoParrotManager.LaunchBoxPlugin.json` beside the plugin DLL:

```json
{
  "tpmScriptPath": "C:\\Path With Spaces\\TeknoParrot-Manager.ps1",
  "teknoParrotRoot": "C:\\Path With Spaces\\TeknoParrot"
}
```

It never writes this file. Missing or ambiguous discovery is displayed rather
than guessed.
