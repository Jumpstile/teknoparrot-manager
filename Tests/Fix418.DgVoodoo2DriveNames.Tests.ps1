Describe 'dgVoodoo2 result names the drives that are not connected' {
    BeforeAll {
        $src = Join-Path (Split-Path -Parent $PSScriptRoot) 'TeknoParrot-Manager.ps1'
        $script:SourceText = Get-Content -LiteralPath $src -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
        $want = @('Get-TpmDgVoodoo2ResultView', 'Get-TpmDgVoodoo2GameOutcomes', 'Get-TpmStepCountsLine', 'Get-TpmBackupFolderLine', 'Get-TpmDriveSkipNext', 'Format-TpmNameList', 'Join-TpmPostgresSetupNames', 'Get-TpmGameTitle')
        $funcs = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $want -contains $n.Name }, $true)
        foreach ($f in $funcs) { . ([scriptblock]::Create($f.Extent.Text)) }
        function Get-TpmTransactionField { param($Object, $Name, $Default) if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name } return $Default }
        function Format-TpmGameCount { param([int]$Count) if ($Count -eq 1) { '1 game' } else { "$Count games" } }
        function Get-TpmDgVoodoo2DetailBlocks { param($Result) @() }
    }

    It 'names the drive and the repair route when games were skipped for a missing drive' {
        $skip = [pscustomobject]@{ Game = 'blitz2k'; ReasonCode = 'DEVICE_UNAVAILABLE'; Reason = 'The saved game drive or device is unavailable.'; SavedPath = 'Q:\Games\blitz2k\game.exe' }
        $result = [pscustomobject]@{ DeploymentDetails = @(); SkipDetails = @($skip); PickedGames = @('blitz2k'); NoOp = $false; AlreadyConfigured = @() }
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        (@($view.Needs) -join ' ') | Should -Match 'Drive not connected: Q:'
        $view.Next | Should -Match 'Library health check'
    }
    It 'says an already set up game kept its files without checking them' {
        $result = [pscustomobject]@{ DeploymentDetails = @(); SkipDetails = @(); PickedGames = @('blitz99'); NoOp = $true; AlreadyConfigured = @('blitz99') }
        $view = Get-TpmDgVoodoo2ResultView -Result $result
        $view.Title | Should -Match 'blitz99'
        $view.Title | Should -Match 'kept as they are, not checked'
    }
    It 'tells the user plainly to continue after the ReShade result' {
        $script:SourceText | Should -Match 'Press Enter to continue to dgVoodoo2'
    }
}
