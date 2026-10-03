# =============================================================================
# TeknoParrot Manager updater helper functions
# =============================================================================
# Pure/testable logic for tools/Invoke-TpmAutoUpdate.ps1, split out so Pester
# can import and exercise it without triggering the orchestrator's top-level
# network calls. Importing this module has no side effects.

# A module's $ErrorActionPreference is snapshotted from the caller's scope at
# *import* time, not read live from the current caller on every call. If this
# module is already loaded (e.g. by a test harness, or a future long-running
# host) with a looser preference, a plain `Import-Module` (without -Force, as
# the orchestrator intentionally uses -- see its own comment) is a no-op and
# never re-snapshots it. Cmdlet calls in this module (Copy-Item, New-Item,
# etc.) must fail closed on error regardless of that history, so set it
# explicitly here rather than depending on inheritance. (Found via destructive
# -path testing on the ChannelForge sibling module: a locked destination file
# during a Copy-Item call silently produced a non-terminating error and
# reported "success" until this was added there; applied here defensively for
# the same reason, since New-TpmUpdateBackup's Copy-Item has the same shape.)
$ErrorActionPreference = 'Stop'

function Get-TpmScriptVersionIdentityFromContent {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Content)

    # Parse only. Candidate content is never executed to determine its identity.
    $tokens = $null
    $parseErrors = $null
    $scriptAst = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Candidate script cannot be parsed to verify its version identity."
    }

    $assignmentStatements = @($scriptAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst]
            }, $true))
    $identityAssignments = @(
        foreach ($assignment in $assignmentStatements) {
            foreach ($target in $assignment.GetAssignmentTargets()) {
                if ($target -isnot [System.Management.Automation.Language.VariableExpressionAst]) {
                    continue
                }
                $targetPath = [string]$target.VariablePath.UserPath
                $targetName = $targetPath
                $scopeSeparator = $targetPath.LastIndexOf(':')
                if ($scopeSeparator -ge 0) {
                    $targetName = $targetPath.Substring($scopeSeparator + 1)
                }
                if ($targetName -ieq 'ScriptVersion' -or $targetName -ieq 'ReleaseCandidateLabel') {
                    [pscustomobject]@{
                        Assignment = $assignment
                        Name = $targetName
                        Path = $targetPath
                    }
                }
            }
        }
    )

    $versionAssignments = @($identityAssignments | Where-Object { $_.Name -ieq 'ScriptVersion' })
    $labelAssignments = @($identityAssignments | Where-Object { $_.Name -ieq 'ReleaseCandidateLabel' })
    if ($versionAssignments.Count -gt 1 -or $labelAssignments.Count -gt 1) {
        throw "Candidate script contains duplicate version identity assignments."
    }

    foreach ($identityAssignment in $identityAssignments) {
        $assignment = $identityAssignment.Assignment
        if (-not [object]::ReferenceEquals($assignment.Parent, $scriptAst.EndBlock) -or
            $identityAssignment.Path -ine $identityAssignment.Name) {
            throw "Candidate version identity assignments must be direct, unscoped top-level declarations."
        }
        if ($assignment.Operator -ne [System.Management.Automation.Language.TokenKind]::Equals -or
            $assignment.Right -isnot [System.Management.Automation.Language.CommandExpressionAst] -or
            $assignment.Right.Expression -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
            throw "Candidate version identity assignments must use constant string literals."
        }
    }

    if ($versionAssignments.Count -eq 0) {
        return $null
    }
    $version = $versionAssignments[0].Assignment.Right.Expression.Value
    $label = if ($labelAssignments.Count -eq 1) {
        $labelAssignments[0].Assignment.Right.Expression.Value
    } else {
        ''
    }
    $identity = if ($label) { "$version-$label" } else { $version }
    [void](Compare-TpmVersions -VersionTextA $identity -VersionTextB $identity)
    return $identity
}

function Get-TpmLocalVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "TeknoParrot Manager script not found: $Path"
    }

    $content = [System.IO.File]::ReadAllText($Path)
    $identity = Get-TpmScriptVersionIdentityFromContent -Content $content
    if (-not $identity) {
        throw "Could not find `$ScriptVersion in $Path"
    }
    return $identity
}

