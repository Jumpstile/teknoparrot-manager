# ReShade wiki update -- staged insert only

Add the following section to the existing ReShade wiki page after its Setup section. This file is a staging/reference patch, not a complete replacement page; the live wiki was not changed.

## Previewing and choosing a profile

The optional non-modal preview offers 22 profiles built from 20 approved pinned shader effects (Original is the untouched reference; Enhanced Arcade is the existing combination), in four groups: Main Catalog, CRT Choices, Advanced Alternatives, and Actual HDR Setups Only (shown only when Windows reports HDR support with HDR on). Choose a profile directly from the preview drop-down or enter its matching number in the terminal chooser; both inputs stay synchronized. The terminal chooser remains usable if the preview is behind another window, closed, unavailable, or fails to open.

The preview shows the selected profile's description and approved shader filenames and techniques. Its image is a safe approximation based on the bundled TPM-owned landscape reference; it does not run the game or execute ReShade shaders. **Before** shows the untouched image, **After** shows the approximation, **Split** compares the two, and the 0-100 slider moves the comparison boundary. The slider and view mode are independent of profile choice, and actual in-game results may vary.

Selecting a profile only changes the preview. Choose terminal `U` and accept the existing explicit confirmation to deploy it. The preview closes automatically when the chooser returns.
