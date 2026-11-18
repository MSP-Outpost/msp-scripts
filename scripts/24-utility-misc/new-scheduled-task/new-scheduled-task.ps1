#Requires -Version 5.1
<#
.SYNOPSIS
    Creates or updates a scheduled task that runs a program at startup, at logon, daily or once.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It registers one scheduled task in the root
    folder of Task Scheduler with one trigger and one action, and nothing
    else: it never runs the task, never deletes a task and never touches
    another one.

    The task is defined by the inputs: TaskName, the program (Command) and its
    Arguments, a Trigger (Startup, Logon, Daily or Once, with At for the last
    two), who it runs as (System, or Users: the BUILTIN\Users group, so it runs
    in the session of whoever signs in) and whether it is Hidden in Task
    Scheduler.

    Running it again with the same inputs changes nothing and says OK. With
    different inputs it updates the task: the old definition is exported to
    XML (Export-ScheduledTask) and copied to
    %ProgramData%\MSPOutpost\Backups\new-scheduled-task\ first.

    Names: TaskName must start with MSPOutpost- so this script only ever
    manages its own tasks. Set AllowAnyName=true to use another name; that can
    replace an existing task of that name (after the backup).

    Privilege-escalation guard: a task that runs as System executes its
    program with full rights, so when RunAs is System the script refuses a
    program (or a file named in Arguments) that standard users could change:
    the file or its folder is writable by Users, Authenticated Users, Everyone
    or Interactive, or it is owned by an ordinary user, or a parent folder
    lets users delete or re-permission it. Fix the permissions or put the
    program under C:\Program Files or C:\Windows.

    The Command is stored as a full path (a bare name such as powershell.exe is
    resolved first). A .ps1 file is refused: run powershell.exe with
    Arguments "-NoProfile -File <script>" instead.

.PARAMETER TaskName
    Task name, required, no \ / : * ? " < > |. Must start with MSPOutpost-
    unless AllowAnyName is true. Environment variable: TaskName

.PARAMETER Command
    Program to run: a full path or a name found on PATH. Required.
    Environment variable: Command

.PARAMETER Arguments
    Arguments passed to the program. Optional. Environment variable: Arguments

.PARAMETER Trigger
    Startup (default), Logon, Daily or Once. Environment variable: Trigger

.PARAMETER At
    Start time for Daily and Once: HH:mm (24-hour, local) or, for Once only,
    yyyy-MM-ddTHH:mm. With Once and HH:mm the next such time is used. Ignored
    for Startup and Logon. Environment variable: At

.PARAMETER RunAs
    System (default) or Users (the BUILTIN\Users group, interactive; use with
    Logon, Daily or Once). Environment variable: RunAs

.PARAMETER Hidden
    true to hide the task in Task Scheduler. Default false.
    Environment variable: Hidden

.PARAMETER AllowAnyName
    true to allow a TaskName without the MSPOutpost- prefix. Default false.
    Environment variable: AllowAnyName

.PARAMETER DryRun
    true to list what would be changed and change nothing. Default false.
    -WhatIf does the same. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\new-scheduled-task.ps1 -TaskName MSPOutpost-Cleanup -Command C:\Windows\System32\cleanmgr.exe -Arguments /AUTOCLEAN -Trigger Daily -At 03:00

    Runs the program every day at 03:00 as SYSTEM.

.EXAMPLE
    .\new-scheduled-task.ps1 -TaskName MSPOutpost-Welcome -Command C:\Windows\System32\msg.exe -Arguments "* Welcome" -Trigger Logon -RunAs Users

    Runs for whoever signs in, in their session.

.NOTES
    Name:        Create or update a scheduled task
    Slug:        new-scheduled-task
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    24 Utility / misc
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Creates or updates one scheduled task; saves the old definition as XML before an update
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 10 seconds
    Answer:      "Created task MSPOutpost-Cleanup: daily at 03:00 as SYSTEM, C:\Windows\System32\cleanmgr.exe"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/new-scheduled-task
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text. Defaults are the
    # place to edit when your RMM cannot pass arguments or variables.
    [string] $TaskName = '',
    [string] $Command = '',
    [string] $Arguments = '',
    [string] $Trigger = 'Startup',
    [string] $At = '',
    [string] $RunAs = 'System',
    [string] $Hidden = 'false',
    [string] $AllowAnyName = 'false',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'new-scheduled-task'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('TaskName', 'Command', 'Arguments', 'Trigger', 'At', 'RunAs', 'Hidden', 'AllowAnyName')
    Fields  = @('Item', 'Change', 'Result')
}

#region MSP Outpost runtime 1.0.0 -- do not edit (shared by every MSP Outpost script)
# Reads inputs, prints, collects rows, writes the RMM field, logs changes, exits.
# Standard: https://mspoutpost.com/scripts/standard

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = 'None' }

# An RMM may start 32-bit PowerShell on 64-bit Windows; registry and System32
# redirection then break scripts silently. Relaunch in 64-bit with the same
# arguments (environment variables are inherited) and pass the exit code on.
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and [Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess -and $PSCommandPath) {
    $outpostHost64 = Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -LiteralPath $outpostHost64) {
        $outpostArgs = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
        foreach ($outpostKey in $PSBoundParameters.Keys) {
            $outpostValue = $PSBoundParameters[$outpostKey]
            if ($outpostKey -eq 'UnknownArguments') {
                $outpostArgs += @($outpostValue)
            }
            elseif ($outpostValue -is [System.Management.Automation.SwitchParameter]) {
                if ($outpostValue.IsPresent) { $outpostArgs += "-$outpostKey" }
            }
            else {
                $outpostArgs += "-$outpostKey"
                $outpostArgs += [string]$outpostValue
            }
        }
        & $outpostHost64 @outpostArgs
        exit $LASTEXITCODE
    }
}

if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

Set-StrictMode -Version 2.0
$script:OutpostBound = @{}
foreach ($outpostKey in $PSBoundParameters.Keys) { $script:OutpostBound[$outpostKey] = $PSBoundParameters[$outpostKey] }
$script:OutpostRun = @{
    Started    = [DateTime]::UtcNow
    Rows       = New-Object -TypeName System.Collections.ArrayList
    Warnings   = New-Object -TypeName System.Collections.ArrayList
    Errors     = New-Object -TypeName System.Collections.ArrayList
    FieldValue = $null
    Format     = 'Text'
    DryRun     = $false
    Done       = $false
}

function Write-OutpostLine {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Text)
    if ($script:OutpostRun.Format -eq 'Text') { Write-Host $Text }
}

function Write-OutpostWarning {
    param([Parameter(Mandatory = $true)][string] $Text)
    [void]$script:OutpostRun.Warnings.Add($Text)
    Write-OutpostLine -Text "WARNING: $Text"
}

