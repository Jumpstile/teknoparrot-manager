@{
    # ADR-0155 Section 5.3 requires every InjectionHunter finding against the
    # ADR-scoped production script (TeknoParrot-Manager.ps1) to carry an
    # individually traced disposition before it can be excluded from
    # UnresolvedFindingCount. This file is that record -- evidence, not
    # suppression: New-TPMProductionFactRecordsFromLegacyV1 still runs
    # InjectionHunter for real on every certification and only consults this
    # file to interpret findings it actually observed. A finding with no
    # matching entry here -- including a NEW finding this file has never seen,
    # even from the same rule -- is treated as unresolved and fails Static
    # Analysis eligibility until it is reviewed and a record is added.
    #
    # Each entry's review, method, and full reasoning:
    # https://github.com/Jumpstile/teknoparrot-manager/issues/171
    #
    # Matching key: RuleName + Extent (the exact flagged source text), not
    # Line -- line numbers drift with unrelated edits elsewhere in the file.
    # Line is recorded only as the location at the time of review, for a
    # human cross-referencing this file against the source.
    #
    # Disposition values: 'Confirmed' (real issue, not yet fixed -- still
    # counts as unresolved), 'Mitigated' (real risk, addressed), or
    # 'FalsePositive' (the rule fired but no actual injection risk exists).
    # Only Mitigated and FalsePositive remove a finding from
    # UnresolvedFindingCount, per ADR Section 5.3.

    SchemaVersion = 1
    Issue         = 171

    Dispositions  = @(
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 86
            Extent      = @'
$display -replace '^v', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Measure-UnsafeEscaping's own regex is backtick-doublequote-or-two-single-quotes.
It fires on the literal two-single-quote empty-string replacement argument
text, not on any actual quote-doubling escape construct. Verified by
evaluating the rule's regex directly against this line; it matches solely
because the replacement argument is an empty string literal. No command or
parameter name is built from the replaced value.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 1053
            Extent      = @'
$s -replace '\(\d{4}\)', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same rule and same false-positive class as line 86 -- ordinary regex cleanup
with an empty-string replacement, not escaping for dynamic command
construction.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 1130
            Extent      = @'
$title -replace '\[[^\]]*\]', '' -replace '\([^\)]*\)', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class -- both -replace calls use an empty-string
replacement argument. No dynamic command or parameter construction.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 5736
            Extent      = @'
$VersionText -replace '^v', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 5756
            Extent      = @'
$VersionText -replace '^v', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86. Distinct call site from line 5736 (same
pattern, different function) -- reviewed independently, not assumed covered
by that entry.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 5832
            Extent      = @'
$firstLine.Trim() -replace '^#+\s*', '' -replace '^[-*]\s*', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class -- both -replace calls use an empty-string
replacement argument.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 6274
            Extent      = @'
$folderName -replace '\.(teknoparrot|parrot|game)$', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 6913
            Extent      = @'
$folderName -replace '\.(teknoparrot|parrot|game)$', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86. Distinct call site from line 6274 (same
pattern, different function) -- reviewed independently, not assumed covered
by that entry.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 7272
            Extent      = @'
$dir.Name -replace '\.(teknoparrot|parrot|game)$', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 7330
            Extent      = @'
$RawZipName -replace '\.(teknoparrot|parrot|game)$', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 7680
            Extent      = @'
$name.Trim() -replace '(?i)^\s*(player\s*[12]|p[12])\s+', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86.
'@
        }
        @{
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 9383
            Extent      = @'
$_.title -replace '[^a-zA-Z0-9]', ''
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 86.
'@
        }
        @{
            RuleName    = 'InjectionRisk.AddType'
            Line        = 311
            Extent      = @'
Add-Type -AssemblyName System.IO.Compression.FileSystem
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Measure-AddType fires on any Add-Type invocation unconditionally, regardless
of whether it loads a well-known assembly by name or compiles dynamic
TypeDefinition source. This call uses -AssemblyName with a static, hardcoded,
well-known .NET Framework assembly name -- no -TypeDefinition, no
interpolation, no variable content at all.
'@
        }
        @{
            RuleName    = 'InjectionRisk.AddType'
            Line        = 417
            Extent      = @'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 311 -- static -AssemblyName, no dynamic
content.
'@
        }
        @{
            RuleName    = 'InjectionRisk.AddType'
            Line        = 3925
            Extent      = @'
Add-Type -AssemblyName System.Net.Http
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 311 -- static -AssemblyName, no dynamic
content.
'@
        }
        @{
            RuleName    = 'InjectionRisk.AddType'
            Line        = 5888
            Extent      = @'
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
'@
            Disposition = 'FalsePositive'
            Reasoning   = @'
Same false-positive class as line 311 -- static -AssemblyName, no dynamic
content.
'@
        }
    )
}
