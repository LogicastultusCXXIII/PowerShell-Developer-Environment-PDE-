# ============================================================================
# POWERSHELL DEVELOPER ENVIRONMENT (PDE) V2 - UNIFIED DEVELOPER PROFILE
# Compatible with Windows PowerShell 5.1 and PowerShell 7+
#
# Notes:
# - This profile is designed for interactive developer use.
# - Its command-risk checks are heuristic warnings, not a security boundary.
# - Live typo suggestions are performed safely when a command is accepted;
#   this version does not repaint the console or replace printable key handlers.
# - History filtering is conservative. A secret scanner cannot guarantee that
#   every credential format will be detected.
# ============================================================================

$global:PSProfileStartupStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$global:PSProfileConfig = @{
    LiveTypoHighlightEnabled = $true
    MaximumEditDistance      = 2
    KeyboardAwareScoring     = $true
    SecurityMode             = 'Warn'       # Off, Warn, Strict
    HistoryFilterEnabled     = $true
    PredictionSource         = 'HistoryAndPlugin'
    PredictionViewStyle      = 'InlineView'
    MaxHistoryIndexCount     = 10000
    DeveloperToolsEnabled    = $true       # Optional integrations and automated project checks
    LiveTypoMaxDistance      = 2
}

$global:PSProfileState = @{
    CommandNameCache         = @()
    CommandNameLookup        = @{}
    HistoryCommandCounts     = @{}
    HistoryCommandsByLength  = @{}
    PSReadLineReady          = $false
    SecurityGuardInstalled   = $false
    SecurityGuardError       = $null
    HistoryFilterInstalled   = $false
    HistoryFilterError       = $null
    LiveTypoKeyBindings      = 0
    OptionalModulesLoaded    = @()
    ModuleLoadTimes          = @{}
    StartupDurationMs        = 0
    CacheBuiltTime           = $null
    ExecutionTracker         = New-Object System.Collections.ArrayList
    MaxExecutionRecords      = 500
}

# QWERTY letter positions. Row offsets model the physical stagger of a keyboard.
$global:PSProfileKeyboardLayout = @{
    'q' = @(0.00, 0.00); 'w' = @(1.00, 0.00); 'e' = @(2.00, 0.00)
    'r' = @(3.00, 0.00); 't' = @(4.00, 0.00); 'y' = @(5.00, 0.00)
    'u' = @(6.00, 0.00); 'i' = @(7.00, 0.00); 'o' = @(8.00, 0.00)
    'p' = @(9.00, 0.00)
    'a' = @(0.50, 1.00); 's' = @(1.50, 1.00); 'd' = @(2.50, 1.00)
    'f' = @(3.50, 1.00); 'g' = @(4.50, 1.00); 'h' = @(5.50, 1.00)
    'j' = @(6.50, 1.00); 'k' = @(7.50, 1.00); 'l' = @(8.50, 1.00)
    'z' = @(1.00, 2.00); 'x' = @(2.00, 2.00); 'c' = @(3.00, 2.00)
    'v' = @(4.00, 2.00); 'b' = @(5.00, 2.00); 'n' = @(6.00, 2.00)
    'm' = @(7.00, 2.00)
}

$global:PSProfileSubcommandCatalog = @{
    'git'    = @('status', 'commit', 'push', 'pull', 'checkout', 'switch', 'branch', 'diff', 'log', 'rebase', 'merge', 'stash', 'fetch', 'remote', 'add', 'reset', 'restore', 'cherry-pick', 'clone', 'tag', 'init', 'blame')
    'dotnet' = @('build', 'run', 'test', 'clean', 'restore', 'publish', 'pack', 'new', 'sln', 'add', 'remove', 'list', 'tool', 'watch', 'format')
    'npm'    = @('install', 'run', 'test', 'start', 'build', 'publish', 'init', 'update', 'audit', 'outdated', 'list', 'uninstall', 'ci', 'cache', 'exec')
    'docker' = @('run', 'ps', 'build', 'images', 'pull', 'push', 'stop', 'rm', 'rmi', 'compose', 'exec', 'logs', 'volume', 'network', 'system', 'inspect')
    'python' = @('-m', '-v', '--version', '-c', '-h', '--help')
    'pip'    = @('install', 'uninstall', 'list', 'freeze', 'show', 'check', 'cache')
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function Test-PSProfileCommandAvailable {
    param([Parameter(Mandatory = $true)][string]$Name)
    return ($null -ne (Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1))
}

function Get-PSProfileSafeProperty {
    param([object]$InputObject, [string]$Name, [object]$Default = $null)
    if ($null -ne $InputObject -and $InputObject.PSObject.Properties[$Name]) {
        return $InputObject.PSObject.Properties[$Name].Value
    }
    return $Default
}

function Test-PSProfileSensitiveCommandLine {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Line)

    $rules = New-Object 'System.Collections.Generic.List[string]'
    $patterns = @(
        @{ Name = 'Private key material'; Pattern = '(?i)-----BEGIN(?: [A-Z0-9]+)* PRIVATE KEY-----' }
        @{ Name = 'AWS access key'; Pattern = '\bAKIA[0-9A-Z]{16}\b' }
        @{ Name = 'GitHub token'; Pattern = '\bgh[pousr]_[A-Za-z0-9_]{20,}\b' }
        @{ Name = 'Slack token'; Pattern = '\bxox[baprs]-[0-9A-Za-z-]{10,}\b' }
        @{ Name = 'JWT-like token'; Pattern = '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b' }
        @{ Name = 'Credential assignment'; Pattern = '(?i)\b(password|passwd|passphrase|secret|api[_-]?key|client[_-]?secret|access[_-]?token|refresh[_-]?token|authorization)\b\s*[:=]\s*["''][^"'']{4,}["'']' }
        @{ Name = 'Sensitive command parameter'; Pattern = '(?i)-(password|passwd|passphrase|secret|token|api[_-]?key|client[_-]?secret|credential)\s+[^\s;]+' }
        @{ Name = 'Plaintext SecureString'; Pattern = '(?i)ConvertTo-SecureString.*-AsPlainText' }
        @{ Name = 'Windows credential utility'; Pattern = '(?i)\bcmdkey(?:\.exe)?\s+/add:' }
    )

    foreach ($rule in $patterns) {
        if ($Line -match $rule.Pattern) {
            [void]$rules.Add($rule.Name)
        }
    }

    # AST checks catch common variable assignments and named sensitive parameters.
    try {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$parseErrors)

        if ($parseErrors.Count -gt 0) {
            # Avoid persisting syntactically incomplete command lines. This is
            # deliberately conservative because the user may have typed a secret.
            [void]$rules.Add('Unparseable command line')
        } else {
            $assignments = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)
            foreach ($assignment in $assignments) {
                $leftText = $assignment.Left.Extent.Text
                if ($leftText -match '(?i)(password|passwd|passphrase|secret|token|api[_-]?key|client[_-]?secret|credential)') {
                    [void]$rules.Add('Sensitive variable assignment')
                    break
                }
            }

            $commandAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
            foreach ($commandAst in $commandAsts) {
                foreach ($element in $commandAst.CommandElements) {
                    if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and
                        $element.ParameterName -match '(?i)^(password|passwd|passphrase|secret|token|apikey|clientsecret|credential|authorization)$') {
                        [void]$rules.Add('Sensitive named parameter')
                        break
                    }
                }
            }
        }
    } catch {
        [void]$rules.Add('History filter parse failure')
    }

    $uniqueRules = @($rules | Select-Object -Unique)
    return [PSCustomObject]@{
        Sensitive = ($uniqueRules.Count -gt 0)
        Rules     = $uniqueRules
    }
}

function Get-PSProfileProjectMarkers {
    param([Parameter(Mandatory = $true)][string]$Path)

    $markers = New-Object 'System.Collections.Generic.List[string]'
    if (Test-Path -LiteralPath (Join-Path $Path '.git')) { [void]$markers.Add('.git') }

    foreach ($pattern in @('*.sln', '*.slnx', '*.csproj', '*.fsproj', '*.vbproj')) {
        $found = @(Get-ChildItem -LiteralPath $Path -Filter $pattern -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($found.Count -gt 0) { [void]$markers.Add($pattern) }
    }

    foreach ($file in @('package.json', 'pyproject.toml', 'requirements.txt', 'Cargo.toml', 'Dockerfile', 'go.mod', 'composer.json')) {
        if (Test-Path -LiteralPath (Join-Path $Path $file) -PathType Leaf) { [void]$markers.Add($file) }
    }
    return @($markers)
}

function Get-PSProfileFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Filter = '*',
        [switch]$FilesOnly,
        [ValidateRange(0, 50)][int]$MaxDepth = 20
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "Directory not found: $Path"
        return
    }

    $skipNames = @('.git', 'node_modules', 'bin', 'obj', '.venv', 'venv', '__pycache__', '.tox', '.pytest_cache')
    $stack = New-Object 'System.Collections.Stack'
    $stack.Push([PSCustomObject]@{ Directory = (Get-Item -LiteralPath $Path).FullName; Depth = 0 })

    while ($stack.Count -gt 0) {
        $item = $stack.Pop()
        $entries = Get-ChildItem -LiteralPath $item.Directory -Force -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            if ($entry.PSIsContainer) {
                if (-not $FilesOnly -and $entry.Name -like $Filter) { $entry }
                if ($item.Depth -lt $MaxDepth -and $entry.Name -notin $skipNames) {
                    $stack.Push([PSCustomObject]@{ Directory = $entry.FullName; Depth = ($item.Depth + 1) })
                }
            } elseif ($entry.Name -like $Filter) {
                $entry
            }
        }
    }
}

function Get-PSProfileCommandNameFromAst {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.CommandAst]$CommandAst)
    $name = $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $command = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command -and $command.CommandType -eq 'Alias' -and $command.ResolvedCommandName) {
        return [string]$command.ResolvedCommandName
    }
    return [string]$name
}

# ---------------------------------------------------------------------------
# Typo detection and command intelligence
# ---------------------------------------------------------------------------

function Get-PSProfileKeyboardDistance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][char]$CharA,
        [Parameter(Mandatory = $true)][char]$CharB
    )

    $a = [char]::ToLowerInvariant($CharA)
    $b = [char]::ToLowerInvariant($CharB)
    if ($a -eq $b) { return 0.0 }

    $keyA = [string]$a
    $keyB = [string]$b
    if ($global:PSProfileKeyboardLayout.ContainsKey($keyA) -and $global:PSProfileKeyboardLayout.ContainsKey($keyB)) {
        $coordA = $global:PSProfileKeyboardLayout[$keyA]
        $coordB = $global:PSProfileKeyboardLayout[$keyB]
        return [Math]::Sqrt([Math]::Pow(($coordA[0] - $coordB[0]), 2) + [Math]::Pow(($coordA[1] - $coordB[1]), 2))
    }
    return 3.5
}

function Get-PSProfileEditDistance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Target,
        [ValidateRange(0, 10)][int]$MaximumDistance = 2
    )

    $src = $Source.ToLowerInvariant()
    $tgt = $Target.ToLowerInvariant()
    if ($src -ceq $tgt) { return 0 }
    if ([Math]::Abs($src.Length - $tgt.Length) -gt $MaximumDistance) { return ($MaximumDistance + 1) }

    $srcLen = $src.Length
    $tgtLen = $tgt.Length
    if ($srcLen -eq 0) { return [Math]::Min($tgtLen, ($MaximumDistance + 1)) }
    if ($tgtLen -eq 0) { return [Math]::Min($srcLen, ($MaximumDistance + 1)) }

    # Optimal String Alignment distance: insertion, deletion, substitution,
    # and adjacent transposition. This is not unrestricted Damerau-Levenshtein.
    $d = New-Object 'int[,]' ($srcLen + 1), ($tgtLen + 1)
    for ($i = 0; $i -le $srcLen; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $tgtLen; $j++) { $d[0, $j] = $j }

    for ($i = 1; $i -le $srcLen; $i++) {
        for ($j = 1; $j -le $tgtLen; $j++) {
            $cost = if ($src[$i - 1] -ceq $tgt[$j - 1]) { 0 } else { 1 }
            $value = [Math]::Min(
                [Math]::Min(($d[($i - 1), $j] + 1), ($d[$i, ($j - 1)] + 1)),
                ($d[($i - 1), ($j - 1)] + $cost)
            )

            if ($i -gt 1 -and $j -gt 1 -and
                $src[$i - 1] -ceq $tgt[$j - 2] -and
                $src[$i - 2] -ceq $tgt[$j - 1]) {
                $transposition = $d[($i - 2), ($j - 2)] + 1
                if ($transposition -lt $value) { $value = $transposition }
            }
            $d[$i, $j] = $value
        }
    }

    $distance = [int]$d[$srcLen, $tgtLen]
    if ($distance -gt $MaximumDistance) { return ($MaximumDistance + 1) }
    return $distance
}