function ConvertTo-OutpostSnakeName {
    param([Parameter(Mandatory = $true)][string] $Name)
    ($Name -creplace '([a-z0-9])([A-Z])', '$1_$2').ToUpperInvariant()
}

function Get-OutpostRawInput {
    # Argument > environment variable (Name or NAME_SNAKE) > default in the file.
    param([Parameter(Mandatory = $true)][string] $Name)
    if ($script:OutpostBound.ContainsKey($Name)) { return [string]$script:OutpostBound[$Name] }
    foreach ($envName in @($Name, (ConvertTo-OutpostSnakeName -Name $Name))) {
        $envValue = [Environment]::GetEnvironmentVariable($envName)
        if ($null -ne $envValue -and $envValue.Trim() -ne '') { return $envValue.Trim() }
    }
    $default = Get-Variable -Name $Name -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if ($null -eq $default) { return '' }
    return ([string]$default).Trim()
}

function Stop-OutpostInput {
    param([string] $Name, [string] $Value, [string] $Expected)
    Stop-OutpostRun -Message "Input $Name is '$Value'; expected $Expected. Set the argument -$Name or the environment variable $Name."
}

function Read-OutpostText {
    param([Parameter(Mandatory = $true)][string] $Name, [switch] $Required)
    $value = Get-OutpostRawInput -Name $Name
    if ($Required -and $value -eq '') {
        Stop-OutpostRun -Message "Required input $Name is not set. Set the argument -$Name or the environment variable $Name."
    }
    return $value
}

function Read-OutpostInt {
    param([Parameter(Mandatory = $true)][string] $Name, [int] $Min = [int]::MinValue, [int] $Max = [int]::MaxValue, [switch] $Required)
    $value = Read-OutpostText -Name $Name -Required:$Required
    $number = 0
    if (-not [int]::TryParse($value, [ref]$number) -or $number -lt $Min -or $number -gt $Max) {
        Stop-OutpostInput -Name $Name -Value $value -Expected "a whole number from $Min to $Max"
    }
    return $number
}

function Read-OutpostBool {
    param([Parameter(Mandatory = $true)][string] $Name)
    $value = (Get-OutpostRawInput -Name $Name).ToLowerInvariant()
    if (@('1', 'true', 'yes', 'y', 'on') -contains $value) { return $true }
    if (@('', '0', 'false', 'no', 'n', 'off') -contains $value) { return $false }
    Stop-OutpostInput -Name $Name -Value $value -Expected 'true or false (also yes/no, 1/0, on/off)'
}

function Read-OutpostChoice {
    param([Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][string[]] $Allowed)
    $value = Get-OutpostRawInput -Name $Name
    foreach ($choice in $Allowed) { if ($choice -ieq $value) { return $choice } }
    Stop-OutpostInput -Name $Name -Value $value -Expected ('one of: ' + ($Allowed -join ', '))
}

function Read-OutpostList {
    param([Parameter(Mandatory = $true)][string] $Name, [switch] $Required)
    $value = Read-OutpostText -Name $Name -Required:$Required
    return @($value -split '[,;\r\n]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

function Read-OutpostSecret {
    # Secrets come from an environment variable only, never an argument, and are never printed.
    param([Parameter(Mandatory = $true)][string] $Name, [switch] $Required)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($value)) { $value = [Environment]::GetEnvironmentVariable((ConvertTo-OutpostSnakeName -Name $Name)) }
    if ($Required -and [string]::IsNullOrEmpty($value)) {
        Stop-OutpostRun -Message "Required secret $Name is not set. Set the environment variable $Name (a secure/hidden field in your RMM)."
    }
    return $value
}

function Start-OutpostRun {
    # Arguments PowerShell could not bind: positional values fill this script's
    # inputs in $OutpostScript.Inputs order (N-sight, Atera); unknown -Name value
    # pairs (N-sight appends -logfile) are ignored with a warning.
    $ignored = @()
    if ($script:OutpostBound.ContainsKey('UnknownArguments')) {
        $tokens = @($script:OutpostBound['UnknownArguments'])
        $null = $script:OutpostBound.Remove('UnknownArguments')
        $freeInputs = @($OutpostScript.Inputs | Where-Object { -not $script:OutpostBound.ContainsKey($_) })
        $slot = 0
        for ($i = 0; $i -lt $tokens.Count; $i++) {
            $token = [string]$tokens[$i]
            if ($token -match '^-(Approve|MaxChanges)$' -and $i + 1 -lt $tokens.Count) {
                # Runtime safety inputs: no param() declaration needed in any script.
                $script:OutpostBound[$Matches[1]] = [string]$tokens[$i + 1]
                $i++
                continue
            }
            if ($token -match '^-[A-Za-z]') {
                $ignored += $token
                if ($i + 1 -lt $tokens.Count -and ([string]$tokens[$i + 1]) -notmatch '^-[A-Za-z]') { $i++ }
            }
            elseif ($slot -lt $freeInputs.Count) {
                if ($token -ne '') { $script:OutpostBound[$freeInputs[$slot]] = $token }
                $slot++
            }
            else { $ignored += "'$token'" }
        }
    }
    $script:OutpostRun.Format = Read-OutpostChoice -Name 'OutputFormat' -Allowed @('Text', 'Answer', 'Json', 'Csv')
    $dryRunText = Get-OutpostRawInput -Name 'DryRun'
    if ($dryRunText -eq '' -and $OutpostScript.Risk -eq 'High') { $dryRunText = 'true' }
    $script:OutpostRun.DryRun = ($OutpostScript.Type -eq 'Action') -and ($WhatIfPreference -or (@('1', 'true', 'yes', 'y', 'on') -contains $dryRunText.ToLowerInvariant()))

    # SAFETY 1: a High-risk Action changes things only when Approve names THIS
    # script, so a site-wide DryRun=false variable cannot unlock every script.
    $needsApproval = ($OutpostScript.Type -eq 'Action') -and ($OutpostScript.Risk -eq 'High') -and (-not $script:OutpostRun.DryRun) -and ((Get-OutpostRawInput -Name 'Approve') -ne $OutpostScript.Slug)
    if ($needsApproval) { $script:OutpostRun.DryRun = $true }

    # SAFETY 2: a cap on how many changes one run may make (High risk: 25 unless MaxChanges says otherwise).
    $script:OutpostRun.Changes = 0
    $limit = 0
    $limitText = Get-OutpostRawInput -Name 'MaxChanges'
    if ($limitText -ne '') {
        if (-not [int]::TryParse($limitText, [ref]$limit) -or $limit -lt 1) { Stop-OutpostInput -Name 'MaxChanges' -Value $limitText -Expected 'a whole number of 1 or more' }
    }
    elseif ($OutpostScript.Risk -eq 'High') { $limit = 25 }
    $script:OutpostRun.MaxChanges = $limit
    $offset = [DateTimeOffset]::Now.ToString('yyyy-MM-dd HH:mm zzz', [Globalization.CultureInfo]::InvariantCulture)
    Write-OutpostLine -Text ("MSP Outpost | {0} {1} | {2} | {3}" -f $OutpostScript.Slug, $OutpostScript.Version, [Environment]::MachineName, $offset)
    if ($ignored.Count -gt 0) { Write-OutpostWarning -Text "Ignored unknown argument(s): $($ignored -join ' '). This script's inputs are listed by Get-Help." }
    if ($needsApproval) { Write-OutpostWarning -Text ("High-risk script: running as a dry run because Approve is not set to '{0}'. To make the changes, set DryRun=false and Approve={0}." -f $OutpostScript.Slug) }
    if ($script:OutpostRun.DryRun) { Write-OutpostLine -Text 'DRY RUN: nothing will be changed.' }
}

function Add-OutpostRow {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary] $Values)
    $row = [ordered]@{}
    foreach ($field in $OutpostScript.Fields) { $row[$field] = $Values[$field] }
    [void]$script:OutpostRun.Rows.Add([pscustomobject]$row)
}