function ConvertTo-TpmVersion {
# Parses the numeric base only. Release ordering must use Compare-TpmVersions
# so RC ordinals and the final-release precedence are preserved.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionText
    )

    $normalized  = ($VersionText -replace '^v', '').Trim()
    $numericPart = ($normalized -split '-')[0].Trim()
    try {
        return [version]$numericPart
    } catch {
        throw "Version '$VersionText' is not a valid System.Version value after normalization."
    }
}
function Compare-TpmVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionTextA,

        [Parameter(Mandatory)]
        [string]$VersionTextB
    )

    $pattern = '^(?i:v)?(?<base>[0-9]+(?:\.[0-9]+){1,3})(?:-(?i:RC)(?<candidate>[1-9][0-9]*))?$'
    $matchA = [regex]::Match($VersionTextA.Trim(), $pattern)
    $matchB = [regex]::Match($VersionTextB.Trim(), $pattern)
    if (-not $matchA.Success) {
        throw "Version '$VersionTextA' is not a supported manager version identity."
    }
    if (-not $matchB.Success) {
        throw "Version '$VersionTextB' is not a supported manager version identity."
    }

    $baseA = ConvertTo-TpmVersion -VersionText $matchA.Groups['base'].Value
    $baseB = ConvertTo-TpmVersion -VersionText $matchB.Groups['base'].Value
    $baseComparison = $baseA.CompareTo($baseB)
    if ($baseComparison -ne 0) {
        return $baseComparison
    }

    $candidateA = if ($matchA.Groups['candidate'].Success) { [int64]::Parse($matchA.Groups['candidate'].Value, [System.Globalization.CultureInfo]::InvariantCulture) } else { $null }
    $candidateB = if ($matchB.Groups['candidate'].Success) { [int64]::Parse($matchB.Groups['candidate'].Value, [System.Globalization.CultureInfo]::InvariantCulture) } else { $null }
    if ($null -eq $candidateA -and $null -eq $candidateB) {
        return 0
    }
    if ($null -eq $candidateA) {
        return 1
    }
    if ($null -eq $candidateB) {
        return -1
    }
    return [int]$candidateA.CompareTo($candidateB)
}

function Test-TpmReleaseAssetUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    # URI-parsed validation (not string -like/prefix matching) so the host
    # check inspects the actual parsed authority, not a substring of the raw
    # URL text. Rejects userinfo tricks (https://github.com@evil.com/...) and
    # lookalike hosts (https://github.com.evil.com/...) that a naive -like
    # prefix check could be fooled by.
    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $parsedUri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$parsedUri)) {
        return $false
    }

    if ($parsedUri.Scheme -ne 'https') {
        return $false
    }

    if ($parsedUri.Host -ne 'github.com') {
        return $false
    }

    if (-not [string]::IsNullOrEmpty($parsedUri.UserInfo)) {
        return $false
    }

    $expectedPrefix = "/$Owner/$Repository/releases/download/"
    return $parsedUri.AbsolutePath.StartsWith($expectedPrefix, [System.StringComparison]::Ordinal)
}

function Invoke-GitHubJsonRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $headers = @{ 'User-Agent' = 'TeknoParrot-Manager-Updater' }
    return Invoke-RestMethod -Uri $Uri -Headers $headers -UseBasicParsing
}

function Get-LatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    $uri = "https://api.github.com/repos/$Owner/$Repository/releases/latest"
    return Invoke-GitHubJsonRequest -Uri $uri
}

function Select-TpmUpdateAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Release,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter(Mandatory)]
        [string]$Owner,

        [Parameter(Mandatory)]
        [string]$Repository
    )

    $asset = @($Release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1)
    if (-not $asset) {
        throw "Latest release '$($Release.tag_name)' does not contain an asset matching $Pattern"
    }

    if (-not (Test-TpmReleaseAssetUrl -Url $asset.browser_download_url -Owner $Owner -Repository $Repository)) {
        throw "Refusing non-release GitHub asset URL: $($asset.browser_download_url)"
    }

    return $asset
}

