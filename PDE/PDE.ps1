#requires -Version 5.1
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
[CmdletBinding()]
param([switch]$NoStart)
foreach ($PDE_LoadVariable in @('PDE_State','PDE_Config')) {
    if (-not (Get-Variable -Name $PDE_LoadVariable -Scope Global -ErrorAction SilentlyContinue)) {
        Set-Variable -Name $PDE_LoadVariable -Scope Global -Value $null
    }
}
Remove-Variable PDE_LoadVariable
foreach ($PDE_Dependency in @('Microsoft.PowerShell.Pager.dll', 'PDE.Editor.Core.dll', 'PDE.Editor.Desktop.dll', 'System.Runtime.InteropServices.RuntimeInformation.dll')) {
    if (-not [IO.File]::Exists((Join-Path $PSScriptRoot $PDE_Dependency))) {
        throw "Incomplete PDE release: $PDE_Dependency"
    }
}
Remove-Variable PDE_Dependency
if ($global:PDE_State -and $global:PDE_State.Version -ne '4.3.0-rc1') {
    throw 'Another PDE version is loaded. Close this terminal and open a fresh window before loading this release.'
}

#region Core
# Modified for PDE 4.3.0-rc1. See README.md.

function global:New-PDEStringSet {
    [CmdletBinding()]
    param([switch]$CaseSensitive)
    $comparer = if ($CaseSensitive) { [StringComparer]::Ordinal } else { [StringComparer]::OrdinalIgnoreCase }
    # PowerShell enumerates collection outputs unless wrapped as one object.
    return ,([System.Collections.Generic.HashSet[string]]::new($comparer))
}

function global:Write-PDELog {
    [CmdletBinding()]
    param([ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO', [Parameter(Mandatory)][string]$Message)
    if (-not $global:PDE_Config -or -not $global:PDE_Config.EnableDiagnosticsLog) { return }
    try {
        $path = [string]$global:PDE_Config.DiagnosticsLogPath
        if ([string]::IsNullOrWhiteSpace($path)) { return }
        $line = '{0:yyyy-MM-dd HH:mm:ss.fff} [{1}] {2}' -f (Get-Date), $Level, $Message.Replace("`r", ' ').Replace("`n", ' ')
        [System.IO.File]::AppendAllText($path, ($line + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    }
    catch { } # Diagnostics never break editing.
}

function global:Test-PDESensitiveHistoryLine {
    [CmdletBinding()]
    param([AllowNull()][string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    if (-not $global:PDE_State -or -not $global:PDE_State.SensitivePatterns) { return $true }
    foreach ($pattern in $global:PDE_State.SensitivePatterns) {
        try { if ($pattern.IsMatch($Line)) { return $true } }
        catch { return $true }
    }
    return $false
}



function global:Start-PDE {
    [CmdletBinding()]
    param([switch]$Force, [switch]$NonInteractive)
    if ($global:PDE_State -and $global:PDE_State.Running -and -not $Force) { return }
    if ($global:PDE_State -and $global:PDE_State.Running) { Stop-PDE }
    $defaults = @{
        EnablePredictions=$true; EnablePromptLearning=$true; EnableLiveHighlight=$true
        FuzzyMaximumDistance=2; EnableFuzzySuggestions=$true; HistoryIndexLimit=1500
        CommandRefreshSeconds=600; EnableDiagnosticsLog=$false
        HighlightMode='Character'; CharacterHighlightMaxDistance=2
        DiagnosticsLogPath=(Join-Path $HOME 'PDE-diagnostics.log')
    }
    if (-not $global:PDE_Config) { $global:PDE_Config=@{} }
    foreach ($key in $defaults.Keys) {
        if (-not $global:PDE_Config.ContainsKey($key)) { $global:PDE_Config[$key]=$defaults[$key] }
    }
    $interactive=$false
    try { $interactive=($Host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) } catch { }
    if ($NonInteractive) { $interactive=$false }
    $patterns=[Collections.Generic.List[Text.RegularExpressions.Regex]]::new()
    foreach ($rule in @('(?i)password|passwd|token|secret|credential|authorization|api[_-]?key|bearer',
        '(?i)ConvertTo-SecureString|://[^\s/]+:[^\s/]+@|-----BEGIN .*PRIVATE KEY')) {
        $patterns.Add([regex]::new($rule,[Text.RegularExpressions.RegexOptions]::CultureInvariant,[TimeSpan]::FromMilliseconds(50)))
    }
    $global:PDE_State=@{
        Version='4.3.0-rc1'; Running=$true; SourcePath=$global:PDE_SourcePath; Interactive=$interactive
        CommandNames=(New-PDEStringSet); CommandPrefixes=(New-PDEStringSet); CommandInfo=@{}; SortedCommandNames=@()
        HistoryCommandNames=(New-PDEStringSet); History=[Collections.Generic.List[string]]::new()
        SensitivePatterns=$patterns; LastIndexUpdate=$null; LastIndexAttempt=$null; DiscoveryHealthy=$false
        LastError=$null; LastHistoryUpdate=$null; IndexPath=$env:PATH; IndexModulePath=$env:PSModulePath
        PredictionAvailable=$false; PredictionReason='Not configured'; OriginalPrediction=$null; AppliedPrediction=$null
        LiveHighlightingEnabled=$false; NativeColouringEnabled=$false; PromptLearningEnabled=$false
        OriginalPrompt=$null; PromptWrapper=$null; LastPromptHistoryId=0
        ColouringStatus='Native PSReadLine rendering; per-command live colouring unavailable.'
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $null=Update-PDEIndex -Force
    if ($interactive) {
        $null=Invoke-PDEApplyOptions
        if ($global:PDE_Config.EnableLiveHighlight) { $null=Enable-PDELiveHighlight }
        if ($global:PDE_Config.EnablePromptLearning) { $null=Enable-PDEPromptLearning }
    }
    $timer.Stop(); $global:PDE_State.StartupMilliseconds=$timer.Elapsed.TotalMilliseconds
}

function global:Stop-PDE {
    [CmdletBinding()]
    param()
    if (-not $global:PDE_State) { return }
    Disable-PDEPromptLearning
    Disable-PDELiveHighlight
    Restore-PDEReadLineOptions
    $global:PDE_State.Running=$false
}
#endregion

#region Commands
# Modified for PDE 4.3.0-rc1. See README.md.

function global:Update-PDEIndex {
    [CmdletBinding()]
    param([switch]$Force)
    $s = $global:PDE_State
    if (-not $Force -and $s.LastIndexAttempt -and $s.IndexPath -eq $env:PATH -and $s.IndexModulePath -eq $env:PSModulePath -and
        ((Get-Date) - $s.LastIndexAttempt).TotalSeconds -lt $global:PDE_Config.CommandRefreshSeconds) {
        return [pscustomobject]@{ Updated = $false; Commands = $s.CommandNames.Count; LastUpdated = $s.LastIndexUpdate }
    }
    $s.LastIndexAttempt = Get-Date
    $s.LastIndexAttempt = Get-Date
    try {
        $names = New-PDEStringSet
        $prefixes = New-PDEStringSet
        $info = @{}
        foreach ($cmd in @(Get-Command -Name '*' -All -ErrorAction Stop)) {
            $name = [string]$cmd.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            [void]$names.Add($name)
            if (-not $info.ContainsKey($name)) { $info[$name] = $cmd }
            if ($name -match '(?i)\.(exe|com|cmd|bat|ps1)$') {
                $shortName = [IO.Path]::GetFileNameWithoutExtension($name)
                if (-not [string]::IsNullOrWhiteSpace($shortName)) {
                    [void]$names.Add($shortName)
                    if (-not $info.ContainsKey($shortName)) { $info[$shortName] = $cmd }
                }
            }
        }
        foreach ($name in $names) {
            for ($i = 1; $i -le $name.Length; $i++) { [void]$prefixes.Add($name.Substring(0, $i)) }
        }
        # Commit only a completely built index.
        $s.CommandNames = $names
        $s.SortedCommandNames = @($names | Sort-Object)
        $s.CommandPrefixes = $prefixes
        $s.CommandInfo = $info
        $s.LastIndexUpdate = Get-Date
        $s.LastError = $null
        $s.DiscoveryHealthy = $true
        $s.IndexPath=$env:PATH; $s.IndexModulePath=$env:PSModulePath
        $s.DiscoveryHealthy = $true
        $s.IndexPath=$env:PATH; $s.IndexModulePath=$env:PSModulePath
        Write-PDELog -Message "Indexed $($names.Count) commands."
        return [pscustomobject]@{ Updated = $true; Commands = $names.Count; LastUpdated = $s.LastIndexUpdate }
    }
    catch {
        $s.LastError = $_.Exception.Message
        $s.DiscoveryHealthy = $false
        $s.DiscoveryHealthy = $false
        Write-PDELog -Level ERROR -Message "Command refresh failed: $($s.LastError)"
        # Keep the last good snapshot; diagnostics expose the failure.
        return [pscustomobject]@{ Updated = $false; Commands = $s.CommandNames.Count; Error = $s.LastError }
    }
}



function global:Test-PDECommandName {
    [CmdletBinding()]
    param([Parameter(Mandatory,ValueFromPipeline)][AllowEmptyString()][string]$Name)
    process {
        $null=Update-PDEIndex
        $code=Get-PDECommandClass -Name $Name
        $info=$global:PDE_State.CommandInfo[$Name]
        [pscustomobject]@{Name=$Name; Classification=@('Normal','RecognisedOrIncomplete','Unknown','Successful')[$code]
            IsRecognised=$global:PDE_State.CommandNames.Contains($Name)
            IsPrefix=$global:PDE_State.CommandPrefixes.Contains($Name)
            DiscoveryHealthy=$global:PDE_State.DiscoveryHealthy
            CommandType=if($info){[string]$info.CommandType}else{$null}}
    }
}

# Only explicit analysis calls resolve paths. Colour maps never touch disk.
function global:Resolve-PDECommand {
    param([Parameter(Mandatory)][string]$Name)
    try {
        $escaped=[Management.Automation.WildcardPattern]::Escape($Name)
        $cmd=Get-Command -Name $escaped -ErrorAction Stop | Select-Object -First 1
        if ($cmd) { return $cmd }
    } catch { }
    return $null
}

function global:Get-PDEParsedCommandNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line, [switch]$RequireRecognised)
    $empty = [pscustomobject]@{ IsValid = $false; Names = @(); Reason = 'Not a single-line, parseable command.' }
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line -match '[\r\n]') { return $empty }
    try {
        $tokens = $null; $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($Line, [ref]$tokens, [ref]$errors)
        if ($errors.Count -gt 0) { return $empty }
        $commands = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] }, $true))
        if ($commands.Count -eq 0) { return $empty }
        $names = [System.Collections.Generic.List[string]]::new()
        $seen = New-PDEStringSet
        foreach ($cmdAst in $commands) {
            $name = $cmdAst.GetCommandName()
            # Dynamic command invocation is not proof that a command exists.
            if ([string]::IsNullOrWhiteSpace($name)) { return $empty }
            if ($RequireRecognised -and -not $global:PDE_State.CommandNames.Contains($name)) {
                $exists = $false
                try { $exists = Test-Path -LiteralPath $name -PathType Leaf -ErrorAction SilentlyContinue } catch { }
                if (-not $exists) { return $empty }
            }
            if ($seen.Add($name)) { [void]$names.Add($name) }
        }
        return [pscustomobject]@{ IsValid = $true; Names = $names.ToArray(); Reason = $null }
    }
    catch { return $empty }
}

