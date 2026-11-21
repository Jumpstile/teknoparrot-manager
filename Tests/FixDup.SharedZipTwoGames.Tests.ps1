#Requires -Module Pester

# Two Eggman DAT games ("Special Forces Elite Training (01.01.01)" and "(01.02.00)") list the same three files and their ZIPs are
# byte-for-byte the same. Their names read the same once the year and tags are removed, so the DAT index keeps the second game under
# Alternates. Registration looked a folder up by the first game only: the (01.02.00) folder was asked about as a "duplicate" of the
# (01.01.01) game and its own profile was never registered. What a user sees or loses: every folder registers the profile of the game
# it is named after, and no question is asked. Fake ZIPs, folders and profiles under TestDrive only.
# What this CANNOT prove: that the real DAT has exactly this shape (the fragment is written from the facts the owner checked).
BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FixDup bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fixdup-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressDir = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressDir)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressDir 'TpmProgress.psm1') -Force
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:ActiveTpmWorkflowStatus = $null; $script:PostgresRecoveryStatus = $null; $script:PostgresRecoveryResumeState = $null; $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fixdup.log'; $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}; $script:FileVersionPins = @{}; $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72; $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new([string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'), [System.StringComparer]::OrdinalIgnoreCase)

    $script:GameA = 'Special Forces Elite Training (01.01.01) (2002)[ICE VP101][TP]'
    $script:GameB = 'Special Forces Elite Training (01.02.00) (2002)[ICE VP101][TP]'
    $datText = @"
<?xml version="1.0"?>
<datafile>
  <game name="$($script:GameA)">
    <GameProfile>specfrceo</GameProfile><Executable>specfrce.zip</Executable><Executable2>specfrce/sf010101.chd</Executable2>
    <rom name="specfrce.zip" size="3146122" crc="00000001" />
    <rom name="specfrce/sf010101.chd" size="105898414" crc="00000002" />
    <rom name="specfrce/sf010200.chd" size="236998439" crc="00000003" />
  </game>
  <game name="$($script:GameB)">
    <GameProfile>specfrce</GameProfile><Executable>specfrce.zip</Executable><Executable2>specfrce/sf010200.chd</Executable2>
    <rom name="specfrce.zip" size="3146122" crc="00000001" />
    <rom name="specfrce/sf010101.chd" size="105898414" crc="00000002" />
    <rom name="specfrce/sf010200.chd" size="236998439" crc="00000003" />
  </game>
</datafile>
"@
    $stream = New-Object System.IO.MemoryStream (, [System.Text.Encoding]::UTF8.GetBytes($datText))
    try { $script:DatIndex = Build-DatIndexFromStream -stream $stream } finally { $stream.Dispose() }

    function New-FixDupZip {
        param([string]$Path)
        $file = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $archive = New-Object IO.Compression.ZipArchive($file, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in 'specfrce.zip', 'specfrce/sf010101.chd', 'specfrce/sf010200.chd') {
                    $writer = New-Object IO.StreamWriter(($archive.CreateEntry($name)).Open(), (New-Object Text.UTF8Encoding($false)))
                    try { $writer.Write('same content of ' + $name) } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $file.Dispose() }
    }

    # Two identical ZIPs in a source folder, extracted by AutoSync into the install folder; one template per profile.
    function New-FixDupCollection {
        $root = Join-Path $TestDrive ('dup-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $c = [pscustomobject]@{
            Games = (Join-Path $root 'Games'); Zips = (Join-Path $root 'Zips'); Profiles = (Join-Path $root 'UserProfiles')
            State = (Join-Path $root 'State'); Templates = (Join-Path $root 'GameProfiles'); TpRoot = (Join-Path $root 'TeknoParrot')
            SyncState = (Join-Path $root 'Games\TeknoParrot-Manager.syncstate.json')
        }
        New-Item -ItemType Directory -Path $c.Games, $c.Zips, $c.Profiles, $c.State, $c.Templates, $c.TpRoot -Force | Out-Null
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $c.State }
        $script:TpmRegistrationLedger = $null; $script:TpmSessionRunId = $null; $script:TpmRegistrationLedgerStopLatch = $null
        foreach ($name in $script:GameA, $script:GameB) { New-FixDupZip -Path (Join-Path $c.Zips ($name + '.zip')) }
        foreach ($code in 'specfrceo', 'specfrce') {
            [IO.File]::WriteAllText((Join-Path $c.Templates ($code + '.xml')), '<GameProfile><GamePath></GamePath><ExecutableName>specfrce.zip</ExecutableName></GameProfile>')
        }
        return $c
    }
}

