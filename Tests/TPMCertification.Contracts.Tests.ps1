#Requires -Module Pester
BeforeAll {
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Authority.psm1') -Force
 Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts\TPMCertification.Contracts.psm1') -Force

 function New-ValidContractFixtureV1 {
  [ordered]@{
   ContractId = 'fixture-emu'
   SchemaVersion = '1.0.0'
   DisplayName = 'Fixture Emulator'
   UpstreamRepository = 'https://example.invalid/fixture/repo'
   UpstreamPinnedCommit = ('a' * 40)
   UpstreamPinnedCommitDate = '2026-01-01'
   VersionDetector = [ordered]@{
    Method = 'WindowTitleRegex'
    Source = 'WindowTitle'
    Pattern = 'Fixture v([0-9a-f]+)'
    MatchedCommitMap = @(
     [ordered]@{ VersionString = ('a' * 40); Commit = ('a' * 40); MatchState = 'Matched' }
    )
   }
   ContractStatus = 'EvidenceGathered'
   EvidenceConfidence = 'SourceVerified'
   OwnershipBoundaries = @(
    [ordered]@{ SettingPath = 'Foo.Bar'; Owner = 'Emulator'; Mutability = 'EmulatorManaged'; ReadPolicy = 'ReadForVerificationOnly'; WritePolicy = 'NeverWrite'; EvidenceReference = 'ev-1' }
    [ordered]@{ SettingPath = 'Foo.Baz'; Owner = 'TPM'; Mutability = 'TPMManaged'; ReadPolicy = 'ReadFreely'; WritePolicy = 'WriteDirectly'; EvidenceReference = 'ev-1' }
   )
   EnvironmentCapabilities = @(
    [ordered]@{
     CapabilityId = 'env-init'
     PresenceDetector = [ordered]@{ Method = 'PathExists'; Source = 'fixture.exe'; Pattern = $null }
     DataRootResolver = [ordered]@{ Method = 'FileContentLiteral'; Source = 'portable.txt'; DefaultValue = 'Default' }
     InitializationAction = [ordered]@{ Method = 'CliInvocation'; Command = 'fixture.exe'; Arguments = @('-testconfig'); ExpectedExitCodes = @(0); TimeoutSeconds = 30 }
     InitializedVerifier = [ordered]@{ RequiredPaths = @('inis/Fixture.ini'); RequiredMarkers = @('[Section]'); ParseMethod = 'IniSections' }
     ObservableEvidence = @('ev-1')
     ExpectedOutcome = 'ini exists and parses'
    }
   )
   RuntimeCapabilities = @(
    [ordered]@{
     CapabilityId = 'runtime-scenario'
     Scenario = 'Fixture scenario'
     ApplicabilityPredicate = [ordered]@{ GunGame = $true }
     Trigger = [ordered]@{ Description = 'fixture trigger'; Source = 'fixture source' }
     ObservableEvidence = @(
      [ordered]@{ EvidenceSourceType = 'EmulatorLog'; Reliability = 1; Locator = 'fixture log pattern'; Status = 'Unconfirmed' }
      [ordered]@{ EvidenceSourceType = 'IniSnapshot'; Reliability = 2; Locator = 'Section.Key=Value'; Status = 'Unconfirmed' }
     )
     ExpectedOutcome = 'fixture runtime state reached'
     CapabilityStatus = 'Investigating'
    }
   )
   EvidenceReferences = @(
    [ordered]@{ EvidenceId = 'ev-1'; Type = 'SourceCitation'; Description = 'fixture citation'; Locator = 'evidence.md#ev-1'; Commit = ('a' * 40); Confidence = 'SourceVerified'; RecordedDate = '2026-01-01' }
   )
   DriftPolicy = [ordered]@{
    OnUnknownVersion = 'FailClosed'
    OnDivergedVersion = 'FailClosed'
    OnCompatibleRange = 'Proceed'
    KnownCompatibleRange = @()
    RevalidationTrigger = 'recheck when upstream default branch HEAD changes'
   }
  }
 }

 function ConvertTo-FixtureJsonV1 {
  param($Fixture)
  $Fixture | ConvertTo-Json -Depth 12
 }
}

