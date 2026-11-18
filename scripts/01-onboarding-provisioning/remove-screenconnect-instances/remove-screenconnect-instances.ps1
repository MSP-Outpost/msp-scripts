#Requires -Version 5.1
<#
.SYNOPSIS
    Removes every ScreenConnect client instance that is not on your allow-list: uninstall, service and folder.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. Every ScreenConnect server an agent was ever
    installed from leaves its own "ScreenConnect Client (<instance id>)"
    service, installed program and folder on the PC. This script finds every
    instance, keeps the ones whose id is in AllowedInstanceIds (YOUR servers)
    and removes all the others, in this order for each:

      * uninstalls the instance through its Windows Installer product code
        (msiexec /x {ProductCode} /qn /norestart);
      * stops and deletes its Windows service if the uninstall left it;
      * deletes its program folder if the uninstall left it.

    Before it deletes a service it backs up the service's registry key (reg
    export) under %ProgramData%\MSPOutpost\Backups\remove-screenconnect-instances.

    An allowed instance is never touched. AllowedInstanceIds is required: an
    empty list is refused, because it would remove YOUR OWN ScreenConnect too,
    unless you set RemoveAll true to remove every instance on purpose (then
    AllowedInstanceIds must be empty). If a removable instance is the agent
    running this script, the run stops before changing anything and tells you
    to add it to AllowedInstanceIds. This script is for Windows only: the
    macOS and Linux ScreenConnect clients have different names and are not
    handled.

    Find the instance ids first with get-remote-access-tools (the Evidence
    column says "Instance <id>") or in your ScreenConnect server (the
    ScreenConnect Client service name ends with the id in brackets).

    Risk is High: it changes nothing unless DryRun is false AND Approve is set
    to remove-screenconnect-instances. The dry run lists every instance and
    what would be removed. Exit codes 3010 and 1641 from an uninstaller count as
    success and mean a reboot is needed to finish: the answer says so and the
    script never reboots.

.PARAMETER AllowedInstanceIds
    Instance ids to KEEP, separated by commas, semicolons or new lines, for
    example 0123456789abcdef. The full service name "ScreenConnect Client
    (0123456789abcdef)" is accepted too. Required unless RemoveAll is true.
    Environment variable: AllowedInstanceIds

.PARAMETER RemoveAll
    true to remove every ScreenConnect instance, with an empty AllowedInstanceIds.
    Default false. Environment variable: RemoveAll

.PARAMETER TimeoutSeconds
    How long to wait for each uninstaller. Whole number, 30 to 7200. Default 600.
    Environment variable: TimeoutSeconds

.PARAMETER DryRun
    Defaults to true for this script. Set false AND Approve=remove-screenconnect-instances
    to make the changes. -WhatIf does the same as true. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\remove-screenconnect-instances.ps1 -AllowedInstanceIds 0123456789abcdef

    Dry run: lists the ScreenConnect instances that would be removed, keeping
    the one with that id.

.EXAMPLE
    .\remove-screenconnect-instances.ps1 -AllowedInstanceIds 0123456789abcdef -DryRun false -Approve remove-screenconnect-instances

    Removes every other ScreenConnect instance.

.NOTES
    Name:        Remove ScreenConnect instances that are not yours
    Slug:        remove-screenconnect-instances
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    01 Onboarding & provisioning
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Uninstalls ScreenConnect client instances not on the allow-list and deletes their leftover services and folders
    Risk:        High
    Reboot:      May
    Runtime:     1 to 5 minutes
    Answer:      "Removed 2 ScreenConnect instances: 1a2b3c4d5e6f7a8b, 9f8e7d6c5b4a3f2e; kept 1: 0123456789abcdef; reboot needed"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/remove-screenconnect-instances
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $AllowedInstanceIds = '',
    [string] $RemoveAll = 'false',
    [string] $TimeoutSeconds = '600',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'remove-screenconnect-instances'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('AllowedInstanceIds', 'RemoveAll', 'TimeoutSeconds')
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
# One ScreenConnect client = a service, an installed program and a program
# folder, each named "ScreenConnect Client (<instance id>)".
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$InstanceNamePattern = '^ScreenConnect Client \(([0-9A-Za-z]+)\)$'
$InstanceIdPattern = '^[0-9A-Za-z]{4,64}$'
$GuidPattern = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
$FolderPatterns = @(
    '%ProgramFiles(x86)%\ScreenConnect Client (*)',
    '%ProgramFiles%\ScreenConnect Client (*)'
)
$SuccessExitCodes = @(0, 3010, 1641)
$VerifyWaitSeconds = 60
$StopWaitSeconds = 30
$MaxAncestorDepth = 12
$MinFolderPathLength = 12

