#Requires -Module Pester

# Isolated regression tests for the durable registration ledger and the support
# evidence it feeds (#352 registration outcomes, #365 support evidence).
# Fake directories and files only: no TeknoParrot, LaunchBox, game, live
# profile, database or service is touched, and every write stays in $TestDrive.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Ledger test bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'tpm-ledger-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
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
    $script:logPath = Join-Path $TestDrive 'ledger-test.log'
    $script:logWarnShown = $false
    $script:RawThrillsPathLimits = @{}
    $script:FileVersionPins = @{}
    $script:GpuIncompatibleGames = @{}
    $script:FuzzyAutoThreshold = 0.72
    $script:FuzzyTieMargin = 0.1
    $script:TitleTokenStopWords = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('the', 'of', 'a', 'an', 'and', 'vs', 'vs.', 'in', 'for', 'to'),
        [System.StringComparer]::OrdinalIgnoreCase)

    function New-LedgerFixture {
        param([switch]$NoStateDirectory)
        $root = Join-Path $TestDrive ('ledger-' + [guid]::NewGuid().ToString('N'))
        $fx = [pscustomobject]@{
            Root = $root; Games = (Join-Path $root 'Games'); Profiles = (Join-Path $root 'UserProfiles')
            Templates = (Join-Path $root 'GameProfiles'); Script = (Join-Path $root 'Scripts'); State = (Join-Path $root 'Scripts\State'); Ledger = ''
        }
        New-Item -ItemType Directory -Path $fx.Games, $fx.Profiles, $fx.Templates, $fx.Script -Force | Out-Null
        if (-not $NoStateDirectory) { New-Item -ItemType Directory -Path $fx.State -Force | Out-Null }
        $fx.Ledger = Join-Path $fx.State 'TPM-RegistrationLedger.json'
        $script:TpmOwnedLayout = [pscustomobject]@{ State = $fx.State }
        $script:TpmRegistrationLedger = $null
        $script:TpmSessionRunId = $null
        $script:TpmRegistrationLedgerStopLatch = $null
        return $fx
    }

    function Add-FakeGame {
        param($Fixture, [string]$Folder, [string]$Exe, [string]$Code, [switch]$NoTemplate)
        $gameDir = Join-Path $Fixture.Games $Folder
        New-Item -ItemType Directory -Path $gameDir -Force | Out-Null
        $exePath = Join-Path $gameDir $Exe
        [IO.File]::WriteAllBytes($exePath, [byte[]](1, 2, 3))
        if (-not $NoTemplate) {
            $template = Join-Path $Fixture.Templates ($Code + '.xml')
            if (-not (Test-Path -LiteralPath $template)) {
                [IO.File]::WriteAllText($template, ('<GameProfile><ExecutableName>{0}</ExecutableName><EmulationProfile>Test</EmulationProfile><ConfigValues></ConfigValues></GameProfile>' -f $Exe), (New-Object System.Text.UTF8Encoding($false)))
            }
        }
        return $exePath
    }

    function Invoke-FakeRegistration {
        param($Fixture)
        $profileIndex = Build-ProfileIndex -gameProfilesDir $Fixture.Templates
        return (Register-Games -userProfilesDir $Fixture.Profiles -installFolder $Fixture.Games -profileIndex $profileIndex -gameProfilesDir $Fixture.Templates -DryRun $false)
    }

    function Get-TreeDigest {
        param([string]$Path)
        $prefix = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        return ((Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
            $_.FullName.Substring($prefix.Length) + '|' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }) -join "`n")
    }

    function Get-FileDigest {
        param([string]$Path)
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    }

    function Get-LedgerDocument {
        param($Fixture)
        $read = Read-TpmRegistrationLedger -Path $Fixture.Ledger
        if ($read.Status -ne 'Ok') { throw ('Ledger was {0}: {1}' -f $read.Status, $read.Message) }
        return $read.Document
    }

    function Add-ProfileFile {
        param($Fixture, [string]$Code, [string]$GamePath = '')
        $path = if ($GamePath) { $GamePath } else { Join-Path (Join-Path $Fixture.Games $Code) ($Code + '.exe') }
        if ($GamePath -ne '<none>') {
            $folder = [IO.Path]::GetDirectoryName($path)
            if ($folder -and $folder.StartsWith($Fixture.Games, [System.StringComparison]::OrdinalIgnoreCase)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
        }
        $xml = if ($GamePath -eq '<none>') { '<GameProfile><GameName>' + $Code + '</GameName></GameProfile>' } else { '<GameProfile><GamePath>' + $path + '</GamePath></GameProfile>' }
        [IO.File]::WriteAllText((Join-Path $Fixture.Profiles ($Code + '.xml')), $xml, (New-Object System.Text.UTF8Encoding($false)))
    }

    function Get-SupportZipText {
        param([string]$Path, [string]$EntryName)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $canonical = $EntryName -replace '\\', '/'
            $entry = @($zip.Entries | Where-Object { (($_.FullName -replace '\\', '/') -eq $canonical) }) | Select-Object -First 1
            if (-not $entry) { return $null }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $zip.Dispose() }
    }

    function Invoke-FakeSupportPackage {
        param($Fixture, [hashtable]$Extra = @{})
        $arguments = @{ ScriptRoot = $Fixture.Script; OutputRoot = (Join-Path $Fixture.Script 'SupportPackages'); UserProfilesDir = $Fixture.Profiles; ApprovedGamesRoot = $Fixture.Games }
        foreach ($key in $Extra.Keys) { $arguments[$key] = $Extra[$key] }
        return (New-TpmSupportPackage @arguments)
    }

    function New-FakeZip {
        param([string]$ZipPath)
        $fs = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::CreateNew)
        try {
            $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
            try {
                $entry = $archive.CreateEntry('game.exe')
                $writer = New-Object System.IO.StreamWriter($entry.Open())
                try { $writer.Write('content') } finally { $writer.Dispose() }
            } finally { $archive.Dispose() }
        } finally { $fs.Dispose() }
    }
    # Pester 5 rejects AfterEach in the file root, so each Describe below calls this reset from its own AfterEach.
    function Reset-LedgerScriptState {
        $script:TpmRegistrationLedger = $null
        $script:TpmOwnedLayout = $null
        $script:TpmSessionRunId = $null
        $script:TpmRegistrationLedgerStopLatch = $null
    }
}

