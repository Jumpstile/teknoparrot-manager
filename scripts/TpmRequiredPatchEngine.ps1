$script:TpmRequiredPatchCatalogSha256 = '87DF31451B267F89FCD2CB3E3DEA1860972EDD4C7601ACE1998E80BD7E4CAD9E'

function Get-TpmRegisteredPatchContext {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$TpRoot,[Parameter(Mandatory)][string]$UserProfilesDir,[Parameter(Mandatory)][string]$ManagerRoot)
    foreach($root in @($TpRoot,$UserProfilesDir,$ManagerRoot)) { if (-not [IO.Path]::IsPathRooted($root) -or -not (Test-TpmNoReparsePath $root)) { throw 'Unsafe TPM or registration root.' } }
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
        if (-not (Test-PathInside $layout.Backups $layout.Root) -or -not (Test-TpmNoReparsePath $layout.Backups)) { throw 'The TPM backup layout is unsafe.' }
        $recovery=Join-Path $layout.Backups 'GamePatches'
    }
    if ($script:TpmOwnedLayout -and (Test-TpmPathOverlap $gameRoot $script:TpmOwnedLayout.Root)) { throw 'The registered game folder overlaps TPM-owned state.' }
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
            -not [IO.File]::Exists($target) -or (Get-Item -LiteralPath $target -ErrorAction Stop).Length -gt 262144 -or
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
            -not [IO.File]::Exists($target) -or (Get-Item -LiteralPath $target -ErrorAction Stop).Length -gt 262144){throw 'Receipt history target is missing, oversized, or outside the backup root.'}
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
        $result.Reason=$_.Exception.Message
        return $result
    } finally {
        foreach($boundary in $locks){foreach($handle in $boundary){$handle.Dispose()}}
    }
}

