#Requires -Module Pester

# Game rules update (data only, signed). Every case ends the same way for a bad file or a bad network: the rules already in use
# stay, nothing is saved, nothing throws. Everything here is synthetic and lives under TestDrive: made-up rules, a TEST KEY PAIR that
# is generated at test time and thrown away (never the owner's key), a mocked network call, and one loopback listener on 127.0.0.1
# for the real byte-level reader. The product script is parsed and only the game-rules functions are dot-sourced; no top-level
# product code runs, and no TeknoParrot, LaunchBox, registry or user-profile data is read or written.
# What this CANNOT prove: that GitHub serves the file the way the mocked reply does, or how a real console paints the one-line message.

# Discovery-time copy (the -ForEach cases below are built before BeforeAll runs); BeforeAll defines the run-time copy.
function New-GrJson {
    param([int]$Version = 2, [string]$Games = '[{"Profile":"Alpha","Disposition":"not-supported","Reason":"Broken on purpose for the test."}]', [string]$Gpu = '[{"Profile":"Alpha","Vendor":"NVIDIA"}]', [string]$Extra = '')
    return ('{{"Format":"TpmGameRulesV1","Version":{0},"Games":{1},"GpuWarnings":{2}{3}}}' -f $Version, $Games, $Gpu, $Extra)
}

BeforeAll {
    $script:GrProduction = (Resolve-Path (Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1')).Path
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:GrProduction, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Game rules tests could not parse the production script.' }
    $functionText = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and ($n.Name -like '*TpmGameRule*' -or $n.Name -eq 'Get-TpmVerifiedGameRules') }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n"
    $file = Join-Path $TestDrive 'game-rules-functions.ps1'
    [System.IO.File]::WriteAllText($file, $functionText, (New-Object System.Text.UTF8Encoding $false))
    . $file
    function Write-Log { param([string]$msg) }   # stand-in so the product logger can be mocked; the real one is not loaded

    $script:TpmGameRulesMaxBytes = 1048576
    $script:TpmGameRulesMaxSignatureBytes = 4096
    $script:TpmGameRulesTimeoutSec = 15
    $script:TpmGameRulesBundledVersion = 1
    $script:TpmGameRulesOverlay = $null
    $script:GrBase = 'https://raw.githubusercontent.com/Jumpstile/teknoparrot-manager/game-data-live/'

    # TEST KEY PAIR ONLY: generated here, never saved, never the owner's key.
    $script:GrKey = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
    $script:GrPublicXml = $script:GrKey.ToXmlString($false)
    $script:GrOtherKey = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)

    function New-GrJson {
        param([int]$Version = 2, [string]$Games = '[{"Profile":"Alpha","Disposition":"not-supported","Reason":"Broken on purpose for the test."}]', [string]$Gpu = '[{"Profile":"Alpha","Vendor":"NVIDIA"}]', [string]$Extra = '')
        return ('{{"Format":"TpmGameRulesV1","Version":{0},"Games":{1},"GpuWarnings":{2}{3}}}' -f $Version, $Games, $Gpu, $Extra)
    }
    function ConvertTo-GrBytes { param([string]$Text) return ,[System.Text.Encoding]::ASCII.GetBytes($Text) }
    function New-GrSignature { param([byte[]]$Bytes, $Key = $script:GrKey) return ,[System.Text.Encoding]::ASCII.GetBytes([System.Convert]::ToBase64String($Key.SignData($Bytes, 'SHA256'))) }
    function Set-GrNetwork {
        param([byte[]]$Data, [byte[]]$Sig, [switch]$Fail)
        $script:GrData = $Data; $script:GrSig = $Sig; $script:GrFail = [bool]$Fail
    }
    function Get-GrTreeList { param([string]$Root) if (-not (Test-Path -LiteralPath $Root)) { return @() }; return @(Get-ChildItem -LiteralPath $Root -Recurse -Force | ForEach-Object { $_.FullName.Substring($Root.Length) } | Sort-Object) }
    function Get-GrTreeNames { param([string]$Root) return (@(Get-GrTreeList $Root) -join ',') }
    function Invoke-GrUpdate {
        param([string]$Root, [string]$BaseUrl = $script:GrBase)
        return (Invoke-TpmGameRulesUpdate -Root $Root -PublicKeyXml $script:GrPublicXml -BaseUrl $BaseUrl -BundledVersion 1)
    }
}

