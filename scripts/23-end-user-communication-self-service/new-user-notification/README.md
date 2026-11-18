# Tell the user something - show a notification

> Shows a pop-up notification (toast) to the user who is signed in, with an optional button that opens a web page.

| | |
|---|---|
| Script | `new-user-notification.ps1` |
| Type | Action |
| Category | End-user communication & self-service |
| Platforms | Windows 10, Windows 11 |
| Runs as | System |
| Requires | PowerShell 5.1, administrator rights, a user signed in at the console |
| Changes | Shows a notification on the signed-in user's screen (a toast, or msg.exe if toasts are off) |
| Risk | Low |
| Reboot | Never |
| Typical runtime | Under 20 seconds |
| Version | 1.0.0 |
| Updated | 2026-11-16 |

## What it does

THIS SCRIPT CHANGES THINGS (it puts a message on the user's screen). As the user who is signed in at the console (the script runs from SYSTEM and shows the message in that user's own session), it:

- shows a Windows notification (toast) with Title and Message, using the Windows PowerShell notification identity,
- adds an Open button when ButtonUrl is set (opens that web page in the user's browser) and, with Urgency reminder, keeps the notification on screen until the user dismisses it,
- if notifications are switched off for that user, or the toast fails, shows the same text with msg.exe in the user's session instead.

It never waits for a click and never blocks the run. The answer says the notification was SHOWN; it cannot tell whether the user read it, and with Do Not Disturb or Focus Assist on, Windows may only put it in the Action Center. Running it twice shows it twice.

Nobody signed in: SKIPPED. Text must be plain ASCII (letters, digits, punctuation, spaces) and at most 300 characters. ButtonUrl must start with https:// or http://. Do not put secrets in a message: it is written to disk for a moment and shown on screen.

## Inputs

| Input | Meaning | Default | Environment variable |
|---|---|---|---|
| `Title` | Bold first line of the notification. Plain ASCII, 1 to 300 characters. Default "Message from IT". | `Message from IT` | `Title` or `TITLE` |
| `Message` | The text of the notification. Plain ASCII, 1 to 300 characters. Required. | (empty) | `Message` or `MESSAGE` |
| `ButtonUrl` | Optional web address (https:// or http://, up to 300 characters). Adds an Open button to the notification. Default empty: no button. | (empty) | `ButtonUrl` or `BUTTON_URL` |
| `Urgency` | normal (default): a normal toast that goes to the Action Center after a few seconds. reminder: stays on screen until the user dismisses it. | `normal` | `Urgency` or `URGENCY` |

<a id="standard-inputs"></a>

### Standard inputs

Every script also accepts `OutputFormat`, `ExportPath` and `ResultField` (see Output below). As an action it also accepts `DryRun` (or `-WhatIf`). Details are in [docs/STANDARD.md](../../../docs/STANDARD.md).

## How to run it

From an elevated Windows PowerShell prompt, or from your RMM as a PowerShell script:

```powershell
.\new-user-notification.ps1 -Title "Restart needed" -Message "Please restart your PC today so updates can finish."
```

Shows a normal notification to the signed-in user.

```powershell
.\new-user-notification.ps1 -Message "Your password expires tomorrow." -ButtonUrl https://example.com/password -Urgency reminder
```

Shows a notification that stays until dismissed, with an Open button.

### In an RMM

Upload the script as a PowerShell script and run it as the System account. Pass inputs in whichever way your RMM supports:

- **Script variables or environment variables:** create a variable with the same name as the input (for example `Title`). Both the PascalCase name and the UPPER_SNAKE name work.
- **Command-line arguments:** `-InputName value`.
- **No variables at all:** edit the default for that input in the `param()` block at the top of the file.

Yes/no values accept `true`, `false`, `yes`, `no`, `1`, `0`.

## Output

The last line of output is always the result, in the form `RESULT: <status> | <answer>`. An example answer:

```
Notification shown to PC01\jsmith as a toast; shown, not confirmed read.
```

Exit codes:

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK`, `CHANGED`, `DRYRUN`, `SKIPPED` | Nothing to do, changed and verified, listed what it would change, or does not apply here. |
| 2 | `ERROR` | The script could not do its job, or a change did not take. |

Data columns: `Item`, `Change`, `Result`.

`OutputFormat` chooses what is printed: `Text` (default, a readable report ending in the result line), `Answer` (only the one-line answer), `Json` (one JSON object) or `Csv` (the rows). `ExportPath` also writes the rows to a `.csv` or `.json` file.

`ResultField` also writes the one-line answer to a custom field. The script writes it on NinjaOne (field name), Datto RMM (UDF number 1 to 300) and Syncro on Windows (asset field). On other RMMs, point their script output or collector at the script with `OutputFormat=Answer`.

Every change is also logged to `%ProgramData%\MSPOutpost\Logs\new-user-notification.log`.

## Changelog

- 1.0.0 2026-11-16 First version.

## More

Full page: https://mspoutpost.com/scripts/new-user-notification

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