Describe 'Pre-mutation evidence gate' {
    AfterEach { Reset-LedgerScriptState }
    It 'refuses a <Name> ledger before any registration write and leaves product and ledger untouched' -ForEach @(
        @{ Name = 'corrupt'; Content = '{ this is not json' }
        @{ Name = 'empty'; Content = '' }
        @{ Name = 'newer-schema'; Content = '{"SchemaVersion":2,"Sequence":1,"Operations":[],"Fatals":[]}' }
        @{ Name = 'array-less'; Content = '{"SchemaVersion":1,"Sequence":1}' }
    ) {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [IO.File]::WriteAllText($fx.Ledger, $Content, (New-Object System.Text.UTF8Encoding($false)))
        $gamesBefore = Get-TreeDigest $fx.Games
        $templatesBefore = Get-TreeDigest $fx.Templates
        $ledgerBefore = Get-FileDigest $fx.Ledger
        $result = Invoke-FakeRegistration $fx
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -Be 'REGISTRATION_EVIDENCE_UNAVAILABLE'
        $result.Summary | Should -Match 'Action required'
        Get-FileDigest $fx.Ledger | Should -Be $ledgerBefore
        @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.xml' -File).Count | Should -Be 0
        Get-TreeDigest $fx.Games | Should -Be $gamesBefore
        Get-TreeDigest $fx.Templates | Should -Be $templatesBefore
        (Test-Path -LiteralPath (Join-Path $fx.Profiles 'ALPHA.xml')) | Should -BeFalse
        Get-TreeDigest $fx.Profiles | Should -BeNullOrEmpty
    }

    It 'refuses an oversized ledger without reading it into a new publication' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [IO.File]::WriteAllBytes($fx.Ledger, (New-Object byte[] 1200000))
        $ledgerBefore = Get-FileDigest $fx.Ledger
        $result = Invoke-FakeRegistration $fx
        $result.ReasonCode | Should -Be 'REGISTRATION_EVIDENCE_UNAVAILABLE'
        $result.Summary | Should -Match 'oversized'
        Get-FileDigest $fx.Ledger | Should -Be $ledgerBefore
        (Test-Path -LiteralPath (Join-Path $fx.Profiles 'ALPHA.xml')) | Should -BeFalse
    }

    It 'refuses an unreadable ledger' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [IO.File]::WriteAllText($fx.Ledger, '{"SchemaVersion":1,"Sequence":1,"Operations":[],"Fatals":[]}', (New-Object System.Text.UTF8Encoding($false)))
        $lock = [IO.File]::Open($fx.Ledger, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
        try {
            $result = Invoke-FakeRegistration $fx
        } finally { $lock.Dispose() }
        $result.ReasonCode | Should -Be 'REGISTRATION_EVIDENCE_UNAVAILABLE'
        $result.Summary | Should -Match 'unreadable'
        (Test-Path -LiteralPath (Join-Path $fx.Profiles 'ALPHA.xml')) | Should -BeFalse
    }

    It 'refuses a reparse-backed State folder' {
        $fx = New-LedgerFixture -NoStateDirectory
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        $real = Join-Path $fx.Root 'RealState'
        New-Item -ItemType Directory -Path $real -Force | Out-Null
        try { New-Item -ItemType Junction -Path $fx.State -Target $real -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'A directory junction could not be created in this environment.'; return }
        try {
            $result = Invoke-FakeRegistration $fx
        } finally { [IO.Directory]::Delete($fx.State) }
        $result.ReasonCode | Should -Be 'REGISTRATION_EVIDENCE_UNAVAILABLE'
        $result.Summary | Should -Match 'unsafe'
        (Test-Path -LiteralPath (Join-Path $fx.Profiles 'ALPHA.xml')) | Should -BeFalse
        @(Get-ChildItem -LiteralPath $real -Force).Count | Should -Be 0
    }

    It 'refuses a projected ledger over the size limit and keeps the previous file' {
        $fx = New-LedgerFixture
        $first = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units @([pscustomobject]@{ Folder = 'One' }) -InstallRoot $fx.Games
        $first.Opened | Should -BeTrue
        $size = (Get-Item -LiteralPath $fx.Ledger).Length
        $before = Get-FileDigest $fx.Ledger
        $units = @(1..30 | ForEach-Object { [pscustomobject]@{ Folder = ('Folder number {0}' -f $_) } })
        $second = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units $units -InstallRoot $fx.Games -MaximumBytes ($size + 40)
        $second.Opened | Should -BeFalse
        $second.Status | Should -Be 'PublishFailed'
        $second.Message | Should -Match 'over the'
        Get-FileDigest $fx.Ledger | Should -Be $before
    }

    # Mutation: remove the pruning of finished runs from Publish-TpmRegistrationLedgerDocument -> after a few runs every new run is refused ('PublishFailed') and AutoSync/Register stop for good.
    It 'drops the oldest finished runs when the ledger is full and keeps an unfinished run' {
        $fx = New-LedgerFixture
        $units = @(1..5 | ForEach-Object { [pscustomobject]@{ Folder = ('Game {0}' -f $_) } })
        $cap = 6000
        $stuck = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units $units -InstallRoot $fx.Games -MaximumBytes $cap
        $stuck.Opened | Should -BeTrue
        $script:TpmRegistrationLedger = $null
        $ids = @()
        foreach ($run in 1..20) {
            $opened = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units $units -InstallRoot $fx.Games -MaximumBytes $cap
            $opened.Opened | Should -BeTrue
            $ids += $opened.OperationId
            [void](Close-TpmRegistrationLedgerOperations -Reason 'TEST')
        }
        (Get-Item -LiteralPath $fx.Ledger).Length | Should -BeLessOrEqual $cap
        $kept = @((Get-LedgerDocument $fx).Operations | ForEach-Object { [string]$_.OperationId })
        $kept | Should -Contain $stuck.OperationId
        $kept | Should -Contain $ids[-1]
        $kept | Should -Not -Contain $ids[0]
    }

    It 'drops the oldest interrupted run when only interrupted runs fill the ledger' {
        $fx = New-LedgerFixture
        $units = @(1..5 | ForEach-Object { [pscustomobject]@{ Folder = ('Game {0}' -f $_) } })
        $cap = 6000
        $ids = @()
        foreach ($run in 1..20) {
            $opened = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units $units -InstallRoot $fx.Games -MaximumBytes $cap
            $opened.Opened | Should -BeTrue
            $ids += $opened.OperationId
            $script:TpmRegistrationLedger = $null
        }
        (Get-Item -LiteralPath $fx.Ledger).Length | Should -BeLessOrEqual $cap
        $kept = @((Get-LedgerDocument $fx).Operations | ForEach-Object { [string]$_.OperationId })
        $kept | Should -Contain $ids[-1]
        $kept | Should -Not -Contain $ids[0]
    }

    It 'keeps both runs when a second window published to the ledger in between' {
        $fx = New-LedgerFixture
        $units = @(1..2 | ForEach-Object { [pscustomobject]@{ Folder = ('Game {0}' -f $_) } })
        $first = Open-TpmRegistrationLedgerOperation -Mode AutoSync -Units $units -InstallRoot $fx.Games
        $first.Opened | Should -BeTrue
        $window1 = $script:TpmRegistrationLedger
        $script:TpmRegistrationLedger = $null
        $second = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units $units -InstallRoot $fx.Games
        $second.Opened | Should -BeTrue
        $window2 = $script:TpmRegistrationLedger
        $script:TpmRegistrationLedger = $window1
        (Publish-TpmRegistrationLedgerContext) | Should -BeTrue
        $ops = @((Get-LedgerDocument $fx).Operations)
        @($ops | ForEach-Object { [string]$_.OperationId }) | Should -Contain $second.OperationId
        @($ops | Where-Object { [string]$_.OperationId -eq $first.OperationId })[0].State | Should -Be 'PENDING'
        $script:TpmRegistrationLedger = $window2
    }

    It 'keeps a crash record another window wrote while this window was running' {
        # Mutation: publish this window's stale document unchanged -> the crash evidence the other window saved is wiped.
        $fx = New-LedgerFixture
        $units = @(1..2 | ForEach-Object { [pscustomobject]@{ Folder = ('Game {0}' -f $_) } })
        $first = Open-TpmRegistrationLedgerOperation -Mode AutoSync -Units $units -InstallRoot $fx.Games
        $first.Opened | Should -BeTrue
        $window1 = $script:TpmRegistrationLedger
        $script:TpmRegistrationLedger = $null
        Add-TpmRegistrationLedgerFatal -Message 'other window crashed' | Should -BeTrue
        $script:TpmRegistrationLedger = $window1
        (Publish-TpmRegistrationLedgerContext) | Should -BeTrue
        $doc = Get-LedgerDocument $fx
        @($doc.Fatals).Count | Should -Be 1
        @($doc.Fatals)[0].Message | Should -Be 'other window crashed'
        @($doc.Operations | Where-Object { [string]$_.OperationId -eq $first.OperationId }).Count | Should -Be 1
    }

    It 'never replaces a ledger file it cannot use, and says so' {
        # Mutation: publish this window's document after a failed read -> the unreadable evidence file is overwritten.
        $fx = New-LedgerFixture
        $first = Open-TpmRegistrationLedgerOperation -Mode AutoSync -Units @([pscustomobject]@{ Folder = 'Game 1' }) -InstallRoot $fx.Games
        $first.Opened | Should -BeTrue
        [System.IO.File]::WriteAllText($fx.Ledger, 'this is not json')
        $before = Get-FileDigest $fx.Ledger
        Mock Write-Host {}
        (Publish-TpmRegistrationLedgerContext) | Should -BeFalse
        Get-FileDigest $fx.Ledger | Should -Be $before
        $script:TpmRegistrationLedger.Message | Should -Match 'does not change a ledger it cannot use'
        @($script:TpmRegistrationLedger.Document.Operations | Where-Object { [string]$_.OperationId -eq $first.OperationId }).Count | Should -Be 1
    }

    It 'creates no ledger when a first manifest is over the limit' {
        $fx = New-LedgerFixture
        $units = @(1..30 | ForEach-Object { [pscustomobject]@{ Folder = ('Folder number {0}' -f $_) } })
        $opened = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units $units -InstallRoot $fx.Games -MaximumBytes 500
        $opened.Opened | Should -BeFalse
        (Test-Path -LiteralPath $fx.Ledger) | Should -BeFalse
        $script:TpmRegistrationLedger | Should -BeNullOrEmpty
    }

    It 'does not write profiles when the manifest cannot be published after discovery' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        Mock Publish-TpmRegistrationLedgerDocument { [pscustomobject]@{ Published = $false; Reason = 'injected publication failure'; Bytes = 0 } }
        $result = Invoke-FakeRegistration $fx
        $result.Outcome | Should -Be 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -Be 'REGISTRATION_EVIDENCE_UNAVAILABLE'
        @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.xml' -File).Count | Should -Be 0
    }

    It 'refuses AutoSync before extraction when the ledger is unusable' {
        $fx = New-LedgerFixture
        [IO.File]::WriteAllText($fx.Ledger, '{ broken', (New-Object System.Text.UTF8Encoding($false)))
        $zipSource = Join-Path $fx.Root 'Zips'
        New-Item -ItemType Directory -Path $zipSource -Force | Out-Null
        New-FakeZip (Join-Path $zipSource 'Gamez.zip')
        Mock Expand-ZipFileSafe { throw 'must not extract' }
        $before = Get-TreeDigest $fx.Games
        $ledgerBefore = Get-FileDigest $fx.Ledger
        $result = Invoke-AutoSync -zipSource $zipSource -installFolder $fx.Games -syncStatePath (Join-Path $fx.Root 'sync.json') -datIndex @{}
        $result.EvidenceRefused | Should -BeTrue
        $result.Synced | Should -Be 0
        Should -Invoke Expand-ZipFileSafe -Times 0
        Get-TreeDigest $fx.Games | Should -Be $before
        Get-FileDigest $fx.Ledger | Should -Be $ledgerBefore
        (Test-Path -LiteralPath (Join-Path $fx.Root 'sync.json')) | Should -BeFalse
    }

    It 'publishes the AutoSync selection manifest before any ZIP is processed' {
        $fx = New-LedgerFixture
        $zipSource = Join-Path $fx.Root 'Zips'
        New-Item -ItemType Directory -Path $zipSource -Force | Out-Null
        New-FakeZip (Join-Path $zipSource 'Alpha Zip.zip')
        # FIX41: a ZIP with no folder at all is now extracted into a new folder. Keep this test on a
        # refused root: an existing non-empty folder with the ZIP name that the resolver did not confirm.
        $unconfirmed = Join-Path $fx.Games 'Alpha Zip'
        New-Item -ItemType Directory -Path $unconfirmed -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $unconfirmed 'user-file.txt'), 'not from this ZIP')
        $script:ledgerPathForTest = $fx.Ledger
        $script:manifestAtFirstZip = $null
        Mock Resolve-ExtractedGameFolder {
            $seen = Read-TpmRegistrationLedger -Path $script:ledgerPathForTest
            $script:manifestAtFirstZip = (@(@($seen.Document.Operations)[0].Units | ForEach-Object { '{0}:{1}' -f $_.Folder, $_.State }) -join ',')
            $null
        }
        Mock Expand-ZipFileSafe { throw 'must not extract' }
        $result = Invoke-AutoSync -zipSource $zipSource -installFolder $fx.Games -syncStatePath (Join-Path $fx.Root 'sync.json') -datIndex @{}
        $result.Synced | Should -Be 0
        # The complete manifest was already durable when the first ZIP was examined.
        $script:manifestAtFirstZip | Should -Be 'Alpha Zip:PENDING'
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        $op.Mode | Should -Be 'AutoSync'
        $op.State | Should -Be 'PENDING'
        @($op.Units).Count | Should -Be 1
        @($op.Units)[0].State | Should -Be 'SKIPPED'
        @($op.Units)[0].Reason | Should -Be 'UNPROVEN_EXTRACTION_ROOT'
        $evidence = Close-TpmRegistrationLedgerOperations -Reason 'NEW_REGISTRATION_TARGETS_UNVERIFIED'
        $evidence.Status | Should -Be 'CURRENT'
        $closed = @((Get-LedgerDocument $fx).Operations)[0]
        $closed.State | Should -Be 'COMPLETED'
        @($closed.Units)[0].State | Should -Be 'SKIPPED'
    }
}

