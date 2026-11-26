#Requires -Module Pester

# R94BF: three things a user sees.
# 1. ReShade picks its hook DLL from the game's real import table: a game that imports dxgi.dll and only contains the text
#    "d3d12.dll" somewhere is not treated as a Direct3D 12 game.
# 2. Pressing Enter at the "path to ReShade64.dll" prompt goes back; it is not reported as "File not found".
# 3. GPU Fix never proposes a value the profile's dropdown does not offer (an Intel PC and an AMD/NVIDIA-only dropdown).

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'R94BF bootstrap could not parse the production script.' }
    $wanted = @('Get-TpmPeImportDllNames', 'Get-GameApiDll', 'Resolve-ReShadeDllAcquisition', 'Test-GpuFixUpToDate', 'ConvertTo-XPathStringLiteral', 'ConvertTo-TpmAutoSyncLongPath')
    $functions = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $args[0].Name }, $true))
    if ($functions.Count -ne $wanted.Count) { throw 'R94BF could not find every function under test.' }
    $functionFile = Join-Path $TestDrive 'r94bf-functions.ps1'
    ($functions | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    . $functionFile
    function Write-Log { param([string]$msg) }

    # A tiny 64-bit PE file: one section that holds an import table naming the given DLLs, plus loose text after it.
    function New-R94bfPe {
        param([string]$Path, [string[]]$Imports, [string]$LooseText = '')
        $bytes = New-Object byte[] 0x800
        $ms = New-Object System.IO.MemoryStream(, $bytes)
        $w = New-Object System.IO.BinaryWriter($ms)
        $w.Write([uint16]0x5A4D)
        $ms.Position = 0x3C; $w.Write([int32]0x80)
        $ms.Position = 0x80; $w.Write([uint32]0x4550)
        $w.Write([uint16]0x8664); $w.Write([uint16]1)          # machine, one section
        $ms.Position = 0x80 + 20; $w.Write([uint16]240)       # optional header size
        $optional = 0x80 + 24
        $ms.Position = $optional; $w.Write([uint16]0x20B)
        $ms.Position = $optional + 120; $w.Write([uint32]0x1000)   # import table RVA
        $section = $optional + 240
        $ms.Position = $section + 8
        $w.Write([uint32]0x600); $w.Write([uint32]0x1000); $w.Write([uint32]0x600); $w.Write([uint32]0x200)
        # Descriptors at file 0x200 (20 bytes each, then a zero one); names at file 0x400 onward.
        $nameOffset = 0x400
        for ($i = 0; $i -lt $Imports.Count; $i++) {
            $ms.Position = 0x200 + (20 * $i) + 12
            $w.Write([uint32](0x1000 + ($nameOffset - 0x200)))
            $nameBytes = [System.Text.Encoding]::ASCII.GetBytes($Imports[$i])
            [Array]::Copy($nameBytes, 0, $bytes, $nameOffset, $nameBytes.Length)
            $nameOffset += $nameBytes.Length + 1
        }
        if ($LooseText) { $loose = [System.Text.Encoding]::ASCII.GetBytes($LooseText); [Array]::Copy($loose, 0, $bytes, 0x700, $loose.Length) }
        [System.IO.File]::WriteAllBytes($Path, $bytes)
    }
}

Describe 'ReShade hook DLL from the real imports' {
    It 'a game that imports dxgi.dll and only contains the text d3d12.dll is a Direct3D 11 game' {
        $exe = Join-Path $TestDrive 'd3d11game.exe'
        New-R94bfPe -Path $exe -Imports @('kernel32.dll', 'dxgi.dll', 'd3d11.dll') -LooseText 'd3d12.dll'
        Get-GameApiDll -ExePath $exe | Should -BeExactly 'dxgi.dll'
    }
    It 'a game that imports d3d12.dll gets the d3d12 hook' {
        $exe = Join-Path $TestDrive 'd3d12game.exe'
        New-R94bfPe -Path $exe -Imports @('kernel32.dll', 'd3d12.dll', 'dxgi.dll')
        Get-GameApiDll -ExePath $exe | Should -BeExactly 'd3d12.dll'
    }
}

Describe 'Manual ReShade DLL prompt' {
    It 'an empty answer cancels with no error' {
        $r = Resolve-ReShadeDllAcquisition -Choice 'B' -InputPath ''
        $r.State | Should -BeExactly 'Cancelled'
    }
}

Describe 'GPU Fix only proposes values the profile offers' {
    BeforeAll {
        function New-GpuDoc { param([string]$Options) return [xml]"<GameProfile><ConfigValues><FieldInformation><FieldName>GPU Fix</FieldName><FieldType>Dropdown</FieldType><FieldValue>AMD</FieldValue><FieldOptions>$Options</FieldOptions></FieldInformation></ConfigValues></GameProfile>" }
    }
    It 'Intel PC and a dropdown with only AMD and NVIDIA: the field is left as it is' {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc '<string>AMD</string><string>NVIDIA</string>') -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'Intel'
        $r.Changes.Count | Should -Be 0
        @($r.NotOffered) | Should -Contain 'GPU Fix'
    }
    It 'a dropdown that offers None still gets None' {
        $r = Test-GpuFixUpToDate -Doc (New-GpuDoc '<string>None</string><string>AMD</string><string>NVIDIA</string>') -BoolFields @() -DropdownFields @('GPU Fix') -Vendor 'Intel'
        $r.Changes[0].NewValue | Should -BeExactly 'None'
    }
}
