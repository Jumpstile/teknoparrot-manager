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
            Line        = 311
            Extent      = 'Add-Type -AssemblyName System.IO.Compression.FileSystem'
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
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddScript'
            Line        = 2320
            # Built with explicit `r`n (rather than a literal here-string)
            # A single double-quoted string with explicit `r`n escapes
            # (restricted/data language mode permits escape sequences within
            # one string literal, but not the `+` concatenation operator
            # between multiple literals) so the entry matches the source
            # file's actual CRLF line endings exactly, regardless of this
            # .psd1 file's own line endings -- InjectionHunter's Extent.Text
            # is an exact substring of the source file, CRLF included.
            Extent      = "`$pesterPs.AddScript({`r`n        param(`$Config, `$OutputPath)`r`n        Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop`r`n        # Issue #136: Pester's own live per-Describe/per-test progress text`r`n        # is written to the Information stream (6), not the Error stream`r`n        # (2) -- confirmed by direct reproduction: with 2>&1, the file stayed`r`n        # completely empty for the whole run and only received the final`r`n        # PassThru result object's default-formatted text dump at the very`r`n        # end (useless during an actual hang, since that end is never`r`n        # reached). With 6>&1, the file receives each line live as Pester`r`n        # writes it. Also confirmed 6>&1 does not additionally echo to the`r`n        # live console (tested in a real foreground session, not just a`r`n        # background job) -- so Summary mode's ""keep the console quiet""`r`n        # intent still holds even though Verbosity is no longer 'None'.`r`n        Invoke-Pester -Configuration `$Config 6>&1 | Tee-Object -FilePath `$OutputPath`r`n    })"
            Disposition = 'FalsePositive'
            Reasoning   = 'The scriptblock argument is a fixed, hardcoded literal (not built from a string or any external input). AddScript with a compile-time literal poses no injection risk -- the risk this rule targets is a scriptblock constructed dynamically from untrusted data, which is not the case here.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 675
            Extent      = '$candidate.$name'
            Disposition = 'FalsePositive'
            Reasoning   = '$name is drawn only from the fixed, hardcoded $fields array a few lines above (literal property-name candidates such as "PassedCount"/"FailedCount"), never from external or attacker-controlled input. No untrusted value reaches the dynamic property name.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1351
            Extent      = 'Add-Type -AssemblyName System.Drawing'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1414
            Extent      = "Add-Type -Language CSharp -TypeDefinition `$tpmWindowInteropSource -ErrorAction Stop"
            Disposition = 'FalsePositive'
            Reasoning   = '$tpmWindowInteropSource is a fixed here-string literal defined a few lines above this call (a hardcoded Win32 interop P/Invoke declaration), not built from any variable or external input. No attacker-controlled source reaches Add-Type -TypeDefinition.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1442
            Extent      = 'Add-Type -AssemblyName System.Windows.Forms'
            Disposition = 'FalsePositive'
            Reasoning   = 'AssemblyName is a fixed string literal. No attacker-controlled input reaches Add-Type.'
        }
        @{
            File        = 'scripts/Invoke-TPM-RealInstanceSmoke.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1480
            Extent      = 'Add-Type -AssemblyName System.Drawing'
            Disposition = 'FalsePositive'
            Reasoning   = 'A second, separate occurrence of Add-Type with the same fixed AssemblyName literal elsewhere in this file (see line 1351 above). No attacker-controlled input reaches Add-Type.'
        }
    )
}
