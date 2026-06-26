#Requires -Module Pester

# Regression suite for the pure / read-only helper functions in
# TeknoParrot-Manager.ps1. The script itself is not a module -- it is one
# file whose function definitions are followed by top-level executable
# code (the interactive menu loop), so it cannot be dot-sourced directly
# without launching that loop. Instead, BeforeAll below parses the file
# with the PowerShell AST and defines only the function bodies in this
# session. This requires zero changes to the production script.
#
# Run with: Invoke-Pester -Path .\Tests\TeknoParrot-Manager.Tests.ps1

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot "..\TeknoParrot-Manager.ps1"
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Failed to parse TeknoParrot-Manager.ps1: $($parseErrors -join '; ')"
    }
    $functionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    foreach ($fn in $functionAsts) {
        . ([scriptblock]::Create($fn.Extent.Text))
    }

    # $FuzzyAutoThreshold/$FuzzyTieMargin are top-level script-scope constants (not
    # function bodies), so the AST extraction above never picks them up. Functions
    # like Resolve-BestFuzzyMatch read them as unqualified script-scope variables,
    # so without this they'd silently read as $null here -- mirror the production
    # values from TeknoParrot-Manager.ps1 explicitly.
    $FuzzyAutoThreshold = 0.72
    $FuzzyTieMargin     = 0.1

    # $script:LocalDriveInfoCache/$LocalDriveInfoCachePopulated are top-level
    # script-scope variables (not function bodies) initialised before
    # Get-LocalDriveInfoSafe / Clear-LocalDriveInfoCache in the production
    # script. Initialise them here so those functions behave correctly in the
    # test scope (an uninitialised $null is falsy, so the first call would still
    # spawn the job, but the explicit init is cleaner and avoids surprises).
    $script:LocalDriveInfoCache          = $null
    $script:LocalDriveInfoCachePopulated = $false
}

Describe "Test-PathInside" {
    It "returns true when child equals parent" {
        Test-PathInside "C:\Foo\Bar" "C:\Foo\Bar" | Should -BeTrue
    }
    It "returns true for a real child path" {
        Test-PathInside "C:\Foo\Bar\baz.txt" "C:\Foo\Bar" | Should -BeTrue
    }
    It "returns false for a sibling path that merely shares a string prefix" {
        Test-PathInside "C:\Foo\Barbaz" "C:\Foo\Bar" | Should -BeFalse
    }
    It "returns false for an unrelated path" {
        Test-PathInside "C:\Other\thing.txt" "C:\Foo\Bar" | Should -BeFalse
    }
    It "is case-insensitive" {
        Test-PathInside "c:\foo\bar\baz.txt" "C:\Foo\Bar" | Should -BeTrue
    }
}

Describe "Invoke-WithHardTimeout" {
    # Issue #5 (v1.0 roadmap): a generic hard-timeout wrapper for a local call
    # that could theoretically still block. Uses a real background job (not
    # mocked) since the whole point is genuine process-level isolation -- these
    # tests use short, deterministic scriptblocks so they stay fast.
    It "returns the scriptblock's output when it completes well within the timeout" {
        Invoke-WithHardTimeout -ScriptBlock { 1 + 1 } -TimeoutSeconds 5 | Should -Be 2
    }
    It "returns null and does not throw when the scriptblock exceeds the timeout" {
        $result = $null
        { $result = Invoke-WithHardTimeout -ScriptBlock { Start-Sleep -Seconds 10 } -TimeoutSeconds 1 } | Should -Not -Throw
        $result | Should -BeNullOrEmpty
    }
    It "returns null and does not throw when the scriptblock itself throws" {
        { Invoke-WithHardTimeout -ScriptBlock { throw "boom" } -TimeoutSeconds 5 } | Should -Not -Throw
        Invoke-WithHardTimeout -ScriptBlock { throw "boom" } -TimeoutSeconds 5 | Should -BeNullOrEmpty
    }
}