Describe 'Registration outcome matrix' {
    AfterEach { Reset-LedgerScriptState }
    It 'records a verified mapping only after the saved profile reads back' {
        $fx = New-LedgerFixture
        $exe = Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA'
        $result = Invoke-FakeRegistration $fx
        $result.Outcome | Should -Be 'SUCCEEDED'
        $result.LedgerEvidence.Status | Should -Be 'CURRENT'
        $doc = Get-LedgerDocument $fx
        @($doc.Operations).Count | Should -Be 1
        $op = @($doc.Operations)[0]
        $op.Mode | Should -Be 'RegisterOnly'
        $op.State | Should -Be 'COMPLETED'
        $op.EvidenceStatus | Should -Be 'CURRENT'
        @($op.Units).Count | Should -Be 1
        @($op.Units)[0].State | Should -Be 'VERIFIED'
        $mapping = @($op.Mappings)[0]
        $mapping.Code | Should -Be 'ALPHA'
        $mapping.State | Should -Be 'VERIFIED'
        $mapping.Readback | Should -BeTrue
        $mapping.PathBase | Should -Be 'InstallRoot'
        $mapping.IntendedPath | Should -Be 'Alpha Game\alpha.exe'
        $mapping.UnitId | Should -Be (@($op.Units)[0].UnitId)
        $op.Transaction.Outcome | Should -Be 'SUCCEEDED'
        [IO.Path]::GetFullPath(([xml](Get-Content -LiteralPath (Join-Path $fx.Profiles 'ALPHA.xml') -Raw)).GameProfile.GamePath) | Should -Be ([IO.Path]::GetFullPath($exe))
        $script:TpmRegistrationLedger | Should -BeNullOrEmpty
    }

    It 'does not call an existing profile verified and leaves it untouched' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        $existing = Join-Path $fx.Profiles 'ALPHA.xml'
        [IO.File]::WriteAllText($existing, '<GameProfile><GamePath>C:\Elsewhere\alpha.exe</GamePath></GameProfile>', (New-Object System.Text.UTF8Encoding($false)))
        $before = Get-FileDigest $existing
        $result = Invoke-FakeRegistration $fx
        @($result.Already) | Should -Contain 'ALPHA'
        Get-FileDigest $existing | Should -Be $before
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Mappings).Count | Should -Be 0
        @($op.Units)[0].State | Should -Be 'SKIPPED'
        @($op.Units)[0].Reason | Should -Be 'NO_PROFILE_WRITE_EXISTING_PROFILE_OR_UNRESOLVED'
    }

    It 'reports an unmatched folder as a reasoned skip' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [void](Add-FakeGame $fx 'Mystery' 'mystery.exe' 'MYSTERY' -NoTemplate)
        [void](Invoke-FakeRegistration $fx)
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Units).Count | Should -Be 2
        $mystery = @($op.Units | Where-Object Folder -eq 'Mystery')[0]
        $mystery.State | Should -Be 'SKIPPED'
        $mystery.Reason | Should -Be 'NO_PROFILE_MATCH'
        @($op.Units | Where-Object Folder -eq 'Alpha Game')[0].State | Should -Be 'VERIFIED'
    }

    It 'does not treat an injected readback failure as success' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        Mock Assert-TpmRegisteredGamePath { throw 'injected readback failure' }
        $result = Invoke-FakeRegistration $fx
        $result.Outcome | Should -Not -Be 'SUCCEEDED'
        @($result.Registered).Count | Should -Be 0
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Mappings)[0].State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
        @($op.Mappings)[0].Readback | Should -BeFalse
        @($op.Units)[0].State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
    }

    It 'keeps duplicate claims visible and associated with their own unit' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [void](Add-FakeGame $fx 'Alpha Game Rev B' 'alpha.exe' 'ALPHA')
        $result = Invoke-FakeRegistration $fx
        @($result.Ambiguous).Count | Should -Be 1
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Units).Count | Should -Be 2
        (@($op.Units | ForEach-Object State) | Sort-Object) -join ',' | Should -Be 'SKIPPED,VERIFIED'
        @($op.Mappings).Count | Should -Be 2
        (@($op.Mappings | ForEach-Object State) | Sort-Object) -join ',' | Should -Be 'SKIPPED,VERIFIED'
        @($op.Mappings | ForEach-Object UnitId | Select-Object -Unique).Count | Should -Be 2
        $skipped = @($op.Mappings | Where-Object State -eq 'SKIPPED')[0]
        $skipped.Reason | Should -Match 'DUPLICATE_PROFILE_CLAIM'
        foreach ($unit in @($op.Units)) { $unit.State | Should -Not -Be 'PENDING' }
    }

    It 'derives unit state from its mappings without hiding mixed or unknown results' {
        Get-TpmLedgerDerivedUnitState -Mappings @([pscustomobject]@{ State = 'VERIFIED' }, [pscustomobject]@{ State = 'VERIFIED' }) | Should -Be 'VERIFIED'
        Get-TpmLedgerDerivedUnitState -Mappings @([pscustomobject]@{ State = 'VERIFIED' }, [pscustomobject]@{ State = 'FAILED_BEFORE_WRITE' }) | Should -Be 'PARTIAL'
        Get-TpmLedgerDerivedUnitState -Mappings @([pscustomobject]@{ State = 'VERIFIED' }, [pscustomobject]@{ State = 'SKIPPED' }) | Should -Be 'PARTIAL'
        Get-TpmLedgerDerivedUnitState -Mappings @([pscustomobject]@{ State = 'VERIFIED' }, [pscustomobject]@{ State = 'WRITE_ATTEMPTED_UNVERIFIED' }) | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
        Get-TpmLedgerDerivedUnitState -Mappings @([pscustomobject]@{ State = 'FAILED_BEFORE_WRITE' }) | Should -Be 'FAILED_BEFORE_WRITE'
        Get-TpmLedgerDerivedUnitState -Mappings @([pscustomobject]@{ State = 'SKIPPED' }) | Should -Be 'SKIPPED'
        Get-TpmLedgerDerivedUnitState -Mappings @() | Should -Be 'PENDING'
    }

    It 'never downgrades a verified mapping because of a later error' {
        $fx = New-LedgerFixture
        $open = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units @([pscustomobject]@{ Folder = 'Alpha Game' }) -InstallRoot $fx.Games
        $open.Opened | Should -BeTrue
        $id = Start-TpmRegistrationMapping -Folder 'Alpha Game' -Code 'ALPHA' -Match 'exe-single' -IntendedPath (Join-Path $fx.Games 'Alpha Game\alpha.exe') -TemplatePath 'ALPHA.xml'
        Complete-TpmRegistrationMapping -MappingId $id -Outcome VERIFIED
        Complete-TpmRegistrationMapping -MappingId $id -Outcome FAILED -WriteAttempted $true -Reason 'late error'
        @(@($script:TpmRegistrationLedger.Document.Operations)[0].Mappings)[0].State | Should -Be 'VERIFIED'
    }
}

