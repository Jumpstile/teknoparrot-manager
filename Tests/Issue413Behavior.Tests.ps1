#Requires -Module Pester

# #413: AutoSync must extract a game whose TeknoParrot profile has no game file yet. Fake ZIPs and folders under $TestDrive only.
# exist yet. Isolated fake ZIPs and folders under $TestDrive only; run on the test PC
# by the coordinator. Each It names the product change that makes it fail.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX41 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix41-autosync-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    # Exactly one TpmProgress per session: an earlier test file can leave its own copy (from a removed $TestDrive)
    # loaded, so the first real extraction here would start from that foreign module state.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:PostgresRecoveryResumeState = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'fix41-autosync.log'
    $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    # Root\Games is the install folder (as configured), Root\Zips the source,
    # Root\State the owned State folder that enables the registration ledger.
    function New-Fix41Fixture {
        $root = Join-Path $TestDrive ('f41-' + [guid]::NewGuid().ToString('N').Substring(0, 10))
        $fx = [pscustomobject]@{
            Root = $root; Games = (Join-Path $root 'Games'); Zips = (Join-Path $root 'Zips')
            Profiles = (Join-Path $root 'UserProfiles'); State = (Join-Path $root 'State')
            SyncState = (Join-Path $root 'Games\TeknoParrot-Manager.syncstate.json')
            Ledger = (Join-Path $root 'State\TPM-RegistrationLedger.json')
        }
        New-Item -ItemType Directory -Path $fx.Games, $fx.Zips, $fx.Profiles, $fx.State -Force | Out-Null
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $fx.State }
        $script:TpmRegistrationLedger = $null
        $script:TpmSessionRunId = $null
        $script:TpmRegistrationLedgerStopLatch = $null
        return $fx
    }

    function New-Fix41Zip {
        param([string]$Path, [System.Collections.IDictionary]$Entries)
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew)
        try {
            $archive = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($name in $Entries.Keys) {
                    $entry = $archive.CreateEntry([string]$name)
                    $writer = New-Object IO.StreamWriter($entry.Open(), (New-Object Text.UTF8Encoding($false)))
                    try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
                }
            } finally { $archive.Dispose() }
        } finally { $stream.Dispose() }
    }

    function New-Fix41GameZip {
        param($Fixture, [string]$Name)
        $zip = Join-Path $Fixture.Zips ($Name + '.zip')
        New-Fix41Zip -Path $zip -Entries ([ordered]@{ 'game.exe' = ('exe of ' + $Name); 'data/level.bin' = ('level of ' + $Name) })
        return $zip
    }

    function Invoke-Fix41AutoSync {
        param($Fixture, [bool]$DryRun = $false, [bool]$RetroBat = $false, [hashtable]$DatIndex = @{})
        return (Invoke-AutoSync -zipSource $Fixture.Zips -installFolder $Fixture.Games -syncStatePath $Fixture.SyncState `
            -DryRun $DryRun -retroBat $RetroBat -datIndex $DatIndex -userProfilesDir $Fixture.Profiles)
    }

    function Get-Fix41TreeDigest {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path)) { return '<absent>' }
        $prefix = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        return ((Get-ChildItem -LiteralPath $Path -Recurse -Force | Sort-Object FullName | ForEach-Object {
            $relative = $_.FullName.Substring($prefix.Length)
            if ($_.PSIsContainer) { $relative + '|dir' } else { $relative + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
        }) -join "`n")
    }

    function Get-Fix41Residue {
        param($Fixture)
        return @(Get-ChildItem -LiteralPath $Fixture.Root -Force -Filter '.tpm-autosync-*') +
            @(Get-ChildItem -LiteralPath $Fixture.Games -Force -Filter '*.extracting')
    }

    function Get-Fix41LedgerUnit {
        param($Fixture, [string]$SourceName)
        $read = Read-TpmRegistrationLedger -Path $Fixture.Ledger
        if ($read.Status -ne 'Ok') { throw ('Ledger was {0}' -f $read.Status) }
        $units = @(@($read.Document.Operations)[-1].Units)
        return @($units | Where-Object { [string]$_.Folder -eq $SourceName })[0]
    }

    # Result detail for -Because: shows which refusal or transaction failure produced an unexpected count or
    # outcome. Never throws, so a missing property cannot hide the real result.
    function Get-Fix41Diagnostic {
        param($Result)
        try {
            $parts = New-Object System.Collections.Generic.List[string]
            foreach ($name in @('Synced', 'Failed', 'UnsafePathSkipped', 'Skipped', 'UpToDate', 'WouldSync', 'EvidenceRefused', 'EvidenceMessage', 'EvidenceStopped')) {
                if ($Result -is [System.Collections.IDictionary] -and $Result.Contains($name)) { [void]$parts.Add(('{0}={1}' -f $name, $Result[$name])) }
            }
            foreach ($tx in @($Result.TransactionResults)) {
                if ($null -eq $tx) { continue }
                $technical = Get-TpmTransactionField -Object $tx -Name 'TechnicalDetails'
                $cleanup = Get-TpmTransactionField -Object $tx -Name 'Cleanup'
                [void]$parts.Add(('tx: Outcome={0} Reason={1} Stage={2} Error={3} Errors={4} Residue={5}' -f
                    (Get-TpmTransactionField -Object $tx -Name 'Outcome'),
                    (Get-TpmTransactionField -Object $tx -Name 'ReasonCode'),
                    (Get-TpmTransactionField -Object $technical -Name 'Stage'),
                    (Get-TpmTransactionField -Object $technical -Name 'Error'),
                    (@(Get-TpmTransactionField -Object $tx -Name 'Errors' -Default @()) -join ' | '),
                    (@(Get-TpmTransactionField -Object $cleanup -Name 'ResiduePaths' -Default @()) -join ';')))
            }
            return ($parts -join '; ')
        } catch { return ('diagnostic unavailable: ' + $_.Exception.Message) }
    }
}