function Get-PSProfileTypoMismatchIndexes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Typed,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    $tLen = $Typed.Length
    $eLen = $Expected.Length
    if ($tLen -eq 0) { return @() }

    $d = New-Object 'int[,]' ($tLen + 1), ($eLen + 1)
    for ($i = 0; $i -le $tLen; $i++) { $d[$i, 0] = $i }
    for ($j = 0; $j -le $eLen; $j++) { $d[0, $j] = $j }

    for ($i = 1; $i -le $tLen; $i++) {
        for ($j = 1; $j -le $eLen; $j++) {
            $cost = if ([char]::ToLowerInvariant($Typed[$i - 1]) -eq [char]::ToLowerInvariant($Expected[$j - 1])) { 0 } else { 1 }
            $value = [Math]::Min(
                [Math]::Min(($d[($i - 1), $j] + 1), ($d[$i, ($j - 1)] + 1)),
                ($d[($i - 1), ($j - 1)] + $cost)
            )
            if ($i -gt 1 -and $j -gt 1 -and
                [char]::ToLowerInvariant($Typed[$i - 1]) -eq [char]::ToLowerInvariant($Expected[$j - 2]) -and
                [char]::ToLowerInvariant($Typed[$i - 2]) -eq [char]::ToLowerInvariant($Expected[$j - 1])) {
                $transposition = $d[($i - 2), ($j - 2)] + 1
                if ($transposition -lt $value) { $value = $transposition }
            }
            $d[$i, $j] = $value
        }
    }

    $indexes = New-Object 'System.Collections.Generic.List[int]'
    $i = $tLen
    $j = $eLen
    while ($i -gt 0 -or $j -gt 0) {
        if ($i -gt 1 -and $j -gt 1 -and
            [char]::ToLowerInvariant($Typed[$i - 1]) -eq [char]::ToLowerInvariant($Expected[$j - 2]) -and
            [char]::ToLowerInvariant($Typed[$i - 2]) -eq [char]::ToLowerInvariant($Expected[$j - 1]) -and
            $d[$i, $j] -eq ($d[($i - 2), ($j - 2)] + 1)) {
            [void]$indexes.Add($i - 1)
            [void]$indexes.Add($i - 2)
            $i -= 2
            $j -= 2
            continue
        }
        if ($i -gt 0 -and $j -gt 0 -and
            [char]::ToLowerInvariant($Typed[$i - 1]) -eq [char]::ToLowerInvariant($Expected[$j - 1]) -and
            $d[$i, $j] -eq $d[($i - 1), ($j - 1)]) {
            $i--
            $j--
            continue
        }
        if ($i -gt 0 -and $j -gt 0 -and $d[$i, $j] -eq ($d[($i - 1), ($j - 1)] + 1)) {
            [void]$indexes.Add($i - 1)
            $i--
            $j--
            continue
        }
        if ($i -gt 0 -and $d[$i, $j] -eq ($d[($i - 1), $j] + 1)) {
            [void]$indexes.Add($i - 1)
            $i--
            continue
        }
        if ($j -gt 0 -and $d[$i, $j] -eq ($d[$i, ($j - 1)] + 1)) {
            $j--
            continue
        }
        break
    }

    return @($indexes | Sort-Object -Unique)
}

function Get-PSProfileCommandMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$Name,
        [ValidateRange(1, 5)][int]$MaximumDistance = 2,
        [ValidateRange(1, 50)][int]$Limit = 10
    )

    if ($global:PSProfileState.CommandNameCache.Count -eq 0) { $null = Update-PSCommandCache }
    $nameLower = $Name.ToLowerInvariant()
    $nameLen = $nameLower.Length
    $results = New-Object System.Collections.ArrayList

    foreach ($candidate in $global:PSProfileState.CommandNameCache) {
        $candidateLower = $candidate.ToLowerInvariant()
        if ([Math]::Abs($candidateLower.Length - $nameLen) -gt $MaximumDistance) { continue }

        $distance = Get-PSProfileEditDistance -Source $nameLower -Target $candidateLower -MaximumDistance $MaximumDistance
        if ($distance -gt $MaximumDistance) { continue }

        $keyboardPenalty = 0.0
        if ($global:PSProfileConfig.KeyboardAwareScoring -and $distance -gt 0) {
            $mismatchIndexes = @(Get-PSProfileTypoMismatchIndexes -Typed $nameLower -Expected $candidateLower)
            foreach ($index in $mismatchIndexes) {
                if ($index -lt $nameLen -and $index -lt $candidateLower.Length) {
                    $keyboardPenalty += Get-PSProfileKeyboardDistance -CharA $nameLower[$index] -CharB $candidateLower[$index]
                } else {
                    $keyboardPenalty += 3.5
                }
            }
        }

        $historyUses = 0
        if ($global:PSProfileState.HistoryCommandCounts.ContainsKey($candidate)) {
            $historyUses = [int]$global:PSProfileState.HistoryCommandCounts[$candidate]
        }
        $commandInfo = $global:PSProfileState.CommandNameLookup[$candidate]
        $rankScore = ($distance * 100) + ($keyboardPenalty * 10) - ([Math]::Min($historyUses, 50) * 2)

        [void]$results.Add([PSCustomObject]@{
            Name            = $candidate
            Distance        = $distance
            KeyboardPenalty = [Math]::Round($keyboardPenalty, 2)
            RankScore       = $rankScore
            HistoryUses     = $historyUses
            UsedBefore      = ($historyUses -gt 0)
            CommandType     = if ($null -ne $commandInfo) { $commandInfo.CommandType } else { 'Unknown' }
            Source          = if ($null -ne $commandInfo) { $commandInfo.Source } else { $null }
        })
    }

    return @($results |
        Sort-Object @{ Expression = 'Distance'; Ascending = $true },
                    @{ Expression = 'RankScore'; Ascending = $true },
                    @{ Expression = 'HistoryUses'; Descending = $true },
                    @{ Expression = 'Name'; Ascending = $true } |
        Select-Object -First $Limit)
}

function Get-PSProfileCommandConfidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Typed,
        [Parameter(Mandatory = $true)][PSCustomObject]$Match
    )

    $score = 100.0
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if ($Match.Distance -eq 0) {
        return [PSCustomObject]@{ Score = 100; Level = 'High'; Confidence = 'Exact match'; Reasons = @('Exact command match'); IsStatisticalProbability = $false }
    }

    $distancePenalty = ($Match.Distance / [Math]::Max($Typed.Length, 1)) * 50
    $score -= $distancePenalty
    [void]$reasons.Add(('Edit distance {0} (-{1:N1})' -f $Match.Distance, $distancePenalty))

    if ($Match.KeyboardPenalty -gt 0) {
        $keyboardPenalty = [Math]::Min(($Match.KeyboardPenalty * 4), 20)
        $score -= $keyboardPenalty
        [void]$reasons.Add(('Keyboard penalty (-{0:N1})' -f $keyboardPenalty))
    }

    if ($Match.UsedBefore) {
        $bonus = [Math]::Min(($Match.HistoryUses * 3), 20)
        $score += $bonus
        [void]$reasons.Add(('Prior history count {0} (+{1:N1})' -f $Match.HistoryUses, $bonus))
    } else {
        $score -= 10
        [void]$reasons.Add('No recorded prior usage (-10)')
    }

    $finalScore = [Math]::Max([Math]::Min([Math]::Round($score, 1), 100.0), 0.0)
    $level = if ($finalScore -ge 80) { 'High' } elseif ($finalScore -ge 55) { 'Medium' } else { 'Low' }
    return [PSCustomObject]@{
        Score                     = $finalScore
        Level                     = $level
        Confidence                = ('{0} heuristic score ({1:N1}/100)' -f $level, $finalScore)
        Reasons                   = @($reasons)
        IsStatisticalProbability  = $false
    }
}

function Test-PSProfileCommandSpelling {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Name)

    $matchesFound = @(Get-PSProfileCommandMatches -Name $Name -MaximumDistance $global:PSProfileConfig.MaximumEditDistance -Limit 5)
    if ($matchesFound.Count -eq 0) {
        Write-Host ("No close installed-command matches found for '{0}'." -f $Name) -ForegroundColor Yellow
        return
    }

    Write-Host "`nCOMMAND INTELLIGENCE REPORT" -ForegroundColor Cyan
    Write-Host ("Typed: {0}" -f $Name) -ForegroundColor White
    $output = foreach ($match in $matchesFound) {
        $confidence = Get-PSProfileCommandConfidence -Typed $Name -Match $match
        [PSCustomObject]@{
            Candidate   = $match.Name
            Distance    = $match.Distance
            Heuristic   = $confidence.Confidence
            HistoryUses = $match.HistoryUses
            CommandType = $match.CommandType
        }
    }
    $output | Format-Table -AutoSize
    Write-Host ("Best Match: {0} (suggestion only; command will not be rewritten)`n" -f $matchesFound[0].Name) -ForegroundColor Green
}

function Test-CommandSpelling {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)
    Test-PSProfileCommandSpelling -Name $Name
}

function Get-PSProfileCommandContext {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CommandLine)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($CommandLine, [ref]$tokens, [ref]$errors)
    $commandAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    if ($null -eq $commandAst -or $commandAst.CommandElements.Count -lt 2) { return $null }

    $leadCommand = [string]$commandAst.GetCommandName()
    $subElement = $commandAst.CommandElements[1]
    if ($subElement -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        $subCommand = [string]$subElement.Value
    } else {
        $subCommand = [string]$subElement.Extent.Text
    }

    $leadCommand = $leadCommand.ToLowerInvariant()
    $subCommand = $subCommand.ToLowerInvariant()
    if (-not $global:PSProfileSubcommandCatalog.ContainsKey($leadCommand)) { return $null }

    $validCommands = $global:PSProfileSubcommandCatalog[$leadCommand]
    if ($validCommands -contains $subCommand) {
        return [PSCustomObject]@{ LeadCommand = $leadCommand; Subcommand = $subCommand; IsValid = $true; IsSubcommand = $true; SuggestedText = $null }
    }

    $bestSubcommand = $null
    $lowestDistance = 99
    foreach ($candidate in $validCommands) {
        $distance = Get-PSProfileEditDistance -Source $subCommand -Target $candidate -MaximumDistance 2
        if ($distance -lt $lowestDistance) {
            $lowestDistance = $distance
            $bestSubcommand = $candidate
        }
    }

    if ($lowestDistance -le 2 -and $null -ne $bestSubcommand) {
        return [PSCustomObject]@{
            LeadCommand  = $leadCommand
            Subcommand   = $subCommand
            IsValid      = $false
            IsSubcommand = $true
            SuggestedText = ('{0} {1}' -f $leadCommand, $bestSubcommand)
            SuggestedSub = $bestSubcommand
            Distance     = $lowestDistance
        }
    }
    return $null
}

