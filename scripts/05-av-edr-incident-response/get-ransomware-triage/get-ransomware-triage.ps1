#Requires -Version 5.1
<#
.SYNOPSIS
    Collects ransomware evidence into one ZIP before anyone reboots: processes, services, tasks, autoruns, notes, connections, logs.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. It changes nothing on the PC except to write its own
    ZIP, %ProgramData%\MSPOutpost\Triage\<UTC time>.zip (the folder is locked to
    SYSTEM and Administrators when the script creates it, because command lines
    and logs can hold secrets). Run it BEFORE rebooting or reimaging: a reboot
    clears running processes and connections.

    The ZIP holds, as CSV and text files:
      * processes: every running process with its command line, parent,
        program path, the Authenticode signature status and signer, and the
        SHA-256 of the program file (up to 400 distinct program files);
      * services and scheduled tasks (non-Microsoft tasks with last run);
      * autoruns: the Run and RunOnce keys of the machine and of loaded user
        profiles, the Winlogon Shell and Userinit values, and the startup folders;
      * possible ransom notes: files named README*.txt, *DECRYPT*, *RECOVER*,
        *RESTORE*FILES* or *RANSOM* in user folders (profile root, Desktop,
        Documents, Downloads, Pictures, OneDrive) changed in the last 7 days,
        at most 200 files and 60 seconds, with the first 300 characters of text
        notes;
      * network connections: TCP connections and UDP endpoints with the owning
        process, and the DNS client cache;
      * the Security, System and Microsoft Defender Operational event logs of
        the last Hours hours, exported with wevtutil (.evtx);
      * local users, members of the local Administrators group, and who is
        signed in;
      * Volume Shadow Copy state (vssadmin list shadows and shadowstorage; a
        ransomware often deletes the shadow copies);
      * summary.txt: what was collected, what failed, how long it took.

    A section that cannot be collected is a WARNING and noted in summary.txt;
    the rest still goes into the ZIP. The answer is the ZIP path and size; the
    ZIP path is also what ResultField receives. Copy the ZIP off the PC (it is
    not uploaded anywhere) and treat it as sensitive.

.PARAMETER Hours
    How many hours of Security, System and Defender events to export. Whole
    number, 1 to 720. Default 24. Environment variable: Hours

.PARAMETER DryRun
    Reserved; ignored by Reports.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows (one per section) to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the ZIP path to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\get-ransomware-triage.ps1

    Collects the evidence with 24 hours of event logs and prints the ZIP path.

.EXAMPLE
    .\get-ransomware-triage.ps1 -Hours 72 -OutputFormat Answer

    Collects 72 hours of event logs; prints only the ZIP path.

.NOTES
    Name:        Ransomware triage: collect the evidence before a reboot
    Slug:        get-ransomware-triage
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Report
    Category:    05 AV / EDR & incident response
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, 1 GB free on the system drive
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     1 to 5 minutes
    Answer:      "Triage ZIP: C:\ProgramData\MSPOutpost\Triage\20261116-141500.zip (12.3 MB, 16 files, events of the last 24h); possible ransom notes: 2"
    Fields:      Section, Items, File
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/get-ransomware-triage
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $Hours = '24',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'get-ransomware-triage'
    Version = '1.0.0'
    Type    = 'Report'
    Risk    = 'Low'
    Inputs  = @('Hours')
    Fields  = @('Section', 'Items', 'File')
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
$MinFreeGB = 1
$MaxSignatureFiles = 400
$NoteDays = 7
$MaxNotes = 200
$NoteSearchSeconds = 60
$NotePreviewChars = 300
$NotePatterns = @('README*.txt', '*DECRYPT*', '*RECOVER*', '*RESTORE*FILES*', '*RANSOM*')
$NoteTextExtensions = @('.txt', '.html', '.htm', '.hta', '.md')
# Folders searched under each profile in the Users folder ('' = the profile root, not recursive).
$NoteFolders = @(
    @{ Sub = ''; Depth = 0 },
    @{ Sub = 'Desktop'; Depth = 3 },
    @{ Sub = 'Documents'; Depth = 3 },
    @{ Sub = 'Downloads'; Depth = 3 },
    @{ Sub = 'Pictures'; Depth = 2 }
)
$RunKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
)
$UserRunSubKeys = @(
    'SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
)

