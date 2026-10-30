# PowerShell Developer Environment (PDE) V2

**Technical Documentation & User Guide**

A unified PowerShell profile for command-line productivity, history intelligence, security awareness, system diagnostics, and developer workflows.

| **DOCUMENT DETAILS** | **VALUE**                                                                   |
|----------------------|-----------------------------------------------------------------------------|
| Profile version      | V2 (as labelled in the supplied script)                                     |
| Target shells        | Windows PowerShell 5.1 and PowerShell 7+                                    |
| Primary dependency   | PSReadLine for interactive editing and validation features                  |
| Document purpose     | Explain the implemented features, usage, configuration, and review findings |
| Review status        | Written from the supplied source; not a runtime certification               |

**IMPORTANT**

The profile contains useful tooling, but some features are heuristic or incompletely connected. The security guard and project-root detection limitations identified in this document should be corrected and tested before the profile is relied on for protection or automated project validation.

# Document map

| **SECTION**                            | **WHAT IT COVERS**                                                                         |
|----------------------------------------|--------------------------------------------------------------------------------------------|
| 1. Overview and scope                 | What PDE V2 is designed to do, and what it does not claim to do.                           |
| 2. Startup and architecture           | Initialisation sequence, shared state, and major subsystems.                               |
| 3. Interactive command intelligence   | Command indexing, typo matching, confidence ranking, and live highlighting.                |
| 4. PSReadLine and history             | Prediction, syntax colours, key bindings, history filtering, and analytics.                |
| 5. Security features                  | History secret filtering, history audit, command-risk classification, and guard behaviour. |
| 6. System and network tools           | Local machine, network, ports, services, storage, and diagnostics.                         |
| 7. Developer workflow tools           | Project discovery, Git, .NET, Python, Node/npm, and Docker helpers.                        |
| 8. Configuration and state            | Configuration keys, state objects, and which settings are currently effective.             |
| 9. Command reference                  | A grouped reference to the profile functions and common examples.                          |
| 10. Limitations and recommended fixes | Static review findings that should be addressed before relying on the profile.             |
| 11. Installation and validation       | A safe setup approach and a practical verification checklist.                              |
| Appendix                               | Quick-start command sheet.                                                                 |

## How to read this document

The descriptions below distinguish three things: implemented behaviour visible in the supplied script; behaviour that depends on the installed PowerShell/PSReadLine version; and intended behaviour that is not fully connected in the current implementation. The latter is called out explicitly rather than presented as a working feature.

> **Evidence boundary**
> No PowerShell execution, cross-version test, or security penetration test was performed as part of preparing this document. Findings labelled “static review” are based on inspection of the supplied source and should be confirmed in a test profile.

# 1. Overview and scope

## 1.1 Purpose

PowerShell Developer Environment (PDE) V2 is a user-profile script intended to make an interactive PowerShell session more useful for software development and system administration. It combines command-line editing improvements with a set of custom functions for discovering commands, analysing command history, checking local system state, navigating software projects, and invoking common development tools.

The profile is loaded when PowerShell starts under a profile path that contains this script. It defines functions and aliases in the session, configures PSReadLine when available, loads selected optional modules, builds an index of installed commands and recent history, and records the time taken by its own initialisation sequence.

## 1.2 Main capability groups

| **CAPABILITY**           | **PRACTICAL PURPOSE**                                                                                                                                       |
|--------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Command intelligence     | Find installed command names, compare mistyped text with known commands, and rank candidates using edit distance, keyboard proximity, and usage history.    |
| Live typo highlighting   | Colour the first command token while typing, using command history as the comparison source. It does not rewrite the command line.                          |
| PSReadLine configuration | Enable predictive suggestions, improve completion and history navigation, apply syntax colours, and install custom key handlers.                            |
| History management       | Filter selected secret-looking commands, count command usage, search history, report duplicates, export entries, and scan for possible credentials.         |
| Security awareness       | Classify selected command patterns as LOW, MEDIUM, HIGH, or CRITICAL and provide a configurable PSReadLine validation handler.                              |
| System and network tools | Inspect CPU and memory information, disk space, adapters, routes, DNS, firewall profiles, services, startup entries, certificates, and listening TCP ports. |
| Developer workflow       | Locate projects and source references, move to a detected project root, and provide wrappers for Git, .NET, Python, npm, and Docker.                        |
| Session management       | Display profile health, configuration, runtime status, module loading information, and startup duration.                                                    |

## 1.3 Intended operating environment

The script is primarily Windows-oriented. It uses Windows networking and system cmdlets when available, refers to Windows-specific tools such as explorer.exe and registry uninstall locations, and uses ConsoleHost behaviour for live highlighting. Some functions have fallbacks or use cross-platform PowerShell features, but that does not amount to a tested cross-platform guarantee.

## 1.4 What PDE V2 is not

PDE V2 is not a replacement for PowerShell, PSReadLine, a full IDE, or a terminal emulator. It is not a comprehensive endpoint-security product or substitute for backups and least-privilege access. It does not monitor every command automatically: ExecutionTracker is populated only through Measure-PSProfileCommand. Its project checker is a small planner rather than a full build system, and its spelling engine is local and algorithmic rather than AI-based.

# 2. Startup sequence and architecture

## 2.1 Startup sequence

The script initialises the environment in a defined order. The sequence below describes the supplied source at a functional level:

