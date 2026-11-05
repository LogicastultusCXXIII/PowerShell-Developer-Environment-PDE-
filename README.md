# PowerShell Developer Environment (PDE)

**User guide for PDE 4.3.0-rc1 — live per-character command colours**

PDE adds command recognition, live green/orange/red/gray colouring, command suggestions, syntax analysis and session-based success learning to a PowerShell console.

This release uses a bundled editor derived from PSReadLine 2.3.6. Its renderer applies command colours while you type and handles the editing buffer, cursor and redraw together.

The compact release contains 13 files. On Linux PowerShell 7.4.6, 56 automated checks and 20 dedicated colour checks passed. Five Windows or interactive checks were skipped. Both editor DLLs compiled successfully. Windows installation and on-screen rendering still need local verification.

## Contents

- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Installation and portable use](#installation-and-portable-use)
- [How the colours work](#how-the-colours-work)
- [Everyday commands](#everyday-commands)
- [Suggestions and syntax checking](#suggestions-and-syntax-checking)
- [History: view, clear and stop saving](#history-view-clear-and-stop-saving)
- [Configuration](#configuration)
- [Keyboard controls and custom shortcuts](#keyboard-controls-and-custom-shortcuts)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Upgrading and uninstalling](#upgrading-and-uninstalling)
- [Where to edit the colouring system](#where-to-edit-the-colouring-system)
- [Project files](#project-files)
- [Known limitations and privacy](#known-limitations-and-privacy)

## Quick start

1. Extract **all** release files into one folder.
2. Close existing PDE PowerShell windows before upgrading.
3. Double-click **`Install-PDE.cmd`**.
4. Read the edition-specific installation results.
5. Open a **fresh PowerShell console**.
6. Check:

```powershell
Get-PDEStatus | Format-List
```

Look for:

| Field | Expected result |
|---|---|
| `Version` | `4.3.0-rc1` |
| `Running` | `True` |
| `Interactive` | `True` in a supported interactive console |
| `LiveHighlightingEnabled` | `True` |
| `DiscoveryHealthy` | `True` after successful command discovery |
| `ColouringStatus` | Reports that the live editor is active |

Type `Get-Dtae` without pressing Enter. With `Get-Date` as the closest indexed command, `Get-D` and the final `e` appear green. The swapped `t` and `a` appear orange. Correct the spelling to `Get-Date` and the whole name turns green, even on first use. Press **Ctrl+C** to clear the line.

## Requirements

| Environment | Live-editor requirement |
|---|---|
| Windows PowerShell | Version 5.1; bundled Desktop editor targets .NET Framework 4.6.2 |
| PowerShell Core | Version 7.4 or later; bundled Core editor targets .NET 8 |
| Terminal | Interactive console with suitable ANSI/VT colour support |
| Permissions | Current-user installation; administrator rights are not normally needed |
| Network | No runtime downloads required for PDE installation |

PowerShell 7 is optional if you use Windows PowerShell 5.1. Installing PDE does not install PowerShell itself. PowerShell 7.0–7.3 do not meet this live-editor build's requirements.

IDE output panels, redirected input/output and noninteractive script runners are not live console editors. ISE and host-specific profile integration are not configured automatically.

## Installation and portable use

### One-click installation

Double-click `Install-PDE.cmd` from the extracted folder. The default Windows installation directory is:

```text
%LOCALAPPDATA%\PDE
```

The installer validates release files, copies them, creates unique backups for changed existing files, and adds a managed startup block to the detected editions' current-user console profiles. It preserves unrelated profile content. Installation attempts to roll back completed writes if a later write fails.

If scripts or DLLs are marked as downloaded, the installer may ask whether to trust and unblock them. A user-level `RemoteSigned` execution-policy change, when needed, requires consent. Organization policies are not bypassed.

If only Windows PowerShell was configured, use that edition. When PowerShell 7 is installed in an unusual portable location, set its executable path and rerun setup from PowerShell:

```powershell
# Replace this example path with your real pwsh.exe path.
$env:PDE_PWSH_PATH = 'D:\Tools\PowerShell\pwsh.exe'
& '.\Install-PDE.cmd'
```

Detection checks PATH, common per-user/machine locations, WinGet links and registry entries. Detection of a PowerShell 7 executable does not establish that it meets the live editor's 7.4 minimum.

### Portable use without profile installation

Open a console in the extracted release folder:

```powershell
. .\PDE.ps1
Get-PDEStatus
```

The dot and following space are required: dot-sourcing makes PDE's commands available in the current session. For a path containing spaces:

```powershell
. 'C:\My Tools\PDE\PDE.ps1'
```

### Install through PowerShell

From the complete extracted release folder:

```powershell
. .\PDE.ps1 -NoStart
Install-PDE
```

This installs for the current PowerShell host. The CMD installer handles both detected console editions. Preview changes with:

```powershell
Install-PDE -WhatIf
```

Choose another installation directory if necessary:

```powershell
Install-PDE -DestinationDirectory (Join-Path $HOME 'Tools\PDE')
```

Keep every application file together in a single flat folder.

## How the colours work

PDE checks command names as you type. These examples use `Get-Date` as the target.

| Colour | When it appears | Example |
|---|---|---|
| Green | A typed character matches the target at the same position, ignoring case. Known commands and exact prefixes are green immediately. | Every letter of `Get-Dat` is green. |
| Orange | A misplaced letter is still available elsewhere in the target. Orange also marks uncertain command resolution. | The `t` and `a` in `Get-Dtae` are orange. |
| Red | A typed letter has no remaining match. If PDE finds no close command and discovery is healthy, the whole unknown name is red. | The `x` in `Get-Datx` is red. |
| Gray | The inline predictor offers text beyond what you typed. | If you type `Get-D` and the editor suggests `ate`, only the suggested suffix appears gray. |

Exact positions take priority. For example, when the target is `ssh` and you type `shh`, the first `s` and final `h` are green. The middle `h` is red because the target’s only `h` already has an exact match. In the live editor, ordinary arguments, switches, pipes and spaces use the terminal’s normal foreground. The standalone preview shows neutral text in gray.

For an unfamiliar spelling, PDE compares nearby command names. It favours lower edit distance, then a longer matching prefix, then a name that succeeded in this session, then alphabetical order. Your installed commands can therefore affect which target is selected. When discovery is unavailable, PDE treats unresolved input as uncertain. Paths and module-qualified names can also appear orange.

### Enable or disable live colours

```powershell
Enable-PDELiveHighlight
Disable-PDELiveHighlight
```

Disabling live mode restores the native host reader. To change PDE's preference for future starts in this session:

```powershell
Set-PDEOptions -EnableLiveHighlight $false
Set-PDEOptions -EnableLiveHighlight $true
```

A standalone preview is also available:

```powershell
Show-PDEHighlight 'Get-Date | FakeCommand -Name test'
```

The preview does not execute the string. It is separate from live editing and cannot, by itself, prove that the live editor is running.

## Everyday commands

| Command | Purpose |
|---|---|
| `Get-PDEStatus` | Version, live-editor state, discovery, learning, timings and last error |
| `Get-PDEDiagnostics` | Status plus host/OS information and diagnostic guidance |
| `Get-PDEStatistics` | Current PDE status/statistics snapshot |
| `Get-PDEHelp` | Lists the main PDE commands |
| `Get-PDESuggestions` | Prefix and typo suggestions |
| `Get-PDECommandAnalysis` | AST command recognition and parse diagnostics |
| `Test-PDESyntax` | Valid/incomplete/invalid syntax result |
| `Show-PDEHighlight` | Non-executing coloured preview |
| `Update-PDEIndex -Force` | Rediscover commands after environment/tool/module changes |
| `Update-PDEHistory` | Reports session learning state; does not import history files |
| `Clear-PDEHistory` | Clears PDE's learned successful names |
| `Enable-PDEPromptLearning` | Enables prompt-based learning in an interactive session |
| `Disable-PDEPromptLearning` | Restores PDE's original prompt when PDE still owns it |
| `Set-PDEOptions` | Updates PDE's session settings |
| `Stop-PDE` | Stops PDE and restores its owned reader/prompt/prediction settings |
| `Start-PDE` | Starts PDE again |
| `Start-PDE -Force` | Reinitialises PDE state; learned successes are reset |
| `Install-PDE` / `Uninstall-PDE` | Manage current-host profile integration |
| `Test-PDE` | Runs automated tests in a disposable child process |

Inspect an error clearly:

```powershell
Get-PDEStatus | Format-List Version, Running, Interactive, LiveHighlightingEnabled,
    ColouringStatus, DiscoveryHealthy, PromptLearningEnabled, LastError
```

## Suggestions and syntax checking

### Prefix and typo suggestions

```powershell
Get-PDESuggestions -Prefix 'Get-Pro' -Limit 5
Get-PDESuggestions -Prefix 'Get-Proccess' -Fuzzy -Limit 3
Get-PDESuggestions -Prefix 'Get-' -Source Command -Limit 10
Get-PDESuggestions -Prefix 'Get-' -Source History -Limit 10
```

`Source` accepts `All`, `Command` or `History`. PDE's history source contains learned command names, not full argument-bearing command lines. Exact valid commands produce no correction. Suggestions never automatically execute or replace your input.

### Live-editor history predictions

When live mode is active, configure its prediction setting directly:

```powershell
Set-PDELivePSReadLineOption -PredictionSource History
Set-PDELivePSReadLineOption -PredictionSource None
```

History prediction uses editor history and can include failed commands; it is separate from session success learning. `Set-PDEOptions -EnablePredictions` manages native PSReadLine prediction settings, so use the prefixed commands above for the active live editor.

### Syntax analysis

Pass text in quotes so it is analysed rather than executed:

```powershell
Get-PDECommandAnalysis -Text 'Get-Date | FakeCommand'
Test-PDESyntax -Text 'Get-Date'
Test-PDESyntax -Text 'if ($true) {'
Test-PDESyntax -Text 'Get-Date | |'
```

`Test-PDESyntax` returns `IsValid`, `IsIncomplete`, `Errors`, `CommandCount` and `UnknownCommands`. An unfinished brace or quote can be incomplete input rather than a completed invalid command. Syntax validity does not establish that execution will succeed or that arguments are appropriate.

## History: view, clear and stop saving

There are **four different history stores**. Clearing one does not automatically clear the others.

| Store | Contains | How to clear |
|---|---|---|
| PDE success memory | Successful command names used in suggestion and colour-target ranking | `Clear-PDEHistory` |
| PowerShell session history | Entries returned by `Get-History` | `Clear-History` |
| Editor memory | Up-arrow/search history in native/live editors | Each editor's `ClearHistory()` API |
| Editor history file | Command text saved between console sessions | Clear the selected file explicitly |

`Clear-Host` or `cls` only clears the display. It does not erase these history stores.

### Clear PDE’s learned command names

```powershell
Clear-PDEHistory
```

Colours refresh when the next editable line starts. Commands you execute after clearing can immediately become learned again, including management commands.

To clear learning and keep it disabled:

```powershell
Set-PDEOptions -EnablePromptLearning $false
Clear-PDEHistory
```

Enable learning again when wanted:

```powershell
Set-PDEOptions -EnablePromptLearning $true
```

### View PowerShell history and history locations

```powershell
Get-History
(Get-PSReadLineOption).HistorySavePath
```

With live mode enabled, also check its actual path:

```powershell
(Get-PDELivePSReadLineOption).HistorySavePath
```

Paths can differ by edition or configuration. Avoid posting history contents publicly; they may contain private paths, arguments or secrets.

### Clear current-session command and editor memory

These commands do not erase saved history files:

```powershell
Clear-History

# Native PSReadLine memory, when the module is loaded.
if (Get-Module PSReadLine) {
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
}

# PDE live-editor memory, once its type has been loaded.
if ('PDE.PowerShell.PSConsoleReadLine' -as [type]) {
    [PDE.PowerShell.PSConsoleReadLine]::ClearHistory()
}

Clear-PDEHistory
```

### Stop future history saving for this session

Set both editors so switching modes does not unexpectedly restore saving. Setting native `SaveNothing` also causes PDE's learning code to decline new success entries.

```powershell
Set-PSReadLineOption -HistorySaveStyle SaveNothing

if (Get-Command Set-PDELivePSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PDELivePSReadLineOption -HistorySaveStyle SaveNothing
}

Set-PDEOptions -EnablePromptLearning $false
```

`SaveNothing` controls persistence; it does not erase old disk history and should not be treated as a guarantee of zero in-memory history or zero logging by other tools.

To stop new entries being added to both editors' history as well, an acceptance handler can be used:

```powershell
# Optional: replaces any existing custom history acceptance handler.
Set-PSReadLineOption -AddToHistoryHandler { $false }
if (Get-Command Set-PDELivePSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PDELivePSReadLineOption -AddToHistoryHandler { $false }
}
```

Use a fresh console to recover your normal profile-defined handlers; do not reset handlers blindly if you had a custom secret-filtering policy.

### Erase saved history files

**This permanently removes the command text from the selected files.** Close other PowerShell windows first: another process can write history back. Repeat for each edition/custom history path you intend to clear. This does not erase transcripts, logs, backups or history elsewhere.

Run the following in the one console you have kept open. It collects the configured paths, disables saving and learning, then empties those files and the current history stores:

```powershell
$historyPaths = @((Get-PSReadLineOption).HistorySavePath)
if (Get-Command Get-PDELivePSReadLineOption -ErrorAction SilentlyContinue) {
    $historyPaths += (Get-PDELivePSReadLineOption).HistorySavePath
}
$historyPaths = @($historyPaths | Where-Object { $_ } | Sort-Object -Unique)

# Review the exact files before clearing them.
$historyPaths
```

After reviewing those paths, run:

```powershell
Set-PSReadLineOption -HistorySaveStyle SaveNothing
if (Get-Command Set-PDELivePSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PDELivePSReadLineOption -HistorySaveStyle SaveNothing
}
Set-PDEOptions -EnablePromptLearning $false

foreach ($historyFile in $historyPaths) {
    if ([IO.File]::Exists($historyFile)) {
        [IO.File]::WriteAllText($historyFile, '')
    }
}

Clear-History
if (Get-Module PSReadLine) {
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
}
if ('PDE.PowerShell.PSConsoleReadLine' -as [type]) {
    [PDE.PowerShell.PSConsoleReadLine]::ClearHistory()
}
Clear-PDEHistory
```

Close that console afterward. New commands and newly opened consoles may build history again according to their settings.

### Resume normal saving

If you disabled saving and want incremental saving again:

```powershell
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
if (Get-Command Set-PDELivePSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PDELivePSReadLineOption -HistorySaveStyle SaveIncrementally
}
Set-PDEOptions -EnablePromptLearning $true
```

This does not restore a replaced `AddToHistoryHandler`; reopen a fresh console or restore the handler you previously saved.

## Configuration

PDE options are session-only unless you add your choices to your profile.

| `Set-PDEOptions` parameter | Default | Allowed values / purpose |
|---|---|---|
| `EnableLiveHighlight` | `$true` | Enables/disables live editor |
| `EnablePromptLearning` | `$true` | Enables/disables success learning |
| `EnablePredictions` | `$true` | Native PSReadLine prediction preference |
| `EnableFuzzySuggestions` | `$true` | Allows fuzzy results in PDE suggestions |
| `FuzzyMaximumDistance` | `2` | Integer `1`–`4` |
| `HistoryIndexLimit` | `1500` | Integer `1`–`20000`; learned-name limit |
| `CommandRefreshSeconds` | `600` | Integer `10`–`3600`; full discovery throttle |
| `EnableDiagnosticsLog` | `$false` | Enables best-effort diagnostic logging |
| `DiagnosticsLogPath` | `$HOME\PDE-diagnostics.log` | Log destination; parent directory must exist |

Examples:

```powershell
Set-PDEOptions -FuzzyMaximumDistance 2 -CommandRefreshSeconds 300
Set-PDEOptions -EnablePromptLearning $false
Set-PDEOptions -EnableLiveHighlight $true
Set-PDEOptions -EnableDiagnosticsLog $true `
    -DiagnosticsLogPath (Join-Path $HOME 'PDE-diagnostics.log')
```

Inspect current preferences:

```powershell
$global:PDE_Config
```

Use `Set-PDEOptions` to change them rather than editing the state tables directly. Reducing `HistoryIndexLimit` does not immediately trim all existing entries; clear history or restart PDE to apply a smaller cap cleanly.

### Keep preferences between sessions

Open the current host's profile:

```powershell
notepad $PROFILE.CurrentUserCurrentHost
```

Add your own choices **after** the managed PDE loader block. Do not edit inside its markers:

```powershell
# My PDE preferences
Set-PDEOptions -FuzzyMaximumDistance 2 -CommandRefreshSeconds 300 | Out-Null

if ((Get-PDEStatus).LiveHighlightingEnabled) {
    Set-PDELivePSReadLineOption -PredictionSource History
}
```

The Windows PowerShell and PowerShell 7 profile paths are separate. Apply preferences to the editions you use. If setup has not created a profile yet, run installation first.

## Keyboard controls and custom shortcuts

Bindings depend on the editor's edit mode and your configuration. Typical controls include Enter to submit, Ctrl+C to cancel, arrows to move, Home/End to navigate a line, Backspace/Delete to remove characters, Tab/Shift+Tab for completion, and Shift+Enter for multiline input.

Inspect the active live-editor bindings:

```powershell
Get-PDELivePSReadLineKeyHandler -Bound
Get-PDELivePSReadLineOption
```

Named native bindings are copied where supported. Custom native script handlers remain attached to the native editor and are not safely transferable through its public enumeration API. Register live handlers explicitly:

```powershell
Set-PDELivePSReadLineKeyHandler -Chord F8 -ScriptBlock {
    [PDE.PowerShell.PSConsoleReadLine]::Insert('CUSTOM')
}
```

Remove that live binding:

```powershell
Remove-PDELivePSReadLineKeyHandler -Chord F8
```

Removing a binding does not recreate a previous one. Use the appropriate `-Function` binding to restore a known function or start a fresh process.

**Use the matching editor API:** live handlers call `[PDE.PowerShell.PSConsoleReadLine]`; native handlers call `[Microsoft.PowerShell.PSConsoleReadLine]`. Calling the native API from a live handler edits the wrong buffer.

`Disable-PDELiveHighlight` returns to the native reader and its native settings/bindings. Enable live mode after any profile framework that replaces `PSConsoleHostReadLine`; a later replacement can otherwise take over the reader.

## Testing

### Dedicated colour tests

From the extracted folder, run `pwsh.exe -NoProfile -File .\Test-PDE.ps1 -Coloring`. For Windows PowerShell 5.1 use `powershell.exe` in place of `pwsh.exe`. This runs the PowerShell colour-map checks in a fresh process, including swapped letters, duplicate letters and quoted commands.

### Automated tests

Run from the complete extracted release folder, in disposable processes:

```powershell
powershell.exe -NoLogo -NoProfile -File .\Test-PDE.ps1
pwsh.exe -NoLogo -NoProfile -File .\Test-PDE.ps1
```

Use only the engines actually installed. Save individual reports:

```powershell
powershell.exe -NoProfile -File .\Test-PDE.ps1 -ReportPath .\results-5.1.json
pwsh.exe -NoProfile -File .\Test-PDE.ps1 -ReportPath .\results-7.json
```

The test script exits with `0` when its executable checks pass and `1` on failure. Check `$LASTEXITCODE` immediately afterward. A zero exit code does not turn SKIP into PASS or certify production readiness.

From a running PDE session, the wrapper launches a child test process:

```powershell
Test-PDE
$result = Test-PDE -Quiet
$result | Select-Object Passed, PassedCount, FailedCount, SkippedCount, ProductionReady
$result.Checks | Where-Object Status -eq 'FAIL'
```

Do not dot-source the standalone test scripts into your everyday session; they intentionally exercise temporary configuration and process exit paths.

Tests cover command maps/classification, parsing, discovery, suggestions, history privacy, lifecycle, live backend loading/restoration, and sandbox install/upgrade/uninstall/rollback. Automated setup checks use temporary profile paths, not your real profile.

### Guided terminal tests

Run each installed edition in a disposable console:

```powershell
powershell.exe -NoProfile -File .\Test-PDE.ps1 -Interactive -ReportPath .\terminal-5.1.json
pwsh.exe -NoProfile -File .\Test-PDE.ps1 -Interactive -ReportPath .\terminal-7.json
```

The guide returns typed test text as data, compares buffers and asks about visible behaviour. Its history saving is suppressed. It disables prompt learning while you exercise the editor.

Manually check:

1. Exact, swapped and incorrect letters using the quick-start example. Check the gray suffix separately when an inline suggestion appears.
2. Red-to-orange/green transitions while correcting a name.
3. Rapid typing, cursor movement, Backspace/Delete and selection.
4. Copy/paste, Unicode, long wrapped lines and multiline input.
5. Up/Down history, Tab completion, custom shortcuts and resizing.
6. Repeated live-mode enable/disable and native reader restoration.
7. Custom prompt frameworks and background/asynchronous output used in your environment.

Some guided checks require explicit `y/n/s` observer answers. `s` means unverified.

## Troubleshooting

| Symptom | Check / action |
|---|---|
| No live colours | Run `Get-PDEStatus`; check `Interactive`, `LiveHighlightingEnabled`, `ColouringStatus`, `LastError` |
| `Get-PDEStatus` is not recognised | Profile did not load PDE, wrong edition/host profile, or a profile error occurred; dot-source `PDE.ps1` from the extracted folder to isolate it |
| Earlier version still appears | Close all old consoles and open a fresh one; loaded DLLs cannot be replaced in an existing process |
| `PowerShell 7 not found` | Windows PowerShell can still work; if 7 is installed elsewhere, set `PDE_PWSH_PATH` and rerun setup |
| PowerShell 7.0–7.3 detected | This Core binary requires 7.4+; use Windows PowerShell 5.1 or a compatible installed Core version |
| DLL/script blocked | Read installer trust prompts and policy errors; trust/unblock only files you reviewed; organization policy remains authoritative |
| Valid command is red | Run `Update-PDEIndex -Force` after installing tools/importing modules; inspect `DiscoveryHealthy` |
| Exact letters do not turn green | Check that `ColouringStatus` reports character highlighting. After an upgrade, open a fresh PowerShell process and check again. |
| A different command is chosen | Use `Get-PDESuggestions` to inspect nearby names and `Update-PDEIndex -Force` to refresh the command index. |

| Old commands remain after Clear-PDEHistory | That clears PDE’s learned command names; clear PowerShell/editor memory or files separately |
| Predictions do not change | Configure the active live editor with `Set-PDELivePSReadLineOption`; PDE's general prediction option addresses the native editor |
| Custom shortcut does nothing | Register it with `Set-PDELivePSReadLineKeyHandler` and the PDE editor type |
| Prompt framework takes over the reader | Call `Enable-PDELiveHighlight` after its setup; disable PDE learning if its status capture conflicts |
| Overlap or cursor problems | `Disable-PDELiveHighlight`, then use a fresh console; record engine/terminal/version and diagnostics for investigation |

Useful diagnostics:

```powershell
$PSVersionTable
Get-PDEStatus | Format-List
Get-PDEDiagnostics | Format-List
Get-PDELivePSReadLineOption | Format-List
Get-PDELivePSReadLineKeyHandler -Bound
Get-ExecutionPolicy -List
```

Review diagnostic output before sharing it; paths and configuration may be private.

## Upgrading and uninstalling

### Upgrade

1. Close all PDE consoles.
2. Extract the complete replacement release into one folder.
3. Run its `Install-PDE.cmd`.
4. Open a fresh console and check `Get-PDEStatus`.
5. Run tests appropriate to your engine and terminal.

Backups have unique `.pde.<id>.bak` filenames. Keep them until the new build is verified. Avoid opening terminals during the multi-file upgrade. Unmarked handwritten profile loader lines are not removed automatically; check for duplicate manual imports if an old version still loads.

### Stop PDE in the current session

```powershell
Stop-PDE
```

Restart without reinstalling:

```powershell
Start-PDE
```

PDE-prefixed functions remain defined after stopping. Stopping restores owned hooks/settings; it does not remove profile startup integration or unload DLLs from the process.

### Remove startup integration

Run `.\Install-PDE.cmd uninstall` from PowerShell in the extracted folder to handle detected editions. For the current host only:

```powershell
Uninstall-PDE -WhatIf
Uninstall-PDE
```

It removes PDE-managed profile blocks and creates profile backups. Installed files, unrelated profile content and backups remain. It does not revert a user-approved execution-policy change or erase personal history. After closing all PDE processes, you may manually remove the dedicated installation folder if you no longer need it.

## Project files

### Where to edit the colouring system

**Start with `PDE.CharacterColoring.cs`.** Open `ComparePositions(typed, target)` to change the green, orange and red rules. The first loop reserves exact matches. The second loop visits the remaining typed letters and assigns orange while a matching target letter is available. Open `Map` to change how PDE chooses the target or treats known prefixes.

| To change | Edit |
|---|---|
| Which letters count as correct, misplaced or incorrect | `PDE.CharacterColoring.cs` → `ComparePositions` |
| Which command a typo is compared with | `PDE.CharacterColoring.cs` → `Map` |
| Standalone preview colours or display | `PDE.ps1` → `Show-PDEHighlight` |
| Live colour shades or where command letters are painted | Inside `PDE.Editor.Source.zip`, open `PDE.CommandColors.cs` → `Palette` or `Prepare` |
| Gray inline prediction shade | Inside the same archive, open `Prediction.Views.cs` and search for `\x1b[90m` |

**Test a rule change** with the dedicated colour tests above. To use the change while typing, extract the editor source and copy your edited `PDE.CharacterColoring.cs` over its copy. Follow `BUILD-NOTES.txt` inside that archive to configure the build dependencies and build `Core.csproj` and `Desktop.csproj` separately. Package the Core build’s `PDE.Editor.dll` as `PDE.Editor.Core.dll` and the Desktop build as `PDE.Editor.Desktop.dll`. Refresh the source archive and release checksums when redistributing. Close existing consoles, reinstall and open a new console to load the rebuilt editor.

### Release contents

| File | Responsibility |
|---|---|
| `PDE.ps1` | PowerShell entry point. Named regions contain startup, command discovery, history, suggestions, analysis, colouring, live-editor integration, diagnostics, tests and installation. |
| `PDE.CharacterColoring.cs` | Shared per-character matching and target-selection rules. |
| `PDE.Editor.Core.dll` | Live editor for PowerShell 7.4 and later. |
| `PDE.Editor.Desktop.dll` | Live editor for Windows PowerShell 5.1. |
| `Microsoft.PowerShell.Pager.dll` | Editor help dependency. |
| `System.Runtime.InteropServices.RuntimeInformation.dll` | Desktop runtime dependency. |
| `PDE.Editor.Source.zip` | Editor source, both project files and build notes. |
| `Install-PDE.cmd` | Windows launcher for setup and removal. |
| `Setup-PDE.ps1` | Runs setup for the requested PowerShell editions. |
| `Test-PDE.ps1` | Automated suite, dedicated colour tests and guided interactive checks. |
| `README.md` | This guide. |
| `SHA256SUMS.txt` | SHA-256 hashes for the other release files. |
| `LICENSE` | Project licence and bundled third-party notices. |

## Known limitations and privacy

- Success learning observes PowerShell's reported outcome, not application-level correctness. A function can mask internal failures.
- PDE success history is bounded, names-only and session-only. PDE does not import or repair your personal history files.
- Editor history can still save full commands according to its settings. Secret-pattern filtering for PDE learning does not guarantee removal from native/live history, transcripts or other logs.
- The native and live editors have separate settings and memory; configure and clear both when appropriate.
- Custom native script key bindings require explicit live registration.
- Prompt learning calls the original prompt once, but arbitrary `$?`-dependent prompt code may need `$global:PDE_LastCommandSucceeded`. `$global:PDE_LastNativeExitCode` contains the captured native exit code.
- Custom history acceptance handlers are called again for learning eligibility. Disable PDE learning if such a handler has side effects.
- Unsupported hosts and load failures fall back to native editing with diagnostic status. Some profiles can subsequently replace the host reader.
- Windows compatibility and terminal behaviour require local verification. Do not interpret passing map tests or compiled DLLs as Windows visual certification.

The modified editor is derived from Microsoft PowerShell PSReadLine 2.3.6 under its MIT license. PDE's supplied license and third-party notices remain part of the release.
