[CmdletBinding()]
param(
    [string]$TeknoParrotRoot = '',
    [string]$InstalledGameProfilesPath = '',
    [string]$InstalledUserProfilesPath = '',
    [string]$UpstreamProfileRoot = '',
    [string]$UpstreamCommitSha = '',
    [string]$UpstreamVersion = '',
    [string]$InstalledTeknoParrotVersion = '',
    [string]$EggmanDatZip = '',
    [string]$DatFilePath = '',
    [string]$FixtureRoot = '',
    [string]$SnapshotId = '',
    [string]$CapturedAtUtc = '',
    [string]$OutputRoot = ''
)

$script:TpmSupportPostureClassifications = @(
    'AUTOMATED_SAFE', 'REVIEW_MANUAL', 'BLOCKED_UNSUPPORTED', 'UNCLASSIFIED'
)
$script:TpmSupportPostureLayouts = @(
    'CHD_ONLY',
    'CHD_PLUS_EXECUTABLE_SAME_FOLDER',
    'CHD_PLUS_EXECUTABLE_PLUS_CONTENT_SUBFOLDER',
    'CHD_IN_CONTENT_OR_MEDIA_SUBFOLDER',
    'CHD_NESTED_ONE_LEVEL',
    'CHD_NESTED_MULTIPLE_LEVELS',
    'MULTIPLE_CHD_CANDIDATES',
    'CHD_PLUS_SEPARATE_LAUNCHER',
    'CHD_PRESENT_WRONG_DIRECTORY_SELECTED',
    'CHD_EXPECTED_GAME_DIRECTORY_MISSING',
    'CHD_REQUIRED_BUT_ABSENT',
    'CHD_PRESENT_BUT_PROFILE_MEDIA_RULE_UNKNOWN',
    'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT',
    'MEDIA_LAYOUT_CONFLICTS_WITH_PROFILE',
    'LAYOUT_UNOBSERVABLE'
)

function Write-TpmSupportUtf8NoBom {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
    $parent = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void][System.IO.Directory]::CreateDirectory($parent)
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertTo-TpmSupportFullPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/') } catch { return $null }
}

