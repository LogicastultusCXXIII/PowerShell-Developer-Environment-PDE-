#requires -Version 5.1
# Modified for PDE 4.3.0-rc1, 2026-11-04.
[CmdletBinding()]
param([switch]$Uninstall,[switch]$AllEditions)
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'PDE.ps1') -NoStart
    if($Uninstall){Uninstall-PDE | Format-List}
    else {Install-PDE | Format-List}
    Write-Host ('[OK] Configured '+$PSVersionTable.PSEdition+' PowerShell '+$PSVersionTable.PSVersion) -ForegroundColor Green
    if($AllEditions -and $PSVersionTable.PSEdition -eq 'Desktop') {
        $pwsh=Find-PDEPowerShell7
        if($pwsh) {
            Write-Host ('[FOUND] PowerShell 7: '+$pwsh)
            $env:PDE_SETUP_SCRIPT=Join-Path $PSScriptRoot 'Setup-PDE.ps1'
            $env:PDE_SETUP_REMOVE=[string][bool]$Uninstall
            $bootstrap={
                try {
                    $ErrorActionPreference='Stop'
                    if((Get-ExecutionPolicy) -in @('Restricted','AllSigned')) {
                        $managed=@(Get-ExecutionPolicy -List | Where-Object { $_.Scope -in @('MachinePolicy','UserPolicy') -and $_.ExecutionPolicy -ne 'Undefined' })
                        if($managed.Count){throw 'Organization policy prevents PDE setup in PowerShell 7.'}
                        $answer=Read-Host 'Allow CurrentUser RemoteSigned for PowerShell 7? [y/N]'
                        if($answer -notmatch '^(?i:y|yes)$'){throw 'PowerShell 7 setup cancelled; policy unchanged.'}
                        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
                    }
                    & $env:PDE_SETUP_SCRIPT -Uninstall:($env:PDE_SETUP_REMOVE -eq 'True')
                } catch { Write-Host $_ -ForegroundColor Red; exit 1 }
            }
            & $pwsh -NoLogo -NoProfile -Command $bootstrap.ToString()
            if($LASTEXITCODE -ne 0){throw 'PowerShell 7 was found, but its setup failed. Windows PowerShell setup succeeded.'}
        } else {
            Write-Host '[INFO] Windows PowerShell setup succeeded. No runnable PowerShell 7 installation was detected.' -ForegroundColor Yellow
            Write-Host 'PDE works in Windows PowerShell 5.1. PowerShell 7 is optional and is not installed by PDE.'
            Write-Host 'For a portable installation, set PDE_PWSH_PATH to its full pwsh.exe path and rerun this installer.'
        }
    }
    exit 0
} catch { Write-Host ('PDE setup failed: '+$_.Exception.Message) -ForegroundColor Red; exit 1 }
