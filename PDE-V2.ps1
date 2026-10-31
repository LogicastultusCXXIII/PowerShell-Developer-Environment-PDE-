#requires -Version 5.1
# ============================================================================
# POWERSHELL DEVELOPER ENVIRONMENT (PDE)
# COMMAND INTELLIGENCE / PSREADLINE INTEGRATION
# Version: 3.1.2
# Compatibility: Windows PowerShell 5.1 and PowerShell 7+
#
# Purpose
#   * Add AST-based green/yellow/red command highlighting on safe single-line input.
#   * Enable history-backed predictive IntelliSense when supported.
#   * Provide prefix-based history navigation and native tab completion.
#   * Maintain a command / alias / executable index for PDE diagnostics.
#   * Provide AST-based command and syntax analysis utilities.
#   * Provide optional fuzzy command suggestions and command-risk inspection.
#   * Preserve the user's prompt; install a narrow printable-key handler for
#     the live colour overlay while leaving PSReadLine in control of editing.
#
# Installation
#   Keep this file and its Modules folder together, then dot-source this loader from your profile:
#       . "C:\Path\To\PDE-Command-Intelligence-Modular\PDE-Command-Intelligence.ps1"  # Replace with the file location
#   Windows PowerShell 5.1 profile path:
#       $PROFILE
#   PowerShell 7 profile path:
#       $PROFILE
#
# Useful commands after loading
#   Get-PDEStatus
#   Test-PDE
#   Update-PDEIndex -Force
#   Update-PDEHistory
#   Get-PDESuggestions -Prefix 'Get-Pro'
#   Get-PDESuggestions -Prefix 'Get-Procss' -Fuzzy
#   Get-PDECommandAnalysis -Text 'Get-Process | Where-Object { $_.CPU -gt 10 }'
#   Set-PDEOptions -PredictionViewStyle ListView
#
# Important design decisions
#   * PSReadLine owns line editing, cursor placement, terminal wrapping,
#     clipboard paste, predictions and native completion. PDE suspends its
#     highlighter during paste and runs it once after insertion has completed.
#   * Up/Down use PSReadLine's native prefix-history search in InlineView.
#   * No custom prompt function or manual Console.SetCursorPosition calls.
#   * The AST helper analyses text on request; it does not execute that text.
# ============================================================================

# ---------------------------------------------------------------------------
# 0. Dependency and host checks
# ---------------------------------------------------------------------------
try {
    Import-Module PSReadLine -ErrorAction Stop
}
catch {
    Write-Warning "PDE command intelligence could not load PSReadLine: $($_.Exception.Message)"
    return
}

$script:PDE_SetOptionCommand = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
$script:PDE_SetKeyCommand    = Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue

if (-not $script:PDE_SetOptionCommand -or -not $script:PDE_SetKeyCommand) {
    Write-Warning 'PDE command intelligence requires the PSReadLine configuration cmdlets.'
    return
}

# ---------------------------------------------------------------------------
# 1. Persistent configuration and runtime state
# ---------------------------------------------------------------------------
if (-not $global:PDE_Config) {
    $global:PDE_Config = [ordered]@{}
}

$PDE_DefaultConfig = @{
    EnablePredictions       = $true
    PredictionViewStyle     = 'InlineView'
    MaximumHistoryCount     = 10000
    HistoryIndexLimit       = 1000
    EnableHistorySearch     = $true
    EnableFuzzySuggestions  = $true
    FuzzyMaximumDistance    = 2
    EnableToolTips          = $true
    EnableDiagnosticsLog    = $false
    DiagnosticsLogPath      = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'PDE\PDE.log'
}

foreach ($PDE_Key in $PDE_DefaultConfig.Keys) {
    if (-not $global:PDE_Config.Contains($PDE_Key)) {
        $global:PDE_Config[$PDE_Key] = $PDE_DefaultConfig[$PDE_Key]
    }
}

if (-not $global:PDE_State) {
    $global:PDE_State = @{
        CommandNames       = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        CommandPrefixes    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        CommandInfo        = @{}
        History            = [System.Collections.Generic.List[string]]::new()
        HistorySet         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        LastIndexUpdate    = $null
        LastHistoryUpdate  = $null
        PredictionAvailable = $false
        PredictionViewStyleEffective = 'InlineView'
        PredictionReason   = 'Not configured'
        LastError          = $null
        Version            = '3.1.2'
    }
}

# Keep the runtime version current when this file is reloaded in an existing session.
$global:PDE_State.Version = '3.1.2'
$global:PDE_State.LiveHighlightingEnabled = $false
$global:PDE_State.PasteInProgress = $false

# Keep the original PDE collection names as compatibility references for any
# neighbouring profile functions that still read them.
$global:PDE_Cmds = $global:PDE_State.CommandNames
$global:PDE_Prefs = $global:PDE_State.CommandPrefixes
$global:PDE_Past = $global:PDE_State.History
$global:PDE_Suggestion = ''
$global:PDE_PrevLen = 0
$global:PDE_HistIdx = -1
$global:PDE_HistMatches = @()
$global:PDE_HistPrefix = ''

# ---------------------------------------------------------------------------
# 2. Load PDE feature modules
# ---------------------------------------------------------------------------
# Keep this file and the Modules folder together. Dot-sourcing the modules
# preserves the original global function names and shared runtime state.
$PDE_ModuleDirectory = Join-Path (Split-Path -Parent $PROFILE) 'Modules'
$PDE_ModuleFiles = @(
    'PDE-Logging.ps1'
    'PDE-Prompt-History.ps1'
    'PDE-Command-Index.ps1'
    'PDE-History-Index.ps1'
    'PDE-AST-Analysis.ps1'
    'PDE-Fuzzy-Suggestions.ps1'
    'PDE-PSReadLine-Integration.ps1'
    'PDE-Live-Highlighting.ps1'
    'PDE-Management-Diagnostics.ps1'
)

try {
    foreach ($PDE_ModuleFile in $PDE_ModuleFiles) {
        $PDE_ModulePath = Join-Path $PDE_ModuleDirectory $PDE_ModuleFile
        if (-not (Test-Path -LiteralPath $PDE_ModulePath -PathType Leaf)) {
            throw "Required PDE module was not found: $PDE_ModulePath"
        }
        . $PDE_ModulePath
    }
}
catch {
    Write-Warning "PDE command intelligence could not load its feature modules: $($_.Exception.Message)"
    return
}

# 11. Startup
# ---------------------------------------------------------------------------
try {
    $null = Update-PDEIndex -Force
    $null = Update-PDEHistory
    $configuration = Invoke-PDEApplyOptions
    Install-PDELiveHighlightHandlers

    Write-PDELog -Level INFO -Message 'PDE command intelligence initialised.'

    if (-not $global:PDE_State.PredictionAvailable) {
        Write-Verbose "PDE predictions unavailable: $($global:PDE_State.PredictionReason)"
    }
}
catch {
    $global:PDE_State.LastError = $_.Exception.Message
    Write-PDELog -Level ERROR -Message ("PDE initialisation failed: {0}" -f $_.Exception.Message)
    Write-Warning "PDE command intelligence initialisation encountered a problem: $($_.Exception.Message)"
}

# End of PDE Command Intelligence v3.1.2
