#Requires -Version 5.1
<#
.SYNOPSIS
    One-shot "this PC is slow" check: CPU, memory, disk, startup load, updates, power plan, crashes and antivirus.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. It collects, in about 15 seconds, the facts a
    technician checks first when a user says the PC is slow, one row each with
    a plain-language concern when something looks wrong:

      * uptime, CPU now and memory now (3 samples, one second apart),
      * the top 5 programs by CPU and by memory (processes of the same name,
        such as every Chrome process, are added together),
      * free space on each fixed drive, how busy the disks are (busy time and
        queue length), and whether Windows is on a hard disk instead of an SSD,
      * how many programs start at sign-in: Run keys (this PC and signed-in
        users), Startup folders, and scheduled tasks that run at logon
        (Microsoft's own tasks are not counted),
      * a restart waiting for Windows Update, the active power plan, and
        whether the CPU is running well below its top speed under load,
      * the last blue screen in the System log (last 30 days count as a concern),
      * whether Defender is scanning or using a lot of CPU, and how many
        antivirus products are active (two slow a PC badly).

    The answer lists the three most important concerns, worst first, or says
    no obvious cause was found. The table has every check so you can see what
    was normal. Startup entries that a user switched off in Task Manager are
    still counted, because Windows keeps that switch somewhere this script
    does not read. Needs administrator rights.

.PARAMETER DryRun
    Reserved; ignored by Reports.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\get-slow-pc-diagnostics.ps1

    Prints every check with its concerns and a one-line answer.

.EXAMPLE
    .\get-slow-pc-diagnostics.ps1 -OutputFormat Json -ExportPath C:\Temp\slow-pc.json

    The same as JSON, also saved to a file.

.NOTES
    Name:        PC is slow - slow-PC first aid diagnostic
    Slug:        get-slow-pc-diagnostics
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Report
    Category:    10 Disk, performance & cleanup
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1; administrator rights
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     About 15 seconds
    Answer:      "3 concerns: memory 6% available; C: has 8% free; up 41 days - restart it"
    Fields:      Check, Value, Concern
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/get-slow-pc-diagnostics
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'get-slow-pc-diagnostics'
    Version = '1.0.0'
    Type    = 'Report'
    Risk    = 'Low'
    Inputs  = @()
    Fields  = @('Check', 'Value', 'Concern')
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
$SampleCount = 3
$TopCount = 5
$IdleProcessNames = @('_Total', 'Idle')
$CbsKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$WindowsUpdateKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$RunKeyPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
$RunKeyPathWow64 = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
$UserHiveRoot = 'Registry::HKEY_USERS'
$StartupFolderTail = 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
$PowerSaverGuid = 'a1841308-3541-4fab-bc81-f71556f20b4a'
$ProductStateOnMask = 61440
$ProductStateOn = 4096

# ---- Functions ------------------------------------------------------------
function Get-PropertyOrNull {
    param($Source, [string] $Name)
    if ($null -eq $Source) { return $null }
    $property = $Source.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Add-Finding {
    # One table row; a non-empty Concern is also kept for the answer, ranked by Weight (higher is worse).
    param([string] $Check, [string] $Value, [string] $Concern = '', [int] $Weight = 0)
    Add-OutpostRow -Values @{ Check = $Check; Value = $Value; Concern = $Concern }
    if ($Concern -ne '') { [void]$script:Concerns.Add([pscustomobject]@{ Text = $Concern; Weight = $Weight }) }
}

function Format-Span {
    param([TimeSpan] $Span)
    if ($Span.TotalDays -ge 2) { return ('{0} days' -f [math]::Floor($Span.TotalDays)) }
    if ($Span.TotalHours -ge 1) { return ('{0} hours' -f [math]::Floor($Span.TotalHours)) }
    return ('{0} minutes' -f [math]::Floor($Span.TotalMinutes))
}

function Format-Size {
    param([double] $Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    return ('{0:N0} MB' -f ($Bytes / 1MB))
}

function Read-CpuNow {
    $total = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'")
    if ($total.Count -eq 0) { return 0.0 }
    return [double]$total[0].PercentProcessorTime
}

function Read-ProcessCpuNow {
    # Name -> CPU as a share of the whole PC; names with #n suffixes are added together.
    param([int] $Logical)
    $result = @{}
    foreach ($item in @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process)) {
        $name = [string]$item.Name
        if ($IdleProcessNames -contains $name) { continue }
        $short = $name -replace '#\d+$', ''
        if (-not $result.ContainsKey($short)) { $result[$short] = 0.0 }
        $result[$short] = $result[$short] + ([double]$item.PercentProcessorTime / $Logical)
    }
    return $result
}

function Read-DiskBusyNow {
    $total = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfDisk_PhysicalDisk -Filter "Name='_Total'" -ErrorAction SilentlyContinue)
    if ($total.Count -eq 0) { return $null }
    $busy = [double](Get-PropertyOrNull -Source $total[0] -Name 'PercentDiskTime')
    if ($busy -gt 100) { $busy = 100 }
    return [pscustomobject]@{ Busy = $busy; Queue = [double](Get-PropertyOrNull -Source $total[0] -Name 'CurrentDiskQueueLength') }
}

function Get-RunValueCount {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @((Get-Item -LiteralPath $Path).GetValueNames() | Where-Object { $_ -ne '' }).Count
}

function Get-StartupCount {
    # Run keys, Startup folders and logon scheduled tasks; the three parts are returned separately.
    param($Profiles)
    $registry = 0
    $registry += Get-RunValueCount -Path ('HKLM:\' + $RunKeyPath)
    $registry += Get-RunValueCount -Path ('HKLM:\' + $RunKeyPathWow64)
    foreach ($hive in @(Get-ChildItem -LiteralPath $UserHiveRoot -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-[\d-]+$' })) {
        $registry += Get-RunValueCount -Path ($UserHiveRoot + '\' + $hive.PSChildName + '\' + $RunKeyPath)
    }
    $folders = 0
    $folderList = @([Environment]::GetFolderPath('CommonStartup'))
    foreach ($profileItem in $Profiles) { $folderList += (Join-Path -Path ([string]$profileItem.LocalPath) -ChildPath $StartupFolderTail) }
    foreach ($folder in $folderList) {
        if ($folder -and (Test-Path -LiteralPath $folder)) {
            $folders += @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count
        }
    }
    $tasks = 0
    foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        if ([string]$task.State -eq 'Disabled' -or ([string]$task.TaskPath).StartsWith('\Microsoft\')) { continue }
        foreach ($trigger in @($task.Triggers)) {
            if ($null -ne $trigger -and [string]$trigger.CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger') { $tasks++; break }
        }
    }
    return [pscustomobject]@{ Registry = $registry; Folders = $folders; Tasks = $tasks; Total = ($registry + $folders + $tasks) }
}

function Test-RebootFlag {
    $reasons = @()
    if (Test-Path -LiteralPath $CbsKey) { $reasons += 'Windows servicing' }
    if (Test-Path -LiteralPath $WindowsUpdateKey) { $reasons += 'Windows Update' }
    return $reasons
}

function Get-ActivePowerPlan {
    # GUID decides; the name in the parentheses is only shown. powercfg prints text in the PC's language.
    $exe = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'powercfg.exe'
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $text = (@(& $exe /getactivescheme 2>&1 | ForEach-Object { "$_" }) -join ' ') }
    finally { $ErrorActionPreference = $savedPreference }
    $guid = ''
    $name = ''
    if ($text -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $guid = $Matches[1].ToLowerInvariant() }
    if ($text -match '\(([^)]+)\)\s*$') { $name = $Matches[1] }
    return [pscustomobject]@{ Guid = $guid; Name = $name }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $script:Concerns = New-Object -TypeName System.Collections.ArrayList

    # Detect
    Write-OutpostLine -Text 'Collecting slow-PC facts (about 15 seconds).'
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $system = Get-CimInstance -ClassName Win32_ComputerSystem
    $logical = [int](Get-PropertyOrNull -Source $system -Name 'NumberOfLogicalProcessors')
    if ($logical -lt 1) { $logical = 1 }
    $profiles = @(Get-CimInstance -ClassName Win32_UserProfile | Where-Object { -not $_.Special -and ([string]$_.SID) -match '^S-1-(5-21|12-1)-' -and $_.LocalPath })

    # Sample CPU, per-process CPU and disk busy time; the first read only primes the counters.
    $null = Read-CpuNow
    $null = Read-ProcessCpuNow -Logical $logical
    $null = Read-DiskBusyNow
    Start-Sleep -Seconds 1
    $cpuSamples = @()
    $busySamples = @()
    $queueSamples = @()
    $processTotals = @{}
    for ($i = 0; $i -lt $SampleCount; $i++) {
        $cpuSamples += Read-CpuNow
        $disk = Read-DiskBusyNow
        if ($null -ne $disk) { $busySamples += $disk.Busy; $queueSamples += $disk.Queue }
        $perProcess = Read-ProcessCpuNow -Logical $logical
        foreach ($name in $perProcess.Keys) {
            if (-not $processTotals.ContainsKey($name)) { $processTotals[$name] = 0.0 }
            $processTotals[$name] = $processTotals[$name] + $perProcess[$name]
        }
        if ($i -lt ($SampleCount - 1)) { Start-Sleep -Seconds 1 }
    }
    $cpuNow = [math]::Round(($cpuSamples | Measure-Object -Average).Average, 0)

    # Uptime
    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeConcern = ''
    $uptimeWeight = 0
    if ($uptime.TotalDays -ge 30) { $uptimeConcern = "up $(Format-Span -Span $uptime) - restart it"; $uptimeWeight = 55 }
    elseif ($uptime.TotalDays -ge 14) { $uptimeConcern = "up $(Format-Span -Span $uptime) - restart it"; $uptimeWeight = 40 }
    Add-Finding -Check 'Uptime' -Value (Format-Span -Span $uptime) -Concern $uptimeConcern -Weight $uptimeWeight

    # CPU now
    $cpuConcern = if ($cpuNow -ge 85) { "CPU at $cpuNow%" } else { '' }
    Add-Finding -Check 'CPU now' -Value "$cpuNow% (average of $SampleCount samples)" -Concern $cpuConcern -Weight 70

    # Memory now
    $totalBytes = [double]$os.TotalVisibleMemorySize * 1KB
    $availableBytes = [double]$os.FreePhysicalMemory * 1KB
    $memoryCounter = @(Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue)
    if ($memoryCounter.Count -gt 0) {
        $counterMB = [double](Get-PropertyOrNull -Source $memoryCounter[0] -Name 'AvailableMBytes')
        if ($counterMB -gt 0) { $availableBytes = $counterMB * 1MB }
    }
    $availablePercent = if ($totalBytes -gt 0) { [math]::Round(100 * $availableBytes / $totalBytes, 0) } else { 0 }
    $memoryConcern = ''
    $memoryWeight = 0
    if ($availablePercent -lt 10) { $memoryConcern = "memory $availablePercent% available"; $memoryWeight = 90 }
    elseif ($availablePercent -lt 20) { $memoryConcern = "memory $availablePercent% available"; $memoryWeight = 70 }
    Add-Finding -Check 'Memory now' -Value ("{0} of {1} available ({2}%)" -f (Format-Size -Bytes $availableBytes), (Format-Size -Bytes $totalBytes), $availablePercent) -Concern $memoryConcern -Weight $memoryWeight

    # Top programs
    $topCpu = @($processTotals.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Cpu = [math]::Round($processTotals[$_] / $SampleCount, 0) } } |
            Sort-Object -Property Cpu -Descending | Select-Object -First $TopCount)
    $topCpuConcern = ''
    if ($topCpu.Count -gt 0 -and $topCpu[0].Cpu -ge 50) { $topCpuConcern = "$($topCpu[0].Name) is using $($topCpu[0].Cpu)% of the CPU" }
    Add-Finding -Check 'Top programs by CPU' -Value (($topCpu | ForEach-Object { "$($_.Name) $($_.Cpu)%" }) -join ', ') -Concern $topCpuConcern -Weight 65
    $topMemory = @(Get-Process | Group-Object -Property ProcessName | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; Bytes = [double](($_.Group | Measure-Object -Property WorkingSet64 -Sum).Sum) }
        } | Sort-Object -Property Bytes -Descending | Select-Object -First $TopCount)
    $topMemoryConcern = ''
    if ($topMemory.Count -gt 0 -and $totalBytes -gt 0 -and ($topMemory[0].Bytes / $totalBytes) -ge 0.4) {
        $topMemoryConcern = "$($topMemory[0].Name) is using $(Format-Size -Bytes $topMemory[0].Bytes) of memory"
    }
    Add-Finding -Check 'Top programs by memory' -Value (($topMemory | ForEach-Object { "$($_.Name) $(Format-Size -Bytes $_.Bytes)" }) -join ', ') -Concern $topMemoryConcern -Weight 60

    # Disk space, busy time, drive type
    foreach ($drive in @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object -Property DeviceID)) {
        $size = [double]$drive.Size
        if ($size -le 0) { continue }
        $freePercent = [math]::Round(100 * [double]$drive.FreeSpace / $size, 0)
        $driveConcern = ''
        $driveWeight = 0
        if ($freePercent -lt 10) { $driveConcern = "$($drive.DeviceID) has $freePercent% free"; $driveWeight = 85 }
        elseif ($freePercent -lt 15) { $driveConcern = "$($drive.DeviceID) has $freePercent% free"; $driveWeight = 60 }
        Add-Finding -Check "Free space $($drive.DeviceID)" -Value ("{0} free of {1} ({2}%)" -f (Format-Size -Bytes ([double]$drive.FreeSpace)), (Format-Size -Bytes $size), $freePercent) -Concern $driveConcern -Weight $driveWeight
    }
    if ($busySamples.Count -gt 0) {
        $busy = [math]::Round(($busySamples | Measure-Object -Average).Average, 0)
        $queue = [math]::Round(($queueSamples | Measure-Object -Average).Average, 1)
        $busyConcern = if ($busy -ge 90) { "disk busy $busy% of the time (queue $queue)" } else { '' }
        Add-Finding -Check 'Disk busy and queue' -Value "busy $busy%, queue length $queue" -Concern $busyConcern -Weight 75
    }
    else {
        Add-Finding -Check 'Disk busy and queue' -Value 'not reported'
    }
    $systemRoot = [IO.Path]::GetPathRoot([Environment]::SystemDirectory)
    $mediaText = 'not reported'
    $mediaConcern = ''
    try {
        $partition = Get-Partition -DriveLetter ([string]$systemRoot[0]) -ErrorAction Stop
        $physical = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceId -eq [string]$partition.DiskNumber })
        if ($physical.Count -gt 0) {
            $mediaText = [string]$physical[0].MediaType
            if ($mediaText -eq 'HDD') { $mediaConcern = 'Windows is on a hard disk (HDD), not an SSD' }
        }
    }
    catch { $mediaText = 'not reported' }
    Add-Finding -Check 'Windows drive type' -Value $mediaText -Concern $mediaConcern -Weight 45

    # Startup load
    $startup = Get-StartupCount -Profiles $profiles
    $startupConcern = if ($startup.Total -ge 20) { "$($startup.Total) programs start at sign-in" } else { '' }
    Add-Finding -Check 'Startup programs' -Value ("{0} (Run keys {1}, Startup folders {2}, logon tasks {3})" -f $startup.Total, $startup.Registry, $startup.Folders, $startup.Tasks) -Concern $startupConcern -Weight 40

    # Pending restart
    $rebootReasons = @(Test-RebootFlag)
    $rebootText = if ($rebootReasons.Count -gt 0) { 'yes (' + ($rebootReasons -join ', ') + ')' } else { 'no' }
    Add-Finding -Check 'Restart pending' -Value $rebootText -Concern $(if ($rebootReasons.Count -gt 0) { 'a restart is waiting to finish updates' } else { '' }) -Weight 50

    # Power plan and CPU speed
    $plan = Get-ActivePowerPlan
    $planText = if ($plan.Guid -eq '') { 'not reported' } elseif ($plan.Name -ne '') { $plan.Name } else { $plan.Guid }
    Add-Finding -Check 'Power plan' -Value $planText -Concern $(if ($plan.Guid -eq $PowerSaverGuid) { 'power plan is Power saver, which slows the CPU' } else { '' }) -Weight 55
    $cpu = @(Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1)
    $speedText = 'not reported'
    $speedConcern = ''
    if ($cpu.Count -gt 0) {
        $current = [double](Get-PropertyOrNull -Source $cpu[0] -Name 'CurrentClockSpeed')
        $maximum = [double](Get-PropertyOrNull -Source $cpu[0] -Name 'MaxClockSpeed')
        if ($maximum -gt 0 -and $current -gt 0) {
            $speedPercent = [math]::Round(100 * $current / $maximum, 0)
            $speedText = ('{0:N1} GHz of {1:N1} GHz ({2}%)' -f ($current / 1000), ($maximum / 1000), $speedPercent)
            if ($cpuNow -ge 50 -and $speedPercent -lt 60) { $speedConcern = "CPU is running at $speedPercent% of its top speed under load" }
        }
    }
    Add-Finding -Check 'CPU speed' -Value $speedText -Concern $speedConcern -Weight 45

    # Last blue screen
    $bugcheck = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; Id = 1001 } -MaxEvents 1 -ErrorAction SilentlyContinue)
    if ($bugcheck.Count -gt 0) {
        $bugTime = $bugcheck[0].TimeCreated.ToUniversalTime()
        $bugDays = ([DateTime]::UtcNow - $bugTime).TotalDays
        $bugText = $bugTime.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        Add-Finding -Check 'Last blue screen' -Value $bugText -Concern $(if ($bugDays -le 30) { "blue screen on $($bugTime.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture))" } else { '' }) -Weight 65
    }
    else {
        Add-Finding -Check 'Last blue screen' -Value 'none recorded'
    }

    # Antivirus: Defender busy, and how many products are active
    $defenderCpu = if ($processTotals.ContainsKey('MsMpEng')) { [math]::Round($processTotals['MsMpEng'] / $SampleCount, 0) } else { 0 }
    $scanProcess = @(Get-Process -Name 'MpCmdRun' -ErrorAction SilentlyContinue)
    $scanText = if ($scanProcess.Count -gt 0) { 'a scan is running (MpCmdRun)' } else { 'no scan command running' }
    $defenderConcern = if ($scanProcess.Count -gt 0 -or $defenderCpu -ge 25) { "Defender is busy ($defenderCpu% CPU), likely scanning" } else { '' }
    Add-Finding -Check 'Defender activity' -Value "MsMpEng $defenderCpu% CPU; $scanText" -Concern $defenderConcern -Weight 50
    $active = @()
    $avAvailable = $true
    try {
        foreach ($product in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntivirusProduct' -ErrorAction Stop)) {
            if (([int]$product.productState -band $ProductStateOnMask) -eq $ProductStateOn) { $active += [string]$product.displayName }
        }
    }
    catch { $avAvailable = $false }
    if ($avAvailable) {
        Add-Finding -Check 'Antivirus products active' -Value ("{0}: {1}" -f $active.Count, $(if ($active.Count -gt 0) { $active -join ', ' } else { 'none' })) -Concern $(if ($active.Count -ge 2) { "$($active.Count) antivirus products are active ($($active -join ', '))" } else { '' }) -Weight 60
    }
    else {
        Add-Finding -Check 'Antivirus products active' -Value 'not reported (Windows Security Center is not on this PC)'
    }

    # Finish
    $ranked = @($script:Concerns | Sort-Object -Property Weight -Descending | Select-Object -First 3)
    $summary = "up $(Format-Span -Span $uptime), CPU $cpuNow%, memory $availablePercent% available"
    if ($ranked.Count -eq 0) {
        Complete-OutpostRun -Status 'OK' -Answer "No obvious cause found: $summary"
    }
    $noun = if ($script:Concerns.Count -eq 1) { 'concern' } else { 'concerns' }
    Complete-OutpostRun -Status 'OK' -Answer ("$($script:Concerns.Count) $noun" + $(if ($script:Concerns.Count -gt 3) { ', top 3' } else { '' }) + ': ' + (($ranked | ForEach-Object { $_.Text }) -join '; '))
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
