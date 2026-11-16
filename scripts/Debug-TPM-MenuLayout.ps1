#Requires -Version 5.1

param(
    [int]$Width = 0,
    [int]$Height = 0,
    [switch]$Render
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path $repoRoot 'TeknoParrot-Manager.ps1'

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($mainScript, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
}

# Loads EVERY function definition from the production script, not a
# hand-maintained allowlist. A hardcoded list of "the menu functions this
# diagnostic needs" silently drifts out of sync the moment a new dependency
# is added to the render pipeline -- confirmed as a real regression: this
# diagnostic crashed with "Limit-MainMenuBodyRowsToBudget: the term ... is
# not recognized" the moment that function was introduced (RC3 short-
# viewport truncation fix) and never added to the old allowlist. Loading
# every function is exactly the same pattern already used by
# Tests\TeknoParrot-Manager.Tests.ps1 and Tests\InstallHealthCheck.Tests.ps1
# to dot-source the production script's functions, so this diagnostic now
# stays correct automatically as the render pipeline gains or renames
# helpers, instead of needing a matching manual edit every time.
$functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
foreach ($fn in $functionAsts) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
$script:ActiveTpmWorkflowStatus = $null
$script:TpmWorkflowRendering = $false


$rawWindowWidth = $null
$rawWindowHeight = $null
$rawBufferWidth = $null
$rawBufferHeight = $null
$consoleWidth = $null
$consoleHeight = $null
$hostType = $null
$rawUiType = $null

try { $rawWindowWidth = [int]$Host.UI.RawUI.WindowSize.Width } catch {}
try { $rawWindowHeight = [int]$Host.UI.RawUI.WindowSize.Height } catch {}
try { $rawBufferWidth = [int]$Host.UI.RawUI.BufferSize.Width } catch {}
try { $rawBufferHeight = [int]$Host.UI.RawUI.BufferSize.Height } catch {}
try { $consoleWidth = [int][Console]::WindowWidth } catch {}
try { $consoleHeight = [int][Console]::WindowHeight } catch {}
try { $hostType = $Host.Name } catch {}
try { $rawUiType = $Host.UI.RawUI.GetType().FullName } catch {}

$detectedWidth = if ($Width -gt 0) { $Width } else { Get-ConsoleContentWidth }
$detectedHeight = if ($Height -gt 0) {
    $Height
} else {
    Get-ConsoleContentHeight
}

$fullTierLineCount = 4 + (@(Get-MainMenuSections | ForEach-Object {
    3 + ($_.Items | ForEach-Object { 1 + $_.FullDesc.Count } | Measure-Object -Sum).Sum
}) | Measure-Object -Sum).Sum

$tier = Get-ConsoleLayoutTier -Width $detectedWidth -Height $detectedHeight
$geometry = Get-MainMenuGeometry -Tier $tier -ViewportWidth $detectedWidth -ViewportHeight $detectedHeight
$heightConstrained = ($detectedHeight -gt 0 -and $fullTierLineCount -gt 0 -and $detectedHeight -lt $fullTierLineCount)
$widthConstrained = ($tier -ne 'Ultra')
$constrainedBy = if ($widthConstrained -and $heightConstrained) { 'width,height' } elseif ($widthConstrained) { 'width' } elseif ($heightConstrained) { 'height' } else { 'none' }

Write-Host "TPM menu layout debug"
Write-Host "---------------------"
Write-Host ("Host type                    : {0}" -f $hostType)
Write-Host ("Host.RawUI type              : {0}" -f $rawUiType)
Write-Host ("Host.RawUI.WindowSize.Width  : {0}" -f $rawWindowWidth)
Write-Host ("Host.RawUI.WindowSize.Height : {0}" -f $rawWindowHeight)
Write-Host ("Host.RawUI.BufferSize.Width  : {0}" -f $rawBufferWidth)
Write-Host ("Host.RawUI.BufferSize.Height : {0}" -f $rawBufferHeight)
Write-Host ("Console.WindowWidth          : {0}" -f $consoleWidth)
Write-Host ("Console.WindowHeight         : {0}" -f $consoleHeight)
Write-Host ("Selected viewport width      : {0}" -f $detectedWidth)
Write-Host ("Selected viewport height     : {0}" -f $detectedHeight)
Write-Host ("Required full lines          : {0}" -f $fullTierLineCount)
Write-Host ("Selected layout tier         : {0}" -f $geometry.Tier)
Write-Host ("Selected layout mode         : {0}" -f $geometry.Layout)
Write-Host ("Column width                 : {0}" -f $geometry.ColumnWidth)
Write-Host ("Description wrap width       : {0}" -f $geometry.WrapWidth)
Write-Host ("Total render width           : {0}" -f $geometry.MenuWidth)
Write-Host ("Constrained by               : {0}" -f $constrainedBy)

if ($Render) {
    Write-Host ""
    $screen = Render-MainMenuScreen -Tier $tier -Width $detectedWidth -Height $detectedHeight
    Write-ConsoleRenderRows -Rows $screen.Rows
}