Describe 'ECVF foundation -- ConvertFrom-TPMOrderedJsonV1' {
 It 'round-trips a nested ordered structure preserving key order' {
  $fixture = New-ValidContractFixtureV1
  $json = ConvertTo-FixtureJsonV1 $fixture
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json $json
  $parsed.ContractId | Should -Be 'fixture-emu'
  @($parsed.Keys)[0] | Should -Be 'ContractId'
  @($parsed.Keys)[1] | Should -Be 'SchemaVersion'
  $parsed.VersionDetector.MatchedCommitMap[0].MatchState | Should -Be 'Matched'
 }

 It 'throws SCHEMA_INVALID prefixed message on malformed JSON' {
  { ConvertFrom-TPMOrderedJsonV1 -Json '{ not json' } | Should -Throw '*SCHEMA_INVALID*'
 }
}

Describe 'ECVF foundation -- Assert-TPMEmulatorContractV1 (valid path)' {
 It 'accepts a well-formed contract and returns the validated map' {
  $fixture = New-ValidContractFixtureV1
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  $result = Assert-TPMEmulatorContractV1 -Contract $parsed -ExpectedContractId 'fixture-emu'
  $result.ContractId | Should -Be 'fixture-emu'
 }
}

Describe 'ECVF foundation -- Assert-TPMEmulatorContractV1 (rejections)' {
 BeforeEach { $fixture = New-ValidContractFixtureV1 }

 It 'rejects a ContractId that does not match its directory name' {
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed -ExpectedContractId 'different-name' } | Should -Throw '*does not match its directory name*'
 }

 It 'rejects a SchemaVersion other than 1.0.0' {
  $fixture.SchemaVersion = '2.0.0'
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*SchemaVersion*'
 }

 It 'rejects a non-40-hex UpstreamPinnedCommit' {
  $fixture.UpstreamPinnedCommit = 'not-a-sha'
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*UpstreamPinnedCommit*'
 }

 It 'rejects an OwnershipBoundary claiming Owner=Emulator with WritePolicy=WriteDirectly' {
  $fixture.OwnershipBoundaries[0].WritePolicy = 'WriteDirectly'
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*may not carry WritePolicy*'
 }

 It 'rejects an OwnershipBoundary claiming Owner=Runtime with WritePolicy=WriteDirectly' {
  $fixture.OwnershipBoundaries[0].Owner = 'Runtime'
  $fixture.OwnershipBoundaries[0].WritePolicy = 'WriteDirectly'
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*may not carry WritePolicy*'
 }

 It 'rejects a dangling EvidenceReference on an OwnershipBoundary' {
  $fixture.OwnershipBoundaries[0].EvidenceReference = 'ev-does-not-exist'
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*references unknown EvidenceId*'
 }

 It 'rejects a dangling EvidenceReference on an EnvironmentCapability ObservableEvidence entry' {
  $fixture.EnvironmentCapabilities[0].ObservableEvidence = @('ev-does-not-exist')
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*references unknown EvidenceId*'
 }

 It 'rejects a duplicate EvidenceId' {
  $fixture.EvidenceReferences += [ordered]@{ EvidenceId = 'ev-1'; Type = 'SourceCitation'; Description = 'dup'; Locator = 'x'; Commit = ('a' * 40); Confidence = 'Theoretical'; RecordedDate = '2026-01-01' }
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*duplicate EvidenceId*'
 }

 It 'rejects a duplicate SettingPath across OwnershipBoundaries' {
  $fixture.OwnershipBoundaries[1].SettingPath = $fixture.OwnershipBoundaries[0].SettingPath
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*duplicate SettingPath*'
 }

 It 'rejects an unknown Owner enum value' {
  $fixture.OwnershipBoundaries[0].Owner = 'NotARealOwner'
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*Owner must be one of*'
 }

 It 'rejects duplicate Reliability ranks within one ObservableEvidence array' {
  $fixture.RuntimeCapabilities[0].ObservableEvidence[1].Reliability = 1
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*duplicate Reliability rank*'
 }

 It 'rejects a missing field (root field count mismatch)' {
  $fixture.Remove('DriftPolicy')
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  { Assert-TPMEmulatorContractV1 -Contract $parsed } | Should -Throw '*SCHEMA_INVALID*'
 }
}