function Get-PSProfileBestHistoryCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TypedName,
        [ValidateRange(1, 5)][int]$MaximumDistance = 2
    )

    if ($global:PSProfileState.HistoryCommandCounts.Count -eq 0 -or [string]::IsNullOrEmpty($TypedName)) { return $null }
    $typedLength = $TypedName.Length
    $prefixMatches = New-Object System.Collections.ArrayList

    foreach ($lengthKey in @($global:PSProfileState.HistoryCommandsByLength.Keys)) {
        $length = [int]$lengthKey
        if ($length -lt $typedLength) { continue }
        foreach ($historyName in $global:PSProfileState.HistoryCommandsByLength[$lengthKey].Keys) {
            if ($historyName.StartsWith($TypedName, [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$prefixMatches.Add([PSCustomObject]@{
                    Name = $historyName
                    Distance = 0
                    HistoryUses = [int]$global:PSProfileState.HistoryCommandCounts[$historyName]
                    MatchMode = 'ValidPrefix'
                    MatchText = $TypedName
                })
            }
        }
    }

    if ($prefixMatches.Count -gt 0) {
        return ($prefixMatches | Sort-Object @{ Expression = 'HistoryUses'; Descending = $true }, @{ Expression = 'Name'; Ascending = $true } | Select-Object -First 1)
    }
    if ($typedLength -lt 2) { return $null }

    $allowedDistance = if ($typedLength -le 4) { 1 } else { $MaximumDistance }
    $fuzzyMatches = New-Object System.Collections.ArrayList
    foreach ($lengthKey in @($global:PSProfileState.HistoryCommandsByLength.Keys)) {
        $length = [int]$lengthKey
        if ([Math]::Abs($length - $typedLength) -gt $allowedDistance) { continue }
        foreach ($historyName in $global:PSProfileState.HistoryCommandsByLength[$lengthKey].Keys) {
            $comparisonText = if ($typedLength -lt $historyName.Length) { $historyName.Substring(0, $typedLength) } else { $historyName }
            $mode = if ($typedLength -lt $historyName.Length) { 'PartialPrefixTypo' } else { 'FullWordTypo' }
            $distance = Get-PSProfileEditDistance -Source $TypedName -Target $comparisonText -MaximumDistance $allowedDistance
            if ($distance -gt 0 -and $distance -le $allowedDistance) {
                [void]$fuzzyMatches.Add([PSCustomObject]@{
                    Name = $historyName
                    Distance = $distance
                    HistoryUses = [int]$global:PSProfileState.HistoryCommandCounts[$historyName]
                    MatchMode = $mode
                    MatchText = $comparisonText
                })
            }
        }
    }

    if ($fuzzyMatches.Count -eq 0) { return $null }
    $ordered = @($fuzzyMatches | Sort-Object @{ Expression = 'Distance'; Ascending = $true }, @{ Expression = 'HistoryUses'; Descending = $true }, @{ Expression = 'Name'; Ascending = $true })
    if ($ordered.Count -gt 1 -and $ordered[0].Distance -eq $ordered[1].Distance -and $ordered[0].HistoryUses -eq $ordered[1].HistoryUses) { return $null }
    return $ordered[0]
}

function Add-PSProfileHistoryCommandUse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateRange(1, 1000000)][int]$Count = 1
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\\/:$]' -or $Name.StartsWith('.')) { return }
    if (-not $global:PSProfileState.CommandNameLookup.ContainsKey($Name)) { return }

    if ($global:PSProfileState.HistoryCommandCounts.ContainsKey($Name)) {
        $global:PSProfileState.HistoryCommandCounts[$Name] += $Count
    } else {
        $global:PSProfileState.HistoryCommandCounts[$Name] = $Count
    }

    $lengthKey = [string]$Name.Length
    if (-not $global:PSProfileState.HistoryCommandsByLength.ContainsKey($lengthKey)) {
        $global:PSProfileState.HistoryCommandsByLength[$lengthKey] = @{}
    }
    $global:PSProfileState.HistoryCommandsByLength[$lengthKey][$Name] = $true
}

function Update-PSCommandCache {
    [CmdletBinding()]
    param(
        [switch]$HistoryOnly,
        [ValidateRange(100, 50000)][int]$HistoryLines = 10000
    )

    if (-not $HistoryOnly -or $global:PSProfileState.CommandNameCache.Count -eq 0) {
        $commandEntries = @(Get-Command -Name '*' -All -ErrorAction SilentlyContinue)
        $global:PSProfileState.CommandNameLookup = @{}

        foreach ($entry in $commandEntries) {
            if ([string]::IsNullOrWhiteSpace($entry.Name)) { continue }
            $names = New-Object 'System.Collections.Generic.List[string]'
            [void]$names.Add([string]$entry.Name)

            if ($entry.CommandType -eq 'Application' -and $entry.Name -match '\.(exe|com|cmd|bat)$') {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($entry.Name)
                if (-not [string]::IsNullOrWhiteSpace($baseName)) { [void]$names.Add($baseName) }
            }

            foreach ($name in $names) {
                if (-not $global:PSProfileState.CommandNameLookup.ContainsKey($name)) {
                    $global:PSProfileState.CommandNameLookup[$name] = [PSCustomObject]@{
                        Name = $name
                        CommandType = $entry.CommandType
                        Source = $entry.Source
                        Executable = $entry.Name
                    }
                }
            }
        }
        $global:PSProfileState.CommandNameCache = @($global:PSProfileState.CommandNameLookup.Keys | Sort-Object)
    }

    $global:PSProfileState.HistoryCommandCounts = @{}
    $global:PSProfileState.HistoryCommandsByLength = @{}
    $historyPath = Get-PSHistoryPath
    $historyLimit = [Math]::Min($HistoryLines, [Math]::Max($global:PSProfileConfig.MaxHistoryIndexCount, 100))

    if (-not [string]::IsNullOrWhiteSpace($historyPath) -and (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        $historyEntries = @(Get-Content -LiteralPath $historyPath -Tail $historyLimit -ErrorAction SilentlyContinue)
        foreach ($line in $historyEntries) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $sensitive = Test-PSProfileSensitiveCommandLine -Line $line
            if ($sensitive.Sensitive) { continue }

            try {
                $tokens = $null
                $errors = $null
                $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$tokens, [ref]$errors)
                if ($errors.Count -gt 0) { continue }
                $commandAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($commandAst in $commandAsts) {
                    $used = Get-PSProfileCommandNameFromAst -CommandAst $commandAst
                    if (-not [string]::IsNullOrWhiteSpace($used)) { Add-PSProfileHistoryCommandUse -Name $used }
                }
            } catch {
                continue
            }
        }
    }

    $global:PSProfileState.CacheBuiltTime = Get-Date
    return [PSCustomObject]@{
        CommandsCached       = $global:PSProfileState.CommandNameCache.Count
        HistoryCommandsFound = $global:PSProfileState.HistoryCommandCounts.Count
        HistoryFile          = $historyPath
        Updated              = $global:PSProfileState.CacheBuiltTime
    }
}

function Update-PSProfile {
    [CmdletBinding()]
    param()
    $result = Update-PSCommandCache
    Write-Host ("PDE V2 cache refreshed: {0} commands, {1} history command names." -f $result.CommandsCached, $result.HistoryCommandsFound) -ForegroundColor Green
}

# This function is intentionally read-only. PSReadLine owns the console buffer;
# the profile no longer writes directly over its rendered input line.
function Invoke-PSProfileLiveTypoHighlight {
    [CmdletBinding()]
    param([switch]$AfterPaste)

    if (-not $global:PSProfileConfig.LiveTypoHighlightEnabled) { return }
    if (-not $global:PSProfileState.PSReadLineReady -or $Host.Name -notmatch 'ConsoleHost') { return }

    try {
        $line = $null
        $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Contains("`n") -or $line.Contains("`r")) { return }
        $match = [regex]::Match($line, '^\s*(?<command>[^\s;&|<>]+)')
        if (-not $match.Success) { return }

        $typedCommand = $match.Groups['command'].Value
        if ($typedCommand -notmatch '^[A-Za-z0-9_.-]+$' -or $typedCommand.StartsWith('.')) { return }
        if ($global:PSProfileState.CommandNameLookup.ContainsKey($typedCommand)) { return }

        $best = Get-PSProfileBestHistoryCommand -TypedName $typedCommand -MaximumDistance $global:PSProfileConfig.LiveTypoMaxDistance
        if ($null -ne $best -and $best.MatchMode -ne 'ValidPrefix') {
            return [PSCustomObject]@{
                TypedCommand = $typedCommand
                SuggestedCommand = $best.Name
                Distance = $best.Distance
                DisplayMode = 'SuggestionOnly'
                Message = ("Possible command typo: '{0}'. Previous command: '{1}'." -f $typedCommand, $best.Name)
            }
        }
    } catch {
        return
    }
}

# ---------------------------------------------------------------------------
# PSReadLine setup and security integration
# ---------------------------------------------------------------------------

if ($Host.Name -notmatch 'ISE') {
    try {
        Import-Module PSReadLine -ErrorAction Stop
        $global:PSProfileState.PSReadLineReady = $true
    } catch {
        $global:PSProfileState.PSReadLineReady = $false
    }
}

function Set-PSProfileSecurityMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateSet('Off', 'Warn', 'Strict')]
        [string]$Mode
    )

    $global:PSProfileConfig.SecurityMode = $Mode
    $global:PSProfileState.SecurityGuardInstalled = $false
    $global:PSProfileState.SecurityGuardError = $null

    if (-not $global:PSProfileState.PSReadLineReady) {
        $global:PSProfileState.SecurityGuardError = 'PSReadLine is not available in this host.'
        Write-Warning 'PDE security guard was not installed because PSReadLine is unavailable.'
        return
    }

    try {
        if ($Mode -eq 'Off') {
            Set-PSReadLineOption -CommandValidationHandler $null -ErrorAction Stop
            $global:PSProfileState.SecurityGuardInstalled = $false
        } else {
            $guard = {
                param([System.Management.Automation.Language.CommandAst]$CommandAst)

                if ($null -eq $CommandAst) { return }
                $commandText = $CommandAst.Extent.Text
                $risk = Get-PSCommandRisk -CommandLine $commandText
                $modeNow = $global:PSProfileConfig.SecurityMode

                if ($global:PSProfileConfig.LiveTypoHighlightEnabled) {
                    $commandName = $CommandAst.GetCommandName()
                    if (-not [string]::IsNullOrWhiteSpace($commandName) -and
                        -not $global:PSProfileState.CommandNameLookup.ContainsKey($commandName)) {
                        $matches = @(Get-PSProfileCommandMatches -Name $commandName -MaximumDistance $global:PSProfileConfig.LiveTypoMaxDistance -Limit 1)
                        if ($matches.Count -gt 0 -and $matches[0].Distance -gt 0) {
                            Write-Host ("[PDE TYPO] Did you mean '{0}'? (suggestion only)" -f $matches[0].Name) -ForegroundColor Yellow
                        }
                    }
                }

                if ($risk.RiskLevel -in @('HIGH', 'CRITICAL')) {
                    if ($modeNow -eq 'Strict') {
                        throw [System.InvalidOperationException]::new(("PDE STRICT GUARD: {0}-risk command blocked: {1}" -f $risk.RiskLevel, $commandText))
                    }
                    if ($modeNow -eq 'Warn') {
                        Write-Host ("`n[PDE SECURITY] Warning: {0}-risk command: {1}" -f $risk.RiskLevel, $commandText) -ForegroundColor Yellow
                    }
                }
            }

            Set-PSReadLineOption -CommandValidationHandler $guard -ErrorAction Stop
            $global:PSProfileState.SecurityGuardInstalled = $true
        }
    } catch {
        $global:PSProfileState.SecurityGuardInstalled = $false
        $global:PSProfileState.SecurityGuardError = $_.Exception.Message
        Write-Warning ("PDE security guard installation failed: {0}" -f $_.Exception.Message)
    }
}

function Get-PSProfileSecurityStatus {
    [CmdletBinding()]
    param()
    [PSCustomObject]@{
        SecurityMode           = $global:PSProfileConfig.SecurityMode
        HistoryFilterEnabled   = [bool]$global:PSProfileConfig.HistoryFilterEnabled
        HistoryFilterInstalled = [bool]$global:PSProfileState.HistoryFilterInstalled
        PSReadLineReady        = [bool]$global:PSProfileState.PSReadLineReady
        PSReadLineGuardHooked  = [bool]$global:PSProfileState.SecurityGuardInstalled
        GuardError             = $global:PSProfileState.SecurityGuardError
    }
}

function Set-PSProfileHistoryFilter {
    [CmdletBinding()]
    param()

    $global:PSProfileState.HistoryFilterInstalled = $false
    $global:PSProfileState.HistoryFilterError = $null

    if (-not $global:PSProfileState.PSReadLineReady) {
        $global:PSProfileState.HistoryFilterError = 'PSReadLine is not available in this host.'
        return
    }

    try {
        if (-not $global:PSProfileConfig.HistoryFilterEnabled) {
            Set-PSReadLineOption -AddToHistoryHandler $null -ErrorAction Stop
            return
        }

        $historyFilter = {
            param([string]$Line)
            $check = Test-PSProfileSensitiveCommandLine -Line $Line
            if ($check.Sensitive) { return 'SkipAdding' }

            try {
                $tokens = $null
                $parseErrors = $null
                $parsed = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$parseErrors)
                if ($parseErrors.Count -gt 0) { return 'SkipAdding' }

                $commandAsts = $parsed.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
                foreach ($commandAst in $commandAsts) {
                    $commandName = Get-PSProfileCommandNameFromAst -CommandAst $commandAst
                    if (-not [string]::IsNullOrWhiteSpace($commandName)) {
                        Add-PSProfileHistoryCommandUse -Name $commandName
                    }
                }
            } catch {
                return 'SkipAdding'
            }
            return 'MemoryAndFile'
        }

        Set-PSReadLineOption -AddToHistoryHandler $historyFilter -ErrorAction Stop
        $global:PSProfileState.HistoryFilterInstalled = $true
    } catch {
        $global:PSProfileState.HistoryFilterInstalled = $false
        $global:PSProfileState.HistoryFilterError = $_.Exception.Message
        Write-Warning ("PDE history filter update failed: {0}" -f $_.Exception.Message)
    }
}