Describe 'Game rules update' {
    BeforeEach {
        $script:GrRoot = Join-Path $TestDrive ('rules-' + [guid]::NewGuid().ToString('N'))
        $script:TpmGameRulesOverlay = $null
        $script:logLines = New-Object System.Collections.Generic.List[string]
        Mock Write-Log { [void]$script:logLines.Add([string]$msg) }
        Mock Write-Host { }
        $script:GrCalls = New-Object System.Collections.Generic.List[string]
        Mock Invoke-TpmGameRulesHttpRequest {
            [void]$script:GrCalls.Add($Url)
            if ($script:GrFail) { throw 'No such host is known.' }
            $bytes = if ($Url.EndsWith('.sig')) { $script:GrSig } else { $script:GrData }
            [pscustomobject]@{ Status = 200; Location = ''; Bytes = $bytes }
        }
    }

    It 'accepts a good signature, uses the rules, saves only its two files and says the version' {
        $data = ConvertTo-GrBytes (New-GrJson -Version 2)
        Set-GrNetwork -Data $data -Sig (New-GrSignature $data)
        $result = Invoke-GrUpdate -Root $script:GrRoot
        $result.Outcome | Should -Be 'Updated' -Because $result.Details
        $result.Version | Should -Be 2
        (Get-TpmGameRuleNote -Code 'Alpha') | Should -Be 'Game rules (version 2): Not supported. Broken on purpose for the test.'
        (@(Get-TpmGameRulesGpuCodes -Vendor 'NVIDIA') -join ',') | Should -Be 'Alpha'
        (Get-GrTreeNames $script:GrRoot) | Should -Be '\game-rules.json,\game-rules.sig'
        [System.IO.File]::ReadAllBytes((Join-Path $script:GrRoot 'game-rules.json')) | Should -Be $data
    }

    It 'shows the one-line result and the one-time notice only once' {
        $data = ConvertTo-GrBytes (New-GrJson -Version 2)
        Set-GrNetwork -Data $data -Sig (New-GrSignature $data)
        $script:GrScreen = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:GrScreen.Add([string]$Object) }
        [void](Invoke-TpmGameRulesStartup -Enabled $true -Root $script:GrRoot -PublicKeyXml $script:GrPublicXml -BaseUrl $script:GrBase -BundledVersion 1)
        @($script:GrScreen | Where-Object { $_ -like '*Game rules updated to version 2.*' }).Count | Should -Be 1
        @($script:GrScreen | Where-Object { $_ -like '*GameRulesUpdate to false*' }).Count | Should -Be 1
        $script:GrScreen.Clear()
        [void](Invoke-TpmGameRulesStartup -Enabled $true -Root $script:GrRoot -PublicKeyXml $script:GrPublicXml -BaseUrl $script:GrBase -BundledVersion 1)
        @($script:GrScreen | Where-Object { $_ -like '*GameRulesUpdate*' }).Count | Should -Be 0
    }

    It 'rejects a signature made by another key and keeps the rules in use' {
        $data = ConvertTo-GrBytes (New-GrJson -Version 2)
        Set-GrNetwork -Data $data -Sig (New-GrSignature $data $script:GrOtherKey)
        $result = Invoke-GrUpdate -Root $script:GrRoot
        $result.Outcome | Should -Be 'Failed'
        $script:TpmGameRulesOverlay | Should -BeNullOrEmpty
        (Get-GrTreeNames $script:GrRoot) | Should -Be ''
    }

    It 'rejects a file with one byte changed after signing' {
        $data = ConvertTo-GrBytes (New-GrJson -Version 2)
        $sig = New-GrSignature $data
        $altered = [byte[]]$data.Clone(); $altered[$altered.Length - 3] = [byte][char]'x'
        Set-GrNetwork -Data $altered -Sig $sig
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Failed'
        $script:TpmGameRulesOverlay | Should -BeNullOrEmpty
        (Get-GrTreeNames $script:GrRoot) | Should -Be ''
    }

    It 'rejects a validly signed file with an unknown or out-of-range value' -ForEach @(
        @{ Why = 'unknown top-level field'; Json = (New-GrJson -Extra ',"Run":"calc.exe"') }
        @{ Why = 'unknown field in a game row'; Json = (New-GrJson -Games '[{"Profile":"A","Disposition":"guided","Reason":"ok","Path":"C:\\x"}]') }
        @{ Why = 'disposition that only code may claim'; Json = (New-GrJson -Games '[{"Profile":"A","Disposition":"tpm-applies-patch","Reason":"ok"}]') }
        @{ Why = 'path-like profile name'; Json = (New-GrJson -Games '[{"Profile":"..\\..\\evil","Disposition":"guided","Reason":"ok"}]') }
        @{ Why = 'profile name with a slash'; Json = (New-GrJson -Gpu '[{"Profile":"a/b","Vendor":"AMD"}]') }
        @{ Why = 'unknown graphics vendor'; Json = (New-GrJson -Gpu '[{"Profile":"A","Vendor":"Matrox"}]') }
        @{ Why = 'version zero'; Json = (New-GrJson -Version 0) }
        @{ Why = 'version as text'; Json = ((New-GrJson) -replace '"Version":2', '"Version":"2"') }
        @{ Why = 'reason longer than 300 characters'; Json = (New-GrJson -Games ('[{"Profile":"A","Disposition":"guided","Reason":"' + ('x' * 301) + '"}]')) }
        @{ Why = 'duplicate game'; Json = (New-GrJson -Games '[{"Profile":"A","Disposition":"guided","Reason":"a"},{"Profile":"a","Disposition":"guided","Reason":"b"}]') }
        @{ Why = 'wrong format name'; Json = ((New-GrJson) -replace 'TpmGameRulesV1', 'TpmGameRulesV2') }
    ) {
        $data = ConvertTo-GrBytes $Json
        Set-GrNetwork -Data $data -Sig (New-GrSignature $data)
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Failed'
        $script:TpmGameRulesOverlay | Should -BeNullOrEmpty
        (Get-GrTreeNames $script:GrRoot) | Should -Be ''
    }

    It 'keeps the saved newer rules when an older or equal version is offered' {
        $v5 = ConvertTo-GrBytes (New-GrJson -Version 5 -Games '[{"Profile":"Five","Disposition":"guided","Reason":"Version five."}]')
        Set-GrNetwork -Data $v5 -Sig (New-GrSignature $v5)
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Updated'
        $v3 = ConvertTo-GrBytes (New-GrJson -Version 3 -Games '[{"Profile":"Three","Disposition":"guided","Reason":"Version three."}]')
        Set-GrNetwork -Data $v3 -Sig (New-GrSignature $v3)
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Failed'
        (Get-TpmGameRuleNote -Code 'Five') | Should -BeLike '*version 5*'
        (Get-TpmGameRuleNote -Code 'Three') | Should -Be ''
        Set-GrNetwork -Data $v5 -Sig (New-GrSignature $v5)
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Current'
        [System.IO.File]::ReadAllBytes((Join-Path $script:GrRoot 'game-rules.json')) | Should -Be $v5
    }

    It 'rejects a file that is not newer than the version that shipped' {
        $v1 = ConvertTo-GrBytes (New-GrJson -Version 1)
        Set-GrNetwork -Data $v1 -Sig (New-GrSignature $v1)
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Current'
        (Get-GrTreeNames $script:GrRoot) | Should -Be ''
    }

    It 'rejects an oversized file from the byte reader and from the whole update' {
        $big = [byte[]]::new($script:TpmGameRulesMaxBytes + 1)
        Set-GrNetwork -Data $big -Sig (ConvertTo-GrBytes 'AAAA')
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Failed'
        (Get-GrTreeNames $script:GrRoot) | Should -Be ''
        { Get-TpmGameRulesBytes -Url ($script:GrBase + 'x.json') -MaxBytes 10 -TimeoutSec 5 } | Should -Throw '*larger than*'
    }

    It 'refuses a non-https address and a wrong host without making a request' -ForEach @(
        @{ Url = 'http://raw.githubusercontent.com/Jumpstile/teknoparrot-manager/game-data-live/' }
        @{ Url = 'https://example.com/Jumpstile/teknoparrot-manager/game-data-live/' }
        @{ Url = 'https://user:pw@raw.githubusercontent.com/x/' }
    ) {
        $data = ConvertTo-GrBytes (New-GrJson -Version 2)
        Set-GrNetwork -Data $data -Sig (New-GrSignature $data)
        (Invoke-GrUpdate -Root $script:GrRoot -BaseUrl $Url).Outcome | Should -Be 'Failed'
        Should -Invoke Invoke-TpmGameRulesHttpRequest -Times 0 -Exactly
        $script:TpmGameRulesOverlay | Should -BeNullOrEmpty
    }

    It 'does not follow a redirect to another host, to http, or after too many hops' -ForEach @(
        @{ Location = 'https://evil.example.com/TpmGameRules.json' }
        @{ Location = 'http://raw.githubusercontent.com/TpmGameRules.json' }
        @{ Location = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/x/TpmGameRules.json' }
    ) {
        $script:GrRedirect = $Location
        Mock Invoke-TpmGameRulesHttpRequest {
            [void]$script:GrCalls.Add($Url)
            [pscustomobject]@{ Status = 302; Location = $script:GrRedirect; Bytes = [byte[]]@() }
        }
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Failed'
        $script:GrCalls.Count | Should -Be 1
        $script:TpmGameRulesOverlay | Should -BeNullOrEmpty
        (Get-GrTreeNames $script:GrRoot) | Should -Be ''
    }

    It 'follows a same-host https redirect but stops after three hops' {
        $script:GrHops = 0
        Mock Invoke-TpmGameRulesHttpRequest {
            $script:GrHops++
            [pscustomobject]@{ Status = 302; Location = ('https://raw.githubusercontent.com/hop' + $script:GrHops); Bytes = [byte[]]@() }
        }
        { Get-TpmGameRulesBytes -Url ($script:GrBase + 'x') -MaxBytes 100 -TimeoutSec 5 } | Should -Throw '*Too many redirects*'
        $script:GrHops | Should -Be 4
    }

    It 'keeps the saved rules and does not crash on a network failure' {
        $v4 = ConvertTo-GrBytes (New-GrJson -Version 4 -Games '[{"Profile":"Four","Disposition":"guided","Reason":"Version four."}]')
        Set-GrNetwork -Data $v4 -Sig (New-GrSignature $v4)
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Updated'
        Set-GrNetwork -Data $v4 -Sig (New-GrSignature $v4) -Fail
        $script:TpmGameRulesOverlay = $null
        $result = Invoke-GrUpdate -Root $script:GrRoot
        $result.Outcome | Should -Be 'Failed'
        $result.Details | Should -BeLike 'The download failed:*'
        (Get-TpmGameRuleNote -Code 'Four') | Should -BeLike '*version 4*'
        ($script:logLines -join "`n") | Should -BeLike '*keeping version 4*'
    }

    It 'ignores a saved copy that was changed on disk' {
        $v4 = ConvertTo-GrBytes (New-GrJson -Version 4)
        Set-GrNetwork -Data $v4 -Sig (New-GrSignature $v4)
        [void](Invoke-GrUpdate -Root $script:GrRoot)
        $path = Join-Path $script:GrRoot 'game-rules.json'
        [System.IO.File]::WriteAllText($path, ((New-GrJson -Version 9) ), [System.Text.Encoding]::ASCII)
        Set-GrNetwork -Data $v4 -Sig (New-GrSignature $v4) -Fail
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Failed'
        $script:TpmGameRulesOverlay | Should -BeNullOrEmpty
    }

    It 'skips the update, without a request, when no public key is built in' {
        $result = Invoke-TpmGameRulesUpdate -Root $script:GrRoot -PublicKeyXml '' -BaseUrl $script:GrBase -BundledVersion 1
        $result.Outcome | Should -Be 'Skipped'
        Should -Invoke Invoke-TpmGameRulesHttpRequest -Times 0 -Exactly
    }

    It 'does not tell the player the rules are checked, or record that notice, while no public key is built in' {
        # Mutation: print and record the notice before knowing the update can run -> the player is told about a check that never happens.
        $script:GrScreen = New-Object System.Collections.Generic.List[string]
        Mock Write-Host { [void]$script:GrScreen.Add([string]$Object) }
        $script:TpmGameRulesPublicKeyXml = ''
        [void](Invoke-TpmGameRulesStartup -Enabled $true -Root $script:GrRoot -PublicKeyXml '' -BaseUrl $script:GrBase -BundledVersion 1)
        @($script:GrScreen | Where-Object { $_ -like '*checks for newer game rules*' }).Count | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:GrRoot 'notice-shown.txt') | Should -BeFalse
    }

    It 'keeps the old verified pair when the signature cannot be replaced after the data was, and says what is on disk' {
        # Mutation: replace the two files one after the other with no way back -> new data sits next to the old signature and the saved rules are lost.
        $v2 = ConvertTo-GrBytes (New-GrJson -Version 2)
        Set-GrNetwork -Data $v2 -Sig (New-GrSignature $v2)
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Updated'
        $v3 = ConvertTo-GrBytes (New-GrJson -Version 3)
        Set-GrNetwork -Data $v3 -Sig (New-GrSignature $v3)
        $script:TpmGameRulesOverlay = $null
        Mock Move-Item { throw 'The file is in use.' } -ParameterFilter { $LiteralPath -like '*game-rules.sig.*.tmp' }
        $result = Invoke-GrUpdate -Root $script:GrRoot
        $result.Outcome | Should -Be 'Failed'
        $result.Details | Should -BeLike '*put back*'
        (Get-GrTreeNames $script:GrRoot) | Should -Be '\game-rules.json,\game-rules.sig'
        $cached = Read-TpmGameRulesCache -Root $script:GrRoot -PublicKeyXml $script:GrPublicXml -BundledVersion 1
        [int64]$cached.Version | Should -Be 2
    }

    It 'makes no request and uses no saved copy when the setting is off' {
        $v4 = ConvertTo-GrBytes (New-GrJson -Version 4)
        Set-GrNetwork -Data $v4 -Sig (New-GrSignature $v4)
        [void](Invoke-GrUpdate -Root $script:GrRoot)
        $script:GrCalls.Clear()
        $null = Invoke-TpmGameRulesStartup -Enabled $false -Root $script:GrRoot -PublicKeyXml $script:GrPublicXml -BaseUrl $script:GrBase -BundledVersion 1
        $script:GrCalls.Count | Should -Be 0
        $script:TpmGameRulesOverlay | Should -BeNullOrEmpty
        (Get-TpmGameRuleNote -Code 'Alpha') | Should -Be ''
    }

    It 'a validly signed file can only change text and warnings: nothing is written outside the two cache files' {
        $games = '[{"Profile":"Alpha","Disposition":"guided","Reason":"Delete C:\\Windows and run powershell -c calc; ..\\..\\x"}]'
        $data = ConvertTo-GrBytes (New-GrJson -Version 2 -Games $games)
        Set-GrNetwork -Data $data -Sig (New-GrSignature $data)
        $knownBefore = New-Object 'System.Collections.Generic.HashSet[string]' (,[string[]]@(Get-GrTreeList $TestDrive))
        (Invoke-GrUpdate -Root $script:GrRoot).Outcome | Should -Be 'Updated'
        $afterTree = @(Get-GrTreeList $TestDrive)
        $new = @($afterTree | Where-Object { -not $knownBefore.Contains([string]$_) })
        @($new | Where-Object { $_ -notlike ('*' + (Split-Path -Leaf $script:GrRoot) + '*') }).Count | Should -Be 0
        (Get-GrTreeNames $script:GrRoot) | Should -Be '\game-rules.json,\game-rules.sig'
        (Get-TpmGameRuleNote -Code 'Alpha') | Should -BeLike '*Delete C:*'
    }

    It 'only adds graphics warnings: the update never returns a shipped entry to remove' {
        $data = ConvertTo-GrBytes (New-GrJson -Version 2 -Games '[]' -Gpu '[{"Profile":"Newgame","Vendor":"AMD"}]')
        Set-GrNetwork -Data $data -Sig (New-GrSignature $data)
        [void](Invoke-GrUpdate -Root $script:GrRoot)
        (@(Get-TpmGameRulesGpuCodes -Vendor 'AMD') -join ',') | Should -Be 'Newgame'
        (@(Get-TpmGameRulesGpuCodes -Vendor 'Intel') -join ',') | Should -Be ''
    }
}