function Test-TpmSupportPathInside {
    param([string]$Child, [string]$Parent)
    $childFull = ConvertTo-TpmSupportFullPath $Child
    $parentFull = ConvertTo-TpmSupportFullPath $Parent
    if (-not $childFull -or -not $parentFull) { return $false }
    if ($childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $childFull.StartsWith($parentFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-TpmSupportNoReparsePath {
    param([string]$Path)
    $current = ConvertTo-TpmSupportFullPath $Path
    if (-not $current) { return $false }
    try {
        while ($current) {
            if (Test-Path -LiteralPath $current) {
                $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
            }
            $parent = [System.IO.Path]::GetDirectoryName($current)
            if (-not $parent -or $parent.Equals($current, [System.StringComparison]::OrdinalIgnoreCase)) {
                $current = $null
            } else {
                $current = $parent.TrimEnd('\', '/')
            }
        }
        return $true
    } catch { return $false }
}

function Get-TpmSupportSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $sha = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        if ($sha) { $sha.Dispose() }
    }
}

function Get-TpmSupportXmlDocument {
    param([Parameter(Mandatory = $true)][string]$Path)
    $doc = New-Object System.Xml.XmlDocument
    $doc.XmlResolver = $null
    $doc.Load($Path)
    return $doc
}

function Get-TpmSupportXmlText {
    param([System.Xml.XmlNode]$Root, [string]$Name)
    if (-not $Root) { return '' }
    $node = $Root.SelectSingleNode('/GameProfile/' + $Name)
    if ($node) { return ([string]$node.InnerText).Trim() }
    return ''
}

function Get-TpmSupportExecutableAlternatives {
    param([string]$Value)
    return @($Value -split '[;|]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-TpmSupportTitle {
    param([System.Xml.XmlNode]$Root, [string]$Fallback)
    foreach ($name in @('GameName', 'GameNameInternal', 'ProfileName')) {
        $value = Get-TpmSupportXmlText -Root $Root -Name $name
        if ($value) { return $value }
    }
    return $Fallback
}

function Get-TpmSupportPathEvidence {
    param([System.Xml.XmlNode]$Root)
    $values = New-Object System.Collections.Generic.List[string]
    if (-not $Root) { return @() }
    foreach ($node in @($Root.SelectNodes('//*'))) {
        if ($node.Name -match '(?i)path|media|content|chd|rom|disc') {
            $text = ([string]$node.InnerText).Trim()
            if ($text -and $values -notcontains $text) { [void]$values.Add($text) }
        }
    }
    return $values.ToArray()
}

function Get-TpmSupportExtensions {
    param([string[]]$Candidates)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in @($Candidates)) {
        try { $ext = [System.IO.Path]::GetExtension($candidate).ToLowerInvariant() } catch { $ext = '' }
        if ($ext -and $result -notcontains $ext) { [void]$result.Add($ext) }
    }
    return $result.ToArray()
}

function New-TpmSupportMalformedProfile {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File, [string]$SourceType, [string]$SourceId, [string]$ErrorText)
    return [ordered]@{
        ProfileCode = $File.BaseName
        ProfileFileName = $File.Name
        ProfileXmlSha256 = $(try { Get-TpmSupportSha256 -Path $File.FullName } catch { '' })
        GameTitle = $File.BaseName
        VariantTitle = ''
        EmulationProfile = ''
        EmulatorType = ''
        GameGenreInternal = ''
        ProfileRevision = $null
        Executable = [ordered]@{
            Raw = ''
            PrimaryCandidates = @()
            SecondaryCandidates = @()
            HasTwoExecutables = $false
            LaunchSecondExecutableFirst = $false
            SecondExecutableArguments = ''
        }
        PathRules = [ordered]@{
            GamePath = ''
            GamePath2 = ''
            ContentDirectories = @()
            MediaDirectories = @()
        }
        Media = [ordered]@{
            ChdRequirement = 'UNKNOWN'
            RequiredExtensions = @()
            MultipleChdAllowed = $false
            MediaRuleEvidence = @()
        }
        Ownership = [ordered]@{
            TeknoParrotOwnedFields = @()
            TpmReadableFields = @()
            TpmWritableFields = @()
            ManualTeknoParrotUiRequired = $true
        }
        Classification = 'BLOCKED_UNSUPPORTED'
        ReasonCode = 'MALFORMED_PROFILE_XML'
        BeginnerAction = 'Open TeknoParrotUI and repair or reinstall this game profile before using TPM.'
        FixtureIds = @()
        Evidence = [ordered]@{
            SourceIds = @($SourceId)
            SourceType = $SourceType
            CapturedAtUtc = ''
            ProfileSha256 = $(try { Get-TpmSupportSha256 -Path $File.FullName } catch { '' })
        }
        SourcePath = $File.FullName
        SourceType = $SourceType
        SourceId = $SourceId
        ParseError = $ErrorText
        IsMalformed = $true
    }
}

function Get-TpmSupportProfileRecord {
    param([Parameter(Mandatory = $true)][System.IO.FileInfo]$File, [string]$SourceType, [string]$SourceId)
    try {
        $doc = Get-TpmSupportXmlDocument -Path $File.FullName
        $root = $doc.SelectSingleNode('/GameProfile')
        if (-not $root) { throw 'missing GameProfile root' }
        $exeRaw = Get-TpmSupportXmlText -Root $root -Name 'ExecutableName'
        $exe2Raw = Get-TpmSupportXmlText -Root $root -Name 'ExecutableName2'
        $exe = Get-TpmSupportExecutableAlternatives $exeRaw
        $exe2 = Get-TpmSupportExecutableAlternatives $exe2Raw
        $fieldNames = @($root.ChildNodes | Where-Object { $_.NodeType -eq [System.Xml.XmlNodeType]::Element } | ForEach-Object Name | Sort-Object -Unique)
        $knownOwned = @('GamePath', 'GamePath2', 'ConfigValues', 'JoystickButtons', 'EmulationProfile', 'ExecutableName', 'ExecutableName2')
        $owned = @($fieldNames | Where-Object { $knownOwned -contains $_ })
        $pathEvidence = @(Get-TpmSupportPathEvidence -Root $root)
        $chdEvidence = @($pathEvidence | Where-Object { $_ -match '(?i)\.chd|chd|media|content' })
        $chdRequirement = if (@($exe | Where-Object { $_ -match '(?i)\.chd$' }).Count -gt 0) { 'EXPLICIT_PROFILE_CHD_TARGET' } elseif ($chdEvidence.Count -gt 0) { 'PROFILE_MEDIA_EVIDENCE' } else { 'UNKNOWN' }
        $revisionText = Get-TpmSupportXmlText -Root $root -Name 'GameProfileRevision'
        $revision = $null
        if ($revisionText -match '^\d+$') { $revision = [int]$revisionText }
        return [ordered]@{
            ProfileCode = $File.BaseName
            ProfileFileName = $File.Name
            ProfileXmlSha256 = Get-TpmSupportSha256 -Path $File.FullName
            GameTitle = Get-TpmSupportTitle -Root $root -Fallback $File.BaseName
            VariantTitle = Get-TpmSupportXmlText -Root $root -Name 'GameVersion'
            EmulationProfile = Get-TpmSupportXmlText -Root $root -Name 'EmulationProfile'
            EmulatorType = Get-TpmSupportXmlText -Root $root -Name 'EmulatorType'
            GameGenreInternal = Get-TpmSupportXmlText -Root $root -Name 'GameGenreInternal'
            ProfileRevision = $revision
            Executable = [ordered]@{
                Raw = $exeRaw
                PrimaryCandidates = $exe
                SecondaryCandidates = $exe2
                HasTwoExecutables = ((Get-TpmSupportXmlText -Root $root -Name 'HasTwoExecutables') -match '^(?i:true|1)$')
                LaunchSecondExecutableFirst = ((Get-TpmSupportXmlText -Root $root -Name 'LaunchSecondExecutableFirst') -match '^(?i:true|1)$')
                SecondExecutableArguments = Get-TpmSupportXmlText -Root $root -Name 'SecondExecutableArguments'
            }
            PathRules = [ordered]@{
                GamePath = Get-TpmSupportXmlText -Root $root -Name 'GamePath'
                GamePath2 = Get-TpmSupportXmlText -Root $root -Name 'GamePath2'
                ContentDirectories = @($pathEvidence | Where-Object { $_ -match '(?i)content' })
                MediaDirectories = @($pathEvidence | Where-Object { $_ -match '(?i)media|chd|rom|disc' })
            }
            Media = [ordered]@{
                ChdRequirement = $chdRequirement
                RequiredExtensions = @(Get-TpmSupportExtensions -Candidates $exe)
                MultipleChdAllowed = ((Get-TpmSupportXmlText -Root $root -Name 'MultipleChdAllowed') -match '^(?i:true|1)$')
                MediaRuleEvidence = $chdEvidence
            }
            Ownership = [ordered]@{
                TeknoParrotOwnedFields = $owned
                TpmReadableFields = $fieldNames
                TpmWritableFields = @()
                ManualTeknoParrotUiRequired = $false
            }
            Classification = 'UNCLASSIFIED'
            ReasonCode = 'NOT_CLASSIFIED'
            BeginnerAction = ''
            FixtureIds = @()
            Evidence = [ordered]@{
                SourceIds = @($SourceId)
                SourceType = $SourceType
                CapturedAtUtc = ''
                ProfileSha256 = Get-TpmSupportSha256 -Path $File.FullName
            }
            SourcePath = $File.FullName
            SourceType = $SourceType
            SourceId = $SourceId
            ParseError = ''
            IsMalformed = $false
        }
    } catch {
        return New-TpmSupportMalformedProfile -File $File -SourceType $SourceType -SourceId $SourceId -ErrorText $_.Exception.Message
    }
}

function Get-TpmSupportProfileSource {
    param([string]$Root, [string]$SourceType, [string]$SourceId, [string]$CapturedAtUtc)
    $source = [ordered]@{
        SourceType = $SourceType
        SourceId = $SourceId
        RootLabel = $SourceType
        Available = $false
        ProfileCount = 0
        DuplicateProfileStems = @()
        MalformedProfileStems = @()
        Profiles = @()
        CapturedAtUtc = $CapturedAtUtc
    }
    $rootFull = ConvertTo-TpmSupportFullPath $Root
    if (-not $rootFull -or -not (Test-Path -LiteralPath $rootFull -PathType Container) -or -not (Test-TpmSupportNoReparsePath -Path $rootFull)) {
        return [pscustomobject]$source
    }
    $source.Available = $true
    $seen = @{}
    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $rootFull -Filter '*.xml' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $key = $file.BaseName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            $source.DuplicateProfileStems += $file.BaseName
        } else { $seen[$key] = $true }
        $record = Get-TpmSupportProfileRecord -File $file -SourceType $SourceType -SourceId $SourceId
        $record.Evidence.CapturedAtUtc = $CapturedAtUtc
        if ($record.IsMalformed) { $source.MalformedProfileStems += $record.ProfileCode }
        [void]$profiles.Add($record)
    }
    $source.Profiles = @($profiles | Sort-Object ProfileCode)
    $source.ProfileCount = $source.Profiles.Count
    $source.DuplicateProfileStems = @($source.DuplicateProfileStems | Sort-Object -Unique)
    $source.MalformedProfileStems = @($source.MalformedProfileStems | Sort-Object -Unique)
    return [pscustomobject]$source
}