if ($global:PSProfileState.PSReadLineReady) {
    $psrlModule = Get-Module -Name PSReadLine | Select-Object -First 1
    $psrlVersion = if ($null -ne $psrlModule) { $psrlModule.Version } else { [version]'0.0' }

    if ($PSVersionTable.PSVersion -ge [version]'7.2' -and $psrlVersion -ge [version]'2.2.0') {
        try {
            Set-PSReadLineOption -PredictionSource $global:PSProfileConfig.PredictionSource -ErrorAction Stop
        } catch {
            Set-PSReadLineOption -PredictionSource 'History' -ErrorAction SilentlyContinue
        }
    } else {
        Set-PSReadLineOption -PredictionSource 'History' -ErrorAction SilentlyContinue
    }

    Set-PSReadLineOption -PredictionViewStyle $global:PSProfileConfig.PredictionViewStyle -ErrorAction SilentlyContinue
    Set-PSReadLineOption -MaximumHistoryCount 50000 -ErrorAction SilentlyContinue
    Set-PSReadLineOption -HistorySaveStyle SaveIncrementally -ErrorAction SilentlyContinue
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd -ErrorAction SilentlyContinue
    Set-PSReadLineOption -HistoryNoDuplicates -ErrorAction SilentlyContinue
    Set-PSReadLineOption -CompletionQueryItems 200 -ErrorAction SilentlyContinue
    Set-PSReadLineOption -ShowToolTips -ErrorAction SilentlyContinue
    Set-PSReadLineOption -WordDelimiters ' ;:,.[]{}()/\|^&*-=+' -ErrorAction SilentlyContinue
    Set-PSReadLineOption -BellStyle None -ErrorAction SilentlyContinue

    Set-PSProfileHistoryFilter

    $palette = @{
        Command = '#00FF00'
        Parameter = '#00FFFF'
        String = '#FFFF00'
        Operator = '#FF00FF'
        Variable = '#FF8800'
        Error = '#FF0000'
        Comment = '#808080'
        Keyword = '#569CD6'
        Number = '#00BFFF'
        Type = '#DDA0DD'
        Member = '#D4D4D4'
        Default = '#D4D4D4'
        Emphasis = '#FFFFFF'
    }
    if ($psrlVersion -ge [version]'2.2.0') { $palette['InlinePrediction'] = '#666666' }
    Set-PSReadLineOption -Colors $palette -ErrorAction SilentlyContinue

    # Keep the standard printable, navigation and paste handlers intact.
    Set-PSReadLineKeyHandler -Key 'Tab' -Function MenuComplete -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Key 'Shift+Tab' -Function TabCompletePrevious -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Key 'Ctrl+Spacebar' -Function MenuComplete -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Key 'Ctrl+r' -Function ReverseSearchHistory -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Key 'Ctrl+s' -Function ForwardSearchHistory -ErrorAction SilentlyContinue
    Set-PSReadLineKeyHandler -Key 'Ctrl+l' -Function ClearScreen -ErrorAction SilentlyContinue
    if ($psrlVersion -ge [version]'2.2.0') {
        Set-PSReadLineKeyHandler -Key 'Alt+RightArrow' -Function AcceptNextSuggestionWord -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Command discovery and help
# ---------------------------------------------------------------------------

function Find-LocalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Name,
        [string]$CommandType = 'All',
        [string]$Module
    )

    $criteria = @{ Name = ('*{0}*' -f $Name); ErrorAction = 'SilentlyContinue' }
    if ($CommandType -ne 'All') { $criteria['CommandType'] = $CommandType }
    if (-not [string]::IsNullOrWhiteSpace($Module)) { $criteria['Module'] = $Module }

    Get-Command @criteria | Select-Object CommandType, Name, Version, Source,
        @{ Name = 'Synopsis'; Expression = { try { (Get-Help $_.Name -ErrorAction SilentlyContinue).Synopsis } catch { '' } } }
}

function Get-PSProfileCommandInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        Write-Warning ("Command '{0}' was not found." -f $Name)
        return
    }

    $help = $null
    try { $help = Get-Help $command.Name -ErrorAction SilentlyContinue } catch { }
    $parameters = @()
    if ($command.Parameters) {
        $parameters = foreach ($parameter in $command.Parameters.Values) {
            [PSCustomObject]@{
                Name        = $parameter.Name
                Type        = $parameter.ParameterType.Name
                IsMandatory = $parameter.IsMandatory
                Position    = if ($parameter.Position -lt 0) { 'Named' } else { [string]$parameter.Position }
            }
        }
    }

    $historyCount = 0
    if ($global:PSProfileState.HistoryCommandCounts.ContainsKey($command.Name)) {
        $historyCount = [int]$global:PSProfileState.HistoryCommandCounts[$command.Name]
    }
    $definition = [string]$command.Definition
    if ($definition.Length -gt 120) { $definition = $definition.Substring(0, 117) + '...' }

    [PSCustomObject]@{
        Name          = $command.Name
        CommandType   = $command.CommandType
        SourceModule  = if ($command.ModuleName) { $command.ModuleName } else { 'Core/External' }
        Version       = $command.Version
        Definition    = $definition
        Synopsis      = if ($null -ne $help -and $help.Synopsis) { $help.Synopsis } else { 'No synopsis available.' }
        ParameterList = $parameters
        HistoryUses   = $historyCount
        OnlineHelpUri = if ($null -ne $help -and $help.relatedLinks -and $help.relatedLinks.navigationLink) { $help.relatedLinks.navigationLink.uri } else { $null }
    }
}

function Get-PSProfileCommandExamples {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Name)

    $help = Get-Help $Name -Examples -ErrorAction SilentlyContinue
    if ($null -eq $help -or $null -eq $help.Examples -or $null -eq $help.Examples.example) {
        Write-Warning ("No examples found for '{0}'." -f $Name)
        return
    }

    $index = 1
    foreach ($example in $help.Examples.example) {
        $title = if ($example.title) { $example.title.Trim() } else { 'Untitled' }
        $code = if ($example.code) { $example.code.Trim() } else { '' }
        Write-Host ("--- EXAMPLE {0}: {1} ---" -f $index, $title) -ForegroundColor Cyan
        if ($code) { Write-Host $code -ForegroundColor Green }
        if ($example.remarks) { Write-Host ($example.remarks.Text.Trim() | Out-String) -ForegroundColor DarkGray }
        $index++
    }
}

function Get-PSProfileCommandUsage {
    [CmdletBinding()]
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ($global:PSProfileState.HistoryCommandCounts.GetEnumerator() |
            Sort-Object Value -Descending |
            Select-Object -First 30 @{ Name = 'Command'; Expression = { $_.Key } }, @{ Name = 'HistoryUses'; Expression = { $_.Value } })
    }

    $count = 0
    if ($global:PSProfileState.HistoryCommandCounts.ContainsKey($Name)) {
        $count = [int]$global:PSProfileState.HistoryCommandCounts[$Name]
    }
    $installed = $global:PSProfileState.CommandNameLookup.ContainsKey($Name)
    [PSCustomObject]@{
        Command    = $Name
        HistoryUses = $count
        IsInstalled = $installed
        CommandType = if ($installed) { $global:PSProfileState.CommandNameLookup[$Name].CommandType } else { 'Unknown/External' }
    }
}

function Get-PSProfileCommandDependencies {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        Write-Warning ("Command '{0}' was not found." -f $Name)
        return
    }
    $module = $command.Module
    [PSCustomObject]@{
        Command           = $command.Name
        ParentModule      = if ($module) { $module.Name } else { 'None' }
        ModulePath        = if ($module) { $module.Path } else { 'N/A' }
        RequiredModules   = if ($module) { @($module.RequiredModules | ForEach-Object { $_.Name }) } else { @() }
        RequiredAssemblies = if ($module) { @($module.RequiredAssemblies) } else { @() }
    }
}

function Search-PSProfileCommandHelp {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Query)
    Get-Help $Query -ErrorAction SilentlyContinue | Select-Object Name, Category, Synopsis
}

# ---------------------------------------------------------------------------
# History tools
# ---------------------------------------------------------------------------

function Get-PSHistoryPath {
    [CmdletBinding()]
    param()
    if (Get-Module -Name PSReadLine) {
        try { return (Get-PSReadLineOption -ErrorAction Stop).HistorySavePath } catch { }
    }
    return $null
}

function Get-PSHistoryStats {
    [CmdletBinding()]
    param()

    $historyPath = Get-PSHistoryPath
    if ([string]::IsNullOrWhiteSpace($historyPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        Write-Warning 'No PowerShell history file was found.'
        return
    }

    $entries = @(Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue)
    $commandFrequency = @{}
    $applicationFrequency = @{}

    foreach ($entry in $entries) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $tokens = $null
        $parseErrors = $null
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($entry, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors.Count -gt 0) { continue }
            $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
            foreach ($commandAst in $commands) {
                $name = Get-PSProfileCommandNameFromAst -CommandAst $commandAst
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                if ($commandFrequency.ContainsKey($name)) { $commandFrequency[$name]++ } else { $commandFrequency[$name] = 1 }
                $info = Get-Command -Name $name -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $info -and $info.CommandType -eq 'Application') {
                    if ($applicationFrequency.ContainsKey($name)) { $applicationFrequency[$name]++ } else { $applicationFrequency[$name] = 1 }
                }
            }
        } catch { continue }
    }

    Write-Host "`nPOWERSHELL HISTORY ANALYTICS" -ForegroundColor Cyan
    Write-Host ("History File:     {0}" -f $historyPath) -ForegroundColor DarkGray
    Write-Host ("Total Entries:    {0:N0}" -f $entries.Count) -ForegroundColor White
    Write-Host ("Unique Commands:  {0:N0}" -f $commandFrequency.Keys.Count) -ForegroundColor White
    Write-Host "`nTOP COMMANDS" -ForegroundColor Yellow
    foreach ($item in @($commandFrequency.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10)) {
        Write-Host ("  {0,-24} {1,6}" -f $item.Key, $item.Value) -ForegroundColor Green
    }
    Write-Host "`nTOP EXTERNAL APPLICATIONS" -ForegroundColor Yellow
    foreach ($item in @($applicationFrequency.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 10)) {
        Write-Host ("  {0,-24} {1,6}" -f $item.Key, $item.Value) -ForegroundColor Green
    }
}

function Get-PSHistoryUnique {
    [CmdletBinding()]
    param([ValidateRange(1, 10000)][int]$Limit = 100)
    $historyPath = Get-PSHistoryPath
    if ([string]::IsNullOrWhiteSpace($historyPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) { return }
    Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue | Select-Object -Unique | Select-Object -Last $Limit
}

function Get-PSHistoryTimeline {
    [CmdletBinding()]
    param([ValidateRange(10, 5000)][int]$Tail = 500)

    $historyPath = Get-PSHistoryPath
    if ([string]::IsNullOrWhiteSpace($historyPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) { return }
    $lines = @(Get-Content -LiteralPath $historyPath -Tail $Tail -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { return }

    $buckets = @{}
    $windowSize = [Math]::Max([int][Math]::Ceiling($lines.Count / 5.0), 1)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ([string]::IsNullOrWhiteSpace($lines[$index])) { continue }
        $label = 'Phase {0}' -f ([int][Math]::Floor($index / $windowSize) + 1)
        $tokens = $null
        $errors = $null
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($lines[$index], [ref]$tokens, [ref]$errors)
            $firstCommand = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
            $name = if ($null -ne $firstCommand) { Get-PSProfileCommandNameFromAst -CommandAst $firstCommand } else { '(unparsed)' }
        } catch { $name = '(unparsed)' }
        if (-not $buckets.ContainsKey($label)) { $buckets[$label] = @{} }
        if ($buckets[$label].ContainsKey($name)) { $buckets[$label][$name]++ } else { $buckets[$label][$name] = 1 }
    }

    foreach ($label in @($buckets.Keys | Sort-Object { [int]($_ -replace '\D', '') })) {
        $top = $buckets[$label].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        [PSCustomObject]@{
            TimelineBucket = $label
            TopCommand     = $top.Key
            SampleCommands = ($buckets[$label].Keys | Sort-Object | Select-Object -First 4) -join ', '
        }
    }
}

function Get-PSHistoryDuplicates {
    [CmdletBinding()]
    param([ValidateRange(1, 50)][int]$MinOccurrences = 5)
    $historyPath = Get-PSHistoryPath
    if ([string]::IsNullOrWhiteSpace($historyPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) { return }
    Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue |
        Group-Object |
        Where-Object { $_.Count -ge $MinOccurrences } |
        Sort-Object Count -Descending |
        Select-Object Count, @{ Name = 'CommandLine'; Expression = { $_.Name } }
}

function Get-PSHistoryErrors {
    [CmdletBinding()]
    param()
    return @($global:PSProfileState.ExecutionTracker | Where-Object { -not $_.Success })
}

function Export-PSHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Csv', 'Json', 'Text')][string]$Format = 'Csv'
    )

    $historyPath = Get-PSHistoryPath
    if ([string]::IsNullOrWhiteSpace($historyPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        Write-Warning 'No history file.'
        return
    }

    $content = @(Get-Content -LiteralPath $historyPath -ErrorAction SilentlyContinue)
    $items = New-Object System.Collections.ArrayList
    $skipped = 0
    foreach ($line in $content) {
        $sensitive = Test-PSProfileSensitiveCommandLine -Line $line
        if ($sensitive.Sensitive) { $skipped++; continue }
        $tokens = $null
        $errors = $null
        $commandName = ''
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$tokens, [ref]$errors)
            $commandAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
            if ($null -ne $commandAst) { $commandName = [string]$commandAst.GetCommandName() }
        } catch { }
        [void]$items.Add([PSCustomObject]@{ CommandLine = $line; Length = $line.Length; Command = $commandName })
    }

    switch ($Format) {
        'Csv'  { $items | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8 }
        'Json' { $items | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $Path -Encoding UTF8 }
        'Text' { $items.CommandLine | Set-Content -LiteralPath $Path -Encoding UTF8 }
    }
    Write-Host ("Exported {0} safe entries to '{1}'. Skipped {2} potentially sensitive entries." -f $items.Count, $Path, $skipped) -ForegroundColor Green
}

