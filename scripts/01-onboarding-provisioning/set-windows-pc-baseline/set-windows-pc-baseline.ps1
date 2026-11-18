#Requires -Version 5.1
<#
.SYNOPSIS
    Applies the standard safe baseline to a new Windows 10/11 PC: time zone, time sync, sleep on AC power, Fast Startup off, System Restore on and long file paths.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It checks six settings one by one and fixes
    only the ones that differ, so it is safe to run on a new PC, again later,
    or on a PC that is half set up. Nothing is rebooted, no user is signed out
    and no software is removed or installed.

    The settings (each can be left alone with SkipSettings, using the name in
    brackets):

      * Time zone (time-zone): set to TimeZone, a Windows time zone ID such as
        "Pacific Standard Time" ("tzutil /l" lists them). Left alone when
        TimeZone is empty, which is the default.
      * Time sync (time-sync): the Windows Time service starts automatically
        and is running, the sync type is NTP and the time server is NtpServer
        (default time.windows.com; empty keeps the PC's current server).
        Skipped on a domain-joined PC, where the domain controller is the time
        source and must not be overridden.
      * Sleep on AC power (sleep-on-ac): the active power plan puts the PC to
        sleep after SleepOnAcMinutes minutes on mains power (default 0 =
        never). The battery setting and the screen timeout are not touched.
      * Fast Startup off (fast-startup): HiberbootEnabled = 0. Fast Startup
        makes "Shut down" a half-hibernate, which keeps pending updates and
        driver faults alive across what users think is a restart. Takes effect
        at the next shutdown.
      * System Restore on (system-restore): System Protection is switched on
        for the system drive. Skipped when a policy disables System Restore.
      * Long file paths (long-paths): LongPathsEnabled = 1, so paths longer than
        260 characters work in apps that support it.

    NOT in the baseline, on purpose: region, language and keyboard (those are
    per user and an RMM runs as SYSTEM, so the setting would land on the wrong
    account), removing consumer apps (remove-windows-bloatware), the firewall
    (enable-windows-firewall), disk encryption (enable-bitlocker) and the
    computer name (set-computer-name).

    Before it changes a registry key it exports that key to
    %ProgramData%\MSPOutpost\Backups\set-windows-pc-baseline\<time>\ so the old
    values can be put back with "reg import". A setting that cannot be read on
    this PC (for example the sleep setting on some virtual machines) is skipped
    with a warning, not guessed.

    Run it again afterwards: it says "Already set". Use DryRun=true to list
    what it would change.

.PARAMETER TimeZone
    Windows time zone ID, for example "Pacific Standard Time" or
    "Eastern Standard Time". Default empty = leave the time zone alone.
    Environment variable: TimeZone

.PARAMETER NtpServer
    Time server host name, for example time.windows.com. Default
    time.windows.com. Empty keeps the PC's current server and only makes sure
    the service runs. Environment variable: NtpServer

.PARAMETER SleepOnAcMinutes
    Minutes of inactivity on AC power before the PC sleeps. Whole number, 0 to
    1440; 0 means never. Default 0. Environment variable: SleepOnAcMinutes

.PARAMETER SkipSettings
    Settings to leave alone, separated by commas: time-zone, time-sync,
    sleep-on-ac, fast-startup, system-restore, long-paths. Default none.
    Environment variable: SkipSettings

.PARAMETER DryRun
    true lists the changes without making them. Default false.
    Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\set-windows-pc-baseline.ps1 -TimeZone "Pacific Standard Time"

    Applies the baseline and sets the time zone to Pacific.

.EXAMPLE
    .\set-windows-pc-baseline.ps1 -DryRun true -SkipSettings "system-restore, sleep-on-ac"

    Lists what would change, leaving System Restore and sleep alone.

.NOTES
    Name:        New Windows PC needs the standard settings - apply the MSP baseline
    Slug:        set-windows-pc-baseline
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Action
    Category:    01 Onboarding & provisioning
    Platforms:   Windows 10, Windows 11
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Time zone, Windows Time service and time server, sleep on AC power, Fast Startup, System Restore on the system drive, long file paths (registry values, service start type, power plan)
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 30 seconds
    Answer:      "Set 3 baseline setting(s): Fast Startup off, Long file paths, Time sync; 3 already set"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/set-windows-pc-baseline
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $TimeZone = '',
    [string] $NtpServer = 'time.windows.com',
    [string] $SleepOnAcMinutes = '0',
    [string] $SkipSettings = '',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'set-windows-pc-baseline'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('TimeZone', 'NtpServer', 'SleepOnAcMinutes', 'SkipSettings')
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
$KnownSettings = @('time-zone', 'time-sync', 'sleep-on-ac', 'fast-startup', 'system-restore', 'long-paths')
$W32TimeParametersKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
$FastStartupKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
$LongPathsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
$SystemRestoreKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
$SystemRestorePolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore'
$SleepSubgroupGuid = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$StandbyIdleGuid = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$NtpPeerFlags = '0x9'
$HostNamePattern = '^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$'
$GuidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

# ---- Functions ------------------------------------------------------------
function Get-RegistryNumber {
    # A registry value as a number, or $null when the key or the value is missing.
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Name)
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $key) { return $null }
    $value = $key.GetValue($Name, $null)
    if ($null -eq $value) { return $null }
    try { return [int64]$value } catch { return $null }
}

