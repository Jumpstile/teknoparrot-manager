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

The authoritative arcade host is LaunchBox 14.0.0.0. Its API assembly is:

```text
C:\\Users\\EliSi\\LaunchBox\\Core\\Unbroken.LaunchBox.Plugins.dll
```

The assembly file/assembly version is `14.0.0.0` and its recorded SHA-256 is
`99342E74EE99AFA28060439E78C6C08EEFFC90F541FBBCC70AE942B8C4AA5944`. Build
against that exact file:

```powershell
dotnet build .\\src\\LaunchBoxPlugin\\Native\\TeknoParrotManager.LaunchBoxPlugin.csproj `
  -p:LaunchBoxRoot='C:\\Path\\To\\LaunchBox'
```

The project expects:

```text
<LaunchBoxRoot>\\Core\\Unbroken.LaunchBox.Plugins.dll
```

An explicit `-p:LaunchBoxApiAssemblyPath=...` can be used only for another
verified host path. The project fails closed when the assembly is absent; it
does not compile against a documentation, NuGet, or invented interface shim.
The historical 13.27 documentation evidence does not establish compatibility
with the actual 14.0 host; interface names must be checked by compilation and
runtime validation.

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