AfterAll {
    $script:TpmOwnedLayout = $null
    $script:TpmRegistrationLedger = $null
    $script:TpmRegistrationLedgerStopLatch = $null
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:TpmProgressModuleImported = $false
    $script:TpmProgressModuleLoadedPath = ''
}

Describe 'Two DAT games that list the same files (same name once year and tags are removed)' {
    BeforeEach { Mock Write-Host { } }

    It 'registers each folder under the profile of the game it is named after, with no duplicate question' {
        # Mutation: look the folder up by the first game only ($datIndex[$normFolder]) in Register-GamesLegacy -> the (01.02.00) folder is
        # reported as a "duplicate" of specfrceo and specfrce is never registered.
        $c = New-FixDupCollection
        $sync = Invoke-AutoSync -zipSource $c.Zips -installFolder $c.Games -syncStatePath $c.SyncState -DryRun $false -retroBat $false -datIndex $script:DatIndex -userProfilesDir $c.Profiles
        $sync.Failed | Should -Be 0
        @(Get-ChildItem -LiteralPath $c.Games -Directory).Count | Should -Be 2
        $script:TpmOwnedLayout = $null
        $profileIndex = @{ 'specfrce.zip' = @(
            [pscustomobject]@{ Code = 'specfrceo'; ExeName = 'specfrce.zip'; TemplatePath = (Join-Path $c.Templates 'specfrceo.xml') },
            [pscustomobject]@{ Code = 'specfrce'; ExeName = 'specfrce.zip'; TemplatePath = (Join-Path $c.Templates 'specfrce.xml') }) }

        $result = Register-Games -userProfilesDir $c.Profiles -installFolder $c.Games -profileIndex $profileIndex -gameProfilesDir $c.Templates `
            -datIndex $script:DatIndex -profileSet $null -tpRootDir $c.TpRoot -subFolderMap @{} -DryRun $false

        @($result.TechnicalDetails.Ambiguous).Count | Should -Be 0
        @($result.TechnicalDetails.Registered | ForEach-Object { $_.Code } | Sort-Object) | Should -Be @('specfrce', 'specfrceo')
        $pathOf = { param($code) ([xml](Get-Content -LiteralPath (Join-Path $c.Profiles ($code + '.xml')) -Raw)).GameProfile.GamePath }
        (& $pathOf 'specfrceo') | Should -Be (Join-Path (Join-Path $c.Games $script:GameA) 'specfrce.zip')
        (& $pathOf 'specfrce') | Should -Be (Join-Path (Join-Path $c.Games $script:GameB) 'specfrce.zip')
    }

    It 'confirms each folder for its own profile only, so LaunchBox matching is told the right game' {
        # Mutation: Get-DatEntryForZipName returns the first game for both names -> the (01.02.00) folder is not confirmed for specfrce.
        $pathA = Join-Path (Join-Path 'W:\Games' $script:GameA) 'specfrce.zip'
        $pathB = Join-Path (Join-Path 'W:\Games' $script:GameB) 'specfrce.zip'
        Get-TpmConfirmedDatName -Code 'specfrceo' -GamePath $pathA -DatIndex $script:DatIndex | Should -Be $script:GameA
        Get-TpmConfirmedDatName -Code 'specfrce' -GamePath $pathB -DatIndex $script:DatIndex | Should -Be $script:GameB
        Get-TpmConfirmedDatName -Code 'specfrce' -GamePath $pathA -DatIndex $script:DatIndex | Should -Be ''
    }
}
