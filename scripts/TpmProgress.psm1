#Requires -Version 5.1
# Shared progress renderer for TeknoParrot Manager (PS 5.1 and PS 7 compatible). This is the ONLY progress
# renderer: every bar, percent, count, elapsed/ETA text and spinner in the product is produced here.
#
# Default columns: right-aligned description, framed bar, count, percentage, elapsed/rate, ETA/state and icon.
# -Columns selects columns in the requested order. Rows share measured description/count/time widths.
# Descriptions use all available space before truncation; there is no fixed 48-character label cap.
# Narrow windows drop optional columns in a fixed order. A description that would be cut first takes the blank ETA
# cells of a running plain line and the bar's extra width, then the elapsed/rate column. A plain line then also gives
# it the count when a shown percent repeats that progress, or a blank percent column, if that lets the whole description
# fit. Only then is it shortened. It never takes the bar, a shown percent, a count that no percent repeats or an
# ETA/state column with text, and terminal failures always retain a recognizable state.
#
# Honesty rules:
#   - Percent and counts show FINISHED work. A running operation never shows 100% (capped at 99%); only a
#     Final close with every unit finished shows 100%. A failed/cancelled/stalled close never shows 100%.
#   - Unknown total (Total <= 0): animated pulse, no percent or ETA; optional count is measured work only.
#   - A step that is ONE long external job (an installer that reports nothing while it runs) is marked with
#     Set-TpmProgressStage -LongStep. Long silence there is normal, so it reads "still working" in the running color
#     with no "(!)" and records no stall. Only a counted loop that stops advancing is shown and recorded as Stalled.
#   - A blocking call that reports nothing while it runs inside a step that keeps its count (a PostgreSQL tool, a web
#     request) is wrapped in Start-TpmProgressLongWait / Stop-TpmProgressLongWait: the same "still working" look, the count stays.
#   - ETA is hidden until the stage has >= 3 finished-count samples AND >= 3 seconds of elapsed time. A new stage
#     (different stage text, total, unit, or a count that went backwards) restarts the clock and the samples; a
#     text-only change hides the ETA until the new stage reports counts.
#   - Final never forces Current to Total; the line shows the real count.
#
# Output modes:
#   - Interactive console: one in-place row per task, redrawn by a background refresh writer independently of work
#     callbacks. Frames are at least 100ms and at most 250ms apart; within that range they are three times the
#     SUSTAINED frame cost (the median of the last measured frames), so one slow frame never stretches the interval
#     and a console slower than 50ms per frame for most frames backs off. A value update (Set-TpmProgressTask,
#     Set-TpmProgressStage, ...) only publishes a snapshot while that writer runs, also while it is still warming up:
#     it never draws or waits for a frame. The first frame and structural changes (a row added, a task state change,
#     which can also add or remove a row) are drawn inline, so a new row is on screen when the call returns. The
#     writer is started at the beginning of Start-TpmProgressOperation and warms up its frame path off screen, then
#     draws the latest snapshot. Each frame is composed into ONE string (rows and VT colors) and
#     emitted with one console write over the previous frame: rows are never blanked first (only rows that disappear
#     are, and the whole frame only after a width change). Width is bounded by BOTH window and buffer width and
#     re-read once more immediately before that write.
#     Rendered cell counts locate and erase reflowed rows after resizing, including an exact wrap at column zero.
#     FIX45: after each write the cursor is checked against the cells the frame was composed for. A frame whose own
#     glyphs took two cells each (the cursor ends exactly where that replay puts it) is recorded with the rows it really
#     took, so the next redraw or lift erases all of them, and the operation draws ASCII glyphs from then on. A cursor
#     end the frame's glyphs do not explain (foreign output) is never recorded and never erased. A caller that moved the
#     cursor into the region (SetCursorPosition) without writing does not strand the bar there: the lift reads the
#     region's cells back and erases them only when every cell still holds exactly the frame text.
#     Foreign output is never overdrawn: the next frame starts on a fresh line. Callers that print while a bar is
#     open use Suspend-TpmProgressOutput / Resume-TpmProgressOutput (the manager routes Write-Host through them),
#     so their text starts on a clean row and the bar is redrawn below it. The background refresh never starts a
#     new region itself: after foreign output (or the prompt of an owner that returned) it stops writing until the
#     next owner call, which redraws below that output. It runs while the owner runspace is Opened and the thread
#     that opened the operation is alive (RunspaceAvailability is not a liveness signal in a console host).
#   - Redirected / non-interactive (or TPM_PROGRESS_PLAIN=1): plain lines on stage change, each 10% of a known
#     total, every 5 seconds, and once for the closing state. No carriage returns, no color, ASCII glyphs (# and -).
#
# Style and color (environment, read at operation start):
#   TPM_PROGRESS_BAR_STYLE = block (default) | line. Block uses U+2588 and U+258F..U+2589 fractions;
#   line uses U+2501/U+2500/U+2578. ASCII uses # and -; both styles have vertical frame ends.
#     - output is redirected / plain mode (TPM_PROGRESS_PLAIN=1), or
#     - frames cannot be written as UTF-16 AND the console output encoding is not UTF-8, or
#     - the console output code page is a CJK double-byte code page (932/936/949/950), where box drawing is
#       ambiguous-width and can take two cells, or
#     - the host is not verified for the glyph font: Windows Terminal (WT_SESSION) and the VS Code terminal are
#       accepted; a classic conhost window is accepted only when its font is a TrueType Consolas/Cascadia face
#       (the legacy raster font and any other/unknown font fall back to ASCII), or
#     - the measured glyph cell probe fails (every selected character must advance one cell on the same row).
#   Frames are written with WriteConsoleW (UTF-16) when a real console handle exists, so the console code page
#   (OEM 437/850 on stock Windows PowerShell 5.1) does not decide whether the glyphs can be shown.
#   TPM_PROGRESS_STYLE = ascii | block | unicode | auto (default auto) forces a look; ascii is the "force ASCII" switch.
#   Auto on an interactive console that is NOT verified for the full glyph set draws the Block look: the solid bar
#   (U+2588 filled, tiny dots U+00B7 in dim gray for the empty part) with ASCII icons, because the full block and the middle dot exist in every console font and OEM
#   code page (it is skipped on CJK code pages and after a measured double-width glyph). Only redirected output,
#   TPM_PROGRESS_PLAIN=1 and TPM_PROGRESS_STYLE=ascii draw # and -.
#   The rate "(n/s)" is the real finished count over the real stage time and is left out until a second has passed.
#   A finished step with no known size (Total 0) removes its live row instead of leaving an empty bar behind.
#   NO_COLOR (non-empty) or TPM_PROGRESS_COLOR = 0|off|false|no|none disables color only (never the glyphs);
#   redirected output never colors. TPM_PROGRESS_PLAIN = 1 forces the plain-line mode.
#   FIX106: color is chosen once per operation (Get-TpmProgressColorMode): TrueColor (a console with virtual terminal
#   processing: Windows Terminal, VS Code, or a Windows console where that mode could be turned on; it is restored on exit),
#   Vt16 (the same sequences with the nearest of the 16 console colors; TPM_PROGRESS_COLOR=quantized), Console16 (no virtual
#   terminal processing: the console's own 16 colors, set run by run) or None (NO_COLOR, redirected output, unknown background).
#   The fill color follows progress along TpmProgressGradientStops (orange 10-20 percent, olive 45-50, teal 70-85, bright green
#   at 100; smooth in between). A finished bar is bright green, an incomplete one pale yellow with an orange warning sign, a
#   failed or overshooting one red with a red X, a skipped one gray, an unknown total cyan arrows. Color is never the only
#   signal: the count, the percent and the state word are always written. Text colors are selected for the background; an
#   unknown background is plain.
#
# Ownership: one operation is open at a time. A group owner (Start -Group) keeps its bar open across phase changes
# and leaf completions. Leaves report stage text and counts only; the owner closes the bar once (Complete) or
# abandons it (Stop). Nested Start calls increase a depth counter; only the outermost Complete closes. A nested
# Error/Cancelled/Stalled/Incomplete close records that outcome on the parent and ends only the nested level, so
# the parent stays open until its owner closes it (and then cannot close as success).
#
# Failure containment: a drawing or console failure never reaches the work being reported. The renderer of that operation is
# switched off (Disable-TpmProgressRenderer: writer joined, frame on screen lifted, cursor and console mode restored, one line to the owner's log hook
# set with Set-TpmProgressRenderLogger) while the operation stays open for ownership, outcomes and its close, and the close
# draws nothing. Genuine cancellation (Ctrl+C, a canceled token) always propagates.
# ASCII only (glyphs are built from code points).
#
# Progress layout, task snapshots, pulse and live-shape accounting adapted from Spectre.Console:
# src/Spectre.Console/{Widgets/ProgressBar.cs,Live/LiveRenderable.cs,Live/Progress/}.
# MIT License - Copyright (c) 2020 Patrik Svensson, Phil Scott, Nils Andresen
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

Set-StrictMode -Version 2.0

$script:TpmProgressOp = $null
$script:TpmProgressDepth = 0
$script:TpmProgressFontVerified = $null
$script:TpmProgressNativeReady = $null
$script:TpmProgressWideWrite = $null
$script:TpmProgressWideWriteActive = $false
$script:TpmProgressCellsReady = $null
$script:TpmProgressGlyphCells = $null
$script:TpmProgressSpinner = @('|', '/', '-', '\')
$script:TpmProgressMinFrameMs = 100
# Adaptive throttle (FIX24): the frame interval follows the MEDIAN cost of the last TpmProgressCostWindow measured frames
# (one slow frame never moves it) and is capped at TpmProgressMaxFrameMs. The first TpmProgressWarmupFrames frames of an
# operation are not measured: they carry one-time work (first-call script compilation, native bindings), not console cost.
$script:TpmProgressMaxFrameMs = 250
$script:TpmProgressCostWindow = 5
$script:TpmProgressWarmupFrames = 3
# True only while the refresh writer warms up its frame path (Invoke-TpmProgressWarmup): the console seams that write,
# move the cursor, blank cells or set the color then do nothing. Never set in the owner's module instance.
$script:TpmProgressDryRun = $false
$script:TpmProgressModulePath = $PSCommandPath
$script:TpmProgressRefreshService = $null
# Subscription id of this module's PowerShell.Exiting handler (FIX43); $null when none was registered.
$script:TpmProgressExitSubscriptionId = $null
$script:TpmProgressExitHookTried = $false
# Script block the owner registers (Set-TpmProgressRenderLogger) to write one line to its own log; $null = no logging.
$script:TpmProgressRenderLogger = $null
# Last console width that was read successfully (FIX40): a failing size query falls back to it instead of a fixed guess.
$script:TpmProgressLastWidth = 0
# How the last Get-TpmProgressWidth call decided (FIX45 support evidence): Window | Buffer | Previous | Default, and the
# window width it read (0 when the query failed).
$script:TpmProgressLastWidthSource = ''
$script:TpmProgressLastWindowWidth = 0
$script:TpmProgressCellReaderReady = $null
# ConsoleColor name -> SGR foreground parameter (the same 16 console table entries the legacy attributes select).
$script:TpmProgressSgrCodes = @{
    Black = '30'; DarkBlue = '34'; DarkGreen = '32'; DarkCyan = '36'; DarkRed = '31'; DarkMagenta = '35'; DarkYellow = '33'; Gray = '37'
    DarkGray = '90'; Blue = '94'; Green = '92'; Cyan = '96'; Red = '91'; Magenta = '95'; Yellow = '93'; White = '97'
}
# Background|State|Role -> SGR parameter ('' = host foreground); filled on first use by the frame composer.
$script:TpmProgressSgrCache = @{}
$script:TpmProgressVtReady = $null
# True only while ENABLE_VIRTUAL_TERMINAL_PROCESSING is set because THIS module set it (restored by Restore-TpmProgressVt).
$script:TpmProgressVtOwned = $false
# FIX106: the fill color of a running bar follows progress. Stops are percent, R, G, B: orange from 10 to 20 percent, olive from
# 45 to 50, teal from 70 to 85 and bright green at 100. Between two stops every channel is interpolated; below the first stop the
# bar keeps the first color.
$script:TpmProgressGradientStops = @(
    @(10, 255, 140, 30), @(20, 255, 140, 30), @(45, 170, 190, 40), @(50, 170, 190, 40),
    @(70, 30, 200, 210), @(85, 30, 200, 210), @(100, 40, 230, 90)
)
# The 16 console colors (the standard Windows palette) as RGB: the 16-color look is the nearest of these to the gradient color.
$script:TpmProgressConsoleRgb = [ordered]@{
    Black = @(0, 0, 0); DarkBlue = @(0, 0, 128); DarkGreen = @(0, 128, 0); DarkCyan = @(0, 128, 128)
    DarkRed = @(128, 0, 0); DarkMagenta = @(128, 0, 128); DarkYellow = @(128, 128, 0); Gray = @(192, 192, 192)
    DarkGray = @(128, 128, 128); Blue = @(0, 0, 255); Green = @(0, 255, 0); Cyan = @(0, 255, 255)
    Red = @(255, 0, 0); Magenta = @(255, 0, 255); Yellow = @(255, 255, 0); White = @(255, 255, 255)
}
# True-color RGB of the bars that are not on the gradient: pale yellow (ended early), orange (its warning sign), red (failed).
$script:TpmProgressStateRgb = @{ Warn = @(240, 230, 140); WarnMark = @(255, 140, 30); Error = @(235, 60, 60) }

# ---------------------------------------------------------------------------------------------------------------
# Seams (small functions so tests can replace the clock and the console)
# ---------------------------------------------------------------------------------------------------------------

function Get-TpmProgressNow {
    # [datetime]::Now is the value Get-Date returns, without the cmdlet cost on every progress update.
    return [datetime]::Now
}

function Get-TpmProgressTimestamp {
    # Monotonic milliseconds (Stopwatch), for measuring frame cost: wall-clock steps (DST, manual changes, time sync)
    # cannot inflate or shrink a measured cost.
    return ([System.Diagnostics.Stopwatch]::GetTimestamp() * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency)
}

function Test-TpmProgressOutputRedirected {
    if ($env:TPM_PROGRESS_PLAIN -eq '1') { return $true }
    try {
        return ([Console]::IsOutputRedirected -or (Get-TpmProgressBufferWidth) -lt 2 -or $null -eq (Get-TpmProgressCursor))
    } catch { return $true }
}

function Get-TpmProgressWidth {
    # -Live: the caller draws the live display, which exists only when output is not redirected, so the redirection
    # probe (two more console calls) is skipped.
    param([int]$Requested = 0, [switch]$Live)
    if (-not $Live -and (Test-TpmProgressOutputRedirected)) {
        if ($Requested -gt 0) { return $Requested }
        return 79
    }
    # One column is kept free so a full-width line never auto-wraps. The window AND the buffer bound the width; the
    # bound that decided is recorded (FIX45).
    $available = 79
    $source = 'Default'
    $windowWidth = Get-TpmProgressWindowWidth
    $bufferWidth = Get-TpmProgressBufferWidth
    if ($windowWidth -gt 0) {
        $available = $windowWidth - 1
        $source = 'Window'
    } elseif ($script:TpmProgressLastWidth -gt 0) {
        # A size query that fails never throws and never jumps to a fixed width: the previous size stays.
        $available = $script:TpmProgressLastWidth
        $source = 'Previous'
    }
    if ($bufferWidth -gt 0 -and ($bufferWidth - 1) -lt $available) {
        $available = $bufferWidth - 1
        $source = 'Buffer'
    }
    if ($windowWidth -gt 0) { $script:TpmProgressLastWidth = $available }
    $script:TpmProgressLastWidthSource = $source
    $script:TpmProgressLastWindowWidth = $windowWidth
    if ($Requested -gt 0) { return [Math]::Min($Requested, $available) }
    return $available
}

function Get-TpmProgressCursor {
    try { return [pscustomobject]@{ Left = [int][Console]::CursorLeft; Top = [int][Console]::CursorTop } } catch { return $null }
}

function Write-TpmProgressRaw {
    param([AllowEmptyString()][string]$Text = '', [switch]$NewLine)
    # Refresh writer warm-up: the frame is composed but never written.
    if ($script:TpmProgressDryRun) { return }
    if ($script:TpmProgressWideWriteActive) {
        # UTF-16 straight to the console: independent of the console code page, so glyph frames never turn into '?'.
        $written = $false
        try { $written = [TpmProgressNative.ConsoleFont]::WriteText($(if ($NewLine) { $Text + "`r`n" } else { $Text })) } catch { $written = $false }
        if ($written) { return }
        $script:TpmProgressWideWriteActive = $false
    }
    if ($NewLine) { [Console]::WriteLine($Text) } else { [Console]::Write($Text) }
}

function Write-TpmProgressPlainLine {
    param([AllowEmptyString()][string]$Text)
    [Console]::Out.WriteLine($Text)
}

function Get-TpmProgressBufferWidth {
    try { return [int][Console]::BufferWidth } catch { return 0 }
}

function Get-TpmProgressWindowWidth {
    try { return [int][Console]::WindowWidth } catch { return 0 }
}

function Read-TpmProgressCells {
    # FIX45: the characters of Count cells from column 0 of buffer row Top (ReadConsoleOutputCharacterW), or $null when
    # they cannot be read. Never moves the cursor.
    param([int]$Top, [int]$Count)
    if ($script:TpmProgressDryRun -or $Count -le 0 -or $Top -lt 0) { return $null }
    try {
        if (Initialize-TpmProgressCellReader) { return [TpmProgressNative.ConsoleCellReader]::Read($Top, $Count) }
    } catch {}
    return $null
}

function Get-TpmProgressWindowHeight {
    try { return [int][Console]::WindowHeight } catch { return 0 }
}

function Set-TpmProgressCursor {
    param([int]$Left, [int]$Top)
    if ($script:TpmProgressDryRun) { return $true }
    try { [Console]::SetCursorPosition($Left, $Top); return $true } catch { return $false }
}

function Get-TpmProgressCursorVisible {
    try { return [bool][Console]::CursorVisible } catch { return $null }
}

function Set-TpmProgressCursorVisible {
    param([bool]$Visible)
    try { [Console]::CursorVisible = $Visible } catch {}
}

function Get-TpmProgressForeground {
    # The console foreground attribute, or $null when the host does not report one.
    try { return [System.ConsoleColor][Console]::ForegroundColor } catch { return $null }
}

function Set-TpmProgressForeground {
    param([System.ConsoleColor]$Color)
    if ($script:TpmProgressDryRun) { return }
    try { [Console]::ForegroundColor = $Color } catch {}
}

function Get-TpmProgressDefaultColumns {
    return @('Description', 'Bar', 'Count', 'Percentage', 'Elapsed', 'Remaining', 'Spinner')
}

function Get-TpmProgressBackground {
    # The console background as a ConsoleColor name, or $null when the host does not report one.
    try {
        $value = [int][Console]::BackgroundColor
        if ($value -lt 0 -or $value -gt 15) { return $null }
        return ([string][System.ConsoleColor]$value)
    } catch { return $null }
}

function Clear-TpmProgressCells {
    # Blanks Count cells from column 0 of buffer row Top (wrapping onto following rows like the text did) without
    # moving the cursor or scrolling. Returns $false when the cells could not be blanked.
    param([int]$Top, [int]$Count)
    if ($script:TpmProgressDryRun) { return $true }
    if ($Count -le 0) { return $true }
    if ($Top -lt 0) { return $false }
    try {
        if (Initialize-TpmProgressCells) { return [bool][TpmProgressNative.ConsoleCells]::Blank($Top, $Count) }
    } catch {}
    # Without the native call only a single row can be blanked (spaces never reach the last column, so no wrap).
    $bufferWidth = Get-TpmProgressBufferWidth
    if ($bufferWidth -le 0 -or $Count -ge $bufferWidth) { return $false }
    if (-not (Set-TpmProgressCursor -Left 0 -Top $Top)) { return $false }
    try { Write-TpmProgressRaw -Text (' ' * $Count); return $true } catch { return $false }
}

function Write-TpmProgressProbe {
    # Writes probe text straight to the console (UTF-16 when possible). Returns $false when nothing could be written.
    param([string]$Text)
    if (Test-TpmProgressWideWriteAvailable) { return [bool][TpmProgressNative.ConsoleFont]::WriteText($Text) }
    [Console]::Write($Text)
    return $true
}

# ---------------------------------------------------------------------------------------------------------------
# Style and color detection
# ---------------------------------------------------------------------------------------------------------------

function Initialize-TpmProgressNative {
    # Compiles the small kernel32 binding once (console font probe and UTF-16 console write). False when unavailable.
    if ($null -ne $script:TpmProgressNativeReady) { return [bool]$script:TpmProgressNativeReady }
    $ready = $false
    try {
        if (-not ('TpmProgressNative.ConsoleFont' -as [type])) {
            Add-Type -Namespace TpmProgressNative -Name ConsoleFont -ErrorAction Stop -MemberDefinition @'
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct CONSOLE_FONT_INFOEX {
    public uint cbSize;
    public uint nFont;
    public short dwFontSizeX;
    public short dwFontSizeY;
    public int FontFamily;
    public int FontWeight;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FaceName;
}
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool GetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFOEX lpConsoleCurrentFontEx);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool WriteConsoleW(IntPtr hConsoleOutput, string lpBuffer, uint nNumberOfCharsToWrite, out uint lpNumberOfCharsWritten, IntPtr lpReserved);
public static bool IsConsoleOutput() {
    uint mode;
    return GetConsoleMode(GetStdHandle(-11), out mode);
}
public static bool WriteText(string text) {
    if (string.IsNullOrEmpty(text)) { return true; }
    uint written;
    return WriteConsoleW(GetStdHandle(-11), text, (uint)text.Length, out written, IntPtr.Zero);
}
'@
        }
        $ready = $true
    } catch { $ready = $false }
    $script:TpmProgressNativeReady = $ready
    return $ready
}

function Initialize-TpmProgressCells {
    # Compiles the console-cell binding once (FillConsoleOutputCharacterW: blanks cells without moving the cursor or
    # scrolling). A separate type so an already loaded older ConsoleFont type in the same session cannot hide it.
    if ($null -ne $script:TpmProgressCellsReady) { return [bool]$script:TpmProgressCellsReady }
    $ready = $false
    try {
        if (-not ('TpmProgressNative.ConsoleCells' -as [type])) {
            Add-Type -Namespace TpmProgressNative -Name ConsoleCells -ErrorAction Stop -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct COORD {
    public short X;
    public short Y;
}
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "FillConsoleOutputCharacterW")]
public static extern bool FillConsoleOutputCharacter(IntPtr hConsoleOutput, char cCharacter, uint nLength, COORD dwWriteCoord, out uint lpNumberOfCharsWritten);
public static bool Blank(int top, int count) {
    if (count <= 0) { return true; }
    if (top < 0 || top > 32766) { return false; }
    COORD origin;
    origin.X = 0;
    origin.Y = (short)top;
    uint written;
    if (!FillConsoleOutputCharacter(GetStdHandle(-11), ' ', (uint)count, origin, out written)) { return false; }
    return written == (uint)count;
}
'@
        }
        $ready = $true
    } catch { $ready = $false }
    $script:TpmProgressCellsReady = $ready
    return $ready
}