| **ORDER** | **STARTUP ACTION**                                                            | **RESULT**                                                                          |
|-----------|-------------------------------------------------------------------------------|-------------------------------------------------------------------------------------|
| 1         | Start a Stopwatch and create global configuration/state hashtables.           | A shared configuration object and runtime state are available to later functions.   |
| 2         | Create the keyboard-layout map and common subcommand catalogue.               | Data used by typo scoring and subcommand suggestions is available.                  |
| 3         | Define command, history, security, diagnostic, project, and helper functions. | The profile exposes its custom command set to the current session.                  |
| 4         | Import PSReadLine unless the host name contains ISE.                          | Interactive line-editing features can be configured when PSReadLine loads.          |
| 5         | Apply PSReadLine settings, colours, predictions, and key handlers.            | Input behaviour is customised for supported interactive hosts.                      |
| 6         | Import optional modules and initialise zoxide/Oh My Posh when found.          | Additional prompt, navigation, icon, or fuzzy-search integrations may be activated. |
| 7         | Build the command cache and parse recent history.                             | Installed command names and command-use counts are indexed.                         |
| 8         | Apply the configured security mode and stop the startup timer.                | The profile records its own initialisation duration.                                |

## 2.2 Shared configuration

The global hashtable $global:PSProfileConfig stores settings that are intended to control feature behaviour. It includes live typo highlighting, keyboard-aware ranking, security mode, history filtering, prediction source/view, and cache limits. The current script does not use every configuration entry; see Section 8 for the implemented/unused distinction.

## 2.3 Runtime state

The global hashtable $global:PSProfileState stores generated data and status values. It includes the command-name cache, a lookup table of command metadata, command frequency counts, the subcommand catalogue, PSReadLine readiness, optional-module load details, startup duration, cache timestamp, and an ArrayList called ExecutionTracker.

| **STATE MEMBER**                                      | **ROLE**                                                                                                             |
|-------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| CommandNameCache / CommandNameLookup                  | Sorted command-name list plus metadata lookup for type, source, and executable name.                                 |
| HistoryCommandCounts / HistoryCommandsByLength        | Parsed command-use counts and a length grouping; the length grouping is currently not used by the main ranking path. |
| PSReadLineReady / LiveTypoKeyBindings                 | Records PSReadLine import success and counts custom key handlers registered by the script.                           |
| OptionalModulesLoaded / ModuleLoadTimes               | Records loaded integrations and their measured import duration.                                                      |
| StartupDurationMs / CacheBuiltTime / ExecutionTracker | Stores startup/cache timing and records created by Measure-PSProfileCommand; it is not a global command monitor.     |

## 2.4 Design characteristics

- Single-file profile: configuration, functions, integration setup, and diagnostics are kept together rather than separated into PowerShell modules.

- In-memory indexing: command and history data are rebuilt when the profile starts or when Update-PSProfile is run.

- Graceful optional dependencies: many optional imports and platform-specific calls use Get-Command checks or try/catch blocks.

- Session scope: configuration changes made with Set-PSProfileConfig or Set-PSProfileSecurityMode affect the current session unless the profile source is edited or another persistence mechanism is added.

# 3. Interactive command intelligence

## 3.1 Command discovery and indexing

Update-PSCommandCache uses Get-Command -Name \* -All to enumerate commands visible to the current session. It stores command metadata in CommandNameLookup and a sorted list of unique command names in CommandNameCache. For external applications with executable extensions such as .exe, .com, .cmd, or .bat, it also adds the filename without the extension as a possible name.

The same function reads the PSReadLine history file, up to the configured HistoryLines tail (default 5,000), parses each line with the PowerShell language parser, finds CommandAst nodes, and counts command names that are present in the command lookup. This is more accurate than simply splitting every history line at its first space, although it still depends on a recognisable command name and the completeness of the parser input.

## 3.2 Edit-distance matching

Get-PSProfileEditDistance uses a dynamic-programming matrix to calculate a string-edit distance. It accounts for insertion, deletion, substitution, and adjacent character transposition. This is a transposition-aware Optimal String Alignment (OSA) variant, not the unrestricted Damerau-Levenshtein algorithm. A maximum-distance threshold allows the function to stop considering candidates that are too different.

```text
Get-PSProfileEditDistance -Source 'statsu' -Target 'status' -MaximumDistance 2
```
The command matcher first removes candidates whose name length differs by more than the allowed distance. It then evaluates the edit distance. If keyboard-aware scoring is enabled, it adds a penalty based on the distance between mismatching characters in an approximate QWERTY coordinate map.

## 3.3 Candidate ranking

Get-PSProfileCommandMatches ranks possible matches using edit distance, keyboard mismatch penalty, and prior command use. The supplied ranking expression is:

```text
RankScore = (EditDistance × 100) + (KeyboardPenalty × 10) - (min(HistoryUses, 50) × 2)
```
Candidates are sorted primarily by the lowest edit distance, then by the calculated rank score, then by history count and name. This makes exact or near-exact textual matches more important than familiarity, while usage history influences close candidates.

## 3.4 Confidence report

Get-PSProfileCommandConfidence converts a selected match into a 0–100 score. It starts at 100, subtracts a length-sensitive edit-distance penalty and a keyboard penalty, then adds a capped bonus for previously used commands or subtracts a penalty when no history is recorded. Scores are labelled High (80+), Medium (55–79.9), or Low (below 55). These are heuristic labels, not calibrated probabilities.

## 3.5 Live typo highlighting

Invoke-PSProfileLiveTypoHighlight reads the current PSReadLine buffer and checks the first command token. It only runs when live typo highlighting is enabled, the host name matches ConsoleHost, and output is not redirected. It looks for a close command prefix or typo in the indexed history and temporarily redraws the typed command characters in the console. Matching characters are displayed green and mismatching characters red. The current buffer is not rewritten.

