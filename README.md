# PowerShell Developer Environment (PDE)

## Command Intelligence v3.1.2
**Technical Documentation & User Guide**

A modular PowerShell command-intelligence component providing live command highlighting, history-backed predictive IntelliSense, command discovery, fuzzy suggestions, AST-based syntax analysis, command-risk inspection and enhanced PSReadLine integration.

| DOCUMENT DETAILS | VALUE |
|---|---|
| Main environment | PowerShell Developer Environment (PDE V2) |
| Component name | PDE Command Intelligence |
| Component version | 3.1.2 |
| Target shells | Windows PowerShell 5.1 and PowerShell 7+ |
| Primary dependency | PSReadLine |
| Architecture | Modular PowerShell scripts, dot-sourced into a shared session |
| Feature files | 9 |
| Main capabilities | Command indexing, history, AST analysis, fuzzy suggestions, live highlighting and keyboard integration |
| Document status | Updated against the supplied v3.1.2 source and modular implementation |
| Runtime validation | Six built-in tests and 19 additional automated checks passed; physical keyboard testing remains outstanding |

> **IMPORTANT — IMPLEMENTATION AND SECURITY BOUNDARY**
>
> PDE v3.1.2 provides AST-based syntax and command analysis, but it does not implement a command execution security guard. Risk warnings are informational and do not prevent commands from running.
>
> The history-sensitive-line filter protects PDE's own history index. It does not independently prevent PSReadLine from saving sensitive commands to its persistent history file.
>
> Live highlighting is implemented using custom PSReadLine key handlers and terminal rendering. It is deliberately restricted to safe single-line printable ASCII input that does not wrap. Multi-line input, non-ASCII input and wrapped lines are left to PSReadLine.
>
> Keyboard handler registration and automated classification tests do not prove that physical typing, cursor positioning and clipboard operations work correctly in every terminal. Those behaviours require additional manual testing.

# Document map

| SECTION | WHAT IT COVERS |
|---|---|
| 1. Overview and scope | Purpose, capability groups and boundaries |
| 2. Architecture and startup | Modular structure, loading sequence and shared state |
| 3. Command indexing | Command discovery, executable indexing and prefix matching |
| 4. History intelligence | Saved history, successful-command tracking and filtering |
| 5. Fuzzy suggestions | Levenshtein matching, suggestion ranking and usage |
| 6. AST analysis and syntax checking | Command recognition, parsing and risk warnings |
| 7. Live command highlighting | Green/yellow/red classification and terminal rendering |
| 8. PSReadLine integration | Predictions, keyboard handlers, completion and clipboard |
| 9. Configuration and runtime state | Settings, variables and management functions |
| 10. Command reference | Complete reference for the supplied public functions |
| 11. Testing and validation | Automated tests, manual keyboard tests and limitations |
| 12. Installation and maintenance | Profile installation, module paths and troubleshooting |
| Appendix A | Quick-start command sheet |

---

# 1. Overview and scope

## 1.1 Purpose

PDE Command Intelligence is a modular extension of the PowerShell Developer Environment.

Its purpose is to improve interactive command-line use by combining command recognition, saved-command history, predictive IntelliSense and live input highlighting.

The component uses PowerShell's Abstract Syntax Tree (AST) parser to inspect commands rather than relying entirely on simple text matching.

It maintains an index of available commands and their prefixes, tracks successful commands from the current session, and uses saved PSReadLine history to provide history-backed highlighting and suggestions.

The live highlighter uses a three-colour classification system:

| COLOUR | MEANING |
|---|---|
| Green | The complete typed line is a prefix of a recognised history entry |
| Yellow | The command is recognised or its name is a valid prefix of an indexed command |
| Red | The command name cannot be found in the command index or prefix index |
| Default | No applicable command classification is available |

PDE also maintains native PSReadLine functionality for command editing, predictions, history navigation, completion and clipboard insertion.

## 1.2 Main capabilities

| CAPABILITY | IMPLEMENTED PURPOSE |
|---|---|
| Command indexing | Discover installed cmdlets, functions, aliases, scripts and executable commands |
| Prefix indexing | Create searchable prefixes for every indexed command name |
| History learning | Record successful commands and maintain a history index |
| History filtering | Exclude selected obvious credential patterns and malformed commands from PDE's own index |
| Predictive IntelliSense | Enable PSReadLine history-backed predictions |
| Three-colour highlighting | Classify entered commands using history and AST-based command recognition |
| Fuzzy suggestions | Suggest similar command names using Levenshtein distance |
| AST analysis | Detect command nodes, syntax errors and unrecognised commands |
| Risk inspection | Warn about selected destructive or disruptive command patterns |
| Native completion | Retain PSReadLine tab completion with highlighting refresh |
| Clipboard management | Suspend highlighting during paste and run it after insertion |
| Diagnostics | Report command counts, history counts, versions and configuration |
| Optional logging | Record selected PDE diagnostic events when logging is enabled |

## 1.3 Scope boundaries

The current v3.1.2 implementation is specifically a command-intelligence component.