function Get-TpmSupportDuplicateProfileStems {
    param([Parameter(Mandatory = $true)][object[]]$Profiles)
    $groups = @{}
    foreach ($profileRecord in @($Profiles)) {
        if ($profileRecord -and -not [string]::IsNullOrWhiteSpace([string]$profileRecord.ProfileCode)) {
            $key = ([string]$profileRecord.ProfileCode).ToLowerInvariant()
            if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.Generic.List[string] }
            [void]$groups[$key].Add([string]$profileRecord.ProfileCode)
        }
    }
    return @($groups.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 } | ForEach-Object { $_.Value.ToArray() } | ForEach-Object { $_ } | Sort-Object -Unique)
}

function Get-TpmSupportUserProfileObservations {
    param([string]$Root, [string]$CapturedAtUtc)
    $result = New-Object System.Collections.Generic.List[object]
    $rootFull = ConvertTo-TpmSupportFullPath $Root
    if (-not $rootFull -or -not (Test-Path -LiteralPath $rootFull -PathType Container) -or -not (Test-TpmSupportNoReparsePath -Path $rootFull)) { return @() }
    foreach ($file in @(Get-ChildItem -LiteralPath $rootFull -Filter '*.xml' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $record = [ordered]@{
            ProfileCode = $file.BaseName
            ProfileFileName = $file.Name
            ProfileXmlSha256 = $(try { Get-TpmSupportSha256 -Path $file.FullName } catch { '' })
            GamePath = ''
            GamePath2 = ''
            RegistrationState = 'UNREADABLE'
            Source = 'InstalledUserProfiles'
            CapturedAtUtc = $CapturedAtUtc
            Error = ''
        }
        try {
            $doc = Get-TpmSupportXmlDocument -Path $file.FullName
            $profileRoot = $doc.SelectSingleNode('/GameProfile')
            if (-not $profileRoot) { throw 'missing GameProfile root' }
            $record.GamePath = Get-TpmSupportXmlText -Root $profileRoot -Name 'GamePath'
            $record.GamePath2 = Get-TpmSupportXmlText -Root $profileRoot -Name 'GamePath2'
            $record.RegistrationState = if ($record.GamePath) { 'REGISTERED_PATH_PRESENT' } else { 'REGISTERED_PATH_EMPTY' }
        } catch { $record.RegistrationState = 'MALFORMED_PROFILE'; $record.Error = $_.Exception.Message }
        [void]$result.Add([pscustomobject]$record)
    }
    return @($result.ToArray())
}

function Get-TpmSupportDatRecordsFromStream {
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)
    $records = New-Object System.Collections.Generic.List[object]
    $settings = New-Object System.Xml.XmlReaderSettings
    $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $reader = [System.Xml.XmlReader]::Create($Stream, $settings)
    $gameName = ''
    $profileCode = ''
    $executable = ''
    try {
        while ($reader.Read()) {
            if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
                if ($reader.Name -eq 'game') {
                    $gameName = [string]$reader.GetAttribute('name')
                    $profileCode = ''
                    $executable = ''
                } elseif ($reader.Name -eq 'GameProfile') {
                    $profileCode = $reader.ReadElementContentAsString().Trim()
                } elseif ($reader.Name -eq 'Executable') {
                    $executable = $reader.ReadElementContentAsString().Trim()
                }
            } elseif ($reader.NodeType -eq [System.Xml.XmlNodeType]::EndElement -and $reader.Name -eq 'game') {
                if ($gameName -and $profileCode) {
                    [void]$records.Add([ordered]@{
                        OriginalName = $gameName.Trim()
                        ProfileCode = $profileCode
                        Executable = $executable
                    })
                }
            }
        }
    } finally { $reader.Close() }
    return @($records.ToArray())
}

function Get-TpmSupportDatSummary {
    param([string]$ZipPath, [string]$DatPath, [string]$CapturedAtUtc)
    $summary = [ordered]@{
        Status = 'NOT_SUPPLIED'
        SourceType = ''
        SourceId = ''
        SourceSha256 = ''
        CapturedAtUtc = $CapturedAtUtc
        EntryCount = 0
        Entries = @()
        Error = ''
    }
    $path = if ($ZipPath) { $ZipPath } else { $DatPath }
    if ([string]::IsNullOrWhiteSpace($path)) { return [pscustomobject]$summary }
    $full = ConvertTo-TpmSupportFullPath $path
    if (-not $full -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $summary.Status = 'SOURCE_UNAVAILABLE'
        $summary.SourceId = [System.IO.Path]::GetFileName($path)
        return [pscustomobject]$summary
    }
    try {
        $summary.SourceSha256 = Get-TpmSupportSha256 -Path $full
        if ([System.IO.Path]::GetExtension($full).ToLowerInvariant() -eq '.zip') {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $archive = [System.IO.Compression.ZipFile]::OpenRead($full)
            try {
                $entries = @($archive.Entries | Where-Object { $_.Name -like '*RomVault*.dat' } | Sort-Object FullName)
                $all = New-Object System.Collections.Generic.List[object]
                foreach ($entry in $entries) {
                    $stream = $entry.Open()
                    try { foreach ($row in @(Get-TpmSupportDatRecordsFromStream -Stream $stream)) { [void]$all.Add($row) } } finally { $stream.Close() }
                }
                $summary.SourceType = 'EggmanRomVaultDatZip'
                $summary.SourceId = [System.IO.Path]::GetFileName($full)
                $summary.Entries = @($all | Sort-Object OriginalName, ProfileCode)
                $summary.EntryCount = $summary.Entries.Count
                $summary.Status = 'READ'
            } finally { $archive.Dispose() }
        } else {
            $stream = [System.IO.File]::OpenRead($full)
            try { $summary.Entries = @(Get-TpmSupportDatRecordsFromStream -Stream $stream) } finally { $stream.Close() }
            $summary.SourceType = 'StandaloneDat'
            $summary.SourceId = [System.IO.Path]::GetFileName($full)
            $summary.EntryCount = $summary.Entries.Count
            $summary.Status = 'READ'
        }
    } catch {
        $summary.Status = 'READ_FAILED'
        $summary.SourceId = [System.IO.Path]::GetFileName($full)
        $summary.Error = $_.Exception.Message
    }
    return [pscustomobject]$summary
}