> **Important distinction**
> The live overlay is a visual hint, not a correction engine. The script explicitly reports that the buffer will not be rewritten. A suggestion can be absent because the command is not in indexed history, the token is excluded by the input filters, or no unambiguous close match is found.

## 3.6 Subcommand catalogue

PSProfileSubcommandCatalog contains selected common subcommands for Git, dotnet, npm, Docker, Python, and pip. Get-PSProfileCommandContext checks the first two whitespace-separated tokens. If the second token is not in the catalogue, it can return a close suggested subcommand. This is a lightweight lookup; it is not a full parser for each external tool.

# 4. PSReadLine and command history

## 4.1 Predictive IntelliSense

When PSReadLine imports successfully, the profile sets the prediction source and view style from configuration. The default source is HistoryAndPlugin and the default view is InlineView. The script requests HistoryAndPlugin only when PowerShell is version 7.2 or later and PSReadLine is version 2.2.0 or later; otherwise it falls back to History. Plugin-based predictors require compatible versions and available predictor modules. The script does not itself install a predictor plugin.

## 4.2 Editing and completion settings

| **SETTING**           | **CONFIGURED BEHAVIOUR**                                                                                    |
|-----------------------|-------------------------------------------------------------------------------------------------------------|
| Maximum history count | 50,000 entries in the PSReadLine option.                                                                    |
| History save style    | SaveIncrementally, so commands are written as the session runs.                                             |
| History navigation    | History search moves the cursor to the end; duplicate recall entries are suppressed.                        |
| Completion menu       | MenuComplete on Tab, previous menu item on Shift+Tab, and MenuComplete on Ctrl+Spacebar.                    |
| Search and screen     | Ctrl+R reverse history search; Ctrl+S forward history search; Ctrl+L clear screen.                          |
| Suggestion acceptance | Alt+RightArrow accepts the next suggestion word on PSReadLine 2.2.0+.                                       |
| Other options         | Tooltips enabled, word delimiters configured, audible bell disabled, completion query threshold set to 200. |

## 4.3 Syntax colours

A custom colour palette is supplied for commands, parameters, strings, operators, variables, errors, comments, keywords, numbers, types, members, default text, and emphasis. InlinePrediction and Selection colours are added for PSReadLine 2.2.0+. These settings alter presentation only; they do not change command execution.

## 4.4 Custom key handlers

The script registers character handlers for letters, digits, and several punctuation keys. Each handler inserts the typed character through PSConsoleReadLine and then calls the live typo-highlighting function. It also wraps Backspace, Delete, arrow navigation, Home, End, history navigation, Undo, Redo, and paste operations so that the highlight is refreshed after editing.

> **Compatibility note**
> Replacing many default key chords can interact with terminal input, keyboard layouts, PSReadLine edit modes, accessibility tools, and other modules that register their own handlers. Validate every key group in the actual terminal before treating the configuration as stable.

## 4.5 History filtering

The AddToHistoryHandler checks each submitted line for selected terms and patterns associated with passwords, tokens, API keys, bearer credentials, plaintext SecureString conversion, and cmdkey credential commands. Matching lines return SkipAdding. Other lines are parsed for command names and return MemoryAndFile. Microsoft documents MemoryAndFile, MemoryOnly, and SkipAdding as valid return values for this handler.

The filter is useful as a preventative convenience, but it is pattern-based. It cannot guarantee that every secret is detected, and it does not retroactively remove secrets already written to history. Commands can also place sensitive values in formats the patterns do not recognise.

## 4.6 History analytics

The history tools read the PSReadLine history file and provide counts, top commands, unique entries, approximate activity phases, repeated full command lines, searches, exports, and a view of failed records in ExecutionTracker. Some analytics use a simple first-token split rather than the AST-based indexer, so their command counts can differ for complex command lines.

# 5. Security features and trust boundaries

## 5.1 History secret detection

Find-PSHistorySecrets scans the history file for selected credential patterns. The supplied rules look for private-key headers, AWS access keys, GitHub tokens, Slack tokens, JWT-like values, hardcoded secret assignments, and ConvertTo-SecureString with -AsPlainText. Findings include a line number, rule name, and redacted text rather than intentionally printing the full matching value.

Without -Purge, the function reports findings only. With -Purge, it creates a timestamped backup and rewrites the history file without lines matched by the current rules. The custom -WhatIf switch displays a preview when used together with -Purge; it is not implemented through PowerShell ShouldProcess semantics.

```powershell
# Report likely secrets without changing the history file

Find-PSHistorySecrets
# Preview the purge operation

Find-PSHistorySecrets -Purge -WhatIf
# Back up the history file and remove flagged lines

Find-PSHistorySecrets -Purge
```

> **History purge caution**
> The backup file contains the original history, including the sensitive entries being removed. Protect or securely delete that backup when appropriate. Close other PowerShell sessions that may still hold or write to the same history file before performing a purge.

## 5.2 Command-risk classification

Get-PSCommandRisk parses a supplied command line into PowerShell Abstract Syntax Tree (AST) command nodes and applies a fixed list of heuristics. It returns the original text, a risk level, trigger descriptions, and an evaluation timestamp. It does not execute the command.

| **LEVEL** | **EXAMPLES OF PATTERNS IN THE SCRIPT**                                                                                | **MEANING**                                                                               |
|-----------|-----------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------|
| LOW       | No listed risk pattern found.                                                                                         | No elevated heuristic trigger was identified; this is not proof that the command is safe. |
| MEDIUM    | Selected service, process, or registry/property modification commands.                                                | Potentially disruptive operation requiring review.                                        |
| HIGH      | Execution-policy changes, shutdown/restart commands, selected account/firewall changes, or recursive forced deletion. | Elevated system impact; Warn/Strict modes display a warning.                              |
| CRITICAL  | Selected disk/volume operations or selected recursive forced removal patterns involving protected Windows paths.      | Potentially destructive operation; Strict mode is intended to block this level.           |

