#Requires -Module Pester
# Issue: https://github.com/Jumpstile/teknoparrot-manager/issues/340
# Audit: <audit-folder>/ISSUES-AUDIT-RESULT.md (#340, PARTIAL).
# AST-extract only the target and its real helper dependency closure. Never load startup.
BeforeAll {
    $sourcePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'TeknoParrot-Manager.ps1'
    $tokens = $null; $errors = $null
    $script:issueAst = [System.Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors -join '; ') }
    $definitions = @{}
    foreach ($node in $script:issueAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if (-not $definitions.ContainsKey($node.Name)) { $definitions[$node.Name] = @() }
        $definitions[$node.Name] += $node
    }
    $external = @('Write-Log','Write-TpmCompactExtractionProgress','Write-Host','Get-DetectedGpuVendor','Suspend-TpmProgressLine','Resume-TpmProgressLine')
    $selected = @{}
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue('Invoke-LibraryHealthCheck')
    $pending.Enqueue('Show-LibraryHealthNextActions')
    $pending.Enqueue('Get-TpmHealthCheckExitCode')
    while ($pending.Count) {
        $name = $pending.Dequeue()
        if ($selected.ContainsKey($name) -or $external -contains $name) { continue }
        if (-not $definitions.ContainsKey($name)) { throw "Missing production helper: $name" }
        if (@($definitions[$name]).Count -ne 1) { throw "Ambiguous production helper: $name" }
        $node = $definitions[$name][0]; $selected[$name] = $node
        foreach ($command in $node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $called = $command.GetCommandName()
            if ($called -and $definitions.ContainsKey($called) -and $external -notcontains $called) { $pending.Enqueue($called) }
        }
    }
    $functionPath = Join-Path $TestDrive 'issue-340-functions.ps1'
    ($selected.Values | Sort-Object { $_.Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "

" | Set-Content -LiteralPath $functionPath -Encoding UTF8
    . $functionPath
    function Write-Log { param([string]$Message) [void]$script:messages.Add($Message) }
    function Write-TpmCompactExtractionProgress { param([Parameter(ValueFromRemainingArguments=$true)]$Arguments) }
    $script:messages = New-Object 'System.Collections.Generic.List[string]'
    # Hardware/service access is external. XML, discovery, field classifiers,
    # optional-coverage helpers and action selection remain production code.
    function Get-DetectedGpuVendor { [pscustomobject]@{ Vendor='NVIDIA'; Name='isolated fixture' } }
    function Suspend-TpmProgressLine {}
    function Resume-TpmProgressLine {}
}
Describe 'RC8 issue #340: incomplete inventory and stopped PostgreSQL are never all-clear' -Tag 'RC8-Issue' {
    BeforeEach {
        $script:healthRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:profiles = Join-Path $script:healthRoot 'UserProfiles'
        [void][System.IO.Directory]::CreateDirectory($script:profiles)
        [void][System.IO.Directory]::CreateDirectory((Join-Path $script:healthRoot 'GameProfiles'))
        $script:PostgresServiceName = 'RC8-test-service-must-never-exist'
        $script:PostgresBinDir = Join-Path $script:healthRoot 'pgsql'
        [void][System.IO.Directory]::CreateDirectory($script:PostgresBinDir)
        [System.IO.File]::WriteAllText((Join-Path $script:PostgresBinDir 'psql.exe'), 'inert marker, never execute')
        $script:FFBBlasterUnsupportedPlatforms = @('pcsx2x6')
        $script:FFBBlasterNamePattern = 'ffb.*blaster|blaster.*ffb'
        $script:hostLines = New-Object 'System.Collections.Generic.List[string]'
        $script:messages = New-Object 'System.Collections.Generic.List[string]'
        Mock Write-Host { [void]$script:hostLines.Add([string]($Object -join ' ')) }
        Mock Read-Host { 'B' }
        Mock Get-Service { [pscustomobject]@{ Status='Stopped' } }
        Mock Start-Service { throw 'Health Check must never start a service.' }
        Mock Stop-Service { throw 'Health Check must never stop a service.' }
    }
    It 'Regression accessible empty, missing, denied, partial inventory; missing/stopped/running service; no real service actions. (<Inventory>)' -ForEach @(
        @{ Inventory='empty'; Complete=$true },
        @{ Inventory='missing'; Complete=$false },
        @{ Inventory='denied'; Complete=$false },
        @{ Inventory='partial'; Complete=$false }
    ) {
        if ($Inventory -eq 'missing') { [System.IO.Directory]::Delete($script:profiles) }
        if ($Inventory -eq 'denied') {
            Mock Get-ChildItem { throw [System.UnauthorizedAccessException]::new('Injected profile enumeration denied') } -ParameterFilter { $LiteralPath -eq $script:profiles }
        }
        if ($Inventory -eq 'partial') {
            $profilePath = Join-Path $script:profiles 'READABLE.xml'
            [System.IO.File]::WriteAllText($profilePath, '<GameProfile><GamePath /></GameProfile>')
            $script:partialProfile = Get-Item -LiteralPath $profilePath
            Mock Get-ChildItem {
                $script:partialProfile
                Write-Error 'Injected enumeration failure after a readable entry' -ErrorId 'RC8PartialInventory' -Category PermissionDenied -ErrorAction Stop
            } -ParameterFilter { $LiteralPath -eq $script:profiles }
        }
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        $result.DiscoveryComplete | Should -Be $Complete
        if ($Complete) {
            $result.PostgresInventoryStatus | Should -BeExactly 'Complete'
            $result.Registered | Should -Be 0
            ($script:hostLines -join "
") | Should -Match 'No registered games were found'
        } else {
            $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
            $result.PostgresInventoryStatus | Should -BeExactly 'Error'
            @($result.PostgresInventoryErrors).Count | Should -BeGreaterThan 0
            @($result.PostgresNeeded).Count | Should -Be 0
            Show-LibraryHealthNextActions -Result $result | Should -BeExactly 'B'
            $report = $script:hostLines -join "
"
            $report | Should -Match 'could not read your list of games'
            $report | Should -Match 'No counts are shown'
            $report | Should -Match 'setup choices are hidden'
            $report | Should -Not -Match 'Everything looks fine|No PostgreSQL database profiles were found|\[P\] Set up|\[R\] Try automatic'
        }
        Should -Invoke Start-Service -Times 0 -Exactly
        Should -Invoke Stop-Service -Times 0 -Exactly
    }
    It 'Regression accessible empty, missing, denied, partial inventory; missing/stopped/running service; no real service actions. (<ServiceState>)' -ForEach @(
        @{ ServiceState='Stopped'; Exists=$true; Display='stopped' },
        @{ ServiceState='Running'; Exists=$true; Display='running' },
        @{ ServiceState='NotInstalled'; Exists=$false; Display='not available' }
    ) {
        $script:healthServiceState = $ServiceState
        Mock Get-Service {
            if ($script:healthServiceState -eq 'NotInstalled') {
                # Throw the record with the exact id real Get-Service reports ('NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.GetServiceCommand'),
                # which the product matches with 'NoServiceFoundForGivenName,*'. A plain throw keeps that id and does not depend on $PSCmdlet.
                $errorRecord = New-Object System.Management.Automation.ErrorRecord ([System.Exception]::new('No service found')), 'NoServiceFoundForGivenName,Microsoft.PowerShell.Commands.GetServiceCommand', ([System.Management.Automation.ErrorCategory]::ObjectNotFound), $script:PostgresServiceName
                throw $errorRecord
            }
            [pscustomobject]@{ Status=$script:healthServiceState }
        }
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        $result.PostgresServiceExists | Should -Be $Exists
        $result.PostgresServiceStatus | Should -BeExactly $ServiceState
        $serviceDetails = (@(Get-TpmLibraryHealthDetailBlocks -Result $result | ForEach-Object { $_.Lines }) -join "
")
        $serviceDetails | Should -Match ('Service state:\s+' + [regex]::Escape($Display))
        if ($ServiceState -ne 'Running') { ($script:hostLines -join "
") | Should -Not -Match 'installed and running|service state\s*:\s*running' }
        Should -Invoke Start-Service -Times 0 -Exactly
        Should -Invoke Stop-Service -Times 0 -Exactly
    }
    It 'Minimal fix explicit Complete/Error/Unknown inventory status; suppress all-clear/repair based on incomplete inventory; report service presence/running separately. (failed classifier)' {
        # Malformed XML makes the real reader/classifier fail; it is not mocked.
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'BAD.xml'), '<GameProfile>')
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        $result.DiscoveryComplete | Should -BeTrue
        $result.PostgresInventoryStatus | Should -BeExactly 'Unknown'
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        @($result.PostgresInventoryErrors).Count | Should -BeGreaterThan 0
        @($result.PostgresNeeded).Count | Should -Be 0
        Show-LibraryHealthNextActions -Result $result | Should -BeExactly 'B'
        ($script:hostLines -join "
") | Should -Match 'setup choices are hidden'
        ($script:hostLines -join "
") | Should -Not -Match 'Everything looks fine|\[P\] Set up'
    }
    It 'an unreadable profile is reported as unreadable and is not offered path repair' {
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'BAD.xml'), '<GameProfile>')
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        @($result.Broken).Count | Should -Be 0
        @($result.Unreadable) | Should -Contain 'BAD'
        Show-LibraryHealthNextActions -Result $result | Should -BeExactly 'B'
        $text = ($script:hostLines -join "`n")
        $text | Should -Match 'could not be read'
        $text | Should -Not -Match 'cannot be found at the saved path|\[R\] Try automatic'
    }
    It 'a PostgreSQL service that cannot be read is not OK: Could not check, no all-clear, ACTION_REQUIRED' {
        $fields = ('DbName', 'Path', 'Address', 'Port', 'User', 'Pass' | ForEach-Object { '<FieldInformation><CategoryName>Postgres</CategoryName><FieldName>' + $_ + '</FieldName><FieldValue>x</FieldValue></FieldInformation>' }) -join ''
        [System.IO.File]::WriteAllText((Join-Path $script:profiles 'PG.xml'), ('<GameProfile><GamePath>' + (Join-Path $script:healthRoot 'missing.exe') + '</GamePath><ConfigValues>' + $fields + '</ConfigValues></GameProfile>'))
        # Any failure other than "no such service" (for example the service manager refuses access) leaves the service unverified.
        Mock Get-Service { throw [System.InvalidOperationException]::new('Cannot open Service Control Manager') }
        $result = Invoke-LibraryHealthCheck -UserProfilesDir $script:profiles -TpRoot $script:healthRoot
        $result.PostgresConfigured | Should -Be 1
        $result.PostgresServiceExists | Should -BeNullOrEmpty
        $result.Outcome | Should -BeExactly 'ACTION_REQUIRED'
        Get-TpmHealthCheckExitCode -Result $result | Should -Be 2
        $text = ($script:hostLines -join "`n")
        $text | Should -Match 'PostgreSQL:?\s+Could not check'
        $text | Should -Not -Match 'Everything looks fine|PostgreSQL:?\s+OK'
    }
}
