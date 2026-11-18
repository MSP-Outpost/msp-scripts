#Requires -Version 5.1
<#
.SYNOPSIS
    Checks that a Windows 10 PC can run Windows 11, then starts the in-place upgrade (apps and files are kept).

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It is a High-risk Action: it only reports what it
    would do until BOTH DryRun=false AND Approve=update-windows-10-to-11 are set.

    Step 1, already done? A PC that already runs Windows 11 answers OK "Already
    Windows 11" and nothing else happens. A PC where an upgrade is already
    running (Windows 11 Installation Assistant or Windows Setup) answers OK. Windows
    Server is skipped.

    Step 2, eligibility, one row per requirement: 64-bit Windows 10 version 2004
    (build 19041) or later; UEFI firmware (Secure Boot capable; its current
    state is reported); TPM 2.0 present and enabled; a 64-bit processor with 2
    or more cores at 1 GHz or faster; RAM of at least MinRamGB; a system disk
    of at least MinDiskGB; FreeSpaceGB free on the system drive; and no restart
    waiting. A PC that fails any row is SKIPPED, and the answer names every
    reason. Microsoft's list of supported CPU models and its compatibility
    "safeguard holds" are NOT checked here: Windows Setup checks them itself
    and refuses to upgrade an unsupported PC.

    Step 3, the upgrade, only when approved and eligible:

      * MediaPath set: runs setup.exe from that folder (extracted Windows 11
        media, a mounted ISO drive such as E:\ or a network share) with
        /auto upgrade /quiet. The file must be signed by Microsoft. Unless
        AllowReboot is true it adds /noreboot, so Setup prepares everything
        and then WAITS for a restart that you choose (restart-computer).
      * MediaPath empty: downloads Microsoft's Windows 11 Installation
        Assistant (go.microsoft.com/fwlink/?linkid=2171764), checks that it is
        signed by Microsoft, and runs it silently. The Assistant restarts the
        PC itself when it has finished, and cannot be stopped from doing so, so
        this only runs when AllowReboot is true. Otherwise the script stops and
        says to set AllowReboot=true or to give a MediaPath.

    The script never restarts the PC itself. AllowReboot=true only lets the
    upgrade restart it, which interrupts a signed-in user without warning: the
    answer names the signed-in user when there is one. The upgrade runs in the
    background for 30 to 90 minutes; the script returns as soon as Setup has
    started. Setup's own log is in C:\$WINDOWS.~BT\Sources\Panther\setupact.log.

    Nothing in the Windows 10 install is deleted by this script. The upgrade
    keeps files, apps and settings, and Windows keeps the old Windows for 10
    days so the user can go back (Settings, System, Recovery). Back up first.

.PARAMETER MediaPath
    Folder that contains Windows 11 setup.exe. Default empty = use the
    Installation Assistant (needs AllowReboot=true).
    Environment variable: MediaPath

.PARAMETER AllowReboot
    true lets the upgrade restart the PC by itself (required for the
    Installation Assistant). Default false: with MediaPath, Setup waits for a
    restart you start. Environment variable: AllowReboot