function Initialize-TpmProgressCellReader {
    # FIX45: compiles the console-cell read binding once. A separate type, so an older ConsoleCells type already loaded in
    # the same session cannot hide it.
    if ($null -ne $script:TpmProgressCellReaderReady) { return [bool]$script:TpmProgressCellReaderReady }
    $ready = $false
    try {
        if (-not ('TpmProgressNative.ConsoleCellReader' -as [type])) {
            Add-Type -Namespace TpmProgressNative -Name ConsoleCellReader -ErrorAction Stop -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct COORD {
    public short X;
    public short Y;
}
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "ReadConsoleOutputCharacterW")]
public static extern bool ReadConsoleOutputCharacter(IntPtr hConsoleOutput, [Out] char[] lpCharacter, uint nLength, COORD dwReadCoord, out uint lpNumberOfCharsRead);
public static string Read(int top, int count) {
    if (count <= 0 || top < 0 || top > 32766) { return null; }
    char[] buffer = new char[count];
    COORD origin;
    origin.X = 0;
    origin.Y = (short)top;
    uint read;
    if (!ReadConsoleOutputCharacter(GetStdHandle(-11), buffer, (uint)count, origin, out read)) { return null; }
    if (read != (uint)count) { return null; }
    return new string(buffer, 0, count);
}
'@
        }
        $ready = $true
    } catch { $ready = $false }
    $script:TpmProgressCellReaderReady = $ready
    return $ready
}

function Test-TpmProgressWideWriteAvailable {
    # True when stdout is a real console handle, so frames can be written as UTF-16 with WriteConsoleW.
    if ($null -ne $script:TpmProgressWideWrite) { return [bool]$script:TpmProgressWideWrite }
    $available = $false
    try { if (Initialize-TpmProgressNative) { $available = [bool][TpmProgressNative.ConsoleFont]::IsConsoleOutput() } } catch { $available = $false }
    $script:TpmProgressWideWrite = $available
    return $available
}

function Get-TpmProgressOutputCodePage {
    try { return [int][Console]::OutputEncoding.CodePage } catch { return 0 }
}

function Test-TpmProgressConhostFont {
    # True only for a TrueType Consolas/Cascadia face in a classic conhost window (never the raster font).
    if ($null -ne $script:TpmProgressFontVerified) { return [bool]$script:TpmProgressFontVerified }
    $verified = $false
    try {
        if (Initialize-TpmProgressNative) {
            $info = New-Object -TypeName 'TpmProgressNative.ConsoleFont+CONSOLE_FONT_INFOEX'
            $info.cbSize = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([type]'TpmProgressNative.ConsoleFont+CONSOLE_FONT_INFOEX')
            $handle = [TpmProgressNative.ConsoleFont]::GetStdHandle(-11)
            if ([TpmProgressNative.ConsoleFont]::GetCurrentConsoleFontEx($handle, $false, [ref]$info)) {
                $trueType = (($info.FontFamily -band 0x04) -ne 0)
                $verified = ($trueType -and ([string]$info.FaceName -match '^(Consolas|Cascadia)'))
            }
        }
    } catch { $verified = $false }
    $script:TpmProgressFontVerified = $verified
    return $verified
}

function Test-TpmProgressCjkCodePage {
    # Box drawing is East Asian Ambiguous width: consoles on a CJK double-byte code page can draw it two cells wide.
    return ((Get-TpmProgressOutputCodePage) -in @(932, 936, 949, 950))
}

function Test-TpmProgressGlyphCells {
    # Measured host evidence, once per process: writes the bar, icon and animation glyphs at the cursor, reads how
    # far the cursor moved (one cell per glyph on the same row), then blanks those cells and puts the cursor back. A host that
    # cannot report the cursor is not verified. When there is no room on the row the probe is not run (and not cached).
    if ($null -ne $script:TpmProgressGlyphCells) { return [bool]$script:TpmProgressGlyphCells }
    $glyphs = ([string][char]0x2501 + [string][char]0x2500 + [string][char]0x2578 +
        [string][char]0x2588 + [string][char]0x258F + [string][char]0x258E + [string][char]0x258D +
        [string][char]0x258C + [string][char]0x258B + [string][char]0x258A + [string][char]0x2589 +
        [string][char]0x25B6 + [string][char]0x25C0 + [string][char]0x26A0 + [string][char]0x2717 +
        [string][char]0x2713 + [string][char]0x25CB + [string][char]0x25A0)
    $before = Get-TpmProgressCursor
    if ($null -eq $before) { $script:TpmProgressGlyphCells = $false; return $false }
    # Room for a double-width result plus one cell, so even a failed probe never wraps.
    if (((Get-TpmProgressWidth) - $before.Left) -lt (2 * $glyphs.Length + 2)) { return $false }
    $measured = $false
    try {
        if (Write-TpmProgressProbe -Text $glyphs) {
            $after = Get-TpmProgressCursor
            $measured = ($null -ne $after -and $after.Top -eq $before.Top -and ($after.Left - $before.Left) -eq $glyphs.Length)
        }
    } catch { $measured = $false }
    finally {
        try {
            if (Set-TpmProgressCursor -Left $before.Left -Top $before.Top) {
                [void](Write-TpmProgressProbe -Text (' ' * (2 * $glyphs.Length)))
                [void](Set-TpmProgressCursor -Left $before.Left -Top $before.Top)
            }
        } catch {}
    }
    $script:TpmProgressGlyphCells = $measured
    return $measured
}

function Test-TpmProgressGlyphOutputUsable {
    # Glyph text can reach this console intact: an interactive console that takes UTF-16 (or runs a UTF-8 code page),
    # and not a CJK double-byte code page, where box drawing is ambiguous-width and can take two cells.
    try {
        if (Test-TpmProgressOutputRedirected) { return $false }
        if (-not (Test-TpmProgressWideWriteAvailable) -and (Get-TpmProgressOutputCodePage) -ne 65001) { return $false }
        return (-not (Test-TpmProgressCjkCodePage))
    } catch { return $false }
}

function Test-TpmProgressUnicodeVerified {
    # The full glyph look is used by default only when the host can render it (rule in the file header).
    try {
        if (-not (Test-TpmProgressGlyphOutputUsable)) { return $false }
        $hostAccepted = $false
        if (-not [string]::IsNullOrEmpty($env:WT_SESSION)) { $hostAccepted = $true }
        elseif ($env:TERM_PROGRAM -eq 'vscode') { $hostAccepted = $true }
        else { $hostAccepted = (Test-TpmProgressConhostFont) }
        if (-not $hostAccepted) { return $false }
        return (Test-TpmProgressGlyphCells)
    } catch { return $false }
}

function Test-TpmProgressBlockBarUsable {
    # The solid bar needs the full block (U+2588) and the middle dot (U+00B7) for the empty part. Both are in the legacy
    # OEM code pages (437, 850, ...), so every console font draws it one cell wide, including the fonts that are not
    # verified for the full glyph set. A host already measured to draw glyphs two cells wide keeps the ASCII look.
    if ($script:TpmProgressGlyphCells -eq $false) { return $false }
    return (Test-TpmProgressGlyphOutputUsable)
}

function Get-TpmProgressStyle {
    # Unicode, Block and Ascii select glyph capability; TPM_PROGRESS_BAR_STYLE independently selects block or line.
    # Block = solid bar only (icons stay ASCII); it is what an interactive console gets when the full glyph set is not verified.
    $mode = ([string]$env:TPM_PROGRESS_STYLE).Trim().ToLowerInvariant()
    if ($mode -eq 'ascii') { return 'Ascii' }
    if ($mode -eq 'block') { return 'Block' }
    if ($mode -in @('unicode', 'glyph', 'glyphs', 'utf8')) { return 'Unicode' }
    if (Test-TpmProgressUnicodeVerified) { return 'Unicode' }
    if (Test-TpmProgressBlockBarUsable) { return 'Block' }
    return 'Ascii'
}

function Get-TpmProgressCapabilities {
    # Everything the style decision looks at, for the preview script and for support evidence.
    $redirected = Test-TpmProgressOutputRedirected
    $background = $(if ($redirected) { $null } else { Get-TpmProgressBackground })
    return [pscustomobject]@{
        Redirected       = $redirected
        WideWrite        = $(if ($redirected) { $false } else { Test-TpmProgressWideWriteAvailable })
        OutputCodePage   = (Get-TpmProgressOutputCodePage)
        WindowsTerminal  = (-not [string]::IsNullOrEmpty($env:WT_SESSION))
        VsCodeTerminal   = ($env:TERM_PROGRAM -eq 'vscode')
        ConhostFont      = $(if ($redirected) { $false } else { Test-TpmProgressConhostFont })
        CjkCodePage      = (Test-TpmProgressCjkCodePage)
        StyleOverride    = [string]$env:TPM_PROGRESS_STYLE
        Style            = (Get-TpmProgressStyle)
        GlyphCells       = $(if ($redirected) { $false } else { $script:TpmProgressGlyphCells })
        Background       = $background
        ColorMode        = (Get-TpmProgressColorMode -Background $background)
    }
}

function Test-TpmProgressColorEnabled {
    if (Test-TpmProgressOutputRedirected) { return $false }
    if (-not [string]::IsNullOrEmpty($env:NO_COLOR)) { return $false }
    $mode = ([string]$env:TPM_PROGRESS_COLOR).Trim().ToLowerInvariant()
    if ($mode -in @('0', 'off', 'false', 'no', 'none')) { return $false }
    if ($env:TERM -eq 'dumb') { return $false }
    return $true
}

function Initialize-TpmProgressConsoleModeApi {
    if (-not ('TpmProgressNative.ConsoleOutputMode' -as [type])) {
        Add-Type -Namespace TpmProgressNative -Name ConsoleOutputMode -ErrorAction Stop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr handle, out uint mode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr handle, uint mode);
public static bool Read(out uint mode) { return GetConsoleMode(GetStdHandle(-11), out mode); }
public static bool Write(uint mode) { return SetConsoleMode(GetStdHandle(-11), mode); }
'@
    }
}

function Get-TpmProgressConsoleMode {
    # Seam: the standard output console mode, or $null when it cannot be read (no console, redirected, API failure).
    try {
        Initialize-TpmProgressConsoleModeApi
        $mode = [uint32]0
        if ([TpmProgressNative.ConsoleOutputMode]::Read([ref]$mode)) { return [uint32]$mode }
    } catch {}
    return $null
}

function Set-TpmProgressConsoleMode {
    # Seam: sets the standard output console mode; returns $false when it could not be set.
    param([uint32]$Mode)
    try {
        Initialize-TpmProgressConsoleModeApi
        return [bool][TpmProgressNative.ConsoleOutputMode]::Write($Mode)
    } catch { return $false }
}

function Test-TpmProgressVt {
    # Enable VT once on a real Windows console; unsupported/legacy surfaces remain plain text. The original mode is
    # left alone when VT is already on; otherwise ownership of the change is recorded so it can be undone.
    if ($null -ne $script:TpmProgressVtReady) { return [bool]$script:TpmProgressVtReady }
    $ready = $false
    try {
        $mode = Get-TpmProgressConsoleMode
        if ($null -ne $mode) {
            if (([long]$mode -band 4) -ne 0) {
                $ready = $true
            } elseif (Set-TpmProgressConsoleMode -Mode ([uint32]([long]$mode -bor 4))) {
                $ready = $true
                $script:TpmProgressVtOwned = $true
            }
        }
    } catch { $ready = $false }
    $script:TpmProgressVtReady = $ready
    return $ready
}

function Restore-TpmProgressVt {
    # Lifetime boundary (every release of the operation and module removal): undo only our own change. The VT bit is
    # cleared only when this module set it and it is still set; every other mode bit is re-read, never overwritten
    # with a stale copy. Ownership is released only when a read proves the bit absent or the clear succeeded, so a
    # failed restore is retried at the next boundary. The cached capability is reset so the next operation re-probes;
    # a still-owned bit is then seen as set and is not claimed as pre-existing (ownership is never dropped by a probe).
    try {
        if ($script:TpmProgressVtOwned) {
            $mode = Get-TpmProgressConsoleMode
            if ($null -ne $mode) {
                if (([long]$mode -band 4) -eq 0) {
                    $script:TpmProgressVtOwned = $false
                } elseif (Set-TpmProgressConsoleMode -Mode ([uint32]([long]$mode - 4))) {
                    $script:TpmProgressVtOwned = $false
                }
            }
        }
    } catch {
    } finally {
        $script:TpmProgressVtReady = $null
    }
}

function Get-TpmProgressColorMode {
    # How this console shows color, decided once per operation. TrueColor: virtual terminal processing with RGB (Windows
    # Terminal, VS Code, or a Windows console where Test-TpmProgressVt could turn that mode on). Vt16: the same sequences with
    # the nearest of the 16 console colors (TPM_PROGRESS_COLOR=quantized). Console16: no virtual terminal processing, so the
    # console's own 16 colors are set run by run. None: redirected output, NO_COLOR, or a background that is not known.
    param([AllowNull()][AllowEmptyString()][string]$Background)
    if ([string]::IsNullOrEmpty($Background) -or -not (Test-TpmProgressColorEnabled)) { return 'None' }
    if (-not (Test-TpmProgressVt)) {
        if ($null -eq (Get-TpmProgressForeground)) { return 'None' }
        return 'Console16'
    }
    if (([string]$env:TPM_PROGRESS_COLOR).Trim().ToLowerInvariant() -eq 'quantized') { return 'Vt16' }
    if (-not [string]::IsNullOrEmpty($env:WT_SESSION) -or $env:TERM_PROGRAM -eq 'vscode' -or [Environment]::OSVersion.Version.Major -ge 10) { return 'TrueColor' }
    return 'Vt16'
}

function Get-TpmProgressNearestColor {
    # The nearest of the 16 console colors to an RGB value. Black is never chosen; a light background only gets dark colors.
    param([int[]]$Rgb, [bool]$Light)
    $best = $null
    $bestDistance = [long]::MaxValue
    foreach ($name in $script:TpmProgressConsoleRgb.Keys) {
        if ($name -eq 'Black' -or ($Light -and -not $name.StartsWith('Dark'))) { continue }
        $candidate = $script:TpmProgressConsoleRgb[$name]
        $distance = [long]0
        for ($channel = 0; $channel -lt 3; $channel++) {
            $delta = $Rgb[$channel] - $candidate[$channel]
            $distance += $delta * $delta
        }
        if ($distance -lt $bestDistance) { $bestDistance = $distance; $best = $name }
    }
    return $best
}

function New-TpmProgressPaint {
    # One bar color: RGB for true color and a console color for 16-color. A light background darkens the RGB and takes the dark
    # console color. -Name fixes the console color (the state colors); without it the nearest console color is used. A console
    # color in the background's own hue is dropped (null: the host foreground).
    param([int[]]$Rgb, [AllowNull()][AllowEmptyString()][string]$Background, [string]$Name = '')
    $light = $Background -in @('White', 'Gray', 'Yellow', 'Cyan', 'Green', 'Magenta')
    if ($light) { $Rgb = @(foreach ($value in $Rgb) { [int][Math]::Round($value * 0.55) }) }
    $color = $Name
    if (-not $color) { $color = Get-TpmProgressNearestColor -Rgb $Rgb -Light $light }
    elseif ($light -and -not $color.StartsWith('Dark')) { $color = 'Dark' + $color }
    if (($color -replace '^Dark', '') -eq ($Background -replace '^Dark', '')) { $color = $null }
    return [pscustomobject]@{ Red = $Rgb[0]; Green = $Rgb[1]; Blue = $Rgb[2]; Color = $color }
}

function Get-TpmProgressGradient {
    # The fill color at a percent (TpmProgressGradientStops): Red, Green, Blue for true color and Color, the nearest console
    # color, for 16-color. Below the first stop it is the first color, above the last the last.
    param([double]$Percent, [AllowNull()][string]$Background = 'Black')
    $stops = $script:TpmProgressGradientStops
    $last = $stops.Count - 1
    # [double] bounds: [Math]::Min(100, <double>) binds the Int32 overload in PowerShell and rounds the percent.
    $p = [Math]::Max([double]$stops[0][0], [Math]::Min([double]$stops[$last][0], $Percent))
    $index = 0
    while ($index -lt $last - 1 -and $p -ge $stops[$index + 1][0]) { $index++ }
    $from = $stops[$index]
    $to = $stops[$index + 1]
    $fraction = ($p - $from[0]) / ($to[0] - $from[0])
    $rgb = @(foreach ($channel in 1, 2, 3) { [int][Math]::Round($from[$channel] + ($to[$channel] - $from[$channel]) * $fraction) })
    return (New-TpmProgressPaint -Rgb $rgb -Background $Background)
}

function Get-TpmProgressRowPaint {
    # The bar colors of one row: Fill (the filled cells) and Mark (the X or warning sign at the bar end). Running follows the
    # gradient, done is the gradient's end, ended early is pale yellow with an orange sign, failed is red. $null when the row has
    # no colored fill (unknown total, pending, skipped): the palette colors its roles alone.
    param([string]$State, [double]$Percent, [AllowNull()][AllowEmptyString()][string]$Background = 'Black')
    if ($State -eq 'Running' -and $Percent -ge 0) {
        $fill = Get-TpmProgressGradient -Percent $Percent -Background $Background
        return [pscustomobject]@{ Fill = $fill; Mark = $fill }
    }
    if ($State -in @('Final', 'No-op')) {
        $fill = Get-TpmProgressGradient -Percent 100 -Background $Background
        return [pscustomobject]@{ Fill = $fill; Mark = $fill }
    }
    if ($State -in @('Incomplete', 'Cancelled', 'Stalled')) {
        $fill = New-TpmProgressPaint -Rgb $script:TpmProgressStateRgb.Warn -Background $Background -Name 'Yellow'
        $mark = New-TpmProgressPaint -Rgb $script:TpmProgressStateRgb.WarnMark -Background $Background -Name 'DarkYellow'
        return [pscustomobject]@{ Fill = $fill; Mark = $mark }
    }
    if ($State -eq 'Error') {
        $fill = New-TpmProgressPaint -Rgb $script:TpmProgressStateRgb.Error -Background $Background -Name 'Red'
        return [pscustomobject]@{ Fill = $fill; Mark = $fill }
    }
    return $null
}

function Get-TpmProgressPalette {
    # State colors for a console background (a ConsoleColor name). Returns $null when the background is unknown:
    # then nothing is colored and every state is still told apart by its mark, fill weight and word.
    param([AllowNull()][AllowEmptyString()][string]$Background)
    if ([string]::IsNullOrEmpty($Background)) { return $null }
    $light = ($Background -in @('White', 'Gray', 'Yellow', 'Cyan', 'Green', 'Magenta'))
    $palette = if ($light) {
        @{ Running = 'DarkCyan'; Final = 'DarkGreen'; Error = 'DarkRed'; Warn = 'DarkYellow'; Track = 'DarkGray'; Label = 'DarkGray'; Percent = 'DarkGreen'; Time = 'DarkBlue'; Dim = 'DarkGray' }
    } else {
        # Dark gray is a readable track only on black; on other dark backgrounds the track uses the host foreground.
        @{ Running = 'Cyan'; Final = 'Green'; Error = 'Red'; Warn = 'Yellow'; Track = $(if ($Background -eq 'Black') { 'DarkGray' } else { $null }); Label = 'Gray'; Percent = 'Green'; Time = 'Cyan'; Dim = 'DarkGray' }
    }
    # Never draw in the background's own hue (for example Red on DarkRed): use the host foreground instead.
    $hue = $Background -replace '^Dark', ''
    foreach ($key in @($palette.Keys)) {
        if ($palette[$key] -and (([string]$palette[$key]) -replace '^Dark', '') -eq $hue) { $palette[$key] = $null }
    }
    return $palette
}

# ---------------------------------------------------------------------------------------------------------------
# Pure formatting (no console access, no clock)
# ---------------------------------------------------------------------------------------------------------------

function ConvertTo-TpmProgressText {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return ($Text -replace '[^\x20-\x7E]', '?')
}

function Limit-TpmProgressText {
    param([AllowEmptyString()][string]$Text, [int]$Width)
    if ($Width -le 0) { return '' }
    if ($Text.Length -le $Width) { return $Text }
    if ($Width -le 3) { return $Text.Substring(0, $Width) }
    return ($Text.Substring(0, $Width - 3) + '...')
}

function Format-TpmProgressDuration {
    # m:ss, or h:mm:ss from one hour. Negative or non-finite input renders as --:--.
    param([double]$Seconds)
    if ($Seconds -lt 0 -or [double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds)) { return '--:--' }
    $whole = [int64][Math]::Floor($Seconds)
    $hours = [int64][Math]::Floor($whole / 3600)
    $minutes = [int][Math]::Floor(($whole % 3600) / 60)
    $secs = [int]($whole % 60)
    if ($hours -gt 0) { return ('{0}:{1:00}:{2:00}' -f $hours, $minutes, $secs) }
    return ('{0}:{1:00}' -f $minutes, $secs)
}