## 5.3 Security mode

Set-PSProfileSecurityMode accepts Off, Warn, or Strict. The guard scriptblock analyses command ASTs and, in Strict mode, throws for CRITICAL findings. HIGH findings are warned about but are not blocked by this guard. The handler is registered through Set-PSReadLineOption -CommandValidationHandler.

> **Critical integration gap: the guard is not currently connected to normal Enter submission**
> The supplied script binds Enter to the PSReadLine function AcceptLine. Microsoft documents that CommandValidationHandler is called from ValidateAndAcceptLine. Because the profile does not bind Enter to ValidateAndAcceptLine, the configured guard should not be assumed to execute when a user presses Enter. Correct the key binding and test the behaviour before relying on Warn or Strict mode.

## 5.4 Security status reporting

Get-PSProfileSecurityStatus and Test-PSProfile infer that the guard is hooked when SecurityMode is not Off. They do not independently verify that PSReadLine accepted the handler or that Enter is routed through ValidateAndAcceptLine. As a result, their status can overstate the active protection.

## 5.5 Security limitations

- Command-risk checks are a small allow-listed heuristic catalogue, not semantic analysis or a comprehensive command policy.

- Dynamic command names, aliases not explicitly listed, variables, encoded arguments, nested scripts, and indirect effects may not be recognised reliably.

- A LOW classification means only that the current rules did not detect a trigger.

- The history filter and scanner cannot guarantee that secrets are absent from command history or exported files.

- Do not treat this profile as a substitute for backups, least privilege, Windows Defender, firewall policy, execution controls, or tested administrative procedures.

# 6. System and network diagnostics

The system and network functions provide local inspection helpers. They primarily gather information and format it for the current user; they do not continuously monitor the computer or automatically repair detected problems.

| **FUNCTION**          | **INFORMATION RETURNED**                                                                                        |
|-----------------------|-----------------------------------------------------------------------------------------------------------------|
| Get-SystemInfo        | Computer name, user name, operating-system caption, PowerShell version, RAM totals, and current folder.         |
| Get-CPUUsage          | First Win32_Processor instance: processor name, WMI load percentage, and core count.                            |
| Get-RamUsage          | Total, used, and free visible RAM in GB, plus percentage used.                                                  |
| Get-DiskHealth        | Available filesystem PSDrives, capacity estimate, free space, and percentage free.                              |
| Get-ServiceHealth     | Service counts grouped by current service status.                                                               |
| Get-StartupPrograms   | Win32_StartupCommand entries, including name, command, location, and user.                                      |
| Get-InstalledSoftware | Software uninstall-registry entries from standard machine-wide registry paths; optional display-name filtering. |
| Get-CertificateInfo   | Subject, expiry, thumbprint, and private-key presence in the CurrentUser My or Root certificate store.          |
| Get-NetworkInfo       | Computer/domain names, non-loopback IPv4 addresses, and configured IPv4 DNS servers.                            |
| Get-NetworkAdapters   | Adapter name, description, status, link speed, and MAC address.                                                 |
| Get-NetworkRoutes     | IPv4 destination prefixes, next hops, metrics, and interface aliases.                                           |
| Get-FirewallStatus    | Firewall profile enabled state and inbound/outbound default actions.                                            |
| Get-ListeningPorts    | Listening TCP endpoints, owning process IDs, and process names when resolvable.                                 |
| Test-TcpPort          | Attempts a TCP connection to a target and port with a configurable wait timeout.                                |
| Test-DnsLookup        | DNS records via Resolve-DnsName, or address resolution through System.Net.Dns.                                  |

## 6.1 System-check report

Invoke-PSProfileSystemCheck accepts All, Network, System, Storage, Security, or Profile. In the supplied implementation, report rows are added for System, Storage, Security, and Profile. There is no Network branch despite Network being an accepted category. Therefore -Category Network currently returns no network checks, and -Category All does not include the network functions.

## 6.2 Interpreting measurements

- Get-CPUUsage reads the WMI LoadPercentage value; it is not a high-resolution per-core performance counter or a continuous sample.

- Get-DiskHealth reports logical filesystem drive usage from Get-PSDrive. It does not read physical drive SMART status or diagnose disk health.

- Get-RamUsage reports visible operating-system memory, not necessarily all physically installed memory or GPU memory.

- Get-ListeningPorts lists local TCP listeners. It does not by itself establish whether a port is reachable from the Internet; firewall rules, NAT, routing, and remote testing also matter.

- Test-TcpPort checks a TCP connection from the current machine to a target; a timeout can mean filtering, routing failure, a closed port, or a slow endpoint.

# 7. Developer workflow and project tooling

## 7.1 Project discovery

| **FUNCTION**          | **PURPOSE**                                                                                                                                                      |
|-----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Find-PSProject        | Searches below a path for common project indicators such as solution/project files, package.json, Python project files, Cargo.toml, Dockerfile, and Git folders. |
| Get-PSProjectRoot     | Walks upward from a path and attempts to identify a project root using .git, solution files, package.json, or pyproject.toml.                                    |
| Set-LocationToGitRoot | Moves the current location to the root returned by Get-PSProjectRoot.                                                                                            |
| Find-PSProjectFiles   | Recursively finds files matching a supplied filter while excluding selected generated/vendor folders.                                                            |
| Find-PSCodeReference  | Searches source files for a text/regex pattern and can return line context.                                                                                      |