Describe 'ECVF foundation -- Resolve-TPMEmulatorVersionMatchV1' {
 It 'returns Matched when the observed signal maps to the pinned commit' {
  $fixture = New-ValidContractFixtureV1
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  $contract = Assert-TPMEmulatorContractV1 -Contract $parsed
  (Resolve-TPMEmulatorVersionMatchV1 -Contract $contract -ObservedVersionString "Fixture v$('a' * 40)") | Should -Be 'Matched'
 }

 It 'returns Unknown for a signal the pattern does not match' {
  $fixture = New-ValidContractFixtureV1
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  $contract = Assert-TPMEmulatorContractV1 -Contract $parsed
  (Resolve-TPMEmulatorVersionMatchV1 -Contract $contract -ObservedVersionString 'Totally Unrelated Title') | Should -Be 'Unknown'
 }

 It 'returns Unknown for a null/empty observed signal' {
  $fixture = New-ValidContractFixtureV1
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  $contract = Assert-TPMEmulatorContractV1 -Contract $parsed
  (Resolve-TPMEmulatorVersionMatchV1 -Contract $contract -ObservedVersionString $null) | Should -Be 'Unknown'
 }

 It 'returns Diverged for a recognized-but-untrusted version string' {
  $fixture = New-ValidContractFixtureV1
  $fixture.VersionDetector.MatchedCommitMap += [ordered]@{ VersionString = ('b' * 40); Commit = ('b' * 40); MatchState = 'Diverged' }
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  $contract = Assert-TPMEmulatorContractV1 -Contract $parsed
  (Resolve-TPMEmulatorVersionMatchV1 -Contract $contract -ObservedVersionString "Fixture v$('b' * 40)") | Should -Be 'Diverged'
 }

 It 'returns Unsupported when ContractStatus is Deprecated, regardless of version match' {
  $fixture = New-ValidContractFixtureV1
  $fixture.ContractStatus = 'Deprecated'
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  $contract = Assert-TPMEmulatorContractV1 -Contract $parsed
  (Resolve-TPMEmulatorVersionMatchV1 -Contract $contract -ObservedVersionString "Fixture v$('a' * 40)") | Should -Be 'Unsupported'
 }
}

Describe 'ECVF foundation -- Assert-TPMOwnershipWriteAllowedV1' {
 BeforeEach {
  $fixture = New-ValidContractFixtureV1
  $parsed = ConvertFrom-TPMOrderedJsonV1 -Json (ConvertTo-FixtureJsonV1 $fixture)
  $script:contract = Assert-TPMEmulatorContractV1 -Contract $parsed
 }

 It 'throws OWNERSHIP_VIOLATION when writing to an Emulator-owned, NeverWrite setting' {
  { Assert-TPMOwnershipWriteAllowedV1 -Contract $script:contract -SettingPath 'Foo.Bar' } | Should -Throw '*OWNERSHIP_VIOLATION*'
 }

 It 'allows writing to a TPM-owned, WriteDirectly setting' {
  { Assert-TPMOwnershipWriteAllowedV1 -Contract $script:contract -SettingPath 'Foo.Baz' } | Should -Not -Throw
 }

 It 'throws OWNERSHIP_UNKNOWN for a SettingPath with no registered boundary' {
  { Assert-TPMOwnershipWriteAllowedV1 -Contract $script:contract -SettingPath 'Never.Registered' } | Should -Throw '*OWNERSHIP_UNKNOWN*'
 }
}