function Search-PSHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Pattern,
        [switch]$SimpleMatch,
        [ValidateRange(1, 10000)][int]$Limit = 50
    )

    $historyPath = Get-PSHistoryPath
    if ([string]::IsNullOrWhiteSpace($historyPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) { return }
    $criteria = @{ LiteralPath = $historyPath; Pattern = $Pattern; ErrorAction = 'SilentlyContinue' }
    if ($SimpleMatch) { $criteria['SimpleMatch'] = $true }
    Select-String @criteria | Select-Object -Last $Limit | ForEach-Object { $_.Line }
}

function Measure-PSProfileCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][scriptblock]$ScriptBlock)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $errorOccurred = $false
    $output = $null
    $nativeExitCode = $null
    $hadLastExitCode = Test-Path Variable:global:LASTEXITCODE
    $previousExitCode = $null
    if ($hadLastExitCode) { $previousExitCode = $global:LASTEXITCODE }

    try {
        $global:LASTEXITCODE = 0
        $output = & $ScriptBlock
        $nativeExitCode = $global:LASTEXITCODE
    } catch {
        $errorOccurred = $true
        Write-Error $_
    } finally {
        $stopwatch.Stop()
        if ($hadLastExitCode) { $global:LASTEXITCODE = $previousExitCode }
        else { Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
    }

    $success = (-not $errorOccurred -and ($null -eq $nativeExitCode -or $nativeExitCode -eq 0))
    $record = [PSCustomObject]@{
        Timestamp      = Get-Date
        DurationMs     = $stopwatch.ElapsedMilliseconds
        Success        = $success
        NativeExitCode = $nativeExitCode
        ScriptText     = $ScriptBlock.ToString().Trim()
    }
    [void]$global:PSProfileState.ExecutionTracker.Add($record)
    while ($global:PSProfileState.ExecutionTracker.Count -gt $global:PSProfileState.MaxExecutionRecords) {
        $global:PSProfileState.ExecutionTracker.RemoveAt(0)
    }

    $status = if ($success) { 'Success' } else { 'Failed' }
    Write-Host ("Execution completed in {0:N0} ms [Status: {1}]" -f $stopwatch.ElapsedMilliseconds, $status) -ForegroundColor DarkGray
    return $output
}

function Find-PSHistorySecrets {
    [CmdletBinding()]
    param(
        [switch]$Purge,
        [switch]$WhatIf
    )

    $historyPath = Get-PSHistoryPath
    if ([string]::IsNullOrWhiteSpace($historyPath) -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        Write-Warning 'History file not found.'
        return
    }

    $entries = @(Get-Content -LiteralPath $historyPath -ErrorAction Stop)
    $findings = New-Object System.Collections.ArrayList
    $cleanLines = New-Object 'System.Collections.Generic.List[string]'
    $insidePrivateKey = $false

    for ($index = 0; $index -lt $entries.Count; $index++) {
        $line = $entries[$index]
        $check = Test-PSProfileSensitiveCommandLine -Line $line
        if ($line -match '(?i)-----BEGIN(?: [A-Z0-9]+)* PRIVATE KEY-----') { $insidePrivateKey = $true }
        $isPrivateKeyLine = $insidePrivateKey
        $flagged = $check.Sensitive -or $isPrivateKeyLine

        if ($flagged) {
            $ruleText = if ($isPrivateKeyLine) { 'Private key block' } elseif ($check.Rules.Count -gt 0) { $check.Rules -join ', ' } else { 'Potential secret' }
            [void]$findings.Add([PSCustomObject]@{
                LineNumber = $index + 1
                Rule       = $ruleText
                Redacted   = '[REDACTED: matching line not displayed]'
            })
        } else {
            [void]$cleanLines.Add($line)
        }

        if ($insidePrivateKey -and $line -match '(?i)-----END(?: [A-Z0-9]+)* PRIVATE KEY-----') { $insidePrivateKey = $false }
    }

    Write-Host "`nPDE HISTORY SECRET AUDIT" -ForegroundColor Cyan
    if ($findings.Count -eq 0) {
        Write-Host '[PASS] No known credential patterns were detected.' -ForegroundColor Green
        return
    }
    Write-Warning ("Detected {0} potentially sensitive history lines:" -f $findings.Count)
    $findings | Format-Table LineNumber, Rule, Redacted -AutoSize

    if (-not $Purge) {
        Write-Host "`nRun Find-PSHistorySecrets -Purge to remove the flagged lines." -ForegroundColor DarkGray
        return
    }
    if ($WhatIf) {
        Write-Host ("[WHATIF] Would remove {0} flagged lines. No files changed." -f $findings.Count) -ForegroundColor Yellow
        return
    }

    # Do not create an unencrypted backup: it would preserve the credentials
    # this function is intended to remove. Back up separately only to protected
    # storage if your incident-response process requires it.
    $temporaryPath = Join-Path (Split-Path -Path $historyPath -Parent) ('.pde-history-{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    try {
        [System.IO.File]::WriteAllLines($temporaryPath, $cleanLines.ToArray(), $encoding)
        try {
            [System.IO.File]::Replace($temporaryPath, $historyPath, $null)
        } catch {
            Move-Item -LiteralPath $temporaryPath -Destination $historyPath -Force -ErrorAction Stop
        }
        Write-Host ("Removed {0} flagged lines from history. No plaintext backup was created." -f $findings.Count) -ForegroundColor Green
        Write-Warning 'Close and reopen all PowerShell sessions: running sessions may still hold old history in memory. Rotate any credentials that were exposed.'
    } catch {
        Write-Error ("History purge failed: {0}" -f $_.Exception.Message)
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Command-risk analysis
# ---------------------------------------------------------------------------

function Get-PSCommandRisk {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$CommandLine)

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($CommandLine, [ref]$tokens, [ref]$parseErrors)
    $triggers = New-Object 'System.Collections.Generic.List[string]'
    $riskLevel = 'LOW'

    if ($parseErrors.Count -gt 0) {
        $riskLevel = 'HIGH'
        [void]$triggers.Add('Command could not be parsed completely; manual review required.')
    }

    $commandAsts = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($commandAst in $commandAsts) {
        $rawName = $commandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($rawName)) {
            if ($riskLevel -notin @('HIGH', 'CRITICAL')) { $riskLevel = 'HIGH' }
            [void]$triggers.Add('Dynamic command invocation could not be resolved.')
            continue
        }

        $commandName = $rawName.ToLowerInvariant()
        $commandInfo = Get-Command -Name $rawName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $commandInfo -and $commandInfo.CommandType -eq 'Alias' -and $commandInfo.ResolvedCommandName) {
            $commandName = $commandInfo.ResolvedCommandName.ToLowerInvariant()
        }

        $hasRecurse = $false
        $hasForce = $false
        $argumentTexts = New-Object 'System.Collections.Generic.List[string]'

        foreach ($element in $commandAst.CommandElements) {
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                $parameterName = $element.ParameterName
                if ($parameterName -match '(?i)^r(ec(ur(se)?)?)?$') { $hasRecurse = $true }
                if ($parameterName -match '(?i)^fo(r(ce)?)?$') { $hasForce = $true }
            } elseif ($element -ne $commandAst.CommandElements[0]) {
                $argumentText = [string]$element.Extent.Text
                $argumentText = $argumentText.Trim().Trim('"').Trim("'")
                if (-not [string]::IsNullOrWhiteSpace($argumentText)) { [void]$argumentTexts.Add($argumentText) }
            }
        }

        $isDiskDestructive = $commandName -in @('format-volume', 'clear-disk', 'initialize-disk', 'remove-partition', 'clear-partition')
        $isRecursiveDelete = ($commandName -eq 'remove-item' -and $hasRecurse -and $hasForce)

        if ($isDiskDestructive) {
            $riskLevel = 'CRITICAL'
            [void]$triggers.Add(("Critical disk-management command: '{0}'" -f $rawName))
            continue
        }

        if ($isRecursiveDelete) {
            $dangerousTarget = $false
            foreach ($argument in $argumentTexts) {
                $expanded = [Environment]::ExpandEnvironmentVariables($argument)
                $expanded = $expanded -replace '(?i)\$env:SystemRoot', $env:SystemRoot
                $expanded = $expanded -replace '(?i)\$env:windir', $env:windir
                $expanded = $expanded.TrimEnd('\\')

                if ($expanded -match '(?i)^[A-Z]:$' -or
                    $expanded -match '(?i)^[A-Z]:\\Windows(?:\\|$)' -or
                    $expanded -match '(?i)^[A-Z]:\\System32(?:\\|$)' -or
                    $expanded -match '(?i)\\Windows\\System32(?:\\|$)') {
                    $dangerousTarget = $true
                    break
                }
            }

            if ($dangerousTarget) {
                $riskLevel = 'CRITICAL'
                [void]$triggers.Add(("Recursive forced deletion targets a drive root or Windows system directory: '{0}'" -f $rawName))
            } else {
                if ($riskLevel -ne 'CRITICAL') { $riskLevel = 'HIGH' }
                [void]$triggers.Add(("Recursive forced deletion: '{0}' (target may need manual review)" -f $rawName))
            }
            continue
        }

        if ($commandName -in @('set-executionpolicy', 'stop-computer', 'restart-computer', 'remove-aduser', 'remove-localuser', 'disable-netfirewallrule', 'set-netfirewallprofile', 'remove-netfirewallrule', 'remove-itemproperty')) {
            if ($riskLevel -ne 'CRITICAL') { $riskLevel = 'HIGH' }
            [void]$triggers.Add(("Elevated system or security change: '{0}'" -f $rawName))
        } elseif ($commandName -in @('stop-service', 'restart-service', 'set-service', 'stop-process', 'kill', 'set-itemproperty', 'set-acl', 'takeown', 'icacls')) {
            if ($riskLevel -notin @('CRITICAL', 'HIGH')) { $riskLevel = 'MEDIUM' }
            [void]$triggers.Add(("Process, permission or configuration change: '{0}'" -f $rawName))
        }

        # cmd.exe /c rd /s /q ... is outside PowerShell's inner AST, so detect
        # this specific common destructive form separately.
        if ($commandName -in @('cmd', 'cmd.exe') -and $CommandLine -match '(?i)\b(?:rd|rmdir)\s+/s\s+/q\s+[A-Z]:\\') {
            $riskLevel = 'CRITICAL'
            [void]$triggers.Add('cmd.exe is invoking recursive quiet deletion against a drive path.')
        }
    }

    return [PSCustomObject]@{
        CommandLine = $CommandLine
        RiskLevel   = $riskLevel
        Triggers    = @($triggers | Select-Object -Unique)
        Evaluated   = Get-Date
        IsSecurityBoundary = $false
    }
}

function Test-PSCommandRisk {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$CommandLine)

    $analysis = Get-PSCommandRisk -CommandLine $CommandLine
    $color = switch ($analysis.RiskLevel) {
        'CRITICAL' { 'Red' }
        'HIGH'     { 'Magenta' }
        'MEDIUM'   { 'Yellow' }
        default    { 'Green' }
    }

    Write-Host "`nCOMMAND RISK AUDIT" -ForegroundColor Cyan
    Write-Host ("Line: {0}" -f $analysis.CommandLine) -ForegroundColor White
    Write-Host ("Risk: {0}" -f $analysis.RiskLevel) -ForegroundColor $color
    if ($analysis.Triggers.Count -gt 0) {
        foreach ($trigger in $analysis.Triggers) { Write-Host ("  - {0}" -f $trigger) -ForegroundColor $color }
    } else {
        Write-Host 'No elevated heuristic risk patterns identified.' -ForegroundColor Green
    }
    Write-Host 'Note: this is heuristic analysis, not a security boundary.' -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# Network and system diagnostics
# ---------------------------------------------------------------------------