Project discovery excludes common generated or dependency directories such as .git, node_modules, bin, and obj from selected recursive searches. The list of project indicators is deliberately small and may need extending for other languages and build systems.

## 7.2 .NET helpers

```powershell
Invoke-PSDotNetBuild -Configuration Release
Invoke-PSDotNetTest
Invoke-PSDotNetClean
Get-PSDotNetProjects
```

The wrappers call dotnet build, dotnet test, dotnet clean, and a project-file search. They are convenience functions; they do not add structured result handling or automatic solution selection.

## 7.3 Python helpers

```powershell
Initialize-PSPythonEnvironment -Name '.venv'
Get-PSPythonEnvironment
Get-PSPythonPackages
Invoke-PSPythonTest
```

The environment initialiser creates a virtual environment using python -m venv. It does not activate the environment or verify the process exit code before printing its success message. The other helpers query Python/pip or run pytest in the current location.

## 7.4 Node.js and npm helpers

```powershell
Get-PSNodeEnvironment
Get-PSNpmScripts
Get-PSNpmOutdated
Invoke-PSNpmTest
```

The Node.js helper reports the resolved node executable and node/npm versions. The npm helpers list package.json scripts, check outdated packages, or run npm test from the current working directory.

## 7.5 Docker helpers

```powershell
Get-PSDockerStatus
Get-PSDockerContainers -All
Get-PSDockerImages
Get-PSDockerUsage
Invoke-PSDockerCleanupPreview
```

These functions wrap docker info, ps, images, and system df. Invoke-PSDockerCleanupPreview is a reporting function only: it displays Docker disk-usage information and does not actually remove containers, images, volumes, or build cache.

## 7.6 Project validation planner

Invoke-PSProjectCheck detects a project root and creates a short list of validation commands: dotnet build and dotnet test when a solution is found, npm test when package.json exists, and pytest when pyproject.toml or requirements.txt exists. Without -Execute it prints a dry-run plan. With -Execute it uses Invoke-Expression to execute the planned commands.

> **Execution context**
> The current implementation does not change directory to the detected project root before executing the validation commands. Run it from the intended project directory, or correct the function so the planned commands execute in the detected root. It also detects a .NET solution rather than every possible standalone project file.

# 8. Configuration and state reference

## 8.1 Configuration keys

| **KEY**                  | **DEFAULT**      | **CURRENT USE IN THE SCRIPT**                                                                                  |
|--------------------------|------------------|----------------------------------------------------------------------------------------------------------------|
| LiveTypoHighlightEnabled | $true           | Used by Invoke-PSProfileLiveTypoHighlight.                                                                     |
| MaximumEditDistance      | 2                | Declared but not used by the main command-matching calls, which pass fixed/default thresholds.                 |
| KeyboardAwareScoring     | $true           | Used to enable or disable keyboard-distance scoring.                                                           |
| SecurityMode             | Warn             | Used by Set-PSProfileSecurityMode and the security-report functions; the Enter binding gap remains.            |
| HistoryFilterEnabled     | $true           | Declared but not checked before the history handler is installed. It does not currently switch the filter off. |
| PredictionSource         | HistoryAndPlugin | Used when configuring PSReadLine, subject to version fallback.                                                 |
| PredictionViewStyle      | InlineView       | Used when configuring PSReadLine.                                                                              |
| MaxHistoryIndexCount     | 10000            | Declared but not used by the cache builder; HistoryLines defaults to 5,000.                                    |
| DeveloperToolsEnabled    | $true           | Declared but not used to gate the developer-tool functions.                                                    |
| LiveTypoMaxDistance      | 2                | Used by the live history typo-matching function.                                                               |

## 8.2 Reading and changing configuration

```powershell
Get-PSProfileConfig
Get-PSProfileConfig | Format-List
Set-PSProfileConfig -Key 'KeyboardAwareScoring' -Value $false
Set-PSProfileSecurityMode -Mode Warn
```

Set-PSProfileConfig checks whether a key exists, but it does not validate the value type or acceptable range for that key. A configuration update is therefore only as safe as the value supplied. Changes are in-memory for the current PowerShell session unless written into the profile script.

## 8.3 Status and dashboard functions

| **FUNCTION**                | **OUTPUT**                                                                                                                                         |
|-----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| Get-PSProfileStatus         | Compact object with PowerShell/PSReadLine versions, security mode, command/history counts, typo key-handler count, startup time, and integrations. |
| Get-PSProfileDiagnostics    | Formatted view of Test-PSProfile checks.                                                                                                           |
| Test-PSProfile              | Structured list of profile health checks and suggested fixes.                                                                                      |
| Show-PSProfileDashboard     | Console dashboard with runtime, indexing, security, integrations, and check results.                                                               |
| Get-PSProfileSecurityStatus | Current security mode, history-filter config flag, and an inferred guard-hooked flag.                                                              |
| Get-PSProfileConfig         | Returns the current configuration as a PSCustomObject.                                                                                             |
| Update-PSProfile            | Rebuilds command/history indexes and prints cache counts.                                                                                          |

## 8.4 Other state details

Optional module load times are stored in ModuleLoadTimes, but the dashboard only lists loaded integration names. The ExecutionTracker is populated by Measure-PSProfileCommand, and Get-PSHistoryErrors reads its failed entries. The profile does not register a general PowerShell event hook to capture every command or every error.

# 9. Command reference

The following tables group the public functions defined by the supplied profile. Parameters shown are the useful/common forms rather than a replacement for Get-Help output. Run Get-Command -CommandType Function to inspect the functions loaded into the current session.

## 9.1 Command intelligence

