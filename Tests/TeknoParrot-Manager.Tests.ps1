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

    # Same situation for the FFB Blaster gating (issue #41) and schema-drift
    # (issue #43) constants -- they are top-level script-scope variables in
    # the production script, not function bodies, so the AST extraction above
    # never picks them up. Get-FFBBlasterSupport reads the first two directly,
    # and Get-GameProfileSchemaDrift uses the rest as parameter defaults
    # (which evaluate to $null in test scope without these). Mirror the
    # production values explicitly.
    $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
    $script:FFBBlasterNamePattern          = 'ffb.*blaster|blaster.*ffb'
    $script:KnownGameProfileTopLevel = @(
        'GamePath','GamePath2','TestMenuParameter','TestMenuIsExecutable',
        'ExtraParameters','TestMenuExtraParameters','EmulationProfile',
        'GameProfileRevision','HasSeparateTestMode','ExecutableName',
        'ExecutableName2','HasTwoExecutables','LaunchSecondExecutableFirst',
        'HasTpoSupport','EmulatorType','Is64Bit','ValidMd5','ConfigValues',
        'GameName','GameGenreInternal','IconName','HasModeForSquare',
        'RequiresAdmin','InvokeFullscreenOnStartup','LaunchedFromUsb',
        'CamberWindowState'
    )
    $script:RequiredGameProfileTopLevel = @('EmulationProfile','ConfigValues')
    $script:KnownFieldTypes = @('Bool','Dropdown','Text','Slider')
    $script:InputConfigFields = @()

    # The production script loads System.IO.Compression.FileSystem at startup
    # (top-level code, line ~82 -- not in a function body, so AST extraction
    # above never captures it). Expand-ZipFileSafe uses ZipFile (from
    # System.IO.Compression.FileSystem.dll). New-TestZip uses ZipArchive (from
    # System.IO.Compression.dll -- a separate assembly). Both are loaded in
    # the Describe "Expand-ZipFileSafe" BeforeAll below.
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # $ScriptVersion is a top-level script-scope constant (not a function
    # body), so the AST extraction above never picks it up. Get-ManagerUpdateRelease
    # and Invoke-CheckForUpdates read it directly (User-Agent header, current-version
    # display/comparison) -- mirror the production value explicitly. Deliberately
    # not hardcoded to match TeknoParrot-Manager.ps1's own version exactly; tests
    # below use their own controlled version strings/mocks instead of relying on
    # this value's specific number, so drift here would not silently break them.
    $ScriptVersion = "0.99.39"
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
        # ZipArchive is in System.IO.Compression.dll; ZipFile is in the separate
        # System.IO.Compression.FileSystem.dll. Load both explicitly because the
        # production script's Add-Type (top-level, not in a function body) is
        # never captured by the AST extraction above.
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem

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