function Get-TpmSupportFixtureManifest {
    param([string]$FixtureRoot)
    if ([string]::IsNullOrWhiteSpace($FixtureRoot)) { return @() }
    $manifestPath = Join-Path $FixtureRoot 'fixtures.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return @() }
    try {
        $raw = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($raw.fixtures) { return @($raw.fixtures) }
        return @($raw)
    } catch { throw ('Fixture manifest is invalid: ' + $_.Exception.Message) }
}

function Get-TpmSupportRelativePath {
    param([string]$Path, [string]$Root)
    $full = ConvertTo-TpmSupportFullPath $Path
    $rootFull = ConvertTo-TpmSupportFullPath $Root
    if (-not $full -or -not $rootFull -or -not (Test-TpmSupportPathInside -Child $full -Parent $rootFull)) { return '' }
    return $full.Substring($rootFull.Length).TrimStart('\', '/') -replace '\\', '/'
}

function Test-TpmSupportProtectedPath {
    param([string]$Path)
    $full = ConvertTo-TpmSupportFullPath $Path
    if (-not $full) { return $false }
    return ($full -match '(?i)\\Windows(\\|$)|\\Program Files( \\(x86\\))?(\\|$)')
}

function Get-TpmSupportLayoutObservation {
    param([string]$FixtureRoot, [object]$Fixture, [object]$ProfileRecord)
    $relativeRoot = [string]$Fixture.relativeRoot
    $gameRoot = if ($relativeRoot) { Join-Path $FixtureRoot $relativeRoot } else { '' }
    $observation = [ordered]@{
        FixtureId = [string]$Fixture.id
        ProfileCode = [string]$Fixture.profileCode
        GameRoot = $relativeRoot
        LayoutClass = 'LAYOUT_UNOBSERVABLE'
        ChdFiles = @()
        ExecutableCandidates = @()
        CandidateCount = 0
        SelectedPath = [string]$Fixture.selectedPath
        PathSafety = 'NOT_CHECKED'
        MediaRuleEvidence = @()
        ExpectedClassification = [string]$Fixture.expectedClassification
        ExpectedReasonCode = [string]$Fixture.expectedReasonCode
        Error = ''
    }
    if (-not $gameRoot -or -not (Test-Path -LiteralPath $gameRoot -PathType Container)) {
        $observation.LayoutClass = 'CHD_EXPECTED_GAME_DIRECTORY_MISSING'
        $observation.PathSafety = 'MISSING'
        $observation.Error = 'game directory is missing'
        return [pscustomobject]$observation
    }
    $rootFull = ConvertTo-TpmSupportFullPath $gameRoot
    if (-not (Test-TpmSupportNoReparsePath -Path $rootFull)) {
        $observation.PathSafety = 'REPARSE_OR_INACCESSIBLE'
        $observation.LayoutClass = 'LAYOUT_UNOBSERVABLE'
        $observation.Error = 'game directory is reparse-backed or inaccessible'
        return [pscustomobject]$observation
    }
    $observation.PathSafety = if (Test-TpmSupportProtectedPath -Path $rootFull) { 'PROTECTED' } else { 'SAFE' }
    if ($observation.PathSafety -eq 'PROTECTED') {
        $observation.LayoutClass = 'LAYOUT_UNOBSERVABLE'
        $observation.Error = 'game directory is protected'
        return [pscustomobject]$observation
    }
    $files = @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -ErrorAction SilentlyContinue)
    $chd = @($files | Where-Object { $_.Extension -ieq '.chd' })
    $observation.ChdFiles = @($chd | ForEach-Object { Get-TpmSupportRelativePath -Path $_.FullName -Root $rootFull })
    $allowed = if ($ProfileRecord -and $ProfileRecord.Executable) { @($ProfileRecord.Executable.PrimaryCandidates) } else { @() }
    $exe = @($files | Where-Object {
        if ($allowed.Count -gt 0) {
            $fileName = $_.Name
            @($allowed | Where-Object { $_ -ieq $fileName }).Count -gt 0
        } else {
            $_.Extension -in @('.exe', '.elf', '.xbe', '.dll')
        }
    })
    $observation.ExecutableCandidates = @($exe | ForEach-Object { Get-TpmSupportRelativePath -Path $_.FullName -Root $rootFull })
    $observation.CandidateCount = $observation.ExecutableCandidates.Count
    if ($Fixture.layoutClass -and $script:TpmSupportPostureLayouts -contains [string]$Fixture.layoutClass) {
        $observation.LayoutClass = [string]$Fixture.layoutClass
    } elseif ($chd.Count -eq 0) {
        if ($Fixture.chdRequirement -eq 'REQUIRED') { $observation.LayoutClass = 'CHD_REQUIRED_BUT_ABSENT' } else { $observation.LayoutClass = 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT' }
    } elseif ($Fixture.separateLauncher) {
        $observation.LayoutClass = 'CHD_PLUS_SEPARATE_LAUNCHER'
    } elseif ($chd.Count -gt 1) {
        $observation.LayoutClass = 'MULTIPLE_CHD_CANDIDATES'
    } elseif ($exe.Count -eq 0) {
        $depth = ($observation.ChdFiles[0] -split '/').Count - 1
        $observation.LayoutClass = if ($depth -le 1) { 'CHD_ONLY' } else { 'CHD_NESTED_MULTIPLE_LEVELS' }
    } else {
        $exeDir = [System.IO.Path]::GetDirectoryName((Join-Path $rootFull $observation.ExecutableCandidates[0])) -replace '\\', '/'
        $chdDir = [System.IO.Path]::GetDirectoryName((Join-Path $rootFull $observation.ChdFiles[0])) -replace '\\', '/'
        if ($exeDir -eq $rootFull.TrimEnd('\', '/') -and $chdDir -eq $rootFull.TrimEnd('\', '/')) {
            $observation.LayoutClass = 'CHD_PLUS_EXECUTABLE_SAME_FOLDER'
        } elseif ($exeDir -eq $rootFull.TrimEnd('\', '/') -and $chdDir -match '(?i)/(content|media)(/|$)') {
            $observation.LayoutClass = 'CHD_PLUS_EXECUTABLE_PLUS_CONTENT_SUBFOLDER'
        } elseif ($chdDir -match '(?i)/(content|media)(/|$)') {
            $observation.LayoutClass = 'CHD_IN_CONTENT_OR_MEDIA_SUBFOLDER'
        } else {
            $depth = ($observation.ChdFiles[0] -split '/').Count - 1
            $observation.LayoutClass = if ($depth -le 1) { 'CHD_NESTED_ONE_LEVEL' } else { 'CHD_NESTED_MULTIPLE_LEVELS' }
        }
    }
    if ($Fixture.selectedPath -and -not (Test-TpmSupportPathInside -Child (Join-Path $FixtureRoot ([string]$Fixture.selectedPath)) -Parent $rootFull)) {
        $observation.LayoutClass = 'CHD_PRESENT_WRONG_DIRECTORY_SELECTED'
        $observation.PathSafety = 'CONFLICTING_SELECTION'
    }
    if ($Fixture.mediaConflict) { $observation.LayoutClass = 'MEDIA_LAYOUT_CONFLICTS_WITH_PROFILE' }
    if ($Fixture.forceProtected) { $observation.PathSafety = 'PROTECTED' }
    if ($Fixture.forceReparse) { $observation.PathSafety = 'REPARSE_OR_INACCESSIBLE' }
    return [pscustomobject]$observation
}
function Get-TpmSupportClassification {
    param([object]$ProfileRecord, [object]$Layout, [object]$Fixture)
    $classification = 'REVIEW_MANUAL'
    $reason = 'LAYOUT_UNOBSERVABLE'
    $action = 'Open TeknoParrotUI, select the exact game directory, save it, then run TPM again.'
    if (-not $ProfileRecord -or $ProfileRecord.IsMalformed) {
        $classification = 'BLOCKED_UNSUPPORTED'; $reason = 'MALFORMED_PROFILE_XML'; $action = 'Open TeknoParrotUI and repair or reinstall this game profile before using TPM.'
    } elseif (-not $Layout) {
        $classification = 'REVIEW_MANUAL'; $reason = 'LAYOUT_UNOBSERVABLE'
    } elseif ($Layout.PathSafety -in @('PROTECTED', 'REPARSE_OR_INACCESSIBLE')) {
        $classification = 'BLOCKED_UNSUPPORTED'; $reason = 'UNSAFE_GAME_PATH'; $action = 'No files were changed because the game path is protected, inaccessible, or reparse-backed. Choose a verified local game directory in TeknoParrotUI.'
    } elseif ($Layout.LayoutClass -eq 'CHD_EXPECTED_GAME_DIRECTORY_MISSING') {
        $classification = 'BLOCKED_UNSUPPORTED'; $reason = 'GAME_DIRECTORY_MISSING'; $action = 'Restore the game directory, then open TeknoParrotUI and select it before running TPM again.'
    } elseif ($Layout.LayoutClass -eq 'MEDIA_LAYOUT_CONFLICTS_WITH_PROFILE') {
        $classification = 'BLOCKED_UNSUPPORTED'; $reason = 'MEDIA_LAYOUT_CONFLICT'; $action = 'Open TeknoParrotUI and review the profile media settings; TPM will not guess between conflicting layouts.'
    } elseif ($Layout.LayoutClass -eq 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT' -and $Layout.CandidateCount -eq 1 -and (($ProfileRecord.Executable.PrimaryCandidates.Count -gt 0) -or $Fixture.exactFolderIdentity)) {
        $classification = 'AUTOMATED_SAFE'; $reason = if ($ProfileRecord.Executable.PrimaryCandidates.Count -gt 0) { 'EXACT_UNIQUE_EXECUTABLE' } else { 'EXACT_PROFILE_FOLDER_IDENTITY' }; $action = 'TPM can use the one exact launch candidate without changing TeknoParrotUI-owned fields.'
    } elseif ($Layout.LayoutClass -eq 'NO_CHD_REQUIRED_ORDINARY_GAME_LAYOUT' -and $Layout.CandidateCount -eq 2 -and $ProfileRecord.Executable.HasTwoExecutables) {
        $classification = 'AUTOMATED_SAFE'; $reason = 'EXACT_TWO_EXECUTABLE_PROFILE'; $action = 'TPM can use the two explicitly ordered executable candidates without changing TeknoParrotUI-owned fields.'
    } elseif ($Layout.LayoutClass -eq 'CHD_ONLY' -and $Fixture.chdRequirement -eq 'EXPLICIT_TARGET' -and $Layout.ChdFiles.Count -eq 1) {
        $classification = 'AUTOMATED_SAFE'; $reason = 'EXPLICIT_UNIQUE_CHD_TARGET'; $action = 'TPM can use the one explicitly identified CHD target; no TeknoParrotUI-owned field is written by this tool.'
    } elseif ($Layout.LayoutClass -eq 'CHD_REQUIRED_BUT_ABSENT') {
        $classification = 'REVIEW_MANUAL'; $reason = 'REQUIRED_MEDIA_MISSING'; $action = 'Provide the required CHD media, open TeknoParrotUI, select the correct game directory, then run TPM again.'
    } elseif ($Layout.LayoutClass -eq 'MULTIPLE_CHD_CANDIDATES') {
        $classification = 'REVIEW_MANUAL'; $reason = 'MULTIPLE_CHD_CANDIDATES'; $action = 'Open TeknoParrotUI and select the intended CHD or media directory. TPM will not choose the first CHD.'
    } elseif ($Layout.LayoutClass -eq 'CHD_PRESENT_WRONG_DIRECTORY_SELECTED') {
        $classification = 'REVIEW_MANUAL'; $reason = 'WRONG_DIRECTORY_SELECTED'; $action = 'Open TeknoParrotUI and select the directory containing the expected launcher and media files.'
    } elseif ($Layout.LayoutClass -eq 'CHD_PRESENT_BUT_PROFILE_MEDIA_RULE_UNKNOWN' -or $Layout.LayoutClass -like 'CHD_*' -or $Layout.LayoutClass -eq 'LAYOUT_UNOBSERVABLE') {
        $classification = 'REVIEW_MANUAL'; $reason = 'MEDIA_RULE_UNKNOWN'; $action = 'Review needed: open TeknoParrotUI and select the exact game or media directory because TPM cannot prove the CHD relationship safely.'
    } elseif ($Layout.CandidateCount -eq 0) {
        $classification = 'REVIEW_MANUAL'; $reason = 'REQUIRED_LAUNCH_TARGET_MISSING'; $action = 'Restore the expected launcher or select the correct game directory in TeknoParrotUI, then run TPM again.'
    }
    if ($Fixture.sourceConflict) {
        $classification = 'REVIEW_MANUAL'; $reason = 'SOURCE_EVIDENCE_CONFLICT'; $action = 'Review the installed and pinned profile sources before choosing a game directory in TeknoParrotUI.'
    }
    return [pscustomobject]@{ Classification = $classification; ReasonCode = $reason; BeginnerAction = $action }
}


function Get-TpmSupportFixtureResults {
    param([string]$FixtureRoot, [hashtable]$ProfilesByCode)
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($fixture in @(Get-TpmSupportFixtureManifest -FixtureRoot $FixtureRoot | Sort-Object id)) {
        $code = [string]$fixture.profileCode
        $fixtureProfile = if ($ProfilesByCode.ContainsKey($code)) { $ProfilesByCode[$code] } else { $null }
        $layout = Get-TpmSupportLayoutObservation -FixtureRoot $FixtureRoot -Fixture $fixture -ProfileRecord $fixtureProfile
        $decision = Get-TpmSupportClassification -ProfileRecord $fixtureProfile -Layout $layout -Fixture $fixture
        $row = [ordered]@{
            FixtureId = [string]$fixture.id
            ProfileCode = $code
            LayoutClass = $layout.LayoutClass
            Classification = $decision.Classification
            ReasonCode = $decision.ReasonCode
            BeginnerAction = $decision.BeginnerAction
            CandidateCount = $layout.CandidateCount
            ChdCount = $layout.ChdFiles.Count
            PathSafety = $layout.PathSafety
            ExpectedClassification = [string]$fixture.expectedClassification
            ExpectedReasonCode = [string]$fixture.expectedReasonCode
            Pass = ((-not $fixture.expectedClassification -or [string]$fixture.expectedClassification -eq $decision.Classification) -and (-not $fixture.expectedReasonCode -or [string]$fixture.expectedReasonCode -eq $decision.ReasonCode))
            Observation = $layout
        }
        [void]$results.Add([pscustomobject]$row)
        if ($fixtureProfile) {
            if (-not $fixtureProfile.FixtureIds) { $fixtureProfile.FixtureIds = @() }
            $fixtureProfile.FixtureIds = @($fixtureProfile.FixtureIds + [string]$fixture.id | Sort-Object -Unique)
            $fixtureProfile.Classification = $decision.Classification
            $fixtureProfile.ReasonCode = $decision.ReasonCode
            $fixtureProfile.BeginnerAction = $decision.BeginnerAction
        }
    }
    return @($results.ToArray())
}

function ConvertTo-TpmSupportJsonValue {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Depth 30)
}

function ConvertTo-TpmSupportMarkdownCell {
    param([object]$Value)
    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    return (($text -replace '\|', '\\|') -replace "`r?`n", ' ')
}

function New-TpmSupportPostureMarkdown {
    param([object]$Model, [object]$FixtureCoverage)
    $lines = New-Object System.Collections.Generic.List[string]
    [void]$lines.Add('# TPM Support Posture Matrix')
    [void]$lines.Add('')
    [void]$lines.Add(('Corpus: {0}' -f $Model.CorpusId))
    [void]$lines.Add(('Captured UTC: {0}' -f $Model.CapturedAtUtc))
    [void]$lines.Add(('Profiles: {0}' -f $Model.ProfileCount))
    [void]$lines.Add(('AUTOMATED_SAFE: {0}; REVIEW_MANUAL: {1}; BLOCKED_UNSUPPORTED: {2}; UNCLASSIFIED: {3}' -f $Model.ClassificationTotals.AUTOMATED_SAFE, $Model.ClassificationTotals.REVIEW_MANUAL, $Model.ClassificationTotals.BLOCKED_UNSUPPORTED, $Model.ClassificationTotals.UNCLASSIFIED))
    [void]$lines.Add(('Release closure eligible: {0}' -f $Model.ReleaseGate.ClosureEligible))
    [void]$lines.Add('')
    [void]$lines.Add('| ProfileCode | Game title | Emulator | Executable rule | Media rule | Layout | Classification | Reason | Beginner action | Fixtures | Evidence |')
    [void]$lines.Add('|---|---|---|---|---|---|---|---|---|---|---|')
    foreach ($profileRecord in @($Model.Profiles | Sort-Object ProfileCode)) {
        $evidence = @($profileRecord.Evidence.SourceIds) -join ', '
        $exe = @($profileRecord.Executable.PrimaryCandidates) -join ', '
        $media = [string]$profileRecord.Media.ChdRequirement
        $layout = if (@($profileRecord.LayoutObservations).Count -gt 0) { (@($profileRecord.LayoutObservations | ForEach-Object LayoutClass) -join ', ') } else { 'LAYOUT_UNOBSERVABLE' }
        $row = @(
            $profileRecord.ProfileCode, $profileRecord.GameTitle, $profileRecord.EmulatorType,
            $exe, $media, $layout, $profileRecord.Classification, $profileRecord.ReasonCode,
            $profileRecord.BeginnerAction, (@($profileRecord.FixtureIds) -join ', '), $evidence
        ) | ForEach-Object { ConvertTo-TpmSupportMarkdownCell $_ }
        [void]$lines.Add(('| {0} |' -f ($row -join ' | ')))
    }
    [void]$lines.Add('')
    [void]$lines.Add('## Fixture coverage')
    [void]$lines.Add('')
    [void]$lines.Add(('Fixtures: {0}; passed: {1}; failed: {2}' -f $FixtureCoverage.Total, $FixtureCoverage.Passed, $FixtureCoverage.Failed))
    [void]$lines.Add('')
    [void]$lines.Add('| FixtureId | ProfileCode | Layout | Classification | Reason | Pass |')
    [void]$lines.Add('|---|---|---|---|---|---|')
    foreach ($fixture in @($FixtureCoverage.Records | Sort-Object FixtureId)) {
        [void]$lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f (ConvertTo-TpmSupportMarkdownCell $fixture.FixtureId), (ConvertTo-TpmSupportMarkdownCell $fixture.ProfileCode), (ConvertTo-TpmSupportMarkdownCell $fixture.LayoutClass), (ConvertTo-TpmSupportMarkdownCell $fixture.Classification), (ConvertTo-TpmSupportMarkdownCell $fixture.ReasonCode), (ConvertTo-TpmSupportMarkdownCell $fixture.Pass)))
    }
    return ($lines -join "`n") + "`n"
}

