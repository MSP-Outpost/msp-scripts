#Requires -Version 5.1
<#
.SYNOPSIS
    Ransomware containment: blocks all network traffic except to your RMM, EDR and DNS, using Windows Firewall.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS AND CAN CUT THIS PC OFF THE NETWORK. It isolates
    a PC you suspect is infected while keeping your management tools working:

      * saves the firewall policy first (netsh advfirewall export, kept in
        %ProgramData%\MSPOutpost\Backups\enable-network-isolation) and the
        current settings of the Domain, Private and Public profiles
        (%ProgramData%\MSPOutpost\Isolation\state.json);
      * creates the Windows Firewall rule group "MSP Outpost Isolation": one
        rule that allows outbound traffic to every address in AllowedHosts, and
        one outbound rule for each program in AllowedPrograms;
      * on all three profiles switches the firewall on, sets the default
        outbound action to Block, and blocks inbound traffic including the
        inbound allow rules (like the "Block all incoming connections" setting).

    Safeguards against locking yourself out:
      * the RMM agent that started this script (the service program found in its
        own process chain) is allowed automatically, in addition to
        AllowedPrograms. A real run with no agent found and AllowedPrograms empty
        stops with an error before changing anything;
      * BEFORE isolating, the FIRST host in AllowedHosts must answer (ping, a TCP
        connect or refusal on 443, 80 or 53, or a DNS reply; at most 15 seconds).
        If it does not, nothing is changed;
      * AFTER isolating, the same test runs again (at most 30 seconds). If it
        fails, a first isolation rolls back at once (rule group removed, saved
        settings restored) and ends in ERROR. A failed RERUN leaves the isolation
        that was already in place and only removes its own new rules;
      * AutoUndoMinutes above 0 registers a one-shot SYSTEM scheduled task
        (MSPOutpost-IsolationAutoUndo) that undoes the isolation by itself after
        that many minutes, so a mistake cannot be permanent. The answer says so.
        disable-network-isolation removes the task.

    Windows keeps every ENABLED outbound allow rule in force under default Block,
    which would leave most programs connected. So the script also switches off
    every other enabled outbound allow rule in this PC's own policy (not the two
    DHCP client rules), lists them in the saved state, and the undo switches
    exactly those on again. Group Policy rules cannot be switched off from here.

    Host names (FQDNs) are resolved to IP addresses when the script runs, with
    the DNS the PC has at that moment, and the firewall rules hold those
    addresses. If a service later moves to other addresses, the rules do not
    follow: run this script again (it rebuilds the rules). Include your DNS
    servers in AllowedHosts.

    A third-party firewall registered in Windows Security Center makes this
    script end SKIPPED: Windows Firewall rules would mean nothing there. What it
    does NOT block: the DHCP client rules stay on; traffic
    to the loopback address is never filtered by Windows Firewall; and a domain
    Group Policy that controls the firewall can override these settings (the
    run then fails its own check, rolls back and says so). It does not disable
    network adapters, and it leaves signed-in users signed in: they lose
    network access except to the allowed hosts. Servers are refused unless
    IncludeServers is true.

    Undo with disable-network-isolation. Running this script again with the
    same inputs and the isolation in place changes nothing and says so.

    Risk is High: it changes nothing unless DryRun is false AND Approve is set
    to enable-network-isolation. The dry run resolves the host names and lists
    every rule it would create.

.PARAMETER AllowedHosts
    Where this PC may still send traffic: host names (FQDNs), IP addresses or
    CIDR ranges of your RMM, EDR and DNS servers, separated by commas,
    semicolons or new lines. The FIRST entry must be one host name or IP address
    (it is used for the test connection). Required.
    Environment variable: AllowedHosts

.PARAMETER AllowedPrograms
    Full paths of programs allowed to use the network to any address (for
    example the RMM agent executables), separated by commas, semicolons or new
    lines. Each file must exist. Default empty.
    Environment variable: AllowedPrograms

.PARAMETER AutoUndoMinutes
    0 (default) = no automatic undo. 1 to 1440 = a scheduled task removes the
    isolation by itself after that many minutes. Environment variable: AutoUndoMinutes

.PARAMETER IncludeServers
    true to allow isolating a Windows Server or domain controller. Default false.
    Environment variable: IncludeServers

