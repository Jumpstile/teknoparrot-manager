# Owner 36, #323, TPM-RC8-CERT-WORKER-BOOTSTRAP-001.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSHOME, 'Modules', 'Microsoft.PowerShell.Utility', 'Microsoft.PowerShell.Utility.psd1')) -ErrorAction Stop
    $repo = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repo 'scripts\TPMCertification.ProductionFacts.psm1') -Force -ErrorAction Stop
}
Describe 'Certification real IH worker module boundary' {
    It 'validates a clean file and its real rule manifest despite foreign Utility search precedence' {
        # Use an actual installed PS7 manifest, never a mock command or fake analyzer.
        $foreign = @(Get-Module -ListAvailable -Name Microsoft.PowerShell.Utility | Where-Object { $_.Version.Major -ge 7 } | Select-Object -First 1)
        if (-not $foreign.Count) {
            Set-ItResult -Skipped -Because 'No real PS7 Utility module is installed to exercise foreign-module precedence.'
            return
        }
        $foreignRoot = [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($foreign[0].Path))
        $saved = $env:PSModulePath
        try {
            # Process-local fixture only; the real Start-Job inherits this path, not parent imports.
            $env:PSModulePath = $foreignRoot + [IO.Path]::PathSeparator + $saved
            $target = Join-Path $TestDrive 'clean-worker.ps1'
            [IO.File]::WriteAllText($target, "Write-Output 'safe worker'", (New-Object Text.UTF8Encoding($false)))
            $registry = Join-Path $TestDrive 'empty-dispositions.psd1'
            [IO.File]::WriteAllText($registry, '@{ SchemaVersion = 1; Dispositions = @() }', (New-Object Text.UTF8Encoding($false)))
            $inv = @([ordered]@{ RelativePath = 'clean-worker.ps1'; FullPath = $target })
            $module = InModuleScope TPMCertification.ProductionFacts { Find-TPMInjectionHunterModuleV1 }
            $module | Should -Not -BeNullOrEmpty
            $expectedVersion = [string](Import-PowerShellDataFile -Path $module.Path).ModuleVersion
            $result = InModuleScope TPMCertification.ProductionFacts -Parameters @{ Inventory = $inv; Registry = $registry } {
                Test-TPMProductionInjectionHunterV1 -Inventory $Inventory -DispositionRegistryPath $Registry
            }
            $result.Executed | Should -BeTrue -Because 'even a zero-finding file must load and validate the real IH manifest in the native worker'
            $result.FindingCount | Should -Be 0
            $result.UnresolvedFindingCount | Should -Be 0
            $result.ToolVersion | Should -Be $expectedVersion
        } finally { $env:PSModulePath = $saved }
    }
}
