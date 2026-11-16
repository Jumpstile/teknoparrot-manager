#Requires -Module Pester
# Finding 10: applying the Original look the way ReShade setup does (no preset, no -CanonicalPreset) keeps the previous look's Techniques=.
BeforeAll {
    $tree = (Split-Path -Parent $PSScriptRoot)
    $scriptPath = Join-Path $tree 'TeknoParrot-Manager.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) { throw 'parse failed' }
    $functionFile = Join-Path $TestDrive 'fns.ps1'
    ($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`r`n`r`n" | Set-Content -LiteralPath $functionFile -Encoding utf8
    Get-Module -Name TpmProgress -All | Remove-Module -Force -ErrorAction SilentlyContinue
    . $functionFile
    . (Join-Path $tree 'Tests\TpmExtractedScriptState.ps1')
    $script:DisplayVersion = 'v1.0 RC8'
    $script:ActiveTpmWorkflowStatus = $null
    $script:TpmWorkflowRendering = $false
    $script:logPath = Join-Path $TestDrive 'f10.log'
    $script:logWarnShown = $false
}
Describe 'Finding 10' {
    BeforeEach {
        Mock Write-Log {}
        Mock Write-TpmCompactExtractionProgress {}
        Mock Write-Host {}
        Mock Get-ExeArchitecture { 'x64' }
    }
    It 'Original applied as setup does leaves no Techniques= from the previous look' {
        $root = Join-Path $TestDrive 'game'; $stage = Join-Path $TestDrive 'stage'
        [void][IO.Directory]::CreateDirectory($root); [void][IO.Directory]::CreateDirectory($stage)
        $exe = Join-Path $root 'game.exe'; [IO.File]::WriteAllText($exe, 'MZ')
        $dll = Join-Path $TestDrive 'ReShade64.dll'; [IO.File]::WriteAllText($dll, 'MZ-rt')
        $fx = Join-Path $stage 'Levels.fx'; $h1 = Join-Path $stage 'ReShade.fxh'; $h2 = Join-Path $stage 'ReShadeUI.fxh'
        [IO.File]::WriteAllText($fx, 'fx'); [IO.File]::WriteAllText($h1, 'h1'); [IO.File]::WriteAllText($h2, 'h2')
        $script:f10Stage = $stage
        $script:f10Files = @(
            [pscustomobject]@{ RelativePath = 'Shaders/SweetFX/Levels.fx'; SourceRelativePath = 'Shaders/SweetFX/Levels.fx'; Path = $fx; SHA256 = (Get-FileHash $fx -Algorithm SHA256).Hash }
            [pscustomobject]@{ RelativePath = 'Shaders/TPM/ReShade.fxh'; SourceRelativePath = 'Shaders/ReShade.fxh'; Path = $h1; SHA256 = (Get-FileHash $h1 -Algorithm SHA256).Hash }
            [pscustomobject]@{ RelativePath = 'Shaders/TPM/ReShadeUI.fxh'; SourceRelativePath = 'TPM-authored/ReShadeUI.fxh'; Path = $h2; SHA256 = (Get-FileHash $h2 -Algorithm SHA256).Hash }
        )
        Mock Install-TpmReShadeApprovedEffect { [pscustomobject]@{ Succeeded = $true; State = 'PREPARED'; StagingRoot = $script:f10Stage; Files = $script:f10Files } }
        $own = Join-Path $TestDrive 'own.json'
        $doc = [xml]'<GameProfile><EmulatorType>Default</EmulatorType></GameProfile>'
        # Look 1 the way setup deploys a non-Original look: a generated preset file passed as -PresetPath, no -CanonicalPreset.
        $levels = Get-TpmReShadeProfile -ProfileId Levels
        $gen = Join-Path $TestDrive 'gen.ini'
        [IO.File]::WriteAllText($gen, (New-TpmReShadePresetContent -ProfileDefinition $levels))
        $first = Install-TpmReShadeProfileDeployment -ProfileDefinition $levels -GamePath $exe -Doc $doc -SourceDll $dll -PresetPath $gen -PerGamePresetPath (Join-Path $TestDrive 'nope\Game.ini') -CacheRoot (Join-Path $root 'cache') -OwnershipPath $own -CanonicalPreset:$false
        $first.Succeeded | Should -BeTrue -Because ($first | ConvertTo-Json -Depth 3)
        $ini = Join-Path $root 'ReShade.ini'
        Write-Output ('AFTER LEVELS: ' + ((Get-Content $ini) -match '^(Techniques|PresetName)=' -join ' | '))
        # Look 2 = Original exactly as setup calls it: $presetPath is $null (setup skips generation for Original), canonicalForGame is $false.
        $second = Install-TpmReShadeProfileDeployment -ProfileDefinition (Get-TpmReShadeProfile -ProfileId Original) -GamePath $exe -Doc $doc -SourceDll $dll -PresetPath $null -PerGamePresetPath (Join-Path $TestDrive 'nope\Game.ini') -CacheRoot (Join-Path $root 'cache') -OwnershipPath $own -CanonicalPreset:$false
        Write-Output ('ORIGINAL RESULT: Succeeded=' + $second.Succeeded + ' State=' + $second.State + ' PresetSource=' + $second.PresetSource)
        Write-Output ('AFTER ORIGINAL: ' + ((Get-Content $ini) -match '^(Techniques|PresetName)=' -join ' | '))
        $second.Succeeded | Should -BeTrue
        (Get-Content $ini -Raw) | Should -Not -Match '(?m)^Techniques=\S'
    }
}
