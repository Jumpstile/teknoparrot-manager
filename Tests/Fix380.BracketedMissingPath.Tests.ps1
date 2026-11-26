Describe 'A missing file inside a bracketed game folder ([TP]) is reported as missing' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $want = @('Get-TpmSupportNativeType', 'Get-TpmSupportFinalPathFromHandle', 'Resolve-TpmSupportExpectedFinalPath', 'Remove-TpmSupportHandle',
            'Get-TpmTreeFileState', 'Remove-TpmTreeOwnedFile', 'Test-TpmGameMutationPath', 'Remove-PostgresTrustRuleMarker')
        $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $want -contains $n.Name }, $true)
        foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
        $script:Base = Join-Path ([System.IO.Path]::GetTempPath()) ('tpm-380-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:Game = Join-Path $script:Base 'Alpha Game (1.00)[TP]'
        New-Item -ItemType Directory -Force -Path $script:Game | Out-Null
    }
    AfterAll {
        if ($script:Base -and (Test-Path -LiteralPath $script:Base)) { Remove-Item -LiteralPath $script:Base -Recurse -Force }
    }

    It 'reports a missing file in a [TP] folder as absent, not unreadable' {
        $state = Get-TpmTreeFileState -Path (Join-Path $script:Game 'winhttp.dll')
        $state.Kind | Should -Be 'Absent'
    }
    It 'reports a missing file in a [TP] folder with its own brackets as absent' {
        $state = Get-TpmTreeFileState -Path (Join-Path $script:Game 'sub[1]\file.txt')
        $state.Kind | Should -Be 'Absent'
    }
    It 'still reads a real file in a [TP] folder' {
        $p = Join-Path $script:Game 'real.txt'
        Set-Content -LiteralPath $p -Value 'x'
        (Get-TpmTreeFileState -Path $p).Kind | Should -Be 'File'
    }
    It 'still refuses a folder sitting where a file should be' {
        $d = Join-Path $script:Game 'folder.txt'
        New-Item -ItemType Directory -Path $d | Out-Null
        (Get-TpmTreeFileState -Path $d).Kind | Should -Be 'Other'
    }
    It 'undoing a file that is already gone from a [TP] folder says Absent instead of failing' {
        $r = Remove-TpmTreeOwnedFile -Path (Join-Path $script:Game 'gone.dll') -ExpectedIdentity 'any'
        $r | Should -Be 'Absent'
    }
    It 'a registered game path that is gone from a [TP] folder is reported as missing, with or without the leaf requirement' {
        $gone = Join-Path $script:Game 'gone.exe'
        (Test-TpmGameMutationPath -GamePath $gone -RequireLeaf).ReasonCode | Should -Be 'GAME_PATH_MISSING'
        (Test-TpmGameMutationPath -GamePath $gone).ReasonCode | Should -Be 'GAME_PATH_MISSING'
        (Test-TpmGameMutationPath -GamePath (Join-Path $script:Base 'Missing (1.00)[TP]\game.exe')).Valid | Should -BeFalse
    }
    It 'removing a PostgreSQL recovery marker that is already gone from a [TP] folder finishes quietly' {
        $script:MarkerForTest = Join-Path $script:Game 'marker.json'
        function Get-PostgresTrustRuleMarkerPath { return $script:MarkerForTest }
        { Remove-PostgresTrustRuleMarker } | Should -Not -Throw
        Set-Content -LiteralPath $script:MarkerForTest -Value '{}'
        { Remove-PostgresTrustRuleMarker } | Should -Not -Throw
        [System.IO.File]::Exists($script:MarkerForTest) | Should -BeFalse
    }
}
