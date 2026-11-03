# 9. PDE live three-colour command highlighter
# ---------------------------------------------------------------------------
# Character colours are assigned only to CommandElements[0] (the command
# token). Arguments, parameters, strings and ordinary text remain neutral.
# Green  = exact command character matched to a command name in indexed history
# Yellow = exact command character matched to a known but unused command name
# Red    = typed command character that does not align to the selected command
#
# Rendering remains restricted to safe, single-line printable ASCII input that
# does not wrap. PSReadLine retains ownership of the input buffer and editing.

# Compile the alignment engine once per PowerShell process. The class name is
# deliberately stable so dot-sourcing this file repeatedly does not recompile.
if (-not ('PDE.LevenshteinHelper' -as [type])) {
    $PDE_LevenshteinSource = @'
using System;

namespace PDE
{
    public static class LevenshteinHelper
    {
        public static int GetDistance(string left, string right)
        {
            left = left ?? String.Empty;
            right = right ?? String.Empty;

            int n = left.Length;
            int m = right.Length;
            int[,] distance = new int[n + 1, m + 1];

            for (int i = 0; i <= n; i++) distance[i, 0] = i;
            for (int j = 0; j <= m; j++) distance[0, j] = j;

            for (int i = 1; i <= n; i++)
            {
                char leftChar = Char.ToUpperInvariant(left[i - 1]);
                for (int j = 1; j <= m; j++)
                {
                    int cost = leftChar == Char.ToUpperInvariant(right[j - 1]) ? 0 : 1;
                    int deletion = distance[i - 1, j] + 1;
                    int insertion = distance[i, j - 1] + 1;
                    int substitution = distance[i - 1, j - 1] + cost;
                    distance[i, j] = Math.Min(Math.Min(deletion, insertion), substitution);
                }
            }

            return distance[n, m];
        }

        public static int CommonPrefixLength(string left, string right)
        {
            left = left ?? String.Empty;
            right = right ?? String.Empty;

            int limit = Math.Min(left.Length, right.Length);
            int count = 0;
            while (count < limit &&
                   Char.ToUpperInvariant(left[count]) == Char.ToUpperInvariant(right[count]))
            {
                count++;
            }
            return count;
        }

        // Returns one colour value per typed character:
        // 1 = matched to known/unused command, 2 = incorrect, 3 = used command.
        // A candidate-only insertion has no corresponding typed cell, so its
        // nearest typed character is marked red to make the omission visible.
        public static int[] GetAlignmentMap(string typed, string candidate, int matchedColour)
        {
            typed = typed ?? String.Empty;
            candidate = candidate ?? String.Empty;

            int n = typed.Length;
            int m = candidate.Length;
            int[] result = new int[n];

            for (int i = 0; i < n; i++) result[i] = 2;
            if (n == 0 || m == 0) return result;
            if (matchedColour != 1 && matchedColour != 3)
                throw new ArgumentOutOfRangeException("matchedColour");

            int[,] distance = new int[n + 1, m + 1];
            for (int i = 0; i <= n; i++) distance[i, 0] = i;
            for (int j = 0; j <= m; j++) distance[0, j] = j;

            for (int i = 1; i <= n; i++)
            {
                char typedChar = Char.ToUpperInvariant(typed[i - 1]);
                for (int j = 1; j <= m; j++)
                {
                    int cost = typedChar == Char.ToUpperInvariant(candidate[j - 1]) ? 0 : 1;
                    int deletion = distance[i - 1, j] + 1;
                    int insertion = distance[i, j - 1] + 1;
                    int substitution = distance[i - 1, j - 1] + cost;
                    distance[i, j] = Math.Min(Math.Min(deletion, insertion), substitution);
                }
            }

            int row = n;
            int column = m;
            while (row > 0 || column > 0)
            {
                if (row > 0 && column > 0)
                {
                    bool same = Char.ToUpperInvariant(typed[row - 1]) ==
                                Char.ToUpperInvariant(candidate[column - 1]);
                    if (same && distance[row, column] == distance[row - 1, column - 1])
                    {
                        result[row - 1] = matchedColour;
                        row--;
                        column--;
                        continue;
                    }

                    if (distance[row, column] == distance[row - 1, column - 1] + 1)
                    {
                        result[row - 1] = 2;
                        row--;
                        column--;
                        continue;
                    }
                }

                if (row > 0 && distance[row, column] == distance[row - 1, column] + 1)
                {
                    result[row - 1] = 2;
                    row--;
                    continue;
                }

                if (column > 0 && distance[row, column] == distance[row, column - 1] + 1)
                {
                    if (row > 0)
                    {
                        int nearestTypedIndex = row < n ? row : n - 1;
                        result[nearestTypedIndex] = 2;
                    }
                    column--;
                    continue;
                }

                // Defensive progress guard; the populated matrix should always
                // permit one of the transitions above.
                if (row > 0)
                {
                    result[row - 1] = 2;
                    row--;
                }
                else if (column > 0)
                {
                    column--;
                }
            }

            return result;
        }
    }
}
'@

    Add-Type -TypeDefinition $PDE_LevenshteinSource -Language CSharp -ErrorAction Stop
    Remove-Variable PDE_LevenshteinSource -ErrorAction SilentlyContinue
}

