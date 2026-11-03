# ============================================================================
# PDE COMMAND INTELLIGENCE v3.1.2
# SECTION 2: INTERNAL LOGGING AND UTILITY FUNCTIONS
# Windows PowerShell 5.1 / PowerShell 7+
# ============================================================================

# ---------------------------------------------------------------------------
# 2.1 Compiled sensitive-history detection
# ---------------------------------------------------------------------------

# Version marker ensures that updated regex rules are rebuilt when the
# profile is reloaded, even when the number of patterns has not changed.

$PDE_SensitiveHistoryRegexVersion = 2

if (
    -not $global:PDE_SensitiveHistoryRegexes -or
    $global:PDE_SensitiveHistoryRegexVersion -ne $PDE_SensitiveHistoryRegexVersion -or
    $global:PDE_SensitiveHistoryRegexes.Count -ne 4
) {
    $PDE_SensitivePatterns = @(

        # Credential assignments, including compound variable names:
        # $password
        # $PDE_DummyPassword
        # $accessToken
        # $myApiKey
        # $clientSecret

        '(?i)(?:\$[A-Za-z_][A-Za-z0-9_]*(?:password|passwd|token|api[_-]?key|secret|authorization|bearer)[A-Za-z0-9_]*|\b(?:password|passwd|token|api[_-]?key|secret|client[_-]?secret|authorization|bearer)\b)\s*(?:=|:)\s*(?:"[^"]*"|''[^'']*''|[^\s;]+)',

        # Sensitive command-line parameters.
        # Supports -Password and --password, including quoted values.

        '(?i)(?:^|\s)-{1,2}(?:password|passwd|token|api[_-]?key|secret|client[_-]?secret)\s+(?:"[^"]*"|''[^'']*''|\S+)',

        # Plaintext secure-string conversion.

        '(?i)ConvertTo-SecureString\b.*?-AsPlainText',

        # Selected authentication commands.

        '(?i)\b(?:gh\s+auth\s+login\s+--with-token|az\s+login\s+--password)\b'
    )

    $PDE_RegexOptions = (
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
        [System.Text.RegularExpressions.RegexOptions]::Compiled -bor
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )

    $PDE_CompiledPatterns = [System.Collections.Generic.List[System.Text.RegularExpressions.Regex]]::new()

    foreach ($PDE_Pattern in $PDE_SensitivePatterns) {
        $PDE_CompiledPatterns.Add(
            [System.Text.RegularExpressions.Regex]::new(
                $PDE_Pattern,
                $PDE_RegexOptions,
                [TimeSpan]::FromMilliseconds(100)
            )
        )
    }

    $global:PDE_SensitiveHistoryRegexes = $PDE_CompiledPatterns
    $global:PDE_SensitiveHistoryRegexVersion = $PDE_SensitiveHistoryRegexVersion

    Remove-Variable PDE_SensitivePatterns, PDE_RegexOptions, PDE_CompiledPatterns, PDE_Pattern -ErrorAction SilentlyContinue
}


# ---------------------------------------------------------------------------
# 2.2 Resilient diagnostic logging
# ---------------------------------------------------------------------------

function global:Write-PDELog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (
        -not $global:PDE_Config -or
        -not $global:PDE_Config.EnableDiagnosticsLog
    ) {
        return
    }

    $stream = $null
    $writer = $null

    try {
        $path = [string]$global:PDE_Config.DiagnosticsLogPath

        if ([string]::IsNullOrWhiteSpace($path)) {
            return
        }

        $directory = [System.IO.Path]::GetDirectoryName($path)

        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            # Safe when multiple PowerShell sessions create the directory.
            [void][System.IO.Directory]::CreateDirectory($directory)
        }

        $entry = '{0} [{1}] {2}' -f (
            Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
        ), $Level, $Message

        $stream = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )

        $encoding = [System.Text.UTF8Encoding]::new($false)

        $writer = [System.IO.StreamWriter]::new(
            $stream,
            $encoding
        )

        $writer.WriteLine($entry)
        $writer.Flush()
    }
    catch {
        # Logging is best-effort.
        # Access denial, file locks and directory failures must never
        # interrupt interactive command-line editing.
    }
    finally {
        try {
            if ($null -ne $writer) {
                $writer.Dispose()
            }
            elseif ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        catch {
            # Cleanup errors must not affect the interactive session.
        }
    }
}