function Assert-TpmWritableTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Move-Item -Force (and Copy-Item -Force) silently clear the ReadOnly
    # attribute and replace the file anyway rather than failing (verified
    # empirically during destructive-path testing). A read-only target is
    # never overridden here -- the update is refused with an actionable
    # message so the user can decide whether to unlock it.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    $item = Get-Item -LiteralPath $Path -Force
    if ($item.IsReadOnly) {
        throw "Refusing to update: '$Path' is marked read-only. Remove the read-only attribute (e.g. Set-ItemProperty -LiteralPath '$Path' -Name IsReadOnly -Value `$false) and re-run the update; this updater will not silently clear it."
    }
}

function New-TpmUpdateBackup {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Helper is called from the updater apply path after the orchestrator has already made the user-facing confirmation decision.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $repoRoot = Split-Path -Parent $Path
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupDir = Join-Path (Join-Path $repoRoot 'UpdateBackups') $stamp
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $backupPath = Join-Path $backupDir (Split-Path -Leaf $Path)
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force

    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw "Backup creation failed: $backupPath"
    }

    return $backupPath
}

function Write-TpmDownloadProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][Int64]$DownloadedBytes,
        [Int64]$TotalBytes = 0,
        [Parameter(Mandatory)][TimeSpan]$Elapsed,
        [switch]$Complete
    )

    $activity = "Downloading $Label"
    if ($Complete) {
        [Console]::Write(("`r[{0}] complete.                    `n" -f $activity))
        return
    }

    $downloadedMb = [Math]::Round($DownloadedBytes / 1MB, 1)
    $seconds = [Math]::Max($Elapsed.TotalSeconds, 0.001)
    $mbps = [Math]::Round(($DownloadedBytes / 1MB) / $seconds, 2)
    if ($TotalBytes -gt 0) {
        $totalMb = [Math]::Round($TotalBytes / 1MB, 1)
        $percent = [Math]::Min(100, [Math]::Max(0, [Math]::Round(($DownloadedBytes / $TotalBytes) * 100, 0)))
        $etaText = ''
        if ($DownloadedBytes -gt 0 -and $mbps -gt 0) {
            $remainingSeconds = (($TotalBytes - $DownloadedBytes) / 1MB) / $mbps
            if ($remainingSeconds -ge 0) {
                $etaText = " ETA {0}" -f ([TimeSpan]::FromSeconds($remainingSeconds).ToString("mm\:ss"))
            }
        }
        [Console]::Write(("`r[{0}] {1}: {2}%  {3}/{4} MB  {5} MB/s{6}" -f $activity, $Method, $percent, $downloadedMb, $totalMb, $mbps, $etaText))
    } else {
        [Console]::Write(("`r[{0}] {1}: {2} MB downloaded  {3} MB/s" -f $activity, $Method, $downloadedMb, $mbps))
    }
}

function Test-TpmDownloadBitsAvailable {
    [CmdletBinding()]
    param()

    $bitsCommand = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    if (-not $bitsCommand) { return $false }
    $bitsService = try { Get-Service -Name BITS -ErrorAction Stop } catch { $null }
    return ($null -ne $bitsService -and $bitsService.Status -eq 'Running')
}

function Invoke-TpmDownloadBitTransfer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DownloadUrl,
        [Parameter(Mandatory)][string]$TempPath,
        [Parameter(Mandatory)][string]$Label
    )

    $job = $null
    $progressWatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $job = Start-BitsTransfer -Source $DownloadUrl -Destination $TempPath `
            -Description "TeknoParrot Manager $Label" `
            -DisplayName "Downloading $Label..." `
            -Asynchronous `
            -ErrorAction Stop
        while ($job.JobState -in @('Connecting', 'Transferring', 'Queued', 'TransientError')) {
            Write-TpmDownloadProgress -Label $Label -Method 'BITS' -DownloadedBytes ([int64]$job.BytesTransferred) -TotalBytes ([int64]$job.BytesTotal) -Elapsed $progressWatch.Elapsed
            Start-Sleep -Milliseconds 500
            $job = Get-BitsTransfer -JobId $job.JobId -ErrorAction Stop
        }
        if ($job.JobState -ne 'Transferred') {
            throw "BITS transfer ended with state $($job.JobState)."
        }
        Complete-BitsTransfer -BitsJob $job -ErrorAction Stop
        $bytes = (Get-Item -LiteralPath $TempPath -ErrorAction Stop).Length
        Write-TpmDownloadProgress -Label $Label -Method 'BITS' -DownloadedBytes $bytes -TotalBytes $bytes -Elapsed $progressWatch.Elapsed -Complete
    } catch {
        if ($job) {
            try {
                Remove-BitsTransfer -BitsJob $job -Confirm:$false -ErrorAction SilentlyContinue
            } catch {
                Write-Verbose "BITS cleanup failed: $_"
            }
        }
        throw
    }
}