It does not currently contain the following wider PDE features described in earlier documentation:

- CPU, RAM and disk monitoring functions.
- Network adapter, firewall, route and TCP diagnostics.
- Installed-software and certificate inventory.
- Docker management.
- Git, .NET, Python and Node.js project tooling.
- Project discovery and validation.
- Automated command execution blocking.
- Credential purging from the actual PSReadLine history file.
- AI-based command suggestions.
- Continuous background monitoring.

These would need to be implemented as separate features before they could be included in the implemented capability list.

## 1.4 Design principles

The implementation follows several important design decisions:

1. PSReadLine remains responsible for command editing, cursor movement, native completion and clipboard insertion.
2. PDE uses AST parsing to identify PowerShell commands and analyse syntax.
3. History-based classification is kept separate from command-name recognition.
4. The original prompt output is preserved through a wrapper rather than replaced with an entirely new visual prompt.
5. Live highlighting is restricted to input that can be rendered safely with the implemented console-position calculations.
6. The AST analysis functions inspect text without executing it.
7. Feature code is separated into individual scripts while retaining shared global functions and state.

# 2. Architecture and startup

## 2.1 Modular architecture

PDE v3.1.2 is divided into a main loader and nine feature files.

The main loader establishes configuration, initialises runtime state and dot-sources the feature scripts.

The modular arrangement is:

```text
PDE V2
│
├── PowerShell Profile
│
├── PDE-V2.ps1
│   │
│   ├── Dependency checks
│   ├── Configuration
│   ├── Runtime state
│   ├── Module loading
│   └── Startup
│
└── Modules
    │
    ├── PDE-Logging.ps1
    ├── PDE-Prompt-History.ps1
    ├── PDE-Command-Index.ps1
    ├── PDE-History-Index.ps1
    ├── PDE-AST-Analysis.ps1
    ├── PDE-Fuzzy-Suggestions.ps1
    ├── PDE-PSReadLine-Integration.ps1
    ├── PDE-Live-Highlighting.ps1
    └── PDE-Management-Diagnostics.ps1
```

## 2.2 Feature responsibilities

| FILE | RESPONSIBILITY |
|---|---|
| PDE-Logging.ps1 | Logging, sensitive-history-line detection and history-entry insertion |
| PDE-Prompt-History.ps1 | Preserve the existing prompt and learn successful commands |
| PDE-Command-Index.ps1 | Build the command index, prefixes and command-recognition tests |
| PDE-History-Index.ps1 | Load, validate and maintain the history index |
| PDE-AST-Analysis.ps1 | Parse command text, identify AST command nodes, inspect syntax and generate risk warnings |
| PDE-Fuzzy-Suggestions.ps1 | Calculate edit distance and return ranked command/history suggestions |
| PDE-PSReadLine-Integration.ps1 | Configure colours, predictions and keyboard navigation |
| PDE-Live-Highlighting.ps1 | Implement green/yellow/red classification, terminal rendering, key handlers and paste handling |
| PDE-Management-Diagnostics.ps1 | Status, statistics, environment diagnostics, help and automated tests |

## 2.3 Why the files are dot-sourced

The feature files are dot-sourced rather than imported as independent PowerShell modules.

This allows them to share the global PDE configuration, history collections and command indexes.

It also allows their functions to remain available globally within the PowerShell session.

This is important because the individual functions depend on common data structures such as:

```powershell
$global:PDE_Config
$global:PDE_State
$global:PDE_State.CommandNames
$global:PDE_State.CommandPrefixes
$global:PDE_State.History
```

## 2.4 Startup sequence

The loader follows this general order:

| ORDER | OPERATION | RESULT |
|---:|---|---|
| 1 | Import PSReadLine | Loads the interactive dependency |
| 2 | Check PSReadLine configuration commands | Ensures the required cmdlets exist |
| 3 | Initialise configuration | Creates default settings if missing |
| 4 | Initialise runtime state | Creates command, prefix and history collections |
| 5 | Set compatibility references | Preserves the original PDE collection names |
| 6 | Load nine feature scripts | Defines the functions and keyboard integration |
| 7 | Update command index | Discovers commands and builds prefixes |
| 8 | Update history index | Reads and validates available history |
| 9 | Apply PSReadLine options | Configures predictions, colours and navigation |
| 10 | Install live highlighting | Registers the custom printable-key and editing handlers |
| 11 | Initialise diagnostics logging | Records successful startup when logging is enabled |

If PSReadLine cannot load, or its required configuration commands are unavailable, the loader displays a warning and returns without initialising the remaining component.

## 2.5 Dependency requirements

| DEPENDENCY | PURPOSE |
|---|---|
| PowerShell 5.1 or later | Execution environment |
| PSReadLine | Interactive command editing, predictions, completion and key handlers |
| System.Management.Automation.Language.Parser | AST and syntax analysis |
| .NET collections | Command-name, prefix and history collections |
| Windows console or compatible terminal | Live console rendering and cursor handling |

The implementation is designed for Windows PowerShell 5.1 and PowerShell 7+.

