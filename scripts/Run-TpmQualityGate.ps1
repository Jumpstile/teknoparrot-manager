[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),
[Alias('RemediationReport')][Parameter(Mandatory)][string]$ReportPath,
    [switch]$CertificationMode
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath($RepoRoot)
$source = Join-Path $repo 'TeknoParrot-Manager.ps1'
$tests = Join-Path $repo 'Tests\TeknoParrot-Manager.Tests.ps1'
$supportTests = Join-Path $repo 'Tests\SupportPackage.Tests.ps1'
$settings = Join-Path $repo 'PSScriptAnalyzerSettings.psd1'
$reportForGate = $ReportPath
$failures = New-Object System.Collections.Generic.List[string]
function Invoke-GateStep([string]$Name, [scriptblock]$Action) {
    try {
        & $Action
        $exitCode = Get-Variable -Name LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $exitCode -and $exitCode -ne 0) { throw "exit code $exitCode" }
    }
    catch { [void]$failures.Add("$Name failed: $($_.Exception.Message)") }
}
Invoke-GateStep 'ASCII and parse' {
    $bytes = [IO.File]::ReadAllBytes($source)
    if (@($bytes | Where-Object { $_ -gt 127 }).Count -ne 0) { throw 'non-ASCII bytes found' }
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { throw "$($errors.Count) parse error(s) found" }
}
Invoke-GateStep 'PSScriptAnalyzer' {
    Invoke-ScriptAnalyzer -Path $source -Severity Error,Warning -Settings $settings -ErrorAction Stop
}
Invoke-GateStep 'Main Pester' { & pwsh -NoProfile -Command "Invoke-Pester -Path '$tests' -CI" }
if (Test-Path -LiteralPath $supportTests -PathType Leaf) { Invoke-GateStep 'SupportPackage Pester' { & pwsh -NoProfile -Command "Invoke-Pester -Path '$supportTests' -CI" } }
Invoke-GateStep 'git diff check' { git -C $repo diff --check }
$changedAt = (Get-Item -LiteralPath $source).LastWriteTimeUtc
Invoke-GateStep 'Permanent procedure gate' {
    & (Join-Path $PSScriptRoot 'Test-TpmPermanentProcedures.ps1') -RepoRoot $repo -ReportPath $reportForGate -SourcePath $source -ChangedAtUtc $changedAt
}
if ($CertificationMode) {
    $pester = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester -or $pester.Version -ne [version]'5.7.1') { [void]$failures.Add('Certification mode requires Pester 5.7.1.') }
}
if ($failures.Count -gt 0) { Write-Error (($failures | ForEach-Object { "QUALITY GATE FAIL: $_" }) -join [Environment]::NewLine); exit 1 }
Write-Output 'TPM quality gate passed.'
exit 0