function global:Update-PDEDynamicCommands {
    $s=$global:PDE_State
    try {
        $dynamic=@(Get-Command -CommandType Function,Filter,Alias -ErrorAction Stop)
        $names=New-PDEStringSet
        foreach ($cmd in $dynamic) { $null=$names.Add($cmd.Name) }
        $changed=$false
        foreach ($name in @($s.CommandInfo.Keys)) {
            if ($s.CommandInfo[$name].CommandType -in @('Function','Filter','Alias') -and -not $names.Contains($name)) {
                $s.CommandInfo.Remove($name); $null=$s.CommandNames.Remove($name); $changed=$true
            }
        }
        foreach ($cmd in $dynamic) {
            if ($s.CommandNames.Add($cmd.Name)) { $changed=$true }
            $s.CommandInfo[$cmd.Name]=$cmd
        }
        if ($changed) {
            $prefixes=New-PDEStringSet
            foreach ($name in $s.CommandNames) {
                for ($i=1;$i -le $name.Length;$i++) { $null=$prefixes.Add($name.Substring(0,$i)) }
            }
            $s.CommandPrefixes=$prefixes
            $s.SortedCommandNames=@($s.CommandNames | Sort-Object)
        }
    } catch { $s.DiscoveryHealthy=$false; $s.LastError='Dynamic command refresh failed.' }
}
#endregion

#region History
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
# Never infer success from PSReadLine's history file. Only names are retained,
# in this session, after a conservative, observed single-command outcome.
function global:Get-PDELearnableCommand {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.Length -gt 32768 -or (Test-PDESensitiveHistoryLine $Line)) { return $null }
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Line,[ref]$tokens,[ref]$errors)
    if ($errors.Count -or $ast.BeginBlock -or $ast.ProcessBlock -or -not $ast.EndBlock) { return $null }
    $statements=@($ast.EndBlock.Statements)
    if ($statements.Count -ne 1 -or $statements[0] -isnot [Management.Automation.Language.PipelineAst]) { return $null }
    $elements=@($statements[0].PipelineElements)
    if ($elements.Count -ne 1 -or $elements[0] -isnot [Management.Automation.Language.CommandAst]) { return $null }
    $cmd=$elements[0]
    if ($cmd.Redirections.Count -or $cmd.InvocationOperator -eq 'Dot') { return $null }
    # A nested command, script block, substitution or variable argument makes
    # attribution ambiguous. Prefer false negatives over false success.
    foreach ($arg in $cmd.CommandElements) {
        if ($arg -is [Management.Automation.Language.CommandParameterAst]) {
            if ($arg.Argument -and $arg.Argument -isnot [Management.Automation.Language.ConstantExpressionAst]) { return $null }
        } elseif ($arg -isnot [Management.Automation.Language.ConstantExpressionAst]) { return $null }
    }
    $name=$cmd.GetCommandName()
    if (-not $name -or $name -notmatch '^[A-Za-z][A-Za-z0-9_.-]{0,127}$') { return $null }
    return $name
}

function global:Add-PDEHistoryEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Line,
        [Parameter(Mandatory)][bool]$Succeeded, [int]$NativeExitCode=0)
    if (-not $Succeeded -or -not $global:PDE_Config.EnablePromptLearning) { return $false }
    try {
        if (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue) {
            $options=Get-PSReadLineOption
            if ([string]$options.HistorySaveStyle -eq 'SaveNothing') { return $false }
            # Honour custom history acceptance policies, including MemoryOnly.
            if ($options.AddToHistoryHandler) {
                $allowed=$options.AddToHistoryHandler.Invoke($Line)
                if ($allowed -eq $false -or [string]$allowed -eq 'SkipAdding') { return $false }
            }
        }
    } catch { return $false }
    $name=Get-PDELearnableCommand $Line
    if (-not $name) { return $false }
    $cmd=Resolve-PDECommand $name
    if (-not $cmd) { return $false }
    $actual=$cmd
    if ($cmd.CommandType -eq 'Alias') { $actual=$cmd.ResolvedCommand }
    if (-not $actual) { return $false }
    if ($actual.CommandType -in @('Application','ExternalScript') -and $NativeExitCode -ne 0) { return $false }
    # Bound memory; no arguments, paths or raw command text enter PDE history.
    if (-not $global:PDE_State.HistoryCommandNames.Contains($name)) {
        if ($global:PDE_State.History.Count -ge $global:PDE_Config.HistoryIndexLimit) {
            $old=$global:PDE_State.History[0]
            $global:PDE_State.History.RemoveAt(0)
            $null=$global:PDE_State.HistoryCommandNames.Remove($old)
        }
        $global:PDE_State.History.Add($name)
        $null=$global:PDE_State.HistoryCommandNames.Add($name)
    }
    return $true
}

function global:Update-PDEHistory {
    [CmdletBinding()]
    param([switch]$Force)
    $global:PDE_State.LastHistoryUpdate=Get-Date
    [pscustomobject]@{Updated=$false; Entries=$global:PDE_State.History.Count
        Reason='Observed outcomes only; historical text is not execution evidence. Session-only command names.'}
}

function global:Clear-PDEHistory {
    $global:PDE_State.History.Clear()
    $global:PDE_State.HistoryCommandNames.Clear()
}
#endregion

#region Suggestions
# Modified for PDE 4.3.0-rc1. See README.md.

function global:Get-PDELevenshteinDistance {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Left,
          [Parameter(Mandatory)][AllowEmptyString()][string]$Right)
    $a = $Left.ToUpperInvariant(); $b = $Right.ToUpperInvariant()
    $n = $a.Length; $m = $b.Length
    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }
    $prev = New-Object 'int[]' ($m + 1)
    $curr = New-Object 'int[]' ($m + 1)
    for ($j = 0; $j -le $m; $j++) { $prev[$j] = $j }
    for ($i = 1; $i -le $n; $i++) {
        $curr[0] = $i
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($a[$i-1] -ceq $b[$j-1]) { 0 } else { 1 }
            $curr[$j] = [Math]::Min([Math]::Min(($prev[$j] + 1), ($curr[$j-1] + 1)), ($prev[$j-1] + $cost))
        }
        $tmp = $prev; $prev = $curr; $curr = $tmp
    }
    return $prev[$m]
}

function global:Get-PDESuggestions {
    [CmdletBinding()]
    param([string]$Prefix = '', [ValidateSet('All','History','Command')][string]$Source = 'All',
          [ValidateRange(1,100)][int]$Limit = 10, [switch]$Fuzzy)
    if ($Source -ne 'History') { [void](Update-PDEIndex) }
    if ($Source -ne 'Command') { [void](Update-PDEHistory) }
    if ($global:PDE_State.CommandNames.Contains($Prefix)) { return }
    $list = [System.Collections.Generic.List[object]]::new()
    $seen = New-PDEStringSet
    if ($Source -ne 'Command') {
        $rank = 0
        foreach ($line in $global:PDE_State.History) {
            if ($line.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) -and $seen.Add($line)) {
                [void]$list.Add([pscustomobject]@{ Suggestion = $line; Source = 'History'; MatchType = 'Prefix'; Distance = 0; Rank = $rank })
            }
            $rank++
        }
    }
    if ($Source -ne 'History') {
        foreach ($name in $global:PDE_State.SortedCommandNames) {
            if ($name.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) -and $seen.Add($name)) {
                [void]$list.Add([pscustomobject]@{ Suggestion = $name; Source = 'Command'; MatchType = 'Prefix'; Distance = 0; Rank = 1000000 })
            }
        }
        if (($Fuzzy -or $global:PDE_Config.EnableFuzzySuggestions) -and $Prefix.Length -ge 3 -and $Prefix.Length -le 64) {
            foreach ($name in $global:PDE_State.SortedCommandNames) {
                if ($seen.Contains($name) -or $name.Length -gt 64 -or ([Math]::Abs($name.Length - $Prefix.Length) -gt $global:PDE_Config.FuzzyMaximumDistance)) { continue }
                $distance = Get-PDELevenshteinDistance -Left $Prefix -Right $name
                if ($distance -le $global:PDE_Config.FuzzyMaximumDistance -and $seen.Add($name)) {
                    [void]$list.Add([pscustomobject]@{ Suggestion = $name; Source = 'Command'; MatchType = 'Fuzzy'; Distance = $distance; Rank = 1000000 })
                }
            }
        }
    }
    $list | Sort-Object -Property Distance, Rank, Suggestion | Select-Object -First $Limit
}
#endregion

