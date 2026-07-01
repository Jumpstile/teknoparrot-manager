#Requires -Version 5.1

param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedZip = (Resolve-Path -LiteralPath $ZipPath).Path
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedZip)
try {
    $entries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\\', '/') })

    $required = @(
        'TeknoParrot-Manager.ps1',
        'TeknoParrot-Manager.bat',
        'TeknoParrot-Manager-README.txt',
        'TeknoParrot-Manager-QuickStart.txt',
        'TeknoParrot-Manager-CHANGELOG.txt',
        'LICENSE',
        'tools/Invoke-TpmAutoUpdate.ps1',
        'tools/TpmAutoUpdate.Core.psm1'
    )

    foreach ($entry in $required) {
        if ($entries -notcontains $entry) {
            throw "Missing required ZIP entry: $entry"
        }
    }

    $crosshairs = @($entries | Where-Object { $_ -match '^Crosshairs/\d{3}\.png$' })
    if ($crosshairs.Count -ne 321) {
        throw "Expected 321 Crosshairs/*.png files, found $($crosshairs.Count)."
    }

    $rootCrosshairs = @($entries | Where-Object { $_ -match '^\d{3}\.png$' })
    if ($rootCrosshairs.Count -gt 0) {
        throw "Crosshair PNGs are incorrectly at ZIP root: $($rootCrosshairs[0..([Math]::Min(4, $rootCrosshairs.Count - 1))] -join ', ')"
    }

    $forbidden = @($entries | Where-Object {
        $_ -match '^(ReShade/|dgVoodoo2/|FFBPlugin/|BepInExCache/)' -or
        $_ -match '^(README\.md|QUICKSTART\.md|SECURITY\.md|LESSONS_LEARNED\.md)$' -or
        $_ -match '\.(log|zip|config\.json)$'
    })
    if ($forbidden.Count -gt 0) {
        throw "Forbidden ZIP entries: $($forbidden -join ', ')"
    }

    [pscustomobject]@{
        ZipPath             = $resolvedZip
        EntryCount          = $entries.Count
        CrosshairPngCount   = $crosshairs.Count
        RootCrosshairPngs   = $rootCrosshairs.Count
        ForbiddenEntryCount = $forbidden.Count
        Valid               = $true
    } | Format-List
} finally {
    $archive.Dispose()
}