function Get-NetworkInfo {
    [CmdletBinding()]
    param()

    $adapters = @()
    if (Test-PSProfileCommandAvailable 'Get-NetIPAddress') {
        $adapters = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
            Select-Object InterfaceAlias, IPAddress, PrefixLength)
    }

    $domain = $env:USERDOMAIN
    if (Test-PSProfileCommandAvailable 'Get-CimInstance') {
        try {
            $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if ($computerSystem.Domain) { $domain = $computerSystem.Domain }
        } catch { }
    }

    $dnsServers = @('Unavailable')
    if (Test-PSProfileCommandAvailable 'Get-DnsClientServerAddress') {
        $foundDns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            ForEach-Object { $_.ServerAddresses } | Where-Object { $_ } | Select-Object -Unique)
        if ($foundDns.Count -gt 0) { $dnsServers = $foundDns }
    }

    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        Domain       = $domain
        IPv4Adapters = $adapters
        DNSServers   = $dnsServers
    }
}

function Get-ListeningPorts {
    [CmdletBinding()]
    param([int]$Port = -1)

    if ($PSBoundParameters.ContainsKey('Port') -and ($Port -lt 1 -or $Port -gt 65535)) {
        throw 'Port must be between 1 and 65535.'
    }

    if (Test-PSProfileCommandAvailable 'Get-NetTCPConnection') {
        $criteria = @{ State = 'Listen'; ErrorAction = 'SilentlyContinue' }
        if ($PSBoundParameters.ContainsKey('Port')) { $criteria['LocalPort'] = $Port }
        Get-NetTCPConnection @criteria | ForEach-Object {
            $process = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                Protocol     = 'TCP'
                LocalAddress = $_.LocalAddress
                Port         = $_.LocalPort
                ProcessId    = $_.OwningProcess
                ProcessName  = if ($process) { $process.ProcessName } else { 'Unknown' }
            }
        }
    } else {
        $filter = if ($PSBoundParameters.ContainsKey('Port')) { ":$Port\s" } else { 'LISTENING' }
        netstat -ano | Select-String $filter
    }
}

function Get-PortProcess {
    [CmdletBinding()]
    param([ValidateRange(1, 65535)][int]$Port)
    Get-ListeningPorts -Port $Port
}

function Test-TcpPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$Target,
        [Parameter(Mandatory = $true, Position = 1)][ValidateRange(1, 65535)][int]$Port,
        [ValidateRange(100, 60000)][int]$TimeoutMs = 1500
    )

    $client = New-Object System.Net.Sockets.TcpClient
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $waitHandle = $null
    $isOpen = $false
    $resultText = 'Timeout or connection refused'

    try {
        $asyncResult = $client.BeginConnect($Target, $Port, $null, $null)
        $waitHandle = $asyncResult.AsyncWaitHandle
        if ($waitHandle.WaitOne($TimeoutMs, $false)) {
            $client.EndConnect($asyncResult)
            $isOpen = $client.Connected
            $resultText = if ($isOpen) { 'Connected' } else { 'Connection failed' }
        } else {
            $resultText = 'Timed out'
        }
    } catch {
        $resultText = $_.Exception.Message
    } finally {
        $stopwatch.Stop()
        if ($null -ne $waitHandle) { $waitHandle.Close() }
        $client.Close()
    }

    [PSCustomObject]@{
        Target     = $Target
        Port       = $Port
        Open       = $isOpen
        LatencyMs  = $stopwatch.ElapsedMilliseconds
        Result     = $resultText
    }
}

function Test-DnsLookup {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][ValidateNotNullOrEmpty()][string]$Name)
    if (Test-PSProfileCommandAvailable 'Resolve-DnsName') {
        Resolve-DnsName -Name $Name -ErrorAction Continue
    } else {
        [System.Net.Dns]::GetHostAddresses($Name)
    }
}

function Get-NetworkAdapters {
    [CmdletBinding()]
    param()
    if (Test-PSProfileCommandAvailable 'Get-NetAdapter') {
        Get-NetAdapter -ErrorAction SilentlyContinue | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
    } else {
        Write-Warning 'Get-NetAdapter is unavailable on this system.'
    }
}

function Get-NetworkRoutes {
    [CmdletBinding()]
    param()
    if (Test-PSProfileCommandAvailable 'Get-NetRoute') {
        Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object DestinationPrefix, NextHop, RouteMetric, InterfaceAlias
    } else {
        route print -4
    }
}

function Get-FirewallStatus {
    [CmdletBinding()]
    param()
    if (Test-PSProfileCommandAvailable 'Get-NetFirewallProfile') {
        Get-NetFirewallProfile -ErrorAction SilentlyContinue | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
    } else {
        Write-Warning 'Get-NetFirewallProfile is unavailable on this system.'
    }
}

function Get-CPUUsage {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'Get-CimInstance')) { return }

    $processors = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    if ($processors.Count -eq 0) {
        return [PSCustomObject]@{ CPUName = 'Unknown'; LoadPercentage = $null; Cores = 0; LogicalProcessors = 0 }
    }

    $loads = @($processors | Where-Object { $null -ne $_.LoadPercentage } | ForEach-Object { [double]$_.LoadPercentage })
    $averageLoad = if ($loads.Count -gt 0) { [Math]::Round((($loads | Measure-Object -Average).Average), 1) } else { $null }
    [PSCustomObject]@{
        CPUName           = (($processors | ForEach-Object { $_.Name.Trim() } | Select-Object -Unique) -join '; ')
        LoadPercentage    = $averageLoad
        Cores             = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
        LogicalProcessors = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    }
}

function Get-RamUsage {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'Get-CimInstance')) { return }

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($null -eq $os -or $os.TotalVisibleMemorySize -le 0) { return }

    $totalGB = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGB = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedGB = [Math]::Round($totalGB - $freeGB, 2)
    [PSCustomObject]@{
        Total_GB = $totalGB
        Used_GB  = $usedGB
        Free_GB  = $freeGB
        PctUsed  = [Math]::Round(($usedGB / $totalGB) * 100, 1)
    }
}

function Get-DiskSpace {
    [CmdletBinding()]
    param()
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $totalBytes = [double]($_.Used + $_.Free)
        $totalGB = [Math]::Round($totalBytes / 1GB, 2)
        $freeGB = [Math]::Round([double]$_.Free / 1GB, 2)
        [PSCustomObject]@{
            DriveName  = $_.Name
            Root       = $_.Root
            Total_GB   = $totalGB
            Free_GB    = $freeGB
            PercentFree = if ($totalGB -gt 0) { [Math]::Round(($freeGB / $totalGB) * 100, 1) } else { 0 }
        }
    }
}

# Kept for compatibility with earlier PDE V2 commands. This measures free space,
# not SMART status or physical drive health.
function Get-DiskHealth {
    [CmdletBinding()]
    param()
    Get-DiskSpace
}

function Get-ServiceHealth {
    [CmdletBinding()]
    param()
    Get-Service -ErrorAction SilentlyContinue | Group-Object Status | Select-Object @{ Name = 'Status'; Expression = { $_.Name } }, Count
}

function Get-StartupPrograms {
    [CmdletBinding()]
    param()
    if (Test-PSProfileCommandAvailable 'Get-CimInstance') {
        Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue | Select-Object Name, Command, Location, User
    }
}

function Get-InstalledSoftware {
    [CmdletBinding()]
    param([string]$Filter)

    $keys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Where-Object { if ($Filter) { $_.DisplayName -like ("*{0}*" -f $Filter) } else { $true } } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object DisplayName
}

function Get-CertificateInfo {
    [CmdletBinding()]
    param([ValidateSet('My', 'Root')][string]$Store = 'My')
    Get-ChildItem -Path ("Cert:\CurrentUser\{0}" -f $Store) -ErrorAction SilentlyContinue |
        Select-Object Subject, NotAfter, Thumbprint, HasPrivateKey
}

function Get-SystemInfo {
    [CmdletBinding()]
    param()

    $osCaption = [Environment]::OSVersion.VersionString
    $totalRam = 0
    $freeRam = 0
    if (Test-PSProfileCommandAvailable 'Get-CimInstance') {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $osCaption = $os.Caption
            $totalRam = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            $freeRam = [Math]::Round($os.FreePhysicalMemory / 1MB, 2)
        } catch { }
    }

    [PSCustomObject]@{
        ComputerName    = $env:COMPUTERNAME
        UserName        = [Environment]::UserName
        OperatingSystem = $osCaption
        PowerShell      = $PSVersionTable.PSVersion.ToString()
        TotalRAM_GB     = $totalRam
        FreeRAM_GB      = $freeRam
        CurrentFolder   = (Get-Location).Path
    }
}

function Invoke-PSProfileSystemCheck {
    [CmdletBinding()]
    param([ValidateSet('All', 'Network', 'System', 'Storage', 'Security', 'Profile')][string]$Category = 'All')

    $report = New-Object System.Collections.ArrayList
    if ($Category -in @('All', 'System')) {
        $ram = Get-RamUsage
        $cpu = Get-CPUUsage
        $ramStatus = if ($null -eq $ram) { 'UNKNOWN' } elseif ($ram.PctUsed -lt 85) { 'PASS' } else { 'WARN' }
        $cpuStatus = if ($null -eq $cpu -or $null -eq $cpu.LoadPercentage) { 'UNKNOWN' } elseif ($cpu.LoadPercentage -lt 85) { 'PASS' } else { 'WARN' }
        [void]$report.Add([PSCustomObject]@{ Domain = 'System'; Check = 'RAM Utilization'; Status = $ramStatus; Metric = if ($ram) { ('{0}% used ({1} GB free)' -f $ram.PctUsed, $ram.Free_GB) } else { 'Unavailable' } })
        [void]$report.Add([PSCustomObject]@{ Domain = 'System'; Check = 'CPU Load'; Status = $cpuStatus; Metric = if ($cpu) { ('{0}% load' -f $cpu.LoadPercentage) } else { 'Unavailable' } })
    }

    if ($Category -in @('All', 'Storage')) {
        foreach ($drive in (Get-DiskSpace)) {
            $status = if ($drive.PercentFree -gt 15) { 'PASS' } else { 'WARN' }
            [void]$report.Add([PSCustomObject]@{ Domain = 'Storage'; Check = ("Disk Space ({0})" -f $drive.DriveName); Status = $status; Metric = ("{0}% free ({1} GB)" -f $drive.PercentFree, $drive.Free_GB) })
        }
    }

    if ($Category -in @('All', 'Network')) {
        $network = Get-NetworkInfo
        $addressCount = @($network.IPv4Adapters).Count
        $networkStatus = if ($addressCount -gt 0) { 'PASS' } else { 'WARN' }
        [void]$report.Add([PSCustomObject]@{ Domain = 'Network'; Check = 'IPv4 Addresses'; Status = $networkStatus; Metric = ("{0} non-loopback IPv4 address(es)" -f $addressCount) })
    }

    if ($Category -in @('All', 'Security')) {
        $security = Get-PSProfileSecurityStatus
        $guardStatus = if ($security.SecurityMode -eq 'Off') { 'WARN' } elseif ($security.PSReadLineGuardHooked) { 'PASS' } else { 'WARN' }
        [void]$report.Add([PSCustomObject]@{ Domain = 'Security'; Check = 'Command Guard'; Status = $guardStatus; Metric = ("{0}; installed={1}" -f $security.SecurityMode, $security.PSReadLineGuardHooked) })
        $historyStatus = if (-not $security.HistoryFilterEnabled) { 'WARN' } elseif ($security.HistoryFilterInstalled) { 'PASS' } else { 'WARN' }
        [void]$report.Add([PSCustomObject]@{ Domain = 'Security'; Check = 'History Filter'; Status = $historyStatus; Metric = ("enabled={0}; installed={1}" -f $security.HistoryFilterEnabled, $security.HistoryFilterInstalled) })
    }

    if ($Category -in @('All', 'Profile')) {
        $cacheStatus = if ($global:PSProfileState.CommandNameCache.Count -gt 0) { 'PASS' } else { 'FAIL' }
        [void]$report.Add([PSCustomObject]@{ Domain = 'Profile'; Check = 'Command Cache'; Status = $cacheStatus; Metric = ("{0} commands indexed" -f $global:PSProfileState.CommandNameCache.Count) })
    }

    $report | Format-Table -AutoSize
}

# ---------------------------------------------------------------------------
# Project discovery and developer tools
# ---------------------------------------------------------------------------