#region Analysis
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
function global:Get-PDECommandAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory,ValueFromPipeline)][AllowEmptyString()][string]$Text)
    process {
        $null=Update-PDEIndex
        Update-PDEDynamicCommands
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
        $records=[Collections.Generic.List[object]]::new()
        $localNames=New-PDEStringSet
        foreach ($def in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) { $null=$localNames.Add($def.Name) }
        foreach ($cmd in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)) {
            $name=$cmd.GetCommandName()
            $dynamic=[string]::IsNullOrEmpty($name)
            $code=if($dynamic){0}else{Get-PDECommandClass $name}
            $resolved=$null
            if (-not $dynamic -and -not $global:PDE_State.CommandNames.Contains($name)) { $resolved=Resolve-PDECommand $name }
            if ($resolved -or $localNames.Contains($name)) { $code=1 }
            $extent=$cmd.CommandElements[0].Extent
            $records.Add([pscustomobject]@{Name=$name; IsDynamic=$dynamic; ColorCode=$code
                Classification=@('Dynamic','RecognisedOrIncomplete','Unknown','Successful')[$code]
                IsRecognised=($resolved -or $localNames.Contains($name) -or $global:PDE_State.CommandNames.Contains($name))
                StartOffset=$extent.StartOffset; EndOffset=$extent.EndOffset})
        }
        $diagnostics=@($errors | ForEach-Object {
            [pscustomobject]@{Message=$_.Message; ErrorId=$_.ErrorId; IncompleteInput=$_.IncompleteInput
                StartOffset=$_.Extent.StartOffset; EndOffset=$_.Extent.EndOffset}
        })
        [pscustomobject]@{
            IsSyntacticallyValid=($errors.Count -eq 0)
            IsIncomplete=($errors.Count -gt 0 -and @($errors | Where-Object {-not $_.IncompleteInput}).Count -eq 0)
            ParseErrors=@($errors | ForEach-Object {$_.Message}); Diagnostics=$diagnostics
            Commands=$records.ToArray(); UnknownCommands=@($records | Where-Object {$_.ColorCode -eq 2} | ForEach-Object {$_.Name})
        }
    }
}
function global:Test-PDESyntax {
    [CmdletBinding()]
    param([Parameter(Mandatory,ValueFromPipeline)][AllowEmptyString()][string]$Text)
    process {
        $result=Get-PDECommandAnalysis $Text
        [pscustomobject]@{IsValid=$result.IsSyntacticallyValid; IsIncomplete=$result.IsIncomplete
            Errors=$result.Diagnostics; CommandCount=$result.Commands.Count; UnknownCommands=$result.UnknownCommands}
    }
}
#endregion

#region Coloring
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
# Map: 0 gray, 1 orange, 2 red, 3 green. No discovery or terminal I/O here.
function global:Get-PDECommandClass {
    param([AllowEmptyString()][string]$Name)
    $s=$global:PDE_State
    if (-not $Name) { return 0 }
    if ($s.CommandNames.Contains($Name)) {
        if ($s.HistoryCommandNames.Contains($Name)) { return 3 }
        return 1
    }
    if ($s.CommandPrefixes.Contains($Name)) { return 1 }
    # Paths/module-qualified names and unknown discovery state are uncertain,
    # never red on cache evidence alone. Explicit analysis can resolve them.
    if (-not $s.DiscoveryHealthy -or $Name -match '[\\/:]' -or $Name.StartsWith('.')) { return 1 }
    return 2
}

# Bounded, case-insensitive Levenshtein distance.  A limit avoids scanning
# every possible edit when the user input cannot be a useful near-match.
function global:Get-PDEBoundedCommandDistance {
    param([string]$Left, [string]$Right, [int]$MaximumDistance = 2)

    $n = $Left.Length; $m = $Right.Length
    if ([Math]::Abs($n - $m) -gt $MaximumDistance) { return ($MaximumDistance + 1) }

    $previous = New-Object 'int[]' ($m + 1)
    for ($j = 0; $j -le $m; $j++) { $previous[$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $current = New-Object 'int[]' ($m + 1)
        $current[0] = $i
        $rowMinimum = $i
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ([string]::Equals([string]$Left[$i - 1], [string]$Right[$j - 1],
                    [StringComparison]::OrdinalIgnoreCase)) { 0 } else { 1 }
            $current[$j] = [Math]::Min(
                [Math]::Min(($previous[$j] + 1), ($current[$j - 1] + 1)),
                ($previous[$j - 1] + $cost))
            if ($current[$j] -lt $rowMinimum) { $rowMinimum = $current[$j] }
        }
        if ($rowMinimum -gt $MaximumDistance) { return ($MaximumDistance + 1) }
        $previous = $current
    }
    return $previous[$m]
}

function global:Get-PDECommandNameColorMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name, [switch]$LocalName)
    $state = $global:PDE_State
    $code = Get-PDECommandClass $Name
    if ($global:PDE_Config.HighlightMode -ne 'Character') {
        return ,([int[]](@($code) * $Name.Length))
    }
    if (-not ('PDE.PowerShell.PDECharacterColoring' -as [type])) {
        Add-Type -Path (Join-Path $PSScriptRoot 'PDE.CharacterColoring.cs') -ErrorAction Stop
    }
    $prefix = $LocalName -or $state.CommandPrefixes.Contains($Name)
    return ,([PDE.PowerShell.PDECharacterColoring]::Map($Name, $state.CommandNames,
        $state.HistoryCommandNames, $prefix, ($code -eq 1), $global:PDE_Config.CharacterHighlightMaxDistance))
}

function global:Get-PDELineColorMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $map=New-Object 'int[]' $Text.Length
    if (-not $Text) { return ,$map }
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$tokens,[ref]$errors)
    # Definitions are recognised within the input without executing it.
    $localNames=New-PDEStringSet
    foreach ($def in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) {
        $null=$localNames.Add($def.Name)
    }
    $characterMode = ($global:PDE_Config -and $global:PDE_Config.HighlightMode -eq 'Character')
    foreach ($cmd in $ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true)) {
        $name=$cmd.GetCommandName()
        if (-not $name -or -not $cmd.CommandElements.Count) { continue }
        $extent=$cmd.CommandElements[0].Extent
        $code=Get-PDECommandClass $name
        $isLocal = $localNames.Contains($name)
        if ($isLocal -and $code -ne 3) { $code=1 }
        # The AST extent can include quotes/invocation syntax. Only overlay a
        # per-character map when the raw extent is precisely the command name.
        $raw = $extent.Text
        $start = $extent.StartOffset
        if ($raw.Length -eq $name.Length + 2 -and $raw[0] -in @("'", '"') -and
            $raw[-1] -eq $raw[0] -and $raw.Substring(1,$name.Length) -ceq $name) {
            $raw = $name
            $start++
        }
        if ($characterMode -and $raw -ceq $name) {
            $nameMap = Get-PDECommandNameColorMap -Name $name -LocalName:$isLocal
            for ($j=0; $j -lt $nameMap.Length; $j++) {
                $offset = $start + $j
                if ($offset -ge 0 -and $offset -lt $map.Length) { $map[$offset] = $nameMap[$j] }
            }
        }
        else {
            for ($i=$extent.StartOffset;$i -lt $extent.EndOffset -and $i -lt $map.Length;$i++) {
                if ($i -ge 0) { $map[$i]=$code }
            }
        }
    }
    return ,$map
}

function global:Show-PDEHighlight {
    <# Non-executing standalone preview. Never call from a PSReadLine handler. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $null=Update-PDEIndex
    $map=Get-PDELineColorMap $Text
    $ansi=$false
    try { $ansi=$Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected } catch { }
    $palette=@('Gray','DarkYellow','Red','Green')
    $esc=[string][char]27
    $vt=@("${esc}[37m","${esc}[38;2;255;165;0m","${esc}[91m","${esc}[92m")
    $i=0
    while ($i -lt $Text.Length) {
        $j=$i+1
        while ($j -lt $Text.Length -and $map[$j] -eq $map[$i]) { $j++ }
        # Strip terminal control sequences from user-supplied preview data.
        $part=$Text.Substring($i,$j-$i) -replace '[\x00-\x08\x0B-\x1F\x7F-\x9F]','?'
        if ($ansi) { Write-Host ($vt[$map[$i]]+$part+"${esc}[0m") -NoNewline }
        else { Write-Host $part -ForegroundColor $palette[$map[$i]] -NoNewline }
        $i=$j
    }
    Write-Host
}
#endregion

#region Prompt
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
function global:Invoke-PDEPrompt {
    # First statement captures status before any helper command changes it.
    $previousSucceeded=$?
    $previousExitCode=Get-Variable LASTEXITCODE -ValueOnly -ErrorAction SilentlyContinue
    $outcome=@($previousSucceeded, $previousExitCode)
    $s=$global:PDE_State
    $global:PDE_LastCommandSucceeded=[bool]$outcome[0]
    $global:PDE_LastNativeExitCode=$outcome[1]
    # Render the user's prompt once, before maintenance. Preserve its text/output.
    $rendered=if ($s.OriginalPrompt) { & $s.OriginalPrompt } else { "PS $($executionContext.SessionState.Path.CurrentLocation)> " }
    try {
        $last=Get-History -Count 1 -ErrorAction Stop
        if ($last -and $last.Id -ne $s.LastPromptHistoryId) {
            $s.LastPromptHistoryId=$last.Id
            if ([string]$last.ExecutionStatus -eq 'Completed') {
                $null=Add-PDEHistoryEntry -Line $last.CommandLine -Succeeded ([bool]$outcome[0]) -NativeExitCode ([int]$outcome[1])
            }
            # Dynamic functions and aliases are refreshed at command boundaries,
            # not keystrokes. Full executable/module discovery remains throttled.
            $null=Update-PDEIndex
            Update-PDEDynamicCommands
        }
    } catch { Write-PDELog -Level WARN -Message 'Prompt maintenance failed; native editing remains available.' }
    return $rendered
}

