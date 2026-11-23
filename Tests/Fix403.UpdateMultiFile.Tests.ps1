#Requires -Module Pester

# Check for Updates must install the WHOLE release (main script, scripts\, data, tools), not only the main script.
# The real Invoke-ManagerUpdateInstall runs against real folders and real ZIPs built under $TestDrive. Only the web
# (the download) is mocked; the SHA-256 check is the real one against the ZIP the test built (one test gives it a wrong value).
# What this CANNOT prove: the live GitHub release API, or a real locked file held open by another program.
# Run on the test PC by the coordinator: Invoke-Pester -Path .\Tests\Fix403.UpdateMultiFile.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'FIX403 bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'fix403-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false

    # Dependencies outside this scope, as in Fix21A.UpdatePackageRefusal.Tests.ps1: inert stubs that replace the real
    # functions, so a test can never reach the network or write the real log. The download is mocked per test.
    function Write-Log { param([string]$msg) }
    function Invoke-TpmDownload {
        param([string]$DownloadUrl, [string]$DestinationPath, [Int64]$ExpectedBytes = 0, [string]$Label = 'Download', [string]$Version = '', [switch]$Quiet, [ref]$LastStatusCode, [string]$ExpectedSha256 = '', [scriptblock]$ValidationScript, [string]$AllowedRoot = '', [switch]$NoOverwrite)
        throw 'Invoke-TpmDownload stub must be mocked.'
    }

    # The update downloads into the temp folder: point it at a folder of its own so "the temp ZIP is gone" can be checked.
    $script:f403OldTemp = $env:TEMP
    $script:f403OldTmp = $env:TMP
    $script:f403Temp = Join-Path $TestDrive 'temp'
    [void][System.IO.Directory]::CreateDirectory($script:f403Temp)
    $env:TEMP = $script:f403Temp
    $env:TMP = $script:f403Temp

    $script:f403NewMain = "# TeknoParrot Manager`r`n`$ScriptVersion = `"0.99.99`"`r`n"
    $script:f403OldMain = "# TeknoParrot Manager`r`n`$ScriptVersion = `"0.0.1`"`r`n"
    $script:f403ZipToServe = $null
    $script:f403MoveLog = New-Object System.Collections.Generic.List[string]

    # A ZIP whose entries keep the exact name given (no normalization).
    function New-F403Zip {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object[]]$Entries)
        $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($item in $Entries) {
                $entry = $zip.CreateEntry([string]$item.Name)
                $stream = $entry.Open()
                try {
                    $bytes = [System.Text.Encoding]::ASCII.GetBytes([string]$item.Text)
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally { $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
        return $Path
    }

    # An installed program: old script, old module, a file identical to the package, the user's own file, a stale old file.
    function New-F403Program {
        $root = Join-Path $TestDrive ('p' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $app = Join-Path $root 'app'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $app 'scripts'))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $app 'docs'))
        [System.IO.File]::WriteAllText((Join-Path $app 'TeknoParrot-Manager.ps1'), $script:f403OldMain)
        [System.IO.File]::WriteAllText((Join-Path $app 'scripts\Module.psm1'), 'old module')
        [System.IO.File]::WriteAllText((Join-Path $app 'docs\same.txt'), 'same text')
        [System.IO.File]::WriteAllText((Join-Path $app 'my-notes.txt'), 'the user wrote this')
        [System.IO.File]::WriteAllText((Join-Path $app 'scripts\stale-old.ps1'), 'from an older version')
        return [pscustomobject]@{ Root = $root; App = $app; Script = (Join-Path $app 'TeknoParrot-Manager.ps1') }
    }

    function New-F403PackageEntries {
        param([string]$MainText = $script:f403NewMain)
        return @(
            [pscustomobject]@{ Name = 'scripts/Module.psm1'; Text = 'new module' }
            [pscustomobject]@{ Name = 'scripts/Added.ps1'; Text = 'added script' }
            [pscustomobject]@{ Name = 'docs/same.txt'; Text = 'same text' }
            [pscustomobject]@{ Name = 'data/new.json'; Text = '{"new":1}' }
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $MainText }
        )
    }

    function New-F403Release {
        param([string]$Tag = 'v0.99.99', [string]$Digest = '')
        if (-not $Digest) { $Digest = 'sha256:' + (Get-FileHash -LiteralPath $script:f403ZipToServe -Algorithm SHA256 -ErrorAction Stop).Hash }
        return [pscustomobject]@{
            TagName = $Tag; Name = $Tag; Body = 'Notes.'; AssetName = 'TeknoParrot.Manager.zip'
            DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.zip'
            SizeBytes = 1; Digest = $Digest
        }
    }

    # Every file and folder of the program folder with its hash and read-only flag, except the UpdateBackups folder
    # (a backup is allowed to appear). Two snapshots are equal only when the folder is byte-for-byte the same.
    function Get-F403Tree {
        param([Parameter(Mandatory)][string]$App)
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($item in @(Get-ChildItem -LiteralPath $App -Recurse -Force)) {
            $relative = $item.FullName.Substring($App.Length + 1)
            if ($relative -eq 'UpdateBackups' -or $relative.StartsWith('UpdateBackups\')) { continue }
            if ($item.PSIsContainer) { [void]$lines.Add('D ' + $relative) }
            else { [void]$lines.Add('F ' + $relative + ' ' + (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash + ' ro=' + $item.IsReadOnly) }
        }
        return (($lines | Sort-Object) -join '|')
    }

    function Get-F403Text { param([string]$Path) return [System.IO.File]::ReadAllText($Path) }
}

AfterAll {
    $env:TEMP = $script:f403OldTemp
    $env:TMP = $script:f403OldTmp
}

Describe 'Check for Updates installs a multi-file release (FIX403)' {
    BeforeEach {
        # Anything that could wait for a person, a timer or the network fails the test at once instead of hanging it.
        Mock Read-Host { throw 'The update must never prompt.' }
        Mock Read-TpmYesNo { throw 'The update must never prompt.' }
        Mock Read-TpmChoice { throw 'The update must never prompt.' }
        Mock Start-Sleep { throw 'The update must never wait.' }
        Mock Start-Process { throw 'The update must never start a program.' }
        Mock Invoke-WebRequest { throw 'The update must never reach the network.' }
        Mock Invoke-RestMethod { throw 'The update must never reach the network.' }
        Mock Write-Log {}
        Mock Write-Host {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Invoke-TpmDownload {
            Copy-Item -LiteralPath $script:f403ZipToServe -Destination $DestinationPath -Force
            return $true
        }
    }

    It 'installs new and changed files, leaves identical, user and stale files alone, backs up what it replaced, and cleans up' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries (New-F403PackageEntries)
        $sameBefore = Get-FileHash -LiteralPath (Join-Path $program.App 'docs\same.txt') -Algorithm SHA256
        $sameTimeBefore = (Get-Item -LiteralPath (Join-Path $program.App 'docs\same.txt')).LastWriteTimeUtc

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release)

        (Test-TpmTransactionResult -Result $result) | Should -BeTrue
        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.ReasonCode | Should -BeExactly 'UPDATE_INSTALLED_VERIFIED'
        $result.Installed | Should -BeTrue
        Get-F403Text (Join-Path $program.App 'TeknoParrot-Manager.ps1') | Should -BeExactly $script:f403NewMain
        Get-F403Text (Join-Path $program.App 'scripts\Module.psm1') | Should -BeExactly 'new module'
        Get-F403Text (Join-Path $program.App 'scripts\Added.ps1') | Should -BeExactly 'added script'
        Get-F403Text (Join-Path $program.App 'data\new.json') | Should -BeExactly '{"new":1}'
        # Identical file untouched (same bytes, same write time); the user's file and the stale file stay.
        (Get-FileHash -LiteralPath (Join-Path $program.App 'docs\same.txt') -Algorithm SHA256).Hash | Should -BeExactly $sameBefore.Hash
        (Get-Item -LiteralPath (Join-Path $program.App 'docs\same.txt')).LastWriteTimeUtc | Should -Be $sameTimeBefore
        Get-F403Text (Join-Path $program.App 'my-notes.txt') | Should -BeExactly 'the user wrote this'
        Get-F403Text (Join-Path $program.App 'scripts\stale-old.ps1') | Should -BeExactly 'from an older version'
        # The stale file is listed in Details; the user's own file in the program folder root is not.
        @($result.TechnicalDetails.MultiFile.LeftInPlace) | Should -Contain 'scripts\stale-old.ps1'
        @($result.TechnicalDetails.MultiFile.LeftInPlace) | Should -Not -Contain 'my-notes.txt'
        # The backup holds the old bytes of every replaced file, and only those.
        $backup = [string]$result.TechnicalDetails.MultiFile.BackupFolder
        $backup | Should -BeLike (Join-Path $program.App 'UpdateBackups\TeknoParrotManager_*')
        Get-F403Text (Join-Path $backup 'TeknoParrot-Manager.ps1') | Should -BeExactly $script:f403OldMain
        Get-F403Text (Join-Path $backup 'scripts\Module.psm1') | Should -BeExactly 'old module'
        @(Get-ChildItem -LiteralPath $backup -Recurse -File).Count | Should -Be 2
        # Staging folder and downloaded ZIP are gone.
        @(Get-ChildItem -LiteralPath $program.App -Force -Filter 'tpm-update-staging-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:f403Temp -Force -Filter 'tpm-update-*').Count | Should -Be 0
    }

    It 'a failure on the third file put in place leaves the program folder exactly as it was' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries (New-F403PackageEntries)
        $before = Get-F403Tree -App $program.App
        # The package order is Module.psm1, Added.ps1, data\new.json, then the main script, so data\new.json is the third file put in
        # place. Only the move of a staged file into the program folder fails; every other call passes through.
        # Every call is written to a list as "<source>|<destination>|<ok or FAILED>" (the list is only added to, never reassigned,
        # the same way Fix21A keeps its log), and the test asserts on that list.
        $script:f403MoveLog.Clear()
        Mock Move-Item {
            $source = (@($LiteralPath) -join ';')
            $target = [string]$Destination
            if ($target -like '*\data\new.json' -and $source -notlike '*.tpm-rollback-backup*') {
                [void]$script:f403MoveLog.Add($source + '|' + $target + '|FAILED')
                throw 'Simulated: the third file could not be put in place.'
            }
            try {
                # The product only moves single files; the call is made with .NET directly (as the other promote tests do), with the first
                # element of the one-item -LiteralPath array.
                [System.IO.File]::Move([string]@($LiteralPath)[0], $target)
            } catch {
                [void]$script:f403MoveLog.Add($source + '|' + $target + '|FAILED: ' + $_.Exception.Message)
                throw
            }
            [void]$script:f403MoveLog.Add($source + '|' + $target + '|ok')
        }

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release)

        $dump = $script:f403MoveLog -join "`n"
        # Put in place (source in the staging folder, not in its rollback folder): two files go in, the third is tried and fails.
        $putInPlace = @($script:f403MoveLog | Where-Object { $_.Split('|')[0] -like '*tpm-update-staging-*' -and $_.Split('|')[0] -notlike '*.tpm-rollback-backup*' })
        $putInPlace.Count | Should -Be 3 -Because "all Move-Item calls:`n$dump"
        $putInPlace[0] | Should -BeLike '*\scripts\Module.psm1|ok' -Because "all Move-Item calls:`n$dump"
        $putInPlace[1] | Should -BeLike '*\scripts\Added.ps1|ok' -Because "all Move-Item calls:`n$dump"
        $putInPlace[2] | Should -BeLike '*\data\new.json|FAILED' -Because "all Move-Item calls:`n$dump"
        # Rollback moves came after: at least the replaced module went back from the rollback folder.
        @($script:f403MoveLog | Where-Object { $_.Split('|')[0] -like '*.tpm-rollback-backup*' -and $_ -like '*|' + $program.App + '\scripts\Module.psm1|ok' }).Count | Should -Be 1 -Because "all Move-Item calls:`n$dump"
        (Test-TpmTransactionResult -Result $result) | Should -BeTrue
        $result.Outcome | Should -BeExactly 'ROLLED_BACK_VERIFIED'
        $result.ProductState | Should -BeExactly 'UNCHANGED'
        $result.Installed | Should -BeFalse
        Get-F403Tree -App $program.App | Should -BeExactly $before
        @(Get-ChildItem -LiteralPath $program.App -Force -Filter 'tpm-update-staging-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:f403Temp -Force -Filter 'tpm-update-*').Count | Should -Be 0
    }

    It 'refuses a ZIP entry named <Name> before anything is extracted or changed' -TestCases @(
        @{ Name = '..\evil.txt' }
        @{ Name = '../evil.txt' }
        @{ Name = 'C:\evil.txt' }
        @{ Name = '/evil.txt' }
        @{ Name = 'scripts/..\..\evil.txt' }
        @{ Name = 'SCRIPTS/MODULE.psm1' }
    ) {
        $program = New-F403Program
        $entries = @(New-F403PackageEntries) + @([pscustomobject]@{ Name = $Name; Text = 'evil' })
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries $entries
        $before = Get-F403Tree -App $program.App

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release)

        (Test-TpmTransactionResult -Result $result) | Should -BeTrue
        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'UPDATE_PACKAGE_BAD_ENTRY'
        $result.Installed | Should -BeFalse
        Get-F403Tree -App $program.App | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $program.App 'UpdateBackups') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $program.Root 'evil.txt') | Should -BeFalse
        Test-Path -LiteralPath 'C:\evil.txt' | Should -BeFalse
        @(Get-ChildItem -LiteralPath $program.App -Force -Filter 'tpm-update-staging-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:f403Temp -Force -Filter 'tpm-update-*').Count | Should -Be 0
    }

    It 'stops when the drive has less than about twice the unpacked size free' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries (New-F403PackageEntries)
        $before = Get-F403Tree -App $program.App
        Mock Get-TpmCps3FreeBytes { return [int64]10 }

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release)

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'UPDATE_NOT_ENOUGH_DISK_SPACE'
        $result.Summary | Should -Match 'not enough free space'
        Get-F403Tree -App $program.App | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $program.App 'UpdateBackups') | Should -BeFalse
    }

    It 'a wrong SHA-256 changes nothing' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries (New-F403PackageEntries)
        $before = Get-F403Tree -App $program.App

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release -Digest ('sha256:' + ('0' * 64)))

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'UPDATE_DIGEST_MISMATCH'
        Get-F403Tree -App $program.App | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $program.App 'UpdateBackups') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $program.App -Force -Filter 'tpm-update-staging-*').Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:f403Temp -Force -Filter 'tpm-update-*').Count | Should -Be 0
    }

    It 'a package whose script is not newer than the installed one changes nothing' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries (New-F403PackageEntries -MainText $script:f403OldMain)
        $before = Get-F403Tree -App $program.App

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release -Tag 'v0.0.1')

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.ReasonCode | Should -BeExactly 'UPDATE_VERSION_NOT_NEWER'
        Get-F403Tree -App $program.App | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $program.App 'UpdateBackups') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $program.App -Force -Filter 'tpm-update-staging-*').Count | Should -Be 0
    }

    It 'a ZIP with only the main script still takes the single-script path' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries @([pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $script:f403NewMain })
        $moduleBefore = Get-F403Text (Join-Path $program.App 'scripts\Module.psm1')

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release)

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        $result.ReasonCode | Should -BeExactly 'UPDATE_INSTALLED_VERIFIED'
        Get-F403Text (Join-Path $program.App 'TeknoParrot-Manager.ps1') | Should -BeExactly $script:f403NewMain
        Get-F403Text (Join-Path $program.App 'scripts\Module.psm1') | Should -BeExactly $moduleBefore
        $result.TechnicalDetails.MultiFile | Should -BeNullOrEmpty
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $program.App 'UpdateBackups') -Recurse -File)
        $backups.Count | Should -Be 1
        Get-F403Text $backups[0].FullName | Should -BeExactly $script:f403OldMain
    }

    It 'replaces read-only installed files and puts the read-only flag back' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries (New-F403PackageEntries)
        foreach ($name in @('TeknoParrot-Manager.ps1', 'scripts\Module.psm1')) {
            Set-ItemProperty -LiteralPath (Join-Path $program.App $name) -Name IsReadOnly -Value $true
        }

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release)

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-F403Text (Join-Path $program.App 'TeknoParrot-Manager.ps1') | Should -BeExactly $script:f403NewMain
        Get-F403Text (Join-Path $program.App 'scripts\Module.psm1') | Should -BeExactly 'new module'
        (Get-Item -LiteralPath (Join-Path $program.App 'TeknoParrot-Manager.ps1')).IsReadOnly | Should -BeTrue
        (Get-Item -LiteralPath (Join-Path $program.App 'scripts\Module.psm1')).IsReadOnly | Should -BeTrue
        # A file that was not read-only does not become read-only.
        (Get-Item -LiteralPath (Join-Path $program.App 'scripts\Added.ps1')).IsReadOnly | Should -BeFalse
        $backup = [string]$result.TechnicalDetails.MultiFile.BackupFolder
        Get-F403Text (Join-Path $backup 'scripts\Module.psm1') | Should -BeExactly 'old module'
    }

    It 'installs RC8.1 over RC7 in a folder whose path has spaces and parentheses, and keeps the user''s own files' {
        # Mutation: break the dotted-label parse (RC8.1 refused as "not a supported version") or build a path by string concatenation without quoting.
        $app = Join-Path $TestDrive ('Program Files (x86) ' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '\TeknoParrot Manager')
        [void][System.IO.Directory]::CreateDirectory((Join-Path $app 'scripts'))
        $oldMain = "# TeknoParrot Manager`r`n`$ScriptVersion = `"1.0`"`r`n`$ReleaseCandidateLabel = `"RC7`"`r`n"
        $newMain = "# TeknoParrot Manager`r`n`$ScriptVersion = `"1.0`"`r`n`$ReleaseCandidateLabel = `"RC8.1`"`r`n"
        [System.IO.File]::WriteAllText((Join-Path $app 'TeknoParrot-Manager.ps1'), $oldMain)
        [System.IO.File]::WriteAllText((Join-Path $app 'scripts\Module.psm1'), 'old module')
        [System.IO.File]::WriteAllText((Join-Path $app 'my notes.txt'), 'the user wrote this')
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries @(
            [pscustomobject]@{ Name = 'scripts/Module.psm1'; Text = 'new module' }
            [pscustomobject]@{ Name = 'scripts/Added.ps1'; Text = 'added script' }
            [pscustomobject]@{ Name = 'TeknoParrot-Manager.ps1'; Text = $newMain }
        )

        $result = Invoke-ManagerUpdateInstall -ScriptPath (Join-Path $app 'TeknoParrot-Manager.ps1') -Release (New-F403Release -Tag 'v1.0-RC8.1')

        $result.Outcome | Should -BeExactly 'SUCCEEDED'
        Get-F403Text (Join-Path $app 'TeknoParrot-Manager.ps1') | Should -BeExactly $newMain
        Get-F403Text (Join-Path $app 'scripts\Module.psm1') | Should -BeExactly 'new module'
        Get-F403Text (Join-Path $app 'scripts\Added.ps1') | Should -BeExactly 'added script'
        Get-F403Text (Join-Path $app 'my notes.txt') | Should -BeExactly 'the user wrote this'
        Get-F403Text (Join-Path ([string]$result.TechnicalDetails.MultiFile.BackupFolder) 'TeknoParrot-Manager.ps1') | Should -BeExactly $oldMain
    }

    It 'a file damaged on its way to disk is not installed and nothing changes' {
        $program = New-F403Program
        $script:f403ZipToServe = New-F403Zip -Path (Join-Path $TestDrive ('rel-' + [guid]::NewGuid().ToString('N') + '.zip')) -Entries (New-F403PackageEntries)
        $before = Get-F403Tree -App $program.App
        $script:f403RealExpand = ${function:Expand-ZipFileSafe}
        # The real extraction runs, then one staged file is changed to other bytes of the same size (a bad write).
        Mock Expand-ZipFileSafe {
            & $script:f403RealExpand @PesterBoundParameters
            [System.IO.File]::WriteAllText((Join-Path $DestDir 'scripts\Module.psm1'), 'NEW MODULE')
        }

        $result = Invoke-ManagerUpdateInstall -ScriptPath $program.Script -Release (New-F403Release)

        $result.Outcome | Should -BeExactly 'FAILED_BEFORE_MUTATION'
        $result.Installed | Should -BeFalse
        Get-F403Tree -App $program.App | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $program.App 'UpdateBackups') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $program.App -Force -Filter 'tpm-update-staging-*').Count | Should -Be 0
    }
}

