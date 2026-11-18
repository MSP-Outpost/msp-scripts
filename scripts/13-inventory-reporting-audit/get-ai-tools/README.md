# Which AI tools do staff use? - shadow AI apps

> Lists the AI tools installed on the PC and for each user: ChatGPT, Claude, Copilot, Ollama, Cursor and more.

| | |
|---|---|
| Script | `get-ai-tools.ps1` |
| Type | Report |
| Category | Inventory, reporting & audit |
| Platforms | Windows 10, Windows 11, Windows Server 2016+ |
| Runs as | System |
| Requires | PowerShell 5.1; administrator rights |
| Changes | None |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 30 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT IS READ-ONLY. It answers "which AI tools do staff use?" by looking for the install traces of well-known AI tools, one row per tool and place it was found:

- installed programs (Programs and Features entries for this PC and for signed-in users),
- Microsoft Store apps for all users (the Copilot app, ChatGPT; the Copilot provider package built into Windows 11 is ignored),
- per-user installs under each user's AppData folder, which need no admin rights and so never show in Programs and Features: Claude, Ollama, LM Studio, GPT4All, Jan, Cursor, Windsurf, Perplexity Comet,
- VS Code extensions in each user's .vscode folder: GitHub Copilot, GitHub Copilot Chat and Claude Code,
- browser extensions identified by their Chrome Web Store ID in every Chrome, Edge and Brave profile: Grammarly.

The tools covered are those whose install names, folders or IDs are known with confidence; it is a list of the common ones, not every AI product. Browser extensions are matched by ID only (a name can be copied by an imitation): other AI extensions (Monica, Sider, Merlin, Harpa and the like) are not recognised here, so use get-browser-extensions with NameMatch to look for them by name. Web-only tools used in a browser tab (chatgpt.com, claude.ai, gemini.google.com) leave no install and are not seen. Finding a tool means it is installed, not that it was used. Needs administrator rights.

## Inputs

This script has no inputs of its own. The [standard inputs](#standard-inputs) below still apply.

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\get-ai-tools.ps1
```

Lists the AI tools found, with where, version and user.

```powershell
.\get-ai-tools.ps1 -OutputFormat Csv
```

The same list as CSV, for a spreadsheet.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `OutputFormat`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
5 AI tools found: ChatGPT desktop, Claude desktop, Cursor, GitHub Copilot (VS Code), Ollama
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `SKIPPED` | The report is complete, or it does not apply to this machine. |
| 2 | `ERROR` | The script could not do its job (bad input, missing prerequisite, failure). |

Data columns: `Tool`, `Where`, `Version`, `User`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/get-ai-tools

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
