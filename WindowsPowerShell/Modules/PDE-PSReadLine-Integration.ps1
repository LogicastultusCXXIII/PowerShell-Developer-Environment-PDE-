# 8. PSReadLine configuration and keyboard integration
# ---------------------------------------------------------------------------
function global:Invoke-PDEApplyOptions {
    [CmdletBinding()]
    param()

    $setCommand = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
    if (-not $setCommand) { throw 'Set-PSReadLineOption is unavailable.' }

    $currentOptions = Get-PSReadLineOption
    $colorPropertyMap = @{
        Command            = 'CommandColor'
        Parameter          = 'ParameterColor'
        Variable           = 'VariableColor'
        String             = 'StringColor'
        Number             = 'NumberColor'
        Type               = 'TypeColor'
        Member             = 'MemberColor'
        Keyword            = 'KeywordColor'
        Operator           = 'OperatorColor'
        Comment            = 'CommentColor'
        Error              = 'ErrorColor'
        Default            = 'DefaultTokenColor'
        ContinuationPrompt = 'ContinuationPromptColor'
        Emphasis           = 'EmphasisColor'
        InlinePrediction   = 'InlinePredictionColor'
        ListPrediction     = 'ListPredictionColor'
    }

    # ConsoleColor values work across Windows PowerShell 5.1 and PowerShell 7.
    $desiredColors = @{
        Command                 = [ConsoleColor]::Yellow
        Parameter               = [ConsoleColor]::Yellow
        Variable                = [ConsoleColor]::Magenta
        String                  = [ConsoleColor]::DarkYellow
        Number                  = [ConsoleColor]::Cyan
        Type                    = [ConsoleColor]::Cyan
        Member                  = [ConsoleColor]::Cyan
        Keyword                 = [ConsoleColor]::Blue
        Operator                = [ConsoleColor]::DarkGray
        Comment                 = [ConsoleColor]::DarkGray
        Error                   = [ConsoleColor]::Red
        Default                 = [ConsoleColor]::Gray
        ContinuationPrompt      = [ConsoleColor]::DarkGray
        Emphasis                = [ConsoleColor]::Cyan
        InlinePrediction        = [ConsoleColor]::DarkGray
        ListPrediction          = [ConsoleColor]::DarkYellow
    }

    $supportedColors = @{}
    foreach ($colorName in $desiredColors.Keys) {
        $propertyName = $colorPropertyMap[$colorName]
        if ($currentOptions.PSObject.Properties[$propertyName]) {
            $supportedColors[$colorName] = $desiredColors[$colorName]
        }
    }

    $arguments = @{}
    if ($setCommand.Parameters.ContainsKey('Colors') -and $supportedColors.Count -gt 0) {
        $arguments.Colors = $supportedColors
    }
    if ($setCommand.Parameters.ContainsKey('HistoryNoDuplicates')) {
        $arguments.HistoryNoDuplicates = $true
    }
    if ($setCommand.Parameters.ContainsKey('HistorySearchCursorMovesToEnd')) {
        $arguments.HistorySearchCursorMovesToEnd = $true
    }
    if ($setCommand.Parameters.ContainsKey('MaximumHistoryCount')) {
        $arguments.MaximumHistoryCount = [int]$global:PDE_Config.MaximumHistoryCount
    }
    if ($setCommand.Parameters.ContainsKey('ShowToolTips')) {
        $arguments.ShowToolTips = [bool]$global:PDE_Config.EnableToolTips
    }

    $global:PDE_State.PredictionAvailable = $false
    $global:PDE_State.PredictionViewStyleEffective = 'InlineView'
    $global:PDE_State.PredictionReason = 'This PSReadLine version does not expose predictive IntelliSense.'

    if ($setCommand.Parameters.ContainsKey('PredictionSource')) {
        if ($global:PDE_Config.EnablePredictions) {
            $arguments.PredictionSource = 'History'
            $global:PDE_State.PredictionAvailable = $true
            if ($setCommand.Parameters.ContainsKey('PredictionViewStyle')) {
                $arguments.PredictionViewStyle = [string]$global:PDE_Config.PredictionViewStyle
                $global:PDE_State.PredictionViewStyleEffective = [string]$global:PDE_Config.PredictionViewStyle
            }
            $global:PDE_State.PredictionReason = 'History-based predictive IntelliSense enabled.'
        }
        else {
            $arguments.PredictionSource = 'None'
            $global:PDE_State.PredictionReason = 'Predictions disabled by PDE configuration.'
        }
    }

    if ($arguments.Count -gt 0) {
        Set-PSReadLineOption @arguments -ErrorAction Stop
    }

    if ($global:PDE_State.PredictionAvailable -and $global:PDE_State.PredictionViewStyleEffective -eq 'ListView') {
        # In ListView, Up/Down navigate the prediction menu. F8/Shift+F8
        # remain available for prefix-history search.
        try { Set-PSReadLineKeyHandler -Chord 'UpArrow' -Function 'PreviousSuggestion' -ErrorAction Stop } catch { }
        try { Set-PSReadLineKeyHandler -Chord 'DownArrow' -Function 'NextSuggestion' -ErrorAction Stop } catch { }
        if ($global:PDE_Config.EnableHistorySearch) {
            try { Set-PSReadLineKeyHandler -Chord 'F8' -Function 'HistorySearchBackward' -ErrorAction Stop } catch { }
            try { Set-PSReadLineKeyHandler -Chord 'Shift+F8' -Function 'HistorySearchForward' -ErrorAction Stop } catch { }
        }
    }
    elseif ($global:PDE_Config.EnableHistorySearch) {
        try { Set-PSReadLineKeyHandler -Chord 'UpArrow' -Function 'HistorySearchBackward' -ErrorAction Stop } catch {
            Write-PDELog -Level WARN -Message ("Could not bind UpArrow history search: {0}" -f $_.Exception.Message)
        }
        try { Set-PSReadLineKeyHandler -Chord 'DownArrow' -Function 'HistorySearchForward' -ErrorAction Stop } catch {
            Write-PDELog -Level WARN -Message ("Could not bind DownArrow history search: {0}" -f $_.Exception.Message)
        }
    }
    else {
        # Restore ordinary history navigation when the PDE search option is off.
        try { Set-PSReadLineKeyHandler -Chord 'UpArrow' -Function 'PreviousHistory' -ErrorAction Stop } catch { }
        try { Set-PSReadLineKeyHandler -Chord 'DownArrow' -Function 'NextHistory' -ErrorAction Stop } catch { }
    }

    # ForwardWord accepts the next word of an inline prediction when the
    # cursor is at the end of the input. Otherwise use standard word movement.
    if ($global:PDE_State.PredictionAvailable -and $global:PDE_State.PredictionViewStyleEffective -eq 'InlineView') {
        try { Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function 'ForwardWord' -ErrorAction Stop } catch { }
    }
    else {
        try { Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function 'NextWord' -ErrorAction Stop } catch { }
    }

    return [pscustomobject]@{
        PredictionsEnabled = $global:PDE_State.PredictionAvailable
        PredictionReason   = $global:PDE_State.PredictionReason
        PredictionViewStyle = $global:PDE_State.PredictionViewStyleEffective
        HistorySearch       = [bool]$global:PDE_Config.EnableHistorySearch
        ColorsConfigured    = $supportedColors.Count
    }
}

function global:Set-PDEOptions {
    [CmdletBinding()]
    param(
        [bool]$EnablePredictions,
        [ValidateSet('InlineView','ListView')][string]$PredictionViewStyle,
        [ValidateRange(100,100000)][int]$MaximumHistoryCount,
        [ValidateRange(100,10000)][int]$HistoryIndexLimit,
        [ValidateRange(1,4)][int]$FuzzyMaximumDistance,
        [bool]$EnableHistorySearch,
        [bool]$EnableToolTips,
        [bool]$EnableFuzzySuggestions,
        [bool]$EnableDiagnosticsLog
    )

    foreach ($key in $PSBoundParameters.Keys) {
        $global:PDE_Config[$key] = $PSBoundParameters[$key]
    }

    Invoke-PDEApplyOptions
}


# ---------------------------------------------------------------------------
