#Requires -Version 5.1
<#
.SYNOPSIS
    Alerts when last night's backup failed or is older than you allow, for the backup products that leave evidence on this PC.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. It looks for the backup products below, reads
    the evidence each one leaves on this machine, and writes one row per
    product found: when it last succeeded and how its newest run ended. It
    alerts (exit 1) when a product's newest run failed, when its last success
    is older than MaxAgeHours, or when the service of a product it cannot read
    is set to start automatically but is not running. It is SKIPPED when no
    supported product is found.

    A run that finished with a warning counts as a completed backup and is
    shown as Warning; it does not alert. Results are read per product, not per
    job: if one product runs several jobs, a failed job followed by a
    successful job of the same product reads as the newest result.

    Only event IDs, event levels, provider names and service names are used,
    never message text, so it works on any Windows language. The evidence used
    and how far to trust it, per product:

    Veeam Agent for Windows - Veeam event logs other than "Veeam Backup" (the
      agent's own log, for example "Veeam Agent"): job-finished event 190, its
      level gives the result (information = success, warning, error = failed).
      Detected by that log having job events or by the service
      VeeamEndpointBackupSvc. Confidence: medium (levels follow what Veeam
      documents for B&R job sessions; not confirmed on every agent version).

    Veeam Backup & Replication server - the "Veeam Backup" log, event 190 with
      the same level rule. Detected by that log having job events or by the
      service VeeamBackupSvc. Backup copy jobs and the configuration backup are
      not read. Confidence: medium.

    Windows Server Backup (wbadmin) - the Microsoft-Windows-Backup log: events
      4 and 14 are success; 5, 8, 9, 20, 21, 22, 49, 517, 521, 561 and 564 are
      failure. Detected only when the log holds one of those events, so a
      schedule that has never run is not seen. Confidence: high for 4, 5 and
      49; medium for the rest.

    Macrium Reflect - Application log events whose provider name starts with
      "Macrium": the level gives the result (information = success, warning,
      error = failed). Reflect also logs other information events, so a start
      event can read as a success. Confidence: low. Without such events the
      product is read like the service-only products below.

    Acronis Cyber Protect, Datto Windows Agent / Datto Cloud Continuity,
    Synology Active Backup for Business agent - only the service is read
    (running, and whether it starts automatically). The last backup result is
    not readable locally: the row says so and the script does not alert on it.
    For Acronis the row also notes error events from an "Acronis" provider in
    the Application log within MaxAgeHours, without alerting on them.
    Confidence: service only.

    When every product found is service-only the answer says that results
    could not be read, with status OK: check those products in their consoles.

.PARAMETER MaxAgeHours
    Alert when a product's newest successful backup is older than this many
    hours. Whole number, 1 to 8760. Default 26 (a nightly backup plus slack).
    Environment variable: MaxAgeHours

.PARAMETER DryRun
    Reserved; ignored by Monitors.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\test-backup-status.ps1

    Checks every supported backup product found; alerts when one failed or is more than 26 hours old.

.EXAMPLE
    .\test-backup-status.ps1 -MaxAgeHours 50 -OutputFormat Json

    Allows a backup that runs every other night and prints one JSON object.

.NOTES
    Name:        Did last night's backup succeed?
    Slug:        test-backup-status
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Monitor
    Category:    08 Backup & DR
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1; administrator rights (event logs)
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 20 seconds
    Answer:      "Veeam Agent for Windows: last success 5 h ago; Windows Server Backup: last success 19 h ago"
    Fields:      Product, LastSuccess, LastResult, Evidence
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/test-backup-status
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text. Defaults are the
    # place to edit when your RMM cannot pass arguments or variables.
    [string] $MaxAgeHours = '26',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'test-backup-status'
    Version = '1.0.0'
    Type    = 'Monitor'
    Risk    = 'Low'
    Inputs  = @('MaxAgeHours')
    Fields  = @('Product', 'LastSuccess', 'LastResult', 'Evidence')
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
$MaxEventsToRead = 200
$LevelWarning = 3
$VeeamJobFinishedId = 190
$ServerBackupSuccessIds = @(4, 14)
$ServerBackupFailureIds = @(5, 8, 9, 20, 21, 22, 49, 517, 521, 561, 564)
$VeeamAgentServices = @('VeeamEndpointBackupSvc')
$VeeamServerServices = @('VeeamBackupSvc')
$MacriumServices = @('Macrium*')
$AcronisServices = @('Acronis*', 'AcrSch2Svc', 'cyber-protect-service')
$DattoServices = @('*Datto*Backup*', '*Datto*Windows Agent*', '*Datto*Continuity*', 'DattoWindowsAgent*')
$SynologyServices = @('*Synology*Active*Backup*', '*ActiveBackup*Agent*')

# ---- Functions ------------------------------------------------------------
function Format-UtcText {
    param([DateTime] $Time)
    return $Time.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
}

function Format-AgeText {
    param([TimeSpan] $Span)
    if ($Span.TotalHours -lt 48) { return ('{0} h' -f [math]::Floor($Span.TotalHours)) }
    return ('{0} days' -f [math]::Floor($Span.TotalDays))
}

function Find-Service {
    # Services whose name or display name matches any pattern.
    param($Services, [string[]] $Patterns)
    $hits = @()
    foreach ($service in $Services) {
        foreach ($pattern in $Patterns) {
            if (([string]$service.Name -like $pattern) -or ([string]$service.DisplayName -like $pattern)) {
                $hits += $service
                break
            }
        }
    }
    return $hits
}

function Get-BackupEvent {
    # Newest first. Empty when the log, the provider or the events do not exist.
    param([Parameter(Mandatory = $true)][string] $LogName, [int[]] $Ids, [string] $ProviderName)
    $filter = @{ LogName = $LogName }
    if ($Ids) { $filter['Id'] = $Ids }
    if ($ProviderName) { $filter['ProviderName'] = $ProviderName }
    try {
        return @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEventsToRead -ErrorAction Stop)
    }
    catch {
        if ($_.FullyQualifiedErrorId -like '*NoMatching*') { return @() }
        throw
    }
}