function Find-PSProject {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-Location).Path,
        [ValidateRange(0, 20)][int]$MaxDepth = 4
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "Directory not found: $Path"
        return
    }

    $stack = New-Object System.Collections.Stack
    $stack.Push([PSCustomObject]@{ Directory = (Get-Item -LiteralPath $Path).FullName; Depth = 0 })
    $skipNames = @('.git', 'node_modules', 'bin', 'obj', '.venv', 'venv', '__pycache__')

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $markers = @(Get-PSProfileProjectMarkers -Path $current.Directory)
        if ($markers.Count -gt 0) {
            [PSCustomObject]@{
                Name       = (Split-Path -Path $current.Directory -Leaf)
                Directory  = $current.Directory
                Indicators = ($markers -join ', ')
            }
        }

        if ($current.Depth -ge $MaxDepth) { continue }
        foreach ($directory in (Get-ChildItem -LiteralPath $current.Directory -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($directory.Name -notin $skipNames) {
                $stack.Push([PSCustomObject]@{ Directory = $directory.FullName; Depth = ($current.Depth + 1) })
            }
        }
    }
}

function Get-PSProjectRoot {
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    $current = (Get-Item -LiteralPath $Path).FullName

    while (-not [string]::IsNullOrWhiteSpace($current)) {
        $markers = @(Get-PSProfileProjectMarkers -Path $current)
        if ($markers.Count -gt 0) { return $current }
        $parent = Split-Path -Path $current -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
    return $null
}

function Set-LocationToGitRoot {
    [CmdletBinding()]
    param()
    $root = Get-PSProjectRoot
    if ($root) {
        Set-Location -LiteralPath $root
        Write-Host ("Moved to: {0}" -f $root) -ForegroundColor Green
    } else {
        Write-Warning 'No project root found.'
    }
}

function Find-PSProjectFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Filter,
        [string]$Path = (Get-Location).Path,
        [ValidateRange(0, 50)][int]$MaxDepth = 20
    )

    Get-PSProfileFiles -Path $Path -Filter $Filter -FilesOnly -MaxDepth $MaxDepth |
        Select-Object Name, Length, LastWriteTime, FullName
}

function Find-PSCodeReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Pattern,
        [string]$Extension,
        [string]$Path = (Get-Location).Path,
        [switch]$CaseSensitive,
        [ValidateRange(0, 20)][int]$ContextLines = 0,
        [ValidateRange(0, 50)][int]$MaxDepth = 20
    )

    $filter = if ($Extension) { '*.{0}' -f $Extension.TrimStart('.') } else { '*' }
    $files = @(Get-PSProfileFiles -Path $Path -Filter $filter -FilesOnly -MaxDepth $MaxDepth)
    if ($files.Count -eq 0) { return }

    $criteria = @{ Pattern = $Pattern; Context = $ContextLines; ErrorAction = 'SilentlyContinue' }
    if ($CaseSensitive) { $criteria['CaseSensitive'] = $true }
    $matches = foreach ($file in $files) {
        Select-String -LiteralPath $file.FullName @criteria
    }
    $matches | Select-Object Path, LineNumber, Line, Context
}

function Invoke-PSDotNetBuild {
    [CmdletBinding()]
    param([ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug')
    if (-not (Test-PSProfileCommandAvailable 'dotnet')) { Write-Warning 'dotnet was not found on PATH.'; return }
    dotnet build -c $Configuration
}

function Invoke-PSDotNetTest {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'dotnet')) { Write-Warning 'dotnet was not found on PATH.'; return }
    dotnet test --logger 'console;verbosity=normal'
}

function Invoke-PSDotNetClean {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'dotnet')) { Write-Warning 'dotnet was not found on PATH.'; return }
    dotnet clean
}

function Get-PSDotNetProjects {
    [CmdletBinding()]
    param([string]$Path = (Get-Location).Path)
    foreach ($filter in @('*.sln', '*.slnx', '*.csproj', '*.fsproj', '*.vbproj')) {
        Find-PSProjectFiles -Filter $filter -Path $Path
    }
}

function Initialize-PSPythonEnvironment {
    [CmdletBinding()]
    param([string]$Name = '.venv')
    if (Test-Path -LiteralPath $Name) {
        Write-Warning 'Environment folder already exists.'
        return
    }
    if (-not (Test-PSProfileCommandAvailable 'python')) { Write-Warning 'python was not found on PATH.'; return }
    python -m venv $Name
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("Virtual environment '{0}' created." -f $Name) -ForegroundColor Green
    } else {
        Write-Warning ("Virtual environment creation failed (exit code {0})." -f $LASTEXITCODE)
    }
}

function Invoke-PSPythonTest {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'pytest')) { Write-Warning 'pytest was not found on PATH.'; return }
    pytest
}

function Get-PSPythonEnvironment {
    [CmdletBinding()]
    param()
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue | Select-Object -First 1
    $pipVersion = $null
    if (Test-PSProfileCommandAvailable 'python') { $pipVersion = (& python -m pip --version 2>$null | Out-String).Trim() }
    [PSCustomObject]@{
        PythonBinary = if ($pythonCommand) { $pythonCommand.Source } else { $null }
        VirtualEnv   = $env:VIRTUAL_ENV
        PipVersion   = $pipVersion
    }
}

function Get-PSPythonPackages {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'python')) { Write-Warning 'python was not found on PATH.'; return }
    python -m pip list
}

function Get-PSNodeEnvironment {
    [CmdletBinding()]
    param()
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue | Select-Object -First 1
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue | Select-Object -First 1
    $nodeVersion = if ($nodeCommand) { (& node -v 2>$null | Out-String).Trim() } else { $null }
    $npmVersion = if ($npmCommand) { (& npm -v 2>$null | Out-String).Trim() } else { $null }
    [PSCustomObject]@{
        NodeBinary = if ($nodeCommand) { $nodeCommand.Source } else { $null }
        NodeVersion = $nodeVersion
        NpmVersion = $npmVersion
    }
}

function Invoke-PSNpmTest {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'npm')) { Write-Warning 'npm was not found on PATH.'; return }
    npm test
}

function Get-PSNpmOutdated {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'npm')) { Write-Warning 'npm was not found on PATH.'; return }
    npm outdated
}

function Get-PSNpmScripts {
    [CmdletBinding()]
    param([string]$Path = (Join-Path (Get-Location).Path 'package.json'))
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Warning 'package.json not found.'
        return
    }
    try {
        $package = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return $package.scripts
    } catch {
        Write-Warning ("Could not read package.json: {0}" -f $_.Exception.Message)
    }
}

function Get-PSDockerStatus {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'docker')) { Write-Warning 'docker was not found on PATH.'; return }
    $json = docker info --format '{{json .}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($json | Out-String))) {
        Write-Warning 'Docker is installed but its daemon did not return status information.'
        return
    }
    try {
        ($json | ConvertFrom-Json -ErrorAction Stop) | Select-Object ServerVersion, Containers, ContainersRunning, Images
    } catch {
        Write-Warning 'Docker returned status data that could not be parsed as JSON.'
    }
}

function Get-PSDockerContainers {
    [CmdletBinding()]
    param([switch]$All)
    if (-not (Test-PSProfileCommandAvailable 'docker')) { Write-Warning 'docker was not found on PATH.'; return }
    if ($All) { docker ps -a } else { docker ps }
}

function Get-PSDockerImages {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'docker')) { Write-Warning 'docker was not found on PATH.'; return }
    docker images
}

function Get-PSDockerUsage {
    [CmdletBinding()]
    param()
    if (-not (Test-PSProfileCommandAvailable 'docker')) { Write-Warning 'docker was not found on PATH.'; return }
    docker system df
}

function Invoke-PSDockerCleanupPreview {
    [CmdletBinding()]
    param()
    Write-Host '[PREVIEW] Docker disk-usage report. No cleanup operation will be run.' -ForegroundColor Cyan
    Get-PSDockerUsage
}

function Invoke-PSProjectCheck {
    [CmdletBinding()]
    param(
        [switch]$Execute,
        [string]$Path = (Get-Location).Path
    )

    if (-not $global:PSProfileConfig.DeveloperToolsEnabled) {
        Write-Warning 'Developer tools are disabled in PDE configuration.'
        return
    }

    $root = Get-PSProjectRoot -Path $Path
    if (-not $root) { Write-Warning 'No project root detected.'; return }
    Write-Host ("Project Root: {0}" -f $root) -ForegroundColor Cyan

    $tasks = New-Object 'System.Collections.Generic.List[string]'
    $dotnetFiles = @()
    foreach ($pattern in @('*.sln', '*.slnx', '*.csproj', '*.fsproj', '*.vbproj')) {
        $dotnetFiles += @(Get-PSProfileFiles -Path $root -Filter $pattern -FilesOnly -MaxDepth 8)
    }
    if ($dotnetFiles.Count -gt 0) {
        [void]$tasks.Add('dotnet build')
        [void]$tasks.Add('dotnet test')
    }
    if (Test-Path -LiteralPath (Join-Path $root 'package.json') -PathType Leaf) {
        $scripts = Get-PSNpmScripts -Path (Join-Path $root 'package.json')
        if ($scripts -and $scripts.test) { [void]$tasks.Add('npm test') }
    }
    if ((Test-Path -LiteralPath (Join-Path $root 'pyproject.toml')) -or (Test-Path -LiteralPath (Join-Path $root 'requirements.txt'))) {
        [void]$tasks.Add('pytest')
    }

    Write-Host 'Planned Validation Commands:' -ForegroundColor Yellow
    foreach ($task in $tasks) { Write-Host ("  [PLAN] {0}" -f $task) -ForegroundColor White }
    if (-not $Execute) {
        Write-Host "`nDry run completed. Add -Execute to run the listed operations." -ForegroundColor DarkGray
        return
    }

    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $root
        foreach ($task in $tasks) {
            Write-Host ("`n>>> Running: {0}" -f $task) -ForegroundColor Cyan
            switch ($task) {
                'dotnet build' {
                    if (Test-PSProfileCommandAvailable 'dotnet') { dotnet build } else { Write-Warning 'dotnet unavailable; skipped.' }
                }
                'dotnet test' {
                    if (Test-PSProfileCommandAvailable 'dotnet') { dotnet test } else { Write-Warning 'dotnet unavailable; skipped.' }
                }
                'npm test' {
                    if (Test-PSProfileCommandAvailable 'npm') { npm test } else { Write-Warning 'npm unavailable; skipped.' }
                }
                'pytest' {
                    if (Test-PSProfileCommandAvailable 'pytest') { pytest }
                    elseif (Test-PSProfileCommandAvailable 'python') { python -m pytest }
                    else { Write-Warning 'pytest and python unavailable; skipped.' }
                }
            }
            if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) {
                Write-Warning ("'{0}' returned exit code {1}." -f $task, $LASTEXITCODE)
            }
        }
    } finally {
        Set-Location -LiteralPath $originalLocation.Path
    }
}

# ---------------------------------------------------------------------------
# Profile diagnostics and configuration
# ---------------------------------------------------------------------------

function Test-PSProfile {
    [CmdletBinding()]
    param()

    $results = New-Object System.Collections.ArrayList
    $psrl = Get-Module -Name PSReadLine | Select-Object -First 1
    [void]$results.Add([PSCustomObject]@{
        Category = 'PSReadLine'; Check = 'Module Loaded'
        Status = if ($psrl) { 'PASS' } else { 'WARN' }
        Severity = 'HIGH'
        Description = if ($psrl) { "Version $($psrl.Version)" } else { 'PSReadLine is not loaded in this host.' }
        SuggestedFix = 'Use an interactive console host and install PSReadLine if required.'
    })

    $cached = $global:PSProfileState.CommandNameCache.Count
    [void]$results.Add([PSCustomObject]@{
        Category = 'Cache'; Check = 'Command Index'
        Status = if ($cached -gt 0) { 'PASS' } else { 'FAIL' }
        Severity = 'HIGH'
        Description = ("{0} commands cached" -f $cached)
        SuggestedFix = 'Run Update-PSProfile.'
    })

    $historyPath = Get-PSHistoryPath
    $historyExists = (-not [string]::IsNullOrWhiteSpace($historyPath) -and (Test-Path -LiteralPath $historyPath -PathType Leaf))
    [void]$results.Add([PSCustomObject]@{
        Category = 'History'; Check = 'History Storage'
        Status = if ($historyExists) { 'PASS' } else { 'WARN' }
        Severity = 'MEDIUM'
        Description = if ($historyExists) { $historyPath } else { 'History path is unavailable.' }
        SuggestedFix = 'Check Get-PSReadLineOption and the history save path.'
    })

    $historyFilterStatus = if (-not $global:PSProfileConfig.HistoryFilterEnabled) { 'WARN' } elseif ($global:PSProfileState.HistoryFilterInstalled) { 'PASS' } else { 'WARN' }
    [void]$results.Add([PSCustomObject]@{
        Category = 'History'; Check = 'Sensitive History Filter'
        Status = $historyFilterStatus
        Severity = 'HIGH'
        Description = ("Enabled={0}; Installed={1}; Error={2}" -f $global:PSProfileConfig.HistoryFilterEnabled, $global:PSProfileState.HistoryFilterInstalled, $global:PSProfileState.HistoryFilterError)
        SuggestedFix = 'Check PSReadLine availability and the history filter installation error.'
    })

    $securityMode = $global:PSProfileConfig.SecurityMode
    $securityStatus = if ($securityMode -eq 'Off') { 'WARN' } elseif ($global:PSProfileState.SecurityGuardInstalled) { 'PASS' } else { 'WARN' }
    [void]$results.Add([PSCustomObject]@{
        Category = 'Security'; Check = 'Command Validation Guard'
        Status = $securityStatus
        Severity = 'HIGH'
        Description = ("Mode={0}; Installed={1}; Error={2}" -f $securityMode, $global:PSProfileState.SecurityGuardInstalled, $global:PSProfileState.SecurityGuardError)
        SuggestedFix = 'Run Set-PSProfileSecurityMode -Mode Warn and inspect any installation error.'
    })

    [void]$results.Add([PSCustomObject]@{
        Category = 'TypoDetection'; Check = 'Command Suggestion'
        Status = if ($global:PSProfileConfig.LiveTypoHighlightEnabled -and $global:PSProfileState.PSReadLineReady) { 'PASS' } else { 'WARN' }
        Severity = 'LOW'
        Description = 'Non-invasive typo suggestions are shown when a command is accepted; the console buffer is not repainted.'
        SuggestedFix = 'Use Test-PSProfileCommandSpelling for a manual lookup.'
    })

    return @($results)
}