| **FUNCTION**                     | **PURPOSE / COMMON PARAMETERS**                                                                           |
|----------------------------------|-----------------------------------------------------------------------------------------------------------|
| Update-PSCommandCache            | Rebuild command and history indexes. Supports -HistoryOnly and -HistoryLines (100–50,000; default 5,000). |
| Update-PSProfile                 | Convenience wrapper that refreshes the cache and reports totals.                                          |
| Get-PSProfileCommandMatches      | Fuzzy-match an installed command name. Supports -Name, -MaximumDistance, and -Limit.                      |
| Get-PSProfileCommandConfidence   | Calculate a heuristic score and explanation for one candidate match.                                      |
| Test-PSProfileCommandSpelling    | Display a command-intelligence report and best candidate without changing the input buffer.               |
| Test-CommandSpelling             | Short alias-style wrapper for Test-PSProfileCommandSpelling.                                              |
| Get-PSProfileBestHistoryCommand  | Find the best history prefix/typo match for a typed command name.                                         |
| Get-PSProfileTypoMismatchIndexes | Return character positions considered mismatches between typed and expected text.                         |
| Get-PSProfileEditDistance        | Calculate transposition-aware edit distance between two strings.                                          |
| Get-PSProfileKeyboardDistance    | Return approximate geometric distance between two QWERTY key coordinates.                                 |
| Get-PSProfileCommandContext      | Check the second token against a selected external-tool subcommand catalogue.                             |
| Find-LocalCommand                | Search Get-Command by wildcard name; optionally filter by command type or module.                         |
| Get-PSProfileCommandInfo         | Return command metadata, help synopsis, parameter details, and history count.                             |
| Get-PSProfileCommandExamples     | Display examples returned by Get-Help for a command.                                                      |
| Get-PSProfileCommandUsage        | Show top command counts, or usage information for one named command.                                      |
| Get-PSProfileCommandDependencies | Report the parent module and declared module/assembly requirements.                                       |
| Search-PSProfileCommandHelp      | Search Get-Help and return name, category, and synopsis.                                                  |

## 9.2 History and security auditing

| **FUNCTION**                   | **PURPOSE / COMMON PARAMETERS**                                                        |
|--------------------------------|----------------------------------------------------------------------------------------|
| Get-PSHistoryPath              | Return the current PSReadLine history-save path.                                       |
| Get-PSHistoryStats             | Summarise raw history lines and show the most frequent first tokens.                   |
| Get-PSHistoryUnique            | Return unique history lines, limited by -Limit.                                        |
| Get-PSHistoryTimeline          | Divide a selected history tail into approximate phases and show sample commands.       |
| Get-PSHistoryDuplicates        | List exact repeated lines meeting -MinOccurrences.                                     |
| Get-PSHistoryErrors            | Return failed records created by Measure-PSProfileCommand.                             |
| Export-PSHistory               | Export history as Csv, Json, or Text to -Path.                                         |
| Search-PSHistory               | Search history using -Pattern; supports -SimpleMatch and -Limit.                       |
| Find-PSHistorySecrets          | Scan for selected credential patterns. Supports -Purge and its custom -WhatIf preview. |
| Get-PSCommandRisk              | Return a heuristic risk report for a supplied command line.                            |
| Test-PSCommandRisk             | Display the risk report in colour-coded console output.                                |
| Set-PSProfileSecurityMode      | Set Off, Warn, or Strict for the intended PSReadLine guard behaviour.                  |
| Get-PSProfileSecurityStatus    | Report the selected mode and inferred guard/filter status.                             |
| Measure-PSProfileCommand       | Run a scriptblock, time it, record a result, and return its output.                    |
| Add-PSProfileHistoryCommandUse | Increment the usage counter for a recognised installed command name.                   |

## 9.3 Local diagnostics and system information

| **FUNCTION**                | **PURPOSE / COMMON PARAMETERS**                                                |
|-----------------------------|--------------------------------------------------------------------------------|
| Get-NetworkInfo             | Show local computer/domain, IPv4 addresses, and DNS servers.                   |
| Get-ListeningPorts          | List local TCP listeners; optionally filter with -Port.                        |
| Get-PortProcess             | Convenience wrapper for Get-ListeningPorts -Port.                              |
| Test-TcpPort                | Test a TCP target/port with optional -TimeoutMs.                               |
| Test-DnsLookup              | Resolve a DNS name.                                                            |
| Get-NetworkAdapters         | List adapters and link information.                                            |
| Get-NetworkRoutes           | List IPv4 routes.                                                              |
| Get-FirewallStatus          | Show Windows Firewall profile status.                                          |
| Get-CPUUsage                | Read basic CPU details and WMI load percentage.                                |
| Get-RamUsage                | Calculate visible RAM usage and percentage.                                    |
| Get-DiskHealth              | Show filesystem drive free space; not physical disk health.                    |
| Get-ServiceHealth           | Count services grouped by status.                                              |
| Get-StartupPrograms         | List WMI startup-command entries.                                              |
| Get-InstalledSoftware       | List registered installed software; supports -Filter.                          |
| Get-CertificateInfo         | List CurrentUser certificates from My or Root store.                           |
| Get-SystemInfo              | Show basic OS, user, PowerShell, RAM, and current-folder information.          |
| Invoke-PSProfileSystemCheck | Build a simple report for All, Network, System, Storage, Security, or Profile. |

## 9.4 Projects and developer tools