Describe "Test-IsNetworkPath" {
    # DriveInfo.DriveType is a read-only OS-derived property with no public
    # constructor for a synthetic "Network" instance, so these tests cover
    # the reachable surface without needing a real mapped network drive:
    # the UNC short-circuit (no drive lookup at all), the explicit -Drives
    # override against this machine's real (non-network) drives, and the
    # fail-safe path when drive info genuinely could not be determined
    # (mocking Get-LocalDriveInfoSafe rather than passing -Drives $null,
    # since that default is indistinguishable from "not supplied" and would
    # otherwise just spawn the real job and exercise the success path).
    It "treats a UNC path as a network path without needing drive info at all" {
        Test-IsNetworkPath '\\nas\share\folder' | Should -BeTrue
    }
    It "returns false for an empty or whitespace path" {
        Test-IsNetworkPath '' | Should -BeFalse
        Test-IsNetworkPath '   ' | Should -BeFalse
    }
    It "uses the Name/IsNetwork shape (not a real DriveInfo) when -Drives is supplied explicitly" {
        # -Drives is deliberately untyped (see Test-IsNetworkPath's own comment) -- a real
        # [System.IO.DriveInfo[]] is NOT what gets passed in production. Get-LocalDriveInfoSafe
        # runs in a background job, and a real DriveInfo crossing that job boundary comes back
        # as an undeserializable stand-in (confirmed from a real tester's crash, issue #5
        # follow-up) -- this is the actual shape real callers use.
        $drives = @([pscustomobject]@{ Name = 'C:\'; IsNetwork = $false })
        Test-IsNetworkPath 'C:\Windows' -Drives $drives | Should -BeFalse
    }
    It "detects a network drive via the Name/IsNetwork shape" {
        $drives = @([pscustomobject]@{ Name = 'Z:\'; IsNetwork = $true })
        Test-IsNetworkPath 'Z:\Games' -Drives $drives | Should -BeTrue
    }
    It "fails safe (returns false, never throws) when drive info could not be determined" {
        Mock Get-LocalDriveInfoSafe { $null }
        { Test-IsNetworkPath 'Z:\Games' } | Should -Not -Throw
        Test-IsNetworkPath 'Z:\Games' | Should -BeFalse
    }
    It "end-to-end: works through the real job-backed Get-LocalDriveInfoSafe without throwing" {
        # Regression test for the actual bug a tester hit: this is the exact call shape
        # Find-TeknoParrotRoot/Find-LaunchBoxRoot use, going through the real background
        # job rather than a mocked or directly-constructed -Drives value. Before the fix,
        # this threw "Cannot convert ... Deserialized.System.IO.DriveInfo ... to type
        # System.IO.DriveInfo" because Get-LocalDriveInfoSafe used to return real DriveInfo
        # objects across the job boundary.
        $localDriveInfo = Get-LocalDriveInfoSafe
        { Test-IsNetworkPath "$($env:SystemDrive)\Windows" -Drives $localDriveInfo } | Should -Not -Throw
        Test-IsNetworkPath "$($env:SystemDrive)\Windows" -Drives $localDriveInfo | Should -BeFalse
    }
}

Describe "Get-LocalDriveInfoSafe" {
    BeforeEach {
        # Reset the cache before every test so each one starts from a clean slate.
        Clear-LocalDriveInfoCache
    }
    It "returns real drive info (including the system drive) within the timeout in the normal case" {
        $result = Get-LocalDriveInfoSafe
        $result | Should -Not -BeNullOrEmpty
        ($result | Where-Object { $_.Name -eq "$($env:SystemDrive)\" }) | Should -Not -BeNullOrEmpty
    }
    It "returns plain pscustomobjects, never real DriveInfo instances (the actual bug this guards against)" {
        # Get-LocalDriveInfoSafe runs across a background-job boundary (Invoke-WithHardTimeout);
        # Receive-Job deserializes a real [System.IO.DriveInfo] into an undeserializable
        # "Deserialized.System.IO.DriveInfo" stand-in that fails any strongly-typed
        # [System.IO.DriveInfo[]] parameter bind downstream. Returning plain Name/IsNetwork
        # data instead is the actual fix -- this test locks that shape in.
        $result = Get-LocalDriveInfoSafe
        foreach ($d in $result) {
            $d | Should -BeOfType [System.Management.Automation.PSCustomObject]
            $d.PSObject.Properties.Name | Should -Contain 'Name'
            $d.PSObject.Properties.Name | Should -Contain 'IsNetwork'
        }
    }
    It "populates the cache after the first call so subsequent calls skip the background job" {
        $script:LocalDriveInfoCachePopulated | Should -BeFalse
        Get-LocalDriveInfoSafe | Out-Null
        $script:LocalDriveInfoCachePopulated | Should -BeTrue
        $script:LocalDriveInfoCache | Should -Not -BeNullOrEmpty
    }
    It "Clear-LocalDriveInfoCache resets the populated flag so the next call re-fetches" {
        Get-LocalDriveInfoSafe | Out-Null
        $script:LocalDriveInfoCachePopulated | Should -BeTrue
        Clear-LocalDriveInfoCache
        $script:LocalDriveInfoCachePopulated | Should -BeFalse
        $script:LocalDriveInfoCache | Should -BeNullOrEmpty
    }
}

Describe "ConvertTo-XPathStringLiteral" {
    It "wraps a plain string in single quotes" {
        ConvertTo-XPathStringLiteral "GPU Fix" | Should -Be "'GPU Fix'"
    }
    It "builds a concat() expression when the string contains a single quote" {
        $result = ConvertTo-XPathStringLiteral "It's a Field"
        $result | Should -BeLike "concat(*"
        $result | Should -Not -BeLike "*''''*"
    }
}

Describe "Get-SafeLaunchBoxPlatformFileName" {
    It "passes through an already-safe name" {
        Get-SafeLaunchBoxPlatformFileName "TeknoParrot" | Should -Be "TeknoParrot"
    }
    It "strips invalid filename characters" {
        Get-SafeLaunchBoxPlatformFileName 'My:Plat*form?' | Should -Be "MyPlatform"
    }
    It "trims surrounding whitespace" {
        Get-SafeLaunchBoxPlatformFileName "  Spaced  " | Should -Be "Spaced"
    }
    It "falls back to TeknoParrot when every character is invalid" {
        Get-SafeLaunchBoxPlatformFileName '<>:*' | Should -Be "TeknoParrot"
    }
}

Describe "Set-SecondaryExecutablePath" {
    BeforeAll {
        function New-TwoExeDoc([string]$exe2Name = "amdaemon.exe", [string]$gamePath2 = "") {
            return [xml]@"
<GameProfile>
  <ExecutableName>InitialD0_DX11_Nu.exe</ExecutableName>
  <ExecutableName2>$exe2Name</ExecutableName2>
  <HasTwoExecutables>true</HasTwoExecutables>
  <GamePath2>$gamePath2</GamePath2>
</GameProfile>
"@
        }
    }

    It "sets GamePath2 when the companion exe sits alongside the primary exe" {
        $dir = Join-Path $TestDrive "idz"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        $doc = New-TwoExeDoc
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be (Join-Path $dir "amdaemon.exe")
    }
    It "leaves GamePath2 unset when the companion exe is not found alongside the primary exe" {
        $dir = Join-Path $TestDrive "idz-missing"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))

        $doc = New-TwoExeDoc
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -BeNullOrEmpty
    }
    It "does nothing when HasTwoExecutables is not true" {
        $dir = Join-Path $TestDrive "single-exe"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "game.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        $doc = [xml]"<GameProfile><ExecutableName2>amdaemon.exe</ExecutableName2><HasTwoExecutables>false</HasTwoExecutables></GameProfile>"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.SelectSingleNode("GamePath2") | Should -BeNullOrEmpty
    }
    It "never overwrites a GamePath2 that already points at the correct companion exe" {
        $dir = Join-Path $TestDrive "idz-already"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        $correctGp2 = Join-Path $dir "amdaemon.exe"
        [System.IO.File]::WriteAllBytes($correctGp2, [byte[]]@(0))

        $doc = New-TwoExeDoc -gamePath2 $correctGp2
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be $correctGp2
    }
    It "corrects a stale GamePath2 left pointing at a folder the primary exe no longer lives in" {
        $dir = Join-Path $TestDrive "idz-stale"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "InitialD0_DX11_Nu.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))
        [System.IO.File]::WriteAllBytes((Join-Path $dir "amdaemon.exe"), [byte[]]@(0))

        # Simulates GamePath having been migrated/repaired to $dir while
        # GamePath2 was left behind pointing at the old pre-migration location.
        $doc = New-TwoExeDoc -gamePath2 "F:\old\stale\location\amdaemon.exe"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.GamePath2 | Should -Be (Join-Path $dir "amdaemon.exe")
    }
    It "does nothing when ExecutableName2 is blank" {
        $dir = Join-Path $TestDrive "no-exe2-name"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $primary = Join-Path $dir "game.exe"
        [System.IO.File]::WriteAllBytes($primary, [byte[]]@(0))

        $doc = [xml]"<GameProfile><ExecutableName2></ExecutableName2><HasTwoExecutables>true</HasTwoExecutables></GameProfile>"
        Set-SecondaryExecutablePath $doc $primary

        $doc.GameProfile.SelectSingleNode("GamePath2") | Should -BeNullOrEmpty
    }
}

Describe "Get-ButtonKey / Test-ButtonIsBound" {
    BeforeAll {
        function New-ButtonNode([string]$xml) {
            $doc = [xml]$xml
            return $doc.DocumentElement
        }
    }

    It "builds an InputMapping|AnalogType composite key" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping><AnalogType>Wheel</AnalogType></JoystickButtons>"
        Get-ButtonKey $btn | Should -Be "P1Button1|Wheel"
    }
    It "defaults AnalogType to None when absent" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping></JoystickButtons>"
        Get-ButtonKey $btn | Should -Be "P1Button1|None"
    }
    It "returns null when InputMapping is missing" {
        $btn = New-ButtonNode "<JoystickButtons><AnalogType>Wheel</AnalogType></JoystickButtons>"
        Get-ButtonKey $btn | Should -BeNullOrEmpty
    }
    It "returns null when InputMapping is blank" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>   </InputMapping></JoystickButtons>"
        Get-ButtonKey $btn | Should -BeNullOrEmpty
    }
    It "reports a button as bound when it has a DirectInputButton child" {
        $btn = New-ButtonNode "<JoystickButtons><DirectInputButton>3</DirectInputButton></JoystickButtons>"
        Test-ButtonIsBound $btn | Should -BeTrue
    }
    It "reports a button as unbound with no binding children" {
        $btn = New-ButtonNode "<JoystickButtons><InputMapping>P1Button1</InputMapping></JoystickButtons>"
        Test-ButtonIsBound $btn | Should -BeFalse
    }
}

Describe "Get-GameApiDll" {
    BeforeAll {
        function New-FakeExe([string]$name, [string]$marker) {
            $path = Join-Path $TestDrive $name
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("MZ-stub-padding-$marker-more-padding")
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return $path
        }
    }

    It "detects d3d9.dll" {
        $p = New-FakeExe "d3d9.exe" "d3d9.dll"
        Get-GameApiDll -ExePath $p | Should -Be "d3d9.dll"
    }
    It "detects opengl32.dll" {
        $p = New-FakeExe "gl.exe" "opengl32.dll"
        Get-GameApiDll -ExePath $p | Should -Be "opengl32.dll"
    }
    It "maps d3d11.dll imports to dxgi.dll" {
        $p = New-FakeExe "d3d11.exe" "d3d11.dll"
        Get-GameApiDll -ExePath $p | Should -Be "dxgi.dll"
    }
    It "prefers d3d12 over d3d11 when an exe imports both" {
        $p = New-FakeExe "both.exe" "d3d11.dll-and-d3d12.dll"
        Get-GameApiDll -ExePath $p | Should -Be "d3d12.dll"
    }
    It "returns null when no known API is imported" {
        $p = New-FakeExe "plain.exe" "nothing-recognizable"
        Get-GameApiDll -ExePath $p | Should -BeNullOrEmpty
    }
}

Describe "Get-GameLegacyApi" {
    BeforeAll {
        function New-FakeExe([string]$name, [string]$marker) {
            $path = Join-Path $TestDrive $name
            $bytes = [System.Text.Encoding]::ASCII.GetBytes("MZ-stub-padding-$marker-more-padding")
            [System.IO.File]::WriteAllBytes($path, $bytes)
            return $path
        }
    }

    It "detects D3D8" {
        $p = New-FakeExe "d3d8.exe" "d3d8.dll"
        Get-GameLegacyApi -ExePath $p | Should -Contain "D3D8"
    }
    It "detects DDraw and Glide2x together" {
        $p = New-FakeExe "combo.exe" "ddraw.dll-and-glide2x.dll"
        $result = Get-GameLegacyApi -ExePath $p
        $result | Should -Contain "DDraw"
        $result | Should -Contain "Glide2x"
    }
    It "returns an empty array when nothing legacy is imported" {
        $p = New-FakeExe "modern.exe" "d3d11.dll"
        Get-GameLegacyApi -ExePath $p | Should -BeNullOrEmpty
    }
}

Describe "Test-GpuFixUpToDate" {
    BeforeAll {
        function New-ProfileDoc([string]$inner) {
            return [xml]"<GameProfile><ConfigValues>$inner</ConfigValues></GameProfile>"
        }
    }

    It "is not eligible when no matching field exists in the profile" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>Unrelated</FieldName><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.Eligible | Should -BeFalse
        $result.UpToDate | Should -BeFalse
    }
    It "flags a bool AMD field that needs to flip from 0 to 1 for an AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '1'
    }
    It "is up to date when a bool AMD field is already 1 for an AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'AMD'
        $result.UpToDate | Should -BeTrue
        $result.Changes.Count | Should -Be 0
    }
    It "wants a bool AMD field set to 0 for a non-AMD vendor" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>EnableAmdFix</FieldName><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @('EnableAmdFix') -DropdownFields @() -Vendor 'NVIDIA'
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '0'
    }
    It "resolves a dropdown GPU Fix field to NVIDIA when offered" {
        $doc = New-ProfileDoc @"
<FieldInformation>
  <FieldName>GPU Fix</FieldName>
  <FieldValue>None</FieldValue>
  <FieldOptions><string>None</string><string>AMD</string><string>NVIDIA</string><string>INTEL</string></FieldOptions>
</FieldInformation>
"@
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $result.Eligible | Should -BeTrue
        $result.Changes[0].NewValue | Should -Be 'NVIDIA'
    }
    It "prefers 'New AMD Driver' over 'AMD' when both dropdown options exist" {
        $doc = New-ProfileDoc @"
<FieldInformation>
  <FieldName>GPU Fix</FieldName>
  <FieldValue>None</FieldValue>
  <FieldOptions><string>None</string><string>AMD</string><string>New AMD Driver</string></FieldOptions>
</FieldInformation>
"@
        $result = Test-GpuFixUpToDate -Doc $doc -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD'
        $result.Changes[0].NewValue | Should -Be 'New AMD Driver'
    }
}