function ConvertTo-TpmProgressSizeText {
    # Floors to the requested decimals (never rounds up), culture independent.
    param([long]$Bytes, [double]$Divisor, [int]$Decimals)
    $scale = [Math]::Pow(10, $Decimals)
    $value = [Math]::Floor(([double]$Bytes / $Divisor) * $scale) / $scale
    return $value.ToString($(if ($Decimals -gt 0) { '0.' + ('0' * $Decimals) } else { '0' }), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-TpmProgressCount {
    # Items: "12/340" (current padded to the total's width) or "12" when the total is unknown.
    # Bytes: "12.4/340.0 MB" scaled to the total (or to the current value when the total is unknown). Sizes are FLOORED, and
    # while Current < Total the two figures are never shown equal (more decimals, then raw bytes), so 99.99% never reads as done.
    param([long]$Current = 0, [long]$Total = 0, [string]$Unit = 'Items')
    if ($Current -lt 0) { $Current = 0 }
    if ($Unit -eq 'Bytes') {
        $scaleSource = if ($Total -gt 0) { $Total } else { $Current }
        $divisor = [double]1
        $name = 'B'
        if ($scaleSource -ge 1073741824) { $divisor = [double]1073741824; $name = 'GB' }
        elseif ($scaleSource -ge 1048576) { $divisor = [double]1048576; $name = 'MB' }
        elseif ($scaleSource -ge 1024) { $divisor = [double]1024; $name = 'KB' }
        if ($name -eq 'B') {
            if ($Total -gt 0) { return ('{0}/{1} B' -f ([string]$Current).PadLeft(([string]$Total).Length), $Total) }
            return ('{0} B' -f $Current)
        }
        if ($Total -le 0) { return ('{0} {1}' -f (ConvertTo-TpmProgressSizeText -Bytes $Current -Divisor $divisor -Decimals 1), $name) }
        $decimals = 1
        $currentText = ConvertTo-TpmProgressSizeText -Bytes $Current -Divisor $divisor -Decimals $decimals
        $totalText = ConvertTo-TpmProgressSizeText -Bytes $Total -Divisor $divisor -Decimals $decimals
        while ($Current -lt $Total -and $currentText -eq $totalText -and $decimals -lt 3) {
            $decimals++
            $currentText = ConvertTo-TpmProgressSizeText -Bytes $Current -Divisor $divisor -Decimals $decimals
            $totalText = ConvertTo-TpmProgressSizeText -Bytes $Total -Divisor $divisor -Decimals $decimals
        }
        if ($Current -lt $Total -and $currentText -eq $totalText) {
            return ('{0}/{1} B' -f ([string]$Current).PadLeft(([string]$Total).Length), $Total)
        }
        return ('{0}/{1} {2}' -f $currentText.PadLeft($totalText.Length), $totalText, $name)
    }
    if ($Total -gt 0) {
        $totalText = [string]$Total
        return ('{0}/{1}' -f ([string]$Current).PadLeft($totalText.Length), $totalText)
    }
    return [string]$Current
}

function Get-TpmProgressPercent {
    # Whole percent of FINISHED work, or -1 when the total is unknown. 100 is returned only for a Final/No-op
    # state with Current >= Total; every other state is capped at 99 (running work is not complete until the
    # owner closes it, and failed/cancelled/stalled work is never 100%).
    param([long]$Current = 0, [long]$Total = 0, [string]$State = 'Running')
    if ($Total -le 0) { return -1 }
    $finished = [Math]::Max([long]0, [Math]::Min([long]$Current, [long]$Total))
    $percent = [int][Math]::Floor(($finished * 100.0) / $Total)
    if ($State -notin @('Final', 'No-op') -and $percent -gt 99) { $percent = 99 }
    return $percent
}

function Get-TpmProgressEta {
    # Estimated remaining seconds, or -1 when it must stay hidden: unknown total, nothing left, fewer than
    # MinSamples finished-count samples, less than MinSeconds elapsed, or no measurable progress.
    param(
        [long]$Current = 0, [long]$Total = 0, [long]$StartCurrent = 0, [double]$ElapsedSeconds = 0,
        [int]$Samples = 0, [int]$MinSamples = 3, [double]$MinSeconds = 3, [double]$SmoothedRate = -1
    )
    if ($Total -le 0 -or $Current -ge $Total) { return [double]-1 }
    if ($Samples -lt $MinSamples -or $ElapsedSeconds -lt $MinSeconds) { return [double]-1 }
    $progressed = $Current - $StartCurrent
    if ($progressed -le 0) { return [double]-1 }
    $rate = if ($SmoothedRate -ge 0) { $SmoothedRate } else { $progressed / $ElapsedSeconds }
    if ($rate -le 0) { return [double]-1 }
    $remaining = ($Total - $Current) / $rate
    if ($remaining -lt 0 -or $remaining -ge 360000) { return [double]-1 }
    return [double]$remaining
}

function New-TpmProgressSegment {
    param([AllowEmptyString()][string]$Text, [string]$Role)
    return [pscustomobject]@{ Text = $Text; Role = $Role }
}

function Get-TpmProgressBarGlyphs {
    param([string]$Style = 'Ascii')
    # The Block look and the Unicode look (without the line bar) draw every empty cell as the middle dot U+00B7 in the dim gray role
    # 'dots'. U+00B7 is in code page 437 and in every console font, like the full block. The line bar and the Ascii look are unchanged.
    $dot = [string][char]0x00B7
    if ($Style -eq 'Unicode' -and ([string]$env:TPM_PROGRESS_BAR_STYLE).Trim().ToLowerInvariant() -eq 'line') {
        return [pscustomobject]@{ Fill = [string][char]0x2501; Rest = [string][char]0x2500; RestRole = 'rest'; Line = $true; Open = '|'; Close = '|' }
    }
    if ($Style -eq 'Block' -or $Style -eq 'Unicode') {
        return [pscustomobject]@{ Fill = [string][char]0x2588; Rest = $dot; RestRole = 'dots'; Line = $false; Open = '|'; Close = '|' }
    }
    return [pscustomobject]@{ Fill = '#'; Rest = '-'; RestRole = 'rest'; Line = $false; Open = '|'; Close = '|' }
}

function New-TpmProgressBarSegments {
    # Each segment's text is exactly its visible cell count, including frame and markers. Segments are built inline
    # (not through New-TpmProgressSegment): this runs for every row of every frame.
    param([long]$Current = 0, [long]$Total = 0, [int]$BarWidth = 20, [string]$State = 'Running', [int]$Tick = 0, [string]$Style = 'Ascii')
    $glyphs = Get-TpmProgressBarGlyphs -Style $Style
    $inner = [Math]::Max(1, $BarWidth - 2)
    $segments = [System.Collections.Generic.List[object]]::new()
    [void]$segments.Add([pscustomobject]@{ Text = $glyphs.Open; Role = 'rest' })
    if ($State -eq 'Skipped') {
        [void]$segments.Add([pscustomobject]@{ Text = ('-' + ($glyphs.Rest * ($inner - 1))); Role = 'state' })
    } elseif (($Total -le 0 -and $State -in @('Running', 'Waiting', 'Stalled', 'Pending')) -or $State -eq 'Pending') {
        $group = [Math]::Min(14, $inner)
        $travel = $inner - $group
        $phase = if ($travel -gt 0) { [int]([Math]::Abs([long]$Tick) % (2 * $travel)) } else { 0 }
        $right = ($travel -eq 0 -or $phase -lt $travel)
        $offset = if ($right) { $phase } else { 2 * $travel - $phase }
        $arrow = if ($Style -eq 'Unicode') { if ($right) { [string][char]0x25B6 } else { [string][char]0x25C0 } } else { if ($right) { '>' } else { '<' } }
        if ($offset -gt 0) { [void]$segments.Add([pscustomobject]@{ Text = ($glyphs.Rest * $offset); Role = $glyphs.RestRole }) }
        [void]$segments.Add([pscustomobject]@{ Text = ($arrow * $group); Role = 'unknown' })
        if ($inner - $offset - $group -gt 0) { [void]$segments.Add([pscustomobject]@{ Text = ($glyphs.Rest * ($inner - $offset - $group)); Role = $glyphs.RestRole }) }
    } elseif ($Total -gt 0) {
        $overshoot = $Current -gt $Total
        # [double] bounds are required: [Math]::Min(1, <double>) binds the Int32 overload in PowerShell, which
        # rounds the ratio to 0 or 1 and made the fill binary (25% and 50% empty, 71% and 75% almost full).
        $ratio = [Math]::Max([double]0, [Math]::Min([double]1, [double]$Current / $Total))
        if (-not $overshoot -and $State -notin @('Final', 'No-op')) { $ratio = [Math]::Min(0.99, $ratio) }
        $exact = $ratio * $inner
        $filled = [Math]::Max(0, [Math]::Min($inner, [int][Math]::Floor($exact)))
        $warning = ($State -in @('Incomplete', 'Cancelled', 'Stalled') -and $filled -lt $inner)
        $cross = ($State -eq 'Error' -or $overshoot)
        if ($overshoot) { $filled = $inner - 1 }
        elseif ($cross) { $filled = [Math]::Min($filled, $inner - 1) }
        if ($filled -gt 0) { [void]$segments.Add([pscustomobject]@{ Text = ($glyphs.Fill * $filled); Role = 'fill' }) }
        $used = $filled
        if ($cross) {
            if ($inner - $used - 1 -gt 0) {
                [void]$segments.Add([pscustomobject]@{ Text = ($glyphs.Rest * ($inner - $used - 1)); Role = $glyphs.RestRole })
                $used = $inner - 1
            }
            $mark = if ($Style -eq 'Unicode') { [string][char]0x2717 } else { 'X' }
            [void]$segments.Add([pscustomobject]@{ Text = $mark; Role = 'mark' })
            $used++
        } elseif ($warning) {
            $mark = if ($Style -eq 'Unicode') { [string][char]0x26A0 } else { '!' }
            [void]$segments.Add([pscustomobject]@{ Text = $mark; Role = 'mark' })
            $used++
        } elseif ($Style -eq 'Unicode' -and $filled -lt $inner) {
            $fraction = [int][Math]::Floor(($exact - $filled) * 8)
            if ($glyphs.Line -and $fraction -ge 4) { $partial = [string][char]0x2578 }
            elseif (-not $glyphs.Line -and $fraction -gt 0) { $partial = [string][char](0x2590 - $fraction) }
            else { $partial = '' }
            if ($partial) { [void]$segments.Add([pscustomobject]@{ Text = $partial; Role = 'fill' }); $used++ }
        }
        if ($inner - $used -gt 0) { [void]$segments.Add([pscustomobject]@{ Text = ($glyphs.Rest * ($inner - $used)); Role = $glyphs.RestRole }) }
    } elseif ($State -in @('Final', 'No-op')) {
        # Finished work with no known size has nothing to count against, so it is shown full: never an empty bar with a check mark.
        [void]$segments.Add([pscustomobject]@{ Text = ($glyphs.Fill * $inner); Role = 'fill' })
    } else {
        [void]$segments.Add([pscustomobject]@{ Text = ($glyphs.Rest * $inner); Role = $glyphs.RestRole })
    }
    [void]$segments.Add([pscustomobject]@{ Text = $glyphs.Close; Role = 'rest' })
    return $segments.ToArray()
}

function Format-TpmProgressBar {
    # Plain bar text of exactly BarWidth cells (no percent, no color). Percent follows Get-TpmProgressPercent.
    param([long]$Current = 0, [long]$Total = 0, [int]$BarWidth = 20, [string]$State = 'Running', [int]$Tick = 0, [string]$Style = 'Ascii')
    $segments = @(New-TpmProgressBarSegments -Current $Current -Total $Total -BarWidth $BarWidth -State $State -Tick $Tick -Style $Style)
    return (($segments | ForEach-Object { $_.Text }) -join '')
}

function Format-TpmProgressSummary {
    # Compact one-piece text for surfaces that cannot draw a bar (workflow status footer): the same percent,
    # count, elapsed and ETA wording and rules as the bar line.
    param([long]$Current = 0, [long]$Total = 0, [string]$Unit = 'Items', [double]$ElapsedSeconds = 0, [double]$EtaSeconds = -1, [string]$State = 'Running')
    $parts = New-Object System.Collections.Generic.List[string]
    $percent = Get-TpmProgressPercent -Current $Current -Total $Total -State $State
    if ($percent -ge 0) { [void]$parts.Add(('{0}%' -f $percent)) }
    [void]$parts.Add((Format-TpmProgressCount -Current $Current -Total $Total -Unit $Unit).Trim())
    [void]$parts.Add((Format-TpmProgressDuration -Seconds $ElapsedSeconds))
    if ($State -eq 'Running' -and $EtaSeconds -ge 0) { [void]$parts.Add(('ETA ' + (Format-TpmProgressDuration -Seconds $EtaSeconds))) }
    return ($parts -join '  ')
}

function Get-TpmProgressLabelText {
    # The one place that joins a title and a stage into the words a row shows. A blank title shows the stage alone.
    param([AllowEmptyString()][AllowNull()][string]$Title = '', [AllowEmptyString()][AllowNull()][string]$Stage = '')
    $label = ConvertTo-TpmProgressText -Text $Title
    $stageText = ConvertTo-TpmProgressText -Text $Stage
    if (-not $stageText) { return $label }
    if (-not $label) { return $stageText }
    return ($label + ': ' + $stageText)
}

function Format-TpmProgressElapsed {
    # "in 2.5s (4.00/s)". A negative rate means "not measurable", and only the time is shown.
    param([double]$ElapsedSeconds = 0, [double]$Rate = -1)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $text = 'in ' + ([Math]::Max([double]0, $ElapsedSeconds)).ToString('0.0', $culture) + 's'
    if ($Rate -lt 0) { return $text }
    return ($text + ' (' + $Rate.ToString('0.00', $culture) + '/s)')
}

function Format-TpmProgressSegments {
    # Pure layout engine. Returns segments {Text, Role} whose Text lengths sum to exactly Width.
    param(
        [AllowEmptyString()][string]$Title = '',
        [AllowEmptyString()][string]$Stage = '',
        [long]$Current = 0,
        [long]$Total = 0,
        [string]$State = 'Running',
        [double]$ElapsedSeconds = 0,
        [double]$EtaSeconds = -1,
        [double]$Rate = -1,
        [int]$Width = 79,
        [int]$Tick = 0,
        [ValidateSet('Ascii', 'Block', 'Unicode')][string]$Style = 'Ascii',
        [ValidateSet('Items', 'Bytes')][string]$Unit = 'Items',
        [switch]$NoCount,
        [ValidateSet('Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining', 'Spinner')][string[]]$Columns = (Get-TpmProgressDefaultColumns),
        [int]$DescriptionWidth = 0,
        [int]$CountWidth = 0,
        [int]$PercentWidth = 0,
        [int]$TimeWidth = 0,
        [switch]$KeepStateColumn
    )
    if ($Width -le 0) { return @() }
    if ([string]::IsNullOrEmpty($State)) { $State = 'Running' }
    $overshoot = ($Total -gt 0 -and $Current -gt $Total)
    if ($overshoot) { $State = 'Error' }
    $keepState = ($State -notin @('Running', 'Final', 'No-op'))

    $statusChar = switch ($State) {
        { $_ -in @('Running', 'Waiting') } {
            if ($Total -le 0 -and $Style -eq 'Unicode') { [string][char]0x25A0 }
            else { $script:TpmProgressSpinner[[int]([Math]::Abs([long]$Tick) % $script:TpmProgressSpinner.Count)] }
        }
        'Pending' { if ($Style -eq 'Unicode') { [string][char]0x25CB } else { 'o' } }
        'Skipped' { '-' }
        'Stalled' { if ($Style -eq 'Unicode') { [string][char]0x26A0 } else { '!' } }
        'Final' { if ($Style -eq 'Unicode') { [string][char]0x2713 } else { ' ' } }
        'No-op' { if ($Style -eq 'Unicode') { [string][char]0x2713 } else { ' ' } }
        'Error' { if ($Style -eq 'Unicode') { [string][char]0x2717 } else { 'X' } }
        'Cancelled' { if ($Style -eq 'Unicode') { [string][char]0x26A0 } else { '!' } }
        'Incomplete' { if ($Style -eq 'Unicode') { [string][char]0x26A0 } else { '!' } }
        default { '?' }
    }
    if ($Width -eq 1) { return @(New-TpmProgressSegment -Text $statusChar -Role 'status') }
    $stateWord = switch ($State) {
        'Pending' { 'pending' }
        'Skipped' { 'skipped' }
        'Stalled' { 'stalled' }
        'Waiting' { 'still working' }
        'Final' { 'done' }
        'No-op' { 'done' }
        'Error' { 'FAILED' }
        'Cancelled' { 'canceled' }
        'Incomplete' { 'incomplete' }
        default { '' }
    }

    $label = Get-TpmProgressLabelText -Title $Title -Stage $Stage

    $percent = if ($State -in @('Pending', 'Skipped')) { -1 } elseif ($overshoot) { [Math]::Floor(([double]$Current * 100) / $Total) } else { Get-TpmProgressPercent -Current $Current -Total $Total -State $State }
    $percentText = if ($percent -ge 0) { ('[{0}%]' -f $percent).PadLeft([Math]::Max(6, $PercentWidth)) } else { ' ' * [Math]::Max(6, $PercentWidth) }
    $countText = if ($NoCount -or $State -eq 'Skipped') { '' } else { Format-TpmProgressCount -Current $Current -Total $Total -Unit $Unit }
    if ($countText -and $State -in @('Error', 'Incomplete', 'Cancelled', 'Stalled')) { $countText = '(!) ' + $countText }
    $countWidth = [Math]::Max($CountWidth, [Math]::Max($countText.Length, $(if ($Unit -eq 'Bytes') { 14 } else { 9 })))
    $elapsedText = Format-TpmProgressElapsed -ElapsedSeconds $ElapsedSeconds -Rate $Rate
    $timeWidth = [Math]::Max($TimeWidth, $elapsedText.Length)
    $tailText = if ($State -eq 'Running') {
        if ($EtaSeconds -ge 0 -and $Total -gt 0) { 'ETA ' + (Format-TpmProgressDuration -Seconds ([Math]::Ceiling($EtaSeconds))) }
        elseif ($Columns -notcontains 'Elapsed') { $elapsedText }
        else { '' }
    } else { $stateWord }
    $tailRole = if ($State -eq 'Running') { 'eta' } else { 'state' }
    $tailWidth = if ($DescriptionWidth -gt 0) { [Math]::Max(12, $tailText.Length) } else { [Math]::Max(11, $tailText.Length) }

    $statusWidth = if ($Columns -contains 'Spinner') { 2 } else { 0 }
    $labelMin = if ($Columns -contains 'Description') { 14 } else { 0 }
    $labelMax = if ($DescriptionWidth -gt 0) { [Math]::Max($labelMin, $DescriptionWidth) } else { $Width }
    $barMin = if ($Style -eq 'Unicode') { 8 } else { 10 }
    $barMax = 40

    # Fixed drop order, richest layout first. A closed non-success state keeps its state word and drops the
    # elapsed time, count, bar and percent before it.
    $layouts = if (($keepState -or $KeepStateColumn) -and ($percent -ge 0 -or $DescriptionWidth -gt 0)) {
        @('bar,pct,count,time,tail', 'bar,pct,count,tail', 'bar,pct,tail', 'pct,tail', 'tail', '')
    } elseif ($keepState) {
        @('bar,pct,count,time,tail', 'bar,pct,count,tail', 'bar,count,tail', 'count,tail', 'tail', '')
    } elseif ($percent -ge 0 -or $DescriptionWidth -gt 0) {
        @('bar,pct,count,time,tail', 'bar,pct,count,time', 'bar,pct,count', 'bar,pct', 'pct', '')
    } else {
        # Unknown total: the blank percent column is dropped first and the count (the only datum) outlives the bar.
        @('bar,pct,count,time,tail', 'bar,pct,count,time', 'bar,pct,count', 'bar,count', 'count', '')
    }
    $columnMin = @{ bar = $barMin; pct = $percentText.Length; count = $countWidth; time = $timeWidth; tail = $tailWidth }
    $columnNames = @{ Bar = 'bar'; Percentage = 'pct'; Count = 'count'; Elapsed = 'time'; Remaining = 'tail' }
    # Plain loops, not pipelines: this layout runs for every row of every frame.
    $configured = [System.Collections.Generic.List[string]]::new()
    foreach ($columnName in $Columns) {
        if ($columnNames.ContainsKey($columnName) -and -not $configured.Contains($columnNames[$columnName])) { [void]$configured.Add($columnNames[$columnName]) }
    }
    # Measure the configured grid once per refresh. Narrow widths drop optional data before the description.
    $layouts = @(foreach ($spec in $layouts) {
        $allowed = $spec.Split(',')
        (@(foreach ($columnName in $configured) { if ($columnName -in $allowed) { $columnName } }) -join ',')
    })

    $chosen = @()
    $chosenMin = $statusWidth + $labelMin
    $fits = $false
    foreach ($spec in $layouts) {
        $layoutColumns = @(foreach ($columnName in $spec.Split(',')) { if ($columnName) { $columnName } })
        $minimum = $statusWidth + $labelMin
        foreach ($column in $layoutColumns) { $minimum += 1 + $columnMin[$column] }
        if ($minimum -le $Width) { $chosen = $layoutColumns; $chosenMin = $minimum; $fits = $true; break }
    }
    if (-not $fits) { $chosen = @(); $chosenMin = $statusWidth + $labelMin }

    $extra = [Math]::Max(0, $Width - $chosenMin)
    $barWidth = 0
    if ($chosen -contains 'bar') {
        $grow = [Math]::Min($barMax - $barMin, [int][Math]::Floor($extra * 0.5))
        $barWidth = $barMin + $grow
        $extra -= $grow
    }
    $labelWidth = if ($fits) { $labelMin + $extra } else { [Math]::Max(0, $Width - $statusWidth) }
    # Text before glyphs: a label the default split would cut (a failure note, a waiting stage) first takes the blank
    # ETA cells of a running line that shows no ETA, then the bar's extra width (never below the bar's minimum). A
    # label that already fits keeps the aligned default layout; one that still does not fit takes whole columns (below).
    $labelNeed = if ($DescriptionWidth -gt 0) { $DescriptionWidth } else { ([string]$label).Length }
    if ($DescriptionWidth -le 0 -and $fits -and $labelWidth -lt $labelNeed -and ($chosen -contains 'tail') -and [string]::IsNullOrEmpty($tailText)) {
        $chosen = @(foreach ($columnName in $chosen) { if ($columnName -ne 'tail') { $columnName } })
        $labelWidth += 1 + $tailWidth
    }
    if ($fits -and $labelWidth -lt $labelNeed -and ($chosen -contains 'bar') -and $barWidth -gt $barMin) {
        $give = [Math]::Min($barWidth - $barMin, $labelNeed - $labelWidth)
        $barWidth -= $give
        $labelWidth += $give
    }
    # Label before secondary data (FIX27): a label that still does not fit takes whole columns before it is shortened.
    # The elapsed/rate column always gives way first. A plain line then gives up the count when a shown percent repeats
    # its progress, or the blank percent column of a row without a percent (unknown total, pending, skipped), but only
    # when that lets the whole label fit. A live frame gives up only the elapsed/rate column: its rows share every
    # width, so every row drops the same column and the rows stay aligned. The bar, a shown percent, a count that no
    # percent repeats and an ETA/state column with text always stay. The cells left are split as above (half of the
    # extra to the bar, then the label takes what it needs from the bar); a label that still does not fit is shortened.
    if ($fits -and $labelMin -gt 0 -and $labelWidth -lt $labelNeed) {
        $labelDrops = if ($DescriptionWidth -gt 0) { @('time') } elseif ($percent -lt 0) { @('time', 'pct') } elseif ($chosen -contains 'pct') { @('time', 'count') } else { @('time') }
        $minimum = $statusWidth + $labelMin
        foreach ($column in $chosen) { $minimum += 1 + $columnMin[$column] }
        $dropped = $false
        foreach ($drop in $labelDrops) {
            if ($chosen -notcontains $drop) { continue }
            $after = $minimum - 1 - $columnMin[$drop]
            if ($drop -ne 'time' -and $labelMin + $Width - $after -lt $labelNeed) { break }
            $chosen = @(foreach ($column in $chosen) { if ($column -ne $drop) { $column } })
            $minimum = $after
            $dropped = $true
            if ($labelMin + $Width - $minimum -ge $labelNeed) { break }
        }
        if ($dropped) {
            $extra = $Width - $minimum
            $barWidth = 0
            if ($chosen -contains 'bar') { $barWidth = $barMin + [Math]::Min($barMax - $barMin, [int][Math]::Floor($extra * 0.5)) }
            $labelWidth = $labelMin + $extra - [Math]::Max(0, $barWidth - $barMin)
            if ($labelWidth -lt $labelNeed -and $barWidth -gt $barMin) {
                $give = [Math]::Min($barWidth - $barMin, $labelNeed - $labelWidth)
                $barWidth -= $give
                $labelWidth += $give
            }
        }
    }
    if ($labelWidth -gt $labelMax) {
        $overflow = $labelWidth - $labelMax
        $labelWidth = $labelMax
        if ($chosen -contains 'bar') {
            $moreBar = [Math]::Min($barMax - $barWidth, $overflow)
            $barWidth += $moreBar
        }
    }

    $segments = [System.Collections.Generic.List[object]]::new()
    $statusRole = 'status'
    $spinnerFirst = ($Columns.Count -gt 0 -and $Columns[0] -eq 'Spinner')
    if ($statusWidth -gt 0 -and $spinnerFirst) { [void]$segments.Add([pscustomobject]@{ Text = ($statusChar + ' '); Role = $statusRole }) }
    $labelOut = $label
    if ($keepState -and $stateWord -and ($chosen -notcontains 'tail')) {
        # Narrow line: the state word leads the label and is never the part that gets cut. Only the label is shortened;
        # when even the word does not fit, its first letters are shown (never an ellipsis in place of the word).
        $rest = $labelWidth - $stateWord.Length - 1
        $labelOut = if ($rest -gt 0) {
            $stateWord + ' ' + (Limit-TpmProgressText -Text $label -Width $rest)
        } elseif ($labelWidth -ge $stateWord.Length) {
            $stateWord
        } else {
            $stateWord.Substring(0, [Math]::Max(0, $labelWidth))
        }
    }
    if ($Columns -contains 'Description') {
        [void]$segments.Add([pscustomobject]@{ Text = ((Limit-TpmProgressText -Text $labelOut -Width $labelWidth).PadLeft($labelWidth)); Role = 'label' })
    }
    foreach ($column in $chosen) {
        [void]$segments.Add([pscustomobject]@{ Text = ' '; Role = 'pad' })
        switch ($column) {
            'bar' { foreach ($part in @(New-TpmProgressBarSegments -Current $Current -Total $Total -BarWidth $barWidth -State $State -Tick $Tick -Style $Style)) { [void]$segments.Add($part) } }
            'pct' { [void]$segments.Add([pscustomobject]@{ Text = $percentText; Role = 'pct' }) }
            'count' { [void]$segments.Add([pscustomobject]@{ Text = $countText.PadLeft($countWidth); Role = 'count' }) }
            'time' { [void]$segments.Add([pscustomobject]@{ Text = $elapsedText.PadLeft($timeWidth); Role = 'time' }) }
            'tail' { [void]$segments.Add([pscustomobject]@{ Text = $tailText.PadRight($tailWidth); Role = $tailRole }) }
        }
    }
    if ($statusWidth -gt 0 -and -not $spinnerFirst) { [void]$segments.Add([pscustomobject]@{ Text = (' ' + $statusChar); Role = $statusRole }) }

    $used = 0
    foreach ($segment in $segments) { $used += $segment.Text.Length }
    if ($used -gt $Width) {
        # Defensive: the layout search guarantees a fit; never emit a line wider than the window.
        $flat = (($segments | ForEach-Object { $_.Text }) -join '').Substring(0, $Width)
        return @(New-TpmProgressSegment -Text $flat -Role 'label')
    }
    if ($used -lt $Width) { [void]$segments.Add([pscustomobject]@{ Text = (' ' * ($Width - $used)); Role = 'pad' }) }
    return $segments.ToArray()
}

function Format-TpmProgressLine {
    # Pure formatter; no console access. Returns exactly Width characters (space padded).
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [string]$Stage = '',
        [long]$Current = 0,
        [long]$Total = 0,
        [string]$State = 'Running',
        [double]$ElapsedSeconds = 0,
        [int]$Width = 79,
        [int]$Tick = 0,
        [ValidateSet('Ascii', 'Block', 'Unicode')][string]$Style = 'Ascii',
        [ValidateSet('Items', 'Bytes')][string]$Unit = 'Items',
        [double]$EtaSeconds = -1,
        [double]$Rate = -1,
        [switch]$NoCount,
        [ValidateSet('Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining', 'Spinner')][string[]]$Columns = (Get-TpmProgressDefaultColumns)
    )
    $segments = @(Format-TpmProgressSegments -Title $Title -Stage $Stage -Current $Current -Total $Total -State $State -ElapsedSeconds $ElapsedSeconds -EtaSeconds $EtaSeconds -Rate $Rate -Width $Width -Tick $Tick -Style $Style -Unit $Unit -NoCount:$NoCount -Columns $Columns)
    return (($segments | ForEach-Object { $_.Text }) -join '')
}

# ---------------------------------------------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------------------------------------------

function Get-TpmProgressSegmentColor {
    # Text and state cues use background-aware console colors; unknown backgrounds use the host foreground.
    param([string]$Role, [string]$State, [AllowNull()][AllowEmptyString()][string]$Background = 'Black')
    $palette = Get-TpmProgressPalette -Background $Background
    if ($null -eq $palette) { return $null }
    $stateColor = switch ($State) {
        'Error' { $palette.Error }
        'Cancelled' { $palette.Warn }
        'Stalled' { $palette.Warn }
        'Waiting' { $palette.Running }
        'Incomplete' { $palette.Warn }
        'Final' { $palette.Final }
        'No-op' { $palette.Final }
        'Pending' { $palette.Dim }
        'Skipped' { $palette.Dim }
        default { $palette.Running }
    }
    switch ($Role) {
        'fill' { return $stateColor }
        'status' { return $stateColor }
        'state' { return $stateColor }
        'mark' { return $stateColor }
        'rest' { return $palette.Track }
        'dots' { return $palette.Dim }
        'unknown' { if ($State -eq 'Pending') { return $palette.Dim } else { return $palette.Running } }
        'label' { return $palette.Label }
        'pct' { return $palette.Percent }
        'time' { return $palette.Time }
        'eta' { return $palette.Time }
        default { return $null }
    }
}

function ConvertTo-TpmProgressPaintSgr {
    # The SGR parameter of one bar paint: its RGB in true color, its console color's code in 16-color, '' for the host
    # foreground (a console color in the background's hue), $null when the row has no paint.
    param($Paint, [bool]$TrueColor)
    if ($null -eq $Paint) { return $null }
    if ($null -eq $Paint.Color) { return '' }
    if ($TrueColor) { return ('38;2;{0};{1};{2}' -f $Paint.Red, $Paint.Green, $Paint.Blue) }
    return [string]$script:TpmProgressSgrCodes[[string]$Paint.Color]
}

function ConvertTo-TpmProgressFrameText {
    # Pure: the complete text of one frame. Rows follow the prefix, joined by CR LF; -NewLine ends the text with CR LF
    # (closing frame). With ColorMode TrueColor or Vt16 every color change is a VT SGR sequence inside the same string: a role
    # color selects the console table entry the palette names, the fill and the bar-end mark use the row paint (gradient,
    # done, ended early, failed) as RGB or as its nearest console color, and a segment without a color uses the host
    # foreground (SGR 39). A row that changed the color ends with SGR 39. Console16 and None are plain text here (Console16 is
    # written run by run by Write-TpmProgressConsoleColorRows).
    param([object[]]$Rows, [string]$Prefix = '', [string]$ColorMode = 'None', [switch]$NewLine, [AllowNull()][AllowEmptyString()][string]$Background = 'Black')
    $esc = [string][char]27
    $useSgr = ($ColorMode -in @('Vt16', 'TrueColor'))
    $trueColor = ($ColorMode -eq 'TrueColor')
    $builder = [System.Text.StringBuilder]::new(256 * [Math]::Max(1, $Rows.Count))
    [void]$builder.Append($Prefix)
    $cache = $script:TpmProgressSgrCache
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $row = $Rows[$index]
        if ($index -gt 0) { [void]$builder.Append("`r`n") }
        # $null, not '': the first segment of every row states its color, so no row inherits another row's state.
        $active = $null
        $fillSgr = $null
        $markSgr = $null
        $keyPrefix = ''
        if ($useSgr) {
            $keyPrefix = [string]$Background + '|' + [string]$row.State + '|'
            $paint = Get-TpmProgressRowPaint -State $row.State -Percent $row.Percent -Background $Background
            if ($null -ne $paint) {
                $fillSgr = ConvertTo-TpmProgressPaintSgr -Paint $paint.Fill -TrueColor $trueColor
                $markSgr = ConvertTo-TpmProgressPaintSgr -Paint $paint.Mark -TrueColor $trueColor
            }
        }
        foreach ($segment in $row.Segments) {
            if ($useSgr) {
                if ($null -ne $fillSgr -and $segment.Role -eq 'fill') {
                    $sgr = $fillSgr
                } elseif ($null -ne $markSgr -and $segment.Role -eq 'mark') {
                    $sgr = $markSgr
                } else {
                    # One lookup per segment; the palette is computed once per background, state and role.
                    $key = $keyPrefix + [string]$segment.Role
                    $sgr = $cache[$key]
                    if ($null -eq $sgr) {
                        $name = Get-TpmProgressSegmentColor -Role $segment.Role -State $row.State -Background $Background
                        $sgr = if ($name) { [string]$script:TpmProgressSgrCodes[[string]$name] } else { '' }
                        $cache[$key] = $sgr
                    }
                }
                if ($sgr -cne $active) {
                    [void]$builder.Append($esc).Append('[').Append($(if ($sgr) { $sgr } else { '39' })).Append('m')
                    $active = $sgr
                }
            }
            [void]$builder.Append($segment.Text)
        }
        if ($active) { [void]$builder.Append($esc).Append('[39m') }
    }
    if ($NewLine) { [void]$builder.Append("`r`n") }
    return $builder.ToString()
}

