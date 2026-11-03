# 6. AST-based syntax and command analysis
# ---------------------------------------------------------------------------
function global:Get-PDECommandAnalysis {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Text)

    process {
        Update-PDEIndex | Out-Null

        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Text,
            [ref]$tokens,
            [ref]$parseErrors
        )

        $commandAsts = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true))

        $commandResults = foreach ($commandAst in $commandAsts) {
            $commandName = $commandAst.GetCommandName()
            $isDynamic = [string]::IsNullOrWhiteSpace($commandName)
            $isRecognised = $false
            $commandType = $null
            $source = $null

            if (-not $isDynamic) {
                $isRecognised = $global:PDE_State.CommandNames.Contains($commandName)
                if ($global:PDE_State.CommandInfo.ContainsKey($commandName)) {
                    $commandType = [string]$global:PDE_State.CommandInfo[$commandName].CommandType
                    $source = [string]$global:PDE_State.CommandInfo[$commandName].Source
                }
            }

            [pscustomobject]@{
                Name         = if ($isDynamic) { $null } else { $commandName }
                IsRecognised = $isRecognised
                IsDynamic    = $isDynamic
                CommandType  = $commandType
                Source       = $source
                StartOffset  = $commandAst.Extent.StartOffset
                EndOffset    = $commandAst.Extent.EndOffset
            }
        }

        # Risk checks operate on parsed command nodes, not arbitrary text, so
        # mentioning a destructive command in a comment or quoted string does
        # not trigger a warning.
        $riskWarnings = [System.Collections.Generic.List[string]]::new()
        foreach ($commandAst in $commandAsts) {
            $riskName = $commandAst.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($riskName)) { continue }

            switch -Regex ($riskName) {
                '(?i)^(Remove-Item|rm|ri|del|erase|rmdir)$' {
                    $message = 'File or directory deletion command detected. Check the target path and options carefully.'
                    if (-not $riskWarnings.Contains($message)) { $riskWarnings.Add($message) }
                }
                '(?i)^(Clear-Disk|Format-Volume|Format-Partition|Remove-Partition|diskpart)$' {
                    $message = 'Disk or volume modification command detected. This may cause data loss.'
                    if (-not $riskWarnings.Contains($message)) { $riskWarnings.Add($message) }
                }
                '(?i)^(Restart-Computer|Stop-Computer|Stop-Service|Restart-Service|Stop-Process|taskkill)$' {
                    $message = 'System, service or process interruption command detected.'
                    if (-not $riskWarnings.Contains($message)) { $riskWarnings.Add($message) }
                }
                '(?i)^Set-ExecutionPolicy$' {
                    if ($commandAst.Extent.Text -match '(?i)\b(?:Unrestricted|Bypass)\b') {
                        $message = 'Permissive execution policy detected. Review the security implications.'
                        if (-not $riskWarnings.Contains($message)) { $riskWarnings.Add($message) }
                    }
                }
            }
        }

        [pscustomobject]@{
            IsSyntacticallyValid = (-not ($parseErrors -and $parseErrors.Count -gt 0))
            ParseErrors          = @($parseErrors | ForEach-Object { $_.Message })
            Commands             = @($commandResults)
            UnknownCommands      = @($commandResults | Where-Object { -not $_.IsDynamic -and -not $_.IsRecognised } | Select-Object -ExpandProperty Name -Unique)
            RiskWarnings         = @($riskWarnings.ToArray())
        }
    }
}

function global:Test-PDESyntax {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)][AllowEmptyString()][string]$Text)

    process {
        $analysis = Get-PDECommandAnalysis -Text $Text
        [pscustomobject]@{
            IsValid    = $analysis.IsSyntacticallyValid
            Errors     = $analysis.ParseErrors
            CommandCount = $analysis.Commands.Count
            UnknownCommands = $analysis.UnknownCommands
        }
    }
}

# ---------------------------------------------------------------------------
