Describe 'BepInEx destination file check explains each refusal' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $want = @('Get-TpmSupportNativeType', 'Get-TpmTreeFileState')
        $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $want -contains $n.Name }, $true)
        foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
        $script:Root = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-415-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $script:Root | Out-Null
        $script:SourceText = Get-Content -LiteralPath $src -Raw
    }
    AfterAll {
        if ($script:Root -and (Test-Path -LiteralPath $script:Root)) { Remove-Item -LiteralPath $script:Root -Recurse -Force }
    }

    It 'treats a missing file as absent, not unsafe' {
        $state = Get-TpmTreeFileState -Path (Join-Path $script:Root '.doorstop_version')
        $state.Kind | Should -Be 'Absent'
    }
    It 'reads an ordinary file' {
        $p = Join-Path $script:Root 'plain.txt'
        Set-Content -LiteralPath $p -Value 'x'
        (Get-TpmTreeFileState -Path $p).Kind | Should -Be 'File'
    }
    It 'refuses a file shared with another folder and says why in plain words' {
        $a = Join-Path $script:Root 'a.txt'
        $b = Join-Path $script:Root 'b.txt'
        Set-Content -LiteralPath $a -Value 'x'
        New-Item -ItemType HardLink -Path $b -Value $a | Out-Null
        $state = Get-TpmTreeFileState -Path $b
        $state.Kind | Should -Be 'Other'
        $state.Reason | Should -Match 'shared with another folder'
    }
    It 'refuses a folder in the place of a file and says why' {
        $d = Join-Path $script:Root 'folder.txt'
        New-Item -ItemType Directory -Path $d | Out-Null
        $state = Get-TpmTreeFileState -Path $d
        $state.Kind | Should -Be 'Other'
        $state.Reason | Should -Match 'folder'
    }
    It 'names the file and the reason in the refusal message' {
        $script:SourceText | Should -Match 'already exists in the game folder and cannot be replaced safely: \$\(\$destinationState\.Reason\)'
    }
}
