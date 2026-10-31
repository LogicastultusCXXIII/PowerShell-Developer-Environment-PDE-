# PowerShell Developer Environment (PDE)

## Command Intelligence 3.1.2 — Technical Documentation & User Guide

A modular PowerShell command-intelligence component providing command discovery, history-backed suggestions, AST-based analysis, character-level green/yellow/red command highlighting, and PSReadLine integration.

> **Documentation scope**  
> This README covers the complete Command Intelligence component: its main loader and all nine feature files. It describes the refactored versions of `PDE-Logging.ps1`, `PDE-History-Index.ps1`, and `PDE-Live-Highlighting.ps1`, together with the compatible `PDE-Management-Diagnostics.ps1` update. The other five feature files remain part of the same nine-file component.

| Document detail | Value |
|---|---|
| Environment | PowerShell Developer Environment (PDE V2) |
| Component | PDE Command Intelligence |
| Component version | 3.1.2 |
| Target shells | Windows PowerShell 5.1 and PowerShell 7+ (designed for; test each host) |
| Primary dependency | PSReadLine |
| Architecture | Main loader plus nine dot-sourced feature scripts |
| Main implementation languages | PowerShell and inline C# helper for live character alignment |
| Main capabilities | Command indexing, history indexing, fuzzy suggestions, AST analysis, live highlighting, PSReadLine configuration and diagnostics |
| Validation status | Earlier pre-optimisation build passed its reported tests. The later C#-optimised replacement set must be re-tested in the target Windows PowerShell session before it is described as fully validated. |

## Important implementation and security boundaries

- Command-risk analysis is advisory. It reports a limited set of suspicious command patterns; it does not intercept or block command execution.
- Sensitive-history patterns are used to exclude lines from PDE's own history index. They do **not** install a PSReadLine `AddToHistoryHandler`, remove entries from the actual PSReadLine history file, or guarantee that secrets are not persisted by PowerShell.
- Green highlighting means that the typed command characters align to a command name or command-name prefix present in PDE's indexed history. A saved PSReadLine history file does not record exit codes, so an imported historical command cannot be assumed to have succeeded.
- Yellow highlighting means the typed command characters align to a recognised command or valid command prefix that is not present in PDE's indexed history.
- Red highlighting marks typed command characters that do not align to the selected recognised command candidate. If no suitable candidate is found within the configured distance, the command token is all red.
- Only the command-name token (`CommandElements[0]`) receives command-name colours. Arguments and parameters remain neutral. Recognised PowerShell separators receive yellow.
- Live rendering is deliberately limited to single-line, printable ASCII input that does not wrap. Multi-line, non-ASCII, and wrapped input is left to PSReadLine.
- The live highlighter uses compiled C# for distance calculation and character alignment, but PowerShell still parses the active input line into an AST and performs terminal rendering. No end-to-end sub-millisecond latency benchmark is claimed.
- Keyboard-handler registration and automated colour-map tests do not prove physical typing, cursor placement, clipboard behaviour, or behaviour in every terminal host. Those require manual testing.

---

# 1. Overview and scope

## 1.1 Purpose

PDE Command Intelligence extends an interactive PowerShell session with a searchable command index, an internal history index, command suggestions, syntax inspection, selected risk warnings, and a live command-name colour overlay.

The component uses `Get-Command -All` to discover commands, PowerShell parser APIs to inspect active command text, `PSParser.Tokenize` for faster bulk history command extraction, and PSReadLine to manage the interactive input buffer.

The live highlighter distinguishes a command that has previously appeared in PDE's accepted history index from a recognised but unused command. For an invalid spelling, it searches a bounded set of likely command candidates and aligns the typed characters against the best candidate.

## 1.2 Main capabilities

| Capability | Implemented purpose |
|---|---|
| Command indexing | Index available cmdlets, functions, aliases, scripts and executable commands returned by `Get-Command -All`. |
| Prefix indexing | Build a case-insensitive set of every leading prefix of each indexed command name. |
| History indexing | Build a newest-first list of accepted command lines plus sets of command names and their prefixes found in indexed history. |
| Successful-command learning | Wrap the existing `prompt` function and add newly completed successful session commands to PDE's history index. |
| Sensitive-line filtering | Exclude lines matching four compiled credential-pattern groups from PDE's own history index. |
| Predictive IntelliSense | Configure PSReadLine's history-based prediction when supported by the installed version. |
| Character-level highlighting | Colour matched command characters green or yellow and mismatched typed command characters red. |
| Fuzzy suggestions | Suggest command names or history lines by prefix and edit-distance matching. |
| AST analysis | Report parse errors, command AST nodes, recognised or unknown command names, and selected risk warnings. |
| PSReadLine integration | Configure syntax colours, prediction view, prefix-history navigation, completion handlers, editing redraws and paste handling. |
| Diagnostics | Report component state, indexed counts, PowerShell/PSReadLine details and run the built-in checks. |
| Optional logging | Write INFO/WARN/ERROR diagnostics when logging is enabled; logging failures are suppressed. |

## 1.3 Out of scope

The nine files in this Command Intelligence component do not implement the wider PDE features below. They must not be documented as available unless separate source files are added and integrated:

- CPU, RAM, disk-capacity or physical disk-health monitoring.
- Network adapter, route, firewall, DNS, TCP-port or Internet diagnostics.
- Installed-software or certificate inventory.
- Docker management.
- Git, .NET, Python or Node.js project tooling.
- Project discovery or build orchestration.
- AI-based command suggestions.
- A command-execution security boundary or command-blocking policy.
- Automatic purging of sensitive entries from the actual PSReadLine history file.
- Continuous background monitoring of the machine.

## 1.4 Design principles