function Invoke-TpmSupportPostureCorpus {
    param(
        [string]$TeknoParrotRoot = '', [string]$InstalledGameProfilesPath = '', [string]$InstalledUserProfilesPath = '',
        [string]$UpstreamProfileRoot = '', [string]$UpstreamCommitSha = '', [string]$UpstreamVersion = '',
        [string]$InstalledTeknoParrotVersion = '', [string]$EggmanDatZip = '', [string]$DatFilePath = '',
        [string]$FixtureRoot = '', [string]$SnapshotId = '', [string]$CapturedAtUtc = '',
        [Parameter(Mandatory = $true)][string]$OutputRoot
    )
    $captured = if ($CapturedAtUtc) { $CapturedAtUtc } else { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $output = ConvertTo-TpmSupportFullPath $OutputRoot
    if (-not $output) { throw 'OutputRoot must be an absolute or resolvable path.' }
    [void][System.IO.Directory]::CreateDirectory($output)
    $installedRoot = if ($InstalledGameProfilesPath) { $InstalledGameProfilesPath } elseif ($TeknoParrotRoot) { Join-Path $TeknoParrotRoot 'GameProfiles' } else { '' }
    $userRoot = if ($InstalledUserProfilesPath) { $InstalledUserProfilesPath } elseif ($TeknoParrotRoot) { Join-Path $TeknoParrotRoot 'UserProfiles' } else { '' }
    $sources = New-Object System.Collections.Generic.List[object]
    if ($installedRoot) { [void]$sources.Add((Get-TpmSupportProfileSource -Root $installedRoot -SourceType 'InstalledGameProfiles' -SourceId $(if ($InstalledTeknoParrotVersion) { $InstalledTeknoParrotVersion } else { 'LOCAL-INSTALL' }) -CapturedAtUtc $captured)) }
    if ($UpstreamProfileRoot) { [void]$sources.Add((Get-TpmSupportProfileSource -Root $UpstreamProfileRoot -SourceType 'PinnedUpstreamGameProfiles' -SourceId $(if ($UpstreamCommitSha) { $UpstreamCommitSha } elseif ($UpstreamVersion) { $UpstreamVersion } else { 'UNPINNED-SOURCE' }) -CapturedAtUtc $captured)) }
    $availableRoots = @($sources | Where-Object Available | ForEach-Object { $_.Profiles | ForEach-Object SourcePath } | Where-Object { $_ })
    foreach ($root in @($installedRoot, $UpstreamProfileRoot)) {
        $rootFull = ConvertTo-TpmSupportFullPath $root
        if ($rootFull -and (Test-TpmSupportPathInside -Child $output -Parent $rootFull)) { throw 'OutputRoot must not be inside a profile source root.' }
    }
    $byCode = @{}
    $profileSources = @{}
    foreach ($source in @($sources | Where-Object Available)) {
        foreach ($profileRecord in @($source.Profiles)) {
            $key = $profileRecord.ProfileCode.ToLowerInvariant()
            if (-not $byCode.ContainsKey($key)) { $byCode[$key] = $profileRecord; $profileSources[$key] = New-Object System.Collections.Generic.List[string] }
            [void]$profileSources[$key].Add($source.SourceId)
            if ($source.SourceType -eq 'InstalledGameProfiles') { $byCode[$key] = $profileRecord }
        }
    }
    $profiles = New-Object System.Collections.Generic.List[object]
    $duplicateCount = 0
    foreach ($key in @($byCode.Keys | Sort-Object)) {
        $profileRecord = $byCode[$key]
        $clone = [ordered]@{}
        foreach ($property in $profileRecord.Keys) { $clone[$property] = $profileRecord[$property] }
        if ($clone.Contains('SourcePath')) { [void]$clone.Remove('SourcePath') }
        $sourceIds = @($profileSources[$key] | Sort-Object -Unique)
        $clone.Evidence = [ordered]@{}
        foreach ($property in $profileRecord.Evidence.Keys) { $clone.Evidence[$property] = $profileRecord.Evidence[$property] }
        $clone.Evidence.SourceIds = $sourceIds
        $clone.Evidence.CapturedAtUtc = $captured
        $clone.SourceDiscrepancy = $false
        $sameCode = @($sources | Where-Object Available | ForEach-Object { $_.Profiles | Where-Object { $_.ProfileCode -ieq $profileRecord.ProfileCode } })
        if ($sameCode.Count -gt 1) {
            $hashes = @($sameCode | ForEach-Object ProfileXmlSha256 | Sort-Object -Unique)
            if ($hashes.Count -gt 1) { $clone.SourceDiscrepancy = $true }
        }
        $destProfile = Join-Path $output ('profiles\' + $profileRecord.ProfileCode + '.xml')
        if ($profileRecord.SourcePath -and (Test-Path -LiteralPath $profileRecord.SourcePath -PathType Leaf)) {
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destProfile))
            Copy-Item -LiteralPath $profileRecord.SourcePath -Destination $destProfile -Force
        }
        $clone.LayoutObservations = @()
        [void]$profiles.Add([pscustomobject]$clone)
    }
    $profilesByCode = @{}
    foreach ($profileRecord in $profiles) { $profilesByCode[$profileRecord.ProfileCode] = $profileRecord }
    $fixtureResults = @(Get-TpmSupportFixtureResults -FixtureRoot $FixtureRoot -ProfilesByCode $profilesByCode)
    foreach ($profileRecord in $profiles) {
        $rows = @($fixtureResults | Where-Object { $_.ProfileCode -ieq $profileRecord.ProfileCode })
        $profileRecord.LayoutObservations = @($rows | ForEach-Object { $_.Observation })
        if ($rows.Count -eq 0) {
            $decision = Get-TpmSupportClassification -ProfileRecord $profileRecord -Layout $null -Fixture ([pscustomobject]@{})
            $profileRecord.Classification = $decision.Classification
            $profileRecord.ReasonCode = $decision.ReasonCode
            $profileRecord.BeginnerAction = $decision.BeginnerAction
        }
    }
    $classificationTotals = [ordered]@{ AUTOMATED_SAFE = 0; REVIEW_MANUAL = 0; BLOCKED_UNSUPPORTED = 0; UNCLASSIFIED = 0 }
    foreach ($profileRecord in $profiles) {
        if (-not $script:TpmSupportPostureClassifications -contains $profileRecord.Classification) { $profileRecord.Classification = 'UNCLASSIFIED' }
        $classificationTotals[$profileRecord.Classification] = [int]$classificationTotals[$profileRecord.Classification] + 1
    }
    $datSummary = Get-TpmSupportDatSummary -ZipPath $EggmanDatZip -DatPath $DatFilePath -CapturedAtUtc $captured
    $userObservations = @(Get-TpmSupportUserProfileObservations -Root $userRoot -CapturedAtUtc $captured)
    $fixtureCoverage = [ordered]@{
        Status = if ($FixtureRoot) { 'READ' } else { 'NOT_SUPPLIED' }
        Total = $fixtureResults.Count
        Passed = @($fixtureResults | Where-Object Pass).Count
        Failed = @($fixtureResults | Where-Object { -not $_.Pass }).Count
        Records = $fixtureResults
    }
    $sourceSummaries = @($sources | ForEach-Object {
        [ordered]@{
            SourceType = $_.SourceType
            SourceId = $_.SourceId
            Available = $_.Available
            ProfileCount = $_.ProfileCount
            DuplicateProfileStems = $_.DuplicateProfileStems
            MalformedProfileStems = $_.MalformedProfileStems
            CapturedAtUtc = $_.CapturedAtUtc
        }
    })
    $snapshotMaterial = @($profiles | ForEach-Object ProfileXmlSha256) -join '|'
    $snapshotIdValue = if ($SnapshotId) { $SnapshotId } else { 'TPM-SUPPORT-' + (Get-TpmSupportShortHash -Bytes ([Text.Encoding]::UTF8.GetBytes($snapshotMaterial))) }
    $model = [ordered]@{
        SchemaVersion = 1
        CorpusId = 'TPM-TPUI-GAME-SUPPORT'
        SnapshotId = $snapshotIdValue
        CapturedAtUtc = $captured
        ProfileCount = $profiles.Count
        Sources = $sourceSummaries
        SecondaryDat = $datSummary
        ClassificationTotals = $classificationTotals
        FixtureCoverage = $fixtureCoverage
        ReleaseGate = [ordered]@{
            ZeroUnclassified = ($classificationTotals.UNCLASSIFIED -eq 0)
            NoDuplicateProfileStems = (@($sources | ForEach-Object DuplicateProfileStems).Count -eq 0)
            SourceIdentityComplete = ($sources.Count -gt 0 -and @($sources | Where-Object { -not $_.Available -or [string]::IsNullOrWhiteSpace($_.SourceId) }).Count -eq 0)
            ProfilesPresent = ($profiles.Count -gt 0)
            FixtureExpectationsPass = ($fixtureCoverage.Failed -eq 0)
            ClosureEligible = ($profiles.Count -gt 0 -and $classificationTotals.UNCLASSIFIED -eq 0 -and @($sources | Where-Object Available).Count -gt 0 -and @($sources | ForEach-Object DuplicateProfileStems).Count -eq 0 -and $fixtureCoverage.Failed -eq 0)
        }
        Profiles = @($profiles | Sort-Object ProfileCode)
    }
    $manifestFiles = New-Object System.Collections.Generic.List[object]
    foreach ($profileRecord in $profiles) {
        $relative = 'profiles/' + $profileRecord.ProfileCode + '.xml'
        $path = Join-Path $output ($relative -replace '/', '\')
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [void]$manifestFiles.Add([ordered]@{ RelativePath = $relative; ProfileCode = $profileRecord.ProfileCode; Sha256 = Get-TpmSupportSha256 -Path $path })
        }
    }
    $manifest = [ordered]@{
        SchemaVersion = 1
        CorpusId = $model.CorpusId
        SnapshotId = $model.SnapshotId
        CapturedAtUtc = $captured
        ProfileCount = $model.ProfileCount
        SourceCount = $sources.Count
        Sources = @($sources | ForEach-Object { [ordered]@{ SourceType = $_.SourceType; SourceId = $_.SourceId; Available = $_.Available; ProfileCount = $_.ProfileCount; DuplicateProfileStems = $_.DuplicateProfileStems; MalformedProfileStems = $_.MalformedProfileStems } })
        ProfileFiles = @($manifestFiles | Sort-Object ProfileCode)
    }
    Write-TpmSupportUtf8NoBom -Path (Join-Path $output 'manifest.json') -Text (ConvertTo-TpmSupportJsonValue $manifest)
    Write-TpmSupportUtf8NoBom -Path (Join-Path $output 'support-posture.json') -Text (ConvertTo-TpmSupportJsonValue $model)
    Write-TpmSupportUtf8NoBom -Path (Join-Path $output 'fixture-coverage.json') -Text (ConvertTo-TpmSupportJsonValue $fixtureCoverage)
    Write-TpmSupportUtf8NoBom -Path (Join-Path $output 'support-posture.md') -Text (New-TpmSupportPostureMarkdown -Model ([pscustomobject]$model) -FixtureCoverage ([pscustomobject]$fixtureCoverage))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $output 'observations'))
    [void][System.IO.Directory]::CreateDirectory((Join-Path $output 'dat'))
    Write-TpmSupportUtf8NoBom -Path (Join-Path $output 'observations\userprofiles.json') -Text (ConvertTo-TpmSupportJsonValue ([ordered]@{ SchemaVersion = 1; CapturedAtUtc = $captured; Records = $userObservations }))
    Write-TpmSupportUtf8NoBom -Path (Join-Path $output 'dat\dat-summary.json') -Text (ConvertTo-TpmSupportJsonValue $datSummary)
    Write-Output ([pscustomobject]@{ SnapshotId = $model.SnapshotId; OutputRoot = $output; ProfileCount = $model.ProfileCount; ClassificationTotals = [pscustomobject]$classificationTotals; FixtureCoverage = [pscustomobject]$fixtureCoverage; ReleaseGate = [pscustomobject]$model.ReleaseGate })
}

function Get-TpmSupportShortHash {
    param([byte[]]$Bytes)
    $sha = $null
    try {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').Substring(0, 12).ToLowerInvariant()
    } finally { if ($sha) { $sha.Dispose() } }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        if ([string]::IsNullOrWhiteSpace($OutputRoot)) { throw 'OutputRoot is required.' }
        Invoke-TpmSupportPostureCorpus -TeknoParrotRoot $TeknoParrotRoot -InstalledGameProfilesPath $InstalledGameProfilesPath -InstalledUserProfilesPath $InstalledUserProfilesPath -UpstreamProfileRoot $UpstreamProfileRoot -UpstreamCommitSha $UpstreamCommitSha -UpstreamVersion $UpstreamVersion -InstalledTeknoParrotVersion $InstalledTeknoParrotVersion -EggmanDatZip $EggmanDatZip -DatFilePath $DatFilePath -FixtureRoot $FixtureRoot -SnapshotId $SnapshotId -CapturedAtUtc $CapturedAtUtc -OutputRoot $OutputRoot
        exit 0
    } catch {
        Write-Error $_
        exit 1
    }
}
