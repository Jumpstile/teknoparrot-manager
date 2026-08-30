@{
    # ADR-0155 Section 5.3 requires every InjectionHunter finding against the
    # complete production PowerShell inventory (Get-TPMProductionPowerShellInventoryV1)
    # to carry an individually traced disposition before it can be excluded
    # from UnresolvedFindingCount. This file is that record -- evidence, not
    # suppression: Test-TPMProductionInjectionHunterV1 still runs
    # InjectionHunter for real on every certification and only consults this
    # file to interpret findings it actually observed. A finding with no
    # matching entry here -- including a NEW finding this file has never
    # seen, even from the same rule -- is treated as unresolved and fails
    # Static Analysis eligibility until it is reviewed and a record is added.
    # A registry entry that no longer matches any current finding is
    # rejected as stale (Assert-TPMDispositionRegistryV1).
    #
    # Matching key: File (normalized repository-relative path) + RuleName +
    # Extent (the exact flagged source text) -- not Line. Line is recorded
    # only as the location at the time of review, for a human
    # cross-referencing this file against the source, and to disambiguate
    # (in file order) on the rare occasions the identical construct appears
    # more than once in the same file (see the two "$folderName -replace"
    # entries below) -- each such occurrence gets its own entry.
    #
    # Disposition values: 'Confirmed' (real issue, not yet fixed -- still
    # counts as unresolved), 'Mitigated' (real risk, addressed), or
    # 'FalsePositive' (the rule fired but no actual injection risk exists).
    # Only Mitigated and FalsePositive remove a finding from
    # UnresolvedFindingCount.

    SchemaVersion = 1

    Dispositions  = @(
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 313
            Extent      = 'Add-Type -AssemblyName System.IO.Compression'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal, not built from any variable or external input. No attacker-controlled value reaches Add-Type, so there is no assembly-load injection vector here.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 86
            Extent      = "`$display -replace '^v', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The regex pattern and replacement string are both fixed literals. Only the left-hand operand being searched is a variable, which this rule does not need to flag -- the injection risk this rule targets is an attacker-controlled pattern or replacement argument, neither of which is present.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 417
            Extent      = 'Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 1053
            Extent      = "`$s -replace '\(\d{4}\)', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 1130
            Extent      = "`$title -replace '\[[^\]]*\]', '' -replace '\([^\)]*\)', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Both chained -replace calls use fixed literal patterns and replacement strings; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 3925
            Extent      = 'Add-Type -AssemblyName System.Net.Http'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 6231
            Extent      = 'Add-Type -AssemblyName System.Security'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal used only to load the framework DPAPI implementation. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 6244
            Extent      = 'Add-Type -AssemblyName System.Security'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal used only to load the framework DPAPI implementation. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.ForeachObjectInjection'
            Line        = 6417
            Extent      = 'ForEach-Object { ConvertTo-PostgresProcessArgument -Value ([string]$_) }'
            Disposition = 'FalsePositive'
            Reasoning   = 'The pipeline iterates a fixed argument array and calls a fixed local quoting helper. It performs no dynamic member access or invocation; the values are only validated process arguments and a generated protected-state path.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 5736
            Extent      = "`$VersionText -replace '^v', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 5756
            Extent      = "`$VersionText -replace '^v', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'A second, separate occurrence of the identical construct elsewhere in this file (see line 5736 above). Pattern and replacement are fixed literals; only the searched value is a variable.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 5832
            Extent      = "`$firstLine.Trim() -replace '^#+\s*', '' -replace '^[-*]\s*', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Both chained -replace calls use fixed literal patterns and replacement strings; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 5888
            Extent      = 'Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 6274
            Extent      = "`$folderName -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 6913
            Extent      = "`$folderName -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'A second, separate occurrence of the identical construct elsewhere in this file (see line 6274 above). Pattern and replacement are fixed literals; only the searched value is a variable.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 7272
            Extent      = "`$dir.Name -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 7330
            Extent      = "`$RawZipName -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 7680
            Extent      = "`$name.Trim() -replace '(?i)^\s*(player\s*[12]|p[12])\s+', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 9383
            Extent      = "`$_.title -replace '[^a-zA-Z0-9]', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'scripts/Debug-TPM-MenuLayout.ps1'
            RuleName    = 'InjectionRisk.Create'
            Line        = 37
            Extent      = '[scriptblock]::Create($fn.Extent.Text)'
            Disposition = 'FalsePositive'
            Reasoning   = '$fn.Extent.Text is source text re-parsed out of TeknoParrot-Manager.ps1 itself (the AST of the same trusted, repository-controlled file this diagnostic ships alongside), not external or attacker-supplied input. Dot-sourcing every function definition it finds is the documented, deliberate design (see the comment immediately above this line in the source) so the diagnostic tracks the render pipeline automatically; it does not execute anything the production script itself does not already contain.'
        }
        @{
            File        = 'tools/Invoke-TpmAutoUpdate.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 53
            Extent      = "`$release.tag_name -replace '^v', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value (a GitHub release tag name) is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'tools/TpmAutoUpdate.Core.psm1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 51
            Extent      = "`$VersionText -replace '^v', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'tools/TpmAutoUpdate.Core.psm1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 296
            Extent      = 'Add-Type -AssemblyName System.Net.Http'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'tools/TpmAutoUpdate.Core.psm1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 521
            Extent      = 'Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'scripts/TPMCertification.Execution.psm1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 484
            Extent      = '$result.$name'
            Disposition = 'FalsePositive'
            Reasoning   = '$name is drawn only from the fixed, hardcoded numeric-field allowlist in Read-TPMPesterResultV1. The JSON result object is untrusted and validated fail-closed, but no external value can select the property name used by this access.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 664
            Extent      = '$candidate.$name'
            Disposition = 'FalsePositive'
            Reasoning   = '$name is drawn only from the fixed, hardcoded $fields array a few lines above (literal property-name candidates such as "PassedCount"/"FailedCount"), never from external or attacker-controlled input. No untrusted value reaches the dynamic property name. (ADR155-0309 round 3: a syntactically identical second occurrence, $summary.Duration = [string]$candidate.$name a few lines further down in the same function, over the fixed "Duration"/"Time" name set, does NOT trigger a raw InjectionRisk.StaticPropertyInjection finding from this scanner/rule version in either checkout compared this round -- confirmed empirically, not assumed. That occurrence is equally safe (same fixed-literal-only $name source) but is deliberately NOT given a disposition entry here, since this registry only records dispositions for findings the scanner actually emits; see ADR-0155-IMPLEMENTATION-CHECKLIST.md for the raw-evidence trail.)'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1195
            Extent      = 'Add-Type -AssemblyName System.Drawing'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1258
            Extent      = "Add-Type -Language CSharp -TypeDefinition `$tpmWindowInteropSource -ErrorAction Stop"
            Disposition = 'FalsePositive'
            Reasoning   = '$tpmWindowInteropSource is a fixed here-string literal defined a few lines above this call (a hardcoded Win32 interop P/Invoke declaration), not built from any variable or external input. No attacker-controlled source reaches Add-Type -TypeDefinition.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1286
            Extent      = 'Add-Type -AssemblyName System.Windows.Forms'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1383
            Extent      = 'Add-Type -AssemblyName System.Drawing'
            Disposition = 'FalsePositive'
            Reasoning   = 'Review round 2 (Luna Max) correction: Test-TPMInteractiveDisplayAvailable (added to prove, live, whether this session has a usable interactive display before the headless-screen-capture test attempts a real GDI+ capture) added a fourth textually-identical "Add-Type -AssemblyName System.Drawing" call, inserted before Save-TPMScreenCapture -- shifting every later line in this file and displacing the ordinal position this registry matches by (File+RuleName+Extent, consumed in ascending Line order). AssemblyName is a fixed string literal here exactly as in the other three occurrences; no attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1455
            Extent      = 'Add-Type -AssemblyName System.Drawing'
            Disposition = 'FalsePositive'
            Reasoning   = 'ADR155-0309 round 3 correction (Line renumbered in review round 2 after Test-TPMInteractiveDisplayAvailable was inserted earlier in this file -- match key is File+RuleName+Extent, not Line, so this renumbering does not change what this entry disposes): this reasoning previously claimed this was "a second, separate occurrence... see line 1169 [now 1185] above" -- that count was wrong. The source actually contains multiple textually-identical "Add-Type -AssemblyName System.Drawing" statements in this file (in Test-TPMPngStructure/PNG validation, in Save-TPMScreenCapture, in Save-TPMRenderedTextCapture, and -- as of review round 2 -- in Test-TPMInteractiveDisplayAvailable). Only three of these trigger a raw InjectionRisk.AddType finding from this scanner/rule version (confirmed empirically: the Save-TPMScreenCapture occurrence, immediately preceded by an Add-Type -AssemblyName System.Windows.Forms call in the same function, does not produce its own separate finding). This entry disposes the finding actually observed at this line (Save-TPMRenderedTextCapture''s occurrence); the Save-TPMScreenCapture occurrence is equally safe (same fixed-literal AssemblyName) but deliberately has no disposition entry of its own, since this registry only records dispositions for findings the scanner actually emits -- see ADR-0155-IMPLEMENTATION-CHECKLIST.md for the raw-evidence trail this correction is based on. No attacker-controlled input reaches Add-Type at any of these source occurrences.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 4167
            Extent      = "[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash(`$bytes))) -replace '-', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The SHA-256 bytes are converted to a string with fixed regex and replacement literals. The variable is only the searched hash byte sequence; no attacker-controlled pattern or replacement reaches -replace.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 4359
            Extent      = "[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash(`$bytes))) -replace '-', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'This is the same fixed-literal hash formatting operation in the preview reference reader. Only the computed byte sequence is variable; the regex and replacement are fixed and cannot carry injection syntax.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 4366
            Extent      = 'Add-Type -AssemblyName System.Drawing -ErrorAction Stop'
            Disposition = 'FalsePositive'
            Reasoning   = 'The assembly name is a fixed framework literal used to create the TPM-owned synthetic preview bitmap. No external or attacker-controlled value reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 4438
            Extent      = 'Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop'
            Disposition = 'FalsePositive'
            Reasoning   = 'The assembly name is a fixed framework literal used for the optional preview window, and the adjacent System.Drawing load is also fixed. No external or attacker-controlled value reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 4574
            Extent      = "`$Role.ToUpperInvariant() -replace 'PATH`$',''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The role name is selected from the fixed internal storage-role list, while both regex pattern and replacement are fixed literals. This normalizes a bounded property-name suffix and cannot perform regex or replacement injection.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 4764
            Extent      = "[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash(`$idBytes))) -replace '-', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The per-game ownership filename is derived from SHA-256 bytes using fixed regex and replacement literals. The variable is only the searched hash byte sequence; no attacker-controlled pattern or replacement reaches -replace.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 5040
            Extent      = "`$context.`$role"
            Disposition = 'FalsePositive'
            Reasoning   = 'The dynamic property name is bounded by the fixed internal list StagingPath, BackupPath, CachePath, TargetPath. The access only reads those four context fields; no untrusted value selects a property or invokes code.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 5041
            Extent      = "([string]`$role).ToUpperInvariant() -replace 'PATH`$',''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The role value comes from the same fixed four-entry storage-role list, and the regex pattern and replacement are fixed literals. This cannot carry attacker-controlled regex or replacement syntax.'
        }
    )
}
