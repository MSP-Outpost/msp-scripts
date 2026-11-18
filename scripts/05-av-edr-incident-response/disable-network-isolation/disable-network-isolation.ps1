#Requires -Version 5.1
<#
.SYNOPSIS
    Ends the network isolation made by enable-network-isolation and checks the PC is back on the network.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It undoes enable-network-isolation exactly:

      * saves the firewall policy as it is now (netsh advfirewall export,
        kept in %ProgramData%\MSPOutpost\Backups\disable-network-isolation);
      * deletes the Windows Firewall rule group "MSP Outpost Isolation";
      * puts the Domain, Private and Public profiles back to the settings
        enable-network-isolation saved before it isolated the PC (firewall on
        or off, default inbound and outbound action, inbound rules). When no
        saved settings exist it sets the default outbound action to Allow and
        lets inbound allow rules apply again, which is how Windows ships, and
        says so in a WARNING;
      * switches the outbound allow rules that the isolation switched off back on
        (the list is in the saved state) and deletes the auto-undo scheduled task
        MSPOutpost-IsolationAutoUndo if enable-network-isolation made one;
      * deletes its saved state file;
      * tests a connection to the first host that was allowed, then to the
        default gateway (ping, a TCP connect or refusal on 443, 80 or 53, or a
        DNS reply). If nothing answers, it ends in ERROR: the firewall is
        restored, so look at the network itself.

    BackupPath is the other way back: the path of a policy backup made by
    enable-network-isolation (the Backups folder named in its change log, a
    .wfw file; its path is also in BackupFile inside
    %ProgramData%\MSPOutpost\Isolation\state.json). The WHOLE firewall policy is then restored from it (netsh
    advfirewall import), which also undoes any firewall rule changed since.

    If this PC is not isolated (no rule group and no saved state), it changes
    nothing and says so. It leaves a firewall that someone else set to block
    outbound traffic alone and warns about it.

.PARAMETER BackupPath
    Optional. A .wfw policy backup to restore with netsh advfirewall import
    instead of the saved profile settings. Environment variable: BackupPath

.PARAMETER DryRun
    true to list what it would change and change nothing. Default false.
    -WhatIf does the same. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\disable-network-isolation.ps1

    Removes the isolation rules, restores the saved firewall settings and tests the network.

.EXAMPLE
    .\disable-network-isolation.ps1 -BackupPath "C:\ProgramData\MSPOutpost\Backups\enable-network-isolation\20261116-141500\C__ProgramData_MSPOutpost_Isolation_policy-20261116-141459.wfw"

    Restores the whole firewall policy from that backup.

.NOTES
    Name:        End network isolation and restore the firewall
    Slug:        disable-network-isolation
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    05 AV / EDR & incident response
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Deletes the Windows Firewall rule group MSP Outpost Isolation and restores the saved firewall profile settings (or a policy backup)
    Risk:        Low
    Reboot:      Never
    Runtime:     10 to 40 seconds
    Answer:      "Isolation removed; firewall restored; connection ok (192.168.1.1 via ping)"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/disable-network-isolation
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $BackupPath = '',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'disable-network-isolation'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('BackupPath')
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
$ProfileNames = @('Domain', 'Private', 'Public')
$ProbeMilliseconds = 2000
$AutoUndoTaskName = 'MSPOutpost-IsolationAutoUndo'
$ProbeTcpPorts = @(443, 80, 53)
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