Terminal rendering should be tested separately because ANSI colour support and console behaviour can differ between hosts.

# 3. Command indexing

## 3.1 Purpose

The command index provides PDE with a local collection of commands currently available to the PowerShell session.

It is the foundation of:

- Command recognition.
- Yellow and red highlighting.
- Command-prefix checking.
- Fuzzy command suggestions.
- AST command analysis.

## 3.2 Building the command index

The primary command is:

```powershell
Update-PDEIndex -Force
```

PDE uses:

```powershell
Get-Command -All
```

to retrieve available commands.

Each command name is added to a case-insensitive `HashSet`.

Additional metadata is maintained in a lookup hashtable.

This metadata includes:

- Command name.
- Command type.
- Command source.
- Associated command information.

## 3.3 Executable-name indexing

PDE also recognises selected executable and script extensions:

- `.exe`
- `.com`
- `.cmd`
- `.bat`
- `.ps1`

Where applicable, the executable name without its extension is added to the command index.

For example:

```text
example.exe
```

can also create an indexed name:

```text
example
```

The original command entry remains available.

## 3.4 Prefix indexing

After the command names are collected, PDE creates every leading substring of each name.

For example:

```text
Get-Process
```

produces:

```text
G
Ge
Get
Get-
Get-P
Get-Pr
Get-Pro
Get-Proc
Get-Proce
Get-Proces
Get-Process
```

These prefixes are stored in a second case-insensitive `HashSet`.

This allows PDE to recognise partially typed command names without having to search every command for every keystroke.

## 3.5 Automatic refresh

The command index has a ten-minute refresh interval.

Running:

```powershell
Update-PDEIndex
```

will avoid rebuilding the index when the previous update is still within that interval.

To force a rebuild:

```powershell
Update-PDEIndex -Force
```

## 3.6 Command recognition

Use:

```powershell
Test-PDECommandName -Name 'Get-Date'
```

Example output:

```text
Name       : Get-Date
IsRecognised : True
CommandType  : Cmdlet
Source       : Microsoft.PowerShell.Utility
```

An imaginary command should return:

```text
IsRecognised : False
```

This function can also accept command names from the pipeline.

# 4. History intelligence

## 4.1 Purpose

PDE maintains an internal history index to support:

- Green input highlighting.
- Prefix-based history recognition.
- Fuzzy history suggestions.
- Command-use tracking within the component.

It uses both the saved PSReadLine history file and the current PowerShell session history.

## 4.2 History storage

The persistent history location is obtained through:

```powershell
(Get-PSReadLineOption).HistorySavePath
```

PDE reads the most recent entries up to the configured `HistoryIndexLimit`.

The default limit is 1,000.

## 4.3 History validation

Before importing saved history, PDE uses PowerShell's AST parser to identify command nodes.

History entries are rejected from the PDE index when:

- The entry is empty.
- The entry contains multiple lines.
- Parsing fails.
- Parsing produces syntax errors.
- No command AST is found.
- A static command name cannot be resolved.
- A referenced command path does not exist.
- The entry matches the configured sensitive-history patterns.

For a pipeline or compound command, the static command names must resolve.

This prevents arbitrary text and obvious invalid command input from automatically becoming green history entries.

## 4.4 Sensitive history filtering

The function:

```powershell
Test-PDESensitiveHistoryLine
```

checks a small set of patterns associated with:

- Passwords.
- Passwd values.
- Tokens.
- API keys.
- Secrets.
- Client secrets.
- Authorization headers.
- Bearer values.
- Plaintext secure-string conversion.
- Selected authentication commands.

This is a limited safeguard for PDE's own history index.

It does not independently change PSReadLine's saved-history policy or remove existing sensitive lines from the underlying history file.

## 4.5 Successful-command learning

PDE uses a wrapper around the existing PowerShell prompt.

The original prompt is saved in:

```powershell
$global:PDE_OriginalPrompt
```

The wrapper checks the last command's success state and reads the latest PowerShell history item.

When the command has succeeded and the history item is new, PDE inserts the command into its internal history index.

This allows successful commands to become available for green prefix highlighting during the current session.

The original prompt is then called to preserve the user's existing prompt output.

This means PDE does replace the global `prompt` function with a wrapper, even though it attempts to preserve the existing appearance.

## 4.6 History ordering

PDE keeps its internal history newest-first.

When a duplicate is promoted, it is removed from its previous position and inserted at the front.

The history is also maintained using a `HashSet` to avoid unnecessary duplicate entries.

## 4.7 Refreshing history

Run:

```powershell
Update-PDEHistory
```

Example output:

```text
Entries      : 45
Order        : Newest first
Updated      : ...
HistoryPath  : ...
```

The actual number of entries depends on the current history file and recognised commands.

# 5. Fuzzy command suggestions

## 5.1 Purpose

PDE provides fuzzy command suggestions when a typed command is close to an indexed command name.

For example:

```text
Get-Procss
```

may suggest:

```text
Get-Process
```

## 5.2 Levenshtein distance