function Invoke-TpmDownloadHttpClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DownloadUrl,
        [Parameter(Mandatory)][string]$TempPath,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not ('System.Net.Http.HttpClient' -as [type])) {
        Add-Type -AssemblyName System.Net.Http
    }

    $client = $null
    $response = $null
    $inputStream = $null
    $outputStream = $null
    try {
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromMinutes(30)
        $response = $client.GetAsync($DownloadUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        [void]$response.EnsureSuccessStatusCode()
        $totalBytes = if ($response.Content.Headers.ContentLength.HasValue) { [int64]$response.Content.Headers.ContentLength.Value } else { [int64]0 }
        $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream = [System.IO.File]::Create($TempPath)
        $buffer = New-Object byte[] 1048576
        $downloadedBytes = [int64]0
        $progressWatch = [System.Diagnostics.Stopwatch]::StartNew()
        while (($read = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outputStream.Write($buffer, 0, $read)
            $downloadedBytes += $read
            Write-TpmDownloadProgress -Label $Label -Method 'HttpClient' -DownloadedBytes $downloadedBytes -TotalBytes $totalBytes -Elapsed $progressWatch.Elapsed
        }
        Write-TpmDownloadProgress -Label $Label -Method 'HttpClient' -DownloadedBytes $downloadedBytes -TotalBytes $totalBytes -Elapsed $progressWatch.Elapsed -Complete
    } finally {
        if ($outputStream) { $outputStream.Dispose() }
        if ($inputStream) { $inputStream.Dispose() }
        if ($response) { $response.Dispose() }
        if ($client) { $client.Dispose() }
    }
}

function Invoke-TpmDownloadWebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DownloadUrl,
        [Parameter(Mandatory)][string]$TempPath,
        [Parameter(Mandatory)][string]$Label
    )

    Write-TpmDownloadProgress -Label $Label -Method 'Invoke-WebRequest' -DownloadedBytes 0 -TotalBytes 0 -Elapsed ([TimeSpan]::Zero)
    $previousProgressPreference = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempPath -UseBasicParsing -ErrorAction Stop
    } finally {
        $ProgressPreference = $previousProgressPreference
    }
    $bytes = (Get-Item -LiteralPath $TempPath -ErrorAction Stop).Length
    Write-TpmDownloadProgress -Label $Label -Method 'Invoke-WebRequest' -DownloadedBytes $bytes -TotalBytes $bytes -Elapsed ([TimeSpan]::Zero) -Complete
}

function Test-TpmDownloadedFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Int64]$ExpectedBytes = 0
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.Length -le 0) { return $false }
    if ($ExpectedBytes -gt 0 -and $item.Length -ne $ExpectedBytes) { return $false }
    return $true
}

function Get-TpmHttpStatusCodeFromError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ErrorRecord
    )

    if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.StatusCode) {
        try { return [int]$ErrorRecord.Exception.Response.StatusCode } catch {}
    }
    if ($ErrorRecord.Exception.Message -match '\((\d{3})\)') { return [int]$Matches[1] }
    if ($ErrorRecord.Exception.Message -match ':\s*(\d{3})\s') { return [int]$Matches[1] }
    return 0
}