function global:Enable-PDEPromptLearning {
    [CmdletBinding()]
    param()
    $s=$global:PDE_State
    if ($s.PromptLearningEnabled) { return $true }
    if (-not $s.Interactive) { return $false }
    $existing=Get-Item Function:prompt -ErrorAction SilentlyContinue
    $s.OriginalPrompt=if($existing){$existing.ScriptBlock}else{$null}
    $last=Get-History -Count 1 -ErrorAction SilentlyContinue
    $s.LastPromptHistoryId=if($last){$last.Id}else{0}
    $s.PromptWrapper=(Get-Command Invoke-PDEPrompt).ScriptBlock
    Set-Item Function:global:prompt -Value $s.PromptWrapper -Force
    $s.PromptLearningEnabled=$true
    return $true
}

function global:Disable-PDEPromptLearning {
    $s=$global:PDE_State
    if (-not $s -or -not $s.PromptLearningEnabled) { return }
    $current=Get-Item Function:prompt -ErrorAction SilentlyContinue
    # Never overwrite a prompt installed by someone else after PDE.
    if ($current -and [object]::ReferenceEquals($current.ScriptBlock,$s.PromptWrapper)) {
        if ($s.OriginalPrompt) { Set-Item Function:global:prompt -Value $s.OriginalPrompt -Force }
        else { Remove-Item Function:prompt -ErrorAction SilentlyContinue }
    }
    $s.PromptLearningEnabled=$false
}
#endregion

#region PSReadLine
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
function global:Invoke-PDEApplyOptions {
    [CmdletBinding()]
    param()
    $s=$global:PDE_State
    if (-not $s.Interactive) { return [pscustomobject]@{Configured=$false; Reason='Noninteractive host'} }
    try {
        if (-not (Get-Module PSReadLine)) { Import-Module PSReadLine -ErrorAction Stop }
        $set=Get-Command Set-PSReadLineOption -ErrorAction Stop
        $options=Get-PSReadLineOption -ErrorAction Stop
        $s.NativeColouringEnabled=$true
        # Preserve the user's syntax palette, prompt geometry and EVERY key.
        if ($set.Parameters.ContainsKey('PredictionSource')) {
            if ($null -eq $s.OriginalPrediction) { $s.OriginalPrediction=[string]$options.PredictionSource }
            $requested=if($global:PDE_Config.EnablePredictions){
                if([string]$options.PredictionSource -eq 'None'){'History'}else{[string]$options.PredictionSource}
            }else{'None'}
            Set-PSReadLineOption -PredictionSource $requested -ErrorAction Stop
            $s.AppliedPrediction=$requested
            $s.PredictionAvailable=($requested -ne 'None')
            $s.PredictionReason="PSReadLine $requested predictions (native history, not success evidence)."
        } else { $s.PredictionReason='Installed PSReadLine does not support prediction.' }
    } catch { $s.PredictionReason='PSReadLine configuration unavailable: '+$_.Exception.Message }
    [pscustomobject]@{Configured=$s.NativeColouringEnabled; Predictions=$s.PredictionAvailable; Reason=$s.PredictionReason}
}
function global:Restore-PDEReadLineOptions {
    $s=$global:PDE_State
    if ($null -ne $s.OriginalPrediction) {
        try {
            if ([string](Get-PSReadLineOption).PredictionSource -eq $s.AppliedPrediction) {
                Set-PSReadLineOption -PredictionSource $s.OriginalPrediction -ErrorAction Stop
            }
            $s.OriginalPrediction=$null; $s.AppliedPrediction=$null; $s.PredictionAvailable=$false
        } catch { $s.LastError='Could not restore prediction setting: '+$_.Exception.Message }
    }
}
#endregion

#region LiveEditor
# PDE 4.3 live editor integration. The bundled editor owns the complete redraw.
# Optional editor-DLL API: PDECommandColors.CharacterMode (static bool).
# Older DLLs remain usable: the editor stays in its original token mode.
function global:Sync-PDELiveEditorHighlightMode {
    $requested = [bool]($global:PDE_Config -and $global:PDE_Config.HighlightMode -eq 'Character')
    [PDE.PowerShell.PDECommandColors]::MaximumDistance = $global:PDE_Config.CharacterHighlightMaxDistance
    $property = [PDE.PowerShell.PDECommandColors].GetProperty(
        'CharacterMode', [Reflection.BindingFlags]'Public,Static')
    if ($property -and $property.CanWrite -and $property.PropertyType -eq [bool]) {
        $property.SetValue($null, $requested, $null)
        return $true
    }
    return (-not $requested)
}
function global:Sync-PDELiveEditorIndex {
    [PDE.PowerShell.PDECommandColors]::SetIndex(
        [string[]]@($global:PDE_State.CommandNames),
        [string[]]@($global:PDE_State.HistoryCommandNames),
        [bool]$global:PDE_State.DiscoveryHealthy)
    $null = Sync-PDELiveEditorHighlightMode
}
function global:Enable-PDELiveHighlight {
    [CmdletBinding()]
    param([switch]$Quiet)
    $s=$global:PDE_State
    if($s.LiveHighlightingEnabled){return $true}
    if(-not $s.Interactive){if(-not $Quiet){Write-Warning 'Live editing requires an interactive console.'};return $false}
    try {
        $root=Split-Path $s.SourcePath
        $binary=if($PSVersionTable.PSEdition -eq 'Desktop'){'PDE.Editor.Desktop.dll'}else{'PDE.Editor.Core.dll'}
        if($PSVersionTable.PSEdition -ne 'Desktop' -and $PSVersionTable.PSVersion -lt [version]'7.4'){
            throw 'This live editor build requires PowerShell 7.4 or later, or Windows PowerShell 5.1.'
        }
        if(-not (Get-Module PSReadLine)){Import-Module PSReadLine -ErrorAction Stop}
        $native=Get-PSReadLineOption
        $nativeBindings=@(Get-PSReadLineKeyHandler -Bound)
        $null=[Reflection.Assembly]::LoadFrom((Join-Path $root 'Microsoft.PowerShell.Pager.dll'))
        Import-Module (Join-Path $root $binary) -Prefix PDELive -Global -ErrorAction Stop
        $options=@{}
        $setter=Get-Command Set-PDELivePSReadLineOption
        foreach($name in @('EditMode','HistorySavePath','HistorySaveStyle','MaximumHistoryCount','HistoryNoDuplicates','ContinuationPrompt','ExtraPromptLineCount','PromptText','BellStyle','WordDelimiters','HistorySearchCursorMovesToEnd')){
            if($setter.Parameters.ContainsKey($name) -and $native.PSObject.Properties[$name] -and $null -ne $native.$name){$options[$name]=$native.$name}
        }
        if($native.AddToHistoryHandler){$options.AddToHistoryHandler=$native.AddToHistoryHandler}
        foreach ($optionName in @($options.Keys)) {
            $single=@{}; $single[$optionName]=$options[$optionName]
            try { Set-PDELivePSReadLineOption @single -ErrorAction Stop } catch { Write-Verbose "Native option $optionName could not be copied; live editor default retained." }
        }
        foreach($binding in $nativeBindings){
            if($binding.Function -ne 'CustomAction' -and $binding.Group -ne 'Custom'){
                try{Set-PDELivePSReadLineKeyHandler -Chord $binding.Key -Function $binding.Function -ErrorAction Stop}catch{}
            }
        }
        $custom=@($nativeBindings | Where-Object {$_.Group -eq 'Custom'})
        if($custom.Count -and -not $Quiet){Write-Warning 'Custom script key bindings remain in the native editor. Register live-editor custom keys with Set-PDELivePSReadLineKeyHandler and [PDE.PowerShell.PSConsoleReadLine]. Disable-PDELiveHighlight restores your native editor.'}
        $original=Get-Item Function:PSConsoleHostReadLine -ErrorAction SilentlyContinue
        $s.LiveOriginalReadLine=if($original){$original.ScriptBlock}else{$null}
        $s.LiveReadLineWrapper={
            $lastRunStatus=$?
            Sync-PDELiveEditorIndex
            [PDE.PowerShell.PSConsoleReadLine]::ReadLine($Host.Runspace,$ExecutionContext,$lastRunStatus)
        }
        Sync-PDELiveEditorIndex
        [PDE.PowerShell.PDECommandColors]::Enabled=$true
        Set-Item Function:global:PSConsoleHostReadLine -Value $s.LiveReadLineWrapper -Force
        $s.LiveHighlightingEnabled=$true
        if (Sync-PDELiveEditorHighlightMode) {
            $mode = if ($global:PDE_Config.HighlightMode -eq 'Character') { 'character' } else { 'token' }
            $s.ColouringStatus="Live editor active; $mode command highlighting."
        }
        else {
            $s.ColouringStatus='Live editor active in token mode; the bundled DLL does not support CharacterMode.'
            if (-not $Quiet) { Write-Warning $s.ColouringStatus }
        }
        return $true
    }catch{
        $s.LastError=$_.Exception.Message
        $s.ColouringStatus='Live editor unavailable: '+$s.LastError
        if(-not $Quiet){Write-Warning $s.ColouringStatus}
        return $false
    }
}
function global:Disable-PDELiveHighlight {
    $s=$global:PDE_State
    if(-not $s){return}
    if($s.LiveHighlightingEnabled){
        $current=Get-Item Function:PSConsoleHostReadLine -ErrorAction SilentlyContinue
        if($current -and [object]::ReferenceEquals($current.ScriptBlock,$s.LiveReadLineWrapper)){
            if($s.LiveOriginalReadLine){Set-Item Function:global:PSConsoleHostReadLine -Value $s.LiveOriginalReadLine -Force}
            else{Remove-Item Function:PSConsoleHostReadLine -ErrorAction SilentlyContinue}
        }
        [PDE.PowerShell.PDECommandColors]::Enabled=$false
    }
    $s.LiveHighlightingEnabled=$false
    $s.ColouringStatus='Native editor restored. Use Enable-PDELiveHighlight to enable live command colours.'
}
#endregion