The matching algorithm is based on Levenshtein edit distance.

It calculates the minimum number of:

- Character insertions.
- Character deletions.
- Character substitutions.

required to transform one string into another.

The implementation uses dynamic programming with two integer arrays.

It is a standard Levenshtein implementation. It does not currently include the separate keyboard-distance scoring or unrestricted transposition-aware scoring described in earlier documentation.

## 5.3 Distance configuration

The default fuzzy maximum distance is:

```powershell
FuzzyMaximumDistance = 2
```

The `Set-PDEOptions` command permits values from 1 to 4.

A lower distance is more restrictive.

A higher distance permits less similar suggestions.

## 5.4 Suggestion sources

The main command is:

```powershell
Get-PDESuggestions
```

Its source parameter supports:

| SOURCE | CONTENT |
|---|---|
| All | History and command suggestions |
| History | Saved and current-session history |
| Command | Indexed command names |

The `Prefix` parameter selects the beginning of the text to match.

The `Limit` parameter controls the maximum number of results, from 1 to 100.

The `Fuzzy` switch explicitly requests fuzzy matching.

Fuzzy matching is also enabled by default through configuration.

## 5.5 Suggestion ranking

Each suggestion records:

- Suggested text.
- Source.
- Match type.
- Edit distance.
- Ranking position.

Results are sorted by:

1. Lowest edit distance.
2. Lowest ranking value.
3. Alphabetical suggestion name.

Duplicate suggestion names are grouped so that the output does not repeatedly display the same command.

## 5.6 Examples

Normal command suggestions:

```powershell
Get-PDESuggestions -Prefix 'Get-Da' -Source Command
```

Fuzzy suggestions:

```powershell
Get-PDESuggestions -Prefix 'Get-Procss' -Source Command -Fuzzy
```

History suggestions:

```powershell
Get-PDESuggestions -Prefix 'Get-PDE' -Source History
```

# 6. AST analysis and syntax checking

## 6.1 Purpose

PDE uses PowerShell's AST parser to inspect command text.

The parser identifies actual PowerShell command nodes rather than treating every matching word as an executable command.

This allows PDE to distinguish command syntax from some forms of quoted or commented text.

## 6.2 Command analysis

The primary function is:

```powershell
Get-PDECommandAnalysis
```

Example:

```powershell
Get-PDECommandAnalysis -Text 'Get-Date | Where-Object { $_.Day -gt 1 }'
```

The returned object contains:

| PROPERTY | PURPOSE |
|---|---|
| `IsSyntacticallyValid` | Indicates whether parsing produced syntax errors |
| `ParseErrors` | Contains parser error messages |
| `Commands` | Contains the command AST findings |
| `UnknownCommands` | Contains unrecognised static command names |
| `RiskWarnings` | Contains selected command-risk messages |

Each command result can include:

- Name.
- IsRecognised.
- IsDynamic.
- CommandType.
- Source.
- StartOffset.
- EndOffset.

## 6.3 Syntax checking

The simpler wrapper is:

```powershell
Test-PDESyntax -Text 'Get-Date | Where-Object { $_.Day -gt 1 }'
```

It reports:

- `IsValid`
- `Errors`
- `CommandCount`
- `UnknownCommands`

An incomplete statement should produce a false validity result and the corresponding parser error.

## 6.4 Command-risk inspection

PDE checks selected command AST nodes for potentially destructive or disruptive operations.

The currently implemented warning categories are:

| COMMAND PATTERN | WARNING |
|---|---|
| `Remove-Item`, `rm`, `ri`, `del`, `erase`, `rmdir` | File or directory deletion command detected |
| `Clear-Disk`, `Format-Volume`, `Format-Partition`, `Remove-Partition`, `diskpart` | Disk or volume modification command detected |
| `Restart-Computer`, `Stop-Computer`, `Stop-Service`, `Restart-Service`, `Stop-Process`, `taskkill` | System, service or process interruption detected |
| `Set-ExecutionPolicy` with `Unrestricted` or `Bypass` in the command extent | Permissive execution policy detected |

Example:

```powershell
Get-PDECommandAnalysis -Text 'Remove-Item -LiteralPath "$env:TEMP\test.txt"'
```

The expected analysis includes:

```text
RiskWarnings:
File or directory deletion command detected.
Check the target path and options carefully.
```

## 6.5 Security limitations

Risk inspection is advisory.

It does not:

- Assign the four-level risk scale described in the previous PDE documentation.
- Block command execution.
- Bind a command-validation handler to Enter.
- Prevent PowerShell commands from running.
- Fully understand the effects of every parameter or pipeline.
- Detect every alias, dynamic command or external executable.
- Guarantee that a command is safe when no warning is returned.

The AST analysis function examines supplied text. It does not execute that text.

# 7. Live command highlighting

## 7.1 Purpose

PDE provides a live command-input colour overlay.

Unlike the earlier typo-suggestion helper, v3.1.2 includes custom PSReadLine key handlers that invoke the highlighter when supported editing actions take place.