# ---- Functions ------------------------------------------------------------
function Expand-KnownFolder {
    # %ProgramFiles%, %ProgramFiles(x86)%, %ProgramData%, %WinDir% and %SystemDrive% from the
    # OS folder API, never from the environment (an agent may strip it). Unresolved = error.
    param([string] $Pattern)
    $windowsDir = [Environment]::GetFolderPath('Windows')
    if (-not $windowsDir) { $windowsDir = 'C:\Windows' }
    $drive = [IO.Path]::GetPathRoot($windowsDir).TrimEnd('\')
    $map = @{
        'ProgramFiles(x86)' = [Environment]::GetFolderPath('ProgramFilesX86')
        'ProgramFiles'      = [Environment]::GetFolderPath('ProgramFiles')
        'ProgramData'       = [Environment]::GetFolderPath('CommonApplicationData')
        'WinDir'            = $windowsDir
        'SystemDrive'       = $drive
    }
    if (-not $map['ProgramFiles(x86)']) { $map['ProgramFiles(x86)'] = $drive + '\Program Files (x86)' }
    if (-not $map['ProgramFiles']) { $map['ProgramFiles'] = $drive + '\Program Files' }
    if (-not $map['ProgramData']) { $map['ProgramData'] = $drive + '\ProgramData' }
    $text = $Pattern
    foreach ($name in @($map.Keys)) {
        $text = $text -replace ('(?i)%' + [regex]::Escape($name) + '%'), ([string]$map[$name]).Replace('$', '$$')
    }
    if ($text.Contains('%')) { throw "Could not resolve the folder $Pattern without the environment; stopping so nothing is guessed." }
    return $text
}

function Get-RegistryValue {
    # Strict mode throws on a missing property, so read through the property bag.
    param($Item, [string] $PropertyName)
    $property = $Item.PSObject.Properties[$PropertyName]
    if ($property) { return $property.Value }
    return $null
}

function Get-SystemTool {
    # A program in System32 without trusting the environment.
    param([string] $FileName)
    return (Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath $FileName)
}

function ConvertTo-HklmPath {
    # A registry PSPath as the HKLM:\ form Backup-OutpostItem takes.
    param([string] $KeyPath)
    return ($KeyPath -replace '^Microsoft\.PowerShell\.Core\\Registry::HKEY_LOCAL_MACHINE\\', 'HKLM:\')
}

function Get-InstalledApplication {
    # Machine-wide installed programs, system components and updates left out.
    $applications = @()
    foreach ($keyPattern in $UninstallKeys) {
        foreach ($item in @(Get-ItemProperty -Path $keyPattern -ErrorAction SilentlyContinue)) {
            $displayName = Get-RegistryValue -Item $item -PropertyName 'DisplayName'
            if (-not $displayName) { continue }
            if ((Get-RegistryValue -Item $item -PropertyName 'SystemComponent') -eq 1) { continue }
            if (Get-RegistryValue -Item $item -PropertyName 'ParentKeyName') { continue }
            if (@('Update', 'Hotfix', 'Security Update') -contains [string](Get-RegistryValue -Item $item -PropertyName 'ReleaseType')) { continue }
            $applications += [pscustomobject]@{
                KeyPath              = [string]$item.PSPath
                KeyName              = [string]$item.PSChildName
                DisplayName          = [string]$displayName
                DisplayVersion       = [string](Get-RegistryValue -Item $item -PropertyName 'DisplayVersion')
                UninstallString      = [string](Get-RegistryValue -Item $item -PropertyName 'UninstallString')
                QuietUninstallString = [string](Get-RegistryValue -Item $item -PropertyName 'QuietUninstallString')
                IsWindowsInstaller   = ((Get-RegistryValue -Item $item -PropertyName 'WindowsInstaller') -eq 1)
                IsBundle             = [bool](Get-RegistryValue -Item $item -PropertyName 'BundleCachePath')
                IsNoRemove           = ((Get-RegistryValue -Item $item -PropertyName 'NoRemove') -eq 1)
            }
        }
    }
    return $applications
}

function Get-ExecutablePath {
    # The program inside a service command line: quoted, or up to the first ".exe".
    param([string] $CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return '' }
    $text = $CommandLine.Trim()
    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -gt 0) { return $text.Substring(1, $end - 1) }
        return $text.TrimStart('"')
    }
    $match = [regex]::Match($text, '^(.+?\.exe)(\s|$)', 'IgnoreCase')
    if ($match.Success) { return $match.Groups[1].Value }
    return $text
}

