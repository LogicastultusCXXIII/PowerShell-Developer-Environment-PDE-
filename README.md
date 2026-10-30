# PowerShell Developer Environment (PDE) V2

**Technical Documentation & User Guide**

A unified PowerShell profile for command-line productivity, command discovery, history analysis, security awareness, system diagnostics, and developer workflows.

| **DOCUMENT DETAILS** | **VALUE** |
|---|---|
| Profile version | V2 (as labelled in the supplied script) |
| Target shells | Windows PowerShell 5.1 and PowerShell 7+ |
| Primary dependency | PSReadLine for interactive editing, history filtering, and command validation integration |
| Optional integrations | Terminal-Icons, posh-git, PSFzf, zoxide, and Oh My Posh when available |
| Document purpose | Explain the supplied implementation, its commands, configuration, limitations, and validation requirements |
| Review status | Static review of the supplied source; not runtime certification |

> **IMPORTANT — SECURITY AND VALIDATION STATUS**
>
> PDE V2 registers a PSReadLine command-validation handler, but the supplied profile does not explicitly bind Enter to `ValidateAndAcceptLine`. Microsoft documents that `CommandValidationHandler` is called from `ValidateAndAcceptLine` and shows Enter being bound to that function. Until the binding is added and tested, do not assume that the command-risk guard runs when Enter is pressed. The typo-suggestion path inside that handler has the same dependency.
>
> The separate `Invoke-PSProfileLiveTypoHighlight` function is not connected to printable-key handlers and does not repaint the console. It returns a suggestion object when it finds a match. This version should therefore be described as providing **command typo suggestions**, not continuous live highlighting.
>
> Risk checks and secret detection are heuristic. They are useful warning and auditing tools, not a security boundary or a guarantee that all credentials or dangerous commands will be detected.

# Document map

| **SECTION** | **WHAT IT COVERS** |
|---|---|
| 1. Overview and scope | Purpose, main capabilities, operating environment, and boundaries. |
| 2. Startup and architecture | Initialisation order, shared configuration, runtime state, and design. |
| 3. Command intelligence | Command indexing, edit distance, keyboard scoring, ranking, confidence, and typo suggestions. |
| 4. PSReadLine and history | Predictions, colours, key bindings, history filtering, and history analytics. |
| 5. Security features | Secret detection, history purging, command-risk classification, and validation-handler limitations. |
| 6. System and network diagnostics | Computer, storage, network, firewall, service, and port inspection. |
| 7. Developer workflow tools | Project discovery, .NET, Python, Node/npm, Docker, and project validation. |
| 8. Configuration and state | Configuration keys, validation, status reporting, and runtime state. |
| 9. Command reference | Grouped reference for the supplied public functions and aliases. |
| 10. Static review and recommended fixes | Remaining issues, known limitations, and optional design improvements. |
| 11. Installation and validation | Safe installation, first-launch checks, functional tests, and rollback. |
| Appendix A | Quick-start command sheet. |

## How to read this document

This document separates three types of information:

1. **Implemented in source** — behaviour directly visible in the supplied PDE V2 script.
2. **Environment-dependent** — behaviour that depends on the installed PowerShell version, PSReadLine version, host, operating system, or optional tools.
3. **Not yet verified or fully connected** — behaviour that needs a code change or runtime test before it should be treated as reliable.

> **Evidence boundary**
>
> This document is based on static inspection of the supplied source. No execution, cross-version test, Pester test run, or security penetration test is claimed. All runtime behaviour should be checked in a disposable test profile before PDE V2 is relied on in a normal working session.

# 1. Overview and scope

## 1.1 Purpose

PowerShell Developer Environment (PDE) V2 is a user-profile script intended to make interactive PowerShell sessions more useful for software development and system administration. It combines PSReadLine configuration with custom functions for discovering commands, suggesting corrections for mistyped command names, analysing command history, checking local system and network state, navigating software projects, and invoking common development tools.

When the profile is loaded, it creates shared configuration and runtime state, defines its functions and aliases, attempts to import PSReadLine, applies interactive settings when PSReadLine is available, loads selected optional integrations, builds command and history indexes, configures the command-risk and history handlers, and records the time taken by its initialisation sequence.

## 1.2 Main capability groups

| **CAPABILITY** | **PRACTICAL PURPOSE** |
|---|---|
| Command intelligence | Index installed command names and rank possible corrections using edit distance, approximate keyboard distance, and previous command use. |
| Command typo suggestions | Suggest likely command names through the command-validation handler when that handler is invoked. A separate history-based helper can return a suggestion object, but it is not connected to keyboard events. |
| PSReadLine configuration | Configure prediction, completion, history behaviour, syntax colours, and selected keyboard shortcuts while retaining the standard printable and navigation handlers. |
| History management | Filter selected sensitive command lines, count recognised command usage, search history, identify duplicates, create approximate activity groups, and export filtered history. |
| Security awareness | Scan history for selected credential patterns, classify selected command patterns as LOW, MEDIUM, HIGH, or CRITICAL, and register a configurable PSReadLine validation handler. |
| System and network diagnostics | Inspect CPU, memory, filesystem space, services, startup entries, installed software, certificates, adapters, routes, DNS, firewall profiles, TCP listeners, and connectivity. |
| Developer workflow | Discover projects, identify likely project roots, search files and source references, and provide Git, .NET, Python, Node/npm, and Docker helpers. |
| Project validation | Create a dry-run plan for supported project types and optionally run the available build/test commands from the detected project root. |
| Session management | Display profile status, configuration, diagnostics, loaded integrations, command-index counts, and startup duration. |

## 1.3 Intended operating environment

The script is primarily Windows-oriented. It uses Windows networking and system cmdlets when available, reads Windows registry uninstall locations, and uses tools such as `explorer.exe` and `notepad.exe`. Some functions use .NET or PowerShell features that may also work elsewhere, but the supplied implementation does not establish a tested cross-platform guarantee.

Windows PowerShell 5.1 and PowerShell 7+ use different profile locations. PSReadLine features and available options can also vary by installed PSReadLine version and host. Optional tools are only loaded when found; the script does not install them.

## 1.4 What PDE V2 is not

PDE V2 is not a replacement for PowerShell, PSReadLine, an IDE, or a terminal emulator. It is not a full endpoint-security product and does not replace backups, least-privilege access, Windows security controls, or careful administrative practice.

The profile does not automatically monitor every command. `ExecutionTracker` is populated only when a script is run through `Measure-PSProfileCommand`. `Get-PSHistoryErrors` therefore reports failed measurements recorded by that function, not every error produced by the PowerShell session.

The command matcher is a local algorithmic suggestion system, not an AI model. The project checker is a small validation planner, not a full build system or dependency manager.

# 2. Startup sequence and architecture

## 2.1 Startup sequence

The supplied script initialises the environment in the following functional order:

| **ORDER** | **STARTUP ACTION** | **RESULT** |
|---:|---|---|
| 1 | Start a `Stopwatch` and create the global configuration and state hashtables. | Shared settings and runtime state are available to later functions. |
| 2 | Create the approximate QWERTY letter-coordinate map and external-tool subcommand catalogue. | Data for keyboard scoring and manual subcommand suggestions is available. |
| 3 | Define internal helpers and public command, history, security, diagnostic, project, and developer functions. | PDE commands become available in the current session. |
| 4 | Attempt to import PSReadLine unless the host name contains `ISE`. | Interactive editing features can be configured when the module is available. |
| 5 | Configure prediction, history handling, syntax colours, completion, and selected key bindings. | PSReadLine behaviour is customised where supported. |
| 6 | Attempt to load optional modules and initialise zoxide or Oh My Posh when their commands are available. | Additional prompt, navigation, icon, or fuzzy-search integrations may be enabled. |
| 7 | Build the installed-command cache and parse recent PSReadLine history. | Command metadata and recognised command-use counts are indexed. |
| 8 | Register the selected security validation handler and stop the startup timer. | The handler-registration result and profile initialisation duration are recorded. |