Describe 'Secondary-executable backfill ledger record' {
    BeforeAll {
        function Add-BackfillProfile {
            # An existing profile whose GamePath is the game exe; the second exe sits next to it.
            param($Fixture, [string]$Folder, [string]$Code, [string]$Exe, [string]$Exe2, [switch]$GamePath2Set)
            $exePath = Join-Path (Join-Path $Fixture.Games $Folder) $Exe
            $exe2Path = Join-Path (Join-Path $Fixture.Games $Folder) $Exe2
            [IO.File]::WriteAllBytes($exe2Path, [byte[]](4, 5, 6))
            $gp2 = if ($GamePath2Set) { '<GamePath2>' + [System.Security.SecurityElement]::Escape($exe2Path) + '</GamePath2>' } else { '' }
            $xml = '<GameProfile><GamePath>' + [System.Security.SecurityElement]::Escape($exePath) + '</GamePath><HasTwoExecutables>true</HasTwoExecutables><ExecutableName2>' + $Exe2 + '</ExecutableName2>' + $gp2 + '</GameProfile>'
            $profilePath = Join-Path $Fixture.Profiles ($Code + '.xml')
            [IO.File]::WriteAllText($profilePath, $xml, (New-Object System.Text.UTF8Encoding($false)))
            return [pscustomobject]@{ ProfilePath = $profilePath; Exe2Path = $exe2Path }
        }
    }
    AfterEach { Reset-LedgerScriptState }

    It 'records one VERIFIED secondary-backfill mapping and a VERIFIED unit for a verified backfill' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        $existing = Add-BackfillProfile $fx 'Alpha Game' 'ALPHA' 'alpha.exe' 'alpha2.exe'
        $result = Invoke-FakeRegistration $fx
        $result.Outcome | Should -Be 'SUCCEEDED'
        ([xml](Get-Content -LiteralPath $existing.ProfilePath -Raw)).GameProfile.GamePath2 | Should -Be $existing.Exe2Path
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Mappings).Count | Should -Be 1
        $mapping = @($op.Mappings)[0]
        $mapping.Match | Should -Be 'secondary-backfill'
        $mapping.Code | Should -Be 'ALPHA'
        $mapping.State | Should -Be 'VERIFIED'
        $mapping.Readback | Should -BeTrue
        $mapping.IntendedPath | Should -Be 'Alpha Game\alpha.exe'
        @($op.Units).Count | Should -Be 1
        @($op.Units)[0].State | Should -Be 'VERIFIED'
        $mapping.UnitId | Should -Be (@($op.Units)[0].UnitId)
        @($op.Units)[0].PSObject.Properties['Reason'] | Should -BeNullOrEmpty
    }

    It 'records a non-verified mapping and unit when the backfilled profile does not read back' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [void](Add-BackfillProfile $fx 'Alpha Game' 'ALPHA' 'alpha.exe' 'alpha2.exe')
        Mock Assert-TpmRegisteredGamePath { throw 'injected backfill readback failure' }
        $result = Invoke-FakeRegistration $fx
        $result.Outcome | Should -Not -Be 'SUCCEEDED'
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Mappings).Count | Should -Be 1
        $mapping = @($op.Mappings)[0]
        $mapping.Match | Should -Be 'secondary-backfill'
        $mapping.State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
        $mapping.Readback | Should -BeFalse
        $mapping.Reason | Should -Match 'injected backfill readback failure'
        @($op.Units)[0].State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
    }

    It 'records a FAILED_BEFORE_WRITE mapping and leaves the profile unchanged when the backfill save fails' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        $existing = Add-BackfillProfile $fx 'Alpha Game' 'ALPHA' 'alpha.exe' 'alpha2.exe'
        $before = Get-FileDigest $existing.ProfilePath
        Mock Save-Xml { throw 'injected backfill save failure' }
        $result = Invoke-FakeRegistration $fx
        $result.Outcome | Should -Not -Be 'SUCCEEDED'
        Get-FileDigest $existing.ProfilePath | Should -Be $before
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Mappings).Count | Should -Be 1
        $mapping = @($op.Mappings)[0]
        $mapping.Match | Should -Be 'secondary-backfill'
        $mapping.State | Should -Be 'FAILED_BEFORE_WRITE'
        $mapping.Readback | Should -BeFalse
        $mapping.Reason | Should -Match 'injected backfill save failure'
        @($op.Units)[0].State | Should -Be 'FAILED_BEFORE_WRITE'
    }

    It 'keeps the existing-profile skip when the backfill has nothing to write' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        $existing = Add-BackfillProfile $fx 'Alpha Game' 'ALPHA' 'alpha.exe' 'alpha2.exe' -GamePath2Set
        $before = Get-FileDigest $existing.ProfilePath
        $result = Invoke-FakeRegistration $fx
        @($result.Already) | Should -Contain 'ALPHA'
        Get-FileDigest $existing.ProfilePath | Should -Be $before
        $op = @((Get-LedgerDocument $fx).Operations)[0]
        @($op.Mappings).Count | Should -Be 0
        @($op.Units)[0].State | Should -Be 'SKIPPED'
        @($op.Units)[0].Reason | Should -Be 'NO_PROFILE_WRITE_EXISTING_PROFILE_OR_UNRESOLVED'
    }
}