Describe "Test-FFBBlasterUpToDate" {
    BeforeAll {
        function New-ProfileDoc([string]$inner) {
            return [xml]"<GameProfile><ConfigValues>$inner</ConfigValues></GameProfile>"
        }
    }

    It "is not eligible when the category is absent" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>Unrelated</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.Eligible | Should -BeFalse
    }
    It "flags a CategoryName-based FFB Blaster field that needs enabling" {
        $doc = New-ProfileDoc "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
        $result.Changes[0].NewValue | Should -Be '1'
    }
    It "is up to date when already enabled" {
        $doc = New-ProfileDoc "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster')
        $result.UpToDate | Should -BeTrue
    }
    It "falls back to matching by FieldName on older-build profiles with no CategoryName match" {
        $doc = New-ProfileDoc "<FieldInformation><FieldName>FFB Blaster Enabled</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $result = Test-FFBBlasterUpToDate -Doc $doc -Categories @('FFB Blaster Enabled')
        $result.Eligible | Should -BeTrue
        $result.Changes[0].NewValue | Should -Be '1'
    }
}

Describe "Get-ReShadeTargetInfo" {
    BeforeAll {
        function New-ProfileDoc([string]$emuType) {
            return [xml]"<GameProfile><EmulatorType>$emuType</EmulatorType></GameProfile>"
        }
        function New-FakeExe([string]$dir, [string]$name, [string]$marker) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $path = Join-Path $dir $name
            [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::ASCII.GetBytes("MZ-pad-$marker-pad"))
            return $path
        }
    }

    It "forces opengl32.dll for BudgieLoader games regardless of detected imports" {
        $exeDir = Join-Path $TestDrive "budgie"
        $exe = New-FakeExe $exeDir "game.exe" "d3d9.dll"
        $doc = New-ProfileDoc "BudgieLoader"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.DllName | Should -Be "opengl32.dll"
        $result.TargetDir | Should -Be $exeDir
    }
    It "redirects to the openparrot subfolder when one exists" {
        $exeDir = Join-Path $TestDrive "opgame"
        $exe = New-FakeExe $exeDir "game.exe" "d3d9.dll"
        $opDir = Join-Path $exeDir "openparrot"
        New-Item -ItemType Directory -Path $opDir -Force | Out-Null
        $doc = New-ProfileDoc "OpenParrot"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.TargetDir | Should -Be $opDir
        $result.DllName | Should -Be "d3d9.dll"
    }
    It "falls back to dxgi.dll and reports ApiDetected=false when nothing is recognized" {
        $exeDir = Join-Path $TestDrive "unknown"
        $exe = New-FakeExe $exeDir "game.exe" "nothing-here"
        $doc = New-ProfileDoc "Default"
        $result = Get-ReShadeTargetInfo -Doc $doc -GamePath $exe -ExeDir $exeDir
        $result.DllName | Should -Be "dxgi.dll"
        $result.ApiDetected | Should -BeFalse
    }
}