The main visual states are:

| COLOUR | CLASSIFICATION |
|---|---|
| Green | Entire typed input is a valid prefix of an indexed history entry |
| Yellow | Command name is recognised or matches a valid command-name prefix |
| Red | Command name is not recognised and is not a valid indexed prefix |
| Neutral | No command AST or no applicable classification |

## 7.2 History-first classification

The first classification check is:

```powershell
Get-PDEHistoryPrefixMatch
```

The input is compared with the stored history entries.

If any history entry begins with the complete typed input, the input is classified as green.

This takes priority over command-name classification.

## 7.3 AST command classification

Where no history prefix matches, PDE parses the current input.

It retrieves PowerShell `CommandAst` nodes and identifies their command names.

Each static command name is compared with:

- `CommandNames`
- `CommandPrefixes`

A recognised command or valid command prefix is classified yellow.

An unknown command name is classified red.

Text without a command AST is treated as default.

## 7.4 Character colour mapping

`Get-PDELineColorMap` creates a colour value for each character in the command line.

The internal colour values are:

| VALUE | MEANING |
|---:|---|
| 0 | Neutral |
| 1 | Yellow |
| 2 | Red |
| 3 | Green |

A history prefix colours the entire input green.

Otherwise, command AST extents are processed and separators such as pipes and semicolons are coloured yellow when identified as actual PowerShell separator tokens.

## 7.5 Terminal rendering

The function:

```powershell
Invoke-PDELiveHighlight
```

performs the live overlay.

It obtains the current PSReadLine buffer and cursor position.

Before repainting, it checks:

- The buffer is not empty.
- The input is single-line.
- The input contains printable ASCII characters only.
- The console buffer width is available.
- The input does not wrap.
- The cursor position can be calculated safely.

PDE then:

1. Generates a line colour map.
2. Saves the current console position.
3. Moves to the beginning of the input.
4. Writes groups of characters using ANSI colour sequences.
5. Resets the terminal colour.
6. Restores the cursor position.

Rendering errors are caught because the highlighter is cosmetic and must not interrupt normal command editing.

## 7.6 Rendering limitations

The current implementation deliberately skips:

- Multi-line commands.
- Non-ASCII input.
- Empty input.
- Wrapped command lines.
- Unsupported console positioning situations.

These conditions are intentional safeguards against incorrect cursor-cell calculations.

The highlighter uses terminal output and console cursor positioning. It is not a PSReadLine-native token renderer.

Therefore, cursor stability, terminal wrapping and ANSI rendering still require physical testing in the intended terminal.

# 8. PSReadLine integration

## 8.1 Prediction configuration

The default configuration is:

```powershell
EnablePredictions   = $true
PredictionViewStyle = 'InlineView'
```

PDE configures history-based prediction when the installed PSReadLine version exposes the required prediction options.

The current implementation uses:

```powershell
PredictionSource = 'History'
```

It does not configure `HistoryAndPlugin` or install external prediction plugins.

If prediction support is unavailable, PDE records the reason in its runtime state.

## 8.2 Syntax colours

PDE configures supported PSReadLine colours for:

- Commands.
- Parameters.
- Variables.
- Strings.
- Numbers.
- Types.
- Members.
- Keywords.
- Operators.
- Comments.
- Errors.
- Default text.
- Continuation prompts.
- Emphasis.
- Inline predictions.
- List predictions.

The code checks which colour properties are exposed by the installed PSReadLine version before applying them.

## 8.3 Keyboard integration

The component installs custom handlers for selected key groups.

| KEY | IMPLEMENTED ACTION |
|---|---|
| Printable ASCII characters | Insert the character using PSReadLine, then update live highlighting |
| Backspace | Delete the previous character, then update highlighting |
| Delete | Delete the character ahead, then update highlighting |
| Tab | Run native next tab completion, then update highlighting |
| Shift+Tab | Run native previous tab completion, then update highlighting |
| Ctrl+V | Suspend highlighting, run PSReadLine paste, then refresh once |
| Shift+Insert | Use the same protected paste mechanism |
| UpArrow | History search in InlineView; prediction navigation in ListView |
| DownArrow | Forward history search in InlineView; prediction navigation in ListView |
| Ctrl+RightArrow | Accept the next inline prediction word when available; otherwise use standard next-word movement |

In ListView, PDE also configures F8 and Shift+F8 for history search where enabled.

## 8.4 Native editing responsibility

PSReadLine retains ownership of core editing.

PDE uses the PSReadLine APIs to:

- Insert characters.
- Delete characters.
- Move through tab completion.
- Retrieve and insert clipboard content.
- Read the current buffer and cursor position.

This avoids implementing a separate complete input editor.

## 8.5 Clipboard handling

Clipboard handling is particularly important because a paste may insert multiple characters or several lines at once.

PDE sets:

```powershell
$global:PDE_State.PasteInProgress = $true
```

before invoking:

```powershell
[Microsoft.PowerShell.PSConsoleReadLine]::Paste()
```

It then releases the guard in a `finally` block.

