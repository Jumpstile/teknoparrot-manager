Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Reports.psm1')
Set-StrictMode -Version 2.0

$script:TpmPublicationArtifactIdentifiersV1 = @('EligibilityJson','PublicationJson','FinalOutcomeJson','ScorecardMarkdown','ValidationMarkdown')

function New-TPMPublicationStagingV1 {
    param(
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)]$EligibilityReport,
        [Parameter(Mandatory=$true)]$PublicationReport,
        [Parameter(Mandatory=$true)]$FinalOutcomeReport,
        [Parameter(Mandatory=$true)]$ScorecardReport,
        [Parameter(Mandatory=$true)]$ValidationReport,
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)]$Marker
    )
    if($null-eq$Manifest-or$Manifest.PSObject.Properties.Name-notcontains'Json'-or$Manifest.PSObject.Properties.Name-notcontains'Bytes'-or[string]$Manifest.FileName-cne'TPM-Certification-Manifest.json'){throw 'PUBLISH_INVALID: Manifest must be a New-TPMManifestReportV1 result'}
    if($null-eq$Marker-or$Marker.PSObject.Properties.Name-notcontains'Json'-or$Marker.PSObject.Properties.Name-notcontains'Bytes'-or[string]$Marker.FileName-cne'TPM-Certification-Commit.json'){throw 'PUBLISH_INVALID: Marker must be a New-TPMCommitMarkerReportV1 result'}
    try{$parsedManifest=ConvertFrom-Json -InputObject $Manifest.Json -ErrorAction Stop}catch{throw 'PUBLISH_INVALID: Manifest.Json did not parse as JSON'}
    try{$parsedMarker=ConvertFrom-Json -InputObject $Marker.Json -ErrorAction Stop}catch{throw 'PUBLISH_INVALID: Marker.Json did not parse as JSON'}
    $utf8=New-Object Text.UTF8Encoding($false)
    $manifestHash=Get-TPMSha256HexV1 -Bytes $Manifest.Bytes
    $manifestJsonHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($Manifest.Json))
    if($manifestJsonHash-cne$manifestHash){throw 'PUBLISH_INVALID: Manifest.Bytes is not the exact BOM-less UTF-8 encoding of Manifest.Json'}
    $markerHash=Get-TPMSha256HexV1 -Bytes $Marker.Bytes
    $markerJsonHash=Get-TPMSha256HexV1 -Bytes ($utf8.GetBytes($Marker.Json))
    if($markerJsonHash-cne$markerHash){throw 'PUBLISH_INVALID: Marker.Bytes is not the exact BOM-less UTF-8 encoding of Marker.Json'}
    foreach($field in @('RunIdentity','ArtifactSetSha256','Artifacts')){if($null-eq$parsedManifest.PSObject.Properties[$field]){throw "PUBLISH_INVALID: Manifest is missing $field"}}
    foreach($field in @('RunIdentity','ManifestSha256')){if($null-eq$parsedMarker.PSObject.Properties[$field]){throw "PUBLISH_INVALID: Marker is missing $field"}}
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsedManifest.RunIdentity)
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsedMarker.RunIdentity)
    if([string]$parsedManifest.RunIdentity-cne[string]$parsedMarker.RunIdentity){throw 'PUBLISH_INVALID: Manifest and Marker RunIdentity differ'}
    Assert-TPMMarkdownSha256V1 ([string]$parsedMarker.ManifestSha256) 'ManifestSha256'
    if([string]$parsedMarker.ManifestSha256-cne$manifestHash){throw 'PUBLISH_INVALID: Marker.ManifestSha256 does not match Manifest bytes'}

    $reportsByIdentifier=[ordered]@{
        EligibilityJson=$EligibilityReport;PublicationJson=$PublicationReport;FinalOutcomeJson=$FinalOutcomeReport
        ScorecardMarkdown=$ScorecardReport;ValidationMarkdown=$ValidationReport
    }
    $orderedArtifacts=New-Object Collections.Generic.List[object]
    $seenIdentifiers=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($entry in @($parsedManifest.Artifacts)){
        $identifier=[string]$entry.Identifier
        if(-not $reportsByIdentifier.Contains($identifier)){throw "PUBLISH_INVALID: unknown manifest artifact identifier $identifier"}
        if(-not $seenIdentifiers.Add($identifier)){throw "PUBLISH_INVALID: duplicate manifest artifact identifier $identifier"}
        $report=$reportsByIdentifier[$identifier]
        if($null-eq$report-or$report.PSObject.Properties.Name-notcontains'Bytes'-or$report.PSObject.Properties.Name-notcontains'FileName'){throw "PUBLISH_INVALID: $identifier report is not a valid report object"}
        if([string]$report.FileName-cne[string]$entry.FileName){throw "PUBLISH_INVALID: $identifier FileName does not match Manifest"}
        $actualHash=Get-TPMSha256HexV1 -Bytes $report.Bytes
        if($actualHash-cne[string]$entry.Sha256){throw "PUBLISH_INVALID: $identifier bytes do not match Manifest Sha256"}
        $orderedArtifacts.Add([pscustomobject]@{Identifier=$identifier;FileName=[string]$entry.FileName;Bytes=$report.Bytes;Role='Report'})
    }
    foreach($identifier in $script:TpmPublicationArtifactIdentifiersV1){
        if(-not $seenIdentifiers.Contains($identifier)){throw "PUBLISH_INVALID: Manifest is missing artifact identifier $identifier"}
    }
    if($orderedArtifacts.Count-ne5){throw 'PUBLISH_INVALID: Manifest does not describe exactly five reports'}
    $orderedArtifacts.Add([pscustomobject]@{Identifier='Manifest';FileName=$Manifest.FileName;Bytes=$Manifest.Bytes;Role='Manifest'})
    $orderedArtifacts.Add([pscustomobject]@{Identifier='Marker';FileName=$Marker.FileName;Bytes=$Marker.Bytes;Role='Marker'})

    if([string]::IsNullOrWhiteSpace($StagingParentRoot)){throw 'PUBLISH_INVALID: StagingParentRoot is required'}
    if(-not [IO.Path]::IsPathRooted($StagingParentRoot)){throw 'PUBLISH_INVALID: StagingParentRoot must be absolute'}
    $normalizedParent=[IO.Path]::GetFullPath($StagingParentRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $runIdentity=[string]$parsedManifest.RunIdentity

    $result=[ordered]@{Committed=$false;RunIdentity=$runIdentity;StagingDirectory=$null;Files=@();FailureCode=$null;FailureMessage=$null}

    try{
        $stagingDir=Resolve-TPMContainedPathV1 -Root $normalizedParent -Path $runIdentity
    }catch{
        $result.FailureCode='STAGING_FAILED';$result.FailureMessage=$_.Exception.Message
        return [pscustomobject]$result
    }
    $result.StagingDirectory=$stagingDir
    $directoryCreatedThisCall=$false
    try{
        if(Test-Path -LiteralPath $stagingDir){
            $existing=Get-Item -LiteralPath $stagingDir -Force -ErrorAction Stop
            if(-not $existing.PSIsContainer){throw 'PATH_INVALID: staging path exists and is not a directory'}
            if(($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'PATH_REPARSE_POINT: staging directory is a reparse point'}
        }else{
            [void](New-Item -ItemType Directory -Path $stagingDir -ErrorAction Stop)
            $directoryCreatedThisCall=$true
            $stagingDir=Resolve-TPMContainedPathV1 -Root $normalizedParent -Path $runIdentity
            if(((Get-Item -LiteralPath $stagingDir -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'PATH_REPARSE_POINT: staging directory is a reparse point'}
        }
    }catch{
        $result.FailureCode='STAGING_FAILED';$result.FailureMessage=$_.Exception.Message
        try{if($directoryCreatedThisCall-and(Test-Path -LiteralPath $stagingDir)){$remaining=@(Get-ChildItem -LiteralPath $stagingDir -Force -ErrorAction Stop);if($remaining.Count-eq0){Remove-Item -LiteralPath $stagingDir -Force -ErrorAction Stop}}}catch{$result.FailureCode='ROLLBACK_FAILED'}
        return [pscustomobject]$result
    }

    $ownedPaths=New-Object Collections.Generic.List[string]
    $writtenFiles=New-Object Collections.Generic.List[object]
    try{
        foreach($artifact in $orderedArtifacts){
            $destination=Resolve-TPMContainedPathV1 -Root $stagingDir -Path $artifact.FileName
            if(Test-Path -LiteralPath $destination){throw "PATH_ALREADY_EXISTS: $($artifact.FileName)"}
            $stream=New-Object IO.FileStream($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
            try{$stream.Write($artifact.Bytes,0,$artifact.Bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
            $ownedPaths.Add($destination)
            $writtenFiles.Add([pscustomobject]@{Identifier=$artifact.Identifier;FileName=$artifact.FileName;Path=$destination;ByteLength=$artifact.Bytes.Length})
        }
    }catch{
        $failureMessage=$_.Exception.Message
        $failureCode=if($artifact.Role-ceq'Marker'){'MARKER_WRITE_FAILED'}else{'PROMOTION_FAILED'}
        $rollbackFailed=$false
        foreach($path in $ownedPaths){
            try{if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force -ErrorAction Stop}}catch{$rollbackFailed=$true}
        }
        try{
            if($directoryCreatedThisCall-and(Test-Path -LiteralPath $stagingDir)){
                $remaining=@(Get-ChildItem -LiteralPath $stagingDir -Force -ErrorAction Stop)
                if($remaining.Count-eq0){Remove-Item -LiteralPath $stagingDir -Force -ErrorAction Stop}
            }
        }catch{$rollbackFailed=$true}
        $result.FailureCode=if($rollbackFailed){'ROLLBACK_FAILED'}else{$failureCode}
        $result.FailureMessage=$failureMessage
        return [pscustomobject]$result
    }

    $result.Files=$writtenFiles.ToArray()
    return [pscustomobject]$result
}

function New-TPMPublicationCommitV1 {
    param(
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)]$EligibilityReport,
        [Parameter(Mandatory=$true)]$PublicationReport,
        [Parameter(Mandatory=$true)]$FinalOutcomeReport,
        [Parameter(Mandatory=$true)]$ScorecardReport,
        [Parameter(Mandatory=$true)]$ValidationReport,
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)]$Marker
    )
    if([string]::IsNullOrWhiteSpace($DestinationRoot)){throw 'PUBLISH_INVALID: DestinationRoot is required'}
    if(-not [IO.Path]::IsPathRooted($DestinationRoot)){throw 'PUBLISH_INVALID: DestinationRoot must be absolute'}

    $staging=New-TPMPublicationStagingV1 -StagingParentRoot $StagingParentRoot -EligibilityReport $EligibilityReport -PublicationReport $PublicationReport -FinalOutcomeReport $FinalOutcomeReport -ScorecardReport $ScorecardReport -ValidationReport $ValidationReport -Manifest $Manifest -Marker $Marker

    $result=[ordered]@{Committed=$false;RunIdentity=$staging.RunIdentity;DestinationDirectory=$null;ManifestSha256=$null;ArtifactSetSha256=$null;DiagnosticWarnings=@();FailureCode=$staging.FailureCode;FailureMessage=$staging.FailureMessage}
    if($staging.FailureCode){
        return [pscustomobject]$result
    }

    $parsedManifest=ConvertFrom-Json -InputObject $Manifest.Json
    $manifestArtifactSetSha256=[string]$parsedManifest.ArtifactSetSha256
    $expectedHashByFileName=@{}
    foreach($entry in @($parsedManifest.Artifacts)){$expectedHashByFileName[[string]$entry.FileName]=[string]$entry.Sha256}
    $manifestHash=Get-TPMSha256HexV1 -Bytes $Manifest.Bytes
    $markerHash=Get-TPMSha256HexV1 -Bytes $Marker.Bytes
    $expectedHashByFileName[[string]$Manifest.FileName]=$manifestHash
    $expectedHashByFileName[[string]$Marker.FileName]=$markerHash

    $normalizedDestinationParent=[IO.Path]::GetFullPath($DestinationRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    try{
        $destinationDir=Resolve-TPMContainedPathV1 -Root $normalizedDestinationParent -Path $staging.RunIdentity
    }catch{
        $result.FailureCode='PROMOTION_FAILED';$result.FailureMessage=$_.Exception.Message
        return [pscustomobject]$result
    }
    $result.DestinationDirectory=$destinationDir
    $destinationCreatedThisCall=$false
    try{
        if(Test-Path -LiteralPath $destinationDir){
            $existing=Get-Item -LiteralPath $destinationDir -Force -ErrorAction Stop
            if(-not $existing.PSIsContainer){throw 'PATH_INVALID: destination path exists and is not a directory'}
            if(($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'PATH_REPARSE_POINT: destination directory is a reparse point'}
        }else{
            [void](New-Item -ItemType Directory -Path $destinationDir -ErrorAction Stop)
            $destinationCreatedThisCall=$true
            $destinationDir=Resolve-TPMContainedPathV1 -Root $normalizedDestinationParent -Path $staging.RunIdentity
            if(((Get-Item -LiteralPath $destinationDir -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'PATH_REPARSE_POINT: destination directory is a reparse point'}
        }
    }catch{
        $result.FailureCode='PROMOTION_FAILED';$result.FailureMessage=$_.Exception.Message
        try{if($destinationCreatedThisCall-and(Test-Path -LiteralPath $destinationDir)){$remaining=@(Get-ChildItem -LiteralPath $destinationDir -Force -ErrorAction Stop);if($remaining.Count-eq0){Remove-Item -LiteralPath $destinationDir -Force -ErrorAction Stop}}}catch{$result.FailureCode='ROLLBACK_FAILED'}
        return [pscustomobject]$result
    }

    $promoted=New-Object Collections.Generic.List[object]
    $promotionFailed=$false
    $promotionFailureCode=$null
    $promotionFailureMessage=$null
    foreach($file in $staging.Files){
        try{
            $destinationPath=Resolve-TPMContainedPathV1 -Root $destinationDir -Path $file.FileName
            if(Test-Path -LiteralPath $destinationPath){throw "PATH_ALREADY_EXISTS: $($file.FileName)"}
            [IO.File]::Move($file.Path,$destinationPath)
            $promoted.Add([pscustomobject]@{Identifier=$file.Identifier;FileName=$file.FileName;StagingPath=$file.Path;DestinationPath=$destinationPath})
        }catch{
            $promotionFailed=$true
            $promotionFailureCode=if($file.Identifier-ceq'Marker'){'MARKER_WRITE_FAILED'}else{'PROMOTION_FAILED'}
            $promotionFailureMessage=$_.Exception.Message
            break
        }
    }

    if($promotionFailed){
        $rollbackFailed=$false
        foreach($p in $promoted){
            try{if(Test-Path -LiteralPath $p.DestinationPath){[IO.File]::Move($p.DestinationPath,$p.StagingPath)}}catch{$rollbackFailed=$true}
        }
        try{if($destinationCreatedThisCall-and(Test-Path -LiteralPath $destinationDir)){$remaining=@(Get-ChildItem -LiteralPath $destinationDir -Force -ErrorAction Stop);if($remaining.Count-eq0){Remove-Item -LiteralPath $destinationDir -Force -ErrorAction Stop}}}catch{$rollbackFailed=$true}
        $result.FailureCode=if($rollbackFailed){'ROLLBACK_FAILED'}else{$promotionFailureCode}
        $result.FailureMessage=$promotionFailureMessage
        return [pscustomobject]$result
    }

    $durableValidationFailed=$false
    $durableValidationMessage=$null
    foreach($p in $promoted){
        try{
            $onDiskBytes=[IO.File]::ReadAllBytes($p.DestinationPath)
            $onDiskHash=Get-TPMSha256HexV1 -Bytes $onDiskBytes
            $expected=$expectedHashByFileName[$p.FileName]
            if($onDiskHash-cne$expected){throw "durable validation hash mismatch for $($p.FileName)"}
        }catch{
            $durableValidationFailed=$true
            $durableValidationMessage=$_.Exception.Message
            break
        }
    }

    if($durableValidationFailed){
        $rollbackFailed=$false
        foreach($p in $promoted){
            try{if(Test-Path -LiteralPath $p.DestinationPath){[IO.File]::Move($p.DestinationPath,$p.StagingPath)}}catch{$rollbackFailed=$true}
        }
        try{if($destinationCreatedThisCall-and(Test-Path -LiteralPath $destinationDir)){$remaining=@(Get-ChildItem -LiteralPath $destinationDir -Force -ErrorAction Stop);if($remaining.Count-eq0){Remove-Item -LiteralPath $destinationDir -Force -ErrorAction Stop}}}catch{$rollbackFailed=$true}
        $result.FailureCode=if($rollbackFailed){'ROLLBACK_FAILED'}else{'DURABLE_VALIDATION_FAILED'}
        $result.FailureMessage=$durableValidationMessage
        return [pscustomobject]$result
    }

    $result.Committed=$true
    $result.FailureCode=$null
    $result.FailureMessage=$null
    $result.ManifestSha256=$manifestHash
    $result.ArtifactSetSha256=$manifestArtifactSetSha256

    $diagnosticWarnings=New-Object Collections.Generic.List[string]
    try{
        if(Test-Path -LiteralPath $staging.StagingDirectory){
            $remaining=@(Get-ChildItem -LiteralPath $staging.StagingDirectory -Force -ErrorAction Stop)
            if($remaining.Count-eq0){Remove-Item -LiteralPath $staging.StagingDirectory -Force -ErrorAction Stop}
        }
    }catch{[void]$diagnosticWarnings.Add('POST_COMMIT_CLEANUP_FAILED')}
    $result.DiagnosticWarnings=$diagnosticWarnings.ToArray()

    return [pscustomobject]$result
}

function Remove-TPMPublicationCommitV1 {
    # Rolls back an ALREADY-COMMITTED bundle (New-TPMPublicationCommitV1
    # returned Committed=$true at $DestinationDirectory) when a step that
    # must run AFTER a successful commit -- but BEFORE a genuine final
    # outcome exists -- fails (e.g. RegisterCommittedPublication or
    # IssueFinalOutcome throwing). The commit marker is the durable "this
    # bundle is authoritative" signal every consumer relies on (the same
    # reason New-TPMPublicationStagingV1/New-TPMPublicationCommitV1
    # promote it strictly LAST when committing) -- so it is removed FIRST
    # here, before any other file. The instant it is gone, no reader can
    # treat this directory as a committed bundle, even if the rest of this
    # cleanup only partially succeeds. Each file's on-disk content is
    # verified against the report object's own bytes before deletion --
    # this function refuses to delete a file whose content does not match
    # what this cycle actually wrote, rather than force-deleting by name
    # alone.
    param(
        [Parameter(Mandatory=$true)][string]$DestinationDirectory,
        [Parameter(Mandatory=$true)]$EligibilityReport,
        [Parameter(Mandatory=$true)]$PublicationReport,
        [Parameter(Mandatory=$true)]$FinalOutcomeReport,
        [Parameter(Mandatory=$true)]$ScorecardReport,
        [Parameter(Mandatory=$true)]$ValidationReport,
        [Parameter(Mandatory=$true)]$Manifest,
        [Parameter(Mandatory=$true)]$Marker
    )
    $ordered=@($Marker,$Manifest,$EligibilityReport,$PublicationReport,$FinalOutcomeReport,$ScorecardReport,$ValidationReport)
    $removed=New-Object Collections.Generic.List[string]
    $remaining=New-Object Collections.Generic.List[string]
    $errors=New-Object Collections.Generic.List[string]
    $markerRemoved=$false
    foreach($report in $ordered){
        $fileName=[string]$report.FileName
        $path=$null
        try{
            $path=Resolve-TPMContainedPathV1 -Root $DestinationDirectory -Path $fileName
        }catch{
            [void]$errors.Add("$fileName`: $($_.Exception.Message)")
            continue
        }
        if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}
        try{
            $onDiskBytes=[IO.File]::ReadAllBytes($path)
            $onDiskHash=Get-TPMSha256HexV1 -Bytes $onDiskBytes
            $expectedHash=Get-TPMSha256HexV1 -Bytes $report.Bytes
            if($onDiskHash-cne$expectedHash){throw "on-disk content does not match this cycle's own report bytes -- refusing to delete a file that may not be the one this cycle wrote"}
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            [void]$removed.Add($path)
            if($fileName-ceq[string]$Marker.FileName){$markerRemoved=$true}
        }catch{
            [void]$remaining.Add($path)
            [void]$errors.Add("$fileName`: $($_.Exception.Message)")
        }
    }
    try{
        if(Test-Path -LiteralPath $DestinationDirectory -PathType Container){
            $left=@(Get-ChildItem -LiteralPath $DestinationDirectory -Force -ErrorAction Stop)
            if($left.Count-eq0){Remove-Item -LiteralPath $DestinationDirectory -Force -ErrorAction Stop}
        }
    }catch{[void]$errors.Add("DestinationDirectory cleanup: $($_.Exception.Message)")}
    return [pscustomobject][ordered]@{
        MarkerRemoved=$markerRemoved
        FullyRolledBack=($remaining.Count-eq0-and$errors.Count-eq0)
        RemovedFiles=$removed.ToArray()
        RemainingFiles=$remaining.ToArray()
        Errors=$errors.ToArray()
    }
}

Export-ModuleMember -Function New-TPMPublicationStagingV1,New-TPMPublicationCommitV1,Remove-TPMPublicationCommitV1