Describe "Get-DiceSimilarity" {
    It "returns 1.0 for identical strings" {
        Get-DiceSimilarity "StreetFighterIII3rdStrike" "StreetFighterIII3rdStrike" | Should -Be 1.0
    }
    It "returns 0.0 for completely different strings" {
        Get-DiceSimilarity "aaaa" "zzzz" | Should -Be 0.0
    }
    It "returns 0.0 when either string is shorter than 2 characters" {
        Get-DiceSimilarity "a" "aa" | Should -Be 0.0
        Get-DiceSimilarity "" "aa" | Should -Be 0.0
    }
    It "is symmetric" {
        $ab = Get-DiceSimilarity "GoldenTeeLive2019" "Golden Tee Live 2019"
        $ba = Get-DiceSimilarity "Golden Tee Live 2019" "GoldenTeeLive2019"
        $ab | Should -Be $ba
    }
    It "scores a close abbreviation higher than an unrelated string" {
        $close      = Get-DiceSimilarity "InitialD8" "InitialDArcadeStage8"
        $unrelated  = Get-DiceSimilarity "InitialD8" "MarioKartArcadeGP"
        $close | Should -BeGreaterThan $unrelated
    }
    It "scores an exact match strictly higher than a partial fuzzy match" {
        $exact   = Get-DiceSimilarity "VirtuaFighter5" "VirtuaFighter5"
        $partial = Get-DiceSimilarity "VirtuaFighter5" "VirtuaFighter4"
        $exact | Should -BeGreaterThan $partial
    }
}

