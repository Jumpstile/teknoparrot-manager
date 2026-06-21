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
