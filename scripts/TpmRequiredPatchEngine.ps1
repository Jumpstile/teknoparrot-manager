$script:TpmRequiredPatchCatalogSha256 = '9AF6BF561E62EF08AA822859D1381F0F6A3D71DFAB01790BB81206A6AD668EE3'
# Largest single patch file the engine will stage, back up or replace (512 MiB). Files are always streamed and hashed in 64 KiB blocks, never read whole into memory.
$script:TpmPatchMaxBytes = 536870912
# Largest receipt.json any reader accepts (256 KiB). One limit for every reader, so a long receipt is never skipped by one and read by another.
$script:TpmReceiptMaxBytes = 262144

function Get-TpmRegisteredPatchContext {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$TpRoot,[Parameter(Mandatory)][string]$UserProfilesDir,[Parameter(Mandatory)][string]$ManagerRoot)
    foreach($root in @($TpRoot,$UserProfilesDir,$ManagerRoot)) { if (-not [IO.Path]::IsPathRooted($root) -or -not (Test-TpmNoReparsePath $root)) { throw 'Unsafe TeknoParrot Manager or registration root.' } }
    if ([IO.Path]::GetFullPath($UserProfilesDir) -ine [IO.Path]::GetFullPath((Join-Path $TpRoot 'UserProfiles')) -or
        -not (Test-Path -LiteralPath (Join-Path $TpRoot 'TeknoParrotUi.exe') -PathType Leaf)) { throw 'A configured TeknoParrot installation is required.' }
    if ($Entry.ProfileId -isnot [string] -or $Entry.ProfileId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { throw 'Invalid exact profile identity.' }
    $registeredProfile=Resolve-TpmPatchPath $UserProfilesDir ($Entry.ProfileId+'.xml')
    $official=Resolve-TpmPatchPath (Join-Path $TpRoot 'GameProfiles') ($Entry.ProfileId+'.xml')
    foreach($file in @($registeredProfile,$official)) {
        $item=Get-Item -LiteralPath $file -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Name -cne ($Entry.ProfileId+'.xml')) { throw 'The exact official and registered profile files are required.' }
    }
    $profileHash=(Get-FileHash -LiteralPath $registeredProfile -Algorithm SHA256).Hash
    $settings=New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null;$settings.MaxCharactersInDocument=4194304
    $reader=[Xml.XmlReader]::Create($registeredProfile,$settings);$doc=New-Object Xml.XmlDocument;$doc.XmlResolver=$null
    try{$doc.Load($reader)}finally{$reader.Dispose()}
    $gameNodes=@($doc.SelectNodes('/GameProfile/GamePath'))
    if($gameNodes.Count -ne 1){throw 'One registered GamePath is required.'}
    $gamePath=[string]$gameNodes[0].InnerText
    if ([string]::IsNullOrWhiteSpace($gamePath) -or -not [IO.Path]::IsPathRooted($gamePath)) { throw 'The registered game executable is unavailable.' }
    $gamePath=[IO.Path]::GetFullPath($gamePath.Trim())
    $relative=[string]$Entry.Executable;$suffix='\'+$relative.Replace('/','\')
    if (-not $gamePath.EndsWith($suffix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Registered GamePath does not match this patch executable.' }
    $gameRoot=$gamePath.Substring(0,$gamePath.Length-$suffix.Length)
    if ((Resolve-TpmPatchPath $gameRoot $relative) -ine $gamePath -or -not (Test-Path -LiteralPath $gamePath -PathType Leaf) -or
        (Get-FileHash -LiteralPath $registeredProfile -Algorithm SHA256).Hash -ine $profileHash) { throw 'The registered game identity changed.' }
    $recovery=Join-Path $ManagerRoot 'UpdateBackups\GamePatches'
    # Use RC8's existing owned layout when present; retain the production helper.
    $layoutVariable=Get-Variable -Name TpmOwnedLayout -Scope Script -ErrorAction SilentlyContinue
    if ($layoutVariable -and $layoutVariable.Value) {
        $layout=$layoutVariable.Value
        if (-not (Test-PathInside $layout.Backups $layout.Root) -or -not (Test-TpmNoReparsePath $layout.Backups)) { throw 'The TeknoParrot Manager backup layout is unsafe.' }
        $recovery=Join-Path $layout.Backups 'GamePatches'
    }
    if ($script:TpmOwnedLayout -and (Test-TpmPathOverlap $gameRoot $script:TpmOwnedLayout.Root)) { throw 'The registered game folder overlaps TeknoParrot Manager files.' }
    $protected=@((Join-Path $TpRoot 'TeknoParrotUi.exe'),(Join-Path $TpRoot 'GameProfiles'),$UserProfilesDir,
        (Join-Path $ManagerRoot 'TeknoParrot-Manager.ps1'),(Join-Path $ManagerRoot 'TeknoParrot-Manager.config.json'),
        (Join-Path $ManagerRoot 'tools'),(Join-Path $ManagerRoot 'Crosshairs'))
    return [pscustomobject]@{ProfileId=$Entry.ProfileId;ProfilePath=$registeredProfile;ProfileSha256=$profileHash;GamePath=$gamePath;GameRoot=$gameRoot;RecoveryRoot=$recovery;ProtectedRoots=$protected;Registered=$true}
}

function Test-TpmResetStoreBoundary {
    param([Parameter(Mandatory)][string]$BackupsRoot,[Parameter(Mandatory)][string]$StoreRoot)
    try {
        $backups=[IO.Path]::GetFullPath($BackupsRoot).TrimEnd('\','/')
        $store=[IO.Path]::GetFullPath($StoreRoot).TrimEnd('\','/')
        if($store -ieq $backups -or -not (Test-PathInside $store $backups)){throw 'Receipt history store is outside the patch backup root.'}
        if(-not [IO.Directory]::Exists($backups) -or -not (Test-TpmNoReparsePath $backups) -or
            -not (Get-Item -LiteralPath $backups -Force -ErrorAction Stop).PSIsContainer){throw 'Patch backup root is unavailable or unsafe.'}
        foreach($path in @($store,(Join-Path $store 'Snapshots'))){
            if([IO.File]::Exists($path) -or ((Test-Path -LiteralPath $path -ErrorAction SilentlyContinue) -and -not [IO.Directory]::Exists($path))){throw 'Receipt history path is not a directory.'}
            if(-not (Test-TpmNoReparsePath $path)){throw 'Receipt history path contains a reparse point.'}
        }
        return [pscustomobject]@{Verified=$true;Reason='Receipt history path is contained and non-reparse.'}
    } catch {
        return [pscustomobject]@{Verified=$false;Reason=$_.Exception.Message}
    }
}

function Test-TpmResetSnapshot {
    param([Parameter(Mandatory)][string]$SnapshotPath)
    $result=[pscustomobject]@{Verified=$false;Manifest=$null;Reason='Snapshot is not verified.'}
    try {
        $snapshot=[IO.Path]::GetFullPath($SnapshotPath).TrimEnd('\','/')
        $snapshotId=[IO.Path]::GetFileName($snapshot)
        if($snapshotId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'){throw 'Receipt history snapshot identifier is invalid.'}
        $snapshotsRoot=[IO.Path]::GetDirectoryName($snapshot)
        $storeRoot=[IO.Path]::GetDirectoryName($snapshotsRoot)
        $backupsRoot=[IO.Path]::GetDirectoryName($storeRoot)
        $boundary=Test-TpmResetStoreBoundary -BackupsRoot $backupsRoot -StoreRoot $storeRoot
        if(-not $boundary.Verified -or -not [IO.Directory]::Exists($snapshot) -or -not (Test-TpmNoReparsePath $snapshot)){throw 'Receipt history snapshot path is unavailable or unsafe.'}
        $manifestPath=Join-Path $snapshot 'manifest.json'
        if(-not (Test-TpmNoReparsePath $manifestPath) -or -not [IO.File]::Exists($manifestPath)){throw 'Receipt history manifest is missing or unsafe.'}
        if((Get-Item -LiteralPath $manifestPath -ErrorAction Stop).Length -gt 16384){throw 'Receipt history manifest exceeds its size limit.'}
        $manifest=[IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json -ErrorAction Stop
        $fields=@('Schema','SnapshotId','Kind','PayloadRetention','Paths')
        $names=@($manifest.PSObject.Properties.Name)
        if(@($names|Where-Object {$_ -notin $fields}).Count -or @($fields|Where-Object {$_ -notin $names}).Count){throw 'Receipt history manifest fields are invalid.'}
        if(($manifest.Schema -isnot [int] -and $manifest.Schema -isnot [long]) -or $manifest.Schema -ne 1 -or
            $manifest.SnapshotId -cne $snapshotId -or $manifest.Kind -cne 'Checkpoint' -or $manifest.PayloadRetention -cne 'StateOnly'){throw 'Receipt history manifest identity is invalid.'}
        $paths=@($manifest.Paths)
        if($paths.Count -ne 1){throw 'Receipt history checkpoint must contain one target.'}
        $pathFields=@('TargetPath','Exists','IsDirectory','Sha256')
        $pathNames=@($paths[0].PSObject.Properties.Name)
        if(@($pathNames|Where-Object {$_ -notin $pathFields}).Count -or @($pathFields|Where-Object {$_ -notin $pathNames}).Count){throw 'Receipt history target fields are invalid.'}
        if($paths[0].TargetPath -isnot [string] -or $paths[0].Exists -isnot [bool] -or $paths[0].IsDirectory -isnot [bool] -or
            $paths[0].Sha256 -isnot [string] -or -not $paths[0].Exists -or $paths[0].IsDirectory -or $paths[0].Sha256 -notmatch '^[A-Fa-f0-9]{64}$'){throw 'Receipt history target state is invalid.'}
        $target=[IO.Path]::GetFullPath($paths[0].TargetPath)
        if(-not (Test-PathInside $target $backupsRoot) -or -not (Test-TpmNoReparsePath $target) -or
            -not [IO.File]::Exists($target) -or (Get-Item -LiteralPath $target -ErrorAction Stop).Length -gt $script:TpmReceiptMaxBytes -or
            (Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash -ine $paths[0].Sha256){throw 'Receipt history target does not match its captured state.'}
        $result.Verified=$true
        $result.Manifest=$manifest
        $result.Reason='Receipt history checkpoint matches the retained target.'
    } catch { $result.Reason=$_.Exception.Message }
    return $result
}

function New-TpmResetSnapshot {
    param(
        [Parameter(Mandatory)][string]$BackupsRoot,
        [Parameter(Mandatory)][string]$StoreRoot,
        [Parameter(Mandatory)][string]$SnapshotId,
        [Parameter(Mandatory)][ValidateSet('Checkpoint')][string]$Kind,
        [Parameter(Mandatory)][string[]]$TargetPaths,
        [Parameter(Mandatory)][ValidateSet('StateOnly')][string]$PayloadRetention
    )
    $locks=@()
    try {
        if($SnapshotId -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$' -or $TargetPaths.Count -ne 1){throw 'Receipt history checkpoint identity or target count is invalid.'}
        $backups=[IO.Path]::GetFullPath($BackupsRoot)
        $store=[IO.Path]::GetFullPath($StoreRoot)
        $boundary=Test-TpmResetStoreBoundary -BackupsRoot $backups -StoreRoot $store
        if(-not $boundary.Verified){throw $boundary.Reason}
        $target=[IO.Path]::GetFullPath($TargetPaths[0])
        if(-not (Test-PathInside $target $backups) -or -not (Test-TpmNoReparsePath $target) -or
            -not [IO.File]::Exists($target) -or (Get-Item -LiteralPath $target -ErrorAction Stop).Length -gt $script:TpmReceiptMaxBytes){throw 'Receipt history target is missing, oversized, or outside the backup root.'}
        $targetHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
        $snapshot=Join-Path (Join-Path $store 'Snapshots') $SnapshotId
        $manifestPath=Join-Path $snapshot 'manifest.json'
        if($snapshot.Length -gt 247 -or $manifestPath.Length -gt 247){throw 'Receipt history snapshot path is too long.'}
        if([IO.Directory]::Exists($snapshot) -or [IO.File]::Exists($snapshot)){
            $existing=Test-TpmResetSnapshot -SnapshotPath $snapshot
            if($existing.Verified -and $existing.Manifest.Kind -ceq $Kind -and
                @($existing.Manifest.Paths)[0].TargetPath -ieq $target -and @($existing.Manifest.Paths)[0].Sha256 -ieq $targetHash){
                return [pscustomobject]@{Status='VERIFIED';PublicationState='VERIFIED';Reason='The matching receipt history checkpoint already exists.'}
            }
            throw 'Receipt history checkpoint already exists with different or invalid state; it was not overwritten.'
        }
        [void][IO.Directory]::CreateDirectory($store)
        [void][IO.Directory]::CreateDirectory((Join-Path $store 'Snapshots'))
        [void][IO.Directory]::CreateDirectory($snapshot)
        if(-not (Test-TpmNoReparsePath $snapshot)){throw 'Receipt history snapshot directory is unsafe.'}
        $locks+=@(Open-TpmPatchDirectoryBoundary $store)
        $locks+=@(Open-TpmPatchDirectoryBoundary (Join-Path $store 'Snapshots'))
        $locks+=@(Open-TpmPatchDirectoryBoundary $snapshot)
        $manifest=[ordered]@{
            Schema=1;SnapshotId=$SnapshotId;Kind=$Kind;PayloadRetention=$PayloadRetention
            Paths=@([ordered]@{TargetPath=$target;Exists=$true;IsDirectory=$false;Sha256=$targetHash})
        }
        $text=ConvertTo-Json -InputObject $manifest -Depth 6
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($text)
        $stream=Open-TpmPatchCreationFile -Path $manifestPath -NewFile -MaximumBytes 16384
        try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
        $check=Test-TpmResetSnapshot -SnapshotPath $snapshot
        if(-not $check.Verified -or $check.Manifest.SnapshotId -cne $SnapshotId){throw ('Receipt history checkpoint readback failed: '+$check.Reason)}
        return [pscustomobject]@{Status='VERIFIED';PublicationState='VERIFIED';Reason='Receipt history checkpoint published and read back.'}
    } catch {
        return [pscustomobject]@{Status='FAILED';PublicationState='UNVERIFIED';Reason=$_.Exception.Message}
    } finally {
        foreach($boundary in $locks){foreach($handle in $boundary){$handle.Dispose()}}
    }
}

# Every readable saved undo copy (receipt) in the patch backup folder, with the folder it sits in. One place reads them, so the
# list of games to undo and the lookup of one game's copies cannot disagree.
function Get-TpmPatchReceiptRecords {
    param([Parameter(Mandatory)][string]$RecoveryRoot)
    if (-not (Test-TpmNoReparsePath $RecoveryRoot)) { throw 'Unsafe patch backup folder.' }
    if (-not (Test-Path -LiteralPath $RecoveryRoot -PathType Container)) { return }
    foreach($directory in @(Get-ChildItem -LiteralPath $RecoveryRoot -Directory -ErrorAction Stop)) {
        if ($directory.Name -notmatch '^[a-f0-9]{32}$' -or -not (Test-TpmNoReparsePath $directory.FullName)) { continue }
        $receiptPath=Join-Path $directory.FullName 'receipt.json'
        if (-not (Test-TpmNoReparsePath $receiptPath) -or -not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { continue }
        try {
            if ((Get-Item -LiteralPath $receiptPath).Length -gt $script:TpmReceiptMaxBytes) { continue }
            $receipt=[IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json -ErrorAction Stop
            # A receipt without its patch, profile and game identity can never match a game, so it is not a record.
            if ($receipt -is [pscustomobject] -and @('PatchId','ProfileId','GameRoot' | Where-Object { $null -eq $receipt.PSObject.Properties[$_] }).Count -eq 0) {
                [pscustomobject]@{ Directory=$directory.FullName; Receipt=$receipt }
            }
        } catch { continue }
    }
}

function Get-TpmPatchRecoveryDirectories {
    param([Parameter(Mandatory)]$Request,[Parameter(Mandatory)][string]$PatchId)
    foreach($record in @(Get-TpmPatchReceiptRecords -RecoveryRoot $Request.Context.RecoveryRoot)) {
        $receipt=$record.Receipt
        if ($receipt.PatchId -ceq $PatchId -and $receipt.ProfileId -ceq $Request.Context.ProfileId -and $receipt.GameRoot -ieq $Request.Context.GameRoot) { $record.Directory }
    }
}

# The ids of the patches that still have something to undo: a saved copy that is not marked as already put back or rolled back.
# A copy with no recorded state is kept in the list, so a game is never hidden when it might still be undone; Undo checks the copy itself.
function Get-TpmUndoablePatchIds {
    param([Parameter(Mandatory)][string]$RecoveryRoot)
    $ids = New-Object System.Collections.Generic.List[string]
    foreach($record in @(Get-TpmPatchReceiptRecords -RecoveryRoot $RecoveryRoot)) {
        $state = if ($record.Receipt.PSObject.Properties['State']) { [string]$record.Receipt.State } else { '' }
        if ($state -cin @('Restored','RolledBack')) { continue }
        if ($record.Receipt.PatchId -is [string] -and -not $ids.Contains($record.Receipt.PatchId)) { [void]$ids.Add($record.Receipt.PatchId) }
    }
    return $ids.ToArray()
}

function Get-TpmPatchTextSha256 {
    param([string]$Text)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '') }
    finally { $hasher.Dispose() }
}

function Assert-TpmPatchFields {
    param($Value, [string[]]$Required)
    if ($Value -isnot [pscustomobject]) { throw 'Missing/invalid catalog object.' }
    $names = @($Value.PSObject.Properties.Name)
    if (@($names | Where-Object { $_ -notin $Required }).Count -or
        @($Required | Where-Object { $_ -notin $names }).Count) { throw 'Unknown or missing catalog fields.' }
}

# Longest name the engine adds under a folder, so every later path can be checked BEFORE anything is written.
# Game folder: sibling temp files (.tpm-create-<32 hex>.tmp is the longest of .tpm-batch-, .tpm-aside-, .tpm-create-, .tpm-undo-).
# Recovery root: <run>\UpdateBackups\TeknoParrotManager_<timestamp>_<n>\original-<n>.bin, or <run>\receipt.json.<32 hex>.tmp.
# The receipt-history checkpoint kept after an undo (ReceiptHistory\Snapshots\<32 hex>_<State>\manifest.json under the same recovery root)
# is 83 characters and is checked against 247, so it fits inside this budget; the 'Undo works at the longest recovery folder' test proves it.
function Get-TpmPatchAppendedPathLength {
    param([Parameter(Mandatory)][ValidateSet('Game','Recovery')][string]$Kind)
    $guid = '0' * 32
    if ($Kind -ceq 'Game') { return (1 + ('.tpm-create-' + $guid + '.tmp').Length) }
    $backup = 1 + $guid.Length + 1 + 'UpdateBackups'.Length + 1 + 'TeknoParrotManager_yyyy-MM-dd_HH-mm-ss_100'.Length + 1 + 'original-255.bin'.Length
    $receipt = 1 + $guid.Length + 1 + ('receipt.json.' + $guid + '.tmp').Length
    return [Math]::Max($backup, $receipt)
}

function Assert-TpmPatchFolderBudget {
    param([Parameter(Mandatory)][string]$Folder, [Parameter(Mandatory)][ValidateSet('Game','Recovery')][string]$Kind)
    if (-not (Test-TpmPathLengthAllowed -Length ($Folder.Length + (Get-TpmPatchAppendedPathLength $Kind)))) {
        throw ('A folder path is too long for Windows to patch safely (' + $Folder.Length + ' characters). Move TeknoParrot or the game to a folder with a shorter path.')
    }
}

function Resolve-TpmPatchPath {
    param([string]$Root, [string]$Relative, [switch]$Staging, [switch]$ForUndo)
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '[:\\/]{2}|:' -or [IO.Path]::IsPathRooted($Relative)) { throw 'Invalid relative patch path.' }
    foreach ($part in ($Relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -match '[<>:"|?*\p{Cc}]' -or $part -match '[. ]$|^(CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])(\.|$)' -or $part -in @('.', '..')) { throw 'Unsafe patch path component.' }
    }
    # A game saved on a drive that is not connected stops here with one plain reason. Join-Path would print a raw red "Cannot find drive" error for every game.
    $driveRoot = try { [IO.Path]::GetPathRoot($Root) } catch { '' }
    if ($driveRoot -match '^[A-Za-z]:\\$' -and -not [IO.Directory]::Exists($driveRoot)) { throw ('The drive {0} is not connected.' -f $driveRoot.Substring(0, 2)) }
    $joined = [IO.Path]::Combine($Root, $Relative)
    $tooLong = 'A file path is too long for Windows to patch safely ({0} characters). Move TeknoParrot or the game to a folder with a shorter path.'
    if (-not $Staging -and -not $ForUndo -and -not (Test-TpmPathLengthAllowed -Length $joined.Length)) { throw ($tooLong -f $joined.Length) }
    try { $path = [IO.Path]::GetFullPath($joined) } catch [IO.PathTooLongException] { throw ($tooLong -f $joined.Length) }
    if (-not $Staging -and -not $ForUndo -and -not (Test-TpmPathLengthAllowed -Length $path.Length)) { throw ($tooLong -f $path.Length) }
    if (-not (Test-PathInside $path $Root) -or -not (Test-TpmNoReparsePath $path)) { throw 'Patch path containment/reparse check failed.' }
    return $path
}

function Get-TpmPatchHardwareVendor {
    param([AllowNull()][object]$Evidence)
    if ($null -eq $Evidence) {
        return [pscustomobject]@{ State='UNKNOWN'; Vendor=''; Name=''; Reason='No captured GPU evidence was supplied.' }
    }
    $result = Get-DetectedGpuVendor -HardwareEvidence $Evidence -RequireUnambiguous
    return [pscustomobject]@{ State=[string]$result.State; Vendor=[string]$result.Vendor; Name=[string]$result.Name; Reason=[string]$result.Reason }
}

# Windows lists the basic display adapter and remote or virtual screens next to the real video cards. They cannot run a game,
# so they are ignored (the same names Get-DetectedGpuVendor ignores when it asks Windows itself). One real card is the card
# the game uses. Several real cards of one make are the same make. Real cards of different makes (a laptop with Intel and
# NVIDIA) are asked about once, in plain words; no answer keeps the safe refusal.
function Resolve-TpmPatchHardwareEvidence {
    param([AllowNull()][object]$Evidence)
    if ($null -eq $Evidence -or -not $Evidence.PSObject.Properties['Adapters']) { return $Evidence }
    $real = @(@($Evidence.Adapters) | Where-Object { [string]$_.Name -notmatch '(?i)microsoft|virtual|remote' })
    if ($real.Count -eq 0) { return $Evidence }
    $options = @(foreach ($adapter in $real) {
        $single = [pscustomobject]@{ Adapters = @($adapter); MultiGpuAmbiguous = $false; ActiveGpuConfidence = 'INFERRED'; ActiveAdapterIndex = 0; ActiveAdapterName = [string]$adapter.Name }
        [pscustomobject]@{ Name = [string]$adapter.Name; Evidence = $single; Vendor = [string](Get-TpmPatchHardwareVendor -Evidence $single).Vendor }
    })
    $vendors = @($options | ForEach-Object { $_.Vendor } | Select-Object -Unique)
    if ($options.Count -eq 1 -or $vendors.Count -eq 1) { return $options[0].Evidence }
    Write-TpmText -Text 'This PC has more than one graphics card, and some patches are made for one make of card.' -Color Cyan -BlankBefore -HangingIndent 2
    for ($i = 0; $i -lt $options.Count; $i++) { Write-TpmText -Text ('{0}) {1}' -f ($i + 1), $options[$i].Name) -HangingIndent 3 }
    Write-TpmText -Text 'Press Enter if you are not sure. Patches made for one make of card are then skipped.' -BlankBefore -BlankAfter -HangingIndent 2
    $answer = ([string](Read-HostSafe '  Which card does the game use? Type its number')).Trim()
    $number = 0
    if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $options.Count) { return $options[$number - 1].Evidence }
    return $Evidence
}

function Resolve-TpmPatchVariantDecision {
    param(
        [Parameter(Mandatory)][object[]]$Entries,
        [Parameter(Mandatory)][string]$PatchId,
        [Parameter(Mandatory)][string]$ProfileId,
        [AllowNull()][object]$HardwareEvidence
    )
    $selectedEntry = @($Entries | Where-Object { $_.Id -ceq $PatchId -and $_.ProfileId -ceq $ProfileId })
    if ($selectedEntry.Count -ne 1) {
        return [pscustomobject]@{ Status='INVALID'; SelectedId=''; Reason='The requested recipe identity is missing or duplicated.' }
    }
    $entry = $selectedEntry[0]
    $group = if ($entry.PSObject.Properties['ExclusiveGroup']) { [string]$entry.ExclusiveGroup } else { '' }
    $variants = @(
        if ($group) {
            $Entries | Where-Object {
                $_.ProfileId -ceq $ProfileId -and $_.PSObject.Properties['ExclusiveGroup'] -and
                $_.ExclusiveGroup -ceq $group -and $_.ExecutableSha256 -ieq $entry.ExecutableSha256
            }
        } else {
            $entry
        }
    )
    $conditional = @($variants | Where-Object { $_.PSObject.Properties['HardwarePredicate'] -and $null -ne $_.HardwarePredicate })
    if ($conditional.Count -eq 0) {
        if ($variants.Count -gt 1) {
            return [pscustomobject]@{ Status='AMBIGUOUS'; SelectedId=''; Reason='More than one mutually exclusive recipe matches this exact build and no hardware predicate distinguishes them.' }
        }
        return [pscustomobject]@{ Status='SELECTED'; SelectedId=[string]$entry.Id; Reason='' }
    }
    $gpu = Get-TpmPatchHardwareVendor -Evidence $HardwareEvidence
    if ($gpu.State -ne 'KNOWN') {
        return [pscustomobject]@{ Status=$gpu.State; SelectedId=''; Reason=$gpu.Reason }
    }
    $eligible = New-Object System.Collections.Generic.List[object]
    foreach ($variant in $variants) {
        if (-not $variant.PSObject.Properties['HardwarePredicate'] -or $null -eq $variant.HardwarePredicate) {
            [void]$eligible.Add($variant)
            continue
        }
        $predicate = $variant.HardwarePredicate
        if ($predicate -isnot [pscustomobject]) {
            return [pscustomobject]@{ Status='INVALID'; SelectedId=''; Reason='The recipe hardware predicate is invalid.' }
        }
        $predicateNames = @($predicate.PSObject.Properties.Name)
        if ($predicateNames.Count -ne 1 -or $predicateNames[0] -cne 'Vendor' -or
            [string]$predicate.Vendor -cnotin @('AMD','NVIDIA','Intel')) {
            return [pscustomobject]@{ Status='INVALID'; SelectedId=''; Reason='The recipe hardware predicate is invalid.' }
        }
        if ([string]$predicate.Vendor -ceq $gpu.Vendor) { [void]$eligible.Add($variant) }
    }
    if ($eligible.Count -eq 0) {
        return [pscustomobject]@{ Status='NOT_APPLICABLE'; SelectedId=''; Reason='No bundled variant applies to the established adapter.' }
    }
    if ($eligible.Count -gt 1) {
        return [pscustomobject]@{ Status='AMBIGUOUS'; SelectedId=''; Reason='More than one mutually exclusive recipe matches this game and adapter.' }
    }
    return [pscustomobject]@{ Status='SELECTED'; SelectedId=[string]$eligible[0].Id; Reason='' }
}

function Get-TpmPatchPlan {
    param(
        [Parameter(Mandatory)][string]$CatalogContent,
        [Parameter(Mandatory)][string]$CatalogSha256,
        [Parameter(Mandatory)][string]$PatchId,
        [Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot,
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$RecoveryRoot,
        [Parameter(Mandatory)][string[]]$ProtectedRoots,
        [AllowNull()][object]$HardwareEvidence = $null,
        [switch]$ForUndo,
        [string]$ReceiptDirectory = ''
    )
    try {
        # Length checks come first so a long root gets the plain message, not the generic "Invalid or reparse root." from the path walk below.
        if (-not $ForUndo -and [IO.Path]::IsPathRooted($GameRoot) -and [IO.Path]::IsPathRooted($RecoveryRoot)) {
            Assert-TpmPatchFolderBudget ([IO.Path]::GetFullPath($GameRoot).TrimEnd('\', '/')) 'Game'
            Assert-TpmPatchFolderBudget ([IO.Path]::GetFullPath($RecoveryRoot).TrimEnd('\', '/')) 'Recovery'
        }
        foreach ($root in @($GameRoot, $PayloadRoot, $RecoveryRoot)) {
            if (-not [IO.Path]::IsPathRooted($root) -or -not (Test-TpmNoReparsePath $root)) { throw 'Invalid or reparse root.' }
        }
        $game = [IO.Path]::GetFullPath($GameRoot)
        if ($game.Length -gt [IO.Path]::GetPathRoot($game).Length) { $game = $game.TrimEnd('\', '/') }
        $payloadRootPath = [IO.Path]::GetFullPath($PayloadRoot)
        $recovery = [IO.Path]::GetFullPath($RecoveryRoot)
        if (-not (Test-Path -LiteralPath $game -PathType Container) -or (-not $ForUndo -and -not (Test-Path -LiteralPath $payloadRootPath -PathType Container))) { throw 'Game/payload root unavailable.' }
        if ((Test-TpmPathOverlap $game $payloadRootPath) -or (Test-TpmPathOverlap $game $recovery) -or (Test-TpmPathOverlap $payloadRootPath $recovery)) { throw 'Patch roots overlap.' }
        if ($ProtectedRoots.Count -eq 0) { throw 'Explicit protected roots required.' }
        foreach ($protected in $ProtectedRoots) {
            if (-not [IO.Path]::IsPathRooted($protected)) { throw 'Invalid protected root.' }
            if ((Test-TpmPathOverlap $game $protected) -or (Test-TpmPathOverlap $recovery $protected)) { throw 'Protected root overlap.' }
        }
        if ($CatalogSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid catalog pin.' }
        if ((Get-TpmPatchTextSha256 $CatalogContent) -ine $CatalogSha256) { throw 'Catalog content hash mismatch.' }
        $catalog = $CatalogContent | ConvertFrom-Json -ErrorAction Stop
        Assert-TpmPatchFields $catalog @('Schema', 'Entries')
        if (($catalog.Schema -isnot [int] -and $catalog.Schema -isnot [long]) -or $catalog.Schema -ne 3 -or $catalog.Entries -isnot [array] -or @($catalog.Entries).Count -eq 0) { throw 'Unsupported catalog schema.' }
        $ids = @{}
        $fields = @('Id','ProfileId','Executable','ExecutableSha256','SourceUrl','SourceRevision','Operations','ExclusiveGroup')
        $optional = @('BuildName','SourceRole','SourceSet','SourceEntry','AlternateSources','SourceSize','SourceSha1','SourceSha256','Prerequisites','HardwarePredicate','AllowExecutableSelfPatch')
        foreach ($entry in @($catalog.Entries)) {
            $entryNames = @($entry.PSObject.Properties.Name)
            $unknown = @($entryNames | Where-Object { $_ -notin ($fields + $optional) })
            $missing = @($fields | Where-Object { $_ -notin $entryNames })
            if ($unknown.Count -or $missing.Count) { throw 'Unknown or missing catalog fields.' }
            foreach ($field in @('BuildName','SourceRole','SourceSet','SourceEntry','SourceSha1','SourceSha256')) {
                $property=$entry.PSObject.Properties[$field]
                if ($property -and $property.Value -isnot [string]) { throw 'Invalid local recipe metadata.' }
            }
            if ($entry.PSObject.Properties['SourceSize'] -and
                (($entry.SourceSize -isnot [int] -and $entry.SourceSize -isnot [long]) -or $entry.SourceSize -lt 0)) { throw 'Invalid source size.' }
            if ($entry.PSObject.Properties['Prerequisites'] -and $entry.Prerequisites -isnot [array]) { throw 'Invalid prerequisite list.' }
            if ($entry.PSObject.Properties['SourceSha1'] -and [string]$entry.SourceSha1 -notmatch '^[a-fA-F0-9]{40}$') { throw 'Invalid source SHA-1 pin.' }
            if ($entry.PSObject.Properties['SourceSha256'] -and [string]$entry.SourceSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid source SHA-256 pin.' }
            if ($entry.PSObject.Properties['AllowExecutableSelfPatch'] -and $entry.AllowExecutableSelfPatch -isnot [bool]) { throw 'Invalid executable self-patch opt-in.' }
            if ($entry.PSObject.Properties['AlternateSources']) {
                if ($entry.AlternateSources -isnot [array] -or @($entry.AlternateSources).Count -eq 0) { throw 'Invalid alternate source list.' }
                foreach ($alternate in @($entry.AlternateSources)) {
                    Assert-TpmPatchFields $alternate @('SourceSet','SourceEntry')
                    if ($alternate.SourceSet -isnot [string] -or $alternate.SourceEntry -isnot [string] -or
                        [string]::IsNullOrWhiteSpace($alternate.SourceSet) -or [string]::IsNullOrWhiteSpace($alternate.SourceEntry) -or
                        [IO.Path]::GetFileName($alternate.SourceSet) -cne $alternate.SourceSet -or $alternate.SourceSet -match '[<>:"|?*\p{Cc}]') { throw 'Invalid alternate source.' }
                }
            }
            foreach ($field in @('Id', 'ProfileId', 'Executable', 'ExecutableSha256', 'SourceUrl', 'SourceRevision')) { if ($entry.PSObject.Properties[$field].Value -isnot [string]) { throw 'Invalid catalog string field.' } }
            if ($entry.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or $ids.ContainsKey([string]$entry.Id)) { throw 'Duplicate/invalid patch identity.' }
            $ids[[string]$entry.Id] = $true
        }
        $matchingEntries = @($catalog.Entries | Where-Object { $_.Id -ceq $PatchId })
        if ($matchingEntries.Count -ne 1) { throw 'Unknown/ambiguous patch.' }
        $entry = $matchingEntries[0]
        if ($entry.ProfileId -cne $ProfileId -or [string]::IsNullOrWhiteSpace($ProfileId)) { throw 'Profile mismatch.' }
        if (-not $ForUndo) {
            $variantDecision = Resolve-TpmPatchVariantDecision -Entries @($catalog.Entries) -PatchId $PatchId -ProfileId $ProfileId -HardwareEvidence $HardwareEvidence
            if ($variantDecision.Status -cne 'SELECTED') { throw $variantDecision.Reason }
            if ($variantDecision.SelectedId -cne $PatchId) { throw ("A different exclusive hardware variant applies: {0}" -f $variantDecision.SelectedId) }
        }
        $editOnly = ($entry.Operations -is [array] -and $entry.Operations.Count -gt 0 -and @($entry.Operations | Where-Object { $_.Type -cne 'SetIniValue' }).Count -eq 0)
        if ($editOnly -and [string]::IsNullOrWhiteSpace($entry.SourceUrl) -and [string]::IsNullOrWhiteSpace($entry.SourceRevision)) {
            # A one-line settings edit downloads and copies no file, so there is no source to pin. Its own exact checks guard the game.
        } elseif ([string]::IsNullOrWhiteSpace($entry.SourceUrl) -and [string]::IsNullOrWhiteSpace($entry.SourceRevision)) {
            $localSource = $entry.PSObject.Properties['SourceRole'] -and $entry.PSObject.Properties['SourceSet'] -and $entry.PSObject.Properties['SourceEntry']
            if (-not $localSource -or $entry.SourceRole -cnotin @('Main','Supplementary','UserSelected') -or
                [string]::IsNullOrWhiteSpace($entry.SourceSet) -or [string]::IsNullOrWhiteSpace($entry.SourceEntry)) {
                throw 'A local recipe must name one user-supplied source role, set, and exact member.'
            }
        } else {
            $source = $null
            if ([string]::IsNullOrWhiteSpace($entry.SourceUrl) -or [string]::IsNullOrWhiteSpace($entry.SourceRevision) -or
                -not [Uri]::TryCreate([string]$entry.SourceUrl, [UriKind]::Absolute, [ref]$source) -or
                $source.Scheme -ne 'https' -or $source.UserInfo -or -not $source.Host -or
                $entry.SourceRevision -notmatch '^[a-fA-F0-9]{40}([a-fA-F0-9]{24})?$') { throw 'Unpinned source provenance.' }
        }
        return (Get-TpmMultiPatchPlan -Entry $entry -PatchId $PatchId -ProfileId $ProfileId -GameRoot $game -PayloadRoot $payloadRootPath -RecoveryRoot $recovery -CatalogSha256 $CatalogSha256 -CatalogEntries @($catalog.Entries) -ForUndo:$ForUndo -ReceiptDirectory $ReceiptDirectory)
    } catch {
        return [pscustomobject]@{ Status = 'Unavailable'; Reason = $_.Exception.Message }
    }
}

function Read-TpmMultiPatchReceiptBytes {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][int]$MaximumBytes)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $memory=New-Object IO.MemoryStream
    try{
        if($stream.Length -gt $MaximumBytes){throw 'Exclusive-group receipt exceeds the supported bound.'}
        $buffer=New-Object byte[] 8192
        while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){
            if($memory.Length+$read -gt $MaximumBytes){throw 'Exclusive-group receipt exceeds the supported bound.'}
            $memory.Write($buffer,0,$read)
        }
        if($memory.Length -ne $stream.Length){throw 'Exclusive-group receipt changed during bounded read.'}
        return ,$memory.ToArray()
    }finally{$memory.Dispose();$stream.Dispose()}
}

function Test-TpmMultiPatchReceiptChain {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$RootReceipt,[Parameter(Mandatory)][string]$RootDirectory)
    if($Plan.Operations.Count -ne 1){return $false}
$planTargets=@($Plan.Operations|ForEach-Object {$_.RelativeTarget});$rootOps=@($RootReceipt.Operations|Where-Object { $_.Target -is [string] -and $_.Target -in $planTargets })
    if($rootOps.Count -ne 1 -or $RootReceipt.Operations.Count -ne 1 -or $RootReceipt.State -cne 'Applied'){return $false}
    $targetRelative=$rootOps[0].Target
    $rootEntry=@($Plan.CatalogEntries|Where-Object {$_.Id -ceq $RootReceipt.PatchId -and $_.ProfileId -ceq $RootReceipt.ProfileId})
    if($rootEntry.Count -ne 1 -or $rootEntry[0].Operations.Count -ne 1 -or $RootReceipt.ProfileId -cne $Plan.ProfileId -or $RootReceipt.GameRoot -ine $Plan.GameRoot){return $false}
    $rootPlan=Get-TpmMultiPatchPlan -Entry $rootEntry[0] -PatchId $RootReceipt.PatchId -ProfileId $RootReceipt.ProfileId -GameRoot $Plan.GameRoot -PayloadRoot $Plan.PayloadRoot -RecoveryRoot $Plan.RecoveryRoot -CatalogSha256 $RootReceipt.CatalogSha256 -CatalogEntries $Plan.CatalogEntries -ForUndo -Probe -ReceiptChainTarget $targetRelative
    [void](Assert-TpmMultiPatchReceipt -Plan $rootPlan -Receipt $RootReceipt -CatalogSha256 $RootReceipt.CatalogSha256 -Directory $RootDirectory -ReceiptChainTarget $targetRelative)
    $rootOperation=@($rootPlan.Operations|Where-Object RelativeTarget -CEQ $targetRelative)
    if($rootOperation.Count -ne 1 -or $rootOps[0].Type -cne 'CreateFile' -or $rootOps[0].AfterFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$'){return $false}
    $targetPath=$rootOperation[0].Target
    if(-not (Test-TpmNoReparsePath $targetPath)){throw 'Receipt-chain target path is unsafe.'}
    $leaf=Open-TpmPatchCreationFile $targetPath
    try{$liveIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($leaf.SafeFileHandle);$liveHash=Get-TpmPatchStreamSha256 $leaf}finally{$leaf.Dispose()}
    $sourceHash=$rootOps[0].AfterSha256;$sourceIdentity=$rootOps[0].AfterFileIdentity
    if($sourceHash -ieq $liveHash -and $sourceIdentity -ceq $liveIdentity){return $false}
    $receiptDirectories=@(Get-ChildItem -LiteralPath $Plan.RecoveryRoot -Directory -ErrorAction Stop)
    if($receiptDirectories.Count -gt 256){throw 'Exclusive-group receipt census exceeds the 256-directory bound.'}
    $receiptSnapshot=New-Object System.Collections.ArrayList;$totalReceiptBytes=[long]0
    foreach($directory in $receiptDirectories){
        if($directory.Name -notmatch '^[a-f0-9]{32}$'){continue}
        $path=Join-Path $directory.FullName 'receipt.json'
        if(-not [IO.File]::Exists($path) -or -not (Test-TpmNoReparsePath $path)){continue}
        $raw=Read-TpmMultiPatchReceiptBytes -Path $path -MaximumBytes $script:TpmReceiptMaxBytes
        $totalReceiptBytes+=$raw.Length
        if($totalReceiptBytes -gt 16777216){throw 'Exclusive-group receipt census exceeds the 16 MiB bound.'}
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$rawHash=[BitConverter]::ToString($sha.ComputeHash($raw)).Replace('-','')}finally{$sha.Dispose()}
        $candidate=[Text.Encoding]::UTF8.GetString($raw)|ConvertFrom-Json -ErrorAction Stop
        [void]$receiptSnapshot.Add([pscustomobject]@{Directory=$directory;Path=$path;Receipt=$candidate;RawSha256=$rawHash})
    }
    $receiptDirectoryNames=@($receiptDirectories|ForEach-Object {$_.FullName}|Sort-Object -CaseSensitive)
    $visited=@{};$visited[[string]$RootReceipt.TransactionId]=$true
    $visitedStates=@{};$initialStateKey=[string]$sourceHash+'|'+[string]$sourceIdentity;$visitedStates[$initialStateKey]=$true
    $validatedReceipts=New-Object System.Collections.ArrayList
    $rootSnapshot=@($receiptSnapshot|Where-Object {$_.Directory.FullName -ieq $RootDirectory})
    if($rootSnapshot.Count -ne 1 -or
        (ConvertTo-Json -InputObject $rootSnapshot[0].Receipt -Depth 12 -Compress) -cne
        (ConvertTo-Json -InputObject $RootReceipt -Depth 12 -Compress)){
        throw 'Grouped receipt-chain root changed during bounded census.'
    }
    [void]$validatedReceipts.Add($rootSnapshot[0])
    for($step=0;$step -lt 256;$step++){
        $successorCandidates=@()
        foreach($snapshot in $receiptSnapshot){
            $candidate=$snapshot.Receipt
            if($candidate.Schema -ne 3 -or $candidate.ProfileId -cne $RootReceipt.ProfileId -or $candidate.GameRoot -ine $RootReceipt.GameRoot){continue}
            if($candidate.Operations -isnot [array]){continue}
            $links=@($candidate.Operations|Where-Object {$_.Type -ceq 'ReplaceFile' -and $_.Target -ceq $targetRelative -and $_.BeforeSha256 -ieq $sourceHash -and $_.BeforeFileIdentity -ceq $sourceIdentity})
            if($links.Count -eq 0){continue}
            if($candidate.Operations.Count -ne 1){throw 'Grouped receipt chain operation shape unsupported.'}
            if($links.Count -ne 1){throw 'Grouped receipt chain is ambiguous.'}
            if($candidate.State -cnotin @('Applied','Restored')){throw 'Grouped receipt chain successor is unresolved.'}
            $successorCandidates+=@([pscustomobject]@{Snapshot=$snapshot;Receipt=$candidate;Operation=$links[0]})
        }
        if($successorCandidates.Count -eq 0){return $false}
        if($successorCandidates.Count -ne 1){throw 'Grouped receipt chain is ambiguous.'}
        $successor=$successorCandidates[0];$candidate=$successor.Receipt
        if($visited.ContainsKey([string]$candidate.TransactionId)){throw 'Grouped receipt chain contains a cycle.'}
        $entry=@($Plan.CatalogEntries|Where-Object {$_.Id -ceq $candidate.PatchId -and $_.ProfileId -ceq $candidate.ProfileId})
        if($entry.Count -ne 1){throw 'Grouped receipt chain recipe binding is invalid.'}
        $historical=$candidate.State -ceq 'Restored'
        $candidatePlan=Get-TpmMultiPatchPlan -Entry $entry[0] -PatchId $candidate.PatchId -ProfileId $candidate.ProfileId -GameRoot $Plan.GameRoot -PayloadRoot $Plan.PayloadRoot -RecoveryRoot $Plan.RecoveryRoot -CatalogSha256 $candidate.CatalogSha256 -CatalogEntries $Plan.CatalogEntries -ForUndo -Probe -Historical:$historical -ReceiptChainTarget $targetRelative
        [void](Assert-TpmMultiPatchReceipt -Plan $candidatePlan -Receipt $candidate -CatalogSha256 $candidate.CatalogSha256 -Directory $successor.Snapshot.Directory.FullName -Historical:$historical -ReceiptChainTarget $targetRelative)
        $destinationHash=if($historical){$successor.Operation.BeforeSha256}else{$successor.Operation.AfterSha256}
        $destinationIdentity=if($historical){$successor.Operation.RestoredFileIdentity}else{$successor.Operation.AfterFileIdentity}
        if($destinationIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$'){throw 'Grouped receipt chain object identity is invalid.'}
        $stateKey=[string]$destinationHash+'|'+[string]$destinationIdentity
        if($visitedStates.ContainsKey($stateKey)){throw 'Grouped receipt chain contains a cycle.'}
        $visited[[string]$candidate.TransactionId]=$true;$visitedStates[$stateKey]=$true
        [void]$validatedReceipts.Add($successor.Snapshot)
        if($destinationHash -ieq $liveHash -and $destinationIdentity -ceq $liveIdentity){
            if(-not (Test-TpmNoReparsePath $targetPath)){throw 'Receipt-chain target path is unsafe.'}
            $currentDirectories=@(Get-ChildItem -LiteralPath $Plan.RecoveryRoot -Directory -ErrorAction Stop)
            if($currentDirectories.Count -gt 256){throw 'Exclusive-group receipt census exceeds the 256-directory bound.'}
            $currentDirectoryNames=@($currentDirectories|ForEach-Object {$_.FullName}|Sort-Object -CaseSensitive)
            if(($currentDirectoryNames -join "`n") -cne ($receiptDirectoryNames -join "`n")){throw 'Grouped receipt census changed while validating receipt chain.'}
            $currentReceiptHashes=@{};$currentReceiptBytes=[long]0
            foreach($directory in $currentDirectories){
                if($directory.Name -notmatch '^[a-f0-9]{32}$'){continue}
                $path=Join-Path $directory.FullName 'receipt.json'
                if(-not [IO.File]::Exists($path) -or -not (Test-TpmNoReparsePath $path)){continue}
                $raw=Read-TpmMultiPatchReceiptBytes -Path $path -MaximumBytes $script:TpmReceiptMaxBytes
                $currentReceiptBytes+=$raw.Length
                if($currentReceiptBytes -gt 16777216){throw 'Exclusive-group receipt census exceeds the 16 MiB bound.'}
                $sha=[Security.Cryptography.SHA256]::Create()
                try{$hash=[BitConverter]::ToString($sha.ComputeHash($raw)).Replace('-','')}finally{$sha.Dispose()}
                $currentReceiptHashes[$path]=$hash
            }
            if($currentReceiptHashes.Count -ne $receiptSnapshot.Count){throw 'Grouped receipt census changed while validating receipt chain.'}
            foreach($snapshot in $receiptSnapshot){
                if(-not $currentReceiptHashes.ContainsKey($snapshot.Path) -or $currentReceiptHashes[$snapshot.Path] -ine $snapshot.RawSha256){
                    throw 'Grouped receipt changed while validating receipt chain.'
                }
            }
            $final=Open-TpmPatchCreationFile $targetPath
            try{$finalIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($final.SafeFileHandle);$finalHash=Get-TpmPatchStreamSha256 $final}finally{$final.Dispose()}
            if($finalHash -ine $liveHash -or $finalIdentity -cne $liveIdentity){throw 'Grouped target changed while validating receipt chain.'}
            return $true
        }
        $sourceHash=$destinationHash;$sourceIdentity=$destinationIdentity
    }
    throw 'Grouped receipt chain exceeds the supported bound.'
}

function Assert-TpmMultiPatchExclusive {
    param([Parameter(Mandatory)]$Plan,[switch]$IncludePrepared)
    if(-not $Plan.ExclusiveGroup -or -not [IO.Directory]::Exists($Plan.RecoveryRoot)){return}
    foreach($directory in @(Get-ChildItem -LiteralPath $Plan.RecoveryRoot -Directory -ErrorAction Stop)){
        $path=Join-Path $directory.FullName 'receipt.json'
        if($directory.Name -notmatch '^[a-f0-9]{32}$' -or -not (Test-TpmNoReparsePath $path) -or -not [IO.File]::Exists($path)){continue}
        if((Get-Item -LiteralPath $path).Length -gt $script:TpmReceiptMaxBytes){throw 'Exclusive-group receipt exceeds the supported bound.'}
        try{$record=[IO.File]::ReadAllText($path)|ConvertFrom-Json -ErrorAction Stop}catch{throw 'A saved patch receipt could not be read, so no patch can be changed for this game. Move that receipt folder out of the game''s GamePatches backup folder and try again.'}
        if($record.Schema -ne 3 -or $record.GameRoot -ine $Plan.GameRoot){continue}
        if($record.State -ceq 'Prepared'){
            if(-not $IncludePrepared){continue}
            # An interrupted install that changed no game file is stale: keep its evidence and go on.
            # Anything else (promoted, mixed, unreadable) stays a hard stop.
            $entry=@($Plan.CatalogEntries|Where-Object Id -CEQ $record.PatchId)
            if($entry.Count -ne 1){throw 'A grouped transaction is unresolved; preserve its recovery evidence.'}
            try{
                $other=Get-TpmMultiPatchPlan -Entry $entry[0] -PatchId $entry[0].Id -ProfileId $entry[0].ProfileId -GameRoot $Plan.GameRoot -PayloadRoot $Plan.PayloadRoot -RecoveryRoot $Plan.RecoveryRoot -CatalogSha256 $record.CatalogSha256 -CatalogEntries $Plan.CatalogEntries -ForUndo -Probe
                [void](Assert-TpmMultiPatchReceipt -Plan $other -Receipt $record -CatalogSha256 $record.CatalogSha256 -Directory $directory.FullName)
            }catch{
                if([string]$_.Exception.Message -clike 'Interrupted grouped transaction * is not applied (targets still original)*'){continue}
                throw 'A grouped transaction is unresolved; preserve its recovery evidence.'
            }
            throw 'A grouped transaction is unresolved; preserve its recovery evidence.'
        }
        $entry=@($Plan.CatalogEntries|Where-Object Id -CEQ $record.PatchId)
        if($entry.Count -ne 1){throw 'Recorded grouped recipe is absent from the approved catalog; undo it using its retained package first.'}
        $historical=($record.State -cin @('Restored','RolledBack'))
        try {
            $other=Get-TpmMultiPatchPlan -Historical:$historical -Entry $entry[0] -PatchId $entry[0].Id -ProfileId $entry[0].ProfileId -GameRoot $Plan.GameRoot -PayloadRoot $Plan.PayloadRoot -RecoveryRoot $Plan.RecoveryRoot -CatalogSha256 $record.CatalogSha256 -CatalogEntries $Plan.CatalogEntries -ForUndo -Probe
            [void](Assert-TpmMultiPatchReceipt -Plan $other -Receipt $record -CatalogSha256 $record.CatalogSha256 -Directory $directory.FullName -Historical:$historical)
        } catch {
            $failure=$_
            if($record.State -ceq 'Applied' -and $failure.Exception.Message -cin @('Grouped target conflict.','Grouped target object identity changed.')){
                if(Test-TpmMultiPatchReceiptChain -Plan $Plan -RootReceipt $record -RootDirectory $directory.FullName){
                    if($record.ExclusiveGroup -ieq $Plan.ExclusiveGroup -and $record.PatchId -cne $Plan.PatchId){throw 'An exclusive recipe is active; undo it before selecting another variant.'}
                    continue
                }
            }
            throw $failure
        }
        if($record.State -ceq 'Applied' -and $other.ExclusiveGroup -ieq $Plan.ExclusiveGroup -and
            $record.PatchId -cne $Plan.PatchId){
            throw 'An exclusive recipe is active; undo it before selecting another variant.'
        }
    }
}

# SetIniValue: change ONE line of a plain text settings file (ini, cfg, lua) and nothing else.
# The recipe gives LinePattern, a whole-line regex (^...$) with a named group (?<v>...) that holds the value, and the new Value.
# Exactly one line in the file must match. Everything outside that group (other lines, line endings, a UTF-8 BOM) stays byte for byte.
# No file hash is pinned because the guide gives none; the one-matching-line rule, the full-file backup, the receipt hashes and the
# exact-result check on undo protect the player instead. BeforeValue (optional) refuses a file whose line holds any other value.
$script:TpmSetIniMaxBytes = 1MB

function Get-TpmPatchBytesSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hasher.ComputeHash($Bytes))).Replace('-', '') }
    finally { $hasher.Dispose() }
}

function Read-TpmSetIniBytes {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw 'The settings file was not found in this game folder. Run the game once, then try again.' }
    if ((New-Object IO.FileInfo($Path)).Length -gt $script:TpmSetIniMaxBytes) { throw 'The settings file is too large to edit safely.' }
    return ,[IO.File]::ReadAllBytes($Path)
}

function Get-TpmSetIniValueEdit {
    # Settings: one or more objects with LinePattern, Value and (optional) BeforeValue. All are applied to the same text; if any one fails, nothing is returned.
    param([Parameter(Mandatory)][byte[]]$Bytes,[Parameter(Mandatory)][object[]]$Settings)
    if ($Bytes.Length -gt $script:TpmSetIniMaxBytes) { throw 'The settings file is too large to edit safely.' }
    if ($Bytes.Length -ge 2 -and (($Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) -or ($Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF))) { throw 'The settings file uses a text format TeknoParrot Manager does not edit.' }
    $bomLength = if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) { 3 } else { 0 }
    try { $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($Bytes, $bomLength, $Bytes.Length - $bomLength) }
    catch { throw 'The settings file is not plain text that TeknoParrot Manager can edit.' }
    if ($text.Contains([string][char]0)) { throw 'The settings file is not plain text that TeknoParrot Manager can edit.' }
    $changed = $false
    foreach ($setting in $Settings) {
        $pattern = New-Object Text.RegularExpressions.Regex($setting.LinePattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromSeconds(1))
        $found = @()
        foreach ($line in [regex]::Matches($text, '[^\r\n]+')) {
            $m = $pattern.Match($line.Value)
            if ($m.Success -and $m.Groups['v'].Success) { $found += @([pscustomobject]@{ Start = $line.Index + $m.Groups['v'].Index; Length = $m.Groups['v'].Length; Current = $m.Groups['v'].Value }) }
        }
        if ($found.Count -ne 1) { throw ('TeknoParrot Manager expected exactly one matching line in the settings file and found {0}. Nothing was changed.' -f $found.Count) }
        $hit = $found[0]
        $beforeValue = $setting.BeforeValue
        if ($null -ne $beforeValue -and $hit.Current -cne [string]$beforeValue -and $hit.Current -cne $setting.Value) { throw 'The setting in the file is not the value TeknoParrot Manager expects. Nothing was changed.' }
        if ($hit.Current -cne $setting.Value) { $changed = $true }
        $text = $text.Substring(0, $hit.Start) + $setting.Value + $text.Substring($hit.Start + $hit.Length)
    }
    $body = (New-Object Text.UTF8Encoding($false)).GetBytes($text)
    $out = New-Object byte[] ($bomLength + $body.Length)
    if ($bomLength) { [Array]::Copy($Bytes, 0, $out, 0, $bomLength) }
    [Array]::Copy($body, 0, $out, $bomLength, $body.Length)
    return [pscustomobject]@{ Bytes = $out; Changed = $changed }
}

# Turns one SetIniValue recipe operation into the ReplaceFile shape the rest of the engine already backs up, receipts and undoes.
# Apply: before = the file now, after = the file with the one line changed (staged in PayloadRoot under its own hash).
# Undo/inspect: before = the saved original in the receipt's copy, after = that original with the same edit; the file must equal it.
function Resolve-TpmSetIniValueOperation {
    param([Parameter(Mandatory)]$Operation,[Parameter(Mandatory)][int]$Index,[Parameter(Mandatory)][string]$GameRoot,[Parameter(Mandatory)][string]$PayloadRoot,[switch]$ForUndo,[string]$ReceiptDirectory='')
    $names = @($Operation.PSObject.Properties.Name)
    $required = @('Type', 'Target', 'LinePattern', 'Value')
    if (@($required | Where-Object { $_ -notin $names }).Count -or @($names | Where-Object { $_ -notin ($required + 'BeforeValue' + 'MoreSettings') }).Count) { throw 'Unknown or missing catalog fields.' }
    foreach ($name in $names) { if ($name -cne 'MoreSettings' -and $Operation.PSObject.Properties[$name].Value -isnot [string]) { throw 'Invalid grouped operation field.' } }
    # The first setting sits on the operation itself; MoreSettings (optional) lists more pattern/value pairs for the same file.
    $settings = @([pscustomobject]@{ LinePattern = $Operation.LinePattern; Value = $Operation.Value; BeforeValue = $(if ($names -contains 'BeforeValue') { [string]$Operation.BeforeValue } else { $null }) })
    if ($names -contains 'MoreSettings') {
        if ($Operation.MoreSettings -isnot [array] -or $Operation.MoreSettings.Count -lt 1 -or $Operation.MoreSettings.Count -gt 16) { throw 'Invalid grouped operation field.' }
        foreach ($more in $Operation.MoreSettings) {
            $moreNames = @($more.PSObject.Properties.Name)
            if (@(@('LinePattern', 'Value') | Where-Object { $_ -notin $moreNames }).Count -or @($moreNames | Where-Object { $_ -notin @('LinePattern', 'Value', 'BeforeValue') }).Count) { throw 'Unknown or missing catalog fields.' }
            foreach ($name in $moreNames) { if ($more.PSObject.Properties[$name].Value -isnot [string]) { throw 'Invalid grouped operation field.' } }
            $settings += @([pscustomobject]@{ LinePattern = $more.LinePattern; Value = $more.Value; BeforeValue = $(if ($moreNames -contains 'BeforeValue') { [string]$more.BeforeValue } else { $null }) })
        }
    }
    foreach ($setting in $settings) {
        if ($setting.LinePattern.Length -gt 300 -or $setting.LinePattern -cnotmatch '^\^.*\$$' -or $setting.LinePattern -cnotmatch '\(\?<v>') { throw 'Invalid settings-line pattern.' }
        if ($setting.Value -cnotmatch '^[^\x00-\x1F\x7F]{1,100}$') { throw 'Invalid settings value.' }
    }
    $target = Resolve-TpmPatchPath $GameRoot $Operation.Target -ForUndo:$ForUndo
    if ($ForUndo) {
        if ([string]::IsNullOrWhiteSpace($ReceiptDirectory)) { throw 'Undo of a settings edit needs its saved copy.' }
        $receiptPath = Join-Path $ReceiptDirectory 'receipt.json'
        if (-not (Test-TpmNoReparsePath $receiptPath) -or -not [IO.File]::Exists($receiptPath) -or (New-Object IO.FileInfo($receiptPath)).Length -gt $script:TpmReceiptMaxBytes) { throw 'The saved copy of this settings edit could not be read.' }
        $saved = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json -ErrorAction Stop
        $record = @($saved.Operations)[$Index]
        if ($null -eq $record -or $record.Target -cne $Operation.Target -or $record.Backup -isnot [string] -or [string]::IsNullOrWhiteSpace($record.Backup) -or
            -not (Test-PathInside $record.Backup $ReceiptDirectory) -or -not (Test-TpmNoReparsePath $record.Backup)) { throw 'The saved copy of this settings edit could not be read.' }
        $source = Read-TpmSetIniBytes $record.Backup
    } else {
        $source = Read-TpmSetIniBytes $target
    }
    $edit = Get-TpmSetIniValueEdit -Bytes $source -Settings $settings
    $beforeSha = Get-TpmPatchBytesSha256 $source
    if (-not $edit.Changed) {
        if ($ForUndo) { throw 'The saved copy of this settings edit does not match this recipe.' }
        $afterSha = $beforeSha
    } else {
        $afterSha = Get-TpmPatchBytesSha256 $edit.Bytes
        if (-not $ForUndo) {
            $stage = Resolve-TpmPatchPath $PayloadRoot ('setini-' + $afterSha.ToLowerInvariant() + '.tmp') -Staging
            [IO.File]::WriteAllBytes($stage, $edit.Bytes)
        }
    }
    $shaped = [pscustomobject]@{ Type = 'ReplaceFile'; Target = [string]$Operation.Target; BeforeSha256 = $beforeSha; AfterSha256 = $afterSha; Payload = ('setini-' + $afterSha.ToLowerInvariant() + '.tmp'); PayloadSha256 = $afterSha }
    return [pscustomobject]@{ Operation = $shaped; NoOp = (-not $edit.Changed) }
}

function Get-TpmMultiPatchPlan {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$PatchId,[Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot,[Parameter(Mandatory)][string]$PayloadRoot,[Parameter(Mandatory)][string]$RecoveryRoot,
        [Parameter(Mandatory)][string]$CatalogSha256,[Parameter(Mandatory)][array]$CatalogEntries,[switch]$ForUndo,[switch]$Probe,[switch]$Historical,[string]$ReceiptChainTarget='',[string]$ReceiptDirectory='')
    if($Historical -and (-not $ForUndo -or -not $Probe)){throw 'Historical plans are only valid for completed receipt inspection.'}
    if($ReceiptChainTarget -and (-not $ForUndo -or -not $Probe -or @($Entry.Operations|Where-Object Target -CEQ $ReceiptChainTarget).Count -ne 1)){throw 'Receipt-chain structural inspection is internal to the exclusive gate.'}
    if($ReceiptChainTarget -and (Get-PSCallStack)[1].FunctionName -cne 'Test-TpmMultiPatchReceiptChain'){throw 'Receipt-chain structural inspection is internal to the exclusive gate.'}
    if($Entry.Operations -isnot [array] -or $Entry.Operations.Count -lt 1 -or $Entry.Operations.Count -gt 256){throw 'Grouped recipes require 1..256 file operations.'}
    if($Entry.ExclusiveGroup -isnot [string] -or ($Entry.ExclusiveGroup -and $Entry.ExclusiveGroup -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')){throw 'Invalid exclusive group.'}
    $selfExecutable = $Entry.PSObject.Properties['AllowExecutableSelfPatch'] -and $Entry.AllowExecutableSelfPatch
    $editOnly=(@($Entry.Operations|Where-Object {$_.Type -cne 'SetIniValue'}).Count -eq 0)
    $exe=Resolve-TpmPatchPath $GameRoot $Entry.Executable -ForUndo:$ForUndo
    if($editOnly -and $Entry.ExecutableSha256 -ceq ''){
        # No exact program hash is known for these games; the program file only has to be present so the right game folder is proven.
        if(-not $ForUndo -and -not [IO.File]::Exists($exe)){throw 'The game program was not found in this folder.'}
        $executableSha256=''
    }else{
        if($Entry.ExecutableSha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Executable revision mismatch.'}
        $executableSha256=(Get-TpmPatchPayloadFacts $exe -MaximumBytes ([int64]::MaxValue)).Sha256
        if(-not $selfExecutable -and $executableSha256 -ine $Entry.ExecutableSha256){throw 'Executable revision mismatch.'}
    }
    if($selfExecutable -and ($Entry.Operations.Count -ne 1 -or $Entry.Operations[0].Type -cne 'ReplaceFile' -or
        $Entry.Operations[0].BeforeSha256 -ine $Entry.ExecutableSha256)){throw 'Executable self-patch requires one exact ReplaceFile before-state.'}
    $targets=@{};$payloads=@{};$operations=@();$ready=0;$applied=0;$total=0L;$opIndex=-1
    foreach($declared in $Entry.Operations){
        $opIndex++;$operation=$declared;$noOp=$false
        if($declared.Type -ceq 'SetIniValue'){
            $resolved=Resolve-TpmSetIniValueOperation -Operation $declared -Index $opIndex -GameRoot $GameRoot -PayloadRoot $PayloadRoot -ForUndo:$ForUndo -ReceiptDirectory $ReceiptDirectory
            $operation=$resolved.Operation;$noOp=$resolved.NoOp
        }
        $create=($operation.Type -ceq 'CreateFile')
        $pre=if($create){'BeforeState'}else{'BeforeSha256'}
        Assert-TpmPatchFields $operation @('Type','Target',$pre,'AfterSha256','Payload','PayloadSha256')
        foreach($field in @('Type','Target',$pre,'AfterSha256','Payload','PayloadSha256')){if($operation.PSObject.Properties[$field].Value -isnot [string]){throw 'Invalid grouped operation field.'}}
        if($operation.Type -cnotin @('ReplaceFile','CreateFile') -or ($create -and $operation.BeforeState -cne 'Absent')){throw 'Unsupported grouped operation/pre-state.'}
        $pins=@($operation.AfterSha256,$operation.PayloadSha256);if(-not $create){$pins+=@($operation.BeforeSha256)}
        foreach($pin in $pins){if($pin -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid grouped content pin.'}}
        if($operation.AfterSha256 -ine $operation.PayloadSha256 -or (-not $create -and -not $noOp -and $operation.BeforeSha256 -ieq $operation.AfterSha256)){throw 'Conflicting/no-op grouped pins.'}
        $target=Resolve-TpmPatchPath $GameRoot $operation.Target -ForUndo:$ForUndo
        if(-not $ForUndo){Assert-TpmPatchFolderBudget ([IO.Path]::GetDirectoryName($target)) 'Game'}
        $payload=Resolve-TpmPatchPath $PayloadRoot $operation.Payload -Staging -ForUndo:$ForUndo
        if($target -ieq $exe){
            if(-not $selfExecutable -or $Entry.Operations.Count -ne 1 -or $operation.Type -cne 'ReplaceFile' -or
                $operation.BeforeSha256 -ine $Entry.ExecutableSha256){throw 'Executable self-patch requires explicit single-file opt-in and the exact executable before-state.'}
        }elseif($selfExecutable){throw 'Executable self-patch must target the exact declared executable.'}
        if($targets.ContainsKey($target) -or $payloads.ContainsKey($payload)){throw 'Duplicate target/payload.'}
        foreach($other in $targets.Keys){if(Test-TpmPathOverlap $target $other){throw 'Overlapping grouped target paths.'}}
        $targets[$target]=$true;$payloads[$payload]=$true
        if(-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($target))){throw 'Grouped targets require existing safe parents.'}
        if(-not $ForUndo -and -not $noOp){
            $facts=Get-TpmPatchPayloadFacts $payload
            if($facts.IsDirectory){throw 'Grouped payload is not a file.'}
            $total+=$facts.Length
            if($total -gt $script:TpmPatchMaxBytes -or $facts.Sha256 -ine $operation.PayloadSha256){throw 'Grouped payload hash/size bound mismatch.'}
        }
        if($noOp){$applied++}elseif(-not $Historical){
            $state=Get-TpmFileState $target
            if(-not $state.Readable -or $state.IsDirectory -or ($state.Exists -and ($state.Attributes -band [int][IO.FileAttributes]::ReadOnly))){throw 'Grouped target is unknown, a directory or read-only.'}
            if($selfExecutable -and $target -ieq $exe -and $state.Sha256 -ine $executableSha256){throw 'Executable changed while planning self-patch.'}
            if(-not ($ReceiptChainTarget -and $operation.Target -ceq $ReceiptChainTarget)){
                $before=($create -and -not $state.Exists) -or (-not $create -and $state.Exists -and $state.Sha256 -ieq $operation.BeforeSha256)
                $after=$state.Exists -and $state.Sha256 -ieq $operation.AfterSha256
                if($before){$ready++}elseif($after){$applied++}else{throw 'Grouped target conflict.'}
            }
        }elseif($selfExecutable){
            $state=Get-TpmFileState $target
            if(-not $state.Readable -or $state.IsDirectory -or $state.Sha256 -ine $executableSha256 -or
                $state.Sha256 -notin @($operation.BeforeSha256,$operation.AfterSha256)){throw 'Historical self-executable receipt is not bound to an exact current state.'}
        }
        $operations+=@([pscustomobject]@{Operation=$operation.Type;Target=$target;RelativeTarget=$operation.Target;Payload=$payload;BeforeSha256=$(if($create){''}else{$operation.BeforeSha256});AfterSha256=$operation.AfterSha256})
    }
    if(-not $Historical -and -not $ReceiptChainTarget -and $ready -ne $operations.Count -and $applied -ne $operations.Count){throw 'Mixed/partially applied target set; no writes are authorized.'}
    $plan=[pscustomobject]@{Status=$(if($Historical){'Historical'}elseif($ReceiptChainTarget){'Structural'}elseif($ready -eq $operations.Count){'Ready'}else{'AlreadyApplied'});Reason=$null;Operation='MultiFile';Operations=$operations;PatchId=$PatchId;ProfileId=$ProfileId;GameRoot=$GameRoot;PayloadRoot=$PayloadRoot;RecoveryRoot=$RecoveryRoot;Target=[string]::Join(', ',@($operations.RelativeTarget));Executable=$exe;ExecutableSha256=$Entry.ExecutableSha256;ExecutableSelfPatch=[bool]$selfExecutable;SourceUrl=$Entry.SourceUrl;SourceRevision=$Entry.SourceRevision;ExclusiveGroup=$Entry.ExclusiveGroup;CatalogEntries=$CatalogEntries}
    if(-not $Probe){Assert-TpmMultiPatchExclusive $plan}
    if(-not $Probe -and $plan.Status -ceq 'AlreadyApplied'){
        $found=@()
        if([IO.Directory]::Exists($RecoveryRoot)){
            foreach($directory in @(Get-ChildItem -LiteralPath $RecoveryRoot -Directory -ErrorAction Stop)){
                if($directory.Name -notmatch '^[a-f0-9]{32}$'){continue}
                try{$receipt=Read-TpmCatalogPatchReceipt -Plan $plan -PatchId $PatchId -ProfileId $ProfileId -CatalogSha256 $CatalogSha256 -RecoveryDirectory $directory.FullName
                    # Read returns a Prepared receipt only after reconciling it with the live targets.
                    if($receipt.State -cin @('Applied','Prepared')){$found+=@($directory.FullName)}
                }catch{if([string]$_.Exception.Message -clike 'ACTION REQUIRED:*'){throw};continue}
            }
        }
        if($found.Count -gt 1){throw 'Grouped after-state has duplicate transaction receipts.'}
    }
    return $plan
}

function Assert-TpmMultiPatchReceipt {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$CatalogSha256,[Parameter(Mandatory)][string]$Directory,[switch]$Historical,[string]$ReceiptChainTarget='')
    if($Historical -and ($Plan.Status -cne 'Historical' -or $Receipt.State -cnotin @('Restored','RolledBack'))){throw 'Only completed receipts may use historical validation.'}
    if($ReceiptChainTarget -and $Plan.Status -notin @('Structural','Historical')){throw 'Receipt-chain validation requires a structural plan.'}
    if($ReceiptChainTarget -and (Get-PSCallStack)[1].FunctionName -cne 'Test-TpmMultiPatchReceiptChain'){throw 'Receipt-chain validation is internal to the exclusive gate.'}
    Assert-TpmPatchFields $Receipt @('Schema','PatchId','CatalogSha256','ProfileId','GameRoot','TransactionId','ExclusiveGroup','State','Operations')
    foreach($field in @('PatchId','CatalogSha256','ProfileId','GameRoot','TransactionId','ExclusiveGroup','State')){if($Receipt.PSObject.Properties[$field].Value -isnot [string]){throw 'Invalid grouped receipt field.'}}
    if(($Receipt.Schema -isnot [int] -and $Receipt.Schema -isnot [long]) -or $Receipt.Schema -ne 3 -or
        $Receipt.PatchId -cne $Plan.PatchId -or $Receipt.ProfileId -cne $Plan.ProfileId -or $Receipt.CatalogSha256 -ine $CatalogSha256 -or
        $Receipt.GameRoot -ine $Plan.GameRoot -or $Receipt.ExclusiveGroup -cne $Plan.ExclusiveGroup -or
        $Receipt.TransactionId -notmatch '^[a-f0-9]{32}$' -or $Receipt.TransactionId -cne [IO.Path]::GetFileName($Directory.TrimEnd('\')) -or
        $Receipt.State -cnotin @('Applied','Restored','RolledBack','Prepared') -or $Receipt.Operations -isnot [array] -or $Receipt.Operations.Count -ne $Plan.Operations.Count){throw 'Grouped receipt identity mismatch.'}
    if($Receipt.State -ceq 'Prepared' -and ($Historical -or $ReceiptChainTarget)){throw 'Only completed receipts may use historical or chain validation.'}
    for($i=0;$i -lt $Plan.Operations.Count;$i++){
        $expected=$Plan.Operations[$i];$record=$Receipt.Operations[$i]
        Assert-TpmPatchFields $record @('Type','Target','BeforeSha256','AfterSha256','Backup','BeforeFileIdentity','AfterFileIdentity','RestoredFileIdentity')
        foreach($field in @('Type','Target','BeforeSha256','AfterSha256','Backup','BeforeFileIdentity','AfterFileIdentity','RestoredFileIdentity')){if($record.PSObject.Properties[$field].Value -isnot [string]){throw 'Invalid grouped receipt operation type.'}}
        if($record.Type -cne $expected.Operation -or $record.Target -cne $expected.RelativeTarget -or $record.BeforeSha256 -ine $expected.BeforeSha256 -or
            $record.AfterSha256 -ine $expected.AfterSha256 -or $record.AfterFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$'){throw 'Grouped receipt operation identity mismatch.'}
        if($record.Type -ceq 'ReplaceFile'){
            if($record.BeforeFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$' -or -not (Test-PathInside $record.Backup $Directory) -or -not (Test-TpmNoReparsePath $record.Backup) -or
                (Get-Item -LiteralPath $record.Backup).Length -gt $script:TpmPatchMaxBytes -or (Get-FileHash -LiteralPath $record.Backup -Algorithm SHA256).Hash -ine $record.BeforeSha256){throw 'Grouped retained backup invalid.'}
        }elseif($record.Backup -cne '' -or $record.BeforeFileIdentity -cne '' -or $record.RestoredFileIdentity -cne ''){throw 'Invalid grouped creation absence evidence.'}
        if($record.Type -ceq 'ReplaceFile' -and
            (($Receipt.State -ceq 'Restored' -and $record.RestoredFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$') -or
            ($Receipt.State -ceq 'RolledBack' -and $record.RestoredFileIdentity -cne ''))){throw 'Invalid grouped completed file identity.'}
        if($Historical){continue}
        if($ReceiptChainTarget -and $record.Target -ceq $ReceiptChainTarget){continue}
        if($Receipt.State -ceq 'Prepared'){continue}
        $after=($Receipt.State -ceq 'Applied')
        if(-not (Test-TpmPatchTargetState $expected $after)){throw 'Grouped receipt target state changed.'}
        if($after -or $record.Type -ceq 'ReplaceFile'){
            $identity=if($after){$record.AfterFileIdentity}elseif($Receipt.State -ceq 'RolledBack'){$record.BeforeFileIdentity}else{$record.RestoredFileIdentity}
            if($identity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$'){throw 'Grouped receipt file identity is unavailable.'}
            $opened=Open-TpmPatchCreationFile $expected.Target
            try{if([TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle) -cne $identity){throw 'Grouped target object identity changed.'}}finally{$opened.Dispose()}
        }
    }
    if($Receipt.State -ceq 'Prepared'){
        # Interrupted between promotion and the Applied revision, so promotion may or may not have
        # happened. Reconcile only against the recorded hashes and file identities; anything else
        # needs the owner and every receipt and backup is kept.
        $notApplied=$false
        try{
            if(Test-TpmPatchTargetState $Plan $false){$notApplied=$true}
            else{
                if(-not (Test-TpmPatchTargetState $Plan $true)){throw 'the targets are neither all original nor all promoted'}
                for($i=0;$i -lt $Plan.Operations.Count;$i++){
                    $opened=Open-TpmPatchCreationFile $Plan.Operations[$i].Target
                    try{if([TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle) -cne $Receipt.Operations[$i].AfterFileIdentity){throw 'a promoted file is not the recorded object'}}finally{$opened.Dispose()}
                }
            }
        }catch{throw ('ACTION REQUIRED: interrupted grouped transaction '+$Directory+' cannot be reconciled with the live targets ('+$_.Exception.Message+'); every receipt and backup was retained for manual recovery.')}
        if($notApplied){throw ('Interrupted grouped transaction '+$Directory+' is not applied (targets still original); it is not an undo record and its receipt and retained backups were kept.')}
    }
    if($Historical){Assert-TpmMultiPatchTerminalCheckpoint -Plan $Plan -Receipt $Receipt -Directory $Directory}
    return $Receipt
}

function Assert-TpmMultiPatchTerminalCheckpoint {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$Directory)
    if($Receipt.State -cnotin @('Restored','RolledBack')){throw 'Grouped terminal checkpoint state is invalid.'}
    $path=Join-Path $Directory 'receipt.json'
    $id=$Receipt.TransactionId+'_'+$Receipt.State
    $snapshot=Join-Path (Join-Path (Join-Path $Plan.RecoveryRoot 'ReceiptHistory') 'Snapshots') $id
    $check=Test-TpmResetSnapshot -SnapshotPath $snapshot
    if(-not $check.Verified -or $check.Manifest.SnapshotId -cne $id -or $check.Manifest.Kind -cne 'Checkpoint' -or
        @($check.Manifest.Paths).Count -ne 1){throw 'Grouped terminal receipt history is unavailable or corrupt.'}
    $captured=@($check.Manifest.Paths)[0]
    if($captured.TargetPath -ine $path -or -not $captured.Exists -or $captured.IsDirectory -or
        (Get-Item -LiteralPath $path).Length -gt $script:TpmReceiptMaxBytes -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $captured.Sha256){throw 'Grouped terminal receipt differs from verified history.'}
}

function New-TpmMultiPatchTerminalCheckpoint {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$Directory)
    if($Receipt.State -cnotin @('Restored','RolledBack')){throw 'Only a verified completed transaction may retain a terminal receipt.'}
    # Called under the transaction gate only after target verification and history.
    $receiptPath=Join-Path $Directory 'receipt.json'
    if(-not (Test-TpmNoReparsePath $receiptPath) -or (Get-Item -LiteralPath $receiptPath).Length -gt $script:TpmReceiptMaxBytes){throw 'Grouped terminal receipt path/bound changed.'}
    $terminalReceipt=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json -ErrorAction Stop
    if($terminalReceipt.State -cne $Receipt.State -or $terminalReceipt.TransactionId -cne $Receipt.TransactionId){throw 'Grouped terminal receipt disposition changed.'}
    [void](Assert-TpmMultiPatchReceipt -Plan $Plan -Receipt $terminalReceipt -CatalogSha256 $Receipt.CatalogSha256 -Directory $Directory)
    $id=$Receipt.TransactionId+'_'+$Receipt.State
    $created=New-TpmResetSnapshot -BackupsRoot $Plan.RecoveryRoot -StoreRoot (Join-Path $Plan.RecoveryRoot 'ReceiptHistory') -SnapshotId $id -Kind Checkpoint -TargetPaths @((Join-Path $Directory 'receipt.json')) -PayloadRetention StateOnly
    if($created.Status -cne 'VERIFIED' -or $created.PublicationState -cne 'VERIFIED'){throw ('Grouped terminal receipt checkpoint failed: '+$created.Reason)}
    Assert-TpmMultiPatchTerminalCheckpoint -Plan $Plan -Receipt $Receipt -Directory $Directory
}

function Copy-TpmPatchBatchStream {
    param([Parameter(Mandatory)][IO.FileStream]$Source,[Parameter(Mandatory)][IO.FileStream]$Destination,[switch]$Metadata)
    $Source.Position=0;$Source.CopyTo($Destination,65536);$Destination.Flush($true)
    if($Metadata){[TpmSupportNativeMethods]::PatchCopyMetadata($Destination.SafeFileHandle,$Source.SafeFileHandle)}
}

# Free bytes on the drive that holds Path, or $null when Windows cannot say (for example a network share).
function Get-TpmPatchFreeBytes {
    param([Parameter(Mandatory)][string]$Path)
    try {
        $root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
        if($root -notmatch '^[A-Za-z]:\\'){return $null}
        return [int64](New-Object IO.DriveInfo($root)).AvailableFreeSpace
    } catch { return $null }
}

# Refuses before anything is written when a drive cannot hold what the patch is about to put on it.
# Needs is a list of @{Path=...;Bytes=...}. An unknown amount of free space is not blocked: the write then fails closed and rolls back on its own.
function Assert-TpmPatchFreeSpace {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Needs)
    $byDrive=@{}
    foreach($need in $Needs){$root=[IO.Path]::GetPathRoot([IO.Path]::GetFullPath([string]$need.Path));$byDrive[$root]=[int64]$byDrive[$root]+[int64]$need.Bytes}
    foreach($root in @($byDrive.Keys)){
        $free=Get-TpmPatchFreeBytes $root
        $required=$byDrive[$root]+16MB
        if($null -ne $free -and $free -lt $required){throw ('Not enough free space on drive {0}: {1} MB needed, {2} MB free. Nothing was changed.' -f $root.TrimEnd('\'),[Math]::Ceiling($required/1MB),[Math]::Floor($free/1MB))}
    }
}

function Invoke-TpmPatchFileBatch {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$CatalogSha256,
        [ValidateSet('Apply','Undo')][string]$Action='Apply',[string]$RecoveryDirectory='',$Receipt=$null,[scriptblock]$ValidationAction=$null)
    $apply=($Action -ceq 'Apply');$run=$RecoveryDirectory;$records=@();$locks=@();$exeGuard=$null;$gate=$null;$committed=$false;$receiptReady=$false
    try{
        foreach($parent in @($Plan.Operations|ForEach-Object {[IO.Path]::GetDirectoryName($_.Target)}|Sort-Object -Unique)){
            $locks+=@(Open-TpmPatchDirectoryBoundary $parent)
        }
        $exeGuard=Open-TpmPatchCreationFile $Plan.Executable -MaximumBytes ([int64]::MaxValue)
        # Games recorded without an exact program hash only prove the program file is there.
        if($Plan.ExecutableSha256){
            $exePin=if($Plan.ExecutableSelfPatch){if($apply){$Plan.Operations[0].BeforeSha256}else{$Plan.Operations[0].AfterSha256}}else{$Plan.ExecutableSha256}
            if((Get-TpmPatchStreamSha256 $exeGuard) -ine $exePin){throw 'Grouped executable identity changed.'}
        }
        $sourceTotal=0L;$beforeTotal=0L
        for($i=0;$i -lt $Plan.Operations.Count;$i++){
            $operation=$Plan.Operations[$i]
            $record=[pscustomobject]@{Operation=$operation;Source=$null;Before=$null;BeforeIdentity='';Desired=$null;DesiredIdentity='';Guard=$null;Aside='';Current=$null;Published=$false;ReceiptRecord=$null}
            $records+=@($record)
            $exists=$apply -and $operation.Operation -ceq 'ReplaceFile'
            if(-not $apply){$exists=$true}
            if($exists){
                $record.Before=Open-TpmPatchCreationFile $operation.Target
                $record.BeforeIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($record.Before.SafeFileHandle)
                $pin=if($apply){$operation.BeforeSha256}else{$operation.AfterSha256}
                if((Get-TpmPatchStreamSha256 $record.Before) -ine $pin){throw 'Grouped current bytes changed before any write.'}
                if($Plan.ExecutableSelfPatch -and [TpmSupportNativeMethods]::PatchFileIdentity($exeGuard.SafeFileHandle) -cne $record.BeforeIdentity){throw 'Self-executable object identity changed before any write.'}
                if(-not $apply -and $record.BeforeIdentity -cne $Receipt.Operations[$i].AfterFileIdentity){throw 'Grouped undo object changed before any write.'}
                $beforeTotal+=$record.Before.Length
            }elseif(-not (Test-TpmPatchTargetState $operation $false)){throw 'Grouped create target is no longer absent.'}
            $sourcePath=if($apply){$operation.Payload}elseif($operation.Operation -ceq 'ReplaceFile'){$Receipt.Operations[$i].Backup}else{''}
            if($sourcePath){
                $record.Source=Open-TpmPatchCreationFile $sourcePath
                $pin=if($apply){$operation.AfterSha256}else{$operation.BeforeSha256}
                $sourceTotal+=$record.Source.Length
                if((Get-TpmPatchStreamSha256 $record.Source) -ine $pin){throw 'Grouped source/backup changed before any write.'}
            }
        }
        if($sourceTotal -gt $script:TpmPatchMaxBytes -or $beforeTotal -gt $script:TpmPatchMaxBytes){throw 'Grouped source/backup aggregate exceeds the patch size bound.'}
        # Game folder: the sibling temp copy of each new file. Saved-copy folder: the original twice (patch copy plus update backup). Checked before any write.
        $needs=@()
        for($i=0;$i -lt $records.Count;$i++){
            if($records[$i].Source){$needs+=@(@{Path=$records[$i].Operation.Target;Bytes=$records[$i].Source.Length})}
            if($apply -and $records[$i].Before){$needs+=@(@{Path=$Plan.RecoveryRoot;Bytes=2*$records[$i].Before.Length})}
        }
        Assert-TpmPatchFreeSpace $needs
        if($ValidationAction){[void](& $ValidationAction)}
        # Only after every file passed preflight may recovery or sibling staging be written.
        [void][IO.Directory]::CreateDirectory($Plan.RecoveryRoot)
        $locks+=@(Open-TpmPatchDirectoryBoundary $Plan.RecoveryRoot)
        $receiptStoreBoundary=Test-TpmResetStoreBoundary -BackupsRoot $Plan.RecoveryRoot -StoreRoot (Join-Path $Plan.RecoveryRoot 'ReceiptHistory')
        if(-not $receiptStoreBoundary.Verified){throw ('Grouped terminal receipt storage is unavailable: '+$receiptStoreBoundary.Reason)}
        $gatePath=Join-Path $Plan.RecoveryRoot 'patch-batch.lock'
        if(-not (Test-TpmNoReparsePath $gatePath)){throw 'Unsafe grouped transaction gate.'}
        $gate=New-Object IO.FileStream($gatePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if((Get-TpmSupportFinalPathFromHandle $gate.SafeFileHandle) -ine (Resolve-TpmSupportExpectedFinalPath $gatePath) -or $gate.Length -ne 0){throw 'Grouped transaction gate identity is invalid.'}
        [void][TpmSupportNativeMethods]::PatchFileIdentity($gate.SafeFileHandle)
        if(-not $apply){$receiptReady=$true}
        if($apply){
            Assert-TpmMultiPatchExclusive $Plan -IncludePrepared
            $run=Join-Path $Plan.RecoveryRoot ([guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($run)
            if(-not (Test-TpmNoReparsePath $run)){throw 'Unsafe grouped recovery run.'}
            $locks+=@(Open-TpmPatchDirectoryBoundary $run)
            $Receipt=[ordered]@{Schema=3;PatchId=$Plan.PatchId;CatalogSha256=$CatalogSha256;ProfileId=$Plan.ProfileId;GameRoot=$Plan.GameRoot;TransactionId=[IO.Path]::GetFileName($run);ExclusiveGroup=$Plan.ExclusiveGroup;State='Prepared';Operations=@()}
        }
        for($i=0;$i -lt $records.Count;$i++){
            $record=$records[$i];$operation=$record.Operation
            if($apply){
                $backup=''
                if($operation.Operation -ceq 'ReplaceFile'){
                    $original=Join-Path $run ('original-'+$i+'.bin')
                    $copy=Open-TpmPatchCreationFile $original -NewFile
                    try{Copy-TpmPatchBatchStream $record.Before $copy -Metadata}finally{$copy.Dispose()}
                    $backup=New-ManagerUpdateBackup $original
                    if(-not (Test-PathInside $backup $run) -or (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ine $operation.BeforeSha256){throw 'Grouped existing-file backup failed verification.'}
                }
                $record.ReceiptRecord=[ordered]@{Type=$operation.Operation;Target=$operation.RelativeTarget;BeforeSha256=$operation.BeforeSha256;AfterSha256=$operation.AfterSha256;Backup=$backup;BeforeFileIdentity=$record.BeforeIdentity;AfterFileIdentity='';RestoredFileIdentity=''}
                $Receipt.Operations+=@($record.ReceiptRecord)
            }else{$record.ReceiptRecord=$Receipt.Operations[$i]}
            if($record.Source){
                $stagePath=Join-Path ([IO.Path]::GetDirectoryName($operation.Target)) ('.tpm-batch-'+[guid]::NewGuid().ToString('N')+'.tmp')
                $record.Desired=Open-TpmPatchCreationFile $stagePath -NewFile
                Copy-TpmPatchBatchStream $record.Source $record.Desired -Metadata:(-not $apply)
                $pin=if($apply){$operation.AfterSha256}else{$operation.BeforeSha256}
                if((Get-TpmPatchStreamSha256 $record.Desired) -ine $pin){throw 'Grouped staged bytes failed verification.'}
                $record.DesiredIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($record.Desired.SafeFileHandle)
                if($apply){$record.ReceiptRecord.AfterFileIdentity=$record.DesiredIdentity}else{$record.ReceiptRecord.RestoredFileIdentity=$record.DesiredIdentity}
            }
        }
        if($apply){Write-TpmPatchCreationReceipt $run $Receipt;$receiptReady=$true}
        if($ValidationAction){[void](& $ValidationAction)}
        # Acquire all existing leaves for exact-object moves before moving any one leaf.
        foreach($record in $records){
            if($record.Before){
                $record.Before.Dispose();$record.Before=$null
                $record.Current=Open-TpmPatchCreationFile $record.Operation.Target -ForRemoval
                $pin=if($apply){$record.Operation.BeforeSha256}else{$record.Operation.AfterSha256}
                if([TpmSupportNativeMethods]::PatchFileIdentity($record.Current.SafeFileHandle) -cne $record.BeforeIdentity -or (Get-TpmPatchStreamSha256 $record.Current) -ine $pin){throw 'Grouped leaf changed at publication boundary.'}
            }elseif(-not (Test-TpmPatchTargetState $record.Operation $false)){throw 'Grouped absent leaf changed at publication boundary.'}
        }
        foreach($record in $records){
            if($record.Current){
                $record.Aside=Join-Path ([IO.Path]::GetDirectoryName($record.Operation.Target)) ('.tpm-aside-'+[guid]::NewGuid().ToString('N')+'.tmp')
                Move-TpmPatchCreationHandle $record.Current.SafeFileHandle $record.Aside
            }
            if($record.Desired){
                Move-TpmPatchCreationHandle $record.Desired.SafeFileHandle $record.Operation.Target
                $record.Published=$true
                $record.Desired.Dispose();$record.Desired=$null
                $record.Guard=Open-TpmPatchCreationFile $record.Operation.Target
                $pin=if($apply){$record.Operation.AfterSha256}else{$record.Operation.BeforeSha256}
                if([TpmSupportNativeMethods]::PatchFileIdentity($record.Guard.SafeFileHandle) -cne $record.DesiredIdentity -or (Get-TpmPatchStreamSha256 $record.Guard) -ine $pin){throw 'Grouped promoted file readback failed.'}
            }
        }
        if(-not (Test-TpmPatchTargetState $Plan $apply)){throw 'Grouped final target-set verification failed.'}
        $Receipt.State=if($apply){'Applied'}else{'Restored'}
        Write-TpmPatchCreationReceipt $run $Receipt
        $publishedReceipt=[IO.File]::ReadAllText((Join-Path $run 'receipt.json'))|ConvertFrom-Json -ErrorAction Stop
        [void](Assert-TpmMultiPatchReceipt -Plan $Plan -Receipt $publishedReceipt -CatalogSha256 $CatalogSha256 -Directory $run)
        if($ValidationAction){[void](& $ValidationAction 'published')}
        if(-not $apply){New-TpmMultiPatchTerminalCheckpoint -Plan $Plan -Receipt $Receipt -Directory $run}
        $committed=$true
    }catch{
        $failure=$_;$rollbackErrors=@()
        foreach($record in $records){if($record.Guard){$record.Guard.Dispose();$record.Guard=$null};if($record.Before){$record.Before.Dispose();$record.Before=$null}}
        for($i=$records.Count-1;$i -ge 0;$i--){
            $record=$records[$i]
            try{
                if($record.Published -and -not $record.Desired){
                    $record.Desired=Open-TpmPatchCreationFile $record.Operation.Target -ForRemoval
                    $pin=if($apply){$record.Operation.AfterSha256}else{$record.Operation.BeforeSha256}
                    if([TpmSupportNativeMethods]::PatchFileIdentity($record.Desired.SafeFileHandle) -cne $record.DesiredIdentity -or (Get-TpmPatchStreamSha256 $record.Desired) -ine $pin){$record.Desired.Dispose();$record.Desired=$null;throw 'Published target changed; foreign content preserved.'}
                }
                if($record.Desired){Remove-TpmSupportHandle $record.Desired.SafeFileHandle;$record.Desired.Dispose();$record.Desired=$null}
                if($record.Current){
                    $location=Get-TpmSupportFinalPathFromHandle $record.Current.SafeFileHandle
                    if($location -ine (Resolve-TpmSupportExpectedFinalPath $record.Operation.Target)){Move-TpmPatchCreationHandle $record.Current.SafeFileHandle $record.Operation.Target}
                    $pin=if($apply){$record.Operation.BeforeSha256}else{$record.Operation.AfterSha256}
                    if([TpmSupportNativeMethods]::PatchFileIdentity($record.Current.SafeFileHandle) -cne $record.BeforeIdentity -or (Get-TpmPatchStreamSha256 $record.Current) -ine $pin){throw 'Grouped rollback object/bytes mismatch.'}
                    $record.Current.Dispose();$record.Current=$null
                    $record.Guard=Open-TpmPatchCreationFile $record.Operation.Target
                }
            }catch{$rollbackErrors+=@($_.Exception.Message)}
        }
        if($rollbackErrors.Count -or -not (Test-TpmPatchTargetState $Plan (-not $apply))){throw ('Grouped rollback requires attention; evidence retained at '+$run+'; '+[string]::Join('; ',$rollbackErrors)+'; original: '+$failure.Exception.Message)}
        if($Receipt -and $run -and $receiptReady){$Receipt.State=if($apply){'RolledBack'}else{'Applied'};Write-TpmPatchCreationReceipt $run $Receipt}
        if($Receipt -and $run -and $receiptReady -and $apply){New-TpmMultiPatchTerminalCheckpoint -Plan $Plan -Receipt $Receipt -Directory $run}
        throw $failure
    }finally{
        foreach($record in $records){foreach($name in @('Source','Before','Desired','Guard')){$property=$record.PSObject.Properties[$name];if($property -and $property.Value){$property.Value.Dispose()}}}
        if(-not $committed){foreach($record in $records){if($record.Current){$record.Current.Dispose()}}}
        if($exeGuard){$exeGuard.Dispose()};if($gate){$gate.Dispose()}
        foreach($boundary in $locks){foreach($handle in $boundary){$handle.Dispose()}}
    }
    # After verified history publication, cleanup may only delete the opened old
    # objects. A cleanup error preserves residue and never claims clean success.
    $cleanupErrors=@();$leftoverFiles=@()
    foreach($record in $records){
        if($record.Current){try{Remove-TpmSupportHandle $record.Current.SafeFileHandle}catch{$cleanupErrors+=@($_.Exception.Message);$leftoverFiles+=@([string]$record.Aside)}finally{$record.Current.Dispose()}}
    }
    $leftover=if($cleanupErrors.Count){'An old copy of a replaced file could not be removed. The change itself is done and checked. You can delete the leftover copy later: '+[string]::Join('; ',$leftoverFiles)}else{''}
    return [pscustomobject]@{Status=$(if($apply){'Applied'}else{'Restored'});RecoveryDirectory=$run;SourceUrl=$Plan.SourceUrl;SourceRevision=$Plan.SourceRevision;LeftoverNote=$leftover}
}

function Open-TpmPatchDirectoryBoundary {
    param([Parameter(Mandatory)][string]$Directory)
    [void](Get-TpmSupportNativeType)
    $full=[IO.Path]::GetFullPath($Directory);if($full.Length -gt [IO.Path]::GetPathRoot($full).Length){$full=$full.TrimEnd('\')}
    if($full.Length -gt 247){throw ('A folder path is too long for Windows to patch safely ('+$full.Length+' characters; the limit is 247). Move TeknoParrot or the game to a folder with a shorter path.')}
    if(-not (Test-TpmNoReparsePath $full) -or -not [IO.Directory]::Exists($full)){throw 'CreateFile requires an existing safe parent directory.'}
    $handles=New-Object 'System.Collections.Generic.List[Microsoft.Win32.SafeHandles.SafeFileHandle]'
    try {
        $root=[IO.Path]::GetPathRoot($full)
        $paths=@($root);$cursor=$root
        foreach($part in ($full.Substring($root.Length) -split '\\')){if($part){$cursor=Join-Path $cursor $part;$paths+=@($cursor)}}
        foreach($path in $paths){
            $handle=[TpmSupportNativeMethods]::CreateFile($path,[TpmSupportNativeMethods]::FileReadAttributes,([TpmSupportNativeMethods]::ShareRead -bor [TpmSupportNativeMethods]::ShareWrite),[IntPtr]::Zero,[TpmSupportNativeMethods]::OpenExisting,([TpmSupportNativeMethods]::FileFlagBackupSemantics -bor [TpmSupportNativeMethods]::FileFlagOpenReparsePoint),[IntPtr]::Zero)
            if($handle.IsInvalid){$handle.Dispose();throw 'Patch directory could not be locked against replacement.'}
            $handles.Add($handle)
            $final=Get-TpmSupportFinalPathFromHandle $handle
            if($final.TrimEnd('\') -ine (Resolve-TpmSupportExpectedFinalPath $path).TrimEnd('\') -or ([TpmSupportNativeMethods]::PatchAttributes($handle) -band 0x410) -ne 0x10){throw 'Patch directory handle identity is unsafe.'}
        }
        return ,$handles
    }catch{foreach($handle in $handles){$handle.Dispose()};throw}
}

function Open-TpmPatchCreationFile {
    param([Parameter(Mandatory)][string]$Path,[switch]$NewFile,[switch]$ForRemoval,[int64]$MaximumBytes=$script:TpmPatchMaxBytes)
    [void](Get-TpmSupportNativeType)
    $access=[TpmSupportNativeMethods]::GenericRead
    $share=[TpmSupportNativeMethods]::ShareRead -bor [TpmSupportNativeMethods]::ShareDelete
    $mode=[TpmSupportNativeMethods]::OpenExisting
    $streamAccess=[IO.FileAccess]::Read
    if($NewFile){$access=$access -bor [TpmSupportNativeMethods]::GenericWrite;$mode=[TpmSupportNativeMethods]::CreateNew;$streamAccess=[IO.FileAccess]::ReadWrite}
    if($NewFile -or $ForRemoval){$access=$access -bor [TpmSupportNativeMethods]::Delete;$share=[TpmSupportNativeMethods]::ShareRead}
    # Long-path form so a game or TeknoParrot folder over 259 characters opens. Inline (not ConvertTo-TpmAutoSyncLongPath) because the engine is also loaded without the main script's helpers.
    $fullPath=[IO.Path]::GetFullPath($Path);$nativePath=$(if($fullPath.StartsWith('\\')){'\\?\UNC\'+$fullPath.Substring(2)}else{'\\?\'+$fullPath})
    $handle=[TpmSupportNativeMethods]::CreateFile($nativePath,$access,$share,[IntPtr]::Zero,$mode,[TpmSupportNativeMethods]::FileFlagOpenReparsePoint,[IntPtr]::Zero)
    $win32=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if($handle.IsInvalid){$handle.Dispose();throw ('Patch file could not be opened without overwriting or sharing writes (Windows error '+$win32+'). '+$(switch($win32){2{'The file is missing.'}3{'The folder is missing or the path is too long.'}5{'Windows denied access.'}32{'Another program is using the file.'}33{'Another program has part of the file locked.'}206{'The path is too long for Windows.'}default{'Close other programs that use this game folder and try again.'}}))}
    try {
        if((Get-TpmSupportFinalPathFromHandle $handle) -ine (Resolve-TpmSupportExpectedFinalPath ([IO.Path]::GetFullPath($Path)))){throw 'Patch opened file identity changed.'}
        [void][TpmSupportNativeMethods]::PatchFileIdentity($handle)
        $stream=New-Object IO.FileStream($handle,$streamAccess,65536,$false)
        if($stream.Length -gt $MaximumBytes){$stream.Dispose();throw 'Patch file exceeds the size bound.'}
        return $stream
    }catch{if($NewFile){Remove-TpmSupportHandle $handle};$handle.Dispose();throw}
}

function Get-TpmPatchStreamSha256 {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    $position=$Stream.Position;$sha=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;return (-join ($sha.ComputeHash($Stream)|ForEach-Object {$_.ToString('x2')}))}finally{$Stream.Position=$position;$sha.Dispose()}
}

function Get-TpmPatchPayloadFacts {
    param([Parameter(Mandatory)][string]$Path,[int64]$MaximumBytes=$script:TpmPatchMaxBytes)
    # Long-path form so a staged payload in a deep temporary folder reads on a PC with long paths off.
    $full=[IO.Path]::GetFullPath($Path);$native=$(if($full.StartsWith('\\')){'\\?\UNC\'+$full.Substring(2)}else{'\\?\'+$full})
    if([IO.Directory]::Exists($native)){return [pscustomobject]@{IsDirectory=$true;Length=0L;Sha256=''}}
    $stream=Open-TpmPatchCreationFile $full -MaximumBytes $MaximumBytes
    try{return [pscustomobject]@{IsDirectory=$false;Length=[int64]$stream.Length;Sha256=(Get-TpmPatchStreamSha256 $stream)}}finally{$stream.Dispose()}
}

function Move-TpmPatchCreationHandle {
    param([Parameter(Mandatory)][Microsoft.Win32.SafeHandles.SafeFileHandle]$Handle,[Parameter(Mandatory)][string]$Destination)
    [TpmSupportNativeMethods]::PatchRenameNoReplace($Handle,$Destination)
    $final=Get-TpmSupportFinalPathFromHandle $Handle
    if($final -ine (Resolve-TpmSupportExpectedFinalPath ([IO.Path]::GetFullPath($Destination)))){throw ('Patch atomic rename readback failed: '+$final+'; expected '+$Destination)}
}

function Test-TpmPatchTargetState {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][bool]$After)
    if($Plan.PSObject.Properties['Operations']){
        foreach($operation in $Plan.Operations){if(-not (Test-TpmPatchTargetState $operation $After)){return $false}}
        return $true
    }
    if(-not (Test-TpmNoReparsePath $Plan.Target)){return $false}
    if($Plan.Operation -ceq 'CreateFile' -and -not $After){
        $state=Get-TpmFileState $Plan.Target
        return ($state.Readable -and -not $state.Exists)
    }
    $expected=if($After){$Plan.AfterSha256}else{$Plan.BeforeSha256}
    return ((Get-FileHash -LiteralPath $Plan.Target -Algorithm SHA256 -ErrorAction Stop).Hash -ieq $expected)
}

function Write-TpmPatchCreationReceipt {
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)]$Receipt)
    # Receipts are recovery evidence. Each revision is flushed to a unique same-directory
    # temp, read back and validated, then atomically replaces (or, when absent, is moved
    # without overwrite to) receipt.json, so a failed or interrupted publication keeps the
    # previous valid receipt instead of leaving it truncated.
    if(-not (Test-TpmNoReparsePath $Directory) -or -not [IO.Directory]::Exists($Directory)){throw 'Unsafe creation receipt directory.'}
    $path=Join-Path $Directory 'receipt.json'
    if(-not (Test-TpmNoReparsePath $path)){throw 'Unsafe creation receipt path.'}
    $expectedState=$null
    if($Receipt -is [Collections.IDictionary]){if($Receipt.Contains('State')){$expectedState=[string]$Receipt['State']}}
    elseif($Receipt.PSObject.Properties['State']){$expectedState=[string]$Receipt.State}
    $encoding=New-Object Text.UTF8Encoding($false)
    $json=$Receipt|ConvertTo-Json -Depth 8
    $bytes=$encoding.GetBytes($json)
    $temp=Join-Path $Directory ('receipt.json.'+[guid]::NewGuid().ToString('N')+'.tmp')
    $ownsTemp=$false;$hadReceipt=$false;$publishing=$false
    try{
        $stream=New-Object IO.FileStream($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $ownsTemp=$true
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        $readBack=[IO.File]::ReadAllText($temp,$encoding)
        $parsed=$readBack|ConvertFrom-Json -ErrorAction Stop
        $parsedState=$null
        if($null -ne $parsed -and $parsed.PSObject.Properties['State']){$parsedState=[string]$parsed.State}
        if($readBack -cne $json -or $parsedState -cne $expectedState){throw 'Receipt revision failed readback validation; the previous receipt was kept.'}
        if(-not (Test-TpmNoReparsePath $Directory) -or -not (Test-TpmNoReparsePath $path)){throw 'Unsafe creation receipt path.'}
        $hadReceipt=[IO.File]::Exists($path);$publishing=$true
        if($hadReceipt){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)}
        $ownsTemp=$false
    }catch{
        $failure=$_
        if($ownsTemp){
            # A failed replace that already removed the previous receipt leaves this
            # validated revision as the only copy; keep it instead of deleting evidence.
            if($publishing -and $hadReceipt -and -not [IO.File]::Exists($path)){
                throw ('Receipt publication failed after the previous receipt was removed; the validated revision was retained at '+$temp+': '+$failure.Exception.Message)
            }
            try{[IO.File]::Delete($temp)}catch{throw ('Receipt publication failed and its temporary file was retained at '+$temp+': '+$_.Exception.Message+'; original: '+$failure.Exception.Message)}
        }
        throw $failure
    }
}

function Get-TpmPatchReceiptResidue {
    param([Parameter(Mandatory)][string]$RecoveryRoot)
    # Interrupted receipt publications can leave receipt.json.<guid>.tmp files. They are
    # never read as receipts and never deleted; they are only listed for the owner.
    if(-not (Test-TpmNoReparsePath $RecoveryRoot) -or -not [IO.Directory]::Exists($RecoveryRoot)){return @()}
    $residue=@()
    foreach($directory in @(Get-ChildItem -LiteralPath $RecoveryRoot -Directory -ErrorAction Stop)){
        if($directory.Name -notmatch '^[a-f0-9]{32}$' -or -not (Test-TpmNoReparsePath $directory.FullName)){continue}
        foreach($file in @(Get-ChildItem -LiteralPath $directory.FullName -File -Filter 'receipt.json.*.tmp' -ErrorAction Stop)){
            if($file.Name -cmatch '^receipt\.json\.[a-f0-9]{32}\.tmp$'){$residue+=@($file.FullName)}
        }
    }
    return $residue
}

function Invoke-TpmCatalogPatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$CatalogContent, [Parameter(Mandatory)][string]$CatalogSha256,
        [Parameter(Mandatory)][string]$PatchId, [Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot, [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$RecoveryRoot, [Parameter(Mandatory)][string[]]$ProtectedRoots,
        [AllowNull()][object]$HardwareEvidence = $null,
        [scriptblock]$ValidationAction=$null
    )
    $inputs = @{}; foreach ($key in $PSBoundParameters.Keys) { if ($key -notin @('WhatIf', 'Confirm', 'ValidationAction')) { $inputs[$key] = $PSBoundParameters[$key] } }
    $plan = Get-TpmPatchPlan @inputs
    if ($plan.Status -eq 'Unavailable') { throw $plan.Reason }
    if ($plan.Status -eq 'AlreadyApplied' -or -not $PSCmdlet.ShouldProcess($plan.Target, "Apply catalog patch $PatchId")) { return $plan }
    return (Invoke-TpmPatchFileBatch -Plan $plan -CatalogSha256 $CatalogSha256 -ValidationAction $ValidationAction)
}

function Read-TpmCatalogPatchReceipt {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$PatchId,[Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$CatalogSha256,[Parameter(Mandatory)][string]$RecoveryDirectory)
    if (-not (Test-PathInside $RecoveryDirectory $plan.RecoveryRoot) -or -not (Test-TpmNoReparsePath $RecoveryDirectory)) { throw 'Invalid recovery directory.' }
    $receiptPath = Join-Path $RecoveryDirectory 'receipt.json'
    if (-not (Test-TpmNoReparsePath $receiptPath)) { throw 'Unsafe receipt.' }
    if ((Get-Item -LiteralPath $receiptPath -ErrorAction Stop).Length -gt $script:TpmReceiptMaxBytes) { throw 'Retained receipt exceeds the supported size.' }
    $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json -ErrorAction Stop
    return (Assert-TpmMultiPatchReceipt -Plan $Plan -Receipt $receipt -CatalogSha256 $CatalogSha256 -Directory $RecoveryDirectory)
}

# The patch-list hash a saved copy recorded; falls back to the given one if the receipt cannot be read.
function Get-TpmSavedCopyCatalogHash {
    param([Parameter(Mandatory)][string]$RecoveryDirectory,[Parameter(Mandatory)][string]$Fallback)
    try {
        $saved=[IO.File]::ReadAllText((Join-Path $RecoveryDirectory 'receipt.json')) | ConvertFrom-Json -ErrorAction Stop
        if ($saved.CatalogSha256 -is [string] -and $saved.CatalogSha256 -match '^[a-fA-F0-9]{64}$') { return $saved.CatalogSha256 }
    } catch { }
    return $Fallback
}

# If the game file no longer matches the NEW list's recipe AND a saved copy recorded a different recipe for this
# patch (Target/Before/After per file), say so plainly. Any other message (a user-edited or unreadable file,
# an interrupted state) is returned unchanged. A change elsewhere in the list does not count.
function Resolve-TpmOlderListReason {
    param([Parameter(Mandatory)][string]$Message,[AllowNull()][object[]]$Operations,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RecoveryDirectory)
    if ($Message -cnotmatch 'target conflict|Mixed/partially|target is unknown' -or $null -eq $Operations) { return $Message }
    $recipe = { param($Items) (@($Items | ForEach-Object { '{0}|{1}|{2}' -f $_.Target, ([string]$_.BeforeSha256).ToLowerInvariant(), ([string]$_.AfterSha256).ToLowerInvariant() }) -join ';') }
    $current = & $recipe $Operations
    foreach ($directory in $RecoveryDirectory) {
        try {
            $saved = [IO.File]::ReadAllText((Join-Path $directory 'receipt.json')) | ConvertFrom-Json -ErrorAction Stop
            $savedOperations = if ($saved.PSObject.Properties['Operations']) { $saved.Operations } else { $saved }
            if ((& $recipe $savedOperations) -cne $current) { return 'This saved copy was made by an older patch list.' }
        } catch { }
    }
    return $Message
}

# Undo is judged by what the receipt recorded (backup, before/after hashes), not by the current patch list hash.
# If the patch list changed this patch itself, the receipt no longer matches and undo refuses.
function Read-TpmUndoReceipt {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$PatchId,[Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$CatalogSha256,[Parameter(Mandatory)][string]$RecoveryDirectory)
    $recorded=Get-TpmSavedCopyCatalogHash -RecoveryDirectory $RecoveryDirectory -Fallback $CatalogSha256
    try { return (Read-TpmCatalogPatchReceipt -Plan $Plan -PatchId $PatchId -ProfileId $ProfileId -CatalogSha256 $recorded -RecoveryDirectory $RecoveryDirectory) }
    catch {
        if ($recorded -ine $CatalogSha256 -and [string]$_.Exception.Message -clike '*identity mismatch*') { throw 'This saved copy was made by an older patch list.' }
        throw
    }
}

function Undo-TpmCatalogPatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$CatalogContent, [Parameter(Mandatory)][string]$CatalogSha256,
        [Parameter(Mandatory)][string]$PatchId, [Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot, [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$RecoveryRoot, [Parameter(Mandatory)][string[]]$ProtectedRoots,
        [Parameter(Mandatory)][string]$RecoveryDirectory,
        [AllowNull()][object]$HardwareEvidence = $null,
        [scriptblock]$ValidationAction=$null
    )
    $inputs = @{}; foreach ($key in $PSBoundParameters.Keys) { if ($key -notin @('RecoveryDirectory', 'WhatIf', 'Confirm', 'ValidationAction')) { $inputs[$key] = $PSBoundParameters[$key] } }
    try {
        $plan = Get-TpmPatchPlan @inputs -ForUndo -ReceiptDirectory $RecoveryDirectory
        if ($plan.Status -eq 'Unavailable') { throw $plan.Reason }
    } catch {
        $failure = [string]$_.Exception.Message
        $current = try { @(@(($CatalogContent | ConvertFrom-Json).Entries | Where-Object { $_.Id -ceq $PatchId })[0].Operations) } catch { $null }
        throw (Resolve-TpmOlderListReason -Message $failure -Operations $current -RecoveryDirectory @($RecoveryDirectory))
    }
    $receipt=Read-TpmUndoReceipt -Plan $plan -PatchId $PatchId -ProfileId $ProfileId -CatalogSha256 $CatalogSha256 -RecoveryDirectory $RecoveryDirectory
    if ($plan.Status -eq 'Ready') { return [pscustomobject]@{ Status = 'AlreadyRestored' } }
    if (-not $PSCmdlet.ShouldProcess($plan.Target, "Undo catalog patch $PatchId")) { return $plan }
    return (Invoke-TpmPatchFileBatch -Plan $plan -CatalogSha256 $receipt.CatalogSha256 -Action Undo -RecoveryDirectory $RecoveryDirectory -Receipt $receipt -ValidationAction $ValidationAction)
}

function Read-TpmRequiredPatchCatalog {
    param([Parameter(Mandatory)][string]$ProgramRoot)
    $path = Join-Path $ProgramRoot 'scripts\TpmRequiredPatchRecipes.json'
    if (-not (Test-TpmNoReparsePath $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'The bundled required-patch recipe catalog is missing or unsafe.'
    }
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($item.Length -gt 262144) { throw 'The bundled required-patch recipe catalog exceeds its size limit.' }
    $bytes = [IO.File]::ReadAllBytes($path)
    $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($sha256 -ine $script:TpmRequiredPatchCatalogSha256) { throw 'The bundled required-patch recipe catalog hash does not match the pinned catalog.' }
    $encoding = New-Object System.Text.UTF8Encoding($false,$true)
    $content = $encoding.GetString($bytes)
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ine $sha256) { throw 'The bundled recipe catalog changed while it was read.' }
    $catalog = $content | ConvertFrom-Json -ErrorAction Stop
    if ($catalog.Schema -ne 3 -or $catalog.Entries -isnot [array] -or @($catalog.Entries).Count -eq 0) {
        throw 'The bundled required-patch recipe catalog schema is invalid.'
    }
    return [pscustomobject]@{ Path=$path; Content=$content; CatalogSha256=$sha256; Entries=@($catalog.Entries); Schema=[int]$catalog.Schema }
}

# The ZIP files and member names that can supply this recipe's file: the main one first, then any alternates the recipe lists.
# Every choice is checked against the same size and SHA-256 pins, so an alternate never weakens the check.
function Get-TpmRequiredPatchSourceChoices {
    param([Parameter(Mandatory)]$Entry)
    $choices = New-Object System.Collections.Generic.List[object]
    [void]$choices.Add([pscustomobject]@{ SourceSet = [string]$Entry.SourceSet; SourceEntry = [string]$Entry.SourceEntry })
    if ($Entry.PSObject.Properties['AlternateSources']) {
        foreach ($alternate in @($Entry.AlternateSources)) { [void]$choices.Add([pscustomobject]@{ SourceSet = [string]$alternate.SourceSet; SourceEntry = [string]$alternate.SourceEntry }) }
    }
    foreach ($choice in $choices) {
        if ([IO.Path]::GetFileName($choice.SourceSet) -cne $choice.SourceSet -or
            $choice.SourceSet -match '[<>:"|?*\p{Cc}]') { throw 'The recipe source set must be one exact ZIP filename.' }
    }
    return $choices.ToArray()
}

# The first choice whose ZIP is a safe file in the folder, or $null.
function Find-TpmRequiredPatchSourceChoice {
    param([Parameter(Mandatory)]$Entry, [string]$Folder = '')
    if ([string]::IsNullOrWhiteSpace($Folder) -or
        -not (Test-Path -LiteralPath $Folder -PathType Container -ErrorAction SilentlyContinue) -or
        -not (Test-TpmNoReparsePath $Folder)) { return $null }
    foreach ($choice in @(Get-TpmRequiredPatchSourceChoices -Entry $Entry)) {
        $archivePath = Join-Path $Folder $choice.SourceSet
        if ((Test-Path -LiteralPath $archivePath -PathType Leaf -ErrorAction SilentlyContinue) -and (Test-TpmNoReparsePath $archivePath)) { return $choice }
    }
    return $null
}

# Plain words for a missing ZIP: it is not downloaded by TeknoParrot Manager, and the exact file names that would work.
function Get-TpmRequiredPatchMissingZipText {
    param([Parameter(Mandatory)]$Entry)
    $choices = @(Get-TpmRequiredPatchSourceChoices -Entry $Entry)
    $names = (@($choices | ForEach-Object { '"' + $_.SourceSet + '"' }) -join ' or ')
    $text = 'The ZIP file with this patch was not found. TeknoParrot Manager does not download it. Put ' + $names + ' in the folder you choose.'
    if ($choices.Count -gt 1) { $text += ' Either file works; the second is the ZIP of the game itself.' }
    elseif ([string]$Entry.SourceRole -ceq 'UserSelected') { $text += ' This is a separate download that TeknoParrot Manager does not provide.' }
    return $text
}

function Resolve-TpmRequiredPatchSourceRoot {
    param(
        [Parameter(Mandatory)]$Entry,
        [string]$MainSource = '',
        [string]$SupplementarySource = '',
        [string]$RememberedFolder = ''
    )
    $choices = @(Get-TpmRequiredPatchSourceChoices -Entry $Entry)
    $root = switch ([string]$Entry.SourceRole) {
        'Main' { $MainSource }
        'Supplementary' { $SupplementarySource }
        default { '' }
    }
    if (Find-TpmRequiredPatchSourceChoice -Entry $Entry -Folder $root) { return [IO.Path]::GetFullPath($root) }
    # The folder the user gave for an earlier patch is tried first, so the question is not asked again when this ZIP is there too.
    if (Find-TpmRequiredPatchSourceChoice -Entry $Entry -Folder $RememberedFolder) { return [IO.Path]::GetFullPath($RememberedFolder) }
    $sourceLabel = switch ([string]$Entry.SourceRole) {
        'Main' { 'Main' }
        'Supplementary' { 'Supplementary' }
        'UserSelected' { 'patch' }
        default { 'required patch' }
    }
    if ($choices.Count -eq 1) {
        Write-Host ("  Select the local {0} ZIP folder containing this exact file: {1}" -f $sourceLabel,$choices[0].SourceSet) -ForegroundColor Cyan
    } else {
        Write-Host ("  Select the local {0} ZIP folder containing one of these exact files:" -f $sourceLabel) -ForegroundColor Cyan
        foreach ($choice in $choices) { Write-Host ('    ' + $choice.SourceSet) -ForegroundColor Cyan }
    }
    Write-Host '  TeknoParrot Manager reads only the named file inside the ZIP. It does not download or unpack the whole ZIP.' -ForegroundColor DarkGray
    Write-Host '  Do not have it? Press Enter with nothing typed to skip this patch. Nothing is changed, and you go on to the next one.' -ForegroundColor Yellow
    $selected = Read-PathWithBrowse -Prompt 'Folder containing the exact required local ZIP' -Mode Folder -InitialDirectory $root
    if ([string]::IsNullOrWhiteSpace($selected) -or
        -not (Test-Path -LiteralPath $selected -PathType Container -ErrorAction SilentlyContinue) -or
        -not (Test-TpmNoReparsePath $selected)) { throw 'No safe local source folder was selected.' }
    $selected = [IO.Path]::GetFullPath($selected)
    if (-not (Find-TpmRequiredPatchSourceChoice -Entry $Entry -Folder $selected)) {
        throw ('The selected folder does not contain the exact required ZIP. ' + (Get-TpmRequiredPatchMissingZipText -Entry $Entry))
    }
    return $selected
}

# Starts the installed 7-Zip on one exact member of a 7z or RAR file and returns the process; the member's bytes arrive on its standard output.
# Only the fixed Program Files location is used (never PATH, never a download). The caller streams the bytes and still checks size and SHA-256, so 7-Zip only supplies bytes.
function Start-TpmSevenZipMember {
    param([Parameter(Mandatory)][string]$ArchivePath,[Parameter(Mandatory)][string]$Member,[Parameter(Mandatory)][int64]$Size)
    $exe = @(@($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | ForEach-Object { Join-Path $_ '7-Zip\7z.exe' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($exe.Count -eq 0 -or -not (Test-TpmNoReparsePath $exe[0])) { throw '7-Zip is not installed, so this 7z or RAR patch file cannot be read.' }
    if ($ArchivePath.Contains('"') -or $Member.Contains('"')) { throw 'The archive or member name is not supported.' }
    $start = {
        param([string]$Arguments)
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $exe[0]; $info.Arguments = $Arguments
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true; $info.RedirectStandardInput = $true
        $info.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
        $started = [Diagnostics.Process]::Start($info)
        $started.StandardInput.Close()
        return $started
    }
    $listing = & $start ('l -slt -ba -spd -sccUTF-8 -bse0 -bsp0 -- "' + $ArchivePath + '"')
    try { $text = $listing.StandardOutput.ReadToEnd(); $listing.WaitForExit(); $listed = $listing.ExitCode } finally { $listing.Dispose() }
    if ($listed -ne 0) { throw 'The archive could not be listed with 7-Zip.' }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($line in ($text -split "`n")) {
        $line = $line.TrimEnd("`r")
        if ($line.StartsWith('Path = ')) { $items.Add([pscustomobject]@{ Path = $line.Substring(7); Size = -1L; IsFolder = $false }) }
        elseif ($items.Count -and $line.StartsWith('Size = ') -and $line.Length -gt 7) { $items[$items.Count - 1].Size = [int64]$line.Substring(7) }
        elseif ($items.Count -and $line.StartsWith('Attributes = D')) { $items[$items.Count - 1].IsFolder = $true }
    }
    # Letter case is ignored (a pack may spell a folder differently from the game); the size and SHA-256 pins still fix the exact file, and two members that differ only by case are refused.
    $found = @($items | Where-Object { ($_.Path -replace '\\','/') -ieq $Member })
    if ($found.Count -ne 1 -or $found[0].IsFolder -or $found[0].Size -ne $Size) {
        throw 'The exact required archive member is absent, duplicated, or has a different size.'
    }
    return (& $start ('e -so -y -bd -spd -bso0 -bsp0 -bse0 -- "' + $ArchivePath + '" "' + $found[0].Path + '"'))
}

function New-TpmRequiredPatchPayloadStage {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$SourceRoot)
    $stage = $null
    $archive = $null
    $memberStream = $null
    $output = $null
    $process = $null
    try {
        if (-not $script:TpmOwnedLayout -or -not $script:TpmOwnedLayout.Temp -or
            -not (Test-PathInside $script:TpmOwnedLayout.Temp $script:TpmOwnedLayout.Root) -or
            -not (Test-TpmNoReparsePath $script:TpmOwnedLayout.Temp)) { throw 'The TeknoParrot Manager temporary staging root is unavailable.' }
        $choice = Find-TpmRequiredPatchSourceChoice -Entry $Entry -Folder $SourceRoot
        if (-not $choice) { throw ('The exact local source ZIP is unavailable or unsafe. ' + (Get-TpmRequiredPatchMissingZipText -Entry $Entry)) }
        $archivePath = [IO.Path]::GetFullPath((Join-Path $SourceRoot $choice.SourceSet))
        if (-not (Test-PathInside $archivePath $SourceRoot) -or -not (Test-TpmNoReparsePath $archivePath) -or
            -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw 'The exact local source ZIP is unavailable or unsafe.' }
        if ($Entry.SourceSize -isnot [int] -and $Entry.SourceSize -isnot [long]) { throw 'The recipe has no bounded member size.' }
        if ($Entry.SourceSize -le 0 -or $Entry.SourceSize -gt $script:TpmPatchMaxBytes) { throw 'The recipe member size exceeds the supported bound.' }
        # SourceSha1 preserves DAT identity metadata; SHA256 is the runtime payload pin.
        if ([string]$Entry.SourceSha1 -notmatch '^[a-fA-F0-9]{40}$' -or
            [string]$Entry.SourceSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'The recipe member hash pins are invalid.' }
        Assert-TpmPatchFreeSpace @(@{Path=$script:TpmOwnedLayout.Temp;Bytes=[int64]$Entry.SourceSize})
        $stage = Join-Path $script:TpmOwnedLayout.Temp ('RequiredPatch-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($stage)
        if (-not (Test-PathInside $stage $script:TpmOwnedLayout.Temp) -or -not (Test-TpmNoReparsePath $stage)) {
            throw 'The unique patch staging directory failed its containment check.'
        }
        $payload = Resolve-TpmPatchPath $stage ([string]$Entry.Operations[0].Payload) -Staging
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
        if ($archivePath -match '\.(7z|rar)$') {
            $process = Start-TpmSevenZipMember -ArchivePath $archivePath -Member $choice.SourceEntry -Size ([int64]$Entry.SourceSize)
            $memberStream = $process.StandardOutput.BaseStream
        } else {
            # Fixed framework assembly names are required by Windows PowerShell 5.1.
            Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
            $members = @($archive.Entries | Where-Object { $_.FullName -ieq $choice.SourceEntry })
            if ($members.Count -ne 1 -or $members[0].Length -ne [int64]$Entry.SourceSize) {
                throw 'The exact required ZIP member is absent, duplicated, or has a different size.'
            }
            $memberStream = $members[0].Open()
        }
        $output = New-Object IO.FileStream($payload,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer = New-Object byte[] 65536
        $total = [int64]0
        while (($read = $memberStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt [int64]$Entry.SourceSize -or $total -gt $script:TpmPatchMaxBytes) { throw 'The ZIP member exceeded its pinned size while streaming.' }
            $output.Write($buffer,0,$read)
        }
        $output.Flush($true)
        $output.Dispose();$output=$null
        if ($process) { $process.WaitForExit(); if ($process.ExitCode -ne 0) { throw 'The archive member could not be read with 7-Zip.' } }
        $memberStream.Dispose();$memberStream=$null
        if ($total -ne [int64]$Entry.SourceSize) { throw 'The ZIP member byte count differs from its pinned size.' }
        $sha256 = (Get-FileHash -LiteralPath $payload -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($sha256 -ine [string]$Entry.SourceSha256 -or
            $sha256 -ine [string]$Entry.Operations[0].PayloadSha256 -or
            $sha256 -ine [string]$Entry.Operations[0].AfterSha256) { throw 'The streamed local member does not match the payload and target SHA-256 pins.' }
        return [pscustomobject]@{ Root=$stage; Payload=$payload; Size=$total; Sha256=$sha256; SourceArchive=$archivePath; SourceEntry=$choice.SourceEntry }
    } catch {
        $failure=$_
        try {
            if($output){$output.Dispose();$output=$null}
            if($memberStream){$memberStream.Dispose();$memberStream=$null}
            if($archive){$archive.Dispose();$archive=$null}
            if($process){if(-not $process.HasExited){$process.Kill()};$process.Dispose();$process=$null}
        } catch {
            throw ('Patch payload staging resources could not be closed; original error: '+$failure.Exception.Message+'; cleanup error: '+$_.Exception.Message)
        }
        if ($stage -and (Test-PathInside $stage $script:TpmOwnedLayout.Temp) -and (Test-Path -LiteralPath $stage)) {
            if(-not (Test-TpmNoReparsePath $stage)){throw ('Unsafe staging residue was preserved at '+$stage+'; original error: '+$failure.Exception.Message)}
            try {
                Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop
                if(Test-Path -LiteralPath $stage){throw 'The staged directory remains after cleanup.'}
            } catch {
                throw ('Patch payload staging cleanup requires attention at '+$stage+': '+$_.Exception.Message+'; original error: '+$failure.Exception.Message)
            }
        }
        throw $failure
    } finally {
        if ($output) { $output.Dispose() }
        if ($memberStream) { $memberStream.Dispose() }
        if ($archive) { $archive.Dispose() }
        if ($process) { if (-not $process.HasExited) { $process.Kill() }; $process.Dispose() }
    }
}

function Test-TpmRequiredPatchPrerequisites {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$GameRoot)
    $missing = New-Object System.Collections.Generic.List[object]
    foreach ($prerequisite in @($Entry.Prerequisites)) {
        if ($prerequisite -isnot [pscustomobject] -or
            @($prerequisite.PSObject.Properties.Name | Where-Object { $_ -notin @('Id','Type','Path','Description','Section','Key','Value') }).Count -gt 0 -or
            [string]::IsNullOrWhiteSpace([string]$prerequisite.Id) -or
            [string]::IsNullOrWhiteSpace([string]$prerequisite.Description)) {
            throw 'A bundled prerequisite rule is malformed.'
        }
        $path = Resolve-TpmPatchPath $GameRoot ([string]$prerequisite.Path)
        if ($prerequisite.Type -ceq 'File') {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue) -or
                -not (Test-TpmNoReparsePath $path)) { [void]$missing.Add($prerequisite); continue }
        } elseif ($prerequisite.Type -ceq 'IniValue') {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue) -or
                -not (Test-TpmNoReparsePath $path) -or (Get-Item -LiteralPath $path).Length -gt 1048576) {
                [void]$missing.Add($prerequisite); continue
            }
            $section = ''
            $values = New-Object System.Collections.Generic.List[string]
            foreach ($line in [IO.File]::ReadAllLines($path)) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^\[([^\]]+)\]$') {
                    $section = $Matches[1].Trim()
                    continue
                }
                if ($section -ieq [string]$prerequisite.Section -and $trimmed -match '^([^=]+?)\s*=\s*(.*?)\s*$' -and
                    $Matches[1].Trim() -ieq [string]$prerequisite.Key) { [void]$values.Add($Matches[2].Trim()) }
            }
            if ($values.Count -ne 1 -or $values[0] -cne [string]$prerequisite.Value) { [void]$missing.Add($prerequisite) }
        } else {
            throw 'A bundled prerequisite type is unsupported.'
        }
    }
    $guidance = @()
    foreach ($item in $missing) {
        if ($item.Id -ceq 'bepinex-core') {
            $guidance += 'BepInEx is not installed for this game. Use the existing BepInEx setup of TeknoParrot Manager with the authorized source, or your own local BepInEx files. TeknoParrot Manager will not download a game patch.'
        } elseif ($item.Id -ceq 'bepinex-entrypoint-mode') {
            $guidance += 'Run the game once so BepInEx creates BepInEx\config\BepInEx.cfg. In [Preloader.Entrypoint], set Type = MonoBehaviour, save, then restart the game. The guide warns the first run may hang at the hazy-blue-screen stage; close it with Task Manager after setup.'
        } else {
            $guidance += [string]$item.Description
        }
    }
    return [pscustomobject]@{ Satisfied=($missing.Count -eq 0); Missing=@($missing.ToArray()); Guidance=@($guidance); Summary=if($missing.Count){'Required setup prerequisites are not yet verified.'}else{'All bundled prerequisites are verified.'} }
}

function Get-TpmManualPatchContext {
    param(
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$TpRoot,
        [Parameter(Mandatory)][string]$UserProfilesDir,
        [Parameter(Mandatory)][string]$ManagerRoot,
        [Parameter(Mandatory)][string]$GameRoot,
        [string[]]$SourceRoots = @(),
        [switch]$ForUndo
    )
    foreach ($root in @($TpRoot,$ManagerRoot)) {
        if (-not [IO.Path]::IsPathRooted($root) -or -not (Test-TpmNoReparsePath $root)) { throw 'The TeknoParrot or TeknoParrot Manager root is unsafe.' }
    }
    if ([IO.Path]::GetFullPath($UserProfilesDir) -ine [IO.Path]::GetFullPath((Join-Path $TpRoot 'UserProfiles')) -or
        -not (Test-Path -LiteralPath (Join-Path $TpRoot 'TeknoParrotUi.exe') -PathType Leaf)) { throw 'A configured TeknoParrot installation is required.' }
    if ($Entry.ProfileId -isnot [string] -or $Entry.ProfileId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { throw 'Invalid exact profile identity.' }
    $official = Resolve-TpmPatchPath (Join-Path $TpRoot 'GameProfiles') ($Entry.ProfileId + '.xml') -ForUndo:$ForUndo
    if (-not (Test-Path -LiteralPath $official -PathType Leaf) -or -not (Test-TpmNoReparsePath $official)) {
        throw 'The exact TeknoParrot GameProfile template is unavailable.'
    }
    if (-not [IO.Path]::IsPathRooted($GameRoot) -or -not (Test-Path -LiteralPath $GameRoot -PathType Container) -or
        -not (Test-TpmNoReparsePath $GameRoot)) { throw 'The selected installed game folder is unavailable or unsafe.' }
    $game = [IO.Path]::GetFullPath($GameRoot)
    # The same trimming as the plan: a folder typed with a trailing backslash must find the same undo records.
    if ($game.Length -gt [IO.Path]::GetPathRoot($game).Length) { $game = $game.TrimEnd('\', '/') }
    if (-not (Test-TpmNoReparsePath $game)) { throw 'The canonical game folder is unsafe.' }
    if ($script:TpmOwnedLayout -and (Test-TpmPathOverlap $game $script:TpmOwnedLayout.Root)) {
        throw 'The selected game folder overlaps TeknoParrot Manager files.'
    }
    $protected = @((Join-Path $TpRoot 'TeknoParrotUi.exe'),(Join-Path $TpRoot 'GameProfiles'),$UserProfilesDir,
        (Join-Path $ManagerRoot 'TeknoParrot-Manager.ps1'),(Join-Path $ManagerRoot 'TeknoParrot-Manager.config.json'),
        (Join-Path $ManagerRoot 'tools'),(Join-Path $ManagerRoot 'Crosshairs'))
    $protected += @($SourceRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($root in $protected) {
        if (Test-TpmPathOverlap $game $root) { throw 'The selected game folder overlaps TeknoParrot, TeknoParrot Manager, or a patch source.' }
    }
    $gamePath = Resolve-TpmPatchPath $game ([string]$Entry.Executable) -ForUndo:$ForUndo
    $gameNative = if ($gamePath.StartsWith('\\')) { '\\?\UNC\' + $gamePath.Substring(2) } else { '\\?\' + $gamePath }
    if (-not [IO.File]::Exists($gameNative) -or -not (Test-TpmNoReparsePath $gamePath)) {
        throw 'The exact recipe executable is not present in the selected game folder.'
    }
    $registered = $false
    $profileHash = ''
    $profilePath = Join-Path $UserProfilesDir ($Entry.ProfileId + '.xml')
    if (Test-Path -LiteralPath $profilePath -PathType Leaf -ErrorAction SilentlyContinue) {
        if (-not (Test-TpmNoReparsePath $profilePath)) { throw 'The existing registered profile path is unsafe.' }
        $profileHash = (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument = 4194304
        $reader = [Xml.XmlReader]::Create($profilePath,$settings)
        $doc = New-Object Xml.XmlDocument
        $doc.XmlResolver = $null
        try { $doc.Load($reader) } finally { $reader.Dispose() }
        $nodes = @($doc.SelectNodes('/GameProfile/GamePath'))
        if ($nodes.Count -ne 1 -or -not [IO.Path]::IsPathRooted([string]$nodes[0].InnerText)) {
            throw 'The existing registered profile has no one rooted GamePath.'
        }
        if ([IO.Path]::GetFullPath(([string]$nodes[0].InnerText).Trim()) -ine [IO.Path]::GetFullPath($gamePath) -or
            (Get-FileHash -LiteralPath $profilePath -Algorithm SHA256).Hash -ine $profileHash) {
            throw 'The registered profile changed or points to a different game executable.'
        }
        $registered = $true
    }
    if ($script:TpmOwnedLayout) {
        if (-not (Test-PathInside $script:TpmOwnedLayout.Backups $script:TpmOwnedLayout.Root) -or
            -not (Test-TpmNoReparsePath $script:TpmOwnedLayout.Backups)) {
            throw 'The TeknoParrot Manager backup layout is unsafe.'
        }
        $recovery = Join-Path $script:TpmOwnedLayout.Backups 'GamePatches'
    } else {
        $recovery = Join-Path $ManagerRoot 'UpdateBackups\GamePatches'
    }
    return [pscustomobject]@{
        ProfileId = $Entry.ProfileId
        ProfilePath = if ($registered) { $profilePath } else { '' }
        ProfileSha256 = $profileHash
        GamePath = $gamePath
        GameRoot = $game
        RecoveryRoot = $recovery
        ProtectedRoots = @($protected)
        Registered = $registered
    }
}

# =============================================================================
# SCREENS OF THE REQUIRED-PATCH MENU (FIX81)
# =============================================================================
# The default view talks about games, not recipe ids: one row per game, games with the same result share one line,
# plain words, a blank line between the parts. Recipe ids, the technical reason, result codes and undo-copy folders
# are behind the D key (one short block per game) and are always written to the log. All text goes through
# Write-TpmText and Show-TpmDetailBlocks, which measure the console on every call, so the screens reflow on resize.

# The exact build name of a recipe (the recipe id when a recipe has none).
function Get-TpmRequiredPatchBuildName {
    param([Parameter(Mandatory)]$Entry)
    if ($Entry.PSObject.Properties['BuildName'] -and -not [string]::IsNullOrWhiteSpace([string]$Entry.BuildName)) { return [string]$Entry.BuildName }
    return [string]$Entry.Id
}

# The game name a person knows: the build name without its version, date and platform tags, for example
# "Hummer Extreme Edition". The exact build name stays in the details.
function Get-TpmRequiredPatchShortName {
    param([AllowEmptyString()][string]$BuildName)
    $short = ($BuildName -replace '\s*[\(\[].*$', '').Trim()
    if ([string]::IsNullOrWhiteSpace($short)) { return $BuildName }
    return $short
}

# The parts of a build name that tell two builds apart, in plain words: the version, the region and the hardware.
# The release date and the [TP] tag are left out. "(1.00.00,1.50.00)" becomes "version 1.00.00 and 1.50.00".
function Get-TpmRequiredPatchBuildParts {
    param([AllowEmptyString()][string]$BuildName)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($found in [regex]::Matches($BuildName, '\(([^)]*)\)|\[([^\]]*)\]')) {
        $text = ($found.Groups[1].Value + $found.Groups[2].Value).Trim()
        if ($text -eq '' -or $text -ceq 'TP' -or $text -match '^\d{4}-\d{2}-\d{2}$') { continue }
        if ($text -match '^\d') { $text = 'version ' + (($text -split '\s*,\s*') -join ' and ') }
        [void]$parts.Add($text)
    }
    return $parts.ToArray()
}

# One group per exact game build, in catalog order: @{ BuildName; Name; Entries; Count }. Name is the short game
# name. When builds share a short name, it is the short name plus only the parts that differ between them, for
# example "Dead or Alive 6, version 1.01.00". Builds that still look the same (for example only the date differs)
# get ", build 1", ", build 2" so no two rows share a name.
function Get-TpmRequiredPatchGameGroups {
    param([object[]]$Entries = @())
    $order = New-Object System.Collections.Generic.List[string]
    $buckets = @{}
    foreach ($entry in @($Entries)) {
        $build = Get-TpmRequiredPatchBuildName -Entry $entry
        if (-not $buckets.ContainsKey($build)) {
            $buckets[$build] = New-Object System.Collections.Generic.List[object]
            [void]$order.Add($build)
        }
        [void]$buckets[$build].Add($entry)
    }
    $shortNames = @{}
    $parts = @{}
    foreach ($build in $order) {
        $shortNames[$build] = Get-TpmRequiredPatchShortName -BuildName $build
        $parts[$build] = @(Get-TpmRequiredPatchBuildParts -BuildName $build)
    }
    $names = @{}
    foreach ($build in $order) {
        $name = $shortNames[$build]
        $same = @($order | Where-Object { $shortNames[$_] -ieq $name })
        if ($same.Count -gt 1) {
            $differing = @($parts[$build] | Where-Object { $part = $_; @($same | Where-Object { $parts[$_] -contains $part }).Count -lt $same.Count })
            if ($differing.Count -gt 0) { $name = $name + ', ' + ($differing -join ', ') }
        }
        $names[$build] = $name
    }
    $counter = @{}
    $groups = New-Object System.Collections.Generic.List[object]
    foreach ($build in $order) {
        $name = $names[$build]
        if (@($order | Where-Object { $names[$_] -ieq $name }).Count -gt 1) {
            $counter[$name] = 1 + [int]$counter[$name]
            $name = '{0}, build {1}' -f $name, $counter[$name]
        }
        $items = $buckets[$build].ToArray()
        [void]$groups.Add([pscustomobject]@{ BuildName = $build; Name = $name; Entries = $items; Count = $items.Count })
    }
    return $groups.ToArray()
}

# Details of the game list: the exact game version and the recipe ids behind each row.
function Get-TpmRequiredPatchGameBlocks {
    param([object[]]$Groups)
    $blocks = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($Groups)) {
        $lines = @(
            ('Exact version: ' + $group.BuildName),
            ('Patches: ' + $group.Count),
            ('Patch ids: ' + ((@($group.Entries | ForEach-Object { [string]$_.Id })) -join ', '))
        )
        [void]$blocks.Add(@{ Heading = $group.Name; Lines = $lines })
    }
    return $blocks.ToArray()
}

# "Pick your game": one numbered row per game, with how many patches it has.
function Show-TpmRequiredPatchGameList {
    param([Parameter(Mandatory)][object[]]$Groups)
    $groupList = @($Groups)
    $numberWidth = ([string]$groupList.Count).Length
    Write-TpmText -Text 'Pick your game:' -Color Cyan -BlankBefore -BlankAfter
    for ($index = 0; $index -lt $groupList.Count; $index++) {
        $prefix = ('{0}) ' -f ($index + 1)).PadLeft($numberWidth + 2)
        $optionalNote = if (@($groupList[$index].Entries | Where-Object { -not (Test-TpmRequiredPatchOptional -Entry $_) }).Count -eq 0) { ', optional' } else { '' }
        $label = '{0} ({1}{2})' -f $groupList[$index].Name, (Format-TpmCountNoun -Count $groupList[$index].Count -Singular 'patch'), $optionalNote
        Write-TpmText -Text $label -Prefix $prefix -Indent 2
    }
    Write-Host ''
}

# Asks which game. D shows the exact game versions and patch ids. Returns the chosen group, or $null when the
# answer is not a number from the list.
# Differs from Read-TpmNumberedListChoice: every row is shown at once (no M), and a wrong answer is told so instead of asked again.
function Read-TpmRequiredPatchGameChoice {
    param([Parameter(Mandatory)][object[]]$Groups)
    $groupList = @($Groups)
    Show-TpmRequiredPatchGameList -Groups $groupList
    $answer = Read-TpmAnswerWithDetails -Prompt '  Type the number of your game, or D for details' -DetailBlocks @(Get-TpmRequiredPatchGameBlocks -Groups $groupList)
    $parsed = 0
    if (-not [int]::TryParse($answer, [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt $groupList.Count) {
        Write-TpmText -Text 'That is not a number in the list. Nothing was changed.' -Color DarkGray
        return $null
    }
    return $groupList[$parsed - 1]
}

# Asks for the folder the chosen game is installed in (once per game, not once per patch).
function Read-TpmRequiredPatchGameFolder {
    param([Parameter(Mandatory)][string]$Choice, [Parameter(Mandatory)]$Group, [string]$InitialDirectory = '')
    $second = if ($Choice -eq 'U') { 'The saved undo copy is used to put the game files back.' } else { 'It must contain {0}. Nothing changes until you say so.' -f $Group.Entries[0].Executable }
    Write-TpmText -Text ('Choose the folder where {0} is installed.' -f $Group.Name) -Color Cyan -BlankBefore
    Write-TpmText -Text $second -Color Cyan
    return (Read-PathWithBrowse -Prompt 'Installed game folder' -Mode Folder -InitialDirectory $InitialDirectory)
}

# The last question of a screen. With details it offers D; the question is asked once, as before.
function Wait-TpmRequiredPatchReturn {
    param([object[]]$DetailBlocks = @(), [string]$DetailsNote = '')
    $prompt = if (@($DetailBlocks).Count -gt 0) { '  Press D for details, or Enter to go back' } else { '  Press Enter to go back' }
    [void](Read-TpmAnswerWithDetails -Prompt $prompt -DetailBlocks $DetailBlocks -DetailsNote $DetailsNote)
}

# Records what happened to one patch and writes it to the log. The screens group these records later.
function Add-TpmRequiredPatchResult {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()]$Results,
        [Parameter(Mandatory)]$Entry,
        [Parameter(Mandatory)][string]$Status,
        [AllowEmptyString()][string]$Reason = '',
        [string]$Receipt = '',
        [bool]$Registered = $true
    )
    [void]$Results.Add([pscustomobject]@{ Entry = $Entry; Status = $Status; Reason = $Reason; Receipt = $Receipt; Registered = $Registered })
    $receiptText = if ($Receipt) { ' Undo copy: ' + $Receipt } else { '' }
    Write-Log ('Required patch result [{0}] {1}: {2}{3}' -f $Status, [string]$Entry.Id, $Reason, $receiptText)
}

# One ZIP-folder question per run: the folder the user gives is remembered and tried first for every following patch.
# A patch whose ZIP is not in that folder asks again. The ZIP file itself is still checked for every patch when its member is read.
function Get-TpmRequiredPatchSourceRootOnce {
    param([Parameter(Mandatory)][hashtable]$Cache, [Parameter(Mandatory)]$Entry, [string]$MainSource = '', [string]$SupplementarySource = '')
    $key = [string]$Entry.SourceRole + '|' + [string]$Entry.SourceSet
    if (-not $Cache.ContainsKey($key)) {
        $remembered = if ($Cache.ContainsKey('RememberedFolder')) { [string]$Cache['RememberedFolder'] } else { '' }
        $Cache[$key] = Resolve-TpmRequiredPatchSourceRoot -Entry $Entry -MainSource $MainSource -SupplementarySource $SupplementarySource -RememberedFolder $remembered
        $Cache['RememberedFolder'] = [string]$Cache[$key]
    }
    return $Cache[$key]
}

# A settings-line edit (SetIniValue) changes one line in a game file: no ZIP, no source folder, and no program hash when the recipe has none.
function Test-TpmRequiredPatchEditOnly {
    param([Parameter(Mandatory)]$Entry)
    $operations = @($Entry.Operations)
    return ($operations.Count -gt 0 -and @($operations | Where-Object { $_.Type -cne 'SetIniValue' }).Count -eq 0)
}

# Optional edits (the game works without them) are never installed by "all my registered games"; the player picks them with M.
function Test-TpmRequiredPatchOptional {
    param([Parameter(Mandatory)]$Entry)
    return ([string]$Entry.Id -cin @('lost-land-adventure-shader-reload-off'))
}

# An empty staging folder for a settings-line edit: the engine puts the edited file here. No ZIP is read.
function New-TpmRequiredPatchEditStage {
    $root = Join-Path $script:TpmOwnedLayout.Temp ('RequiredPatchEdit-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    return [pscustomobject]@{ Root = $root; Payload = '' }
}

# The installed executable is checked before any ZIP is asked for or staged, so a build the user does not have never asks for its ZIP.
# Returns $true when the installed build is the one this recipe is for; otherwise it records the result and returns $false.
function Test-TpmRequiredPatchBuild {
    param([Parameter(Mandatory)]$Entry, [Parameter(Mandatory)][string]$GamePath, [Parameter(Mandatory)][object[]]$Entries, [Parameter(Mandatory)]$Results)
    if ((Test-TpmRequiredPatchEditOnly -Entry $Entry) -and [string]::IsNullOrWhiteSpace([string]$Entry.ExecutableSha256)) { return $true }
    $installed = (Get-FileHash -LiteralPath $GamePath -Algorithm SHA256 -ErrorAction Stop).Hash
    $isInstalledBuild = {
        param($candidate)
        $allowed = @([string]$candidate.ExecutableSha256)
        if ($candidate.PSObject.Properties['AllowExecutableSelfPatch'] -and $candidate.AllowExecutableSelfPatch) { $allowed += [string]$candidate.Operations[0].AfterSha256 }
        return ($installed -in $allowed)
    }
    if (& $isInstalledBuild $Entry) { return $true }
    if (@($Entries | Where-Object { $_.ProfileId -ceq $Entry.ProfileId -and (& $isInstalledBuild $_) }).Count) {
        Add-TpmRequiredPatchResult -Results $Results -Entry $Entry -Status 'SKIPPED' -Reason 'Another build of this game is installed here, so this build was not needed.'
    } else {
        Add-TpmRequiredPatchResult -Results $Results -Entry $Entry -Status 'BLOCKED' -Reason 'The installed executable is not in an exact supported before/after state.'
    }
    return $false
}

# The words, color and weight of a result status. Problem is true only for a real failure.
function Get-TpmRequiredPatchStatusInfo {
    param([string]$Status, [string]$Action = 'Install')
    $could = if ($Action -eq 'Undo') { 'Could not undo' } else { 'Could not install' }
    $table = @{
        'INSTALLED'       = @('Installed and checked', 'Green', $false)
        'UNDONE'          = @('Undone', 'Green', $false)
        'ALREADY_APPLIED' = @('Already installed, nothing to do', 'Green', $false)
        'SKIPPED'         = @('Skipped', 'DarkGray', $false)
        'OTHER_VARIANT'   = @('Skipped', 'DarkGray', $false)
        'NOTHING_TO_UNDO' = @('Nothing to undo', 'DarkGray', $false)
        'CANCELLED'       = @('Skipped', 'DarkGray', $false)
        'FAILED'          = @($could, 'Red', $true)
        'BLOCKED'         = @($could, 'Yellow', $true)
        'ACTION REQUIRED' = @('Needs your attention', 'Yellow', $true)
    }
    $row = if ($table.ContainsKey($Status)) { $table[$Status] } else { @($Status, 'Yellow', $true) }
    return [pscustomobject]@{ Lead = [string]$row[0]; Color = [string]$row[1]; Problem = [bool]$row[2] }
}

# One plain sentence for the reason behind a result. The first matching rule wins; the technical text stays
# in the details and the log. An unknown reason gets a safe general sentence.
function Get-TpmRequiredPatchPlainReason {
    param([string]$Status, [AllowEmptyString()][string]$Reason = '')
    if ($Status -ceq 'INSTALLED' -or $Status -ceq 'ALREADY_APPLIED') { return '' }
    if ($Status -ceq 'UNDONE') { return 'The game files are back the way they were.' }
    if ($Status -ceq 'SKIPPED') { return 'Nothing was changed.' }
    # A missing-ZIP reason that already carries the plain sentence (with the exact file names) is shown as it is.
    $missingMarker = 'The ZIP file with this patch was not found.'
    $missingAt = $Reason.IndexOf($missingMarker, [StringComparison]::Ordinal)
    if ($missingAt -ge 0) { return $Reason.Substring($missingAt) }

    $rules = @(
        @('No game folder was selected', 'You did not choose a game folder, so nothing was changed.'),
        @('Undo was not confirmed', 'You chose not to undo it, so nothing was changed.'),
        @('The drive [A-Za-z]: is not connected', 'The drive for this game is not connected, so nothing was changed. Connect it, or point the game at its new folder in 13) Library health check.'),
        @('^ACTION REQUIRED', 'An earlier patch install stopped part way, so some game files may already be changed. Check Details before you try again. This run changed nothing.'),
        @('Close the game', 'The game is running. Close it and try again.'),
        @('saved copy of this settings edit|needs its saved copy', 'The saved copy for undo was not found or is not correct. Nothing was changed.'),
        @('settings file was not found', 'The game settings file was not found in that folder. Run the game once, then try again. Nothing was changed.'),
        @('settings file|setting in the file', 'The game settings file is not the way TeknoParrot Manager expects, so it was left alone. Nothing was changed.'),
        @('BepInEx is not installed|BepInEx must be installed', 'BepInEx is not installed for this game. Set it up first with BepInEx setup in the main menu.'),
        @('Run the game once so BepInEx|BepInEx must run its preloader', 'BepInEx needs one more setting. Details have the steps.'),
        @('different exclusive hardware variant|No bundled variant applies', 'This version of the patch is for a different graphics card.'),
        @('exclusive recipe is active', 'Another version of this patch is already installed. Undo it first.'),
        @('does not contain the exact required ZIP|source ZIP is unavailable|No safe local source folder', 'The ZIP file with this patch was not found.'),
        @('Not enough free space', 'There is not enough free space on the drive for this patch. Nothing was changed.'),
        @('7-Zip is not installed', 'This patch is in a 7z or RAR file, so 7-Zip is needed. Install 7-Zip, then try again.'),
        @('archive member|with 7-Zip', 'The patch file inside the 7z or RAR file is missing or could not be read.'),
        @('ZIP member|payload and target', 'The patch file inside the ZIP is missing or is not the expected one.'),
        @('executable is not present', 'The game file was not found in that folder.'),
        @('Executable revision|executable is not in an exact supported', 'This is not the game version that the patch is made for.'),
        @('no verified applied patch state', 'There is no patch from TeknoParrot Manager to undo here.'),
        @('older patch list', 'This saved copy was made by an older patch list. Nothing was changed.'),
        @('receipt|backup invalid', 'The saved copy for undo was not found or is not correct. Nothing was changed.'),
        @('target conflict|Mixed/partially|target is unknown', 'A file in the game folder is different from what the patch expects. It was left alone.'),
        @('inside your source folder', 'This game is inside your source folder (where your game collection is kept). TeknoParrot Manager never changes your source folder. Move the game out of it, or fix the game folder in its profile.'),
        @('overlap|unsafe|reparse|containment', 'This folder cannot be used safely, so nothing was changed.'),
        @('More than one video adapter', 'This PC has more than one graphics card and none was picked. Run this again and choose the card the game uses.'),
        @('adapter|GPU|variant|hardware', 'This patch depends on your graphics card, and it could not be matched.'),
        @('path is too long', 'A folder path is too long for Windows. Move TeknoParrot or the game to a shorter folder, then try again. Nothing was changed.'),
        @('registered|GamePath|GameProfile|profile', 'This game is not set up in TeknoParrot the way the patch expects.')
    )
    foreach ($rule in $rules) {
        if ($Reason -match $rule[0]) { return [string]$rule[1] }
    }
    return 'Details have the reason.'
}

# Groups the results that share a status and a plain reason: @{ Key; Status; Lead; Color; Problem; Why; Results; Games }.
function Get-TpmRequiredPatchResultGroups {
    param([object[]]$Results, [string]$Action = 'Install')
    $groups = New-Object System.Collections.Generic.List[object]
    $byKey = @{}
    foreach ($result in @($Results)) {
        $why = Get-TpmRequiredPatchPlainReason -Status $result.Status -Reason $result.Reason
        $key = $result.Status + '|' + $why
        if (-not $byKey.ContainsKey($key)) {
            $info = Get-TpmRequiredPatchStatusInfo -Status $result.Status -Action $Action
            $byKey[$key] = [pscustomobject]@{ Key = $key; Status = [string]$result.Status; Lead = $info.Lead; Color = $info.Color; Problem = $info.Problem; Why = $why; Results = (New-Object System.Collections.Generic.List[object]); Games = @() }
            [void]$groups.Add($byKey[$key])
        }
        [void]$byKey[$key].Results.Add($result)
    }
    foreach ($group in $groups) {
        $group.Results = $group.Results.ToArray()
        $group.Games = @(Get-TpmRequiredPatchGameGroups -Entries @($group.Results | ForEach-Object { $_.Entry }))
    }
    return $groups.ToArray()
}

# Details of the results: one block per game and result, with every technical fact.
function Get-TpmRequiredPatchResultBlocks {
    param([object[]]$Groups)
    $blocks = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($Groups)) {
        $meaning = Get-TpmPlainReason -Code $group.Status
        foreach ($game in @($group.Games)) {
            $items = @($group.Results | Where-Object { (Get-TpmRequiredPatchBuildName -Entry $_.Entry) -ceq $game.BuildName })
            $lines = New-Object System.Collections.Generic.List[string]
            [void]$lines.Add('Result: ' + $group.Lead)
            if ($group.Why) { [void]$lines.Add('What happened: ' + $group.Why) }
            if ($meaning.Known) { [void]$lines.Add('What it means: ' + $meaning.Text) }
            foreach ($reason in @($items | ForEach-Object { [string]$_.Reason } | Where-Object { $_ } | Select-Object -Unique)) { [void]$lines.Add('Technical reason: ' + $reason) }
            [void]$lines.Add('Result code: ' + $group.Status)
            [void]$lines.Add('Patch ids: ' + ((@($items | ForEach-Object { [string]$_.Entry.Id })) -join ', '))
            foreach ($item in $items) { if ($item.Receipt) { [void]$lines.Add('Undo copy folder: ' + $item.Receipt) } }
            [void]$blocks.Add(@{ Heading = $game.BuildName; Lines = $lines.ToArray() })
        }
    }
    return $blocks.ToArray()
}

# Prints one line per group of results ("Already installed, nothing to do: A and B.") and returns the detail blocks.
function Show-TpmRequiredPatchResults {
    param([object[]]$Results, [string]$Action = 'Install')
    $groups = @(Get-TpmRequiredPatchResultGroups -Results $Results -Action $Action)
    foreach ($group in $groups) {
        $text = '{0}: {1}.' -f $group.Lead, (Format-TpmNameList -Names @($group.Games | ForEach-Object { $_.Name }))
        if ($group.Why) { $text += ' ' + $group.Why }
        Write-TpmText -Text $text -Color $group.Color -BlankBefore -HangingIndent 2
    }
    return (Get-TpmRequiredPatchResultBlocks -Groups $groups)
}

# Leftover receipt files from an interrupted install or undo are kept, never deleted. They are one cleanup note, not a result for a game:
# a game is named only when the file sits in that game's own undo folder. Returns the detail blocks.
function Write-TpmRequiredPatchResidueNote {
    param([hashtable]$Owners = @{})
    $paths = @($Owners.Keys | Sort-Object)
    if ($paths.Count -eq 0) { return @() }
    $names = @($Owners.Values | ForEach-Object { @($_) } | Select-Object -Unique)
    $text = 'Cleanup note: leftover files from an interrupted install or undo were kept. Nothing was deleted.'
    if ($names.Count -gt 0) { $text += ' They belong to ' + (Format-TpmNameList -Names $names) + '.' }
    Write-TpmText -Text $text -Color Yellow -BlankBefore -HangingIndent 2
    return @(@{ Heading = 'Leftover files'; Lines = @($paths | ForEach-Object { 'Kept: ' + $_ }) })
}

# After an install: what to do next, once (not once per patch).
function Write-TpmRequiredPatchNextSteps {
    param([object[]]$Results)
    $installed = @($Results | Where-Object { $_.Status -ceq 'INSTALLED' })
    if ($installed.Count -eq 0) { return }
    $notRegistered = @($installed | Where-Object { -not $_.Registered })
    if ($notRegistered.Count -gt 0) {
        $games = @(Get-TpmRequiredPatchGameGroups -Entries @($notRegistered | ForEach-Object { $_.Entry }))
        $pronoun = if ($games.Count -eq 1) { 'it' } else { 'them' }
        Write-TpmText -Text ('Not in TeknoParrot yet: {0}. Use Register only in the main menu to add {1}.' -f (Format-TpmNameList -Names @($games | ForEach-Object { $_.Name })), $pronoun) -Color Cyan -BlankBefore -HangingIndent 2
    }
    Write-TpmText -Text 'Next: start the game in TeknoParrotUI and test it and its controls.' -BlankBefore -HangingIndent 6
}

# When nothing is installed: say why, and only call it a problem when something really failed.
function Write-TpmRequiredPatchNothingInstalled {
    param([object[]]$Results, [string]$Choice)
    $items = @($Results)
    if ($Choice -ceq 'A' -and $items.Count -eq 0) {
        Write-TpmText -Text 'None of your registered games has a patch in this list. Nothing was changed.' -Color DarkGray -BlankBefore
        Write-TpmText -Text 'Next: if a game is installed but not registered, choose M and pick its folder.' -BlankBefore -HangingIndent 6
        return
    }
    if (@($items | Where-Object { (Get-TpmRequiredPatchStatusInfo -Status $_.Status).Problem }).Count -gt 0) {
        Write-TpmText -Text 'Nothing was installed. Fix the problem above, then try again.' -Color Yellow -BlankBefore
        return
    }
    Write-TpmText -Text 'Nothing was changed.' -Color DarkGray -BlankBefore
}

# The end-of-step summary of a patch run: how the selected games came out (each game counted once, so the counts add up to the games),
# where the saved copies for undo are, and one line about the Library health check when a game was skipped because its drive is not connected.
function Write-TpmRequiredPatchSummary {
    param([object[]]$Results)
    $items = @($Results)
    if ($items.Count -eq 0) { return }
    $rank = @{ Failed = 4; Changed = 3; AlreadySetUp = 2; Skipped = 1 }
    $kinds = @{}
    $driveGames = @{}
    foreach ($result in $items) {
        $build = Get-TpmRequiredPatchBuildName -Entry $result.Entry
        $driveGone = ([string]$result.Reason -match 'The drive [A-Za-z]: is not connected')
        $kind = 'Skipped'
        if ($result.Status -ceq 'INSTALLED' -or $result.Status -ceq 'UNDONE') { $kind = 'Changed' }
        elseif ($result.Status -ceq 'ALREADY_APPLIED') { $kind = 'AlreadySetUp' }
        elseif ((Get-TpmRequiredPatchStatusInfo -Status $result.Status).Problem -and -not $driveGone) { $kind = 'Failed' }
        if (-not $kinds.ContainsKey($build) -or $rank[$kind] -gt $rank[[string]$kinds[$build]]) { $kinds[$build] = $kind }
        if ($driveGone) { $driveGames[$build] = $true }
    }
    $count = { param([string]$Kind) @($kinds.Keys | Where-Object { $kinds[$_] -eq $Kind }).Count }
    $line = Get-TpmStepCountsLine -Picked $kinds.Count -Changed (& $count 'Changed') -AlreadySetUp (& $count 'AlreadySetUp') -Skipped (& $count 'Skipped') -Failed (& $count 'Failed')
    Write-TpmText -Text $line -BlankBefore -HangingIndent 2
    $backupLine = Get-TpmBackupFolderLine -ExtraPaths @($items | ForEach-Object { [string]$_.Receipt } | Where-Object { $_ }) -What 'the original game files'
    if ($backupLine) { Write-TpmText -Text $backupLine -HangingIndent 2 }
    if (@($kinds.Keys | Where-Object { $driveGames.ContainsKey($_) -and $kinds[$_] -eq 'Skipped' }).Count -gt 0) {
        Write-TpmText -Text ('Next: ' + (Get-TpmDriveSkipNext)) -BlankBefore -HangingIndent 6
    }
}

# The question before anything is written: which games, how many patches, and that a saved copy is kept.
function Write-TpmRequiredPatchPlan {
    param([object[]]$Candidates)
    $games = @(Get-TpmRequiredPatchGameGroups -Entries @($Candidates | ForEach-Object { $_.Entry }))
    $names = Format-TpmNameList -Names @($games | ForEach-Object { $_.Name })
    $patches = Format-TpmCountNoun -Count (@($Candidates).Count) -Singular 'patch'
    Write-TpmText -Text ('Ready to install {0} for {1}: {2}.' -f $patches, (Format-TpmGameCount -Count $games.Count), $names) -Color Cyan -BlankBefore -HangingIndent 2
    foreach ($edit in @($Candidates | Where-Object { Test-TpmRequiredPatchEditOnly -Entry $_.Entry })) {
        $editText = '{0}: TeknoParrot Manager will change one line in a game settings file.' -f (Get-TpmRequiredPatchShortName -BuildName (Get-TpmRequiredPatchBuildName -Entry $edit.Entry))
        if (Test-TpmRequiredPatchOptional -Entry $edit.Entry) { $editText += ' This is optional. Use it only if the game crashes.' }
        Write-TpmText -Text $editText -BlankBefore -HangingIndent 2
    }
    Write-TpmText -Text 'TeknoParrot Manager keeps a saved copy of the original files, so you can undo this later.' -BlankBefore -BlankAfter
}

# Details of the question before installing: one block per game.
function Get-TpmRequiredPatchPlanBlocks {
    param([object[]]$Candidates)
    $blocks = New-Object System.Collections.Generic.List[object]
    foreach ($game in @(Get-TpmRequiredPatchGameGroups -Entries @($Candidates | ForEach-Object { $_.Entry }))) {
        $lines = New-Object System.Collections.Generic.List[string]
        [void]$lines.Add('Patches: ' + $game.Count)
        [void]$lines.Add('Patch ids: ' + ((@($game.Entries | ForEach-Object { [string]$_.Id })) -join ', '))
        if (@($game.Entries | Where-Object { -not (Test-TpmRequiredPatchEditOnly -Entry $_) }).Count -eq 0) {
            [void]$lines.Add('Checked: the settings file has exactly one line that TeknoParrot Manager can change. Nothing else in the file is touched.')
        } else {
            foreach ($zip in @($game.Entries | ForEach-Object { [string]$_.SourceSet } | Where-Object { $_ } | Select-Object -Unique)) { [void]$lines.Add('ZIP file: ' + $zip) }
            foreach ($zip in @($game.Entries | ForEach-Object { @(Get-TpmRequiredPatchSourceChoices -Entry $_ | Select-Object -Skip 1) | ForEach-Object { [string]$_.SourceSet } } | Where-Object { $_ } | Select-Object -Unique)) { [void]$lines.Add('Or this ZIP file: ' + $zip) }
            $queuedIds = @($Candidates | Where-Object { -not $_.Plan } | ForEach-Object { [string]$_.Entry.Id })
            if (@($game.Entries | Where-Object { [string]$_.Id -in $queuedIds }).Count -gt 0) {
                [void]$lines.Add('Checked: the file inside the ZIP matches what the patch expects. A patch that builds on an earlier patch in this list will match the game file only after the earlier patch is installed.')
            } else {
                [void]$lines.Add('Checked: the game file and the file inside the ZIP match what the patch expects.')
            }
        }
        [void]$lines.Add('Saved copy: TeknoParrot Manager keeps a backup and an undo receipt.')
        [void]$blocks.Add(@{ Heading = $game.BuildName; Lines = $lines.ToArray() })
    }
    return $blocks.ToArray()
}

# Temporary files that could not be removed: one plain sentence, then what was left behind (rare, so shown at once).
function Write-TpmRequiredPatchCleanupWarning {
    param([string[]]$Failures)
    foreach ($failure in @($Failures)) { Write-Log ('Required patch cleanup: {0}' -f $failure) }
    Write-TpmText -Text 'TeknoParrot Manager could not remove some temporary files. Your game files are not affected.' -Color Yellow -BlankBefore
    Show-TpmDetailBlocks -Blocks @(@{ Heading = 'Temporary files that were not removed'; Lines = @($Failures | ForEach-Object { 'Left behind: ' + $_ }) })
}

# Owner rule R6: a patch (install or undo) is never written into a game folder inside the source collection (the main or the supplementary
# source folder). Uses the shared guard, so a junction to a source folder cannot hide it; throws, and the caller blocks the game before staging.
function Assert-TpmPatchGameOutsideSourceFolders {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$GameRoot, [string[]]$SourceFolders = @())
    $holdingRoot = Find-TpmProtectedSourceRoot -Path $GameRoot -ProtectedRoots $SourceFolders
    if (-not $holdingRoot) { return }
    Write-Log ('Required patch: refused game folder {0}; it is inside the source folder {1}.' -f $GameRoot, $holdingRoot)
    throw 'The game folder is inside your source folder (where your game collection is kept). TeknoParrot Manager never changes your source folder. Move the game out of it, or fix the game folder in its profile.'
}

function Invoke-TpmRequiredPatchMenu {
    param(
        [Parameter(Mandatory)][string]$TpRoot,
        [Parameter(Mandatory)][string]$UserProfilesDir,
        [Parameter(Mandatory)][string]$ManagerRoot,
        [Parameter(Mandatory)][string]$ProgramRoot,
        [string]$MainSource = '',
        [string]$SupplementarySource = ''
    )
    $sourceFolders = @($MainSource, $SupplementarySource)
    $assertGameClosed = {
        param([Parameter(Mandatory)][string]$GamePath)
        $name=[WildcardPattern]::Escape([IO.Path]::GetFileNameWithoutExtension($GamePath))
        if(@(Get-Process -Name $name -ErrorAction SilentlyContinue).Count -gt 0){throw 'Close the game before applying or undoing its patch.'}
    }.GetNewClosure()
    $detailsNote = 'Installing a file patch does not by itself prove the game is ready or playable. Test each game in TeknoParrotUI.'
    $noPatchToUndo = 'This exact game has no verified applied patch state to undo.'
    try { $catalog = Read-TpmRequiredPatchCatalog -ProgramRoot $ProgramRoot }
    catch {
        $catalogFailure = $_.Exception.Message
        Write-Log ('Required patch recipes are unavailable: {0}' -f $catalogFailure)
        Write-TpmText -Text 'The patch list could not be read, so nothing was changed.' -Color Red -BlankBefore
        Wait-TpmRequiredPatchReturn -DetailBlocks @(@{ Heading = 'Patch list'; Lines = @('Reason: ' + $catalogFailure) })
        return
    }
    Write-TpmText -Text 'Required game patches' -Color Cyan -BlankBefore -BlankAfter
    Write-TpmText -Text 'A) Install patches for my registered games' -HangingIndent 3
    Write-TpmText -Text 'M) Install patches for one game I pick' -HangingIndent 3
    Write-TpmText -Text 'U) Undo patches that TeknoParrot Manager installed' -HangingIndent 3
    Write-TpmText -Text 'Q) Go back' -HangingIndent 3 -BlankAfter
    $choice = ([string](Read-HostSafe '  Choose A, M, U, or Q')).Trim().ToUpperInvariant()
    if ($choice -eq 'Q' -or -not $choice) { return }
    if ($choice -notin @('A','M','U')) {
        Write-TpmText -Text 'That is not a choice. Nothing was changed.' -Color Yellow -BlankBefore
        Wait-TpmRequiredPatchReturn
        return
    }
    $action = if ($choice -eq 'U') { 'Undo' } else { 'Install' }
    # Undo lists only the games that have a saved undo copy, so nobody scrolls past games with nothing to undo.
    $undoEntries = @()
    if ($choice -eq 'U') {
        $undoRoot = if ($script:TpmOwnedLayout) { Join-Path $script:TpmOwnedLayout.Backups 'GamePatches' } else { Join-Path $ManagerRoot 'UpdateBackups\GamePatches' }
        try { $undoIds = @(Get-TpmUndoablePatchIds -RecoveryRoot $undoRoot) }
        catch {
            Write-Log ('Required patch undo: the saved undo copies could not be read: {0}' -f $_.Exception.Message)
            Write-TpmText -Text 'The saved undo copies could not be read, so nothing was changed.' -Color Red -BlankBefore
            Wait-TpmRequiredPatchReturn -DetailBlocks @(@{ Heading = 'Saved undo copies'; Lines = @('Reason: ' + $_.Exception.Message) })
            return
        }
        $undoEntries = @($catalog.Entries | Where-Object { $undoIds -ccontains [string]$_.Id })
        if ($undoEntries.Count -eq 0) {
            Write-Log 'Required patch undo: no saved undo copy was found, so there is nothing to undo.'
            Write-TpmText -Text 'There is nothing to undo. TeknoParrot Manager has not installed any patches that can be undone.' -Color DarkGray -BlankBefore
            Wait-TpmRequiredPatchReturn
            return
        }
    }
    $hardwareEvidence = $null
    $hasHardwarePredicates = @($catalog.Entries | Where-Object { $_.PSObject.Properties['HardwarePredicate'] -and $null -ne $_.HardwarePredicate }).Count -gt 0
    if ($choice -ne 'U' -and $hasHardwarePredicates) {
        $hardwareEvidence = Get-TpmHardwareEnvironmentEvidence
    }
    $stages = New-Object System.Collections.Generic.List[string]
    $detailBlocks = New-Object System.Collections.Generic.List[object]
    $sourceRoots = @{}
    try {
        $selectedEntries = @(if ($choice -eq 'U') { $undoEntries } else { $catalog.Entries })
        $reported = New-Object System.Collections.Generic.List[object]
        $residueOwners = @{}
        $gameRoot = ''
        $group = $null
        if ($choice -eq 'M' -or $choice -eq 'U') {
            $group = Read-TpmRequiredPatchGameChoice -Groups @(Get-TpmRequiredPatchGameGroups -Entries $selectedEntries)
            if ($null -eq $group) { return }
            $selectedEntries = @($group.Entries)
            $gameRoot = Read-TpmRequiredPatchGameFolder -Choice $choice -Group $group -InitialDirectory $gamesInstallFolder
            if ([string]::IsNullOrWhiteSpace($gameRoot)) {
                Add-TpmRequiredPatchResult -Results $reported -Entry $selectedEntries[0] -Status 'CANCELLED' -Reason 'No game folder was selected.'
                $selectedEntries = @()
            }
        }
        # Two real video cards of different makes: ask once, and only when a patch in this run depends on the card.
        if ($choice -ne 'U' -and $hardwareEvidence -and @($selectedEntries | Where-Object { $_.PSObject.Properties['HardwarePredicate'] -and $null -ne $_.HardwarePredicate -and ($choice -ne 'A' -or (Test-Path -LiteralPath (Join-Path $UserProfilesDir ($_.ProfileId + '.xml')) -PathType Leaf -ErrorAction SilentlyContinue)) }).Count -gt 0) {
            $hardwareEvidence = Resolve-TpmPatchHardwareEvidence -Evidence $hardwareEvidence
        }
        $candidates = New-Object System.Collections.Generic.List[object]
        $waiting = New-Object System.Collections.Generic.List[object]
        $optionalSkipped = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $selectedEntries) {
            $profilePath = Join-Path $UserProfilesDir ($entry.ProfileId + '.xml')
            if ($choice -eq 'A' -and -not (Test-Path -LiteralPath $profilePath -PathType Leaf -ErrorAction SilentlyContinue)) { continue }
            if ($choice -eq 'A' -and (Test-TpmRequiredPatchOptional -Entry $entry)) { [void]$optionalSkipped.Add($entry); continue }
            if ($choice -ne 'U') {
                # The graphics card question comes first, so a patch made for another card never asks for its ZIP file.
                $variant = Resolve-TpmPatchVariantDecision -Entries @($catalog.Entries) -PatchId $entry.Id -ProfileId $entry.ProfileId -HardwareEvidence $hardwareEvidence
                if ($variant.Status -ceq 'SELECTED' -and $variant.SelectedId -cne $entry.Id) {
                    $variant = [pscustomobject]@{ Status = 'NOT_APPLICABLE'; Reason = ('A different exclusive hardware variant applies: {0}' -f $variant.SelectedId) }
                }
                if ($variant.Status -cne 'SELECTED') {
                    Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status $(if ($variant.Status -ceq 'NOT_APPLICABLE') { 'OTHER_VARIANT' } else { 'BLOCKED' }) -Reason $variant.Reason
                    continue
                }
            }
            if ($choice -eq 'M') {
                try {
                    Assert-TpmPatchGameOutsideSourceFolders -GameRoot $gameRoot -SourceFolders $sourceFolders
                    $context = Get-TpmManualPatchContext -Entry $entry -TpRoot $TpRoot -UserProfilesDir $UserProfilesDir -ManagerRoot $ManagerRoot -GameRoot $gameRoot
                    if (-not (Test-TpmRequiredPatchBuild -Entry $entry -GamePath $context.GamePath -Entries @($catalog.Entries) -Results $reported)) { continue }
                    if (Test-TpmRequiredPatchEditOnly -Entry $entry) { $sourceRoot = ''; $stageInfo = New-TpmRequiredPatchEditStage }
                    else {
                        $sourceRoot = Get-TpmRequiredPatchSourceRootOnce -Cache $sourceRoots -Entry $entry -MainSource $MainSource -SupplementarySource $SupplementarySource
                        $stageInfo = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $sourceRoot
                    }
                    [void]$stages.Add($stageInfo.Root)
                    $context = Get-TpmManualPatchContext -Entry $entry -TpRoot $TpRoot -UserProfilesDir $UserProfilesDir -ManagerRoot $ManagerRoot -GameRoot $gameRoot -SourceRoots @($sourceRoot)
                } catch {
                    Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'BLOCKED' -Reason $_.Exception.Message
                    continue
                }
            } else {
                try {
                    if ($choice -eq 'A') {
                        $context = Get-TpmRegisteredPatchContext -Entry $entry -TpRoot $TpRoot -UserProfilesDir $UserProfilesDir -ManagerRoot $ManagerRoot
                        Assert-TpmPatchGameOutsideSourceFolders -GameRoot $context.GameRoot -SourceFolders $sourceFolders
                        if (-not (Test-TpmRequiredPatchBuild -Entry $entry -GamePath $context.GamePath -Entries @($catalog.Entries) -Results $reported)) { continue }
                        if (Test-TpmRequiredPatchEditOnly -Entry $entry) { $sourceRoot = ''; $stageInfo = New-TpmRequiredPatchEditStage }
                        else {
                            $sourceRoot = Get-TpmRequiredPatchSourceRootOnce -Cache $sourceRoots -Entry $entry -MainSource $MainSource -SupplementarySource $SupplementarySource
                            $stageInfo = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $sourceRoot
                        }
                        [void]$stages.Add($stageInfo.Root)
                        if ($sourceRoot) { $context.ProtectedRoots = @($context.ProtectedRoots) + @($sourceRoot) }
                    } else {
                        $context = Get-TpmManualPatchContext -Entry $entry -TpRoot $TpRoot -UserProfilesDir $UserProfilesDir -ManagerRoot $ManagerRoot -GameRoot $gameRoot -ForUndo
                        Assert-TpmPatchGameOutsideSourceFolders -GameRoot $gameRoot -SourceFolders $sourceFolders
                    }
                } catch {
                    Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'BLOCKED' -Reason $_.Exception.Message
                    continue
                }
                if ($choice -eq 'U') {
                    try {
                        $emptyStage = Join-Path $script:TpmOwnedLayout.Temp ('RequiredPatchUndo-' + [guid]::NewGuid().ToString('N'))
                        [void][IO.Directory]::CreateDirectory($emptyStage)
                        [void]$stages.Add($emptyStage)
                        try {
                            # A settings edit is rebuilt from its saved copy, so the probe is given each saved copy folder in turn.
                            $probeDirectories = if (Test-TpmRequiredPatchEditOnly -Entry $entry) { @(Get-TpmPatchRecoveryDirectories -Request ([pscustomobject]@{Context=$context}) -PatchId $entry.Id) } else { @() }
                            if ($probeDirectories.Count -eq 0) { $probeDirectories = @('') }
                            foreach ($probeDirectory in $probeDirectories) {
                                $plan = Get-TpmPatchPlan -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $entry.Id -ProfileId $entry.ProfileId -GameRoot $context.GameRoot -PayloadRoot $emptyStage -RecoveryRoot $context.RecoveryRoot -ProtectedRoots $context.ProtectedRoots -ForUndo -ReceiptDirectory $probeDirectory
                                if ($plan.Status -ne 'Unavailable') { break }
                            }
                            if ($plan.Status -eq 'Unavailable') { throw $plan.Reason }
                        } catch {
                            $receiptDirectories = @(Get-TpmPatchRecoveryDirectories -Request ([pscustomobject]@{Context=$context}) -PatchId $entry.Id)
                            # The other variant of an exclusive pair was never installed here: nothing to undo, not a conflict.
                            if ($entry.PSObject.Properties['ExclusiveGroup'] -and $entry.ExclusiveGroup -and $receiptDirectories.Count -eq 0 -and [string]$_.Exception.Message -cin @('Grouped target conflict.', 'An exclusive recipe is active; undo it before selecting another variant.')) {
                                Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'NOTHING_TO_UNDO' -Reason 'This variant was not installed here.'
                                continue
                            }
                            throw (Resolve-TpmOlderListReason -Message ([string]$_.Exception.Message) -Operations @($entry.Operations) -RecoveryDirectory $receiptDirectories)
                        }
                        if ($plan.Status -ne 'AlreadyApplied') {
                            Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'NOTHING_TO_UNDO' -Reason $noPatchToUndo
                            continue
                        }
                        $request = [pscustomobject]@{Context=$context}
                        $recoveryDirectories = @(Get-TpmPatchRecoveryDirectories -Request $request -PatchId $entry.Id)
                        $validReceipts = New-Object System.Collections.Generic.List[string]
                        $actionRequired = New-Object System.Collections.Generic.List[string]
                        $olderListCopy = ''
                        foreach ($directory in $recoveryDirectories) {
                            try {
                                [void](Read-TpmUndoReceipt -Plan $plan -PatchId $entry.Id -ProfileId $entry.ProfileId -CatalogSha256 $catalog.CatalogSha256 -RecoveryDirectory $directory)
                                [void]$validReceipts.Add($directory)
                            } catch {
                                if ([string]$_.Exception.Message -clike 'ACTION REQUIRED:*') { [void]$actionRequired.Add([string]$_.Exception.Message) }
                                elseif ([string]$_.Exception.Message -clike 'This saved copy was made by an older patch list*') { $olderListCopy = [string]$_.Exception.Message }
                            }
                        }
                        foreach ($residuePath in @(Get-TpmPatchReceiptResidue -RecoveryRoot $context.RecoveryRoot)) {
                            if (-not $residueOwners.ContainsKey($residuePath)) { $residueOwners[$residuePath] = New-Object System.Collections.Generic.List[string] }
                            if (@($recoveryDirectories) -contains [IO.Path]::GetDirectoryName($residuePath)) { [void]$residueOwners[$residuePath].Add([string]$group.Name) }
                        }
                        # An unreconciled interrupted transaction blocks undo; all of its evidence is kept.
                        if ($actionRequired.Count) {
                            Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'ACTION REQUIRED' -Reason ($actionRequired -join ' ')
                            continue
                        }
                        if ($recoveryDirectories.Count -eq 0) {
                            Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'NOTHING_TO_UNDO' -Reason $noPatchToUndo
                            continue
                        }
                        if ($validReceipts.Count -eq 0 -and $olderListCopy) { throw $olderListCopy }
                        if ($validReceipts.Count -ne 1) { throw 'Exactly one verified undo receipt is required; ambiguous or missing receipts block undo.' }
                        $partText = if ($selectedEntries.Count -gt 1) { ' (patch {0} of {1})' -f ([array]::IndexOf($selectedEntries, $entry) + 1), $selectedEntries.Count } else { '' }
                        $undoConfirm = ([string](Read-HostSafe ('  Undo the patch for {0}{1}? Press Y to undo, or Enter to cancel' -f $group.Name, $partText))).Trim().ToUpperInvariant()
                        if ($undoConfirm -cne 'Y') {
                            Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'CANCELLED' -Reason 'Undo was not confirmed; no game files were changed.'
                            continue
                        }
                        & $assertGameClosed $context.GamePath
                        $validation = {
                            param($validationState)
                            & $assertGameClosed $context.GamePath
                            $expectedExecutable = [string]$entry.ExecutableSha256
                            if ($plan.PSObject.Properties['ExecutableSelfPatch'] -and $plan.ExecutableSelfPatch) {
                                $expectedExecutable = if ($validationState -ceq 'published') { [string]$entry.Operations[0].BeforeSha256 } else { [string]$entry.Operations[0].AfterSha256 }
                            }
                            if ($expectedExecutable -or -not (Test-TpmRequiredPatchEditOnly -Entry $entry)) { if ((Get-FileHash -LiteralPath $context.GamePath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $expectedExecutable) { throw 'The exact game executable changed before undo.' } }
                            elseif (-not (Test-Path -LiteralPath $context.GamePath -PathType Leaf)) { throw 'The game program was not found in this folder.' }
                        }
                        $result = Undo-TpmCatalogPatch -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $entry.Id -ProfileId $entry.ProfileId -GameRoot $context.GameRoot -PayloadRoot $emptyStage -RecoveryRoot $context.RecoveryRoot -ProtectedRoots $context.ProtectedRoots -RecoveryDirectory $validReceipts[0] -ValidationAction $validation -Confirm:$false
                        Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'UNDONE' -Reason (('Undo result: {0}. The receipt and current target state were verified. {1}' -f $result.Status,$(if($result.PSObject.Properties['LeftoverNote']){[string]$result.LeftoverNote})).Trim())
                    } catch {
                        Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'BLOCKED' -Reason $_.Exception.Message
                    }
                    continue
                }
            }
            try {
                $plan = Get-TpmPatchPlan -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $entry.Id -ProfileId $entry.ProfileId -GameRoot $context.GameRoot -PayloadRoot $stageInfo.Root -RecoveryRoot $context.RecoveryRoot -ProtectedRoots $context.ProtectedRoots -HardwareEvidence $hardwareEvidence
                if ($plan.Status -eq 'Unavailable') {
                    if ($plan.Reason -ceq 'Grouped target conflict.') {
                        [void]$waiting.Add([pscustomobject]@{Entry=$entry;Context=$context;Stage=$stageInfo;SourceRoot=$sourceRoot;Reason=$plan.Reason})
                        continue
                    }
                    throw $plan.Reason
                }
                if ($plan.Status -eq 'AlreadyApplied') {
                    Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'ALREADY_APPLIED' -Reason 'The exact pinned target bytes are already present; no write was made.'
                    continue
                }
                $prerequisites = Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $context.GameRoot
                if (-not $prerequisites.Satisfied) {
                    Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'BLOCKED' -Reason ($prerequisites.Guidance -join ' ')
                    continue
                }
                [void]$candidates.Add([pscustomobject]@{Entry=$entry;Context=$context;Stage=$stageInfo;SourceRoot=$sourceRoot;Plan=$plan;Prerequisites=$prerequisites})
            } catch {
                Add-TpmRequiredPatchResult -Results $reported -Entry $entry -Status 'BLOCKED' -Reason $_.Exception.Message
            }
        }
        # A patch that lays a file on top of one that another patch in this same run creates could not be planned yet. It is added behind the patch that creates the file.
        foreach ($later in $waiting) {
            $builtOnQueued = $false
            foreach ($queued in @($candidates | Where-Object { $_.Context.GameRoot -ieq $later.Context.GameRoot })) {
                foreach ($made in @($queued.Entry.Operations)) {
                    if (@($later.Entry.Operations | Where-Object { $_.Type -ceq 'ReplaceFile' -and $_.Target -ceq $made.Target -and $_.BeforeSha256 -ieq $made.AfterSha256 }).Count) { $builtOnQueued = $true }
                }
            }
            if (-not $builtOnQueued) {
                Add-TpmRequiredPatchResult -Results $reported -Entry $later.Entry -Status 'BLOCKED' -Reason $later.Reason
                continue
            }
            $prerequisites = Test-TpmRequiredPatchPrerequisites -Entry $later.Entry -GameRoot $later.Context.GameRoot
            if (-not $prerequisites.Satisfied) {
                Add-TpmRequiredPatchResult -Results $reported -Entry $later.Entry -Status 'BLOCKED' -Reason ($prerequisites.Guidance -join ' ')
                continue
            }
            [void]$candidates.Add([pscustomobject]@{Entry=$later.Entry;Context=$later.Context;Stage=$later.Stage;SourceRoot=$later.SourceRoot;Plan=$null;Prerequisites=$prerequisites})
        }
        if ($optionalSkipped.Count -gt 0) {
            Write-TpmText -Text ('Optional, not installed: {0}. Use it only if the game crashes. To use it, choose M and pick the game.' -f (Format-TpmNameList -Names @(Get-TpmRequiredPatchGameGroups -Entries $optionalSkipped.ToArray() | ForEach-Object { $_.Name }))) -Color DarkGray -BlankBefore -HangingIndent 2
        }
        $detailBlocks.AddRange([object[]]@(Show-TpmRequiredPatchResults -Results $reported.ToArray() -Action $action))
        $detailBlocks.AddRange([object[]]@(Write-TpmRequiredPatchResidueNote -Owners $residueOwners))
        if ($choice -eq 'U') { Write-TpmRequiredPatchSummary -Results $reported.ToArray(); Wait-TpmRequiredPatchReturn -DetailBlocks $detailBlocks.ToArray() -DetailsNote $detailsNote;return }
        if ($candidates.Count -eq 0) {
            Write-TpmRequiredPatchNothingInstalled -Results $reported.ToArray() -Choice $choice
            Write-TpmRequiredPatchSummary -Results $reported.ToArray()
            Wait-TpmRequiredPatchReturn -DetailBlocks $detailBlocks.ToArray() -DetailsNote $detailsNote
            return
        }
        Write-TpmRequiredPatchPlan -Candidates $candidates.ToArray()
        $detailBlocks.AddRange([object[]]@(Get-TpmRequiredPatchPlanBlocks -Candidates $candidates.ToArray()))
        $confirm = Read-TpmAnswerWithDetails -Prompt '  Press Y to install, D for details, or Enter to cancel' -DetailBlocks $detailBlocks.ToArray() -DetailsNote $detailsNote
        if ($confirm -cne 'Y') {
            Write-TpmText -Text 'Canceled. Nothing was changed.' -Color DarkGray
            return
        }
        $applied = New-Object System.Collections.Generic.List[object]
        foreach ($candidate in $candidates) {
            try {
                & $assertGameClosed $candidate.Context.GamePath
                $validation = {
                    param($validationState)
                    & $assertGameClosed $candidate.Context.GamePath
                    $expectedExecutable = [string]$candidate.Entry.ExecutableSha256
                    if ($candidate.Plan -and $candidate.Plan.PSObject.Properties['ExecutableSelfPatch'] -and $candidate.Plan.ExecutableSelfPatch) {
                        $expectedExecutable = if ($validationState -ceq 'published') { [string]$candidate.Entry.Operations[0].AfterSha256 } else { [string]$candidate.Entry.Operations[0].BeforeSha256 }
                    }
                    if ($expectedExecutable -or -not (Test-TpmRequiredPatchEditOnly -Entry $candidate.Entry)) {
                        if ((Get-FileHash -LiteralPath $candidate.Context.GamePath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $expectedExecutable) { throw 'The exact game executable changed before publication.' }
                    } elseif (-not (Test-Path -LiteralPath $candidate.Context.GamePath -PathType Leaf)) { throw 'The game program was not found in this folder.' }
                    $check = Test-TpmRequiredPatchPrerequisites -Entry $candidate.Entry -GameRoot $candidate.Context.GameRoot
                    if (-not $check.Satisfied) { throw ($check.Guidance -join ' ') }
                    if ($candidate.Stage.Payload -and (Get-FileHash -LiteralPath $candidate.Stage.Payload -Algorithm SHA256 -ErrorAction Stop).Hash -ine $candidate.Entry.SourceSha256) {
                        throw 'The staged local payload changed before publication.'
                    }
                    if ($candidate.Context.Registered -and
                        (Get-FileHash -LiteralPath $candidate.Context.ProfilePath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $candidate.Context.ProfileSha256) {
                        throw 'The registered TeknoParrot profile changed before publication.'
                    }
                }
                $result = Invoke-TpmCatalogPatch -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $candidate.Entry.Id -ProfileId $candidate.Entry.ProfileId -GameRoot $candidate.Context.GameRoot -PayloadRoot $candidate.Stage.Root -RecoveryRoot $candidate.Context.RecoveryRoot -ProtectedRoots $candidate.Context.ProtectedRoots -HardwareEvidence $hardwareEvidence -ValidationAction $validation -Confirm:$false
                if ($result.Status -eq 'Applied') {
                    Add-TpmRequiredPatchResult -Results $applied -Entry $candidate.Entry -Status 'INSTALLED' -Reason (('Installed. The result was read back and checked. {0}' -f $(if($result.PSObject.Properties['LeftoverNote']){[string]$result.LeftoverNote})).Trim()) -Receipt ([string]$result.RecoveryDirectory) -Registered ([bool]$candidate.Context.Registered)
                } else {
                    Add-TpmRequiredPatchResult -Results $applied -Entry $candidate.Entry -Status 'SKIPPED' -Reason ('Result: {0}' -f $result.Status)
                }
            } catch {
                Add-TpmRequiredPatchResult -Results $applied -Entry $candidate.Entry -Status 'FAILED' -Reason $_.Exception.Message
            }
        }
        $detailBlocks.AddRange([object[]]@(Show-TpmRequiredPatchResults -Results $applied.ToArray() -Action 'Install'))
        Write-TpmRequiredPatchNextSteps -Results $applied.ToArray()
        Write-TpmRequiredPatchSummary -Results (@($reported.ToArray()) + @($applied.ToArray()))
        Wait-TpmRequiredPatchReturn -DetailBlocks $detailBlocks.ToArray() -DetailsNote $detailsNote
    } finally {
        $cleanupFailures=New-Object System.Collections.Generic.List[string]
        foreach ($stage in @($stages.ToArray())) {
            if ((Test-PathInside $stage $script:TpmOwnedLayout.Temp) -and (Test-Path -LiteralPath $stage)) {
                try {
                    if(-not (Test-TpmNoReparsePath $stage)){throw 'The staging path is unsafe; it was preserved.'}
                    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Stop
                    if(Test-Path -LiteralPath $stage){throw 'The staged directory remains after cleanup.'}
                } catch {
                    [void]$cleanupFailures.Add(($stage+' -- '+$_.Exception.Message))
                }
            }
        }
        if($cleanupFailures.Count){
            Write-TpmRequiredPatchCleanupWarning -Failures $cleanupFailures.ToArray()
        }
    }
}