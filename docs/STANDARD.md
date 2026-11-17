# Script standard

Every script in this repository follows the same standard, so you can run any
of them the same way in any RMM and read the result the same way.

The short version: one file per script, inputs in three ways, results in four
ways, never a prompt, and nothing destructive without a deliberate step.

## Script types

| Type | File name starts with | What it does | Changes the machine? |
|---|---|---|---|
| Monitor | `test-` | Checks one condition and says healthy or not. Built to run on a schedule and raise an alert. | Never |
| Report | `get-` | Collects facts into a table (inventory, audit, evidence). | Never |
| Action | `install-` `uninstall-` `set-` `enable-` `disable-` `remove-` `clear-` `reset-` `repair-` `restart-` `update-` `new-` `invoke-` | Makes a change, checks it worked, says what changed. | Yes |

A Monitor and an Action that share a noun form a pair (a `test-` script that
alerts, a `repair-` script that fixes). The Monitor's alert (exit code 1) is
what an RMM uses to trigger the Action.

The folder and file name is the script's slug: lowercase, verb first.

## Inputs

Every input has one name in PascalCase (for example `MinAgeDays`) and works
three ways:

1. A command-line argument: `-MinAgeDays 180`.
2. An environment variable, which is how most RMMs pass script variables:
   `MinAgeDays=180` or `MIN_AGE_DAYS=180`. Windows environment variables are
   not case sensitive.
3. The default at the top of the file, in the `param()` block, for RMMs that
   can only run a script as it is.

If more than one is set, the order is: argument, then environment variable,
then the default in the file. Values are plain text; yes/no inputs accept
`true`, `false`, `yes`, `no`, `1`, `0`, `on`, `off` in any case. An invalid
value stops the run with an error that names the input and the allowed
values. Unknown arguments are ignored with a warning, because some RMMs add
their own.

Every script also accepts these inputs:

| Input | Values | Default | Meaning |
|---|---|---|---|
| `DryRun` | true / false | false (true for High-risk actions) | Actions only: list every change and make none. `-WhatIf` means the same. |
| `OutputFormat` | `Text`, `Answer`, `Json`, `Csv` | `Text` | What is printed (see Output). |
| `ExportPath` | file path | empty | Also write the data rows to this `.csv` or `.json` file. |
| `ResultField` | custom field name | empty | Also write the answer to this RMM custom field. |
| `Approve` | the script's name | empty | High-risk actions only (see Safety). |
| `MaxChanges` | whole number | 25 for High risk | The most changes one run may make. |

Secrets are never passed as arguments and never printed.

## Output

### Exit codes

| Exit | Status | Meaning |
|---|---|---|
| 0 | `OK` | Monitor healthy; report complete; action had nothing to do. |
| 0 | `CHANGED` | Action made its change and checked it worked. |
| 0 | `DRYRUN` | Action listed what it would change and changed nothing. |
| 0 | `SKIPPED` | Does not apply here (wrong OS, feature absent). |
| 1 | `ALERT` | Monitor found the problem it checks for. |
| 2 | `ERROR` | The script could not do its job: bad input, missing prerequisite, a failure, or a change that did not take. |

Monitors never exit 0 while unhealthy. Actions never exit 1.

### The RESULT line

In `Text` mode the last line printed is always:

```
RESULT: ALERT | C: 12% free (48 GB of 400 GB); threshold 15%
```

That is `RESULT: <status> | <answer>`. The answer is one line, 200 characters at
most, and leads with the fact and its numbers. Errors also print
`ERROR: <what failed>. <what to do>` to stderr first.

### Formats

- `Text` (default): a header line, a plain description of what it is doing, a
  table of results, any warnings, and the RESULT line.
- `Answer`: only the answer, one line. Use it where an RMM stores the whole
  output in a field.
- `Json`: one JSON object (`schema`, `script`, `version`, `computer`,
  `startedUtc`, `durationSeconds`, `status`, `exitCode`, `answer`, `fields`,
  `rows`, `warnings`, `errors`) and nothing else.
- `Csv`: the rows as CSV with a header, and nothing else.

`ExportPath` also writes the rows to a file. Dates are ISO 8601 UTC.

### Custom fields

With `ResultField` set, the answer is written to that field on the RMM the
script detects: NinjaOne (field name), Datto RMM (UDF number 1 to 300, 255
characters), and Syncro on Windows (asset field). Other RMMs do not accept a
write from the script: point their collector or script field at the script
with `OutputFormat=Answer`. A failed field write is a warning and never fails
the run.

### Change log

Every change an action makes is also appended, one line each, to
`%ProgramData%\MSPOutpost\Logs\<script>.log`, so you can show a client what
the script did to their PC. Monitors and reports write no log.

## Safety

- Monitors and reports are read-only. Their description says so.
- Actions are idempotent (running twice changes nothing the second time),
  validate every input before changing anything, support `-WhatIf` / `DryRun`,
  and check the result after changing.
- A High-risk action (deletes data, removes security software, signs users
  out, or acts on many accounts) is a dry run unless both `DryRun=false` and
  `Approve=<script name>` are set. Typing the script's name is the deliberate
  step; one site-wide `DryRun=false` can never unlock every destructive script.
- `MaxChanges` caps the real changes in one run (25 by default for High risk).
  A plan over the limit changes nothing and ends with an error that says what
  to set.
- Before an action edits or deletes configuration, it copies it to
  `%ProgramData%\MSPOutpost\Backups\<script>\<UTC time>\` and keeps the last 10
  runs. If the backup fails, nothing is changed.
- Protected things are never touched: the RMM agent running the script, the
  script's own process tree, built-in and system accounts, service profiles,
  loaded user profiles and the system drive's root folders.
- Disruptive steps (reboot, sign-out, closing apps) wait for a machine with
  nobody signed in, unless an explicit input allows them.
- Name filters that match everything are refused.

## Requirements and behaviour

- Windows PowerShell 5.1 syntax, so scripts run on every supported Windows and
  on PowerShell 7. If an RMM starts a 32-bit PowerShell on 64-bit Windows, the
  script restarts itself in 64-bit.
- A script never prompts and never waits for a key.
- Scripts are plain ASCII text with LF line endings, one self-contained file:
  no modules to install and no other files to copy.
- Network downloads use HTTPS and are verified before they run.

## Disclaimer

Provided "as is" under the MIT License, without warranty of any kind. Test
before production use. MSP Outpost and User First Digital Inc. accept no
liability for any damage or loss.