# Warm the JIT outside the first interactive keystroke.
[void][PDE.LevenshteinHelper]::GetDistance('PDE', 'PDE')
[void][PDE.LevenshteinHelper]::GetAlignmentMap('pde', 'PDE', 1)
if ($global:PDE_State) {
    $global:PDE_State.LevenshteinHelperReady = $true
}

function global:Get-PDECommandNameColorMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Name
    )

    # 0 = neutral, 1 = yellow, 2 = red, 3 = green.
    $map = New-Object 'int[]' $Name.Length
    if ([string]::IsNullOrEmpty($Name)) { return ,$map }

    $state = $global:PDE_State
    if (-not $state) {
        for ($i = 0; $i -lt $Name.Length; $i++) { $map[$i] = 2 }
        return ,$map
    }

    $historyNames = $state.HistoryCommandNames
    $historyPrefixes = $state.HistoryCommandPrefixes

    # Exact known command: all characters match. Green means the exact command
    # name appears in the accepted history index; otherwise it is yellow.
    if ($state.CommandNames.Contains($Name)) {
        $colour = 1
        if ($historyNames -and $historyNames.Contains($Name)) { $colour = 3 }
        for ($i = 0; $i -lt $Name.Length; $i++) { $map[$i] = $colour }
        return ,$map
    }

    # Valid partial command name: all typed characters match. The history
    # prefix set makes this test O(1), even with a large indexed history.
    if ($state.CommandPrefixes.Contains($Name)) {
        $colour = 1
        if ($historyPrefixes -and $historyPrefixes.Contains($Name)) { $colour = 3 }
        for ($i = 0; $i -lt $Name.Length; $i++) { $map[$i] = $colour }
        return ,$map
    }

    # Find the longest valid leading prefix. Candidate enumeration is
    # imperative and bounded so a typo cannot launch a large pipeline per key.
    $candidatePrefix = ''
    for ($prefixLength = $Name.Length - 1; $prefixLength -ge 1; $prefixLength--) {
        $probe = $Name.Substring(0, $prefixLength)
        if ($state.CommandPrefixes.Contains($probe)) {
            $candidatePrefix = $probe
            break
        }
    }

    $candidateNames = [System.Collections.Generic.List[string]]::new()
    $candidateSeen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $candidateLimit = 25

    if ($candidatePrefix.Length -gt 0) {
        foreach ($candidate in $state.CommandNames) {
            if ($candidate.StartsWith($candidatePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($candidateSeen.Add($candidate)) {
                    $candidateNames.Add($candidate)
                    if ($candidateNames.Count -ge $candidateLimit) { break }
                }
            }
        }
    }
    else {
        # When the first character is wrong, try progressively shorter suffixes.
        # Stop at the first suffix that yields candidates and retain at most 25.
        for ($suffixLength = $Name.Length - 1; $suffixLength -ge 2; $suffixLength--) {
            $suffix = $Name.Substring($Name.Length - $suffixLength)
            foreach ($candidate in $state.CommandNames) {
                if ($candidate.EndsWith($suffix, [System.StringComparison]::OrdinalIgnoreCase)) {
                    if ($candidateSeen.Add($candidate)) {
                        $candidateNames.Add($candidate)
                        if ($candidateNames.Count -ge $candidateLimit) { break }
                    }
                }
            }
            if ($candidateNames.Count -gt 0) { break }
        }
    }

    if ($candidateNames.Count -eq 0) {
        for ($i = 0; $i -lt $Name.Length; $i++) { $map[$i] = 2 }
        return ,$map
    }

    $maximumDistance = 2
    if ($global:PDE_Config -and $global:PDE_Config.Contains('FuzzyMaximumDistance')) {
        $maximumDistance = [Math]::Max(1, [Math]::Min(4, [int]$global:PDE_Config.FuzzyMaximumDistance))
    }

    # Single-pass best-candidate selection. Ordering is deliberately explicit:
    # distance, common-prefix length, prior-use status, length difference, name.
    $bestName = $null
    $bestDistance = [int]::MaxValue
    $bestCommonPrefix = -1
    $bestWasUsed = $false
    $bestLengthDifference = [int]::MaxValue

    foreach ($candidate in $candidateNames) {
        $distanceValue = [PDE.LevenshteinHelper]::GetDistance($Name, $candidate)
        if ($distanceValue -gt $maximumDistance) { continue }

        $commonPrefix = [PDE.LevenshteinHelper]::CommonPrefixLength($Name, $candidate)
        $wasUsed = [bool]($historyNames -and $historyNames.Contains($candidate))
        $lengthDifference = [Math]::Abs($Name.Length - $candidate.Length)
        $isBetter = $false

        if ($null -eq $bestName) {
            $isBetter = $true
        }
        elseif ($distanceValue -lt $bestDistance) {
            $isBetter = $true
        }
        elseif ($distanceValue -eq $bestDistance -and $commonPrefix -gt $bestCommonPrefix) {
            $isBetter = $true
        }
        elseif ($distanceValue -eq $bestDistance -and
                $commonPrefix -eq $bestCommonPrefix -and
                $wasUsed -and -not $bestWasUsed) {
            $isBetter = $true
        }
        elseif ($distanceValue -eq $bestDistance -and
                $commonPrefix -eq $bestCommonPrefix -and
                $wasUsed -eq $bestWasUsed -and
                $lengthDifference -lt $bestLengthDifference) {
            $isBetter = $true
        }
        elseif ($distanceValue -eq $bestDistance -and
                $commonPrefix -eq $bestCommonPrefix -and
                $wasUsed -eq $bestWasUsed -and
                $lengthDifference -eq $bestLengthDifference -and
                [string]::Compare($candidate, $bestName, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $isBetter = $true
        }

        if ($isBetter) {
            $bestName = $candidate
            $bestDistance = $distanceValue
            $bestCommonPrefix = $commonPrefix
            $bestWasUsed = $wasUsed
            $bestLengthDifference = $lengthDifference
        }
    }

    if ($null -eq $bestName) {
        for ($i = 0; $i -lt $Name.Length; $i++) { $map[$i] = 2 }
        return ,$map
    }

    $matchedColour = if ($bestWasUsed) { 3 } else { 1 }
    $alignedMap = [PDE.LevenshteinHelper]::GetAlignmentMap($Name, $bestName, $matchedColour)
    return ,$alignedMap
}

function global:Get-PDELineColorMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    # Only CommandElements[0] receives command colours. Parameters, arguments,
    # quoted strings and ordinary text stay neutral. Separators receive yellow.
    $map = New-Object 'int[]' $Text.Length
    if ([string]::IsNullOrEmpty($Text)) { return ,$map }

    $tokens = $null
    $parseErrors = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Text, [ref]$tokens, [ref]$parseErrors
        )

        $commands = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)

        foreach ($commandAst in $commands) {
            $commandName = $commandAst.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($commandName)) { continue }
            if ($commandAst.CommandElements.Count -eq 0) { continue }

            $nameExtent = $commandAst.CommandElements[0].Extent
            $start = [Math]::Max(0, [int]$nameExtent.StartOffset)
            $end = [Math]::Min($Text.Length, [int]$nameExtent.EndOffset)

            # A quoted or otherwise transformed command element may have a
            # source extent that differs from GetCommandName(); leave it neutral
            # rather than applying a character map at incorrect offsets.
            if (($end - $start) -ne $commandName.Length) { continue }

            $nameMap = Get-PDECommandNameColorMap -Name $commandName
            for ($offset = 0; $offset -lt $nameMap.Length; $offset++) {
                $map[$start + $offset] = $nameMap[$offset]
            }
        }

        foreach ($token in $tokens) {
            $kind = $token.Kind.ToString()
            if ($kind -eq 'Pipe' -or $kind -eq 'Semicolon' -or
                $kind -eq 'Ampersand' -or $kind -eq 'AndAnd' -or $kind -eq 'OrOr') {
                $start = [Math]::Max(0, [int]$token.Extent.StartOffset)
                $end = [Math]::Min($Text.Length, [int]$token.Extent.EndOffset)
                for ($i = $start; $i -lt $end; $i++) { $map[$i] = 1 }
            }
        }
    }
    catch {
        Write-PDELog -Level WARN -Message ("Line colour-map generation failed: {0}" -f $_.Exception.Message)
    }

    return ,$map
}

