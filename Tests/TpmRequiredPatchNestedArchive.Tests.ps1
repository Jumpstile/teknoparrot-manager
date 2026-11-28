#Requires -Module Pester

# A patch file can hold another archive (Dragon Dance.rar holds Fix iDmacDrv32.rar). The engine reads the file inside the inner
# archive with the player's own 7-Zip. These tests build tiny fake archives with that same 7-Zip (a 7z inside a 7z stands in for
# a RAR inside a RAR, because 7-Zip cannot write RAR) and skip when 7-Zip is not installed.
BeforeAll {
    . (Join-Path $PSScriptRoot '..\scripts\TpmRequiredPatchEngine.ps1')
    $mainAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'), [ref]$null, [ref]$null)
    foreach ($functionName in @('Get-TpmSupportNativeType','Get-TpmSupportFinalPathFromHandle','Resolve-TpmSupportExpectedFinalPath','Remove-TpmSupportHandle','Get-TpmFileState','Test-PathInside','Test-TpmNoReparsePath')) {
        $functionAst = $mainAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }, $true)
        if (-not $functionAst) { throw ('Missing required helper: ' + $functionName) }
        . ([scriptblock]::Create($functionAst.Extent.Text))
    }
    [void](Get-TpmSupportNativeType)
    $script:sevenZip = @(@($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | ForEach-Object { Join-Path $_ '7-Zip\7z.exe' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)

    function Read-NestedMember {
        param([string]$Archive, [string]$Member, [int64]$Size, [string]$Work)
        $process = Start-TpmSevenZipMember -ArchivePath $Archive -Member $Member -Size $Size -WorkDir $Work
        try {
            $memory = New-Object IO.MemoryStream
            $process.StandardOutput.BaseStream.CopyTo($memory)
            $process.WaitForExit()
            return $memory.ToArray()
        } finally {
            $temp = $process.PSObject.Properties['TempArchive']
            $process.Dispose()
            if ($temp) { [IO.File]::Delete([string]$temp.Value) }
        }
    }
}

Describe 'A patch file inside another patch file' {
    BeforeEach {
        $script:root = Join-Path $TestDrive ('n-' + [guid]::NewGuid().ToString('N'))
        $script:work = Join-Path $script:root 'work'
        [void][IO.Directory]::CreateDirectory($script:work)
        $script:bytes = [Text.Encoding]::ASCII.GetBytes('fake patch dll bytes, made by the test')
        if ($script:sevenZip.Count) {
            $inside = Join-Path $script:root 'inside'
            [void][IO.Directory]::CreateDirectory($inside)
            [IO.File]::WriteAllBytes((Join-Path $inside 'fix.dll'), $script:bytes)
            [IO.File]::WriteAllText((Join-Path $inside 'run.bat'), 'echo never run')
            $inner = Join-Path $script:root 'Inner Fix.7z'
            Push-Location $inside; try { & $script:sevenZip[0] a -bso0 -bsp0 $inner 'fix.dll' | Out-Null } finally { Pop-Location }
            $outerSource = Join-Path $script:root 'outer'
            [void][IO.Directory]::CreateDirectory($outerSource)
            Copy-Item -LiteralPath $inner -Destination $outerSource
            Copy-Item -LiteralPath (Join-Path $inside 'run.bat') -Destination $outerSource
            $script:outer = Join-Path $script:root 'Outer.7z'
            Push-Location $outerSource; try { & $script:sevenZip[0] a -bso0 -bsp0 $script:outer 'Inner Fix.7z' 'run.bat' | Out-Null } finally { Pop-Location }
        }
    }

    It 'reads the exact file inside the inner archive and leaves no temporary copy behind' {
        if (-not $script:sevenZip.Count) { Set-ItResult -Skipped -Because '7-Zip is not installed'; return }
        $read = Read-NestedMember -Archive $script:outer -Member 'Inner Fix.7z>fix.dll' -Size $script:bytes.Length -Work $script:work
        [Convert]::ToBase64String($read) | Should -BeExactly ([Convert]::ToBase64String($script:bytes))
        @(Get-ChildItem -LiteralPath $script:work -Force).Count | Should -Be 0
    }

    It 'refuses a wrong size, a missing inner archive and a missing file, and leaves no temporary copy' {
        if (-not $script:sevenZip.Count) { Set-ItResult -Skipped -Because '7-Zip is not installed'; return }
        { Start-TpmSevenZipMember -ArchivePath $script:outer -Member 'Inner Fix.7z>fix.dll' -Size 5 -WorkDir $script:work } | Should -Throw '*different size*'
        { Start-TpmSevenZipMember -ArchivePath $script:outer -Member 'Nope.7z>fix.dll' -Size $script:bytes.Length -WorkDir $script:work } | Should -Throw '*absent*'
        { Start-TpmSevenZipMember -ArchivePath $script:outer -Member 'Inner Fix.7z>missing.dll' -Size $script:bytes.Length -WorkDir $script:work } | Should -Throw '*absent*'
        @(Get-ChildItem -LiteralPath $script:work -Force).Count | Should -Be 0
    }
}
