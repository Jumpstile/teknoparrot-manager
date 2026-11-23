#Requires -Module Pester

# The standalone updater (tools\TpmAutoUpdate.Core.psm1) must run while the main script is being
# replaced, so it carries its own copy of the download helpers. This test runs each copy of the
# same helper side by side on the same input and fails if one ever behaves differently from the
# other: a user would then get a different download, retry or error depending on which program
# started the download. Each helper is checked on what it returns, throws, writes to disk and
# which download methods it tries, never on how its source text looks.
#
# Write-TpmDownloadProgress is the one helper that cannot be compared: it draws to two different
# screens (a plain console line in the updater, TPM's progress bar in the main script).
# The other six are compared below. Invoke-TpmDownload is compared on outcome: the main script
# returns $false where the updater throws, and both count as "failed".
BeforeAll {
    function Get-DupFunctionText {
        param([string]$File, [string]$Name)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw ('Cannot parse ' + $File) }
        $found = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $Name }, $true))
        if ($found.Count -ne 1) { throw ('Expected one ' + $Name + ' in ' + $File + ', found ' + $found.Count) }
        return $found[0].Extent.Text
    }
    $mainPath = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).ProviderPath
    $updaterPath = (Resolve-Path (Join-Path $PSScriptRoot '..\tools\TpmAutoUpdate.Core.psm1')).ProviderPath
    $shared = @('Test-TpmDownloadBitsAvailable', 'Invoke-TpmDownloadHttpClient', 'Invoke-TpmDownloadWebRequest', 'Test-TpmDownloadedFile', 'Get-TpmHttpStatusCodeFromError', 'Invoke-TpmDownload')
    foreach ($name in $shared) {
        foreach ($side in @(@('Main', $mainPath), @('Upd', $updaterPath))) {
            $text = Get-DupFunctionText $side[1] $name
            . ([scriptblock]::Create(($text -replace ('^function\s+' + [regex]::Escape($name)), ('function ' + $side[0] + '_' + $name))))
        }
    }
    # Real helpers the main-script copies call, plus no-op stand-ins for logging and progress drawing.
    foreach ($name in @('Get-TpmHttpStatusCodeFromError', 'Invoke-TpmWebRequestSilently', 'Test-TpmDownloadedFile')) { . ([scriptblock]::Create((Get-DupFunctionText $mainPath $name))) }
    . ([scriptblock]::Create((Get-DupFunctionText $updaterPath 'Get-TpmResponseContentLength')))
    $script:TpmDownloadNoProgressTimeoutSeconds = 120
    function Write-Log { param($Message) }
    function Write-TpmDownloadProgress { param($Label, $Method, $DownloadedBytes, $TotalBytes, $Elapsed, [switch]$Complete) }
    function Write-TpmDownloadMetrics { param($Label, $Method, $Path, $Elapsed, [switch]$Quiet) }
    function Write-DownloadAudit { param($Source, $FileName, $Path, $Version) }
    function Write-TpmCompactExtractionProgress { param($Phase, $Label, $Current, $Total, $StartedAt, [switch]$Complete, $Outcome, [switch]$NotAvailable, [switch]$Completed, $Unit) }
    function Assert-TpmNoReparseWriteTarget { param($Path, $Operation) }
    function Start-Sleep { param($Seconds) $global:DupCalls += 'sleep' }
    # Download methods: each call takes the next scripted result ('ok', 'f500' or 'f404') for that method.
    function Use-DupStep {
        param([string]$Method, [string]$TempPath)
        $global:DupCalls += $Method
        $queue = $global:DupPlan[$Method]
        $step = if ($queue -and $queue.Count) { $queue[0] } else { 'ok' }
        if ($queue -and $queue.Count) { $global:DupPlan[$Method] = @($queue | Select-Object -Skip 1) }
        if ($step -ceq 'ok') { [IO.File]::WriteAllText($TempPath, 'data') } else { throw ('transfer failed (' + $step.Substring(1) + ')') }
    }
    function Test-TpmDownloadBitsAvailable { return $global:DupBitsOn }
    function Invoke-TpmDownloadBitTransfer { param($DownloadUrl, $TempPath, $Label) Use-DupStep 'bits' $TempPath }
    function Invoke-TpmDownloadBits { param($DownloadUrl, $TempPath, $Label) Use-DupStep 'bits' $TempPath }
    function Invoke-TpmDownloadHttpClient { param($DownloadUrl, $TempPath, $Label) Use-DupStep 'http' $TempPath }
    function Invoke-TpmDownloadWebRequest { param($DownloadUrl, $TempPath, $Label) Use-DupStep 'web' $TempPath }

    # Loopback server for the real HttpClient and Invoke-WebRequest copies: /ok answers 200, anything else 404.
    $probe = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
    $global:DupBase = 'http://127.0.0.1:' + $port + '/'
    $global:DupServer = Start-Job -ArgumentList $port -ScriptBlock {
        param($port)
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add('http://127.0.0.1:' + $port + '/')
        $listener.Start()
        'ready'
        while ($true) {
            $context = $listener.GetContext()
            if ($context.Request.Url.AbsolutePath -eq '/quit') { $context.Response.Close(); break }
            $bytes = [Text.Encoding]::ASCII.GetBytes('hello download')
            if ($context.Request.Url.AbsolutePath -eq '/ok') { $context.Response.StatusCode = 200; $context.Response.OutputStream.Write($bytes, 0, $bytes.Length) } else { $context.Response.StatusCode = 404 }
            $context.Response.Close()
        }
        $listener.Stop()
    }
    $ready = $false
    for ($i = 0; $i -lt 100 -and -not $ready; $i++) { if (@(Receive-Job $global:DupServer -Keep) -contains 'ready') { $ready = $true } else { [Threading.Thread]::Sleep(100) } }
    if (-not $ready) { throw 'The loopback test server did not start.' }

    # Same input to both copies; returns what a caller can observe.
    function Invoke-DupSide {
        param([string]$Side, [string]$Name, [hashtable]$Arguments)
        $function = $Side + '_' + $Name
        $outcome = 'returned'
        $value = $null
        try { $value = & $function @Arguments } catch { $outcome = 'threw' }
        return [pscustomobject]@{ Outcome = $outcome; Value = $value }
    }
    function Invoke-DupDownload {
        param([string]$Side, [hashtable]$Plan, [bool]$BitsOn, [Int64]$ExpectedBytes = 0, [bool]$Existing = $false)
        $global:DupCalls = @(); $global:DupPlan = @{}; foreach ($key in $Plan.Keys) { $global:DupPlan[$key] = @($Plan[$key]) }; $global:DupBitsOn = $BitsOn
        $dest = Join-Path $TestDrive ($Side + [guid]::NewGuid().ToString('N') + '.bin')
        if ($Existing) { [IO.File]::WriteAllText($dest, 'old') }
        $result = Invoke-DupSide $Side 'Invoke-TpmDownload' @{ DownloadUrl = 'https://example.invalid/f'; DestinationPath = $dest; ExpectedBytes = $ExpectedBytes; Label = 'f' }
        $ok = ($result.Outcome -ceq 'returned' -and $result.Value -eq $true)
        $content = if (Test-Path -LiteralPath $dest) { [IO.File]::ReadAllText($dest) } else { '<absent>' }
        return ('ok=' + $ok + ' file=' + $content + ' calls=' + ($global:DupCalls -join ','))
    }
}