.PARAMETER DryRun
    Defaults to true for this script. Set false AND Approve=enable-network-isolation
    to isolate the PC. -WhatIf does the same as true. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\enable-network-isolation.ps1 -AllowedHosts "rmm.example.com,192.168.1.1" -AllowedPrograms "C:\Program Files\NinjaRMMAgent\NinjaRMMAgent.exe"

    Dry run: shows the rules that would isolate the PC but keep the RMM.

.EXAMPLE
    .\enable-network-isolation.ps1 -AllowedHosts "192.168.1.1,rmm.example.com" -DryRun false -Approve enable-network-isolation

    Isolates the PC, keeping traffic to the DNS server 192.168.1.1 and the RMM.

.NOTES
    Name:        Isolate a PC from the network but keep the RMM
    Slug:        enable-network-isolation
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    05 AV / EDR & incident response
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, Windows Firewall service running and no third-party firewall
    Changes:     Creates the Windows Firewall rule group MSP Outpost Isolation, blocks all other inbound and outbound traffic on all profiles, switches off other enabled outbound allow rules, saves the old firewall settings, optionally registers a scheduled task that undoes it
    Risk:        High
    Reboot:      Never
    Runtime:     10 to 60 seconds
    Answer:      "Isolated: traffic allowed only to 2 address(es) (192.168.1.1) and 1 program(s); 140 other outbound rule(s) disabled; test connection ok (192.168.1.1 via dns)"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/enable-network-isolation
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $AllowedHosts = '',
    [string] $AllowedPrograms = '',
    [string] $AutoUndoMinutes = '0',
    [string] $IncludeServers = 'false',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'enable-network-isolation'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('AllowedHosts', 'AllowedPrograms', 'AutoUndoMinutes', 'IncludeServers')
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
$GroupName = 'MSP Outpost Isolation'
$HostRuleNamePrefix = 'MSPOutpostIsolation-Hosts-'
$ProgramRuleNamePrefix = 'MSPOutpostIsolation-Program-'
$AutoUndoTaskName = 'MSPOutpost-IsolationAutoUndo'
$WindowsFirewallGuid = '{D68DDC3A-831F-4fae-9E44-DA132C1ACF46}'
$KeepRuleNames = @('CoreNet-DHCP-Out', 'CoreNet-DHCPV6-Out')
$PreCheckSeconds = 15
$PostCheckSeconds = 30
$MaxAncestorDepth = 12
$ProfileNames = @('Domain', 'Private', 'Public')
$ProbeMilliseconds = 2000
$ProbeTcpPorts = @(443, 80, 53)
$HostNamePattern = '^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'
$Ipv4Pattern = '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'

# ---- Functions ------------------------------------------------------------
function Get-SystemTool {
    # A program in System32 without trusting the environment.
    param([string] $FileName)
    return (Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath $FileName)
}