Describe 'ECVF foundation -- generic capability evaluators (fixture filesystem, no real emulator)' {
 BeforeEach { $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:root | Out-Null }

 It 'Resolve-TPMEnvironmentDataRootV1: falls back to DefaultValue when the source file is empty' {
  [IO.File]::WriteAllText((Join-Path $script:root 'portable.txt'), '')
  $resolver = [ordered]@{ Method = 'FileContentLiteral'; Source = 'portable.txt'; DefaultValue = 'TeknoParrot' }
  (Resolve-TPMEnvironmentDataRootV1 -Resolver $resolver -InstallDir $script:root) | Should -Be (Join-Path $script:root 'TeknoParrot')
 }

 It 'Resolve-TPMEnvironmentDataRootV1: uses literal non-empty content instead of the default' {
  [IO.File]::WriteAllText((Join-Path $script:root 'portable.txt'), 'CustomDataRoot')
  $resolver = [ordered]@{ Method = 'FileContentLiteral'; Source = 'portable.txt'; DefaultValue = 'TeknoParrot' }
  (Resolve-TPMEnvironmentDataRootV1 -Resolver $resolver -InstallDir $script:root) | Should -Be (Join-Path $script:root 'CustomDataRoot')
 }

 It 'Resolve-TPMEnvironmentDataRootV1: treats a missing source file the same as empty content' {
  $resolver = [ordered]@{ Method = 'FileContentLiteral'; Source = 'portable.txt'; DefaultValue = 'TeknoParrot' }
  (Resolve-TPMEnvironmentDataRootV1 -Resolver $resolver -InstallDir $script:root) | Should -Be (Join-Path $script:root 'TeknoParrot')
 }

 It 'Test-TPMEnvironmentInitializedV1: reports not-initialized when the required path is missing' {
  $verifier = [ordered]@{ RequiredPaths = @('inis/Fixture.ini'); RequiredMarkers = @(); ParseMethod = 'IniSections' }
  (Test-TPMEnvironmentInitializedV1 -Verifier $verifier -DataRoot $script:root).Initialized | Should -Be $false
 }

 It 'Test-TPMEnvironmentInitializedV1: reports initialized when required path and markers are present' {
  New-Item -ItemType Directory -Path (Join-Path $script:root 'inis') | Out-Null
  [IO.File]::WriteAllText((Join-Path $script:root 'inis/Fixture.ini'), "[UI]`r`n[USB1]`r`n[USB2]`r`n")
  $verifier = [ordered]@{ RequiredPaths = @('inis/Fixture.ini'); RequiredMarkers = @('[USB1]', '[USB2]'); ParseMethod = 'IniSections' }
  (Test-TPMEnvironmentInitializedV1 -Verifier $verifier -DataRoot $script:root).Initialized | Should -Be $true
 }

 It 'Test-TPMEnvironmentInitializedV1: reports not-initialized when a required marker is absent' {
  New-Item -ItemType Directory -Path (Join-Path $script:root 'inis') | Out-Null
  [IO.File]::WriteAllText((Join-Path $script:root 'inis/Fixture.ini'), "[UI]`r`n")
  $verifier = [ordered]@{ RequiredPaths = @('inis/Fixture.ini'); RequiredMarkers = @('[USB1]'); ParseMethod = 'IniSections' }
  (Test-TPMEnvironmentInitializedV1 -Verifier $verifier -DataRoot $script:root).Initialized | Should -Be $false
 }

 It 'Test-TPMRuntimeApplicabilityV1: matches when all predicate keys equal the context' {
  $predicate = [ordered]@{ GunGame = $true; EmulatorType = 'fixture' }
  (Test-TPMRuntimeApplicabilityV1 -Predicate $predicate -Context @{ GunGame = $true; EmulatorType = 'fixture'; Other = 'ignored' }) | Should -Be $true
 }

 It 'Test-TPMRuntimeApplicabilityV1: does not match when a predicate key differs' {
  $predicate = [ordered]@{ GunGame = $true }
  (Test-TPMRuntimeApplicabilityV1 -Predicate $predicate -Context @{ GunGame = $false }) | Should -Be $false
 }

 It 'Resolve-TPMObservableEvidenceV1: skips Unconfirmed entries and returns Matched=false with no source' {
  $evidence = @([ordered]@{ EvidenceSourceType = 'EmulatorLog'; Reliability = 1; Locator = 'anything'; Status = 'Unconfirmed' })
  $result = Resolve-TPMObservableEvidenceV1 -ObservableEvidence $evidence -Sources @{}
  $result.Matched | Should -Be $false
  $result.SourceUsed | Should -Be $null
 }

 It 'Resolve-TPMObservableEvidenceV1: uses the highest-reliability Confirmed EmulatorLog source when the pattern is present' {
  $logPath = Join-Path $script:root 'fixture.log'
  [IO.File]::WriteAllText($logPath, "some line`r`nACGAME: jvsmode=lightgun -> GunCon2 on USB1+USB2`r`n")
  $evidence = @(
   [ordered]@{ EvidenceSourceType = 'EmulatorLog'; Reliability = 1; Locator = 'jvsmode=lightgun -> GunCon2'; Status = 'Confirmed' }
   [ordered]@{ EvidenceSourceType = 'IniSnapshot'; Reliability = 2; Locator = 'Type = guncon2'; Status = 'Confirmed' }
  )
  $result = Resolve-TPMObservableEvidenceV1 -ObservableEvidence $evidence -Sources @{ LogPath = $logPath }
  $result.Matched | Should -Be $true
  $result.SourceUsed.EvidenceSourceType | Should -Be 'EmulatorLog'
 }
}