Describe 'Publication failure after a product write' {
    AfterEach { Reset-LedgerScriptState }

    It 'keeps refusing manual and duplicate follow-ups after a publication failure even when later publishes succeed' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [void](Add-FakeGame $fx 'Beta Game' 'beta.exe' 'BETA')
        $sharedDir = Join-Path $fx.Games 'Shared Game'
        New-Item -ItemType Directory -Path $sharedDir -Force | Out-Null
        $sharedExe = Join-Path $sharedDir 'shared.exe'
        [IO.File]::WriteAllBytes($sharedExe, [byte[]](1, 2, 3))
        [IO.File]::WriteAllText((Join-Path $fx.Templates 'GAMMA.xml'), '<GameProfile><ExecutableName>gamma.exe</ExecutableName><ConfigValues></ConfigValues></GameProfile>', (New-Object System.Text.UTF8Encoding($false)))
        $script:RealPublish = ${function:Publish-TpmRegistrationLedgerDocument}
        $script:publishCalls = 0
        # Exactly one publish fails (the post-write boundary); every later publish, including Close, succeeds.
        Mock Publish-TpmRegistrationLedgerDocument {
            $script:publishCalls++
            if ($script:publishCalls -eq 3) { return [pscustomobject]@{ Published = $false; Reason = 'injected one-time publication failure'; Bytes = 0 } }
            & $script:RealPublish -Path $Path -Document $Document -MaximumBytes $MaximumBytes
        }
        Mock Read-Host { throw 'a refused follow-up must not prompt' }
        $result = Invoke-FakeRegistration $fx
        $result.LedgerEvidence.Stopped | Should -BeTrue
        $script:TpmRegistrationLedger | Should -BeNullOrEmpty
        # Close cleared the ledger context, but the workflow latch must survive it.
        Test-TpmRegistrationLedgerStopped | Should -BeTrue
        $profilesBefore = @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.xml' -File).Count
        $manual = @{ 'Shared Game' = @{ Exe = $sharedExe; Profiles = 'GAMMA' } }
        $after = Invoke-ManualRegistrationChoices -ManualRegData $manual -UserProfilesDir $fx.Profiles -GameProfilesDir $fx.Templates -InstallFolder $fx.Games -Result $result
        [object]::ReferenceEquals($after, $result) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $fx.Profiles 'GAMMA.xml')) | Should -BeFalse
        @(Get-ChildItem -LiteralPath $fx.Profiles -Filter '*.xml' -File).Count | Should -Be $profilesBefore
        # The duplicate-switch block opens its operation through the same gate.
        $duplicate = Open-TpmRegistrationLedgerOperation -Mode ManualChoice -Units @([pscustomobject]@{ Folder = 'Shared Game' }) -InstallRoot $fx.Games
        $duplicate.Opened | Should -BeFalse
        $duplicate.Status | Should -Be 'Stopped'
        { Start-TpmRegistrationMapping -Folder 'Shared Game' -Code 'GAMMA' -Match 'manual-choice' -IntendedPath $sharedExe -TemplatePath 'GAMMA.xml' } | Should -Throw
        Test-TpmRegistrationLedgerReady | ForEach-Object Ready | Should -BeFalse
        # A new menu workflow starts clean.
        Reset-TpmRegistrationLedgerStopLatch
        (Open-TpmRegistrationLedgerOperation -Mode ManualChoice -Units @([pscustomobject]@{ Folder = 'Shared Game' }) -InstallRoot $fx.Games).Opened | Should -BeTrue
    }
}