| **FUNCTION**                                     | **PURPOSE / COMMON PARAMETERS**                                               |
|--------------------------------------------------|-------------------------------------------------------------------------------|
| Find-PSProject                                   | Search a path for selected project markers; supports -MaxDepth.               |
| Get-PSProjectRoot                                | Walk upward to find a likely project root.                                    |
| Set-LocationToGitRoot                            | Move to the detected project root.                                            |
| Find-PSProjectFiles                              | Search files by -Filter under a path.                                         |
| Find-PSCodeReference                             | Search source files; supports extension, case sensitivity, and context lines. |
| Invoke-PSDotNetBuild                             | Run dotnet build with a selected configuration.                               |
| Invoke-PSDotNetTest / Clean                      | Run dotnet test or dotnet clean.                                              |
| Get-PSDotNetProjects                             | Find files matching the \*.\*proj wildcard.                                   |
| Initialize-PSPythonEnvironment                   | Create a virtual environment folder using python -m venv.                     |
| Invoke-PSPythonTest                              | Run pytest.                                                                   |
| Get-PSPythonEnvironment / Packages               | Report Python/pip environment details or list installed packages.             |
| Get-PSNodeEnvironment                            | Report Node.js and npm paths/versions.                                        |
| Invoke-PSNpmTest / Get-PSNpmOutdated             | Run npm test or npm outdated.                                                 |
| Get-PSNpmScripts                                 | Read the scripts property from package.json.                                  |
| Get-PSDockerStatus / Containers / Images / Usage | Report Docker daemon, containers, images, or disk use.                        |
| Invoke-PSDockerCleanupPreview                    | Display Docker disk usage as a cleanup assessment; does not delete anything.  |

## 9.5 Shell, Git, and profile helpers

| **FUNCTION / ALIAS**                        | **PURPOSE**                                                             |
|---------------------------------------------|-------------------------------------------------------------------------|
| Edit-PSProfile                              | Open the current profile path in Notepad.                               |
| Open-PSProfileFolder                        | Open the directory containing the profile, or print its path.           |
| Reload-PSProfile                            | Dot-source the current profile again.                                   |
| mkcd                                        | Create a directory and move into it.                                    |
| up                                          | Move up one or more directory levels.                                   |
| croot                                       | Move to the home directory.                                             |
| ll                                          | List current directory entries in a table.                              |
| Copy-CurrentPath / cpath                    | Copy the current path to the clipboard when Set-Clipboard is available. |
| Open-CurrentDirectory / owd                 | Open the current directory in File Explorer, or print the path.         |
| git-status, git-diff, git-log, git-branches | Convenience wrappers for common Git inspection commands.                |
| git-pull, git-push, git-commit              | Convenience wrappers that pass remaining arguments to Git.              |

# 10. Static review: limitations and recommended fixes

The following findings are the most important issues visible in the supplied source. They are presented as engineering review items, not as proof that every item will reproduce identically in every PowerShell version.

| **PRIORITY** | **FINDING**                                                                                                                                       | **RECOMMENDED ACTION**                                                                                                                                                                  |
|--------------|---------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Critical     | Security validation is registered, but Enter is bound to AcceptLine. The PSReadLine CommandValidationHandler is invoked by ValidateAndAcceptLine. | Bind Enter to ValidateAndAcceptLine (or explicitly invoke validation another supported way). Test that a known CRITICAL test command is blocked in Strict mode and warned in Warn mode. |
| High         | Get-PSProjectRoot and Invoke-PSProjectCheck contain compound Test-Path conditions written without parenthesising each command invocation.         | Rewrite compound conditions as explicit expressions, for example: if ((Test-Path $a) -or (Test-Path $b)) { ... }. Run the functions under both target PowerShell editions.            |
| High         | Security status reports the guard as hooked whenever the mode is not Off, rather than verifying the actual key binding and handler state.         | Track handler-registration success separately and report “configured” versus “active on Enter” accurately.                                                                              |
| High         | HistoryFilterEnabled is not used to control installation or operation of the AddToHistoryHandler.                                                 | Wrap handler registration in a config check and provide a safe way to restore normal history handling.                                                                                  |
| Medium       | MaximumEditDistance, MaxHistoryIndexCount, and DeveloperToolsEnabled are declared but are not used as operative settings.                         | Either implement each setting consistently or remove it to avoid misleading configuration.                                                                                              |
| Medium       | Invoke-PSProfileSystemCheck accepts Network but has no Network implementation.                                                                    | Add network checks to the Network branch and to All, or remove Network from ValidateSet until implemented.                                                                              |
| Medium       | The keyboard map assigns duplicate coordinates to some punctuation keys and uses a simplified grid.                                               | Correct key coordinates for the supported layout, make layout configurable, and test scoring with realistic adjacent-key mistakes.                                                      |
| Medium       | The edit-distance method handles adjacent transpositions but is an OSA variant, not unrestricted Damerau-Levenshtein.                             | Name the algorithm accurately in output/documentation, or replace it if unrestricted Damerau-Levenshtein behaviour is required.                                                         |
| Medium       | The live highlight directly redraws console cells and many key handlers replace default PSReadLine bindings.                                      | Test wrapping, multiline prompts, resize, paste, terminal emulators, keyboard layouts, and coexistence with PSFzf/other modules.                                                        |
| Medium       | Invoke-PSProjectCheck executes planned commands with Invoke-Expression and does not change to the detected root first.                            | Use an explicit command dispatch and run under Push-Location $root / Pop-Location with try/finally.                                                                                    |
| Medium       | Initialize-PSPythonEnvironment prints success without verifying python availability or the process exit code.                                     | Check Get-Command python, capture $LASTEXITCODE, and report success only when the process succeeds.                                                                                    |
| Medium       | Get-PSHistoryErrors only reports Measure-PSProfileCommand records, not all command failures.                                                      | Rename the function to reflect measured-script failures or add a deliberate error-capture mechanism.                                                                                    |
| Low          | Optional module load timings are collected but not shown on the dashboard.                                                                        | Display ModuleLoadTimes or remove the unused telemetry field.                                                                                                                           |