function global:Invoke-PDELiveHighlight {
    [CmdletBinding()]
    param()

    if ($global:PDE_State -and $global:PDE_State.PasteInProgress) { return }

    $savedX = $null
    $savedY = $null
    try {
        $line = $null
        $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

        # Leave multi-line and non-ASCII input to PSReadLine.
        if ([string]::IsNullOrEmpty($line) -or $line -match '[\r\n]') { return }
        if ($line -match '[^\x20-\x7E]') { return }

        $width = 0
        try { $width = [Console]::BufferWidth } catch { return }
        if ($width -lt 2) { return }

        $savedX = [Console]::CursorLeft
        $savedY = [Console]::CursorTop
        $startColumn = $savedX - $cursor

        # Do not repaint if the prompt/input wraps or cursor math is uncertain.
        if ($startColumn -lt 0 -or ($startColumn + $line.Length) -ge $width) { return }

        Update-PDEIndex | Out-Null
        $map = Get-PDELineColorMap -Text $line
        $esc = [char]27
        $palette = @(
            "$esc[90m",     # Neutral
            "$esc[93;1m",   # Yellow: known/unused match or separator
            "$esc[91;1m",   # Red: incorrect typed command character
            "$esc[92;1m"    # Green: matched indexed-history command character
        )

        [Console]::SetCursorPosition($startColumn, $savedY)
        $index = 0
        while ($index -lt $line.Length) {
            $colour = [int]$map[$index]
            if ($colour -lt 0 -or $colour -gt 3) { $colour = 0 }
            $runEnd = $index + 1
            while ($runEnd -lt $line.Length -and $map[$runEnd] -eq $colour) {
                $runEnd++
            }
            [Console]::Write($palette[$colour])
            [Console]::Write($line.Substring($index, $runEnd - $index))
            [Console]::Write("$esc[0m")
            $index = $runEnd
        }

        [Console]::SetCursorPosition($savedX, $savedY)
    }
    catch {
        Write-PDELog -Level WARN -Message ("Live highlighting skipped: {0}" -f $_.Exception.Message)
        try {
            if ($null -ne $savedX -and $null -ne $savedY) {
                [Console]::SetCursorPosition($savedX, $savedY)
            }
        }
        catch { }
    }
}