Describe 'Restart and fatal evidence' {
    AfterEach { Reset-LedgerScriptState }
    It 'marks an open prior operation INTERRUPTED_UNKNOWN on restart and never as success' {
        $fx = New-LedgerFixture
        $first = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units @([pscustomobject]@{ Folder = 'Alpha Game' }, [pscustomobject]@{ Folder = 'Beta Game' }) -InstallRoot $fx.Games
        $first.Opened | Should -BeTrue
        $mappingId = Start-TpmRegistrationMapping -Folder 'Alpha Game' -Code 'ALPHA' -Match 'exe-single' -IntendedPath (Join-Path $fx.Games 'Alpha Game\alpha.exe') -TemplatePath 'ALPHA.xml'
        $mappingId | Should -Not -BeNullOrEmpty
        # The process dies here: its in-memory context is gone and the next run has a new run id.
        $script:TpmRegistrationLedger = $null
        $script:TpmSessionRunId = 'restartedrun00000000000000000001'
        $second = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units @() -InstallRoot $fx.Games
        $second.Opened | Should -BeTrue
        $doc = Get-LedgerDocument $fx
        @($doc.Operations).Count | Should -Be 2
        $old = @($doc.Operations | Where-Object OperationId -eq $first.OperationId)[0]
        $old.State | Should -Be 'INTERRUPTED_UNKNOWN'
        foreach ($unit in @($old.Units)) { $unit.State | Should -Be 'INTERRUPTED_UNKNOWN' }
        @($old.Mappings)[0].State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
        ($doc | ConvertTo-Json -Depth 10 -Compress) | Should -Not -Match '"State":"VERIFIED"'
        @($doc.Operations | Where-Object OperationId -eq $second.OperationId)[0].State | Should -Be 'PENDING'
    }

    It 'appends a bounded, redacted fatal record correlated to the run and open operations' {
        $fx = New-LedgerFixture
        $open = Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units @([pscustomobject]@{ Folder = 'Alpha Game' }) -InstallRoot $fx.Games
        # The filler goes BEFORE the profile path: the redactor replaces a user-profile path and everything after it on the line, so filler after it would be redacted away and never reach the 500-character limit.
        $message = 'boom password=hunter2 ' + ('x' * 900) + ' at C:\Users\Bob\x.ps1'
        Add-TpmRegistrationLedgerFatal -Message $message -ExceptionType 'System.InvalidOperationException' | Should -BeTrue
        $doc = Get-LedgerDocument $fx
        @($doc.Fatals).Count | Should -Be 1
        $fatal = @($doc.Fatals)[0]
        $fatal.RunId | Should -Be (Get-TpmSessionRunId)
        $fatal.Message | Should -Match 'redacted'
        $fatal.Message | Should -Not -Match 'hunter2|Bob'
        $fatal.MessageTruncated | Should -BeTrue
        $fatal.Message.Length | Should -BeLessOrEqual 500
        @($fatal.OpenOperationIds) | Should -Contain $open.OperationId
        # A fatal record is separate from per-game outcomes.
        @($doc.Operations)[0].State | Should -Be 'PENDING'
    }

    It 'never overwrites an unusable ledger with a fatal record' {
        $fx = New-LedgerFixture
        [IO.File]::WriteAllText($fx.Ledger, '{ corrupt', (New-Object System.Text.UTF8Encoding($false)))
        $before = Get-FileDigest $fx.Ledger
        Add-TpmRegistrationLedgerFatal -Message 'boom' | Should -BeFalse
        Get-FileDigest $fx.Ledger | Should -Be $before
    }

    It 'exports interrupted work, fatal evidence and transaction facts as separate redacted metadata' {
        $fx = New-LedgerFixture
        [void](Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units @([pscustomobject]@{ Folder = 'Alpha Game' }) -InstallRoot $fx.Games)
        $absolute = 'C:\Users\Bob\Elsewhere\alpha.exe'
        [void](Start-TpmRegistrationMapping -Folder 'Alpha Game' -Code 'ALPHA' -Match 'exe-single' -IntendedPath $absolute -TemplatePath 'ALPHA.xml')
        $script:TpmRegistrationLedger = $null
        $script:TpmSessionRunId = 'otherrun00000000000000000000002'
        [void](Add-TpmRegistrationLedgerFatal -Message 'late fatal password=hunter2')
        $package = Invoke-FakeSupportPackage $fx
        $package.Succeeded | Should -BeTrue
        $ledgerText = Get-SupportZipText $package.PackagePath 'metadata/registration-ledger.json'
        $ledger = $ledgerText | ConvertFrom-Json
        @($ledger.Operations)[0].State | Should -Match '^INTERRUPTED_UNKNOWN \(derived'
        @($ledger.Operations)[0].StoredState | Should -Be 'PENDING'
        @($ledger.Operations)[0].RunId | Should -Not -Be (Get-TpmSessionRunId)
        @(@($ledger.Operations)[0].Units)[0].State | Should -Match '^INTERRUPTED_UNKNOWN'
        @(@($ledger.Operations)[0].Mappings)[0].State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
        @(@($ledger.Operations)[0].Mappings)[0].IntendedPath | Should -Be '<absolute>\alpha.exe'
        $ledgerText | Should -Not -Match 'Bob|hunter2'
        $ledgerText | Should -Not -Match '"State":\s*"VERIFIED"'
        $fatalText = Get-SupportZipText $package.PackagePath 'metadata/fatal-record.json'
        $fatalText | Should -Not -Match 'hunter2'
        (($fatalText | ConvertFrom-Json).Fatals | Measure-Object).Count | Should -Be 1
        (Get-SupportZipText $package.PackagePath 'metadata/transaction-facts.json') | Should -Not -BeNullOrEmpty
        (Get-SupportZipText $package.PackagePath 'MANIFEST.txt') | Should -Match 'INTERRUPTED_UNKNOWN \(derived'
    }
}