.PARAMETER MinRamGB
    Minimum RAM in GB. Whole number, 1 to 4096. Default 4 (Microsoft's minimum).
    Environment variable: MinRamGB

.PARAMETER MinDiskGB
    Minimum size of the system disk in GB. Whole number, 1 to 100000. Default
    64 (Microsoft's minimum). Environment variable: MinDiskGB

.PARAMETER FreeSpaceGB
    Minimum free space on the system drive in GB. Whole number, 1 to 100000.
    Default 30. Environment variable: FreeSpaceGB

.PARAMETER IncludeWindows11
    true runs the eligibility checks on a PC that already runs Windows 11, for
    a dry run to test the checks. A real upgrade is refused on Windows 11.
    Default false. Environment variable: IncludeWindows11

.PARAMETER DryRun
    Default true for this script. false (with Approve) makes the change.
    Environment variable: DryRun

.PARAMETER Approve
    Must be update-windows-10-to-11 for DryRun=false to take effect.
    Environment variable: Approve

.PARAMETER MaxChanges
    The most changes one run may make (this script makes at most one). Default 25.
    Environment variable: MaxChanges

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\update-windows-10-to-11.ps1

    Dry run: checks the PC and says whether and how it would start the upgrade.

.EXAMPLE
    .\update-windows-10-to-11.ps1 -DryRun false -Approve update-windows-10-to-11 -MediaPath E:\

    Starts the upgrade from the mounted Windows 11 media on E: and leaves the restart to you.

.NOTES
    Name:        Windows 10 PC needs Windows 11 - check eligibility and start the in-place upgrade
    Slug:        update-windows-10-to-11
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Action
    Category:    03 Patching & Windows Update
    Platforms:   Windows 10
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, Windows 11 media or internet access to Microsoft
    Changes:     Starts the Windows 11 in-place upgrade (Windows Setup or the Installation Assistant), which later restarts the PC and replaces Windows 10
    Risk:        High
    Reboot:      May
    Runtime:     Under 1 minute to start; the upgrade then runs 30 to 90 minutes
    Answer:      "Started the Windows 11 upgrade from setup media; it waits for a restart"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/update-windows-10-to-11
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $MediaPath = '',
    [string] $AllowReboot = 'false',
    [string] $MinRamGB = '4',
    [string] $MinDiskGB = '64',
    [string] $FreeSpaceGB = '30',
    [string] $IncludeWindows11 = 'false',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'update-windows-10-to-11'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('MediaPath', 'AllowReboot', 'MinRamGB', 'MinDiskGB', 'FreeSpaceGB', 'IncludeWindows11')
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
$Windows11MinBuild = 22000
$Windows10MinBuild = 19041
$MinCpuCores = 2
$MinCpuMegahertz = 1000
$ClientProductType = 1
$AssistantUrl = 'https://go.microsoft.com/fwlink/?linkid=2171764'
$AssistantFileName = 'Windows11InstallationAssistant.exe'
$UpgradeProcessNames = @('Windows11InstallationAssistant', 'SetupHost', 'setupprep')
$PendingRebootKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
)
$StartCheckSeconds = 15

# ---- Functions ------------------------------------------------------------
function Get-TpmSummary {
    # Returns @{ Present; Enabled; Version } from Win32_Tpm.
    $summary = @{ Present = $false; Enabled = $false; Version = '' }
    try {
        $tpm = Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop | Select-Object -First 1
        if ($tpm) {
            $summary.Present = $true
            $summary.Enabled = [bool]$tpm.IsEnabled_InitialValue
            $summary.Version = (([string]$tpm.SpecVersion) -split ',')[0].Trim()
        }
    }
    catch { $null = $_ }
    return $summary
}

function Get-FirmwareSummary {
    # Returns @{ Uefi = $true/$false/$null; SecureBoot = $true/$false/$null }.
    # Confirm-SecureBootUEFI throws "not supported on this platform" on legacy BIOS.
    $summary = @{ Uefi = $null; SecureBoot = $null }
    try {
        $summary.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
        $summary.Uefi = $true
    }
    catch {
        # Legacy BIOS: PlatformNotSupportedException, status 0xC0000002 (any language).
        if ($_.Exception -is [System.PlatformNotSupportedException] -or $_.Exception.Message -match '0xC0000002|not supported on this platform') { $summary.Uefi = $false }
    }
    return $summary
}

function Get-SystemDiskGB {
    # Size in decimal GB of the physical disk that holds the system drive.
    param([Parameter(Mandatory = $true)][string] $DriveLetter)
    try {
        $partition = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
        return [math]::Round((Get-Disk -Number $partition.DiskNumber -ErrorAction Stop).Size / 1e9, 0)
    }
    catch {
        $logical = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '${DriveLetter}:'"
        return [math]::Round([double]$logical.Size / 1e9, 0)
    }
}

function Get-SystemDriveLetter {
    $root = [IO.Path]::GetPathRoot([Environment]::GetFolderPath('Windows'))
    if (-not $root) { return 'C' }
    return $root.Substring(0, 1)
}

function Test-MicrosoftSigned {
    # True when the file has a valid Authenticode signature from Microsoft Corporation.
    param([Parameter(Mandatory = $true)][string] $Path)
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ([string]$signature.Status -ne 'Valid') { return $false }
    if ($null -eq $signature.SignerCertificate) { return $false }
    return ([string]$signature.SignerCertificate.Subject -match 'O=Microsoft Corporation')
}

function Add-CheckRow {
    # One eligibility requirement as a row.
    param([string] $Requirement, [string] $Needs, [bool] $Pass, [string] $Found)
    $verdict = if ($Pass) { 'Pass' } else { 'Fail' }
    Add-OutpostRow -Values @{ Item = $Requirement; Change = "Needs $Needs"; Result = "${verdict}: $Found" }
}

function Get-UpgradeProcess {
    return @(Get-Process -Name $UpgradeProcessNames -ErrorAction SilentlyContinue)
}

function Start-UpgradeProcess {
    # Starts the upgrade and checks that it did not die at once. Throws when it did.
    param([Parameter(Mandatory = $true)][string] $FilePath, [Parameter(Mandatory = $true)][string[]] $Arguments)
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    $null = $process.Handle
    $waited = 0
    while ($waited -lt $StartCheckSeconds -and -not $process.HasExited) {
        Start-Sleep -Seconds 1
        $waited++
    }
    if ($process.HasExited -and $process.ExitCode -ne 0) {
        throw ('The upgrade program stopped at once with exit code {0} (0x{1}). See C:\$WINDOWS.~BT\Sources\Panther\setupact.log, if it exists, for the reason.' -f $process.ExitCode, $process.ExitCode.ToString('X'))
    }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        MediaPath        = Read-OutpostText -Name 'MediaPath'
        AllowReboot      = Read-OutpostBool -Name 'AllowReboot'
        MinRamGB         = Read-OutpostInt -Name 'MinRamGB' -Min 1 -Max 4096
        MinDiskGB        = Read-OutpostInt -Name 'MinDiskGB' -Min 1 -Max 100000
        FreeSpaceGB      = Read-OutpostInt -Name 'FreeSpaceGB' -Min 1 -Max 100000
        IncludeWindows11 = Read-OutpostBool -Name 'IncludeWindows11'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ([int]$osInfo.ProductType -ne $ClientProductType) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: Windows Server does not upgrade to Windows 11.'
    }
    $buildNumber = [int]$osInfo.BuildNumber
    $caption = ([string]$osInfo.Caption -replace '^Microsoft\s+', '').Trim()
    $displayVersion = ''
    try { $displayVersion = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion -ErrorAction Stop).DisplayVersion } catch { $displayVersion = '' }
    $osText = "$caption $displayVersion build $buildNumber".Replace('  ', ' ')

    # Already done?
    if ($buildNumber -ge $Windows11MinBuild) {
        if (-not $Config.IncludeWindows11) {
            Complete-OutpostRun -Status 'OK' -Answer "Already Windows 11 ($osText)."
        }
        if (-not $script:OutpostRun.DryRun) {
            Stop-OutpostRun -Message 'IncludeWindows11 is for dry runs only: this PC already runs Windows 11 and is never upgraded again. Remove IncludeWindows11, or set DryRun=true.'
        }
    }
    $running = @(Get-UpgradeProcess)
    if ($running.Count -gt 0) {
        Complete-OutpostRun -Status 'OK' -Answer "A Windows 11 upgrade is already running ($($running[0].ProcessName)); nothing started."
    }

    # Detect: eligibility
    Write-OutpostLine -Text "Checking this PC for the Windows 11 upgrade ($osText)."
    $failures = @()

    $is64BitOs = [Environment]::Is64BitOperatingSystem
    $isBuildOk = $buildNumber -ge $Windows10MinBuild
    $bitText = if ($is64BitOs) { '64-bit' } else { '32-bit' }
    Add-CheckRow -Requirement 'Operating system' -Needs '64-bit Windows 10 build 19041 or later' -Pass ($isBuildOk -and $is64BitOs) -Found "$osText, $bitText"
    if (-not $isBuildOk) { $failures += "Windows build $buildNumber is too old (update Windows 10 to version 2004 or later first)" }
    if (-not $is64BitOs) { $failures += '32-bit Windows (Windows 11 needs a 64-bit install)' }

    $firmware = Get-FirmwareSummary
    $isUefi = $firmware.Uefi -eq $true
    $uefiText = if ($firmware.Uefi -eq $true) { 'UEFI' } elseif ($firmware.Uefi -eq $false) { 'Legacy BIOS' } else { 'could not be read' }
    Add-CheckRow -Requirement 'UEFI firmware' -Needs 'UEFI (Secure Boot capable)' -Pass $isUefi -Found $uefiText
    if (-not $isUefi) { $failures += "firmware is $uefiText, UEFI needed" }
    $secureText = if ($firmware.SecureBoot -eq $true) { 'on' } elseif ($firmware.SecureBoot -eq $false) { 'off (can be turned on in firmware)' } else { 'not available' }
    Add-CheckRow -Requirement 'Secure Boot' -Needs 'capable, not necessarily on' -Pass $isUefi -Found $secureText

    $tpm = Get-TpmSummary
    $isTpmOk = $tpm.Present -and $tpm.Enabled -and $tpm.Version -eq '2.0'
    $tpmText = if (-not $tpm.Present) { 'no TPM found' } else { "TPM $($tpm.Version), " + $(if ($tpm.Enabled) { 'enabled' } else { 'disabled' }) }
    Add-CheckRow -Requirement 'TPM' -Needs 'TPM 2.0, enabled' -Pass $isTpmOk -Found $tpmText
    if (-not $isTpmOk) { $failures += $(if (-not $tpm.Present) { 'TPM 2.0 missing' } elseif ($tpm.Version -ne '2.0') { "TPM is version $($tpm.Version), 2.0 needed" } else { 'TPM is disabled' }) }

    $processors = @(Get-CimInstance -ClassName Win32_Processor)
    $cpuName = (($processors | Select-Object -First 1).Name -replace '\s+', ' ').Trim()
    $coreCount = [int](($processors | Measure-Object -Property NumberOfCores -Sum).Sum)
    $megahertz = [int](($processors | Select-Object -First 1).MaxClockSpeed)
    # Architecture 9 = x64, 12 = ARM64: the CPU itself, so 32-bit Windows on a 64-bit CPU is not blamed on the CPU.
    $isCpu64 = @(9, 12) -contains [int](($processors | Select-Object -First 1).Architecture)
    $isClockOk = $megahertz -eq 0 -or $megahertz -ge $MinCpuMegahertz
    $isCpuOk = $isCpu64 -and $coreCount -ge $MinCpuCores -and $isClockOk
    $clockText = if ($megahertz -eq 0) { 'clock not reported' } else { "$megahertz MHz" }
    Add-CheckRow -Requirement 'Processor' -Needs "64-bit, $MinCpuCores or more cores, 1 GHz or faster, on Microsoft's supported list (list not checked)" -Pass $isCpuOk -Found "$cpuName; $coreCount core(s); $clockText"
    if (-not $isCpuOk) { $failures += "processor fails 64-bit, $MinCpuCores cores or 1 GHz ($coreCount cores, $clockText)" }

    $ramBytes = [double](@(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue) | Measure-Object -Property Capacity -Sum).Sum
    if ($ramBytes -le 0) { $ramBytes = [double](Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory }
    $ramGB = [int][math]::Round($ramBytes / 1GB, 0)
    $isRamOk = $ramGB -ge $Config.MinRamGB
    Add-CheckRow -Requirement 'RAM' -Needs "$($Config.MinRamGB) GB" -Pass $isRamOk -Found "$ramGB GB"
    if (-not $isRamOk) { $failures += "RAM $ramGB GB (needs $($Config.MinRamGB))" }

    $systemLetter = Get-SystemDriveLetter
    $diskGB = [int](Get-SystemDiskGB -DriveLetter $systemLetter)
    $isDiskOk = $diskGB -ge $Config.MinDiskGB
    Add-CheckRow -Requirement 'System disk' -Needs "$($Config.MinDiskGB) GB" -Pass $isDiskOk -Found "$diskGB GB"
    if (-not $isDiskOk) { $failures += "system disk $diskGB GB (needs $($Config.MinDiskGB))" }

    $logicalDisk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID = '${systemLetter}:'"
    $freeGB = [int][math]::Floor([double]$logicalDisk.FreeSpace / 1GB)
    $isFreeOk = $freeGB -ge $Config.FreeSpaceGB
    Add-CheckRow -Requirement 'Free space' -Needs "$($Config.FreeSpaceGB) GB free on ${systemLetter}:" -Pass $isFreeOk -Found "$freeGB GB free"
    if (-not $isFreeOk) { $failures += "only $freeGB GB free on ${systemLetter}: (needs $($Config.FreeSpaceGB))" }

    $isRebootPending = $false
    foreach ($rebootKey in $PendingRebootKeys) { if (Test-Path -LiteralPath $rebootKey) { $isRebootPending = $true } }
    $pendingText = if ($isRebootPending) { 'a restart is waiting' } else { 'no restart waiting' }
    Add-CheckRow -Requirement 'Pending restart' -Needs 'no restart waiting' -Pass (-not $isRebootPending) -Found $pendingText
    if ($isRebootPending) { $failures += 'a restart is waiting (restart the PC first)' }

    if ($failures.Count -gt 0) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer ('Skipped: this PC cannot take Windows 11 yet: ' + ($failures -join '; '))
    }

    # Detect: where the upgrade comes from
    $useAssistant = $Config.MediaPath -eq ''
    $setupFile = ''
    if ($useAssistant) {
        if (-not $Config.AllowReboot) {
            $assistantProblem = 'No MediaPath is set, and the Windows 11 Installation Assistant restarts the PC by itself, so it needs AllowReboot=true. Set AllowReboot=true, or set MediaPath to a folder with Windows 11 setup.exe.'
            if ($script:OutpostRun.DryRun) { Complete-OutpostRun -Status 'SKIPPED' -Answer "Skipped: this PC can take Windows 11. $assistantProblem" }
            Stop-OutpostRun -Message $assistantProblem
        }
    }
    else {
        $setupFile = Join-Path -Path $Config.MediaPath -ChildPath 'setup.exe'
        if (-not (Test-Path -LiteralPath $setupFile -PathType Leaf)) {
            Stop-OutpostInput -Name 'MediaPath' -Value $Config.MediaPath -Expected 'a folder that contains Windows 11 setup.exe'
        }
        if (-not (Test-MicrosoftSigned -Path $setupFile)) {
            Stop-OutpostRun -Message "The file $setupFile is not signed by Microsoft, so it was not run. Check the Windows 11 media."
        }
    }
    $signedInUser = Get-OutpostSignedInUser
    if ($Config.AllowReboot -and $signedInUser) {
        Write-OutpostWarning -Text "$signedInUser is signed in. The upgrade will restart this PC without asking them."
    }

    # Act
    Assert-OutpostChangeLimit -Planned 1
    $sourceText = if ($useAssistant) { 'the Windows 11 Installation Assistant downloaded from Microsoft' } else { "Windows Setup from $($Config.MediaPath)" }
    $restartText = if ($Config.AllowReboot) { 'the upgrade restarts the PC itself' } else { 'Setup waits for a restart you start' }
    $null = Invoke-OutpostChange -Item 'Windows 11 upgrade' -Change "Start the in-place upgrade with $sourceText; $restartText" -Action {
        if ($useAssistant) {
            $workFolder = Join-Path -Path (Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Work') -ChildPath $OutpostScript.Slug
            $null = New-Item -Path $workFolder -ItemType Directory -Force
            Protect-OutpostFolder -Path $workFolder
            $assistantFile = Join-Path -Path $workFolder -ChildPath $AssistantFileName
            Write-OutpostLine -Text 'Downloading the Windows 11 Installation Assistant from Microsoft.'
            Invoke-WebRequest -Uri $AssistantUrl -OutFile $assistantFile -UseBasicParsing -TimeoutSec 300
            if (-not (Test-MicrosoftSigned -Path $assistantFile)) {
                Remove-Item -LiteralPath $assistantFile -Force -ErrorAction SilentlyContinue
                throw 'The downloaded Installation Assistant is not signed by Microsoft, so it was deleted and not run.'
            }
            Start-UpgradeProcess -FilePath $assistantFile -Arguments @('/QuietInstall', '/SkipEULA')
        }
        else {
            $setupArguments = @('/auto', 'upgrade', '/quiet', '/eula', 'accept')
            if (-not $Config.AllowReboot) { $setupArguments += '/noreboot' }
            Start-UpgradeProcess -FilePath $setupFile -Arguments $setupArguments
        }
    }

    # Verify (skipped in a dry run: nothing was started)
    if (-not $script:OutpostRun.DryRun) {
        Write-OutpostLine -Text 'Setup log: C:\$WINDOWS.~BT\Sources\Panther\setupact.log (appears once Setup is preparing).'
    }

    # Finish
    $answer = 'Started the Windows 11 upgrade ' + $(if ($useAssistant) { 'with the Installation Assistant' } else { 'from setup media' }) + '; ' + $(if ($Config.AllowReboot) { 'it will restart the PC itself' } else { 'it waits for a restart' })
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
