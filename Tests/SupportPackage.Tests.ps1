#Requires -Module Pester

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Support package test bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'tpm-support-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'test.log'
    $script:logWarnShown = $false
    $script:logFailedCount = 0

    function New-SupportFixture {
        $root = Join-Path $TestDrive ('support-' + [guid]::NewGuid().ToString('N'))
        $scriptRoot = Join-Path $root 'Scripts'
        $tpRoot = Join-Path $root 'TeknoParrot'
        $gamesRoot = Join-Path $root 'Games'
        $profiles = Join-Path $tpRoot 'UserProfiles'
        $output = Join-Path $scriptRoot 'SupportPackages'
        New-Item -ItemType Directory -Path $scriptRoot,$tpRoot,$gamesRoot,$profiles,$output -Force | Out-Null
        return [pscustomobject]@{ Root=$root; Script=$scriptRoot; Tp=$tpRoot; Games=$gamesRoot; Profiles=$profiles; Output=$output }
    }

    function Write-SupportText {
        param([string]$Path,[string]$Text)
        $parent = [System.IO.Path]::GetDirectoryName($Path)
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($Path,$Text,(New-Object System.Text.UTF8Encoding($false)))
    }

    function Add-SupportGame {
        param($Fixture,[string]$Code='TMNT')
        $gameRoot = Join-Path $Fixture.Games $Code
        New-Item -ItemType Directory -Path $gameRoot -Force | Out-Null
        $exe = Join-Path $gameRoot ($Code + '.exe')
        [System.IO.File]::WriteAllBytes($exe,[byte[]](1,2,3,4))
        Write-SupportText -Path (Join-Path $Fixture.Profiles ($Code + '.xml')) -Text ('<GameProfile><GamePath>' + $exe + '</GamePath></GameProfile>')
        return $gameRoot
    }

    function Get-SupportZipEntries {
        param([string]$Path)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { return @($zip.Entries | ForEach-Object FullName) } finally { $zip.Dispose() }
    }

    function Get-SupportZipText {
        param([string]$Path,[string]$EntryName)
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $entry = $zip.GetEntry($EntryName)
            if (-not $entry) { return $null }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally { $zip.Dispose() }
    }
}