function Get-TpmProgressSegmentConsoleColor {
    # The console color of one segment for Console16: the row paint for the fill and the bar-end mark, otherwise the palette
    # color of its role. $null is the host foreground.
    param($Segment, [string]$State, [AllowNull()][AllowEmptyString()][string]$Background, $Paint)
    if ($null -ne $Paint -and $Segment.Role -eq 'fill') { return $Paint.Fill.Color }
    if ($null -ne $Paint -and $Segment.Role -eq 'mark') { return $Paint.Mark.Color }
    return (Get-TpmProgressSegmentColor -Role $Segment.Role -State $State -Background $Background)
}

function Write-TpmProgressColorRun {
    # One run of text in one console color (Console16).
    param([AllowEmptyString()][string]$Text, [string]$Color)
    if ([string]::IsNullOrEmpty($Text)) { return }
    if ($Color) { Set-TpmProgressForeground -Color $Color }
    Write-TpmProgressRaw -Text $Text
}

function Write-TpmProgressConsoleColorRows {
    # Console16: a console without virtual terminal processing colors text only through its own foreground attribute, so the
    # frame is written as runs of one color (the foreground is set before each run). The text and its cells are the same as
    # the one-string frame; -Foreground is the host color used for segments without a color.
    param([object[]]$Rows, [string]$Prefix = '', [switch]$NewLine, [AllowNull()][AllowEmptyString()][string]$Background = 'Black', [AllowNull()]$Foreground = $null)
    Write-TpmProgressColorRun -Text $Prefix -Color ''
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $row = $Rows[$index]
        if ($index -gt 0) { Write-TpmProgressColorRun -Text "`r`n" -Color '' }
        $paint = Get-TpmProgressRowPaint -State $row.State -Percent $row.Percent -Background $Background
        $runColor = ''
        $run = ''
        foreach ($segment in $row.Segments) {
            $name = [string](Get-TpmProgressSegmentConsoleColor -Segment $segment -State $row.State -Background $Background -Paint $paint)
            if (-not $name) { $name = [string]$Foreground }
            if ($name -cne $runColor) {
                Write-TpmProgressColorRun -Text $run -Color $runColor
                $run = ''
                $runColor = $name
            }
            $run += $segment.Text
        }
        Write-TpmProgressColorRun -Text $run -Color $runColor
    }
    if ($NewLine) { Write-TpmProgressColorRun -Text "`r`n" -Color '' }
}

function Write-TpmProgressSegments {
    # Emits one whole frame. TrueColor, Vt16 and None: ONE console write (text from ConvertTo-TpmProgressFrameText).
    # Console16: runs of one color (Write-TpmProgressConsoleColorRows). A colored frame then puts back the console foreground
    # attribute read at operation start, the state the old per-segment attribute writes left behind.
    param([object[]]$Rows, [string]$Prefix = '', [string]$ColorMode = 'None', [switch]$NewLine, [AllowNull()][AllowEmptyString()][string]$Background = 'Black', [AllowNull()]$Foreground = $null)
    try {
        if ($ColorMode -eq 'Console16') {
            Write-TpmProgressConsoleColorRows -Rows $Rows -Prefix $Prefix -NewLine:$NewLine -Background $Background -Foreground $Foreground
        } else {
            Write-TpmProgressRaw -Text (ConvertTo-TpmProgressFrameText -Rows $Rows -Prefix $Prefix -ColorMode $ColorMode -NewLine:$NewLine -Background $Background)
        }
    } finally { if ($ColorMode -ne 'None' -and $null -ne $Foreground) { Set-TpmProgressForeground -Color $Foreground } }
}

function Get-TpmProgressElapsed {
    param($Op, [string]$State, [datetime]$Now)
    if ($State -eq 'Skipped') { return [double]0 }
    $clock = if ($null -ne $Op.PauseStarted) { $Op.PauseStarted } else { $Now }
    if ($null -ne $Op.Finished) { $clock = $Op.Finished }
    return $(if ($Op.Group -and $State -notin @('Running', 'Waiting', 'Stalled')) { ($clock - $Op.Started).TotalSeconds } else { ($clock - $Op.StageStarted).TotalSeconds })
}

function Get-TpmProgressTaskRate {
    # Units finished per second since the stage began, from the real count and the real elapsed time. -1 (not shown)
    # when it cannot be measured: under one second elapsed, nothing finished yet, or a closing line that has no count.
    param($Task, [double]$ElapsedSeconds, [string]$State = '')
    # A skipped step never ran: 0.00/s over 0.0 s.
    if ($State -eq 'Skipped') { return [double]0 }
    if ([bool]$Task.NoCount -or $ElapsedSeconds -lt 1.0) { return [double]-1 }
    $finished = [long]$Task.Current - [long]$Task.StageFirstCurrent
    if ($finished -le 0) { return [double]-1 }
    return [double]($finished / $ElapsedSeconds)
}

function Get-TpmProgressLineSegments {
    param($Op, [string]$State, [datetime]$Now, [int]$Width, [string]$Style, [int]$DescriptionWidth = 0, [int]$CountWidth = 0, [int]$PercentWidth = 0, [int]$TimeWidth = 0, [switch]$KeepStateColumn)
    $stageElapsed = Get-TpmProgressElapsed -Op $Op -State $State -Now $Now
    $eta = [double]-1
    if ($State -eq 'Running' -and -not [bool]$Op.EtaHidden) {
        $eta = Get-TpmProgressEta -Current $Op.Current -Total $Op.Total -StartCurrent $Op.StageFirstCurrent -ElapsedSeconds $stageElapsed -Samples $Op.StageSamples -SmoothedRate $Op.SmoothedRate
    }
    return @(Format-TpmProgressSegments -Title $Op.Title -Stage $Op.Stage -Current $Op.Current -Total $Op.Total -State $State -ElapsedSeconds $stageElapsed -EtaSeconds $eta -Rate (Get-TpmProgressTaskRate -Task $Op -ElapsedSeconds $stageElapsed -State $State) -Width $Width -Tick $Op.Tick -Style $Style -Unit $Op.Unit -NoCount:([bool]$Op.NoCount) -Columns $Op.Columns -DescriptionWidth $DescriptionWidth -CountWidth $CountWidth -PercentWidth $PercentWidth -TimeWidth $TimeWidth -KeepStateColumn:$KeepStateColumn)
}

function Write-TpmProgressPlainFrame {
    param($Op, [string]$State, [datetime]$Now, [switch]$Force)
    $decile = -1
    if ($Op.Total -gt 0) { $decile = [int][Math]::Floor(([Math]::Min([long]$Op.Current, [long]$Op.Total) * 10.0) / $Op.Total) }
    $since = ($Now - $Op.LastPlainWrite).TotalSeconds
    $stageChanged = ($Op.Stage -ne $Op.LastPlainStage)
    $due = $Force -or $Op.PlainForce -or ($decile -ne $Op.LastPlainDecile) -or ($since -ge 5) -or ($stageChanged -and $since -ge 1)
    if (-not $due) { return }
    $width = Get-TpmProgressWidth -Requested $Op.WidthRequested
    foreach ($row in @(Get-TpmProgressRows -Op $Op -State $State)) {
        $segments = @(Get-TpmProgressLineSegments -Op $row.Task -State $row.State -Now $Now -Width $width -Style 'Ascii')
        Write-TpmProgressPlainLine -Text ((($segments | ForEach-Object { $_.Text }) -join '').TrimEnd())
    }
    $Op.LastPlainStage = $Op.Stage
    $Op.LastPlainDecile = $decile
    $Op.LastPlainWrite = $Now
    $Op.PlainForce = $false
}

function Get-TpmProgressRowSpan {
    param([int]$Cells, [int]$BufferWidth, [switch]$Last)
    if ($Last) { return (1 + [int][Math]::Floor($Cells / [double]$BufferWidth)) }
    # Reflow consumes an exact-width non-cursor row once; its hard newline does not add an empty continuation.
    return [Math]::Max(1, [int][Math]::Ceiling($Cells / [double]$BufferWidth))
}

function Resolve-TpmProgressFrameTop {
    # Track rendered cells, NOT CursorLeft: an exact wrap leaves CursorLeft=0, not a zero-cell frame.
    # Reflow is applied to every logical row, including the last row's end offset.
    param($Op, $Position, [int]$BufferWidth, [int]$WindowHeight)
    if (-not $Op.HasFrame -or $null -eq $Position -or $null -eq $Op.CursorLeft -or $null -eq $Op.FrameTop) { return -1 }
    $Op.Clipped = $false
    if ($Position.Left -eq $Op.CursorLeft -and $Position.Top -eq $Op.CursorTop -and $BufferWidth -eq $Op.FrameBufferWidth) { return [int]$Op.FrameTop }
    if ($BufferWidth -le 0 -or ($BufferWidth -eq $Op.FrameBufferWidth -and $WindowHeight -eq $Op.FrameWindowHeight)) { return -1 }
    $lastCells = [int]$Op.RowCells[$Op.RowCells.Count - 1]
    $reflow = ($BufferWidth -ne $Op.FrameBufferWidth)
    $expectedLeft = if ($reflow) { $lastCells % $BufferWidth } else { $Op.CursorLeft }
    $unpredicted = $false
    if ($Position.Left -ne $expectedLeft) {
        # Classic hosts may crop instead of reflowing, clamping the cursor on the SAME buffer row.
        # In that mode only cells still on those rows are ours; never erase imagined continuation rows.
        $clampedLeft = [Math]::Min([int]$Op.CursorLeft, $BufferWidth - 1)
        if ($reflow -and $Position.Left -eq $clampedLeft -and $Position.Top -eq $Op.CursorTop) {
            $Op.Clipped = $true
            return [int]$Op.FrameTop
        }
        # FIX40: the buffer width changed and the host left the cursor in a column the reflow model did not predict
        # (Windows Terminal / ConPTY resize repaints differ from classic conhost). The column is tolerated ONLY when the
        # cursor ROW is exactly where reflowing the frame we drew puts it (old cursor row plus the rows the frame gained
        # at the new width, checked below). Output written after the frame moves the cursor to another row, so it never
        # qualifies: a cursor that moved with no size change, or with a row the model cannot account for, is foreign
        # output and is never erased.
        if (-not $reflow -or $Position.Left -ge $BufferWidth) { return -1 }
        $unpredicted = $true
    }
    $rowsAbove = 0
    for ($index = 0; $index -lt $Op.RowCells.Count; $index++) {
        $rowsAbove += Get-TpmProgressRowSpan -Cells $Op.RowCells[$index] -BufferWidth $BufferWidth -Last:($index -eq $Op.RowCells.Count - 1)
    }
    if ($unpredicted -and $Position.Top -ne ([int]$Op.CursorTop + $rowsAbove - [int]$Op.FrameRows)) { return -1 }
    $top = $Position.Top - $rowsAbove + 1
    if ($top -lt 0) { return -1 }
    return $top
}

function Clear-TpmProgressFrame {
    param($Frame, [int]$Top, [int]$BufferWidth)
    if ($Top -lt 0 -or $BufferWidth -le 0) { return $false }
    $row = $Top
    for ($index = 0; $index -lt $Frame.RowCells.Count; $index++) {
        $cells = $Frame.RowCells[$index]
        $count = if ($Frame.Clipped) { [Math]::Min($cells, $BufferWidth) } else { $cells }
        if (-not (Clear-TpmProgressCells -Top $row -Count $count)) { return $false }
        $row += $(if ($Frame.Clipped) { 1 } else { Get-TpmProgressRowSpan -Cells $cells -BufferWidth $BufferWidth -Last:($index -eq $Frame.RowCells.Count - 1) })
    }
    return (Set-TpmProgressCursor -Left 0 -Top $Top)
}

function Find-TpmProgressMovedRegion {
    # FIX45: the top row of the previous frame when the cursor was moved INTO it (SetCursorPosition by a caller that has
    # not written yet), or -1. Proof, not a guess: same buffer width and window height as when it was drawn, the cursor
    # inside the cells of one of its rows (a cursor past them may follow foreign text written after the bar), and every
    # cell of every row read back holds exactly the text that frame wrote there. Any difference (foreign text, a scroll,
    # a reflow, an unreadable console) returns -1 and nothing is erased.
    param($Frame, $Position, [int]$BufferWidth, [int]$WindowHeight)
    if (-not $Frame.HasFrame -or $Frame.Overflow -or $Frame.Clipped -or $null -eq $Position -or $null -eq $Frame.FrameTop) { return -1 }
    if ($BufferWidth -lt 2 -or $BufferWidth -ne [int]$Frame.FrameBufferWidth -or $WindowHeight -ne [int]$Frame.FrameWindowHeight) { return -1 }
    $cells = @($Frame.RowCells)
    $texts = @($Frame.RowTexts)
    if ($cells.Count -eq 0 -or $texts.Count -ne $cells.Count) { return -1 }
    $top = [int]$Frame.FrameTop
    if ($Position.Top -lt $top -or $Position.Top -gt ($top + $cells.Count - 1)) { return -1 }
    if ([int]$Position.Left -lt 0 -or [int]$Position.Left -ge [int]$cells[[int]$Position.Top - $top]) { return -1 }
    $verified = 0
    for ($index = 0; $index -lt $cells.Count; $index++) {
        $count = [int]$cells[$index]
        $text = [string]$texts[$index]
        if ($count -le 0) { continue }
        if ($count -gt $text.Length -or $count -ge $BufferWidth) { return -1 }
        $read = Read-TpmProgressCells -Top ($top + $index) -Count $count
        if ($null -eq $read -or -not [string]::Equals([string]$read, $text.Substring(0, $count), [System.StringComparison]::Ordinal)) { return -1 }
        $verified++
    }
    if ($verified -eq 0) { return -1 }
    return $top
}