function Get-TpmPatchRecoveryDirectories {
    param([Parameter(Mandatory)]$Request,[Parameter(Mandatory)]$Package,[Parameter(Mandatory)][string]$PatchId)
    $root=$Request.Context.RecoveryRoot
    if (-not (Test-TpmNoReparsePath $root)) { throw 'Unsafe patch backup folder.' }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
    foreach($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop)) {
        if ($directory.Name -notmatch '^[a-f0-9]{32}$' -or -not (Test-TpmNoReparsePath $directory.FullName)) { continue }
        $receiptPath=Join-Path $directory.FullName 'receipt.json'
        if (-not (Test-TpmNoReparsePath $receiptPath) -or -not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { continue }
        try {
            if ((Get-Item -LiteralPath $receiptPath).Length -gt 16384) { continue }
            $receipt=[IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json -ErrorAction Stop
            if ($receipt.PatchId -ceq $PatchId -and $receipt.ProfileId -ceq $Request.Context.ProfileId -and $receipt.CatalogSha256 -ieq $Package.CatalogSha256 -and $receipt.GameRoot -ieq $Request.Context.GameRoot) { $directory.FullName }
        } catch { continue }
    }
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

function Resolve-TpmPatchPath {
    param([string]$Root, [string]$Relative)
    if ([string]::IsNullOrWhiteSpace($Relative) -or $Relative -match '[:\\/]{2}|:' -or [IO.Path]::IsPathRooted($Relative)) { throw 'Invalid relative patch path.' }
    foreach ($part in ($Relative -split '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($part) -or $part -match '[<>:"|?*\p{Cc}]' -or $part -match '[. ]$|^(CON|PRN|AUX|NUL|CLOCK\$|CONIN\$|CONOUT\$|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])(\.|$)' -or $part -in @('.', '..')) { throw 'Unsafe patch path component.' }
    }
    $path = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
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
    $variants = if ($group) {
        @($Entries | Where-Object {
            $_.ProfileId -ceq $ProfileId -and $_.PSObject.Properties['ExclusiveGroup'] -and
            $_.ExclusiveGroup -ceq $group -and $_.ExecutableSha256 -ieq $entry.ExecutableSha256
        })
    } else { @($entry) }
    $conditional = @($variants | Where-Object { $_.PSObject.Properties['HardwarePredicate'] -and $null -ne $_.HardwarePredicate })
    if ($conditional.Count -eq 0) {
        if ($variants.Count -gt 1) {
            return [pscustomobject]@{ Status='AMBIGUOUS'; SelectedId=''; Reason='More than one mutually exclusive recipe matches this exact build and no hardware predicate distinguishes them.' }
        }
        return [pscustomobject]@{ Status='SELECTED'; SelectedId=[string]$entry.Id; Reason='' }
    }
    $gpu = $null
    if ($conditional.Count -gt 0) {
        $gpu = Get-TpmPatchHardwareVendor -Evidence $HardwareEvidence
        if ($gpu.State -ne 'KNOWN') {
            return [pscustomobject]@{ Status=$gpu.State; SelectedId=''; Reason=$gpu.Reason }
        }
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
        [Parameter(Mandatory,ParameterSetName="File")][string]$CatalogPath, [Parameter(Mandatory,ParameterSetName="Content")][string]$CatalogContent,
        [Parameter(Mandatory)][string]$CatalogSha256,
        [Parameter(Mandatory)][string]$PatchId,
        [Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot,
        [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$RecoveryRoot,
        [Parameter(Mandatory)][string[]]$ProtectedRoots,
        [AllowNull()][object]$HardwareEvidence = $null,
        [switch]$ForUndo
    )
    try {
        foreach ($root in @($GameRoot, $PayloadRoot, $RecoveryRoot)) {
            if (-not [IO.Path]::IsPathRooted($root) -or -not (Test-TpmNoReparsePath $root)) { throw 'Invalid or reparse root.' }
        }
        $game = [IO.Path]::GetFullPath($GameRoot)
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
        if ($PSCmdlet.ParameterSetName -eq 'Content') {
            if ((Get-TpmPatchTextSha256 $CatalogContent) -ine $CatalogSha256) { throw 'Catalog content hash mismatch.' }
            $catalog = $CatalogContent | ConvertFrom-Json -ErrorAction Stop
        } else {
            if (-not (Test-TpmNoReparsePath $CatalogPath)) { throw 'Invalid catalog path.' }
            if ((Get-FileHash -LiteralPath $CatalogPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $CatalogSha256) { throw 'Catalog hash mismatch.' }
            $catalog = [IO.File]::ReadAllText($CatalogPath) | ConvertFrom-Json -ErrorAction Stop
            if ((Get-FileHash -LiteralPath $CatalogPath -Algorithm SHA256 -ErrorAction Stop).Hash -ne $CatalogSha256) { throw 'Catalog changed during read.' }
        }
        Assert-TpmPatchFields $catalog @('Schema', 'Entries')
        if (($catalog.Schema -isnot [int] -and $catalog.Schema -isnot [long]) -or $catalog.Schema -notin @(1,2,3) -or $catalog.Entries -isnot [array] -or @($catalog.Entries).Count -eq 0) { throw 'Unsupported catalog schema.' }
        $ids = @{}
        foreach ($entry in @($catalog.Entries)) {
            $fields = @('Id','ProfileId','Executable','ExecutableSha256','SourceUrl','SourceRevision','Operations')
            if ($catalog.Schema -eq 3) {
                $fields += @('ExclusiveGroup')
                $optional = @('BuildName','SourceRole','SourceSet','SourceEntry','SourceSize','SourceSha1','SourceSha256','Prerequisites','HardwarePredicate','AllowExecutableSelfPatch')
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
            } else {
                Assert-TpmPatchFields $entry $fields
            }
            foreach ($field in @('Id', 'ProfileId', 'Executable', 'ExecutableSha256', 'SourceUrl', 'SourceRevision')) { if ($entry.PSObject.Properties[$field].Value -isnot [string]) { throw 'Invalid catalog string field.' } }
            if ($entry.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$' -or $ids.ContainsKey([string]$entry.Id)) { throw 'Duplicate/invalid patch identity.' }
            $ids[[string]$entry.Id] = $true
        }
        $matchingEntries = @($catalog.Entries | Where-Object { $_.Id -ceq $PatchId })
        if ($matchingEntries.Count -ne 1) { throw 'Unknown/ambiguous patch.' }
        $entry = $matchingEntries[0]
        if ($entry.ProfileId -cne $ProfileId -or [string]::IsNullOrWhiteSpace($ProfileId)) { throw 'Profile mismatch.' }
        if ($catalog.Schema -eq 3 -and -not $ForUndo) {
            $variantDecision = Resolve-TpmPatchVariantDecision -Entries @($catalog.Entries) -PatchId $PatchId -ProfileId $ProfileId -HardwareEvidence $HardwareEvidence
            if ($variantDecision.Status -cne 'SELECTED') { throw $variantDecision.Reason }
            if ($variantDecision.SelectedId -cne $PatchId) { throw ("A different exclusive hardware variant applies: {0}" -f $variantDecision.SelectedId) }
        }
        $localSource = $false
        if ($catalog.Schema -eq 3 -and
            [string]::IsNullOrWhiteSpace($entry.SourceUrl) -and [string]::IsNullOrWhiteSpace($entry.SourceRevision)) {
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
        if($catalog.Schema -eq 3){return (Get-TpmMultiPatchPlan -Entry $entry -PatchId $PatchId -ProfileId $ProfileId -GameRoot $game -PayloadRoot $payloadRootPath -RecoveryRoot $recovery -CatalogSha256 $CatalogSha256 -CatalogEntries @($catalog.Entries) -ForUndo:$ForUndo)}
        if ($entry.Operations -isnot [array] -or @($entry.Operations).Count -ne 1) { throw 'First slice supports exactly one replacement.' }
        $operation = @($entry.Operations)[0]
        $create=($catalog.Schema -eq 2 -and $operation.Type -ceq 'CreateFile')
        $preField=if($create){'BeforeState'}else{'BeforeSha256'}
        Assert-TpmPatchFields $operation @('Type', 'Target', $preField, 'AfterSha256', 'Payload', 'PayloadSha256')
        foreach ($field in @('Type', 'Target', $preField, 'AfterSha256', 'Payload', 'PayloadSha256')) { if ($operation.PSObject.Properties[$field].Value -isnot [string]) { throw 'Invalid operation string field.' } }
        if ($operation.Type -cne 'ReplaceFile' -and -not $create) { throw 'Unsupported operation.' }
        if($create -and $operation.BeforeState -cne 'Absent'){throw 'CreateFile requires explicit Absent pre-state.'}
        $contentPins=@($entry.ExecutableSha256,$operation.AfterSha256,$operation.PayloadSha256);if(-not $create){$contentPins+=@($operation.BeforeSha256)}
        foreach ($hash in $contentPins) {
            if ($hash -isnot [string] -or $hash -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Invalid content pin.' }
        }
        if ($operation.AfterSha256 -ine $operation.PayloadSha256 -or $operation.BeforeSha256 -ieq $operation.AfterSha256) { throw 'Conflicting/no-op content pins.' }
        $exe = Resolve-TpmPatchPath $game $entry.Executable
        $target = Resolve-TpmPatchPath $game $operation.Target
        $payload = Resolve-TpmPatchPath $payloadRootPath $operation.Payload
        if ($target -eq $exe -or (Get-FileHash -LiteralPath $exe -Algorithm SHA256 -ErrorAction Stop).Hash -ine $entry.ExecutableSha256) { throw 'Executable revision mismatch or self-patch.' }
        if($create -and -not $ForUndo -and (Get-Item -LiteralPath $payload -ErrorAction Stop).Length -gt 64MB){throw 'CreateFile source exceeds the 64 MiB bound.'}
        if (-not $ForUndo -and (Get-FileHash -LiteralPath $payload -Algorithm SHA256 -ErrorAction Stop).Hash -ine $operation.PayloadSha256) { throw 'Payload hash mismatch.' }
        $result=[pscustomobject]@{Status='Ready';Reason=$null;PatchId=$PatchId;ProfileId=$ProfileId;GameRoot=$game;Target=$target;RelativeTarget=[string]$operation.Target;Payload=$payload;RecoveryRoot=$recovery;BeforeSha256=$(if($create){''}else{$operation.BeforeSha256});AfterSha256=$operation.AfterSha256;SourceUrl=$entry.SourceUrl;SourceRevision=$entry.SourceRevision;Operation=$operation.Type;Executable=$exe;ExecutableSha256=$entry.ExecutableSha256}
        if($create){
            if(-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($target))){throw 'CreateFile requires an existing parent directory.'}
            $state=Get-TpmFileState $target
            if(-not $state.Readable -or $state.IsDirectory){throw 'CreateFile target state is unavailable or not a file.'}
            if($state.Exists){
                if($state.Sha256 -ine $operation.AfterSha256){throw 'Target conflict.'}
                $result.Status='AlreadyApplied'
            }
        }else{
            $current=(Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash
            $result.Status=if($current -eq $operation.AfterSha256){'AlreadyApplied'}elseif($current -eq $operation.BeforeSha256){'Ready'}else{throw 'Target conflict.'}
        }
        return $result
    } catch {
        return [pscustomobject]@{ Status = 'Unavailable'; Reason = $_.Exception.Message }
    }
}

function Get-TpmPatchPlanOperations {
    param([Parameter(Mandatory)]$Plan)
    if($Plan.PSObject.Properties['Operations']){return @($Plan.Operations)}
    return @($Plan)
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
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$RootReceipt,[Parameter(Mandatory)][string]$RootDirectory,[Parameter(Mandatory)][string]$CatalogSha256)
    if($Plan.Operations.Count -ne 1){return $false}
$planTargets=@($Plan.Operations|ForEach-Object {$_.RelativeTarget});$rootOps=@($RootReceipt.Operations|Where-Object { $_.Target -is [string] -and $_.Target -in $planTargets })
    if($rootOps.Count -ne 1 -or $RootReceipt.Operations.Count -ne 1 -or $RootReceipt.State -cne 'Applied'){return $false}
    $targetRelative=$rootOps[0].Target
    $rootEntry=@($Plan.CatalogEntries|Where-Object {$_.Id -ceq $RootReceipt.PatchId -and $_.ProfileId -ceq $RootReceipt.ProfileId})
    if($rootEntry.Count -ne 1 -or $rootEntry[0].Operations.Count -ne 1 -or $RootReceipt.ProfileId -cne $Plan.ProfileId -or $RootReceipt.GameRoot -ine $Plan.GameRoot -or $RootReceipt.CatalogSha256 -ine $CatalogSha256){return $false}
    $rootPlan=Get-TpmMultiPatchPlan -Entry $rootEntry[0] -PatchId $RootReceipt.PatchId -ProfileId $RootReceipt.ProfileId -GameRoot $Plan.GameRoot -PayloadRoot $Plan.PayloadRoot -RecoveryRoot $Plan.RecoveryRoot -CatalogSha256 $CatalogSha256 -CatalogEntries $Plan.CatalogEntries -ForUndo -Probe -ReceiptChainTarget $targetRelative
    [void](Assert-TpmMultiPatchReceipt -Plan $rootPlan -Receipt $RootReceipt -CatalogSha256 $CatalogSha256 -Directory $RootDirectory -ReceiptChainTarget $targetRelative)
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
        $raw=Read-TpmMultiPatchReceiptBytes -Path $path -MaximumBytes 262144
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
            if($candidate.Schema -ne 3 -or $candidate.ProfileId -cne $RootReceipt.ProfileId -or $candidate.GameRoot -ine $RootReceipt.GameRoot -or $candidate.CatalogSha256 -ine $CatalogSha256){continue}
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
        $candidatePlan=Get-TpmMultiPatchPlan -Entry $entry[0] -PatchId $candidate.PatchId -ProfileId $candidate.ProfileId -GameRoot $Plan.GameRoot -PayloadRoot $Plan.PayloadRoot -RecoveryRoot $Plan.RecoveryRoot -CatalogSha256 $CatalogSha256 -CatalogEntries $Plan.CatalogEntries -ForUndo -Probe -Historical:$historical -ReceiptChainTarget $targetRelative
        [void](Assert-TpmMultiPatchReceipt -Plan $candidatePlan -Receipt $candidate -CatalogSha256 $CatalogSha256 -Directory $successor.Snapshot.Directory.FullName -Historical:$historical -ReceiptChainTarget $targetRelative)
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
                $raw=Read-TpmMultiPatchReceiptBytes -Path $path -MaximumBytes 262144
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
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$CatalogSha256,[switch]$IncludePrepared)
    if(-not $Plan.ExclusiveGroup -or -not [IO.Directory]::Exists($Plan.RecoveryRoot)){return}
    foreach($directory in @(Get-ChildItem -LiteralPath $Plan.RecoveryRoot -Directory -ErrorAction Stop)){
        $path=Join-Path $directory.FullName 'receipt.json'
        if($directory.Name -notmatch '^[a-f0-9]{32}$' -or -not (Test-TpmNoReparsePath $path) -or -not [IO.File]::Exists($path)){continue}
        if((Get-Item -LiteralPath $path).Length -gt 262144){throw 'Exclusive-group receipt exceeds the supported bound.'}
        $record=[IO.File]::ReadAllText($path)|ConvertFrom-Json -ErrorAction Stop
        if($record.Schema -ne 3 -or $record.GameRoot -ine $Plan.GameRoot){continue}
        if($record.State -ceq 'Prepared'){
            if($IncludePrepared){throw 'A grouped transaction is unresolved; preserve its recovery evidence.'}
            continue
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
                if(Test-TpmMultiPatchReceiptChain -Plan $Plan -RootReceipt $record -RootDirectory $directory.FullName -CatalogSha256 $CatalogSha256){
                    if($record.ExclusiveGroup -ieq $Plan.ExclusiveGroup -and ($record.PatchId -cne $Plan.PatchId -or $record.CatalogSha256 -ine $CatalogSha256)){throw 'An exclusive recipe is active; undo it before selecting another variant.'}
                    continue
                }
            }
            throw $failure
        }
        if($record.State -ceq 'Applied' -and $other.ExclusiveGroup -ieq $Plan.ExclusiveGroup -and
            ($record.PatchId -cne $Plan.PatchId -or $record.CatalogSha256 -ine $CatalogSha256)){
            throw 'An exclusive recipe is active; undo it before selecting another variant.'
        }
    }
}

function Get-TpmMultiPatchPlan {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$PatchId,[Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot,[Parameter(Mandatory)][string]$PayloadRoot,[Parameter(Mandatory)][string]$RecoveryRoot,
        [Parameter(Mandatory)][string]$CatalogSha256,[Parameter(Mandatory)][array]$CatalogEntries,[switch]$ForUndo,[switch]$Probe,[switch]$Historical,[string]$ReceiptChainTarget='')
    if($Historical -and (-not $ForUndo -or -not $Probe)){throw 'Historical plans are only valid for completed receipt inspection.'}
    if($ReceiptChainTarget -and (-not $ForUndo -or -not $Probe -or @($Entry.Operations|Where-Object Target -CEQ $ReceiptChainTarget).Count -ne 1)){throw 'Receipt-chain structural inspection is internal to the exclusive gate.'}
    if($ReceiptChainTarget -and (Get-PSCallStack)[1].FunctionName -cne 'Test-TpmMultiPatchReceiptChain'){throw 'Receipt-chain structural inspection is internal to the exclusive gate.'}
    if($Entry.Operations -isnot [array] -or $Entry.Operations.Count -lt 1 -or $Entry.Operations.Count -gt 256){throw 'Grouped recipes require 1..256 file operations.'}
    if($Entry.ExclusiveGroup -isnot [string] -or ($Entry.ExclusiveGroup -and $Entry.ExclusiveGroup -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')){throw 'Invalid exclusive group.'}
    $selfExecutable = $Entry.PSObject.Properties['AllowExecutableSelfPatch'] -and $Entry.AllowExecutableSelfPatch
    $exe=Resolve-TpmPatchPath $GameRoot $Entry.Executable
    if($Entry.ExecutableSha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Executable revision mismatch.'}
    $executableSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    if(-not $selfExecutable -and $executableSha256 -ine $Entry.ExecutableSha256){throw 'Executable revision mismatch.'}
    if($selfExecutable -and ($Entry.Operations.Count -ne 1 -or $Entry.Operations[0].Type -cne 'ReplaceFile' -or
        $Entry.Operations[0].BeforeSha256 -ine $Entry.ExecutableSha256)){throw 'Executable self-patch requires one exact ReplaceFile before-state.'}
    $targets=@{};$payloads=@{};$operations=@();$ready=0;$applied=0;$total=0L
    foreach($operation in $Entry.Operations){
        $create=($operation.Type -ceq 'CreateFile')
        $pre=if($create){'BeforeState'}else{'BeforeSha256'}
        Assert-TpmPatchFields $operation @('Type','Target',$pre,'AfterSha256','Payload','PayloadSha256')
        foreach($field in @('Type','Target',$pre,'AfterSha256','Payload','PayloadSha256')){if($operation.PSObject.Properties[$field].Value -isnot [string]){throw 'Invalid grouped operation field.'}}
        if($operation.Type -cnotin @('ReplaceFile','CreateFile') -or ($create -and $operation.BeforeState -cne 'Absent')){throw 'Unsupported grouped operation/pre-state.'}
        $pins=@($operation.AfterSha256,$operation.PayloadSha256);if(-not $create){$pins+=@($operation.BeforeSha256)}
        foreach($pin in $pins){if($pin -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid grouped content pin.'}}
        if($operation.AfterSha256 -ine $operation.PayloadSha256 -or (-not $create -and $operation.BeforeSha256 -ieq $operation.AfterSha256)){throw 'Conflicting/no-op grouped pins.'}
        $target=Resolve-TpmPatchPath $GameRoot $operation.Target
        $payload=Resolve-TpmPatchPath $PayloadRoot $operation.Payload
        if($target -ieq $exe){
            if(-not $selfExecutable -or $Entry.Operations.Count -ne 1 -or $operation.Type -cne 'ReplaceFile' -or
                $operation.BeforeSha256 -ine $Entry.ExecutableSha256){throw 'Executable self-patch requires explicit single-file opt-in and the exact executable before-state.'}
        }elseif($selfExecutable){throw 'Executable self-patch must target the exact declared executable.'}
        if($targets.ContainsKey($target) -or $payloads.ContainsKey($payload)){throw 'Duplicate target/payload.'}
        foreach($other in $targets.Keys){if(Test-TpmPathOverlap $target $other){throw 'Overlapping grouped target paths.'}}
        $targets[$target]=$true;$payloads[$payload]=$true
        if(-not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($target))){throw 'Grouped targets require existing safe parents.'}
        if(-not $ForUndo){
            $item=Get-Item -LiteralPath $payload -ErrorAction Stop
            if($item.PSIsContainer){throw 'Grouped payload is not a file.'}
            $total+=[int64]$item.Length
            if($total -gt 64MB -or (Get-FileHash -LiteralPath $payload -Algorithm SHA256).Hash -ine $operation.PayloadSha256){throw 'Grouped payload hash/64 MiB bound mismatch.'}
        }
        if(-not $Historical){
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
    if(-not $Probe){Assert-TpmMultiPatchExclusive $plan $CatalogSha256}
    if(-not $Probe -and $plan.Status -ceq 'AlreadyApplied'){
        $found=@()
        if([IO.Directory]::Exists($RecoveryRoot)){
            foreach($directory in @(Get-ChildItem -LiteralPath $RecoveryRoot -Directory -ErrorAction Stop)){
                if($directory.Name -notmatch '^[a-f0-9]{32}$'){continue}
                try{$receipt=Read-TpmCatalogPatchReceipt -Plan $plan -PatchId $PatchId -ProfileId $ProfileId -CatalogSha256 $CatalogSha256 -RecoveryDirectory $directory.FullName
                    if($receipt.State -ceq 'Applied'){$found+=@($directory.FullName)}
                }catch{continue}
            }
        }
        if($found.Count -gt 1){throw 'Grouped after-state has duplicate transaction receipts.'}
        $plan | Add-Member -NotePropertyName UndoAvailable -NotePropertyValue ($found.Count -eq 1) -Force
        if($found.Count -eq 1){$plan | Add-Member -NotePropertyName RecoveryDirectory -NotePropertyValue $found[0] -Force}
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
        $Receipt.State -cnotin @('Applied','Restored','RolledBack') -or $Receipt.Operations -isnot [array] -or $Receipt.Operations.Count -ne $Plan.Operations.Count){throw 'Grouped receipt identity mismatch.'}
    for($i=0;$i -lt $Plan.Operations.Count;$i++){
        $expected=$Plan.Operations[$i];$record=$Receipt.Operations[$i]
        Assert-TpmPatchFields $record @('Type','Target','BeforeSha256','AfterSha256','Backup','BeforeFileIdentity','AfterFileIdentity','RestoredFileIdentity')
        foreach($field in @('Type','Target','BeforeSha256','AfterSha256','Backup','BeforeFileIdentity','AfterFileIdentity','RestoredFileIdentity')){if($record.PSObject.Properties[$field].Value -isnot [string]){throw 'Invalid grouped receipt operation type.'}}
        if($record.Type -cne $expected.Operation -or $record.Target -cne $expected.RelativeTarget -or $record.BeforeSha256 -ine $expected.BeforeSha256 -or
            $record.AfterSha256 -ine $expected.AfterSha256 -or $record.AfterFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$'){throw 'Grouped receipt operation identity mismatch.'}
        if($record.Type -ceq 'ReplaceFile'){
            if($record.BeforeFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$' -or -not (Test-PathInside $record.Backup $Directory) -or -not (Test-TpmNoReparsePath $record.Backup) -or
                (Get-Item -LiteralPath $record.Backup).Length -gt 64MB -or (Get-FileHash -LiteralPath $record.Backup -Algorithm SHA256).Hash -ine $record.BeforeSha256){throw 'Grouped retained backup invalid.'}
        }elseif($record.Backup -cne '' -or $record.BeforeFileIdentity -cne '' -or $record.RestoredFileIdentity -cne ''){throw 'Invalid grouped creation absence evidence.'}
        if($record.Type -ceq 'ReplaceFile' -and
            (($Receipt.State -ceq 'Restored' -and $record.RestoredFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$') -or
            ($Receipt.State -ceq 'RolledBack' -and $record.RestoredFileIdentity -cne ''))){throw 'Invalid grouped completed file identity.'}
        if($Historical){continue}
        if($ReceiptChainTarget -and $record.Target -ceq $ReceiptChainTarget){continue}
        $after=($Receipt.State -ceq 'Applied')
        if(-not (Test-TpmPatchTargetState $expected $after)){throw 'Grouped receipt target state changed.'}
        if($after -or $record.Type -ceq 'ReplaceFile'){
            $identity=if($after){$record.AfterFileIdentity}elseif($Receipt.State -ceq 'RolledBack'){$record.BeforeFileIdentity}else{$record.RestoredFileIdentity}
            if($identity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$'){throw 'Grouped receipt file identity is unavailable.'}
            $opened=Open-TpmPatchCreationFile $expected.Target
            try{if([TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle) -cne $identity){throw 'Grouped target object identity changed.'}}finally{$opened.Dispose()}
        }
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
        (Get-Item -LiteralPath $path).Length -gt 262144 -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $captured.Sha256){throw 'Grouped terminal receipt differs from verified history.'}
}

function New-TpmMultiPatchTerminalCheckpoint {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$Directory)
    if($Receipt.State -cnotin @('Restored','RolledBack')){throw 'Only a verified completed transaction may retain a terminal receipt.'}
    # Called under the transaction gate only after target verification and history.
    $receiptPath=Join-Path $Directory 'receipt.json'
    if(-not (Test-TpmNoReparsePath $receiptPath) -or (Get-Item -LiteralPath $receiptPath).Length -gt 262144){throw 'Grouped terminal receipt path/bound changed.'}
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

function Invoke-TpmPatchFileBatch {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][hashtable]$Inputs,[Parameter(Mandatory)][string]$CatalogSha256,
        [ValidateSet('Apply','Undo')][string]$Action='Apply',[string]$RecoveryDirectory='',$Receipt=$null,[scriptblock]$ValidationAction=$null,[scriptblock]$HistoryAction=$null)
    $apply=($Action -ceq 'Apply');$run=$RecoveryDirectory;$records=@();$locks=@();$exeGuard=$null;$gate=$null;$historyStarted=$false;$committed=$false;$receiptReady=(-not $apply)
    try{
        foreach($parent in @($Plan.Operations|ForEach-Object {[IO.Path]::GetDirectoryName($_.Target)}|Sort-Object -Unique)){
            $locks+=@(Open-TpmPatchDirectoryBoundary $parent)
        }
        $exeGuard=Open-TpmPatchCreationFile $Plan.Executable -MaximumBytes ([int64]::MaxValue)
        $exePin=if($Plan.ExecutableSelfPatch){if($apply){$Plan.Operations[0].BeforeSha256}else{$Plan.Operations[0].AfterSha256}}else{$Plan.ExecutableSha256}
        if((Get-TpmPatchStreamSha256 $exeGuard) -ine $exePin){throw 'Grouped executable identity changed.'}
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
        if($sourceTotal -gt 64MB -or $beforeTotal -gt 64MB){throw 'Grouped source/backup aggregate exceeds 64 MiB.'}
        if($ValidationAction){[void](& $ValidationAction)}
        # Only after every file passed preflight may recovery or sibling staging be written.
        [void][IO.Directory]::CreateDirectory($Plan.RecoveryRoot)
        $locks+=@(Open-TpmPatchDirectoryBoundary $Plan.RecoveryRoot)
        $receiptStoreBoundary=Test-TpmResetStoreBoundary -BackupsRoot $Plan.RecoveryRoot -StoreRoot (Join-Path $Plan.RecoveryRoot 'ReceiptHistory')
        if(-not $receiptStoreBoundary.Verified){throw ('Grouped terminal receipt storage is unavailable: '+$receiptStoreBoundary.Reason)}
        $gatePath=Join-Path $Plan.RecoveryRoot 'patch-batch.lock'
        if(-not (Test-TpmNoReparsePath $gatePath)){throw 'Unsafe grouped transaction gate.'}
        $gate=New-Object IO.FileStream($gatePath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        if((Get-TpmSupportFinalPathFromHandle $gate.SafeFileHandle) -ine $gatePath -or $gate.Length -ne 0){throw 'Grouped transaction gate identity is invalid.'}
        [void][TpmSupportNativeMethods]::PatchFileIdentity($gate.SafeFileHandle)
        if($apply){
            Assert-TpmMultiPatchExclusive $Plan $CatalogSha256 -IncludePrepared
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
        if($HistoryAction){$historyStarted=$true;[void](& $HistoryAction 'before' $Plan $run)}
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
        if($HistoryAction){[void](& $HistoryAction 'after' $Plan $run)}
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
                    if($location -ine $record.Operation.Target){Move-TpmPatchCreationHandle $record.Current.SafeFileHandle $record.Operation.Target}
                    $pin=if($apply){$record.Operation.BeforeSha256}else{$record.Operation.AfterSha256}
                    if([TpmSupportNativeMethods]::PatchFileIdentity($record.Current.SafeFileHandle) -cne $record.BeforeIdentity -or (Get-TpmPatchStreamSha256 $record.Current) -ine $pin){throw 'Grouped rollback object/bytes mismatch.'}
                    $record.Current.Dispose();$record.Current=$null
                    $record.Guard=Open-TpmPatchCreationFile $record.Operation.Target
                }
            }catch{$rollbackErrors+=@($_.Exception.Message)}
        }
        if($rollbackErrors.Count -or -not (Test-TpmPatchTargetState $Plan (-not $apply))){throw ('Grouped rollback requires attention; evidence retained at '+$run+'; '+[string]::Join('; ',$rollbackErrors)+'; original: '+$failure.Exception.Message)}
        if($Receipt -and $run -and $receiptReady){$Receipt.State=if($apply){'RolledBack'}else{'Applied'};Write-TpmPatchCreationReceipt $run $Receipt}
        if($historyStarted){
            try{[void](& $HistoryAction 'rolledback' $Plan $run)}catch{throw ('Grouped rollback bytes verified but terminal history unavailable: '+$_.Exception.Message+'; original: '+$failure.Exception.Message)}
        }
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
    $cleanupErrors=@()
    foreach($record in $records){
        if($record.Current){try{Remove-TpmSupportHandle $record.Current.SafeFileHandle}catch{$cleanupErrors+=@($_.Exception.Message)}finally{$record.Current.Dispose()}}
    }
    if($cleanupErrors.Count){throw ('Grouped transaction committed but owned cleanup requires attention: '+[string]::Join('; ',$cleanupErrors)+'; recovery '+$run)}
    return [pscustomobject]@{Status=$(if($apply){'Applied'}else{'Restored'});RecoveryDirectory=$run;SourceUrl=$Plan.SourceUrl;SourceRevision=$Plan.SourceRevision}
}

function Open-TpmPatchDirectoryBoundary {
    param([Parameter(Mandatory)][string]$Directory)
    [void](Get-TpmSupportNativeType)
    $full=[IO.Path]::GetFullPath($Directory).TrimEnd('\')
    if($full.Length -gt 247 -or -not (Test-TpmNoReparsePath $full) -or -not [IO.Directory]::Exists($full)){throw 'CreateFile requires an existing safe parent directory.'}
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
            if($final.TrimEnd('\') -ine $path.TrimEnd('\') -or ([TpmSupportNativeMethods]::PatchAttributes($handle) -band 0x410) -ne 0x10){throw 'Patch directory handle identity is unsafe.'}
        }
        return ,$handles
    }catch{foreach($handle in $handles){$handle.Dispose()};throw}
}

function Open-TpmPatchCreationFile {
    param([Parameter(Mandatory)][string]$Path,[switch]$NewFile,[switch]$ForRemoval,[int64]$MaximumBytes=67108864)
    [void](Get-TpmSupportNativeType)
    $access=[TpmSupportNativeMethods]::GenericRead
    $share=[TpmSupportNativeMethods]::ShareRead -bor [TpmSupportNativeMethods]::ShareDelete
    $mode=[TpmSupportNativeMethods]::OpenExisting
    $streamAccess=[IO.FileAccess]::Read
    if($NewFile){$access=$access -bor [TpmSupportNativeMethods]::GenericWrite;$mode=[TpmSupportNativeMethods]::CreateNew;$streamAccess=[IO.FileAccess]::ReadWrite}
    if($NewFile -or $ForRemoval){$access=$access -bor [TpmSupportNativeMethods]::Delete;$share=[TpmSupportNativeMethods]::ShareRead}
    $handle=[TpmSupportNativeMethods]::CreateFile($Path,$access,$share,[IntPtr]::Zero,$mode,[TpmSupportNativeMethods]::FileFlagOpenReparsePoint,[IntPtr]::Zero)
    if($handle.IsInvalid){$handle.Dispose();throw 'Patch file could not be opened without overwriting or sharing writes.'}
    try {
        if((Get-TpmSupportFinalPathFromHandle $handle) -ine [IO.Path]::GetFullPath($Path)){throw 'Patch opened file identity changed.'}
        [void][TpmSupportNativeMethods]::PatchFileIdentity($handle)
        $stream=New-Object IO.FileStream($handle,$streamAccess,65536,$false)
        if($stream.Length -gt $MaximumBytes){$stream.Dispose();throw 'Patch file exceeds the 64 MiB bound.'}
        return $stream
    }catch{if($NewFile){Remove-TpmSupportHandle $handle};$handle.Dispose();throw}
}

function Get-TpmPatchStreamSha256 {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    $position=$Stream.Position;$sha=[Security.Cryptography.SHA256]::Create()
    try{$Stream.Position=0;return (-join ($sha.ComputeHash($Stream)|ForEach-Object {$_.ToString('x2')}))}finally{$Stream.Position=$position;$sha.Dispose()}
}

function Move-TpmPatchCreationHandle {
    param([Parameter(Mandatory)][Microsoft.Win32.SafeHandles.SafeFileHandle]$Handle,[Parameter(Mandatory)][string]$Destination)
    [TpmSupportNativeMethods]::PatchRenameNoReplace($Handle,$Destination)
    $final=Get-TpmSupportFinalPathFromHandle $Handle
    if($final -ine [IO.Path]::GetFullPath($Destination)){throw ('Patch atomic rename readback failed: '+$final+'; expected '+$Destination)}
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
    $path=Join-Path $Directory 'receipt.json'
    if(-not (Test-TpmNoReparsePath $path)){throw 'Unsafe creation receipt path.'}
    [IO.File]::WriteAllText($path,($Receipt|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
}

function Find-TpmPatchCreationReceipt {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$CatalogSha256)
    $creationReceipts=@()
    if(-not [IO.Directory]::Exists($Plan.RecoveryRoot)){throw 'Existing CreateFile target lacks recovery evidence.'}
    foreach($dir in @(Get-ChildItem -LiteralPath $Plan.RecoveryRoot -Directory -ErrorAction Stop)){
        if($dir.Name -notmatch '^[a-f0-9]{32}$' -or -not (Test-TpmNoReparsePath $dir.FullName)){continue}
        try{
            $receipt=Read-TpmCatalogPatchReceipt -Plan $Plan -PatchId $Plan.PatchId -ProfileId $Plan.ProfileId -CatalogSha256 $CatalogSha256 -RecoveryDirectory $dir.FullName
            if($receipt.State -ceq 'Applied'){$creationReceipts+=@($dir.FullName)}
        }catch{continue}
    }
    if($creationReceipts.Count -ne 1){throw 'Existing CreateFile target lacks unique matching transaction evidence.'}
    return $creationReceipts[0]
}

function Invoke-TpmPatchFileCreation {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][hashtable]$Inputs,[Parameter(Mandatory)][string]$CatalogSha256,[scriptblock]$ValidationAction=$null,[scriptblock]$HistoryAction=$null)
    $locks=$null;$source=$null;$created=$null;$guard=$null;$exeGuard=$null;$moved=$false;$historyStarted=$false;$run=$null;$receipt=$null
    try{
        $locks=Open-TpmPatchDirectoryBoundary ([IO.Path]::GetDirectoryName($Plan.Target))
        $exeGuard=Open-TpmPatchCreationFile $Plan.Executable -MaximumBytes ([int64]::MaxValue)
        if((Get-TpmPatchStreamSha256 $exeGuard) -ine $Plan.ExecutableSha256){throw 'CreateFile executable identity changed.'}
        $fresh=Get-TpmPatchPlan @Inputs
        if($fresh.Status -cne 'Ready' -or -not (Test-TpmPatchTargetState $Plan $false)){throw 'CreateFile state changed before preparation.'}
        $source=Open-TpmPatchCreationFile $Plan.Payload
        if((Get-TpmPatchStreamSha256 $source) -ine $Plan.AfterSha256){throw 'CreateFile source hash mismatch.'}
        $run=Join-Path $Plan.RecoveryRoot ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($run)
        if(-not (Test-TpmNoReparsePath $run)){throw 'Unsafe creation recovery directory.'}
        $backup=Join-Path $run 'created-payload'
        $retained=[IO.File]::Open($backup,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$source.Position=0;$source.CopyTo($retained,65536);$retained.Flush($true)}finally{$retained.Dispose()}
        if((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ine $Plan.AfterSha256){throw 'Creation retained payload verification failed.'}
        $temp=Join-Path ([IO.Path]::GetDirectoryName($Plan.Target)) ('.tpm-create-'+[guid]::NewGuid().ToString('N')+'.tmp')
        $created=Open-TpmPatchCreationFile $temp -NewFile
        $source.Position=0;$source.CopyTo($created,65536);$created.Flush($true)
        if((Get-TpmPatchStreamSha256 $created) -ine $Plan.AfterSha256){throw 'Creation staged payload verification failed.'}
        $receipt=[ordered]@{Schema=2;Operation='CreateFile';BeforeState='Absent';PatchId=$Plan.PatchId;CatalogSha256=$CatalogSha256;ProfileId=$Plan.ProfileId;GameRoot=$Plan.GameRoot;Target=$Plan.RelativeTarget;Backup=$backup;BeforeSha256='';AfterSha256=$Plan.AfterSha256;TransactionId=[IO.Path]::GetFileName($run);CreatedFileIdentity=[TpmSupportNativeMethods]::PatchFileIdentity($created.SafeFileHandle);State='Prepared'}
        Write-TpmPatchCreationReceipt $run $receipt
        if($ValidationAction){[void](& $ValidationAction)}
        if($HistoryAction){$historyStarted=$true;[void](& $HistoryAction 'before' $Plan $run)}
        if($ValidationAction){[void](& $ValidationAction)}
        if((Get-TpmPatchPlan @Inputs).Status -cne 'Ready' -or -not (Test-TpmPatchTargetState $Plan $false)){throw 'CreateFile state changed before atomic publication.'}
        Move-TpmPatchCreationHandle $created.SafeFileHandle $Plan.Target
        $moved=$true
        $created.Dispose();$created=$null
        $guard=Open-TpmPatchCreationFile $Plan.Target
        if([TpmSupportNativeMethods]::PatchFileIdentity($guard.SafeFileHandle) -cne $receipt.CreatedFileIdentity -or
            (Get-TpmPatchStreamSha256 $guard) -ine $Plan.AfterSha256){throw 'Creation readback failed.'}
        $receipt.State='Applied';Write-TpmPatchCreationReceipt $run $receipt
        if($ValidationAction){[void](& $ValidationAction)}
        if($HistoryAction){[void](& $HistoryAction 'after' $Plan $run)}
        return [pscustomobject]@{Status='Applied';RecoveryDirectory=$run;SourceUrl=$Plan.SourceUrl;SourceRevision=$Plan.SourceRevision}
    }catch{
        $failure=$_
        if($guard){$guard.Dispose();$guard=$null}
        if($moved -and -not $created){
            try{
                $created=Open-TpmPatchCreationFile $Plan.Target -ForRemoval
                if([TpmSupportNativeMethods]::PatchFileIdentity($created.SafeFileHandle) -cne $receipt.CreatedFileIdentity -or (Get-TpmPatchStreamSha256 $created) -ine $Plan.AfterSha256){
                    $created.Dispose();$created=$null;throw 'Creation target changed during rollback; preserved.'
                }
            }catch{throw ('Creation rollback identity unavailable; evidence retained at '+$run+': '+$_.Exception.Message+'; original: '+$failure.Exception.Message)}
        }
        if($created){
            try{Remove-TpmSupportHandle $created.SafeFileHandle;$created.Dispose();$created=$null}catch{throw ('Creation rollback failed; evidence retained at '+$run+': '+$_.Exception.Message+'; original: '+$failure.Exception.Message)}
        }
        if($moved -and -not (Test-TpmPatchTargetState $Plan $false)){throw ('Creation rollback absence verification failed; evidence retained at '+$run)}
        if($receipt){$receipt.State='RolledBack';Write-TpmPatchCreationReceipt $run $receipt}
        if($historyStarted -and (Test-TpmPatchTargetState $Plan $false)){
            try{[void](& $HistoryAction 'rolledback' $Plan $run)}catch{throw ('Creation rollback verified but terminal history unavailable: '+$_.Exception.Message+'; original: '+$failure.Exception.Message)}
        }
        throw $failure
    }finally{
        if($exeGuard){$exeGuard.Dispose()};if($guard){$guard.Dispose()};if($created){$created.Dispose()};if($source){$source.Dispose()};if($locks){foreach($handle in $locks){$handle.Dispose()}}
    }
}

function Undo-TpmPatchFileCreation {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$Receipt,[Parameter(Mandatory)][string]$RecoveryDirectory,[scriptblock]$ValidationAction=$null,[scriptblock]$HistoryAction=$null)
    $locks=$null;$owned=$null;$exeGuard=$null;$removed=$false;$historyStarted=$false
    $aside=Join-Path ([IO.Path]::GetDirectoryName($Plan.Target)) ('.tpm-undo-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $locks=Open-TpmPatchDirectoryBoundary ([IO.Path]::GetDirectoryName($Plan.Target))
        $exeGuard=Open-TpmPatchCreationFile $Plan.Executable -MaximumBytes ([int64]::MaxValue)
        if((Get-TpmPatchStreamSha256 $exeGuard) -ine $Plan.ExecutableSha256){throw 'Creation undo executable identity changed.'}
        $owned=Open-TpmPatchCreationFile $Plan.Target
        if([TpmSupportNativeMethods]::PatchFileIdentity($owned.SafeFileHandle) -cne $Receipt.CreatedFileIdentity -or (Get-TpmPatchStreamSha256 $owned) -ine $Plan.AfterSha256){throw 'Created target identity or bytes changed; destructive undo refused.'}
        if($ValidationAction){[void](& $ValidationAction)}
        if($HistoryAction){$historyStarted=$true;[void](& $HistoryAction 'before' $Plan $RecoveryDirectory)}
        $owned.Dispose();$owned=$null
        $owned=Open-TpmPatchCreationFile $Plan.Target -ForRemoval
        if([TpmSupportNativeMethods]::PatchFileIdentity($owned.SafeFileHandle) -cne $Receipt.CreatedFileIdentity -or (Get-TpmPatchStreamSha256 $owned) -ine $Plan.AfterSha256){throw 'Created target changed at undo publication boundary.'}
        Move-TpmPatchCreationHandle $owned.SafeFileHandle $aside
        $removed=$true
        if(-not (Test-TpmPatchTargetState $Plan $false)){throw 'Creation undo absence readback failed.'}
        if($ValidationAction){[void](& $ValidationAction)}
        $Receipt.State='Restored';Write-TpmPatchCreationReceipt $RecoveryDirectory $Receipt
        if($HistoryAction){[void](& $HistoryAction 'after' $Plan $RecoveryDirectory)}
    }catch{
        $failure=$_
        if($removed){
            try{Move-TpmPatchCreationHandle $owned.SafeFileHandle $Plan.Target
                if([TpmSupportNativeMethods]::PatchFileIdentity($owned.SafeFileHandle) -cne $Receipt.CreatedFileIdentity -or (Get-TpmPatchStreamSha256 $owned) -ine $Plan.AfterSha256){throw 'Restored created bytes failed readback.'}
                $owned.Dispose();$owned=$null
                $owned=Open-TpmPatchCreationFile $Plan.Target
                if([TpmSupportNativeMethods]::PatchFileIdentity($owned.SafeFileHandle) -cne $Receipt.CreatedFileIdentity -or (Get-TpmPatchStreamSha256 $owned) -ine $Plan.AfterSha256){throw 'Restored target changed after rollback.'}
            }catch{throw ('Creation undo rollback failed; owned bytes retained at '+$aside+'; '+$_.Exception.Message+'; original: '+$failure.Exception.Message)}
        }
        if($removed){$Receipt.State='Applied';Write-TpmPatchCreationReceipt $RecoveryDirectory $Receipt}
        if($historyStarted -and (Test-TpmPatchTargetState $Plan $true)){
            if($owned){$owned.Dispose();$owned=$null}
            $owned=Open-TpmPatchCreationFile $Plan.Target
            try{[void](& $HistoryAction 'rolledback' $Plan $RecoveryDirectory)}catch{throw ('Creation undo rollback verified but terminal history unavailable: '+$_.Exception.Message+'; original: '+$failure.Exception.Message)}
        }
        throw $failure
    }finally{
        if($exeGuard){$exeGuard.Dispose()};if($owned){$owned.Dispose()};if($locks){foreach($handle in $locks){$handle.Dispose()}}
    }
    # The target is already verified absent and inverse history committed. Delete
    # only the renamed owned file; never follow or delete a substituted path.
    $residue=Open-TpmPatchCreationFile $aside -ForRemoval
    try{
        if([TpmSupportNativeMethods]::PatchFileIdentity($residue.SafeFileHandle) -cne $Receipt.CreatedFileIdentity -or (Get-TpmPatchStreamSha256 $residue) -ine $Plan.AfterSha256){throw ('Undo residue identity changed; preserved at '+$aside)}
        Remove-TpmSupportHandle $residue.SafeFileHandle
    }finally{$residue.Dispose()}
    return [pscustomobject]@{Status='Restored';RecoveryDirectory=$RecoveryDirectory}
}

function Invoke-TpmCatalogPatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,ParameterSetName="File")][string]$CatalogPath, [Parameter(Mandatory,ParameterSetName="Content")][string]$CatalogContent, [Parameter(Mandatory)][string]$CatalogSha256,
        [Parameter(Mandatory)][string]$PatchId, [Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot, [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$RecoveryRoot, [Parameter(Mandatory)][string[]]$ProtectedRoots,
        [AllowNull()][object]$HardwareEvidence = $null,
        [scriptblock]$ValidationAction=$null,[scriptblock]$HistoryAction=$null
    )
    $inputs = @{}; foreach ($key in $PSBoundParameters.Keys) { if ($key -notin @('WhatIf', 'Confirm', 'ValidationAction','HistoryAction')) { $inputs[$key] = $PSBoundParameters[$key] } }
    $plan = Get-TpmPatchPlan @inputs
    if ($plan.Status -eq 'Unavailable') { throw $plan.Reason }
    if ($plan.Status -eq 'AlreadyApplied' -or -not $PSCmdlet.ShouldProcess($plan.Target, "Apply catalog patch $PatchId")) { return $plan }
    if($plan.Operation -ceq 'MultiFile'){return (Invoke-TpmPatchFileBatch -Plan $plan -Inputs $inputs -CatalogSha256 $CatalogSha256 -ValidationAction $ValidationAction -HistoryAction $HistoryAction)}
    if($plan.Operation -ceq 'CreateFile'){return (Invoke-TpmPatchFileCreation -Plan $plan -Inputs $inputs -CatalogSha256 $CatalogSha256 -ValidationAction $ValidationAction -HistoryAction $HistoryAction)}
    $stage = New-TpmStagingDirectory 'CatalogPatch'
    foreach ($root in @($plan.GameRoot, $PayloadRoot, $plan.RecoveryRoot) + $ProtectedRoots) { if (Test-TpmPathOverlap $stage $root) { throw 'Unsafe staging overlap.' } }
    $run = Join-Path $plan.RecoveryRoot ([Guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run)
    if (-not (Test-TpmNoReparsePath $run)) { throw 'Unsafe recovery path.' }
    $original = Join-Path $run 'original'
    [void][IO.Directory]::CreateDirectory($original)
    $copy = Join-Path $original ([IO.Path]::GetFileName($plan.Target))
    Copy-Item -LiteralPath $plan.Target -Destination $copy -ErrorAction Stop
    # Reuse the existing backup layout/helper inside a unique, patch-owned run.
    $backup = New-ManagerUpdateBackup $copy
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256 -ErrorAction Stop).Hash -ne $plan.BeforeSha256) { throw 'Pre-change backup verification failed.' }
    $staged = Resolve-TpmPatchPath $stage $plan.RelativeTarget
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($staged))
    Copy-Item -LiteralPath $plan.Payload -Destination $staged -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256 -ErrorAction Stop).Hash -ne $plan.AfterSha256) { throw 'Staged payload verification failed.' }
    $receipt = [ordered]@{ Schema = 1; PatchId = $PatchId; CatalogSha256 = $CatalogSha256; ProfileId = $ProfileId; GameRoot = $plan.GameRoot; Target = $plan.RelativeTarget; Backup = $backup; BeforeSha256 = $plan.BeforeSha256; AfterSha256 = $plan.AfterSha256 }
    [IO.File]::WriteAllText((Join-Path $run 'receipt.json'), ($receipt | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $fresh = Get-TpmPatchPlan @inputs
    if ($fresh.Status -ne 'Ready' -or -not (Test-TpmNoReparsePath $stage) -or -not (Test-TpmNoReparsePath $backup)) { throw 'Patch state changed before promotion.' }
    if ($ValidationAction) { [void](& $ValidationAction) }
    if ($HistoryAction) { [void](& $HistoryAction 'before' $plan $run) }
    try {
    if ($ValidationAction) { [void](& $ValidationAction) }
    [void](Invoke-TpmTransactionalPromote $stage $plan.GameRoot @($plan.RelativeTarget) {
        if ($ValidationAction) { [void](& $ValidationAction) }
        if (-not (Test-TpmNoReparsePath $plan.Target) -or (Get-FileHash -LiteralPath $plan.Target -Algorithm SHA256 -ErrorAction Stop).Hash -ne $plan.AfterSha256) { throw 'Patch readback failed.' }
        if ($HistoryAction) { [void](& $HistoryAction 'after' $plan $run) }
    })
    } catch {
        $patchFailure=$_
        if ($HistoryAction -and (Test-TpmNoReparsePath $plan.Target) -and
            (Get-FileHash -LiteralPath $plan.Target -Algorithm SHA256).Hash -ieq $plan.BeforeSha256) {
            try { [void](& $HistoryAction 'rolledback' $plan $run) }
            catch { throw ('Patch rollback bytes are verified but terminal history is unavailable: '+$_.Exception.Message+'; original error: '+$patchFailure.Exception.Message) }
        }
        throw $patchFailure
    }
    return [pscustomobject]@{ Status = 'Applied'; RecoveryDirectory = $run; SourceUrl = $plan.SourceUrl; SourceRevision = $plan.SourceRevision }
}

function Read-TpmCatalogPatchReceipt {
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$PatchId,[Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$CatalogSha256,[Parameter(Mandatory)][string]$RecoveryDirectory)
    if (-not (Test-PathInside $RecoveryDirectory $plan.RecoveryRoot) -or -not (Test-TpmNoReparsePath $RecoveryDirectory)) { throw 'Invalid recovery directory.' }
    $receiptPath = Join-Path $RecoveryDirectory 'receipt.json'
    if (-not (Test-TpmNoReparsePath $receiptPath)) { throw 'Unsafe receipt.' }
    if ((Get-Item -LiteralPath $receiptPath -ErrorAction Stop).Length -gt $(if($Plan.Operation -ceq 'MultiFile'){262144}else{16384})) { throw 'Retained receipt exceeds the supported size.' }
    $receipt = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json -ErrorAction Stop
    if($Plan.Operation -ceq 'MultiFile'){return (Assert-TpmMultiPatchReceipt -Plan $Plan -Receipt $receipt -CatalogSha256 $CatalogSha256 -Directory $RecoveryDirectory)}
    if($Plan.Operation -ceq 'CreateFile'){
        Assert-TpmPatchFields $receipt @('Schema','Operation','BeforeState','PatchId','CatalogSha256','ProfileId','GameRoot','Target','Backup','BeforeSha256','AfterSha256','TransactionId','CreatedFileIdentity','State')
        foreach($field in @('Operation','BeforeState','PatchId','CatalogSha256','ProfileId','GameRoot','Target','Backup','BeforeSha256','AfterSha256','TransactionId','CreatedFileIdentity','State')){if($receipt.PSObject.Properties[$field].Value -isnot [string]){throw 'Invalid creation receipt string field.'}}
        if(($receipt.Schema -isnot [int] -and $receipt.Schema -isnot [long]) -or $receipt.Schema -ne 2 -or
            $receipt.Operation -cne 'CreateFile' -or $receipt.BeforeState -cne 'Absent' -or $receipt.BeforeSha256 -cne '' -or
            $receipt.TransactionId -notmatch '^[a-f0-9]{32}$' -or $receipt.TransactionId -cne [IO.Path]::GetFileName([IO.Path]::GetFullPath($RecoveryDirectory).TrimEnd('\')) -or
            $receipt.CreatedFileIdentity -cnotmatch '^[A-F0-9]{8}:[A-F0-9]{16}$' -or $receipt.State -cnotin @('Applied','Restored') -or
            $receipt.PatchId -cne $PatchId -or $receipt.ProfileId -cne $ProfileId -or $receipt.CatalogSha256 -ine $CatalogSha256 -or
            $receipt.GameRoot -ine $Plan.GameRoot -or $receipt.Target -cne $Plan.RelativeTarget -or $receipt.AfterSha256 -ine $Plan.AfterSha256){throw 'Creation receipt identity mismatch.'}
        if($receipt.Backup -ine (Join-Path $RecoveryDirectory 'created-payload') -or -not (Test-TpmNoReparsePath $receipt.Backup) -or
            (Get-Item -LiteralPath $receipt.Backup -ErrorAction Stop).Length -gt 64MB -or (Get-FileHash -LiteralPath $receipt.Backup -Algorithm SHA256 -ErrorAction Stop).Hash -ine $Plan.AfterSha256){throw 'Retained creation payload invalid.'}
        if($receipt.State -ceq 'Applied'){
            $opened=Open-TpmPatchCreationFile $Plan.Target
            try{if([TpmSupportNativeMethods]::PatchFileIdentity($opened.SafeFileHandle) -cne $receipt.CreatedFileIdentity -or
                (Get-TpmPatchStreamSha256 $opened) -ine $Plan.AfterSha256){throw 'Created target identity or bytes changed.'}}finally{$opened.Dispose()}
        }elseif(-not (Test-TpmPatchTargetState $Plan $false)){throw 'Restored creation target is no longer absent.'}
        return $receipt
    }
    Assert-TpmPatchFields $receipt @('Schema', 'PatchId', 'CatalogSha256', 'ProfileId', 'GameRoot', 'Target', 'Backup', 'BeforeSha256', 'AfterSha256')
    foreach ($field in @('PatchId', 'CatalogSha256', 'ProfileId', 'GameRoot', 'Target', 'Backup', 'BeforeSha256', 'AfterSha256')) { if ($receipt.PSObject.Properties[$field].Value -isnot [string]) { throw 'Invalid receipt string field.' } }
    if (($receipt.Schema -isnot [int] -and $receipt.Schema -isnot [long]) -or $receipt.Schema -ne 1 -or $receipt.PatchId -cne $PatchId -or $receipt.ProfileId -cne $ProfileId -or $receipt.CatalogSha256 -ne $CatalogSha256 -or $receipt.GameRoot -ne $plan.GameRoot -or $receipt.Target -ne $plan.RelativeTarget -or $receipt.BeforeSha256 -ne $plan.BeforeSha256 -or $receipt.AfterSha256 -ne $plan.AfterSha256) { throw 'Receipt identity mismatch.' }
    if (-not (Test-PathInside $receipt.Backup $RecoveryDirectory) -or -not (Test-TpmNoReparsePath $receipt.Backup) -or (Get-FileHash -LiteralPath $receipt.Backup -Algorithm SHA256 -ErrorAction Stop).Hash -ne $plan.BeforeSha256) { throw 'Retained backup invalid.' }

    return $receipt
}

function Undo-TpmCatalogPatch {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory,ParameterSetName="File")][string]$CatalogPath, [Parameter(Mandatory,ParameterSetName="Content")][string]$CatalogContent, [Parameter(Mandatory)][string]$CatalogSha256,
        [Parameter(Mandatory)][string]$PatchId, [Parameter(Mandatory)][string]$ProfileId,
        [Parameter(Mandatory)][string]$GameRoot, [Parameter(Mandatory)][string]$PayloadRoot,
        [Parameter(Mandatory)][string]$RecoveryRoot, [Parameter(Mandatory)][string[]]$ProtectedRoots,
        [Parameter(Mandatory)][string]$RecoveryDirectory,
        [AllowNull()][object]$HardwareEvidence = $null,
        [scriptblock]$ValidationAction=$null,[scriptblock]$HistoryAction=$null
    )
    $inputs = @{}; foreach ($key in $PSBoundParameters.Keys) { if ($key -notin @('RecoveryDirectory', 'WhatIf', 'Confirm', 'ValidationAction','HistoryAction')) { $inputs[$key] = $PSBoundParameters[$key] } }
    $plan = Get-TpmPatchPlan @inputs -ForUndo
    if ($plan.Status -eq 'Unavailable') { throw $plan.Reason }
    $receipt=Read-TpmCatalogPatchReceipt -Plan $plan -PatchId $PatchId -ProfileId $ProfileId -CatalogSha256 $CatalogSha256 -RecoveryDirectory $RecoveryDirectory
    if ($plan.Status -eq 'Ready') { return [pscustomobject]@{ Status = 'AlreadyRestored' } }
    if (-not $PSCmdlet.ShouldProcess($plan.Target, "Undo catalog patch $PatchId")) { return $plan }
    if($plan.Operation -ceq 'MultiFile'){return (Invoke-TpmPatchFileBatch -Plan $plan -Inputs $inputs -CatalogSha256 $CatalogSha256 -Action Undo -RecoveryDirectory $RecoveryDirectory -Receipt $receipt -ValidationAction $ValidationAction -HistoryAction $HistoryAction)}
    if($plan.Operation -ceq 'CreateFile'){return (Undo-TpmPatchFileCreation -Plan $plan -Receipt $receipt -RecoveryDirectory $RecoveryDirectory -ValidationAction $ValidationAction -HistoryAction $HistoryAction)}
    $stage = New-TpmStagingDirectory 'CatalogUndo'
    foreach ($root in @($plan.GameRoot, $PayloadRoot, $plan.RecoveryRoot) + $ProtectedRoots) { if (Test-TpmPathOverlap $stage $root) { throw 'Unsafe staging overlap.' } }
    $staged = Resolve-TpmPatchPath $stage $plan.RelativeTarget
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($staged))
    Copy-Item -LiteralPath $receipt.Backup -Destination $staged -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256 -ErrorAction Stop).Hash -ne $plan.BeforeSha256 -or (Get-TpmPatchPlan @inputs -ForUndo).Status -ne 'AlreadyApplied') { throw 'Undo state changed before promotion.' }
    if ($ValidationAction) { [void](& $ValidationAction) }
    if ($HistoryAction) { [void](& $HistoryAction 'before' $plan $RecoveryDirectory) }
    try {
    if ($ValidationAction) { [void](& $ValidationAction) }
    [void](Invoke-TpmTransactionalPromote $stage $plan.GameRoot @($plan.RelativeTarget) {
        if ($ValidationAction) { [void](& $ValidationAction) }
        if (-not (Test-TpmNoReparsePath $plan.Target) -or (Get-FileHash -LiteralPath $plan.Target -Algorithm SHA256 -ErrorAction Stop).Hash -ne $plan.BeforeSha256) { throw 'Undo readback failed.' }
        if ($HistoryAction) { [void](& $HistoryAction 'after' $plan $RecoveryDirectory) }
    })
    } catch {
        $patchFailure=$_
        if ($HistoryAction -and (Test-TpmNoReparsePath $plan.Target) -and
            (Get-FileHash -LiteralPath $plan.Target -Algorithm SHA256).Hash -ieq $plan.AfterSha256) {
            try { [void](& $HistoryAction 'rolledback' $plan $RecoveryDirectory) }
            catch { throw ('Patch rollback bytes are verified but terminal history is unavailable: '+$_.Exception.Message+'; original error: '+$patchFailure.Exception.Message) }
        }
        throw $patchFailure
    }
    return [pscustomobject]@{ Status = 'Restored'; RecoveryDirectory = $RecoveryDirectory }
}
function Read-TpmRequiredPatchCatalog {
    param([Parameter(Mandatory)][string]$ProgramRoot)
    $path = Join-Path $ProgramRoot 'scripts\TpmRequiredPatchRecipes.json'
    if (-not (Test-TpmNoReparsePath $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'The bundled required-patch recipe catalog is missing or unsafe.'
    }
    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($item.Length -gt 131072) { throw 'The bundled required-patch recipe catalog exceeds its size limit.' }
    $bytes = [IO.File]::ReadAllBytes($path)
    $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($sha256 -ine $script:TpmRequiredPatchCatalogSha256) { throw 'The bundled required-patch recipe catalog hash does not match the TPM-pinned catalog.' }
    $encoding = New-Object System.Text.UTF8Encoding($false,$true)
    $content = $encoding.GetString($bytes)
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash -ine $sha256) { throw 'The bundled recipe catalog changed while it was read.' }
    $catalog = $content | ConvertFrom-Json -ErrorAction Stop
    if ($catalog.Schema -ne 3 -or $catalog.Entries -isnot [array] -or @($catalog.Entries).Count -eq 0) {
        throw 'The bundled required-patch recipe catalog schema is invalid.'
    }
    return [pscustomobject]@{ Path=$path; Content=$content; CatalogSha256=$sha256; Entries=@($catalog.Entries); Schema=[int]$catalog.Schema }
}

function Resolve-TpmRequiredPatchSourceRoot {
    param(
        [Parameter(Mandatory)]$Entry,
        [string]$MainSource = '',
        [string]$SupplementarySource = ''
    )
    if ([IO.Path]::GetFileName([string]$Entry.SourceSet) -cne [string]$Entry.SourceSet -or
        [string]$Entry.SourceSet -match '[<>:"|?*\p{Cc}]') { throw 'The recipe source set must be one exact ZIP filename.' }
    $root = switch ([string]$Entry.SourceRole) {
        'Main' { $MainSource }
        'Supplementary' { $SupplementarySource }
        default { '' }
    }
    $validRoot = $false
    if (-not [string]::IsNullOrWhiteSpace($root) -and
        (Test-Path -LiteralPath $root -PathType Container -ErrorAction SilentlyContinue) -and
        (Test-TpmNoReparsePath $root)) {
        $archivePath = Join-Path $root ([string]$Entry.SourceSet)
        $validRoot = (Test-Path -LiteralPath $archivePath -PathType Leaf -ErrorAction SilentlyContinue) -and
            (Test-TpmNoReparsePath $archivePath)
    }
    if ($validRoot) { return [IO.Path]::GetFullPath($root) }
    $sourceLabel = switch ([string]$Entry.SourceRole) {
        'Main' { 'Main' }
        'Supplementary' { 'Supplementary' }
        'UserSelected' { 'patch' }
        default { 'required patch' }
    }
    Write-Host ("  Select the local {0} ZIP folder containing this exact file: {1}" -f $sourceLabel,$Entry.SourceSet) -ForegroundColor Cyan
    Write-Host '  TPM reads only the named ZIP member. It does not download or extract the collection.' -ForegroundColor DarkGray
    $selected = Read-PathWithBrowse -Prompt 'Folder containing the exact required local ZIP' -Mode Folder -InitialDirectory $root
    if ([string]::IsNullOrWhiteSpace($selected) -or
        -not (Test-Path -LiteralPath $selected -PathType Container -ErrorAction SilentlyContinue) -or
        -not (Test-TpmNoReparsePath $selected)) { throw 'No safe local source folder was selected.' }
    $selected = [IO.Path]::GetFullPath($selected)
    $archivePath = Join-Path $selected ([string]$Entry.SourceSet)
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf -ErrorAction SilentlyContinue) -or
        -not (Test-TpmNoReparsePath $archivePath)) { throw 'The selected folder does not contain the exact required ZIP.' }
    return $selected
}

function New-TpmRequiredPatchPayloadStage {
    param([Parameter(Mandatory)]$Entry,[Parameter(Mandatory)][string]$SourceRoot)
    $stage = $null
    $archive = $null
    $memberStream = $null
    $output = $null
    try {
        if (-not $script:TpmOwnedLayout -or -not $script:TpmOwnedLayout.Temp -or
            -not (Test-PathInside $script:TpmOwnedLayout.Temp $script:TpmOwnedLayout.Root) -or
            -not (Test-TpmNoReparsePath $script:TpmOwnedLayout.Temp)) { throw 'The TPM-owned temporary staging root is unavailable.' }
        $archivePath = [IO.Path]::GetFullPath((Join-Path $SourceRoot ([string]$Entry.SourceSet)))
        if (-not (Test-PathInside $archivePath $SourceRoot) -or -not (Test-TpmNoReparsePath $archivePath) -or
            -not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw 'The exact local source ZIP is unavailable or unsafe.' }
        if ($Entry.SourceSize -isnot [int] -and $Entry.SourceSize -isnot [long]) { throw 'The recipe has no bounded member size.' }
        if ($Entry.SourceSize -le 0 -or $Entry.SourceSize -gt 67108864) { throw 'The recipe member size exceeds the supported bound.' }
        # SourceSha1 preserves DAT identity metadata; SHA256 is the runtime payload pin.
        if ([string]$Entry.SourceSha1 -notmatch '^[a-fA-F0-9]{40}$' -or
            [string]$Entry.SourceSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'The recipe member hash pins are invalid.' }
        $stage = Join-Path $script:TpmOwnedLayout.Temp ('RequiredPatch-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($stage)
        if (-not (Test-PathInside $stage $script:TpmOwnedLayout.Temp) -or -not (Test-TpmNoReparsePath $stage)) {
            throw 'The unique patch staging directory failed its containment check.'
        }
        # Fixed framework assembly names are required by Windows PowerShell 5.1.
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        $members = @($archive.Entries | Where-Object { $_.FullName -ceq [string]$Entry.SourceEntry })
        if ($members.Count -ne 1 -or $members[0].Length -ne [int64]$Entry.SourceSize) {
            throw 'The exact required ZIP member is absent, duplicated, or has a different size.'
        }
        $payload = Resolve-TpmPatchPath $stage ([string]$Entry.Operations[0].Payload)
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($payload))
        $memberStream = $members[0].Open()
        $output = New-Object IO.FileStream($payload,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer = New-Object byte[] 65536
        $total = [int64]0
        while (($read = $memberStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt [int64]$Entry.SourceSize -or $total -gt 67108864) { throw 'The ZIP member exceeded its pinned size while streaming.' }
            $output.Write($buffer,0,$read)
        }
        $output.Flush($true)
        $output.Dispose();$output=$null
        $memberStream.Dispose();$memberStream=$null
        if ($total -ne [int64]$Entry.SourceSize) { throw 'The ZIP member byte count differs from its pinned size.' }
        $sha256 = (Get-FileHash -LiteralPath $payload -Algorithm SHA256 -ErrorAction Stop).Hash
        if ($sha256 -ine [string]$Entry.SourceSha256 -or
            $sha256 -ine [string]$Entry.Operations[0].PayloadSha256 -or
            $sha256 -ine [string]$Entry.Operations[0].AfterSha256) { throw 'The streamed local member does not match the payload and target SHA-256 pins.' }
        return [pscustomobject]@{ Root=$stage; Payload=$payload; Size=$total; Sha256=$sha256; SourceArchive=$archivePath; SourceEntry=[string]$Entry.SourceEntry }
    } catch {
        $failure=$_
        try {
            if($output){$output.Dispose();$output=$null}
            if($memberStream){$memberStream.Dispose();$memberStream=$null}
            if($archive){$archive.Dispose();$archive=$null}
        } catch {
            throw ('Patch payload staging resources could not be closed; original error: '+$failure.Exception.Message+'; cleanup error: '+$_.Exception.Message)
        }
        if ($stage -and (Test-PathInside $stage $script:TpmOwnedLayout.Temp) -and (Test-Path -LiteralPath $stage)) {
            if(-not (Test-TpmNoReparsePath $stage)){throw ('Unsafe TPM staging residue was preserved at '+$stage+'; original error: '+$failure.Exception.Message)}
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
            $guidance += 'BepInEx is not installed for this game. Use TPM''s existing BepInEx setup with the authorized source, or your own local BepInEx files. TPM will not download a game patch.'
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
        [string[]]$SourceRoots = @()
    )
    foreach ($root in @($TpRoot,$ManagerRoot)) {
        if (-not [IO.Path]::IsPathRooted($root) -or -not (Test-TpmNoReparsePath $root)) { throw 'TeknoParrot or TPM root is unsafe.' }
    }
    if ([IO.Path]::GetFullPath($UserProfilesDir) -ine [IO.Path]::GetFullPath((Join-Path $TpRoot 'UserProfiles')) -or
        -not (Test-Path -LiteralPath (Join-Path $TpRoot 'TeknoParrotUi.exe') -PathType Leaf)) { throw 'A configured TeknoParrot installation is required.' }
    if ($Entry.ProfileId -isnot [string] -or $Entry.ProfileId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { throw 'Invalid exact profile identity.' }
    $official = Resolve-TpmPatchPath (Join-Path $TpRoot 'GameProfiles') ($Entry.ProfileId + '.xml')
    if (-not (Test-Path -LiteralPath $official -PathType Leaf) -or -not (Test-TpmNoReparsePath $official)) {
        throw 'The exact TeknoParrot GameProfile template is unavailable.'
    }
    if (-not [IO.Path]::IsPathRooted($GameRoot) -or -not (Test-Path -LiteralPath $GameRoot -PathType Container) -or
        -not (Test-TpmNoReparsePath $GameRoot)) { throw 'The selected installed game folder is unavailable or unsafe.' }
    $game = [IO.Path]::GetFullPath($GameRoot)
    if (-not (Test-TpmNoReparsePath $game)) { throw 'The canonical game folder is unsafe.' }
    if ($script:TpmOwnedLayout -and (Test-TpmPathOverlap $game $script:TpmOwnedLayout.Root)) {
        throw 'The selected game folder overlaps TPM-owned state.'
    }
    $protected = @((Join-Path $TpRoot 'TeknoParrotUi.exe'),(Join-Path $TpRoot 'GameProfiles'),$UserProfilesDir,
        (Join-Path $ManagerRoot 'TeknoParrot-Manager.ps1'),(Join-Path $ManagerRoot 'TeknoParrot-Manager.config.json'),
        (Join-Path $ManagerRoot 'tools'),(Join-Path $ManagerRoot 'Crosshairs'))
    $protected += @($SourceRoots | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($root in $protected) {
        if (Test-TpmPathOverlap $game $root) { throw 'The selected game folder overlaps TeknoParrot, TPM, or a patch source.' }
    }
    $gamePath = Resolve-TpmPatchPath $game ([string]$Entry.Executable)
    if (-not (Test-Path -LiteralPath $gamePath -PathType Leaf) -or -not (Test-TpmNoReparsePath $gamePath)) {
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
            throw 'The TPM backup layout is unsafe.'
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

function Invoke-TpmRequiredPatchMenu {
    param(
        [Parameter(Mandatory)][string]$TpRoot,
        [Parameter(Mandatory)][string]$UserProfilesDir,
        [Parameter(Mandatory)][string]$ManagerRoot,
        [Parameter(Mandatory)][string]$ProgramRoot,
        [string]$MainSource = '',
        [string]$SupplementarySource = ''
    )
    $assertGameClosed = {
        param([Parameter(Mandatory)][string]$GamePath)
        $name=[WildcardPattern]::Escape([IO.Path]::GetFileNameWithoutExtension($GamePath))
        if(@(Get-Process -Name $name -ErrorAction SilentlyContinue).Count -gt 0){throw 'Close the game before applying or undoing its patch.'}
    }.GetNewClosure()
    try { $catalog = Read-TpmRequiredPatchCatalog -ProgramRoot $ProgramRoot }
    catch {
        Write-Host ("  Required patch recipes are unavailable: {0}" -f $_.Exception.Message) -ForegroundColor Red
        [void](Read-HostSafe '  Press Enter to return')
        return
    }
    Write-Host ''
    Write-Host '  Required game patches' -ForegroundColor Cyan
    Write-Host '  A) Find and install all applicable required patches for registered supported games'
    Write-Host '  M) Install one required patch into an already-installed game folder'
    Write-Host '  U) Undo a TPM-installed required patch'
    Write-Host '  Q) Return without changes'
    $choice = ([string](Read-HostSafe '  Choose A, M, U, or Q')).Trim().ToUpperInvariant()
    if ($choice -eq 'Q' -or -not $choice) { return }
    if ($choice -notin @('A','M','U')) {
        Write-Host '  Invalid choice; no changes were made.' -ForegroundColor Yellow
        [void](Read-HostSafe '  Press Enter to return')
        return
    }
    $hardwareEvidence = $null
    $hasHardwarePredicates = @($catalog.Entries | Where-Object { $_.PSObject.Properties['HardwarePredicate'] -and $null -ne $_.HardwarePredicate }).Count -gt 0
    if ($choice -ne 'U' -and $hasHardwarePredicates) {
        $hardwareEvidence = Get-TpmHardwareEnvironmentEvidence
    }
    $stages = New-Object System.Collections.Generic.List[string]
    try {
        $selectedEntries = @($catalog.Entries)
        if ($choice -eq 'M' -or $choice -eq 'U') {
            for ($index=0;$index -lt $selectedEntries.Count;$index++) {
                Write-Host ("  {0}) {1} -- {2}" -f ($index+1),$selectedEntries[$index].BuildName,$selectedEntries[$index].Id)
            }
            $number = ([string](Read-HostSafe '  Select the exact required recipe number')).Trim()
            $parsed = 0
            if (-not [int]::TryParse($number,[ref]$parsed) -or $parsed -lt 1 -or $parsed -gt $selectedEntries.Count) {
                Write-Host '  No valid recipe was selected; nothing changed.' -ForegroundColor DarkGray
                return
            }
            $selectedEntries = @($selectedEntries[$parsed-1])
        }
        $candidates = New-Object System.Collections.Generic.List[object]
        $reported = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $selectedEntries) {
            $profilePath = Join-Path $UserProfilesDir ($entry.ProfileId + '.xml')
            if ($choice -eq 'A' -and -not (Test-Path -LiteralPath $profilePath -PathType Leaf -ErrorAction SilentlyContinue)) { continue }
            if ($choice -eq 'M') {
                Write-Host ("  Select the installed game folder containing {0}. It will not be registered or changed by this step." -f $entry.Executable) -ForegroundColor Cyan
                $gameRoot = Read-PathWithBrowse -Prompt 'Installed game folder' -Mode Folder -InitialDirectory $gamesInstallFolder
                if ([string]::IsNullOrWhiteSpace($gameRoot)) { [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='CANCELLED';Reason='No game folder was selected.'});continue }
                try {
                    $sourceRoot = Resolve-TpmRequiredPatchSourceRoot -Entry $entry -MainSource $MainSource -SupplementarySource $SupplementarySource
                    $stageInfo = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $sourceRoot
                    [void]$stages.Add($stageInfo.Root)
                    $context = Get-TpmManualPatchContext -Entry $entry -TpRoot $TpRoot -UserProfilesDir $UserProfilesDir -ManagerRoot $ManagerRoot -GameRoot $gameRoot -SourceRoots @($sourceRoot)
                } catch {
                    [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='BLOCKED';Reason=$_.Exception.Message})
                    continue
                }
            } else {
                try {
                    if ($choice -eq 'A') {
                        $context = Get-TpmRegisteredPatchContext -Entry $entry -TpRoot $TpRoot -UserProfilesDir $UserProfilesDir -ManagerRoot $ManagerRoot
                        $sourceRoot = Resolve-TpmRequiredPatchSourceRoot -Entry $entry -MainSource $MainSource -SupplementarySource $SupplementarySource
                        $stageInfo = New-TpmRequiredPatchPayloadStage -Entry $entry -SourceRoot $sourceRoot
                        [void]$stages.Add($stageInfo.Root)
                        $context.ProtectedRoots = @($context.ProtectedRoots) + @($sourceRoot)
                    } else {
                        Write-Host '  Select the installed game folder whose patch receipt you want to undo.' -ForegroundColor Cyan
                        $gameRoot = Read-PathWithBrowse -Prompt 'Installed game folder' -Mode Folder -InitialDirectory $gamesInstallFolder
                        if ([string]::IsNullOrWhiteSpace($gameRoot)) { [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='CANCELLED';Reason='No game folder was selected.'});continue }
                        $context = Get-TpmManualPatchContext -Entry $entry -TpRoot $TpRoot -UserProfilesDir $UserProfilesDir -ManagerRoot $ManagerRoot -GameRoot $gameRoot
                    }
                } catch {
                    [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='BLOCKED';Reason=$_.Exception.Message})
                    continue
                }
                if ($choice -eq 'U') {
                    try {
                        $emptyStage = Join-Path $script:TpmOwnedLayout.Temp ('RequiredPatchUndo-' + [guid]::NewGuid().ToString('N'))
                        [void][IO.Directory]::CreateDirectory($emptyStage)
                        [void]$stages.Add($emptyStage)
                        $plan = Get-TpmPatchPlan -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $entry.Id -ProfileId $entry.ProfileId -GameRoot $context.GameRoot -PayloadRoot $emptyStage -RecoveryRoot $context.RecoveryRoot -ProtectedRoots $context.ProtectedRoots -ForUndo
                        if ($plan.Status -eq 'Unavailable') { throw $plan.Reason }
                        if ($plan.Status -ne 'AlreadyApplied') { throw 'This exact game has no verified applied patch state to undo.' }
                        $request = [pscustomobject]@{Context=$context}
                        $package = [pscustomobject]@{CatalogSha256=$catalog.CatalogSha256}
                        $recoveryDirectories = @(Get-TpmPatchRecoveryDirectories -Request $request -Package $package -PatchId $entry.Id)
                        $validReceipts = New-Object System.Collections.Generic.List[string]
                        foreach ($directory in $recoveryDirectories) {
                            try {
                                [void](Read-TpmCatalogPatchReceipt -Plan $plan -PatchId $entry.Id -ProfileId $entry.ProfileId -CatalogSha256 $catalog.CatalogSha256 -RecoveryDirectory $directory)
                                [void]$validReceipts.Add($directory)
                            } catch {}
                        }
                        if ($validReceipts.Count -ne 1) { throw 'Exactly one verified undo receipt is required; ambiguous or missing receipts block undo.' }
                        $undoConfirm = ([string](Read-HostSafe '  Undo this exact TPM patch now? Enter Y to continue; default is N')).Trim().ToUpperInvariant()
                        if ($undoConfirm -cne 'Y') {
                            [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='CANCELLED';Reason='Undo was not confirmed; no game files were changed.'})
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
                            if ((Get-FileHash -LiteralPath $context.GamePath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $expectedExecutable) { throw 'The exact game executable changed before undo.' }
                        }
                        $result = Undo-TpmCatalogPatch -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $entry.Id -ProfileId $entry.ProfileId -GameRoot $context.GameRoot -PayloadRoot $emptyStage -RecoveryRoot $context.RecoveryRoot -ProtectedRoots $context.ProtectedRoots -RecoveryDirectory $validReceipts[0] -ValidationAction $validation -Confirm:$false
                        Write-Host ("  Undo result: {0}. The receipt and current target state were verified." -f $result.Status) -ForegroundColor Green
                    } catch {
                        [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='BLOCKED';Reason=$_.Exception.Message})
                    }
                    continue
                }
            }
            if ($choice -eq 'U') { continue }
            try {
                $currentExecutableHash = (Get-FileHash -LiteralPath $context.GamePath -Algorithm SHA256 -ErrorAction Stop).Hash
                $allowedExecutableHashes = @([string]$entry.ExecutableSha256)
                if ($entry.PSObject.Properties['AllowExecutableSelfPatch'] -and $entry.AllowExecutableSelfPatch) {
                    $allowedExecutableHashes += [string]$entry.Operations[0].AfterSha256
                }
                if ($currentExecutableHash -notin $allowedExecutableHashes) { throw 'The installed executable is not in an exact supported before/after state.' }
                $plan = Get-TpmPatchPlan -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $entry.Id -ProfileId $entry.ProfileId -GameRoot $context.GameRoot -PayloadRoot $stageInfo.Root -RecoveryRoot $context.RecoveryRoot -ProtectedRoots $context.ProtectedRoots -HardwareEvidence $hardwareEvidence
                if ($plan.Status -eq 'Unavailable') { throw $plan.Reason }
                if ($plan.Status -eq 'AlreadyApplied') {
                    [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='ALREADY_APPLIED';Reason='The exact pinned target bytes are already present; no write was made.'})
                    continue
                }
                $prerequisites = Test-TpmRequiredPatchPrerequisites -Entry $entry -GameRoot $context.GameRoot
                if (-not $prerequisites.Satisfied) {
                    [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='BLOCKED';Reason=($prerequisites.Guidance -join ' ')})
                    continue
                }
                [void]$candidates.Add([pscustomobject]@{Entry=$entry;Context=$context;Stage=$stageInfo;SourceRoot=$sourceRoot;Plan=$plan;Prerequisites=$prerequisites})
            } catch {
                [void]$reported.Add([pscustomobject]@{Entry=$entry;Status='BLOCKED';Reason=$_.Exception.Message})
            }
        }
        foreach ($item in $reported) {
            $color = if ($item.Status -eq 'ALREADY_APPLIED') { 'Green' } elseif ($item.Status -eq 'CANCELLED') { 'DarkGray' } else { 'Yellow' }
            Write-Host ("  {0}: {1} -- {2}" -f $item.Status,$item.Entry.BuildName,$item.Reason) -ForegroundColor $color
        }
        if ($choice -eq 'U') { [void](Read-HostSafe '  Press Enter to return');return }
        if ($candidates.Count -eq 0) {
            if ($choice -eq 'A' -and $reported.Count -eq 0) {
                Write-Host '  No registered game with a bundled required recipe was found. Use manual install for an already-installed game.' -ForegroundColor DarkGray
            } else {
                Write-Host '  No patch was applied. Resolve the listed prerequisites or source/build issue, then retry.' -ForegroundColor Yellow
            }
            [void](Read-HostSafe '  Press Enter to return')
            return
        }
        Write-Host ''
        Write-Host '  Ready to apply the following required patch(es):' -ForegroundColor Cyan
        foreach ($candidate in $candidates) {
            Write-Host ("    {0} -- exact executable and local ZIP member verified; TPM backup/undo receipt will be retained." -f $candidate.Entry.BuildName)
        }
        Write-Host '  Applying a file patch does not by itself prove the game is ready or playable.' -ForegroundColor Yellow
        $confirm = ([string](Read-HostSafe '  Apply all listed patches now? Enter Y to continue; default is N')).Trim().ToUpperInvariant()
        if ($confirm -cne 'Y') {
            Write-Host '  Cancelled. No game files were changed.' -ForegroundColor DarkGray
            return
        }
        foreach ($candidate in $candidates) {
            try {
                & $assertGameClosed $candidate.Context.GamePath
                $validation = {
                    param($validationState)
                    & $assertGameClosed $candidate.Context.GamePath
                    $expectedExecutable = [string]$candidate.Entry.ExecutableSha256
                    if ($candidate.Plan.PSObject.Properties['ExecutableSelfPatch'] -and $candidate.Plan.ExecutableSelfPatch) {
                        $expectedExecutable = if ($validationState -ceq 'published') { [string]$candidate.Entry.Operations[0].AfterSha256 } else { [string]$candidate.Entry.Operations[0].BeforeSha256 }
                    }
                    if ((Get-FileHash -LiteralPath $candidate.Context.GamePath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $expectedExecutable) {
                        throw 'The exact game executable changed before publication.'
                    }
                    $check = Test-TpmRequiredPatchPrerequisites -Entry $candidate.Entry -GameRoot $candidate.Context.GameRoot
                    if (-not $check.Satisfied) { throw ($check.Guidance -join ' ') }
                    if ((Get-FileHash -LiteralPath $candidate.Stage.Payload -Algorithm SHA256 -ErrorAction Stop).Hash -ine $candidate.Entry.SourceSha256) {
                        throw 'The staged local payload changed before publication.'
                    }
                    if ($candidate.Context.Registered -and
                        (Get-FileHash -LiteralPath $candidate.Context.ProfilePath -Algorithm SHA256 -ErrorAction Stop).Hash -ine $candidate.Context.ProfileSha256) {
                        throw 'The registered TeknoParrot profile changed before publication.'
                    }
                }
                $result = Invoke-TpmCatalogPatch -CatalogContent $catalog.Content -CatalogSha256 $catalog.CatalogSha256 -PatchId $candidate.Entry.Id -ProfileId $candidate.Entry.ProfileId -GameRoot $candidate.Context.GameRoot -PayloadRoot $candidate.Stage.Root -RecoveryRoot $candidate.Context.RecoveryRoot -ProtectedRoots $candidate.Context.ProtectedRoots -HardwareEvidence $hardwareEvidence -ValidationAction $validation -Confirm:$false
                if ($result.Status -eq 'Applied') {
                    Write-Host ("  APPLIED AND VERIFIED: {0}. Undo receipt: {1}" -f $candidate.Entry.BuildName,$result.RecoveryDirectory) -ForegroundColor Green
                    if (-not $candidate.Context.Registered) {
                        Write-Host '  Next: use TPM Register only to add this game to TeknoParrot, then configure controls in TeknoParrotUI.' -ForegroundColor Cyan
                    }
                    Write-Host '  Next: launch from TeknoParrotUI and verify the game and controls. A verified file copy is not gameplay proof.' -ForegroundColor Cyan
                } else {
                    Write-Host ("  SKIPPED: {0} -- {1}" -f $candidate.Entry.BuildName,$result.Status) -ForegroundColor DarkGray
                }
            } catch {
                Write-Host ("  FAILED: {0} -- {1}. No readiness is claimed." -f $candidate.Entry.BuildName,$_.Exception.Message) -ForegroundColor Red
                Write-Log ("Required patch failed for {0}: {1}" -f $candidate.Entry.Id,$_.Exception.Message)
            }
        }
        [void](Read-HostSafe '  Press Enter to return')
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
            Write-Host '  WARNING: TPM could not remove one or more temporary patch stages. Game-file verification remains separate.' -ForegroundColor Yellow
            foreach($failure in $cleanupFailures){Write-Host ('    '+$failure) -ForegroundColor Yellow}
        }
    }
}