After a successful paste, PDE calls the highlighter once.

This prevents PDE's printable-character highlighting logic from repeatedly repainting the buffer while clipboard insertion is in progress.

Multi-line and non-ASCII paste operations are left to native PSReadLine rendering.

## 8.6 History navigation

With the default `InlineView` and history search enabled:

- UpArrow searches backward through history entries matching the current input prefix.
- DownArrow searches forward.

With `ListView`, UpArrow and DownArrow navigate the prediction list, while F8 and Shift+F8 are configured for history search.

The effective behaviour depends on the currently selected prediction view and configuration.

## 8.7 Manual verification requirement

The registration of a key handler is not proof that the physical action works correctly.

The following require manual verification:

- Character insertion and cursor position.
- Left/right cursor movement.
- Backspace and Delete.
- Tab and Shift+Tab.
- Up and Down history behaviour.
- Ctrl+Right prediction acceptance.
- Single-line paste.
- Multi-line paste.
- Shift+Insert paste.

# 9. Configuration and runtime state

## 9.1 Default configuration

| KEY | DEFAULT | PURPOSE |
|---|---|---|
| `EnablePredictions` | `$true` | Enable or disable PSReadLine predictions |
| `PredictionViewStyle` | `InlineView` | Select InlineView or ListView |
| `MaximumHistoryCount` | `10000` | Configure the PSReadLine history maximum |
| `HistoryIndexLimit` | `1000` | Maximum number of PDE history entries retained |
| `EnableHistorySearch` | `$true` | Enable prefix-based history navigation |
| `EnableFuzzySuggestions` | `$true` | Enable fuzzy command suggestions |
| `FuzzyMaximumDistance` | `2` | Maximum fuzzy matching distance |
| `EnableToolTips` | `$true` | Configure PSReadLine tooltips where supported |
| `EnableDiagnosticsLog` | `$false` | Enable PDE diagnostic file logging |
| `DiagnosticsLogPath` | `%LOCALAPPDATA%\PDE\PDE.log` | Default logging location |

## 9.2 Changing settings

The main configuration function is:

```powershell
Set-PDEOptions
```

Example:

```powershell
Set-PDEOptions -PredictionViewStyle ListView
```

Other examples:

```powershell
Set-PDEOptions -EnablePredictions $false

Set-PDEOptions -EnableFuzzySuggestions $true -FuzzyMaximumDistance 3

Set-PDEOptions -EnableHistorySearch $true

Set-PDEOptions -EnableDiagnosticsLog $true
```

Supported validation ranges:

| SETTING | RANGE |
|---|---|
| MaximumHistoryCount | 100–100000 |
| HistoryIndexLimit | 100–10000 |
| FuzzyMaximumDistance | 1–4 |

Configuration changes are session-scoped unless incorporated into the startup configuration.

## 9.3 Runtime state

The main shared state is:

```powershell
$global:PDE_State
```

It contains:

| PROPERTY | PURPOSE |
|---|---|
| `CommandNames` | Case-insensitive command-name index |
| `CommandPrefixes` | Case-insensitive prefix index |
| `CommandInfo` | Command metadata lookup |
| `History` | Newest-first PDE history list |
| `HistorySet` | Duplicate-detection collection |
| `LastIndexUpdate` | Last command-index refresh |
| `LastHistoryUpdate` | Last history-index update |
| `PredictionAvailable` | Whether prediction configuration is available |
| `PredictionViewStyleEffective` | Effective prediction view |
| `PredictionReason` | Explanation of prediction availability |
| `LastError` | Most recent recorded initialisation or index error |
| `Version` | PDE component version |
| `LiveHighlightingEnabled` | Live-highlighter installation status |
| `PasteInProgress` | Prevents highlighting during clipboard insertion |

## 9.4 Compatibility references

PDE also maintains the following global compatibility references:

```powershell
$global:PDE_Cmds
$global:PDE_Prefs
$global:PDE_Past
$global:PDE_Suggestion
$global:PDE_PrevLen
$global:PDE_HistIdx
$global:PDE_HistMatches
$global:PDE_HistPrefix
```

The first three reference the current command names, prefixes and history collections.

These names are retained for neighbouring profile code that may still use the earlier collection names.

## 9.5 Diagnostics logging

Logging is controlled by:

```powershell
EnableDiagnosticsLog = $false
```

When enabled, PDE writes timestamped INFO, WARN and ERROR entries through:

```powershell
Write-PDELog
```

The default path is:

```text
%LOCALAPPDATA%\PDE\PDE.log
```

Logging failures are suppressed so that diagnostics do not interfere with command-line editing.

# 10. Command reference

## 10.1 Command indexing

| FUNCTION | PURPOSE |
|---|---|
| `Update-PDEIndex` | Build or refresh the installed-command index |
| `Test-PDECommandName` | Test whether a command name is recognised |
| `Test-PDEHistoryLineRecognised` | Validate saved history command names |
| `Update-PDEHistory` | Rebuild the internal history index |

## 10.2 History and logging

