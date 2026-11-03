# 7. Fuzzy matching and suggestion inspection
# ---------------------------------------------------------------------------
function global:Get-PDELevenshteinDistance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )

    $a = $Left.ToLowerInvariant()
    $b = $Right.ToLowerInvariant()
    $n = $a.Length
    $m = $b.Length

    if ($n -eq 0) { return $m }
    if ($m -eq 0) { return $n }

    $previous = New-Object 'int[]' ($m + 1)
    $current  = New-Object 'int[]' ($m + 1)
    for ($j = 0; $j -le $m; $j++) { $previous[$j] = $j }

    for ($i = 1; $i -le $n; $i++) {
        $current[0] = $i
        for ($j = 1; $j -le $m; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $deletion = $previous[$j] + 1
            $insertion = $current[$j - 1] + 1
            $substitution = $previous[$j - 1] + $cost
            $current[$j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }
        $temporary = $previous
        $previous = $current
        $current = $temporary
    }

    return $previous[$m]
}

function global:Get-PDESuggestions {
    [CmdletBinding()]
    param(
        [string]$Prefix = '',
        [ValidateSet('All','History','Command')][string]$Source = 'All',
        [ValidateRange(1,100)][int]$Limit = 10,
        [switch]$Fuzzy
    )

    if ($Source -in @('All','History')) {
        Update-PDEHistory | Out-Null
    }
    if ($Source -in @('All','Command')) {
        Update-PDEIndex | Out-Null
    }

    $results = [System.Collections.Generic.List[object]]::new()

    if ($Source -in @('All','History')) {
        $rank = 0
        foreach ($entry in $global:PDE_State.History) {
            $rank++
            if ([string]::IsNullOrEmpty($Prefix) -or $entry.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add([pscustomobject]@{
                    Suggestion = $entry
                    Source     = 'History'
                    MatchType  = 'Prefix'
                    Distance   = 0
                    Rank       = $rank
                })
            }
        }
    }

    if ($Source -in @('All','Command')) {
        foreach ($name in $global:PDE_State.CommandNames) {
            if ([string]::IsNullOrEmpty($Prefix) -or $name.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add([pscustomobject]@{
                    Suggestion = $name
                    Source     = 'Command'
                    MatchType  = 'Prefix'
                    Distance   = 0
                    Rank       = 0
                })
            }
        }

        if (($Fuzzy -or $global:PDE_Config.EnableFuzzySuggestions) -and $Prefix.Length -ge 3) {
            $maxDistance = [int]$global:PDE_Config.FuzzyMaximumDistance
            foreach ($name in $global:PDE_State.CommandNames) {
                if ($name.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $distance = Get-PDELevenshteinDistance -Left $Prefix -Right $name
                if ($distance -le $maxDistance) {
                    $results.Add([pscustomobject]@{
                        Suggestion = $name
                        Source     = 'Command'
                        MatchType  = 'Fuzzy'
                        Distance   = $distance
                        Rank       = 0
                    })
                }
            }
        }
    }

    $unique = $results |
        Sort-Object -Property @{ Expression = 'Distance'; Ascending = $true }, @{ Expression = 'Rank'; Ascending = $true }, @{ Expression = 'Suggestion'; Ascending = $true } |
        Group-Object -Property Suggestion |
        ForEach-Object { $_.Group | Select-Object -First 1 }

    $unique | Select-Object -First $Limit
}

# ---------------------------------------------------------------------------
