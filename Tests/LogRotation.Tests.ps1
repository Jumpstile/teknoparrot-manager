#Requires -Module Pester

# Log size cap: the managed log is rotated once at startup. Synthetic files only; support package builds a ZIP from a fixture.
BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Log rotation test bootstrap could not parse the production script.' }
    $functionFile = Join-Path $TestDrive 'tpm-logrotation-functions.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding UTF8
    $progressModuleDirectory = Join-Path $TestDrive 'scripts'
    [void][IO.Directory]::CreateDirectory($progressModuleDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\scripts\TpmProgress.psm1') -Destination (Join-Path $progressModuleDirectory 'TpmProgress.psm1') -Force
    . $functionFile
    . (Join-Path $PSScriptRoot 'TpmExtractedScriptState.ps1')
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ScriptVersion = '1.0'
    $script:ReleaseCandidateLabel = 'RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:PostgresRecoveryStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'test.log'
    $script:logWarnShown = $false
    $script:Utf8 = New-Object System.Text.UTF8Encoding $false

    function New-LogFolder {
        $dir = Join-Path $TestDrive ('logs-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($dir)
        return $dir
    }
    function Write-Bytes([string]$Path, [int]$Count, [string]$Fill) {
        [IO.File]::WriteAllText($Path, ($Fill * $Count), $script:Utf8)
    }
    function Get-ZipText([string]$Zip, [string]$Like) {
        $z = [System.IO.Compression.ZipFile]::OpenRead($Zip)
        try {
            $e = @($z.Entries | Where-Object { ($_.FullName -replace '\\','/') -like $Like })
            $r = New-Object System.IO.StreamReader($e[0].Open())
            try { return $r.ReadToEnd() } finally { $r.Dispose() }
        } finally { $z.Dispose() }
    }
}

Describe 'Invoke-TpmLogRotation' {
    It 'moves an over-cap log to the previous file and leaves no fresh file' {
        $d = New-LogFolder; $p = Join-Path $d 'TeknoParrot-Manager.log'
        Write-Bytes $p 2000 'a'
        Invoke-TpmLogRotation -Path $p -MaxBytes 1000 | Should -BeTrue
        Test-Path -LiteralPath $p | Should -BeFalse
        (Get-Item -LiteralPath (Join-Path $d 'TeknoParrot-Manager.previous.log')).Length | Should -Be 2000
    }
    It 'leaves an under-cap log untouched' {
        $d = New-LogFolder; $p = Join-Path $d 'TeknoParrot-Manager.log'
        Write-Bytes $p 500 'b'
        Invoke-TpmLogRotation -Path $p -MaxBytes 1000 | Should -BeFalse
        (Get-Item -LiteralPath $p).Length | Should -Be 500
        Test-Path -LiteralPath (Join-Path $d 'TeknoParrot-Manager.previous.log') | Should -BeFalse
    }
    It 'replaces the older previous file instead of accumulating files' {
        $d = New-LogFolder; $p = Join-Path $d 'TeknoParrot-Manager.log'
        Write-Bytes (Join-Path $d 'TeknoParrot-Manager.previous.log') 50 'old'
        Write-Bytes $p 2000 'n'
        Invoke-TpmLogRotation -Path $p -MaxBytes 1000 | Should -BeTrue
        @(Get-ChildItem -LiteralPath $d).Count | Should -Be 1
        (Get-Content -LiteralPath (Join-Path $d 'TeknoParrot-Manager.previous.log') -Raw).StartsWith('nnn') | Should -BeTrue
    }
    It 'does not throw when the move fails and keeps the current log' {
        $d = New-LogFolder; $p = Join-Path $d 'TeknoParrot-Manager.log'
        Write-Bytes $p 2000 'c'
        # A directory squatting on the previous name makes the move fail.
        [void][IO.Directory]::CreateDirectory((Join-Path $d 'TeknoParrot-Manager.previous.log'))
        { $script:rotated = Invoke-TpmLogRotation -Path $p -MaxBytes 1000 } | Should -Not -Throw
        $script:rotated | Should -BeFalse
        (Get-Item -LiteralPath $p).Length | Should -Be 2000
    }
}

Describe 'Support package with a previous log' {
    It 'includes the current log and the previous log and says so in the README' {
        $root = Join-Path $TestDrive ('pkg-' + [guid]::NewGuid().ToString('N'))
        $s = Join-Path $root 'Scripts'; $out = Join-Path $s 'SupportPackages'
        [void][IO.Directory]::CreateDirectory((Join-Path $s 'Logs')); [void][IO.Directory]::CreateDirectory($out)
        [IO.File]::WriteAllText((Join-Path $s 'Logs\TeknoParrot-Manager.log'), 'NEWEST-RUN-LINE', $script:Utf8)
        [IO.File]::WriteAllText((Join-Path $s 'Logs\TeknoParrot-Manager.previous.log'), 'OLDER-RUN-LINE', $script:Utf8)
        $r = New-TpmSupportPackage -ScriptRoot $s -OutputRoot $out
        $r.Succeeded | Should -BeTrue
        (Get-ZipText $r.PackagePath 'diagnostics/tpm-01-*') | Should -Match 'NEWEST-RUN-LINE'
        (Get-ZipText $r.PackagePath 'diagnostics/tpm-15-*') | Should -Match 'OLDER-RUN-LINE'
        (Get-ZipText $r.PackagePath 'README.txt') | Should -Match 'previous\.log'
    }
}