Describe 'Game rules byte reader (loopback only)' {
    BeforeAll {
        $script:GrPort = Get-Random -Minimum 20000 -Maximum 40000
        $script:GrListener = New-Object System.Net.HttpListener
        $script:GrListener.Prefixes.Add("http://127.0.0.1:$($script:GrPort)/")
        $script:GrListener.Start()
        $script:GrPs = [powershell]::Create()
        [void]$script:GrPs.AddScript({
            param($listener)
            while ($listener.IsListening) {
                try { $context = $listener.GetContext() } catch { break }
                $path = $context.Request.Url.AbsolutePath
                if ($path -eq '/redirect') { $context.Response.StatusCode = 302; $context.Response.RedirectLocation = 'https://evil.example.com/x' }
                elseif ($path -eq '/big') { $body = [byte[]]::new(5000); $context.Response.OutputStream.Write($body, 0, $body.Length) }
                else { $body = [System.Text.Encoding]::ASCII.GetBytes('small'); $context.Response.OutputStream.Write($body, 0, $body.Length) }
                $context.Response.Close()
            }
        }).AddArgument($script:GrListener)
        $script:GrHandle = $script:GrPs.BeginInvoke()
    }
    AfterAll {
        try { $script:GrListener.Stop(); $script:GrListener.Close() } catch { }
        try { $script:GrPs.Stop(); $script:GrPs.Dispose() } catch { }
    }

    It 'reads a small body and reports the status' {
        $reply = Invoke-TpmGameRulesHttpRequest -Url "http://127.0.0.1:$($script:GrPort)/small" -MaxBytes 100 -TimeoutSec 5
        $reply.Status | Should -Be 200
        [System.Text.Encoding]::ASCII.GetString($reply.Bytes) | Should -Be 'small'
    }
    It 'stops reading a body bigger than the limit' {
        { Invoke-TpmGameRulesHttpRequest -Url "http://127.0.0.1:$($script:GrPort)/big" -MaxBytes 1000 -TimeoutSec 5 } | Should -Throw '*larger than*'
    }
    It 'does not follow a redirect by itself' {
        $reply = Invoke-TpmGameRulesHttpRequest -Url "http://127.0.0.1:$($script:GrPort)/redirect" -MaxBytes 1000 -TimeoutSec 5
        $reply.Status | Should -Be 302
        $reply.Location | Should -Be 'https://evil.example.com/x'
        $reply.Bytes.Length | Should -Be 0
    }
}