Describe "Resolve-ExtractedGameFolder (issue #66 extraction prompt correctness)" {
    BeforeAll {
        $script:OriginalRawThrillsPathLimits = $script:RawThrillsPathLimits
    }

    BeforeEach {
        $script:installRoot = Join-Path $TestDrive "Games"
        Remove-Item -LiteralPath $script:installRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $script:installRoot -Force | Out-Null
        $script:RawThrillsPathLimits = @{
            AliensArmageddon = @{ Limit = 96; Suggested = 'ALIENS' }
        }
    }

    AfterEach {
        $script:RawThrillsPathLimits = $script:OriginalRawThrillsPathLimits
    }

    It "recognizes a RetroBat-suffixed Raw Thrills short-name folder for Aliens Armageddon" {
        $existing = Join-Path $script:installRoot "ALIENS.teknoparrot"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.exe") -Value "content"
        $zipName = "Aliens Armageddon (1.04)(2014-11-17)[Raw Thrills PC][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "AliensArmageddon"
                Executable  = "game.exe"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex | Should -Be $existing
    }

    It "matches Battle Gear 3 despite harmless DAT year/date metadata differences" {
        $existingName = "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        $existing = Join-Path $script:installRoot $existingName
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "game.elf") -Value "content"
        $zipName = "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]"
        $datIndex = @{
            (Get-NormalizedGameKey $zipName) = [pscustomobject]@{
                ProfileCode = "BattleGear3"
                Executable  = "game.elf"
            }
        }

        Resolve-ExtractedGameFolder -RawZipName $zipName -InstallFolder $script:installRoot -DatIndex $datIndex | Should -Be $existing
    }

    It "does not confuse similarly named sequels" {
        $existing = Join-Path $script:installRoot "Virtua Fighter 4"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existing "vf4.exe") -Value "content"

        Resolve-ExtractedGameFolder -RawZipName "Virtua Fighter 5" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
    }

    It "does not treat an empty matching folder as already extracted" {
        $existing = Join-Path $script:installRoot "Battle Gear 3 (2.08J)(2003-04-11)[Namco System 246][TP]"
        New-Item -ItemType Directory -Path $existing -Force | Out-Null

        Resolve-ExtractedGameFolder -RawZipName "Battle Gear 3 (2.08J)(2002)[Namco System 246][TP]" -InstallFolder $script:installRoot | Should -BeNullOrEmpty
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

Describe "Invoke-ControlPropagation duplicate-key handling (issue #53)" {
    BeforeAll {
        function New-ControlProfileXml {
            param(
                [string]$Name,
                [string]$Buttons
            )

            return @"
<GameProfile>
  <GameName>$Name</GameName>
  <JoystickButtons>
$Buttons
  </JoystickButtons>
  <ConfigValues />
</GameProfile>
"@
        }

        function New-WheelButtonXml {
            param(
                [string]$Name,
                [string]$Mapping = 'P1Wheel',
                [switch]$Bound
            )

            $binding = if ($Bound) {
                @"
      <RawInputButton>
        <DevicePath>test-wheel</DevicePath>
        <ButtonName>X+</ButtonName>
      </RawInputButton>
"@
            } else {
                ''
            }

            return @"
    <JoystickButtons>
      <ButtonName>$Name</ButtonName>
      <InputMapping>$Mapping</InputMapping>
      <AnalogType>Wheel</AnalogType>
$binding
    </JoystickButtons>
"@
        }
    }

    It "uses an archetype match key only once per target profile" {
        $profiles = Join-Path $TestDrive 'UserProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null

        $archetypeButtons = @(
            New-WheelButtonXml -Name 'Wheel Right' -Bound
            New-WheelButtonXml -Name 'Gas' -Mapping 'P1Gas' -Bound
            New-WheelButtonXml -Name 'Brake' -Mapping 'P1Brake' -Bound
        ) -join "`n"
        New-ControlProfileXml -Name 'Reference Driver' -Buttons $archetypeButtons |
            Set-Content -LiteralPath (Join-Path $profiles 'ReferenceDriver.xml') -Encoding UTF8

        $targetButtons = @(
            New-WheelButtonXml -Name 'Wheel Left'
            New-WheelButtonXml -Name 'Wheel Right'
        ) -join "`n"
        New-ControlProfileXml -Name 'Duplicate Wheel Target' -Buttons $targetButtons |
            Set-Content -LiteralPath (Join-Path $profiles 'DuplicateWheelTarget.xml') -Encoding UTF8

        $pool = Build-ArchetypePool $profiles 3
        $reports = Invoke-ControlPropagation -userProfilesDir $profiles -pool $pool -minBound 3 -DryRun:$false
        [xml]$updated = Get-Content -LiteralPath (Join-Path $profiles 'DuplicateWheelTarget.xml') -Raw
        $targetSlots = @($updated.SelectNodes('/GameProfile/JoystickButtons/JoystickButtons'))
        $boundSlots = @($targetSlots | Where-Object { Test-ButtonIsBound $_ })
        $manualReport = @($reports | Where-Object { $_.Code -eq 'DuplicateWheelTarget' } | Select-Object -First 1)

        $boundSlots.Count | Should -Be 1
        $manualReport.Status | Should -Be 'bound'
        $manualReport.Manual | Should -Contain 'Wheel Right'
    }
}

Describe "Write-ControlPropagationResults (issue #59: standalone Propagate Controls)" {
    # This function is the shared reporting step behind both the AutoSync/
    # Register-only flow and the standalone "Propagate Controls" menu option
    # (issue #59) -- the same $reports shape Invoke-ControlPropagation always
    # returns, in, count out. Exercising it directly protects both call sites
    # from drifting out of sync with each other.
    It "counts bound/api-fixed/api-fixed-canonical as updated and returns the no-archetype subset" {
        $reports = @(
            [pscustomobject]@{ Code = 'GameA'; Status = 'bound'; Family = 'driving'; Archetype = 'RefDriver'; Bound = 3; Manual = @(); ConfigCarried = @(); ApiSet = $true; ArchetypeApi = 'RawInput'; Forced = $false; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameB'; Status = 'api-fixed'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameC'; Status = 'api-fixed-canonical'; ArchetypeApi = 'RawInput'; Archetype = 'RefDriver'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameD'; Status = 'no-archetype'; Family = 'lightgun'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameE'; Status = 'skipped-bound'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameF'; Status = 'skipped-override'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameG'; Status = 'save-failed'; Archetype = 'RefDriver'; MismatchSlots = $null }
        )

        $result = Write-ControlPropagationResults -Reports $reports

        $result.BoundCount | Should -Be 3
        $result.NoArchetypeItems.Count | Should -Be 1
        $result.NoArchetypeItems[0].Code | Should -Be 'GameD'
    }

    It "returns zero updated and an empty no-archetype list for an all-skipped report set" {
        $reports = @(
            [pscustomobject]@{ Code = 'GameH'; Status = 'skipped-bound'; MismatchSlots = $null }
            [pscustomobject]@{ Code = 'GameI'; Status = 'skipped-override'; MismatchSlots = $null }
        )

        $result = Write-ControlPropagationResults -Reports $reports

        $result.BoundCount | Should -Be 0
        $result.NoArchetypeItems.Count | Should -Be 0
    }
}

Describe "New-PropagationBackup (P1 fix: standalone Propagate Controls must abort on incomplete backup)" {
    # Independent engineering review finding on PR #62: a backup-copy error in the standalone
    # Propagate Controls menu option only warned and allowed the caller to
    # continue -- including automatically in -Unattended mode -- so
    # Invoke-ControlPropagation could run against an incomplete backup. This
    # directly proves the gating condition every caller relies on: ErrorCount
    # is greater than zero whenever any source file could not be copied, with
    # no path that reports success/zero on a partial failure.
    It "reports zero errors and the correct path when every file copies successfully" {
        $profiles = Join-Path $TestDrive ("propback-ok-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profiles 'Game.xml') -Value '<GameProfile/>' -Encoding UTF8

        $result = New-PropagationBackup -UserProfilesDir $profiles

        $result.ErrorCount | Should -Be 0
        Test-Path -LiteralPath (Join-Path $result.Path 'Game.xml') | Should -BeTrue
    }

    It "signals an abort-worthy failure when a source file is locked and cannot be copied" {
        # A sharing-violation on Copy-Item can surface either as a
        # non-terminating error (caught into ErrorCount via -ErrorAction
        # SilentlyContinue) or, depending on exactly how the underlying I/O
        # call fails, as a terminating exception that -ErrorAction alone
        # does not suppress. Both are safe: the real caller in the
        # "PropagateControls" menu block wraps this call in try/catch AND
        # checks ErrorCount, so either outcome correctly prevents
        # Invoke-ControlPropagation from running. This test accepts either,
        # since the point is proving no path silently reports success.
        $profiles = Join-Path $TestDrive ("propback-locked-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        $lockedPath = Join-Path $profiles 'Locked.xml'
        Set-Content -LiteralPath $lockedPath -Value '<GameProfile/>' -Encoding UTF8

        $handle = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $threw = $false
            $result = $null
            try {
                $result = New-PropagationBackup -UserProfilesDir $profiles
            } catch {
                $threw = $true
            }
            ($threw -or $result.ErrorCount -gt 0) | Should -BeTrue
        } finally {
            $handle.Dispose()
        }
    }
}

# =============================================================================
# COMPATIBILITY REGRESSION SUITE (issues #41 / #43 / #46)
# These contexts protect the compatibility-sensitive setup decisions against
# upstream TeknoParrot schema/platform drift. The cardinal invariant under
# test throughout: an unsupported or unknown outcome must report WouldWrite =
# $false, i.e. never causes the setup flow to write a profile.
# =============================================================================

Describe "Get-FFBBlasterSupport (issue #41 capability gating)" {
    BeforeAll {
        # Builds a full <GameProfile> with an EmulationProfile and arbitrary
        # ConfigValues inner XML, so the platform deny-list and field gate are
        # both exercised the way the real per-profile loop sees them.
        function New-FfbProfileDoc {
            param([string]$Platform, [string]$Inner)
            return [xml]"<GameProfile><EmulationProfile>$Platform</EmulationProfile><ConfigValues>$Inner</ConfigValues></GameProfile>"
        }
        $script:FfbField = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
    }

    It "Supported: a profile with an FFB Blaster Bool field is offered setup and WouldWrite when not yet enabled" {
        $doc = New-FfbProfileDoc -Platform "EuropaRFordRacing" -Inner $script:FfbField
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Supported'
        $r.WouldWrite | Should -BeTrue
        $r.Changes[0].NewValue | Should -Be '1'
    }
    It "Supported but no write needed: an already-enabled field reports WouldWrite=false" {
        $inner = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "Daytona3" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Supported'
        $r.UpToDate   | Should -BeTrue
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (no field): a profile without an FFB Blaster field is skipped and never written" {
        $inner = "<FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>0</FieldValue></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "EuropaRFordRacing" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (PCSX2x6): a pcsx2x6 profile is skipped EVEN when an FFB Blaster field is present" {
        # Deny-list must win over field presence -- this is the core safety
        # property: a future upstream field on an unsupported platform must
        # never trigger a write.
        $doc = New-FfbProfileDoc -Platform "pcsx2x6" -Inner $script:FfbField
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
        $r.Reason     | Should -Match 'pcsx2x6'
    }
    It "Unsupported (PCSX2x6 via EmulatorType fallback): deny-list also matches when only EmulatorType carries the platform" {
        $doc = [xml]"<GameProfile><EmulatorType>pcsx2x6</EmulatorType><ConfigValues>$script:FfbField</ConfigValues></GameProfile>"
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
    It "Unsupported (PCSX2x6 case-insensitive): 'PCSX2X6' is matched regardless of case" {
        $doc = New-FfbProfileDoc -Platform "PCSX2X6" -Inner $script:FfbField
        (Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')).Status | Should -Be 'Unsupported'
    }
    It "Unknown: an FFB Blaster-shaped field that is NOT a writable Bool is flagged for review, never written" {
        # FieldType is Dropdown, not Bool -> schema drift -> Unknown, no write.
        $inner = "<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Mode</FieldName><FieldType>Dropdown</FieldType><FieldValue>Off</FieldValue><FieldOptions><string>Off</string><string>On</string></FieldOptions></FieldInformation>"
        $doc = New-FfbProfileDoc -Platform "Daytona3" -Inner $inner
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')
        $r.Status     | Should -Be 'Unknown'
        $r.WouldWrite | Should -BeFalse
    }
    It "paid-membership confirmation alone does not make an unsupported profile writable (gate is structural, not membership-based)" {
        # The function takes no membership flag -- membership is asked once at
        # the top of Invoke-FFBBlasterSetup and never feeds this decision. A
        # pcsx2x6 profile is Unsupported no matter what the user answered.
        $doc = New-FfbProfileDoc -Platform "pcsx2x6" -Inner $script:FfbField
        (Get-FFBBlasterSupport -Doc $doc -Categories @('FFB Blaster')).WouldWrite | Should -BeFalse
    }
}

Describe "Get-FFBBlasterFieldNames drift vs absent distinction (issue #41 diagnostic improvement)" {
    # Get-FFBBlasterFieldNames returns only Bool fields -- by design. When it
    # returns empty the caller must distinguish schema drift (shaped non-Bool
    # field exists) from genuine absence (no FFB-Blaster-shaped field at all).
    # This Describe exercises the pure detection helper rather than the setup
    # flow (which involves I/O on a GameProfiles directory).
    BeforeAll {
        function New-GpFieldDoc {
            param([string]$FieldType)
            return [xml]"<GameProfile><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>$FieldType</FieldType><FieldValue>0</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        }
    }
    It "Get-FFBBlasterFieldNames returns a non-empty set when the field is Bool" {
        $doc = New-GpFieldDoc "Bool"
        # Categories are discovered from GameProfile XML at runtime; here we
        # validate that a Bool field would be discovered (so Get-FFBBlasterSupport
        # later gets a valid Categories list and reaches the Supported branch).
        $doc.SelectNodes("/GameProfile/ConfigValues/FieldInformation") |
            Where-Object { $_.FieldType -ieq 'Bool' -and
                           ($_.CategoryName -imatch $script:FFBBlasterNamePattern -or
                            $_.FieldName    -imatch $script:FFBBlasterNamePattern) } |
            Should -Not -BeNullOrEmpty
    }
    It "Get-FFBBlasterSupport returns Unknown (not Unsupported) when the only shaped field is non-Bool (upstream schema drift)" {
        # This is the critical distinction: if ALL shaped fields changed FieldType
        # upstream, Get-FFBBlasterFieldNames returns empty (no Bool fields to
        # discover). At the per-profile level, Get-FFBBlasterSupport still sees the
        # shaped-but-wrong-type field and correctly returns Unknown, not Unsupported.
        $doc = [xml]"<GameProfile><EmulationProfile>Daytona3</EmulationProfile><ConfigValues><FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldType>Dropdown</FieldType><FieldValue>Off</FieldValue><FieldOptions><string>Off</string><string>On</string></FieldOptions></FieldInformation></ConfigValues></GameProfile>"
        # Pass empty categories (as Get-FFBBlasterFieldNames would return after drift)
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @()
        $r.Status     | Should -Be 'Unknown'
        $r.WouldWrite | Should -BeFalse
    }
    It "Get-FFBBlasterSupport returns Unsupported (not Unknown) when no shaped field exists at all" {
        $doc = [xml]"<GameProfile><EmulationProfile>Daytona3</EmulationProfile><ConfigValues><FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation></ConfigValues></GameProfile>"
        $r = Get-FFBBlasterSupport -Doc $doc -Categories @()
        $r.Status     | Should -Be 'Unsupported'
        $r.WouldWrite | Should -BeFalse
    }
}

Describe "Get-GameProfileSchemaDrift (issue #43 schema drift detection)" {
    BeforeAll {
        function New-DriftDoc { param([string]$Xml) return [xml]$Xml }
        $script:GoodProfile = @"
<GameProfile>
  <EmulationProfile>EuropaRFordRacing</EmulationProfile>
  <GameProfileRevision>22</GameProfileRevision>
  <ExecutableName>fordracing.exe</ExecutableName>
  <EmulatorType>TeknoParrot</EmulatorType>
  <ConfigValues>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>
    <FieldInformation><CategoryName>General</CategoryName><FieldName>Input API</FieldName><FieldType>Dropdown</FieldType><FieldValue>DirectInput</FieldValue></FieldInformation>
  </ConfigValues>
</GameProfile>
"@
    }

    It "reports no drift for a known, well-formed profile" {
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $script:GoodProfile)
        $r.HasDrift          | Should -BeFalse
        $r.UnknownNodes.Count    | Should -Be 0
        $r.MissingRequired.Count | Should -Be 0
        $r.WouldWrite        | Should -BeFalse
    }
    It "tolerates a known optional node (GamePath2) without flagging drift" {
        $xml = $script:GoodProfile -replace '</ConfigValues>', '</ConfigValues><GamePath2>C:\game\amdaemon.exe</GamePath2>'
        (Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)).HasDrift | Should -BeFalse
    }
    It "reports an unknown NEW top-level node but never proposes a write" {
        # Simulates an upstream addition like a CXBXR/Lindbergh-ELF2 marker.
        $xml = $script:GoodProfile -replace '</ConfigValues>', '</ConfigValues><Cxbxr_SomeNewMarker>true</Cxbxr_SomeNewMarker>'
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift     | Should -BeTrue
        $r.UnknownNodes | Should -Contain 'Cxbxr_SomeNewMarker'
        $r.WouldWrite   | Should -BeFalse
    }
    It "reports a removed REQUIRED node as drift" {
        $xml = $script:GoodProfile -replace '<EmulationProfile>EuropaRFordRacing</EmulationProfile>', ''
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift         | Should -BeTrue
        $r.MissingRequired  | Should -Contain 'EmulationProfile'
    }
    It "reports an unknown FieldType as drift but never proposes a write" {
        $xml = $script:GoodProfile -replace '<FieldType>Bool</FieldType>', '<FieldType>FutureRangeSliderV2</FieldType>'
        $r = Get-GameProfileSchemaDrift -Doc (New-DriftDoc $xml)
        $r.HasDrift           | Should -BeTrue
        $r.UnknownFieldTypes  | Should -Contain 'FutureRangeSliderV2'
        $r.WouldWrite         | Should -BeFalse
    }
    It "treats a missing <GameProfile> root as maximal drift, never a write" {
        $r = Get-GameProfileSchemaDrift -Doc ([xml]"<NotAGameProfile><Foo/></NotAGameProfile>")
        $r.HasRoot    | Should -BeFalse
        $r.HasDrift   | Should -BeTrue
        $r.WouldWrite | Should -BeFalse
    }
}

Describe "Third-party FFB plugin destination safety (issue #46)" {
    # The plugin flow resolves a destination DLL filename from the live
    # AutoSetup.cmd table (untrusted) and guards it with Test-PathInside
    # before any copy. These assert that guard's contract directly.
    It "accepts a destination DLL inside the game's own folder" {
        Test-PathInside (Join-Path "C:\Games\MyGame" "d3d9.dll") "C:\Games\MyGame" | Should -BeTrue
    }
    It "rejects a traversal destination that escapes the game folder" {
        Test-PathInside (Join-Path "C:\Games\MyGame" "..\..\Windows\System32\evil.dll") "C:\Games\MyGame" | Should -BeFalse
    }
    It "rejects a sibling folder that only shares a name prefix" {
        Test-PathInside "C:\Games\MyGameOther\x.dll" "C:\Games\MyGame" | Should -BeFalse
    }
}

Describe "RawInput / RawInputTrackball field handling (issue #46)" {
    BeforeAll {
        function New-Btn { param([string]$Inner) return ([xml]"<JoystickButtons>$Inner</JoystickButtons>").JoystickButtons }
    }
    It "treats a present RawInputButton binding as bound (supported field present)" {
        Test-ButtonIsBound (New-Btn "<RawInputButton>MOUSE_LEFT</RawInputButton>") | Should -BeTrue
    }
    It "treats a button with no binding field as not bound (field absent)" {
        Test-ButtonIsBound (New-Btn "<InputMapping>P1Trackball</InputMapping>") | Should -BeFalse
    }
    It "does NOT treat an unknown future binding field as bound (unknown field is not acted on)" {
        # A hypothetical future field name must not be mistaken for a real
        # binding -- the safe default is 'not bound', matching the project's
        # 'unknown fields are never acted on' rule.
        Test-ButtonIsBound (New-Btn "<RawInputTrackballButtonV2>MOUSE_X</RawInputTrackballButtonV2>") | Should -BeFalse
    }
}

Describe "GPU fix vendor matrix + safe re-run (issue #46)" {
    BeforeAll {
        function New-GpuDoc {
            param([string]$Inner)
            return [xml]"<GameProfile><ConfigValues>$Inner</ConfigValues></GameProfile>"
        }
        $script:GpuDropdown = "<FieldInformation><FieldName>GPU Fix</FieldName><FieldType>Dropdown</FieldType><FieldValue>None</FieldValue><FieldOptions><string>None</string><string>NVIDIA</string><string>AMD</string><string>INTEL</string></FieldOptions></FieldInformation>"
    }
    It "AMD: selects the AMD dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD'
        $r.Eligible | Should -BeTrue
        $r.Changes[0].NewValue | Should -Be 'AMD'
    }
    It "NVIDIA: selects the NVIDIA dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $r.Changes[0].NewValue | Should -Be 'NVIDIA'
    }
    It "Intel: selects the INTEL dropdown option" {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $script:GpuDropdown) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'Intel'
        $r.Changes[0].NewValue | Should -Be 'INTEL'
    }
    It "safe re-run after a GPU change: an already-correct value is up to date and needs no write" {
        $inner = "<FieldInformation><FieldName>GPU Fix</FieldName><FieldType>Dropdown</FieldType><FieldValue>NVIDIA</FieldValue><FieldOptions><string>None</string><string>NVIDIA</string><string>AMD</string><string>INTEL</string></FieldOptions></FieldInformation>"
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc $inner) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'NVIDIA'
        $r.UpToDate | Should -BeTrue
        $r.Changes.Count | Should -Be 0
    }
    It "not eligible (no GPU field) means nothing to write" {
        $inner = "<FieldInformation><FieldName>Windowed</FieldName><FieldType>Bool</FieldType><FieldValue>1</FieldValue></FieldInformation>"
        (Test-GpuFixUpToDate -Doc (New-GpuDoc $inner) -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'AMD').Eligible | Should -BeFalse
    }
}

