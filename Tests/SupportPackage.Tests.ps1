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
        @($entries | Where-Object { $_ -like 'diagnostics/tpm-*' }).Count | Should -BeGreaterThan 0
    }

    It 'collects allowlisted TeknoParrot diagnostics including ParrotPatcher_Log.txt' {
        $f = New-SupportFixture
        Write-SupportText (Join-Path $f.Tp 'ParrotPatcher_Log.txt') 'launcher error'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -TeknoParrotRoot $f.Tp -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        @((Get-SupportZipEntries $r.PackagePath) | Where-Object { $_ -like 'diagnostics/tekno-*' }).Count | Should -BeGreaterThan 0
    }

    It 'collects game-local BepInEx LogOutput.log' {
        $f = New-SupportFixture
        $game = Add-SupportGame $f
        Write-SupportText (Join-Path $game 'BepInEx\LogOutput.log') 'BepInEx startup failed'
        $r = New-TpmSupportPackage -ScriptRoot $f.Script -UserProfilesDir $f.Profiles -ApprovedGamesRoot $f.Games -OutputRoot $f.Output
        $r.Succeeded | Should -BeTrue
        $entries = Get-SupportZipEntries $r.PackagePath
        @($entries | Where-Object { $_ -like 'diagnostics/game-TMNT-BepInEx_LogOutput.log' }).Count | Should -Be 1
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
        $inventoryEntry = @($entries | Where-Object { $_ -like 'metadata/inventory-TMNT.tsv' })
        $inventoryEntry.Count | Should -Be 1
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
}