Describe 'ECVF foundation -- Test-TPMEmulatorPresentV1' {
 BeforeEach { $script:presRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:presRoot | Out-Null }

 It 'PathExists: true when the relative Source path exists under InstallDir' {
  [IO.File]::WriteAllText((Join-Path $script:presRoot 'fixture.exe'), '')
  $detector = [ordered]@{ Method = 'PathExists'; Source = 'fixture.exe'; Pattern = $null }
  (Test-TPMEmulatorPresentV1 -Detector $detector -InstallDir $script:presRoot) | Should -Be $true
 }

 It 'PathExists: false when the relative Source path does not exist' {
  $detector = [ordered]@{ Method = 'PathExists'; Source = 'missing.exe'; Pattern = $null }
  (Test-TPMEmulatorPresentV1 -Detector $detector -InstallDir $script:presRoot) | Should -Be $false
 }

 It 'an unimplemented Method returns false rather than throwing (never invasive by accident)' {
  $detector = [ordered]@{ Method = 'WindowTitleRegex'; Source = 'x'; Pattern = 'y' }
  (Test-TPMEmulatorPresentV1 -Detector $detector -InstallDir $script:presRoot) | Should -Be $false
 }
}

Describe 'ECVF foundation -- Get-TPMEmulatorContractObservationsV1 (shared by Shadow and Smoke)' {
 BeforeAll {
  function New-ContractFixtureOnDiskV1 {
   param([string]$ContractsRoot, [string]$ContractId, [hashtable]$Overrides = @{})
   $contract = New-ValidContractFixtureV1
   $contract.ContractId = $ContractId
   foreach ($key in $Overrides.Keys) { $contract[$key] = $Overrides[$key] }
   $dir = Join-Path $ContractsRoot $ContractId
   New-Item -ItemType Directory -Path $dir -Force | Out-Null
   [IO.File]::WriteAllText((Join-Path $dir 'contract.json'), (ConvertTo-FixtureJsonV1 $contract))
   [IO.File]::WriteAllText((Join-Path $dir 'evidence.md'), "# fixture`n`n### ev-1`nfixture citation`n")
   return $dir
  }
 }

 BeforeEach {
  $script:contractsRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '-contracts')
  New-Item -ItemType Directory -Path $script:contractsRoot | Out-Null
  $script:installRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N') + '-install')
  New-Item -ItemType Directory -Path $script:installRoot | Out-Null
 }

 It 'reports RegistryValid=false and empty Observations when the registry itself is broken' {
  $dir = New-ContractFixtureOnDiskV1 -ContractsRoot $script:contractsRoot -ContractId 'broken-emu'
  Remove-Item -LiteralPath (Join-Path $dir 'evidence.md') -Force
  $result = Get-TPMEmulatorContractObservationsV1 -InstallRoot $script:installRoot -ContractsRoot $script:contractsRoot
  $result.RegistryValid | Should -Be $false
  $result.Observations.Count | Should -Be 0
 }

 It 'Environment capability: Applicable=false and CapabilityPassed=false when the emulator is absent from InstallRoot' {
  New-ContractFixtureOnDiskV1 -ContractsRoot $script:contractsRoot -ContractId 'absent-emu' | Out-Null
  $result = Get-TPMEmulatorContractObservationsV1 -InstallRoot $script:installRoot -ContractsRoot $script:contractsRoot
  $result.RegistryValid | Should -Be $true
  $obs = $result.Observations | Where-Object { $_.CapabilityType -eq 'Environment' } | Select-Object -First 1
  $obs.Applicable | Should -Be $false
  $obs.CapabilityPassed | Should -Be $false
 }

 It 'Environment capability: Applicable=true and CapabilityPassed=true when present and already initialized' {
  New-ContractFixtureOnDiskV1 -ContractsRoot $script:contractsRoot -ContractId 'present-emu' | Out-Null
  [IO.File]::WriteAllText((Join-Path $script:installRoot 'fixture.exe'), '')
  New-Item -ItemType Directory -Path (Join-Path $script:installRoot 'Default\inis') -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $script:installRoot 'Default\inis\Fixture.ini'), "[Section]`r`n")
  $result = Get-TPMEmulatorContractObservationsV1 -InstallRoot $script:installRoot -ContractsRoot $script:contractsRoot
  $obs = $result.Observations | Where-Object { $_.CapabilityType -eq 'Environment' } | Select-Object -First 1
  $obs.Applicable | Should -Be $true
  $obs.CapabilityPassed | Should -Be $true
  $obs.DataRoot | Should -Be (Join-Path $script:installRoot 'Default')
 }

 It 'Environment capability: Applicable=true and CapabilityPassed=false when present but not yet initialized' {
  New-ContractFixtureOnDiskV1 -ContractsRoot $script:contractsRoot -ContractId 'uninit-emu' | Out-Null
  [IO.File]::WriteAllText((Join-Path $script:installRoot 'fixture.exe'), '')
  $result = Get-TPMEmulatorContractObservationsV1 -InstallRoot $script:installRoot -ContractsRoot $script:contractsRoot
  $obs = $result.Observations | Where-Object { $_.CapabilityType -eq 'Environment' } | Select-Object -First 1
  $obs.Applicable | Should -Be $true
  $obs.CapabilityPassed | Should -Be $false
  $obs.Reason | Should -Not -BeNullOrEmpty
 }

 It 'never invokes InitializationAction -- absence of the ini is reported, not repaired' {
  New-ContractFixtureOnDiskV1 -ContractsRoot $script:contractsRoot -ContractId 'never-repair-emu' | Out-Null
  [IO.File]::WriteAllText((Join-Path $script:installRoot 'fixture.exe'), '')
  Get-TPMEmulatorContractObservationsV1 -InstallRoot $script:installRoot -ContractsRoot $script:contractsRoot | Out-Null
  (Test-Path -LiteralPath (Join-Path $script:installRoot 'Default\inis\Fixture.ini')) | Should -Be $false
 }

 It 'RuntimeCapability: only applicable contexts produce an observation, each explicitly unresolved (no live launch performed)' {
  New-ContractFixtureOnDiskV1 -ContractsRoot $script:contractsRoot -ContractId 'runtime-emu' | Out-Null
  $result = Get-TPMEmulatorContractObservationsV1 -InstallRoot $script:installRoot -ContractsRoot $script:contractsRoot -RuntimeContexts @(@{ GunGame = $true }, @{ GunGame = $false })
  $runtimeObs = @($result.Observations | Where-Object { $_.CapabilityType -eq 'Runtime' })
  $runtimeObs.Count | Should -Be 1
  $runtimeObs[0].CapabilityPassed | Should -Be $false
  $runtimeObs[0].Reason | Should -Match 'live launch'
 }
}

