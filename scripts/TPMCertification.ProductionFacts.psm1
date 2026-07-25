Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Authority.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Production.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Reports.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Publication.psm1')
Import-Module (Join-Path $PSScriptRoot 'TPMCertification.Execution.psm1')
Set-StrictMode -Version 2.0

# ADR-0155 Section 5.3/5.7 production fact collection (ADR155-0309
# Checkpoint B1). This module builds every one of the eleven raw facts the
# production authority (TPMCertification.Production.psm1) consumes. It does
# not import or call TPMCertification.Shadow.psm1 -- Phase 2's shadow
# adapter is a placeholder-tolerant, never-authoritative construct; reusing
# it here silently carried Static Analysis/Artifacts placeholders into
# Phase 3 eligibility (the defect this checkpoint exists to fix). Every
# value this module reports is a real, freshly observed result: an
# unavailable tool, a process timeout, malformed diagnostic output, or an
# unwritable path is reported honestly as Executed=$false / not-ready, which
# correctly fails eligibility rather than silently passing.

# The authoritative production PowerShell inventory: the union of (a) the
# release-package PowerShell contents (Tests/Test-ReleasePackage.ps1's own
# required-ZIP-entries list, filtered to .ps1/.psm1 -- TeknoParrot-Manager.bat,
# the .txt docs, and LICENSE are not PowerShell) and (b) the production
# certification/harness PowerShell content ADR-0155 introduces or drives at
# real-hardware-certification time. Each entry's inclusion/exclusion class:
#
# Included -- release package (ships to end users):
#   TeknoParrot-Manager.ps1              the certified product itself
#   scripts/Debug-TPM-MenuLayout.ps1     ships in the release ZIP (Test-ReleasePackage.ps1)
#   tools/Invoke-TpmAutoUpdate.ps1       ships in the release ZIP
#   tools/TpmAutoUpdate.Core.psm1        ships in the release ZIP
#
# Included -- ADR-0155 production certification/harness (drives or is
# driven by a real certification run; not test specs, not dev-only):
#   scripts/Invoke-TPM-RealInstanceSmoke.ps1      the real-hardware harness itself
#   scripts/Invoke-TPM-InstallHealthCheck.ps1     real install-health probe the harness consumes
#   scripts/Resolve-Pcsx2Directory.ps1            shared helper dot-sourced by both of the above
#   scripts/Run-TPM-Tests.ps1                     the entry point real certification runs actually
#                                                  execute (dispatches directly to
#                                                  Invoke-TPM-RealInstanceSmoke.ps1 -- confirmed by
#                                                  reading its own source, not assumed)
#   scripts/TPMCertification.Authority.psm1        Phase 1 authority/schema primitives
#   scripts/TPMCertification.Production.psm1       Phase 3 production authority (canonical, untouched
#                                                   by this checkpoint)
#   scripts/TPMCertification.ProductionCycle.psm1  Phase 3 orchestration (ADR155-0309 Sub-step A)
#   scripts/TPMCertification.ProductionFacts.psm1  this module
#   scripts/TPMCertification.Publication.psm1      Phase 3 publication/staging
#   scripts/TPMCertification.Reports.psm1          Phase 3 report builders
#   scripts/TPMCertification.Shadow.psm1           Phase 2 shadow authority (its own file content is
#                                                   certified here; this module still never imports
#                                                   or calls it as a fact source -- those are separate
#                                                   concerns)
#   scripts/Test-TPMParserCheckV1.ps1              the parser-check probe this module launches
#
# Excluded -- development-only, never shipped or executed at real
# certification time:
#   Tests/*.ps1, Tests/Test-ReleasePackage.ps1     Pester specs and release-ZIP validator; dev-only,
#                                                   explicitly excluded from the release ZIP itself
#   scripts/Preview-TPM-ConsoleUx.ps1              a developer console-rendering preview/diagnostic
#                                                   tool; not part of the certification pipeline (no
#                                                   facts, no harness invocation, not in the release
#                                                   ZIP) -- confirmed by reading its source
#   PSScriptAnalyzerSettings.psd1, *.psd1          data files, not PowerShell script/module source
#
# ECVF's scripts/TPMCertification.Contracts.psm1 (a different initiative,
# out of scope for ADR-0155/this checkpoint, and not present on this
# branch) is deliberately not part of this list.
$script:TpmProductionPowerShellInventoryRelativePathsV1 = @(
    'TeknoParrot-Manager.ps1',
    'scripts/Debug-TPM-MenuLayout.ps1',
    'tools/Invoke-TpmAutoUpdate.ps1',
    'tools/TpmAutoUpdate.Core.psm1',
    'scripts/Invoke-TPM-RealInstanceSmoke.ps1',
    'scripts/Invoke-TPM-InstallHealthCheck.ps1',
    'scripts/Resolve-Pcsx2Directory.ps1',
    'scripts/Run-TPM-Tests.ps1',
    'scripts/TPMCertification.Execution.psm1',
    'scripts/Invoke-TPM-PesterChild.ps1',
    'scripts/TPMCertification.Authority.psm1',
    'scripts/TPMCertification.Production.psm1',
    'scripts/TPMCertification.ProductionCycle.psm1',
    'scripts/TPMCertification.ProductionEvidence.psm1',
    'scripts/TPMCertification.ProductionFacts.psm1',
    'scripts/TPMCertification.Publication.psm1',
    'scripts/TPMCertification.Reports.psm1',
    'scripts/TPMCertification.Shadow.psm1',
    'scripts/Test-TPMParserCheckV1.ps1'
)

function Resolve-TPMProductionPowerShellInventoryEntriesV1 {
    # Private validation engine, intentionally NOT exported. The production
    # entry point (Get-TPMProductionPowerShellInventoryV1, below) is the
    # only exported way to obtain an inventory and always uses the fixed
    # list above -- callers cannot substitute a different file set through
    # any exported parameter. Tests reach this function directly via
    # Pester's InModuleScope to exercise the missing/duplicate/outside-root/
    # unreadable/incomplete rejection paths against a synthetic list,
    # without weakening the production API's contract.
    param(
        [Parameter(Mandatory=$true)][string]$RepositoryPath,
        [Parameter(Mandatory=$true)][string[]]$RelativePaths
    )
    $normalizedRoot=[IO.Path]::GetFullPath($RepositoryPath).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $expected=@($RelativePaths)
    $seenFull=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seenRelative=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $inventory=New-Object Collections.Generic.List[object]
    foreach($relative in $expected){
        if(-not$seenRelative.Add($relative)){throw "PRODUCTION_INVENTORY_DUPLICATE: $relative"}
        $osSegment=$relative -replace '/',[IO.Path]::DirectorySeparatorChar
        $candidate=Join-Path $normalizedRoot $osSegment
        $full=[IO.Path]::GetFullPath($candidate)
        try{$contained=Resolve-TPMContainedPathV1 -Root $normalizedRoot -Path $full}catch{throw "PRODUCTION_INVENTORY_OUTSIDE_ROOT: $relative"}
        if($contained-cne$full){throw "PRODUCTION_INVENTORY_OUTSIDE_ROOT: $relative"}
        if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw "PRODUCTION_INVENTORY_MISSING: $relative"}
        try{
            $stream=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            $stream.Dispose()
        }catch{throw "PRODUCTION_INVENTORY_UNREADABLE: $relative"}
        if(-not$seenFull.Add($full)){throw "PRODUCTION_INVENTORY_DUPLICATE: $relative"}
        $inventory.Add([ordered]@{RelativePath=$relative;FullPath=$full})
    }
    if($inventory.Count-ne$expected.Count){throw 'PRODUCTION_INVENTORY_INCOMPLETE'}
    return ,$inventory.ToArray()
}

function Get-TPMProductionPowerShellInventoryV1 {
    # The fixed, sole production entry point. Takes only -RepositoryPath --
    # there is no way for any caller, production or test, to override which
    # files are certified through this function.
    param([Parameter(Mandatory=$true)][string]$RepositoryPath)
    return ,(Resolve-TPMProductionPowerShellInventoryEntriesV1 -RepositoryPath $RepositoryPath -RelativePaths $script:TpmProductionPowerShellInventoryRelativePathsV1)
}

function Find-TPMInjectionHunterModuleV1 {
    # Get-Module -ListAvailable only searches the CURRENT engine's own
    # $env:PSModulePath. Windows PowerShell 5.1's default path does not
    # include the sibling "...\PowerShell\Modules" convention pwsh uses, so a
    # module installed only under that convention is invisible from 5.1 even
    # though it is genuinely present on the machine. Probe the sibling
    # module-root convention too so this reports honestly regardless of which
    # engine invokes it.
    $found=Get-Module -ListAvailable InjectionHunter -ErrorAction SilentlyContinue|Select-Object -First 1
    if($found){return $found}
    $candidateRoots=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in @($env:PSModulePath -split ';')){
        if([string]::IsNullOrWhiteSpace($entry)){continue}
        [void]$candidateRoots.Add($entry)
        if($entry -match '(?i)\\WindowsPowerShell\\Modules$'){[void]$candidateRoots.Add(($entry -replace '(?i)\\WindowsPowerShell\\Modules$','\PowerShell\Modules'))}
        elseif($entry -match '(?i)\\PowerShell\\Modules$'){[void]$candidateRoots.Add(($entry -replace '(?i)\\PowerShell\\Modules$','\WindowsPowerShell\Modules'))}
    }
    foreach($root in $candidateRoots){
        $manifest=Get-ChildItem -LiteralPath (Join-Path $root 'InjectionHunter') -Filter 'InjectionHunter.psd1' -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1
        if($manifest){
            try{
                $data=Import-PowerShellDataFile -Path $manifest.FullName
                return [pscustomobject]@{Path=$manifest.FullName;Version=[version]($data.ModuleVersion)}
            }catch{
                # A candidate manifest existing but failing to read/parse is
                # a real, diagnosable condition (a lock, a corrupt file, a
                # sync placeholder) -- surface it instead of silently moving
                # on to the next candidate root with no trail. Still
                # continues the search (a second candidate root may hold a
                # good copy), never assume this is fatal by itself.
                Write-Warning ("INJECTIONHUNTER_MANIFEST_READ_FAILED: path=$($manifest.FullName) exceptionType=$($_.Exception.GetType().FullName) message=$(ConvertTo-TPMSafeTechnicalTextV1 $_.Exception.Message)")
                continue
            }
        }
    }
    return $null
}