Describe 'Support profile inventory' {
    AfterEach { Reset-LedgerScriptState }
    It 'lists every profile with a disposition, bounds per-game collection and marks the package partial' {
        $fx = New-LedgerFixture
        Add-ProfileFile $fx 'A_Broken'
        [IO.File]::WriteAllText((Join-Path $fx.Profiles 'A_Broken.xml'), '<not xml', (New-Object System.Text.UTF8Encoding($false)))
        Add-ProfileFile $fx 'A_NoPath' '<none>'
        Add-ProfileFile $fx 'A_Outside' (Join-Path $fx.Root 'Elsewhere\game.exe')
        foreach ($index in 1..8) { Add-ProfileFile $fx ('G{0}' -f $index) }
        $package = Invoke-FakeSupportPackage $fx @{ MaximumGameCollections = 3 }
        $package.Succeeded | Should -BeTrue
        $package.Partial | Should -BeTrue
        $inventory = (Get-SupportZipText $package.PackagePath 'metadata/profile-inventory.json') | ConvertFrom-Json
        $inventory.EnumerationComplete | Should -BeTrue
        $inventory.Discovered | Should -Be 11
        $inventory.DispositionCounts.SNAPSHOT_INCLUDED | Should -Be 3
        $inventory.DispositionCounts.UNREADABLE_OR_MALFORMED | Should -Be 1
        $inventory.DispositionCounts.NOT_PRESENT | Should -Be 1
        $inventory.DispositionCounts.INTENTIONALLY_OMITTED | Should -Be 6
        $inventory.OmittedByCollectionLimit | Should -Be 5
        @($inventory.Profiles).Count | Should -Be 11
        @($package.PartialReasons) -join ' ' | Should -Match 'limited to 3'
        (Get-SupportZipText $package.PackagePath 'MANIFEST.txt') | Should -Match 'PARTIAL EVIDENCE'
    }

    It 'inventories more than 200 profiles and states exactly what was omitted' {
        $fx = New-LedgerFixture
        foreach ($index in 1..205) { Add-ProfileFile $fx ('P{0:D3}' -f $index) }
        $package = Invoke-FakeSupportPackage $fx
        $package.Succeeded | Should -BeTrue
        $inventory = (Get-SupportZipText $package.PackagePath 'metadata/profile-inventory.json') | ConvertFrom-Json
        $inventory.Discovered | Should -Be 205
        @($inventory.Profiles).Count | Should -Be 205
        $inventory.DispositionCounts.SNAPSHOT_INCLUDED | Should -Be 200
        $inventory.OmittedByCollectionLimit | Should -Be 5
        $package.Partial | Should -BeTrue
    }

    It 'collects ledger-affected profiles first and correlates them with the verified saved mapping' {
        $fx = New-LedgerFixture
        [void](Add-FakeGame $fx 'Alpha Game' 'alpha.exe' 'ALPHA')
        [void](Invoke-FakeRegistration $fx)
        foreach ($index in 1..6) { Add-ProfileFile $fx ('A{0}' -f $index) }
        $package = Invoke-FakeSupportPackage $fx @{ MaximumGameCollections = 1 }
        $inventory = (Get-SupportZipText $package.PackagePath 'metadata/profile-inventory.json') | ConvertFrom-Json
        $row = @($inventory.Profiles | Where-Object Code -eq 'ALPHA')[0]
        $row.LedgerAffected | Should -BeTrue
        $row.Disposition | Should -Be 'SNAPSHOT_INCLUDED'
        $row.LedgerMappings | Should -Be 'VERIFIED/MATCHES_INTENT'
        @($inventory.Profiles | Where-Object { $_.Code -ne 'ALPHA' -and $_.Disposition -eq 'SNAPSHOT_INCLUDED' }).Count | Should -Be 0
        (Get-SupportZipText $package.PackagePath 'metadata/profile-ALPHA.txt') | Should -Match 'GamePath'
    }

    It 'does not say a profile snapshot is in the package when it could not be written' {
        # Mutation: set the disposition to SNAPSHOT_INCLUDED without looking at the result of Write-TpmSupportProfileSnapshot -> the inventory names a file the package does not have.
        $fx = New-LedgerFixture
        Add-ProfileFile $fx 'BrokenWrite'
        Mock Get-TpmSupportProfileSnapshotText { throw 'simulated write failure' }
        $package = Invoke-FakeSupportPackage $fx
        $package.Succeeded | Should -BeTrue
        $inventory = (Get-SupportZipText $package.PackagePath 'metadata/profile-inventory.json') | ConvertFrom-Json
        $inventory.DispositionCounts.SNAPSHOT_INCLUDED | Should -Be 0
        @($inventory.Profiles | Where-Object Code -eq 'BrokenWrite')[0].Disposition | Should -Not -Be 'SNAPSHOT_INCLUDED'
    }

    It 'reports an unfinished enumeration as partial without overwriting a product failure' {
        $fx = New-LedgerFixture
        [void](Open-TpmRegistrationLedgerOperation -Mode RegisterOnly -Units @([pscustomobject]@{ Folder = 'Alpha Game' }) -InstallRoot $fx.Games)
        $id = Start-TpmRegistrationMapping -Folder 'Alpha Game' -Code 'ALPHA' -Match 'exe-single' -IntendedPath (Join-Path $fx.Games 'Alpha Game\alpha.exe') -TemplatePath 'ALPHA.xml'
        Complete-TpmRegistrationMapping -MappingId $id -Outcome FAILED -WriteAttempted $true -Reason 'saved profile did not read back'
        [void](Close-TpmRegistrationLedgerOperations -Reason 'TEST')
        Mock Get-TpmSupportProfileFiles { [pscustomobject]@{ Files = @(); EnumerationFailure = 'injected enumeration failure' } }
        $package = Invoke-FakeSupportPackage $fx
        $package.Succeeded | Should -BeTrue
        $package.Partial | Should -BeTrue
        @($package.PartialReasons) -join ' ' | Should -Match 'injected enumeration failure'
        @($package.Records | Where-Object { $_.Status -eq 'CollectionFailed' }).Count | Should -BeGreaterThan 0
        $inventory = (Get-SupportZipText $package.PackagePath 'metadata/profile-inventory.json') | ConvertFrom-Json
        $inventory.EnumerationComplete | Should -BeFalse
        $ledger = (Get-SupportZipText $package.PackagePath 'metadata/registration-ledger.json') | ConvertFrom-Json
        @(@($ledger.Operations)[0].Mappings)[0].State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
        @(@($ledger.Operations)[0].Units)[0].State | Should -Be 'WRITE_ATTEMPTED_UNVERIFIED'
    }

    It 'marks the package partial when support metadata exceeds its size limit' {
        $fx = New-LedgerFixture
        Add-ProfileFile $fx 'G1'
        $package = Invoke-FakeSupportPackage $fx @{ MaximumMetadataBytes = 50 }
        $package.Succeeded | Should -BeTrue
        $package.Partial | Should -BeTrue
        @($package.PartialReasons) -join ' ' | Should -Match 'support metadata limit'
        @($package.Records | Where-Object { $_.Status -eq 'CollectionFailed' -and $_.Source -like 'Metadata:*' }).Count | Should -BeGreaterThan 0
    }

    It 'reports a corrupt ledger as a distinct collection problem, not a workflow result' {
        $fx = New-LedgerFixture
        [IO.File]::WriteAllText($fx.Ledger, '{ corrupt', (New-Object System.Text.UTF8Encoding($false)))
        $package = Invoke-FakeSupportPackage $fx
        $package.Succeeded | Should -BeTrue
        $package.Partial | Should -BeTrue
        @($package.PartialReasons) -join ' ' | Should -Match 'Registration ledger could not be collected: Corrupt'
        $ledger = (Get-SupportZipText $package.PackagePath 'metadata/registration-ledger.json') | ConvertFrom-Json
        $ledger.Status | Should -Be 'Corrupt'
        @($ledger.Operations).Count | Should -Be 0
    }

    It 'stays non-partial when there is no ledger and nothing to inventory' {
        $fx = New-LedgerFixture
        $package = New-TpmSupportPackage -ScriptRoot $fx.Script -OutputRoot (Join-Path $fx.Script 'SupportPackages')
        $package.Succeeded | Should -BeTrue
        $package.Partial | Should -BeFalse
        $inventory = (Get-SupportZipText $package.PackagePath 'metadata/profile-inventory.json') | ConvertFrom-Json
        $inventory.Applicable | Should -BeFalse
        ((Get-SupportZipText $package.PackagePath 'metadata/registration-ledger.json') | ConvertFrom-Json).Status | Should -Be 'Missing'
    }
}