Describe "Expand-ZipFileSafe" {
    BeforeAll {
        function New-TestZip([string]$zipPath, [hashtable]$entries) {
            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            $fs = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::CreateNew)
            try {
                $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
                try {
                    foreach ($name in $entries.Keys) {
                        $entry = $archive.CreateEntry($name)
                        $w = New-Object System.IO.StreamWriter($entry.Open())
                        try { $w.Write($entries[$name]) } finally { $w.Dispose() }
                    }
                } finally { $archive.Dispose() }
            } finally { $fs.Dispose() }
        }
    }

    It "extracts normal nested entries with their content intact" {
        $zip  = Join-Path $TestDrive "normal.zip"
        $dest = Join-Path $TestDrive "normal-out"
        New-TestZip $zip @{ "sub/folder/file.txt" = "hello" }
        Expand-ZipFileSafe -ZipPath $zip -DestDir $dest
        Get-Content -LiteralPath (Join-Path $dest "sub\folder\file.txt") -Raw | Should -Be "hello"
    }
    It "rejects an entry with a directory traversal segment" {
        $zip  = Join-Path $TestDrive "traversal.zip"
        $dest = Join-Path $TestDrive "traversal-out"
        New-TestZip $zip @{ "../escape.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "rejects an entry with a deeper directory traversal segment" {
        $zip  = Join-Path $TestDrive "traversal2.zip"
        $dest = Join-Path $TestDrive "traversal2-out"
        New-TestZip $zip @{ "sub/../../escape.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "rejects an absolute (rooted) entry path" {
        $zip  = Join-Path $TestDrive "rooted.zip"
        $dest = Join-Path $TestDrive "rooted-out"
        New-TestZip $zip @{ "C:/evil.txt" = "evil" }
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw "*escapes destination folder*"
    }
    It "throws cleanly on a corrupt zip file" {
        $zip = Join-Path $TestDrive "corrupt.zip"
        [System.IO.File]::WriteAllBytes($zip, [byte[]]@(1,2,3,4,5))
        $dest = Join-Path $TestDrive "corrupt-out"
        { Expand-ZipFileSafe -ZipPath $zip -DestDir $dest } | Should -Throw
    }
}

Describe "Test-DgVoodoo2UpToDate" {
    It "is not eligible when the game imports no legacy API" {
        $result = Test-DgVoodoo2UpToDate -Apis @() -ExeDir (Join-Path $TestDrive "anything")
        $result.Eligible | Should -BeFalse
        $result.UpToDate | Should -BeTrue
    }
    It "is eligible but not up to date when the required DLL is missing" {
        $dir = Join-Path $TestDrive "needsdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $result = Test-DgVoodoo2UpToDate -Apis @('D3D8') -ExeDir $dir
        $result.Eligible | Should -BeTrue
        $result.UpToDate | Should -BeFalse
    }
    It "is up to date once the required DLL is present" {
        $dir = Join-Path $TestDrive "hasdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dir "D3D8.dll"), [byte[]]@(0))
        $result = Test-DgVoodoo2UpToDate -Apis @('D3D8') -ExeDir $dir
        $result.UpToDate | Should -BeTrue
    }
    It "requires every implicated DLL, not just one of several" {
        $dir = Join-Path $TestDrive "partialdg"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $dir "DDraw.dll"), [byte[]]@(0))
        $result = Test-DgVoodoo2UpToDate -Apis @('DDraw', 'Glide2x') -ExeDir $dir
        $result.UpToDate | Should -BeFalse
    }
}

Describe "Write-DownloadAudit" {
    BeforeAll {
        Mock Write-Log {}
    }

    It "logs the actual SHA256 of the downloaded file" {
        $path = Join-Path $TestDrive "audit1.bin"
        [System.IO.File]::WriteAllBytes($path, [System.Text.Encoding]::ASCII.GetBytes("some download content"))
        $expectedHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash

        Write-DownloadAudit -Source "https://example.com/file.bin" -FileName "audit1.bin" -Path $path

        Should -Invoke Write-Log -Times 1 -ParameterFilter {
            $msg -like "*SHA256=$expectedHash*" -and $msg -like "*File=audit1.bin*" -and $msg -like "*Source=https://example.com/file.bin*"
        }
    }
    It "omits the Version segment when no version is supplied" {
        $path = Join-Path $TestDrive "audit2.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))

        Write-DownloadAudit -Source "src" -FileName "audit2.bin" -Path $path

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -notlike "*Version=*" }
    }
    It "includes the Version segment when a version is supplied" {
        $path = Join-Path $TestDrive "audit3.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))

        Write-DownloadAudit -Source "src" -FileName "audit3.bin" -Path $path -Version "1.2.3"

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*Version=1.2.3*" }
    }
    It "fails closed (logs, does not throw) when the file does not exist" {
        $missingPath = Join-Path $TestDrive "does-not-exist.bin"

        { Write-DownloadAudit -Source "src" -FileName "missing.bin" -Path $missingPath } | Should -Not -Throw

        Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*could not hash*missing.bin*" }
    }
    It "fails closed (logs, does not throw) when the file is locked by another process" {
        $path = Join-Path $TestDrive "locked.bin"
        [System.IO.File]::WriteAllBytes($path, [byte[]]@(1, 2, 3))
        $handle = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            { Write-DownloadAudit -Source "src" -FileName "locked.bin" -Path $path } | Should -Not -Throw
            Should -Invoke Write-Log -Times 1 -ParameterFilter { $msg -like "*could not hash*locked.bin*" }
        } finally {
            $handle.Dispose()
        }
    }
}

