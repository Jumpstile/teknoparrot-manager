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

$menuFunctions = @(
    'Get-MainMenuSections',
    'Get-MainMenuItems',
    'Get-ConsoleLayoutTier',
    'Get-ConsoleContentWidth',
    'Get-MainMenuRenderMetrics',
    'Split-TextForMenuWidth',
    'Format-MainMenuItemLines',
    'Format-MainMenuSectionLines',
    'Join-MainMenuColumns',
    'Show-MainMenu'
)

$functionAsts = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $menuFunctions -contains $node.Name
}, $true)

foreach ($functionName in $menuFunctions) {
    $fn = $functionAsts | Where-Object { $_.Name -eq $functionName } | Select-Object -First 1
    if (-not $fn) { throw "Menu function not found: $functionName" }
    . ([scriptblock]::Create($fn.Extent.Text))
}

$rawWindowWidth = $null
$rawWindowHeight = $null
$rawBufferWidth = $null
$consoleWidth = $null
$consoleHeight = $null

try { $rawWindowWidth = [int]$Host.UI.RawUI.WindowSize.Width } catch {}
try { $rawWindowHeight = [int]$Host.UI.RawUI.WindowSize.Height } catch {}
try { $rawBufferWidth = [int]$Host.UI.RawUI.BufferSize.Width } catch {}
try { $consoleWidth = [int][Console]::WindowWidth } catch {}
try { $consoleHeight = [int][Console]::WindowHeight } catch {}

$detectedWidth = if ($Width -gt 0) { $Width } else { Get-ConsoleContentWidth }
$detectedHeight = if ($Height -gt 0) {
    $Height
} elseif ($rawWindowHeight -gt 0) {
    $rawWindowHeight
} elseif ($consoleHeight -gt 0) {
    $consoleHeight
} else {
    25
}

$fullTierLineCount = 4 + (@(Get-MainMenuSections | ForEach-Object {
    3 + ($_.Items | ForEach-Object { 1 + $_.FullDesc.Count } | Measure-Object -Sum).Sum
}) | Measure-Object -Sum).Sum

$tier = Get-ConsoleLayoutTier -Width $detectedWidth -Height $detectedHeight -RequiredFullLines $fullTierLineCount
$metrics = Get-MainMenuRenderMetrics -Tier $tier -Width $detectedWidth

Write-Host "TPM menu layout debug"
Write-Host "---------------------"
Write-Host ("Host.RawUI.WindowSize.Width  : {0}" -f $rawWindowWidth)
Write-Host ("Host.RawUI.WindowSize.Height : {0}" -f $rawWindowHeight)
Write-Host ("Host.RawUI.BufferSize.Width  : {0}" -f $rawBufferWidth)
Write-Host ("Console.WindowWidth          : {0}" -f $consoleWidth)
Write-Host ("Console.WindowHeight         : {0}" -f $consoleHeight)
Write-Host ("Detected width               : {0}" -f $detectedWidth)
Write-Host ("Detected height              : {0}" -f $detectedHeight)
Write-Host ("Required full lines          : {0}" -f $fullTierLineCount)
Write-Host ("Selected layout tier         : {0}" -f $metrics.SelectedTier)
Write-Host ("Selected layout mode         : {0}" -f $metrics.Layout)
Write-Host ("Label width                  : {0}" -f $metrics.LabelWidth)
Write-Host ("Description width            : {0}" -f $metrics.DescriptionWidth)
Write-Host ("Total render width           : {0}" -f $metrics.TotalRenderWidth)

if ($Render) {
    Write-Host ""
    Show-MainMenu -Tier $tier -Width $detectedWidth
}
