#Requires -Module Pester
# Permanent Contract Stability Regression Suite (ECVF). Runs against the
# real contracts\ directory, not fixtures -- this is the gate that must
# fail the instant any registered contract becomes invalid, has a dangling
# evidence/experiment reference, a duplicate ownership path or capability
# ID, or an unsupported schema version. If this suite is red, certification
# must never proceed as though the contract still applies.
BeforeAll {
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1') -Force
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Contracts.psm1') -Force
 $script:registered = Get-TPMRegisteredEmulatorContractsV1
 $script:integrity = Test-TPMContractRegistryIntegrityV1
}

Describe 'ECVF Contract Stability Regression Suite' {
 It 'discovers at least one registered contract' {
  $script:registered.Count | Should -BeGreaterThan 0
 }

 It 'registry integrity check reports Valid=true with no errors' {
  $script:integrity.Valid | Should -Be $true
  $script:integrity.Errors.Count | Should -Be 0
 }

 It 'every discovered contract validates individually with Assert-TPMEmulatorContractV1' {
  foreach ($entry in $script:registered) {
   $json = [IO.File]::ReadAllText($entry.Path)
   $parsed = ConvertFrom-TPMOrderedJsonV1 -Json $json
   { Assert-TPMEmulatorContractV1 -Contract $parsed -ExpectedContractId $entry.ContractId } | Should -Not -Throw -Because "contracts/$($entry.ContractId)/contract.json must validate"
  }
 }

 It 'every EvidenceReference Locator resolves to a real file and heading' {
  foreach ($entry in $script:registered) {
   $dir = Split-Path -Parent $entry.Path
   { Assert-TPMContractLocatorsResolveV1 -Contract $entry.Contract -ContractDirectory $dir } | Should -Not -Throw -Because "contracts/$($entry.ContractId)/*.md anchors must exist"
  }
 }

 It 'every contract declares a supported SchemaVersion' {
  foreach ($entry in $script:registered) {
   { Assert-TPMSupportedContractSchemaVersionV1 -Contract $entry.Contract } | Should -Not -Throw -Because "contracts/$($entry.ContractId)/contract.json SchemaVersion must be in Get-TPMSupportedContractSchemaVersionsV1"
  }
 }

 It 'every contract has unique OwnershipBoundaries[].SettingPath' {
  foreach ($entry in $script:registered) {
   $paths = @($entry.Contract.OwnershipBoundaries | ForEach-Object { $_.SettingPath })
   ($paths | Select-Object -Unique).Count | Should -Be $paths.Count -Because "contracts/$($entry.ContractId) must not declare the same SettingPath twice"
  }
 }

 It 'every contract has unique EnvironmentCapabilities[].CapabilityId' {
  foreach ($entry in $script:registered) {
   $ids = @($entry.Contract.EnvironmentCapabilities | ForEach-Object { $_.CapabilityId })
   @($ids | Select-Object -Unique).Count | Should -Be @($ids).Count
  }
 }

 It 'every contract has unique RuntimeCapabilities[].CapabilityId' {
  foreach ($entry in $script:registered) {
   $ids = @($entry.Contract.RuntimeCapabilities | ForEach-Object { $_.CapabilityId })
   @($ids | Select-Object -Unique).Count | Should -Be @($ids).Count
  }
 }

 It 'every contract has unique EvidenceReferences[].EvidenceId' {
  foreach ($entry in $script:registered) {
   $ids = @($entry.Contract.EvidenceReferences | ForEach-Object { $_.EvidenceId })
   ($ids | Select-Object -Unique).Count | Should -Be $ids.Count
  }
 }

 It 'no RuntimeCapability ObservableEvidence entry is marked Confirmed without a hardware-backed EvidenceReference existing in the contract' {
  # This does not assert Confirmed entries are wrong -- it only guards
  # against a contract quietly flipping Unconfirmed to Confirmed with no
  # corresponding evidence trail at all, which would defeat the entire
  # point of the confidence/lifecycle separation.
  foreach ($entry in $script:registered) {
   foreach ($cap in $entry.Contract.RuntimeCapabilities) {
    $confirmedCount = @($cap.ObservableEvidence | Where-Object { $_.Status -eq 'Confirmed' }).Count
    if ($confirmedCount -gt 0) {
     $entry.Contract.EvidenceReferences.Count | Should -BeGreaterThan 0 -Because "contracts/$($entry.ContractId) capability '$($cap.CapabilityId)' has Confirmed evidence but no EvidenceReferences at all"
    }
   }
  }
 }
}

Describe 'ECVF Contract Stability Regression Suite -- pcsx2x6 specific invariants' {
 BeforeAll {
  $script:pcsx2 = $script:registered | Where-Object { $_.ContractId -eq 'pcsx2x6' } | Select-Object -First 1
 }

 It 'pcsx2x6 is registered' {
  $script:pcsx2 | Should -Not -BeNullOrEmpty
 }

 It 'pcsx2x6 jvs-lightgun RuntimeCapability has no Confirmed ObservableEvidence yet (EXP-002 has not run)' {
  $cap = $script:pcsx2.Contract.RuntimeCapabilities | Where-Object { $_.CapabilityId -eq 'jvs-lightgun' } | Select-Object -First 1
  $cap | Should -Not -BeNullOrEmpty
  @($cap.ObservableEvidence | Where-Object { $_.Status -eq 'Confirmed' }).Count | Should -Be 0 -Because 'this must only flip once contracts/pcsx2x6/experiments.md#exp-002-jvs-runtime-signal records a real hardware result'
 }

 It 'pcsx2x6 emulator-owned USB1/USB2 Type and JvsMode boundaries never allow WriteDirectly' {
  $paths = @('USB1.Type', 'USB2.Type', 'JvsMode')
  foreach ($path in $paths) {
   $boundary = $script:pcsx2.Contract.OwnershipBoundaries | Where-Object { $_.SettingPath -eq $path } | Select-Object -First 1
   $boundary | Should -Not -BeNullOrEmpty -Because "$path must have a registered OwnershipBoundary"
   $boundary.WritePolicy | Should -Not -Be 'WriteDirectly'
  }
 }
}