Describe 'An update that was cut off is noticed at the next start (FIX403)' {
    BeforeEach {
        $script:f403Notice = New-Object System.Collections.Generic.List[string]
        $script:f403NoticeLog = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:f403Notice.Add([string]$Object) }
        Mock Write-Log { [void]$script:f403NoticeLog.Add([string]$msg) }
        $script:Unattended = $false
        $script:f403Prog = Join-Path $TestDrive ('np' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:f403Prog 'UpdateBackups\TeknoParrotManager_2026-01-01_10-00-00'))
    }

    It 'says an update did not finish, how to get the old files back, logs it, and removes nothing' {
        $staging = Join-Path $script:f403Prog 'tpm-update-staging-aaaa'
        [void][System.IO.Directory]::CreateDirectory($staging)
        [System.IO.File]::WriteAllText((Join-Path $staging '.tpm-update-running'), '')
        [System.IO.File]::WriteAllText((Join-Path $staging 'moved-aside.txt'), 'the only copy')
        # This update started before the backup folder was made, so the backup belongs to it.
        [System.IO.Directory]::SetCreationTimeUtc($staging, [datetime]::UtcNow.AddMinutes(-10))

        Write-TpmInterruptedUpdateNotice -ProgramDir $script:f403Prog

        $text = $script:f403Notice -join "`n"
        $text | Should -Match 'An earlier update of TeknoParrot Manager did not finish\.'
        $text | Should -Match 'UpdateBackups'
        $text | Should -Match 'TeknoParrotManager_2026-01-01_10-00-00'
        $text | Should -Match 'choose 15 \(Check for Updates\)'
        @($script:f403NoticeLog | Where-Object { $_ -like 'Interrupted update:*tpm-update-staging-aaaa*' }).Count | Should -Be 1
        Get-F403Text (Join-Path $staging 'moved-aside.txt') | Should -BeExactly 'the only copy'
    }

    It 'does not offer an older update''s backup when the cut-off update never made one' {
        # Mutation: name the newest folder in UpdateBackups no matter which update made it (copying it back would put an older version over this one).
        [System.IO.Directory]::SetCreationTimeUtc((Join-Path $script:f403Prog 'UpdateBackups\TeknoParrotManager_2026-01-01_10-00-00'), [datetime]::UtcNow.AddMinutes(-10))
        $staging = Join-Path $script:f403Prog 'tpm-update-staging-dddd'
        [void][System.IO.Directory]::CreateDirectory($staging)
        [System.IO.File]::WriteAllText((Join-Path $staging '.tpm-update-running'), '')
        [System.IO.File]::WriteAllText((Join-Path $staging 'part.txt'), 'kept')

        Write-TpmInterruptedUpdateNotice -ProgramDir $script:f403Prog

        $text = $script:f403Notice -join "`n"
        $text | Should -Match 'An earlier update of TeknoParrot Manager did not finish\.'
        $text | Should -Match 'It stopped before it changed any program file'
        $text | Should -Match 'choose 15 \(Check for Updates\)'
        $text | Should -Not -Match 'TeknoParrotManager_2026'
        $text | Should -Not -Match 'mix of old and new'
        $text | Should -Not -Match 'copy its files'
        @($script:f403NoticeLog | Where-Object { $_ -like 'Interrupted update:*Newest backup: none' }).Count | Should -Be 1
        Get-F403Text (Join-Path $staging 'part.txt') | Should -BeExactly 'kept'
    }

    It 'gives the same plain notice when there is no UpdateBackups folder at all (the first update ever)' {
        Remove-Item -LiteralPath (Join-Path $script:f403Prog 'UpdateBackups') -Recurse -Force
        $staging = Join-Path $script:f403Prog 'tpm-update-staging-eeee'
        [void][System.IO.Directory]::CreateDirectory($staging)
        [System.IO.File]::WriteAllText((Join-Path $staging '.tpm-update-running'), '')

        { Write-TpmInterruptedUpdateNotice -ProgramDir $script:f403Prog } | Should -Not -Throw

        $text = $script:f403Notice -join "`n"
        $text | Should -Match 'It stopped before it changed any program file'
        $text | Should -Not -Match 'UpdateBackups'
    }

    It 'says nothing while another window is running an update (its marker is held open)' {
        $staging = Join-Path $script:f403Prog 'tpm-update-staging-bbbb'
        [void][System.IO.Directory]::CreateDirectory($staging)
        $held = [System.IO.File]::Open((Join-Path $staging '.tpm-update-running'), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        try {
            Write-TpmInterruptedUpdateNotice -ProgramDir $script:f403Prog
        } finally { $held.Dispose() }

        $script:f403Notice.Count | Should -Be 0
        $script:f403NoticeLog.Count | Should -Be 0
    }

    It 'says nothing when there is no unfinished update, and only logs it in an unattended run' {
        Write-TpmInterruptedUpdateNotice -ProgramDir $script:f403Prog
        $script:f403Notice.Count | Should -Be 0

        $staging = Join-Path $script:f403Prog 'tpm-update-staging-cccc'
        [void][System.IO.Directory]::CreateDirectory($staging)
        [System.IO.File]::WriteAllText((Join-Path $staging '.tpm-update-running'), '')
        $script:Unattended = $true
        Write-TpmInterruptedUpdateNotice -ProgramDir $script:f403Prog
        $script:f403Notice.Count | Should -Be 0
        @($script:f403NoticeLog | Where-Object { $_ -like 'Interrupted update:*' }).Count | Should -Be 1
    }
}