The script catches a number of optional setup errors so that a missing integration does not necessarily prevent the profile from loading. This does not prove that every setup operation succeeds; check the status functions after startup.

## 2.2 Shared configuration

`$global:PSProfileConfig` is a hashtable containing the feature settings. It controls typo-suggestion behaviour, keyboard scoring, security mode, history filtering, PSReadLine prediction, history indexing limits, and optional developer integrations.

Unlike the earlier version of the documentation, the current script uses the main configuration values in its functions. See Section 8 for the key-by-key description and value validation.

## 2.3 Runtime state

`$global:PSProfileState` stores generated data and installation status.

| **STATE MEMBER** | **ROLE** |
|---|---|
| `CommandNameCache` / `CommandNameLookup` | Sorted command-name list and metadata lookup containing command type, source, and executable name. |
| `HistoryCommandCounts` | Count of recognised installed commands found in parsed history or recorded by the history handler. |
| `HistoryCommandsByLength` | Groups recognised history command names by string length to reduce the candidate set during history-based typo matching. |
| `PSReadLineReady` | Records whether PSReadLine imported successfully. |
| `SecurityGuardInstalled` / `SecurityGuardError` | Records whether the command-validation handler was registered successfully and any installation error. It does not verify the Enter key binding. |
| `HistoryFilterInstalled` / `HistoryFilterError` | Records whether the history-filter handler was registered successfully and any installation error. |
| `LiveTypoKeyBindings` | Retained state member for a key-handler count; the current script does not populate it with custom printable-key handlers. |
| `OptionalModulesLoaded` / `ModuleLoadTimes` | Names of optional integrations loaded and their measured import times. |
| `StartupDurationMs` / `CacheBuiltTime` | Startup duration and the last command/history cache build time. |
| `ExecutionTracker` | An in-memory list of records created by `Measure-PSProfileCommand`; it is not a global command or error monitor. |
| `MaxExecutionRecords` | Maximum number of execution measurement records retained. The current default is 500. |

## 2.4 Design characteristics

- **Single-file profile:** configuration, functions, integrations, and diagnostics are kept in one script rather than separate PowerShell modules.
- **In-memory indexing:** command metadata and history counts are rebuilt at startup or when `Update-PSProfile` is called.
- **AST-based parsing:** several history and command functions use the PowerShell language parser to identify command nodes rather than relying only on splitting text at spaces.
- **Optional dependencies:** integrations are loaded only when their module or command is available. Many optional operations use `try/catch` or `-ErrorAction` handling.
- **Session-scoped configuration:** changes made with `Set-PSProfileConfig` or `Set-PSProfileSecurityMode` affect the current session. To make a setting permanent, change the profile source or add another persistence mechanism.

# 3. Interactive command intelligence

## 3.1 Command discovery and indexing

`Update-PSCommandCache` uses `Get-Command -Name * -All` to enumerate commands visible to the current session. It stores command metadata in `CommandNameLookup` and a sorted list of unique names in `CommandNameCache`.

For external applications with extensions such as `.exe`, `.com`, `.cmd`, or `.bat`, the cache also includes the executable name without its extension. The lookup preserves the original executable name in its metadata.

The function then reads the PSReadLine history file. Its `-HistoryLines` parameter defaults to 10,000 and accepts values from 100 to 50,000. The actual number of lines read is also limited by `MaxHistoryIndexCount` in the configuration.

Each history line is checked by `Test-PSProfileSensitiveCommandLine`. Lines identified as potentially sensitive are excluded from indexing. Remaining lines are parsed with the PowerShell language parser; `CommandAst` nodes are used to identify command names. Recognised aliases are resolved to their underlying command names where possible. This is more structured than simply splitting every line at its first space, but it still depends on parseable history and commands present in the current command lookup.

## 3.2 Edit-distance matching

`Get-PSProfileEditDistance` uses a dynamic-programming matrix to calculate a string-edit distance. It accounts for insertion, deletion, substitution, and adjacent character transposition.

The algorithm is the **Optimal String Alignment (OSA) distance**, a restricted Damerau-style variant. It is not the unrestricted Damerau-Levenshtein algorithm. A maximum-distance threshold limits the candidates considered and returns a value above the limit when the strings are too different.

```powershell
Get-PSProfileEditDistance -Source 'statsu' -Target 'status' -MaximumDistance 2
```

## 3.3 Keyboard-aware scoring

`Get-PSProfileKeyboardDistance` compares two letters using an approximate QWERTY coordinate map. The map models the stagger between the three letter rows. It currently contains letter positions rather than a complete configurable keyboard layout for every punctuation key or international keyboard.

When `KeyboardAwareScoring` is enabled, the command matcher uses the mismatch indexes from `Get-PSProfileTypoMismatchIndexes` and adds a keyboard penalty for substitutions at those positions. Insertions, deletions, and mismatches without a corresponding coordinate use a fallback penalty.

## 3.4 Candidate ranking

`Get-PSProfileCommandMatches` ranks candidate installed commands using edit distance, keyboard mismatch penalty, and prior command use. The supplied ranking expression is:

```text
RankScore = (EditDistance × 100) + (KeyboardPenalty × 10) - (min(HistoryUses, 50) × 2)
```

Results are sorted first by the lowest edit distance, then by the lowest rank score, then by higher history use, and finally by command name. This makes textual similarity more important than familiarity while allowing previous use to influence close matches.

`MaximumEditDistance` is used by `Test-PSProfileCommandSpelling`. The matching function also accepts its own `-MaximumDistance` parameter.

## 3.5 Confidence report

`Get-PSProfileCommandConfidence` converts a match into a heuristic score from 0 to 100. It starts at 100, subtracts a length-sensitive edit-distance penalty and a keyboard penalty, then adds a capped bonus for previous history use or subtracts a penalty when no prior use is recorded.

Scores are labelled:

- **High:** 80 or above.
- **Medium:** 55 to 79.9.
- **Low:** below 55.

These labels are heuristic rankings, not calibrated probabilities. The returned object explicitly sets `IsStatisticalProbability` to false.

## 3.6 Command typo suggestions

The current source has two related typo-suggestion paths. Neither provides continuous coloured highlighting while the user types.

### Command-validation suggestion

The command-validation scriptblock created by `Set-PSProfileSecurityMode` checks the command name when PSReadLine invokes the validation handler. If typo suggestions are enabled and the command is not in the command lookup, it searches the installed-command cache and can display a message such as:

```text
[PDE TYPO] Did you mean 'Get-ChildItem'? (suggestion only)
```

This path depends on the PSReadLine validation handler actually being invoked. The supplied profile does not explicitly bind Enter to `ValidateAndAcceptLine`; see Section 5.3.

### History-based helper

`Invoke-PSProfileLiveTypoHighlight` reads the current PSReadLine buffer, extracts the first command token, and searches indexed history using `Get-PSProfileBestHistoryCommand`. If it finds a suitable non-prefix match, it returns a `PSCustomObject` containing the typed command, suggested command, distance, display mode, and message.