1. PSReadLine remains the input-buffer and editing engine.
2. PDE uses AST parsing for the active command line and interactive history additions.
3. Bulk history import uses a tokenizer rather than building a full AST for every saved line.
4. The live alignment algorithm is compiled C# to avoid running the Levenshtein matrix and backtracking loops in PowerShell on every redraw.
5. Candidate collection is capped at 25 names and the best candidate is selected with a single-pass comparison.
6. The highlighter does not recolour arguments or parameters as command names.
7. Unsafe terminal layouts are left to PSReadLine rather than manually repainted.
8. The feature scripts are dot-sourced so they share the loader's global configuration and state.

# 2. Architecture and startup

## 2.1 Project layout

The component contains a profile bootstrap, a main loader and nine feature scripts:

```text
PowerShell profile ($PROFILE)
└── dot-sources PDE-V2.ps1
    ├── dependency checks
    ├── global configuration and runtime state
    ├── loads the nine feature scripts in order
    └── initialises indexes and PSReadLine integration

Modules\
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

In the distributed modular layout, the loader can resolve `Modules` relative to `$PSScriptRoot`. In the current user installation, the loader was adjusted to resolve `Modules` beside the active profile directory:

```powershell
$PDE_ModuleDirectory = Join-Path (Split-Path -Parent $PROFILE) 'Modules'
```

Use one path strategy consistently. The nine files must be in the directory selected by `$PDE_ModuleDirectory`.

## 2.2 Responsibilities of all nine feature files

| File | Responsibilities and principal functions |
|---|---|
| `PDE-Logging.ps1` | `Write-PDELog`; compiles and applies sensitive-history regex rules; `Test-PDESensitiveHistoryLine`; tracks recognised history command names/prefixes; `Add-PDEHistoryEntry` for interactive additions. |
| `PDE-Prompt-History.ps1` | Saves the original prompt, wraps `prompt`, detects a newly completed session history item and adds it when the preceding command succeeded. |
| `PDE-Command-Index.ps1` | `Update-PDEIndex`, `Test-PDECommandName`, `Test-PDEHistoryLineRecognised`; discovers commands and builds command prefixes. |
| `PDE-History-Index.ps1` | `Get-PDEFastHistoryCommandNames`, `Add-PDEHistoryIndexEntryFast`, `Update-PDEHistory`; imports session and saved history without repeated front insertion. |
| `PDE-AST-Analysis.ps1` | `Get-PDECommandAnalysis` and `Test-PDESyntax`; parses text, inspects command AST nodes and generates selected advisory risk warnings. |
| `PDE-Fuzzy-Suggestions.ps1` | `Get-PDELevenshteinDistance` and `Get-PDESuggestions`; produces prefix and fuzzy suggestions from command and history indexes. |
| `PDE-PSReadLine-Integration.ps1` | `Invoke-PDEApplyOptions` and `Set-PDEOptions`; applies supported token colours, history prediction, view style and navigation bindings. |
| `PDE-Live-Highlighting.ps1` | Compiles `PDE.LevenshteinHelper`; `Get-PDECommandNameColorMap`, `Get-PDELineColorMap`, `Invoke-PDELiveHighlight`, `Install-PDELiveHighlightHandlers`; handles character alignment and live redraw. |
| `PDE-Management-Diagnostics.ps1` | `Get-PDEStatus`, `Get-PDEStatistics`, `Get-PDEDiagnostics`, `Get-PDEHelp`, and `Test-PDE`. The refactored version tests `Get-PDECommandNameColorMap` and reports helper readiness. |

The optimised refactor replaces three main component files (`PDE-Logging.ps1`, `PDE-History-Index.ps1`, and `PDE-Live-Highlighting.ps1`). It also includes a compatible update to `PDE-Management-Diagnostics.ps1`, because the old diagnostics implementation called `Get-PDEInputHighlightClass`, which is removed from the optimised highlighter. This is still a nine-module project; the diagnostics update replaces an existing module and does not add a tenth module.

## 2.3 Shared configuration

The loader creates `$global:PDE_Config` as an ordered hashtable when it does not already exist. Default values are added only when a key is missing, so pre-existing values survive a profile reload.

## 2.4 Shared runtime state

The loader creates `$global:PDE_State` when it does not already exist. The initial state includes:

| State member | Purpose |
|---|---|
| `CommandNames` | Case-insensitive set of available command names. |
| `CommandPrefixes` | Case-insensitive set of command-name prefixes. |
| `CommandInfo` | Lookup table of `Get-Command` metadata. |
| `History` | Newest-first list of accepted history command lines. |
| `HistorySet` | Ordinal set used to deduplicate full history lines. |
| `LastIndexUpdate` | Timestamp of the last command-index update. |
| `LastHistoryUpdate` | Timestamp of the last history-index update. |
| `PredictionAvailable` | Whether PSReadLine prediction configuration was accepted. |
| `PredictionViewStyleEffective` | Effective InlineView or ListView setting. |
| `PredictionReason` | Human-readable prediction status. |
| `LastError` | Most recent recorded index or startup error. |
| `Version` | Component version (`3.1.2`). |
| `LiveHighlightingEnabled` | Whether live handler installation completed. |
| `PasteInProgress` | Guard that suspends PDE repaint during clipboard insertion. |
| `HistoryCommandNames` | Created by the logging/history helpers; contains recognised command names represented in PDE's history index. |
| `HistoryCommandPrefixes` | Created by the logging/history helpers; contains every prefix of those history command names. |
| `LevenshteinHelperReady` | Set by the highlighter after the compiled C# helper is loaded and warmed. |

Compatibility variables `$global:PDE_Cmds`, `$global:PDE_Prefs`, and `$global:PDE_Past` reference the command names, command prefixes and history collections respectively. Additional legacy suggestion/history variables are also initialised by the loader.

## 2.5 Module load and startup order

The loader dot-sources the files in this order:

1. `PDE-Logging.ps1`
2. `PDE-Prompt-History.ps1`
3. `PDE-Command-Index.ps1`
4. `PDE-History-Index.ps1`
5. `PDE-AST-Analysis.ps1`
6. `PDE-Fuzzy-Suggestions.ps1`
7. `PDE-PSReadLine-Integration.ps1`
8. `PDE-Live-Highlighting.ps1`
9. `PDE-Management-Diagnostics.ps1`

The startup block then forces a command-index refresh, builds the history index, applies PSReadLine options and installs live highlighting.

The loader first imports PSReadLine and checks that `Set-PSReadLineOption` and `Set-PSReadLineKeyHandler` are available. If these checks fail, it warns and returns. Missing feature files or module-load exceptions are caught and reported as a module-loading warning.

## 2.6 Prompt behaviour

`PDE-Prompt-History.ps1` defines a global `prompt` wrapper. It preserves the previously defined prompt scriptblock, checks the last command's success state, inspects the latest `Get-History` entry and adds a new successful command through `Add-PDEHistoryEntry`.

The original prompt output is called and returned when available; otherwise PDE uses a basic `PS <path>>` fallback. Therefore the project does define a custom wrapper around `prompt`; it does not leave the global prompt function untouched.

The live highlighter also calls `[Console]::SetCursorPosition` when painting the input line. Any loader comments claiming that PDE never uses a custom prompt or never calls `Console.SetCursorPosition` are stale and should be corrected.

# 3. Command and executable indexing

## 3.1 Command discovery

`Update-PDEIndex` calls:

```powershell
Get-Command -All -ErrorAction Stop
```

It clears and rebuilds the command-name set, prefix set and metadata lookup. The indexed names include commands visible to the current session, such as cmdlets, functions, aliases, scripts and applications returned by `Get-Command`.

## 3.2 Executable basenames

For names ending in `.exe`, `.com`, `.cmd`, `.bat`, or `.ps1`, the basename without the extension is also added as a convenience lookup. The original name is retained.

## 3.3 Prefix set

For each indexed name, every leading substring from length one through the complete name is inserted into `CommandPrefixes`. This allows exact O(1)-average hash-set lookups for a typed prefix, subject to hash-table behaviour.

## 3.4 Refresh policy

The command index uses a ten-minute refresh interval. `Update-PDEIndex` returns the current counts without rebuilding while the index is still inside the interval. `-Force` rebuilds immediately.

```powershell
Update-PDEIndex
Update-PDEIndex -Force
```

## 3.5 Command recognition

`Test-PDECommandName` accepts a name from the pipeline or `-Name`, ensures the index is reasonably current, and returns the name, recognition result, command type and source when available.

`Test-PDEHistoryLineRecognised` remains available as a full-AST history-line validator. The optimised bulk history import described in Section 4 uses the faster tokenizer function instead.

# 4. History indexing and prompt learning

## 4.1 Two history paths

The refactored implementation uses different paths for bulk history import and a newly completed interactive command:

- **Bulk import:** `Update-PDEHistory` uses `Get-PDEFastHistoryCommandNames` and `PSParser.Tokenize`; it does not construct a full AST for every saved history line.
- **Interactive addition:** `Add-PDEHistoryEntry` uses the full PowerShell AST parser for the one newly completed line, rejects parse errors and extracts command AST names.

This split reduces startup work while retaining stronger parsing for newly accepted interactive lines.

## 4.2 Bulk token extraction

`Get-PDEFastHistoryCommandNames` tokenizes a single-line history entry with `[System.Management.Automation.PSParser]::Tokenize`. It examines tokens whose type is `Command`, checks whether each command name exists in the command index or resolves to an existing file path, and rejects the line if a static command token is unresolved, the tokenizer reports errors, or no command token is found.

This is lexical token extraction, not full AST validation. It is intended to reduce bulk import overhead. It should not be described as semantically equivalent to a complete AST walk for every possible PowerShell construct.

## 4.3 O(N) bulk list construction

`Add-PDEHistoryIndexEntryFast` appends accepted lines to a `List[string]`. `Update-PDEHistory` traverses the current-session history newest-to-oldest, then the saved PSReadLine history file newest-to-oldest, using a `HashSet` to avoid duplicate lines.

Because bulk imports append rather than repeatedly calling `List.Insert(0, ...)`, list construction is O(N) in the number of accepted entries, apart from tokenization, command lookups and collection operations. The configured history limit caps the number of retained entries.

`Add-PDEHistoryEntry` still inserts a single new interactive command at index zero when promoting it to newest position. That is a per-command operation; it is not used as the bulk-import loop.

## 4.4 History ordering and precedence

The final list is newest-first. Current-session entries are considered first, followed by saved file entries. Duplicate command lines are not added twice. The current-session item can therefore take precedence over an identical saved-file item.

The `HistoryIndexLimit` default is 1,000. The saved file is read using `Get-Content -Tail` with the configured limit, and import stops when the in-memory list reaches the limit.

## 4.5 History command-name indexes

For each recognised command name extracted from an accepted history line, `Add-PDEHistoryCommandName` adds:

- The exact command name to `HistoryCommandNames`.
- Every leading prefix of that command name to `HistoryCommandPrefixes`.

Only names present in the current command index are added. These sets drive the green-history distinction in the character-level highlighter.

## 4.6 Sensitive-line filtering

Before a line is added to PDE's own index, it is checked by `Test-PDESensitiveHistoryLine`. If it matches a configured pattern, it is excluded from the PDE index.

This does **not** configure PSReadLine's `AddToHistoryHandler` and does not guarantee that PSReadLine will omit the same line from its persistent history file. It also does not purge existing entries.

## 4.7 Session successful-command tracking

The prompt wrapper compares the latest history ID with `$global:PDE_LastHistId`. When a new history item is detected and `$?` indicates success, the line is added through `Add-PDEHistoryEntry -PromoteDuplicate`.

Saved history files do not store success/failure exit status. As a result, imported command names are treated as previously indexed history usage even though their original success cannot be proven.

## 4.8 History refresh

```powershell
Update-PDEHistory
```

The result object reports:

- `Entries`
- `IndexedCommandNames`
- `Order` (`Newest first`)
- `Updated`
- `HistoryPath`

# 5. Utilities, sensitive filters and logging

## 5.1 `Write-PDELog`

Logging is disabled by default through `EnableDiagnosticsLog = $false`. When enabled, `Write-PDELog` writes a timestamped INFO, WARN or ERROR entry to `DiagnosticsLogPath`.

The implementation creates the parent directory when necessary, opens the file in append mode with read/write sharing, writes UTF-8 without a byte-order mark and disposes the writer/stream in a `finally` block.

All logging failures are suppressed. This is best-effort logging: it does not retry a locked file or report a logging failure to the interactive console, because logging must not disrupt command-line input.

## 5.2 Compiled sensitive-history regexes

Four regex patterns are compiled once and retained in `$global:PDE_SensitiveHistoryRegexes`. They use IgnoreCase, Compiled and CultureInvariant options, with a 100 ms match timeout.

The patterns target selected forms of:

1. Credential-like assignments containing password, passwd, token, API key, secret, client secret, authorization or bearer labels.
2. Selected sensitive command-line parameters such as `-Password`, `-Token`, `-ApiKey` and related names.
3. `ConvertTo-SecureString` used with `-AsPlainText`.
4. Selected GitHub and Azure login commands that place a token or password directly on the command line.

The filter is heuristic. It does not cover every credential format, variable naming convention, secret provider or authentication workflow. A regex timeout or filter exception is treated conservatively as sensitive for PDE's own index.

## 5.3 `Add-PDEHistoryEntry`

This function handles an individual interactive command line. It trims and validates the line, rejects empty or multi-line input, applies the sensitive-line filter, parses the line with `Parser.ParseInput`, and rejects parser errors.

It then deduplicates or promotes the line, inserts it at the front of the history list, extracts command AST nodes and adds recognised command names to `HistoryCommandNames` and `HistoryCommandPrefixes`. It trims the in-memory list to `HistoryIndexLimit`.

## 5.4 Safety boundary

Sensitive-line matching is not a complete secret scanner and is not a security boundary. Do not type real credentials into a shell command simply because PDE has this filter. Use secure prompts, credential stores or supported secret-management tools. If a credential has already been exposed in history, rotate it; removing a history index entry does not invalidate it.

# 6. Fuzzy suggestions

## 6.1 `Get-PDELevenshteinDistance`

The public fuzzy-suggestion function in `PDE-Fuzzy-Suggestions.ps1` uses a PowerShell dynamic-programming implementation of standard Levenshtein distance with two integer arrays. It supports insertion, deletion and substitution. This public suggestion implementation remains PowerShell; the compiled C# helper described in Section 8 is used by the live character highlighter.

## 6.2 `Get-PDESuggestions`

Parameters:

| Parameter | Meaning |
|---|---|
| `-Prefix` | Text to match; defaults to an empty string. |
| `-Source` | `All`, `History` or `Command`; defaults to `All`. |
| `-Limit` | Maximum number of suggestions, 1–100; defaults to 10. |
| `-Fuzzy` | Explicitly requests fuzzy command suggestions. |

History suggestions use prefix matching against complete indexed history lines. Command suggestions first include command names that start with the supplied prefix. Fuzzy command matching runs when `-Fuzzy` is specified or `EnableFuzzySuggestions` is true, and the prefix is at least three characters long.

The results include the suggestion text, source, match type, edit distance and rank. The function sorts by distance, rank and suggestion text, groups duplicate suggestion strings and returns the first `Limit` results.

Examples:

```powershell
Get-PDESuggestions -Prefix 'Get-Da' -Source Command
Get-PDESuggestions -Prefix 'Get-Procss' -Source Command -Fuzzy
Get-PDESuggestions -Prefix 'Get-PDE' -Source History
```

**Performance distinction:** the 25-candidate cap and single-pass best-match selection apply to the live highlighter's per-keystroke command alignment. They do not currently apply to `Get-PDESuggestions`, which scans the command-name set and uses a PowerShell sorting/grouping pipeline.

# 7. AST analysis and command-risk inspection

## 7.1 `Get-PDECommandAnalysis`

This function updates the command index if its refresh interval has expired, calls `Parser.ParseInput` on the supplied text and finds `CommandAst` nodes.

Each command result can include:

- `Name`
- `IsRecognised`
- `IsDynamic`
- `CommandType`
- `Source`
- `StartOffset`
- `EndOffset`

The returned summary contains `IsSyntacticallyValid`, `ParseErrors`, `Commands`, `UnknownCommands` and `RiskWarnings`.

## 7.2 `Test-PDESyntax`

This is a smaller wrapper over `Get-PDECommandAnalysis`. It returns `IsValid`, `Errors`, `CommandCount` and `UnknownCommands`.

## 7.3 Risk patterns

The current implementation reports warnings for selected command names:

| Pattern | Warning |
|---|---|
| `Remove-Item`, `rm`, `ri`, `del`, `erase`, `rmdir` | File or directory deletion command detected. |
| `Clear-Disk`, `Format-Volume`, `Format-Partition`, `Remove-Partition`, `diskpart` | Disk or volume modification command detected. |
| `Restart-Computer`, `Stop-Computer`, `Stop-Service`, `Restart-Service`, `Stop-Process`, `taskkill` | System, service or process interruption command detected. |
| `Set-ExecutionPolicy` with `Unrestricted` or `Bypass` in the command extent | Permissive execution policy detected. |

The checks operate on parsed command AST nodes, so simply mentioning one of these words in a comment or quoted string does not normally trigger the command-name rule.

## 7.4 Limitations

Risk checks are advisory. They do not block or approve commands, and they do not understand all parameter values, aliases, dynamic command names, scripts, external executables or indirect side effects. A command with no warning is not guaranteed to be safe.

# 8. Live character-level highlighting

## 8.1 Compiled helper

`PDE-Live-Highlighting.ps1` defines the C# type `PDE.LevenshteinHelper` through `Add-Type` if that type is not already loaded in the PowerShell process.

The helper exposes:

| Method | Purpose |
|---|---|
| `GetDistance(string, string)` | Calculate case-insensitive Levenshtein distance using a C# dynamic-programming matrix. |
| `CommonPrefixLength(string, string)` | Count the matching initial characters, case-insensitively. |
| `GetAlignmentMap(string, string, int)` | Backtrack through the alignment matrix and return one colour value per typed character. |

The helper is warmed during module loading so that its initial JIT compilation is not first triggered by a user's keystroke. The type remains loaded for the lifetime of the PowerShell process. When replacing the C# implementation, restart PowerShell before loading the new type because .NET types added with `Add-Type` cannot normally be unloaded from the current process.

The C# helper accelerates edit-distance and alignment loops. It allocates a two-dimensional matrix for each distance/alignment operation; the code does not establish a measured sub-millisecond end-to-end latency guarantee.

## 8.2 Character colour values

`Get-PDECommandNameColorMap` returns one integer per typed character:

| Integer | Colour | Meaning |
|---:|---|---|
| 0 | Neutral | Not part of the coloured command token or no applicable classification. |
| 1 | Yellow | Character aligned to a known command or command prefix not present in indexed history. |
| 2 | Red | Typed character that does not align to the selected command candidate. |
| 3 | Green | Character aligned to a recognised command or command prefix present in indexed history. |

## 8.3 Exact command and valid prefix

If the typed name is an exact indexed command, every character is yellow unless the command name is in `HistoryCommandNames`, in which case every character is green.

If the typed name is a valid command prefix, every character is yellow unless the prefix is in `HistoryCommandPrefixes`, in which case every character is green.

## 8.4 Typo candidate selection

For an invalid spelling, the highlighter:

1. Searches from the longest leading prefix downwards until it finds a valid indexed command prefix.
2. If no useful leading prefix is found, tries progressively shorter typed suffixes.
3. Enumerates candidates with imperative loops and stores no more than 25 unique names.
4. Calculates distance, common-prefix length, history-use status and length difference for each candidate.
5. Selects the best candidate in a single pass using this priority: lowest edit distance, longest common prefix, previously used candidate, smallest length difference, then case-insensitive alphabetical order.
6. Uses the C# backtracking alignment map to classify each typed character.

If the selected candidate was found in the indexed history, aligned characters are green. Otherwise, aligned characters are yellow. Incorrect typed characters are red. If the candidate requires a character that the user omitted, the nearest typed character is marked red to make the omission visible.

The candidate count is capped at 25, but candidate enumeration may still scan part or all of the command-name set to find those candidates. The cap bounds the expensive distance/ranking work, not necessarily every lookup iteration.

## 8.5 Examples

Assuming `cls` is in PDE's indexed history and is the chosen nearest candidate:

| Typed input | Expected map | Explanation |
|---|---|---|
| `cls` | `G G G` | Exact recognised command found in indexed history. |
| `cld` | `G G R` | First two characters align with `cls`; final character does not. |
| `Get-Verb` | `Y Y Y Y Y Y Y Y` | Recognised command not present in indexed history. |
| `Get-PDEStatus` | All green when indexed in history | Exact command is in the history command-name set. |

These are examples dependent on the current command and history indexes, not hard-coded outputs.

## 8.6 Command-token-only colouring

`Get-PDELineColorMap` parses the active input line and visits `CommandAst` nodes. It applies the name map only to `CommandElements[0]`, which represents the command-name element. Parameters, arguments, quoted strings and other command elements remain neutral.

If a quoted or transformed command element has an extent length that does not match the command name returned by the AST, that element is left neutral rather than risking incorrect character offsets.

PowerShell separator tokens (`Pipe`, `Semicolon`, `Ampersand`, `AndAnd` and `OrOr`) are coloured yellow. They are separators, not command-name characters.

## 8.7 Per-keystroke processing and rendering

When the highlighter runs, it:

1. Reads the PSReadLine buffer and cursor offset.
2. Skips empty, multi-line or non-ASCII input.
3. Reads console width and cursor coordinates.
4. Skips rendering if the input would wrap or cursor geometry is uncertain.
5. Refresh-checks the command index.
6. Parses the active line into an AST and obtains the character colour map.
7. Writes contiguous runs using ANSI colour sequences.
8. Restores the original cursor coordinates.

The C# helper removes the Levenshtein matrix/backtracking loops from PowerShell, but `Parser.ParseInput`, PowerShell control flow, candidate discovery and terminal output still occur in the redraw path. Benchmark the complete path on the target terminal before making latency claims.

# 9. PSReadLine integration and keyboard handlers

## 9.1 Prediction and options

The loader defaults are:

| Configuration key | Default | Purpose |
|---|---:|---|
| `EnablePredictions` | `$true` | Enable PSReadLine predictions when supported. |
| `PredictionViewStyle` | `InlineView` | Select InlineView or ListView. |
| `MaximumHistoryCount` | `10000` | PSReadLine maximum history count. |
| `HistoryIndexLimit` | `1000` | PDE in-memory history index limit. |
| `EnableHistorySearch` | `$true` | Enable prefix-history navigation. |
| `EnableFuzzySuggestions` | `$true` | Enable fuzzy command suggestions by default. |
| `FuzzyMaximumDistance` | `2` | Maximum edit distance for fuzzy suggestions and live typo candidate selection. |
| `EnableToolTips` | `$true` | Enable PSReadLine tooltips when supported. |
| `EnableDiagnosticsLog` | `$false` | Enable PDE file logging. |
| `DiagnosticsLogPath` | `%LOCALAPPDATA%\PDE\PDE.log` | Default log location. |

PDE configures `PredictionSource = History` when the installed `Set-PSReadLineOption` exposes that parameter. If predictions are disabled, it sets the source to `None` where supported. The effective prediction state and reason are stored in `$global:PDE_State`.

## 9.2 Native token colours

`Invoke-PDEApplyOptions` maps available PSReadLine colour properties to console colours for commands, parameters, variables, strings, numbers, types, members, keywords, operators, comments, errors, default text, continuation prompts, emphasis and prediction text. It checks the installed options object before applying supported colour properties.

These native PSReadLine token colours are distinct from PDE's ANSI live overlay. PDE's yellow/red/green command-name classification is applied by the live renderer; PSReadLine's syntax colours continue to handle the rest of the input presentation.

## 9.3 Key handlers installed by the integration layer

| Key | Behaviour |
|---|---|
| UpArrow / DownArrow in InlineView | Prefix-based history search when `EnableHistorySearch` is enabled. Otherwise native previous/next history. |
| UpArrow / DownArrow in ListView | Previous/next prediction suggestion. |
| F8 / Shift+F8 in ListView | Backward/forward prefix-history search when enabled. |
| Ctrl+RightArrow in InlineView | `ForwardWord`, allowing the next inline prediction word to be accepted when the cursor is at the end; otherwise standard word movement. |
| Ctrl+RightArrow outside InlineView prediction mode | `NextWord`. |

## 9.4 Key handlers installed by the live highlighter

| Key | Behaviour |
|---|---|
| Printable ASCII characters 32–126 | Calls PSReadLine `SelfInsert`, then redraws highlighting. This preserves PSReadLine's native self-insert behaviour such as quote/bracket pairing where supported. |
| Backspace | Calls `BackwardDeleteChar`, then redraws. |
| Delete | Calls `DeleteChar`, then redraws. |
| Tab | Calls `TabCompleteNext`, then redraws. |
| Shift+Tab | Calls `TabCompletePrevious`, then redraws. |
| Ctrl+W, Ctrl+Backspace, Alt+Backspace | Calls `BackwardKillWord`, then redraws. |
| Ctrl+Delete | Calls `KillWord`, then redraws. |
| Ctrl+V, Shift+Insert | Sets the paste guard, calls PSReadLine `Paste`, clears the guard in `finally`, then redraws once after successful insertion. |

Left/right cursor movement is left to PSReadLine. The highlighter does not install custom redraw handlers for every cursor movement chord. This should be considered when validating visual behaviour after moving the cursor without changing the buffer.

## 9.5 Paste behaviour

PDE treats paste as one operation. It sets `PasteInProgress` before invoking PSReadLine's paste API, clears the flag in a `finally` block, and calls the highlighter once when paste completes. Multi-line and non-ASCII paste is left to PSReadLine by the highlighter's safety checks.

## 9.6 Rendering limitations

The live overlay is skipped when:

- The input is empty.
- The input contains a newline.
- The input contains non-ASCII characters.
- Console buffer width cannot be read or is too narrow.
- The line would wrap based on the current start column and input length.
- Cursor coordinates cannot be calculated safely.

The component uses ANSI escape sequences and `Console.SetCursorPosition`; terminal hosts can differ in their support and cursor-cell behaviour. Test Windows Terminal, legacy console hosts and any IDE terminal separately if they are part of the intended environment.

# 10. Configuration, runtime state and diagnostics

## 10.1 `Set-PDEOptions`

`Set-PDEOptions` updates only the parameters explicitly supplied, then calls `Invoke-PDEApplyOptions`.

| Parameter | Validation |
|---|---|
| `EnablePredictions` | Boolean |
| `PredictionViewStyle` | `InlineView` or `ListView` |
| `MaximumHistoryCount` | 100–100000 |
| `HistoryIndexLimit` | 100–10000 |
| `FuzzyMaximumDistance` | 1–4 |
| `EnableHistorySearch` | Boolean |
| `EnableToolTips` | Boolean |
| `EnableFuzzySuggestions` | Boolean |
| `EnableDiagnosticsLog` | Boolean |

Example:

```powershell
Set-PDEOptions -PredictionViewStyle ListView
Set-PDEOptions -EnablePredictions $false
Set-PDEOptions -EnableFuzzySuggestions $true -FuzzyMaximumDistance 3
Set-PDEOptions -EnableDiagnosticsLog $true
```

Configuration changes are session-scoped unless the corresponding values are changed in the loader or another persistent configuration layer.

## 10.2 Diagnostics functions

| Function | Purpose |
|---|---|
| `Get-PDEStatus` | Reports PDE, PowerShell and PSReadLine versions; command, prefix and history counts; prediction state; helper readiness; logging state and last error. |
| `Get-PDEStatistics` | Refreshes history/index data and reports command, prefix, history and history-command-name counts. |
| `Get-PDEDiagnostics` | Reports computer/host, PowerShell edition/version, OS, PSReadLine path/version, history path, console width, prediction support, C# helper readiness and log path. |
| `Get-PDEHelp` | Calls `Get-Help -Full` for a named command. |
| `Test-PDE` | Runs six built-in checks for PSReadLine, command index, AST parsing, unknown-character red mapping, command recognition and prediction availability. |

The updated diagnostics file must accompany the updated highlighter because the old `Test-PDE` called `Get-PDEInputHighlightClass`, which is no longer part of the refactored highlighter.

# 11. Complete function reference by file

## 11.1 `PDE-Logging.ps1`

- `Write-PDELog` — best-effort diagnostic file logging.
- `Test-PDESensitiveHistoryLine` — compiled-regex scan for selected credential patterns.
- `Add-PDEHistoryCommandName` — add a recognised history command name and all of its prefixes to the history-name sets.
- `Add-PDEHistoryEntry` — AST-validate and promote one interactive history line.

## 11.2 `PDE-Prompt-History.ps1`

- `prompt` — wrapper that tracks newly completed successful commands and returns the original prompt output.

The module also captures `$global:PDE_OriginalPrompt` and initialises `$global:PDE_LastHistId` when needed.

## 11.3 `PDE-Command-Index.ps1`

- `Update-PDEIndex` — discover available commands and build command/prefix indexes.
- `Test-PDECommandName` — report command recognition and command metadata.
- `Test-PDEHistoryLineRecognised` — full-AST validation for a history line; not the fast bulk import path.

## 11.4 `PDE-History-Index.ps1`

- `Get-PDEFastHistoryCommandNames` — use `PSParser.Tokenize` to extract and resolve command tokens from one saved line.
- `Add-PDEHistoryIndexEntryFast` — append one validated bulk-import line and its command names.
- `Update-PDEHistory` — rebuild the newest-first history list and command-name prefix sets.

## 11.5 `PDE-AST-Analysis.ps1`

- `Get-PDECommandAnalysis` — return syntax, command-recognition and risk-warning details.
- `Test-PDESyntax` — return a compact syntax-validation object.

## 11.6 `PDE-Fuzzy-Suggestions.ps1`

- `Get-PDELevenshteinDistance` — PowerShell implementation of standard Levenshtein distance.
- `Get-PDESuggestions` — prefix/fuzzy search across history and command indexes.

## 11.7 `PDE-PSReadLine-Integration.ps1`

- `Invoke-PDEApplyOptions` — apply supported PSReadLine colours, predictions and navigation bindings.
- `Set-PDEOptions` — validate configuration changes and apply them.

## 11.8 `PDE-Live-Highlighting.ps1`

- `PDE.LevenshteinHelper` — inline C# static class with distance, common-prefix and alignment methods.
- `Get-PDECommandNameColorMap` — return per-character colour values for a command name.
- `Get-PDELineColorMap` — return a colour map for an entire input line, applying command colours only to command-name extents.
- `Invoke-PDELiveHighlight` — render the safe single-line input overlay.
- `Install-PDELiveHighlightHandlers` — register character insertion, deletion, completion, word-deletion and paste handlers.

The refactored highlighter intentionally removes the earlier PowerShell functions `Get-PDEHistoryPrefixMatch`, `Get-PDEInputHighlightClass` and `Get-PDECharacterAlignmentMap`. Their roles are replaced by the command-name map and the compiled C# helper.

## 11.9 `PDE-Management-Diagnostics.ps1`

- `Get-PDEStatus` — current component status.
- `Get-PDEStatistics` — index and history counts.
- `Get-PDEDiagnostics` — environment and helper diagnostics.
- `Get-PDEHelp` — full help for a command.
- `Test-PDE` — six-check built-in self-test.

# 12. Testing and validation

## 12.1 Built-in checks

Run:

```powershell
Test-PDE
```

The refactored test suite checks:

1. PSReadLine is loaded.
2. The command index contains commands.
3. A sample pipeline parses into at least two command AST nodes.
4. A deliberately unrecognised repeated-character command maps entirely to red.
5. `Get-Date` is recognised.
6. Predictive IntelliSense is available according to PDE's PSReadLine configuration state.

`Test-PDE` refreshes the command and history indexes before running these checks. A failed prediction check can indicate version or configuration support rather than a failure of AST or highlighting logic.

## 12.2 Character-map checks

For the refactored colour map, use:

```powershell
foreach ($name in 'cls','cld','Get-Verb','Get-PDEStatus') {
    $map = Get-PDECommandNameColorMap -Name $name
    $labels = foreach ($value in $map) {
        switch ([int]$value) {
            0 { 'N' }
            1 { 'Y' }
            2 { 'R' }
            3 { 'G' }
        }
    }
    [pscustomobject]@{
        Command = $name
        Characters = $name.ToCharArray() -join ' '
        ColourMap = $labels -join ' '
    }
} | Format-Table -AutoSize
```

In Windows PowerShell 5.1, if piping a `foreach` statement causes an empty-pipeline parse error, assign the loop output to `$results` first and then run `$results | Format-Table -AutoSize`.

Expected examples depend on the current index:

- `cls` should be green if `cls` is indexed as a history command.
- `cld` should align to `cls` when that is selected as the best candidate; expected `G G R` when `cls` is used.
- A known unused command such as `Get-Verb` should be yellow if it has not appeared in the indexed history.
- A previously indexed command such as `Get-PDEStatus` should be green.

## 12.3 Keyboard and terminal tests

Manually test all of the following in the actual terminal used for development:

- Type command names one character at a time and confirm per-character colours.
- Move the cursor left and right and check cursor position and display stability.
- Backspace and Delete.
- Tab and Shift+Tab completion.
- Ctrl+W, Ctrl+Backspace, Alt+Backspace and Ctrl+Delete.
- UpArrow and DownArrow under InlineView and ListView.
- Ctrl+RightArrow with an available inline prediction.
- Single-line Ctrl+V.
- Multi-line Ctrl+V.
- Shift+Insert.
- A long line that approaches the console width; it should be left to PSReadLine rather than manually repainted if wrapping would occur.
- Non-ASCII input; it should be left to PSReadLine.

## 12.4 Validation record and evidence boundary

A previous build was tested in Windows PowerShell 5.1.26100.9818 with PSReadLine 2.4.5. The user reported six of six built-in tests passing, nineteen of nineteen additional automated checks passing, and character-map results including `cls = G G G` and `cld = G G R` for the earlier character-level implementation.

Those results are historical evidence for the earlier implementation. They must **not** be presented as proof that the later C#-optimised four-file replacement set has been installed or passed runtime testing. After installing the optimised files, rerun `Test-PDE`, the character-map checks, and the physical keyboard tests, then update this section with the actual new results.

# 13. Installation and maintenance

## 13.1 Profile bootstrap

The user's current profile bootstrap follows this pattern:

```powershell
# PowerShell Developer Environment V2 - Profile Loader
$PdeProfilePath = Join-Path $HOME 'PDE-V2.ps1'