# ---------------------------------------------------------------------------
# 2.3 Sensitive-history line detection
# ---------------------------------------------------------------------------

function global:Test-PDESensitiveHistoryLine {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $false
    }

    if (-not $global:PDE_SensitiveHistoryRegexes) {
        # Fail closed if the protection rules failed to initialise.
        return $true
    }

    foreach ($pattern in $global:PDE_SensitiveHistoryRegexes) {
        try {
            if ($pattern.IsMatch($Line)) {
                return $true
            }
        }
        catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
            # A timed-out safety scan is treated conservatively.
            return $true
        }
        catch {
            # A broken filter is also treated conservatively.
            return $true
        }
    }

    return $false
}


# ---------------------------------------------------------------------------
# 2.4 History command-name and prefix tracking
# ---------------------------------------------------------------------------

function global:Add-PDEHistoryCommandName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return
    }

    if (
        -not $global:PDE_State -or
        -not $global:PDE_State.CommandNames
    ) {
        return
    }

    if (-not $global:PDE_State.CommandNames.Contains($Name)) {
        return
    }

    if (-not $global:PDE_State.HistoryCommandNames) {
        $global:PDE_State.HistoryCommandNames = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    if (-not $global:PDE_State.HistoryCommandPrefixes) {
        $global:PDE_State.HistoryCommandPrefixes = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
    }

    [void]$global:PDE_State.HistoryCommandNames.Add($Name)

    # Store every leading command-name prefix.
    for ($length = 1; $length -le $Name.Length; $length++) {
        [void]$global:PDE_State.HistoryCommandPrefixes.Add(
            $Name.Substring(0, $length)
        )
    }
}


# ---------------------------------------------------------------------------
# 2.5 Interactive history-entry insertion
# ---------------------------------------------------------------------------

function global:Add-PDEHistoryEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Line,

        [switch]$PromoteDuplicate
    )

    if (
        -not $global:PDE_State -or
        -not $global:PDE_Config
    ) {
        return
    }

    $cleanLine = $Line.Trim()

    if ([string]::IsNullOrWhiteSpace($cleanLine)) {
        return
    }

    # Only accept completed single-line commands.
    if ($cleanLine -match '[\r\n]') {
        return
    }

    # Exclude obvious credential-bearing commands.
    if (Test-PDESensitiveHistoryLine -Line $cleanLine) {
        return
    }

    $tokens = $null
    $parseErrors = $null

    try {
        $parsedAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $cleanLine,
            [ref]$tokens,
            [ref]$parseErrors
        )
    }
    catch {
        return
    }

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return
    }

    # Handle duplicate commands.
    if ($global:PDE_State.HistorySet.Contains($cleanLine)) {
        if (-not $PromoteDuplicate) {
            return
        }

        [void]$global:PDE_State.History.Remove($cleanLine)
        [void]$global:PDE_State.HistorySet.Remove($cleanLine)
    }

    # This function processes newly completed interactive commands.
    # Front insertion is intentional here.
    #
    # Bulk history imports use the O(N) append/reverse implementation
    # in PDE-History-Index.ps1 instead.

    $global:PDE_State.History.Insert(0, $cleanLine)

    [void]$global:PDE_State.HistorySet.Add($cleanLine)

    # Identify actual command AST nodes.
    $historyCommands = $parsedAst.FindAll({
        param($node)

        $node -is [System.Management.Automation.Language.CommandAst]

    }, $true)

    foreach ($historyCommandAst in $historyCommands) {
        $historyCommandName = $historyCommandAst.GetCommandName()

        if (-not [string]::IsNullOrWhiteSpace($historyCommandName)) {
            Add-PDEHistoryCommandName -Name $historyCommandName
        }
    }

    # Enforce the configured history-index limit.
    $limit = [int]$global:PDE_Config.HistoryIndexLimit

    if ($limit -lt 1) {
        $limit = 1
    }

    while ($global:PDE_State.History.Count -gt $limit) {
        $lastIndex = $global:PDE_State.History.Count - 1

        $lastValue = $global:PDE_State.History[$lastIndex]

        $global:PDE_State.History.RemoveAt($lastIndex)

        [void]$global:PDE_State.HistorySet.Remove($lastValue)
    }
}


# ---------------------------------------------------------------------------
# END OF PDE-LOGGING.PS1
# ============================================================================