The helper does not repaint the console, alter the command buffer, or write a visible suggestion itself. The supplied script does not connect this helper to printable-key handlers or another event, so it should not be described as active live highlighting.

## 3.7 Subcommand catalogue

`PSProfileSubcommandCatalog` contains selected common subcommands for Git, dotnet, npm, Docker, Python, and pip. `Get-PSProfileCommandContext` parses a command line and checks the second command element against the relevant list. It can return a close subcommand suggestion.

This is a lightweight lookup helper. It is not a complete parser for each external tool, and the current validation handler does not call it automatically.

# 4. PSReadLine and command history

## 4.1 Predictive IntelliSense

When PSReadLine imports successfully, the profile applies the configured prediction source and view style.

The default prediction source is `HistoryAndPlugin`, and the default view is `InlineView`. The script requests the configured source only when PowerShell is version 7.2 or later and the installed PSReadLine version is 2.2.0 or later. Otherwise, it falls back to `History`. If the requested source cannot be applied, the script also attempts the History fallback.

Plugin-based predictors require compatible versions and available predictor modules. PDE V2 does not install predictor plugins itself. `Set-PSProfileConfig` permits `None`, `History`, `Plugin`, and `HistoryAndPlugin` as prediction-source values, subject to the installed PSReadLine version.

## 4.2 Editing and completion settings

| **SETTING** | **CONFIGURED BEHAVIOUR** |
|---|---|
| Maximum history count | Sets the PSReadLine maximum history count to 50,000. |
| History save style | Uses `SaveIncrementally`, so accepted commands are saved as the session runs, subject to the history handler. |
| History navigation | Enables cursor-to-end behaviour for history search and suppresses duplicate entries during recall. |
| Completion menu | Binds Tab to `MenuComplete`, Shift+Tab to `TabCompletePrevious`, and Ctrl+Spacebar to `MenuComplete`. |
| Search and screen | Binds Ctrl+R to reverse history search, Ctrl+S to forward history search, and Ctrl+L to clear the screen. |
| Suggestion acceptance | Binds Alt+RightArrow to `AcceptNextSuggestionWord` when PSReadLine is version 2.2.0 or later. |
| Other options | Enables tooltips where supported, configures word delimiters, disables the audible bell, and sets the completion query threshold to 200. |

Unsupported options are generally applied with `-ErrorAction SilentlyContinue`, so an unavailable option may be skipped without stopping profile startup.

## 4.3 Syntax colours

The custom palette configures colours for commands, parameters, strings, operators, variables, errors, comments, keywords, numbers, types, members, default text, and emphasis. `InlinePrediction` is added when PSReadLine is version 2.2.0 or later.

The current palette does not configure a separate `Selection` colour. Colours change presentation only; they do not change command execution.

## 4.4 Key bindings

The current profile deliberately leaves the standard printable-character, navigation, deletion, undo/redo, and paste handlers in place. It does not register the large collection of custom character handlers or wrap standard editing keys to repaint a live typo overlay.

It explicitly configures only the completion, search, clear-screen, and suggestion-acceptance shortcuts listed in Section 4.2. It does **not** explicitly bind Enter in the supplied source.

> **Compatibility and validation note**
>
> Key bindings can vary by PSReadLine version, edit mode, terminal host, keyboard layout, and other modules. Use `Get-PSReadLineKeyHandler` to inspect the actual bindings in the running session. Test Tab, Shift+Tab, Ctrl+R, Ctrl+S, Ctrl+L, Alt+RightArrow, Enter, paste, Backspace, Delete, and arrow navigation in each terminal you use.

## 4.5 History filtering

`Set-PSProfileHistoryFilter` configures PSReadLine's `AddToHistoryHandler` when PSReadLine is available.

For each submitted line, the handler:

1. Calls `Test-PSProfileSensitiveCommandLine` to check for selected credential patterns and AST-based sensitive assignments or parameters.
2. Returns `SkipAdding` if the line is flagged as sensitive.
3. Parses the command line and updates command-use counts for recognised commands.
4. Returns `SkipAdding` if parsing fails or an exception occurs.
5. Returns `MemoryAndFile` for a line that passes the checks.

`HistoryFilterEnabled` controls whether the handler is installed. Setting it to false asks PSReadLine to remove the custom handler by setting `AddToHistoryHandler` to `$null`. The profile records whether the handler was installed and any registration error.

The filter is a pattern-based precaution, not a guarantee. It cannot recognise every credential format, does not remove secrets already present in history, and may skip syntactically incomplete lines even when they do not contain a secret.