Describe 'Runtime artifact identity' {
    AfterEach { Reset-LedgerScriptState }
    It 'hashes the exact script and reports unavailable package identity without inferring it' {
        $dir = Join-Path $TestDrive ('identity-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $fake = Join-Path $dir 'TeknoParrot-Manager.ps1'
        [IO.File]::WriteAllText($fake, '# fake running script v1.0 RC8', (New-Object System.Text.UTF8Encoding($false)))
        $identity = Get-TpmRuntimeArtifactIdentity -ScriptPath $fake
        $identity.ScriptStatus | Should -Be 'captured'
        $identity.ScriptSha256 | Should -Be (Get-FileHash -LiteralPath $fake -Algorithm SHA256).Hash
        $identity.ScriptLength | Should -Be (Get-Item -LiteralPath $fake).Length
        $identity.ManagerVersionLabel | Should -Be 'v1.0 RC8'
        $identity.PackageManifestStatus | Should -Be 'unavailable'
        $identity.PackageId | Should -Be 'unavailable'
        $identity.SourceCommit | Should -Be 'unavailable'
        $identity.PackageManifestSha256 | Should -Be 'unavailable'
        $identity.PowerShellVersion | Should -Be $PSVersionTable.PSVersion.ToString()
    }

    It 'reads package and commit identity only from the distribution manifest' {
        $dir = Join-Path $TestDrive ('identity-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $fake = Join-Path $dir 'TeknoParrot-Manager.ps1'
        [IO.File]::WriteAllText($fake, '# fake', (New-Object System.Text.UTF8Encoding($false)))
        $manifest = Join-Path $dir 'TPM-PackageIdentity.json'
        $commit = ('0123456789abcdef' * 3).Substring(0, 40)
        [IO.File]::WriteAllText($manifest, ('{{"PackageId":"tpm-rc8-test","SourceCommit":"{0}"}}' -f $commit), (New-Object System.Text.UTF8Encoding($false)))
        $identity = Get-TpmRuntimeArtifactIdentity -ScriptPath $fake
        $identity.PackageManifestStatus | Should -Be 'present'
        $identity.PackageId | Should -Be 'tpm-rc8-test'
        $identity.SourceCommit | Should -Be $commit
        $identity.PackageManifestSha256 | Should -Be (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
    }

    It 'rejects a malformed commit and never turns the RC label into one' {
        $dir = Join-Path $TestDrive ('identity-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $fake = Join-Path $dir 'TeknoParrot-Manager.ps1'
        [IO.File]::WriteAllText($fake, '# fake', (New-Object System.Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText((Join-Path $dir 'TPM-PackageIdentity.json'), '{"PackageId":"tpm-rc8-test","SourceCommit":"RC8"}', (New-Object System.Text.UTF8Encoding($false)))
        $identity = Get-TpmRuntimeArtifactIdentity -ScriptPath $fake
        $identity.SourceCommit | Should -Be 'unavailable'
        $identity.ManagerVersionLabel | Should -Be 'v1.0 RC8'
        $malformed = Join-Path $dir 'TPM-PackageIdentity.json'
        [IO.File]::WriteAllText($malformed, '{ not json', (New-Object System.Text.UTF8Encoding($false)))
        (Get-TpmRuntimeArtifactIdentity -ScriptPath $fake).PackageManifestStatus | Should -Match '^unavailable'
    }

    It 'reports an unavailable script path instead of inventing a digest' {
        $identity = Get-TpmRuntimeArtifactIdentity -ScriptPath (Join-Path $TestDrive 'does-not-exist.ps1')
        $identity.ScriptStatus | Should -Match '^unavailable'
        $identity.ScriptSha256 | Should -Be 'unavailable'
        (Get-TpmRuntimeArtifactIdentity -ScriptPath '').ScriptStatus | Should -Match '^unavailable'
    }

    It 'exports the supplied identity into the support package' {
        $fx = New-LedgerFixture
        $fake = Join-Path $fx.Root 'TeknoParrot-Manager.ps1'
        [IO.File]::WriteAllText($fake, '# fake running script', (New-Object System.Text.UTF8Encoding($false)))
        $identity = Get-TpmRuntimeArtifactIdentity -ScriptPath $fake
        $package = Invoke-FakeSupportPackage $fx @{ RuntimeIdentity = $identity }
        $exported = (Get-SupportZipText $package.PackagePath 'metadata/runtime-identity.json') | ConvertFrom-Json
        $exported.ScriptSha256 | Should -Be $identity.ScriptSha256
        $exported.SourceCommit | Should -Be 'unavailable'
        $exported.PackageId | Should -Be 'unavailable'
        (Get-SupportZipText $package.PackagePath 'MANIFEST.txt') | Should -Match ([regex]::Escape($identity.ScriptSha256))
    }
}