#region Options
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
function global:Set-PDEOptions {
    [CmdletBinding()]
    param([bool]$EnablePredictions,[bool]$EnablePromptLearning,[bool]$EnableLiveHighlight,
        [ValidateRange(1,4)][int]$FuzzyMaximumDistance,[bool]$EnableFuzzySuggestions,
        [ValidateRange(1,20000)][int]$HistoryIndexLimit,
        [ValidateRange(10,3600)][int]$CommandRefreshSeconds,
        [bool]$EnableDiagnosticsLog,[string]$DiagnosticsLogPath)
    foreach ($key in $PSBoundParameters.Keys) { $global:PDE_Config[$key]=$PSBoundParameters[$key] }
    if ($PSBoundParameters.ContainsKey('EnablePromptLearning')) {
        if($EnablePromptLearning){$null=Enable-PDEPromptLearning}else{Disable-PDEPromptLearning}
    }
    if ($PSBoundParameters.ContainsKey('EnableLiveHighlight')) {
        if($EnableLiveHighlight){$null=Enable-PDELiveHighlight}else{Disable-PDELiveHighlight}
    }
    if ($PSBoundParameters.ContainsKey('EnablePredictions')) { $null=Invoke-PDEApplyOptions }
    Get-PDEStatus
}
#endregion

#region Diagnostics
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
function global:Get-PDEStatus {
    $s=$global:PDE_State
    $readline=Get-Module PSReadLine | Select-Object -First 1
    [pscustomobject]@{
        Version=$s.Version; Running=$s.Running; SourcePath=$s.SourcePath
        PowerShellVersion=$PSVersionTable.PSVersion.ToString()
        PSReadLineVersion=if($readline){$readline.Version.ToString()}else{'Not loaded'}
        Interactive=$s.Interactive; IndexedCommands=$s.CommandNames.Count
        DiscoveryHealthy=$s.DiscoveryHealthy; LastIndexUpdate=$s.LastIndexUpdate
        SuccessfulCommandNames=$s.HistoryCommandNames.Count; HistoryStorage='Session memory; command names only'
        PromptLearningEnabled=$s.PromptLearningEnabled; PredictionsEnabled=$s.PredictionAvailable
        PredictionStatus=$s.PredictionReason; NativeColouringEnabled=$s.NativeColouringEnabled
        LiveHighlightingEnabled=$s.LiveHighlightingEnabled; ColouringStatus=$s.ColouringStatus; KeyBindingsChanged=0
        StartupMilliseconds=$s.StartupMilliseconds; LastError=$s.LastError
        AcceptanceStatus='Live rendering implemented; Windows runtime and visual verification required.'
    }
}
function global:Get-PDEStatistics { Get-PDEStatus }
function global:Get-PDEDiagnostics {
    [pscustomobject]@{Status=(Get-PDEStatus); HostName=$Host.Name
        OperatingSystem=[Environment]::OSVersion.VersionString
        Guidance='Run Test-PDE.ps1 in a disposable process. Read README.md. PDE never reads personal history files.'}
}
function global:Get-PDEHelp {
    param([string]$Name='PDE.ps1')
    if($Name -eq 'PDE.ps1') {
        'Get-PDEStatus; Get-PDESuggestions; Get-PDECommandAnalysis; Test-PDESyntax; Show-PDEHighlight; Update-PDEIndex -Force; Clear-PDEHistory; Set-PDEOptions; Stop-PDE; Start-PDE; Install-PDE; Uninstall-PDE; Test-PDE'
    } else { Get-Help -Name $Name -Full }
}
#endregion