| FUNCTION | PURPOSE |
|---|---|
| `Test-PDESensitiveHistoryLine` | Check selected obvious credential patterns |
| `Add-PDEHistoryEntry` | Validate and insert a history entry |
| `Write-PDELog` | Write an optional PDE diagnostic entry |
| `prompt` | Wrap and preserve the original prompt while tracking successful commands |

## 10.3 AST analysis

| FUNCTION | PURPOSE |
|---|---|
| `Get-PDECommandAnalysis` | Inspect command ASTs, parse errors, recognition and risk warnings |
| `Test-PDESyntax` | Return a simplified syntax result |

## 10.4 Fuzzy suggestions

| FUNCTION | PURPOSE |
|---|---|
| `Get-PDELevenshteinDistance` | Calculate edit distance between two strings |
| `Get-PDESuggestions` | Produce ranked history or command suggestions |

## 10.5 Live highlighting

| FUNCTION | PURPOSE |
|---|---|
| `Get-PDEHistoryPrefixMatch` | Check whether the typed input prefixes a history entry |
| `Get-PDEInputHighlightClass` | Return Green, Yellow, Red or Default |
| `Get-PDELineColorMap` | Generate per-character colour classifications |
| `Invoke-PDELiveHighlight` | Render the line overlay using terminal colours |
| `Install-PDELiveHighlightHandlers` | Register printable-character, editing, completion and paste handlers |

## 10.6 PSReadLine configuration

| FUNCTION | PURPOSE |
|---|---|
| `Invoke-PDEApplyOptions` | Apply prediction, colours and keyboard configuration |
| `Set-PDEOptions` | Change configuration and reapply PSReadLine options |

## 10.7 Management and diagnostics

| FUNCTION | PURPOSE |
|---|---|
| `Get-PDEStatus` | Return current PDE status |
| `Get-PDEStatistics` | Return index and history statistics |
| `Get-PDEDiagnostics` | Report PowerShell, host, PSReadLine and console information |
| `Get-PDEHelp` | Retrieve full PowerShell help for a command |
| `Test-PDE` | Run the built-in six-check test suite |

# 11. Testing and validation

## 11.1 Built-in test suite

Run:

```powershell
Test-PDE
```

The built-in suite currently checks six areas:

| TEST | VALIDATION |
|---|---|
| PSReadLine module | Confirms the module is loaded |
| Command index | Confirms command names have been indexed |
| PowerShell AST parsing | Confirms a sample pipeline contains at least two command AST nodes and parses successfully |
| Unknown command classification | Confirms a long unknown command is classified red rather than green |
| Command recognition | Confirms `Get-Date` is present in the index |
| Predictive IntelliSense | Confirms the component reports prediction configuration as available |

The function outputs a table and a summary object containing:

- `Passed`
- `PassedCount`
- `FailedCount`
- `Checks`

These six checks do not test every keyboard or clipboard interaction.

## 11.2 Additional automated validation

The current installation was also checked using a separate acceptance-test command.

The observed result was:

| AREA | RESULT |
|---|---|
| Yellow highlighting classification | Passed |
| Red highlighting classification | Passed |
| Green history classification | Passed |
| Live highlighting callback availability | Passed |
| Backspace registration | Passed |
| Delete registration | Passed |
| Tab registration | Passed |
| Shift+Tab registration | Passed |
| UpArrow history handler | Passed |
| DownArrow history handler | Passed |
| Ctrl+RightArrow handler | Passed |
| Ctrl+V registration | Passed |
| Shift+Insert registration | Passed |
| Tab completion engine | Passed |
| Inline prediction settings | Passed |
| Valid AST parsing | Passed |
| Invalid AST detection | Passed |
| Risk warning generation | Passed |
| Fuzzy command suggestions | Passed |

**Additional automated result: 19 passed, 0 failed.**

These checks establish that the tested logic and handlers are present and configured. They do not certify actual physical keypress behaviour.

## 11.3 Physical keyboard acceptance tests

The following tests remain required.

| TEST | ACTION | EXPECTED RESULT |
|---|---|---|
| Live highlighting | Type a recognised command manually | Correct colour appears as input is entered |
| Cursor positioning | Move left/right during highlighted input | Cursor remains aligned with the intended character |
| Backspace | Delete a character before the cursor | Correct character is removed |
| Delete | Delete a character ahead of the cursor | Correct character is removed |
| Tab | Request completion | Native completion works and highlighting refreshes |
| Shift+Tab | Request previous completion | Completion moves backwards correctly |
| UpArrow | Enter a partial command and search history | Matching history is displayed |
| DownArrow | Move forward through history | Matching history navigation works |
| Ctrl+RightArrow | Accept the next inline prediction word | Prediction acceptance works |
| Ctrl+V single-line | Paste a command | Complete command inserted without duplication |
| Ctrl+V multi-line | Paste several lines | Full block inserted and PSReadLine handles rendering |
| Shift+Insert | Paste a command | Same correct behaviour as Ctrl+V |

Do not treat handler registration as proof of successful manual interaction.