AfterAll {
    $script:TpmOwnedLayout = $null
    $script:TpmRegistrationLedger = $null
    $script:TpmRegistrationLedgerStopLatch = $null
    # The progress module was imported from this file's $TestDrive; do not leave it loaded for the next file.
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    $script:TpmProgressModuleImported = $false
    $script:TpmProgressModuleLoadedPath = ''
}

Describe 'AutoSync with a profile that has no game file yet (#413)' {
    AfterEach {
        $script:TpmOwnedLayout = $null
        $script:TpmRegistrationLedger = $null
        $script:TpmRegistrationLedgerStopLatch = $null
    }

    It 'extracts a game whose profile has an empty game path' {
        $fx = New-Fix41Fixture
        $name = 'Nova Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $dat = @{ (Get-NormalizedGameKey $name) = [pscustomobject]@{ ProfileCode = 'NOVA'; OriginalName = $name; Executable = 'game.exe' } }
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'NOVA.xml'), '<GameProfile><GamePath></GamePath></GameProfile>', (New-Object Text.UTF8Encoding($false)))

        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $result)
        $result.UnsafePathSkipped | Should -Be 0
        Test-Path -LiteralPath (Join-Path (Join-Path $fx.Games $name) 'game.exe') -PathType Leaf | Should -BeTrue
    }

    It 'extracts a game whose profile has no game path line at all' {
        $fx = New-Fix41Fixture
        $name = 'Orbit Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $dat = @{ (Get-NormalizedGameKey $name) = [pscustomobject]@{ ProfileCode = 'ORBIT'; OriginalName = $name; Executable = 'game.exe' } }
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'ORBIT.xml'), '<GameProfile><GameName>Orbit</GameName></GameProfile>', (New-Object Text.UTF8Encoding($false)))

        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $result)
        $result.UnsafePathSkipped | Should -Be 0
    }

    It 'extracts a game whose saved game file is missing at an old location (library moved to another drive)' {
        $fx = New-Fix41Fixture
        $name = 'Pixel Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $dat = @{ (Get-NormalizedGameKey $name) = [pscustomobject]@{ ProfileCode = 'PIXEL'; OriginalName = $name; Executable = 'game.exe' } }
        $old = Join-Path (Join-Path $fx.Root 'OldDrive') 'game.exe'
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'PIXEL.xml'), ('<GameProfile><GamePath>' + $old + '</GamePath></GameProfile>'), (New-Object Text.UTF8Encoding($false)))

        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $result)
        $result.UnsafePathSkipped | Should -Be 0
        Test-Path -LiteralPath (Join-Path (Join-Path $fx.Games $name) 'game.exe') -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Split-Path -Parent $old) | Should -BeFalse
    }

    It 'extracts a game whose saved game file is on a drive letter that no longer exists (#412)' {
        $unused = [char[]]'QRSTUVWXYZ' | Where-Object { -not (Test-Path -LiteralPath ($_ + ':\')) } | Select-Object -First 1
        if (-not $unused) { Set-ItResult -Skipped -Because 'every drive letter from Q to Z is in use on this PC'; return }
        $fx = New-Fix41Fixture
        $name = 'Ridge Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $dat = @{ (Get-NormalizedGameKey $name) = [pscustomobject]@{ ProfileCode = 'RIDGE'; OriginalName = $name; Executable = 'game.exe' } }
        $old = $unused + ':\Games\Ridge Game\game.exe'
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'RIDGE.xml'), ('<GameProfile><GamePath>' + $old + '</GamePath></GameProfile>'), (New-Object Text.UTF8Encoding($false)))

        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 1 -Because (Get-Fix41Diagnostic $result)
        $result.UnsafePathSkipped | Should -Be 0
        Test-Path -LiteralPath (Join-Path (Join-Path $fx.Games $name) 'game.exe') -PathType Leaf | Should -BeTrue
    }

    It 'still refuses a game that is already installed at another place, and changes nothing' {
        $fx = New-Fix41Fixture
        $name = 'Quartz Game (1.0)[TP]'
        [void](New-Fix41GameZip -Fixture $fx -Name $name)
        $dat = @{ (Get-NormalizedGameKey $name) = [pscustomobject]@{ ProfileCode = 'QUARTZ'; OriginalName = $name; Executable = 'game.exe' } }
        $elsewhere = Join-Path (Join-Path $fx.Root 'Installed') 'game.exe'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $elsewhere))
        [IO.File]::WriteAllText($elsewhere, 'installed elsewhere')
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'QUARTZ.xml'), ('<GameProfile><GamePath>' + $elsewhere + '</GamePath></GameProfile>'), (New-Object Text.UTF8Encoding($false)))

        $result = Invoke-Fix41AutoSync -Fixture $fx -DatIndex $dat

        $result.Synced | Should -Be 0
        $result.UnsafePathSkipped | Should -Be 1
        Test-Path -LiteralPath (Join-Path $fx.Games $name) | Should -BeFalse
        [IO.File]::ReadAllText($elsewhere) | Should -BeExactly 'installed elsewhere'
    }
}