#region Tests
# Modified for PDE 4.3.0-rc1. See README.md.
function global:Test-PDE {
    <# Always run tests in a disposable process: no profile, history or bindings changed here. #>
    [CmdletBinding()]
    param([switch]$Quiet)
    $report=Join-Path ([IO.Path]::GetTempPath()) ('PDE-tests-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        $engine=Join-Path $PSHOME $(if($PSVersionTable.PSEdition -eq 'Desktop'){'powershell.exe'}elseif($env:OS -eq 'Windows_NT'){'pwsh.exe'}else{'pwsh'})
        & $engine -NoLogo -NoProfile -NonInteractive -File (Join-Path (Split-Path $global:PDE_SourcePath) 'Test-PDE.ps1') -ReportPath $report | Out-Null
        if(-not [IO.File]::Exists($report)){throw 'Test worker did not produce a report.'}
        $result=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
        if(-not $Quiet){$result.Checks | Format-Table Status,Name,Detail -Wrap | Out-Host}
        return $result
    } finally { if([IO.File]::Exists($report)){[IO.File]::Delete($report)} }
}
function global:Invoke-PDETestSuite {
    [CmdletBinding()]
    param()
    $checks=[Collections.Generic.List[object]]::new()
    function Assert-PDE([bool]$Condition,[string]$Message='Assertion failed') {if(-not $Condition){throw $Message}}
    function Case-PDE([string]$Name,[scriptblock]$Body) {
        try { $null=& $Body; $checks.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail='Verified by runtime assertion'}) }
        catch { $checks.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message}) }
    }
    function Skip-PDE([string]$Name,[string]$Reason) {$checks.Add([pscustomobject]@{Name=$Name;Status='SKIP';Detail=$Reason})}
    $root=Split-Path $global:PDE_SourcePath
    $sandbox=Join-Path ([IO.Path]::GetTempPath()) ('PDE test [space] '+[guid]::NewGuid().ToString('N'))
    $null=[IO.Directory]::CreateDirectory($sandbox)
    try {
        Case-PDE 'All release files and PowerShell syntax' {
            foreach($name in Get-PDEReleaseFiles){
                $file=Join-Path $root $name
                Assert-PDE ([IO.File]::Exists($file)) "Missing $name"
                if($name.EndsWith('.ps1')){
                    $t=$null;$e=$null
                    $null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$t,[ref]$e)
                    Assert-PDE ($e.Count -eq 0) "Parse errors: $name"
                }
            }
        }
        Case-PDE 'No duplicate feature functions' {
            $names=@(foreach($f in Get-Item -LiteralPath (Join-Path $root 'PDE.ps1')){
                $t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$t,[ref]$e)
                $a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true).Name
            })
            Assert-PDE (@($names | Group-Object | Where-Object Count -gt 1).Count -eq 0)
        }
        Case-PDE 'Loader repeated initialization preserves state' {
            $before=$global:PDE_State
            . (Join-Path $root 'PDE.ps1')
            Assert-PDE ([object]::ReferenceEquals($before,$global:PDE_State))
        }
        Case-PDE 'Cmdlet and alias discovery' {
            Assert-PDE ($global:PDE_State.CommandNames.Contains('Get-Date'))
            Assert-PDE ($global:PDE_State.CommandNames.Contains('gci'))
        }
        Case-PDE 'Native executable discovery' {
            $name=[IO.Path]::GetFileName((Get-Process -Id $PID).Path)
            # This portable runtime may not be on PATH: use a system executable.
            $probe=if($env:OS -eq 'Windows_NT'){'cmd.exe'}else{'sh'}
            Assert-PDE ($global:PDE_State.CommandNames.Contains($probe)) "$probe missing from index"
        }
        Case-PDE 'Index refresh throttled' {Assert-PDE (-not (Update-PDEIndex).Updated)}
        Case-PDE 'Dynamic function addition and removal' {
            function global:Test-PDETemporaryFunction { 'ok' }
            Update-PDEDynamicCommands
            Assert-PDE ($global:PDE_State.CommandNames.Contains('Test-PDETemporaryFunction'))
            Remove-Item Function:Test-PDETemporaryFunction
            Update-PDEDynamicCommands
            Assert-PDE (-not $global:PDE_State.CommandNames.Contains('Test-PDETemporaryFunction'))
        }
        Case-PDE 'Recognised command orange before success' {Assert-PDE ((Get-PDECommandClass 'Get-Date') -eq 1)}
        Case-PDE 'Incomplete prefix orange' {Assert-PDE ((Get-PDECommandClass 'Get-Pro') -eq 1)}
        Case-PDE 'Misspelling preserves exact positions and flags an extra letter' {
            $m=Get-PDECommandNameColorMap 'Get-Proccess'
            Assert-PDE ($m.Length -eq 12 -and $m[0] -eq 3 -and $m[8] -eq 2 -and $m[9] -eq 1)
        }
        Case-PDE 'Discovery unavailable is uncertain rather than red' {
            $global:PDE_State.DiscoveryHealthy=$false
            try{Assert-PDE ((Get-PDECommandClass 'NoSuchPDECommandZZZ') -eq 1)}finally{$global:PDE_State.DiscoveryHealthy=$true}
        }
        Case-PDE 'Pipeline arguments and operators gray' {
            $text='Get-Process -Name explorer | NoSuchPDECommandZZZ'
            $m=Get-PDELineColorMap $text
            Assert-PDE ($m.Length -eq $text.Length -and $m[0] -eq 3 -and $m[12] -eq 0 -and $m[18] -eq 0 -and $m[26] -eq 0 -and $m[29] -eq 2)
        }
        Case-PDE 'Nested script blocks and command substitution mapped' {
            $text='& { Get-Date; Write-Output $(Get-Process) }'
            $m=Get-PDELineColorMap $text
            foreach($name in @('Get-Date','Write-Output','Get-Process')){Assert-PDE ($m[$text.IndexOf($name)] -eq 3)}
        }
        Case-PDE 'Quoted invocation command mapped; argument remains gray' {
            $text="& 'Get-Date' 'text'";$m=Get-PDELineColorMap $text
            Assert-PDE ($m[3] -eq 3 -and $m[14] -eq 0)
        }
        Case-PDE 'Dynamic invocation remains neutral' {$m=Get-PDELineColorMap '& $name';Assert-PDE (@($m | Where-Object {$_ -ne 0}).Count -eq 0)}
        Case-PDE 'Function defined in current input recognised' {
            $text='function Test-NewPDE { Get-Date }; Test-NewPDE'
            $m=Get-PDELineColorMap $text; Assert-PDE ($m[$text.LastIndexOf('Test-NewPDE')] -eq 3)
        }
        Case-PDE 'Unicode UTF-16 offsets and multiline input' {
            $text="Write-Output '$( [char]0x03bb )';`nGet-Date";$m=Get-PDELineColorMap $text
            Assert-PDE ($m.Length -eq $text.Length -and $m[$text.IndexOf('Get-Date')] -eq 3)
        }
        Case-PDE 'Incomplete syntax distinguished' {Assert-PDE ((Test-PDESyntax 'if ($true) {').IsIncomplete)}
        Case-PDE 'Invalid syntax detected' {$s=Test-PDESyntax 'Get-Date | |';Assert-PDE (-not $s.IsValid)}
        Case-PDE 'Empty input accepted' {Assert-PDE ((Test-PDESyntax '').IsValid)}
        Case-PDE 'AST offsets cover name only' {
            $a=Get-PDECommandAnalysis 'Get-Date -Format o'
            Assert-PDE ($a.Commands[0].StartOffset -eq 0 -and $a.Commands[0].EndOffset -eq 8)
        }
        Case-PDE 'Fuzzy correction Get-Proccess' {Assert-PDE ((Get-PDESuggestions 'Get-Proccess' -Limit 1).Suggestion -eq 'Get-Process')}
        Case-PDE 'Prefix suggestions' {Assert-PDE (@(Get-PDESuggestions 'Get-Pro').Suggestion -contains 'Get-Process')}
        Case-PDE 'Valid command produces no correction' {Assert-PDE (@(Get-PDESuggestions 'Get-Date').Count -eq 0)}
        Case-PDE 'Levenshtein empty and case handling' {
            Assert-PDE ((Get-PDELevenshteinDistance '' 'abc') -eq 3)
            Assert-PDE ((Get-PDELevenshteinDistance 'ABC' 'abc') -eq 0)
        }
        Case-PDE 'Failed command never learned' {Assert-PDE (-not (Add-PDEHistoryEntry 'Get-Date' -Succeeded $false));Assert-PDE (-not $global:PDE_State.HistoryCommandNames.Contains('Get-Date'))}
        Case-PDE 'Successful command learned; exact name green' {
            Assert-PDE (Add-PDEHistoryEntry 'Get-Date' -Succeeded $true)
            Assert-PDE ((Get-PDECommandClass 'Get-Date') -eq 3)
            Assert-PDE ((Get-PDECommandClass 'Get-Dat') -eq 1)
        }
        Case-PDE 'History contains no command arguments' {
            $null=Add-PDEHistoryEntry 'Write-Output ordinary-private-value' -Succeeded $true
            Assert-PDE (-not (($global:PDE_State.History -join ' ') -match 'ordinary-private-value'))
        }
        Case-PDE 'Secrets excluded' {
            foreach($line in @('Write-Output -Token abc','Write-Output "https://user:pass@example.com"','ConvertTo-SecureString abc -AsPlainText','Write-Output "api_key=abc"')) {
                Assert-PDE (Test-PDESensitiveHistoryLine $line)
                Assert-PDE (-not (Add-PDEHistoryEntry $line -Succeeded $true))
            }
        }
        Case-PDE 'Unexecuted definitions and nested statements not learned' {
            foreach($line in @('function x { Get-Date }','if ($false) { Get-Date }','Get-Date; Write-Output ok','Write-Output $(Get-Date)','Get-Date | Out-Null','& { Get-Date }')) {
                Assert-PDE ($null -eq (Get-PDELearnableCommand $line)) "Unsafe attribution: $line"
            }
        }
        Case-PDE 'Native nonzero exit excluded' {
            $probe=if($env:OS -eq 'Windows_NT'){'cmd.exe'}else{'sh'}
            Assert-PDE (-not (Add-PDEHistoryEntry $probe -Succeeded $true -NativeExitCode 2))
        }
        Case-PDE 'History refresh cannot import unknown outcomes' {
            Clear-PDEHistory; $null=Update-PDEHistory -Force
            Assert-PDE ($global:PDE_State.History.Count -eq 0)
        }
        Case-PDE 'History memory limit' {
            $old=$global:PDE_Config.HistoryIndexLimit;$global:PDE_Config.HistoryIndexLimit=1
            try{$null=Add-PDEHistoryEntry 'Get-Date' -Succeeded $true;$null=Add-PDEHistoryEntry 'Get-Process' -Succeeded $true;Assert-PDE ($global:PDE_State.History.Count -eq 1)}
            finally{$global:PDE_Config.HistoryIndexLimit=$old;Clear-PDEHistory}
        }
        Case-PDE 'Safe live fallback installs zero bindings' {
            for($i=0;$i -lt 10;$i++){Assert-PDE (-not (Enable-PDELiveHighlight -Quiet));Disable-PDELiveHighlight}
            Assert-PDE (-not $global:PDE_State.LiveHighlightingEnabled)
        }
        Case-PDE 'No cursor writes, private PSReadLine reflection or key interception' {
            $code=[IO.File]::ReadAllText((Join-Path $root 'PDE.ps1'))
            $text=foreach($section in @('Coloring','PSReadLine')){
                $match=[regex]::Match($code,"(?ms)^#region $section\r?\n(.*?)^#endregion")
                Assert-PDE $match.Success "Missing $section section"
                $match.Groups[1].Value
            }
            $text=$text -join [Environment]::NewLine
            Assert-PDE ($text -notmatch 'SetCursorPosition|Console\]::Write|Set-PSReadLineKeyHandler|BindingFlags|GetField\(')
        }
        try { Import-Module PSReadLine -ErrorAction Stop; $hasReadline=$true } catch { $hasReadline=$false }
        if($hasReadline){
            Case-PDE 'PSReadLine bindings unchanged after repeated enable/disable' {
                $before=Get-PSReadLineKeyHandler | ConvertTo-Json -Depth 4 -Compress
                $null=Enable-PDELiveHighlight -Quiet;Disable-PDELiveHighlight
                $after=Get-PSReadLineKeyHandler | ConvertTo-Json -Depth 4 -Compress
                Assert-PDE ($before -ceq $after)
            }
            Case-PDE 'SaveNothing disables learning' {
                $old=(Get-PSReadLineOption).HistorySaveStyle
                try{Set-PSReadLineOption -HistorySaveStyle SaveNothing;Assert-PDE (-not (Add-PDEHistoryEntry 'Get-Date' -Succeeded $true))}
                finally{Set-PSReadLineOption -HistorySaveStyle $old}
            }
            Case-PDE 'Custom history rejection respected' {
                $old=(Get-PSReadLineOption).AddToHistoryHandler
                try{Set-PSReadLineOption -AddToHistoryHandler {$false};Assert-PDE (-not (Add-PDEHistoryEntry 'Get-Date' -Succeeded $true))}
                finally{Set-PSReadLineOption -AddToHistoryHandler $old}
            }
        }else{Skip-PDE 'PSReadLine integration' 'Module unavailable in this runtime'}
        Case-PDE 'Prompt install and exact restoration; repeated disable' {
            $oldPrompt=(Get-Item Function:prompt).ScriptBlock
            $global:PDE_State.Interactive=$true
            try {
                Assert-PDE (Enable-PDEPromptLearning)
                Assert-PDE (Enable-PDEPromptLearning)
                Disable-PDEPromptLearning;Disable-PDEPromptLearning
                Assert-PDE ([object]::ReferenceEquals((Get-Item Function:prompt).ScriptBlock,$oldPrompt))
            }finally{$global:PDE_State.Interactive=$false}
        }
        Case-PDE 'Prompt outcome captures failure and success before maintenance' {
            $priorPrompt=$global:PDE_State.OriginalPrompt
            $priorPreference=$ErrorActionPreference
            try {
                $global:PDE_State.OriginalPrompt={'TEST> '}
                Clear-PDEHistory
                $record=[pscustomobject]@{CommandLine='Get-Date';ExecutionStatus='Completed';StartExecutionTime=(Get-Date);EndExecutionTime=(Get-Date)}
                Add-History -InputObject $record
                $ErrorActionPreference='Continue'
                Write-Error 'Intentional test failure' -ErrorAction SilentlyContinue
                $text=Invoke-PDEPrompt
                $ErrorActionPreference='Stop'
                Assert-PDE (-not $global:PDE_LastCommandSucceeded)
                Assert-PDE (-not $global:PDE_State.HistoryCommandNames.Contains('Get-Date'))
                Add-History -InputObject $record
                $null=Get-Date
                $text=Invoke-PDEPrompt
                Assert-PDE ($text -eq 'TEST> ')
                Assert-PDE $global:PDE_LastCommandSucceeded
                Assert-PDE ($global:PDE_State.HistoryCommandNames.Contains('Get-Date'))
            }finally{$global:PDE_State.OriginalPrompt=$priorPrompt;$ErrorActionPreference=$priorPreference;Clear-PDEHistory}
        }
        Case-PDE 'Later custom prompt is not overwritten on disable' {
            $oldPrompt=(Get-Item Function:prompt).ScriptBlock;$global:PDE_State.Interactive=$true
            try {
                $null=Enable-PDEPromptLearning
                $replacement={'custom> '};Set-Item Function:global:prompt $replacement
                Disable-PDEPromptLearning
                Assert-PDE ([object]::ReferenceEquals((Get-Item Function:prompt).ScriptBlock,$replacement))
            }finally{Set-Item Function:global:prompt $oldPrompt;$global:PDE_State.Interactive=$false}
        }
        $target=Join-Path $sandbox "install ' quoted [test]"
        $profile=Join-Path $sandbox 'profile.ps1'
        $original="# user profile`r`n`$userSetting = '$( [char]0x03bb )'`r`n"
        [IO.File]::WriteAllText($profile,$original,[Text.Encoding]::Unicode)
        $originalBytes=[IO.File]::ReadAllBytes($profile)
        Case-PDE 'Install WhatIf changes nothing' {
            $null=Install-PDE -DestinationDirectory $target -ProfilePaths $profile -WhatIf
            Assert-PDE (-not [IO.Directory]::Exists($target))
            Assert-PDE ([Convert]::ToBase64String([IO.File]::ReadAllBytes($profile)) -eq [Convert]::ToBase64String($originalBytes))
        }
        Case-PDE 'Install handles quoted paths and preserves profile encoding' {
            $null=Install-PDE -DestinationDirectory $target -ProfilePaths $profile
            Assert-PDE ([IO.File]::Exists((Join-Path $target 'PDE.ps1')))
            Assert-PDE ([IO.File]::ReadAllText($profile).StartsWith($original))
            Assert-PDE ([IO.File]::ReadAllBytes($profile)[0] -eq 255)
            $t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseFile($profile,[ref]$t,[ref]$e)
            Assert-PDE ($e.Count -eq 0)
        }
        Case-PDE 'Identical upgrade is idempotent' {
            $result=Install-PDE -DestinationDirectory $target -ProfilePaths $profile
            Assert-PDE ($result.ChangedFiles -eq 0)
            Assert-PDE ([regex]::Matches([IO.File]::ReadAllText($profile),'# >>> PDE 4.2 loader >>>').Count -eq 1)
        }
        Case-PDE 'Uninstall restores original profile bytes' {
            $null=Uninstall-PDE -ProfilePaths $profile
            Assert-PDE ([Convert]::ToBase64String([IO.File]::ReadAllBytes($profile)) -eq [Convert]::ToBase64String($originalBytes))
            Assert-PDE ([IO.File]::Exists((Join-Path $target 'LICENSE')))
        }
        Case-PDE 'Repeated uninstall is harmless' {Assert-PDE (@(Uninstall-PDE -ProfilePaths $profile).Count -eq 0)}
        Case-PDE 'Legacy v4 markers migrate without unrelated deletion' {
            $legacy="before`r`n# >>> PDE 4 modular loader >>>`r`nold code`r`n# <<< PDE 4 modular loader <<<`r`nafter"
            Assert-PDE ((Remove-PDEProfileBlock $legacy) -ceq "before`r`nafter")
        }
        Case-PDE 'Malformed profile markers refused' {
            $thrown=$false;try{$null=Remove-PDEProfileBlock '# >>> PDE 4.2 loader >>>'}catch{$thrown=$true}
            Assert-PDE $thrown
        }
        Case-PDE 'Install rollback on profile write failure' {
            $rollbackTarget=Join-Path $sandbox 'rollback'
            $badProfile=Join-Path $sandbox 'directory-instead-of-profile';$null=[IO.Directory]::CreateDirectory($badProfile)
            $thrown=$false
            try{$null=Install-PDE -DestinationDirectory $rollbackTarget -ProfilePaths @($profile,$badProfile)}catch{$thrown=$true}
            Assert-PDE $thrown
            Assert-PDE (-not [IO.File]::Exists((Join-Path $rollbackTarget 'PDE.ps1')))
            Assert-PDE ([Convert]::ToBase64String([IO.File]::ReadAllBytes($profile)) -eq [Convert]::ToBase64String($originalBytes))
        }
        Case-PDE 'Loader rejects missing dependency before loading' {
            $incomplete=Join-Path $sandbox 'incomplete';$null=[IO.Directory]::CreateDirectory($incomplete)
            Copy-Item -LiteralPath (Join-Path $root 'PDE.ps1') -Destination $incomplete
            $thrown=$false;try{. (Join-Path $incomplete 'PDE.ps1')}catch{$thrown=$true}
            Assert-PDE $thrown
        }
        Case-PDE 'Live backend loads, maps semantic colours and restores host reader' {
            $wasInteractive=$global:PDE_State.Interactive
            $global:PDE_State.Interactive=$true
            $before=(Get-Item Function:PSConsoleHostReadLine).ScriptBlock
            try {
                Assert-PDE (Enable-PDELiveHighlight -Quiet) $global:PDE_State.ColouringStatus
                Assert-PDE $global:PDE_State.LiveHighlightingEnabled
                [PDE.PowerShell.PDECommandColors]::SetIndex([string[]]@('Get-Date','Get-Process'),[string[]]@('Get-Date'),$true)
                $m=[PDE.PowerShell.PDECommandColors]::GetMap('Get-Date | Get-Pro | FakeCommand -Name test')
                Assert-PDE ($m[0] -eq 3 -and $m[11] -eq 3 -and $m[21] -eq 2 -and $m[32] -eq 0)
                $mixed=[PDE.PowerShell.PDECommandColors]::GetMap("Get-Dtae | Get-Datx")
                Assert-PDE (($mixed -join '') -eq '3333311300033333332')
                Disable-PDELiveHighlight
                Assert-PDE ([object]::ReferenceEquals((Get-Item Function:PSConsoleHostReadLine).ScriptBlock,$before))
            } finally {Disable-PDELiveHighlight;$global:PDE_State.Interactive=$wasInteractive}
        }
        Case-PDE 'Configuration validates range' {
            $thrown=$false;try{$null=Set-PDEOptions -FuzzyMaximumDistance 100}catch{$thrown=$true}
            Assert-PDE $thrown
        }
        Case-PDE 'PowerShell 7 detector rejects missing candidates' {
            Assert-PDE ($null -eq (Find-PDEPowerShell7 -Candidates @((Join-Path $sandbox 'missing.exe'))))
        }
        Case-PDE 'PowerShell 7 detector validates a runnable engine' {
            if($PSVersionTable.PSVersion.Major -eq 7) {
                $engine=Join-Path $PSHOME $(if($env:OS -eq 'Windows_NT'){'pwsh.exe'}else{'pwsh'})
                Assert-PDE ((Find-PDEPowerShell7 -Candidates @($engine)) -eq $engine)
            } else {
                $engine=Join-Path $PSHOME 'powershell.exe'
                Assert-PDE ($null -eq (Find-PDEPowerShell7 -Candidates @($engine)))
            }
        }
        Case-PDE 'Stop/start lifecycle' {Stop-PDE;Assert-PDE (-not $global:PDE_State.Running);Start-PDE -NonInteractive;Assert-PDE $global:PDE_State.Running}
        $timer=[Diagnostics.Stopwatch]::StartNew()
        for($i=0;$i -lt 200;$i++){$null=Get-PDELineColorMap 'Get-Date | NoSuchPDECommandZZZ -Name value'}
        $timer.Stop();$mapMs=$timer.Elapsed.TotalMilliseconds/200
        $timer.Restart();$null=Get-PDELineColorMap ('Get-Date; '*1000);$timer.Stop();$longMs=$timer.Elapsed.TotalMilliseconds
        $checks.Add([pscustomobject]@{Name='Performance observations (not visual latency)';Status='PASS';Detail=('Map mean {0:N3} ms; 10k-character map {1:N1} ms; startup {2:N1} ms' -f $mapMs,$longMs,$global:PDE_State.StartupMilliseconds)})
        if($env:OS -eq 'Windows_NT' -and $PSVersionTable.PSVersion.Major -eq 5){Case-PDE 'Windows PowerShell 5.1 runtime' {Assert-PDE ($PSVersionTable.PSVersion -ge [version]'5.1')}}
        else{Skip-PDE 'Windows PowerShell 5.1 runtime' 'NOT VERIFIED here. Run powershell.exe -NoProfile -File .\Test-PDE.ps1'}
        if($env:OS -eq 'Windows_NT' -and $PSVersionTable.PSVersion.Major -eq 7){Case-PDE 'Windows PowerShell 7 runtime' {Assert-PDE $true}}
        else{Skip-PDE 'Windows PowerShell 7 runtime' 'NOT VERIFIED here. Run pwsh.exe -NoProfile -File .\Test-PDE.ps1'}
        Skip-PDE 'Windows one-click setup / normal profile startup' 'NOT VERIFIED by sandbox file tests. Follow README.md on Windows.'
        Skip-PDE 'Windows live four-colour editing acceptance' 'Linux live rendering visually observed; Windows terminal verification still required.'
        Skip-PDE 'Terminal input, resize, paste and asynchronous output' 'NOT VERIFIED automatically. Run Test-PDE.ps1 -Interactive in each target terminal.'
    }finally{if([IO.Directory]::Exists($sandbox)){[IO.Directory]::Delete($sandbox,$true)}}
    $failed=@($checks | Where-Object Status -eq 'FAIL').Count
    [pscustomobject]@{Version=$global:PDE_State.Version;Runtime=$PSVersionTable.PSVersion.ToString();OS=[Environment]::OSVersion.VersionString
        Passed=($failed -eq 0);PassedCount=@($checks | Where-Object Status -eq 'PASS').Count
        FailedCount=$failed;SkippedCount=@($checks | Where-Object Status -eq 'SKIP').Count
        ProductionReady=$false;Checks=$checks.ToArray()}
}
#endregion