if (Test-Path -LiteralPath $PdeProfilePath -PathType Leaf) {
    . $PdeProfilePath
} else {
    Write-Warning "PDE V2 profile not found: $PdeProfilePath"
}
```

The main `PDE-V2.ps1` loader then dot-sources the nine feature scripts.

## 13.2 Module directory

In the current installation, the feature files are located in:

```text
<directory containing $PROFILE>\Modules\
```

The corresponding loader expression is:

```powershell
$PDE_ModuleDirectory = Join-Path (Split-Path -Parent $PROFILE) 'Modules'
```

The packaged standalone loader uses `$PSScriptRoot\Modules` instead. Do not mix these path conventions without checking the actual folder layout.

## 13.3 Required files

The expected runtime module directory contains all nine files:

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

For the C#-optimised character-highlighting refactor, replace these four existing files:

1. `PDE-Live-Highlighting.ps1`
2. `PDE-History-Index.ps1`
3. `PDE-Logging.ps1`
4. `PDE-Management-Diagnostics.ps1` (compatibility update for the removed highlighter functions)

The other five feature files remain in place. Do not add duplicate copies or rename the files expected by the loader.

## 13.4 Unblocking downloaded files

When downloaded `.ps1` files are blocked by Windows under `RemoteSigned`, unblock only the trusted PDE files after checking their source:

```powershell
$modules = Join-Path (Split-Path -Parent $PROFILE) 'Modules'
Get-ChildItem -LiteralPath $modules -Filter 'PDE-*.ps1' -File | Unblock-File
```

Do not change the machine or user execution policy to `Unrestricted` or `Bypass` just to load the PDE files. Unblocking removes the downloaded-file mark; it does not validate the script's contents.

## 13.5 First-start validation

After opening a fresh PowerShell session, run:

```powershell
Get-PDEStatus | Format-List
Test-PDE
Get-PDEStatistics | Format-List
Get-PDEDiagnostics | Format-List
```

For the refactored C# helper, check:

```powershell
[bool]('PDE.LevenshteinHelper' -as [type])
$global:PDE_State.LevenshteinHelperReady
```

If the C# helper has changed since it was first added to the process, close and reopen PowerShell before reloading the updated file.

## 13.6 Safe update procedure

1. Back up the four files being replaced.
2. Copy the replacement files into the existing `Modules` directory using the exact filenames.
3. Unblock only those downloaded PDE files after verifying them.
4. Restart PowerShell if the compiled C# helper has changed.
5. Reload the profile.
6. Run `Get-PDEStatus` and `Test-PDE`.
7. Run the character-map checks.
8. Complete physical keyboard, cursor and clipboard tests.
9. Keep backups until the refactor has passed in the intended terminal.

# Appendix A. Quick reference

| Task | Command |
|---|---|
| Show PDE status | `Get-PDEStatus \| Format-List` |
| Run built-in tests | `Test-PDE` |
| Show statistics | `Get-PDEStatistics \| Format-List` |
| Show environment diagnostics | `Get-PDEDiagnostics \| Format-List` |
| Force command-index refresh | `Update-PDEIndex -Force` |
| Refresh history index | `Update-PDEHistory` |
| Recognise a command | `Test-PDECommandName -Name 'Get-Date'` |
| Analyse a command | `Get-PDECommandAnalysis -Text 'Get-Date \| Where-Object { $_ }'` |
| Test syntax | `Test-PDESyntax -Text 'Get-Date \| Where-Object { $_ }'` |
| Get command suggestions | `Get-PDESuggestions -Prefix 'Get-Da' -Source Command` |
| Get fuzzy suggestions | `Get-PDESuggestions -Prefix 'Get-Procss' -Source Command -Fuzzy` |
| Inspect per-character colours | `Get-PDECommandNameColorMap -Name 'cld'` |
| Inspect a complete line's colour map | `Get-PDELineColorMap -Text 'Get-Date'` |
| Change prediction view | `Set-PDEOptions -PredictionViewStyle ListView` |
| Disable predictions | `Set-PDEOptions -EnablePredictions $false` |
| Enable diagnostics logging | `Set-PDEOptions -EnableDiagnosticsLog $true` |

---

**End of PDE Command Intelligence 3.1.2 Technical Documentation.**