function Set-OutpostFieldValue {
    # What ResultField receives; defaults to the answer.
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Value)
    $script:OutpostRun.FieldValue = $Value
}

function Test-OutpostAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OutpostSignedInUser {
    # DOMAIN\user of the console session (else the owner of an Explorer shell,
    # which covers RDP sessions), or $null when nobody is signed in.
    $user = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
    if (-not [string]::IsNullOrWhiteSpace($user)) { return $user }
    foreach ($shell in @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'explorer.exe'")) {
        try {
            $owner = Invoke-CimMethod -InputObject $shell -MethodName GetOwner
            if ($owner.ReturnValue -eq 0 -and $owner.User) { return ($owner.Domain + '\' + $owner.User) }
        }
        catch { $null = $_ }
    }
    return $null
}

function Invoke-OutpostAsUser {
    # Runs PowerShell code as the signed-in user (from SYSTEM), the way an RMM's
    # "run as logged-on user" does: a one-shot scheduled task with that user's
    # interactive principal. Returns @{ ExitCode; Output } or $null when nobody is
    # signed in. The code runs with the USER'S rights (never more), sees the user's
    # HKCU and profile, and must not contain secrets (it is written to disk).
    param(
        [Parameter(Mandatory = $true)][string] $Code,
        [int] $TimeoutSeconds = 120,
        [string] $User
    )
    if (-not $User) { $User = Get-OutpostSignedInUser }
    if (-not $User) { return $null }
    $windowsDir = [Environment]::GetFolderPath('Windows')
    if (-not $windowsDir) { $windowsDir = 'C:\Windows' }
    # A per-run folder only SYSTEM, Administrators and THIS user can write to, under
    # the secured data folder: no other user can swap the code before it runs.
    $id = [Guid]::NewGuid().ToString('N')
    $folder = Join-Path -Path (Get-OutpostDataFolder) -ChildPath ('RunAsUser\' + $id)
    $null = New-Item -Path $folder -ItemType Directory -Force
    Protect-OutpostFolder -Path $folder -ExtraUser $User
    $scriptFile = Join-Path -Path $folder -ChildPath ($id + '.ps1')
    $outputFile = Join-Path -Path $folder -ChildPath ($id + '.out.txt')
    $wrapper = '$ErrorActionPreference = ''Stop''' + "`r`n" + 'try { & {' + "`r`n" + $Code + "`r`n" + '} *>&1 | Out-String -Width 400 | Set-Content -LiteralPath ''' + $outputFile + ''' -Encoding UTF8; exit 0 }' + "`r`n" + 'catch { (''ERROR: '' + $_.Exception.Message) | Set-Content -LiteralPath ''' + $outputFile + ''' -Encoding UTF8; exit 1 }'
    Set-Content -LiteralPath $scriptFile -Value $wrapper -Encoding UTF8
    $taskName = 'MSPOutpost-RunAsUser-' + $id
    $powershell = Join-Path -Path $windowsDir -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        $action = New-ScheduledTaskAction -Execute $powershell -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptFile + '"')
        $principal = New-ScheduledTaskPrincipal -UserId $User -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::FromSeconds($TimeoutSeconds + 30))
        $null = Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force
        $started = (Get-Date).AddSeconds(-1)
        Start-ScheduledTask -TaskName $taskName
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        # Done = not Running/Queued, has run since we started it, and has a real
        # result (267009 = still running, 267011 = has not run yet).
        do {
            Start-Sleep -Milliseconds 500
            $state = [string](Get-ScheduledTask -TaskName $taskName).State
            $info = Get-ScheduledTaskInfo -TaskName $taskName
            $finished = ($state -ne 'Running') -and ($state -ne 'Queued') -and ($info.LastRunTime -ge $started) -and (@(267009, 267011) -notcontains $info.LastTaskResult)
        } while (-not $finished -and [DateTime]::UtcNow -lt $deadline)
        if (-not $finished) {
            Stop-ScheduledTask -TaskName $taskName
            throw "The code run as $User did not finish within $TimeoutSeconds seconds."
        }
        $output = if (Test-Path -LiteralPath $outputFile) { (Get-Content -LiteralPath $outputFile -Raw) } else { '' }
        if ($null -eq $output) { $output = '' }
        return [pscustomobject]@{ ExitCode = [long]$info.LastTaskResult; Output = $output.TrimEnd() }
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-OutpostDataFolder {
    # %ProgramData%\MSPOutpost without trusting the environment: some agents start
    # scripts with a stripped one, where GetFolderPath and %ProgramData% are empty.
    $base = [Environment]::GetFolderPath('CommonApplicationData')
    if (-not $base) { $base = $env:ProgramData }
    if (-not $base) {
        $windowsDir = if ($env:SystemRoot) { $env:SystemRoot } else { 'C:\Windows' }
        $base = (Split-Path -Path $windowsDir -Qualifier) + '\ProgramData'
    }
    $folder = Join-Path -Path $base -ChildPath 'MSPOutpost'
    if (-not $script:OutpostRun.ContainsKey('DataFolderChecked')) {
        $script:OutpostRun.DataFolderChecked = $true
        Protect-OutpostFolder -Path $folder
    }
    return $folder
}

function Protect-OutpostFolder {
    # Standard users can create folders in ProgramData. If someone pre-created ours,
    # they could tamper with logs, downloads or code run later. Owner must be
    # SYSTEM or Administrators, inheritance off, Full control for SYSTEM and
    # Administrators only, read for Users. Fixed when wrong; a failure is a WARNING.
    param([Parameter(Mandatory = $true)][string] $Path, [string] $ExtraUser)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -ItemType Directory -Force }
        $system = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-18'
        $admins = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-544'
        $users = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList 'S-1-5-32-545'
        $acl = Get-Acl -LiteralPath $Path
        $ownerSid = (New-Object -TypeName Security.Principal.NTAccount -ArgumentList $acl.Owner).Translate([Security.Principal.SecurityIdentifier])
        $wantedRules = 3
        if ($ExtraUser) { $wantedRules = 4 }
        $ok = ($ownerSid -eq $system -or $ownerSid -eq $admins) -and $acl.AreAccessRulesProtected -and (@($acl.Access).Count -eq $wantedRules)
        if ($ok) { return }
        $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        $none = [Security.AccessControl.PropagationFlags]::None
        $new = New-Object -TypeName Security.AccessControl.DirectorySecurity
        $new.SetOwner($admins)
        $new.SetAccessRuleProtection($true, $false)
        $new.AddAccessRule((New-Object -TypeName Security.AccessControl.FileSystemAccessRule -ArgumentList $system, 'FullControl', $inherit, $none, 'Allow'))
        $new.AddAccessRule((New-Object -TypeName Security.AccessControl.FileSystemAccessRule -ArgumentList $admins, 'FullControl', $inherit, $none, 'Allow'))
        $new.AddAccessRule((New-Object -TypeName Security.AccessControl.FileSystemAccessRule -ArgumentList $users, 'ReadAndExecute', $inherit, $none, 'Allow'))
        if ($ExtraUser) {
            $new.AddAccessRule((New-Object -TypeName Security.AccessControl.FileSystemAccessRule -ArgumentList $ExtraUser, 'Modify', $inherit, $none, 'Allow'))
        }
        Set-Acl -LiteralPath $Path -AclObject $new
    }
    catch {
        Write-OutpostWarning -Text "Could not secure the folder $($Path): $($_.Exception.Message)"
    }
}

function Write-OutpostLog {
    param([Parameter(Mandatory = $true)][string] $Text)
    try {
        $folder = Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Logs'
        if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
        $file = Join-Path -Path $folder -ChildPath ($OutpostScript.Slug + '.log')
        if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 1MB) {
            Move-Item -LiteralPath $file -Destination ($file + '.old') -Force
        }
        $line = '{0}  {1} {2}  {3}' -f [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture), $OutpostScript.Slug, $OutpostScript.Version, $Text
        Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    }
    catch {
        Write-OutpostWarning -Text "Could not write the change log: $($_.Exception.Message)"
    }
}

function Assert-OutpostChangeLimit {
    # SAFETY 2, planned: call before acting with the number of changes planned.
    # Over MaxChanges, nothing is changed (a dry run only warns).
    param([Parameter(Mandatory = $true)][int] $Planned)
    $limit = $script:OutpostRun.MaxChanges
    if ($limit -le 0 -or $Planned -le $limit) { return }
    if ($script:OutpostRun.DryRun) {
        Write-OutpostWarning -Text "A real run would stop: $Planned changes planned and MaxChanges is $limit. Set MaxChanges=$Planned or more to allow it."
        return
    }
    Stop-OutpostRun -Message "$Planned changes planned but MaxChanges is $limit, so nothing was changed. Check the list with a dry run, then set MaxChanges=$Planned or more."
}

function Backup-OutpostItem {
    # SAFETY 3: copy a file, folder or registry key (HKLM:\..., HKU:\...) aside before
    # changing it, under %ProgramData%\MSPOutpost\Backups\<slug>\<time>\ (10 runs kept).
    # Returns the backup path; nothing happens in a dry run. A failed backup throws.
    param([Parameter(Mandatory = $true)][string] $Path)
    if ($script:OutpostRun.DryRun) { return $null }
    if (-not $script:OutpostRun.ContainsKey('BackupFolder')) {
        $root = Join-Path -Path (Get-OutpostDataFolder) -ChildPath ('Backups\' + $OutpostScript.Slug)
        $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
        $script:OutpostRun.BackupFolder = Join-Path -Path $root -ChildPath $stamp
        $null = New-Item -Path $script:OutpostRun.BackupFolder -ItemType Directory -Force
        Get-ChildItem -LiteralPath $root -Directory | Sort-Object -Property Name -Descending | Select-Object -Skip 10 |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    $target = Join-Path -Path $script:OutpostRun.BackupFolder -ChildPath ($Path -replace '[\\/:*?"<>|]', '_')
    if ($Path -match '^(HKLM|HKCU|HKU|HKCR|HKCC):?\\') {
        $regPath = $Path -replace '^(HK[A-Z]+):?\\', '$1\'
        $target = $target + '.reg'
        $null = & reg.exe export $regPath $target /y 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Could not back up registry key $Path (reg export exit code $LASTEXITCODE)." }
    }
    else {
        Copy-Item -LiteralPath $Path -Destination $target -Recurse -Force
    }
    Write-OutpostLog -Text "BACKUP  $Path  ->  $target"
    return $target
}

function Invoke-OutpostChange {
    # Every change an Action makes goes through here: dry run, row, log.
    param(
        [Parameter(Mandatory = $true)][string] $Item,
        [Parameter(Mandatory = $true)][string] $Change,
        [Parameter(Mandatory = $true)][scriptblock] $Action
    )
    if ($script:OutpostRun.DryRun) {
        Add-OutpostRow -Values @{ Item = $Item; Change = $Change; Result = 'Would change' }
        return $false
    }
    # SAFETY 2, backstop: never more than MaxChanges real changes in one run.
    if ($script:OutpostRun.MaxChanges -gt 0 -and $script:OutpostRun.Changes -ge $script:OutpostRun.MaxChanges) {
        Stop-OutpostRun -Message ("Stopped after {0} change(s): MaxChanges is {0}. Run it again with a higher MaxChanges to finish." -f $script:OutpostRun.MaxChanges)
    }
    & $Action
    $script:OutpostRun.Changes++
    Add-OutpostRow -Values @{ Item = $Item; Change = $Change; Result = 'Done' }
    Write-OutpostLog -Text "CHANGED  $Change  $Item"
    return $true
}

function Get-OutpostRmm {
    # Which RMM can receive a custom field here: NinjaOne, NinjaOneCli, Syncro, Datto, or $null.
    if (Get-Command -Name 'Ninja-Property-Set' -ErrorAction SilentlyContinue) { return 'NinjaOne' }
    if ($env:NINJARMMCLI -and (Test-Path -LiteralPath $env:NINJARMMCLI)) { return 'NinjaOneCli' }
    if ($env:SyncroModule) { return 'Syncro' }
    if ($env:CS_PROFILE_UID -or (Test-Path -LiteralPath 'HKLM:\SOFTWARE\CentraStage')) { return 'Datto' }
    return $null
}

function Write-OutpostField {
    # Returns $true when the value was written. Never throws: a failed write is a WARNING.
    param([string] $Name, [string] $Value)
    try {
        switch (Get-OutpostRmm) {
            'NinjaOne' { Ninja-Property-Set $Name $Value; return $true }
            'NinjaOneCli' { & $env:NINJARMMCLI set $Name $Value | Out-Null; return ($LASTEXITCODE -eq 0) }
            'Syncro' {
                Import-Module -Name $env:SyncroModule -WarningAction SilentlyContinue
                Set-Asset-Field -Name $Name -Value $Value
                return $true
            }
            'Datto' {
                if ($Name -notmatch '^(?:Custom)?([1-9][0-9]?|[12][0-9][0-9]|300)$') {
                    Write-OutpostWarning -Text "Datto RMM: ResultField must be a UDF number from 1 to 300, not '$Name'."
                    return $false
                }
                $udf = 'Custom' + $Matches[1]
                if ($Value.Length -gt 255) { $Value = $Value.Substring(0, 255) }
                $null = New-ItemProperty -Path 'HKLM:\SOFTWARE\CentraStage' -Name $udf -Value $Value -PropertyType String -Force
                return $true
            }
        }
        Write-OutpostWarning -Text 'ResultField is set but no supported RMM was detected; the answer is in the RESULT line.'
        return $false
    }
    catch {
        Write-OutpostWarning -Text "Could not write ResultField '$Name': $($_.Exception.Message)"
        return $false
    }
}

function Assert-OutpostSecretField {
    # Call in Validate, BEFORE changing anything, in a script that will produce a
    # secret (a generated password): the secret may only go to an RMM custom field,
    # so ResultField must be set and a supported RMM present, and Answer format is refused.
    if ($script:OutpostRun.Format -eq 'Answer') {
        Stop-OutpostRun -Message 'OutputFormat Answer is not allowed here: this script produces a secret. Use Text or Json and a secure ResultField.'
    }
    $name = Get-OutpostRawInput -Name 'ResultField'
    if ($name -eq '') {
        Stop-OutpostRun -Message 'Set ResultField to a secure/secret custom field first, so the new password is stored and not lost. Nothing was changed.'
    }
    $rmm = Get-OutpostRmm
    if (-not $rmm) {
        Stop-OutpostRun -Message "ResultField is set but no supported RMM (NinjaOne, Datto RMM, Syncro) was detected to store the secret in. Nothing was changed."
    }
    if ($rmm -eq 'NinjaOneCli') {
        Stop-OutpostRun -Message 'Only the ninjarmm-cli tool was found, which would put the secret on a command line other processes can read. Run this script from NinjaOne itself (where Ninja-Property-Set exists). Nothing was changed.'
    }
    if ($rmm -eq 'Datto' -and $name -notmatch '^(?:Custom)?([1-9][0-9]?|[12][0-9][0-9]|300)$') {
        Stop-OutpostRun -Message "Datto RMM: ResultField must be a UDF number from 1 to 300, not '$name'. Nothing was changed."
    }
    $script:OutpostRun.SecretField = $true
}

function Write-OutpostSecretField {
    # Writes a secret to ResultField once, right after it was created. The value is
    # never printed, logged or exported, and Complete-OutpostRun will not overwrite
    # the field with the answer. A failed write ends the run as ERROR.
    param([Parameter(Mandatory = $true)][string] $Value)
    if (-not ($script:OutpostRun.ContainsKey('SecretField') -and $script:OutpostRun.SecretField)) {
        throw 'Script bug: call Assert-OutpostSecretField in Validate before Write-OutpostSecretField.'
    }
    $name = Get-OutpostRawInput -Name 'ResultField'
    if (-not (Write-OutpostField -Name $name -Value $Value)) {
        Stop-OutpostRun -Message "The secret was created but could NOT be written to ResultField '$name'. Run again to create a new one."
    }
    $script:OutpostRun.SecretWritten = $true
    Write-OutpostLog -Text "SECRET  written to ResultField $name (value not logged)"
}

function Complete-OutpostRun {
    param(
        [Parameter(Mandatory = $true)][string] $Status,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Answer
    )
    # Re-entered means the first call crashed part-way: still end as ERROR, never silently.
    if ($script:OutpostRun.Done) {
        Write-Host ('RESULT: ERROR | ' + (($Answer -replace '\s+', ' ').Trim()))
        try { $Host.SetShouldExit(2) } catch { $null = $_ }
        exit 2
    }
    $script:OutpostRun.Done = $true
    # Not a ValidateSet: the status is reassigned below (DRYRUN), which a validated parameter rejects.
    if (@('OK', 'CHANGED', 'SKIPPED', 'ALERT', 'ERROR') -notcontains $Status) { $Answer = "Script bug: unknown status '$Status'. $Answer"; $Status = 'ERROR' }
    if ($Status -eq 'ALERT' -and $OutpostScript.Type -ne 'Monitor') { $Status = 'ERROR'; $Answer = "Script bug: only a Monitor may ALERT. $Answer" }
    if ($Status -eq 'CHANGED' -and $OutpostScript.Type -ne 'Action') { $Status = 'ERROR'; $Answer = "Script bug: only an Action may report CHANGED. $Answer" }
    if ($Status -eq 'CHANGED' -and $script:OutpostRun.DryRun) { $Status = 'DRYRUN'; $Answer = "Dry run, nothing changed. Would have: $Answer" }
    $Answer = ($Answer -replace '\s+', ' ').Trim()
    if ($Answer.Length -gt 200) { $Answer = $Answer.Substring(0, 197) + '...' }
    $exitCode = switch ($Status) { 'ALERT' { 1 } 'ERROR' { 2 } default { 0 } }

    $rows = @($script:OutpostRun.Rows)
    if ($script:OutpostRun.Format -eq 'Text' -and $rows.Count -gt 0) {
        Write-Host ''
        $table = ($rows | Format-Table -Property $OutpostScript.Fields -AutoSize | Out-String -Width 200).Trim()
        foreach ($line in ($table -split "`r?`n")) { Write-Host $line.TrimEnd() }
        Write-Host ''
    }

    $exportPath = ''
    try { $exportPath = Get-OutpostRawInput -Name 'ExportPath' } catch { $exportPath = '' }
    if ($exportPath -ne '') {
        try {
            $folder = Split-Path -Path $exportPath -Parent
            if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
            if ($exportPath -like '*.json') {
                ConvertTo-Json -InputObject @($rows) -Depth 5 | Set-Content -LiteralPath $exportPath -Encoding UTF8
            }
            else {
                $rows | Export-Csv -LiteralPath $exportPath -NoTypeInformation -Encoding UTF8
            }
            Write-OutpostLine -Text "Exported $($rows.Count) row(s) to $exportPath"
        }
        catch {
            Write-OutpostWarning -Text "Could not export to '$exportPath': $($_.Exception.Message)"
        }
    }

    $resultField = ''
    try { $resultField = Get-OutpostRawInput -Name 'ResultField' } catch { $resultField = '' }
    # A script that handles a secret writes its field itself (Write-OutpostSecretField); never overwrite it.
    $secretMode = $script:OutpostRun.ContainsKey('SecretField') -and $script:OutpostRun.SecretField
    if ($resultField -ne '' -and -not $secretMode) {
        $fieldValue = if ($null -ne $script:OutpostRun.FieldValue) { $script:OutpostRun.FieldValue } else { $Answer }
        $null = Write-OutpostField -Name $resultField -Value $fieldValue
    }

    if ($Status -eq 'DRYRUN' -or $Status -eq 'CHANGED') { Write-OutpostLog -Text "$Status  $Answer" }

    # Datto RMM monitors read the result between these markers.
    if ($script:OutpostRun.Format -eq 'Text' -and $OutpostScript.Type -eq 'Monitor' -and ($env:CS_PROFILE_UID -or (Test-Path -LiteralPath 'HKLM:\SOFTWARE\CentraStage'))) {
        Write-Host '<-Start Result->'
        Write-Host "STATUS=$Answer"
        Write-Host '<-End Result->'
    }

    switch ($script:OutpostRun.Format) {
        'Answer' {
            if ($null -ne $script:OutpostRun.FieldValue) { Write-Host $script:OutpostRun.FieldValue } else { Write-Host $Answer }
        }
        'Json' {
            $result = [ordered]@{
                schema          = 'mspoutpost.result/1'
                script          = $OutpostScript.Slug
                version         = $OutpostScript.Version
                computer        = [Environment]::MachineName
                startedUtc      = $script:OutpostRun.Started.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
                durationSeconds = [math]::Round(([DateTime]::UtcNow - $script:OutpostRun.Started).TotalSeconds, 1)
                status          = $Status
                exitCode        = $exitCode
                answer          = $Answer
                fields          = @($OutpostScript.Fields)
                rows            = @($rows)
                warnings        = @($script:OutpostRun.Warnings)
                errors          = @($script:OutpostRun.Errors)
            }
            Write-Host (ConvertTo-Json -InputObject $result -Depth 6 -Compress)
        }
        'Csv' {
            if ($rows.Count -gt 0) { foreach ($line in ($rows | ConvertTo-Csv -NoTypeInformation)) { Write-Host $line } }
        }
        default { Write-Host "RESULT: $Status | $Answer" }
    }
    # Some RMM hosts (Tactical) only see the code through SetShouldExit.
    try { $Host.SetShouldExit($exitCode) } catch { $null = $_ }
    exit $exitCode
}

function Stop-OutpostRun {
    # The one way a script fails: message to stderr, RESULT: ERROR, exit 2.
    param([string] $Message, [System.Management.Automation.ErrorRecord] $ErrorRecord)
    if ($ErrorRecord) {
        $where = if ($ErrorRecord.InvocationInfo) { " (line $($ErrorRecord.InvocationInfo.ScriptLineNumber))" } else { '' }
        $detail = $ErrorRecord.Exception.Message + $where
        if ($Message) { $Message = "$Message $detail" } else { $Message = "Unexpected error: $detail" }
    }
    [void]$script:OutpostRun.Errors.Add($Message)
    [Console]::Error.WriteLine("ERROR: $Message")
    Complete-OutpostRun -Status 'ERROR' -Answer "Error: $Message"
}

# Last-resort net: a terminating error nothing else caught (in Constants, or
# thrown inside Main's catch block itself) still ends as RESULT: ERROR, exit 2,
# never as a bare PowerShell error with exit 1 and no RESULT line.
trap {
    if (-not $script:OutpostRun.Done) { Stop-OutpostRun -ErrorRecord $_ }
    Write-Host ('RESULT: ERROR | Error: ' + (($_.Exception.Message -replace '\s+', ' ').Trim()))
    try { $Host.SetShouldExit(2) } catch { $null = $_ }
    exit 2
}
#endregion MSP Outpost runtime

# ---- Constants ------------------------------------------------------------
$NamePrefix = 'MSPOutpost-'
$NameMaxLength = 200
$TaskFolder = '\'
$TaskDescription = 'Created by MSP Outpost new-scheduled-task'
# Groups that are not administrators: any right below for one of these on the program is an escalation path.
$UntrustedSids = @('S-1-5-32-545', 'S-1-5-11', 'S-1-1-0', 'S-1-5-4', 'S-1-5-32-546', 'S-1-5-32-547')
$FileDangerRights = 'WriteData, AppendData, Delete, ChangePermissions, TakeOwnership'
$FolderDangerRights = 'WriteData, AppendData, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
$AncestorDangerRights = 'DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership'
$SystemSid = 'S-1-5-18'
$UsersSid = 'S-1-5-32-545'

# ---- Functions ------------------------------------------------------------
function Get-SidText {
    # Name of a well-known untrusted SID for messages.
    param([string] $Sid)
    switch ($Sid) {
        'S-1-5-32-545' { return 'Users' }
        'S-1-5-11' { return 'Authenticated Users' }
        'S-1-1-0' { return 'Everyone' }
        'S-1-5-4' { return 'Interactive' }
        'S-1-5-32-546' { return 'Guests' }
        'S-1-5-32-547' { return 'Power Users' }
        default { return $Sid }
    }
}

function Test-UntrustedSid {
    param([string] $Sid)
    if ($UntrustedSids -contains $Sid) { return $true }
    return ($Sid -match '^S-1-5-21-.*-513$')
}

function Get-WritableReason {
    # Why a non-administrator could change this path (or what runs from it), else ''.
    param([string] $Path, [string] $Kind)
    $mask = switch ($Kind) {
        'File' { [int][Security.AccessControl.FileSystemRights]$FileDangerRights }
        'Folder' { [int][Security.AccessControl.FileSystemRights]$FolderDangerRights }
        default { [int][Security.AccessControl.FileSystemRights]$AncestorDangerRights }
    }
    $acl = Get-Acl -LiteralPath $Path
    $ownerSid = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($ownerSid -match '^S-1-5-21-' -and $ownerSid -notmatch '-(500|512|518|519)$') {
        return "is owned by an ordinary account ($ownerSid), which can change its permissions"
    }
    foreach ($rule in @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))) {
        if ([string]$rule.AccessControlType -ne 'Allow') { continue }
        # Rules that apply to children only do not give rights on this folder itself.
        if ($Kind -ne 'File' -and ([int]$rule.PropagationFlags -band 2) -ne 0) { continue }
        $sid = $rule.IdentityReference.Value
        if (-not (Test-UntrustedSid -Sid $sid)) { continue }
        if (([int]$rule.FileSystemRights -band $mask) -ne 0) {
            return ('can be changed by {0} ({1})' -f (Get-SidText -Sid $sid), $rule.FileSystemRights)
        }
    }
    return ''
}

function Get-UnsafeReason {
    # Reason a standard user could change what runs as SYSTEM from this file, or ''.
    param([string] $FilePath)
    $reason = Get-WritableReason -Path $FilePath -Kind 'File'
    if ($reason) { return "the file $FilePath $reason" }
    $folder = Split-Path -Path $FilePath -Parent
    $reason = Get-WritableReason -Path $folder -Kind 'Folder'
    if ($reason) { return "its folder $folder $reason" }
    $ancestor = Split-Path -Path $folder -Parent
    while ($ancestor) {
        $reason = Get-WritableReason -Path $ancestor -Kind 'Ancestor'
        if ($reason) { return "the parent folder $ancestor $reason" }
        $ancestor = Split-Path -Path $ancestor -Parent
    }
    return ''
}

function Get-ReferencedFile {
    # Absolute file paths named in the arguments (quoted or not) that exist.
    param([string] $ArgumentText)
    $found = New-Object -TypeName System.Collections.ArrayList
    $expanded = [Environment]::ExpandEnvironmentVariables($ArgumentText)
    $candidates = New-Object -TypeName System.Collections.ArrayList
    foreach ($match in [regex]::Matches($expanded, '"([A-Za-z]:\\[^"]+)"')) { [void]$candidates.Add($match.Groups[1].Value) }
    foreach ($match in [regex]::Matches(($expanded -replace '"[^"]*"', ' '), '[A-Za-z]:\\[^\s"''|<>*?]+')) { [void]$candidates.Add($match.Value) }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { [void]$found.Add((Get-Item -LiteralPath $candidate).FullName) }
    }
    return @($found | Select-Object -Unique)
}

function Get-SidFromName {
    param([string] $Name)
    if ($Name -match '^S-1-\d') { return $Name }
    try { return (New-Object -TypeName Security.Principal.NTAccount -ArgumentList $Name).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch { return $Name }
}

function Get-TaskSignature {
    # Comparable text of the parts of a task this script controls. Works on a task
    # read back with Get-ScheduledTask and on one built with New-ScheduledTask.
    param($Task, [bool] $KeepDate)
    $actions = @($Task.Actions)
    $triggers = @($Task.Triggers)
    $parts = New-Object -TypeName System.Collections.ArrayList
    [void]$parts.Add("actions=$($actions.Count)")
    [void]$parts.Add("triggers=$($triggers.Count)")
    if ($actions.Count -gt 0) {
        $execute = ([string]$actions[0].Execute).Trim().Trim('"')
        $actionArguments = if ($null -eq $actions[0].Arguments) { '' } else { ([string]$actions[0].Arguments).Trim() }
        [void]$parts.Add("execute=$execute")
        [void]$parts.Add("arguments=$actionArguments")
    }
    if ($triggers.Count -gt 0) {
        $triggerClass = [string]$triggers[0].CimClass.CimClassName
        $start = ''
        if ($triggerClass -eq 'MSFT_TaskDailyTrigger' -or $triggerClass -eq 'MSFT_TaskTimeTrigger') {
            $boundary = [string]$triggers[0].StartBoundary
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse($boundary, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
                $start = if ($KeepDate) { $parsed.ToString('yyyy-MM-ddTHH:mm', [Globalization.CultureInfo]::InvariantCulture) } else { $parsed.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
            }
            else { $start = $boundary }
        }
        [void]$parts.Add("trigger=$triggerClass $start")
        [void]$parts.Add("triggerEnabled=$($triggers[0].Enabled)")
    }
    $principal = $Task.Principal
    $principalName = if ($principal.GroupId) { [string]$principal.GroupId } else { [string]$principal.UserId }
    [void]$parts.Add('principal=' + (Get-SidFromName -Name $principalName))
    [void]$parts.Add('runLevel=' + [string]$principal.RunLevel)
    [void]$parts.Add('hidden=' + [string][bool]$Task.Settings.Hidden)
    [void]$parts.Add('enabled=' + [string][bool]$Task.Settings.Enabled)
    return ($parts -join '; ')
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    $Config = [pscustomobject]@{
        TaskName     = Read-OutpostText -Name 'TaskName' -Required
        Command      = Read-OutpostText -Name 'Command' -Required
        Arguments    = Read-OutpostText -Name 'Arguments'
        Trigger      = Read-OutpostChoice -Name 'Trigger' -Allowed @('Startup', 'Logon', 'Daily', 'Once')
        At           = Read-OutpostText -Name 'At'
        RunAs        = Read-OutpostChoice -Name 'RunAs' -Allowed @('System', 'Users')
        Hidden       = Read-OutpostBool -Name 'Hidden'
        AllowAnyName = Read-OutpostBool -Name 'AllowAnyName'
    }
    if ($Config.TaskName -match '[\\/:*?"<>|]' -or $Config.TaskName.Length -gt $NameMaxLength) {
        Stop-OutpostInput -Name 'TaskName' -Value $Config.TaskName -Expected "a name up to $NameMaxLength characters without \ / : * ? `" < > |"
    }
    if (-not $Config.AllowAnyName -and (-not $Config.TaskName.StartsWith($NamePrefix, [StringComparison]::OrdinalIgnoreCase) -or $Config.TaskName.Length -le $NamePrefix.Length)) {
        Stop-OutpostInput -Name 'TaskName' -Value $Config.TaskName -Expected "a name starting with $NamePrefix (or set AllowAnyName=true)"
    }
    if ($Config.RunAs -eq 'Users' -and $Config.Trigger -eq 'Startup') {
        Stop-OutpostRun -Message 'RunAs Users cannot use the Startup trigger: no user is signed in at startup. Use Trigger Logon, Daily or Once, or RunAs System.'
    }
    $startTime = [datetime]::MinValue
    $keepDate = $false
    if ($Config.Trigger -eq 'Daily' -or $Config.Trigger -eq 'Once') {
        if ($Config.At -eq '') { Stop-OutpostRun -Message "Trigger is $($Config.Trigger) but At is not set. Set At to a time like 03:30 (24-hour, local)." }
        $parsedTime = [datetime]::MinValue
        $formats = @('HH:mm', 'yyyy-MM-ddTHH:mm')
        if (-not [datetime]::TryParseExact($Config.At, [string[]]$formats, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsedTime)) {
            Stop-OutpostInput -Name 'At' -Value $Config.At -Expected 'a time like 03:30 (HH:mm, 24-hour, local) or, for Once, 2026-12-01T03:30'
        }
        if ($Config.Trigger -eq 'Daily' -and $Config.At.Length -gt 5) {
            Stop-OutpostInput -Name 'At' -Value $Config.At -Expected 'a time of day like 03:30 for Trigger Daily'
        }
        if ($Config.At.Length -gt 5) {
            if ($parsedTime -le (Get-Date)) { Stop-OutpostInput -Name 'At' -Value $Config.At -Expected 'a time in the future' }
            $startTime = $parsedTime
            $keepDate = $true
        }
        else {
            $startTime = [datetime]::Today.Add($parsedTime.TimeOfDay)
            if ($Config.Trigger -eq 'Once' -and $startTime -le (Get-Date)) { $startTime = $startTime.AddDays(1) }
        }
    }
    elseif ($Config.At -ne '') {
        Write-OutpostWarning -Text "At is ignored for Trigger $($Config.Trigger)."
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    if (-not (Get-Command -Name 'Register-ScheduledTask' -ErrorAction SilentlyContinue)) {
        Stop-OutpostRun -Message 'The ScheduledTasks module (Register-ScheduledTask) is not available on this PC. Run it on Windows 10, 11 or Server 2016 or later.'
    }

    # Resolve and guard the program
    $commandText = [Environment]::ExpandEnvironmentVariables($Config.Command).Trim('"')
    $resolvedCommand = ''
    if ([IO.Path]::IsPathRooted($commandText)) {
        if (Test-Path -LiteralPath $commandText -PathType Leaf) { $resolvedCommand = (Get-Item -LiteralPath $commandText).FullName }
    }
    else {
        $found = Get-Command -Name $commandText -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $resolvedCommand = [string]$found.Source }
    }
    if ($resolvedCommand -eq '') {
        Stop-OutpostRun -Message "The program '$($Config.Command)' was not found. Give a full path to a file that exists, or a program name on PATH."
    }
    if ([IO.Path]::GetExtension($resolvedCommand) -ieq '.ps1') {
        Stop-OutpostRun -Message 'Command is a .ps1 file, which Task Scheduler would open in an editor instead of running. Use Command powershell.exe with Arguments "-NoProfile -ExecutionPolicy Bypass -File <script>".'
    }
    if ($Config.RunAs -eq 'System') {
        if ($resolvedCommand.StartsWith('\\')) {
            Stop-OutpostRun -Message "The program $resolvedCommand is on a network path; a task that runs as System would run it with the computer's account. Copy it to a local folder under C:\Program Files first."
        }
        $guarded = @($resolvedCommand) + @(Get-ReferencedFile -ArgumentText $Config.Arguments)
        foreach ($guardedFile in ($guarded | Select-Object -Unique)) {
            $unsafe = Get-UnsafeReason -FilePath $guardedFile
            if ($unsafe -ne '') {
                Stop-OutpostRun -Message "Refusing to create a task that runs as System: $unsafe, so a standard user could make it run their own code with full rights. Move it under C:\Program Files or fix the permissions, then run again."
            }
        }
    }

    # Build the wanted task
    $principalName = if ($Config.RunAs -eq 'System') { (New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList $SystemSid).Translate([Security.Principal.NTAccount]).Value } else { (New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList $UsersSid).Translate([Security.Principal.NTAccount]).Value }
    $actionParameters = @{ Execute = $resolvedCommand }
    if ($Config.Arguments -ne '') { $actionParameters.Argument = $Config.Arguments }
    $taskAction = New-ScheduledTaskAction @actionParameters
    $taskTrigger = switch ($Config.Trigger) {
        'Startup' { New-ScheduledTaskTrigger -AtStartup }
        'Logon' { New-ScheduledTaskTrigger -AtLogOn }
        'Daily' { New-ScheduledTaskTrigger -Daily -At $startTime }
        default { New-ScheduledTaskTrigger -Once -At $startTime }
    }
    $taskPrincipal = if ($Config.RunAs -eq 'System') {
        New-ScheduledTaskPrincipal -UserId $principalName -LogonType ServiceAccount -RunLevel Highest
    }
    else {
        New-ScheduledTaskPrincipal -GroupId $principalName -RunLevel Limited
    }
    $settingParameters = @{ AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true; StartWhenAvailable = $true; MultipleInstances = 'IgnoreNew' }
    if ($Config.Hidden) { $settingParameters.Hidden = $true }
    $taskSettings = New-ScheduledTaskSettingsSet @settingParameters
    $wantedTask = New-ScheduledTask -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Description $TaskDescription
    $wantedSignature = Get-TaskSignature -Task $wantedTask -KeepDate $keepDate

    $triggerText = switch ($Config.Trigger) {
        'Startup' { 'at startup' }
        'Logon' { 'at logon' }
        'Daily' { 'daily at ' + $startTime.ToString('HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
        default { 'once at ' + $startTime.ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) }
    }
    $runAsText = if ($Config.RunAs -eq 'System') { 'SYSTEM' } else { 'Users' }
    $summary = "$triggerText as $runAsText, $resolvedCommand"

    # Detect
    $existingTask = @(Get-ScheduledTask -TaskName $Config.TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue)
    $existingSignature = ''
    if ($existingTask.Count -gt 0) {
        $existingSignature = Get-TaskSignature -Task $existingTask[0] -KeepDate $keepDate
        if ($existingSignature -ieq $wantedSignature) {
            Complete-OutpostRun -Status 'OK' -Answer "Already set: task $($Config.TaskName) exists as specified ($summary)"
        }
    }

    # Act
    $verb = if ($existingTask.Count -gt 0) { 'Update' } else { 'Create' }
    $null = Invoke-OutpostChange -Item $Config.TaskName -Change "$verb task: $summary" -Action {
        if ($existingTask.Count -gt 0) {
            $xmlFile = Join-Path -Path (Get-OutpostDataFolder) -ChildPath ($Config.TaskName + '.xml')
            $null = New-Item -Path (Split-Path -Path $xmlFile -Parent) -ItemType Directory -Force
            try {
                Export-ScheduledTask -TaskName $Config.TaskName -TaskPath $TaskFolder | Set-Content -LiteralPath $xmlFile -Encoding Unicode
                $null = Backup-OutpostItem -Path $xmlFile
            }
            finally { Remove-Item -LiteralPath $xmlFile -Force -ErrorAction SilentlyContinue }
        }
        $null = Register-ScheduledTask -TaskName $Config.TaskName -TaskPath $TaskFolder -InputObject $wantedTask -Force
    }

    # Verify
    if (-not $script:OutpostRun.DryRun) {
        $afterTask = @(Get-ScheduledTask -TaskName $Config.TaskName -TaskPath $TaskFolder -ErrorAction SilentlyContinue)
        if ($afterTask.Count -eq 0) { throw "Task $($Config.TaskName) is not there after registering it." }
        $afterSignature = Get-TaskSignature -Task $afterTask[0] -KeepDate $keepDate
        if ($afterSignature -ine $wantedSignature) { throw "Task $($Config.TaskName) did not read back as specified. Wanted: $wantedSignature. Found: $afterSignature." }
    }

    # Finish
    $doneVerb = if ($existingTask.Count -gt 0) { 'Updated' } else { 'Created' }
    Complete-OutpostRun -Status 'CHANGED' -Answer "$doneVerb task $($Config.TaskName): $summary"
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