function Get-ProbeAddress {
    # Where to test the connection after the isolation is gone: the first allowed
    # host the isolation was built with, then the default gateways.
    param($State)
    $found = @()
    if ($State) {
        $first = [string]$State.FirstHost
        $parsed = $null
        if (($first -match $Ipv4Pattern -or $first.Contains(':')) -and [Net.IPAddress]::TryParse($first, [ref]$parsed)) { $found += $first }
        elseif ($first -ne '') {
            try { $found += @(Resolve-HostAddress -Name $first) } catch { $null = $_ }
        }
    }
    foreach ($adapter in @(Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE')) {
        $gateways = Get-RegistryValue -Item $adapter -PropertyName 'DefaultIPGateway'
        foreach ($gateway in @($gateways)) {
            $parsed = $null
            if ($gateway -and [Net.IPAddress]::TryParse([string]$gateway, [ref]$parsed) -and $found -notcontains [string]$gateway) { $found += [string]$gateway }
        }
    }
    return $found
}

function Get-RegistryValue {
    # Strict mode throws on a missing property, so read through the property bag.
    param($Item, [string] $PropertyName)
    $property = $Item.PSObject.Properties[$PropertyName]
    if ($property) { return $property.Value }
    return $null
}

function Get-EffectiveSetting {
    # NotConfigured means the Windows default: the firewall on, inbound Block, outbound Allow, inbound rules on.
    param([string] $Name, [string] $Value)
    if ($Value -ne 'NotConfigured') { return $Value }
    switch ($Name) {
        'DefaultInboundAction' { return 'Block' }
        'DefaultOutboundAction' { return 'Allow' }
        default { return 'True' }
    }
}

function Test-ProfileMatch {
    # True when every profile in force has the saved values (NotConfigured read as its default).
    param($Current, $Saved)
    foreach ($want in @($Saved)) {
        $have = @($Current | Where-Object { $_.Name -eq [string]$want.Name }) | Select-Object -First 1
        if (-not $have) { return $false }
        foreach ($property in @('Enabled', 'DefaultInboundAction', 'DefaultOutboundAction', 'AllowInboundRules')) {
            $haveValue = Get-EffectiveSetting -Name $property -Value ([string]$have.$property)
            $wantValue = Get-EffectiveSetting -Name $property -Value ([string]$want.$property)
            if ($haveValue -ne $wantValue) { return $false }
        }
    }
    return $true
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        BackupPath = Read-OutpostText -Name 'BackupPath'
    }
    if ($Config.BackupPath -ne '') {
        if ($Config.BackupPath -notmatch '^[A-Za-z]:\\' -or $Config.BackupPath -match '[\*\?]') {
            Stop-OutpostInput -Name 'BackupPath' -Value $Config.BackupPath -Expected 'the full path of a policy backup file (.wfw), without wildcards'
        }
        if (-not (Test-Path -LiteralPath $Config.BackupPath -PathType Leaf)) {
            Stop-OutpostRun -Message "BackupPath $($Config.BackupPath) does not exist. Check the path in the change log of enable-network-isolation."
        }
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    if (-not (Get-Command -Name 'Remove-NetFirewallRule' -ErrorAction SilentlyContinue)) {
        Stop-OutpostRun -Message 'The Windows Firewall cmdlets (NetSecurity module) are not available on this PC.'
    }

    # Detect
    $rules = @(Get-IsolationRule)
    $state = Read-IsolationState
    $currentProfiles = @(Get-FirewallProfileState)
    $undoTask = @(Get-ScheduledTask -TaskName $AutoUndoTaskName -ErrorAction SilentlyContinue)
    if ($rules.Count -eq 0 -and -not $state -and $undoTask.Count -eq 0) {
        $blocking = @($currentProfiles | Where-Object { $_.DefaultOutboundAction -eq 'Block' } | ForEach-Object { $_.Name })
        if ($blocking.Count -gt 0) {
            Write-OutpostWarning -Text ('Outbound traffic is blocked by default on the ' + ($blocking -join ', ') + ' profile(s), but not by this script (no rule group, no saved state). It was left alone.')
        }
        $unused = ''
        if ($Config.BackupPath -ne '') { $unused = ' BackupPath was not used.' }
        Complete-OutpostRun -Status 'OK' -Answer ('Already not isolated: no MSP Outpost isolation rules or saved state found.' + $unused)
    }
    Write-OutpostLine -Text ("Isolation found: {0} rule(s) in the group, saved state {1}." -f $rules.Count, $(if ($state) { 'present' } else { 'absent' }))

    # Act
    $null = Invoke-OutpostChange -Item 'Firewall policy' -Change 'Back up the current firewall policy (netsh advfirewall export)' -Action {
        $exportFile = Join-Path -Path (Get-OutpostDataFolder) -ChildPath ('Isolation\policy-now-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture) + '.wfw')
        $exportFolder = Split-Path -Path $exportFile -Parent
        if (-not (Test-Path -LiteralPath $exportFolder)) { $null = New-Item -Path $exportFolder -ItemType Directory -Force }
        $null = & (Get-SystemTool -FileName 'netsh.exe') advfirewall export $exportFile
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exportFile)) { throw "netsh advfirewall export failed (exit code $LASTEXITCODE)." }
        $null = Backup-OutpostItem -Path $exportFile
        Remove-Item -LiteralPath $exportFile -Force
    }
    if ($Config.BackupPath -ne '') {
        $null = Invoke-OutpostChange -Item 'Firewall policy' -Change "Restore the whole policy from $($Config.BackupPath) (netsh advfirewall import)" -Action {
            $null = & (Get-SystemTool -FileName 'netsh.exe') advfirewall import $Config.BackupPath
            if ($LASTEXITCODE -ne 0) { throw "netsh advfirewall import failed (exit code $LASTEXITCODE)." }
        }
    }
    if ($rules.Count -gt 0) {
        $null = Invoke-OutpostChange -Item "Firewall rule group $GroupName" -Change "Delete $($rules.Count) rule(s)" -Action {
            $null = Remove-NetFirewallRule -Group $GroupName -ErrorAction SilentlyContinue
        }
    }
    $disabledRules = @()
    if ($state) { $disabledRules = @($state.DisabledRules | Where-Object { $_ }) }
    if ($disabledRules.Count -gt 0) {
        $null = Invoke-OutpostChange -Item 'Firewall rules' -Change "Switch $($disabledRules.Count) outbound allow rule(s) back on" -Action {
            $null = Enable-NetFirewallRule -Name $disabledRules -ErrorAction SilentlyContinue
        }
    }
    if ($undoTask.Count -gt 0) {
        $null = Invoke-OutpostChange -Item "Scheduled task $AutoUndoTaskName" -Change 'Delete the auto-undo task' -Action { Remove-AutoUndo }
    }
    if ($Config.BackupPath -eq '' -and ($state -or $rules.Count -gt 0)) {
        if (-not $state) { Write-OutpostWarning -Text 'No saved settings were found, so Windows DEFAULTS were restored (default outbound Allow, inbound allow rules on), not the settings from before the isolation. Check the firewall settings you expect.' }
        $restoreText = 'Set all profiles to default outbound Allow and inbound rules on (no saved settings)'
        if ($state) { $restoreText = 'Restore the saved settings of the Domain, Private and Public profiles' }
        $null = Invoke-OutpostChange -Item 'Firewall profiles' -Change $restoreText -Action {
            if ($state) { Set-FirewallProfileState -Profiles @($state.Profiles) }
            else { Set-NetFirewallProfile -Profile $ProfileNames -DefaultOutboundAction Allow -AllowInboundRules True }
        }
    }
    if ($state) {
        $null = Invoke-OutpostChange -Item 'Saved state' -Change 'Delete the saved isolation state' -Action {
            Remove-Item -LiteralPath (Get-StatePath) -Force
        }
    }

    # Verify (skipped in a dry run: nothing was changed)
    $connection = ''
    if (-not $script:OutpostRun.DryRun) {
        if (@(Get-IsolationRule).Count -gt 0) { Stop-OutpostRun -Message "The rule group $GroupName is still there after deleting it. Check the firewall policy and run again." }
        $after = @(Get-FirewallProfileState -Store 'ActiveStore')
        if ($Config.BackupPath -eq '') {
            if ($state -and -not (Test-ProfileMatch -Current $after -Saved $state.Profiles)) {
                Stop-OutpostRun -Message ('The firewall profiles in force differ from the saved settings after restoring them (saved: ' + (@($state.Profiles | ForEach-Object { $_.Name + ' ' + $_.Enabled + '/' + $_.DefaultInboundAction + '/' + $_.DefaultOutboundAction + '/' + $_.AllowInboundRules }) -join '; ') + '; in force: ' + (@($after | ForEach-Object { $_.Name + ' ' + $_.Enabled + '/' + $_.DefaultInboundAction + '/' + $_.DefaultOutboundAction + '/' + $_.AllowInboundRules }) -join '; ') + '). A Group Policy may control the firewall.')
            }
            $stillBlocking = @($after | Where-Object { $_.DefaultOutboundAction -eq 'Block' } | ForEach-Object { $_.Name })
            if (-not $state -and $stillBlocking.Count -gt 0) {
                Stop-OutpostRun -Message ('Outbound traffic is still blocked by default on the ' + ($stillBlocking -join ', ') + ' profile(s). A Group Policy may control the firewall on this PC.')
            }
        }
        $probeAddresses = @(Get-ProbeAddress -State $state)
        if ($probeAddresses.Count -eq 0) {
            Write-OutpostWarning -Text 'No host or default gateway to test the connection against; the firewall settings were verified, the connection was not.'
        }
        else {
            $connection = Test-HostReachable -Addresses $probeAddresses
            if ($connection -eq '') {
                Stop-OutpostRun -Message ("The isolation is removed and the firewall is back to its saved settings, but nothing answers at " + ($probeAddresses -join ', ') + '. Check the cable, Wi-Fi, IP address and the network itself.')
            }
        }
    }

    # Finish
    $answer = 'Isolation removed; firewall restored'
    if ($Config.BackupPath -ne '') { $answer = 'Isolation removed; firewall policy restored from the backup' }
    if ($connection -ne '') { $answer += "; connection ok ($connection)" }
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