function Get-VeeamLogName {
    # Every Veeam event log on this PC (the agent's log name differs by version).
    $names = @()
    try {
        foreach ($log in @(Get-WinEvent -ListLog '*Veeam*' -ErrorAction Stop)) { $names += [string]$log.LogName }
    }
    catch {
        if ($_.FullyQualifiedErrorId -notlike '*NoMatching*') { throw }
    }
    return $names
}

function ConvertTo-LevelResult {
    # Event level: 1 critical and 2 error = Failed, 3 = Warning, anything else = Success.
    param($Entry)
    $level = [int]$Entry.Level
    if ($level -ge 1 -and $level -le 2) { return 'Failed' }
    if ($level -eq $LevelWarning) { return 'Warning' }
    return 'Success'
}

function New-EventResult {
    param($Entry, [string] $Result)
    return [pscustomobject]@{ TimeUtc = $Entry.TimeCreated.ToUniversalTime(); Result = $Result }
}

function New-EventProductResult {
    # From finished-run results (TimeUtc, Result) to the product's verdict.
    param([string] $Product, $Results, [string] $Evidence, [int] $MaxAgeHours)
    $now = [DateTime]::UtcNow
    $sorted = @($Results | Sort-Object -Property TimeUtc -Descending)
    if ($sorted.Count -eq 0) {
        return [pscustomobject]@{
            Product = $Product; LastSuccessUtc = $null; LastResult = 'No finished run found'; IsAlert = $true
            Reason = "${Product}: no finished backup found in the event log"; Evidence = $Evidence
        }
    }
    $newest = $sorted[0]
    $completed = @($sorted | Where-Object { $_.Result -ne 'Failed' })
    $lastSuccess = $null
    if ($completed.Count -gt 0) { $lastSuccess = $completed[0].TimeUtc }
    $window = @($sorted | Where-Object { ($now - $_.TimeUtc).TotalHours -le $MaxAgeHours })
    $failedInWindow = @($window | Where-Object { $_.Result -eq 'Failed' }).Count
    $isAlert = $true
    $newestAge = Format-AgeText -Span ($now - $newest.TimeUtc)
    if ($newest.Result -eq 'Failed') {
        $reason = "${Product}: last backup failed $newestAge ago"
    }
    elseif ($null -eq $lastSuccess) {
        $reason = "${Product}: no successful backup in the log"
    }
    elseif (($now - $lastSuccess).TotalHours -gt $MaxAgeHours) {
        $reason = "${Product}: last success $(Format-AgeText -Span ($now - $lastSuccess)) ago (limit $MaxAgeHours h)"
    }
    else {
        $isAlert = $false
        $reason = "${Product}: last success $(Format-AgeText -Span ($now - $lastSuccess)) ago"
        if ($newest.Result -eq 'Warning') { $reason += ' (warning)' }
    }
    return [pscustomobject]@{
        Product = $Product; LastSuccessUtc = $lastSuccess; LastResult = $newest.Result; IsAlert = $isAlert; Reason = $reason
        Evidence = "$Evidence; $($window.Count) finished in $MaxAgeHours h, $failedInWindow failed"
    }
}