function Get-RegistryText {
    # A registry value as text, or '' when the key or the value is missing.
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Name)
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($null -eq $key) { return '' }
    $value = $key.GetValue($Name, $null)
    if ($null -eq $value) { return '' }
    return [string]$value
}

function Invoke-Native {
    # Runs a program and returns its exit code and output. Stderr text must not become an error here.
    param([Parameter(Mandatory = $true)][string] $FilePath, [string[]] $Arguments = @())
    $ErrorActionPreference = 'Continue'
    $text = (& $FilePath @Arguments 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $text }
}

function Get-ActiveSchemeGuid {
    $result = Invoke-Native -FilePath 'powercfg.exe' -Arguments @('/getactivescheme')
    if ($result.ExitCode -ne 0) { return $null }
    $match = [regex]::Match($result.Output, $GuidPattern)
    if ($match.Success) { return $match.Value }
    return $null
}

function Get-AcSleepSeconds {
    # The AC sleep timeout in seconds, or $null when powercfg cannot say. The last two numbers
    # "powercfg /query" prints are the AC and DC values, which does not depend on the language.
    param([Parameter(Mandatory = $true)][string] $SchemeGuid)
    $result = Invoke-Native -FilePath 'powercfg.exe' -Arguments @('/query', $SchemeGuid, $SleepSubgroupGuid, $StandbyIdleGuid)
    if ($result.ExitCode -ne 0) { return $null }
    $numbers = @([regex]::Matches($result.Output, '0x[0-9a-fA-F]{8}'))
    if ($numbers.Count -lt 2) { return $null }
    return [Convert]::ToInt64($numbers[$numbers.Count - 2].Value.Substring(2), 16)
}

function Get-SystemDriveRoot {
    # C:\ without trusting the environment.
    $root = [IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))
    if (-not $root) { $root = 'C:\' }
    return $root
}

function Get-NtpHost {
    # The first time server in the registry value ("time.windows.com,0x9 other,0x9").
    param([string] $Text)
    $first = (($Text.Trim() -split '\s+') | Select-Object -First 1)
    if (-not $first) { return '' }
    return (($first -split ',')[0]).Trim()
}

function New-PlanItem {
    # One baseline setting: Status is Pending (needs a change), Compliant (already right) or Skipped.
    param(
        [Parameter(Mandatory = $true)][string] $Id,
        [Parameter(Mandatory = $true)][string] $Item,
        [Parameter(Mandatory = $true)][string] $Status,
        [string] $Change = '',
        [string] $Note = '',
        [string] $BackupKey = ''
    )
    return [pscustomobject]@{ Id = $Id; Item = $Item; Status = $Status; Change = $Change; Note = $Note; BackupKey = $BackupKey }
}

