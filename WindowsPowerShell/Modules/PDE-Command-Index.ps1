# 4. Command and executable index
# ---------------------------------------------------------------------------
function global:Update-PDEIndex {
    [CmdletBinding()]
    param([switch]$Force)

    $refreshMinutes = 10
    if (-not $Force -and $global:PDE_State.LastIndexUpdate) {
        $age = (Get-Date) - [datetime]$global:PDE_State.LastIndexUpdate
        if ($age.TotalMinutes -lt $refreshMinutes) {
            return [pscustomobject]@{
                Updated = $false
                Reason  = 'Index is still within its refresh interval.'
                Commands = $global:PDE_State.CommandNames.Count
                Prefixes = $global:PDE_State.CommandPrefixes.Count
                LastUpdated = $global:PDE_State.LastIndexUpdate
            }
        }
    }

    try {
        $commands = @(Get-Command -All -ErrorAction Stop)
        $global:PDE_State.CommandNames.Clear()
        $global:PDE_State.CommandPrefixes.Clear()
        $global:PDE_State.CommandInfo.Clear()

        foreach ($command in $commands) {
            $name = [string]$command.Name
            if ([string]::IsNullOrWhiteSpace($name)) { continue }

            [void]$global:PDE_State.CommandNames.Add($name)
            $global:PDE_State.CommandInfo[$name] = $command

            # Index extensionless executable/script names as an additional
            # convenient lookup, without changing the original command name.
            if ($name -match '\.(exe|com|cmd|bat|ps1)$') {
                try {
                    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($name)
                    if ($baseName) {
                        [void]$global:PDE_State.CommandNames.Add($baseName)
                        if (-not $global:PDE_State.CommandInfo.ContainsKey($baseName)) {
                            $global:PDE_State.CommandInfo[$baseName] = $command
                        }
                    }
                }
                catch { }
            }
        }

        foreach ($name in $global:PDE_State.CommandNames) {
            for ($length = 1; $length -le $name.Length; $length++) {
                [void]$global:PDE_State.CommandPrefixes.Add($name.Substring(0, $length))
            }
        }

        $global:PDE_State.LastIndexUpdate = Get-Date
        $global:PDE_State.LastError = $null
        Write-PDELog -Level INFO -Message ("Command index refreshed: {0} names." -f $global:PDE_State.CommandNames.Count)

        return [pscustomobject]@{
            Updated = $true
            Reason  = 'Command index rebuilt.'
            Commands = $global:PDE_State.CommandNames.Count
            Prefixes = $global:PDE_State.CommandPrefixes.Count
            LastUpdated = $global:PDE_State.LastIndexUpdate
        }
    }
    catch {
        $global:PDE_State.LastError = $_.Exception.Message
        Write-PDELog -Level ERROR -Message ("Command index update failed: {0}" -f $_.Exception.Message)
        Write-Warning "PDE could not refresh its command index: $($_.Exception.Message)"
    }
}

function global:Test-PDECommandName {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][string]$Name)

    process {
        if (-not $global:PDE_State.LastIndexUpdate) {
            Update-PDEIndex -Force | Out-Null
        }
        else {
            Update-PDEIndex | Out-Null
        }

        $known = $global:PDE_State.CommandNames.Contains($Name)
        [pscustomobject]@{
            Name        = $Name
            IsRecognised = $known
            CommandType = if ($global:PDE_State.CommandInfo.ContainsKey($Name)) {
                [string]$global:PDE_State.CommandInfo[$Name].CommandType
            } else { $null }
            Source      = if ($global:PDE_State.CommandInfo.ContainsKey($Name)) {
                [string]$global:PDE_State.CommandInfo[$Name].Source
            } else { $null }
        }
    }
}


function global:Test-PDEHistoryLineRecognised {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Line)

    # The persistent PSReadLine file does not store each command's exit code.
    # Only import entries whose static command names resolve in this session
    # (or whose command path exists). This prevents old failed inputs such as
    # "aaaaaaaaaaaa" from becoming green merely because they were once typed.
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }

    $tokens = $null
    $parseErrors = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Line, [ref]$tokens, [ref]$parseErrors
        )
        if ($parseErrors -and $parseErrors.Count -gt 0) { return $false }

        $commands = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true))
        if ($commands.Count -eq 0) { return $false }

        foreach ($commandAst in $commands) {
            $name = $commandAst.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($name)) { return $false }
            if ($global:PDE_State.CommandNames.Contains($name)) { continue }

            $isExistingPath = $false
            try {
                $isExistingPath = Test-Path -LiteralPath $name -PathType Leaf -ErrorAction SilentlyContinue
            } catch { }
            if (-not $isExistingPath) { return $false }
        }
        return $true
    }
    catch {
        return $false
    }
}

# ---------------------------------------------------------------------------