Describe "ConvertTo-ManagerComparableVersion" {
    It "strips a leading v and parses a normal version" {
        ConvertTo-ManagerComparableVersion -VersionText 'v0.99.39' | Should -Be ([version]'0.99.39')
    }
    It "parses a version with no leading v" {
        ConvertTo-ManagerComparableVersion -VersionText '0.99.39' | Should -Be ([version]'0.99.39')
    }
    It "throws on a non-numeric version string" {
        { ConvertTo-ManagerComparableVersion -VersionText 'latest' } | Should -Throw
    }
}

Describe "Get-ManagerUpdateRelease" {
    It "returns the matching asset for a well-formed release" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{
                        name                  = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                        browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
                    })
                } | ConvertTo-Json -Depth 5)
            }
        }
        $release = Get-ManagerUpdateRelease
        $release.TagName | Should -Be 'v0.99.99'
        $release.AssetName | Should -Be 'TeknoParrot.Manager.v0.99.99.BETA.zip'
    }

    It "returns null when no asset matches the expected name pattern" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{ name = 'unrelated.txt'; browser_download_url = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/unrelated.txt' })
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
    }

    It "returns null and does not retry when the matching asset URL is not a real GitHub release URL" {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                Content = (@{
                    tag_name = 'v0.99.99'
                    assets   = @(@{ name = 'TeknoParrot.Manager.v0.99.99.BETA.zip'; browser_download_url = 'https://evil.example.com/TeknoParrot.Manager.v0.99.99.BETA.zip' })
                } | ConvertTo-Json -Depth 5)
            }
        }
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
    }

    It "retries on a transient (5xx-shaped) failure and gives up after 3 attempts" {
        Mock Invoke-WebRequest { throw [System.Net.WebException]::new('transient') }
        Mock Start-Sleep {}
        Get-ManagerUpdateRelease | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 3
        Should -Invoke Start-Sleep -Times 2
    }
}

