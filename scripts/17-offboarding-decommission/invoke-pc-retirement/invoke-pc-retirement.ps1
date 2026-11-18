#Requires -Version 5.1
<#
.SYNOPSIS
    Retires a PC: leaves Entra ID and the domain, removes MDM enrollment, and writes a retirement record. Does not wipe the disk.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It is the "PC is leaving service" step, and it
    does only the parts that apply to this PC:

      * Entra ID: if the PC is Entra joined or hybrid joined, it runs
        dsregcmd /leave (LeaveEntra).
      * Domain: if the PC is joined to an Active Directory domain, it leaves the
        domain and joins the workgroup WorkgroupName (LeaveDomain). The PC must
        be restarted to finish this; the script never restarts it. It leaves the
        computer account in Active Directory: delete it there.
      * MDM: any remaining MDM enrollment (Intune and similar) is removed from
        this PC: its registry key (exported to the backup folder first) and its
        scheduled tasks (UnenrollMdm). The device record in the MDM console is
        NOT touched: retire or delete it there.
      * Record: always writes a retirement record, a text file in
        %ProgramData%\MSPOutpost\Retirement\ with the computer name, serial
        number, make and model, OS, disk models and serial numbers, BitLocker
        status and recovery key IDs (never the keys themselves), what the PC
        was joined to, what this run did, and the optional Note.

    A part that does not apply is SKIPPED with its reason in the table (not
    domain joined, not Entra joined, no MDM enrollment, or turned off by its
    input). A PC that is not joined to anything still gets its record.

    IT DOES NOT WIPE ANYTHING. User files, profiles, programs and the disk
    contents are untouched and the record says so: erase the drives (Reset this
    PC with "Clean the drive", the MDM wipe, or the vendor's secure-erase) before
    the PC leaves your control. It also does NOT remove the RMM or remote
    support agent that is running this script, because that would end the run
    and the record: remove it last, with uninstall-rmm-agent, once the record is
    written. Cached credentials and saved passwords are not cleared.

    Only Windows 10 and 11 PCs; servers and domain controllers are SKIPPED.

    A High-risk Action: it only lists what it would do until BOTH DryRun=false
    AND Approve=invoke-pc-retirement are set. Each part is one change (the
    record is one), so a run makes at most 4 changes plus one per MDM
    enrollment; MaxChanges defaults to 25. A second run, with nothing left to
    leave, says "Already retired". After a domain leave, restart, then run it
    again to confirm.

    Not proven on a joined PC: the Entra, domain and MDM parts need a PC
    joined to a real tenant or domain. Run the dry run on the PC first and read
    the table.

.PARAMETER LeaveEntra
    true leaves Entra ID (dsregcmd /leave) when the PC is joined or registered.
    Default true.
    Environment variable: LeaveEntra

.PARAMETER LeaveDomain
    true leaves the Active Directory domain and joins WorkgroupName. Default
    true. Environment variable: LeaveDomain

.PARAMETER UnenrollMdm
    true removes the MDM enrollment from this PC. Default true.
    Environment variable: UnenrollMdm

.PARAMETER WorkgroupName
    The workgroup to join when leaving the domain. 1 to 15 letters, digits or
    hyphens. Default WORKGROUP.
    Environment variable: WorkgroupName

.PARAMETER Note
    Free text for the record, for example a ticket number or the reason. Up to
    100 characters, plain ASCII. Default empty.
    Environment variable: Note

.PARAMETER DryRun
    Default true for this script. false (with Approve) makes the changes.
    Environment variable: DryRun

.PARAMETER Approve
    Must be invoke-pc-retirement for DryRun=false to take effect.
    Environment variable: Approve

.PARAMETER MaxChanges
    The most changes one run may make. Default 25.
    Environment variable: MaxChanges

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\invoke-pc-retirement.ps1

    Dry run: lists what it would leave and remove, and writes nothing.

.EXAMPLE
    .\invoke-pc-retirement.ps1 -DryRun false -Approve invoke-pc-retirement -Note "Ticket 4821, replaced"

    Leaves Entra ID, the domain and MDM as they apply, and writes the record.

.NOTES
    Name:        Retire a PC - leave domain and Entra ID, remove MDM, write the record
    Slug:        invoke-pc-retirement
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Action
    Category:    17 Offboarding & decommission
    Platforms:   Windows 10, Windows 11
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Leaves Entra ID and the domain, removes MDM enrollments (registry key and tasks), writes a retirement record file; does not wipe or restart
    Risk:        High
    Reboot:      May
    Runtime:     Under a minute
    Answer:      "Retired: left Entra ID, left domain corp.local (restart to finish); record PC042-20261117-101500.txt written; disks NOT wiped"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/invoke-pc-retirement
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $LeaveEntra = 'true',
    [string] $LeaveDomain = 'true',
    [string] $UnenrollMdm = 'true',
    [string] $WorkgroupName = 'WORKGROUP',
    [string] $Note = '',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'invoke-pc-retirement'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('LeaveEntra', 'LeaveDomain', 'UnenrollMdm', 'WorkgroupName', 'Note')
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
$EntraJoinKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo'
$EnrollmentsKey = 'HKLM:\SOFTWARE\Microsoft\Enrollments'
$EnterpriseMgmtTaskRoot = '\Microsoft\Windows\EnterpriseMgmt\'
$RecordFolderName = 'Retirement'
$MaxNoteCharacters = 100

# ---- Functions ------------------------------------------------------------
function Get-EntraJoinState {
    # True when the PC holds an Entra ID join (also hybrid). Registry, not
    # dsregcmd text, so it does not depend on the display language.
    if (-not (Test-Path -LiteralPath $EntraJoinKey)) { return $false }
    return (@(Get-ChildItem -LiteralPath $EntraJoinKey -ErrorAction SilentlyContinue).Count -gt 0)
}

function Get-MdmEnrollment {
    # Enrollments with a provider and an enrollment state: Intune and similar.
    $found = @()
    if (-not (Test-Path -LiteralPath $EnrollmentsKey)) { return $found }
    foreach ($key in @(Get-ChildItem -LiteralPath $EnrollmentsKey -ErrorAction SilentlyContinue)) {
        if ($key.PSChildName -notmatch '^[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}$') { continue }
        $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) { continue }
        $provider = $properties.PSObject.Properties['ProviderID']
        $state = $properties.PSObject.Properties['EnrollmentState']
        if (-not $provider -or -not $state -or [string]$provider.Value -eq '') { continue }
        # Windows ships its own local MDM authorities on every PC (seen on a clean Windows 11,
        # 2026-11-17); they are not an enrollment and removing them breaks Windows' MDM stack.
        if ([string]$provider.Value -in @('Deploy Authority', 'Cloud Authority', 'Local Authority')) { continue }
        $found += [pscustomobject]@{
            Id       = $key.PSChildName
            Provider = [string]$provider.Value
            Path     = ($EnrollmentsKey + '\' + $key.PSChildName)
        }
    }
    return $found
}

function Get-RecordFolder {
    # Path only (nothing is created here), without trusting the environment.
    $base = [Environment]::GetFolderPath('CommonApplicationData')
    if (-not $base) { $base = 'C:\ProgramData' }
    return (Join-Path -Path (Join-Path -Path $base -ChildPath 'MSPOutpost') -ChildPath $RecordFolderName)
}

function Get-BitLockerSummary {
    # Status and recovery key IDs of the system drive. The keys are never read out.
    if (-not (Get-Command -Name 'Get-BitLockerVolume' -ErrorAction SilentlyContinue)) { return 'BitLocker module not available on this edition' }
    try {
        $systemFolder = [Environment]::GetFolderPath('System')
        if (-not $systemFolder) { $systemFolder = 'C:\Windows\System32' }
        $drive = Split-Path -Path $systemFolder -Qualifier
        $volume = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
        $identifiers = @($volume.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' } | ForEach-Object { [string]$_.KeyProtectorId })
        return "System drive $($drive): protection $($volume.ProtectionStatus); recovery key ID(s): $(if ($identifiers.Count -gt 0) { $identifiers -join ', ' } else { 'none' })"
    }
    catch { return "BitLocker status could not be read: $($_.Exception.Message)" }
}

function New-RetirementRecordText {
    param([string[]] $Before, [string[]] $Done, [string] $Failure, [string] $NoteText)
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS
    $system = Get-CimInstance -ClassName Win32_OperatingSystem
    $lines = @(
        'MSP Outpost PC retirement record',
        ('Written (UTC):   ' + [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', $invariant)),
        ('By:              ' + $OutpostScript.Slug + ' ' + $OutpostScript.Version),
        ('Computer name:   ' + [Environment]::MachineName),
        ('Serial number:   ' + [string]$bios.SerialNumber),
        ('Make and model:  ' + [string]$computer.Manufacturer + ' ' + [string]$computer.Model),
        ('Operating system: ' + [string]$system.Caption + ' ' + [string]$system.Version),
        ('Note:            ' + $NoteText),
        '',
        'Disks:'
    )
    foreach ($disk in @(Get-CimInstance -ClassName Win32_DiskDrive)) {
        $sizeGB = [math]::Round([double]$disk.Size / 1GB, 0).ToString($invariant)
        $lines += ('  ' + [string]$disk.Model + ', serial ' + ([string]$disk.SerialNumber).Trim() + ', ' + $sizeGB + ' GB')
    }
    $lines += ''
    $lines += ('BitLocker: ' + (Get-BitLockerSummary))
    $lines += ''
    $lines += 'Before this run:'
    foreach ($line in $Before) { $lines += ('  ' + $line) }
    $lines += ''
    $lines += 'Done by this run:'
    if ($Done.Count -eq 0) { $lines += '  nothing to leave or remove' }
    foreach ($line in $Done) { $lines += ('  ' + $line) }
    if ($Failure -ne '') {
        $lines += ''
        $lines += ('STOPPED BY AN ERROR: ' + $Failure)
    }
    $lines += ''
    $lines += 'The data on the disks was NOT wiped by this script. Erase the drives before the PC leaves your control.'
    $lines += 'Still to do: delete this device in the MDM, Entra ID and Active Directory consoles; remove the RMM agent last.'
    return ($lines -join "`r`n")
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        LeaveEntra    = Read-OutpostBool -Name 'LeaveEntra'
        LeaveDomain   = Read-OutpostBool -Name 'LeaveDomain'
        UnenrollMdm   = Read-OutpostBool -Name 'UnenrollMdm'
        WorkgroupName = Read-OutpostText -Name 'WorkgroupName'
        Note          = (Read-OutpostText -Name 'Note') -replace '[^\x20-\x7E]', ' '
    }
    if ($Config.WorkgroupName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
        Stop-OutpostInput -Name 'WorkgroupName' -Value $Config.WorkgroupName -Expected '1 to 15 letters, digits or hyphens, starting with a letter or digit'
    }
    if ($Config.Note.Length -gt $MaxNoteCharacters) {
        Stop-OutpostInput -Name 'Note' -Value "$($Config.Note.Length) characters" -Expected "at most $MaxNoteCharacters characters"
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ([int]$osInfo.ProductType -ne 1 -or [int]$osInfo.BuildNumber -lt 10240) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: this is not a Windows 10 or 11 PC (servers and domain controllers are not retired by this script).'
    }

    # Detect
    $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    $isEntraJoined = Get-EntraJoinState
    $isDomainJoined = [bool]$computerInfo.PartOfDomain
    $domainName = [string]$computerInfo.Domain
    $enrollments = @(Get-MdmEnrollment)
    $doEntra = $Config.LeaveEntra -and $isEntraJoined
    $doDomain = $Config.LeaveDomain -and $isDomainJoined
    $doMdm = $Config.UnenrollMdm -and ($enrollments.Count -gt 0)
    $before = @(
        $(if ($isEntraJoined) { 'Entra ID: joined or registered' } else { 'Entra ID: not joined' }),
        $(if ($isDomainJoined) { "Domain: $domainName" } else { "Workgroup: $domainName" }),
        $(if ($enrollments.Count -gt 0) { 'MDM: ' + (($enrollments | ForEach-Object { $_.Provider }) -join ', ') } else { 'MDM: not enrolled' })
    )
    Write-OutpostLine -Text ($before -join '; ')
    $recordFolder = Get-RecordFolder
    $existingRecords = @()
    if (Test-Path -LiteralPath $recordFolder) {
        $existingRecords = @(Get-ChildItem -LiteralPath $recordFolder -Filter ([Environment]::MachineName + '-*.txt') -ErrorAction SilentlyContinue | Sort-Object -Property Name)
    }
    # The legs that do not apply are shown, with the reason.
    if (-not $doEntra) {
        $why = if (-not $Config.LeaveEntra) { 'LeaveEntra is false' } else { 'not joined to Entra ID' }
        Add-OutpostRow -Values @{ Item = 'Entra ID'; Change = 'Leave (dsregcmd /leave)'; Result = "Skipped: $why" }
    }
    if (-not $doDomain) {
        $why = if (-not $Config.LeaveDomain) { 'LeaveDomain is false' } else { 'not joined to a domain' }
        Add-OutpostRow -Values @{ Item = 'Domain'; Change = 'Leave and join the workgroup'; Result = "Skipped: $why" }
    }
    if (-not $doMdm) {
        $why = if (-not $Config.UnenrollMdm) { 'UnenrollMdm is false' } else { 'no MDM enrollment' }
        Add-OutpostRow -Values @{ Item = 'MDM'; Change = 'Remove the enrollment'; Result = "Skipped: $why" }
    }
    $hasLegs = $doEntra -or $doDomain -or $doMdm
    if (-not $hasLegs -and $existingRecords.Count -gt 0) {
        Complete-OutpostRun -Status 'OK' -Answer "Already retired: nothing left to leave or remove, and the record $($existingRecords[$existingRecords.Count - 1].Name) exists."
    }
    # One change per leg, one per MDM enrollment, one for the record.
    $planned = 1
    if ($doEntra) { $planned++ }
    if ($doDomain) { $planned++ }
    if ($doMdm) { $planned += $enrollments.Count }
    Assert-OutpostChangeLimit -Planned $planned

    # Act
    $summary = New-Object -TypeName System.Collections.ArrayList
    $failure = ''
    $restartNeeded = $false
    try {
        if ($doEntra) {
            $null = Invoke-OutpostChange -Item 'Entra ID' -Change 'Leave (dsregcmd /leave)' -Action {
                $systemFolder = [Environment]::GetFolderPath('System')
                if (-not $systemFolder) { $systemFolder = 'C:\Windows\System32' }
                $null = & (Join-Path -Path $systemFolder -ChildPath 'dsregcmd.exe') /leave 2>&1
                if ($LASTEXITCODE -ne 0) { throw "dsregcmd /leave failed with exit code $LASTEXITCODE." }
            }
            [void]$summary.Add('left Entra ID')
        }
        if ($doMdm) {
            # Leaving Entra ID removes its own enrollment; whatever is still there is removed here.
            $targets = $enrollments
            if (-not $script:OutpostRun.DryRun) { $targets = @(Get-MdmEnrollment) }
            $mdmCount = 0
            foreach ($enrollment in $targets) {
                $null = Invoke-OutpostChange -Item ("MDM enrollment " + $enrollment.Provider + ' ' + $enrollment.Id) -Change 'Remove the enrollment and its scheduled tasks' -Action {
                    $null = Backup-OutpostItem -Path $enrollment.Path
                    $taskPath = $EnterpriseMgmtTaskRoot + $enrollment.Id + '\'
                    foreach ($task in @(Get-ScheduledTask -TaskPath $taskPath -ErrorAction SilentlyContinue)) {
                        Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $taskPath -Confirm:$false
                    }
                    Remove-Item -LiteralPath $enrollment.Path -Recurse -Force
                }
                $mdmCount++
            }
            if ($mdmCount -gt 0) { [void]$summary.Add("removed $mdmCount MDM enrollment(s)") }
            else { Add-OutpostRow -Values @{ Item = 'MDM'; Change = 'Remove the enrollment'; Result = 'Skipped: leaving Entra ID removed it' } }
        }
        if ($doDomain) {
            $null = Invoke-OutpostChange -Item "Domain $domainName" -Change "Leave the domain and join workgroup $($Config.WorkgroupName) (restart needed)" -Action {
                Remove-Computer -WorkgroupName $Config.WorkgroupName -Force -ErrorAction Stop
            }
            [void]$summary.Add("left domain $domainName (restart to finish)")
            $restartNeeded = $true
        }
        # Verify (skipped in a dry run: nothing was changed)
        if (-not $script:OutpostRun.DryRun) {
            if ($doEntra -and (Get-EntraJoinState)) { throw 'The PC still shows an Entra ID join after dsregcmd /leave. Run dsregcmd /status on the PC and leave it from there.' }
            if ($doMdm -and @(Get-MdmEnrollment).Count -gt 0) { throw 'An MDM enrollment is still present after it was removed. Check HKLM:\SOFTWARE\Microsoft\Enrollments.' }
        }
    }
    catch {
        $failure = $_.Exception.Message
    }

    # The record is written even when a part failed, so the PC's state is on file.
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
    $recordName = [Environment]::MachineName + '-' + $stamp + '.txt'
    try {
        $null = Invoke-OutpostChange -Item (Join-Path -Path $recordFolder -ChildPath $recordName) -Change 'Write the retirement record' -Action {
            if (-not (Test-Path -LiteralPath $recordFolder)) {
                $null = Get-OutpostDataFolder
                $null = New-Item -Path $recordFolder -ItemType Directory -Force
            }
            $text = New-RetirementRecordText -Before $before -Done @($summary) -Failure $failure -NoteText $Config.Note
            Set-Content -LiteralPath (Join-Path -Path $recordFolder -ChildPath $recordName) -Value $text -Encoding UTF8
        }
    }
    catch {
        if ($failure -eq '') { $failure = "The retirement record could not be written: $($_.Exception.Message)" }
    }
    if ($failure -ne '') {
        Stop-OutpostRun -Message "$failure Done before this: $(if ($summary.Count -gt 0) { $summary -join ', ' } else { 'nothing' }). Fix it and run again."
    }
    if (-not $script:OutpostRun.DryRun -and -not (Test-Path -LiteralPath (Join-Path -Path $recordFolder -ChildPath $recordName))) {
        Stop-OutpostRun -Message "The retirement record $recordName is not in $recordFolder after writing. Check the folder permissions and run again."
    }

    # Finish
    $legText = if ($summary.Count -gt 0) { 'Retired: ' + ($summary -join ', ') } else { 'Retired: no domain, Entra ID or MDM part to leave' }
    Complete-OutpostRun -Status 'CHANGED' -Answer "$legText; record $recordName written; disks NOT wiped"
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