# ---- Functions ------------------------------------------------------------
function Get-EventLogSpec {
    # The event logs exported, with the file each goes to and the name shown in the report.
    return @(
        @{ Log = 'Security'; File = 'events-security.evtx'; Label = 'Security' },
        @{ Log = 'System'; File = 'events-system.evtx'; Label = 'System' },
        @{ Log = 'Microsoft-Windows-Windows Defender/Operational'; File = 'events-defender.evtx'; Label = 'Defender' }
    )
}

function Get-SystemTool {
    # A program in System32 without trusting the environment.
    param([string] $FileName)
    return (Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath $FileName)
}

function Invoke-NativeText {
    # Runs a program, keeps its output (both streams) as text, and returns the exit code too.
    param([string] $File, [string[]] $Arguments)
    $ErrorActionPreference = 'Continue'
    $lines = @(& $File @Arguments 2>&1 | ForEach-Object { [string]$_ })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Text = ($lines -join "`r`n") }
}

function Format-UtcTime {
    param($Value)
    if ($null -eq $Value) { return '' }
    try { return ([DateTime]$Value).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
    catch { return '' }
}

function Save-Csv {
    # A CSV with its header even when there are no rows.
    param([string] $Path, $Rows, [string[]] $Columns)
    $list = @($Rows)
    if ($list.Count -eq 0) {
        Set-Content -LiteralPath $Path -Value (($Columns | ForEach-Object { '"' + $_ + '"' }) -join ',') -Encoding UTF8
    }
    else {
        $list | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
}

function Get-ProcessRow {
    # Every process, with signature and hash of each distinct program file.
    $processes = @(Get-CimInstance -ClassName Win32_Process)
    $fileInfo = @{}
    $checked = 0
    foreach ($process in $processes) {
        $path = [string]$process.ExecutablePath
        if ($path -eq '' -or $fileInfo.ContainsKey($path)) { continue }
        if ($checked -ge $MaxSignatureFiles -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $fileInfo[$path] = [pscustomobject]@{ Status = 'NotChecked'; Signer = ''; Sha256 = '' }
            continue
        }
        $checked++
        $status = 'Unknown'
        $signer = ''
        $hash = ''
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            $status = [string]$signature.Status
            if ($signature.SignerCertificate) { $signer = [string]$signature.SignerCertificate.Subject }
        }
        catch { $status = 'Error' }
        try { $hash = [string](Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } catch { $hash = '' }
        $fileInfo[$path] = [pscustomobject]@{ Status = $status; Signer = $signer; Sha256 = $hash }
    }
    $rows = @()
    foreach ($process in $processes) {
        $path = [string]$process.ExecutablePath
        $info = $null
        if ($path -ne '' -and $fileInfo.ContainsKey($path)) { $info = $fileInfo[$path] }
        $rows += [pscustomobject]@{
            ProcessId       = [int]$process.ProcessId
            ParentProcessId = [int]$process.ParentProcessId
            Name            = [string]$process.Name
            Path            = $path
            CommandLine     = [string]$process.CommandLine
            StartedUtc      = (Format-UtcTime -Value $process.CreationDate)
            SessionId       = [int]$process.SessionId
            Signature       = $(if ($info) { $info.Status } else { '' })
            Signer          = $(if ($info) { $info.Signer } else { '' })
            Sha256          = $(if ($info) { $info.Sha256 } else { '' })
        }
    }
    return $rows
}

function Get-ServiceRow {
    $rows = @()
    foreach ($service in @(Get-CimInstance -ClassName Win32_Service)) {
        $rows += [pscustomobject]@{
            Name        = [string]$service.Name
            DisplayName = [string]$service.DisplayName
            State       = [string]$service.State
            StartMode   = [string]$service.StartMode
            Account     = [string]$service.StartName
            ProcessId   = [int]$service.ProcessId
            PathName    = [string]$service.PathName
        }
    }
    return $rows
}

function Get-TaskRow {
    $rows = @()
    foreach ($task in @(Get-ScheduledTask)) {
        $actions = @()
        foreach ($action in @($task.Actions)) {
            $execute = $action.PSObject.Properties['Execute']
            $arguments = $action.PSObject.Properties['Arguments']
            if ($execute) { $actions += (([string]$execute.Value + ' ' + $(if ($arguments) { [string]$arguments.Value } else { '' })).Trim()) }
        }
        $lastRun = ''
        $lastResult = ''
        if ($task.TaskPath -notlike '\Microsoft\*') {
            try {
                $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath
                $lastRun = Format-UtcTime -Value $info.LastRunTime
                $lastResult = [string]$info.LastTaskResult
            }
            catch { $null = $_ }
        }
        $rows += [pscustomobject]@{
            TaskPath       = [string]$task.TaskPath
            TaskName       = [string]$task.TaskName
            State          = [string]$task.State
            Author         = [string]$task.Author
            RunAs          = [string]$task.Principal.UserId
            Actions        = ($actions -join ' ; ')
            LastRunUtc     = $lastRun
            LastTaskResult = $lastResult
        }
    }
    return $rows
}

function Get-RegistryValueRow {
    # Every value under one registry key as Location, Name, Value rows.
    param([string] $Key, [string] $Label)
    $rows = @()
    $item = Get-ItemProperty -Path $Key -ErrorAction SilentlyContinue
    if (-not $item) { return $rows }
    foreach ($property in @($item.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
        $rows += [pscustomobject]@{ Location = $Label; Name = [string]$property.Name; Value = [string]$property.Value }
    }
    return $rows
}

function Get-AutorunRow {
    $rows = @()
    foreach ($key in $RunKeys) {
        $found = @(Get-RegistryValueRow -Key $key -Label $key)
        if ($key -like '*Winlogon') { $found = @($found | Where-Object { $_.Name -in @('Shell', 'Userinit', 'Taskman', 'AppSetup') }) }
        $rows += $found
    }
    $hivesRoot = 'Registry::HKEY_USERS'
    foreach ($hive in @(Get-ChildItem -Path $hivesRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-[0-9-]+$' })) {
        foreach ($sub in $UserRunSubKeys) {
            $rows += @(Get-RegistryValueRow -Key ($hive.PSPath + '\' + $sub) -Label ('HKU\' + $hive.PSChildName + '\' + $sub))
        }
    }
    $startupFolders = @([Environment]::GetFolderPath('CommonStartup'))
    $usersFolder = Join-Path -Path ([IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))) -ChildPath 'Users'
    foreach ($profileFolder in @(Get-ChildItem -LiteralPath $usersFolder -Directory -Force -ErrorAction SilentlyContinue)) {
        $startupFolders += (Join-Path -Path $profileFolder.FullName -ChildPath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup')
    }
    foreach ($folder in $startupFolders) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue)) {
            $rows += [pscustomobject]@{ Location = ('Startup folder ' + $folder); Name = [string]$file.Name; Value = [string]$file.FullName }
        }
    }
    return $rows
}

function Get-NotePreview {
    param([string] $Path, [long] $Length)
    if ($NoteTextExtensions -notcontains [IO.Path]::GetExtension($Path).ToLowerInvariant()) { return '' }
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try {
            $buffer = New-Object -TypeName byte[] -ArgumentList ([int][math]::Min($Length, $NotePreviewChars))
            $count = $stream.Read($buffer, 0, $buffer.Length)
            $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $count)
            return (($text -replace '[^\x20-\x7E]', ' ') -replace '\s+', ' ').Trim()
        }
        finally { $stream.Dispose() }
    }
    catch { return '' }
}

function Get-NoteRow {
    # Files that look like ransom notes, in user folders, from the last NoteDays days; bounded.
    # One walk per folder with the deadline checked at every folder, so a huge tree cannot overrun it.
    # A cloud placeholder (OneDrive "online only") is listed but never opened: reading it would download it.
    param($Truncated)
    $rows = New-Object -TypeName System.Collections.ArrayList
    $since = (Get-Date).AddDays(-$NoteDays)
    $deadline = (Get-Date).AddSeconds($NoteSearchSeconds)
    $usersFolder = Join-Path -Path ([IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))) -ChildPath 'Users'
    $cloudMask = [int]([IO.FileAttributes]::Offline) -bor 0x400000 -bor 0x40000
    $pending = New-Object -TypeName System.Collections.ArrayList
    foreach ($profileFolder in @(Get-ChildItem -LiteralPath $usersFolder -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
        foreach ($place in $NoteFolders) {
            $searchFolder = $profileFolder.FullName
            if ($place.Sub -ne '') { $searchFolder = Join-Path -Path $profileFolder.FullName -ChildPath $place.Sub }
            if (Test-Path -LiteralPath $searchFolder -PathType Container) { [void]$pending.Add(@($searchFolder, $place.Depth)) }
        }
        # "OneDrive", "OneDrive - <Organisation>" and similar folders.
        foreach ($oneDrive in @(Get-ChildItem -LiteralPath $profileFolder.FullName -Directory -Force -Filter 'OneDrive*' -ErrorAction SilentlyContinue)) {
            [void]$pending.Add(@($oneDrive.FullName, 3))
        }
    }
    $seen = @{}
    while ($pending.Count -gt 0) {
        if ((Get-Date) -gt $deadline -or $rows.Count -ge $MaxNotes) { $Truncated.Value = $true; break }
        $item = $pending[0]
        $pending.RemoveAt(0)
        $folder = [string]$item[0]
        $depth = [int]$item[1]
        if ($seen.ContainsKey($folder)) { continue }
        $seen[$folder] = $true
        foreach ($file in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue)) {
            $matched = $false
            foreach ($pattern in $NotePatterns) { if ($file.Name -like $pattern) { $matched = $true; break } }
            if (-not $matched) { continue }
            if ($file.LastWriteTime -lt $since -and $file.CreationTime -lt $since) { continue }
            if ($rows.Count -ge $MaxNotes) { $Truncated.Value = $true; break }
            $isPlaceholder = (([int]$file.Attributes) -band $cloudMask) -ne 0
            [void]$rows.Add([pscustomobject]@{
                Path        = [string]$file.FullName
                SizeBytes   = [long]$file.Length
                ModifiedUtc = (Format-UtcTime -Value $file.LastWriteTime)
                CreatedUtc  = (Format-UtcTime -Value $file.CreationTime)
                Preview     = $(if ($isPlaceholder) { '(cloud placeholder: not opened)' } else { Get-NotePreview -Path $file.FullName -Length $file.Length })
            })
        }
        if ($depth -gt 0) {
            foreach ($child in @(Get-ChildItem -LiteralPath $folder -Directory -Force -ErrorAction SilentlyContinue | Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })) {
                [void]$pending.Add(@($child.FullName, ($depth - 1)))
            }
        }
    }
    return @($rows)
}