Describe "Assert-ManagerUpdateTargetWritable" {
    It "throws a clear, actionable error when the target is read-only" {
        $path = Join-Path $TestDrive 'readonly.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.39"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            { Assert-ManagerUpdateTargetWritable -Path $path } | Should -Throw '*read-only*'
            { Assert-ManagerUpdateTargetWritable -Path $path } | Should -Throw "*$path*"
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
    It "does not throw when the target is writable" {
        $path = Join-Path $TestDrive 'writable.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.39"' -Encoding ascii
        { Assert-ManagerUpdateTargetWritable -Path $path } | Should -Not -Throw
    }
    It "does not throw when the target does not exist yet" {
        { Assert-ManagerUpdateTargetWritable -Path (Join-Path $TestDrive 'does-not-exist.ps1') } | Should -Not -Throw
    }
}

Describe "New-ManagerUpdateBackup" {
    It "creates a timestamped backup of the target file under UpdateBackups" {
        $root = Join-Path $TestDrive ("backuproot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $scriptPath = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $scriptPath -Value '$ScriptVersion = "0.99.39"' -Encoding ascii

        $backupPath = New-ManagerUpdateBackup -Path $scriptPath

        $backupPath | Should -Match ([regex]::Escape((Join-Path $root 'UpdateBackups')))
        Test-Path -LiteralPath $backupPath -PathType Leaf | Should -BeTrue
        (Get-Content -LiteralPath $backupPath -Raw) | Should -Match 'ScriptVersion'
    }
}

Describe "Expand-ManagerUpdateAsset and Test-ManagerUpdateExtractedScript" {
    BeforeAll {
        function New-CheckForUpdatesFixtureZip {
            param(
                [string]$EntryName = 'TeknoParrot-Manager.ps1',
                [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
            )
            $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-fixture-" + [guid]::NewGuid().ToString('N') + '.zip')
            $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-staging-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $stagingDir $EntryName) -Value $EntryContent -Encoding ascii -NoNewline
                [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
            } finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $zipPath
        }
    }

    It "extracts the named entry and it passes content validation" {
        $zipPath = New-CheckForUpdatesFixtureZip
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            Expand-ManagerUpdateAsset -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath
            Test-ManagerUpdateExtractedScript -Path $destPath | Should -BeTrue
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $destPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "throws when the zip does not contain the expected entry" {
        $zipPath = New-CheckForUpdatesFixtureZip -EntryName 'SomethingElse.ps1'
        $destPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-menu-extracted-" + [guid]::NewGuid().ToString('N') + '.ps1')
        try {
            { Expand-ManagerUpdateAsset -ZipPath $zipPath -EntryName 'TeknoParrot-Manager.ps1' -DestinationPath $destPath } | Should -Throw
        } finally {
            Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        }
    }

    It "rejects an extracted file that begins with a raw zip (PK) signature" {
        $path = Join-Path $TestDrive 'zipbytes.ps1'
        [System.IO.File]::WriteAllBytes($path, [byte[]](0x50, 0x4B, 0x03, 0x04, 0x00, 0x00))
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*zip signature*'
    }

    It "rejects an extracted file missing the TeknoParrot Manager marker" {
        $path = Join-Path $TestDrive 'nomarker.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.99.99"' -Encoding ascii
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*TeknoParrot Manager*'
    }

    It "rejects an extracted file with no ScriptVersion assignment" {
        $path = Join-Path $TestDrive 'noversion.ps1'
        Set-Content -LiteralPath $path -Value '# TeknoParrot Manager' -Encoding ascii
        { Test-ManagerUpdateExtractedScript -Path $path } | Should -Throw '*ScriptVersion*'
    }
}

Describe "Invoke-CheckForUpdates" {
    BeforeAll {
        function New-CheckForUpdatesReleaseJson {
            param([string]$TagName = 'v0.99.99', [string]$AssetName = 'TeknoParrot.Manager.v0.99.99.BETA.zip')
            return (@{
                tag_name = $TagName
                assets   = @(@{
                    name                  = $AssetName
                    browser_download_url = "https://github.com/Jumpstile/teknoparrot-manager/releases/download/$TagName/$AssetName"
                })
            } | ConvertTo-Json -Depth 5)
        }
    }

    It "reports already current and returns false without prompting when there is no newer release" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson -TagName $ScriptVersion) } }
        Mock Read-Host { throw "Read-Host should not be called when already current" }

        $path = Join-Path $TestDrive 'current.ps1'
        Set-Content -LiteralPath $path -Value "`$ScriptVersion = `"$ScriptVersion`"" -Encoding ascii

        Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
    }

    It "returns false and makes no changes when the user declines the update" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson) } }
        Mock Read-Host { "N" }

        $path = Join-Path $TestDrive 'decline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $path -Raw

        Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
    }

    It "returns false without downloading when the target is read-only" {
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = (New-CheckForUpdatesReleaseJson) } }
        Mock Read-Host { "Y" }

        $root = Join-Path $TestDrive ("readonlyroot-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true

        try {
            Invoke-CheckForUpdates -ScriptPath $path | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
}

Describe "Get-ManagerUpdateReleaseSummary" {
    It "returns the first non-blank line, trimmed of heading/bullet markdown" {
        Get-ManagerUpdateReleaseSummary -Body "## What's new`n`nFixes a startup crash." | Should -Be "What's new"
    }
    It "strips a leading bullet marker" {
        Get-ManagerUpdateReleaseSummary -Body "- Fixes a startup crash." | Should -Be "Fixes a startup crash."
    }
    It "truncates a long first line to 150 chars plus an ellipsis" {
        $long = "X" * 200
        $summary = Get-ManagerUpdateReleaseSummary -Body $long
        $summary.Length | Should -Be 153
        $summary | Should -Match '\.\.\.$'
    }
    It "returns null for an empty or whitespace-only body" {
        Get-ManagerUpdateReleaseSummary -Body "" | Should -BeNullOrEmpty
        Get-ManagerUpdateReleaseSummary -Body "   " | Should -BeNullOrEmpty
        Get-ManagerUpdateReleaseSummary -Body $null | Should -BeNullOrEmpty
    }
}

Describe "Get-ManagerUpdateRelease -MaxAttempts" {
    It "makes exactly one request and does not sleep when MaxAttempts is 1" {
        Mock Invoke-WebRequest { throw [System.Net.WebException]::new('transient') }
        Mock Start-Sleep {}
        Get-ManagerUpdateRelease -MaxAttempts 1 -TimeoutSec 5 | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times 1
        Should -Invoke Start-Sleep -Times 0
    }
}

Describe "Invoke-ManagerUpdateInstall" {
    BeforeAll {
        function New-StartupCheckFixtureZipBytes {
            param(
                [string]$EntryName = 'TeknoParrot-Manager.ps1',
                [string]$EntryContent = "# TeknoParrot Manager`n`$ScriptVersion = `"0.99.99`"`n"
            )
            $zipPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-startup-fixture-" + [guid]::NewGuid().ToString('N') + '.zip')
            $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tpm-startup-staging-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
            try {
                Set-Content -LiteralPath (Join-Path $stagingDir $EntryName) -Value $EntryContent -Encoding ascii -NoNewline
                [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $zipPath)
                return , ([System.IO.File]::ReadAllBytes($zipPath))
            } finally {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
            }
        }

        function New-StartupCheckRelease {
            [pscustomobject]@{
                TagName     = 'v0.99.99'
                Name        = 'v0.99.99 BETA'
                Body        = 'Test release notes.'
                AssetName   = 'TeknoParrot.Manager.v0.99.99.BETA.zip'
                DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/TeknoParrot.Manager.v0.99.99.BETA.zip'
            }
        }
    }

    It "installs successfully and returns true" {
        $zipBytes = New-StartupCheckFixtureZipBytes
        Mock Invoke-WebRequest { param($Uri, $OutFile, $UseBasicParsing) [System.IO.File]::WriteAllBytes($OutFile, $zipBytes) }.GetNewClosure()

        $path = Join-Path $TestDrive 'install-target.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeTrue
        (Get-Content -LiteralPath $path -Raw) | Should -Match 'ScriptVersion = "0.99.99"'
    }

    It "returns false and leaves the original untouched when the target is read-only" {
        $path = Join-Path $TestDrive 'readonly-install-target.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii -NoNewline
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true
        try {
            Invoke-ManagerUpdateInstall -ScriptPath $path -Release (New-StartupCheckRelease) | Should -BeFalse
            (Get-Content -LiteralPath $path -Raw) | Should -Be '$ScriptVersion = "0.0.1"'
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
}

Describe "Invoke-StartupUpdateCheck" {
    It "returns false and does not prompt when already current" {
        Mock Get-ManagerUpdateRelease { [pscustomobject]@{ TagName = "v$ScriptVersion"; Name = $null; Body = $null; AssetName = 'x'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.39/x' } }
        Mock Read-Host { throw "Read-Host should not be called when already current" }

        $path = Join-Path $TestDrive 'startup-current.ps1'
        Set-Content -LiteralPath $path -Value "`$ScriptVersion = `"$ScriptVersion`"" -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
    }

    It "returns false without prompting again when the release check fails (e.g. offline)" {
        Mock Get-ManagerUpdateRelease { $null }
        Mock Read-Host { throw "Read-Host should not be called when the release check fails" }

        $path = Join-Path $TestDrive 'startup-offline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
    }

    It "returns false and makes no changes when the user chooses N (remind me later)" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        Mock Read-Host { "N" }

        $path = Join-Path $TestDrive 'startup-decline.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        $originalContent = Get-Content -LiteralPath $path -Raw

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
        (Get-Content -LiteralPath $path -Raw) | Should -Be $originalContent
    }

    It "shows release notes on V and then still lets the user decline with N" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Detailed notes here.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        $script:readHostCallCount = 0
        Mock Read-Host {
            $script:readHostCallCount++
            if ($script:readHostCallCount -eq 1) { return "V" }
            return "N"
        }

        $path = Join-Path $TestDrive 'startup-view-notes.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii

        Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
        Should -Invoke Read-Host -Times 2
    }

    It "returns false without downloading when Y is chosen but the target is read-only" {
        Mock Get-ManagerUpdateRelease {
            [pscustomobject]@{ TagName = 'v0.99.99'; Name = 'v0.99.99'; Body = 'Notes.'; AssetName = 'x.zip'; DownloadUrl = 'https://github.com/Jumpstile/teknoparrot-manager/releases/download/v0.99.99/x.zip' }
        }
        Mock Read-Host { "Y" }
        Mock Invoke-WebRequest { throw "Invoke-WebRequest should not be called when the target is read-only" }

        $root = Join-Path $TestDrive ("startup-readonly-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $path = Join-Path $root 'TeknoParrot-Manager.ps1'
        Set-Content -LiteralPath $path -Value '$ScriptVersion = "0.0.1"' -Encoding ascii
        Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $true

        try {
            Invoke-StartupUpdateCheck -ScriptPath $path | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root 'UpdateBackups') | Should -BeFalse
        } finally {
            Set-ItemProperty -LiteralPath $path -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
    }
}

