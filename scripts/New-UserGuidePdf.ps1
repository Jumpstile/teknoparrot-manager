#Requires -Version 7.0
<#
.SYNOPSIS
    Builds TeknoParrot-Manager-User-Guide.pdf (repo root) from docs\USER-GUIDE.md, or with
    -Guide Tester, TeknoParrot-Manager-Tester-Guide.pdf from docs\TESTER-GUIDE.md.
.DESCRIPTION
    Converts the Markdown guide to HTML (with the screenshots next to it) and prints it
    to PDF with Microsoft Edge in headless mode. Run this whenever the guide changes,
    then commit the PDF. The release package ships the committed PDF, and for the user guide
    a test fails if the PDF is older than the guide it was built from.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('User', 'Tester')][string]$Guide = 'User'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($SourceRoot)
$docs = Join-Path $root 'docs'
$markdownPath = Join-Path $docs $(if ($Guide -eq 'Tester') { 'TESTER-GUIDE.md' } else { 'USER-GUIDE.md' })
$pdfPath = Join-Path $root "TeknoParrot-Manager-$Guide-Guide.pdf"
$stampPath = Join-Path $docs 'TeknoParrot-Manager-User-Guide.source-sha256'
if (-not (Test-Path -LiteralPath $markdownPath -PathType Leaf)) { throw "GUIDE_MISSING: $markdownPath" }

$edge = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $edge) { throw 'EDGE_MISSING: Microsoft Edge is needed to print the PDF' }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-guide-pdf-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $body = (ConvertFrom-Markdown -LiteralPath $markdownPath).Html
    $css = @'
body { font-family: "Segoe UI", Arial, sans-serif; font-size: 11pt; line-height: 1.45; color: #1a1a1a; margin: 0; }
h1 { font-size: 24pt; border-bottom: 2px solid #1b6f77; padding-bottom: 4px; }
h2 { font-size: 17pt; border-bottom: 1px solid #bbb; padding-bottom: 3px; margin-top: 26px; page-break-after: avoid; }
h3 { font-size: 13pt; page-break-after: avoid; }
img { max-width: 100%; border: 1px solid #ccc; page-break-inside: avoid; }
table { border-collapse: collapse; width: 100%; margin: 8px 0; page-break-inside: auto; }
tr { page-break-inside: avoid; }
th, td { border: 1px solid #bbb; padding: 4px 8px; vertical-align: top; text-align: left; }
th { background: #eef3f4; }
pre { background: #f4f4f4; border: 1px solid #ddd; padding: 8px; white-space: pre-wrap; word-wrap: break-word; font-size: 9.5pt; page-break-inside: avoid; }
code { font-family: Consolas, "Courier New", monospace; font-size: 10pt; background: #f4f4f4; }
pre code { background: none; }
blockquote { border-left: 4px solid #1b6f77; margin-left: 0; padding-left: 12px; color: #333; }
a { color: #0b5a63; }
'@
    $html = "<!DOCTYPE html><html lang=`"en`"><head><meta charset=`"utf-8`"><title>TeknoParrot Manager: $Guide guide</title><style>$css</style></head><body>$body</body></html>"
    # The page sits in docs\ so relative image links such as images\13-tpm-main-menu.png resolve.
    $htmlPath = Join-Path $docs ('.user-guide-print-' + [guid]::NewGuid().ToString('N') + '.html')
    try {
        [System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))
        $tempPdf = Join-Path $work 'guide.pdf'
        $edgeProfile = Join-Path $work 'edge-profile'
        $uri = ([System.Uri]$htmlPath).AbsoluteUri
        $arguments = @(
            '--headless=new', '--disable-gpu', '--no-first-run', '--no-pdf-header-footer',
            "--user-data-dir=$edgeProfile", "--print-to-pdf=$tempPdf", $uri
        )
        $process = Start-Process -FilePath $edge -ArgumentList $arguments -PassThru -WindowStyle Hidden
        if (-not $process.WaitForExit(180000)) { try { $process.Kill() } catch {} ; throw 'EDGE_PRINT_TIMEOUT: Edge did not finish printing in 3 minutes' }
        if (-not (Test-Path -LiteralPath $tempPdf -PathType Leaf) -or (Get-Item -LiteralPath $tempPdf).Length -lt 10000) {
            throw 'EDGE_PRINT_FAILED: no usable PDF was produced'
        }
        Copy-Item -LiteralPath $tempPdf -Destination $pdfPath -Force
    } finally {
        if (Test-Path -LiteralPath $htmlPath) { Remove-Item -LiteralPath $htmlPath -Force }
    }
    $hash = (Get-FileHash -LiteralPath $markdownPath -Algorithm SHA256).Hash
    if ($Guide -eq 'User') { [System.IO.File]::WriteAllText($stampPath, $hash + "`n", (New-Object System.Text.UTF8Encoding($false))) }
    [pscustomobject]@{ Pdf = $pdfPath; Bytes = (Get-Item -LiteralPath $pdfPath).Length; SourceSha256 = $hash }
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