function Get-SettingItem {
    # Reads one setting and says whether it needs a change.
    param([Parameter(Mandatory = $true)][string] $Id)
    switch ($Id) {
        'time-zone' {
            $item = 'Time zone'
            if ($Config.TimeZone -eq '') { return New-PlanItem -Id $Id -Item $item -Status 'Skipped' -Note 'TimeZone is not set' }
            $current = (Get-TimeZone).Id
            if ($current -ieq $Config.TimeZone) { return New-PlanItem -Id $Id -Item $item -Status 'Compliant' -Note $current }
            return New-PlanItem -Id $Id -Item $item -Status 'Pending' -Change "Set the time zone from $current to $($Config.TimeZone)"
        }
        'time-sync' {
            $item = 'Time sync'
            if ([bool](Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
                return New-PlanItem -Id $Id -Item $item -Status 'Skipped' -Note 'domain-joined PC: the domain controller is the time source'
            }
            $service = Get-CimInstance -ClassName Win32_Service -Filter "Name = 'W32Time'" -ErrorAction SilentlyContinue
            if ($null -eq $service) { return New-PlanItem -Id $Id -Item $item -Status 'Skipped' -Note 'the Windows Time service is not installed' }
            $problems = @()
            if ([string]$service.StartMode -ne 'Auto') { $problems += "service start type is $($service.StartMode)" }
            if ([string]$service.State -ne 'Running') { $problems += "service is $($service.State)" }
            if ((Get-RegistryText -Path $W32TimeParametersKey -Name 'Type') -ine 'NTP') { $problems += 'sync type is not NTP' }
            if ($Config.NtpServer -ne '') {
                $currentHost = Get-NtpHost -Text (Get-RegistryText -Path $W32TimeParametersKey -Name 'NtpServer')
                if ($currentHost -ine $Config.NtpServer) { $problems += "time server is '$currentHost'" }
            }
            if ($problems.Count -eq 0) { return New-PlanItem -Id $Id -Item $item -Status 'Compliant' -Note 'automatic, running, NTP' }
            return New-PlanItem -Id $Id -Item $item -Status 'Pending' -Change ('Fix the Windows Time service: ' + ($problems -join '; ')) -BackupKey $W32TimeParametersKey
        }
        'sleep-on-ac' {
            $item = 'Sleep on AC power'
            $scheme = Get-ActiveSchemeGuid
            $seconds = $null
            if ($scheme) { $seconds = Get-AcSleepSeconds -SchemeGuid $scheme }
            if ($null -eq $seconds) { return New-PlanItem -Id $Id -Item $item -Status 'Skipped' -Note 'this PC does not report the sleep setting' }
            $wanted = [int64]$Config.SleepOnAcMinutes * 60
            if ($seconds -eq $wanted) { return New-PlanItem -Id $Id -Item $item -Status 'Compliant' -Note "$($Config.SleepOnAcMinutes) minute(s)" }
            return New-PlanItem -Id $Id -Item $item -Status 'Pending' -Change "Sleep after $($Config.SleepOnAcMinutes) minute(s) on AC power (now $([math]::Round($seconds / 60, 0)))"
        }
        'fast-startup' {
            $item = 'Fast Startup'
            if ((Get-RegistryNumber -Path $FastStartupKey -Name 'HiberbootEnabled') -eq 0) { return New-PlanItem -Id $Id -Item $item -Status 'Compliant' -Note 'off' }
            return New-PlanItem -Id $Id -Item $item -Status 'Pending' -Change 'Turn Fast Startup off (HiberbootEnabled = 0)' -BackupKey $FastStartupKey
        }
        'system-restore' {
            $item = 'System Restore'
            if ((Get-RegistryNumber -Path $SystemRestorePolicyKey -Name 'DisableSR') -eq 1) {
                return New-PlanItem -Id $Id -Item $item -Status 'Skipped' -Note 'a policy disables System Restore'
            }
            if ((Get-RegistryNumber -Path $SystemRestoreKey -Name 'RPSessionInterval') -eq 1) { return New-PlanItem -Id $Id -Item $item -Status 'Compliant' -Note 'on' }
            return New-PlanItem -Id $Id -Item $item -Status 'Pending' -Change "Turn System Protection on for $(Get-SystemDriveRoot)"
        }
        'long-paths' {
            $item = 'Long file paths'
            if ((Get-RegistryNumber -Path $LongPathsKey -Name 'LongPathsEnabled') -eq 1) { return New-PlanItem -Id $Id -Item $item -Status 'Compliant' -Note 'on' }
            return New-PlanItem -Id $Id -Item $item -Status 'Pending' -Change 'Turn long file paths on (LongPathsEnabled = 1)' -BackupKey $LongPathsKey
        }
    }
    throw "Script bug: unknown baseline setting '$Id'."
}

function Get-SettingPlan {
    $plan = @()
    foreach ($settingId in $KnownSettings) {
        if ($Config.SkipSettings -contains $settingId) {
            $plan += New-PlanItem -Id $settingId -Item $settingId -Status 'Skipped' -Note 'listed in SkipSettings'
        }
        else {
            $plan += Get-SettingItem -Id $settingId
        }
    }
    return $plan
}

function Set-RegistryNumber {
    param([Parameter(Mandatory = $true)][string] $Path, [Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][int] $Value)
    if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force }
    $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType DWord -Force
}