function Clear-TpmProgressMovedRegion {
    # FIX45: blanks a region found by Find-TpmProgressMovedRegion (one buffer row per frame row) and puts the cursor back
    # where the caller had moved it, so its text still starts there.
    param($Frame, [int]$Top, $Position)
    $cleared = $true
    for ($index = 0; $cleared -and $index -lt $Frame.RowCells.Count; $index++) {
        $cleared = Clear-TpmProgressCells -Top ($Top + $index) -Count ([int]$Frame.RowCells[$index])
    }
    $restored = Set-TpmProgressCursor -Left ([int]$Position.Left) -Top ([int]$Position.Top)
    return ($cleared -and $restored)
}

function Get-TpmProgressWideRowSpan {
    # FIX45: replays one written frame row on a console row of BufferWidth cells with every non-ASCII glyph two cells wide
    # (a glyph that does not fit in the last cell moves to the next row, as a console does). Returns the rows it takes,
    # the column it ends in and its glyph count, or $null when it ends exactly at a row end (whether the host then uses
    # another row differs between hosts, so such a frame is not measured).
    param([string]$Text, [int]$BufferWidth)
    $left = 0
    $rows = 1
    $glyphs = 0
    foreach ($ch in $Text.ToCharArray()) {
        $cells = 1
        if ([int]$ch -gt 0x7E) { $cells = 2; $glyphs++ }
        if ($left + $cells -gt $BufferWidth) { $rows++; $left = 0 }
        $left += $cells
        if ($left -ge $BufferWidth) { $rows++; $left = 0 }
    }
    if ($left -eq 0 -and $Text.Length -gt 0) { return $null }
    return [pscustomobject]@{ Rows = $rows; Left = $left; Glyphs = $glyphs }
}

function Measure-TpmProgressOverflow {
    # FIX45: compares where the cursor ended after a live frame write with where the composed cells put it. Every frame
    # row is composed to exactly its cell count and below the buffer width, so a correct write ends on the last row at
    # column (last row cells). Returns $null when it did, and when the check cannot be made: no cursor, the buffer width
    # changed during the write (a resize, handled by the FIX40 reflow model), the cursor did not move at all (a surface
    # that does not track it). A different end is recorded ONLY when the frame's own glyphs explain it exactly: replayed
    # with every non-ASCII glyph two cells wide (Get-TpmProgressWideRowSpan), the frame ends in the cursor's column and
    # takes at least the rows the cursor moved. Anything else (foreign output or a cursor moved by another thread during
    # the write) is not recorded, so it is never erased later. Returns PhysicalRows (rows the frame took, from the replay,
    # so also right when the write scrolled the buffer) and Cells (one pseudo row from its top row to the cursor, for
    # Clear-TpmProgressFrame and Resolve-TpmProgressFrameTop).
    param([object[]]$Composed, $Before, $After, [int]$StartTop, [int]$BufferWidth, [int]$MeasuredBufferWidth)
    if ($null -eq $After -or $null -eq $Before -or $null -eq $Composed -or $Composed.Count -eq 0) { return $null }
    if ($BufferWidth -lt 2 -or $MeasuredBufferWidth -ne $BufferWidth) { return $null }
    if ([int]$After.Left -eq [int]$Before.Left -and [int]$After.Top -eq [int]$Before.Top) { return $null }
    $rows = $Composed.Count
    $left = [int]$After.Left
    $lastCells = [int]$Composed[$rows - 1].Cells
    # A frame that scrolled the buffer ends on its last row, never below it.
    $expectedTop = if ($StartTop -ge 0) { $StartTop + $rows - 1 } else { -1 }
    if ($left -eq ($lastCells % $BufferWidth) -and ($expectedTop -lt 0 -or [int]$After.Top -le $expectedTop)) { return $null }
    $physicalRows = 0
    $glyphs = 0
    $span = $null
    foreach ($row in $Composed) {
        $span = Get-TpmProgressWideRowSpan -Text ([string]$row.Text) -BufferWidth $BufferWidth
        if ($null -eq $span) { return $null }
        $physicalRows += $span.Rows
        $glyphs += $span.Glyphs
    }
    if ($glyphs -eq 0 -or $span.Left -ne $left) { return $null }
    if ($StartTop -ge 0 -and ([int]$After.Top - $StartTop + 1) -gt $physicalRows) { return $null }
    return [pscustomobject]@{ PhysicalRows = $physicalRows; Cells = (($physicalRows - 1) * $BufferWidth + $left) }
}

function Register-TpmProgressOverflow {
    # FIX45 (caller holds the Gate): records a frame whose glyphs took two cells each as ONE region from its top row to the
    # cursor, so the next redraw or lift erases every row it took (never an in-place overwrite, which would leave the
    # wrapped remainder on screen), and makes the operation draw ASCII glyphs from the next frame on.
    param($Live, $Frame, $Overflow, $After)
    $Frame.Overflow = $true
    $Frame.RowCells = @([int]$Overflow.Cells)
    $Frame.RowTexts = @()
    $Frame.FrameRows = [int]$Overflow.PhysicalRows
    $Frame.FrameTop = [Math]::Max(0, [int]$After.Top - [int]$Overflow.PhysicalRows + 1)
    $Live['ForceAscii'] = $true
}

function Get-TpmProgressRows {
    param($Op, [string]$State)
    $rows = New-Object System.Collections.Generic.List[object]
    # The compatibility operation is the first task. Additional task IDs never change existing nesting semantics.
    if (-not $Op.HideCompleted -or $null -eq $Op.Finished) {
        [void]$rows.Add([pscustomobject]@{ Task = $Op; State = $State })
    }
    foreach ($task in $Op.Tasks) {
        if ($Op.HideCompleted -and $task.State -notin @('Running', 'Stalled', 'Pending')) { continue }
        [void]$rows.Add([pscustomobject]@{ Task = $task; State = $task.State })
    }
    return $rows.ToArray()
}

function Get-TpmProgressFrameRows {
    # Lays out every row of one frame at one width: the segments, state and percent the writer colors, and the cells
    # each row owns on screen (conhost trims padding on non-cursor rows during reflow; only the last, cursor row
    # keeps its full width).
    param([object[]]$Rows, [datetime]$Now, [int]$Width, [string]$Style, [int]$DescriptionWidth, [int]$CountWidth, [int]$PercentWidth, [int]$TimeWidth, [bool]$KeepStateColumn)
    $composed = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $row = $Rows[$index]
        $task = $row.Task
        $segments = @(Get-TpmProgressLineSegments -Op $task -State $row.State -Now $Now -Width $Width -Style $Style -DescriptionWidth $DescriptionWidth -CountWidth $CountWidth -PercentWidth $PercentWidth -TimeWidth $TimeWidth -KeepStateColumn:$KeepStateColumn)
        # The plain row text is kept (FIX45): the lift reads cells back against it before it erases a moved-to region.
        $text = -join @(foreach ($segment in $segments) { $segment.Text })
        $cells = $Width
        if ($index -lt $Rows.Count - 1) { $cells = $text.TrimEnd().Length }
        [void]$composed.Add([pscustomobject]@{
            Segments = $segments
            State = $(if ($task.Total -gt 0 -and $task.Current -gt $task.Total) { 'Error' } else { $row.State })
            Percent = $(if ($task.Total -gt 0) { 100.0 * $task.Current / $task.Total } else { -1 })
            Cells = $cells
            Text = $text
        })
    }
    return ,$composed.ToArray()
}

function Get-TpmProgressStableGeometry {
    # One consistent console sample (FIX40): buffer width, window height and cursor. A resize reflows the buffer and moves
    # the cursor together, so a sample counts only when the width and height read before the cursor equal the ones read
    # after it (three tries; the last sample is used when the size keeps changing). A failing query (0 / $null) never
    # throws: the previous size passed in takes its place.
    param([int]$FallbackWidth = 0, [int]$FallbackHeight = 0)
    $width = 0
    $height = 0
    $cursor = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $width = Get-TpmProgressBufferWidth
        $height = Get-TpmProgressWindowHeight
        $cursor = Get-TpmProgressCursor
        if ((Get-TpmProgressBufferWidth) -eq $width -and (Get-TpmProgressWindowHeight) -eq $height) { break }
    }
    if ($width -lt 2) { $width = $FallbackWidth }
    if ($height -le 0) { $height = $FallbackHeight }
    return [pscustomobject]@{ BufferWidth = [int]$width; WindowHeight = [int]$height; Cursor = $cursor }
}

function Clear-TpmProgressReflowedRemains {
    # FIX52 (#384): blanks the rows directly above Top that still show the beginning of a ONE-row frame the console
    # reflowed while it was being overwritten in place (see Write-TpmProgressLiveFrame). That row ended where the cursor
    # stood, so at BufferWidth it took floor(length / BufferWidth) rows above the row the carriage return went to, and row
    # Top - d holds its slice number (above - d). Every one of those rows is read back first and must equal its slice
    # exactly (trailing blanks ignored; a blank slice of the frame's own padding must read blank); only when all of them
    # do are the non-blank ones blanked. Anything else (a multi-row frame, foreign text, an unreadable console) blanks
    # nothing. Rows above the top of the buffer (scrolled away) end the check. Never moves the cursor itself. Returns the
    # number of rows blanked.
    param([string[]]$OldTexts = @(), [int]$Top, [int]$BufferWidth)
    if ($null -eq $OldTexts -or $OldTexts.Count -ne 1 -or $Top -le 0 -or $BufferWidth -lt 2) { return 0 }
    $text = [string]$OldTexts[0]
    $above = [int][Math]::Floor($text.Length / [double]$BufferWidth)
    $owned = New-Object System.Collections.Generic.List[object]
    for ($distance = 1; $distance -le $above; $distance++) {
        $row = $Top - $distance
        if ($row -lt 0) { break }
        $offset = ($above - $distance) * $BufferWidth
        $slice = $text.Substring($offset, [Math]::Min($BufferWidth, $text.Length - $offset)).TrimEnd()
        $read = Read-TpmProgressCells -Top $row -Count $BufferWidth
        if ($null -eq $read) { return 0 }
        $shown = ([string]$read).TrimEnd()
        if (-not [string]::Equals($shown, $slice, [System.StringComparison]::Ordinal)) { return 0 }
        if ($shown.Length -gt 0) { [void]$owned.Add([pscustomobject]@{ Row = $row; Count = $shown.Length }) }
    }
    $cleared = 0
    foreach ($item in $owned) {
        if (-not (Clear-TpmProgressCells -Top $item.Row -Count $item.Count)) { break }
        $cleared++
    }
    return $cleared
}

function Repair-TpmProgressClosingFrame {
    # FIX52 (#384): the closing rows are the last thing an operation writes, so no later frame corrects them. When the
    # window became narrower while they were composed or written, the console wrapped them onto more rows than they were
    # composed for. They are found again from the cursor (every closing row ends with CR LF, so the cursor is at column 0
    # of the row after the last one; each row then spans its cells divided by the new buffer width, counted with and
    # without its trailing blanks because hosts reflow those differently), PROVEN by reading every row back, erased and
    # written once more at the new width (at most two attempts). -OverwrittenTexts (the live frame the closing rows were
    # written over in place) are looked for directly above the closing rows once they are found and blanked when proven
    # (Clear-TpmProgressReflowedRemains), also when the closing rows themselves still fit. Anything not proven (the cursor
    # not at column 0, foreign text, an unreadable console) leaves the screen as it is: nothing is erased that the frame
    # cannot be shown to own.
    param($Op, [hashtable]$Layout, [object[]]$Composed, [int]$Width, [int]$BufferWidth, [string[]]$OverwrittenTexts = @())
    $live = $Op.Live
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $bufferAfter = Get-TpmProgressBufferWidth
        if ($bufferAfter -lt 2) { return }
        $widthAfter = [Math]::Min((Get-TpmProgressWidth -Requested $Op.WidthRequested -Live), $bufferAfter - 1)
        if ($bufferAfter -eq $BufferWidth -and $widthAfter -ge $Width) { return }
        $texts = @(foreach ($row in $Composed) { ([string]$row.Text).TrimEnd() })
        $longest = 0
        foreach ($text in $texts) { $longest = [Math]::Max($longest, $text.Length) }
        # Rewrite only when a visible cell no longer fits in one row of the new width.
        $rewrite = ($longest -gt $widthAfter)
        $remains = ($bufferAfter -ne $BufferWidth -and $null -ne $OverwrittenTexts -and $OverwrittenTexts.Count -gt 0)
        if (-not $rewrite -and -not $remains) { return }
        $cursor = Get-TpmProgressCursor
        if ($null -eq $cursor -or [int]$cursor.Left -ne 0) { return }
        $top = -1
        $spans = @()
        foreach ($counted in @('Visible', 'Written')) {
            $candidateSpans = @(foreach ($row in $Composed) {
                    $cells = if ($counted -eq 'Visible') { ([string]$row.Text).TrimEnd().Length } else { ([string]$row.Text).Length }
                    [Math]::Max(1, [int][Math]::Ceiling($cells / [double]$bufferAfter))
                })
            $candidate = [int]$cursor.Top
            foreach ($span in $candidateSpans) { $candidate -= $span }
            if ($candidate -lt 0) { continue }
            $row = $candidate
            $verified = 0
            $same = $true
            for ($index = 0; $same -and $index -lt $texts.Count; $index++) {
                if ($texts[$index].Length -gt 0) {
                    $read = Read-TpmProgressCells -Top $row -Count $texts[$index].Length
                    $same = ($null -ne $read -and [string]::Equals([string]$read, $texts[$index], [System.StringComparison]::Ordinal))
                    if ($same) { $verified++ }
                }
                $row += $candidateSpans[$index]
            }
            if ($same -and $verified -gt 0) { $top = $candidate; $spans = $candidateSpans; break }
        }
        if ($top -lt 0) { return }
        if ($remains) {
            [void](Clear-TpmProgressReflowedRemains -OldTexts $OverwrittenTexts -Top $top -BufferWidth $bufferAfter)
            $OverwrittenTexts = @()
        }
        if (-not $rewrite) {
            [void](Set-TpmProgressCursor -Left 0 -Top ([int]$cursor.Top))
            return
        }
        $row = $top
        for ($index = 0; $index -lt $texts.Count; $index++) {
            if (-not (Clear-TpmProgressCells -Top $row -Count $texts[$index].Length)) { return }
            $row += $spans[$index]
        }
        if (-not (Set-TpmProgressCursor -Left 0 -Top $top)) { return }
        $Width = $widthAfter
        $BufferWidth = $bufferAfter
        $Composed = Get-TpmProgressFrameRows @Layout -Width $Width
        Write-TpmProgressSegments -Rows $Composed -Prefix "`r" -ColorMode $Op.ColorMode -Background $Op.Background -NewLine -Foreground $live.Foreground
    }
}


function Write-TpmProgressLiveFrame {
    # Every row is laid out first and the whole frame (rows and colors) is emitted with ONE console write; geometry is
    # re-read once immediately before that write.
    # -NoAppend (refresh runspace only): when the previous frame cannot be found where it was left (foreign output,
    # for example the shell prompt after the owner returned, or text written without Suspend-TpmProgressOutput), do
    # not append a new live region from the background. Live.Parked is set instead and the next owner call redraws.
    param($Op, [string]$State, [datetime]$Now, [switch]$Closing, [switch]$NoAppend)
    $live = $Op.Live
    if ($live.PromptDepth -gt 0 -or $live.OutputDepth -gt 0) { return }
    $costStart = Get-TpmProgressTimestamp
    $frame = $live.Frame
    $rows = @(Get-TpmProgressRows -Op $Op -State $State)
    $height = Get-TpmProgressWindowHeight
    if ($height -le 0 -and $frame.HasFrame) { $height = [int]$frame.FrameWindowHeight }
    # Never scroll away our own origin if there are more tasks than visible console rows.
    if (-not $Closing -and $height -gt 1 -and $rows.Count -ge $height) { $rows = @($rows | Select-Object -Last ($height - 1)) }
    $width = Get-TpmProgressWidth -Requested $Op.WidthRequested -Live
    $bufferWidth = Get-TpmProgressBufferWidth
    if ($bufferWidth -lt 2 -and $frame.HasFrame -and $frame.FrameBufferWidth -ge 2) { $bufferWidth = [int]$frame.FrameBufferWidth }
    if ($bufferWidth -lt 2) { return }
    if ($bufferWidth -gt 0) { $width = [Math]::Min($width, [Math]::Max(1, $bufferWidth - 1)) }
    # FIX45: a glyph this host measurably drew two cells wide made the operation fall back to ASCII glyphs.
    $style = if ([bool]$live['ForceAscii']) { 'Ascii' } else { [string]$Op.Style }
    # FIX40: a size change since the last drawn frame (width or height) is checked on every frame attempt, which the frame
    # interval caps at 4 per second. A width change erases the old region as a whole (rows counted at the NEW width, see
    # Resolve-TpmProgressFrameTop) and draws it again at the new size. A height-only change keeps the same grid and is
    # drawn over the old region in place, never erased first (FIX24 decision, restored by FIX40B); it only counts as a resize.
    $heightChanged = ($frame.HasFrame -and $height -ne $frame.FrameWindowHeight)
    if ($frame.HasFrame -and ($heightChanged -or $bufferWidth -ne $frame.FrameBufferWidth)) { $frame.Resizes++ }
    $descriptionWidth = 0
    $countWidth = 0
    $percentWidth = 6
    $timeWidth = 5
    $keepStateColumn = $false
    foreach ($row in $rows) {
        $task = $row.Task
        $description = Get-TpmProgressLabelText -Title $task.Title -Stage $task.Stage
        $descriptionWidth = [Math]::Max($descriptionWidth, $description.Length)
        $countLength = (Format-TpmProgressCount -Current $task.Current -Total $task.Total -Unit $task.Unit).Length
        if ($row.State -in @('Error', 'Incomplete', 'Cancelled', 'Stalled') -or ($task.Total -gt 0 -and $task.Current -gt $task.Total)) { $countLength += 4 }
        $countWidth = [Math]::Max($countWidth, [Math]::Max($(if ($task.Unit -eq 'Bytes') { 14 } else { 9 }), $countLength))
        if ($task.Total -gt 0 -and $task.Current -gt $task.Total) {
            $overshootText = '[{0}%]' -f [Math]::Floor(([double]$task.Current * 100) / $task.Total)
            $percentWidth = [Math]::Max($percentWidth, $overshootText.Length)
        }
        $elapsed = [Math]::Max([double]0, (Get-TpmProgressElapsed -Op $task -State $row.State -Now $Now))
        $timeText = Format-TpmProgressElapsed -ElapsedSeconds $elapsed -Rate (Get-TpmProgressTaskRate -Task $task -ElapsedSeconds $elapsed -State $row.State)
        $timeWidth = [Math]::Max($timeWidth, $timeText.Length)
        if ($row.State -notin @('Running', 'Final', 'No-op') -or ($task.Total -gt 0 -and $task.Current -gt $task.Total)) { $keepStateColumn = $true }
    }
    $prefix = "`r"
    $position = Get-TpmProgressCursor
    $top = -1
    # True only while the previous frame is being overwritten in place without having been erased first.
    $inPlace = $false
    # FIX45: the buffer row the first frame row is written to (-1 unknown) and the cursor just before the write, for the
    # overflow check after the write.
    $startTop = -1
    $preWrite = $position
    if ($frame.HasFrame) {
        $top = Resolve-TpmProgressFrameTop -Op $frame -Position $position -BufferWidth $bufferWidth -WindowHeight $height
        # FIX45: an owner call also finds its region when a caller only moved the cursor into it (its cells read back
        # unchanged). The background writer never does: it parks, because that caller is about to write there.
        if ($top -lt 0 -and -not $NoAppend) {
            $top = Find-TpmProgressMovedRegion -Frame $frame -Position $position -BufferWidth $bufferWidth -WindowHeight $height
        }
        # Same width and buffer width (FIX24): the frame is written over the old one and never erased first, so no row is
        # ever blank or half drawn on screen, also when rows are added or removed, and also after a height-only change.
        # Every row is exactly $width cells and one buffer row, so each kept row covers its old cells and added rows go
        # below; only rows the new frame no longer has are blanked, before the write. A changed width erases the whole
        # old frame first (below), and so does a frame that took more rows than composed (FIX45 overflow).
        $sameGrid = ($top -ge 0 -and -not $frame.Overflow -and $width -eq $frame.FrameWidth -and $bufferWidth -eq $frame.FrameBufferWidth)
        $placed = $false
        if ($sameGrid) {
            $placed = $true
            for ($index = $rows.Count; $placed -and $index -lt $frame.RowCells.Count; $index++) {
                $placed = Clear-TpmProgressCells -Top ($top + $index) -Count ([int]$frame.RowCells[$index])
            }
            # The cursor is still on the old frame's last row: a one-row frame needs only the carriage return.
            if ($placed) { $placed = ($frame.RowCells.Count -eq 1 -or (Set-TpmProgressCursor -Left 0 -Top $top)) }
            if ($placed -and $frame.RowCells.Count -gt 1) { $preWrite = [pscustomobject]@{ Left = 0; Top = $top } }
            $inPlace = $placed
        } elseif ($top -ge 0) {
            $placed = Clear-TpmProgressFrame -Frame $frame -Top $top -BufferWidth $bufferWidth
            if ($placed) { $preWrite = [pscustomobject]@{ Left = 0; Top = $top } }
        }
        if ($placed) { $startTop = $top }
        if (-not $placed) {
            if ($NoAppend) { $live.Parked = $true; return }
            # A foreign write is not ours to erase. Only this case may append a fresh live region.
            if ($null -eq $position -or $position.Left -gt 0) { $prefix = "`n`r" }
            $top = -1
        }
    } elseif ($null -eq $position -or $position.Left -gt 0) {
        if ($NoAppend) { $live.Parked = $true; return }
        if ($null -ne $position) { $prefix = "`n`r" }
    }
    if ($startTop -lt 0 -and $null -ne $position) { $startTop = [int]$position.Top + $(if ($prefix -eq "`r") { 0 } else { 1 }) }
    if ($rows.Count -eq 0 -or ($Closing -and $Op.AutoClear)) {
        if ($frame.HasFrame -and $top -ge 0) { [void](Clear-TpmProgressFrame -Frame $frame -Top $top -BufferWidth $bufferWidth) }
        $frame.HasFrame = $false
        return
    }
    $layout = @{
        Rows = $rows; Now = $Now; Style = $style; DescriptionWidth = $descriptionWidth; CountWidth = $countWidth
        PercentWidth = $percentWidth; TimeWidth = $timeWidth; KeepStateColumn = $keepStateColumn
    }
    $composed = Get-TpmProgressFrameRows @layout -Width $width
    # Re-check geometry after layout, immediately before emitting any cells.
    $currentWidth = Get-TpmProgressWidth -Requested $Op.WidthRequested -Live
    $currentBuffer = Get-TpmProgressBufferWidth
    if ($currentBuffer -lt 2) { $currentBuffer = $bufferWidth }
    $currentWidth = [Math]::Min($currentWidth, [Math]::Max(1, $currentBuffer - 1))
    if ($currentWidth -lt $width) {
        $narrow = $true
        if ($inPlace -and $currentBuffer -eq $bufferWidth) {
            # The window narrowed after the in-place decision. A narrower rewrite would leave the old wider cells on
            # screen and unowned, so erase every cell of the old frame first (the cursor ends at its top) and draw the
            # whole frame there at the new width. Same buffer width: each row is one buffer row.
            $erase = [pscustomobject]@{ RowCells = @($frame.RowCells); Clipped = $false }
            $narrow = Clear-TpmProgressFrame -Frame $erase -Top $top -BufferWidth $bufferWidth
            if ($narrow) { $preWrite = [pscustomobject]@{ Left = 0; Top = $top } }
            # Not erased: keep the old width so the in-place rewrite still covers every previously owned cell.
        }
        if ($narrow) {
            $width = $currentWidth
            $composed = Get-TpmProgressFrameRows @layout -Width $width
        }
    }
    Write-TpmProgressSegments -Rows $composed -Prefix $prefix -ColorMode $Op.ColorMode -Background $Op.Background -NewLine:$Closing -Foreground $live.Foreground
    if ($Closing) {
        $frame.HasFrame = $false
        # FIX52 (#384): no later frame corrects the closing rows, so a size change during their write is repaired here.
        # -BufferWidth is the width the in-place decision was made at, so a change at any point after it is seen.
        $repair = @{ Op = $Op; Layout = $layout; Composed = $composed; Width = $width; BufferWidth = $bufferWidth }
        if ($inPlace) { $repair['OverwrittenTexts'] = @($frame.RowTexts) }
        Repair-TpmProgressClosingFrame @repair
        return
    }
    $rowCells = @(foreach ($row in $composed) { $row.Cells })
    $overwrittenTexts = @($frame.RowTexts)
    $frame.HasFrame = $true
    $frame.LastFrame = $Now
    $frame.FrameWidth = $width
    $frame.RowCells = $rowCells
    $frame.RowTexts = @(foreach ($row in $composed) { [string]$row.Text })
    $frame.Overflow = $false
    $frame.WidthSource = [string]$script:TpmProgressLastWidthSource
    $frame.WindowWidthRead = [int]$script:TpmProgressLastWindowWidth
    $geometry = Get-TpmProgressStableGeometry -FallbackWidth $currentBuffer -FallbackHeight $height
    $after = $geometry.Cursor
    $frame.CursorLeft = if ($null -ne $after) { $after.Left } else { $null }
    $frame.CursorTop = if ($null -ne $after) { $after.Top } else { $null }
    $frame.FrameBufferWidth = $geometry.BufferWidth
    $frame.FrameWindowHeight = $geometry.WindowHeight
    # FIX52 (#384): the size changed while this frame was composed or written (a user can drag the window at any moment,
    # and Windows Terminal resizes its pseudo console after the terminal itself). The frame stays recorded where the
    # console says it is now (the FIX40 reflow model finds it there), and RedrawPending makes the very next refresh step
    # draw it again at the new size instead of waiting for the frame interval. Both directions count: a wider window gets
    # the wider layout at once, a narrower one never keeps a frame composed for the old width.
    $widthAfter = Get-TpmProgressWidth -Requested $Op.WidthRequested -Live
    if ($geometry.BufferWidth -ge 2) { $widthAfter = [Math]::Min($widthAfter, [Math]::Max(1, $geometry.BufferWidth - 1)) }
    $frame.RedrawPending = ($geometry.BufferWidth -ne $currentBuffer -or $geometry.WindowHeight -ne $height -or $widthAfter -ne $width)
    $physicalRows = 0
    $measuredBuffer = [Math]::Max(1, $frame.FrameBufferWidth)
    for ($index = 0; $index -lt $frame.RowCells.Count; $index++) {
        $physicalRows += Get-TpmProgressRowSpan -Cells $frame.RowCells[$index] -BufferWidth $measuredBuffer -Last:($index -eq $frame.RowCells.Count - 1)
    }
    $frame.FrameRows = $physicalRows
    $frame.FrameTop = if ($null -ne $after) { [Math]::Max(0, $after.Top - $physicalRows + 1) } else { $null }
    # FIX52 (#384): the buffer width changed after the in-place decision (during layout or the write). The console
    # reflowed the frame that was being overwritten, so the carriage return went to the start of that frame's last
    # reflowed row and the rows just above the new frame may still hold the beginning of the old one. Only rows proven
    # by read-back are blanked.
    if ($inPlace -and $geometry.BufferWidth -ne $bufferWidth -and $null -ne $frame.FrameTop -and $null -ne $after) {
        if ((Clear-TpmProgressReflowedRemains -OldTexts $overwrittenTexts -Top ([int]$frame.FrameTop) -BufferWidth $geometry.BufferWidth) -gt 0) {
            [void](Set-TpmProgressCursor -Left $after.Left -Top $after.Top)
        }
    }
    # FIX45: did the frame take the cells it was composed for? A frame its glyphs widened is recorded with the rows it
    # really took (Register-TpmProgressOverflow), so the next redraw or lift leaves no fragment of it behind.
    $overflow = Measure-TpmProgressOverflow -Composed $composed -Before $preWrite -After $after -StartTop $startTop -BufferWidth $currentBuffer -MeasuredBufferWidth $geometry.BufferWidth
    if ($null -ne $overflow) { Register-TpmProgressOverflow -Live $live -Frame $frame -Overflow $overflow -After $after }
    # Adaptive throttle input: the cost of this whole frame (layout, geometry and write) on the monotonic clock.
    # DrawnAt (the same clock) is the end of this frame, just after its write; Frames counts this operation's frames.
    $drawnAt = Get-TpmProgressTimestamp
    $frame.CostMs = [Math]::Max([double]0, $drawnAt - $costStart)
    $frame.DrawnAt = $drawnAt
    Add-TpmProgressFrameCost -Frame $frame -CostMs $frame.CostMs
}