#region Install
# Modified for PDE 4.3.0-rc1, 2026-11-03. See README.md.
function global:Get-PDEReleaseFiles {
    @(
        'PDE.ps1'
        'PDE.CharacterColoring.cs'
        'Install-PDE.cmd'
        'Setup-PDE.ps1'
        'Test-PDE.ps1'
        'Microsoft.PowerShell.Pager.dll'
        'PDE.Editor.Core.dll'
        'PDE.Editor.Desktop.dll'
        'System.Runtime.InteropServices.RuntimeInformation.dll'
        'PDE.Editor.Source.zip'
        'README.md'
        'LICENSE'
        'SHA256SUMS.txt'
    )
}
function global:Remove-PDEProfileBlock {
    param([AllowEmptyString()][string]$Text)
    $pattern='(?m)^# >>> PDE (?:4 (?:standalone|modular)|4\.2) loader >>>\r?$'
    $starts=[regex]::Matches($Text,$pattern).Count
    $ends=[regex]::Matches($Text,'(?m)^# <<< PDE (?:4 (?:standalone|modular)|4\.2) loader <<<\r?$').Count
    if ($starts -ne $ends) { throw 'Malformed PDE profile markers. Profile was not changed; restore or repair the marked block.' }
    $clean=$Text
    # Our separator belongs to our block; old releases did not track theirs.
    foreach ($label in @('4.2','4 modular','4 standalone')) {
        $prefix=if($label -eq '4.2'){'(?:\r?\n)?'}else{''}
        $rx=$prefix+'(?m:^# >>> PDE '+[regex]::Escape($label)+' loader >>>\r?\n)[\s\S]*?(?m:^# <<< PDE '+[regex]::Escape($label)+' loader <<<\r?\n?)'
        $clean=[regex]::Replace($clean,$rx,'')
    }
    if ($clean -match '(?m)^# [><]{3} PDE .* loader [><]{3}') { throw 'Unrecognised or mismatched PDE marker; refusing to rewrite profile.' }
    return $clean
}
function global:Get-PDEProfileDocument {
    param([string]$Path)
    $bytes=if([IO.File]::Exists($Path)){[IO.File]::ReadAllBytes($Path)}else{[byte[]]@()}
    $offset=0; $encoding=[Text.UTF8Encoding]::new($true)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { $offset=3 }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 255 -and $bytes[1] -eq 254) { $encoding=[Text.Encoding]::Unicode; $offset=2 }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 254 -and $bytes[1] -eq 255) { $encoding=[Text.Encoding]::BigEndianUnicode; $offset=2 }
    elseif ($bytes.Length) {
        $encoding=[Text.UTF8Encoding]::new($false,$true)
        try { $null=$encoding.GetString($bytes) } catch { $encoding=[Text.Encoding]::Default }
    }
    [pscustomobject]@{Bytes=$bytes; Encoding=$encoding; Text=$encoding.GetString($bytes,$offset,$bytes.Length-$offset)}
}
function global:Write-PDEAtomicBytes {
    param([string]$Path,[byte[]]$Bytes)
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,($temp+'.bak')) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}; if([IO.File]::Exists($temp+'.bak')){[IO.File]::Delete($temp+'.bak')} }
}
function global:Install-PDE {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$DestinationDirectory=$(if($env:LOCALAPPDATA){Join-Path $env:LOCALAPPDATA 'PDE'}else{Join-Path $HOME 'PDE'}),
        [string[]]$ProfilePaths=@([string]$PROFILE.CurrentUserCurrentHost))
    $source=Split-Path -Parent $global:PDE_SourcePath
    $target=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationDirectory)
    if ([IO.File]::Exists($target)) { throw 'Installation destination is a file.' }
    $files=@(Get-PDEReleaseFiles)
    $writes=[ordered]@{}
    foreach ($name in $files) {
        $from=Join-Path $source $name
        if (-not [IO.File]::Exists($from)) { throw "Release is incomplete: $name" }
        if ($name.EndsWith('.ps1')) {
            $t=$null; $e=$null
            $null=[Management.Automation.Language.Parser]::ParseFile($from,[ref]$t,[ref]$e)
            if($e.Count){throw "Invalid PowerShell file: $name"}
        }
        $writes[(Join-Path $target $name)]=[IO.File]::ReadAllBytes($from)
    }
    $literal=(Join-Path $target 'PDE.ps1').Replace("'","''")
    $block="`r`n# >>> PDE 4.2 loader >>>`r`nif (Test-Path -LiteralPath '$literal') { . '$literal' }`r`n# <<< PDE 4.2 loader <<<`r`n"
    $profileSet=New-PDEStringSet
    foreach ($path in $ProfilePaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw 'Cannot locate a profile path.' }
        $full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if (-not $profileSet.Add($full)) { continue }
        if ($writes.Contains($full)) { throw 'Profile path collides with a PDE release file.' }
        $doc=Get-PDEProfileDocument $full
        $updated=(Remove-PDEProfileBlock $doc.Text)+$block
        if ($updated -ne $doc.Text) { $writes[$full]=[byte[]]($doc.Encoding.GetPreamble()+$doc.Encoding.GetBytes($updated)) }
    }
    if (-not $PSCmdlet.ShouldProcess($target,'Install validated PDE release and update selected current-user profiles')) { return }
    $null=[IO.Directory]::CreateDirectory($target)
    $lockPath=Join-Path $target '.pde-install.lock'
    $lock=$null; $before=[ordered]@{}; $completed=[Collections.Generic.List[string]]::new()
    try {
        $lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
        foreach ($path in $writes.Keys) {
            $null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
            $exists=[IO.File]::Exists($path)
            $before[$path]=if($exists){[IO.File]::ReadAllBytes($path)}else{$null}
            if ($exists) {
                if ([Convert]::ToBase64String($before[$path]) -eq [Convert]::ToBase64String($writes[$path])) { continue }
                # Unique byte-exact backups are never overwritten on upgrades.
                [IO.File]::WriteAllBytes($path+'.pde.'+[guid]::NewGuid().ToString('N')+'.bak',$before[$path])
            }
            Write-PDEAtomicBytes $path $writes[$path]
            $completed.Add($path)
        }
        [pscustomobject]@{InstalledScript=(Join-Path $target 'PDE.ps1'); InstalledFiles=$files.Count
            Profiles=@($profileSet); ChangedFiles=$completed.Count; PolicyChanged=$false}
    } catch {
        $original=$_
        $rollbackErrors=[Collections.Generic.List[string]]::new()
        for($i=$completed.Count-1;$i -ge 0;$i--) {
            $path=$completed[$i]
            try {
                if($null -eq $before[$path]){[IO.File]::Delete($path)}else{Write-PDEAtomicBytes $path $before[$path]}
            } catch { $rollbackErrors.Add($path) }
        }
        if($rollbackErrors.Count){throw "Install failed; rollback also failed for: $($rollbackErrors -join ', '). Backups retained. $original"}
        throw $original
    } finally { if($lock){$lock.Dispose(); [IO.File]::Delete($lockPath)} }
}
function global:Uninstall-PDE {
    [CmdletBinding(SupportsShouldProcess)]
    param([string[]]$ProfilePaths=@([string]$PROFILE.CurrentUserCurrentHost))
    foreach($path in $ProfilePaths) {
        if(-not [IO.File]::Exists($path)){continue}
        $doc=Get-PDEProfileDocument $path
        $clean=Remove-PDEProfileBlock $doc.Text
        if($clean -eq $doc.Text){continue}
        if($PSCmdlet.ShouldProcess($path,'Back up profile and remove only PDE-managed blocks')) {
            [IO.File]::WriteAllBytes($path+'.pde.'+[guid]::NewGuid().ToString('N')+'.bak',$doc.Bytes)
            Write-PDEAtomicBytes $path ([byte[]]($doc.Encoding.GetPreamble()+$doc.Encoding.GetBytes($clean)))
            [pscustomobject]@{Profile=$path; Removed=$true; FilesRetained=$true}
        }
    }
    # Files and backups are intentionally retained; no recursive deletion.
}
#endregion