function Invoke-TpmDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DownloadUrl,
        [Parameter(Mandatory)][string]$DestinationPath,
        [Int64]$ExpectedBytes = 0,
        [string]$Label = 'download'
    )

    $saveDir = Split-Path -Parent $DestinationPath
    if ([string]::IsNullOrWhiteSpace($saveDir)) { $saveDir = (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $saveDir -PathType Container)) {
        New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
    }

    # Kept in lockstep with TeknoParrot-Manager.ps1's own Invoke-TpmDownload --
    # see that function's comment for why the temp/partial file lands on local
    # disk instead of next to $DestinationPath, which can be a network-mapped
    # drive. Falls back to $saveDir if local temp isn't writable.
    $tempDir = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($tempDir) -or -not (Test-Path -LiteralPath $tempDir -PathType Container)) {
        $tempDir = $saveDir
    }
    $tempPath = Join-Path $tempDir ('.{0}.{1}.partial' -f ([System.IO.Path]::GetFileName($DestinationPath)), ([guid]::NewGuid().ToString('N')))
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $methodUsed = $null
    try {
        $bitsSucceeded = $false
        if (Test-TpmDownloadBitsAvailable) {
            try {
                Invoke-TpmDownloadBitTransfer -DownloadUrl $DownloadUrl -TempPath $tempPath -Label $Label
                $bitsSucceeded = $true
                $methodUsed = 'BITS'
            } catch {
                Write-Verbose "${Label}: BITS transfer failed (${_}), trying HttpClient."
                try {
                    if (Test-Path -LiteralPath $tempPath) { [System.IO.File]::Delete($tempPath) }
                } catch {
                    Write-Verbose "Partial cleanup after BITS failure failed: $_"
                }
            }
        }

        if (-not $bitsSucceeded) {
            $httpClientSucceeded = $false
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                try {
                    Invoke-TpmDownloadHttpClient -DownloadUrl $DownloadUrl -TempPath $tempPath -Label $Label
                    $methodUsed = 'HttpClient'
                    $httpClientSucceeded = $true
                    break
                } catch {
                    $statusCode = Get-TpmHttpStatusCodeFromError -ErrorRecord $_
                    Write-Verbose "${Label}: HttpClient attempt $attempt failed: $_"
                    try {
                        if (Test-Path -LiteralPath $tempPath) { [System.IO.File]::Delete($tempPath) }
                    } catch {
                        Write-Verbose "Partial cleanup after HttpClient failure failed: $_"
                    }
                    if ($attempt -ge 3 -or ($statusCode -ge 400 -and $statusCode -lt 500)) {
                        Write-Verbose "${Label}: HttpClient download failed, trying Invoke-WebRequest."
                        break
                    }
                    Start-Sleep -Seconds 2
                }
            }

            if (-not $httpClientSucceeded) {
                for ($attempt = 1; $attempt -le 3; $attempt++) {
                    try {
                        Invoke-TpmDownloadWebRequest -DownloadUrl $DownloadUrl -TempPath $tempPath -Label $Label
                        $methodUsed = 'Invoke-WebRequest'
                        break
                    } catch {
                        $statusCode = Get-TpmHttpStatusCodeFromError -ErrorRecord $_
                        Write-Verbose "${Label}: Invoke-WebRequest attempt $attempt failed: $_"
                        try {
                            if (Test-Path -LiteralPath $tempPath) { [System.IO.File]::Delete($tempPath) }
                        } catch {
                            Write-Verbose "Partial cleanup after Invoke-WebRequest failure failed: $_"
                        }
                        if ($attempt -ge 3 -or ($statusCode -ge 400 -and $statusCode -lt 500)) { throw }
                        Start-Sleep -Seconds 2
                    }
                }
            }
        }

        if (-not (Test-TpmDownloadedFile -Path $tempPath -ExpectedBytes $ExpectedBytes)) {
            throw "Downloaded file is incomplete or empty."
        }

        Move-Item -LiteralPath $tempPath -Destination $DestinationPath -Force -ErrorAction Stop
        $stopwatch.Stop()
        $bytes = (Get-Item -LiteralPath $DestinationPath -ErrorAction Stop).Length
        $mb = [Math]::Round($bytes / 1MB, 2)
        $seconds = [Math]::Max($stopwatch.Elapsed.TotalSeconds, 0.001)
        $mbps = [Math]::Round(($bytes / 1MB) / $seconds, 2)
        Write-Verbose ("{0}: download method={1} size={2}MB elapsed={3:n1}s speed={4}MB/s" -f $Label, $methodUsed, $mb, $stopwatch.Elapsed.TotalSeconds, $mbps)
        return $true
    } catch {
        $stopwatch.Stop()
        try {
            if (Test-Path -LiteralPath $tempPath) { [System.IO.File]::Delete($tempPath) }
        } catch {
            Write-Verbose "Partial cleanup after download failure failed: $_"
        }
        throw
    }
}

