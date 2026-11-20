# Screen inventory: how each screen fits the window

This lists every kind of TeknoParrot Manager screen, how it decides its width, which tests cover it, and what has not been proven on a real console. "Not proven" means no one has watched it on a real Windows console at that size. It does not mean it is broken.

The narrowest console used in the guards below is the default 80-column window (79 usable cells). The ReShade chooser and the progress bar are also tested at 40 columns.

| Screen | How it fits the window | Tests | Not proven on a real console |
| ------ | ---------------------- | ----- | ---------------------------- |
| Result screens, recaps, "Needs your attention" lists, Details blocks (`Write-TpmText`, `Write-TpmOutcome`, `Show-TpmDetailBlocks`) | Wraps at the live window width, capped at 100, never narrower than 20 text cells. | `Fix66.ReadabilityHelpers`, `Fix83.ScreenReadabilityWave2`, `Fix80.ScreenReadability` (no line reaches the width) | Real window resize while a screen is shown |
| Progress bar (`scripts\TpmProgress.psm1`) | Measures the window and redraws when it changes, including height-only changes. | `Fix45.ProgressFrameWidth`, `Fix52.LiveResizeReflow`, `Fix16B.Progress`, `Rc8Ui.ProgressFix10` | Maximize during a live bar in Windows PowerShell 5.1; 125, 150 and 200 percent scaling |
| Workflow status panel (`Format-TpmWorkflowStatusRows`) | Takes a width (default 80, never below 24) and clips each row to it. | `TeknoParrot-Manager.Tests`, `SupportPackage.Tests` | Same as above |
| ReShade terminal chooser | Title, description and note on separate wrapped rows; options wrapped between whole options; redraws after a resize and keeps typed text. | `Fix46.ReShadeSelectionRedraw`, `Fix52.LiveResizeReflow` (40 to 200 columns), `ReShade.FiniteBuffer` | Live maximize in conhost; buffer-scroll cases |
| ReShade preview window (a Windows form) | Owner-drawn list with group headings that cannot be selected; text sizes set for the form and its painted labels. | `TeknoParrot-Manager.Tests` ("grouped preview selector and readable layout") | 100, 125, 150 and 200 percent scaling; the "Advanced Alternatives" group does not exist yet (no catalog entry uses it) |
| Older fixed screens (single `Write-Host` lines of plain text) | Fixed width. They wrap in the middle of a word when the window is narrower than the line. | `Fix411.ScreenWidthInventory` keeps the number of lines over 79 characters from growing | Wrapping these lines with `Write-TpmText` is not done; it needs a real console pass screen by screen |
| Windows file, folder and save dialogs | Owned by Windows. | None | Scaling |

How to add a new screen: write long text with `Write-TpmText` so it wraps. Do not add a `Write-Host` line of plain text longer than 79 characters.