Describe "Build-DatIndexFromStream" {
    # Real collection dats have dozens to hundreds of <rom> hash entries per
    # <game>, skipped via reader.Skip() for performance. A real regression
    # (issue #12) had the surrounding loop call Read() again right after
    # Skip() already advanced the reader, silently discarding whatever node
    # Skip() had landed on -- on a real 506-game dat this dropped roughly
    # half of all games (493 opened, only 236 closed) regardless of whether
    # they had a valid GameProfile. These games deliberately carry varying
    # <rom> counts (0, 1, 3) so a regression of that exact shape fails here
    # instead of only on a multi-hundred-entry real dat.
    BeforeAll {
        function New-DatStream {
            param([int[]]$RomCounts)
            $sb = [System.Text.StringBuilder]::new()
            [void]$sb.Append('<?xml version="1.0"?><datafile>')
            for ($i = 0; $i -lt $RomCounts.Count; $i++) {
                [void]$sb.Append("<game name=`"Game$i`"><GameProfile>code$i</GameProfile><Executable>game$i.exe</Executable>")
                for ($r = 0; $r -lt $RomCounts[$i]; $r++) {
                    [void]$sb.Append("<rom name=`"file$r`" size=`"1`" crc=`"0`" />")
                }
                [void]$sb.Append('</game>')
            }
            [void]$sb.Append('</datafile>')
            return [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
        }
    }

    It "indexes every game regardless of how many <rom> entries precede its closing tag" {
        $stream = New-DatStream -RomCounts @(0, 1, 3, 2, 0)
        $index = Build-DatIndexFromStream -stream $stream
        $index.Count | Should -Be 5
        foreach ($i in 0..4) {
            $index["game$i"].ProfileCode | Should -Be "code$i"
            $index["game$i"].Executable  | Should -Be "game$i.exe"
        }
    }

    It "indexes a game with many <rom> entries followed by another game" {
        $stream = New-DatStream -RomCounts @(137, 4)
        $index = Build-DatIndexFromStream -stream $stream
        $index.Count | Should -Be 2
        $index["game0"].ProfileCode | Should -Be "code0"
        $index["game1"].ProfileCode | Should -Be "code1"
    }
}

Describe "Read-Xml" {
    It "loads a well-formed file successfully" {
        $path = Join-Path $TestDrive "good.xml"
        [System.IO.File]::WriteAllText($path, "<Root><Child>value</Child></Root>")
        $doc = Read-Xml $path
        $doc.Root.Child | Should -Be "value"
    }
    It "throws on a corrupt (non-well-formed) file rather than returning a partial document" {
        $path = Join-Path $TestDrive "corrupt.xml"
        [System.IO.File]::WriteAllText($path, "<Root><Unclosed>")
        { Read-Xml $path } | Should -Throw
    }
    It "throws on a missing file rather than returning null" {
        $path = Join-Path $TestDrive "doesnotexist.xml"
        { Read-Xml $path } | Should -Throw
    }
}

Describe "Get-NormalizedGameKey naming edge cases" {
    It "preserves digits, so sequel numbers stay distinct after normalization" {
        Get-NormalizedGameKey "VirtuaFighter4" | Should -Not -Be (Get-NormalizedGameKey "VirtuaFighter5")
    }
    It "known collision risk: bracketed tags are stripped entirely, so titles differing only by tag content normalize identically" {
        # Documents a real risk identified in the fuzzy-matching audit: a dat/folder-name
        # pair like "Game [Demo]" vs "Game [Arcade]" collapses to the same normalized key
        # because square-bracket metadata is removed wholesale, not inspected. This is
        # locked in as a characterization test (not asserted as "correct") so a future
        # change to this collision behavior is deliberate, not silent.
        $demo   = Get-NormalizedGameKey "Game [Demo]"
        $arcade = Get-NormalizedGameKey "Game [Arcade]"
        $demo | Should -Be $arcade
    }
    It "strips region codes but does not strip meaningful parenthesized names like (Special Edition)" {
        $withRegion = Get-NormalizedGameKey "Some Game (USA)"
        $plain      = Get-NormalizedGameKey "Some Game"
        $withRegion | Should -Be $plain

        Get-NormalizedGameKey "Some Game (Special Edition)" | Should -Not -Be $plain
    }
    It "normalizes Eggman-dat-style version/date suffixes to the same key as the bare title" {
        $full = Get-NormalizedGameKey "Cars (1.42)(2013-08-28)[Raw Thrills PC][TP]"
        $bare = Get-NormalizedGameKey "Cars"
        $full | Should -Be $bare
    }
}

Describe "Get-DiceSimilarity near-threshold / tie behavior" {
    # These document a real gap from the fuzzy-matching audit: Get-DiceSimilarity itself
    # has no concept of a threshold or a tie-break -- that logic lives in each caller's
    # "track the best score seen so far" loop (e.g. Register-Games ~line 4650-4668), which
    # only keeps a single best candidate and silently lets iteration order decide ties.
    # These tests pin down the scoring behavior the caller relies on, so a change to
    # Get-DiceSimilarity that quietly shifts near-threshold scores doesn't go unnoticed.
    It "can produce two distinct candidates scoring within a hair of each other, with no signal to prefer one" {
        $target = Get-NormalizedGameKey "NicktoonsNitro"
        $a = Get-DiceSimilarity $target (Get-NormalizedGameKey "NicktoonNitro")
        $b = Get-DiceSimilarity $target (Get-NormalizedGameKey "NicktoonsNitros")
        # Both are near-misses of the real title by one character; the function returns
        # a bare score for each with no indication of which (if either) is the real match.
        $a | Should -BeGreaterThan 0.85
        $b | Should -BeGreaterThan 0.85
        [Math]::Abs($a - $b) | Should -BeLessThan 0.1
    }
    It "a one-character difference near the auto-register threshold can land on either side of it" {
        # FuzzyAutoThreshold is 0.72 (TeknoParrot-Manager.ps1:582). A single transposed
        # or substituted character close to the threshold means whether a game gets
        # auto-registered or falls through to manual review is sensitive to exact spelling.
        $score = Get-DiceSimilarity (Get-NormalizedGameKey "InitialDArcadeStageZero") (Get-NormalizedGameKey "InitialDArcadeStageZer0")
        $score | Should -BeGreaterThan 0.6
        $score | Should -BeLessThan 1.0
    }
}

Describe "Resolve-BestFuzzyMatch" {
    # Fix for issue #15: the old inline loop in Register-Games had no tie-break --
    # whichever candidate scored highest (with ties broken purely by iteration order)
    # was trusted as an auto-register decision with no signal that a second candidate
    # was just as plausible. These tests cover the new top-2 tracking and tie margin.
    It "auto-trusts a clear winner with no close runner-up" {
        $matchList = @(
            [pscustomobject]@{ Code = "StreetFighterIII3rdStrike" }
            [pscustomobject]@{ Code = "MarioKartArcadeGP" }
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "StreetFighterIII3rdStrike") -MatchList $matchList -RawThrillsAliases @{}
        $result.Best.Code | Should -Be "StreetFighterIII3rdStrike"
        $result.IsConfidentMatch | Should -BeTrue
    }
    It "does not trust a match below the auto-register threshold" {
        $matchList = @(
            [pscustomobject]@{ Code = "CompletelyUnrelatedTitle" }
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "SomeOtherGame") -MatchList $matchList -RawThrillsAliases @{}
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "refuses to auto-trust an exact tie between two different candidates" {
        $matchList = @(
            [pscustomobject]@{ Code = "VirtuaFighter4" }
            [pscustomobject]@{ Code = "VirtuaFighter5" }
        )
        # A folder name equidistant from both candidates -- same score for each.
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "VirtuaFighter") -MatchList $matchList -RawThrillsAliases @{}
        $result.SecondScore | Should -Be $result.BestScore
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "refuses to auto-trust a near-tie even when the best score clears the threshold" {
        $matchList = @(
            [pscustomobject]@{ Code = "NicktoonNitro" }    # one char short of the real title
            [pscustomobject]@{ Code = "NicktoonsNitros" }  # one char long of the real title
        )
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "NicktoonsNitro") -MatchList $matchList -RawThrillsAliases @{}
        $result.BestScore | Should -BeGreaterThan $FuzzyAutoThreshold
        ($result.BestScore - $result.SecondScore) | Should -BeLessThan $FuzzyTieMargin
        $result.IsConfidentMatch | Should -BeFalse
    }
    It "still applies the RawThrillsAliases short-name fallback for a single unambiguous candidate" {
        $matchList = @( [pscustomobject]@{ Code = "NicktoonsNitro" } )
        $aliases   = @{ NicktoonsNitro = [pscustomobject]@{ Suggested = "NTN" } }
        $result = Resolve-BestFuzzyMatch -NormFolder (Get-NormalizedGameKey "NTN") -MatchList $matchList -RawThrillsAliases $aliases
        $result.Best.Code | Should -Be "NicktoonsNitro"
        $result.IsConfidentMatch | Should -BeTrue
    }
}

Describe "New-PostgresPgPassFile / Remove-PostgresPgPassFile" {
    # Issue #3 (v1.0 roadmap): migrated Postgres credential passing from
    # $env:PGPASSWORD to a temporary .pgpass-format file, so the password is
    # never visible in psql.exe/etc.'s own process environment block. These
    # tests cover the file format (libpq's documented
    # hostname:port:database:username:password syntax) and escaping rules,
    # plus cleanup -- not the icacls lockdown, which is best-effort hardening
    # on top and not load-bearing for correctness.
    It "writes a single line in the documented hostname:port:database:username:password format" {
        $path = New-PostgresPgPassFile -Password "hunter2"
        try {
            (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be "127.0.0.1:5432:*:postgres:hunter2"
        } finally {
            Remove-PostgresPgPassFile -Path $path
        }
    }
    It "escapes a backslash and a colon in the password per the pgpass format" {
        $path = New-PostgresPgPassFile -Password 'p:a\ss'
        try {
            (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be '127.0.0.1:5432:*:postgres:p\:a\\ss'
        } finally {
            Remove-PostgresPgPassFile -Path $path
        }
    }
    It "creates a real file that Remove-PostgresPgPassFile then deletes" {
        $path = New-PostgresPgPassFile -Password "anything"
        Test-Path -LiteralPath $path | Should -BeTrue
        Remove-PostgresPgPassFile -Path $path
        Test-Path -LiteralPath $path | Should -BeFalse
    }
    It "does not throw when asked to remove a path that doesn't exist" {
        $missing = Join-Path $TestDrive "does-not-exist.conf"
        { Remove-PostgresPgPassFile -Path $missing } | Should -Not -Throw
    }
    It "does not throw when asked to remove a null/empty path" {
        { Remove-PostgresPgPassFile -Path $null } | Should -Not -Throw
        { Remove-PostgresPgPassFile -Path "" } | Should -Not -Throw
    }
}

Describe "Read-PathWithBrowse" {
    # This is UI code (it can launch a real WinForms file/folder picker), which
    # is outside this project's stated Pester scope the same way other menu/UI
    # code already is -- these tests only cover the manual-entry passthrough
    # (mocking Read-Host, the one real cmdlet involved), never the actual
    # dialog-showing branch, which has no practical way to assert against in an
    # automated run without clicking through a real modal window.
    It "returns whatever was typed, unchanged, when the user does not type B" {
        Mock Read-Host { "C:\Some\Typed\Path" }
        Read-PathWithBrowse "Enter a path" | Should -Be "C:\Some\Typed\Path"
    }
    It "is case-insensitive when checking for the browse trigger (only 'b'/'B' triggers it, not a path that happens to start with B)" {
        Mock Read-Host { "B:\SomeDrive" }
        # A typed path literally starting with the letter B must NOT be misread as
        # the browse trigger -- only an exact "B" (after Trim) should be.
        Read-PathWithBrowse "Enter a path" | Should -Be "B:\SomeDrive"
    }
    It "returns an empty string passthrough when the user presses Enter with nothing typed" {
        Mock Read-Host { "" }
        Read-PathWithBrowse "Enter a path" | Should -Be ""
    }
}

Describe "Get-ReShadeLatestVersion retry behavior" {
    BeforeAll {
        Mock Invoke-WebRequest {}
    }

    It "makes only a single attempt and returns null on failure -- no retry, unlike the Eggman/FFB/BepInEx fetchers" {
        Mock Invoke-WebRequest { throw "site unreachable" }
        $result = Get-ReShadeLatestVersion
        $result | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
    }
    It "parses the version out of a successful response" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = "...ReShade_Setup_6.7.3.exe..." } }
        Get-ReShadeLatestVersion | Should -Be "6.7.3"
    }
}

Describe "Invoke-EggmanDatDownload retry and partial-file cleanup" {
    BeforeAll {
        Mock Get-Service { $null }   # BITS unavailable -> exercises the Invoke-WebRequest fallback path
        Mock Start-Sleep {}
        Mock Write-Log {}
    }
    BeforeEach {
        $script:attemptCount = 0
    }

    It "retries a transient failure and succeeds on a later attempt" {
        Mock Invoke-WebRequest {
            $script:attemptCount++
            if ($script:attemptCount -lt 2) { throw "transient network error" }
            Set-Content -LiteralPath $OutFile -Value "fake zip content"
        }
        $savePath = Join-Path $TestDrive "retry-success.zip"

        $result = Invoke-EggmanDatDownload "https://example.com/file.zip" $savePath

        $result | Should -BeTrue
        $script:attemptCount | Should -Be 2
        Test-Path -LiteralPath $savePath | Should -BeTrue
    }
    It "deletes any partial file and returns false once all retry attempts are exhausted" {
        Mock Invoke-WebRequest { throw "still failing" }
        $savePath = Join-Path $TestDrive "retry-exhausted.zip"
        # Simulate a partial file left behind by a prior failed attempt.
        Set-Content -LiteralPath $savePath -Value "partial garbage"

        $result = Invoke-EggmanDatDownload "https://example.com/file.zip" $savePath

        $result | Should -BeFalse
        Test-Path -LiteralPath $savePath | Should -BeFalse
        Should -Invoke Invoke-WebRequest -Times 3
    }
}

Describe "Test-ButtonNameDirectional" {
    # Pure up/down/left/right labels (with various player-prefix formats) are directional.
    It "classifies plain 'Up' as directional" {
        Test-ButtonNameDirectional "Up" | Should -BeTrue
    }
    It "classifies 'Player 1 Up' as directional" {
        Test-ButtonNameDirectional "Player 1 Up" | Should -BeTrue
    }
    It "classifies 'P1 UP' as directional (case-insensitive, P1 prefix)" {
        Test-ButtonNameDirectional "P1 UP" | Should -BeTrue
    }
    It "classifies 'Player 2 Down' as directional" {
        Test-ButtonNameDirectional "Player 2 Down" | Should -BeTrue
    }
    It "classifies diagonal 'Up Right' as directional" {
        Test-ButtonNameDirectional "Up Right" | Should -BeTrue
    }

    # Names that contain direction words but also have non-direction qualifiers are NOT directional.
    It "classifies 'Player 1 Left Punch' as NOT directional (attack qualifier)" {
        Test-ButtonNameDirectional "Player 1 Left Punch" | Should -BeFalse
    }
    It "classifies 'Player 1 Right Kick' as NOT directional (attack qualifier)" {
        Test-ButtonNameDirectional "Player 1 Right Kick" | Should -BeFalse
    }
    It "classifies 'Player 1 Left Shoulder' as NOT directional (non-direction qualifier)" {
        Test-ButtonNameDirectional "Player 1 Left Shoulder" | Should -BeFalse
    }

    # Pure attack/action labels with no direction words are NOT directional.
    It "classifies 'Player 1 LP' as NOT directional" {
        Test-ButtonNameDirectional "Player 1 LP" | Should -BeFalse
    }
    It "classifies 'P1 ATTACK' as NOT directional" {
        Test-ButtonNameDirectional "P1 ATTACK" | Should -BeFalse
    }
    It "classifies empty string as NOT directional" {
        Test-ButtonNameDirectional "" | Should -BeFalse
    }
}