Describe "Main menu source-level drift check" {
    # The main menu loop is top-level executable code (not a function), so it
    # is never picked up by the AST function-extraction in the top-level
    # BeforeAll and can't be exercised directly. Instead, this reads the raw
    # script source and cross-checks the displayed menu option numbers
    # against the switch statement's case labels, so a future edit to one
    # without the other (the exact drift class documented in
    # LESSONS_LEARNED.md for v0.99.25/v0.99.28) fails CI instead of shipping.
    BeforeAll {
        $script:mainScriptContent = Get-Content -LiteralPath $scriptPath -Raw
    }

    It "has a switch case for every displayed menu option number, 1 through the Exit option, with no gaps" {
        $menuLineMatches = [regex]::Matches($script:mainScriptContent, 'Write-Host\s+"\s*(\d+)\)\s')
        $displayedNumbers = $menuLineMatches | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique

        # The menu block is the first place these numbers appear in the file;
        # take the first N matches in file order rather than every numeric
        # "N)" that could coincidentally appear elsewhere (e.g. inside the
        # Restore-from-Backup sub-menu, which also uses "1)"/"2)"/"3)").
        $menuBlockStart = $script:mainScriptContent.IndexOf('Write-Host " Library Management"')
        $menuBlockEnd    = $script:mainScriptContent.IndexOf('Enter 1-')
        $menuBlockStart | Should -BeGreaterThan 0
        $menuBlockEnd | Should -BeGreaterThan $menuBlockStart

        $menuBlockText = $script:mainScriptContent.Substring($menuBlockStart, $menuBlockEnd - $menuBlockStart)
        $displayedNumbers = [regex]::Matches($menuBlockText, 'Write-Host\s+"\s*(\d+)\)\s') |
            ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique

        $switchBlockStart = $script:mainScriptContent.IndexOf('switch ($modeChoice) {')
        # The switch block's own cases each have their own "{ ... }" (e.g.
        # "1" { $mode = "AutoSync" }), so IndexOf('}', ...) would only find
        # the first case's closing brace. "if ($modeChoice -eq" reliably
        # appears immediately after the whole switch statement closes.
        $switchBlockEnd   = $script:mainScriptContent.IndexOf('if ($modeChoice -eq', $switchBlockStart)
        $switchBlockText  = $script:mainScriptContent.Substring($switchBlockStart, $switchBlockEnd - $switchBlockStart)
        $switchNumbers    = [regex]::Matches($switchBlockText, '"(\d+)"\s*\{') |
            ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique

        $displayedNumbers.Count | Should -BeGreaterThan 0
        # Join to strings for comparison -- piping an array directly into
        # Should -Be iterates it element-by-element against the whole
        # right-hand side instead of comparing the collections as a whole.
        ($displayedNumbers -join ',') | Should -Be ($switchNumbers -join ',')

        $expectedSequence = 1..($displayedNumbers[-1])
        ($displayedNumbers -join ',') | Should -Be ($expectedSequence -join ',')
    }

    It "shows Enter 1-N matching the highest displayed menu option" {
        $menuBlockStart = $script:mainScriptContent.IndexOf('Write-Host " Library Management"')
        $enterMatch = [regex]::Match($script:mainScriptContent.Substring($menuBlockStart), 'Enter 1-(\d+)')
        $enterMatch.Success | Should -BeTrue

        $menuBlockEnd = $script:mainScriptContent.IndexOf('Enter 1-', $menuBlockStart)
        $menuBlockText = $script:mainScriptContent.Substring($menuBlockStart, $menuBlockEnd - $menuBlockStart)
        $displayedNumbers = [regex]::Matches($menuBlockText, 'Write-Host\s+"\s*(\d+)\)\s') |
            ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique

        [int]$enterMatch.Groups[1].Value | Should -Be $displayedNumbers[-1]
    }
}
