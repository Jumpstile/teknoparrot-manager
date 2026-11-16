[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MainArchivePath
)
$ErrorActionPreference = 'Stop'

function Assert-DriverLane {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw $Message }
}
function Get-DriverLaneSha256 {
    param([byte[]]$Bytes)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $hash.Dispose() }
}
function Copy-DriverLaneZipMember {
    param($Archive,[string]$Name,[string]$Destination)
    $members = @($Archive.Entries | Where-Object { $_.FullName -ceq $Name })
    if ($members.Count -ne 1) { throw "Expected one exact ZIP member: $Name" }
    $input = $members[0].Open()
    $output = [IO.File]::Create($Destination)
    try { $input.CopyTo($output) }
    finally { $output.Dispose(); $input.Dispose() }
}
function New-DriverLaneCatalogContent {
    param($Entry)
    return (ConvertTo-Json -InputObject ([ordered]@{ Schema = 3; Entries = @($Entry) }) -Depth 20 -Compress)
}
function New-DriverLaneInputs {
    param([string]$Content,[string]$PatchId,[string]$ProfileId,[string]$GameRoot,[string]$PayloadRoot,[string]$RecoveryRoot,[string]$ProtectedRoot)
    $hash = Get-TpmPatchTextSha256 $Content
    return @{
        CatalogContent = $Content; CatalogSha256 = $hash; PatchId = $PatchId; ProfileId = $ProfileId
        GameRoot = $GameRoot; PayloadRoot = $PayloadRoot; RecoveryRoot = $RecoveryRoot
        ProtectedRoots = @($ProtectedRoot)
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('TpmDriverRecipeLane-' + [guid]::NewGuid().ToString('N'))
$functionFile = Join-Path $testRoot 'production-functions.ps1'
$mainRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$mainScript = Join-Path $mainRoot 'TeknoParrot-Manager.ps1'
$engineScript = Join-Path $mainRoot 'scripts\TpmRequiredPatchEngine.ps1'
$stateScript = Join-Path $mainRoot 'Tests\TpmExtractedScriptState.ps1'
$fragmentPath = Join-Path $PSScriptRoot 'driver-recipe-fragment.json'
$archive = $null
try {
    if (-not (Test-Path -LiteralPath $MainArchivePath -PathType Leaf)) { throw 'The exact Main ZIP path is unavailable.' }
    $MainArchivePath = [IO.Path]::GetFullPath($MainArchivePath)
    if ([IO.Path]::GetFileName($MainArchivePath) -cne 'Taisen Hot Gimmick 5 - Mirai Eigou (2.04)(2005-12-08)(JPN)[Taito Type X][TP].zip') {
        throw 'The supplied archive filename is not the exact recipe SourceSet.'
    }
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($mainScript,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Could not parse production function source.' }
    $definitions = ($ast.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] },$true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    [IO.File]::WriteAllText($functionFile,$definitions,(New-Object Text.UTF8Encoding($false)))
    . $functionFile
    . $stateScript
    . $engineScript
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

    $managerRoot = Join-Path $testRoot 'manager'
    $managerTemp = Join-Path $managerRoot 'temp'
    $productionGame = Join-Path $testRoot 'production-game'
    $productionPayload = Join-Path $testRoot 'production-payload'
    $productionRecovery = Join-Path $testRoot 'production-recovery'
    $productionProtected = Join-Path $testRoot 'production-protected'
    foreach ($directory in @($managerTemp,$productionGame,$productionPayload,$productionRecovery,$productionProtected)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    $script:TpmOwnedLayout = [pscustomobject]@{ Root = $managerRoot; Temp = $managerTemp; Backups = $managerRoot }

    $fragment = [IO.File]::ReadAllText($fragmentPath) | ConvertFrom-Json -ErrorAction Stop
    $entries = @($fragment.Entries)
    Assert-DriverLane ($entries.Count -eq 3) 'Expected exactly the three approved Taisen source restorations.'
    $catalogContent = ConvertTo-Json -InputObject ([ordered]@{ Schema = 3; Entries = $entries }) -Depth 20 -Compress
    $archive = [IO.Compression.ZipFile]::OpenRead($MainArchivePath)
    $gameExePath = Join-Path $productionGame 'game.exe'
    Copy-DriverLaneZipMember -Archive $archive -Name 'game.exe' -Destination $gameExePath
    $gameHash = (Get-FileHash -LiteralPath $gameExePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expectedExeHashes = @($entries.ExecutableSha256 | Select-Object -Unique)
    Assert-DriverLane ($expectedExeHashes.Count -eq 1 -and $gameHash -ceq $expectedExeHashes[0]) 'Main game.exe does not match the exact production fragment build pin.'

    foreach ($entry in $entries) {
        Assert-DriverLane ($entry.SourceRole -ceq 'Main' -and $entry.SourceSet -ceq [IO.Path]::GetFileName($MainArchivePath)) "Wrong source binding: $($entry.Id)"
        $staged = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot ([IO.Path]::GetDirectoryName($MainArchivePath))
        try {
            $destination = Resolve-TpmPatchPath $productionPayload ([string]$entry.Operations[0].Payload)
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            [IO.File]::Copy($staged.Payload,$destination,$false)
        } finally {
            if ($staged.Root -and (Test-Path -LiteralPath $staged.Root)) { Remove-Item -LiteralPath $staged.Root -Recurse -Force -ErrorAction Stop }
        }
        $input = New-DriverLaneInputs -Content $catalogContent -PatchId $entry.Id -ProfileId $entry.ProfileId -GameRoot $productionGame -PayloadRoot $productionPayload -RecoveryRoot $productionRecovery -ProtectedRoot $productionProtected
        $plan = Get-TpmPatchPlan @input
        Assert-DriverLane ($plan.Status -ceq 'Ready') "Production recipe failed engine validation/planning ($($entry.Id)): $($plan.Reason)"
        Assert-DriverLane ($plan.Operations.Count -eq 1 -and $plan.Operations[0].Operation -ceq 'CreateFile') "Unexpected operation plan for $($entry.Id)."
    }
    $archive.Dispose(); $archive = $null
    Write-Output 'PASS production fragment: Schema 3 catalog, exact Main game.exe, exact Main members, three engine plans Ready'

    $syntheticRoot = Join-Path $testRoot 'synthetic'
    $syntheticGame = Join-Path $syntheticRoot 'game'
    $syntheticPayload = Join-Path $syntheticRoot 'payload-root'
    $syntheticRecovery = Join-Path $syntheticRoot 'recovery'
    $syntheticProtected = Join-Path $syntheticRoot 'protected'
    foreach ($directory in @($syntheticGame,$syntheticPayload,$syntheticRecovery,$syntheticProtected)) {
        [IO.Directory]::CreateDirectory($directory) | Out-Null
    }
    $exeBytes = [byte[]](0x10,0x20,0x30,0x40,0x50)
    $payloadBytes = [Text.Encoding]::UTF8.GetBytes('synthetic driver payload only')
    $exePath = Join-Path $syntheticGame 'game.exe'
    [IO.File]::WriteAllBytes($exePath,$exeBytes)
    $payloadRelative = 'payload/synthetic-driver.dll'
    $payloadPath = Resolve-TpmPatchPath $syntheticPayload $payloadRelative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payloadPath)) | Out-Null
    [IO.File]::WriteAllBytes($payloadPath,$payloadBytes)
    $payloadSha = Get-DriverLaneSha256 $payloadBytes
    $sha1 = [Security.Cryptography.SHA1]::Create()
    try { $sourceSha1 = ([BitConverter]::ToString($sha1.ComputeHash($payloadBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha1.Dispose() }
    $target = 'TTX-Monitor.dll'
    $syntheticEntry = [pscustomobject]@{
        Id = 'synthetic-driver-create'; ProfileId = 'SyntheticTaisen'; BuildName = 'Synthetic test fixture'
        Executable = 'game.exe'; ExecutableSha256 = Get-DriverLaneSha256 $exeBytes
        SourceUrl = ''; SourceRevision = ''; SourceRole = 'Main'; SourceSet = 'synthetic-source.zip'
        SourceEntry = 'synthetic/driver.dll'; SourceSize = $payloadBytes.Length; SourceSha1 = $sourceSha1; SourceSha256 = $payloadSha
        ExclusiveGroup = ''; Prerequisites = @()
        Operations = @([pscustomobject]@{ Type = 'CreateFile'; Target = $target; BeforeState = 'Absent'; AfterSha256 = $payloadSha; Payload = $payloadRelative; PayloadSha256 = $payloadSha })
    }
    $syntheticContent = New-DriverLaneCatalogContent -Entry $syntheticEntry
    $syntheticInputs = New-DriverLaneInputs -Content $syntheticContent -PatchId $syntheticEntry.Id -ProfileId $syntheticEntry.ProfileId -GameRoot $syntheticGame -PayloadRoot $syntheticPayload -RecoveryRoot $syntheticRecovery -ProtectedRoot $syntheticProtected
    $targetPath = Resolve-TpmPatchPath $syntheticGame $target

    Assert-DriverLane ((Get-TpmPatchPlan @syntheticInputs).Status -ceq 'Ready') 'Synthetic create plan was not Ready.'
    $applied = Invoke-TpmCatalogPatch @syntheticInputs -Confirm:$false
    Assert-DriverLane ($applied.Status -ceq 'Applied') 'Synthetic absent-only create did not apply.'
    Assert-DriverLane ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash -ieq $payloadSha) 'Synthetic create bytes did not match the payload pin.'
    Assert-DriverLane ((Get-TpmPatchPlan @syntheticInputs).Status -ceq 'AlreadyApplied') 'Exact-after state was not idempotent.'
    Assert-DriverLane ((Invoke-TpmCatalogPatch @syntheticInputs -Confirm:$false).Status -ceq 'AlreadyApplied') 'Repeated apply changed an exact-after target.'
    Assert-DriverLane ((Undo-TpmCatalogPatch @syntheticInputs -RecoveryDirectory $applied.RecoveryDirectory -Confirm:$false).Status -ceq 'Restored') 'Synthetic undo did not restore the absent pre-state.'
    Assert-DriverLane (-not (Test-Path -LiteralPath $targetPath)) 'Synthetic undo did not remove its created file.'
    Write-Output 'PASS synthetic engine lifecycle: absent create, exact-after idempotency, undo to absent'

    $unknownBytes = [Text.Encoding]::UTF8.GetBytes('unknown operator data')
    [IO.File]::WriteAllBytes($targetPath,$unknownBytes)
    $unknownPlan = Get-TpmPatchPlan @syntheticInputs
    Assert-DriverLane ($unknownPlan.Status -ceq 'Unavailable') 'Unknown existing target was not refused.'
    Assert-DriverLane ((Get-DriverLaneSha256 ([IO.File]::ReadAllBytes($targetPath))) -ceq (Get-DriverLaneSha256 $unknownBytes)) 'Unknown existing target was modified.'
    Remove-Item -LiteralPath $targetPath -Force
    Write-Output 'PASS synthetic refusal: unknown existing bytes preserved'

    [IO.File]::WriteAllBytes($exePath,[Text.Encoding]::UTF8.GetBytes('wrong executable revision'))
    $wrongExe = Get-TpmPatchPlan @syntheticInputs
    Assert-DriverLane ($wrongExe.Status -ceq 'Unavailable' -and $wrongExe.Reason -match 'Executable revision mismatch') 'Wrong executable revision was not refused.'
    Assert-DriverLane (-not (Test-Path -LiteralPath $targetPath)) 'Wrong-executable refusal created a target.'
    [IO.File]::WriteAllBytes($exePath,$exeBytes)
    Write-Output 'PASS synthetic refusal: wrong executable revision'

    $modifiedApplied = Invoke-TpmCatalogPatch @syntheticInputs -Confirm:$false
    Assert-DriverLane ($modifiedApplied.Status -ceq 'Applied') 'Synthetic setup for modified-after undo did not apply.'
    $modifiedBytes = [Text.Encoding]::UTF8.GetBytes('operator changed after create')
    [IO.File]::WriteAllBytes($targetPath,$modifiedBytes)
    $undoRefused = $false
    try { [void](Undo-TpmCatalogPatch @syntheticInputs -RecoveryDirectory $modifiedApplied.RecoveryDirectory -Confirm:$false) }
    catch { $undoRefused = $true }
    Assert-DriverLane $undoRefused 'Undo accepted a created file whose bytes changed after application.'
    Assert-DriverLane ((Get-DriverLaneSha256 ([IO.File]::ReadAllBytes($targetPath))) -ceq (Get-DriverLaneSha256 $modifiedBytes)) 'Modified-after-undo refusal changed operator bytes.'
    Write-Output 'PASS synthetic refusal: modified-after-apply undo preserves changed bytes'
    Write-Output 'PASS all bounded driver recipe lane checks'
} finally {
    if ($archive) { $archive.Dispose() }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction Stop }
}
