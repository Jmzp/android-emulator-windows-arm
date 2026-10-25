# PSScriptAnalyzer settings used by the lint workflow (.github/workflows/lint.yml).
# Run locally with: Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # These are interactive console scripts: Write-Host is the intended output.
        'PSAvoidUsingWriteHost'
        # Internal helpers, not cmdlets; -WhatIf / -Confirm would add nothing.
        'PSUseShouldProcessForStateChangingFunctions'
        'PSUseSingularNouns'
        # Variables in common.ps1 are dot-sourced into other scripts, and script
        # parameters are read inside functions; the analyzer can't see either use.
        'PSUseDeclaredVarsMoreThanAssignments'
        'PSReviewUnusedParameter'
        # Flags "2>$null" inside if (...) conditions, which is intended.
        'PSPossibleIncorrectUsageOfRedirectionOperator'
        # Flags param() blocks in Start-Job script blocks, which don't need $using:.
        'PSUseUsingScopeModifierInNewRunspaces'
    )
}
