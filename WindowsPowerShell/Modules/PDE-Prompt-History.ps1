# 3. Successful-command learning through the existing prompt
# ---------------------------------------------------------------------------
# Preserve the user's prompt output while recording successful commands as
# they finish.  This keeps PDE's green history-prefix colour live during the
# current session instead of requiring a manual history refresh.
if (-not $global:PDE_OriginalPrompt) {
    $global:PDE_OriginalPrompt = $function:prompt
}
if ($null -eq $global:PDE_LastHistId) {
    try {
        $initialHistoryItem = Get-History -Count 1 -ErrorAction SilentlyContinue
        if ($initialHistoryItem) { $global:PDE_LastHistId = $initialHistoryItem.Id }
    } catch { }
}

function global:prompt {
    $lastCommandSucceeded = $?

    try {
        $lastHistoryItem = Get-History -Count 1 -ErrorAction SilentlyContinue
        if ($lastHistoryItem -and $lastHistoryItem.Id -ne $global:PDE_LastHistId) {
            $global:PDE_LastHistId = $lastHistoryItem.Id
            if ($lastCommandSucceeded -and $lastHistoryItem.CommandLine) {
                Add-PDEHistoryEntry -Line ([string]$lastHistoryItem.CommandLine) -PromoteDuplicate
            }
        }
    }
    catch {
        Write-PDELog -Level WARN -Message ("Prompt history tracking failed: {0}" -f $_.Exception.Message)
    }

    if ($global:PDE_OriginalPrompt) {
        $originalPromptText = & $global:PDE_OriginalPrompt
        if ($null -ne $originalPromptText) { return $originalPromptText }
    }

    return "PS $($executionContext.SessionState.Path.CurrentLocation)> "
}

# ---------------------------------------------------------------------------
