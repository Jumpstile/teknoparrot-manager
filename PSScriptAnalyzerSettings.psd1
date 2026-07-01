@{
    ExcludeRules = @(
        # Interactive CLI -- Write-Host is the intentional output mechanism throughout.
        'PSAvoidUsingWriteHost',

        # Empty catch blocks are intentional in optional/best-effort paths (registry
        # reads, BITS availability checks, optional service discovery). Each was
        # reviewed in the v0.91 security sweep. 27 instances as of v0.99.35.
        'PSAvoidUsingEmptyCatchBlock',

        # PostgreSQL credential parameters use plaintext strings because TeknoParrotUI
        # reads the Pass field directly from GameProfile XML at game-launch time.
        # SecureString would break TPUI's own connection. Accepted and documented risk;
        # see ARCHITECTURE.md (PostgreSQL section) and SECURITY.md.
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingUsernameAndPasswordParams',

        # Interactive CLI, not a reusable cmdlet or module. ShouldProcess (-WhatIf/
        # -Confirm support) does not apply; user confirmation is handled interactively
        # at each step in the menu flow.
        'PSUseShouldProcessForStateChangingFunctions',

        # Function names use plural nouns to match domain vocabulary
        # (e.g., Get-FFBBlasterFieldNames, Register-Games, Backup-LaunchBoxFiles).
        # These are internal helpers, not published cmdlets.
        'PSUseSingularNouns',

        # "Backfill" is a private helper verb not intended as a published cmdlet.
        'PSUseApprovedVerbs',

        # Parameters declared for interface consistency across related function
        # families. Reviewed; none are dead paths in current code.
        'PSReviewUnusedParameter',

        # Interactive script internals use short positional helper calls heavily
        # (Save-XmlMaybe, Resolve-RegisteredGameFolder, Set-XmlChildText, etc.).
        # This is a style rule, not a release safety rule, and mass-renaming those
        # call sites during feature freeze would create unnecessary churn.
        'PSAvoidUsingPositionalParameters',

        # Internal helper functions in the single-file script and updater module are
        # covered by README/docs plus focused Pester tests. Comment-based help on
        # every private helper would add noise without improving release safety.
        'PSProvideCommentHelp',

        # Write-Log is an internal helper. PSScriptAnalyzer flags it as overwriting a
        # PowerShell Core (6+) built-in, but this script targets Windows PowerShell 5.1
        # where no Write-Log cmdlet exists. False positive for the target runtime.
        'PSAvoidOverwritingBuiltInCmdlets',

        # Stylistic: $x -ne $null vs $null -ne $x. The affected comparisons are not
        # against pipeline-valued arrays; the functional risk the rule guards against
        # does not apply to these call sites.
        'PSPossibleIncorrectComparisonWithNull',

        # Two known instances as of v0.99.35:
        #   $branchEncoded (line ~3460) -- PSScriptAnalyzer false positive; the variable
        #     IS used in string interpolation on the very next line.
        #   $gpuSetupDone  -- removed in v0.99.35 (dead variable, never read).
        # Rule excluded because of the confirmed false positive for $branchEncoded.
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
