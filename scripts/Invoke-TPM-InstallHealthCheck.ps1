param(
    [Parameter(Mandatory=$true)]
    [string]$TeknoParrotRoot,

    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$runId = [guid]::NewGuid().ToString('N')

if (!(Test-Path -LiteralPath $TeknoParrotRoot -PathType Container)) {
    throw "TeknoParrot root not found: $TeknoParrotRoot"
}
$TeknoParrotRoot = (Resolve-Path -LiteralPath $TeknoParrotRoot).Path

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) "TPM-TestHarness\Reports\InstallHealth-$stamp"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$logPath = Join-Path $OutDir 'InstallHealth.log'
$jsonPath = Join-Path $OutDir 'InstallHealth.json'
$mdPath = Join-Path $OutDir 'InstallHealth.md'

function Write-HealthLog {
    param(
        [string]$Level,
        [string]$Event,
        [string]$Message
    )
    $line = "{0} [{1}] [{2}] {3}" -f (Get-Date).ToString('o'), $Level, $Event, $Message
    $line | Out-File -FilePath $logPath -Append -Encoding utf8
}

function Add-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Details
    )
    $script:checks += [pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Details = $Details
    }
    $level = if ($Passed) { 'INFO' } else { 'WARN' }
    Write-HealthLog $level $Name $Details
}

function Test-XmlFolder {
    param(
        [string]$Name,
        [string]$Path
    )

    $files = @()
    $bad = @()
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $Path -File -Filter '*.xml' -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            try {
                [xml](Get-Content -LiteralPath $file.FullName -Raw) | Out-Null
            }
            catch {
                $bad += [pscustomobject]@{
                    Path = $file.FullName
                    Error = $_.Exception.Message
                }
            }
        }
    }

    [pscustomobject]@{
        Name = $Name
        Path = $Path
        FileCount = $files.Count
        InvalidCount = $bad.Count
        Invalid = $bad
    }
}

$checks = @()
Write-HealthLog 'INFO' 'Start' "RunId=$runId Root=$TeknoParrotRoot"

$gameProfilesPath = Join-Path $TeknoParrotRoot 'GameProfiles'
$userProfilesPath = Join-Path $TeknoParrotRoot 'UserProfiles'
$crosshairPath = Join-Path $TeknoParrotRoot 'pcsx2x6\TeknoParrot\crosshairs'

Add-Check 'TeknoParrotUi.exe exists' (Test-Path -LiteralPath (Join-Path $TeknoParrotRoot 'TeknoParrotUi.exe') -PathType Leaf) (Join-Path $TeknoParrotRoot 'TeknoParrotUi.exe')
Add-Check 'GameProfiles folder exists' (Test-Path -LiteralPath $gameProfilesPath -PathType Container) $gameProfilesPath
Add-Check 'UserProfiles folder exists' (Test-Path -LiteralPath $userProfilesPath -PathType Container) $userProfilesPath
Add-Check 'pcsx2x6 crosshair folder exists' (Test-Path -LiteralPath $crosshairPath -PathType Container) $crosshairPath

$gameXml = Test-XmlFolder 'GameProfiles XML' $gameProfilesPath
$userXml = Test-XmlFolder 'UserProfiles XML' $userProfilesPath

Add-Check 'GameProfiles XML parse' ($gameXml.InvalidCount -eq 0 -and $gameXml.FileCount -gt 0) "files=$($gameXml.FileCount) invalid=$($gameXml.InvalidCount)"
Add-Check 'UserProfiles XML parse' ($userXml.InvalidCount -eq 0) "files=$($userXml.FileCount) invalid=$($userXml.InvalidCount)"

$gameProfileFiles = @()
if (Test-Path -LiteralPath $gameProfilesPath -PathType Container) {
    $gameProfileFiles = @(Get-ChildItem -LiteralPath $gameProfilesPath -File -Filter '*.xml' -ErrorAction SilentlyContinue)
}
$duplicateNames = @($gameProfileFiles | Group-Object Name | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
Add-Check 'No duplicate GameProfiles filenames' ($duplicateNames.Count -eq 0) "duplicates=$($duplicateNames.Count)"

$profileCodeCandidates = @($gameProfileFiles | Where-Object { $_.BaseName -match 'centipede|chaos|zoids|timecrs|tekken' } | Select-Object -ExpandProperty Name)

$finished = Get-Date
$result = [ordered]@{
    RunId = $runId
    Started = $started.ToString('o')
    Finished = $finished.ToString('o')
    TeknoParrotRoot = $TeknoParrotRoot
    Checks = $checks
    GameProfiles = $gameXml
    UserProfiles = $userXml
    DuplicateGameProfileNames = $duplicateNames
    InterestingProfileCandidates = $profileCodeCandidates
    Status = if (@($checks | Where-Object { -not $_.Passed }).Count -eq 0) { 'PASS' } else { 'WARN' }
}

$result | ConvertTo-Json -Depth 8 | Out-File -FilePath $jsonPath -Encoding utf8

'# TPM Real Install Health Check' | Out-File -FilePath $mdPath -Encoding utf8
'' | Out-File -FilePath $mdPath -Append -Encoding utf8
("Run ID: {0}" -f $runId) | Out-File -FilePath $mdPath -Append -Encoding utf8
("Status: **{0}**" -f $result.Status) | Out-File -FilePath $mdPath -Append -Encoding utf8
("TeknoParrot root: {0}" -f $TeknoParrotRoot) | Out-File -FilePath $mdPath -Append -Encoding utf8
'' | Out-File -FilePath $mdPath -Append -Encoding utf8
'## Checks' | Out-File -FilePath $mdPath -Append -Encoding utf8
foreach ($check in $checks) {
    $mark = if ($check.Passed) { 'PASS' } else { 'WARN' }
    ('- [{0}] {1}: {2}' -f $mark, $check.Name, $check.Details) | Out-File -FilePath $mdPath -Append -Encoding utf8
}
'' | Out-File -FilePath $mdPath -Append -Encoding utf8
'## Artifacts' | Out-File -FilePath $mdPath -Append -Encoding utf8
('- JSON: {0}' -f $jsonPath) | Out-File -FilePath $mdPath -Append -Encoding utf8
('- Log: {0}' -f $logPath) | Out-File -FilePath $mdPath -Append -Encoding utf8

Write-Host ("Install health report: {0}" -f $mdPath)