Describe 'New-TpmSupportPackage' {
    It 'collects TPM diagnostics into one support ZIP' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Script 'TeknoParrot-Manager.log') 'TPM failure: password=topsecret'
        Write-SupportText (Join-Path $f.Script 'TeknoParrot-Manager-ActionItems.txt') 'Controls: Not verified'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $entries = Get-SupportZipEntries $r.PackagePath
        $entries | Should -Contain 'MANIFEST.txt'
        @($entries | Where-Object { ($_ -replace '\\','/') -like 'diagnostics/tpm-*' }).Count | Should -BeGreaterThan 0
    }

    It 'collects allowlisted TeknoParrot diagnostics including ParrotPatcher_Log.txt' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Tp 'ParrotPatcher_Log.txt') 'launcher error'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        @((Get-SupportZipEntries $r.PackagePath) | Where-Object { ($_ -replace '\\','/') -like 'diagnostics/tekno-*' }).Count | Should -BeGreaterThan 0
    }

    It 'collects game-local BepInEx LogOutput.log' {
        $f = New-SupportFixture
        $game = Add-SupportGame $f
        Write-SupportText (Join-Path $game 'BepInEx\LogOutput.log') 'BepInEx startup failed'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $entries = Get-SupportZipEntries $r.PackagePath
        @($entries | Where-Object { ($_ -replace '\\','/') -eq 'diagnostics/game-TMNT-BepInEx_LogOutput.log' }).Count | Should -Be 1
    }

    It 'generates metadata-only plugin inventories' {
        $f = New-SupportFixture
        $game = Add-SupportGame $f
        New-Item -ItemType Directory -Path (Join-Path $game 'BepInEx\plugins'),(Join-Path $game 'TMNT_Data\Plugins\x86_64') -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $game 'BepInEx\plugins\TMNTTPPlugin.dll'),[byte[]](1,2,3))
        [System.IO.File]::WriteAllBytes((Join-Path $game 'TMNT_Data\Plugins\x86_64\OrenVid.dll'),[byte[]](4,5,6))
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $entries = Get-SupportZipEntries $r.PackagePath
        $inventoryEntry = @($entries | Where-Object { ($_ -replace '\\','/') -like 'metadata/inventory-TMNT.tsv' })
        $inventory = Get-SupportZipText $r.PackagePath $inventoryEntry[0]
        $inventory | Should -Match 'TMNTTPPlugin.dll'
        $inventory | Should -Match 'OrenVid.dll'
        $entries | Where-Object { $_ -match '\.(dll|exe)$' } | Should -BeNullOrEmpty
    }

    It 'does not collect forbidden binaries or arbitrary game content' {
        $f = New-SupportFixture
        $game = Add-SupportGame $f
        [System.IO.File]::WriteAllBytes((Join-Path $game 'game.dll'),[byte[]](1,2,3))
        [System.IO.File]::WriteAllBytes((Join-Path $game 'game.exe'),[byte[]](4,5,6))
        Write-SupportText (Join-Path $game 'ROM.zip') 'not a real archive'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        @((Get-SupportZipEntries $r.PackagePath) | Where-Object { $_ -match '\.(dll|exe|zip)$' }).Count | Should -Be 0
    }

    It 'excludes credential and recovery-state files' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Script '.pgpass') 'localhost:5432:*:postgres:secret'
        Write-SupportText (Join-Path $f.Script 'TeknoParrot-Manager.config.json') '{"password":"secret"}'
        Write-SupportText (Join-Path $f.Script '.tpm-postgres-recovery-12345678901234567890123456789012.json') 'secret'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $entries = Get-SupportZipEntries $r.PackagePath
        $entries | Where-Object { $_ -match 'pgpass|config|recovery' } | Should -BeNullOrEmpty
    }

    It 'redacts common credentials and user-profile paths from text' {
        $f = New-SupportFixture
        $secret = 'password=topsecret token=abc123 postgres://user:pw@host/db C:\Users\EliSi\private'
        Write-SupportText (Join-Path $f.Script 'TeknoParrot-Manager.log') $secret
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $entries = @((Get-SupportZipEntries $r.PackagePath) | Where-Object { $_ -like 'diagnostics/tpm-*' })
        $text = Get-SupportZipText $r.PackagePath $entries[0]
        $text | Should -Not -Match 'topsecret|abc123|user:pw|EliSi'
        $r.RedactionCount | Should -BeGreaterThan 0
    }

    It 'succeeds when optional diagnostics are absent and records them as not present' {
        $f = New-SupportFixture
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $r.Partial | Should -BeFalse
        @($r.Records | Where-Object Status -eq 'NotPresent').Count | Should -BeGreaterThan 0
    }

    It 'creates a partial package when one registered profile is malformed' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Profiles 'Broken.xml') '<not xml'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $r.Partial | Should -BeTrue
        @($r.Records | Where-Object Status -eq 'CollectionFailed').Count | Should -BeGreaterThan 0
    }

    It 'reports ZIP creation failure without claiming success' {
        $f = New-SupportFixture
        $badOutput = Join-Path $f.Root 'not-a-folder'
        Write-SupportText $badOutput 'file'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $badOutput
        $r.Succeeded | Should -BeFalse
        $r.PackagePath | Should -BeNullOrEmpty
        $r.Errors.Count | Should -BeGreaterThan 0
    }

    It 'cleans workflow status on both success and failure' {
        $f = New-SupportFixture
        $success = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $success.StatusContext.Closed | Should -BeTrue
        $script:ActiveTpmWorkflowStatus | Should -BeNullOrEmpty
        $badOutput = Join-Path $f.Root 'bad-output'
        Write-SupportText $badOutput 'file'
        $failure = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $badOutput
        $failure.StatusContext.Closed | Should -BeTrue
        $script:ActiveTpmWorkflowStatus | Should -BeNullOrEmpty
    }

    It 'keeps status rows usable at narrow and wide widths' {
        $ctx = New-TpmWorkflowStatusContext -WorkflowKey 'SupportPackage' -Title 'Create support package' -Steps @('tpm','tekno','game','redact','zip') -ConsoleFacts ([pscustomobject]@{NoRender=$true})
        Start-TpmWorkflowStatus $ctx
        Start-TpmWorkflowStep $ctx -StepId 'tpm' -Activity 'Collecting TPM diagnostics'
        $narrow = Format-TpmWorkflowStatusRows -Snapshot (Get-TpmWorkflowStatusSnapshot $ctx) -Width 24
        $wide = Format-TpmWorkflowStatusRows -Snapshot (Get-TpmWorkflowStatusSnapshot $ctx) -Width 120
        $narrow.Count | Should -BeGreaterThan 0
        $wide.Count | Should -BeGreaterThan 0
        Stop-TpmWorkflowStatus $ctx
        Close-TpmWorkflowStatus $ctx
    }

    It 'uses safe deterministic package names and avoids collisions' {
        $f = New-SupportFixture
        $one = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $two = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $one.Succeeded | Should -BeTrue
        $two.Succeeded | Should -BeTrue
        [System.IO.Path]::GetFileName($one.PackagePath) | Should -Match '^TeknoParrotManager-Support-\d{8}-\d{6}(-\d{3})?\.zip$'
        $one.PackagePath | Should -Not -Be $two.PackagePath
    }

    It 'rejects an unapproved game path without collecting outside files' {
        $f = New-SupportFixture
        $outside = Join-Path $f.Root 'Outside'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Write-SupportText (Join-Path $outside 'BepInEx\LogOutput.log') 'outside secret'
        Write-SupportText (Join-Path $f.Profiles 'Outside.xml') ('<GameProfile><GamePath>' + (Join-Path $outside 'game.exe') + '</GamePath></GameProfile>')
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $r.Records | Where-Object { $_.Source -eq 'Game:Outside' } | Select-Object -ExpandProperty Status | Should -Contain 'IntentionallyExcluded'
        (Get-SupportZipText $r.PackagePath 'MANIFEST.txt') | Should -Not -Match 'outside secret'
    }

    It 'excludes oversized optional text diagnostics' {
        $f = New-SupportFixture
        $large = New-Object byte[] 5242881
        [System.IO.File]::WriteAllBytes((Join-Path $f.Script 'TeknoParrot-Manager.log'),$large)
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $r.Records | Where-Object Source -eq 'TPM:TeknoParrot-Manager.log' | Select-Object -ExpandProperty Status | Should -Be 'IntentionallyExcluded'
    }

    It 'uses the structured no-render fallback for redirected, unattended, and certification facts' {
        foreach ($property in @('InputRedirected','OutputRedirected','Unattended','Certification')) {
            $facts = [pscustomobject]@{ NoRender = $false; Unattended = $false; InputRedirected = $false; OutputRedirected = $false; Certification = $false; CanCursor = $true; Width = 120; Height = 30; BufferWidth = 120; BufferHeight = 30 }
            $facts.$property = $true
            (Get-TpmWorkflowConsoleCapability -Facts $facts).Mode | Should -Be 'None'
        }
    }

    It 'keeps the support manifest free of absolute development paths' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Script 'TeknoParrot-Manager.log') 'path=C:\Users\EliSi\private W:\ROMS\secret'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $manifest = Get-SupportZipText $r.PackagePath 'MANIFEST.txt'
        $manifest | Should -Not -Match 'C:\\Users\\EliSi|W:\\ROMS'
    }

    It 'opens the TPM logs folder through the normal Windows shell boundary' {
        $f = New-SupportFixture
        Mock Start-Process {}
        $r = Open-TpmLogsAndReports -ScriptRoot $f.Script
        $r.Succeeded | Should -BeTrue
        Should -Invoke Start-Process -Times 1 -Exactly
    }
    It 'rejects executable and archive signatures but accepts valid UTF-8 and BOM text' {
        foreach ($bytes in @(
            ,([byte[]](0x4d,0x5a,1,2))
            ,([byte[]](0x50,0x4b,0x03,0x04,1,2))
            ,([byte[]](0x37,0x7a,0xbc,0xaf,0x27,0x1c,1))
            ,([byte[]](0x52,0x61,0x72,0x21,0x1a,0x07,1))
            ,([byte[]](0x1f,0x8b,1,2))
            ,([byte[]](0,1,2,0,3))
        )) {
            (Test-TpmSupportTextContent -Bytes $bytes).Safe | Should -BeFalse
        }
        $utf8 = New-Object System.Text.UTF8Encoding($true)
        (Test-TpmSupportTextContent -Bytes ([byte[]]($utf8.GetPreamble() + $utf8.GetBytes('valid text')))).Safe | Should -BeTrue
        $utf16 = New-Object System.Text.UnicodeEncoding($false,$true,$true)
        $decoded = Test-TpmSupportTextContent -Bytes ([byte[]]($utf16.GetPreamble() + $utf16.GetBytes('unicode text')))
        $decoded.Safe | Should -BeTrue
        $decoded.Text | Should -Be 'unicode text'
    }

    It 'records unsafe content instead of staging allowlisted binary masquerades' {
        $f = New-SupportFixture
        [IO.File]::WriteAllBytes((Join-Path $f.Script 'TeknoParrot-Manager.log'),[byte[]](0x4d,0x5a,1,2))
        [IO.File]::WriteAllBytes((Join-Path $f.Tp 'ParrotPatcher_Log.txt'),[byte[]](0x50,0x4b,0x03,0x04,1,2))
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        @($r.Records | Where-Object Status -eq 'RejectedUnsafeContent').Count | Should -BeGreaterThan 1
        (Get-SupportZipText $r.PackagePath 'MANIFEST.txt') | Should -Match 'RejectedUnsafeContent'
        @((Get-SupportZipEntries $r.PackagePath) | Where-Object { $_ -like 'diagnostics/*.txt' }).Count | Should -Be 0
    }

    It 'redacts every dynamic manifest field before insertion' {
        $records = New-Object System.Collections.Generic.List[object]
        [void]$records.Add([pscustomobject]@{Source='Authorization: Bearer abc';Status='CollectionFailed';Destination='C:\Users\EliSi\secret';Detail='api_key=one'})
        $errors = New-Object System.Collections.Generic.List[string]
        [void]$errors.Add('postgresql://user:pw@host/db token=two')
        $manifest = Get-TpmSupportManifestText -Records $records -Errors $errors -GameCodes ([string[]]@()) -AffectedGameSummary 'password=leaked-secret UNC=\\server\share'
        $manifest | Should -Not -Match '\babc\b|\bone\b|pw@host|\btwo\b|leaked-secret|EliSi|server\\share'
        $manifest | Should -Match 'Affected game scope:'
        $manifest | Should -Match 'Collection or packaging failures:'
    }

    It 'rejects a source when the reparse safety check changes before open' {
        $f = New-SupportFixture
        $source = Join-Path $f.Script 'TeknoParrot-Manager.log'
        Write-SupportText $source 'safe text'
        $stage = Join-Path $f.Root 'stage'
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $records = New-Object System.Collections.Generic.List[object]
        $script:safetyChecks = 0
        Mock Test-TpmNoReparsePath { $script:safetyChecks++; return ($script:safetyChecks -eq 1) }
        Copy-TpmSupportTextFile -Records $records -SourcePath $source -AllowedRoot $f.Script -SourceLabel 'TPM:race' -StageDirectory $stage -DestinationName 'race.txt'
        $records[0].Status | Should -Be 'RejectedUnsafeContent'
        Test-Path -LiteralPath (Join-Path $stage 'race.txt') | Should -BeFalse
    }

    It 'fails closed for a reparse-backed destination when the platform can create a junction' {
        $f = New-SupportFixture
        $outside = Join-Path $f.Root 'outside'
        Remove-Item -LiteralPath $f.Output -Recurse -Force
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        try { New-Item -ItemType Junction -Path $f.Output -Target $outside -ErrorAction Stop | Out-Null } catch { Set-ItResult -Skipped -Because 'Windows junction creation was unavailable'; return }
        try {
            $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
            $r.Succeeded | Should -BeFalse
            $r.PackagePath | Should -BeNullOrEmpty
        } finally {
            Remove-Item -LiteralPath $f.Output -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports staging cleanup failure as partial without clean success' {
        $f = New-SupportFixture
        Mock Remove-TpmSupportStageDirectory { return $false }
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeFalse
        $r.Partial | Should -BeTrue
        $r.PackagePath | Should -Not -BeNullOrEmpty
        if ($r.PackagePath) { Remove-Item -LiteralPath $r.PackagePath -Force -ErrorAction SilentlyContinue }
    }

    It 'emits support workflow events in phase order and closes ownership' {
        $f = New-SupportFixture
        $events = New-Object System.Collections.Generic.List[string]
        $sink = { param($event) [void]$events.Add([string]$event.EventKind) }.GetNewClosure()
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output -EventSink $sink
        $r.Succeeded | Should -BeTrue
        @($events | Where-Object { $_ -eq 'WorkflowStarted' }).Count | Should -Be 1
        $steps = @($events | Where-Object { $_ -eq 'StepStarted' })
        $steps.Count | Should -Be 5
        $steps | Should -Be @('StepStarted','StepStarted','StepStarted','StepStarted','StepStarted')
        $events[$events.Count - 1] | Should -Be 'WorkflowClosed'
        $r.StatusContext.Closed | Should -BeTrue
    }
    It 'writes only relative safe ZIP entry names' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Script 'TeknoParrot-Manager.log') 'diagnostic'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        foreach ($entry in @(Get-SupportZipEntries $r.PackagePath)) {
            $entry | Should -Not -Match '(^|[\\/])\.\.([\\/]|$)'
            $entry | Should -Not -Match '^[A-Za-z]:[\\/]'
            $entry | Should -Not -Match '^[/\\]'
        }
    }

    It 'does not read profiles from a reparse-backed profiles root' {
        $f = New-SupportFixture
        Add-SupportGame $f | Out-Null
        Mock Test-TpmNoReparsePath { param([string]$Path) return ($Path -ne $f.Profiles) }
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        ($r.Records | Where-Object Source -eq 'Registered game diagnostics').Status | Should -Be 'IntentionallyExcluded'
    }
    It 'rejects a real source-parent junction substituted before object validation consumes it' {
        $f = New-SupportFixture
        $logs = Join-Path $f.Tp 'Logs'
        $outside = Join-Path $f.Root 'outside-source'
        $source = Join-Path $logs 'TeknoParrot.log'
        $stage = Join-Path $f.Root 'stage-source'
        New-Item -ItemType Directory -Path $logs,$outside,$stage -Force | Out-Null
        Write-SupportText $source 'approved source'
        Write-SupportText (Join-Path $outside 'TeknoParrot.log') 'outside source secret'
        $realSafety = ${function:Test-TpmNoReparsePath}
        $script:safetyCalls = 0
        Mock Test-TpmNoReparsePath {
            $script:safetyCalls++
            $safe = & $realSafety -Path $Path
            if ($script:safetyCalls -eq 2) {
                Remove-Item -LiteralPath $logs -Recurse -Force
                New-Item -ItemType Junction -Path $logs -Target $outside -ErrorAction Stop | Out-Null
            }
            return $safe
        }
        $records = New-Object System.Collections.Generic.List[object]
        Copy-TpmSupportTextFile -Records $records -SourcePath $source -AllowedRoot $logs -SourceLabel 'race-source' -StageDirectory $stage -DestinationName 'race.txt'
        $records[0].Status | Should -Be 'RejectedUnsafeContent'
        Test-Path -LiteralPath (Join-Path $stage 'race.txt') | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $outside 'TeknoParrot.log')) | Should -BeTrue
    }

    It 'rejects a real profile-parent junction substituted before XML parsing' {
        $f = New-SupportFixture
        $outside = Join-Path $f.Root 'outside-profile'
        $profile = Join-Path $f.Profiles 'TMNT.xml'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Write-SupportText $profile '<GameProfile><GamePath>approved.exe</GamePath></GameProfile>'
        Write-SupportText (Join-Path $outside 'TMNT.xml') '<GameProfile><GamePath>outside.exe</GamePath></GameProfile>'
        $realSafety = ${function:Test-TpmNoReparsePath}
        $script:profileSafetyCalls = 0
        Mock Test-TpmNoReparsePath {
            $script:profileSafetyCalls++
            $safe = & $realSafety -Path $Path
            if ($script:profileSafetyCalls -eq 2) {
                Remove-Item -LiteralPath $f.Profiles -Recurse -Force
                New-Item -ItemType Junction -Path $f.Profiles -Target $outside -ErrorAction Stop | Out-Null
            }
            return $safe
        }
        $caught = $null
        try { Open-TpmSupportSafeFileStream -SourcePath $profile -AllowedRoot $f.Profiles -MaximumBytes 16777216 | Out-Null } catch { $caught = $_ }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Exception.Message | Should -Match 'identity|escaped|root'
    }

    It 'does not hash a plugin reached through a substituted real junction' {
        $f = New-SupportFixture
        $game = Add-SupportGame $f
        $pluginRoot = Join-Path $game 'BepInEx\plugins'
        $outside = Join-Path $f.Root 'outside-plugin'
        $outsideDll = Join-Path $outside 'Evil.dll'
        $stage = Join-Path $f.Root 'stage-plugin'
        New-Item -ItemType Directory -Path $pluginRoot,$outside,$stage -Force | Out-Null
        [IO.File]::WriteAllBytes($outsideDll,[byte[]](1,2,3,4,5))
        $expectedHash = (-join ((New-Object Security.Cryptography.SHA256Managed).ComputeHash([IO.File]::ReadAllBytes($outsideDll)) | ForEach-Object { $_.ToString('x2') }))
        $realSafety = ${function:Test-TpmNoReparsePath}
        $script:pluginSafetyCalls = 0
        Mock Test-TpmNoReparsePath {
            $script:pluginSafetyCalls++
            $safe = & $realSafety -Path $Path
            if ($script:pluginSafetyCalls -eq 3) {
                Remove-Item -LiteralPath $pluginRoot -Recurse -Force
                New-Item -ItemType Junction -Path $pluginRoot -Target $outside -ErrorAction Stop | Out-Null
            }
            return $safe
        }
        $records = New-Object System.Collections.Generic.List[object]
        Get-TpmSupportPluginInventory -GameRoot $game -GameCode 'TMNT' -Records $records -StageDirectory $stage
        Test-Path -LiteralPath (Join-Path $stage 'metadata\inventory-TMNT.tsv') | Should -BeFalse
        $script:pluginSafetyCalls | Should -BeGreaterOrEqual 3
    }

    It 'rejects destination substitution between authorization and promotion' {
        $f = New-SupportFixture
        $outside = Join-Path $f.Root 'outside-destination'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        $realSafety = ${function:Test-TpmNoReparsePath}
        $script:outputSafetyCalls = 0
        Mock Test-TpmNoReparsePath {
            $safe = & $realSafety -Path $Path
            if ([IO.Path]::GetFullPath($Path) -eq [IO.Path]::GetFullPath($f.Output)) {
                $script:outputSafetyCalls++
                if ($script:outputSafetyCalls -eq 2) {
                    Remove-Item -LiteralPath $f.Output -Recurse -Force
                    New-Item -ItemType Junction -Path $f.Output -Target $outside -ErrorAction Stop | Out-Null
                }
            }
            return $safe
        }
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -OutputRoot $f.Output
        $r.Succeeded | Should -BeFalse
        $r.Partial | Should -BeFalse
        @((Get-ChildItem -LiteralPath $outside -Filter '*.zip' -File -ErrorAction SilentlyContinue)).Count | Should -Be 0
    }

    It 'preserves residue when a staging child becomes a real junction' {
        $f = New-SupportFixture
        $stage = Join-Path $f.Root 'owned-stage'
        $outside = Join-Path $f.Root 'outside-stage'
        New-Item -ItemType Directory -Path (Join-Path $stage 'diagnostics'),(Join-Path $stage 'metadata'),$outside -Force | Out-Null
        Write-SupportText (Join-Path $stage 'MANIFEST.txt') 'manifest'
        New-Item -ItemType Junction -Path (Join-Path $stage 'diagnostics') -Target $outside -ErrorAction Stop | Out-Null
        $removed = Remove-TpmSupportStageDirectory -Path $stage
        $removed | Should -BeFalse
        Test-Path -LiteralPath $stage | Should -BeTrue
        Test-Path -LiteralPath $outside | Should -BeTrue
    }
}
