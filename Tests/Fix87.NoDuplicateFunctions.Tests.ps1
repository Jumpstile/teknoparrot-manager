#Requires -Module Pester

# FIX87: permanent guard. PowerShell keeps only the LAST definition of a function name, so a second definition
# silently replaces the first and every caller of the first signature breaks or changes. (FIX81 and FIX83 both
# defined Format-TpmNameList; the FIX83 copy won and the FIX81 callers passed a parameter it did not have.)
# The guard parses TeknoParrot-Manager.ps1, every scripts\*.ps1 and (FIX131 N7) every scripts\*.psm1 module with the PowerShell
# parser (nothing is run) and fails when one function name is defined twice, in one file or in two files, unless the name is on
# the allow-list below with the reason it is allowed.

BeforeAll {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:F87Files = @(Join-Path $root 'TeknoParrot-Manager.ps1') + @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File | Where-Object { $_.Extension -ieq '.ps1' -or $_.Extension -ieq '.psm1' } | Sort-Object -Property Name | ForEach-Object { $_.FullName })
    $files = $script:F87Files
    $script:F87Definitions = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $files) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw ('FIX87 guard could not parse ' + $file) }
        foreach ($definition in @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
            [void]$script:F87Definitions.Add([pscustomobject]@{ Name = [string]$definition.Name; File = [System.IO.Path]::GetFileName($file); Line = [int]$definition.Extent.StartLineNumber })
        }
    }

    # Intentional duplicates: name -> why it is allowed and EXACTLY where it may be defined (file name = number of definitions).
    # An extra definition of an allowed name, in the same file or in another one, is not allowed. Every entry must still be a real
    # duplicate with exactly this layout (checked below), so the list cannot go stale. Names are compared without regard to case, as PowerShell does.
    $script:F87Allowed = @{
        'Resolve-Pcsx2Directory'       = @{ Layout = 'Resolve-Pcsx2Directory.ps1=1;TeknoParrot-Manager.ps1=1'; Reason = 'The certification scripts dot-source scripts\Resolve-Pcsx2Directory.ps1 and never load TeknoParrot-Manager.ps1, so the two copies are never in one session.' }
        'Get-TpmProfileMap'            = @{ Layout = 'Test-TpmReleaseCatalogSnapshot.ps1=1;TpmReleaseCatalogSnapshot.Common.ps1=1'; Reason = 'TpmReleaseCatalogSnapshot.Common.ps1 is dot-sourced by the snapshot builders; Test-TpmReleaseCatalogSnapshot.ps1 is a separate stand-alone verifier that does not load it.' }
        'Get-TpmSemanticHash'          = @{ Layout = 'Test-TpmReleaseCatalogSnapshot.ps1=1;TpmReleaseCatalogSnapshot.Common.ps1=1'; Reason = 'TpmReleaseCatalogSnapshot.Common.ps1 is dot-sourced by the snapshot builders; Test-TpmReleaseCatalogSnapshot.ps1 is a separate stand-alone verifier that does not load it.' }
        'Get-TpmSnapshotSha256Bytes'   = @{ Layout = 'Test-TpmReleaseCatalogSnapshot.ps1=1;TpmReleaseCatalogSnapshot.Common.ps1=1'; Reason = 'TpmReleaseCatalogSnapshot.Common.ps1 is dot-sourced by the snapshot builders; Test-TpmReleaseCatalogSnapshot.ps1 is a separate stand-alone verifier that does not load it.' }
        'Get-TpmSnapshotSha256File'    = @{ Layout = 'Test-TpmReleaseCatalogSnapshot.ps1=1;TpmReleaseCatalogSnapshot.Common.ps1=1'; Reason = 'TpmReleaseCatalogSnapshot.Common.ps1 is dot-sourced by the snapshot builders; Test-TpmReleaseCatalogSnapshot.ps1 is a separate stand-alone verifier that does not load it.' }
    }

    # The names that are defined more than once, each with where: "Name: File:Line, File:Line".
    function Get-F87DuplicateGroups {
        param([object[]]$Definitions)
        return @($Definitions | Group-Object -Property Name | Where-Object { $_.Count -gt 1 })
    }
    function Get-F87GroupText {
        param($Group)
        return ('{0}: {1}' -f $Group.Name, ((@($Group.Group) | ForEach-Object { '{0}:{1}' -f $_.File, $_.Line }) -join ', '))
    }
    # "File=count;File=count", files in a fixed (ordinal, case-insensitive) order: the exact places a name is defined.
    function Get-F87GroupLayout {
        param($Group)
        $perFile = @(@($Group.Group) | Group-Object -Property File | Sort-Object -Property Name)
        return (($perFile | ForEach-Object { '{0}={1}' -f $_.Name, $_.Count }) -join ';')
    }
    # A group is allowed only when its name is on the list AND it is defined in exactly the listed files, the listed number of times.
    function Test-F87GroupAllowed {
        param($Group, [hashtable]$Allowed)
        if (-not $Allowed.ContainsKey($Group.Name)) { return $false }
        return ((Get-F87GroupLayout -Group $Group) -ceq [string]$Allowed[$Group.Name].Layout)
    }
}