function Publish-TpmProgressSnapshot {
    # Shallow copies of the operation and its tasks are the only progress state the refresh writer reads. Publishing is
    # one reference assignment, so it needs no Gate and never waits for a frame.
    param($Op)
    $snapshot = $Op.psobject.Copy()
    $snapshot.Tasks = @(foreach ($task in $Op.Tasks) { $task.psobject.Copy() })
    $Op.Live.Snapshot = $snapshot
}

function New-TpmProgressFrameState {
    # Where the live frame is on screen and how it is paced. One per operation; changed only under the Gate.
    return [pscustomobject]@{
        HasFrame = $false; LastFrame = [datetime]::MinValue; FrameWidth = 0
        CursorLeft = $null; CursorTop = $null; FrameTop = $null
        FrameBufferWidth = 0; FrameWindowHeight = 0; FrameRows = 0; RowCells = @(); Resizes = 0
        Clipped = $false; CostMs = [double]0
        # FIX52 (#384): RedrawPending is set when the size changed between composing and writing the last frame (the next
        # refresh step draws at once).
        RedrawPending = $false
        # FIX45: the plain text of each row (cell read-back before a moved-to region is erased); Overflow is set while the
        # region is recorded with the rows the last frame really took. WidthSource and WindowWidthRead are support
        # evidence for the last frame.
        RowTexts = @(); Overflow = $false; WidthSource = ''; WindowWidthRead = 0
        # Adaptive throttle (FIX24): frames drawn so far, the recent measured costs (oldest first) and their median, the
        # clock of the last due refresh attempt, and the monotonic time at the end of the last frame.
        Frames = 0; CostSamples = [double[]]@(); SustainedMs = [double]0; LastTry = [datetime]::MinValue; DrawnAt = [double]0
    }
}

function Add-TpmProgressFrameCost {
    # Records one drawn frame (FIX24; caller holds the Gate). The first TpmProgressWarmupFrames frames of an operation are
    # only counted: they carry one-time work such as the first-call compile of the frame code, which is not what the
    # console costs. Later costs enter a window of the last TpmProgressCostWindow frames, and SustainedMs is its median
    # once it holds three (0 until then), so one slow frame - a console hiccup, a garbage collection - never changes it.
    param($Frame, [double]$CostMs)
    $Frame.Frames++
    if ($Frame.Frames -le $script:TpmProgressWarmupFrames) { return }
    $window = $Frame.CostSamples
    $keep = [Math]::Min($window.Count, $script:TpmProgressCostWindow - 1)
    $samples = New-Object 'double[]' ($keep + 1)
    if ($keep -gt 0) { [Array]::Copy($window, $window.Count - $keep, $samples, 0, $keep) }
    $samples[$keep] = $CostMs
    $Frame.CostSamples = $samples
    if ($samples.Count -lt 3) { return }
    $sorted = [double[]]$samples.Clone()
    [Array]::Sort($sorted)
    # The median; for an even count the lower of the two middle values.
    $Frame.SustainedMs = $sorted[[int][Math]::Floor(($sorted.Count - 1) / 2)]
}

function Get-TpmProgressFrameInterval {
    # Adaptive throttle (FIX24): frames are TpmProgressMinFrameMs (100 ms) to TpmProgressMaxFrameMs (250 ms) apart and,
    # within that range, three times the sustained frame cost (Add-TpmProgressFrameCost). Frames up to about 33 ms keep
    # 100 ms, the interval passes 150 ms only while most recent frames cost more than 50 ms, and a single slow frame
    # never stretches it. A console slower than 250 ms per frame is redrawn back to back (one timer tick apart).
    param($Frame)
    return [Math]::Min([double]$script:TpmProgressMaxFrameMs, [Math]::Max([double]$script:TpmProgressMinFrameMs, 3 * [double]$Frame.SustainedMs))
}

function Get-TpmProgressRefreshWait {
    # Milliseconds the refresh writer sleeps before its next attempt (FIX24):
    # - the rest of the frame interval since the last frame started;
    # - 1 (the next timer tick) when that frame is already overdue: it took longer than the interval (a console hiccup),
    #   or the writer has just taken over from frames the owner drew. The next frame follows at once instead of one
    #   more whole interval later;
    # - a whole interval after a due attempt that drew nothing (suspended, parked, no frame yet: LastTry is later than
    #   LastFrame), so a blocked writer retries at the frame rate and never spins.
    # A clock that went back gives one whole interval.
    param($Live)
    $frame = $Live.Frame
    $interval = Get-TpmProgressFrameInterval -Frame $frame
    $from = if ($frame.LastTry -gt $frame.LastFrame) { $frame.LastTry } else { $frame.LastFrame }
    # FIX52: a frame written while the size changed is redrawn at the next timer tick, unless an attempt since then drew
    # nothing (suspended or parked), which keeps the normal pace so a blocked writer never spins.
    if ($frame.RedrawPending -and $frame.LastTry -le $frame.LastFrame) { return 1 }
    $left = $interval - ((Get-TpmProgressNow) - $from).TotalMilliseconds
    if ($left -gt $interval) { $left = $interval }
    return [int][Math]::Max(1, [Math]::Ceiling($left))
}

function Invoke-TpmProgressRefreshStep {
    # Caller holds Live.Gate. Both foreground callbacks and the refresh runspace use this same writer.
    # -CheckOwner is passed only by the refresh runspace: it verifies the owner and never appends after foreign output.
    # Frame.LastTry records each due attempt (FIX24); when it is later than LastFrame the attempt drew nothing.
    param($Live, [switch]$Force, [switch]$CheckOwner)
    if ($null -ne $Live.Failure) { throw $Live.Failure }
    if ($CheckOwner -and -not (Test-TpmProgressOwnerActive -Live $Live)) {
        $Live.Abandoned = $true
        $Live.Stop = $true
        if ($null -ne $Live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $Live.CursorVisible }
        return
    }
    $now = Get-TpmProgressNow
    if ($Live.Stop -or $Live.AwaitCleanRow -or ($CheckOwner -and $Live.Parked) -or $Live.PromptDepth -gt 0 -or $Live.OutputDepth -gt 0 -or $null -eq $Live.Snapshot) {
        $Live.Frame.LastTry = $now
        return
    }
    $op = $Live.Snapshot
    # A negative age (the clock went back) counts as due, so a clock change cannot freeze the display.
    $since = ($now - $Live.Frame.LastFrame).TotalMilliseconds
    if (-not $Force -and -not $Live.Frame.RedrawPending -and $Live.Frame.HasFrame -and $since -ge 0 -and $since -lt (Get-TpmProgressFrameInterval -Frame $Live.Frame)) { return }
    $Live.Frame.LastTry = $now
    $op.Tick = [int][Math]::Floor([Math]::Max([double]0, ($now - $op.Started).TotalMilliseconds) / 100)
    foreach ($task in $op.Tasks) { if ($task.State -in @('Running', 'Pending')) { $task.Tick = $op.Tick } }
    # The look follows the CURRENT silence only: work that resumed counts as running again (the stall history stays in the stage note).
    $state = if (($now - $op.LastChange).TotalSeconds -ge $op.StallSeconds) { Get-TpmProgressSilentState -Op $op } else { 'Running' }
    Write-TpmProgressLiveFrame -Op $op -State $state -Now $now -NoAppend:$CheckOwner
    if ($CheckOwner -and $Live.Parked -and $null -ne $Live.CursorVisible) {
        # Parked by foreign output (possibly the prompt of an owner that returned): give the cursor back.
        Set-TpmProgressCursorVisible -Visible $Live.CursorVisible
    }
}

function Test-TpmProgressOwnerActive {
    # The refresh runspace keeps drawing only while the owner can still close the operation: the owner runspace is
    # Opened (not Closing/Closed/Broken) and the thread that opened the operation is alive. RunspaceAvailability is
    # deliberately NOT used: a console host reports its default runspace as Available while the owner's script is
    # still running, which stopped every live display after its first frame (FIX22, Windows Terminal, PS 5.1).
    # An owner that returns to the prompt with the operation still open is covered by -NoAppend parking: the prompt
    # is foreign output, so the refresh writer stops writing and restores the cursor until an owner call.
    param($Live)
    if ($null -eq $Live.Owner) { return $false }
    try {
        if ([string]$Live.Owner.RunspaceStateInfo.State -ne 'Opened') { return $false }
        if ($null -ne $Live.OwnerThread -and -not [bool]$Live.OwnerThread.IsAlive) { return $false }
    } catch { return $false }
    return $true
}

function Invoke-TpmProgressWarmup {
    # Refresh writer, once per runspace before its first operation (FIX24). Runs the whole live frame path - refresh
    # step, row layout, colors, frame composition, placement and bookkeeping - twice (appended, then redrawn in place as
    # the writer does) on a private sample operation, with every console write, cursor move, cell blank and color
    # restore switched off (TpmProgressDryRun); only console geometry is read. The first call of a script function
    # compiles it (4-25 ms per function measured on PS 5.1), which made cold frames cost hundreds of ms. Compiled code
    # is shared by every runspace that imports this module file, so this also shortens the owner's first frame when it
    # finishes first. Nothing here reads or changes the operation on screen.
    $now = Get-TpmProgressNow
    $started = $now.AddSeconds(-5)
    $columns = @(Get-TpmProgressDefaultColumns)
    $samples = @(
        @{ Title = 'Warm-up'; Stage = 'Sample'; Current = 40; Total = 100; Unit = 'Items'; State = 'Running' },
        @{ Title = 'Warm-up bytes'; Stage = ''; Current = 1048576; Total = 2097152; Unit = 'Bytes'; State = 'Running' },
        @{ Title = 'Warm-up count'; Stage = ''; Current = 7; Total = 0; Unit = 'Items'; State = 'Running' },
        @{ Title = 'Warm-up pending'; Stage = ''; Current = 0; Total = 10; Unit = 'Items'; State = 'Pending' }
    )
    $rows = @(foreach ($sample in $samples) {
        [pscustomobject]@{
            Title = $sample.Title; Stage = $sample.Stage; Current = [long]$sample.Current; Total = [long]$sample.Total
            Unit = $sample.Unit; State = $sample.State; Tick = 0; Started = $started; StageStarted = $started; Finished = $null
            PauseStarted = $null; Group = $false; EtaHidden = $false; NoCount = $false; StageFirstCurrent = [long]0
            StageSamples = 4; SmoothedRate = [double]8; Columns = $columns
        }
    })
    $live = [hashtable]::Synchronized(@{
        Stop = $false; AwaitCleanRow = $false; Parked = $false; PromptDepth = 0; OutputDepth = 0; Failure = $null
        ForceAscii = $false
        Owner = [runspace]::DefaultRunspace; OwnerThread = [System.Threading.Thread]::CurrentThread
        CursorVisible = $null; Foreground = [System.ConsoleColor]::Gray; Frame = (New-TpmProgressFrameState)
    })
    $op = $rows[0]
    $op | Add-Member -NotePropertyName Tasks -NotePropertyValue @($rows[1], $rows[2], $rows[3])
    $op | Add-Member -NotePropertyMembers @{
        HideCompleted = $false; WidthRequested = 0; Style = 'Unicode'; ColorMode = 'TrueColor'; Background = 'Black'
        StalledFor = 0; LastChange = $now; StallSeconds = 60; LongStep = $false; Live = $live
    }
    $live.Snapshot = $op
    $script:TpmProgressDryRun = $true
    try {
        Invoke-TpmProgressRefreshStep -Live $live -Force
        Invoke-TpmProgressRefreshStep -Live $live -Force -CheckOwner
        [void](Get-TpmProgressRefreshWait -Live $live)
    } finally {
        $script:TpmProgressDryRun = $false
    }
}

function Start-TpmProgressRefresh {
    # One cached refresh writer per module, in its own runspace. Only snapshots cross threads, and one Gate owns all
    # console writes. Without -Op (Start-TpmProgressOperation calls it first, before its console probes and first frame)
    # the writer is only created: its runspace opens, imports this module and warms up the frame path while the owner
    # carries on (FIX24). With -Op the operation is attached to the writer, which is created first when needed.
    param($Op)
    if ($null -ne $Op -and ($Op.Redirected -or -not $Op.AutoRefresh)) { return }
    $service = $script:TpmProgressRefreshService
    if ($null -ne $service -and ($null -ne $service.Failure -or $service.Stop -or $service.Async.IsCompleted)) {
        # A writer that failed or ended. Its operation already surfaced the failure (or it never ran), so a later
        # operation gets a fresh writer; the old one's error is not raised again here.
        try { Stop-TpmProgressRefreshService } catch {}
        $service = $null
    }
    if ($null -eq $service) { $service = New-TpmProgressRefreshService }
    if ($null -eq $Op) { return }
    $live = $Op.Live
    $live.RefreshService = $service
    $service.Session = $live
    [void]$service.Signal.Set()
}

function New-TpmProgressRefreshService {
    # Creates and caches the refresh writer. It waits for a session (Start-TpmProgressRefresh -Op) after its warm-up.
    # Ready: the warm-up is over and the writer loop runs (diagnostics, read by tools\dev\Measure-TpmProgressCost.ps1).
    $runner = [powershell]::Create()
    $service = [hashtable]::Synchronized(@{
        Signal = (New-Object System.Threading.AutoResetEvent($false))
        Stop = $false; Session = $null; Failure = $null; Ready = $false; Background = $null
        Runner = $runner; Async = $null
        # The runspace and thread that created the writer (FIX43): an idle writer ends itself when its owner is gone.
        Owner = [runspace]::DefaultRunspace; OwnerThread = [System.Threading.Thread]::CurrentThread
    })
    try {
        [void]$runner.AddScript({
            param($modulePath, $shared)
            $ErrorActionPreference = 'Stop'
            # FIX43: the writer is a daemon. A foreground worker thread keeps powershell.exe -File alive after the script
            # ends (the process never exited after Q in a real console window), so it must never count as a foreground thread.
            try { [System.Threading.Thread]::CurrentThread.IsBackground = $true } catch {}
            # Diagnostic read by the FIX43 tests: whether the writer thread really is a background thread.
            try { $shared.Background = [bool][System.Threading.Thread]::CurrentThread.IsBackground } catch {}
            try {
                $module = Import-Module -Name $modulePath -PassThru -ErrorAction Stop
                & $module {
                    param($service)
                    # Compile the frame path off screen before the first frame (FIX24). Skipped when an operation is
                    # already waiting: its value updates are drawn only by this writer, and its owner has drawn frames by
                    # then (compiled code is shared between runspaces), so drawing at once beats warming up first. A
                    # failed warm-up only means a slower first frame.
                    if ($null -eq $service.Session) { try { Invoke-TpmProgressWarmup } catch {} }
                    $service.Ready = $true
                    while (-not $service.Stop) {
                        $live = $service.Session
                        if ($null -eq $live) {
                            # FIX43: a bounded wait, not an endless one. With no operation to draw, the writer ends itself once
                            # its owner (the runspace or thread that created it) is gone, instead of sleeping forever.
                            [void]$service.Signal.WaitOne(1000)
                            if ($null -eq $service.Session -and -not $service.Stop -and -not (Test-TpmProgressOwnerActive -Live $service)) { $service.Stop = $true }
                            continue
                        }
                        # Sleep until the next frame is due (adaptive interval); Stop and a new session signal at once.
                        [void]$service.Signal.WaitOne((Get-TpmProgressRefreshWait -Live $live))
                        [System.Threading.Monitor]::Enter($live.Gate)
                        try {
                            if (-not $live.Stop) {
                                $script:TpmProgressWideWriteActive = $live.WideWrite
                                Invoke-TpmProgressRefreshStep -Live $live -CheckOwner
                            }
                        } catch {
                            $live.Failure = $_
                            $live.Stop = $true
                        } finally {
                            if ($live.Stop -and $null -ne $live.Failure -and $null -ne $live.CursorVisible) {
                                Set-TpmProgressCursorVisible -Visible $live.CursorVisible
                            }
                            [System.Threading.Monitor]::Exit($live.Gate)
                        }
                        if ($live.Stop) {
                            $service.Session = $null
                            # Acknowledge AFTER the last write and after releasing the gate. The owner can now dispose.
                            [void]$live.Signal.Set()
                        }
                    }
                } $shared
            } catch {
                $shared.Failure = $_
                $live = $shared.Session
                if ($null -ne $live) {
                    $live.Failure = $_
                    $live.Stop = $true
                    if ($null -ne $live.CursorVisible) { try { [Console]::CursorVisible = $live.CursorVisible } catch {} }
                    $shared.Session = $null
                    [void]$live.Signal.Set()
                }
            }
        }).AddArgument($script:TpmProgressModulePath).AddArgument($service)
        # No runspace is assigned, so BeginInvoke opens the runner's own runspace on a pool thread and returns at once (an
        # explicit Open() here blocked the owner 40-100 ms on PS 5.1). Disposing the runner also closes that runspace.
        $service.Async = $runner.BeginInvoke()
    } catch {
        $service.Signal.Dispose()
        $runner.Dispose()
        throw
    }
    $script:TpmProgressRefreshService = $service
    Register-TpmProgressExitHook
    return $service
}