function Show-PSProfileDashboard {
    [CmdletBinding()]
    param()

    $diagnostics = Test-PSProfile
    $passCount = @($diagnostics | Where-Object { $_.Status -eq 'PASS' }).Count
    $warningCount = @($diagnostics | Where-Object { $_.Status -eq 'WARN' }).Count
    $failCount = @($diagnostics | Where-Object { $_.Status -eq 'FAIL' }).Count

    Write-Host "`n================================================================================" -ForegroundColor Cyan
    Write-Host '             POWERSHELL DEVELOPER ENVIRONMENT (PDE) V2' -ForegroundColor White
    Write-Host '================================================================================' -ForegroundColor Cyan
    Write-Host 'RUNTIME TELEMETRY' -ForegroundColor Yellow
    Write-Host ("  PowerShell:       {0} ({1})" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
    Write-Host ("  Host Process:     {0}" -f $Host.Name)
    Write-Host ("  Startup Duration: {0} ms" -f $global:PSProfileState.StartupDurationMs)
    Write-Host ("  Profile Path:     {0}" -f $PROFILE)
    Write-Host "`nCOMMAND INTELLIGENCE & PERFORMANCE" -ForegroundColor Yellow
    Write-Host ("  Indexed Commands: {0:N0}" -f $global:PSProfileState.CommandNameCache.Count)
    Write-Host ("  History Indexed:  {0:N0}" -f $global:PSProfileState.HistoryCommandCounts.Count)
    Write-Host '  Spelling Engine:  Optimal String Alignment + keyboard scoring'
    Write-Host ("  Security Mode:    {0}" -f $global:PSProfileConfig.SecurityMode)
    Write-Host ("  Loaded Tooling:   {0}" -f ($global:PSProfileState.OptionalModulesLoaded -join ', '))
    Write-Host "`nHEALTH STATUS: " -NoNewline
    if ($failCount -gt 0) {
        Write-Host ("FAILURES [{0} FAILS, {1} WARNINGS]" -f $failCount, $warningCount) -ForegroundColor Red
    } elseif ($warningCount -gt 0) {
        Write-Host ("OPERATIONAL WITH WARNINGS [{0}]" -f $warningCount) -ForegroundColor Yellow
    } else {
        Write-Host ("OPERATIONAL [{0} CHECKS PASSED]" -f $passCount) -ForegroundColor Green
    }
    Write-Host ''
    $diagnostics | Format-Table Status, Category, Check, Description -AutoSize
}

function Get-PSProfileStatus {
    [CmdletBinding()]
    param()
    $psrl = Get-Module -Name PSReadLine | Select-Object -First 1
    [PSCustomObject]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PSReadLineVersion = if ($psrl) { $psrl.Version.ToString() } else { 'Not loaded' }
        SecurityMode      = $global:PSProfileConfig.SecurityMode
        SecurityGuard     = $global:PSProfileState.SecurityGuardInstalled
        HistoryFilter     = $global:PSProfileState.HistoryFilterInstalled
        CommandsIndexed   = $global:PSProfileState.CommandNameCache.Count
        HistoryIndexed    = $global:PSProfileState.HistoryCommandCounts.Count
        StartupTimeMs     = $global:PSProfileState.StartupDurationMs
        Integrations      = ($global:PSProfileState.OptionalModulesLoaded -join ', ')
    }
}

function Get-PSProfileDiagnostics {
    [CmdletBinding()]
    param()
    Test-PSProfile | Format-Table -AutoSize
}

function Get-PSProfileConfig {
    [CmdletBinding()]
    param()
    [PSCustomObject]$global:PSProfileConfig
}

function Set-PSProfileConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value
    )

    if (-not $global:PSProfileConfig.ContainsKey($Key)) {
        Write-Warning ("Unknown configuration key: {0}" -f $Key)
        return
    }

    switch ($Key) {
        'SecurityMode' {
            if ($Value -notin @('Off', 'Warn', 'Strict')) { throw "SecurityMode must be Off, Warn or Strict." }
            Set-PSProfileSecurityMode -Mode $Value
            return
        }
        { $_ -in @('LiveTypoHighlightEnabled', 'KeyboardAwareScoring', 'HistoryFilterEnabled', 'DeveloperToolsEnabled') } {
            if ($Value -isnot [bool]) { throw "$Key must be a Boolean value." }
            break
        }
        { $_ -in @('MaximumEditDistance', 'MaxHistoryIndexCount', 'LiveTypoMaxDistance') } {
            $integerValue = 0
            if (-not [int]::TryParse([string]$Value, [ref]$integerValue)) { throw "$Key must be an integer." }
            if ($Key -eq 'MaximumEditDistance' -and ($integerValue -lt 1 -or $integerValue -gt 5)) { throw 'MaximumEditDistance must be between 1 and 5.' }
            if ($Key -eq 'LiveTypoMaxDistance' -and ($integerValue -lt 1 -or $integerValue -gt 5)) { throw 'LiveTypoMaxDistance must be between 1 and 5.' }
            if ($Key -eq 'MaxHistoryIndexCount' -and ($integerValue -lt 100 -or $integerValue -gt 50000)) { throw 'MaxHistoryIndexCount must be between 100 and 50000.' }
            $Value = $integerValue
            break
        }
        'PredictionSource' {
            if ($Value -notin @('None', 'History', 'Plugin', 'HistoryAndPlugin')) { throw 'Invalid PredictionSource.' }
            if ($global:PSProfileState.PSReadLineReady) {
                Set-PSReadLineOption -PredictionSource $Value -ErrorAction Stop
            }
            break
        }
        'PredictionViewStyle' {
            if ($Value -notin @('InlineView', 'ListView')) { throw 'Invalid PredictionViewStyle.' }
            if ($global:PSProfileState.PSReadLineReady) {
                Set-PSReadLineOption -PredictionViewStyle $Value -ErrorAction Stop
            }
            break
        }
    }

    $global:PSProfileConfig[$Key] = $Value

    if ($Key -eq 'HistoryFilterEnabled') {
        Set-PSProfileHistoryFilter
    } elseif ($Key -eq 'MaxHistoryIndexCount') {
        $null = Update-PSCommandCache
    } elseif ($Key -eq 'DeveloperToolsEnabled') {
        Write-Warning 'Developer-tool integration loading is applied on the next profile reload. Existing imported modules are not forcibly unloaded.'
    }

    Write-Host ("Configuration '{0}' updated." -f $Key) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Profile utilities and aliases
# ---------------------------------------------------------------------------

function Edit-PSProfile {
    [CmdletBinding()]
    param()
    if (Test-PSProfileCommandAvailable 'notepad.exe') { notepad.exe $PROFILE }
    else { Write-Output $PROFILE }
}

function Open-PSProfileFolder {
    [CmdletBinding()]
    param()
    $directory = Split-Path -Path $PROFILE -Parent
    if (Test-PSProfileCommandAvailable 'explorer.exe') { explorer.exe $directory }
    else { Write-Output $directory }
}

function Reload-PSProfile {
    [CmdletBinding()]
    param()
    try {
        . $PROFILE
        if ($?) { Write-Host 'Profile reload completed. Check the dashboard for component status.' -ForegroundColor Green }
        else { Write-Warning 'Profile reload returned a failure status.' }
    } catch {
        Write-Error ("Profile reload failed: {0}" -f $_.Exception.Message)
    }
}

function mkcd {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    Set-Location -LiteralPath $Path
}

function up {
    [CmdletBinding()]
    param([ValidateRange(0, 100)][int]$Levels = 1)
    $target = (Get-Location).Path
    for ($index = 0; $index -lt $Levels; $index++) {
        $parent = Split-Path -Path $target -Parent
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $target) { break }
        $target = $parent
    }
    Set-Location -LiteralPath $target
}

function croot { Set-Location -LiteralPath $HOME }
function ll { Get-ChildItem -Force | Format-Table Mode, LastWriteTime, Length, Name -AutoSize }

function Copy-CurrentPath {
    [CmdletBinding()]
    param()
    if (Test-PSProfileCommandAvailable 'Set-Clipboard') {
        (Get-Location).Path | Set-Clipboard
        Write-Host 'Current path copied.' -ForegroundColor Green
    } else {
        Write-Output (Get-Location).Path
    }
}

function Open-CurrentDirectory {
    [CmdletBinding()]
    param()
    if (Test-PSProfileCommandAvailable 'explorer.exe') { explorer.exe (Get-Location).Path }
    else { Write-Output (Get-Location).Path }
}

function git-status   { git status --short --branch @args }
function git-diff     { git diff @args }
function git-log      { git log --oneline --decorate -15 @args }
function git-branches { git branch -vv @args }
function git-pull     { git pull @args }
function git-push     { git push @args }
function git-commit   { git commit @args }

Set-Alias -Name cpath -Value Copy-CurrentPath -Scope Global -Force
Set-Alias -Name owd -Value Open-CurrentDirectory -Scope Global -Force

# ---------------------------------------------------------------------------
# Optional integrations
# ---------------------------------------------------------------------------

$optionalModules = @('Terminal-Icons', 'posh-git', 'PSFzf')
if ($global:PSProfileConfig.DeveloperToolsEnabled) {
foreach ($moduleName in $optionalModules) {
    if (Get-Module -ListAvailable -Name $moduleName) {
        try {
            $moduleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Import-Module $moduleName -ErrorAction Stop
            $moduleStopwatch.Stop()
            $global:PSProfileState.OptionalModulesLoaded += $moduleName
            $global:PSProfileState.ModuleLoadTimes[$moduleName] = $moduleStopwatch.ElapsedMilliseconds
        } catch {
            Write-Verbose ("Optional module '{0}' failed to load: {1}" -f $moduleName, $_.Exception.Message)
        }
    }
}

# PSFzf provider binding only: leave Ctrl+R under the profile's explicit
# ReverseSearchHistory binding to avoid competing handlers.
if (Test-PSProfileCommandAvailable 'Set-PsFzfOption') {
    try { Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' } catch { }
}

if (Test-PSProfileCommandAvailable 'zoxide') {
    try {
        $zoxideInit = zoxide init powershell | Out-String
        if (-not [string]::IsNullOrWhiteSpace($zoxideInit)) {
            Invoke-Expression $zoxideInit
            $global:PSProfileState.OptionalModulesLoaded += 'zoxide'
        }
    } catch {
        Write-Verbose ("zoxide initialisation failed: {0}" -f $_.Exception.Message)
    }
}

if ($PSVersionTable.PSEdition -eq 'Core' -and (Test-PSProfileCommandAvailable 'oh-my-posh')) {
    try {
        oh-my-posh init pwsh | Invoke-Expression
        $global:PSProfileState.OptionalModulesLoaded += 'Oh My Posh'
    } catch {
        Write-Verbose ("Oh My Posh initialisation failed: {0}" -f $_.Exception.Message)
    }
}
}

# ---------------------------------------------------------------------------
# Final initialisation
# ---------------------------------------------------------------------------

try {
    $null = Update-PSCommandCache
} catch {
    Write-Warning ("PDE command cache initialisation failed: {0}" -f $_.Exception.Message)
}

Set-PSProfileSecurityMode -Mode $global:PSProfileConfig.SecurityMode

$global:PSProfileStartupStopwatch.Stop()
$global:PSProfileState.StartupDurationMs = $global:PSProfileStartupStopwatch.ElapsedMilliseconds

# End of PDE V2 profile.
