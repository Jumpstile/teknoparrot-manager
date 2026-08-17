# Phase 0 specification inventory

This inventory records the external specifications and contracts that govern
the LaunchBox integration. It is intentionally limited to facts required by
the Phase 0 spike.

| ID | Governing specification | Evidence | Phase 0 use | Verification | Failure handling |
| --- | --- | --- | --- | --- | --- |
| LB-API-001 | `ISystemMenuItemPlugin` adds a non-game-specific item to LaunchBox Tools and/or Big Box System. | Official interface documentation | `TpmSystemMenuItem` requests both surfaces. | Native build and host smoke test once the host DLL is supplied. | Do not ship if assembly or host callback differs. |
| LB-API-002 | `IGameMenuItemPlugin` adds LaunchBox right-click and/or Big Box game-details items and exposes validity callbacks. | Official interface documentation | Records the deferred selected-game spike. | Add only after a read-only TPM selected-profile seam exists. | Keep the menu absent until the seam is proven. |
| LB-API-003 | `PluginHelper.DataManager` exposes reads and writes for games, platforms, emulators, reload, and save. | Official `IDataManager` documentation | No DataManager write, reload, or save is called. | Source scan and no-write snapshot. | Treat any write call as a Phase 0 blocker. |
| LB-API-004 | Regular plugin deployment is `LaunchBox\\Plugins`; theme-specific deployment is `LaunchBox\\LBThemes\\<Theme Name>\\Plugins`. | Current official LaunchBox help | Documents deployment and restart requirements. | Verify against a supplied 13.27 install. | Do not infer a different folder from an absent install. |
| LB-API-005 | LaunchBox 13.19 moved the host runtime to .NET 9.0. | Official LaunchBox staff notice | Native project targets `net9.0-windows`. | Build against the supplied host API assembly. | Do not target .NET 6 based on stale forum posts. |
| LB-API-006 | API documentation artifact reports `Unbroken.LaunchBox.Plugins.dll` version `13.5.0.0`; current 13.27 assembly is not locally available. | Official API pages plus official path-change notice | Records the exact evidence without claiming a current assembly version. | Inspect `Core\\Unbroken.LaunchBox.Plugins.dll` in a real install. | Hold host smoke test and publication. |
| TPM-CONTRACT-001 | Phase 0 contract version is `1.0`; operation is `library.health-check`. | `tpm-frontend-contract-v1.schema.json` | Both sides use exact constants. | PowerShell adapter and C# validator tests. | Fail closed on unsupported versions or operations. |
| TPM-CONTRACT-002 | Result must carry correlation ID, status, flags, stable error code, summary, warnings, evidence, and sanitized technical evidence. | Contract schema and validator | Native plugin validates before display. | Core self-test plus Pester failure matrix. | Missing, unknown, or inconsistent fields fail closed. |
| TPM-CONTRACT-003 | TPM invocation is explicit, bounded, non-interactive, and uses an isolated result file. | Adapter parameters and process runner | No console text is used as the integration contract. | Spaces, timeout, cancellation, and missing-result tests. | Process is killed on timeout/cancel; missing result is failure. |
