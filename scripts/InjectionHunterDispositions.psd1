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
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 21360
            Extent      = "`$VersionText -replace '^v', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'Pattern and replacement are fixed literals; only the searched value is a variable. Not a regex/replacement injection vector.'
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
            File        = 'scripts/Debug-TPM-MenuLayout.ps1'
            RuleName    = 'InjectionRisk.Create'
            Line        = 37
            Extent      = '[scriptblock]::Create($fn.Extent.Text)'
            Disposition = 'FalsePositive'
            Reasoning   = '$fn.Extent.Text is source text re-parsed out of TeknoParrot-Manager.ps1 itself (the AST of the same trusted, repository-controlled file this diagnostic ships alongside), not external or attacker-supplied input. Dot-sourcing every function definition it finds is the documented, deliberate design (see the comment immediately above this line in the source) so the diagnostic tracks the render pipeline automatically; it does not execute anything the production script itself does not already contain.'
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
            File        = 'tools/TpmAutoUpdate.Core.psm1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 939
            Extent      = 'Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue'
            Disposition = 'FalsePositive'
            Reasoning   = 'A second, separate occurrence of the identical construct (see the Line 521 entry above, review-time line of the first occurrence, now in Expand-TpmReleaseZipEntry; entries sharing a match key are matched in ascending Line order), added by FIX16A in Test-TpmUpdatePackageIsSingleScript, which refuses a multi-file release package before anything is extracted. AssemblyName is a fixed string literal of a .NET framework assembly; no -TypeDefinition, -MemberDefinition or -Path source is compiled, and the downloaded ZIP path is passed only to ZipFile::OpenRead, never to Add-Type. No variable, path, or archive content reaches Add-Type.'
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
            Line        = 4764
            Extent      = "[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash(`$idBytes))) -replace '-', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The per-game ownership filename is derived from SHA-256 bytes using fixed regex and replacement literals. The variable is only the searched hash byte sequence; no attacker-controlled pattern or replacement reaches -replace.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 4724
            Extent      = 'Add-Type -AssemblyName System.Drawing -ErrorAction Stop'
            Disposition = 'FalsePositive'
            Reasoning   = 'The assembly name is a fixed framework literal used to decode the bundled TPM-owned preview reference. No external or attacker-controlled value reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 5248
            Extent      = 'Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop'
            Disposition = 'FalsePositive'
            Reasoning   = 'The assembly name is a fixed framework literal used for the optional TPM-owned preview gallery. No external or attacker-controlled value reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 469
            Extent      = "`$Layout.`$bucket"
            Disposition = 'FalsePositive'
            Reasoning   = 'The bucket value is selected only from fixed internal category literals (Assets, State, Logs, Reports, Backups, Cache), and Layout is TPM-owned migration state. No untrusted input selects a property.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 6258
            Extent      = "[string]`$Manifest.EffectId -replace '^ReShadeProfile\.', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The regex pattern and replacement are fixed literals; the variable is only the searched value. No attacker-controlled pattern or replacement is evaluated.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 14926
            Extent      = "[string]`$ScanRecord.Manifest.EffectId -replace '^ReShadeProfile\.', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Remove-TpmReShadeOwnedDeployment the regex pattern and replacement are fixed literals; the variable is only the searched value, the effect id read from the ownership file TeknoParrot Manager wrote. It only builds the look name stored in the undo copy. No attacker-controlled pattern or replacement is evaluated.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 15339
            Extent      = "[string]`$Manifest.EffectId -replace '^ReShadeProfile\.', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'A second, separate occurrence of the identical construct (see the Line 6258 entry above; matched in ascending Line order), in Get-TpmReShadeSetupUndoRequest. The regex pattern and replacement are fixed literals; the variable is only the searched value, the effect id of the ownership file TeknoParrot Manager wrote. It only builds the look name stored in the undo copy.'
        }
        @{
            File        = 'scripts/TpmRequiredPatchEngine.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 1137
            Extent      = 'Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop'
            Disposition = 'FalsePositive'
            Reasoning   = 'The framework assembly name is a fixed literal required to read user-supplied ZIP members under Windows PowerShell 5.1. No variable, path, or archive content reaches Add-Type; member selection, size, and SHA256 are independently pinned by the recipe.'
        }
        @{
            File        = 'scripts/TpmRequiredPatchEngine.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 1576
            Extent      = "`$BuildName -replace '\s*[\(\[].*$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'The regex pattern and replacement are fixed literals; only the searched value, a build name from the recipe, is a variable. The result is only text shown to the user. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 12696
            Extent      = "`$Before.`$name"
            Disposition = 'FalsePositive'
            Reasoning   = 'The property name is selected from a fixed literal console-geometry allowlist, and Before/After are TPM-generated geometry snapshots. No profile or other untrusted value chooses the accessed property.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 12834
            Extent      = "`$geometry.`$name"
            Disposition = 'FalsePositive'
            Reasoning   = 'The property name is selected from a fixed literal console-geometry allowlist, and geometry/renderedGeometry are TPM-generated snapshots. No profile or other untrusted value chooses the accessed property.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 7240
            Extent      = 'Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop'
            Disposition = 'FalsePositive'
            Reasoning   = 'In Invoke-TpmCps3SupplementaryInstall the framework assembly name is a fixed literal needed before ZipFile::OpenRead reads the user-selected CPS3 archive. The archive path is passed only to OpenRead, never to Add-Type; no variable, path, or archive content reaches Add-Type.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 7468
            Extent      = '$result.($problem[0])'
            Disposition = 'FalsePositive'
            Reasoning   = 'In Invoke-TpmCps3SupplementaryOffer the property name is $problem[0], taken only from the fixed literal pair list on the line above (Missing, Extra, Unsafe, Ambiguous, Mismatched). $result is the TPM-generated CPS3 install result, and the access only reads a count for display; no external value selects the property.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 17299
            Extent      = '$marker.$field'
            Disposition = 'FalsePositive'
            Reasoning   = 'In Read-PostgresTrustRuleMarkerFile $field is drawn only from the fixed literal list Guid, HbaPath, BackupHbaPath, OriginalSha256 on the line above. The marker JSON is read after reparse-point and ACL checks and is still validated fail-closed, but its content cannot choose which property is read; the access is a read-only presence check.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 28268
            Extent      = '$Object.$Name'
            Disposition = 'FalsePositive'
            Reasoning   = 'Set-TpmLedgerField assigns a note property on a TPM-owned registration-ledger object. Every call site in this file passes -Name as a fixed string literal (EvidenceStatus, InterruptedUtc, Reason, Extraction, TargetFolder, Rollback, Transaction, EvidenceStopped); ledger or profile content only ever reaches -Value, never the property name, and no code is invoked.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 28661
            Extent      = "([string]`$unit.Folder) -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Close-TpmRegistrationLedgerOperations the regex pattern and replacement are fixed literals; the ledger unit folder name is only the searched value, used to build a comparison key. No attacker-controlled pattern or replacement reaches -replace.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 28935
            Extent      = "([string]`$_) -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'In ConvertTo-TpmRegistrationResult the regex pattern and replacement are fixed literals; each unattempted folder name is only the searched value, used to build a comparison key. No attacker-controlled pattern or replacement reaches -replace.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 28946
            Extent      = '$Legacy.$name'
            Disposition = 'FalsePositive'
            Reasoning   = 'In ConvertTo-TpmRegistrationResult $name is drawn only from the fixed literal list Registered, Already, Ambiguous, Unmatched on the line above, and $Legacy is the TPM-generated registration result. The access only reads those four fields to copy them onto the transaction result; no external value selects the property.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 29882
            Extent      = "`$candidateFolder -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Register-GamesLegacy the regex pattern and replacement are fixed literals; the install-folder name is only the searched value, used to build a matching key for unattempted folders. No attacker-controlled pattern or replacement reaches -replace.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 29962
            Extent      = "`$folderName -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'A third, separate occurrence of the identical construct (see the Line 6274 and 6913 entries above; matched in ascending Line order), in Invoke-ManualRegistrationChoices after a verified manual mapping. Pattern and replacement are fixed literals; only the install-folder name being searched is a variable.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 41055
            Extent      = "`$folderName -replace '\.(teknoparrot|parrot|game)$', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'A fourth, separate occurrence of the identical construct (see the Line 6274, 6913, and 29962 entries above; matched in ascending Line order), in the duplicate-registration switch loop after a verified mapping. Pattern and replacement are fixed literals; only the install-folder name being searched is a variable.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 21154
            Extent      = "`$originalHash -replace '-', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Save-TpmInvalidAutoSyncStateCopy (added by FIX16A) the regex pattern and replacement are fixed literals. $originalHash is the SHA-256 of the sync-state bytes this function read itself, formatted locally by [System.BitConverter]::ToString as hyphen-separated hex; removing the hyphens only lets it be compared with the Get-FileHash value of the same file, and that comparison only decides whether the preserved copy is accepted or the function throws. No attacker-controlled pattern or replacement reaches -replace, and the result never builds a command, path, parameter name or script text.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 28616
            Extent      = 'Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue'
            Disposition = 'FalsePositive'
            Reasoning   = 'A second, separate occurrence of the identical construct (see the Line 5888 entry above, review-time line of the first occurrence, now in Expand-ManagerUpdateAsset; entries sharing a match key are matched in ascending Line order), added by FIX16A in Test-ManagerUpdatePackageIsSingleScript, which inspects a release package before anything is extracted. AssemblyName is a fixed string literal of a .NET framework assembly; no -TypeDefinition, -MemberDefinition or -Path source is compiled, and the downloaded ZIP path is passed only to ZipFile::OpenRead, never to Add-Type. No variable, path, or archive content reaches Add-Type.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 275
            Extent      = "Add-Type -Namespace TpmProgressNative -Name ConsoleFont -ErrorAction Stop -MemberDefinition @'`r`n[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]`r`npublic struct CONSOLE_FONT_INFOEX {`r`n    public uint cbSize;`r`n    public uint nFont;`r`n    public short dwFontSizeX;`r`n    public short dwFontSizeY;`r`n    public int FontFamily;`r`n    public int FontWeight;`r`n    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FaceName;`r`n}`r`n[DllImport(`"kernel32.dll`", SetLastError = true)]`r`npublic static extern IntPtr GetStdHandle(int nStdHandle);`r`n[DllImport(`"kernel32.dll`", SetLastError = true, CharSet = CharSet.Unicode)]`r`npublic static extern bool GetCurrentConsoleFontEx(IntPtr hConsoleOutput, bool bMaximumWindow, ref CONSOLE_FONT_INFOEX lpConsoleCurrentFontEx);`r`n[DllImport(`"kernel32.dll`", SetLastError = true)]`r`npublic static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);`r`n[DllImport(`"kernel32.dll`", SetLastError = true, CharSet = CharSet.Unicode)]`r`npublic static extern bool WriteConsoleW(IntPtr hConsoleOutput, string lpBuffer, uint nNumberOfCharsToWrite, out uint lpNumberOfCharsWritten, IntPtr lpReserved);`r`npublic static bool IsConsoleOutput() {`r`n    uint mode;`r`n    return GetConsoleMode(GetStdHandle(-11), out mode);`r`n}`r`npublic static bool WriteText(string text) {`r`n    if (string.IsNullOrEmpty(text)) { return true; }`r`n    uint written;`r`n    return WriteConsoleW(GetStdHandle(-11), text, (uint)text.Length, out written, IntPtr.Zero);`r`n}`r`n'@"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Initialize-TpmProgressNative the -MemberDefinition source is a fixed single-quoted here-string literal (no expansion) declaring only the kernel32 GetStdHandle, GetCurrentConsoleFontEx, GetConsoleMode and WriteConsoleW signatures plus two fixed wrappers; -Namespace and -Name are fixed literals. No variable, path, console, file or network data is compiled; the text WriteText prints is a runtime argument of the compiled method, never part of the source.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 318
            Extent      = "Add-Type -Namespace TpmProgressNative -Name ConsoleCells -ErrorAction Stop -MemberDefinition @'`r`n[StructLayout(LayoutKind.Sequential)]`r`npublic struct COORD {`r`n    public short X;`r`n    public short Y;`r`n}`r`n[DllImport(`"kernel32.dll`", SetLastError = true)]`r`npublic static extern IntPtr GetStdHandle(int nStdHandle);`r`n[DllImport(`"kernel32.dll`", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = `"FillConsoleOutputCharacterW`")]`r`npublic static extern bool FillConsoleOutputCharacter(IntPtr hConsoleOutput, char cCharacter, uint nLength, COORD dwWriteCoord, out uint lpNumberOfCharsWritten);`r`npublic static bool Blank(int top, int count) {`r`n    if (count <= 0) { return true; }`r`n    if (top < 0 || top > 32766) { return false; }`r`n    COORD origin;`r`n    origin.X = 0;`r`n    origin.Y = (short)top;`r`n    uint written;`r`n    if (!FillConsoleOutputCharacter(GetStdHandle(-11), ' ', (uint)count, origin, out written)) { return false; }`r`n    return written == (uint)count;`r`n}`r`n'@"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Initialize-TpmProgressCells the -MemberDefinition source is a fixed single-quoted here-string literal (no expansion) declaring only the kernel32 GetStdHandle and FillConsoleOutputCharacterW signatures and the fixed Blank wrapper; -Namespace and -Name are fixed literals. No variable or external data is compiled; Blank receives its row and count as runtime integer arguments, range-checked inside the compiled method.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 472
            Extent      = "Add-Type -Namespace TpmProgressNative -Name ConsoleOutputMode -ErrorAction Stop -MemberDefinition @'`r`n[DllImport(`"kernel32.dll`", SetLastError = true)]`r`npublic static extern IntPtr GetStdHandle(int nStdHandle);`r`n[DllImport(`"kernel32.dll`", SetLastError = true)]`r`npublic static extern bool GetConsoleMode(IntPtr handle, out uint mode);`r`n[DllImport(`"kernel32.dll`", SetLastError = true)]`r`npublic static extern bool SetConsoleMode(IntPtr handle, uint mode);`r`npublic static bool Read(out uint mode) { return GetConsoleMode(GetStdHandle(-11), out mode); }`r`npublic static bool Write(uint mode) { return SetConsoleMode(GetStdHandle(-11), mode); }`r`n'@"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Initialize-TpmProgressConsoleModeApi the -MemberDefinition source is a fixed single-quoted here-string literal (no expansion) declaring only the kernel32 GetStdHandle, GetConsoleMode and SetConsoleMode signatures and two fixed wrappers; -Namespace and -Name are fixed literals. No variable or external data is compiled; the console mode is a runtime uint argument.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 562
            Extent      = "`$color -replace '^Dark', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'In New-TpmProgressPaint (called by Get-TpmProgressGradient and Get-TpmProgressRowPaint) the regex pattern and replacement are fixed literals; only the searched value is a variable, and $color is a fixed literal console color name: the caller''s -Name argument or one picked from the fixed color table in Get-TpmProgressNearestColor. The result is only compared for equality with the background hue to avoid drawing in it. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 579
            Extent      = "`$Background -replace '^Dark', ''"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Get-TpmProgressPalette and New-TpmProgressPaint the regex pattern and replacement are fixed literals; only the searched value ($Background, a console color name) is a variable, and the result is only compared for equality with fixed palette color names. Not a regex/replacement injection vector.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.AddScript'
            Line        = 1637
            Extent      = "`$runner.AddScript({`r`n            param(`$modulePath, `$shared)`r`n            `$ErrorActionPreference = 'Stop'`r`n            # FIX43: the writer is a daemon. A foreground worker thread keeps powershell.exe -File alive after the script`r`n            # ends (the process never exited after Q in a real console window), so it must never count as a foreground thread.`r`n            try { [System.Threading.Thread]::CurrentThread.IsBackground = `$true } catch {}`r`n            # Diagnostic read by the FIX43 tests: whether the writer thread really is a background thread.`r`n            try { `$shared.Background = [bool][System.Threading.Thread]::CurrentThread.IsBackground } catch {}`r`n            try {`r`n                `$module = Import-Module -Name `$modulePath -PassThru -ErrorAction Stop`r`n                & `$module {`r`n                    param(`$service)`r`n                    # Compile the frame path off screen before the first frame (FIX24). Skipped when an operation is`r`n                    # already waiting: its value updates are drawn only by this writer, and its owner has drawn frames by`r`n                    # then (compiled code is shared between runspaces), so drawing at once beats warming up first. A`r`n                    # failed warm-up only means a slower first frame.`r`n                    if (`$null -eq `$service.Session) { try { Invoke-TpmProgressWarmup } catch {} }`r`n                    `$service.Ready = `$true`r`n                    while (-not `$service.Stop) {`r`n                        `$live = `$service.Session`r`n                        if (`$null -eq `$live) {`r`n                            # FIX43: a bounded wait, not an endless one. With no operation to draw, the writer ends itself once`r`n                            # its owner (the runspace or thread that created it) is gone, instead of sleeping forever.`r`n                            [void]`$service.Signal.WaitOne(1000)`r`n                            if (`$null -eq `$service.Session -and -not `$service.Stop -and -not (Test-TpmProgressOwnerActive -Live `$service)) { `$service.Stop = `$true }`r`n                            continue`r`n                        }`r`n                        # Sleep until the next frame is due (adaptive interval); Stop and a new session signal at once.`r`n                        [void]`$service.Signal.WaitOne((Get-TpmProgressRefreshWait -Live `$live))`r`n                        [System.Threading.Monitor]::Enter(`$live.Gate)`r`n                        try {`r`n                            if (-not `$live.Stop) {`r`n                                `$script:TpmProgressWideWriteActive = `$live.WideWrite`r`n                                Invoke-TpmProgressRefreshStep -Live `$live -CheckOwner`r`n                            }`r`n                        } catch {`r`n                            `$live.Failure = `$_`r`n                            `$live.Stop = `$true`r`n                        } finally {`r`n                            if (`$live.Stop -and `$null -ne `$live.Failure -and `$null -ne `$live.CursorVisible) {`r`n                                Set-TpmProgressCursorVisible -Visible `$live.CursorVisible`r`n                            }`r`n                            [System.Threading.Monitor]::Exit(`$live.Gate)`r`n                        }`r`n                        if (`$live.Stop) {`r`n                            `$service.Session = `$null`r`n                            # Acknowledge AFTER the last write and after releasing the gate. The owner can now dispose.`r`n                            [void]`$live.Signal.Set()`r`n                        }`r`n                    }`r`n                } `$shared`r`n            } catch {`r`n                `$shared.Failure = `$_`r`n                `$live = `$shared.Session`r`n                if (`$null -ne `$live) {`r`n                    `$live.Failure = `$_`r`n                    `$live.Stop = `$true`r`n                    if (`$null -ne `$live.CursorVisible) { try { [Console]::CursorVisible = `$live.CursorVisible } catch {} }`r`n                    `$shared.Session = `$null`r`n                    [void]`$live.Signal.Set()`r`n                }`r`n            }`r`n        })"
            Disposition = 'FalsePositive'
            Reasoning   = 'In New-TpmProgressRefreshService AddScript receives a scriptblock literal written in this module (fixed at parse time); no string is built or concatenated into it. The only inputs are passed with AddArgument as bound parameters, never as script text: $script:TpmProgressModulePath (this module''s own $PSCommandPath, set when the module loads) and the synchronized service hashtable created in the same function. No user, file or network data reaches the script text.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 2275
            Extent      = "`$task.`$name"
            Disposition = 'FalsePositive'
            Reasoning   = 'In Resume-TpmProgressLine $name iterates only over the fixed literal list Started, StageStarted, RateAt in the enclosing foreach, and $task is one of TPM''s own progress operation/task objects. No external value selects the property name.'
        }
        @{
            File        = 'scripts/TpmProgress.psm1'
            RuleName    = 'InjectionRisk.AddType'
            Line        = 396
            Extent      = "Add-Type -Namespace TpmProgressNative -Name ConsoleCellReader -ErrorAction Stop -MemberDefinition @'`r`n[StructLayout(LayoutKind.Sequential)]`r`npublic struct COORD {`r`n    public short X;`r`n    public short Y;`r`n}`r`n[DllImport(`"kernel32.dll`", SetLastError = true)]`r`npublic static extern IntPtr GetStdHandle(int nStdHandle);`r`n[DllImport(`"kernel32.dll`", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = `"ReadConsoleOutputCharacterW`")]`r`npublic static extern bool ReadConsoleOutputCharacter(IntPtr hConsoleOutput, [Out] char[] lpCharacter, uint nLength, COORD dwReadCoord, out uint lpNumberOfCharsRead);`r`npublic static string Read(int top, int count) {`r`n    if (count <= 0 || top < 0 || top > 32766) { return null; }`r`n    char[] buffer = new char[count];`r`n    COORD origin;`r`n    origin.X = 0;`r`n    origin.Y = (short)top;`r`n    uint read;`r`n    if (!ReadConsoleOutputCharacter(GetStdHandle(-11), buffer, (uint)count, origin, out read)) { return null; }`r`n    if (read != (uint)count) { return null; }`r`n    return new string(buffer, 0, count);`r`n}`r`n'@"
            Disposition = 'FalsePositive'
            Reasoning   = 'The C# member definition is a fixed here-string literal compiled once to bind the kernel32 ReadConsoleOutputCharacterW call (FIX45 console-cell reader). No variable, path, user input or downloaded content reaches Add-Type; the type is created only when it is not already loaded.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 15458
            Extent      = "`$change.Geometry.`$name"
            Disposition = 'FalsePositive'
            Reasoning   = '$name is drawn only from the fixed, hardcoded array of geometry field names (Width, Height, BufferWidth, BufferHeight) in the ReShade chooser resize check (FIX52). The geometry objects hold console size integers; no external value can select the property name used by this access.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 2346
            Extent      = '$Snapshot.$name'
            Disposition = 'FalsePositive'
            Reasoning   = 'In ConvertTo-TpmWorkflowEvidenceRecord $name iterates only over the fixed literal list WorkflowId, RunId, WorkflowKey, Lifecycle, State, Sequence. The snapshot is a TPM-owned workflow status object, and the access only reads a property after checking that it exists. No outside value can pick the property name.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 39720
            Extent      = '$Row.$Name'
            Disposition = 'FalsePositive'
            Reasoning   = 'In Get-TpmGuideText every caller passes a fixed literal field name, or a fixed vendor key (amd, nvidia, intel) joined to _issues or _status, or an item from the fixed list supp_archives, additional_archives. The row is parsed guide data, the access only reads a field after checking that it exists, and nothing is executed or written from it.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 54019
            Extent      = '$Item.$Name'
            Disposition = 'FalsePositive'
            Reasoning   = 'The textOf helper in the game setup notes report is called only with fixed literal field names (BaseGame, GuideStatus, SecondFile, TestProgram, GeneralIssues, LinkedProfile and similar). The item is a TPM-built notes object, the access only reads a property after checking that it exists, and no outside value can pick the name.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 45459
            Extent      = '$_ -replace "''", "''''"'
            Disposition = 'Mitigated'
            Reasoning   = 'In Get-TpmGamesDbIndex the platform names are doubled single quotes before they are put in the quoted list of a read-only SELECT on the LaunchBox game list. The names come from the script (Arcade, Taito Type X), not from a user or a file, and the query only reads.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 45556
            Extent      = '$InternalName -replace ''\s*\([^()]*\)\s*$'', '''''
            Disposition = 'FalsePositive'
            Reasoning   = 'The regex pattern and replacement string are both fixed literals (a trailing bracketed note is cut from a game name). Only the left-hand operand is a variable, and no outside value can pick the pattern or the replacement.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.StaticPropertyInjection'
            Line        = 46095
            Extent      = '$facts.Dat.$fact'
            Disposition = 'FalsePositive'
            Reasoning   = 'The loop that fills in LaunchBox game details only takes $fact from the fixed list Year, Developer, Hardware. The facts object is TPM-built, the access only reads a property, and nothing is executed or written from the name.'
        }
        @{
            File        = 'TeknoParrot-Manager.ps1'
            RuleName    = 'InjectionRisk.UnsafeEscaping'
            Line        = 55165
            Extent      = '$name -replace ''^CONTROL_'', '''''
            Disposition = 'FalsePositive'
            Reasoning   = 'The regex pattern and replacement string are both fixed literals (the CONTROL_ prefix is cut from a LEDBlinky control name). Only the left-hand operand is a variable, and no outside value can pick the pattern or the replacement.'
        }
    )
}