function Stop-TpmProgressRefresh {
    param($Op)
    $live = $Op.Live
    $live.Stop = $true
    $service = $live.RefreshService
    if ($null -eq $service) { return }
    [void]$service.Signal.Set()
    # The writer acknowledges after its last write. A writer whose runspace never started (or that has ended) cannot,
    # so the end of its invocation also releases the owner instead of blocking it forever.
    $handles = @($live.Signal)
    if ($null -ne $service.Async) { $handles += $service.Async.AsyncWaitHandle }
    [void][System.Threading.WaitHandle]::WaitAny([System.Threading.WaitHandle[]]$handles)
}

function Register-TpmProgressExitHook {
    # FIX43: second line of defense. The engine raises PowerShell.Exiting when the host closes its runspace (end of a
    # -File script, an exit statement, an unhandled error), also for paths the product's own finally does not cover.
    # Registered once per module and only on a best-effort basis: another handler already registered for the event, or a
    # host that refuses it, only means the other lines of defense (daemon writer thread, owner check, the product's
    # finally) carry the guarantee. A handler of anyone else is never touched.
    if ($script:TpmProgressExitHookTried) { return }
    $script:TpmProgressExitHookTried = $true
    $module = $ExecutionContext.SessionState.Module
    if ($null -eq $module) { return }
    try {
        $before = @(Get-EventSubscriber -SourceIdentifier 'PowerShell.Exiting' -ErrorAction SilentlyContinue | ForEach-Object { $_.SubscriptionId })
        [void](Register-EngineEvent -SourceIdentifier 'PowerShell.Exiting' -MessageData $module -ErrorAction Stop -Action {
            try { & $Event.MessageData { Close-TpmProgressSession -WaitMs 3000 } } catch {}
        })
        $ours = @(Get-EventSubscriber -SourceIdentifier 'PowerShell.Exiting' -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.SubscriptionId })
        if ($ours.Count -gt 0) { $script:TpmProgressExitSubscriptionId = $ours[0].SubscriptionId }
    } catch {}
}

function Unregister-TpmProgressExitHook {
    $id = $script:TpmProgressExitSubscriptionId
    $script:TpmProgressExitSubscriptionId = $null
    $script:TpmProgressExitHookTried = $false
    if ($null -eq $id) { return }
    try { Unregister-Event -SubscriptionId $id -Force -ErrorAction SilentlyContinue } catch {}
}

function Stop-TpmProgressRefreshService {
    # -WaitMs >= 0 is for exit paths: the writer gets at most that long to end. A writer that does not answer in time is
    # dropped without disposing its running pipeline or its signal (it is a daemon thread and cannot hold the process).
    param([int]$WaitMs = -1)
    $service = $script:TpmProgressRefreshService
    if ($null -eq $service) { return }
    $service.Stop = $true
    $live = $service.Session
    if ($null -ne $live) { $live.Stop = $true }
    [void]$service.Signal.Set()
    $ended = $true
    try {
        if ($WaitMs -ge 0 -and $null -ne $service.Async) { $ended = [bool]$service.Async.AsyncWaitHandle.WaitOne($WaitMs) }
        if ($ended) { [void]$service.Runner.EndInvoke($service.Async) }
    }
    finally {
        if ($null -ne $live -and $null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $live.CursorVisible }
        if ($ended) {
            # Disposing the runner also closes the runspace it opened for the writer.
            $service.Runner.Dispose()
            $service.Signal.Dispose()
        }
        $script:TpmProgressRefreshService = $null
    }
}

function Close-TpmProgressSession {
    # FIX43: the one shutdown for every way the product (or a script that uses this module) ends: closes an open operation
    # as abandoned, stops the refresh writer, restores the console. Safe to call at any time and more than once. The
    # product calls it from the finally of its main block; the module also calls it from PowerShell.Exiting and OnRemove.
    # -WaitMs bounds the wait for the writer (see Stop-TpmProgressRefreshService); the default waits for it.
    param([int]$WaitMs = -1)
    try { if ($null -ne $script:TpmProgressOp) { Stop-TpmProgressAbandoned } }
    finally {
        try { Stop-TpmProgressRefreshService -WaitMs $WaitMs }
        finally { Restore-TpmProgressVt }
    }
}

function Set-TpmProgressRenderLogger {
    # The owner hands over one script block that writes a line to its log. A drawing failure is reported through it and
    # never reaches the work being reported on. $null removes the hook.
    param([AllowNull()][scriptblock]$Logger)
    $script:TpmProgressRenderLogger = $Logger
}

function Test-TpmProgressCancellationError {
    # True for genuine cancellation (Ctrl+C / Stop-Pipeline, a canceled token) anywhere in the error chain. Cancellation is
    # never a drawing error: it always propagates.
    param($ErrorRecord)
    $current = if ($ErrorRecord -is [System.Management.Automation.ErrorRecord]) { $ErrorRecord.Exception } else { $ErrorRecord }
    while ($current -is [System.Exception]) {
        if ($current -is [System.Management.Automation.PipelineStoppedException] -or $current -is [System.OperationCanceledException]) { return $true }
        $current = $current.InnerException
    }
    return $false
}

function Disable-TpmProgressRenderer {
    # A drawing failure never reaches the work being reported on. The renderer of this operation is switched off for good: the
    # refresh writer is joined, the cursor and console mode are put back and one line goes to the owner's log. The operation
    # itself stays open (group ownership, recorded outcomes and its close keep working); nothing is drawn for it any more.
    # Genuine cancellation is re-thrown after the same clean-up. The caller must NOT hold Live.Gate (joining the writer
    # while holding it would deadlock).
    param($Op, $Failure)
    $live = $Op.Live
    $cancelled = Test-TpmProgressCancellationError -ErrorRecord $Failure
    if (-not [bool]$live['RenderDisabled']) {
        $live['RenderDisabled'] = $true
        if ($null -eq $live.Failure) { $live.Failure = $Failure }
        try {
            Stop-TpmProgressRefresh -Op $Op
            # The frame already on screen is lifted now (a second failure is ignored), so the next line starts on a clean row.
            try { Remove-TpmProgressLiveRegion -Op $Op } catch {}
        }
        finally {
            if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $live.CursorVisible }
            Restore-TpmProgressVt
        }
        $logger = $script:TpmProgressRenderLogger
        if ($null -ne $logger -and -not $cancelled) {
            $reason = if ($Failure -is [System.Management.Automation.ErrorRecord]) { $Failure.Exception.Message } else { [string]$Failure }
            try { & $logger ('Progress display stopped; the work goes on: {0}' -f $reason) } catch {}
        }
    }
    if ($cancelled) { throw $Failure }
}

function Write-TpmProgressFrame {
    # Foreground entry of every progress update. While the refresh writer runs (the normal interactive case) a value
    # update only publishes the new snapshot and returns: it never draws and never waits for the Gate, so a slow console
    # cannot slow the work being reported. That holds while the writer is still warming up as well (FIX24); it draws
    # the latest snapshot once it is ready. The writer shows it within one frame interval. Drawing here (under the
    # Gate) happens only for -Sync (the first frame, a structural change such as a new row or a task state change, a
    # redraw right after a print or prompt, the stall watchdog), a writer parked by foreign output, a pending clean-row
    # guard, a writer failure or stop (surfaced or cleaned up here), and when no writer exists (redirected output,
    # AutoRefresh off).
    param([switch]$Force, [switch]$Sync)
    $op = $script:TpmProgressOp
    if ($null -eq $op) { return }
    $live = $op.Live
    # A renderer that failed stays off for the rest of this operation (Disable-TpmProgressRenderer).
    if ([bool]$live['RenderDisabled']) { return }
    if (-not $Sync -and -not $op.Redirected -and $null -ne $live.RefreshService -and $null -eq $live.Failure -and
        -not $live.Stop -and -not $live.Parked -and -not $live.AwaitCleanRow) {
        Publish-TpmProgressSnapshot -Op $op
        return
    }
    $renderFailure = $null
    [System.Threading.Monitor]::Enter($live.Gate)
    try {
        $live.AwaitCleanRow = $false
        Publish-TpmProgressSnapshot -Op $op
        if ($live.PromptDepth -gt 0 -or $live.OutputDepth -gt 0) { return }
        if ($live.Parked) {
            # The refresh writer parked after foreign output. This owner call redraws below that output.
            $live.Parked = $false
            $Force = [switch]$true
            if (-not $op.Redirected -and $null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $false }
        }
        if ($op.Redirected) {
            $state = if (Test-TpmProgressSilent) { Get-TpmProgressSilentState -Op $op } else { 'Running' }
            Write-TpmProgressPlainFrame -Op $op -State $state -Now (Get-TpmProgressNow) -Force:$Force
        } else {
            Invoke-TpmProgressRefreshStep -Live $live -Force:$Force
        }
    } catch {
        $live.Failure = $_
        $renderFailure = $_
    } finally { [System.Threading.Monitor]::Exit($live.Gate) }
    if ($null -ne $renderFailure) {
        if (-not (Test-TpmProgressCancellationError -ErrorRecord $renderFailure)) {
            # A drawing failure never reaches the work being reported on; only genuine cancellation is raised below.
            Disable-TpmProgressRenderer -Op $op -Failure $renderFailure
            return
        }
        # Joining the refresh writer while holding its gate would deadlock.
        try { Stop-TpmProgressRefresh -Op $op }
        finally {
            if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $live.CursorVisible }
            Restore-TpmProgressVt
            $live.Signal.Dispose()
            $script:TpmProgressOp = $null
            $script:TpmProgressDepth = 0
        }
        throw $renderFailure
    }
}

function Write-TpmProgressClosingFrame {
    param($Op, [string]$State)
    $live = $Op.Live
    [System.Threading.Monitor]::Enter($live.Gate)
    try {
        if ($live.Abandoned -or $live.PromptDepth -gt 0 -or $live.OutputDepth -gt 0) { return }
        $now = Get-TpmProgressNow
        if ($Op.Redirected) {
            $width = Get-TpmProgressWidth -Requested $Op.WidthRequested
            foreach ($row in @(Get-TpmProgressRows -Op $Op -State $State)) {
                $segments = @(Get-TpmProgressLineSegments -Op $row.Task -State $row.State -Now $now -Width $width -Style 'Ascii')
                Write-TpmProgressPlainLine -Text ((($segments | ForEach-Object { $_.Text }) -join '').TrimEnd())
            }
        } else {
            Write-TpmProgressLiveFrame -Op $Op -State $State -Now $now -Closing
        }
    } finally { [System.Threading.Monitor]::Exit($live.Gate) }
}

# ---------------------------------------------------------------------------------------------------------------
# Operation state
# ---------------------------------------------------------------------------------------------------------------

function Test-TpmProgressActive {
    return ($null -ne $script:TpmProgressOp -and -not $script:TpmProgressOp.Live.Abandoned)
}

function Test-TpmProgressGroupOwned {
    return ((Test-TpmProgressActive) -and [bool]$script:TpmProgressOp.Group)
}

function Get-TpmProgressState {
    # Read-only snapshot of the open operation, or $null.
    $op = $script:TpmProgressOp
    if (-not (Test-TpmProgressActive)) { return $null }
    return [pscustomobject]@{
        Title = $op.Title; Stage = $op.Stage; Current = $op.Current; Total = $op.Total; Unit = $op.Unit
        State = $op.State; Outcome = $op.Outcome; Group = $op.Group; Depth = $script:TpmProgressDepth
        Redirected = $op.Redirected; Style = $op.Style; ColorMode = $op.ColorMode; Background = $op.Background
        StageStarted = $op.StageStarted; StageSamples = $op.StageSamples; EtaHidden = $op.EtaHidden
        Started = $op.Started; Suspended = ($op.Live.PromptDepth -gt 0); TaskCount = 1 + $op.Tasks.Count
        Columns = @($op.Columns); AutoRefresh = $op.AutoRefresh; LongStep = (Test-TpmProgressLongStep -Op $op); NoCount = [bool]$op.NoCount
    }
}

function Get-TpmProgressOutcomeRank {
    # Severity of a recorded outcome: a worse state is never hidden by an earlier, milder one.
    # Stalled is only telemetry (work may resume); Incomplete, Cancelled and Error are real results.
    param([string]$State)
    switch ($State) {
        'Stalled' { return 1 }
        'Incomplete' { return 2 }
        'Cancelled' { return 3 }
        'Error' { return 4 }
        default { return 0 }
    }
}

function Get-TpmProgressStalledStage {
    # The stage text ending in one "(no update for Ns)" note. An older note is replaced, never stacked.
    param([string]$Stage, [int]$StalledFor)
    $at = $Stage.LastIndexOf(' (no update for ', [System.StringComparison]::Ordinal)
    if ($at -ge 0 -and $Stage.EndsWith('s)', [System.StringComparison]::Ordinal)) { $Stage = $Stage.Substring(0, $at) }
    return ('{0} (no update for {1}s)' -f $Stage, $StalledFor)
}

function Register-TpmProgressOutcome {
    # Records the worst non-Final state observed during an operation (Error > Cancelled > Incomplete > Stalled).
    # A terminal Final or No-op close retains that classification instead of reporting success, except a stall:
    # work that went quiet and then finished is reported as finished (the stall stays visible as text only).
    param([Parameter(Mandatory)][ValidateSet('Final', 'Error', 'Cancelled', 'Stalled', 'Incomplete')][string]$State)
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $State -eq 'Final') { return }
    if ((Get-TpmProgressOutcomeRank -State $State) -gt (Get-TpmProgressOutcomeRank -State $op.Outcome)) { $op.Outcome = $State }
}

function Get-TpmProgressTitle {
    if (-not (Test-TpmProgressActive)) { return $null }
    return $script:TpmProgressOp.Title
}

function Start-TpmProgressOperation {
    # Outermost call opens the operation; nested calls only increase the depth.
    # -Group marks a workflow owner. Its bar stays open until the owner calls
    # Complete-TpmProgressOperation (Final/No-op) or Stop-TpmProgressAbandoned.
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title,
        [string]$Stage = 'Starting',
        [long]$Total = 0,
        [ValidateRange(1, 2147483647)][int]$StallSeconds = 60,
        [int]$Width = 0,
        [switch]$Group,
        [ValidateSet('Items', 'Bytes')][string]$Unit = 'Items',
        [ValidateSet('Description', 'Bar', 'Percentage', 'Count', 'Elapsed', 'Remaining', 'Spinner')][string[]]$Columns = (Get-TpmProgressDefaultColumns),
        [bool]$AutoRefresh = $true,
        [switch]$HideCompleted,
        [switch]$AutoClear
    )
    if ($null -ne $script:TpmProgressOp -and $script:TpmProgressOp.Live.Abandoned) {
        Stop-TpmProgressRefresh -Op $script:TpmProgressOp
        $script:TpmProgressOp.Live.Signal.Dispose()
        Restore-TpmProgressVt
        $script:TpmProgressOp = $null
        $script:TpmProgressDepth = 0
    }
    if ($null -ne $script:TpmProgressOp) {
        if (-not $Group -or $script:TpmProgressOp.Group) {
            $script:TpmProgressDepth++
            # Remembered so a nested failure can be named on the parent's line.
            [void]$script:TpmProgressOp.NestedTitles.Add($Title)
            return $script:TpmProgressOp
        }
        # A group never adopts an open standalone operation: close that one as abandoned.
        Stop-TpmProgressAbandoned
    }
    if ($Total -lt 0) { $Total = 0 }
    $now = Get-TpmProgressNow
    $redirected = Test-TpmProgressOutputRedirected
    # FIX24: start the refresh writer before the console probes and the first frame. Its runspace opens, imports this
    # module and warms up the frame path in the background meanwhile; the operation is attached after its first frame.
    # A failure here is retried, and surfaced, by that attach.
    if (-not $redirected -and $AutoRefresh) { try { Start-TpmProgressRefresh } catch {} }
    $background = if ($redirected) { $null } else { Get-TpmProgressBackground }
    $colorMode = Get-TpmProgressColorMode -Background $background
    $live = [hashtable]::Synchronized(@{
        Gate = (New-Object object); Signal = (New-Object System.Threading.ManualResetEvent($false))
        Stop = $false; Snapshot = $null; Failure = $null; PromptDepth = 0; OutputDepth = 0
        AwaitCleanRow = $false; Parked = $false
        RefreshService = $null; Owner = [runspace]::DefaultRunspace; OwnerThread = [System.Threading.Thread]::CurrentThread
        Abandoned = $false; WideWrite = $false
        # FIX45: set by Register-TpmProgressOverflow when this host measurably drew a glyph two cells wide.
        ForceAscii = $false
        CursorVisible = $(if ($redirected) { $null } else { Get-TpmProgressCursorVisible })
        # Foreground attribute put back after every colored frame (read once here, not per frame).
        Foreground = $(if ($colorMode -ne 'None') { Get-TpmProgressForeground } else { $null })
        Frame = (New-TpmProgressFrameState)
    })
    $script:TpmProgressDepth = 1
    $script:TpmProgressOp = [pscustomobject]@{
        Title = $Title; Stage = $Stage; Current = [long]0; Total = [long]$Total; Unit = $Unit
        State = 'Running'; Outcome = $null; Group = [bool]$Group; StalledFor = 0; LongStep = $false
        Started = $now; StageStarted = $now; StageFirstCurrent = [long]0; StageLastCurrent = [long]0; StageSamples = 0
        SmoothedRate = [double]0; RateAt = $now; RateCurrent = [long]0; RateSamples = 0
        StageKey = $Stage; EtaHidden = $false; NestedTitles = (New-Object System.Collections.Generic.List[string])
        LastChange = $now; PauseStarted = $null
        StallSeconds = $StallSeconds; WidthRequested = $Width
        Redirected = $redirected; Tick = 0
        Style = $(if ($redirected) { 'Ascii' } else { Get-TpmProgressStyle })
        # Color needs a known background: an unknown one could make any chosen color unreadable.
        Background = $background
        ColorMode = $colorMode
        Live = $live; Finished = $null; AutoRefresh = $AutoRefresh
        Columns = @($Columns | Select-Object -Unique); HideCompleted = [bool]$HideCompleted; AutoClear = [bool]$AutoClear
        Tasks = (New-Object System.Collections.Generic.List[object]); NextTaskId = 1
        NoCount = $false; PlainForce = $true
        LastPlainStage = $null; LastPlainDecile = -2; LastPlainWrite = [datetime]::MinValue
    }
    # Glyph frames are written as UTF-16 straight to the console whenever that is possible (code-page independent).
    $script:TpmProgressWideWriteActive = ((-not $redirected) -and $script:TpmProgressOp.Style -in @('Unicode', 'Block') -and (Test-TpmProgressWideWriteAvailable))
    $live.WideWrite = $script:TpmProgressWideWriteActive
    try {
        if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $false }
        # The first frame is always drawn here, so the operation is on screen when this call returns.
        Write-TpmProgressFrame -Force -Sync
        if (-not [bool]$live['RenderDisabled']) { Start-TpmProgressRefresh -Op $script:TpmProgressOp }
        return $script:TpmProgressOp
    } catch {
        if (-not (Test-TpmProgressCancellationError -ErrorRecord $_) -and $null -ne $script:TpmProgressOp) {
            # A drawing failure never stops the work: the operation stays open with its renderer off.
            Disable-TpmProgressRenderer -Op $script:TpmProgressOp -Failure $_
            return $script:TpmProgressOp
        }
        if ($null -ne $script:TpmProgressOp) {
            Stop-TpmProgressRefresh -Op $script:TpmProgressOp
            if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $live.CursorVisible }
            $live.Signal.Dispose()
        }
        Restore-TpmProgressVt
        $script:TpmProgressOp = $null
        $script:TpmProgressDepth = 0
        throw
    }
}

function Update-TpmProgressRate {
    # Time-weighted EMA with a three-second time constant. Zero-work samples decay the rate.
    param($Task, [long]$Current, [datetime]$Now)
    if ($null -ne $Task.PauseStarted) { $Now = $Task.PauseStarted }
    $seconds = ($Now - $Task.RateAt).TotalSeconds
    if ($seconds -le 0) { return }
    $delta = [Math]::Max([double]0, ([double]$Current - $Task.RateCurrent))
    $instant = $delta / $seconds
    $alpha = 1 - [Math]::Exp(-$seconds / 3.0)
    if ($Task.RateSamples -eq 0) { $Task.SmoothedRate = $instant }
    else { $Task.SmoothedRate += $alpha * ($instant - $Task.SmoothedRate) }
    $Task.RateSamples++
    $Task.RateAt = $Now
    $Task.RateCurrent = $Current
}

function Add-TpmProgressTask {
    # Independent rows are opt-in; existing nested Start calls still belong to the workflow owner.
    param(
        [Parameter(Mandatory)][string]$Description,
        [long]$Total = 0,
        [ValidateSet('Items', 'Bytes')][string]$Unit = 'Items',
        [switch]$Pending
    )
    $op = $script:TpmProgressOp
    if ($null -eq $op) { throw 'Start a progress operation before adding a task.' }
    $now = Get-TpmProgressNow
    if ($null -ne $op.PauseStarted) { $now = $op.PauseStarted }
    $task = [pscustomobject]@{
        Id = $op.NextTaskId; Title = $Description; Stage = ''; Current = [long]0; Total = [Math]::Max([long]0, $Total); Unit = $Unit
        State = $(if ($Pending) { 'Pending' } else { 'Running' }); Started = $now; StageStarted = $now; Finished = $null; PauseStarted = $op.PauseStarted
        Group = $false; EtaHidden = $false; NoCount = $false; Tick = 0
        StageFirstCurrent = [long]0; StageLastCurrent = [long]0; StageSamples = 0; Columns = $op.Columns
        SmoothedRate = [double]0; RateAt = $now; RateCurrent = [long]0; RateSamples = 0
    }
    $op.NextTaskId++
    [void]$op.Tasks.Add($task)
    # A structural change (FIX24): the new row is drawn here, so it is on screen when this call returns.
    Write-TpmProgressFrame -Force -Sync
    return $task.Id
}