Describe 'ECVF foundation -- Invoke-TPMEnvironmentInitializationActionV1 timeout enforcement (issue #173)' {
 BeforeEach { $script:root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N')); New-Item -ItemType Directory -Path $script:root | Out-Null }

 It 'returns Invoked=true with the real exit code when the process exits within the timeout' {
  [IO.File]::WriteAllText((Join-Path $script:root 'quick.cmd'), "@echo off`r`nexit /b 0`r`n")
  $action = [ordered]@{ Method = 'CliInvocation'; Command = 'quick.cmd'; Arguments = @(); ExpectedExitCodes = @(0); TimeoutSeconds = 15 }
  $result = Invoke-TPMEnvironmentInitializationActionV1 -Action $action -InstallDir $script:root
  $result.Invoked | Should -Be $true
  $result.ExitCode | Should -Be 0
 }

 It 'throws INITIALIZATION_ACTION_FAILED and does not hang when the exit code is unexpected' {
  [IO.File]::WriteAllText((Join-Path $script:root 'bad-exit.cmd'), "@echo off`r`nexit /b 7`r`n")
  $action = [ordered]@{ Method = 'CliInvocation'; Command = 'bad-exit.cmd'; Arguments = @(); ExpectedExitCodes = @(0); TimeoutSeconds = 15 }
  { Invoke-TPMEnvironmentInitializationActionV1 -Action $action -InstallDir $script:root } | Should -Throw '*INITIALIZATION_ACTION_FAILED*'
 }

 It 'kills the process and throws when it does not exit within TimeoutSeconds, instead of blocking forever' {
  # Copy powershell.exe directly as the tracked process (rather than a .cmd
  # wrapper that would launch it as an orphanable child) so Kill() actually
  # terminates the sleeping process immediately -- a cmd.exe wrapper killed
  # mid-wait leaves its own child process running on Windows (no POSIX
  # process-group semantics), which would otherwise hold a lock on
  # $TestDrive and fail Pester's own cleanup after this test.
  $processName = 'hang-' + ([guid]::NewGuid().ToString('N'))
  $hangExe = Join-Path $script:root ($processName + '.exe')
  Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -Destination $hangExe -Force
  $action = [ordered]@{ Method = 'CliInvocation'; Command = ($processName + '.exe'); Arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30'); ExpectedExitCodes = @(0); TimeoutSeconds = 1 }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
   { Invoke-TPMEnvironmentInitializationActionV1 -Action $action -InstallDir $script:root } | Should -Throw '*did not exit within*'
   @(Get-Process -Name $processName -ErrorAction SilentlyContinue).Count | Should -Be 0 -Because "the timed-out child must be confirmed terminated before the action fails"
  } finally {
   Get-Process -Name $processName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  }
  $sw.Stop()
  $sw.Elapsed.TotalSeconds | Should -BeLessThan 20 -Because "the call must return once the timeout elapses, not once the hung process would eventually exit on its own"
 }
}