function global:Install-PDELiveHighlightHandlers {
    [CmdletBinding()]
    param()

    # SelfInsert is the PSReadLine API for normal character insertion. It keeps
    # native quote/bracket pairing and other SelfInsert behaviour intact.
    $typeAction = {
        param($key, $arg)
        [Microsoft.PowerShell.PSConsoleReadLine]::SelfInsert($key, $arg)
        Invoke-PDELiveHighlight
    }

    $printableChars = @(32..126 | ForEach-Object { [string][char]$_ })
    try {
        Set-PSReadLineKeyHandler -Chord $printableChars -ScriptBlock $typeAction -ErrorAction Stop
    }
    catch {
        foreach ($character in $printableChars) {
            try {
                Set-PSReadLineKeyHandler -Chord $character -ScriptBlock $typeAction -ErrorAction Stop
            }
            catch { }
        }
    }

    Set-PSReadLineKeyHandler -Chord 'Backspace' -ScriptBlock {
        param($key, $arg)
        [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
        Invoke-PDELiveHighlight
    }

    try {
        Set-PSReadLineKeyHandler -Chord 'Delete' -ScriptBlock {
            param($key, $arg)
            [Microsoft.PowerShell.PSConsoleReadLine]::DeleteChar($key, $arg)
            Invoke-PDELiveHighlight
        } -ErrorAction Stop
    }
    catch { }

    Set-PSReadLineKeyHandler -Chord 'Tab' -ScriptBlock {
        param($key, $arg)
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompleteNext($key, $arg)
        Invoke-PDELiveHighlight
    }

    Set-PSReadLineKeyHandler -Chord 'Shift+Tab' -ScriptBlock {
        param($key, $arg)
        [Microsoft.PowerShell.PSConsoleReadLine]::TabCompletePrevious($key, $arg)
        Invoke-PDELiveHighlight
    }

    # Word-deletion wrappers preserve the native PSReadLine edit operation and
    # redraw only after the buffer has been changed.
    $backwardWordDelete = {
        param($key, $arg)
        [Microsoft.PowerShell.PSConsoleReadLine]::BackwardKillWord($key, $arg)
        Invoke-PDELiveHighlight
    }
    foreach ($chord in @('Ctrl+w', 'Ctrl+Backspace', 'Alt+Backspace')) {
        try {
            Set-PSReadLineKeyHandler -Chord $chord -ScriptBlock $backwardWordDelete -ErrorAction Stop
        }
        catch {
            Write-PDELog -Level WARN -Message ("Could not install {0} highlight handler: {1}" -f $chord, $_.Exception.Message)
        }
    }

    $forwardWordDelete = {
        param($key, $arg)
        [Microsoft.PowerShell.PSConsoleReadLine]::KillWord($key, $arg)
        Invoke-PDELiveHighlight
    }
    try {
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Delete' -ScriptBlock $forwardWordDelete -ErrorAction Stop
    }
    catch {
        Write-PDELog -Level WARN -Message ("Could not install Ctrl+Delete highlight handler: {0}" -f $_.Exception.Message)
    }

    # Paste is treated as one operation: suspend repainting, let PSReadLine
    # insert the whole clipboard, then repaint once when safe to do so.
    Set-PSReadLineKeyHandler -Chord @('Ctrl+v', 'Shift+Insert') -ScriptBlock {
        param($key, $arg)

        $global:PDE_State.PasteInProgress = $true
        $pasteCompleted = $false
        try {
            [Microsoft.PowerShell.PSConsoleReadLine]::Paste()
            $pasteCompleted = $true
        }
        catch {
            Write-PDELog -Level WARN -Message ("Clipboard paste failed: {0}" -f $_.Exception.Message)
        }
        finally {
            $global:PDE_State.PasteInProgress = $false
        }

        if ($pasteCompleted) { Invoke-PDELiveHighlight }
    }

    # Up/Down retain the history/prediction bindings from Invoke-PDEApplyOptions.
    $global:PDE_State.LiveHighlightingEnabled = $true
    Write-PDELog -Level INFO -Message 'PDE live character-level command highlighting installed.'
}

# ---------------------------------------------------------------------------