Describe 'FIX87 no function is defined twice' {
    It 'defines every function name once, except the allow-listed names in their listed places' {
        # Mutation: define any function a second time in TeknoParrot-Manager.ps1 or a scripts\*.ps1 file (for example paste Format-TpmNameList again, or add a third Resolve-Pcsx2Directory in an allowed file) -> it is listed here.
        $unexpected = @(Get-F87DuplicateGroups -Definitions @($script:F87Definitions) | Where-Object { -not (Test-F87GroupAllowed -Group $_ -Allowed $script:F87Allowed) } | ForEach-Object { Get-F87GroupText -Group $_ })
        $unexpected -join [Environment]::NewLine | Should -BeExactly '' -Because 'a function name defined twice keeps only the last definition'
    }

    It 'scans every scripts module (psm1) as well as every scripts script (ps1)' {
        # FIX131 N7. Mutation: put the Filter '*.ps1' scan back (modules are no longer read) -> a module is missing here, and a function pasted
        # into a module and into the main script would pass the guard unseen.
        $scriptsDirectory = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'scripts'
        $scanned = @($script:F87Files | ForEach-Object { [System.IO.Path]::GetFileName($_) })
        $modules = @(Get-ChildItem -LiteralPath $scriptsDirectory -File | Where-Object { $_.Extension -ieq '.psm1' } | ForEach-Object { $_.Name })
        $modules.Count | Should -BeGreaterThan 0
        @($modules | Where-Object { $scanned -cnotcontains $_ }) | Should -BeNullOrEmpty
        foreach ($module in $modules) {
            @($script:F87Definitions | Where-Object { $_.File -ceq $module }).Count | Should -BeGreaterThan 0 -Because ($module + ' defines functions, so the guard must have read them')
        }
    }

    It 'reports a function that a module and the main script both define' {
        # FIX131 N7. Mutation: compare names only inside one file, or drop modules from the scan -> the planted module copy is not reported.
        $planted = @(
            [pscustomobject]@{ Name = 'Get-PlantedHelper'; File = 'TeknoParrot-Manager.ps1'; Line = 100 },
            [pscustomobject]@{ Name = 'Get-PlantedHelper'; File = 'Planted.Core.psm1'; Line = 12 }
        )
        $found = @(Get-F87DuplicateGroups -Definitions $planted)
        $found.Count | Should -Be 1
        (Get-F87GroupText -Group $found[0]) | Should -BeExactly 'Get-PlantedHelper: TeknoParrot-Manager.ps1:100, Planted.Core.psm1:12'
        Test-F87GroupAllowed -Group $found[0] -Allowed $script:F87Allowed | Should -BeFalse
    }

    It 'finds a duplicate in the definitions it is given (the guard can fail)' {
        # Mutation: make the duplicate finder ignore the name, or require more than two definitions -> the planted duplicate is not found.
        $planted = @(
            [pscustomobject]@{ Name = 'Format-Planted'; File = 'a.ps1'; Line = 1 },
            [pscustomobject]@{ Name = 'format-planted'; File = 'a.ps1'; Line = 9 },
            [pscustomobject]@{ Name = 'Format-Single'; File = 'a.ps1'; Line = 20 }
        )
        $found = @(Get-F87DuplicateGroups -Definitions $planted)
        $found.Count | Should -Be 1
        (Get-F87GroupText -Group $found[0]) | Should -BeExactly 'Format-Planted: a.ps1:1, a.ps1:9'
    }

    It 'does not allow an extra definition of an allow-listed name' {
        # Mutation: allow a name by its name only (ignore the file and count layout) -> an extra same-file or other-file copy of an allowed name passes.
        $allowed = @{ 'Get-Allowed' = @{ Layout = 'a.ps1=1;b.ps1=1'; Reason = 'planted' } }
        $exact = @(
            [pscustomobject]@{ Name = 'Get-Allowed'; File = 'a.ps1'; Line = 1 },
            [pscustomobject]@{ Name = 'Get-Allowed'; File = 'b.ps1'; Line = 2 }
        )
        $extraSameFile = $exact + @([pscustomobject]@{ Name = 'Get-Allowed'; File = 'a.ps1'; Line = 30 })
        $extraOtherFile = $exact + @([pscustomobject]@{ Name = 'get-allowed'; File = 'c.ps1'; Line = 5 })
        Test-F87GroupAllowed -Group (Get-F87DuplicateGroups -Definitions $exact)[0] -Allowed $allowed | Should -BeTrue
        Test-F87GroupAllowed -Group (Get-F87DuplicateGroups -Definitions $extraSameFile)[0] -Allowed $allowed | Should -BeFalse
        Test-F87GroupAllowed -Group (Get-F87DuplicateGroups -Definitions $extraOtherFile)[0] -Allowed $allowed | Should -BeFalse
    }

    It 'keeps every allow-list entry real and explained' {
        # Mutation: leave an allow-list entry behind after its duplicate was removed or moved, or give it no reason -> it is listed here.
        $groups = @(Get-F87DuplicateGroups -Definitions @($script:F87Definitions))
        $problems = New-Object System.Collections.Generic.List[string]
        foreach ($name in @($script:F87Allowed.Keys)) {
            $group = @($groups | Where-Object { $_.Name -ieq $name })
            if ($group.Count -eq 0) { [void]$problems.Add($name + ': no longer defined twice, remove it from the allow-list') }
            elseif (-not (Test-F87GroupAllowed -Group $group[0] -Allowed $script:F87Allowed)) { [void]$problems.Add($name + ': is no longer defined exactly as listed (' + (Get-F87GroupLayout -Group $group[0]) + ')') }
            if ([string]::IsNullOrWhiteSpace([string]$script:F87Allowed[$name].Reason)) { [void]$problems.Add($name + ': no reason given') }
        }
        $problems -join [Environment]::NewLine | Should -BeExactly ''
    }
}