function Invoke-SettingChange {
    # Makes one setting right. Throws when it cannot.
    param([Parameter(Mandatory = $true)][string] $Id)
    switch ($Id) {
        'time-zone' {
            Set-TimeZone -Id $Config.TimeZone
        }
        'time-sync' {
            if ($Config.NtpServer -ne '') {
                $null = New-ItemProperty -LiteralPath $W32TimeParametersKey -Name 'NtpServer' -Value ($Config.NtpServer + ',' + $NtpPeerFlags) -PropertyType String -Force
            }
            $null = New-ItemProperty -LiteralPath $W32TimeParametersKey -Name 'Type' -Value 'NTP' -PropertyType String -Force
            Set-Service -Name 'W32Time' -StartupType Automatic
            if ((Get-Service -Name 'W32Time').Status -eq 'Running') {
                $update = Invoke-Native -FilePath 'w32tm.exe' -Arguments @('/config', '/update')
                if ($update.ExitCode -ne 0) { throw "w32tm /config /update failed (exit code $($update.ExitCode)): $($update.Output)" }
            }
            else {
                Start-Service -Name 'W32Time'
            }
        }
        'sleep-on-ac' {
            $scheme = Get-ActiveSchemeGuid
            if (-not $scheme) { throw 'Could not read the active power plan.' }
            $seconds = [string]([int64]$Config.SleepOnAcMinutes * 60)
            $set = Invoke-Native -FilePath 'powercfg.exe' -Arguments @('/setacvalueindex', $scheme, $SleepSubgroupGuid, $StandbyIdleGuid, $seconds)
            if ($set.ExitCode -ne 0) { throw "powercfg /setacvalueindex failed (exit code $($set.ExitCode)): $($set.Output)" }
            $apply = Invoke-Native -FilePath 'powercfg.exe' -Arguments @('/setactive', $scheme)
            if ($apply.ExitCode -ne 0) { throw "powercfg /setactive failed (exit code $($apply.ExitCode)): $($apply.Output)" }
        }
        'fast-startup' {
            Set-RegistryNumber -Path $FastStartupKey -Name 'HiberbootEnabled' -Value 0
        }
        'system-restore' {
            Enable-ComputerRestore -Drive (Get-SystemDriveRoot)
        }
        'long-paths' {
            Set-RegistryNumber -Path $LongPathsKey -Name 'LongPathsEnabled' -Value 1
        }
        default { throw "Script bug: unknown baseline setting '$Id'." }
    }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        TimeZone         = Read-OutpostText -Name 'TimeZone'
        NtpServer        = Read-OutpostText -Name 'NtpServer'
        SleepOnAcMinutes = Read-OutpostInt -Name 'SleepOnAcMinutes' -Min 0 -Max 1440
        SkipSettings     = @(Read-OutpostList -Name 'SkipSettings' | ForEach-Object { $_.ToLowerInvariant() })
    }
    foreach ($name in $Config.SkipSettings) {
        if ($KnownSettings -notcontains $name) {
            Stop-OutpostInput -Name 'SkipSettings' -Value $name -Expected ('names from: ' + ($KnownSettings -join ', '))
        }
    }
    if ($Config.NtpServer -ne '' -and $Config.NtpServer -notmatch $HostNamePattern) {
        Stop-OutpostInput -Name 'NtpServer' -Value $Config.NtpServer -Expected 'a time server host name such as time.windows.com'
    }
    if ($Config.TimeZone -ne '') {
        try { $null = [TimeZoneInfo]::FindSystemTimeZoneById($Config.TimeZone) }
        catch { Stop-OutpostInput -Name 'TimeZone' -Value $Config.TimeZone -Expected 'a Windows time zone ID such as "Pacific Standard Time" (tzutil /l lists them)' }
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ([int]$osInfo.ProductType -ne 1) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: the baseline is for Windows 10/11 PCs, not servers.'
    }

    # Detect
    Write-OutpostLine -Text 'Checking the baseline settings.'
    $plan = @(Get-SettingPlan)
    $pending = @($plan | Where-Object { $_.Status -eq 'Pending' })
    $compliant = @($plan | Where-Object { $_.Status -eq 'Compliant' })
    $skipped = @($plan | Where-Object { $_.Status -eq 'Skipped' })
    foreach ($entry in $compliant) { Add-OutpostRow -Values @{ Item = $entry.Item; Change = 'None needed'; Result = "Already set ($($entry.Note))" } }
    foreach ($entry in $skipped) {
        Add-OutpostRow -Values @{ Item = $entry.Item; Change = 'None'; Result = "Skipped: $($entry.Note)" }
        if ($entry.Note -notlike 'listed in SkipSettings' -and $entry.Note -notlike 'TimeZone is not set') { Write-OutpostWarning -Text "Skipped $($entry.Item): $($entry.Note)." }
    }
    if ($pending.Count -eq 0) {
        if ($compliant.Count -eq 0) {
            Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: every baseline setting is skipped or not available on this PC.'
        }
        Complete-OutpostRun -Status 'OK' -Answer "Already set: $($compliant.Count) baseline setting(s); $($skipped.Count) skipped."
    }

    # Act
    Assert-OutpostChangeLimit -Planned $pending.Count
    $backedUp = @{}
    foreach ($entry in $pending) {
        if ($entry.BackupKey -ne '' -and -not $backedUp.ContainsKey($entry.BackupKey) -and (Test-Path -LiteralPath $entry.BackupKey)) {
            $null = Backup-OutpostItem -Path $entry.BackupKey
            $backedUp[$entry.BackupKey] = $true
        }
    }
    foreach ($entry in $pending) {
        $settingToChange = $entry.Id
        $null = Invoke-OutpostChange -Item $entry.Item -Change $entry.Change -Action { Invoke-SettingChange -Id $settingToChange }
    }

    # Verify (skipped in a dry run: nothing was changed)
    if (-not $script:OutpostRun.DryRun) {
        $after = @(Get-SettingPlan | Where-Object { $_.Status -eq 'Pending' })
        if ($after.Count -gt 0) {
            Stop-OutpostRun -Message ("Still not set after the change: " + (@($after | ForEach-Object { $_.Item }) -join ', ') + '. Run it again; if it repeats, leave that setting out with SkipSettings and set it by hand.')
        }
    }

    # Finish
    $answer = "Set $($pending.Count) baseline setting(s): " + (@($pending | ForEach-Object { $_.Item } | Sort-Object) -join ', ') + "; $($compliant.Count) already set"
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