function Invoke-Uninstaller {
    # Runs one uninstaller hidden and returns its exit code.
    param($Plan, [int] $WaitSeconds)
    $startArguments = @{ FilePath = $Plan.File; PassThru = $true; WindowStyle = 'Hidden' }
    if ($Plan.Arguments -ne '') { $startArguments['ArgumentList'] = $Plan.Arguments }
    $process = Start-Process @startArguments
    $null = $process.Handle
    if (-not $process.WaitForExit($WaitSeconds * 1000)) {
        throw "The uninstaller did not finish within $WaitSeconds seconds (process id $($process.Id) is still running). Wait for it, then run this script again."
    }
    return $process.ExitCode
}

function Get-AncestorProcess {
    # This script's own process and every parent above it: id and program path.
    $chain = @()
    $current = [int]$PID
    $seen = @()
    for ($depth = 0; $depth -lt $MaxAncestorDepth -and $current -gt 0; $depth++) {
        $rows = @(Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$current" -Property ParentProcessId, ExecutablePath)
        if ($rows.Count -eq 0) { break }
        $seen += $current
        $chain += [pscustomobject]@{ Id = $current; Path = [string]$rows[0].ExecutablePath }
        $next = [int]$rows[0].ParentProcessId
        if ($seen -contains $next) { break }
        $current = $next
    }
    return $chain
}

function Test-PathUnder {
    # True when Path is inside Folder (case-insensitive, whole folder names).
    param([string] $Path, [string] $Folder)
    if ([string]::IsNullOrEmpty($Path) -or [string]::IsNullOrEmpty($Folder)) { return $false }
    return ($Path.TrimEnd('\') + '\').StartsWith($Folder.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Stop-ServiceHard {
    # Stops a service; if it will not stop, ends its own process (never a shared one).
    param([string] $ServiceName)
    $controller = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $controller) { return }
    if ($controller.Status -eq 'Stopped') { return }
    try { Stop-Service -Name $ServiceName -Force }
    catch { Write-OutpostWarning -Text "Stop request for $ServiceName failed: $($_.Exception.Message)" }
    $deadline = (Get-Date).AddSeconds($StopWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        $controller = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if (-not $controller -or $controller.Status -eq 'Stopped') { return }
        Start-Sleep -Seconds 1
    }
    $filter = "Name='" + ($ServiceName -replace "'", "''") + "'"
    $cim = @(Get-CimInstance -ClassName Win32_Service -Filter $filter)
    $processId = 0
    if ($cim.Count -gt 0) { $processId = [int]$cim[0].ProcessId }
    if ($processId -le 0) { throw "$ServiceName did not stop within $StopWaitSeconds seconds. Restart the computer and run this script again." }
    $sharedWith = @(Get-CimInstance -ClassName Win32_Service -Filter "ProcessId=$processId" | Where-Object { $_.Name -ne $ServiceName -and $_.State -ne 'Stopped' })
    if ($sharedWith.Count -gt 0) { throw "$ServiceName did not stop, and its process (id $processId) is shared with running services, so it was not ended. Restart the computer." }
    Stop-Process -Id $processId -Force
    Start-Sleep -Seconds 2
}

function Remove-ServiceByName {
    param([string] $ServiceName)
    Stop-ServiceHard -ServiceName $ServiceName
    $null = & (Get-SystemTool -FileName 'sc.exe') delete $ServiceName
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1072) { throw "sc delete $ServiceName failed with exit code $LASTEXITCODE." }
}

function Test-FolderRemovable {
    # A last guard: only a real program folder is ever deleted.
    param([string] $Path)
    if ($Path.Length -lt $MinFolderPathLength) { return $false }
    foreach ($known in @('ProgramFiles', 'ProgramFilesX86', 'CommonApplicationData', 'Windows', 'System')) {
        $folder = [Environment]::GetFolderPath($known)
        if ($folder -and $Path.TrimEnd('\') -ieq $folder.TrimEnd('\')) { return $false }
    }
    return $true
}

function Remove-ProgramFolder {
    param([string] $Path, $Ancestors)
    if (-not (Test-FolderRemovable -Path $Path)) { throw "Refusing to delete $Path." }
    $ancestorIds = @($Ancestors | ForEach-Object { $_.Id })
    $lastError = ''
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        # Stop programs still running from the folder (never this script's own chain).
        foreach ($process in @(Get-CimInstance -ClassName Win32_Process -Property ProcessId, ExecutablePath)) {
            $processPath = [string]$process.ExecutablePath
            if ($processPath -ne '' -and (Test-PathUnder -Path $processPath -Folder $Path) -and $ancestorIds -notcontains [int]$process.ProcessId) {
                Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction SilentlyContinue
            }
        }
        try {
            if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
            return
        }
        catch { $lastError = $_.Exception.Message; Start-Sleep -Seconds 2 }
    }
    throw "Could not delete $Path ($lastError). A file is probably locked: restart the computer and run this script again."
}

function Get-Plural {
    param([int] $Count, [string] $Word)
    if ($Count -eq 1) { return "$Count $Word" }
    return "$Count ${Word}s"
}

function Get-InstanceIdFromText {
    # The instance id in "ScreenConnect Client (id)", or the text itself when it is a bare id.
    param([string] $Text)
    $match = [regex]::Match($Text.Trim(), $InstanceNamePattern)
    if ($match.Success) { return $match.Groups[1].Value }
    return $Text.Trim()
}

function Get-ScreenConnectInstance {
    # Every instance on this PC with its service, installed programs and folders.
    $services = @(Get-CimInstance -ClassName Win32_Service | Where-Object { $_.Name -match $InstanceNamePattern })
    $programs = @(Get-InstalledApplication | Where-Object { $_.DisplayName -match $InstanceNamePattern })
    $folders = @()
    foreach ($pattern in $FolderPatterns) {
        foreach ($found in @(Get-Item -Path ((Expand-KnownFolder -Pattern $pattern)) -Force -ErrorAction SilentlyContinue)) {
            if ($found.PSIsContainer -and $found.Name -match $InstanceNamePattern -and $folders -notcontains $found.FullName) { $folders += $found.FullName }
        }
    }
    $ids = @()
    foreach ($service in $services) { $ids += (Get-InstanceIdFromText -Text $service.Name) }
    foreach ($program in $programs) { $ids += (Get-InstanceIdFromText -Text $program.DisplayName) }
    foreach ($folder in $folders) { $ids += (Get-InstanceIdFromText -Text (Split-Path -Path $folder -Leaf)) }
    $instances = @()
    $seen = @{}
    foreach ($id in $ids) {
        $lower = $id.ToLowerInvariant()
        if ($seen.ContainsKey($lower)) { continue }
        $seen[$lower] = $true
        $instances += [pscustomobject]@{
            Id       = $id
            Services = @($services | Where-Object { (Get-InstanceIdFromText -Text $_.Name) -ieq $id })
            Programs = @($programs | Where-Object { (Get-InstanceIdFromText -Text $_.DisplayName) -ieq $id })
            Folders  = @($folders | Where-Object { (Get-InstanceIdFromText -Text (Split-Path -Path $_ -Leaf)) -ieq $id })
        }
    }
    return $instances
}

function Get-InstanceStepCount {
    param($Instance)
    return ($Instance.Programs.Count + $Instance.Services.Count + $Instance.Folders.Count)
}

function Get-InstanceSelfReason {
    # Why removing this instance would cut off the process that runs this script.
    param($Instance, $Ancestors)
    $reasons = @()
    if (@($Ancestors).Count -lt 2) { $reasons += 'this script''s own process chain could not be read, so it cannot be shown that the instance is not running it' }
    $ancestorIds = @($Ancestors | ForEach-Object { $_.Id })
    foreach ($service in $Instance.Services) {
        if ([int]$service.ProcessId -gt 0 -and $ancestorIds -contains [int]$service.ProcessId) {
            $reasons += "service $($service.Name) runs process $($service.ProcessId), which is running this script"
            continue
        }
        $servicePath = Get-ExecutablePath -CommandLine ([string]$service.PathName)
        foreach ($ancestor in $Ancestors) {
            if ($servicePath -ne '' -and $ancestor.Path -ne '' -and $ancestor.Path -ieq $servicePath) {
                $reasons += "the program of service $($service.Name) ($servicePath) is in this script's own process chain"
                break
            }
        }
    }
    foreach ($folder in $Instance.Folders) {
        foreach ($ancestor in $Ancestors) {
            if (Test-PathUnder -Path $ancestor.Path -Folder $folder) { $reasons += "this script runs under $($ancestor.Path), inside $folder"; break }
        }
    }
    return @($reasons | Select-Object -Unique)
}

function Get-ProductCode {
    # The Windows Installer product code of an installed program, or ''.
    param($Application)
    if ($Application.KeyName -match "^$GuidPattern`$") { return $Application.KeyName }
    if ($Application.UninstallString -match 'msiexec') {
        $found = [regex]::Match($Application.UninstallString, $GuidPattern)
        if ($found.Success) { return $found.Value }
    }
    return ''
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        AllowedInstanceIds = @(Read-OutpostList -Name 'AllowedInstanceIds')
        RemoveAll          = Read-OutpostBool -Name 'RemoveAll'
        TimeoutSeconds     = Read-OutpostInt -Name 'TimeoutSeconds' -Min 30 -Max 7200
    }
    $allowedIds = @($Config.AllowedInstanceIds | ForEach-Object { Get-InstanceIdFromText -Text $_ })
    foreach ($allowedId in $allowedIds) {
        if ($allowedId -notmatch $InstanceIdPattern) {
            Stop-OutpostInput -Name 'AllowedInstanceIds' -Value $allowedId -Expected 'instance ids of 4 to 64 letters and digits, such as 0123456789abcdef (no wildcards)'
        }
    }
    if ($allowedIds.Count -eq 0 -and -not $Config.RemoveAll) {
        Stop-OutpostRun -Message 'Required input AllowedInstanceIds is not set, so this run would remove EVERY ScreenConnect instance, including yours. Set the argument -AllowedInstanceIds (or the environment variable AllowedInstanceIds) to the ids to keep, or set RemoveAll true to remove them all on purpose.'
    }
    if ($allowedIds.Count -gt 0 -and $Config.RemoveAll) {
        Stop-OutpostRun -Message 'RemoveAll is true but AllowedInstanceIds is not empty. Clear one of them: RemoveAll removes every instance, AllowedInstanceIds keeps some.'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }

    # Detect
    Write-OutpostLine -Text 'Looking for ScreenConnect client instances in services, installed programs and program folders.'
    $instances = @(Get-ScreenConnectInstance)
    $kept = @($instances | Where-Object { $allowedIds -contains $_.Id })
    $targets = @($instances | Where-Object { $allowedIds -notcontains $_.Id })
    foreach ($allowedId in $allowedIds) {
        if (@($instances | Where-Object { $_.Id -ieq $allowedId }).Count -eq 0) {
            Write-OutpostWarning -Text "Allowed instance $allowedId is not installed on this PC."
        }
    }
    $keptText = ''
    if ($kept.Count -gt 0) { $keptText = "; kept $($kept.Count): " + (@($kept | ForEach-Object { $_.Id }) -join ', ') }
    if ($targets.Count -eq 0) {
        if ($instances.Count -eq 0) { Complete-OutpostRun -Status 'OK' -Answer 'Already clean: no ScreenConnect instances are installed.' }
        Complete-OutpostRun -Status 'OK' -Answer ("Already clean: no ScreenConnect instances besides the allowed ones" + $keptText)
    }
    Write-OutpostLine -Text ("Found {0} instance(s); {1} to remove, {2} allowed." -f $instances.Count, $targets.Count, $kept.Count)

    $ancestors = @(Get-AncestorProcess)
    $selfProblems = @()
    foreach ($target in $targets) {
        $reasons = @(Get-InstanceSelfReason -Instance $target -Ancestors $ancestors)
        if ($reasons.Count -gt 0) { $selfProblems += "instance $($target.Id): $($reasons -join '; ')" }
    }
    if ($selfProblems.Count -gt 0) {
        Stop-OutpostRun -Message ("A ScreenConnect instance that is not on the allow-list is the agent running this script (" + ($selfProblems -join ' | ') + "). Add its id to AllowedInstanceIds, or run this script from another tool.")
    }

    $problems = @()
    foreach ($target in $targets) {
        foreach ($program in $target.Programs) {
            if ((Get-ProductCode -Application $program) -eq '') { $problems += "ScreenConnect instance $($target.Id) has an installed-programs entry without a Windows Installer product code, so it cannot be uninstalled silently. Remove it by hand." }
            elseif ($program.IsNoRemove) { $problems += "ScreenConnect instance $($target.Id) is marked as not removable (NoRemove). Remove it by hand if you are sure." }
        }
    }
    if ($problems.Count -gt 0) { Stop-OutpostRun -Message ($problems -join ' ') }
    $planned = 0
    foreach ($target in $targets) { $planned += (Get-InstanceStepCount -Instance $target) }
    Assert-OutpostChangeLimit -Planned $planned

    # Act: instance by instance; an instance whose uninstall failed is not touched further.
    $failures = @()
    $removedIds = @()
    $flow = @{ RebootNeeded = $false }
    foreach ($target in $targets) {
        $instanceId = [string]$target.Id
        $failedHere = $false
        foreach ($program in $target.Programs) {
            $productCode = Get-ProductCode -Application $program
            try {
                $null = Invoke-OutpostChange -Item "ScreenConnect Client ($instanceId)" -Change 'Uninstall (MSI)' -Action {
                    $plan = [pscustomobject]@{ File = (Get-SystemTool -FileName 'msiexec.exe'); Arguments = "/x $productCode /qn /norestart" }
                    $exitCode = Invoke-Uninstaller -Plan $plan -WaitSeconds $Config.TimeoutSeconds
                    if ($exitCode -eq 3010 -or $exitCode -eq 1641) { $flow.RebootNeeded = $true }
                    if ($SuccessExitCodes -notcontains $exitCode) {
                        if (Test-Path -LiteralPath $program.KeyPath) { throw "The uninstaller (msiexec) exited with code $exitCode and the program is still installed." }
                        Write-OutpostWarning -Text "The uninstaller of instance $instanceId exited with code $exitCode but the program is gone."
                    }
                }
            }
            catch { $failures += "Instance ${instanceId}: $($_.Exception.Message)"; $failedHere = $true }
        }
        if ($failedHere) { continue }

        # The uninstaller removes the service and folder itself; look again before removing leftovers.
        $current = $target
        if (-not $script:OutpostRun.DryRun) {
            $current = @(Get-ScreenConnectInstance | Where-Object { $_.Id -ieq $instanceId }) | Select-Object -First 1
        }
        if ($current) {
            foreach ($service in $current.Services) {
                $serviceName = [string]$service.Name
                try {
                    $null = Invoke-OutpostChange -Item "Service $serviceName" -Change 'Stop and delete service' -Action {
                        $null = Backup-OutpostItem -Path ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $serviceName)
                        Remove-ServiceByName -ServiceName $serviceName
                    }
                }
                catch { $failures += "Service ${serviceName}: $($_.Exception.Message)"; $failedHere = $true }
            }
            foreach ($folder in $current.Folders) {
                try {
                    $null = Invoke-OutpostChange -Item "Folder $folder" -Change 'Delete program folder' -Action {
                        Remove-ProgramFolder -Path $folder -Ancestors $ancestors
                    }
                }
                catch { $failures += "Folder ${folder}: $($_.Exception.Message)"; $failedHere = $true }
            }
        }
        if (-not $failedHere) { $removedIds += $instanceId }
    }

    # Verify (skipped in a dry run: nothing was changed)
    if (-not $script:OutpostRun.DryRun) {
        $deadline = (Get-Date).AddSeconds($VerifyWaitSeconds)
        do {
            $leftover = @(Get-ScreenConnectInstance | Where-Object { $allowedIds -notcontains $_.Id -and $removedIds -contains $_.Id })
            if ($leftover.Count -eq 0) { break }
            Start-Sleep -Seconds 3
        } while ((Get-Date) -lt $deadline)
        foreach ($item in $leftover) { $failures += "Instance $($item.Id) is still present after the removal." }
        # An allowed instance must be exactly as it was.
        foreach ($keptInstance in $kept) {
            $now = @(Get-ScreenConnectInstance | Where-Object { $_.Id -ieq $keptInstance.Id })
            if ($now.Count -eq 0) { $failures += "Allowed instance $($keptInstance.Id) is no longer present. Check the change log." }
        }
    }
    if ($failures.Count -gt 0) {
        Stop-OutpostRun -Message ('Not fully removed: ' + ($failures -join ' | ') + ' Check the change log, restart the computer if something is locked, then run again.')
    }

    # Finish
    $plural = if ($targets.Count -eq 1) { '' } else { 's' }
    $answer = "Removed $($targets.Count) ScreenConnect instance${plural}: " + (@($targets | ForEach-Object { $_.Id }) -join ', ') + $keptText
    if ($flow.RebootNeeded) { $answer += '; reboot needed' }
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