#region Discovery
# Modified for PDE 4.3.0-rc1, 2026-11-04.
function global:Get-PDEPowerShellCandidates {
    [CmdletBinding()]
    param()
    if ($env:PDE_PWSH_PATH) { $env:PDE_PWSH_PATH }
    foreach ($command in @(Get-Command pwsh.exe -All -CommandType Application -ErrorAction SilentlyContinue)) { $command.Source }
    foreach ($base in @($env:ProgramW6432,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)) {
        if (-not $base) { continue }
        Join-Path $base 'PowerShell\7\pwsh.exe'
        if ([IO.Directory]::Exists((Join-Path $base 'PowerShell'))) {
            Get-ChildItem -LiteralPath (Join-Path $base 'PowerShell') -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^7(?:\.|$)' -and $_.Name -notmatch 'preview' } |
                ForEach-Object { Join-Path $_.FullName 'pwsh.exe' }
        }
    }
    if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell\7\pwsh.exe'
        Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\pwsh.exe'
    }
    if ($env:OS -eq 'Windows_NT') {
        foreach ($hive in @([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryHive]::CurrentUser)) {
            foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)) {
                $baseKey=$null; $versions=$null
                try {
                    $baseKey=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
                    $versions=$baseKey.OpenSubKey('SOFTWARE\Microsoft\PowerShellCore\InstalledVersions')
                    if ($versions) {
                        foreach ($id in $versions.GetSubKeyNames()) {
                            $entry=$versions.OpenSubKey($id)
                            try {
                                $location=[string]$entry.GetValue('InstallLocation')
                                if ($location) { Join-Path $location 'pwsh.exe' }
                            } finally { if ($entry) { $entry.Dispose() } }
                        }
                    }
                } catch { Write-Verbose 'A registry view could not be read.' }
                finally { if($versions){$versions.Dispose()}; if($baseKey){$baseKey.Dispose()} }
            }
        }
    }
}
function global:Find-PDEPowerShell7 {
    [CmdletBinding()]
    param([string[]]$Candidates)
    if (-not $PSBoundParameters.ContainsKey('Candidates')) { $Candidates=@(Get-PDEPowerShellCandidates) }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in $Candidates) {
        if (-not $candidate -or -not $seen.Add($candidate) -or -not [IO.File]::Exists($candidate)) { continue }
        $process=$null
        try {
            $info=[Diagnostics.ProcessStartInfo]::new()
            $info.FileName=$candidate
            $info.Arguments='-NoLogo -NoProfile -NonInteractive -Command "if ($PSVersionTable.PSVersion.Major -eq 7) { [Console]::Write(''PDE_PS7_OK'') } else { exit 7 }"'
            $info.UseShellExecute=$false; $info.CreateNoWindow=$true
            $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
            $process=[Diagnostics.Process]::Start($info)
            $output=$process.StandardOutput.ReadToEndAsync()
            $errors=$process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(5000)) { $process.Kill(); $process.WaitForExit(); continue }
            if ($process.ExitCode -eq 0 -and $output.Result.Trim() -eq 'PDE_PS7_OK') { return [IO.Path]::GetFullPath($candidate) }
        } catch { Write-Verbose "Rejected PowerShell candidate: $candidate" }
        finally { if($process){$process.Dispose()} }
    }
    return $null
}
#endregion

$global:PDE_SourcePath = $PSCommandPath
if (-not $NoStart) { Start-PDE }
