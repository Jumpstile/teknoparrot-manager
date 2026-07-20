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
    foreach($field in @('RunIdentity','ArtifactSetSha256','Artifacts')){if($null-eq$parsedManifest.PSObject.Properties[$field]){throw "PUBLISH_INVALID: Manifest is missing $field"}}
    foreach($field in @('RunIdentity','ManifestSha256')){if($null-eq$parsedMarker.PSObject.Properties[$field]){throw "PUBLISH_INVALID: Marker is missing $field"}}
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsedManifest.RunIdentity)
    Assert-TPMMarkdownRunIdentityV1 ([string]$parsedMarker.RunIdentity)
    if([string]$parsedManifest.RunIdentity-cne[string]$parsedMarker.RunIdentity){throw 'PUBLISH_INVALID: Manifest and Marker RunIdentity differ'}
    Assert-TPMMarkdownSha256V1 ([string]$parsedMarker.ManifestSha256) 'ManifestSha256'
    $manifestHash=Get-TPMSha256HexV1 -Bytes $Manifest.Bytes
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

Export-ModuleMember -Function New-TPMPublicationStagingV1