function Save-TpmReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Asset
    )

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-update-" + [guid]::NewGuid().ToString('N') + '.zip')
    $expectedBytes = 0
    if ($Asset.PSObject.Properties.Name -contains 'size') {
        $expectedBytes = [int64]$Asset.size
    }
    [void](Invoke-TpmDownload -DownloadUrl $Asset.browser_download_url -DestinationPath $tempPath -ExpectedBytes $expectedBytes -Label 'TPM update package')

    $downloaded = Get-Item -LiteralPath $tempPath -ErrorAction Stop
    if ($downloaded.Length -le 0) {
        throw "Downloaded update asset is empty: $tempPath"
    }

    return $tempPath
}

function Expand-TpmReleaseZipEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ZipPath,

        [Parameter(Mandatory)]
        [string]$EntryName,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
        throw "Downloaded release asset not found: $ZipPath"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue

    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq $EntryName } | Select-Object -First 1
        if (-not $entry) {
            throw "Release asset '$ZipPath' does not contain expected entry '$EntryName'."
        }

        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $DestinationPath, $true)
    } finally {
        $zip.Dispose()
    }

    return $DestinationPath
}

function Test-TpmExtractedScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedVersion
    )

    # Defense-in-depth before the extracted file ever replaces the live
    # script: verify it exists, is non-empty, is not the raw zip container
    # (a bug that would move zip bytes over the .ps1 if extraction were ever
    # skipped or broken upstream), and looks like TeknoParrot-Manager.ps1
    # rather than an unrelated or truncated file.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Extracted script not found: $Path"
    }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) {
        throw "Extracted script is empty: $Path"
    }

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B) {
        throw "Extracted script begins with a zip signature (PK) -- refusing to install: $Path"
    }

    # Windows PowerShell 5.1 interprets BOM-less script bytes as Windows-1252.
    # Require ASCII so AST validation and installed-source interpretation agree.
    foreach ($byte in $bytes) {
        if ($byte -gt 0x7F) {
            throw "Extracted script contains non-ASCII bytes -- refusing to install: $Path"
        }
    }
    $content = [System.Text.Encoding]::ASCII.GetString($bytes)

    if ($content -notmatch 'TeknoParrot Manager') {
        throw "Extracted script does not contain the expected 'TeknoParrot Manager' marker: $Path"
    }

    $identity = Get-TpmScriptVersionIdentityFromContent -Content $content
    if (-not $identity) {
        throw "Extracted script does not contain a top-level `$ScriptVersion assignment: $Path"
    }
    if ((Compare-TpmVersions -VersionTextA $identity -VersionTextB $ExpectedVersion) -ne 0) {
        throw "Extracted script identity '$identity' does not match release tag '$ExpectedVersion'."
    }

    return $true
}

function Enable-TpmTls12 {
    [CmdletBinding()]
    param()

    # Windows PowerShell 5.1 on older .NET Framework builds does not always
    # default to TLS 1.2, which causes GitHub API/download calls to fail with
    # "Could not create SSL/TLS secure channel." Only Windows PowerShell needs
    # this; PowerShell 6+ already defaults to modern TLS.
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Warning "Could not enable TLS 1.2: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function @(
    'Get-TpmLocalVersion',
    'ConvertTo-TpmVersion',
    'Compare-TpmVersions',
    'Test-TpmReleaseAssetUrl',
    'Invoke-GitHubJsonRequest',
    'Get-LatestRelease',
    'Select-TpmUpdateAsset',
    'Assert-TpmWritableTarget',
    'New-TpmUpdateBackup',
    'Save-TpmReleaseAsset',
    'Expand-TpmReleaseZipEntry',
    'Test-TpmExtractedScript',
    'Enable-TpmTls12'
)