AfterAll {
    try { [void][Net.WebRequest]::Create($global:DupBase + 'quit').GetResponse() } catch {}
    if ($global:DupServer) { Wait-Job $global:DupServer -Timeout 10 | Out-Null; Remove-Job $global:DupServer -Force }
    Remove-Variable -Scope Global -Name DupCalls, DupPlan, DupBitsOn, DupBase, DupServer -ErrorAction SilentlyContinue
}

Describe 'The updater and the main script download helpers behave the same' {
    It 'Get-TpmHttpStatusCodeFromError gives the same code for every error shape, also under strict mode' {
        $shapes = @(
            [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'plain failure' } },
            [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'server said (503)' } },
            [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'x: 429 too many' } },
            [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'x'; Response = [pscustomobject]@{ StatusCode = 404 } } },
            [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'x (500)'; Response = [pscustomobject]@{ Other = 1 } } },
            [pscustomobject]@{ Exception = [pscustomobject]@{ Message = 'x'; Response = $null } },
            [pscustomobject]@{ Exception = [InvalidOperationException]::new('boom') },
            [pscustomobject]@{ Exception = [System.Net.WebException]::new('boom: 502 bad gateway') }
        )
        foreach ($shape in $shapes) {
            $results = foreach ($side in 'Main', 'Upd') {
                & { Set-StrictMode -Version 2.0; $r = Invoke-DupSide $side 'Get-TpmHttpStatusCodeFromError' @{ ErrorRecord = $shape }; $r.Outcome + ':' + $r.Value }
            }
            $results[1] | Should -BeExactly $results[0] -Because ($shape.Exception.Message)
        }
    }

    It 'Test-TpmDownloadBitsAvailable gives the same answer for a running, stopped and missing BITS service' {
        function global:Start-BitsTransfer { }
        function global:Get-Service { param($Name, $ErrorAction) if ($global:DupBitsState -ceq 'Throw') { throw 'no service' }; [pscustomobject]@{ Status = $global:DupBitsState } }
        try {
            foreach ($state in 'Running', 'Stopped', 'Throw') {
                $global:DupBitsState = $state
                $main = Invoke-DupSide 'Main' 'Test-TpmDownloadBitsAvailable' @{}
                $upd = Invoke-DupSide 'Upd' 'Test-TpmDownloadBitsAvailable' @{}
                ($upd.Outcome + ':' + $upd.Value) | Should -BeExactly ($main.Outcome + ':' + $main.Value) -Because $state
            }
        } finally {
            Remove-Item Function:\global:Start-BitsTransfer, Function:\global:Get-Service -ErrorAction SilentlyContinue
            Remove-Variable -Scope Global -Name DupBitsState -ErrorAction SilentlyContinue
        }
    }

    It 'Test-TpmDownloadedFile gives the same answer for missing, empty, wrong-size and right-size files' {
        $empty = Join-Path $TestDrive 'empty.bin'; [IO.File]::WriteAllBytes($empty, [byte[]]@())
        $four = Join-Path $TestDrive 'four.bin'; [IO.File]::WriteAllText($four, 'data')
        $cases = @(
            @{ Path = (Join-Path $TestDrive 'missing.bin') }, @{ Path = $empty }, @{ Path = $four },
            @{ Path = $four; ExpectedBytes = 4 }, @{ Path = $four; ExpectedBytes = 5 }, @{ Path = $TestDrive }
        )
        foreach ($case in $cases) {
            $main = Invoke-DupSide 'Main' 'Test-TpmDownloadedFile' $case
            $upd = Invoke-DupSide 'Upd' 'Test-TpmDownloadedFile' $case
            ($upd.Outcome + ':' + $upd.Value) | Should -BeExactly ($main.Outcome + ':' + $main.Value) -Because (($case.Keys | ForEach-Object { $_ + '=' + $case[$_] }) -join ' ')
        }
    }

    It '<Name> saves the same bytes for a good address and fails with the same status for a missing one' -TestCases @(
        @{ Name = 'Invoke-TpmDownloadHttpClient' }, @{ Name = 'Invoke-TpmDownloadWebRequest' }
    ) {
        $seen = foreach ($side in 'Main', 'Upd') {
            $good = Join-Path $TestDrive ($side + $Name + 'good.bin')
            $bad = Join-Path $TestDrive ($side + $Name + 'bad.bin')
            $g = Invoke-DupSide $side $Name @{ DownloadUrl = ($global:DupBase + 'ok'); TempPath = $good; Label = 'f' }
            $failure = $null
            try { & ($side + '_' + $Name) -DownloadUrl ($global:DupBase + 'missing') -TempPath $bad -Label 'f' } catch { $failure = $_ }
            $code = if ($failure) { Get-TpmHttpStatusCodeFromError -ErrorRecord $failure } else { 'no error' }
            $g.Outcome + ' file=' + $(if (Test-Path -LiteralPath $good) { [IO.File]::ReadAllText($good) } else { '<absent>' }) + ' missing=' + $code
        }
        $seen[0] | Should -BeLike 'returned file=hello download missing=404'
        $seen[1] | Should -BeExactly $seen[0]
    }

    It 'Invoke-TpmDownload tries the same methods in the same order and ends in the same state: <Name>' -TestCases @(
        @{ Name = 'BITS works'; Plan = @{}; Bits = $true; Expected = 0; Existing = $false; Ok = $true }
        @{ Name = 'BITS fails, HttpClient works'; Plan = @{ bits = @('f500') }; Bits = $true; Expected = 0; Existing = $false; Ok = $true }
        @{ Name = 'two HttpClient failures, then success'; Plan = @{ http = @('f500', 'f500') }; Bits = $false; Expected = 0; Existing = $false; Ok = $true }
        @{ Name = 'HttpClient 404, web request works'; Plan = @{ http = @('f404') }; Bits = $false; Expected = 0; Existing = $false; Ok = $true }
        @{ Name = 'HttpClient fails 3 times, web request 404'; Plan = @{ http = @('f500', 'f500', 'f500'); web = @('f404') }; Bits = $false; Expected = 0; Existing = $false; Ok = $false }
        @{ Name = 'every method fails 3 times'; Plan = @{ http = @('f500', 'f500', 'f500'); web = @('f500', 'f500', 'f500') }; Bits = $false; Expected = 0; Existing = $false; Ok = $false }
        @{ Name = 'wrong size is refused'; Plan = @{}; Bits = $false; Expected = 99; Existing = $false; Ok = $false }
        @{ Name = 'right size replaces an old file'; Plan = @{}; Bits = $false; Expected = 4; Existing = $true; Ok = $true }
        @{ Name = 'failure keeps the old file'; Plan = @{ http = @('f404'); web = @('f404') }; Bits = $false; Expected = 0; Existing = $true; Ok = $false }
    ) {
        $main = Invoke-DupDownload 'Main' $Plan $Bits $Expected $Existing
        $upd = Invoke-DupDownload 'Upd' $Plan $Bits $Expected $Existing
        $main | Should -BeLike ('ok=' + $Ok + ' *')
        $upd | Should -BeExactly $main
    }

    It 'the harness copy of Resolve-Pcsx2Directory finds the same folder as the main script for every layout' {
        foreach ($side in @(@('Main', $mainPath), @('Harness', (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Resolve-Pcsx2Directory.ps1')).ProviderPath))) {
            . ([scriptblock]::Create(((Get-DupFunctionText $side[1] 'Resolve-Pcsx2Directory') -replace '^function\s+Resolve-Pcsx2Directory', ('function ' + $side[0] + '_Resolve-Pcsx2Directory'))))
        }
        $layouts = @(@(), @('pcsx2x6'), @('PCSX2'), @('pcsx2-custom'), @('pcsx2x6', 'pcsx2'), @('pcsx2x6:file'), @('pcsx2x6:file', 'pcsx2'), @('other'))
        $index = 0
        foreach ($layout in $layouts) {
            $root = Join-Path $TestDrive ('pcsx2layout' + $index++)
            [void][IO.Directory]::CreateDirectory($root)
            foreach ($item in $layout) {
                if ($item -like '*:file') { [IO.File]::WriteAllText((Join-Path $root $item.Split(':')[0]), 'x') } else { [void][IO.Directory]::CreateDirectory((Join-Path $root $item)) }
            }
            $main = Main_Resolve-Pcsx2Directory -TeknoParrotRoot $root
            $harness = Harness_Resolve-Pcsx2Directory -TeknoParrotRoot $root
            $harness | Should -BeExactly $main -Because ($layout -join ',')
        }
    }
}