function Get-StatePath {
    # Where enable-network-isolation keeps the settings it must restore.
    return (Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Isolation\state.json')
}

function Read-IsolationState {
    # The saved state object, or $null when isolation was never enabled by this script.
    $path = Get-StatePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Get-FirewallProfileState {
    # The three profiles as plain text values, ready to be saved and set again.
    # PersistentStore = what this PC's own settings say (saved and restored);
    # ActiveStore = what is really in force, Group Policy and all (verified).
    param([string] $Store = 'PersistentStore')
    $rows = @()
    foreach ($profileItem in @(Get-NetFirewallProfile -Profile $ProfileNames -PolicyStore $Store)) {
        $rows += [pscustomobject]@{
            Name                  = [string]$profileItem.Name
            Enabled               = [string]$profileItem.Enabled
            DefaultInboundAction  = [string]$profileItem.DefaultInboundAction
            DefaultOutboundAction = [string]$profileItem.DefaultOutboundAction
            AllowInboundRules     = [string]$profileItem.AllowInboundRules
        }
    }
    return $rows
}

function Get-IsolationRule {
    return @(Get-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue)
}

function Set-FirewallProfileState {
    # Sets each saved profile back exactly as it was.
    param($Profiles)
    foreach ($saved in @($Profiles)) {
        Set-NetFirewallProfile -Name ([string]$saved.Name) -Enabled ([string]$saved.Enabled) -DefaultInboundAction ([string]$saved.DefaultInboundAction) -DefaultOutboundAction ([string]$saved.DefaultOutboundAction) -AllowInboundRules ([string]$saved.AllowInboundRules)
    }
}

function Get-DnsQueryBytes {
    # A minimal DNS question for "example.com" type A.
    $bytes = New-Object -TypeName System.Collections.ArrayList
    foreach ($value in @(0x12, 0x34, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)) { [void]$bytes.Add([byte]$value) }
    foreach ($label in @('example', 'com')) {
        [void]$bytes.Add([byte]$label.Length)
        foreach ($character in $label.ToCharArray()) { [void]$bytes.Add([byte][int]$character) }
    }
    foreach ($value in @(0x00, 0x00, 0x01, 0x00, 0x01)) { [void]$bytes.Add([byte]$value) }
    return [byte[]]$bytes.ToArray()
}

function Test-AddressReachable {
    # Names the first way one address answers (ping, a TCP port that connects or
    # refuses, a DNS reply), or '' when nothing answers or the deadline passes. A
    # refusal still proves the packets get through.
    param([string] $Address, [datetime] $Deadline)
    $ip = [Net.IPAddress]::Parse($Address)
    try {
        $reply = (New-Object -TypeName Net.NetworkInformation.Ping).Send($ip, $ProbeMilliseconds)
        if ($reply.Status -eq [Net.NetworkInformation.IPStatus]::Success) { return 'ping' }
    }
    catch { $null = $_ }
    foreach ($port in $ProbeTcpPorts) {
        if ((Get-Date) -gt $Deadline) { return '' }
        $client = New-Object -TypeName Net.Sockets.TcpClient -ArgumentList $ip.AddressFamily
        try {
            $pending = $client.BeginConnect($ip, $port, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne($ProbeMilliseconds)) {
                try { $client.EndConnect($pending); return "tcp $port" }
                catch [Net.Sockets.SocketException] {
                    if ($_.Exception.SocketErrorCode -eq [Net.Sockets.SocketError]::ConnectionRefused) { return "tcp $port refused" }
                }
            }
        }
        catch { $null = $_ }
        finally { $client.Close() }
    }
    if ((Get-Date) -gt $Deadline) { return '' }
    $udp = New-Object -TypeName Net.Sockets.UdpClient -ArgumentList $ip.AddressFamily
    try {
        $udp.Client.ReceiveTimeout = $ProbeMilliseconds
        $query = Get-DnsQueryBytes
        [void]$udp.Send($query, $query.Length, $ip.ToString(), 53)
        $remote = New-Object -TypeName Net.IPEndPoint -ArgumentList $ip, 0
        $answer = $udp.Receive([ref]$remote)
        if ($answer.Length -gt 0) { return 'dns' }
    }
    catch { $null = $_ }
    finally { $udp.Close() }
    return ''
}

function Test-HostReachable {
    # Tries each address, twice over, within MaxSeconds in all; returns "<address> via <way>" or ''.
    param([string[]] $Addresses, [int] $MaxSeconds = 30)
    $deadline = (Get-Date).AddSeconds($MaxSeconds)
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        foreach ($address in $Addresses) {
            if ((Get-Date) -gt $deadline) { return '' }
            $way = Test-AddressReachable -Address $address -Deadline $deadline
            if ($way -ne '') { return "$address via $way" }
        }
        if ($attempt -eq 1 -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    }
    return ''
}

function Resolve-HostAddress {
    # IPv4 and IPv6 addresses of a name (link-local IPv6 left out), as text.
    param([string] $Name)
    $addresses = @()
    foreach ($found in @([Net.Dns]::GetHostAddresses($Name))) {
        if ($found.IsIPv6LinkLocal) { continue }
        $text = $found.ToString()
        if ($addresses -notcontains $text) { $addresses += $text }
    }
    return $addresses
}

function Get-AutoUndoCode {
    # The script the one-shot SYSTEM task runs: the same undo, from the saved state.
    return @(
        '$ErrorActionPreference = ''Continue''',
        '$stateFile = Join-Path -Path ([Environment]::GetFolderPath(''CommonApplicationData'')) -ChildPath ''MSPOutpost\Isolation\state.json''',
        '$saved = $null',
        'if (Test-Path -LiteralPath $stateFile) { $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json }',
        'Remove-NetFirewallRule -Group ''MSP Outpost Isolation'' -ErrorAction SilentlyContinue',
        'if ($saved) {',
        '    foreach ($p in @($saved.Profiles)) { Set-NetFirewallProfile -Name ([string]$p.Name) -Enabled ([string]$p.Enabled) -DefaultInboundAction ([string]$p.DefaultInboundAction) -DefaultOutboundAction ([string]$p.DefaultOutboundAction) -AllowInboundRules ([string]$p.AllowInboundRules) }',
        '    if (@($saved.DisabledRules).Count -gt 0) { Enable-NetFirewallRule -Name @($saved.DisabledRules) -ErrorAction SilentlyContinue }',
        '    Remove-Item -LiteralPath $stateFile -Force',
        '}',
        'else { Set-NetFirewallProfile -Profile Domain,Private,Public -DefaultOutboundAction Allow -AllowInboundRules True }',
        'Unregister-ScheduledTask -TaskName ''MSPOutpost-IsolationAutoUndo'' -Confirm:$false -ErrorAction SilentlyContinue',
        'Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue'
    )
}

function Remove-AutoUndo {
    # The auto-undo task and its script, when they exist.
    Unregister-ScheduledTask -TaskName $AutoUndoTaskName -Confirm:$false -ErrorAction SilentlyContinue
    $file = Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Isolation\auto-undo.ps1'
    if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force }
}

function Undo-Isolation {
    # Rollback and disable share this: the rule group goes, the saved profile settings and
    # the outbound allow rules that were switched off come back, the auto-undo task goes.
    param($Profiles, $DisabledNames)
    $null = Remove-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue
    Set-FirewallProfileState -Profiles $Profiles
    if (@($DisabledNames).Count -gt 0) { $null = Enable-NetFirewallRule -Name @($DisabledNames) -ErrorAction SilentlyContinue }
    Remove-AutoUndo
    $statePath = Get-StatePath
    if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
}

function Get-HostSpec {
    # One AllowedHosts entry as a host name, an address or a CIDR range.
    param([string] $Text)
    $kind = ''
    $rangeParts = $Text -split '/'
    if ($rangeParts.Count -eq 2 -and $rangeParts[1] -match '^[0-9]{1,3}$') {
        $parsed = $null
        $isAddress = ($rangeParts[0] -match $Ipv4Pattern -or $rangeParts[0].Contains(':')) -and [Net.IPAddress]::TryParse($rangeParts[0], [ref]$parsed)
        if ($isAddress) {
            $maximum = if ($parsed.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { 128 } else { 32 }
            if ([int]$rangeParts[1] -ge 0 -and [int]$rangeParts[1] -le $maximum) { $kind = 'Range' }
        }
    }
    elseif ($rangeParts.Count -eq 1) {
        $parsed = $null
        if (($Text -match $Ipv4Pattern -or $Text.Contains(':')) -and [Net.IPAddress]::TryParse($Text, [ref]$parsed)) { $kind = 'Address' }
        elseif ($Text -match $HostNamePattern) { $kind = 'Name' }
    }
    return [pscustomobject]@{ Text = $Text; Kind = $kind }
}

function Get-Sha256Text {
    param([string] $Text)
    $hash = [Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
    return (([BitConverter]::ToString($hash)) -replace '-', '').ToLowerInvariant()
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

function Get-AgentProgram {
    # The program files of service processes above this script in its process chain (outside the
    # Windows folder): the RMM agent that started it. Its own network must survive the isolation.
    param($Ancestors)
    $windowsDir = [Environment]::GetFolderPath('Windows')
    if (-not $windowsDir) { $windowsDir = 'C:\Windows' }
    $servicePids = @(Get-CimInstance -ClassName Win32_Service | Where-Object { [int]$_.ProcessId -gt 0 } | ForEach-Object { [int]$_.ProcessId })
    $found = @()
    foreach ($ancestor in $Ancestors) {
        if ([int]$ancestor.Id -eq [int]$PID -or $ancestor.Path -eq '') { continue }
        if (($ancestor.Path.TrimEnd('\') + '\').StartsWith($windowsDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($servicePids -contains [int]$ancestor.Id -and $found -notcontains $ancestor.Path) { $found += $ancestor.Path }
    }
    return $found
}

function Get-ThirdPartyFirewall {
    # Names of enabled non-Microsoft firewall products registered in Windows Security Center.
    $names = @()
    try {
        foreach ($product in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName FirewallProduct -ErrorAction Stop)) {
            if ([string]$product.instanceGuid -ieq $WindowsFirewallGuid) { continue }
            if (([int]$product.productState -band 0x1000) -ne 0) { $names += [string]$product.displayName }
        }
    }
    catch { $null = $_ }
    return $names
}

function Get-DisableCandidate {
    # Names of enabled outbound allow rules in this PC's own policy, outside our group: under
    # default Block they would stay in force, so they are switched off while isolated.
    $names = @()
    foreach ($rule in @(Get-NetFirewallRule -PolicyStore PersistentStore -Direction Outbound -Action Allow -Enabled True -ErrorAction SilentlyContinue)) {
        if ([string]$rule.Group -eq $GroupName -or ([string]$rule.Name).StartsWith('MSPOutpostIsolation-') -or $KeepRuleNames -contains [string]$rule.Name) { continue }
        $names += [string]$rule.Name
    }
    return $names
}

function Register-AutoUndo {
    # A one-shot SYSTEM task that runs the undo after Minutes minutes.
    param([int] $Minutes)
    $folder = Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Isolation'
    if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
    $file = Join-Path -Path $folder -ChildPath 'auto-undo.ps1'
    Set-Content -LiteralPath $file -Value (Get-AutoUndoCode) -Encoding ASCII
    $powershell = Join-Path -Path (Get-SystemTool -FileName 'WindowsPowerShell\v1.0') -ChildPath 'powershell.exe'
    $action = New-ScheduledTaskAction -Execute $powershell -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $file + '"')
    $trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes($Minutes))
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    $null = Register-ScheduledTask -TaskName $AutoUndoTaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        AllowedHosts    = @(Read-OutpostList -Name 'AllowedHosts' -Required)
        AllowedPrograms = @(Read-OutpostList -Name 'AllowedPrograms')
        AutoUndoMinutes = Read-OutpostInt -Name 'AutoUndoMinutes' -Min 0 -Max 1440
        IncludeServers  = Read-OutpostBool -Name 'IncludeServers'
    }
    $specs = @()
    foreach ($entry in $Config.AllowedHosts) {
        $spec = Get-HostSpec -Text $entry
        if ($spec.Kind -eq '') {
            Stop-OutpostInput -Name 'AllowedHosts' -Value $entry -Expected 'a host name such as rmm.example.com, an IP address, or an address range such as 10.0.0.0/24 (no wildcards)'
        }
        $specs += $spec
    }
    if ($specs[0].Kind -eq 'Range') {
        Stop-OutpostInput -Name 'AllowedHosts' -Value $specs[0].Text -Expected 'a single host name or IP address FIRST (the test connection needs one host to try), then any ranges'
    }
    foreach ($program in $Config.AllowedPrograms) {
        if ($program -notmatch '^[A-Za-z]:\\' -or $program -notlike '*.exe' -or $program -match '[\*\?]') {
            Stop-OutpostInput -Name 'AllowedPrograms' -Value $program -Expected 'the full path of a program, such as C:\Program Files\Agent\agent.exe (no wildcards)'
        }
        if (-not (Test-Path -LiteralPath $program -PathType Leaf)) {
            Stop-OutpostRun -Message "AllowedPrograms entry $program does not exist. Correct the path (the RMM agent's real install folder), then run again."
        }
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    if (-not (Get-Command -Name 'New-NetFirewallRule' -ErrorAction SilentlyContinue)) {
        Stop-OutpostRun -Message 'The Windows Firewall cmdlets (NetSecurity module) are not available on this PC, so it cannot be isolated by this script.'
    }
    $firewallService = Get-Service -Name 'mpssvc' -ErrorAction SilentlyContinue
    if (-not $firewallService -or $firewallService.Status -ne 'Running') {
        Stop-OutpostRun -Message 'The Windows Defender Firewall service (mpssvc) is not running, so firewall rules would not be enforced. Start it (or remove the third-party firewall policy), then run again.'
    }
    $productType = [int](Get-CimInstance -ClassName Win32_OperatingSystem).ProductType
    if ($productType -ne 1 -and -not $Config.IncludeServers) {
        Stop-OutpostRun -Message 'This PC is a Windows Server or domain controller. Isolating a server drops every service it provides, so it is refused. Set IncludeServers true if you are sure.'
    }

    $thirdParty = @(Get-ThirdPartyFirewall)
    if ($thirdParty.Count -gt 0) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer ('Skipped: a non-Microsoft firewall is active (' + ($thirdParty -join ', ') + '), so Windows Firewall rules would not isolate this PC.')
    }

    # Detect: resolve names now, with the DNS this PC has now.
    Write-OutpostLine -Text 'Resolving AllowedHosts to IP addresses now; the firewall rules will hold these addresses until you run this script again.'
    $addresses = @()
    $firstAddresses = @()
    $specIndex = 0
    foreach ($spec in $specs) {
        $found = @()
        if ($spec.Kind -eq 'Name') {
            try { $found = @(Resolve-HostAddress -Name $spec.Text) }
            catch { Stop-OutpostRun -Message "Could not resolve $($spec.Text) to an IP address ($($_.Exception.Message)). Isolation needs the address while DNS still works: check the name or put the IP address in AllowedHosts." }
            if ($found.Count -eq 0) { Stop-OutpostRun -Message "$($spec.Text) has no IP address in DNS. Check the name or use the IP address." }
            Write-OutpostLine -Text "  $($spec.Text) -> $($found -join ', ')"
        }
        else { $found = @($spec.Text) }
        if ($specIndex -eq 0) { $firstAddresses = $found }
        $specIndex++
        foreach ($address in $found) { if ($addresses -notcontains $address) { $addresses += $address } }
    }

    # The RMM agent running this script must keep its network: it is found in the process chain.
    $ancestors = @(Get-AncestorProcess)
    $agentPrograms = @(Get-AgentProgram -Ancestors $ancestors)
    $programs = @(@($Config.AllowedPrograms) + $agentPrograms | Where-Object { $_ } | Sort-Object -Unique)
    if ($agentPrograms.Count -gt 0) { Write-OutpostLine -Text ('Allowing the agent that runs this script: ' + ($agentPrograms -join ', ')) }
    if ($programs.Count -eq 0) {
        $noAgent = 'No agent program was found in this script''s own process chain and AllowedPrograms is empty, so the RMM agent could lose its connection for good. Set AllowedPrograms to the full path of the RMM agent executable, then run again.'
        if ($script:OutpostRun.DryRun) { Write-OutpostWarning -Text "A real run would stop: $noAgent" }
        else { Stop-OutpostRun -Message $noAgent }
    }
    $signature = Get-Sha256Text -Text ((@($addresses | Sort-Object) -join ',') + '|' + ((@($programs | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)) -join ','))
    $shortSignature = $signature.Substring(0, 12)
    $hostRuleName = $HostRuleNamePrefix + $shortSignature
    $description = "MSP Outpost network isolation (enable-network-isolation). Signature $signature"

    $currentProfiles = @(Get-FirewallProfileState)
    $rules = @(Get-IsolationRule)
    $state = Read-IsolationState
    if ($rules.Count -gt 0 -and -not $state) {
        Stop-OutpostRun -Message "The rule group $GroupName exists but its saved state is missing, so the original firewall settings are unknown and the current (isolated) ones must not be saved as the original. Run disable-network-isolation first, then run this script again."
    }
    $isBlocking = (@(Get-FirewallProfileState -Store 'ActiveStore' | Where-Object { $_.Enabled -ne 'True' -or $_.DefaultOutboundAction -ne 'Block' -or $_.DefaultInboundAction -ne 'Block' -or $_.AllowInboundRules -ne 'False' }).Count -eq 0)
    $oldRules = @($rules | Where-Object { $_.Name -notlike "*-$shortSignature" })
    $isCurrent = $isBlocking -and $state -and ($oldRules.Count -eq 0) -and ($rules.Count -eq (1 + $programs.Count)) -and (@($rules | Where-Object { [string]$_.Enabled -ne 'True' }).Count -eq 0)
    if ($isCurrent) {
        Complete-OutpostRun -Status 'OK' -Answer ("Already isolated: traffic allowed only to $($addresses.Count) address(es) (" + ($Config.AllowedHosts -join ', ') + ") and $($programs.Count) program(s).")
    }
    $isRerun = [bool]$state

    # The first host must answer NOW: if it does not, nothing is changed.
    $before = Test-HostReachable -Addresses $firstAddresses -MaxSeconds $PreCheckSeconds
    if ($before -eq '') {
        Stop-OutpostRun -Message "The first AllowedHost $($Config.AllowedHosts[0]) ($($firstAddresses -join ', ')) is not reachable from this PC now (no ping, TCP 443/80/53 answer or DNS reply), so isolating could cut this PC off for good. Nothing was changed. Check the host, or put a host that answers first."
    }
    Write-OutpostLine -Text "First AllowedHost answers now ($before)."

    $signedInUser = Get-OutpostSignedInUser
    if ($signedInUser) { Write-OutpostWarning -Text "$signedInUser is signed in and will lose network access except to the allowed hosts." }
    if ($isRerun) { Write-OutpostLine -Text 'Isolation is already on with other settings: new rules are added first and the old ones removed after; the original firewall settings stay as saved.' }

    # The settings to restore are the ones from before the FIRST isolation.
    $original = @($currentProfiles)
    $backupFile = ''
    $disabledBefore = @()
    if ($state) {
        $original = @($state.Profiles)
        $backupFile = [string]$state.BackupFile
        $disabledBefore = @($state.DisabledRules | Where-Object { $_ })
    }
    $toDisable = @(Get-DisableCandidate)
    $disabledAll = @(@($disabledBefore) + $toDisable | Where-Object { $_ } | Sort-Object -Unique)
    $planned = 4 + $programs.Count
    if ($Config.AutoUndoMinutes -gt 0) { $planned++ }
    if ($isRerun -and $oldRules.Count -gt 0) { $planned++ }
    Assert-OutpostChangeLimit -Planned $planned

    # Act: allow rules first, the default Block last. A failed first run rolls everything back; a
    # failed rerun removes only the new rules and leaves the isolation that was already in place.
    $flow = @{ Touched = $false; BackupFile = $backupFile; Way = '' }
    try {
        $null = Invoke-OutpostChange -Item 'Firewall policy' -Change 'Back up the firewall policy and save the current settings (profiles, outbound rules to disable)' -Action {
            if ($flow.BackupFile -eq '') {
                $exportFile = Join-Path -Path (Get-OutpostDataFolder) -ChildPath ('Isolation\policy-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture) + '.wfw')
                $exportFolder = Split-Path -Path $exportFile -Parent
                if (-not (Test-Path -LiteralPath $exportFolder)) { $null = New-Item -Path $exportFolder -ItemType Directory -Force }
                $null = & (Get-SystemTool -FileName 'netsh.exe') advfirewall export $exportFile
                if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exportFile)) { throw "netsh advfirewall export failed (exit code $LASTEXITCODE)." }
                $flow.BackupFile = [string](Backup-OutpostItem -Path $exportFile)
                Remove-Item -LiteralPath $exportFile -Force
            }
            $saved = [ordered]@{ SavedUtc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture); BackupFile = $flow.BackupFile; FirstHost = $Config.AllowedHosts[0]; Profiles = @($original); DisabledRules = @($disabledAll) }
            $statePath = Get-StatePath
            $stateFolder = Split-Path -Path $statePath -Parent
            if (-not (Test-Path -LiteralPath $stateFolder)) { $null = New-Item -Path $stateFolder -ItemType Directory -Force }
            ConvertTo-Json -InputObject $saved -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
        }
        $null = Invoke-OutpostChange -Item "Firewall rule $hostRuleName" -Change ("Allow outbound to $($addresses.Count) address(es): " + ($addresses -join ', ')) -Action {
            $flow.Touched = $true
            $null = Remove-NetFirewallRule -Name $hostRuleName -ErrorAction SilentlyContinue
            $null = New-NetFirewallRule -Name $hostRuleName -DisplayName 'MSP Outpost Isolation - allowed hosts' -Group $GroupName -Description $description -Direction Outbound -Action Allow -RemoteAddress $addresses -Profile Any -Enabled True
        }
        $number = 0
        foreach ($program in $programs) {
            $number++
            $ruleName = $ProgramRuleNamePrefix + $number + '-' + $shortSignature
            $null = Invoke-OutpostChange -Item "Firewall rule $ruleName" -Change "Allow outbound for $program" -Action {
                $null = Remove-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
                $null = New-NetFirewallRule -Name $ruleName -DisplayName ('MSP Outpost Isolation - allowed program ' + (Split-Path -Path $program -Leaf)) -Group $GroupName -Description $description -Direction Outbound -Action Allow -Program $program -Profile Any -Enabled True
            }
        }
        if ($Config.AutoUndoMinutes -gt 0) {
            $null = Invoke-OutpostChange -Item "Scheduled task $AutoUndoTaskName" -Change "Undo the isolation by itself after $($Config.AutoUndoMinutes) minute(s)" -Action {
                Register-AutoUndo -Minutes $Config.AutoUndoMinutes
            }
        }
        $null = Invoke-OutpostChange -Item 'Firewall rules' -Change "Switch off $($toDisable.Count) other enabled outbound allow rule(s) (listed in the saved state, switched on again by the undo)" -Action {
            if ($toDisable.Count -gt 0) { Disable-NetFirewallRule -Name $toDisable }
        }
        $null = Invoke-OutpostChange -Item 'Firewall profiles' -Change 'Switch Domain, Private and Public on; block all other outbound and inbound traffic' -Action {
            Set-NetFirewallProfile -Profile $ProfileNames -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Block -AllowInboundRules False
        }
        if ($isRerun -and $oldRules.Count -gt 0) {
            $null = Invoke-OutpostChange -Item 'Firewall rules' -Change "Remove $($oldRules.Count) rule(s) of the previous isolation" -Action {
                foreach ($oldRule in $oldRules) { Remove-NetFirewallRule -Name $oldRule.Name }
            }
        }

        # Verify against what is really in force (skipped in a dry run: nothing was changed)
        if (-not $script:OutpostRun.DryRun) {
            $badProfiles = @(Get-FirewallProfileState -Store 'ActiveStore' | Where-Object { $_.Enabled -ne 'True' -or $_.DefaultOutboundAction -ne 'Block' -or $_.DefaultInboundAction -ne 'Block' -or $_.AllowInboundRules -ne 'False' } | ForEach-Object { $_.Name })
            if ($badProfiles.Count -gt 0) {
                throw ('The firewall profile(s) ' + ($badProfiles -join ', ') + ' are not blocking in the ACTIVE policy. A Group Policy or another firewall product probably controls the firewall on this PC.')
            }
            $madeRules = @(Get-IsolationRule)
            if ($madeRules.Count -ne (1 + $programs.Count)) { throw "Expected $(1 + $programs.Count) firewall rules in the group but found $($madeRules.Count)." }
            $way = Test-HostReachable -Addresses $firstAddresses -MaxSeconds $PostCheckSeconds
            if ($way -eq '') {
                throw "The test connection to $($Config.AllowedHosts[0]) ($($firstAddresses -join ', ')) failed while isolated."
            }
            $flow.Way = $way
        }
    }
    catch {
        $problem = $_.Exception.Message
        if ($isRerun) {
            try { foreach ($newRule in @(Get-IsolationRule | Where-Object { $_.Name -like "*-$shortSignature" })) { Remove-NetFirewallRule -Name $newRule.Name -ErrorAction SilentlyContinue } }
            catch { $null = $_ }
            Stop-OutpostRun -Message "$problem The isolation that was already in place was left as it was; only the new rules were removed."
        }
        if ($flow.Touched) {
            try {
                Undo-Isolation -Profiles $original -DisabledNames $disabledAll
                Write-OutpostLog -Text "ROLLBACK  isolation removed and the saved firewall settings restored: $problem"
                Stop-OutpostRun -Message "$problem ROLLED BACK: isolation rules removed and the original firewall settings restored, so this PC is not isolated. Check AllowedHosts and run again."
            }
            catch {
                Stop-OutpostRun -Message "$problem The rollback also failed ($($_.Exception.Message)). Run disable-network-isolation, or restore the policy backup $($flow.BackupFile) with netsh advfirewall import."
            }
        }
        if (Test-Path -LiteralPath (Get-StatePath)) { Remove-Item -LiteralPath (Get-StatePath) -Force }
        Stop-OutpostRun -Message "$problem Nothing was isolated."
    }

    # Finish
    $answer = "Isolated: traffic allowed only to $($addresses.Count) address(es) (" + ($Config.AllowedHosts -join ', ') + ") and $($programs.Count) program(s); $($toDisable.Count) other outbound rule(s) disabled"
    if ($Config.AutoUndoMinutes -gt 0) { $answer += "; auto-undo in $($Config.AutoUndoMinutes) min" }
    if (-not $script:OutpostRun.DryRun) { $answer += "; test connection ok ($($flow.Way))" }
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