## 11.4 Runtime environment observed

During the latest validation session, the reported environment was:

| PROPERTY | OBSERVED VALUE |
|---|---|
| PowerShell | Windows PowerShell 5.1.26100.9818 |
| PSReadLine | 2.4.5 |
| PDE | 3.1.2 |
| Indexed command names | 1,992 |
| Indexed prefixes | 20,157 |
| Initial history entries | 45 |

These counts are session-dependent and will change as available commands and recognised history change.

The built-in test suite returned six passed and zero failed.

The separate automated acceptance test returned 19 passed and zero failed.

Physical keyboard and clipboard tests still need to be completed before full interactive acceptance can be claimed.

# 12. Installation and maintenance

## 12.1 Profile loading

The current profile uses a small entry-point loader.

Example:

```powershell
# PowerShell Developer Environment V2 - Profile Loader
$PdeProfilePath = Join-Path $HOME 'PDE-V2.ps1'

if (Test-Path -LiteralPath $PdeProfilePath -PathType Leaf) {
    . $PdeProfilePath
} else {
    Write-Warning "PDE V2 profile not found: $PdeProfilePath"
}
```

The main PDE loader then establishes its feature-module directory and dot-sources the nine scripts.

## 12.2 Module path

The module path must point to the directory containing all nine `PDE-*.ps1` feature files.

The original modular arrangement keeps the loader and `Modules` directory together:

```powershell
$PDE_ModuleDirectory = Join-Path $PSScriptRoot 'Modules'
```

In the current installation, the feature scripts are stored in the active PowerShell profile directory's `Modules` folder. The corresponding loader path is:

```powershell
$PDE_ModuleDirectory = Join-Path (Split-Path -Parent $PROFILE) 'Modules'
```

Use the expression that matches the actual installation layout. Do not load the same feature scripts twice.

## 12.3 Verify the module directory

```powershell
Get-ChildItem -LiteralPath (Join-Path (Split-Path -Parent $PROFILE) 'Modules') -Filter 'PDE-*.ps1' -File |
    Select-Object Name, Length
```

The expected feature files are:

```text
PDE-AST-Analysis.ps1
PDE-Command-Index.ps1
PDE-Fuzzy-Suggestions.ps1
PDE-History-Index.ps1
PDE-Live-Highlighting.ps1
PDE-Logging.ps1
PDE-Management-Diagnostics.ps1
PDE-Prompt-History.ps1
PDE-PSReadLine-Integration.ps1
```

## 12.4 First-launch checks

After opening a new PowerShell session, run:

```powershell
Get-PDEStatus | Format-List
```

```powershell
Test-PDE
```

```powershell
Get-PDEStatistics | Format-List
```

```powershell
Get-PDEDiagnostics | Format-List
```

Check that:

- PDE reports version 3.1.2.
- PSReadLine is loaded.
- Command names and prefixes are indexed.
- History entries are being recognised.
- Predictions are enabled when supported.
- Live highlighting reports as enabled.
- No unexpected initialisation error is present.

## 12.5 Safe update procedure

1. Keep a backup of the current loader and all nine feature files.
2. Edit one feature file at a time where possible.
3. Open a new test session or reload the profile.
4. Run `Get-PDEStatus`.
5. Run `Test-PDE`.
6. Run the additional command, AST and highlighting tests.
7. Complete the relevant physical keyboard tests.
8. Promote the change into the normal profile once the results are satisfactory.

# Appendix A. Quick-start command sheet

| TASK | COMMAND |
|---|---|
| Show PDE status | `Get-PDEStatus \| Format-List` |
| Run automated tests | `Test-PDE` |
| Show statistics | `Get-PDEStatistics \| Format-List` |
| Show diagnostics | `Get-PDEDiagnostics \| Format-List` |
| Refresh command index | `Update-PDEIndex -Force` |
| Refresh history | `Update-PDEHistory` |
| Recognise a command | `Test-PDECommandName -Name 'Get-Date'` |
| Test syntax | `Test-PDESyntax -Text 'Get-Date \| Where-Object { $_.Day -gt 1 }'` |
| Analyse a command | `Get-PDECommandAnalysis -Text 'Get-Process'` |
| Check command risk | `Get-PDECommandAnalysis -Text 'Remove-Item test.txt'` |
| Find command suggestions | `Get-PDESuggestions -Prefix 'Get-Da' -Source Command` |
| Find fuzzy suggestions | `Get-PDESuggestions -Prefix 'Get-Procss' -Source Command -Fuzzy` |
| Find history suggestions | `Get-PDESuggestions -Prefix 'Get-PDE' -Source History` |
| Test colour classification | `Get-PDEInputHighlightClass -Text 'Get-Pro'` |
| Change prediction view | `Set-PDEOptions -PredictionViewStyle ListView` |
| Disable predictions | `Set-PDEOptions -EnablePredictions $false` |
| Enable diagnostic logging | `Set-PDEOptions -EnableDiagnosticsLog $true` |

---

**End of PDE Command Intelligence v3.1.2 Technical Documentation.**
