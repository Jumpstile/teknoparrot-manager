#Requires -Module Pester

# AutoSync only unpacks .zip. A user with .7z or .rar archives must be told they were skipped, and a folder of
# ZIPs must stay quiet. Isolated fixtures under $TestDrive only.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\TeknoParrot-Manager.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'Bootstrap could not parse the production script.' }
    $fn = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Write-TpmSkippedArchiveNotice' }, $true)[0]
    function Write-Log { param([string]$msg) }
    . ([scriptblock]::Create($fn.Extent.Text))
}

Describe 'Skipped .7z / .rar archive notice' {
    BeforeEach {
        Mock Write-Host {}
        Mock Write-Log {}
    }

    It 'tells the user how many .7z and .rar archives were skipped and changes nothing' {
        $dir = Join-Path $TestDrive 'src1'
        New-Item -ItemType Directory -Path $dir | Out-Null
        foreach ($n in 'a.7z', 'B.RAR', 'g.7z.001', 'c.zip', 'd.7zx', 'e.txt') { Set-Content -LiteralPath (Join-Path $dir $n) -Value 'x' }
        (Write-TpmSkippedArchiveNotice -SourceFolder $dir) | Should -Be 3
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*cannot unpack*' } -Times 1
        @(Get-ChildItem -LiteralPath $dir).Count | Should -Be 6
    }

    It 'stays quiet for a folder of ZIPs or a missing folder' {
        $dir = Join-Path $TestDrive 'src2'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'c.zip') -Value 'x'
        (Write-TpmSkippedArchiveNotice -SourceFolder $dir) | Should -Be 0
        (Write-TpmSkippedArchiveNotice -SourceFolder (Join-Path $TestDrive 'nowhere')) | Should -Be 0
        Should -Invoke Write-Host -Times 0 -Exactly
    }
}
