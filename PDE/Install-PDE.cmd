@echo off
rem Modified for PDE 4.3.0-rc1. See README.md.
setlocal EnableExtensions DisableDelayedExpansion
set "PDE_SETUP_DIR=%~dp0"
set "PDE_SETUP_MODE=%~1"
set "PDE_RESULT=0"
echo PDE 4.3 release candidate - current-user setup
echo Live green/orange/red/gray command editor included.
echo No administrator permissions or downloads are required.
if not exist "%PDE_SETUP_DIR%Setup-PDE.ps1" (
  echo ERROR: Extract every release file into one folder first.
  set "PDE_RESULT=1"
  goto finish
)
call :setup "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if errorlevel 1 set "PDE_RESULT=1"
:finish
if "%PDE_RESULT%"=="0" (echo Setup finished. Review the edition-specific results above.) else (echo Setup incomplete. Read the errors above.)
pause
exit /b %PDE_RESULT%
:setup
if not exist "%~1" if /i not "%~1"=="pwsh.exe" exit /b 1
rem No execution-policy bypass. Any CurrentUser policy change requires consent.
"%~1" -NoLogo -NoProfile -Command "try { $ErrorActionPreference='Stop'; if ($PSVersionTable.PSVersion -lt [version]'5.1') { throw 'PowerShell 5.1 or newer is required.' }; $p=Get-ExecutionPolicy; if ($p -in @('Restricted','AllSigned')) { $list=Get-ExecutionPolicy -List; if (@($list | Where-Object { $_.Scope -in @('MachinePolicy','UserPolicy') -and $_.ExecutionPolicy -ne 'Undefined' }).Count) { throw 'Organization policy prevents unsigned PDE scripts. Ask your administrator.' }; $answer=Read-Host 'Allow local scripts with CurrentUser RemoteSigned? This changes your user policy [y/N]'; if ($answer -notmatch '^(?i:y|yes)$') { throw 'Policy unchanged; setup cancelled.' }; Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force }; $marked=@(Get-ChildItem -LiteralPath $env:PDE_SETUP_DIR -File | Where-Object { $_.Extension -in @('.ps1','.dll') } | Where-Object { Get-Item -LiteralPath $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue }); if($marked.Count) { $answer=Read-Host 'Trust and unblock the extracted PDE scripts in this folder? [y/N]'; if($answer -notmatch '^(?i:y|yes)$'){throw 'Files remain blocked; setup cancelled.'}; $marked | Unblock-File }; & (Join-Path $env:PDE_SETUP_DIR 'Setup-PDE.ps1') -Uninstall:($env:PDE_SETUP_MODE -eq 'uninstall') -AllEditions } catch { Write-Host $_ -ForegroundColor Red; exit 1 }"
exit /b %errorlevel%
