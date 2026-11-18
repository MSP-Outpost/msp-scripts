#Requires -Version 5.1
<#
.SYNOPSIS
    Outlook first-aid report: Office build and channel, profiles, OST and PST files, add-ins and recent crashes.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. It reports what a technician checks first when
    classic Outlook is slow, hangs or crashes:

      * Office version, update channel and Outlook.exe build (from the Click-to-Run
        configuration, or the installed file for an MSI install),
      * the signed-in user's Outlook profiles, the default profile and how many
        accounts each holds,
      * OST and PST files with their sizes: an OST over OstWarningGB (default 50
        GB) is flagged because Outlook slows and can corrupt, and a PST or OST on
        a network path is flagged because Microsoft does not support it,
      * Cached Exchange Mode: the Cached Mode policy value, and whether an OST
        exists (an OST means Outlook is working from a local cache),
      * COM add-ins with their LoadBehavior, and the ones Outlook disabled
        itself (Resiliency: DisabledItems, CrashingAddinList and any list with
        Slow in its name),
      * Outlook crashes (Application Error, event 1000) and hangs (Application
        Hang, event 1002) in the last CrashDays days, newest first, up to 10.

    The user's registry and folders are read in the signed-in user's session
    (Invoke-OutpostAsUser); the Office install and the event log are read as
    SYSTEM. With nobody signed in the user part is left out with a WARNING.

    It covers classic Outlook (OUTLOOK.EXE). The new Outlook for Windows is
    not covered. Outlook not installed ends SKIPPED. The Flagged column marks
    what to look at first.

.PARAMETER OstWarningGB
    Flag an OST or NST file larger than this many GB. Whole number, 1 to
    10000. Default 50. Environment variable: OstWarningGB

.PARAMETER CrashDays
    Look back this many days for Outlook crashes and hangs. Whole number, 1 to
    365. Default 14. Environment variable: CrashDays

.PARAMETER DryRun
    Reserved; ignored by Reports.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\get-outlook-diagnostics.ps1

    Reports on Outlook for the signed-in user.

.EXAMPLE
    .\get-outlook-diagnostics.ps1 -OstWarningGB 30 -CrashDays 30 -ExportPath C:\Temp\outlook.csv

    Flags OST files over 30 GB, looks back 30 days and also saves the rows as CSV.

.NOTES
    Name:        Outlook slow or crashing - first-aid report
    Slug:        get-outlook-diagnostics
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Report
    Category:    16 Browser & application config
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1; a signed-in user for the profile, file and add-in sections
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 1 minute
    Answer:      "Outlook 16.0.17328.20162 (Current Channel); 1 profile(s); OST 3.2 GB; 1 add-in disabled; 2 crashes in 14 days"
    Fields:      Section, Item, Value, Flagged
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/get-outlook-diagnostics
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text. Defaults are the
    # place to edit when your RMM cannot pass arguments or variables.
    [string] $OstWarningGB = '50',
    [string] $CrashDays = '14',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'get-outlook-diagnostics'
    Version = '1.0.0'
    Type    = 'Report'
    Risk    = 'Low'
    Inputs  = @('OstWarningGB', 'CrashDays')
    Fields  = @('Section', 'Item', 'Value', 'Flagged')
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
$AppPathKeys = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE')
$InstallRootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Office\16.0\Outlook\InstallRoot', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Outlook\InstallRoot',
    'HKLM:\SOFTWARE\Microsoft\Office\15.0\Outlook\InstallRoot', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\15.0\Outlook\InstallRoot',
    'HKLM:\SOFTWARE\Microsoft\Office\14.0\Outlook\InstallRoot', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\14.0\Outlook\InstallRoot'
)
$ClickToRunKey = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
$UpdatePolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate'
$MaxCrashRows = 10
$ProbeTimeoutSeconds = 100