## 10.1 Further design improvements

- Split the profile into separate files (configuration, command intelligence, history/security, diagnostics, developer tooling, and startup) and dot-source them from a short entry-point profile.

- Add a configuration validation function that checks types, ranges, installed module versions, and feature dependencies before applying settings.

- Add a test suite using Pester for edit distance, command ranking, history parsing, risk classification, and project-root discovery.

- Use SupportsShouldProcess and -WhatIf for any function that modifies files or executes potentially disruptive operations.

- Add structured logging for startup failures instead of silently swallowing every optional-module and PSReadLine configuration exception.

- Separate “risk advisory” from “execution enforcement”; make it visually clear when a guard is not active.

# 11. Installation, setup, and validation

## 11.1 Before installation

1.  Identify the profile path for the shell and host where PDE should run: display $PROFILE in that PowerShell session.

2.  Back up the existing profile before replacing or merging any content.

3.  Create the profile directory if it does not exist. Do not assume Windows PowerShell 5.1 and PowerShell 7 use the same profile file.

4.  Test the script in a separate test profile or in a session launched with -NoProfile before making it the normal startup profile.

5.  Keep a second PowerShell session open while changing profile files so a broken startup profile can be repaired.

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
# Open the profile

Edit-PSProfile
```

## 11.3 First-launch verification

```powershell
$PSVersionTable | Format-List
Get-Module PSReadLine | Select-Object Name, Version
Get-PSProfileStatus | Format-List
Test-PSProfile | Format-Table -AutoSize
Show-PSProfileDashboard
Get-PSProfileSecurityStatus | Format-List
```

Run these checks in both Windows PowerShell 5.1 and PowerShell 7+ if both are intended targets. Check the console input behaviour manually: Tab, Shift+Tab, Ctrl+R, Ctrl+S, arrow keys, paste, Backspace, Delete, Enter, and prediction acceptance. Also test in each terminal emulator that will be used regularly.

## 11.4 Functional test checklist

| **AREA**          | **TEST**                                                                               | **EXPECTED RESULT**                                                                        |
|-------------------|----------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| Command cache     | Run Update-PSProfile.                                                                  | A non-zero command count is reported; no terminating errors.                               |
| Typo report       | Run Test-CommandSpelling -Name 'Get-ChilItem'.                                         | A close command candidate is displayed when indexed.                                       |
| History index     | Run Get-PSProfileCommandUsage.                                                         | The most frequently recognised command names are listed.                                   |
| History filter    | Submit a harmless test line containing a dummy token marker.                           | The line is skipped from PSReadLine history; do not use a real credential.                 |
| Risk classifier   | Run Test-PSCommandRisk -CommandLine 'Format-Volume -DriveLetter Z'.                    | A CRITICAL classification is displayed; the command is not executed by this test function. |
| Security guard    | After fixing Enter binding, submit a controlled test command in Warn and Strict modes. | Warn produces a warning; Strict blocks the controlled CRITICAL test.                       |
| Network           | Run Get-ListeningPorts and Test-TcpPort against a known test endpoint.                 | Output reflects the current machine/network and errors are handled clearly.                |
| Project detection | Run Get-PSProjectRoot from inside and outside a test repository.                       | Correct root is found, or null is returned without a parser error.                         |
| Project check     | Run Invoke-PSProjectCheck without -Execute.                                            | Only a plan is printed; no build/test commands run.                                        |
| Cross-version     | Repeat key tests in 5.1 and 7+.                                                        | Unsupported features degrade clearly rather than breaking profile startup.                 |

## 11.5 Rollback

If the profile prevents normal startup, launch a shell with -NoProfile, restore the saved profile backup, or temporarily rename the profile file. Keep optional modules and custom PSReadLine bindings disabled until the base profile loads reliably.

# Appendix A. Quick-start command sheet

| **TASK**                       | **COMMAND**                                                        |
|--------------------------------|--------------------------------------------------------------------|
| Show profile dashboard         | Show-PSProfileDashboard                                            |
| Get compact profile status     | Get-PSProfileStatus \| Format-List                                 |
| Run profile diagnostics        | Test-PSProfile \| Format-Table -AutoSize                           |
| Refresh command/history index  | Update-PSProfile                                                   |
| Find a likely command spelling | Test-CommandSpelling -Name 'Get-ChilItem'                          |
| Inspect one command            | Get-PSProfileCommandInfo -Name 'Get-ChildItem' \| Format-List      |
| Show common command usage      | Get-PSProfileCommandUsage                                          |
| Show history statistics        | Get-PSHistoryStats                                                 |
| Search command history         | Search-PSHistory -Pattern 'Get-NetTCPConnection'                   |
| Scan existing history          | Find-PSHistorySecrets                                              |
| Preview history purge          | Find-PSHistorySecrets -Purge -WhatIf                               |
| Inspect listening TCP ports    | Get-ListeningPorts \| Sort-Object Port                             |
| Check a TCP endpoint           | Test-TcpPort -Target 'localhost' -Port 443                         |
| Show firewall profiles         | Get-FirewallStatus                                                 |
| Show RAM and disk usage        | Get-RamUsage; Get-DiskHealth                                       |
| Move to project root           | Set-LocationToGitRoot                                              |
| Search project references      | Find-PSCodeReference -Pattern 'Invoke-Expression' -Extension 'ps1' |
| Plan project checks            | Invoke-PSProjectCheck                                              |
