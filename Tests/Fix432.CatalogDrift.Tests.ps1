#Requires -Module Pester

# scripts\Test-TpmCatalogDrift.ps1: every profile resolves to a decision (a recorded one, its family's default, or the generic default) with no
# error, and a new profile with an emulator type nobody has decided about is what makes the tool exit with 1.
# The facts files hold codes, emulator types and revisions only (testdata\teknoparrot-new-profiles-facts.json, testdata\real-game-registration-fixture.json),
# and the pinned snapshot lists the code of every profile it holds. What this CANNOT prove: that the real current catalog has no code outside these.

BeforeAll {
    $script:driftScript = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\Test-TpmCatalogDrift.ps1')).Path
    . $script:driftScript
    $script:driftDecisions = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\scripts\TpmGameSupportDecisions.json')) | ConvertFrom-Json
    $script:driftIndex = Get-TpmCatalogDecisionIndex -Decisions $script:driftDecisions
    $script:driftManifestPath = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\contracts\snapshots') -Filter 'snapshot-manifest.json' -File -Recurse)[0].FullName
}

Describe 'Every TeknoParrot profile resolves to a decision' {
    It 'gives every code of the pinned catalog, the real registration fixture and the new-profile facts a decision with no error' {
        $codes = New-Object System.Collections.Generic.List[object]
        $manifest = [System.IO.File]::ReadAllText($script:driftManifestPath) | ConvertFrom-Json
        foreach ($file in $manifest.Files) { if ($file.Root -eq 'GameProfiles') { [void]$codes.Add(@{ Code = [string]$file.ProfileCode; Emulator = '' }) } }
        foreach ($path in @('real-game-registration-fixture.json', 'teknoparrot-new-profiles-facts.json')) {
            $facts = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot ('..\testdata\' + $path))) | ConvertFrom-Json
            foreach ($profile in $facts.Profiles) { [void]$codes.Add(@{ Code = [string]$profile.Code; Emulator = [string]$profile.EmulatorType }) }
        }
        $codes.Count | Should -BeGreaterThan 1000
        $bad = New-Object System.Collections.Generic.List[string]
        foreach ($item in $codes) {
            try {
                $decision = Get-TpmCatalogDecision -Code $item.Code -EmulatorType $item.Emulator -Index $script:driftIndex
                if ($decision.Source -notin @('Recorded', 'FamilyDefault', 'GenericDefault') -or [string]::IsNullOrWhiteSpace($decision.Disposition)) { [void]$bad.Add($item.Code) }
            } catch { [void]$bad.Add($item.Code + ': ' + $_.Exception.Message) }
        }
        ($bad -join '; ') | Should -BeExactly ''
        # The new Golden Tee, IGS and IT Arcade Collection games (ElfLdr2) fit that loader's family default: nothing about them needs a person.
        # The ROM-set loaders (TeknoCoJag, TeknoPsikyo, TeknoTZ, TeknoVP and the other new ones) and the register-only loaders (TeknoDOS, TeknoRender0, TeknoTJC)
        # resolve to FamilyDefault, so nothing about them needs a person. The drift tool checks the real catalog itself; it is not pinned here.
        $newFacts = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\testdata\teknoparrot-new-profiles-facts.json')) | ConvertFrom-Json
        $elf = @($newFacts.Profiles | Where-Object { $_.EmulatorType -eq 'ElfLdr2' })
        $elf.Count | Should -Be 15
        foreach ($profile in $elf) { (Get-TpmCatalogDecision -Code $profile.Code -EmulatorType $profile.EmulatorType -Index $script:driftIndex).Source | Should -Not -Be 'GenericDefault' }
    }
}

Describe 'Test-TpmCatalogDrift.ps1' {
    It 'lists new profiles that fit a family and exits 0, and exits 1 for a new profile with an emulator type nobody decided about' {
        $folder = Join-Path $TestDrive 'drift-tp'
        $profiles = Join-Path $folder 'GameProfiles'
        New-Item -ItemType Directory -Path $profiles -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $profiles 'BrandNewKnownFamily.xml'), '<GameProfile><EmulatorType>TeknoParrot</EmulatorType><ExecutableName>a.exe</ExecutableName><GameProfileRevision>3</GameProfileRevision></GameProfile>')
        $report = Join-Path $TestDrive 'drift-report.md'
        $facts = Join-Path $TestDrive 'drift-facts.json'
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:driftScript -ProfilesPath $folder -ReportPath $report -WriteFactsPath $facts
        $LASTEXITCODE | Should -Be 0
        (Get-Content -LiteralPath $report -Raw) | Should -Match 'Nothing needs a decision'
        (Get-Content -LiteralPath $report -Raw) | Should -Match 'TeknoParrot: BrandNewKnownFamily'
        ([System.IO.File]::ReadAllText($facts) | ConvertFrom-Json).Profiles[0].GameProfileRevision | Should -Be '3'

        [System.IO.File]::WriteAllText((Join-Path $profiles 'BrandNewLoaderGame.xml'), '<GameProfile><EmulatorType>SomeLoaderFromTheFuture</EmulatorType><ExecutableName>b.exe</ExecutableName></GameProfile>')
        $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $script:driftScript -ProfilesPath $folder -ReportPath $report
        $LASTEXITCODE | Should -Be 1
        (Get-Content -LiteralPath $report -Raw) | Should -Match '## Needs a decision'
        (Get-Content -LiteralPath $report -Raw) | Should -Match 'BrandNewLoaderGame \| SomeLoaderFromTheFuture'
    }
}