# ---- Functions ------------------------------------------------------------
function Get-RegistryValueOrNull {
    param([string] $Key, [string] $Name)
    $item = Get-ItemProperty -LiteralPath $Key -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    $property = $item.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-ChannelName {
    param([string] $Url)
    $guid = ''
    if ($Url) { $guid = ($Url.TrimEnd('/') -split '/')[-1].ToLowerInvariant() }
    switch ($guid) {
        '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' { return 'Current Channel' }
        '64256afe-f5d9-4f86-8936-8840a6a4f5be' { return 'Current Channel (Preview)' }
        '55336b82-a18d-4dd6-b5f6-9e5095c314a6' { return 'Monthly Enterprise Channel' }
        '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' { return 'Semi-Annual Enterprise Channel' }
        'b8f9b850-328d-4355-9145-c59439a0c4cf' { return 'Semi-Annual Enterprise Channel (Preview)' }
        '5440fd1f-7ecb-4221-8110-145efaa6372f' { return 'Beta Channel' }
        'f2e724c1-748f-4b47-8fb8-8e0d210e9208' { return 'Office 2019 volume license' }
        '5030841d-c919-4594-8d2d-84ae4f96e58e' { return 'Office 2021 volume license' }
        default { if ($guid) { return "unknown channel ($guid)" } else { return 'unknown channel' } }
    }
}

function Get-OutlookExe {
    # Full path of the installed OUTLOOK.EXE, or '' when classic Outlook is not installed.
    foreach ($key in $AppPathKeys) {
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $path = [string](Get-Item -LiteralPath $key).GetValue('')
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path }
    }
    foreach ($key in $InstallRootKeys) {
        $root = Get-RegistryValueOrNull -Key $key -Name 'Path'
        if (-not $root) { continue }
        $path = Join-Path -Path ([string]$root) -ChildPath 'OUTLOOK.EXE'
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    return ''
}

function Format-SizeText {
    param([double] $Bytes)
    if ($Bytes -ge 1GB) { return ('{0} GB' -f [math]::Round($Bytes / 1GB, 1)) }
    return ('{0} MB' -f [math]::Round($Bytes / 1MB, 1))
}

function Add-DiagnosticRow {
    param([string] $Section, [string] $Item, [string] $Value, [bool] $Flagged)
    Add-OutpostRow -Values @{ Section = $Section; Item = $Item; Value = $Value; Flagged = $Flagged }
    if ($Flagged) { $script:FlaggedCount++ }
}

function Get-LoadBehaviorText {
    param([int] $Value)
    switch ($Value) {
        0 { return 'unloaded, will not load' }
        1 { return 'loaded now, will not load at startup' }
        2 { return 'unloaded, set to load at startup (Outlook sets this when it disables an add-in)' }
        3 { return 'loads at startup' }
        8 { return 'unloaded, loads on demand' }
        9 { return 'loaded, loads on demand' }
        16 { return 'loads on demand after the first run' }
        -1 { return 'no LoadBehavior value' }
        default { return "LoadBehavior $Value" }
    }
}

function Get-ProbeCode {
    # Read-only code that runs in the user's session and prints one JSON line.
    return @'
$uInfo = [ordered]@{}
$uInfo.User = [Environment]::UserName
$uVer = '16.0'
foreach ($uTry in @('16.0', '15.0', '14.0')) {
    if (Test-Path -LiteralPath ('HKCU:\Software\Microsoft\Office\' + $uTry + '\Outlook')) { $uVer = $uTry; break }
}
$uInfo.OfficeKey = $uVer
$uOutlookKey = 'HKCU:\Software\Microsoft\Office\' + $uVer + '\Outlook'
$uInfo.DefaultProfile = [string](Get-ItemProperty -LiteralPath $uOutlookKey -ErrorAction SilentlyContinue).DefaultProfile

$uProfiles = @()
$uProfileRoot = $uOutlookKey + '\Profiles'
if (Test-Path -LiteralPath $uProfileRoot) {
    foreach ($uProfile in @(Get-ChildItem -LiteralPath $uProfileRoot)) {
        $uAccountCount = 0
        $uAccountKey = $uProfile.PSPath + '\9375CFF0413111d3B88A00104B2A6676'
        if (Test-Path -LiteralPath $uAccountKey) { $uAccountCount = @(Get-ChildItem -LiteralPath $uAccountKey).Count }
        $uProfiles += [pscustomobject]@{ Name = $uProfile.PSChildName; Accounts = $uAccountCount }
    }
}
$uInfo.Profiles = $uProfiles

$uFiles = New-Object -TypeName System.Collections.ArrayList
$uDedupe = @{}
$uAdd = {
    param($uPath, $uSource)
    if (-not $uPath) { return }
    $uLower = $uPath.ToLowerInvariant()
    if ($uDedupe.ContainsKey($uLower)) { return }
    $uDedupe[$uLower] = $true
    $uExt = [IO.Path]::GetExtension($uPath).ToLowerInvariant()
    $uNetwork = $false
    if ($uPath.StartsWith('\\')) { $uNetwork = $true }
    else {
        try {
            $uRootPath = [IO.Path]::GetPathRoot($uPath)
            if ($uRootPath -and ([IO.DriveInfo]$uRootPath).DriveType -eq 'Network') { $uNetwork = $true }
        }
        catch { $uNetwork = $false }
    }
    $uExists = $false
    $uSize = -1
    if (-not $uNetwork -and (Test-Path -LiteralPath $uPath -PathType Leaf)) {
        $uExists = $true
        $uSize = (Get-Item -LiteralPath $uPath -Force).Length
    }
    [void]$uFiles.Add([pscustomobject]@{ Path = $uPath; Ext = $uExt; Network = $uNetwork; Exists = $uExists; Size = $uSize; Source = $uSource })
}
if (Test-Path -LiteralPath $uProfileRoot) {
    foreach ($uSubKey in @(Get-ChildItem -LiteralPath $uProfileRoot -Recurse -ErrorAction SilentlyContinue)) {
        foreach ($uValueName in @('001f6700', '001f6610')) {
            $uRaw = $uSubKey.GetValue($uValueName)
            if ($uRaw -is [byte[]]) {
                $uText = [Text.Encoding]::Unicode.GetString($uRaw).Trim([char]0)
                if ($uText -match '^([A-Za-z]:\\|\\\\).+\.(ost|pst|nst)$') { & $uAdd $uText 'profile' }
            }
        }
    }
}
$uDocuments = [Environment]::GetFolderPath('MyDocuments')
foreach ($uFolder in @(($env:LOCALAPPDATA + '\Microsoft\Outlook'), ($uDocuments + '\Outlook Files'), $uDocuments)) {
    if (-not (Test-Path -LiteralPath $uFolder -PathType Container)) { continue }
    foreach ($uItem in @(Get-ChildItem -LiteralPath $uFolder -File -ErrorAction SilentlyContinue)) {
        if (@('.ost', '.pst', '.nst') -contains $uItem.Extension.ToLowerInvariant()) { & $uAdd $uItem.FullName 'folder' }
    }
}
$uInfo.Files = @($uFiles)

$uAddins = @()
foreach ($uAddinRoot in @('HKCU:\Software\Microsoft\Office\Outlook\Addins', 'HKLM:\SOFTWARE\Microsoft\Office\Outlook\Addins', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\Outlook\Addins')) {
    if (-not (Test-Path -LiteralPath $uAddinRoot)) { continue }
    $uWhere = if ($uAddinRoot.StartsWith('HKCU')) { 'user' } elseif ($uAddinRoot -match 'WOW6432Node') { 'machine 32-bit' } else { 'machine' }
    foreach ($uAddin in @(Get-ChildItem -LiteralPath $uAddinRoot)) {
        $uAddinProps = Get-ItemProperty -LiteralPath $uAddin.PSPath
        $uLoad = -1
        if ($null -ne $uAddinProps.LoadBehavior) { $uLoad = [int]$uAddinProps.LoadBehavior }
        $uAddins += [pscustomobject]@{ Name = $uAddin.PSChildName; Where = $uWhere; Friendly = [string]$uAddinProps.FriendlyName; Load = $uLoad }
    }
}
$uInfo.Addins = $uAddins

$uLists = @()
$uResilienceKey = $uOutlookKey + '\Resiliency'
if (Test-Path -LiteralPath $uResilienceKey) {
    foreach ($uList in @(Get-ChildItem -LiteralPath $uResilienceKey)) {
        $uEntries = @()
        $uKeyObject = Get-Item -LiteralPath $uList.PSPath
        foreach ($uValue in @($uKeyObject.GetValueNames())) {
            $uData = $uKeyObject.GetValue($uValue)
            if ($uData -is [byte[]]) {
                $uClean = ([Text.Encoding]::Unicode.GetString($uData) -replace '[^\x20-\x7E]', ' ') -replace '\s+', ' '
                $uClean = $uClean.Trim()
                if ($uClean.Length -gt 120) { $uClean = $uClean.Substring(0, 120) }
                if ($uClean -ne '') { $uEntries += $uClean }
            }
            else { $uEntries += [string]$uValue }
        }
        $uLists += [pscustomobject]@{ Name = $uList.PSChildName; Entries = $uEntries }
    }
}
$uInfo.Resiliency = $uLists

$uInfo.CachedPolicy = ''
foreach ($uCachedKey in @(('HKCU:\Software\Policies\Microsoft\Office\' + $uVer + '\Outlook\Cached Mode'), ($uOutlookKey + '\Cached Mode'))) {
    $uCachedProps = Get-ItemProperty -LiteralPath $uCachedKey -ErrorAction SilentlyContinue
    if ($null -ne $uCachedProps -and $null -ne $uCachedProps.Enable) { $uInfo.CachedPolicy = [string]$uCachedProps.Enable; break }
}
$uInfo | ConvertTo-Json -Compress -Depth 6
'@
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    $Config = [pscustomobject]@{
        OstWarningGB = Read-OutpostInt -Name 'OstWarningGB' -Min 1 -Max 10000
        CrashDays    = Read-OutpostInt -Name 'CrashDays' -Min 1 -Max 365
    }
    $script:FlaggedCount = 0

    # Detect: Office
    $outlookExe = Get-OutlookExe
    if ($outlookExe -eq '') {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: classic Outlook (OUTLOOK.EXE) is not installed on this PC.'
    }
    Write-OutpostLine -Text "Outlook first-aid report (crashes looked for over the last $($Config.CrashDays) days)."
    $fileVersion = [string](Get-Item -LiteralPath $outlookExe).VersionInfo.FileVersion
    $officeVersion = $fileVersion
    $channelName = 'Windows Installer (MSI) install'
    $cdnUrl = Get-RegistryValueOrNull -Key $ClickToRunKey -Name 'CDNBaseUrl'
    if (-not $cdnUrl) { $cdnUrl = Get-RegistryValueOrNull -Key $ClickToRunKey -Name 'UpdateChannel' }
    if (Test-Path -LiteralPath $ClickToRunKey) {
        $reported = Get-RegistryValueOrNull -Key $ClickToRunKey -Name 'VersionToReport'
        if ($reported) { $officeVersion = [string]$reported }
        $channelName = Get-ChannelName -Url ([string]$cdnUrl)
        $branch = Get-RegistryValueOrNull -Key $UpdatePolicyKey -Name 'UpdateBranch'
        if ($branch) { $channelName += " (policy UpdateBranch $branch)" }
        $platform = Get-RegistryValueOrNull -Key $ClickToRunKey -Name 'Platform'
        $products = Get-RegistryValueOrNull -Key $ClickToRunKey -Name 'ProductReleaseIds'
        Add-DiagnosticRow -Section 'Office' -Item 'Products' -Value ([string]$products) -Flagged $false
        if ($platform) { Add-DiagnosticRow -Section 'Office' -Item 'Architecture' -Value ([string]$platform) -Flagged $false }
    }
    Add-DiagnosticRow -Section 'Office' -Item 'Version' -Value $officeVersion -Flagged $false
    Add-DiagnosticRow -Section 'Office' -Item 'Update channel' -Value $channelName -Flagged $false
    Add-DiagnosticRow -Section 'Office' -Item 'Outlook.exe' -Value "$outlookExe ($fileVersion)" -Flagged $false

    # Detect: the signed-in user's Outlook
    $profileCount = 0
    $ostBytes = 0.0
    $cachedModeSeen = $false
    $userDataRead = $false
    $signedIn = Get-OutpostSignedInUser
    if (-not $signedIn) {
        Write-OutpostWarning -Text 'Nobody is signed in: profiles, data files and add-ins were not read.'
    }
    else {
        $probe = Invoke-OutpostAsUser -Code (Get-ProbeCode) -TimeoutSeconds $ProbeTimeoutSeconds -User $signedIn
        $jsonLine = @()
        if ($null -ne $probe) { $jsonLine = @(($probe.Output -split "\r?\n") | Where-Object { $_.TrimStart().StartsWith('{') } | Select-Object -First 1) }
        if ($null -eq $probe -or $probe.ExitCode -ne 0 -or $jsonLine.Count -eq 0) {
            $detail = if ($null -ne $probe) { "exit code $($probe.ExitCode): $($probe.Output)" } else { 'nobody signed in' }
            Write-OutpostWarning -Text "Could not read Outlook in the session of ${signedIn} ($detail); profile, data file and add-in sections are left out."
        }
        else {
            $userDataRead = $true
            $info = $jsonLine[0] | ConvertFrom-Json

            foreach ($outlookProfile in @($info.Profiles | Where-Object { $null -ne $_ })) {
                $profileCount++
                $defaultText = if ([string]$outlookProfile.Name -ieq [string]$info.DefaultProfile) { ' (default)' } else { '' }
                Add-DiagnosticRow -Section 'Profile' -Item ([string]$outlookProfile.Name + $defaultText) -Value "$($outlookProfile.Accounts) account(s) in Office $($info.OfficeKey)" -Flagged $false
            }
            if ($profileCount -eq 0) { Add-DiagnosticRow -Section 'Profile' -Item 'Outlook profiles' -Value "none found for $signedIn (Outlook has not been set up)" -Flagged $false }

            foreach ($dataFile in @($info.Files | Where-Object { $null -ne $_ })) {
                $isCache = @('.ost', '.nst') -contains [string]$dataFile.Ext
                $kindText = if ($dataFile.Ext -eq '.pst') { 'PST' } elseif ($dataFile.Ext -eq '.nst') { 'NST' } else { 'OST' }
                $flag = $false
                if ($dataFile.Network) {
                    $valueText = "$kindText on a network path (not supported by Microsoft; risk of corruption and slowness)"
                    $flag = $true
                }
                elseif (-not $dataFile.Exists) {
                    $valueText = "$kindText listed in the profile but the file was not found"
                    $flag = $true
                }
                else {
                    $valueText = "$kindText, " + (Format-SizeText -Bytes ([double]$dataFile.Size))
                    if ($isCache) {
                        $cachedModeSeen = $true
                        $ostBytes += [double]$dataFile.Size
                        if ([double]$dataFile.Size -gt ([double]$Config.OstWarningGB * 1GB)) {
                            $valueText += " (over $($Config.OstWarningGB) GB: slow and at risk of corruption)"
                            $flag = $true
                        }
                    }
                }
                Add-DiagnosticRow -Section 'Data file' -Item ([string]$dataFile.Path) -Value $valueText -Flagged $flag
            }
            if (@($info.Files | Where-Object { $null -ne $_ }).Count -eq 0) { Add-DiagnosticRow -Section 'Data file' -Item 'OST and PST files' -Value 'none found' -Flagged $false }

            $policyText = switch ([string]$info.CachedPolicy) {
                '1' { 'Cached Mode policy: enabled' }
                '0' { 'Cached Mode policy: disabled' }
                default { 'Cached Mode policy: not set' }
            }
            $cacheText = if ($cachedModeSeen) { 'an OST exists, so Outlook is working from a local cache' } else { 'no OST found, so Outlook is not using a local cache' }
            Add-DiagnosticRow -Section 'Cached mode' -Item $signedIn -Value "$policyText; $cacheText" -Flagged $false

            foreach ($addin in @($info.Addins | Where-Object { $null -ne $_ })) {
                $loadValue = [int]$addin.Load
                $label = if ([string]$addin.Friendly -ne '') { "$($addin.Name) ($($addin.Friendly))" } else { [string]$addin.Name }
                $addinFlag = ($loadValue -eq 0) -or ($loadValue -eq 2)
                Add-DiagnosticRow -Section 'Add-in' -Item $label -Value ("$($addin.Where): " + (Get-LoadBehaviorText -Value $loadValue)) -Flagged $addinFlag
            }
            foreach ($list in @($info.Resiliency | Where-Object { $null -ne $_ })) {
                $listFlag = @('DisabledItems', 'CrashingAddinList') -contains [string]$list.Name -or ([string]$list.Name -match 'Slow')
                $entries = @($list.Entries | Where-Object { $null -ne $_ })
                foreach ($entry in ($entries | Select-Object -First 20)) {
                    Add-DiagnosticRow -Section 'Add-in' -Item "Outlook resiliency: $($list.Name)" -Value ([string]$entry) -Flagged $listFlag
                }
            }
        }
    }

    # Detect: crashes and hangs
    $since = (Get-Date).AddDays(-$Config.CrashDays)
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = @(1000, 1002); StartTime = $since } -ErrorAction SilentlyContinue |
            Where-Object { $_.Properties.Count -gt 0 -and [string]$_.Properties[0].Value -ieq 'OUTLOOK.EXE' } |
            Sort-Object -Property TimeCreated -Descending)
    $shown = 0
    foreach ($logged in $events) {
        if ($shown -ge $MaxCrashRows) { break }
        $shown++
        $stamp = $logged.TimeCreated.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        if ($logged.Id -eq 1000) {
            if ($logged.Properties.Count -gt 6) {
                $detailText = "crash in module $($logged.Properties[3].Value), exception $($logged.Properties[6].Value), Outlook $($logged.Properties[1].Value)"
            }
            else { $detailText = 'crash (Application Error 1000, details not readable)' }
        }
        else { $detailText = 'hang (Application Hang 1002: Outlook stopped responding)' }
        Add-DiagnosticRow -Section 'Crash' -Item $stamp -Value $detailText -Flagged $true
    }
    if ($events.Count -gt $shown) { Add-DiagnosticRow -Section 'Crash' -Item 'More' -Value "$($events.Count - $shown) older event(s) not listed" -Flagged $true }
    if ($events.Count -eq 0) { Add-DiagnosticRow -Section 'Crash' -Item 'Last days' -Value "no Outlook crash or hang in the last $($Config.CrashDays) days" -Flagged $false }

    # Finish
    $parts = New-Object -TypeName System.Collections.ArrayList
    [void]$parts.Add("Outlook $officeVersion ($channelName)")
    if ($userDataRead) {
        [void]$parts.Add("$profileCount profile(s)")
        if ($cachedModeSeen) { [void]$parts.Add('OST ' + (Format-SizeText -Bytes $ostBytes)) }
    }
    [void]$parts.Add("$($events.Count) crash/hang event(s) in $($Config.CrashDays) days")
    if ($script:FlaggedCount -gt 0) { [void]$parts.Add("$($script:FlaggedCount) item(s) flagged") }
    Complete-OutpostRun -Status 'OK' -Answer ($parts -join '; ')
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