function ConvertTo-TPMWin32QuotedArgumentV1 {
    # Confirmed by direct reproduction that Start-Process -ArgumentList does
    # NOT quote array elements containing spaces on this environment's
    # PowerShell/Windows build -- "a file (with) [odd] chars.ps1" arrived at
    # the child process split into multiple separate argv tokens, silently
    # corrupting the path. Each argument must be pre-quoted here using the
    # standard Win32 CommandLineToArgvW-compatible algorithm (the same
    # convention powershell.exe/pwsh use to parse their own argv) before
    # Start-Process joins the array elements with plain spaces.
    param([Parameter(Mandatory=$true)][string]$Value)
    if($Value.Length-gt0-and$Value.IndexOfAny([char[]](' ',"`t",'"'))-lt0){return $Value}
    $sb=New-Object Text.StringBuilder
    [void]$sb.Append('"')
    $i=0
    while($i-lt$Value.Length){
        $numBackslashes=0
        while($i-lt$Value.Length-and$Value[$i]-eq'\'){$numBackslashes++;$i++}
        if($i-eq$Value.Length){
            [void]$sb.Append('\'*($numBackslashes*2))
            break
        }elseif($Value[$i]-eq'"'){
            [void]$sb.Append('\'*($numBackslashes*2+1))
            [void]$sb.Append('"')
            $i++
        }else{
            [void]$sb.Append('\'*$numBackslashes)
            [void]$sb.Append($Value[$i])
            $i++
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Invoke-TPMExternalProcessWithTimeoutV1 {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [Parameter(Mandatory=$true)][string[]]$ArgumentList,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds,
        [Parameter(Mandatory=$true)][string]$WorkingDirectoryRoot,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory
    )
    # Deliberately no pre-existence check on $WorkingDirectory here --
    # Invoke-TPMIsolatedProcessV1 (scripts/TPMCertification.Execution.psm1)
    # is the single source of truth for working/log-directory validation and
    # creation (full-path resolution, reparse-point rejection, and creating
    # the directory on first use via -CreateIfMissing when it does not yet
    # exist). A redundant guard here that bailed out before ever calling it
    # was confirmed by direct reproduction to silently report Executed=$false
    # for every real caller whose working directory is created lazily on
    # first use (as the production harness's own working directory is) --
    # this function's existing try/catch below already fails closed on any
    # genuine validation error the shared primitive throws.
    #
    # $WorkingDirectoryRoot is the caller's own already-validated scratch
    # parent (ADR155-0309 round 3) -- this function has no authority of its
    # own to invent a trust anchor, so it is threaded straight through from
    # New-TPMProductionFactRecordsV1's own -WorkingDirectoryRoot parameter,
    # which the real harness supplies as its already-established
    # ProductionWork\<stamp> directory (see
    # scripts/Invoke-TPM-RealInstanceSmoke.ps1). Used as both the working-
    # and log-directory root because this probe's working directory and log
    # directory are, deliberately, the same directory.
    try{
        $invocation=Invoke-TPMIsolatedProcessV1 -FilePath $FilePath -ArgumentList $ArgumentList -TimeoutSeconds $TimeoutSeconds -WorkingDirectoryRoot $WorkingDirectoryRoot -WorkingDirectory $WorkingDirectory -LogDirectoryRoot $WorkingDirectoryRoot -LogDirectory $WorkingDirectory -Identity 'parser-probe'
        $stdout=if(Test-Path -LiteralPath $invocation.StdOutPath){Get-Content -LiteralPath $invocation.StdOutPath -Raw -ErrorAction SilentlyContinue}else{$null}
        $stderr=if(Test-Path -LiteralPath $invocation.StdErrPath){Get-Content -LiteralPath $invocation.StdErrPath -Raw -ErrorAction SilentlyContinue}else{$null}
        return [ordered]@{TimedOut=$invocation.TimedOut;TerminationConfirmed=$invocation.TerminationConfirmed;ExitCode=$invocation.ExitCode;StdOut=$stdout;StdErr=$stderr;StdOutPath=$invocation.StdOutPath;StdErrPath=$invocation.StdErrPath;StdInPath=$invocation.StandardInputPath;MetadataPath=$invocation.MetadataPath}
    }catch{
        return [ordered]@{TimedOut=$true;TerminationConfirmed=$false;ExitCode=$null;StdOut=$null;StdErr=$_.Exception.Message;StdOutPath=$null;StdErrPath=$null;StdInPath=$null;MetadataPath=$null}
    }
}
function Test-TPMProductionParserProbeV1 {
    param(
        [Parameter(Mandatory=$true)]$Inventory,
        [Parameter(Mandatory=$true)][ValidateSet('WindowsPowerShell51','Pwsh')][string]$Engine,
        [Parameter(Mandatory=$true)][string]$WorkingDirectoryRoot,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [int]$TimeoutSeconds=60
    )
    $notExecuted=[ordered]@{Identifier=$Engine;Executed=$false;ErrorCount=0;ToolVersion=$null}
    $exeName=if($Engine -eq 'WindowsPowerShell51'){'powershell.exe'}else{'pwsh'}
    $exe=Get-Command $exeName -ErrorAction SilentlyContinue
    if(-not$exe){return $notExecuted}
    $probeScript=Join-Path $PSScriptRoot 'Test-TPMParserCheckV1.ps1'
    if(-not(Test-Path -LiteralPath $probeScript -PathType Leaf)){return $notExecuted}
    $fullPaths=@($Inventory|ForEach-Object{$_.FullPath})
    if($fullPaths.Count-eq0){return $notExecuted}

    # One process invocation per requested file -- not one invocation with
    # every path on the command line -- so "exactly one structured result
    # per requested file" and exact requested-file/result correlation are
    # enforced by construction, not by hoping a single process's combined
    # output stays untangled across every file. Start-Process -ArgumentList
    # is given each path as its own array element (never string-concatenated
    # into a single -Command argument), so paths containing spaces or shell
    # metacharacters survive intact -- proven by
    # Tests/TPMCertification.ProductionFacts.Tests.ps1's dedicated case.
    $totalErrors=0;$version=$null
    foreach($full in $fullPaths){
        $resultPath=Join-Path $WorkingDirectory ('parser-result-'+[guid]::NewGuid().ToString('N')+'.json')
        $argumentList=@('-NoProfile','-NonInteractive','-File',$probeScript,'-OutputPath',$resultPath,'-Path',$full)
        $invocation=Invoke-TPMExternalProcessWithTimeoutV1 -FilePath $exe.Source -ArgumentList $argumentList -TimeoutSeconds $TimeoutSeconds -WorkingDirectoryRoot $WorkingDirectoryRoot -WorkingDirectory $WorkingDirectory
        if($invocation.TimedOut){return $notExecuted}
        if($null-eq$invocation.ExitCode-or$invocation.ExitCode-ne0){return $notExecuted}
        if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){return $notExecuted}
        try{
            $raw=Get-Content -LiteralPath $resultPath -Raw
            $parsed=$raw|ConvertFrom-Json
        }catch{Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue;return $notExecuted}
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
        if($null-eq$parsed-or$parsed.PSObject.Properties.Name-notcontains'Results'){return $notExecuted}
        $items=@($parsed.Results)
        if($items.Count-ne1){return $notExecuted}
        $item=$items[0]
        if($null-eq$item){return $notExecuted}
        $propNames=@($item.PSObject.Properties.Name|Sort-Object)
        if(($propNames-join',')-ne'ErrorCount,Path,Version'){return $notExecuted}
        if($item.Path-isnot[string]-or$item.Path-cne$full){return $notExecuted}
        if(-not($item.ErrorCount-is[int]-or$item.ErrorCount-is[long])){return $notExecuted}
        if([long]$item.ErrorCount-lt0){return $notExecuted}
        if($item.Version-isnot[string]-or[string]::IsNullOrWhiteSpace($item.Version)){return $notExecuted}
        # The same engine executable must report the same version for every
        # file in this inventory -- a mismatch mid-run means something (a
        # PATH change, a swapped executable) shifted under us and the
        # aggregate is no longer trustworthy.
        if($null-ne$version -and $item.Version-cne$version){return $notExecuted}
        $totalErrors+=[int]$item.ErrorCount
        $version=[string]$item.Version
    }
    return [ordered]@{Identifier=$Engine;Executed=$true;ErrorCount=$totalErrors;ToolVersion=$version}
}

function Test-TPMProductionEncodingV1 {
    param([Parameter(Mandatory=$true)]$Inventory)
    $totalNonAscii=0;$executed=$true
    foreach($item in $Inventory){
        try{
            $bytes=[IO.File]::ReadAllBytes($item.FullPath)
            foreach($b in $bytes){if($b-gt127){$totalNonAscii++}}
        }catch{
            $executed=$false
            Write-Warning ("PRODUCTION_ENCODING_READ_FAILED: file=$($item.RelativePath) exceptionType=$($_.Exception.GetType().FullName) message=$(ConvertTo-TPMSafeTechnicalTextV1 $_.Exception.Message)")
        }
    }
    $files=@($Inventory|ForEach-Object{$_.RelativePath})
    return [ordered]@{Executed=$executed;NonAsciiByteCount=$totalNonAscii;Files=$files}
}

function Invoke-TPMBoundedScriptBlockV1 {
    # Bounded, out-of-process execution for in-process analysis calls
    # (Invoke-ScriptAnalyzer for both PSScriptAnalyzer and InjectionHunter).
    # A pathological input file could otherwise hang the analyzer
    # indefinitely with no boundary to enforce a timeout against, unlike the
    # parser probe (which already runs out-of-process). Uses Start-Job
    # (a genuine background process, not a same-process runspace) so the
    # result crosses back through normal PowerShell remoting serialization
    # -- confirmed necessary by direct reproduction: DiagnosticRecord's
    # Line/Column are ScriptProperties bound to the runspace that produced
    # them, not intrinsic .NET properties, so a same-process
    # [PowerShell]::Create() runspace handoff intermittently lost them
    # (and, worse, produced sporadic unrelated failures reading the result)
    # depending on timing; Start-Job's serialization boundary captures the
    # property's VALUE at the time of serialization, which is stable.
    # -Parameters must be an ORDERED dictionary ([ordered]@{...}) -- Start-Job
    # binds -ArgumentList positionally to the target scriptblock's param()
    # block, and a plain Hashtable's enumeration order is not guaranteed to
    # match insertion order.
    param(
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory=$true)]$Parameters,
        [Parameter(Mandatory=$true)][int]$TimeoutSeconds
    )
    $orderedArgs=@($Parameters.Values)
    $job=Start-Job -ScriptBlock $ScriptBlock -ArgumentList $orderedArgs
    $terminationConfirmed=$true
    try{
        $completed=Wait-Job -Job $job -Timeout $TimeoutSeconds
        if($null-eq$completed-or$job.State-eq'Running'){
            try{Stop-Job -Job $job -ErrorAction Stop}catch{}
            # Stop-Job does not guarantee the job has actually stopped by the
            # time it returns -- wait a short grace window and re-check the
            # job's own State rather than assuming success.
            [void](Wait-Job -Job $job -Timeout 5)
            $terminationConfirmed=($job.State-cne'Running')
            if(-not$terminationConfirmed){
                # Do not report a cleanly handled timeout when termination
                # could not be confirmed -- preserve the job (never
                # Remove-Job it here) so its Id/State remain available for
                # investigation instead of silently discarding the only
                # diagnostic evidence of why it would not stop.
                return [ordered]@{TimedOut=$true;TerminationConfirmed=$false;Result=$null;HadErrors=$false;JobId=$job.Id;JobState=$job.State.ToString();ErrorMessages=@()}
            }
            return [ordered]@{TimedOut=$true;TerminationConfirmed=$true;Result=$null;HadErrors=$false;JobId=$null;JobState=$null;ErrorMessages=@()}
        }
        try{
            $result=@(Receive-Job -Job $job -ErrorAction Stop -ErrorVariable jobErrors)
            $hadErrors=($job.State-eq'Failed'-or@($jobErrors).Count-gt0)
            # Preserve what the job's own error stream actually said -- a
            # bare HadErrors=$true with no message was the exact shape of
            # diagnostic loss this hardening round exists to close. Each
            # entry is reduced to its own exception type/message (primitive
            # strings) since ErrorRecord objects captured via -ErrorVariable
            # on a job's remoting output are not reliably usable beyond
            # this call.
            $errorMessages=@($jobErrors|ForEach-Object{
                $exceptionType=$(if($_.Exception){$_.Exception.GetType().FullName}else{$null})
                "$($exceptionType): $($_.ToString())"
            })
            return [ordered]@{TimedOut=$false;TerminationConfirmed=$true;Result=$result;HadErrors=$hadErrors;JobId=$null;JobState=$null;ErrorMessages=$errorMessages}
        }catch{
            $exceptionType=$_.Exception.GetType().FullName
            return [ordered]@{TimedOut=$false;TerminationConfirmed=$true;Result=$null;HadErrors=$true;JobId=$null;JobState=$null;ErrorMessages=@("$($exceptionType): $($_.Exception.Message)")}
        }
    }finally{
        if($terminationConfirmed){Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
    }
}

function Test-TPMProductionPSScriptAnalyzerV1 {
    # ToolVersion is reported by the bounded job itself (the process that
    # actually performed the analysis), never by a parent-process
    # Get-Module -ListAvailable discovery -- a version discovered in the
    # parent is not proof of what the job genuinely loaded and ran.
    param([Parameter(Mandatory=$true)]$Inventory,[Parameter(Mandatory=$true)][string]$SettingsPath,[int]$PerFileTimeoutSeconds=60)
    $notExecuted=[ordered]@{Executed=$false;FindingCount=0;ToolVersion=$null;Diagnostic=$null}
    if(-not(Test-Path -LiteralPath $SettingsPath -PathType Leaf)){
        $notExecuted.Diagnostic=[ordered]@{Stage='PSSCRIPTANALYZER_SETTINGS_MISSING';ExceptionType=$null;Message="Settings file not found: $SettingsPath"}
        Write-Warning 'PSSCRIPTANALYZER_TOOL_LOAD_FAILED: stage=PSSCRIPTANALYZER_SETTINGS_MISSING'
        return $notExecuted
    }
    $total=0;$version=$null
    foreach($item in $Inventory){
        $bounded=Invoke-TPMBoundedScriptBlockV1 -ScriptBlock {
            param($Path,$Settings)
            $findings=@(Invoke-ScriptAnalyzer -Path $Path -Severity Error,Warning -Settings $Settings)
            $loaded=Get-Module PSScriptAnalyzer|Select-Object -First 1
            [pscustomobject]@{Path=$Path;FindingCount=$findings.Count;ToolVersion=$(if($loaded){$loaded.Version.ToString()}else{$null})}
        } -Parameters ([ordered]@{Path=$item.FullPath;Settings=$SettingsPath}) -TimeoutSeconds $PerFileTimeoutSeconds
        if($bounded.TimedOut-or$bounded.HadErrors-or$null-eq$bounded.Result){
            $jobErrorText=$(if($bounded.ErrorMessages-and@($bounded.ErrorMessages).Count-gt0){(ConvertTo-TPMSafeTechnicalTextV1 (($bounded.ErrorMessages)-join' | '))}else{'(none captured)'})
            $stage=if($bounded.TimedOut){'PSSCRIPTANALYZER_JOB_TIMED_OUT'}else{'PSSCRIPTANALYZER_JOB_EXECUTION_FAILED'}
            $failed=[ordered]@{Executed=$false;FindingCount=0;ToolVersion=$null;Diagnostic=[ordered]@{Stage=$stage;ExceptionType=$null;Message="file=$($item.RelativePath) timedOut=$($bounded.TimedOut) hadErrors=$($bounded.HadErrors) jobErrors=$jobErrorText"}}
            Write-Warning "PSSCRIPTANALYZER_TOOL_LOAD_FAILED: stage=$stage"
            return $failed
        }
        $items=@($bounded.Result|ForEach-Object{$_})
        if($items.Count-ne1){return $notExecuted}
        $r=$items[0]
        if($null-eq$r){return $notExecuted}
        $propNames=Get-TPMJobResultOwnPropertyNamesV1 $r
        if(($propNames-join',')-ne'FindingCount,Path,ToolVersion'){return $notExecuted}
        if($r.Path-isnot[string]-or$r.Path-cne$item.FullPath){return $notExecuted}
        if(-not($r.FindingCount-is[int]-or$r.FindingCount-is[long])-or[long]$r.FindingCount-lt0){return $notExecuted}
        if($r.ToolVersion-isnot[string]-or[string]::IsNullOrWhiteSpace($r.ToolVersion)){return $notExecuted}
        if($null-ne$version-and$r.ToolVersion-cne$version){return $notExecuted}
        $total+=[int]$r.FindingCount
        $version=[string]$r.ToolVersion
    }
    return [ordered]@{Executed=$true;FindingCount=$total;ToolVersion=$version}
}

function Assert-TPMDispositionRegistryV1 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $data=Import-PowerShellDataFile -Path $Path
    $topKeys=@($data.Keys|ForEach-Object{[string]$_}|Sort-Object)
    if(($topKeys-join',')-ne'Dispositions,SchemaVersion'){throw 'DISPOSITION_REGISTRY_INVALID: unexpected top-level fields'}
    if($data.SchemaVersion-isnot[int]-and$data.SchemaVersion-isnot[long]){throw 'DISPOSITION_REGISTRY_INVALID: SchemaVersion must be an integer'}
    if([int]$data.SchemaVersion-ne1){throw 'DISPOSITION_REGISTRY_INVALID: unsupported SchemaVersion'}
    $entries=@($data.Dispositions)
    $allowedDispositions=@('Confirmed','Mitigated','FalsePositive')
    $seenEntryIdentity=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $byMatchKey=@{}
    foreach($entry in $entries){
        if($entry-isnot[hashtable]){throw 'DISPOSITION_REGISTRY_INVALID: entry must be a map'}
        $entryKeys=@($entry.Keys|ForEach-Object{[string]$_}|Sort-Object)
        if(($entryKeys-join',')-ne'Disposition,Extent,File,Line,Reasoning,RuleName'){throw 'DISPOSITION_REGISTRY_INVALID: entry has unexpected fields'}
        if($entry.File-isnot[string]-or[string]::IsNullOrWhiteSpace($entry.File)){throw 'DISPOSITION_REGISTRY_INVALID: File must be a non-empty string'}
        if([IO.Path]::IsPathRooted($entry.File)-or$entry.File.Contains('\')-or@($entry.File-split'[\\/]'|Where-Object{$_-eq'.'-or$_-eq'..'}).Count-gt0){throw 'DISPOSITION_REGISTRY_INVALID: File must be a normalized repository-relative path'}
        if($entry.RuleName-isnot[string]-or[string]::IsNullOrWhiteSpace($entry.RuleName)){throw 'DISPOSITION_REGISTRY_INVALID: RuleName must be a non-empty string'}
        if($entry.Extent-isnot[string]-or[string]::IsNullOrWhiteSpace($entry.Extent)){throw 'DISPOSITION_REGISTRY_INVALID: Extent must be a non-empty string'}
        if(($entry.Line-isnot[int]-and$entry.Line-isnot[long])-or[long]$entry.Line-le0){throw 'DISPOSITION_REGISTRY_INVALID: Line must be a positive integer'}
        if($entry.Reasoning-isnot[string]-or[string]::IsNullOrWhiteSpace($entry.Reasoning)){throw 'DISPOSITION_REGISTRY_INVALID: Reasoning must be a non-empty string'}
        if($allowedDispositions-cnotcontains[string]$entry.Disposition){throw 'DISPOSITION_REGISTRY_INVALID: unsupported Disposition value'}
        $entryIdentity=[string]$entry.File+"`u{1F}"+[string]$entry.RuleName+"`u{1F}"+[string]$entry.Extent+"`u{1F}"+[string]$entry.Line
        if(-not$seenEntryIdentity.Add($entryIdentity)){throw 'DISPOSITION_REGISTRY_INVALID: duplicate File/RuleName/Extent/Line entry'}
        $matchKey=[string]$entry.File+"`u{1F}"+[string]$entry.RuleName+"`u{1F}"+[string]$entry.Extent
        if(-not$byMatchKey.ContainsKey($matchKey)){$byMatchKey[$matchKey]=New-Object Collections.Generic.List[object]}
        $byMatchKey[$matchKey].Add($entry)
    }
    return [ordered]@{ByMatchKey=$byMatchKey}
}

$script:TpmJobResultNoisePropertyNamesV1=@('RunspaceId','PSComputerName','PSShowComputerName','PSSourceJobInstanceId')

function Get-TPMJobResultOwnPropertyNamesV1 {
    # Receive-Job attaches its own bookkeeping properties to every
    # deserialized result object (confirmed by direct reproduction: the
    # exact set observed varies -- RunspaceId always, PSShowComputerName in
    # some runs -- but none of them are part of the job's own returned
    # shape). These must never be treated as unexpected/malformed extra
    # fields; only the job's own declared properties are checked against an
    # expected schema.
    param($Value)
    return ,@($Value.PSObject.Properties.Name|Where-Object{$script:TpmJobResultNoisePropertyNamesV1-cnotcontains$_}|Sort-Object)
}

function Sort-TPMByLineV1 {
    # A tiny manual insertion sort by .Line, deliberately NOT using
    # Sort-Object -Property Line. Confirmed by direct reproduction: piping a
    # List[object] of Hashtables through Sort-Object intermittently produced
    # corrupted/incomplete results here (a $null element reachable within
    # the reported .Count, and unrelated property-lookup failures on other
    # elements) -- Hashtable implements IDictionary/IEnumerable, and mixing
    # that with Sort-Object's own property-extraction pipeline over a
    # collection of dictionaries was not reliable. Every list this sorts is
    # at most a handful of items (one registry entry or current finding per
    # distinct source occurrence), so an O(n^2) manual sort has no
    # measurable cost.
    param($Items)
    # Deliberately NOT "@($Items)" -- confirmed by direct reproduction that
    # the array-subexpression operator applied directly to a
    # Collections.Generic.List[object] throws "Argument types do not match"
    # on this environment's PowerShell build, even though the same list
    # enumerates correctly via ForEach-Object, .ToArray(), or an [array]
    # cast. Piping through ForEach-Object is the reliable path.
    $arr=@($Items|ForEach-Object{$_})
    for($i=0;$i-lt$arr.Count;$i++){
        for($j=$i+1;$j-lt$arr.Count;$j++){
            if([int]$arr[$j].Line-lt[int]$arr[$i].Line){$tmp=$arr[$i];$arr[$i]=$arr[$j];$arr[$j]=$tmp}
        }
    }
    return ,$arr
}

function New-TPMInjectionHunterStageExceptionV1 {
    # Same tagged-message/InnerException-preservation discipline as
    # New-TPMSanitizationExhaustedExceptionV1 (TPMCertification.Execution.psm1)
    # -- a stable, closed-set Stage tag prefix followed by a colon, with the
    # original exception (if any) preserved as InnerException so its own
    # type/HResult/message are never lost, only ever caught at the single
    # outer boundary in Test-TPMProductionInjectionHunterV1, which turns it
    # into a structured Diagnostic instead of erasing it.
    param(
        [Parameter(Mandatory=$true)][string]$Stage,
        [Parameter(Mandatory=$true)][string]$Detail,
        [Exception]$InnerException
    )
    $message="$($Stage): $Detail"
    if($InnerException){return (New-Object Exception($message,$InnerException))}
    return (New-Object Exception($message))
}

function Test-TPMProductionInjectionHunterV1 {
    # Every failure path returns a Diagnostic field alongside the existing
    # Executed=$false/ToolVersion=$null shape (an additive field -- callers
    # that only read the original named properties, such as
    # New-TPMProductionFactRecordsV1, are unaffected) so a caller that DOES
    # want to know why the gate failed never has to guess. Diagnostic is
    # always [ordered]@{Stage=<tag>;ExceptionType=<.NET type or $null>;
    # Message=<sanitized text>}; Stage is one of a small closed set of tags
    # identifying which stage of tool loading/scanning failed -- never a
    # free-form/empty value. A concise, tagged Write-Warning is also emitted
    # at the point of failure so the operator-facing console output points
    # at the underlying cause instead of a bare Executed=False.
    param([Parameter(Mandatory=$true)]$Inventory,[Parameter(Mandatory=$true)][string]$DispositionRegistryPath,[int]$PerFileTimeoutSeconds=60)
    $notExecuted=[ordered]@{Executed=$false;FindingCount=0;UnresolvedFindingCount=0;ToolVersion=$null;Dispositions=@();Diagnostic=$null}
    $module=Find-TPMInjectionHunterModuleV1
    if(-not$module){
        $notExecuted.Diagnostic=[ordered]@{Stage='INJECTIONHUNTER_MODULE_NOT_FOUND';ExceptionType=$null;Message='InjectionHunter module manifest was not found on this engine''s module path (or its sibling WindowsPowerShell/PowerShell convention).'}
        Write-Warning 'INJECTIONHUNTER_TOOL_LOAD_FAILED: stage=INJECTIONHUNTER_MODULE_NOT_FOUND'
        return $notExecuted
    }
    if(-not(Test-Path -LiteralPath $DispositionRegistryPath -PathType Leaf)){
        $notExecuted.Diagnostic=[ordered]@{Stage='INJECTIONHUNTER_REGISTRY_MISSING';ExceptionType=$null;Message="Disposition registry not found: $DispositionRegistryPath"}
        Write-Warning 'INJECTIONHUNTER_TOOL_LOAD_FAILED: stage=INJECTIONHUNTER_REGISTRY_MISSING'
        return $notExecuted
    }
    try{
        $registry=Assert-TPMDispositionRegistryV1 -Path $DispositionRegistryPath
        $allFindings=New-Object Collections.Generic.List[object]
        $version=$null
        foreach($item in $Inventory){
            # Project to plain, primitive-typed fields INSIDE the bounded
            # runspace before returning -- DiagnosticRecord's Line/Column are
            # ScriptProperties bound to the runspace that ran the analyzer,
            # not intrinsic .NET properties, so they read back as missing
            # once the object crosses back into this runspace (confirmed by
            # direct reproduction). ToolVersion is read from the exact
            # custom-rule module manifest the job was handed ($RulePath),
            # inside the job -- never a parent-process discovery -- so a
            # reported version is proof of what the job genuinely loaded.
            $bounded=Invoke-TPMBoundedScriptBlockV1 -ScriptBlock {
                param($Path,$RulePath)
                $findings=@(Invoke-ScriptAnalyzer -Path $Path -CustomRulePath $RulePath|ForEach-Object{[pscustomobject]@{RuleName=[string]$_.RuleName;Line=[int]$_.Extent.StartLineNumber;Extent=[string]$_.Extent.Text}})
                $manifestVersion=$null;$manifestErrorType=$null;$manifestErrorMessage=$null;$manifestErrorHResult=$null
                try{
                    $manifestData=Import-PowerShellDataFile -Path $RulePath
                    $manifestVersion=[string]$manifestData.ModuleVersion
                }catch{
                    # Preserve the real exception as primitive fields --
                    # crossing the job's serialization boundary, only
                    # primitive-typed properties survive intact (the same
                    # reason DiagnosticRecord's Line/Column are projected to
                    # plain fields above). Never silently drop this: a
                    # manifest read/parse failure here is exactly the defect
                    # class that used to surface only as ToolVersion=$null
                    # with no explanation.
                    $manifestErrorType=$_.Exception.GetType().FullName
                    $manifestErrorMessage=$_.Exception.Message
                    $manifestErrorHResult=$_.Exception.HResult
                }
                [pscustomobject]@{Path=$Path;Findings=$findings;ToolVersion=$manifestVersion;ManifestErrorType=$manifestErrorType;ManifestErrorMessage=$manifestErrorMessage;ManifestErrorHResult=$manifestErrorHResult}
            } -Parameters ([ordered]@{Path=$item.FullPath;RulePath=$module.Path}) -TimeoutSeconds $PerFileTimeoutSeconds
            if($bounded.TimedOut-or$bounded.HadErrors-or$null-eq$bounded.Result){
                $jobErrorText=$(if($bounded.ErrorMessages-and@($bounded.ErrorMessages).Count-gt0){(ConvertTo-TPMSafeTechnicalTextV1 (($bounded.ErrorMessages)-join' | '))}else{'(none captured)'})
                throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_JOB_EXECUTION_FAILED' -Detail "file=$($item.RelativePath) timedOut=$($bounded.TimedOut) hadErrors=$($bounded.HadErrors) jobErrors=$jobErrorText")
            }
            $items=@($bounded.Result|ForEach-Object{$_})
            if($items.Count-ne1){throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_RESULT_SHAPE_INVALID' -Detail "file=$($item.RelativePath) resultCount=$($items.Count)")}
            $r=$items[0]
            if($null-eq$r){throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_RESULT_SHAPE_INVALID' -Detail "file=$($item.RelativePath) result=null")}
            $propNames=Get-TPMJobResultOwnPropertyNamesV1 $r
            if(($propNames-join',')-ne'Findings,ManifestErrorHResult,ManifestErrorMessage,ManifestErrorType,Path,ToolVersion'){throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_RESULT_SCHEMA_INVALID' -Detail "file=$($item.RelativePath) properties=$($propNames -join ',')")}
            if($r.Path-isnot[string]-or$r.Path-cne$item.FullPath){throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_RESULT_PATH_MISMATCH' -Detail "expected=$($item.FullPath) actual=$($r.Path)")}
            if($r.ToolVersion-isnot[string]-or[string]::IsNullOrWhiteSpace($r.ToolVersion)){
                if($r.ManifestErrorType){
                    $inner=New-Object Exception(([string]$r.ManifestErrorMessage))
                    throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_MANIFEST_LOAD_FAILED' -Detail ("file={0} manifest={1} innerType={2} innerHResult=0x{3} innerMessage={4}" -f $item.RelativePath,$module.Path,$r.ManifestErrorType,('{0:X8}' -f [int]$r.ManifestErrorHResult),(ConvertTo-TPMSafeTechnicalTextV1 $r.ManifestErrorMessage)) -InnerException $inner)
                }
                throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_TOOL_VERSION_MISSING' -Detail "file=$($item.RelativePath) manifest=$($module.Path) (no manifest exception captured)")
            }
            if($null-ne$version-and$r.ToolVersion-cne$version){throw (New-TPMInjectionHunterStageExceptionV1 -Stage 'INJECTIONHUNTER_TOOL_VERSION_MISMATCH' -Detail "file=$($item.RelativePath) previous=$version current=$($r.ToolVersion)")}
            $version=[string]$r.ToolVersion
            foreach($f in @($r.Findings|ForEach-Object{$_})){[void]$allFindings.Add([pscustomobject]@{RelativePath=$item.RelativePath;RuleName=$f.RuleName;Line=$f.Line;Extent=$f.Extent})}
        }

        # Current-finding identity is File+RuleName+Extent+Line -- the exact
        # physical occurrence. Two genuinely identical occurrences of that
        # full identity would mean the scan itself double-reported a single
        # finding (a scanner defect, not a real second finding), so that is
        # rejected outright rather than silently merged or duplicated in the
        # Dispositions output.
        $seenFindingIdentity=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($finding in $allFindings){
            $identity=$finding.RelativePath+"`u{1F}"+$finding.RuleName+"`u{1F}"+$finding.Extent+"`u{1F}"+$finding.Line
            if(-not$seenFindingIdentity.Add($identity)){throw 'INJECTIONHUNTER_DUPLICATE_FINDING'}
        }

        # Matching key is File+RuleName+Extent (per ADR requirement -- Line
        # is deliberately excluded from the MATCH key so unrelated edits
        # elsewhere in a file don't invalidate a disposition). When more than
        # one current finding in the same file shares an identical
        # RuleName+Extent (a real, legitimate case in this repository --
        # e.g. the same -replace construct appears twice in
        # TeknoParrot-Manager.ps1 at different lines), each occurrence still
        # needs its OWN registry entry: entries sharing a match key are
        # consumed in ascending Line order against findings sharing that
        # same match key, also in ascending Line order, giving a strict,
        # deterministic one-to-one pairing. A count mismatch in either
        # direction (more findings than entries, or more entries than
        # findings, for a given match key) leaves the surplus on both sides
        # unmatched -- surplus findings are Confirmed/unresolved (safe
        # default), and surplus entries make the whole gate fail closed
        # (stale-entry detection, below), never silently paired against the
        # wrong occurrence.
        $findingsByKey=@{}
        foreach($finding in $allFindings){
            $key=$finding.RelativePath+"`u{1F}"+$finding.RuleName+"`u{1F}"+$finding.Extent
            if(-not$findingsByKey.ContainsKey($key)){$findingsByKey[$key]=New-Object Collections.Generic.List[object]}
            $findingsByKey[$key].Add($finding)
        }
        $consumedEntry=@{}
        $dispositionByIdentity=@{}
        foreach($key in $findingsByKey.Keys){
            $orderedFindings=Sort-TPMByLineV1 $findingsByKey[$key]
            # Deliberately NOT a bare "else{@()}" -- confirmed by direct
            # reproduction that an if/else branch's own output enumeration
            # collapses a zero-element array to $null when captured by
            # assignment (the same "return @() vs return ,@()" null-collapse
            # documented elsewhere in this file), so the empty-registry
            # branch must be comma-wrapped too or a match key with no
            # registry entry yet crashes here instead of falling through to
            # the safe "Confirmed" default below.
            $orderedEntries=if($registry.ByMatchKey.ContainsKey($key)){Sort-TPMByLineV1 $registry.ByMatchKey[$key]}else{,@()}
            for($i=0;$i-lt$orderedFindings.Count;$i++){
                $finding=$orderedFindings[$i]
                $findingIdentity=$finding.RelativePath+"`u{1F}"+$finding.RuleName+"`u{1F}"+$finding.Extent+"`u{1F}"+$finding.Line
                if($i-lt$orderedEntries.Count){
                    $entry=$orderedEntries[$i]
                    $entryIdentity=[string]$entry.File+"`u{1F}"+[string]$entry.RuleName+"`u{1F}"+[string]$entry.Extent+"`u{1F}"+[string]$entry.Line
                    $consumedEntry[$entryIdentity]=$true
                    $dispositionByIdentity[$findingIdentity]=[string]$entry.Disposition
                }else{
                    $dispositionByIdentity[$findingIdentity]='Confirmed'
                }
            }
        }
        foreach($key in $registry.ByMatchKey.Keys){
            foreach($entry in $registry.ByMatchKey[$key]){
                $entryIdentity=[string]$entry.File+"`u{1F}"+[string]$entry.RuleName+"`u{1F}"+[string]$entry.Extent+"`u{1F}"+[string]$entry.Line
                if(-not$consumedEntry.ContainsKey($entryIdentity)){throw "DISPOSITION_REGISTRY_STALE: $($entry.File):$($entry.Line) does not match any current finding"}
            }
        }

        $dispositions=New-Object Collections.Generic.List[object]
        $unresolvedCount=0
        foreach($finding in $allFindings){
            $findingIdentity=$finding.RelativePath+"`u{1F}"+$finding.RuleName+"`u{1F}"+$finding.Extent+"`u{1F}"+$finding.Line
            $disposition=$dispositionByIdentity[$findingIdentity]
            if($disposition-ne'Mitigated'-and$disposition-ne'FalsePositive'){$unresolvedCount++}
            $identifier="$($finding.RelativePath)::$($finding.RuleName)@L$($finding.Line)"
            $dispositions.Add([ordered]@{FindingIdentifier=$identifier;Disposition=$disposition})
        }
        return [ordered]@{Executed=$true;FindingCount=$allFindings.Count;UnresolvedFindingCount=$unresolvedCount;ToolVersion=$version;Dispositions=$dispositions.ToArray()}
    }catch{
        # Single outer boundary: every throw above (job execution, result
        # shape/schema, path mismatch, manifest load, tool-version mismatch,
        # duplicate-finding, stale-registry-entry, or a raw
        # DISPOSITION_REGISTRY_INVALID from Assert-TPMDispositionRegistryV1)
        # lands here. Never erase it -- extract the stable Stage tag from the
        # message prefix (falling back to a single unclassified tag only if
        # something throws without one, which would itself be a defect to
        # investigate), preserve the exception type, and emit a concise
        # tagged warning so the operator-facing console output always names
        # the real cause instead of a bare Executed=False.
        $stage='INJECTIONHUNTER_UNCLASSIFIED_FAILURE'
        $rawMessage=[string]$_.Exception.Message
        if($rawMessage-match'^([A-Z0-9_]+):\s*(.*)$'){$stage=$Matches[1]}
        $safeMessage=ConvertTo-TPMSafeTechnicalTextV1 $rawMessage
        Write-Warning "INJECTIONHUNTER_TOOL_LOAD_FAILED: stage=$stage exceptionType=$($_.Exception.GetType().FullName)"
        $result=[ordered]@{Executed=$false;FindingCount=0;UnresolvedFindingCount=0;ToolVersion=$null;Dispositions=@();Diagnostic=[ordered]@{Stage=$stage;ExceptionType=$_.Exception.GetType().FullName;Message=$safeMessage}}
        return $result
    }
}

$script:TpmProductionCanonicalArtifactFileNamesV1=@(
    'TPM-Certification-Eligibility.json',
    'TPM-Certification-Publication.json',
    'TPM-Certification-Final-Outcome.json',
    'TPM-Certification-Scorecard.md',
    'TPM-Certification-Validation.md',
    'TPM-Certification-Manifest.json',
    'TPM-Certification-Commit.json'
)

function New-TPMPreflightPngBytesV1 {
    param([int]$Seed)
    return [byte[]](137,80,78,71,13,10,26,10,$Seed)
}

function New-TPMPreflightSyntheticFactsV1 {
    param([Parameter(Mandatory=$true)][string]$ReportRoot)
    $hash='0'*64
    @(
        [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath='C:\preflight';RepositoryAvailable=$true;RepositoryClean=$true;GitStatus='(clean)'}}
        [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=$true;Total=1;Passed=1;Failed=0;Skipped=0;NotRun=0;Engine='preflight';SuiteSha256=$hash}}
        [ordered]@{Identifier='Static Analysis';Applicable=$true;Data=[ordered]@{Parser=@([ordered]@{Identifier='WindowsPowerShell51';Executed=$true;ErrorCount=0;ToolVersion='preflight'},[ordered]@{Identifier='Pwsh';Executed=$true;ErrorCount=0;ToolVersion='preflight'});Encoding=[ordered]@{Executed=$true;NonAsciiByteCount=0;Files=@('preflight.ps1')};PSScriptAnalyzer=[ordered]@{Executed=$true;FindingCount=0;ToolVersion='preflight'};InjectionHunter=[ordered]@{Executed=$true;FindingCount=0;UnresolvedFindingCount=0;ToolVersion='preflight';Dispositions=@()}}}
        [ordered]@{Identifier='Real Install Health';Applicable=$true;Data=[ordered]@{ReportPath=$null;LoadState='Missing';LoadError='preflight synthetic run: no real install health report';Checks=@()}}
        [ordered]@{Identifier='Backups';Applicable=$true;Data=[ordered]@{UserProfilesBackupCreated=$false;UserProfilesBackupPath=$null;UserProfilesBackupVerified=$false;UserProfilesBackupSha256=$null;GameProfilesBackupCreated=$false;GameProfilesBackupPath=$null;GameProfilesBackupVerified=$false;GameProfilesBackupSha256=$null;BackupVerificationExecuted=$true}}
        [ordered]@{Identifier='Smoke File Safety';Applicable=$true;Data=[ordered]@{UserProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};GameProfiles=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0};Pcsx2x6Crosshairs=[ordered]@{Added=0;Removed=0;Changed=0;BeforeSkipped=0;AfterSkipped=0}}}
        [ordered]@{Identifier='Artifacts';Applicable=$true;Data=[ordered]@{ReportDirectory=$ReportRoot;ReportDirectoryReserved=$true;StagingDirectoryReady=$true;RequiredArtifactManifestConfigured=$true;PublisherAvailable=$true;PackageValidationExecuted=$true;PackageValidationPassed=$true;PackageValidationErrorCount=0}}
        [ordered]@{Identifier='pcsx2x6 crosshair path (issue #79)';Applicable=$false;Data=[ordered]@{Present=$false;CanonicalFilesDeployed=$false;LegacyRootPresent=$false;IniFound=$false;CursorPathPointsCanonical=$false;Pcsx2Directory=$null}}
        [ordered]@{Identifier='Behavioral Certification (Virtual Beta Tester)';Applicable=$true;Data=[ordered]@{Executed=$true;Total=1;Passed=1;Failed=0;HumanBehaviors=0;IdempotencyChecks=0;RecoveryBehaviors=0;EnvironmentVariations=0;HighTvdBehaviors=0}}
        [ordered]@{Identifier='Unattended TPM root binding';Applicable=$false;Data=[ordered]@{RequestedRoot='C:\preflight';EffectiveRoot=$null;EffectiveRootParseState='Missing'}}
        [ordered]@{Identifier='Unattended TPM config restoration';Applicable=$false;Data=[ordered]@{}}
    )
}

function New-TPMOwnedScratchDirectoryV1 {
    # Creates and owns exactly ONE unique child directory beneath a
    # validated parent. The parent itself (which may be a pre-existing,
    # caller-supplied, or otherwise broadly-scoped directory) is never
    # owned, never modified beyond containing this one child, and never
    # recursively deleted -- only the exact child this call creates is ever
    # a candidate for later recursive removal (Remove-TPMOwnedScratchDirectoryV1).
    param([Parameter(Mandatory=$true)][string]$ParentRoot,[string]$ChildName)
    if(-not(Test-Path -LiteralPath $ParentRoot -PathType Container)){[void](New-Item -ItemType Directory -Path $ParentRoot -Force)}
    $normalizedParent=[IO.Path]::GetFullPath($ParentRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if([string]::IsNullOrWhiteSpace($ChildName)){$ChildName=[guid]::NewGuid().ToString('N')}
    $candidate=Join-Path $normalizedParent $ChildName
    $full=[IO.Path]::GetFullPath($candidate)
    try{$contained=Resolve-TPMContainedPathV1 -Root $normalizedParent -Path $full}catch{throw 'SCRATCH_CHILD_OUTSIDE_ROOT'}
    if($contained-cne$full){throw 'SCRATCH_CHILD_OUTSIDE_ROOT'}
    if(Test-Path -LiteralPath $full){throw 'SCRATCH_CHILD_ALREADY_EXISTS'}
    [void](New-Item -ItemType Directory -Path $full -ErrorAction Stop)
    $item=Get-Item -LiteralPath $full -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'SCRATCH_CHILD_REPARSE_POINT'}
    return [pscustomobject]@{Path=$full;ParentRoot=$normalizedParent;Owned=$true}
}

function Remove-TPMOwnedScratchDirectoryV1 {
    # Recursively removes ONLY the exact child New-TPMOwnedScratchDirectoryV1
    # created and returned -- never the parent, never a path that no longer
    # verifiably resolves inside that parent, and never a path that has
    # since become (or already was) a reparse point.
    param([Parameter(Mandatory=$true)]$Owned)
    if(-not$Owned.Owned){return $true}
    try{
        try{$contained=Resolve-TPMContainedPathV1 -Root $Owned.ParentRoot -Path $Owned.Path}catch{return $false}
        if($contained-cne$Owned.Path){return $false}
        if(-not(Test-Path -LiteralPath $Owned.Path -PathType Container)){return $true}
        $item=Get-Item -LiteralPath $Owned.Path -Force
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
        Remove-Item -LiteralPath $Owned.Path -Recurse -Force -ErrorAction Stop
        return $true
    }catch{return $false}
}

function Test-TPMProductionPackagePreflightV1 {
    # Genuine preflight: rather than trusting Get-Command's ambient
    # visibility as the dependency contract, this actually drives a
    # synthetic run through the real production authority and every real
    # report/publication command, entirely inside its own single owned
    # scratch child directory beneath PreflightScratchRoot -- never the
    # caller's real StagingParentRoot/DestinationRoot, and never
    # PreflightScratchRoot itself, which is never recursively deleted. A
    # stubbed or broken command is caught by genuine execution failure, not
    # just name resolution. The caller's real StagingParentRoot/
    # DestinationRoot are checked separately, only for write-reservation,
    # never populated with synthetic certification-looking artifacts.
    param(
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][string]$PreflightScratchRoot
    )
    $errorCount=0

    $stagingReady=$false
    try{
        if(-not(Test-Path -LiteralPath $StagingParentRoot -PathType Container)){[void](New-Item -ItemType Directory -Path $StagingParentRoot -Force)}
        $probe=Join-Path $StagingParentRoot ('.preflight-probe-'+[guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe,'preflight');Remove-Item -LiteralPath $probe -Force
        $stagingReady=$true
    }catch{$errorCount++}

    $destinationReady=$false
    try{
        if(-not(Test-Path -LiteralPath $DestinationRoot -PathType Container)){[void](New-Item -ItemType Directory -Path $DestinationRoot -Force)}
        $probe=Join-Path $DestinationRoot ('.preflight-probe-'+[guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe,'preflight');Remove-Item -LiteralPath $probe -Force
        $destinationReady=$true
    }catch{$errorCount++}

    $publisherAvailable=$false
    $canonicalNamesMatch=$false
    $owned=$null
    try{
        $owned=New-TPMOwnedScratchDirectoryV1 -ParentRoot $PreflightScratchRoot
        $runRoot=$owned.Path
        $evidenceRoot=[IO.Path]::GetFullPath((Join-Path $runRoot 'evidence'));$scratchStaging=Join-Path $runRoot 'staging';$scratchDestination=Join-Path $runRoot 'destination'
        [void](New-Item -ItemType Directory -Path $evidenceRoot,$scratchStaging,$scratchDestination -Force)
        $validator={param($Path)[pscustomobject]@{Valid=$true;Reason='preflight';Width=1;Height=1}}
        $authority=New-TPMProductionWorkflowAuthorityV1 -Mode Smoke -EvidenceRoot $evidenceRoot -ReportRoot $evidenceRoot -PngValidator $validator
        foreach($fact in (New-TPMPreflightSyntheticFactsV1 -ReportRoot $evidenceRoot)){&$authority RecordFact $fact}
        $ids=@('certification-suite-running','requested-effective-root-evidence','live-thumbnail-evidence','live-controls-evidence','adaptive-menu-normal','adaptive-menu-small','adaptive-menu-maximized','smoke-file-safety-evidence')
        $types=@('ScreenCapture','ScreenCapture',$null,$null,'DeterministicRender','DeterministicRender','DeterministicRender','DeterministicRender')
        for($i=0;$i-lt$ids.Count;$i++){
            if($i-in2,3){
                &$authority RecordEvidence ([ordered]@{Identifier=$ids[$i];Status='Skipped';EvidenceType=$null;Required=$false;Path=$null;CaptureScope=$null;FileSha256=$null;Width=$null;Height=$null;FailureCode='EVIDENCE_SKIPPED';FailureMessage='preflight synthetic run: optional evidence not exercised'})
                continue
            }
            $path=Join-Path $evidenceRoot ("$i.png");[IO.File]::WriteAllBytes($path,(New-TPMPreflightPngBytesV1 -Seed $i))
            $sha=[Security.Cryptography.SHA256]::Create();try{$hash=-join($sha.ComputeHash([IO.File]::ReadAllBytes($path))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}
            $scope=if($types[$i]-ceq'ScreenCapture'){'ConsoleWindow'}else{'Deterministic'}
            &$authority RecordEvidence ([ordered]@{Identifier=$ids[$i];Status='Captured';EvidenceType=$types[$i];Required=$true;Path=$path;CaptureScope=$scope;FileSha256=$hash;Width=1;Height=1;FailureCode=$null;FailureMessage=$null})
        }
        $preview=&$authority DeriveScorePreview
        $finalPath=Join-Path $evidenceRoot '8.png';[IO.File]::WriteAllBytes($finalPath,(New-TPMPreflightPngBytesV1 -Seed 8))
        $sha=[Security.Cryptography.SHA256]::Create();try{$finalHash=-join($sha.ComputeHash([IO.File]::ReadAllBytes($finalPath))|ForEach-Object{$_.ToString('x2')})}finally{$sha.Dispose()}
        &$authority IssueFinalEvidence ([ordered]@{Identifier='final-certification-result';Status='Captured';EvidenceType='ScreenCapture';Required=$true;Path=$finalPath;CaptureScope='ConsoleWindow';FileSha256=$finalHash;Width=1;Height=1;FailureCode=$null;FailureMessage=$null}) $preview
        $sealedRun=&$authority Seal
        $eligibility=&$authority IssueEligibility $sealedRun
        $publicationCandidate=&$authority IssuePublicationCandidate $eligibility

        $eligibilityReport=New-TPMEligibilityReportV1 -Eligibility $eligibility
        $publicationReport=New-TPMPublicationReportV1 -PublicationCandidate $publicationCandidate
        $finalOutcomeCandidateReport=New-TPMFinalOutcomeCandidateReportV1 -Eligibility $eligibility
        $scorecardReport=New-TPMScorecardReportV1 -Eligibility $eligibility
        $validationReport=New-TPMValidationReportV1 -SealedRun $sealedRun -Eligibility $eligibility
        $manifestReport=New-TPMManifestReportV1 -Eligibility $eligibility -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport
        $markerReport=New-TPMCommitMarkerReportV1 -Manifest $manifestReport

        $observedNames=@($eligibilityReport.FileName,$publicationReport.FileName,$finalOutcomeCandidateReport.FileName,$scorecardReport.FileName,$validationReport.FileName,$manifestReport.FileName,$markerReport.FileName)
        $expectedNames=@($script:TpmProductionCanonicalArtifactFileNamesV1)
        $canonicalNamesMatch=(@(Compare-Object $expectedNames $observedNames -SyncWindow 0).Count -eq 0)

        $commit=New-TPMPublicationCommitV1 -StagingParentRoot $scratchStaging -DestinationRoot $scratchDestination -EligibilityReport $eligibilityReport -PublicationReport $publicationReport -FinalOutcomeReport $finalOutcomeCandidateReport -ScorecardReport $scorecardReport -ValidationReport $validationReport -Manifest $manifestReport -Marker $markerReport
        $publisherAvailable=($canonicalNamesMatch -and $null-ne$commit -and [bool]$commit.Committed)
    }catch{$publisherAvailable=$false;$canonicalNamesMatch=$false}
    $cleanupSucceeded=$true
    if($null-ne$owned){$cleanupSucceeded=Remove-TPMOwnedScratchDirectoryV1 -Owned $owned}
    if(-not$publisherAvailable){$errorCount++}
    if(-not$cleanupSucceeded){$errorCount++}

    # Cleanup failure must never be masked by an otherwise-successful
    # pipeline proof -- PackageValidationPassed folds it in explicitly.
    $passed=$stagingReady-and$destinationReady-and$publisherAvailable-and$cleanupSucceeded
    return [ordered]@{StagingDirectoryReady=$stagingReady;PublisherAvailable=$publisherAvailable;PackageValidationExecuted=$true;PackageValidationPassed=$passed;PackageValidationErrorCount=$errorCount}
}

function Get-TPMProductionTreeSha256V1 {
    param([string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Container)){return $null}
    $items=New-Object Collections.Generic.List[object]
    foreach($file in @(Get-ChildItem -LiteralPath $Path -File -Recurse|Sort-Object FullName)){
        $relative=$file.FullName.Substring([IO.Path]::GetFullPath($Path).TrimEnd('\').Length).TrimStart('\').Replace('\','/')
        $items.Add([ordered]@{Path=$relative;Sha256=(Get-TPMSha256HexV1 -Bytes ([IO.File]::ReadAllBytes($file.FullName)))})
    }
    return Get-TPMSha256HexV1 -Bytes ((New-Object Text.UTF8Encoding $false).GetBytes((ConvertTo-TPMJcsV1 $items.ToArray())))
}

function New-TPMProductionFactRecordsV1 {
    param(
        $Results,
        [Parameter(Mandatory=$true)][string]$RepositoryPath,
        [Parameter(Mandatory=$true)][string]$ReportDirectory,
        [Parameter(Mandatory=$true)][string]$BackupDirectory,
        $HealthResult,
        [string]$HealthLoadError,
        $UnattendedBinding,
        [Parameter(Mandatory=$true)][string]$StagingParentRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][string]$WorkingDirectoryRoot,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory,
        [string]$DispositionRegistryPath,
        [string]$PSScriptAnalyzerSettingsPath
    )
    $mode=if($Results.SmokeMode){'Smoke'}else{'Unattended'}
    $checks=@{};foreach($c in @($Results.Checks)){$checks[[string]$c.Name]=[bool]$c.Passed}
    $testDigest=Get-TPMProductionTreeSha256V1 (Join-Path $RepositoryPath 'Tests')

    $healthPath=Join-Path $ReportDirectory 'InstallHealth\InstallHealth.json'
    if($HealthLoadError){
        $healthState=if(Test-Path -LiteralPath $healthPath -PathType Leaf){'InvalidJson'}else{'Missing'}
    }else{
        if($null-eq$HealthResult){
            throw 'PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult is null without an explicit load error'
        }
        if($HealthResult-isnot[Management.Automation.PSCustomObject]){
            throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult must be a PSCustomObject, found $($HealthResult.GetType().FullName)"
        }
        if(@($HealthResult.PSObject.Properties.Name)-cnotcontains'Checks'){
            throw 'PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks is missing'
        }
        if($null-eq$HealthResult.Checks){
            throw 'PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks is null'
        }
        $healthState='Loaded'
    }
    $healthChecks=@()
    if($healthState-ceq'Loaded'){
        $rawHealthChecks=$HealthResult.Checks
        if($rawHealthChecks-is[string]-or$rawHealthChecks-isnot[Collections.IEnumerable]){
            throw 'PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks must be a non-empty collection'
        }
        $validatedHealthChecks=@()
        $healthIndex=0
        foreach($entry in $rawHealthChecks){
            if($null-eq$entry){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks[$healthIndex] is null"
            }
            if($entry-isnot[Management.Automation.PSCustomObject]){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks[$healthIndex] must be a PSCustomObject"
            }
            $entryProperties=@($entry.PSObject.Properties.Name)
            if($entryProperties-cnotcontains'Name'){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks[$healthIndex].Name is missing"
            }
            if($entry.Name-isnot[string]-or[string]::IsNullOrWhiteSpace([string]$entry.Name)){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks[$healthIndex].Name must be a nonblank string"
            }
            if($entryProperties-cnotcontains'Passed'){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks[$healthIndex].Passed is missing"
            }
            if($entry.Passed-isnot[bool]){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks[$healthIndex].Passed must be Boolean"
            }
            $validatedHealthChecks+=,[pscustomobject]@{Name=[string]$entry.Name;Passed=[bool]$entry.Passed}
            $healthIndex++
        }
        if($validatedHealthChecks.Count-eq0){
            throw 'PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: HealthResult.Checks must not be empty'
        }
        foreach($name in @('TeknoParrotUi.exe exists','GameProfiles folder exists','UserProfiles folder exists')){
            $healthMatches=@($validatedHealthChecks|Where-Object{$_.Name-ceq$name})
            if($healthMatches.Count-eq0){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: required health check '$name' is missing"
            }
            if($healthMatches.Count-ne1){
                throw "PRODUCTION_HEALTH_RESULT_SCHEMA_INVALID: required health check '$name' is duplicated"
            }
            $healthChecks+=,[ordered]@{Name=$name;Passed=[bool]$healthMatches[0].Passed}
        }
    }

    $userBackup=Join-Path $BackupDirectory 'UserProfiles';$gameBackup=Join-Path $BackupDirectory 'GameProfiles'
    $userCreated=[bool]$Results.Backup.UserProfiles;$gameCreated=[bool]$Results.Backup.GameProfiles
    $userHash=if($userCreated){Get-TPMProductionTreeSha256V1 $userBackup}else{$null}
    $gameHash=if($gameCreated){Get-TPMProductionTreeSha256V1 $gameBackup}else{$null}

    $snapshots=if($mode-ceq'Smoke'){$Results.Snapshots}else{$null}
    $pcsx=$Results.Pcsx2x6;$pcsxPresent=[bool]$pcsx.Present
    $pcsxCanonical=if($pcsxPresent){[bool]$pcsx.CanonicalFilesDeployed}else{$false}
    $pcsxLegacy=if($pcsxPresent){[bool]$pcsx.LegacyRootFilesPresent}else{$false}
    $pcsxIni=if($pcsxPresent){[bool]$pcsx.IniFound}else{$false}
    $pcsxCursor=if($pcsxPresent){[bool]$pcsx.CursorPathPointsCanonical}else{$false}
    $vbt=$Results.VirtualBetaTester;$binding=$UnattendedBinding

    $inventory=Get-TPMProductionPowerShellInventoryV1 -RepositoryPath $RepositoryPath
    if([string]::IsNullOrWhiteSpace($DispositionRegistryPath)){$DispositionRegistryPath=Join-Path $PSScriptRoot 'InjectionHunterDispositions.psd1'}
    if([string]::IsNullOrWhiteSpace($PSScriptAnalyzerSettingsPath)){$PSScriptAnalyzerSettingsPath=Join-Path $RepositoryPath 'PSScriptAnalyzerSettings.psd1'}

    $parserWin=Test-TPMProductionParserProbeV1 -Inventory $inventory -Engine 'WindowsPowerShell51' -WorkingDirectoryRoot $WorkingDirectoryRoot -WorkingDirectory $WorkingDirectory
    $parserPwsh=Test-TPMProductionParserProbeV1 -Inventory $inventory -Engine 'Pwsh' -WorkingDirectoryRoot $WorkingDirectoryRoot -WorkingDirectory $WorkingDirectory
    $encoding=Test-TPMProductionEncodingV1 -Inventory $inventory
    $psAnalyzer=Test-TPMProductionPSScriptAnalyzerV1 -Inventory $inventory -SettingsPath $PSScriptAnalyzerSettingsPath
    $injectionHunter=Test-TPMProductionInjectionHunterV1 -Inventory $inventory -DispositionRegistryPath $DispositionRegistryPath

    $staticAnalysisFact=[ordered]@{
        Identifier='Static Analysis';Applicable=$true;Data=[ordered]@{
            Parser=@([ordered]@{Identifier=$parserWin.Identifier;Executed=$parserWin.Executed;ErrorCount=$parserWin.ErrorCount;ToolVersion=$parserWin.ToolVersion},[ordered]@{Identifier=$parserPwsh.Identifier;Executed=$parserPwsh.Executed;ErrorCount=$parserPwsh.ErrorCount;ToolVersion=$parserPwsh.ToolVersion})
            Encoding=[ordered]@{Executed=$encoding.Executed;NonAsciiByteCount=$encoding.NonAsciiByteCount;Files=$encoding.Files}
            PSScriptAnalyzer=[ordered]@{Executed=$psAnalyzer.Executed;FindingCount=$psAnalyzer.FindingCount;ToolVersion=$psAnalyzer.ToolVersion}
            InjectionHunter=[ordered]@{Executed=$injectionHunter.Executed;FindingCount=$injectionHunter.FindingCount;UnresolvedFindingCount=$injectionHunter.UnresolvedFindingCount;ToolVersion=$injectionHunter.ToolVersion;Dispositions=$injectionHunter.Dispositions}
        }
    }

    $preflightScratchRoot=Join-Path $WorkingDirectory ('artifacts-preflight-'+[guid]::NewGuid().ToString('N'))
    $artifactsPreflight=Test-TPMProductionPackagePreflightV1 -StagingParentRoot $StagingParentRoot -DestinationRoot $DestinationRoot -PreflightScratchRoot $preflightScratchRoot
    $reportDirectoryReserved=Test-Path -LiteralPath $ReportDirectory -PathType Container
    $artifactsFact=[ordered]@{
        Identifier='Artifacts';Applicable=$true;Data=[ordered]@{
            ReportDirectory=[IO.Path]::GetFullPath($ReportDirectory)
            ReportDirectoryReserved=$reportDirectoryReserved
            StagingDirectoryReady=$artifactsPreflight.StagingDirectoryReady
            RequiredArtifactManifestConfigured=$true
            PublisherAvailable=$artifactsPreflight.PublisherAvailable
            PackageValidationExecuted=$artifactsPreflight.PackageValidationExecuted
            PackageValidationPassed=$artifactsPreflight.PackageValidationPassed
            PackageValidationErrorCount=$artifactsPreflight.PackageValidationErrorCount
        }
    }

    return @(
        [ordered]@{Identifier='Repository';Applicable=$true;Data=[ordered]@{RepositoryPath=[IO.Path]::GetFullPath($RepositoryPath);RepositoryAvailable=[bool]$checks['Repository available'];RepositoryClean=($Results.GitStatus-ceq'(clean)');GitStatus=[string]$Results.GitStatus}}
        [ordered]@{Identifier='Pester';Applicable=$true;Data=[ordered]@{Executed=($null-ne$Results.Pester);Total=[int]$Results.Pester.Total;Passed=[int]$Results.Pester.Passed;Failed=[int]$Results.Pester.Failed;Skipped=[int]$Results.Pester.Skipped;NotRun=[int]$Results.Pester.NotRun;Engine=("Pester {0} / PowerShell {1}"-f$Results.PesterVersion,$Results.PowerShellVersion);SuiteSha256=$testDigest}}
        $staticAnalysisFact
        [ordered]@{Identifier='Real Install Health';Applicable=$true;Data=[ordered]@{ReportPath=$(if(Test-Path -LiteralPath $healthPath -PathType Leaf){[IO.Path]::GetFullPath($healthPath)}else{$null});LoadState=$healthState;LoadError=$(if($healthState-ceq'Loaded'){$null}else{[string]$HealthLoadError});Checks=$healthChecks}}
        [ordered]@{Identifier='Backups';Applicable=$true;Data=[ordered]@{UserProfilesBackupCreated=$userCreated;UserProfilesBackupPath=$(if($userCreated){[IO.Path]::GetFullPath($userBackup)}else{$null});UserProfilesBackupVerified=($userCreated-and$null-ne$userHash);UserProfilesBackupSha256=$userHash;GameProfilesBackupCreated=$gameCreated;GameProfilesBackupPath=$(if($gameCreated){[IO.Path]::GetFullPath($gameBackup)}else{$null});GameProfilesBackupVerified=($gameCreated-and$null-ne$gameHash);GameProfilesBackupSha256=$gameHash;BackupVerificationExecuted=$true}}
        $(if($mode-ceq'Smoke'){[ordered]@{Identifier='Smoke File Safety';Applicable=$true;Data=[ordered]@{UserProfiles=[ordered]@{Added=[int]$snapshots.UserProfiles.Added;Removed=[int]$snapshots.UserProfiles.Removed;Changed=[int]$snapshots.UserProfiles.Changed;BeforeSkipped=[int]$snapshots.UserProfiles.BeforeSkipped;AfterSkipped=[int]$snapshots.UserProfiles.AfterSkipped};GameProfiles=[ordered]@{Added=[int]$snapshots.GameProfiles.Added;Removed=[int]$snapshots.GameProfiles.Removed;Changed=[int]$snapshots.GameProfiles.Changed;BeforeSkipped=[int]$snapshots.GameProfiles.BeforeSkipped;AfterSkipped=[int]$snapshots.GameProfiles.AfterSkipped};Pcsx2x6Crosshairs=[ordered]@{Added=[int]$snapshots.Pcsx2x6Crosshairs.Added;Removed=[int]$snapshots.Pcsx2x6Crosshairs.Removed;Changed=[int]$snapshots.Pcsx2x6Crosshairs.Changed;BeforeSkipped=[int]$snapshots.Pcsx2x6Crosshairs.BeforeSkipped;AfterSkipped=[int]$snapshots.Pcsx2x6Crosshairs.AfterSkipped}}}}else{[ordered]@{Identifier='Smoke File Safety';Applicable=$false;Data=[ordered]@{}}})
        $artifactsFact
        [ordered]@{Identifier='pcsx2x6 crosshair path (issue #79)';Applicable=$pcsxPresent;Data=[ordered]@{Present=$pcsxPresent;CanonicalFilesDeployed=$pcsxCanonical;LegacyRootPresent=$pcsxLegacy;IniFound=$pcsxIni;CursorPathPointsCanonical=$pcsxCursor;Pcsx2Directory=$(if($pcsxPresent){[IO.Path]::GetFullPath([string]$pcsx.Pcsx2Dir)}else{$null})}}
        [ordered]@{Identifier='Behavioral Certification (Virtual Beta Tester)';Applicable=$true;Data=[ordered]@{Executed=($null-ne$vbt);Total=[int]$vbt.Total;Passed=[int]$vbt.Passed;Failed=[int]$vbt.Failed;HumanBehaviors=[int]$vbt.HumanBehaviors;IdempotencyChecks=[int]$vbt.IdempotencyChecks;RecoveryBehaviors=[int]$vbt.RecoveryBehaviors;EnvironmentVariations=[int]$vbt.EnvironmentVariations;HighTvdBehaviors=[int]$vbt.HighTvdBehaviors}}
        $(if($mode-ceq'Smoke'){[ordered]@{Identifier='Unattended TPM root binding';Applicable=$false;Data=[ordered]@{RequestedRoot=[IO.Path]::GetFullPath([string]$Results.RequestedTeknoParrotRoot);EffectiveRoot=$null;EffectiveRootParseState='Missing'}}}else{[ordered]@{Identifier='Unattended TPM root binding';Applicable=$true;Data=[ordered]@{RequestedRoot=[IO.Path]::GetFullPath([string]$Results.RequestedTeknoParrotRoot);EffectiveRoot=$(if($Results.EffectiveTeknoParrotRoot){[IO.Path]::GetFullPath([string]$Results.EffectiveTeknoParrotRoot)}else{$null});EffectiveRootParseState=$(if($Results.EffectiveTeknoParrotRoot){'Parsed'}else{'Missing'})}}})
        $(if($mode-ceq'Smoke'){[ordered]@{Identifier='Unattended TPM config restoration';Applicable=$false;Data=[ordered]@{}}}else{[ordered]@{Identifier='Unattended TPM config restoration';Applicable=$true;Data=[ordered]@{PriorConfigExisted=[bool]$binding.PriorConfigExisted;TemporaryConfigCreated=[bool]$binding.TemporaryConfigCreated;RestoreAttempted=[bool]$binding.RestoreAttempted;RestoreSucceeded=[bool]$binding.RestoreSucceeded;VerificationSucceeded=[bool]$binding.VerificationSucceeded;SnapshotSha256=$binding.SnapshotSha256;FailureReason=$binding.RestorationFailureReason}}})
    )
}

# Minimal public surface, deliberately. Every other function in this module
# (parser/PSScriptAnalyzer/InjectionHunter probes, the bounded-execution and
# external-process primitives, the disposition-registry validator, and --
# most importantly -- the scratch-directory creation/removal primitives) is
# an implementation detail, not a caller-facing API. Exporting
# New-/Remove-TPMOwnedScratchDirectoryV1 would let any caller forge an
# "Owned=$true" descriptor with an arbitrary ParentRoot/Path and invoke a
# public recursive-deletion capability -- ownership represented by a
# caller-constructible PSCustomObject is not an authorization boundary.
# Tests reach every private function directly via Pester's InModuleScope.
# If a genuine B2 caller needs another function exported, document the exact
# caller and reason here before adding it.
Export-ModuleMember -Function Get-TPMProductionPowerShellInventoryV1,New-TPMProductionFactRecordsV1