function Set-TpmProgressTask {
    param(
        [Parameter(Mandatory)][int]$Id,
        [long]$Current,
        [long]$Total,
        [string]$Description,
        [ValidateSet('Pending', 'Running', 'Final', 'No-op', 'Error', 'Cancelled', 'Stalled', 'Incomplete', 'Skipped')][string]$State
    )
    $op = $script:TpmProgressOp
    if ($null -eq $op) { throw 'There is no active progress operation.' }
    $task = $null
    # A loop, not a pipeline: this runs on every task update.
    foreach ($candidate in $op.Tasks) { if ($candidate.Id -eq $Id) { $task = $candidate; break } }
    if ($null -eq $task) { throw ('Unknown progress task ID: {0}' -f $Id) }
    if ($task.State -notin @('Pending', 'Running', 'Stalled')) { throw 'A completed progress task cannot be updated.' }
    $previousState = $task.State
    $now = Get-TpmProgressNow
    $clock = if ($null -ne $op.PauseStarted) { $op.PauseStarted } else { $now }
    if ($task.State -eq 'Pending' -and ($PSBoundParameters.ContainsKey('Current') -or ($PSBoundParameters.ContainsKey('State') -and $State -eq 'Running'))) {
        $task.State = 'Running'
        $task.Started = $clock; $task.StageStarted = $clock; $task.RateAt = $clock
    }
    $oldTotal = $task.Total
    if ($PSBoundParameters.ContainsKey('Total')) { $task.Total = [Math]::Max([long]0, $Total) }
    if ($PSBoundParameters.ContainsKey('Current')) {
        $task.Current = [Math]::Max([long]0, $Current)
        if ($task.Current -lt $task.StageLastCurrent -or ($oldTotal -gt 0 -and $task.Total -ne $oldTotal)) {
            $task.StageStarted = $clock; $task.StageFirstCurrent = $task.Current; $task.StageSamples = 0
            $task.SmoothedRate = 0; $task.RateAt = $clock; $task.RateCurrent = $task.Current; $task.RateSamples = 0
        } else {
            Update-TpmProgressRate -Task $task -Current $task.Current -Now $clock
            if ($task.Current -gt $task.StageLastCurrent) { $task.StageSamples++ }
        }
        $task.StageLastCurrent = $task.Current
    }
    if ($PSBoundParameters.ContainsKey('Description')) { $task.Title = $Description }
    if ($task.Total -gt 0 -and $task.Current -gt $task.Total) { Register-TpmProgressOutcome -State Error }
    if ($PSBoundParameters.ContainsKey('State')) {
        if ($State -in @('Final', 'No-op') -and $task.Total -gt 0 -and $task.Current -lt $task.Total) { $State = 'Incomplete' }
        if ($task.Total -gt 0 -and $task.Current -gt $task.Total) { $State = 'Error' }
        $task.State = $State
        if ($State -notin @('Pending', 'Running', 'Stalled')) { $task.Finished = $clock }
        if ($State -in @('Error', 'Cancelled', 'Stalled', 'Incomplete')) { Register-TpmProgressOutcome -State $State }
    }
    $op.LastChange = $now
    # A state change alters the row (its mark, colors and words; with -HideCompleted the row goes away): drawn here like
    # a new row (FIX24). A value update only publishes while the refresh writer runs.
    # Redirected output prints a line per frame: a value-only update must obey the 10%/5s throttle, a state change is drawn.
    Write-TpmProgressFrame -Force:(-not $op.Redirected -or $task.State -ne $previousState) -Sync:($task.State -ne $previousState)
}

function Set-TpmProgressStage {
    # Total is grounded only when supplied > 0; pass 0 for unknown. Current is the FINISHED count.
    # -StageOnly updates the text and keeps the operation's own Current and Total. When that text names other work
    # than the stage being measured, the ETA is hidden until the next counted update.
    # A new stage restarts the stage clock and samples so elapsed and ETA describe the stage on screen: a different
    # stage text, a different total, a count that went backwards, or a different unit. -SameStage marks a counted
    # update whose text is only a cosmetic relabel of the same work (for example "<label> done"), which keeps the clock.
    # -LongStep marks the stage as ONE long external job that reports nothing while it runs (an installer): the count
    # is hidden, a long silence reads "still working" (no "(!)", no stall recorded) and the next Set-TpmProgressStage
    # call without -LongStep ends the mark. A counted loop never uses it, so a loop that stops advancing still stalls.
    param(
        [Parameter(Mandatory)][string]$Stage,
        [long]$Current = 0,
        [long]$Total = 0,
        [switch]$StageOnly,
        [ValidateSet('Items', 'Bytes')][string]$Unit = 'Items',
        [switch]$SameStage,
        [switch]$LongStep
    )
    $op = $script:TpmProgressOp
    if ($null -eq $op) { return }
    # A blocking loop cannot draw a live stall, so the stall is reported on the
    # first update after a silent gap of at least StallSeconds.
    $now = Get-TpmProgressNow
    $gap = ($now - $op.LastChange).TotalSeconds
    $stalled = Test-TpmProgressStalled
    # The mark of the stage that was running until now (set below for the new one): it decides whether the silence
    # that just ended was a stall, and whether the hidden count comes back.
    $wasLongStep = (Test-TpmProgressLongStep -Op $op)
    $op.StalledFor = if ($stalled) { [int][Math]::Floor($gap) } elseif ($op.Outcome -eq 'Stalled') { $op.StalledFor } else { 0 }
    $op.Stage = if ($stalled) {
        Get-TpmProgressStalledStage -Stage $Stage -StalledFor $op.StalledFor
    } elseif ($op.Outcome -eq 'Stalled' -and $op.StalledFor -gt 0) {
        '{0} (stall observed after {1}s)' -f $Stage, $op.StalledFor
    } else {
        $Stage
    }
    if ($stalled) { Register-TpmProgressOutcome -State Stalled }
    $restart = $false
    if ($StageOnly) {
        if ($Stage -cne $op.StageKey) { $op.EtaHidden = $true }
    } else {
        if ($Current -lt 0) { $Current = 0 }
        if ($Total -lt 0) { $Total = 0 }
        $newStage = ((-not $SameStage) -and ($Stage -cne $op.StageKey))
        $restart = ($newStage -or ($Total -ne $op.Total) -or ($Current -lt $op.StageLastCurrent) -or ($Unit -ne $op.Unit))
        $op.Current = $Current; $op.Total = $Total; $op.Unit = $Unit
        if (-not $SameStage) { $op.StageKey = $Stage }
        $op.EtaHidden = $false
        if ($restart) {
            $op.StageStarted = $now; $op.StageFirstCurrent = $Current; $op.StageLastCurrent = $Current; $op.StageSamples = 0
            $op.SmoothedRate = 0; $op.RateAt = $now; $op.RateCurrent = $Current; $op.RateSamples = 0
            $op.LastPlainDecile = -2; $op.PlainForce = $true
        } else {
            Update-TpmProgressRate -Task $op -Current $Current -Now $now
            if ($Current -gt $op.StageLastCurrent) {
                $op.StageSamples++
                $op.StageLastCurrent = $Current
            }
        }
        if ($op.Total -gt 0 -and $op.Current -gt $op.Total) { Register-TpmProgressOutcome -State Error }
    }
    if ($LongStep) { $op.NoCount = $true } elseif ($wasLongStep) { $op.NoCount = $false }
    $op.LongStep = [bool]$LongStep
    $op.LastChange = $now; $op.Tick++
    Write-TpmProgressFrame -Force:$restart
}

function Test-TpmProgressTransientClose {
    # A finished step with no known size (a scan that only counted) has no bar to leave behind: on a live console its
    # row is removed, so the measured step that follows is the one bar on screen. A failed or unfinished step keeps its row.
    param($Op, [string]$State)
    return ($State -in @('Final', 'No-op') -and -not $Op.Group -and $Op.Total -le 0 -and $Op.Tasks.Count -eq 0)
}

function Complete-TpmProgressOperation {
    # State: Final | No-op | Error | Cancelled | Stalled | Incomplete.
    # A nested completion (depth > 1) ends only its own level and never closes the parent: Final/No-op just return,
    # every other state is recorded on the parent as its outcome and shown on the parent's line. The parent's owner
    # closes the bar later, and a recorded outcome turns its Final/No-op close into that outcome.
    # Final never forces Current to Total: the line shows the real count, or no
    # percent when the total is unmeasured. A group owner's closing line has no count: Final shows a full
    # bar (the workflow result is verified by the owner), every other state shows an empty track and its word.
    # -Superseded is passed when a new stage replaces a stage that its owner never closed. Such a stage has no
    # recorded result: when its known total was not reached it closes Incomplete instead of claiming Final.
    param([ValidateSet('Final', 'No-op', 'Error', 'Cancelled', 'Stalled', 'Incomplete')][string]$State = 'Final', [string]$Message = '', [switch]$Superseded)
    $op = $script:TpmProgressOp
    if ($null -eq $op) { return }
    if ($Superseded -and $State -eq 'Final' -and $null -eq $op.Outcome -and $op.Total -gt 0 -and $op.Current -lt $op.Total) { $State = 'Incomplete' }
    $terminalClose = ($script:TpmProgressDepth -le 1)
    try {
        if ($terminalClose) {
            Stop-TpmProgressRefresh -Op $op
            # A renderer that failed on its own (the refresh writer) is switched off; the close itself goes on.
            if ($null -ne $op.Live.Failure) { Disable-TpmProgressRenderer -Op $op -Failure $op.Live.Failure }
            foreach ($task in $op.Tasks) {
                # Owner decision (kept deliberately): a task that never started is optional work, so it closes Skipped and
                # does NOT block a successful owner close. Started-but-unfinished work (Running/Stalled) is Incomplete.
                # Callers whose pending work is required must close it themselves with a non-success state.
                if ($task.State -eq 'Pending') { $task.State = 'Skipped'; $task.Finished = Get-TpmProgressNow }
                if ($task.State -in @('Running', 'Stalled')) {
                    $task.State = 'Incomplete'
                    $task.Finished = Get-TpmProgressNow
                    Register-TpmProgressOutcome -State Incomplete
                }
            }
        }
        if ($State -in @('Final', 'No-op') -and (Test-TpmProgressStalled)) {
            $op.StalledFor = [int][Math]::Floor(((Get-TpmProgressNow) - $op.LastChange).TotalSeconds)
            $op.Stage = Get-TpmProgressStalledStage -Stage ([string]$op.Stage) -StalledFor $op.StalledFor
            Register-TpmProgressOutcome -State Stalled
        }
        if ($script:TpmProgressDepth -gt 1) {
            $nestedTitle = $null
            if ($op.NestedTitles.Count -gt 0) {
                $nestedTitle = $op.NestedTitles[$op.NestedTitles.Count - 1]
                $op.NestedTitles.RemoveAt($op.NestedTitles.Count - 1)
            }
            $script:TpmProgressDepth--
            $op.LastChange = Get-TpmProgressNow
            if ($State -notin @('Final', 'No-op')) {
                # The parent may still recover or return its own result: keep it open, but it can no longer succeed.
                Register-TpmProgressOutcome -State $State
                $word = switch ($State) { 'Error' { 'failed' } 'Cancelled' { 'canceled' } 'Stalled' { 'stalled' } default { 'incomplete' } }
                $what = if ($nestedTitle) { '{0} {1}' -f $nestedTitle, $word } else { $word }
                $op.Stage = if ($Message) { '{0}: {1}' -f $what, $Message } else { $what }
                $op.EtaHidden = $true
                $op.Tick++
                Write-TpmProgressFrame -Force
            }
            if ($State -in @('Final', 'No-op')) { Write-TpmProgressFrame }
            return
        }
        # A stall is telemetry: work that resumed and finished closes as finished. A recorded worse outcome always wins over the
        # close state, success or not (Error > Cancelled > Incomplete > Stalled).
        $recorded = $op.Outcome
        $stallOnly = ($recorded -eq 'Stalled' -and $State -in @('Final', 'No-op'))
        if ($null -ne $recorded -and -not $stallOnly -and (Get-TpmProgressOutcomeRank -State $recorded) -gt (Get-TpmProgressOutcomeRank -State $State)) { $State = $recorded }
        if ($State -eq 'Final' -and -not $op.Group -and $op.Total -gt 0 -and $op.Current -lt $op.Total) { $State = 'Incomplete' }
        $script:TpmProgressDepth = 0
        $op.State = $State
        if ($op.Group) {
            $op.NoCount = $true
            if ($State -in @('Final', 'No-op')) { $op.Current = 1; $op.Total = 1; $op.Unit = 'Items' } else { $op.Current = 0; $op.Total = 0; $op.Unit = 'Items' }
            if (-not $Message) { $op.Stage = '' }
        }
        if ($Message) {
            if (($State -eq 'Stalled' -or $op.Outcome -eq 'Stalled') -and $op.StalledFor -gt 0) {
                $op.Stage = '{0} (stall observed after {1}s)' -f $Message, $op.StalledFor
            } else {
                $op.Stage = $Message
            }
        }
        $op.Finished = if ($null -ne $op.PauseStarted) { $op.PauseStarted } else { Get-TpmProgressNow }
        if (Test-TpmProgressTransientClose -Op $op -State $State) { $op.AutoClear = $true }
        # The closing frame is only drawn while the renderer is on; a drawing failure here never changes the close.
        try { if (-not [bool]$op.Live['RenderDisabled']) { Write-TpmProgressClosingFrame -Op $op -State $State } }
        catch { Disable-TpmProgressRenderer -Op $op -Failure $_ }
    } finally {
        # Every terminal close clears state even if formatting or console output fails.
        if ($terminalClose) {
            if ($null -ne $op.Live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $op.Live.CursorVisible }
            # FIX45: a glyph this host drew two cells wide keeps later operations on ASCII glyphs as well.
            if ([bool]$op.Live['ForceAscii']) { $script:TpmProgressGlyphCells = $false }
            Restore-TpmProgressVt
            $op.Live.Signal.Dispose()
            $script:TpmProgressDepth = 0
            $script:TpmProgressOp = $null
        }
    }
}

function Stop-TpmProgressAbandoned {
    # Called from a finally block so an operation that was never completed
    # cannot leak its title into the next operation.
    # A group owner classifies pipeline cancellation before this cleanup; standalone abandoned work closes as Error.
    # It closes the whole operation whatever the nesting depth (a nested close alone would keep the parent open).
    if ($null -ne $script:TpmProgressOp) {
        $script:TpmProgressDepth = 1
        Complete-TpmProgressOperation -State Error -Message 'Abandoned before completion'
    }
    $script:TpmProgressDepth = 0
}

function Test-TpmProgressSilent {
    # True when the operation reported nothing for StallSeconds (and is not paused for a prompt). Silence alone is not a stall.
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $null -ne $op.PauseStarted) { return $false }
    return ((((Get-TpmProgressNow) - $op.LastChange).TotalSeconds) -ge $op.StallSeconds)
}

function Test-TpmProgressLongStep {
    # True when the operation's current stage is marked -LongStep. An operation object built by hand without the field reads false.
    param($Op)
    $property = $Op.PSObject.Properties['LongStep']
    return ($null -ne $property -and [bool]$property.Value)
}

function Get-TpmProgressSilentState {
    # The look of an operation that has been silent for StallSeconds: a long external job (-LongStep) is "Waiting", which
    # reads as normal; anything else is "Stalled", the warning.
    param($Op)
    if (Test-TpmProgressLongStep -Op $Op) { return 'Waiting' }
    return 'Stalled'
}

function Test-TpmProgressStalled {
    # A real stall: silence from work that should be advancing. A long external job (-LongStep) is never a stall.
    $op = $script:TpmProgressOp
    if ($null -eq $op -or (Test-TpmProgressLongStep -Op $op)) { return $false }
    return (Test-TpmProgressSilent)
}

function Start-TpmProgressLongWait {
    # A blocking call that reports nothing while it runs (a PostgreSQL tool, a web request, the Windows permission question)
    # marks the CURRENT step as a long wait: long silence reads "still working", never "stalled", and the count stays as it is.
    # Returns $true when this call set the mark; the caller then ends it with Stop-TpmProgressLongWait in a finally block.
    # Returns $false and changes nothing when no operation is open or the step already is a long step (its owner ends that mark).
    # The silence clock restarts here, so the wait is measured from its own start.
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $op.Live.Abandoned -or (Test-TpmProgressLongStep -Op $op)) { return $false }
    $op.LongStep = $true
    $op.LastChange = Get-TpmProgressNow
    $op.Tick++
    Write-TpmProgressFrame
    return $true
}

function Stop-TpmProgressLongWait {
    # Ends the mark Start-TpmProgressLongWait set. The call that was waited for has returned, which is progress, so the silence
    # clock restarts: later silence is measured from here and an ordinary step can be shown as stalled again.
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $op.Live.Abandoned -or -not (Test-TpmProgressLongStep -Op $op)) { return }
    $op.LongStep = $false
    $op.LastChange = Get-TpmProgressNow
    $op.Tick++
    Write-TpmProgressFrame
}

function Remove-TpmProgressLiveRegion {
    param($Op)
    $frame = $Op.Live.Frame
    if ($Op.Redirected -or -not $frame.HasFrame) { return }
    $position = Get-TpmProgressCursor
    $bufferWidth = Get-TpmProgressBufferWidth
    if ($bufferWidth -lt 2) { $bufferWidth = [int]$frame.FrameBufferWidth }
    $windowHeight = Get-TpmProgressWindowHeight
    if ($windowHeight -le 0) { $windowHeight = [int]$frame.FrameWindowHeight }
    $top = Resolve-TpmProgressFrameTop -Op $frame -Position $position -BufferWidth $bufferWidth -WindowHeight $windowHeight
    $cleared = ($top -ge 0 -and (Clear-TpmProgressFrame -Frame $frame -Top $top -BufferWidth $bufferWidth))
    if ($top -lt 0) {
        # FIX45: a caller that moved the cursor into the region (SetCursorPosition) before printing or prompting there. The
        # region is erased only when its cells read back unchanged; the cursor stays where that caller put it.
        $moved = Find-TpmProgressMovedRegion -Frame $frame -Position $position -BufferWidth $bufferWidth -WindowHeight $windowHeight
        if ($moved -ge 0) { $cleared = Clear-TpmProgressMovedRegion -Frame $frame -Top $moved -Position $position }
    }
    $frame.HasFrame = $false
    if (-not $cleared -and ($null -eq $position -or $position.Left -gt 0)) { Write-TpmProgressRaw -Text '' -NewLine }
}

function Suspend-TpmProgressLine {
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $op.Live.Abandoned) { return }
    $live = $op.Live
    $renderFailure = $null
    [System.Threading.Monitor]::Enter($live.Gate)
    try {
        $live.PromptDepth++
        if ($live.PromptDepth -gt 1) { return }
        $op.PauseStarted = Get-TpmProgressNow
        foreach ($task in $op.Tasks) { if ($null -eq $task.Finished) { $task.PauseStarted = $op.PauseStarted } }
        if (-not [bool]$live['RenderDisabled']) {
            try { Remove-TpmProgressLiveRegion -Op $op } catch { $renderFailure = $_ }
        }
    } finally {
        if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $live.CursorVisible }
        [System.Threading.Monitor]::Exit($live.Gate)
    }
    if ($null -ne $renderFailure) { Disable-TpmProgressRenderer -Op $op -Failure $renderFailure }
}

function Resume-TpmProgressLine {
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $op.Live.Abandoned) { return }
    $live = $op.Live
    $draw = $false
    [System.Threading.Monitor]::Enter($live.Gate)
    try {
        if ($live.PromptDepth -le 0) { return }
        $live.PromptDepth--
        if ($live.PromptDepth -gt 0) { return }
        $resumed = Get-TpmProgressNow
        $pause = $op.PauseStarted
        # Shift BOTH the group clock and every active stage clock, bounded when a stage started during the prompt.
        foreach ($task in (@($op) + @($op.Tasks.ToArray()))) {
            if ($null -eq $task.Finished) {
                foreach ($name in @('Started', 'StageStarted', 'RateAt')) {
                    $from = if ($task.$name -gt $pause) { $task.$name } else { $pause }
                    $task.$name = $task.$name.Add($resumed - $from)
                }
            }
            $task.PauseStarted = $null
        }
        $from = if ($op.LastChange -gt $pause) { $op.LastChange } else { $pause }
        $op.LastChange = $op.LastChange.Add($resumed - $from)
        if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $false }
        Publish-TpmProgressSnapshot -Op $op
        $position = Get-TpmProgressCursor
        $live.AwaitCleanRow = (-not $op.Redirected -and ($null -eq $position -or $position.Left -gt 0))
        $draw = ($op.Redirected -or ($null -ne $position -and $position.Left -eq 0))
    } finally { [System.Threading.Monitor]::Exit($live.Gate) }
    if ($draw) { Write-TpmProgressFrame -Force -Sync }
}

function Suspend-TpmProgressOutput {
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $op.Live.Abandoned -or $op.Redirected) { return $false }
    $live = $op.Live
    $renderFailure = $null
    [System.Threading.Monitor]::Enter($live.Gate)
    try {
        if ($live.PromptDepth -gt 0) { return $false }
        $live.OutputDepth++
        if ($live.OutputDepth -eq 1 -and -not [bool]$live['RenderDisabled']) {
            try { Remove-TpmProgressLiveRegion -Op $op } catch { $renderFailure = $_ }
        }
        if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $live.CursorVisible }
    } finally { [System.Threading.Monitor]::Exit($live.Gate) }
    if ($null -ne $renderFailure) { Disable-TpmProgressRenderer -Op $op -Failure $renderFailure }
    return $true
}

function Resume-TpmProgressOutput {
    $op = $script:TpmProgressOp
    if ($null -eq $op -or $op.Live.Abandoned -or $op.Redirected) { return }
    $live = $op.Live
    $draw = $false
    [System.Threading.Monitor]::Enter($live.Gate)
    try {
        if ($live.OutputDepth -le 0) { return }
        $live.OutputDepth--
        if ($live.OutputDepth -gt 0 -or $live.PromptDepth -gt 0) { return }
        if ($null -ne $live.CursorVisible) { Set-TpmProgressCursorVisible -Visible $false }
        $position = Get-TpmProgressCursor
        # Keep the guard until the next callback if ordinary output ended mid-row.
        $live.AwaitCleanRow = ($null -eq $position -or $position.Left -gt 0)
        $draw = -not $live.AwaitCleanRow
    } finally { [System.Threading.Monitor]::Exit($live.Gate) }
    if ($draw) { Write-TpmProgressFrame -Force -Sync }
}

Export-ModuleMember -Function Start-TpmProgressOperation, Set-TpmProgressStage, Complete-TpmProgressOperation, Stop-TpmProgressAbandoned, Test-TpmProgressStalled, Test-TpmProgressActive, Test-TpmProgressGroupOwned, Register-TpmProgressOutcome, Get-TpmProgressTitle, Get-TpmProgressState, Format-TpmProgressLine, Format-TpmProgressSegments, Format-TpmProgressBar, Format-TpmProgressSummary, Format-TpmProgressCount, Format-TpmProgressDuration, Get-TpmProgressPercent, Get-TpmProgressEta, Get-TpmProgressStyle, Get-TpmProgressCapabilities, Get-TpmProgressPalette, Test-TpmProgressColorEnabled, Test-TpmProgressOutputRedirected, Suspend-TpmProgressLine, Resume-TpmProgressLine, Suspend-TpmProgressOutput, Resume-TpmProgressOutput
Export-ModuleMember -Function Add-TpmProgressTask, Set-TpmProgressTask, Get-TpmProgressWidth
Export-ModuleMember -Function Close-TpmProgressSession
Export-ModuleMember -Function Set-TpmProgressRenderLogger, Test-TpmProgressCancellationError
Export-ModuleMember -Function Start-TpmProgressLongWait, Stop-TpmProgressLongWait

$ExecutionContext.SessionState.Module.OnRemove = {
    # Unloading a live module is an exit path too: stop the writer before restoring console state.
    try { Close-TpmProgressSession }
    finally { Unregister-TpmProgressExitHook }
}