Microsoft documents `MemoryAndFile`, `MemoryOnly`, and `SkipAdding` as supported history-handler results. See the [Set-PSReadLineOption documentation](https://learn.microsoft.com/en-us/powershell/module/psreadline/set-psreadlineoption).

## 4.6 History analytics

The history functions read the current PSReadLine history file and provide:

- Total history-entry counts and top recognised commands.
- Counts of external applications used in history.
- Unique history lines.
- Approximate activity phases based on groups of entries, not actual timestamps.
- Exact repeated command lines.
- Pattern-based history searching.
- CSV, JSON, and text exports that skip lines flagged by the current sensitive-command scanner.
- Failed records from `ExecutionTracker`, but only when those records were created through `Measure-PSProfileCommand`.

`Get-PSHistoryStats` and the cache builder use AST parsing to identify commands. `Get-PSHistoryTimeline` also uses AST parsing for the first recognised command in each entry. Timeline phases are based on history order; they are not time-of-day or timestamp reports.

# 5. Security features and trust boundaries

## 5.1 History secret detection

`Test-PSProfileSensitiveCommandLine` checks selected text patterns and parses the command line for additional AST indicators. The supplied rules include patterns for:

- Private-key headers.
- AWS access-key identifiers.
- GitHub and Slack token formats.
- JWT-like values.
- Quoted credential assignments, such as password, secret, API-key, or token variables.
- Sensitive command parameters.
- Plaintext `ConvertTo-SecureString` usage.
- Windows `cmdkey` credential commands.
- AST variable assignments with sensitive names and AST command parameters with sensitive names.

`Find-PSHistorySecrets` scans the history file and reports a line number and rule description. It intentionally displays a redacted placeholder rather than printing the full matching line. It also treats lines inside a detected private-key block as sensitive until the matching end marker is reached.

### Usage

```powershell
# Report likely secrets without changing the history file
Find-PSHistorySecrets

# Preview how many lines would be removed
Find-PSHistorySecrets -Purge -WhatIf

# Remove the currently flagged lines
Find-PSHistorySecrets -Purge
```

The custom `-WhatIf` switch is a preview option implemented by this function. It is not implemented through `SupportsShouldProcess` and is not the standard PowerShell `ShouldProcess` mechanism.

### History purge caution

The current purge implementation writes the retained lines to a temporary file and replaces the history file. It does **not** create a separate timestamped plaintext backup. This avoids creating another obvious copy of the flagged lines, but it does not guarantee secure erasure from storage media, filesystem snapshots, backups, or other PowerShell sessions that may still hold history in memory.

Close other PowerShell sessions that may write to the same history file before purging. Rotate credentials that may have been exposed; removing a history line does not invalidate a credential.

## 5.2 Command-risk classification

`Get-PSCommandRisk` parses a supplied command line into PowerShell AST command nodes and checks a fixed list of command and argument patterns. It returns the original command text, risk level, trigger descriptions, evaluation time, and `IsSecurityBoundary = $false`. It analyses the text; it does not execute the command.

| **LEVEL** | **EXAMPLES OF PATTERNS IN THE SCRIPT** | **MEANING** |
|---|---|---|
| LOW | No listed risk pattern found. | No configured risk pattern was detected. This is not proof that the command is safe. |
| MEDIUM | Selected service, process, permission, or configuration changes, such as `Stop-Service`, `Restart-Service`, `Stop-Process`, `Set-ItemProperty`, or `Set-Acl`. | Potentially disruptive operation requiring review. |
| HIGH | Parse errors, unresolved dynamic command names, selected execution-policy, shutdown/restart, account or firewall changes, and recursive forced deletion that does not match the protected-path CRITICAL rules. | Elevated system impact; Warn mode reports it and Strict mode is intended to block it. |
| CRITICAL | Selected disk-management commands, recursive forced deletion targeting a drive root or Windows system directory, and selected `cmd.exe` recursive quiet deletion against a drive path. | Potentially destructive operation; Warn mode reports it and Strict mode is intended to block it. |

The classification is based on a limited set of command names, parameters, and path patterns. It is not a complete analysis of the effects of a PowerShell pipeline, script, executable, or indirect command.

## 5.3 Security mode and command-validation handler

`Set-PSProfileSecurityMode` accepts `Off`, `Warn`, or `Strict`.

- **Off:** attempts to remove the PSReadLine command-validation handler.
- **Warn:** the handler is intended to display warnings for HIGH and CRITICAL findings, then allow the command line to continue.
- **Strict:** the handler is intended to throw an exception for both HIGH and CRITICAL findings, preventing the validated command line from being accepted.

MEDIUM findings are returned by `Get-PSCommandRisk`, but the current handler does not warn about or block MEDIUM findings.

### Enter-binding integration gap

The profile registers the handler using:

```powershell
Set-PSReadLineOption -CommandValidationHandler $guard
```

However, the supplied source does not include an explicit Enter binding to `ValidateAndAcceptLine`. Microsoft documents that `CommandValidationHandler` is called from `ValidateAndAcceptLine` and its example binds Enter to that function. Therefore, successful handler registration alone does not prove that pressing Enter invokes the handler.

The source should add and test the corresponding key binding before the guard is treated as active. For reference, see the [Microsoft PSReadLine command-validation documentation](https://learn.microsoft.com/en-us/powershell/module/psreadline/set-psreadlineoption).

## 5.4 Security status reporting

`Get-PSProfileSecurityStatus`, `Test-PSProfile`, and `Get-PSProfileStatus` report the selected security mode and whether the handler-registration call succeeded.

`SecurityGuardInstalled` means that `Set-PSReadLineOption` accepted the handler without reporting an installation error. It does **not** independently verify that Enter is bound to `ValidateAndAcceptLine` or that the handler is invoked during normal command submission. The `PSReadLineGuardHooked` property should therefore be interpreted as handler-registration status, not proof of active execution enforcement.

The history-filter status is tracked separately through `HistoryFilterInstalled` and `HistoryFilterError`.

## 5.5 Security limitations

- Risk classification uses a small heuristic catalogue, not semantic analysis or a comprehensive command policy.
- Dynamic command names, aliases, variables, encoded arguments, nested scripts, external executables, and indirect effects may not be recognised reliably.
- A LOW classification means only that the current rules did not identify a configured trigger.
- The history filter and scanner cannot guarantee that every secret is detected or removed.
- Exported history is filtered using the same pattern-based scanner and is not guaranteed to be free of all sensitive information.
- Do not use the profile as a substitute for backups, least privilege, Windows Defender, firewall policy, execution controls, or tested administrative procedures.

# 6. System and network diagnostics

The system and network functions provide local inspection helpers. They gather information when called; they do not continuously monitor the computer or automatically repair detected problems.

| **FUNCTION** | **INFORMATION RETURNED** |
|---|---|
| `Get-SystemInfo` | Computer name, user name, operating-system caption, PowerShell version, visible RAM totals, and current folder. |
| `Get-CPUUsage` | CPU name, average WMI `LoadPercentage` across available processor instances, total core count, and logical processor count. |
| `Get-RamUsage` | Total, used, and free visible operating-system memory in GB, plus percentage used. |
| `Get-DiskSpace` | Filesystem PSDrive name, root, estimated capacity, free space, and percentage free. |
| `Get-DiskHealth` | Compatibility wrapper around `Get-DiskSpace`; it does not inspect physical disk health or SMART status. |
| `Get-ServiceHealth` | Service counts grouped by current service status. |
| `Get-StartupPrograms` | `Win32_StartupCommand` entries, including name, command, location, and user. |
| `Get-InstalledSoftware` | Software uninstall-registry entries from standard HKLM and HKCU registry locations; optional display-name filtering. |
| `Get-CertificateInfo` | Subject, expiry, thumbprint, and private-key presence in the CurrentUser `My` or `Root` certificate store. |
| `Get-NetworkInfo` | Computer/domain names, non-loopback IPv4 addresses, and configured IPv4 DNS servers when the relevant cmdlets are available. |
| `Get-NetworkAdapters` | Adapter name, description, status, link speed, and MAC address. |
| `Get-NetworkRoutes` | IPv4 destination prefixes, next hops, metrics, and interface aliases. |
| `Get-FirewallStatus` | Firewall profile enabled state and inbound/outbound default actions. |
| `Get-ListeningPorts` | Listening TCP endpoints, owning process IDs, and process names when resolvable. |
| `Test-TcpPort` | Attempts a TCP connection to a target and port with a configurable timeout and reports the result and elapsed time. |
| `Test-DnsLookup` | DNS records through `Resolve-DnsName`, or address resolution through `System.Net.Dns` when that cmdlet is unavailable. |

## 6.1 System-check report

`Invoke-PSProfileSystemCheck` accepts `All`, `Network`, `System`, `Storage`, `Security`, or `Profile`.

The current implementation creates report rows for:

- **System:** RAM utilisation and CPU load.
- **Storage:** free-space percentage for each filesystem drive.
- **Network:** count of non-loopback IPv4 addresses returned by `Get-NetworkInfo`.
- **Security:** command-guard registration status and history-filter installation status.
- **Profile:** whether the command cache contains indexed commands.

`-Category All` includes all five domains. The Network category is implemented, but its report is deliberately limited: it checks whether non-loopback IPv4 addresses were found. It does not test DNS resolution, external reachability, firewall rules, or every network helper.

## 6.2 Interpreting measurements

- `Get-CPUUsage` reads WMI `LoadPercentage` values and averages the available processor instances. It is not a high-resolution per-core performance counter or a continuous sample.
- `Get-RamUsage` reports memory visible to the operating system. It does not report GPU memory or necessarily all physically installed memory.
- `Get-DiskSpace` uses filesystem PSDrive capacity values. It does not read physical drive SMART status or diagnose hardware health. `Get-DiskHealth` is retained only as a compatibility name.
- `Get-ListeningPorts` lists local TCP listeners. It does not prove that a port is reachable from the Internet; firewall rules, NAT, routing, and remote testing also matter.
- `Test-TcpPort` checks a TCP connection from the current machine. A timeout can indicate filtering, routing failure, a closed port, or a slow endpoint.
- Some network and system cmdlets are Windows-specific. Fallbacks are provided for selected functions, but not every function has a complete cross-platform implementation.

# 7. Developer workflow and project tooling

## 7.1 Project discovery

| **FUNCTION** | **PURPOSE** |
|---|---|
| `Find-PSProject` | Searches below a path for selected project indicators and reports the containing directory and detected markers. Supports `-MaxDepth`. |
| `Get-PSProjectRoot` | Walks upward from a path and returns the first directory containing a recognised project marker. |
| `Set-LocationToGitRoot` | Moves the current location to the root returned by `Get-PSProjectRoot`. The function name is retained for compatibility, although the detected root may be identified by a non-Git project marker. |
| `Find-PSProjectFiles` | Recursively finds files matching a supplied filter while skipping selected generated or dependency directories. |
| `Find-PSCodeReference` | Searches matching files for a text or regular-expression pattern and can return surrounding context lines. |

The current project markers include `.git`, solution and project files (`.sln`, `.slnx`, `.csproj`, `.fsproj`, `.vbproj`), `package.json`, `pyproject.toml`, `requirements.txt`, `Cargo.toml`, `Dockerfile`, `go.mod`, and `composer.json`.

Recursive file searches skip common generated or dependency directories, including `.git`, `node_modules`, `bin`, `obj`, `.venv`, `venv`, `__pycache__`, `.tox`, and `.pytest_cache`. The project-discovery search has its own skip list. The marker list is deliberately limited and may need extending for other languages and build systems.

## 7.2 .NET helpers

```powershell
Invoke-PSDotNetBuild -Configuration Release
Invoke-PSDotNetTest
Invoke-PSDotNetClean
Get-PSDotNetProjects
```

The wrappers call `dotnet build`, `dotnet test`, and `dotnet clean`, after checking whether `dotnet` is available. `Get-PSDotNetProjects` searches for `.sln`, `.slnx`, `.csproj`, `.fsproj`, and `.vbproj` files. These helpers are convenience wrappers; they do not perform full solution selection or structured build-result analysis.

## 7.3 Python helpers

```powershell
Initialize-PSPythonEnvironment -Name '.venv'
Get-PSPythonEnvironment
Get-PSPythonPackages
Invoke-PSPythonTest
```

`Initialize-PSPythonEnvironment` checks whether the target folder already exists and whether `python` is available. It runs `python -m venv` and checks `$LASTEXITCODE` before reporting success or failure.

The function does not activate the environment or install packages. `Get-PSPythonEnvironment` reports the resolved Python executable, `VIRTUAL_ENV`, and pip version when available. `Get-PSPythonPackages` runs `python -m pip list`. `Invoke-PSPythonTest` runs `pytest` when the command is available; it does not automatically create or activate a virtual environment.

## 7.4 Node.js and npm helpers

```powershell
Get-PSNodeEnvironment
Get-PSNpmScripts
Get-PSNpmOutdated
Invoke-PSNpmTest
```

`Get-PSNodeEnvironment` reports the resolved Node.js executable and Node/npm versions when available. `Get-PSNpmScripts` reads the `scripts` property from a `package.json` file. The other helpers run `npm outdated` and `npm test` from the current working directory.

## 7.5 Docker helpers

```powershell
Get-PSDockerStatus
Get-PSDockerContainers -All
Get-PSDockerImages
Get-PSDockerUsage
Invoke-PSDockerCleanupPreview
```

These functions wrap Docker status, container, image, and disk-usage commands. `Get-PSDockerStatus` requests JSON-formatted daemon information and attempts to parse selected fields. `Invoke-PSDockerCleanupPreview` is read-only: it displays Docker disk-usage information and does not remove containers, images, volumes, or build cache.

## 7.6 Project validation planner

`Invoke-PSProjectCheck` detects a project root and builds a short list of validation commands.

| **DETECTED PROJECT CONTENT** | **PLANNED VALIDATION** |
|---|---|
| A `.sln`, `.slnx`, `.csproj`, `.fsproj`, or `.vbproj` file found under the detected root (within the search depth) | `dotnet build` and `dotnet test` |
| A root-level `package.json` containing a `scripts.test` entry | `npm test` |
| A root-level `pyproject.toml` or `requirements.txt` | `pytest` |

Without `-Execute`, the function prints the plan only. With `-Execute`, it changes to the detected root, dispatches each planned command through an explicit `switch`, and restores the original location in a `finally` block.

The project checker does not use `Invoke-Expression`. It checks for the relevant executable before each task and prints a warning when the executable is unavailable. For Python tests, it can use `python -m pytest` when a standalone `pytest` command is not found.

This is a basic planner rather than a full build orchestrator. It does not inspect every possible project format, discover all nested package scripts, install dependencies, select a specific solution, or guarantee that a detected test command is appropriate for every project.

# 8. Configuration and state reference

## 8.1 Configuration keys

| **KEY** | **DEFAULT** | **CURRENT USE IN THE SCRIPT** |
|---|---:|---|
| `LiveTypoHighlightEnabled` | `$true` | Enables or disables the history-based typo helper and the typo-suggestion check inside the command-validation handler. It does not enable continuous keyboard highlighting. |
| `MaximumEditDistance` | `2` | Sets the maximum distance used by `Test-PSProfileCommandSpelling`. The matching function also accepts its own `-MaximumDistance` parameter. |
| `KeyboardAwareScoring` | `$true` | Enables or disables keyboard-distance scoring in installed-command matching. |
| `SecurityMode` | `'Warn'` | Selects `Off`, `Warn`, or `Strict` behaviour for the registered validation handler. Actual command-submission enforcement still depends on the Enter binding. |
| `HistoryFilterEnabled` | `$true` | Controls whether the custom PSReadLine history handler is installed. Changing it calls `Set-PSProfileHistoryFilter`. |
| `PredictionSource` | `'HistoryAndPlugin'` | Sets the PSReadLine prediction source, subject to PowerShell/PSReadLine version support and fallback to History. |
| `PredictionViewStyle` | `'InlineView'` | Sets the PSReadLine prediction view style. |
| `MaxHistoryIndexCount` | `10000` | Limits the number of history lines indexed by `Update-PSCommandCache`, together with its `-HistoryLines` parameter. |
| `DeveloperToolsEnabled` | `$true` | Gates optional integration loading and `Invoke-PSProjectCheck`. It does not remove or disable every individual developer helper function. A change to optional integration loading takes effect on profile reload. |
| `LiveTypoMaxDistance` | `2` | Sets the maximum distance used by the history-based typo helper and the command-validation typo suggestion. |

## 8.2 Reading and changing configuration

```powershell
Get-PSProfileConfig
Get-PSProfileConfig | Format-List
Set-PSProfileConfig -Key 'KeyboardAwareScoring' -Value $false
Set-PSProfileConfig -Key 'HistoryFilterEnabled' -Value $true
Set-PSProfileSecurityMode -Mode Warn
```

`Set-PSProfileConfig` checks that the key exists and validates the supplied value for the supported key groups:

- Boolean settings must receive a Boolean value.
- `MaximumEditDistance` and `LiveTypoMaxDistance` must be integers from 1 to 5.
- `MaxHistoryIndexCount` must be an integer from 100 to 50,000.
- `SecurityMode` must be `Off`, `Warn`, or `Strict`.
- `PredictionSource` must be `None`, `History`, `Plugin`, or `HistoryAndPlugin`.
- `PredictionViewStyle` must be `InlineView` or `ListView`.

Changing prediction settings applies them to PSReadLine when it is available. Changing `HistoryFilterEnabled` reinstalls or removes the history handler. Changing `MaxHistoryIndexCount` rebuilds the command/history cache. Changing `DeveloperToolsEnabled` displays a warning that optional integration loading is applied on the next profile reload.

Configuration changes are session-scoped unless the profile source is edited. Changing `DeveloperToolsEnabled` does not forcibly unload integrations that have already been imported.

## 8.3 Status and dashboard functions

| **FUNCTION** | **OUTPUT** |
|---|---|
| `Get-PSProfileStatus` | Compact object with PowerShell/PSReadLine versions, security mode, handler-registration status, command/history counts, startup time, and loaded integrations. |
| `Get-PSProfileDiagnostics` | Formatted view of the checks returned by `Test-PSProfile`. |
| `Test-PSProfile` | Structured list of profile health checks and suggested fixes, including PSReadLine, command cache, history storage/filter, security handler registration, and typo-suggestion readiness. |
| `Show-PSProfileDashboard` | Console dashboard showing runtime details, indexing, security mode, integrations, and health-check results. |
| `Get-PSProfileSecurityStatus` | Security mode, history-filter configuration and installation status, PSReadLine readiness, command-handler registration status, and handler error. |
| `Get-PSProfileConfig` | Returns the current configuration as a PSCustomObject. |
| `Set-PSProfileConfig` | Validates and changes a recognised configuration value. |
| `Update-PSProfile` | Rebuilds command/history indexes and reports cache counts. |

The status checks report what the script has configured or registered. They do not independently prove that every PSReadLine callback is triggered by the intended keyboard action.

## 8.4 Other state details

Optional module load times are stored in `ModuleLoadTimes`, but the current dashboard lists integration names rather than displaying each load duration. `ExecutionTracker` is populated by `Measure-PSProfileCommand` and is capped at `MaxExecutionRecords` (500 by default).

`Get-PSHistoryErrors` reads unsuccessful records from this tracker. The profile does not register a general PowerShell event hook to capture every command, non-terminating error, or failed external process.

# 9. Command reference

The following tables group the functions defined in the supplied profile. Parameters shown are common or useful forms, not a replacement for `Get-Help`. Run `Get-Command -CommandType Function` to inspect the functions loaded into the current session.

## 9.1 Command intelligence

| **FUNCTION** | **PURPOSE / COMMON PARAMETERS** |
|---|---|
| `Update-PSCommandCache` | Rebuild command and history indexes. Supports `-HistoryOnly` and `-HistoryLines` (100–50,000; default 10,000). |
| `Update-PSProfile` | Convenience wrapper that refreshes the cache and reports totals. |
| `Get-PSProfileCommandMatches` | Fuzzy-match an installed command name. Supports `-Name`, `-MaximumDistance`, and `-Limit`. |
| `Get-PSProfileCommandConfidence` | Calculate a heuristic score and explanation for one candidate match. |
| `Test-PSProfileCommandSpelling` | Display a command-intelligence report and best candidate without changing the input buffer. |
| `Test-CommandSpelling` | Short wrapper for `Test-PSProfileCommandSpelling`. |
| `Get-PSProfileBestHistoryCommand` | Find the best history prefix/typo match for a typed command name. |
| `Get-PSProfileTypoMismatchIndexes` | Return character positions considered mismatches between typed and expected text. |
| `Get-PSProfileEditDistance` | Calculate OSA edit distance between two strings. |
| `Get-PSProfileKeyboardDistance` | Return approximate geometric distance between two QWERTY letter coordinates. |
| `Get-PSProfileCommandContext` | Check a selected external tool's second command element against the subcommand catalogue. |
| `Invoke-PSProfileLiveTypoHighlight` | Inspect the current buffer and return a history-based suggestion object; it is not connected to keyboard events or console repainting. |
| `Find-LocalCommand` | Search `Get-Command` by wildcard name; optionally filter by command type or module. |
| `Get-PSProfileCommandInfo` | Return command metadata, help synopsis, parameter details, and history count. |
| `Get-PSProfileCommandExamples` | Display examples returned by `Get-Help` for a command. |
| `Get-PSProfileCommandUsage` | Show top command counts, or usage information for one named command. |
| `Get-PSProfileCommandDependencies` | Report the parent module and declared module/assembly requirements. |
| `Search-PSProfileCommandHelp` | Search `Get-Help` and return name, category, and synopsis. |

## 9.2 History and security auditing

| **FUNCTION** | **PURPOSE / COMMON PARAMETERS** |
|---|---|
| `Get-PSHistoryPath` | Return the current PSReadLine history-save path. |
| `Get-PSHistoryStats` | Summarise history entries and show frequently used commands and external applications. |
| `Get-PSHistoryUnique` | Return unique history lines, limited by `-Limit`. |
| `Get-PSHistoryTimeline` | Divide a selected history tail into approximate entry-order phases and show sample commands. |
| `Get-PSHistoryDuplicates` | List exact repeated lines meeting `-MinOccurrences`. |
| `Get-PSHistoryErrors` | Return unsuccessful records created by `Measure-PSProfileCommand`; not all session errors. |
| `Export-PSHistory` | Export history as Csv, Json, or Text to `-Path`, skipping lines flagged by the current sensitive-pattern scanner. |
| `Search-PSHistory` | Search history using `-Pattern`; supports `-SimpleMatch` and `-Limit`. |
| `Find-PSHistorySecrets` | Scan selected credential patterns. Supports `-Purge` and its custom `-WhatIf` preview. |
| `Test-PSProfileSensitiveCommandLine` | Internal helper that checks selected sensitive text patterns and AST indicators. |
| `Get-PSCommandRisk` | Return a heuristic risk report for a supplied command line. |
| `Test-PSCommandRisk` | Display the risk report in colour-coded console output. |
| `Set-PSProfileSecurityMode` | Set `Off`, `Warn`, or `Strict` for the PSReadLine command-validation handler. |
| `Get-PSProfileSecurityStatus` | Report security mode, history-filter status, PSReadLine readiness, and handler-registration status. |
| `Set-PSProfileHistoryFilter` | Install or remove the custom history handler according to `HistoryFilterEnabled`. |
| `Measure-PSProfileCommand` | Run a scriptblock, time it, record a result, and return its output. |
| `Add-PSProfileHistoryCommandUse` | Increment the usage counter for a recognised installed command name. |

## 9.3 Local diagnostics and system information

| **FUNCTION** | **PURPOSE / COMMON PARAMETERS** |
|---|---|
| `Get-SystemInfo` | Show basic OS, user, PowerShell, RAM, and current-folder information. |
| `Get-CPUUsage` | Read CPU names, average WMI load, core count, and logical processor count. |
| `Get-RamUsage` | Calculate visible RAM usage and percentage. |
| `Get-DiskSpace` | Show filesystem drive capacity and free space. |
| `Get-DiskHealth` | Compatibility wrapper around `Get-DiskSpace`; not physical disk-health checking. |
| `Get-ServiceHealth` | Count services grouped by status. |
| `Get-StartupPrograms` | List WMI startup-command entries. |
| `Get-InstalledSoftware` | List registered installed software; supports `-Filter`. |
| `Get-CertificateInfo` | List CurrentUser certificates from the `My` or `Root` store. |
| `Get-NetworkInfo` | Show local computer/domain, IPv4 addresses, and DNS servers. |
| `Get-NetworkAdapters` | List adapters and link information. |
| `Get-NetworkRoutes` | List IPv4 routes. |
| `Get-FirewallStatus` | Show Windows Firewall profile status. |
| `Get-ListeningPorts` | List local TCP listeners; optionally filter with `-Port`. |
| `Get-PortProcess` | Convenience wrapper for `Get-ListeningPorts -Port`. |
| `Test-TcpPort` | Test a TCP target/port with optional `-TimeoutMs`. |
| `Test-DnsLookup` | Resolve a DNS name. |
| `Invoke-PSProfileSystemCheck` | Build a report for `All`, `Network`, `System`, `Storage`, `Security`, or `Profile`. The Network report checks IPv4 address presence only. |

## 9.4 Projects and developer tools

| **FUNCTION** | **PURPOSE / COMMON PARAMETERS** |
|---|---|
| `Find-PSProject` | Search a path for selected project markers; supports `-MaxDepth`. |
| `Get-PSProjectRoot` | Walk upward to find the nearest directory containing a recognised project marker. |
| `Set-LocationToGitRoot` | Move to the detected project root, which may be identified without Git. |
| `Find-PSProjectFiles` | Search files by `-Filter` under a path. |
| `Find-PSCodeReference` | Search source files; supports extension, case sensitivity, context lines, and maximum depth. |
| `Invoke-PSDotNetBuild` | Run `dotnet build` with a selected configuration. |
| `Invoke-PSDotNetTest` | Run `dotnet test` with normal console logging. |
| `Invoke-PSDotNetClean` | Run `dotnet clean`. |
| `Get-PSDotNetProjects` | Find solution and project files (`.sln`, `.slnx`, `.csproj`, `.fsproj`, `.vbproj`). |
| `Initialize-PSPythonEnvironment` | Create a virtual environment folder using `python -m venv`; checks Python availability and the native exit code. |
| `Get-PSPythonEnvironment` | Report Python executable, active virtual-environment path, and pip version. |
| `Get-PSPythonPackages` | Run `python -m pip list`. |
| `Invoke-PSPythonTest` | Run `pytest` when available. |
| `Get-PSNodeEnvironment` | Report Node.js and npm paths/versions. |
| `Get-PSNpmScripts` | Read the `scripts` property from `package.json`. |
| `Get-PSNpmOutdated` | Run `npm outdated`. |
| `Invoke-PSNpmTest` | Run `npm test`. |
| `Get-PSDockerStatus` | Report selected Docker daemon information. |
| `Get-PSDockerContainers` | List running containers or all containers with `-All`. |
| `Get-PSDockerImages` | List Docker images. |
| `Get-PSDockerUsage` | Report Docker disk usage. |
| `Invoke-PSDockerCleanupPreview` | Display Docker disk-usage information; does not delete anything. |
| `Invoke-PSProjectCheck` | Detect supported project content and print a validation plan; `-Execute` runs supported tasks from the detected root. |

## 9.5 Shell, Git, and profile helpers

| **FUNCTION / ALIAS** | **PURPOSE** |
|---|---|
| `Edit-PSProfile` | Open the current profile path in Notepad, or print the path if Notepad is unavailable. |
| `Open-PSProfileFolder` | Open the directory containing the profile, or print its path. |
| `Reload-PSProfile` | Dot-source the current profile again and report the reload result. |
| `mkcd` | Create a directory and move into it. |
| `up` | Move up one or more directory levels. |
| `croot` | Move to the home directory. |
| `ll` | List current directory entries in a table. |
| `Copy-CurrentPath` / `cpath` | Copy the current path to the clipboard when `Set-Clipboard` is available. |
| `Open-CurrentDirectory` / `owd` | Open the current directory in File Explorer, or print the path. |
| `git-status` | Run `git status --short --branch`. |
| `git-diff` | Run `git diff` with the supplied arguments. |
| `git-log` | Show a decorated one-line log of the latest 15 commits, with supplied arguments. |
| `git-branches` | Run `git branch -vv`. |
| `git-pull`, `git-push`, `git-commit` | Convenience wrappers that pass remaining arguments to Git. |

# 10. Static review: limitations and recommended fixes

The following findings are based on the supplied source. Prior issues that have been corrected in this version are not listed as current defects.

| **PRIORITY** | **CURRENT FINDING** | **RECOMMENDED ACTION** |
|---|---|---|
| Critical | The command-validation handler is registered, but the profile does not explicitly bind Enter to `ValidateAndAcceptLine`. Registration alone does not prove that the handler runs on command submission. | Add `Set-PSReadLineKeyHandler -Key Enter -Function ValidateAndAcceptLine` after the handler is configured. Verify the binding with `Get-PSReadLineKeyHandler -Chord Enter`, then test the callback safely in an isolated profile. |
| High | `Invoke-PSProfileLiveTypoHighlight` is not connected to key events and returns a suggestion object rather than displaying a live highlight. | Rename it to reflect suggestion lookup, connect it to a deliberate supported interaction, or remove it if the command-validation suggestion is the intended interface. Do not document it as continuous live highlighting. |
| High | `SecurityGuardInstalled` records successful handler registration but does not verify the Enter binding or actual callback execution. | Report handler registration and Enter validation binding as separate status values. Only report enforcement as active after both have been verified. |
| Medium | The security rules are heuristic and cover only selected command names, parameters, and path patterns. | Add tests for expected detections and bypass cases. Keep the explicit warning that the feature is not a security boundary. |
| Medium | The history filter skips command lines that fail AST parsing, even when no secret pattern was detected. | Keep this conservative behaviour documented, or decide whether parse failures should be skipped, retained in memory only, or handled through another policy. Test multiline and incomplete input. |
| Medium | `Get-PSProfileCommandContext` is a manual helper and is not integrated into the command-validation handler. | Connect it to an intended user interaction if automatic subcommand suggestions are required; otherwise document it as a manual lookup function. |
| Medium | The QWERTY map is a simplified letter-only model and does not support configurable layouts. | Test realistic adjacent-key errors and add layout support only if it provides measurable value. |
| Medium | `Get-PSProfileSystemCheck -Category Network` checks for IPv4 addresses only. | Add DNS, adapter, route, or connectivity checks if a broader network health report is required. |
| Medium | `Get-PSHistoryErrors` reports only failed `Measure-PSProfileCommand` records, not all PowerShell session errors. | Keep the narrower description or implement a deliberate error-capture mechanism. |
| Medium | `DeveloperToolsEnabled` gates optional integration loading and `Invoke-PSProjectCheck`, but does not disable every developer helper function. | Keep the setting description precise, or extend the setting consistently if it is intended to disable all developer tooling. |
| Low | Optional module load times are collected but are not shown in the dashboard. | Display the timings or remove the unused telemetry field. |
| Low | The project marker list supports common formats but is not exhaustive. | Add markers only when required by target projects and test root detection for nested repositories and monorepos. |

## 10.1 Improvements already made in this version

The current source addresses several issues identified in the earlier review:

- `HistoryFilterEnabled` now controls installation or removal of the PSReadLine history handler.
- `MaximumEditDistance`, `MaxHistoryIndexCount`, and `DeveloperToolsEnabled` now have operational uses, although `DeveloperToolsEnabled` does not disable every helper function.
- `Invoke-PSProfileSystemCheck` now creates a Network report row and includes it in `All`.
- Project-root checks use explicit `Test-Path` expressions.
- `Invoke-PSProjectCheck` changes to the detected project root and restores the original location in a `finally` block.
- Project validation uses explicit command dispatch rather than `Invoke-Expression`.
- `Initialize-PSPythonEnvironment` checks that Python is available and checks `$LASTEXITCODE` before reporting success.
- Security and history-filter handler registration states and errors are stored separately.
- The old console-repainting typo implementation and custom printable-character key handlers have been removed.
- History purging no longer creates an additional plaintext backup file.

These changes improve the source but still require runtime tests.

## 10.2 Further design improvements

- Split the profile into separate files for configuration, command intelligence, history/security, diagnostics, developer tooling, and startup. Dot-source those files from a short entry-point profile.
- Add a Pester test suite for edit distance, command ranking, history parsing, sensitive-line detection, risk classification, project-root discovery, configuration validation, and project-check planning.
- Use `SupportsShouldProcess` and standard `-WhatIf` behaviour for future functions that modify files or perform potentially disruptive operations.
- Add structured logging for startup failures instead of relying only on warnings, verbose messages, or silently caught exceptions.
- Separate **risk advisory** from **execution enforcement** in the dashboard and status output.
- Add a check for the actual Enter key binding before reporting command validation as active.
- Consider replacing the broad, single-file startup process with independently testable components once the current implementation is stable.

# 11. Installation, setup, and validation

## 11.1 Before installation

1. Identify the profile path for the shell and host where PDE should run by displaying `$PROFILE` in that PowerShell session.
2. Back up the existing profile before replacing or merging any content.
3. Create the profile directory if it does not exist. Do not assume Windows PowerShell 5.1 and PowerShell 7 use the same profile file.
4. Test the script in a separate test profile or a session launched with `-NoProfile` before making it the normal startup profile.
5. Keep a second PowerShell session open while changing profile files so a broken startup profile can be repaired.
6. Confirm that required external tools are installed before testing their wrappers. Optional modules are not installed automatically by PDE V2.

## 11.2 Useful setup commands

```powershell
# Inspect the active profile path
$PROFILE

# Check whether the profile exists
Test-Path -LiteralPath $PROFILE

# Create the parent directory if required
$profileDir = Split-Path -Parent $PROFILE
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

# Back up an existing profile before editing
if (Test-Path -LiteralPath $PROFILE) {
    Copy-Item -LiteralPath $PROFILE -Destination ($PROFILE + '.backup') -Force
}

# Open the profile after PDE has been installed
Edit-PSProfile
```

## 11.3 First-launch verification

Run the following commands after loading the profile:

```powershell
$PSVersionTable | Format-List
Get-Module PSReadLine | Select-Object Name, Version
Get-PSProfileStatus | Format-List
Test-PSProfile | Format-Table -AutoSize
Show-PSProfileDashboard
Get-PSProfileSecurityStatus | Format-List
Get-PSReadLineKeyHandler -Chord Enter
```

Repeat the checks in Windows PowerShell 5.1 and PowerShell 7+ if both are intended targets. Confirm the Enter binding separately; the supplied script does not currently configure it.

Manually test Tab, Shift+Tab, Ctrl+R, Ctrl+S, Ctrl+L, Alt+RightArrow, Enter, paste, Backspace, Delete, and arrow navigation. Also test in each terminal emulator used regularly.

## 11.4 Functional test checklist

| **AREA** | **TEST** | **EXPECTED RESULT** |
|---|---|---|
| Command cache | Run `Update-PSProfile`. | A non-zero command count is reported and no terminating error occurs. |
| Typo report | Run `Test-CommandSpelling -Name 'Get-ChilItem'`. | A close installed-command candidate is displayed when the command cache contains a suitable match. |
| History index | Run `Get-PSProfileCommandUsage`. | Frequently recognised command names are listed when history data is available. |
| History filter | Submit a harmless dummy assignment such as `$pdeDummyPassword = 'not-a-real-secret'`. | The sensitive assignment is skipped from PSReadLine history. Remove the temporary variable after the test. |
| Secret scanner | Run `Find-PSHistorySecrets`. | Matching lines are reported by line number and rule without printing their contents. |
| Risk classifier | Run `Test-PSCommandRisk -CommandLine 'Format-Volume -DriveLetter Z'`. | A CRITICAL classification is displayed. This reporting function analyses the supplied text and does not execute it. |
| Security handler registration | Run `Set-PSProfileSecurityMode -Mode Warn`, then inspect `Get-PSProfileSecurityStatus`. | The status reports whether PSReadLine accepted the handler and whether an installation error occurred. |
| Security Enter integration | Inspect `Get-PSReadLineKeyHandler -Chord Enter` after adding the intended binding. | Enter is bound to `ValidateAndAcceptLine`. Test actual handler behaviour only in an isolated test environment using a controlled test method. Do not execute a destructive command to test the guard. |
| Network | Run `Get-NetworkInfo`, `Get-ListeningPorts`, and `Test-TcpPort` against a known test endpoint. | Output reflects the current machine/network and unavailable commands or connection failures are reported clearly. |
| Project detection | Run `Get-PSProjectRoot` from inside and outside a test repository. | The nearest recognised root is returned, or `$null` is returned when no marker is found. |
| Project check | Run `Invoke-PSProjectCheck` without `-Execute`. | A plan is printed and no build/test command is run. |
| Project execution | Run `Invoke-PSProjectCheck -Execute` in a disposable test project. | Planned tasks run from the detected root and the original location is restored. |
| Python environment | Run `Initialize-PSPythonEnvironment -Name '.venv-test'` in a disposable folder. | Success is reported only when the Python process returns exit code 0. Remove the test environment afterwards. |
| Cross-version | Repeat key tests in Windows PowerShell 5.1 and PowerShell 7+. | Unsupported features degrade clearly rather than breaking profile startup. |

Do not test the history purge against important history without first preserving any entries you need. For purge testing, use a disposable profile/history file and dummy patterns rather than real credentials.

## 11.5 Rollback

If the profile prevents normal startup, launch PowerShell with `-NoProfile`, restore the saved profile backup, or temporarily rename the profile file. Keep optional modules and custom PSReadLine settings disabled until the base profile loads reliably.

# Appendix A. Quick-start command sheet

| **TASK** | **COMMAND** |
|---|---|
| Show profile dashboard | `Show-PSProfileDashboard` |
| Get compact profile status | `Get-PSProfileStatus \| Format-List` |
| Run profile diagnostics | `Test-PSProfile \| Format-Table -AutoSize` |
| Refresh command/history index | `Update-PSProfile` |
| Find a likely command spelling | `Test-CommandSpelling -Name 'Get-ChilItem'` |
| Inspect one command | `Get-PSProfileCommandInfo -Name 'Get-ChildItem' \| Format-List` |
| Show common command usage | `Get-PSProfileCommandUsage` |
| Show history statistics | `Get-PSHistoryStats` |
| Search command history | `Search-PSHistory -Pattern 'Get-NetTCPConnection'` |
| Scan existing history | `Find-PSHistorySecrets` |
| Preview history purge | `Find-PSHistorySecrets -Purge -WhatIf` |
| Inspect listening TCP ports | `Get-ListeningPorts \| Sort-Object Port` |
| Check a TCP endpoint | `Test-TcpPort -Target 'localhost' -Port 443` |
| Show firewall profiles | `Get-FirewallStatus` |
| Show RAM and disk space | `Get-RamUsage; Get-DiskSpace` |
| Move to detected project root | `Set-LocationToGitRoot` |
| Search project references | `Find-PSCodeReference -Pattern 'Invoke-Expression' -Extension 'ps1'` |
| Plan project checks | `Invoke-PSProjectCheck` |
| Inspect Enter binding | `Get-PSReadLineKeyHandler -Chord Enter` |

---

**End of PDE V2 Technical Documentation.**