function Get-ConnectionRow {
    # TCP connections and UDP endpoints with the process that owns them.
    $names = @{}
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, Name)) { $names[[int]$process.ProcessId] = [string]$process.Name }
    $rows = @()
    foreach ($connection in @(Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        $owner = [int]$connection.OwningProcess
        $rows += [pscustomobject]@{
            Protocol      = 'TCP'
            State         = [string]$connection.State
            LocalAddress  = [string]$connection.LocalAddress
            LocalPort     = [int]$connection.LocalPort
            RemoteAddress = [string]$connection.RemoteAddress
            RemotePort    = [int]$connection.RemotePort
            ProcessId     = $owner
            ProcessName   = $(if ($names.ContainsKey($owner)) { $names[$owner] } else { '' })
        }
    }
    foreach ($endpoint in @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue)) {
        $owner = [int]$endpoint.OwningProcess
        $rows += [pscustomobject]@{
            Protocol      = 'UDP'
            State         = ''
            LocalAddress  = [string]$endpoint.LocalAddress
            LocalPort     = [int]$endpoint.LocalPort
            RemoteAddress = ''
            RemotePort    = 0
            ProcessId     = $owner
            ProcessName   = $(if ($names.ContainsKey($owner)) { $names[$owner] } else { '' })
        }
    }
    return $rows
}