function New-ServiceProductResult {
    # A product whose last result cannot be read here: alert only on an automatic service that is not running.
    param([string] $Product, $Found, [string] $Evidence)
    $stopped = @($Found | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' })
    if ($stopped.Count -gt 0) {
        return [pscustomobject]@{
            Product = $Product; LastSuccessUtc = $null; LastResult = 'Service not running'; IsAlert = $true
            Reason = "${Product}: service $($stopped[0].Name) is $($stopped[0].State)"; Evidence = "$Evidence; service $($stopped[0].Name) $($stopped[0].State)"
        }
    }
    return [pscustomobject]@{
        Product = $Product; LastSuccessUtc = $null; LastResult = 'Present, last result not readable locally'; IsAlert = $false
        Reason = "${Product}: present, last result not readable locally"; Evidence = "$Evidence; service $($Found[0].Name) $($Found[0].State)"
    }
}

function Get-VeeamAgentResult {
    param($Services, [int] $MaxAgeHours)
    $found = @(Find-Service -Services $Services -Patterns $VeeamAgentServices)
    $results = @()
    $logs = @(Get-VeeamLogName | Where-Object { $_ -ne 'Veeam Backup' })
    foreach ($logName in $logs) {
        foreach ($entry in @(Get-BackupEvent -LogName $logName -Ids @($VeeamJobFinishedId))) {
            $results += New-EventResult -Entry $entry -Result (ConvertTo-LevelResult -Entry $entry)
        }
    }
    if ($found.Count -eq 0 -and $results.Count -eq 0) { return $null }
    $logText = if ($logs.Count -gt 0) { $logs -join ', ' } else { 'no Veeam agent log' }
    return New-EventProductResult -Product 'Veeam Agent for Windows' -Results $results -MaxAgeHours $MaxAgeHours `
        -Evidence "Event log $logText, event $VeeamJobFinishedId level; confidence medium"
}

function Get-VeeamServerResult {
    param($Services, [int] $MaxAgeHours)
    $found = @(Find-Service -Services $Services -Patterns $VeeamServerServices)
    $results = @()
    foreach ($entry in @(Get-BackupEvent -LogName 'Veeam Backup' -Ids @($VeeamJobFinishedId))) {
        $results += New-EventResult -Entry $entry -Result (ConvertTo-LevelResult -Entry $entry)
    }
    if ($found.Count -eq 0 -and $results.Count -eq 0) { return $null }
    return New-EventProductResult -Product 'Veeam Backup & Replication' -Results $results -MaxAgeHours $MaxAgeHours `
        -Evidence "Event log Veeam Backup, event $VeeamJobFinishedId level; confidence medium"
}

function Get-ServerBackupResult {
    param([int] $MaxAgeHours)
    $events = @(Get-BackupEvent -LogName 'Microsoft-Windows-Backup' -Ids ($ServerBackupSuccessIds + $ServerBackupFailureIds))
    if ($events.Count -eq 0) { return $null }
    $results = @()
    foreach ($entry in $events) {
        $result = if ($ServerBackupSuccessIds -contains [int]$entry.Id) { 'Success' } else { 'Failed' }
        $results += New-EventResult -Entry $entry -Result $result
    }
    return New-EventProductResult -Product 'Windows Server Backup' -Results $results -MaxAgeHours $MaxAgeHours `
        -Evidence 'Event log Microsoft-Windows-Backup, success 4 and 14, failure 5 8 9 20-22 49 517 521 561 564; confidence high/medium'
}

function Get-MacriumResult {
    param($Services, [int] $MaxAgeHours)
    $found = @(Find-Service -Services $Services -Patterns $MacriumServices)
    $events = @(Get-BackupEvent -LogName 'Application' -ProviderName 'Macrium*')
    if ($events.Count -gt 0) {
        $results = @()
        foreach ($entry in $events) { $results += New-EventResult -Entry $entry -Result (ConvertTo-LevelResult -Entry $entry) }
        return New-EventProductResult -Product 'Macrium Reflect' -Results $results -MaxAgeHours $MaxAgeHours `
            -Evidence 'Application log, provider Macrium*, event level; confidence low'
    }
    if ($found.Count -eq 0) { return $null }
    return New-ServiceProductResult -Product 'Macrium Reflect' -Found $found -Evidence 'Service only; no Macrium events in the Application log; confidence service only'
}