function Get-DnsCacheRow {
    $rows = @()
    foreach ($entry in @(Get-DnsClientCache -ErrorAction SilentlyContinue | Select-Object -First 3000)) {
        $rows += [pscustomobject]@{ Name = [string]$entry.Entry; Type = [string]$entry.Type; Data = [string]$entry.Data; TimeToLive = [int]$entry.TimeToLive }
    }
    return $rows
}

function Get-LocalUserRow {
    $rows = @()
    foreach ($user in @(Get-LocalUser)) {
        $rows += [pscustomobject]@{
            Name            = [string]$user.Name
            Enabled         = [bool]$user.Enabled
            Sid             = [string]$user.SID.Value
            LastLogonUtc    = (Format-UtcTime -Value $user.LastLogon)
            PasswordSetUtc  = (Format-UtcTime -Value $user.PasswordLastSet)
            Description     = [string]$user.Description
        }
    }
    return $rows
}

function Get-LocalAdminRow {
    # Members of the local Administrators group (found by its well-known SID).
    $rows = @()
    try {
        foreach ($member in @(Get-LocalGroupMember -SID 'S-1-5-32-544')) {
            $rows += [pscustomobject]@{ Name = [string]$member.Name; Kind = [string]$member.ObjectClass; Source = [string]$member.PrincipalSource; Sid = [string]$member.SID.Value }
        }
    }
    catch {
        # Get-LocalGroupMember throws on an unresolvable member; read the group through CIM instead.
        $group = @(Get-CimInstance -ClassName Win32_Group -Filter "SID='S-1-5-32-544'") | Select-Object -First 1
        if ($group) {
            foreach ($member in @(Get-CimAssociatedInstance -InputObject $group -Association Win32_GroupUser)) {
                $rows += [pscustomobject]@{ Name = ([string]$member.Domain + '\' + [string]$member.Name); Kind = ([string]$member.CimClass.CimClassName); Source = ''; Sid = [string]$member.SID }
            }
        }
    }
    return $rows
}

function Get-ShadowRow {
    $rows = @()
    foreach ($shadow in @(Get-CimInstance -ClassName Win32_ShadowCopy -ErrorAction SilentlyContinue)) {
        $rows += [pscustomobject]@{ Id = [string]$shadow.ID; CreatedUtc = (Format-UtcTime -Value $shadow.InstallDate); Volume = [string]$shadow.VolumeName; DeviceObject = [string]$shadow.DeviceObject }
    }
    return $rows
}

function Add-Section {
    # Runs one collector; a failure is a warning and a line in the summary, never the end of the run.
    param([string] $Section, [string] $FileName, [scriptblock] $Collector, $Notes)
    try {
        $count = [int](& $Collector)
        Add-OutpostRow -Values @{ Section = $Section; Items = $count; File = $FileName }
    }
    catch {
        Write-OutpostWarning -Text "$Section could not be collected: $($_.Exception.Message)"
        [void]$Notes.Add("FAILED  $Section ($FileName): $($_.Exception.Message)")
        Add-OutpostRow -Values @{ Section = $Section; Items = 0; File = '(failed)' }
    }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        Hours = Read-OutpostInt -Name 'Hours' -Min 1 -Max 720
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $triageRoot = Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Triage'
    $driveLetter = [IO.Path]::GetPathRoot($triageRoot)
    $freeGB = (New-Object -TypeName IO.DriveInfo -ArgumentList $driveLetter).AvailableFreeSpace / 1GB
    if ($freeGB -lt $MinFreeGB) {
        Stop-OutpostRun -Message ("Only {0} GB free on {1}; the triage needs at least $MinFreeGB GB. Free some space (clear-disk-space) and run again." -f [math]::Round($freeGB, 1), $driveLetter)
    }

    # Collect: nothing but the staging folder and the ZIP is written.
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
    if (-not (Test-Path -LiteralPath $triageRoot)) {
        $null = New-Item -Path $triageRoot -ItemType Directory -Force
        try {
            $null = & (Get-SystemTool -FileName 'icacls.exe') $triageRoot '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F'
            if ($LASTEXITCODE -ne 0) { Write-OutpostWarning -Text "Could not restrict access to $triageRoot (icacls exit code $LASTEXITCODE); the ZIP is readable by other users." }
        }
        catch { Write-OutpostWarning -Text "Could not restrict access to ${triageRoot}: $($_.Exception.Message)" }
    }
    $staging = Join-Path -Path $triageRoot -ChildPath $stamp
    $zipPath = Join-Path -Path $triageRoot -ChildPath ($stamp + '.zip')
    $null = New-Item -Path $staging -ItemType Directory -Force
    Write-OutpostLine -Text "Collecting evidence into $zipPath (event logs: last $($Config.Hours) hour(s))."
    $notes = New-Object -TypeName System.Collections.ArrayList
    $noteState = @{ NoteCount = 0; Truncated = $false }
    $windowHours = $Config.Hours

    Add-Section -Section 'Processes (command line, signature, hash)' -FileName 'processes.csv' -Notes $notes -Collector {
        $rows = @(Get-ProcessRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'processes.csv') -Rows $rows -Columns @('ProcessId', 'ParentProcessId', 'Name', 'Path', 'CommandLine', 'StartedUtc', 'SessionId', 'Signature', 'Signer', 'Sha256')
        $rows.Count
    }
    Add-Section -Section 'Services' -FileName 'services.csv' -Notes $notes -Collector {
        $rows = @(Get-ServiceRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'services.csv') -Rows $rows -Columns @('Name', 'DisplayName', 'State', 'StartMode', 'Account', 'ProcessId', 'PathName')
        $rows.Count
    }
    Add-Section -Section 'Scheduled tasks' -FileName 'scheduled-tasks.csv' -Notes $notes -Collector {
        $rows = @(Get-TaskRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'scheduled-tasks.csv') -Rows $rows -Columns @('TaskPath', 'TaskName', 'State', 'Author', 'RunAs', 'Actions', 'LastRunUtc', 'LastTaskResult')
        $rows.Count
    }
    Add-Section -Section 'Autoruns (Run keys, Winlogon, startup folders)' -FileName 'autoruns.csv' -Notes $notes -Collector {
        $rows = @(Get-AutorunRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'autoruns.csv') -Rows $rows -Columns @('Location', 'Name', 'Value')
        $rows.Count
    }
    Add-Section -Section 'Possible ransom notes' -FileName 'ransom-note-candidates.csv' -Notes $notes -Collector {
        $truncated = New-Object -TypeName psobject -Property @{ Value = $false }
        $rows = @(Get-NoteRow -Truncated $truncated)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'ransom-note-candidates.csv') -Rows $rows -Columns @('Path', 'SizeBytes', 'ModifiedUtc', 'CreatedUtc', 'Preview')
        $noteState.NoteCount = $rows.Count
        $noteState.Truncated = [bool]$truncated.Value
        $rows.Count
    }
    Add-Section -Section 'Network connections' -FileName 'connections.csv' -Notes $notes -Collector {
        $rows = @(Get-ConnectionRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'connections.csv') -Rows $rows -Columns @('Protocol', 'State', 'LocalAddress', 'LocalPort', 'RemoteAddress', 'RemotePort', 'ProcessId', 'ProcessName')
        $rows.Count
    }
    Add-Section -Section 'DNS client cache' -FileName 'dns-cache.csv' -Notes $notes -Collector {
        $rows = @(Get-DnsCacheRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'dns-cache.csv') -Rows $rows -Columns @('Name', 'Type', 'Data', 'TimeToLive')
        $rows.Count
    }
    foreach ($log in @(Get-EventLogSpec)) {
        $logName = [string]$log.Log
        $logFile = [string]$log.File
        Add-Section -Section ('Event log ' + [string]$log.Label + ', last ' + $windowHours + ' h (KB)') -FileName $logFile -Notes $notes -Collector {
            $target = Join-Path -Path $staging -ChildPath $logFile
            $milliseconds = [int64]$windowHours * 3600000
            $result = Invoke-NativeText -File (Get-SystemTool -FileName 'wevtutil.exe') -Arguments @('epl', $logName, $target, "/q:*[System[TimeCreated[timediff(@SystemTime) <= $milliseconds]]]", '/ow:true')
            if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $target)) { throw "wevtutil exit code $($result.ExitCode): $($result.Text)" }
            [int][math]::Ceiling((Get-Item -LiteralPath $target).Length / 1KB)
        }
    }
    Add-Section -Section 'Local users' -FileName 'local-users.csv' -Notes $notes -Collector {
        $rows = @(Get-LocalUserRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'local-users.csv') -Rows $rows -Columns @('Name', 'Enabled', 'Sid', 'LastLogonUtc', 'PasswordSetUtc', 'Description')
        $rows.Count
    }
    Add-Section -Section 'Local administrators' -FileName 'local-admins.csv' -Notes $notes -Collector {
        $rows = @(Get-LocalAdminRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'local-admins.csv') -Rows $rows -Columns @('Name', 'Kind', 'Source', 'Sid')
        $rows.Count
    }
    Add-Section -Section 'Signed-in sessions (quser)' -FileName 'sessions.txt' -Notes $notes -Collector {
        $result = Invoke-NativeText -File (Get-SystemTool -FileName 'quser.exe') -Arguments @()
        Set-Content -LiteralPath (Join-Path -Path $staging -ChildPath 'sessions.txt') -Value ('Console user (Win32_ComputerSystem): ' + [string](Get-CimInstance -ClassName Win32_ComputerSystem).UserName + "`r`n" + $result.Text) -Encoding UTF8
        @($result.Text -split "`r?`n" | Where-Object { $_.Trim() -ne '' }).Count
    }
    Add-Section -Section 'Shadow copies (vssadmin)' -FileName 'shadow-copies.txt' -Notes $notes -Collector {
        $shadows = Invoke-NativeText -File (Get-SystemTool -FileName 'vssadmin.exe') -Arguments @('list', 'shadows')
        $storage = Invoke-NativeText -File (Get-SystemTool -FileName 'vssadmin.exe') -Arguments @('list', 'shadowstorage')
        $rows = @(Get-ShadowRow)
        Save-Csv -Path (Join-Path -Path $staging -ChildPath 'shadow-copies.csv') -Rows $rows -Columns @('Id', 'CreatedUtc', 'Volume', 'DeviceObject')
        Set-Content -LiteralPath (Join-Path -Path $staging -ChildPath 'shadow-copies.txt') -Value ("vssadmin list shadows (exit code $($shadows.ExitCode))`r`n" + $shadows.Text + "`r`n`r`nvssadmin list shadowstorage (exit code $($storage.ExitCode))`r`n" + $storage.Text) -Encoding UTF8
        $rows.Count
    }

    # The summary goes in last, so it can list what failed.
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $summary = @(
        "MSP Outpost ransomware triage, get-ransomware-triage $($OutpostScript.Version)",
        "Computer:        $([Environment]::MachineName)",
        "Collected (UTC): $(Format-UtcTime -Value ([DateTime]::UtcNow))",
        "Operating system: $([string]$os.Caption) build $([string]$os.BuildNumber)",
        "Last boot (UTC): $(Format-UtcTime -Value $os.LastBootUpTime)",
        "Console user:    $([string](Get-CimInstance -ClassName Win32_ComputerSystem).UserName)",
        "Event log window: last $($Config.Hours) hour(s)",
        "Possible ransom notes: $($noteState.NoteCount)$(if ($noteState.Truncated) { ' (search stopped at its limit: ' + $MaxNotes + ' files or ' + $NoteSearchSeconds + ' seconds)' } else { '' })",
        '',
        'Sections:'
    )
    foreach ($row in @($script:OutpostRun.Rows)) { $summary += ("  {0}: {1} item(s) -> {2}" -f $row.Section, $row.Items, $row.File) }
    if ($notes.Count -gt 0) { $summary += ''; $summary += 'Problems:'; foreach ($note in $notes) { $summary += "  $note" } }
    Set-Content -LiteralPath (Join-Path -Path $staging -ChildPath 'summary.txt') -Value $summary -Encoding UTF8
    Add-OutpostRow -Values @{ Section = 'Summary'; Items = 1; File = 'summary.txt' }

    # Pack and check the ZIP, then remove the staging folder.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($staging, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try { $entryNames = @($archive.Entries | ForEach-Object { $_.Name }) }
    finally { $archive.Dispose() }
    if ($entryNames -notcontains 'summary.txt') {
        Stop-OutpostRun -Message "The ZIP $zipPath does not contain summary.txt, so it is incomplete. Run the script again."
    }
    Remove-Item -LiteralPath $staging -Recurse -Force
    $sizeMB = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)

    # Finish
    Set-OutpostFieldValue -Value $zipPath
    Complete-OutpostRun -Status 'OK' -Answer ("Triage ZIP: $zipPath ($sizeMB MB, $($entryNames.Count) files, events of the last $($Config.Hours)h); possible ransom notes: $($noteState.NoteCount)")
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