function Get-AcronisResult {
    param($Services, [int] $MaxAgeHours)
    $found = @(Find-Service -Services $Services -Patterns $AcronisServices)
    if ($found.Count -eq 0) { return $null }
    $cutoff = [DateTime]::UtcNow.AddHours(-$MaxAgeHours)
    $errors = @(Get-BackupEvent -LogName 'Application' -ProviderName 'Acronis*' | Where-Object { $_.TimeCreated.ToUniversalTime() -ge $cutoff -and [int]$_.Level -ge 1 -and [int]$_.Level -le 2 })
    $result = New-ServiceProductResult -Product 'Acronis Cyber Protect' -Found $found -Evidence 'Service only; confidence service only'
    if ($errors.Count -gt 0) { $result.Evidence = "$($result.Evidence); $($errors.Count) Acronis error event(s) in $MaxAgeHours h, check the console" }
    return $result
}

function Get-ServiceOnlyProduct {
    param($Services, [string] $Product, [string[]] $Patterns)
    $found = @(Find-Service -Services $Services -Patterns $Patterns)
    if ($found.Count -eq 0) { return $null }
    return New-ServiceProductResult -Product $Product -Found $found -Evidence 'Service only; confidence service only'
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    $Config = [pscustomobject]@{
        MaxAgeHours = Read-OutpostInt -Name 'MaxAgeHours' -Min 1 -Max 8760
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'Administrator rights are required to read the backup event logs. Run the script as SYSTEM or an administrator.'
    }

    # Detect
    Write-OutpostLine -Text "Looking for backup products and reading their last result (limit $($Config.MaxAgeHours) h)."
    $services = @(Get-CimInstance -ClassName Win32_Service)
    $found = New-Object -TypeName System.Collections.ArrayList
    $candidates = @(
        (Get-VeeamAgentResult -Services $services -MaxAgeHours $Config.MaxAgeHours),
        (Get-VeeamServerResult -Services $services -MaxAgeHours $Config.MaxAgeHours),
        (Get-ServerBackupResult -MaxAgeHours $Config.MaxAgeHours),
        (Get-MacriumResult -Services $services -MaxAgeHours $Config.MaxAgeHours),
        (Get-AcronisResult -Services $services -MaxAgeHours $Config.MaxAgeHours),
        (Get-ServiceOnlyProduct -Services $services -Product 'Datto backup agent' -Patterns $DattoServices),
        (Get-ServiceOnlyProduct -Services $services -Product 'Synology Active Backup for Business' -Patterns $SynologyServices)
    )
    foreach ($candidate in $candidates) {
        if ($null -ne $candidate) { [void]$found.Add($candidate) }
    }
    if ($found.Count -eq 0) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: no supported backup product detected (Veeam, Windows Server Backup, Macrium, Acronis, Datto, Synology).'
    }

    foreach ($product in $found) {
        $lastSuccessText = 'unknown'
        if ($null -ne $product.LastSuccessUtc) { $lastSuccessText = Format-UtcText -Time $product.LastSuccessUtc }
        elseif ($product.LastResult -eq 'No finished run found') { $lastSuccessText = 'never' }
        Add-OutpostRow -Values @{ Product = $product.Product; LastSuccess = $lastSuccessText; LastResult = $product.LastResult; Evidence = $product.Evidence }
    }

    # Finish
    $alerts = @($found | Where-Object { $_.IsAlert })
    if ($alerts.Count -gt 0) {
        Complete-OutpostRun -Status 'ALERT' -Answer (($alerts | ForEach-Object { $_.Reason }) -join '; ')
    }
    Complete-OutpostRun -Status 'OK' -Answer (($found | ForEach-Object { $_.Reason }) -join '; ')
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
