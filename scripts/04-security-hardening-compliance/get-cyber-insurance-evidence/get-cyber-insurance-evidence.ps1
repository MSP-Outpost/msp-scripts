#Requires -Version 5.1
<#
.SYNOPSIS
    Collects the device half of a cyber-insurance questionnaire as one evidence table with a Pass, Fail or Unknown for each control.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. One run answers the questions an insurer asks
    about a Windows device. It writes one row per control (Control, Value,
    Status, Evidence) and ends with "N of M controls pass; fails: ...". Set
    ExportPath to a .csv file to hand the table to the client file.

    Controls: operating system support status; age of the last patch (quality
    update); BitLocker on the operating system drive; antivirus active
    (Windows Security Center on workstations, Defender status); an EDR agent
    (Microsoft Defender for Endpoint, CrowdStrike, SentinelOne, Huntress,
    Cylance, Carbon Black, Cortex XDR); the three firewall profiles as
    enforced; the local Administrators group (a list); Remote Desktop and
    Network Level Authentication; SMB1; Secure Boot; TPM; the machine screen
    lock timeout policy (InactivityTimeoutSecs); local password length,
    complexity and account lockout (read with secedit, no text parsed from net
    accounts); a backup product present; remote access tools present.

    Pass and Fail are stated only when the evidence supports them. Unknown
    means the script could not read it, or that a person has to judge it: the
    EDR row is Unknown when no product from the short list is found (the list
    is not every product), and the remote access row is Unknown when tools are
    found (the script cannot tell your approved tool from an unapproved one).
    Limits to know:
    - Patch age is the newest of Get-HotFix and the KB-numbered updates in the
      Windows Update history (Defender definitions and the malicious software
      removal tool are ignored). Confidence: medium.
    - OS support uses a built-in table of end-of-support dates for Windows 10,
      Windows 11 and Windows Server (Home/Pro and Enterprise/Education dates
      differ). Windows 10 Extended Security Updates and Long-Term Servicing
      releases are not detected (an LTSC edition is Unknown). A build newer
      than the table is Pass.
    - The screen lock row reads only the machine policy InactivityTimeoutSecs;
      per-user screen saver policies are not read.
    - On a domain-joined PC the password rows show the effective policy,
      which includes domain Group Policy.
    - The backup row only shows that a product is present; run
      test-backup-status to know whether it succeeded.

.PARAMETER MaxPatchAgeDays
    Fail the patch row when the newest update is older than this many days.
    Whole number, 1 to 3650. Default 45.
    Environment variable: MaxPatchAgeDays

.PARAMETER MaxScreenLockSeconds
    Fail the screen lock row when InactivityTimeoutSecs is not set or is
    longer than this. Whole number, 1 to 86400. Default 900 (15 minutes).
    Environment variable: MaxScreenLockSeconds

.PARAMETER MinPasswordLength
    Fail the password length row when the local minimum is shorter than this.
    Whole number, 1 to 128. Default 8.
    Environment variable: MinPasswordLength

.PARAMETER MaxLocalAdmins
    Fail the local administrators row when the Administrators group has more
    members than this. Whole number, 1 to 100. Default 3.
    Environment variable: MaxLocalAdmins

.PARAMETER DryRun
    Reserved; ignored by Reports.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Use a .csv path to keep the
    evidence table for the client file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\get-cyber-insurance-evidence.ps1 -ExportPath C:\Temp\insurance-evidence.csv

    Prints the table and saves it as a CSV for the client file.

.EXAMPLE
    .\get-cyber-insurance-evidence.ps1 -MinPasswordLength 12 -MaxScreenLockSeconds 600 -OutputFormat Json

    Holds the device to a 12 character password and a 10 minute lock, as JSON.

.NOTES
    Name:        Cyber-insurance questionnaire - device evidence pack
    Slug:        get-cyber-insurance-evidence
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Report
    Category:    04 Security hardening & compliance
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1; administrator rights
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 60 seconds
    Answer:      "11 of 17 controls pass; fails: BitLocker, Firewall, Screen lock; 1 unknown"
    Fields:      Control, Value, Status, Evidence
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/get-cyber-insurance-evidence
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text. Defaults are the
    # place to edit when your RMM cannot pass arguments or variables.
    [string] $MaxPatchAgeDays = '45',
    [string] $MaxScreenLockSeconds = '900',
    [string] $MinPasswordLength = '8',
    [string] $MaxLocalAdmins = '3',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'get-cyber-insurance-evidence'
    Version = '1.0.0'
    Type    = 'Report'
    Risk    = 'Low'
    Inputs  = @('MaxPatchAgeDays', 'MaxScreenLockSeconds', 'MinPasswordLength', 'MaxLocalAdmins')
    Fields  = @('Control', 'Value', 'Status', 'Evidence')
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
$WorkstationProductType = 1
$EarliestRealYear = 2000
$EvidenceMaxChars = 150
$HistoryEntriesToRead = 200
$OperationInstallation = 1
$ResultSucceeded = 2
$IgnoredKbNumbers = @('2267602', '890830', '915597')
$ProductStateOnMask = 61440
$ProductStateOn = 4096
$CurrentVersionKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$SystemPolicyKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$TerminalServerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$RdpTcpKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
$TerminalPolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
$LanmanServerKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
$SecureBootStateKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State'
$AdministratorsSid = 'S-1-5-32-544'
# Family|Build|end of support for Home and Pro|end for Enterprise, Education and Server.
$SupportTable = @(
    'W10|19044|2023-06-13|2024-06-11',
    'W10|19045|2025-10-14|2025-10-14',
    'W11|22000|2023-10-10|2024-10-08',
    'W11|22621|2024-10-08|2025-10-14',
    'W11|22631|2025-11-11|2026-11-10',
    'W11|26100|2026-10-13|2027-10-12',
    'W11|26200|2027-10-12|2028-10-10',
    'SRV|9200|2023-10-10|2023-10-10',
    'SRV|9600|2023-10-10|2023-10-10',
    'SRV|14393|2027-01-12|2027-01-12',
    'SRV|17763|2029-01-09|2029-01-09',
    'SRV|20348|2031-10-14|2031-10-14',
    'SRV|26100|2034-10-10|2034-10-10'
)
$EdrProducts = @(
    @{ Tool = 'Microsoft Defender for Endpoint'; Service = 'Sense' },
    @{ Tool = 'CrowdStrike Falcon'; Service = 'CSFalconService' },
    @{ Tool = 'SentinelOne'; Service = 'SentinelAgent' },
    @{ Tool = 'Huntress'; Service = 'HuntressAgent' },
    @{ Tool = 'Cylance'; Service = 'CylanceSvc' },
    @{ Tool = 'VMware Carbon Black'; Service = 'CbDefense' },
    @{ Tool = 'Cortex XDR'; Service = 'cyserver' }
)
$BackupProducts = @(
    @{ Tool = 'Veeam Agent'; Services = @('VeeamEndpointBackupSvc') },
    @{ Tool = 'Veeam Backup & Replication'; Services = @('VeeamBackupSvc') },
    @{ Tool = 'Macrium Reflect'; Services = @('Macrium*') },
    @{ Tool = 'Acronis'; Services = @('Acronis*', 'AcrSch2Svc', 'cyber-protect-service') },
    @{ Tool = 'Datto backup agent'; Services = @('*Datto*Backup*', '*Datto*Windows Agent*', '*Datto*Continuity*', 'DattoWindowsAgent*') },
    @{ Tool = 'Synology Active Backup for Business'; Services = @('*Synology*Active*Backup*', '*ActiveBackup*Agent*') },
    @{ Tool = 'N-able Cove'; Services = @('Backup Service Controller') },
    @{ Tool = 'Azure Backup (MARS)'; Services = @('obengine') }
)
$ServerBackupEventIds = @(4, 14, 5, 8, 9, 20, 21, 22, 49, 517, 521, 561, 564)
$RemoteTools = @(
    @{ Tool = 'AnyDesk'; Services = @('AnyDesk*') },
    @{ Tool = 'TeamViewer'; Services = @('TeamViewer*') },
    @{ Tool = 'Splashtop'; Services = @('Splashtop*', 'SplashtopRemoteService', 'SSUService') },
    @{ Tool = 'RustDesk'; Services = @('RustDesk*') },
    @{ Tool = 'LogMeIn'; Services = @('LogMeIn*', 'LMIGuardianSvc') },
    @{ Tool = 'GoTo Resolve'; Services = @('GoToResolve*', 'GoTo Resolve*') },
    @{ Tool = 'Chrome Remote Desktop'; Services = @('chromoting') },
    @{ Tool = 'ScreenConnect'; Services = @('ScreenConnect Client (*)') },
    @{ Tool = 'RealVNC'; Services = @('vncserver', 'vncserver-*') },
    @{ Tool = 'TightVNC'; Services = @('tvnserver') },
    @{ Tool = 'UltraVNC'; Services = @('uvnc_service') },
    @{ Tool = 'Zoho Assist'; Services = @('ZohoURS', 'Zoho Assist*') },
    @{ Tool = 'BeyondTrust (Bomgar)'; Services = @('bomgar-*', 'Bomgar*', 'BeyondTrust*') },
    @{ Tool = 'NoMachine'; Services = @('nxservice', 'NoMachine*') },
    @{ Tool = 'MeshCentral'; Services = @('Mesh Agent') },
    @{ Tool = 'Radmin'; Services = @('RServer3', 'Radmin*') }
)

# ---- Functions ------------------------------------------------------------
function Get-PropertyOrNull {
    param($Source, [string] $Name)
    if ($null -eq $Source) { return $null }
    $property = $Source.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-RegistryValueOrNull {
    param([string] $Path, [string] $Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-ItemProperty -LiteralPath $Path -ErrorAction SilentlyContinue
    return (Get-PropertyOrNull -Source $item -Name $Name)
}

function Limit-Text {
    param([string] $Text, [int] $Max = $EvidenceMaxChars)
    if ($Text.Length -le $Max) { return $Text }
    return $Text.Substring(0, $Max - 3) + '...'
}

function Format-DateText {
    param([DateTime] $Time)
    return $Time.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
}

function Invoke-NativeText {
    # Runs a program and returns its output lines. stderr is folded in without
    # raising: under $ErrorActionPreference Stop Windows PowerShell 5.1 would throw.
    param([Parameter(Mandatory = $true)][string] $FilePath, [string[]] $Arguments)
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return @(& $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $savedPreference }
}

function New-Control {
    param([string] $Control, [string] $Value, [string] $Status, [string] $Evidence)
    return [pscustomobject]@{ Control = $Control; Value = $Value; Status = $Status; Evidence = (Limit-Text -Text $Evidence) }
}

function Invoke-Control {
    # One control must never end the whole report: an unreadable one becomes Unknown.
    param([string] $Name, [scriptblock] $Code)
    try { return (& $Code) }
    catch { return (New-Control -Control $Name -Value 'not readable' -Status 'Unknown' -Evidence ("Could not read: " + (($_.Exception.Message -replace '\s+', ' ').Trim()))) }
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

function Get-OsSupportControl {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $isServer = ([int]$os.ProductType -ne $WorkstationProductType)
    $edition = [string](Get-RegistryValueOrNull -Path $CurrentVersionKey -Name 'EditionID')
    $display = [string](Get-RegistryValueOrNull -Path $CurrentVersionKey -Name 'DisplayVersion')
    $name = ([string]$os.Caption) -replace '^Microsoft\s+', ''
    $value = "$name build $build"
    if ($display) { $value = "$name $display (build $build)" }
    $family = 'W10'
    if ($isServer) { $family = 'SRV' }
    elseif ($build -ge 22000) { $family = 'W11' }
    if ($edition -cmatch '^(Enterprise|IoTEnterprise)S(N)?$') {
        return New-Control -Control 'OS support' -Value $value -Status 'Unknown' -Evidence 'Long-Term Servicing release: check its own lifecycle date'
    }
    $isEnterprise = $edition -match '^(Enterprise|Education|ProfessionalEducation|IoTEnterprise)'
    $known = @()
    foreach ($line in $SupportTable) {
        $part = $line -split '\|'
        if ($part[0] -eq $family) { $known += [pscustomobject]@{ Build = [int]$part[1]; HomeEnd = $part[2]; EnterpriseEnd = $part[3] } }
    }
    if ($known.Count -eq 0) {
        return New-Control -Control 'OS support' -Value $value -Status 'Unknown' -Evidence 'No support dates for this Windows family'
    }
    $exact = @($known | Where-Object { $_.Build -eq $build })
    $esuNote = ''
    if ($family -eq 'W10') { $esuNote = ' (Extended Security Updates are not detected)' }
    if ($exact.Count -gt 0) {
        $endText = $exact[0].HomeEnd
        if ($isEnterprise -or $isServer) { $endText = $exact[0].EnterpriseEnd }
        $endDate = [DateTime]::ParseExact($endText, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        if ([DateTime]::UtcNow.Date -gt $endDate) {
            return New-Control -Control 'OS support' -Value $value -Status 'Fail' -Evidence "Support ended $endText$esuNote"
        }
        return New-Control -Control 'OS support' -Value $value -Status 'Pass' -Evidence "Supported until $endText"
    }
    $newest = ($known | Measure-Object -Property Build -Maximum).Maximum
    if ($build -gt $newest) {
        return New-Control -Control 'OS support' -Value $value -Status 'Pass' -Evidence "Build is newer than the newest release this script knows ($newest)"
    }
    return New-Control -Control 'OS support' -Value $value -Status 'Fail' -Evidence "Build $build is an old release that is no longer serviced$esuNote"
}

function Get-LastPatch {
    # Newest installed update (UTC) and where it came from; $null when neither source answers.
    # Returns Errors too so the caller can say why nothing was found.
    $best = $null
    $source = ''
    $errors = @()
    try {
        foreach ($fix in @(Get-HotFix)) {
            $installed = $fix.InstalledOn
            if ($installed -is [DateTime] -and $installed.Year -ge $EarliestRealYear) {
                $utc = $installed.ToUniversalTime()
                if ($null -eq $best -or $utc -gt $best) { $best = $utc; $source = "hotfix $($fix.HotFixID)" }
            }
        }
    }
    catch { $errors += "Get-HotFix: $($_.Exception.Message)" }
    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher = $session.CreateUpdateSearcher()
        $total = $searcher.GetTotalHistoryCount()
        if ($total -gt 0) {
            foreach ($entry in $searcher.QueryHistory(0, [math]::Min($total, $HistoryEntriesToRead))) {
                if ([int]$entry.Operation -ne $OperationInstallation -or [int]$entry.ResultCode -ne $ResultSucceeded) { continue }
                if ([string]$entry.Title -match 'KB(\d{6,8})') { $kb = $Matches[1] } else { continue }
                if ($IgnoredKbNumbers -contains $kb) { continue }
                $utc = [DateTime]::SpecifyKind([DateTime]$entry.Date, [DateTimeKind]::Utc)
                if ($utc.Year -ge $EarliestRealYear -and ($null -eq $best -or $utc -gt $best)) { $best = $utc; $source = "update history KB$kb" }
            }
        }
    }
    catch { $errors += "Windows Update history: $($_.Exception.Message)" }
    return [pscustomobject]@{ Utc = $best; Source = $source; Errors = $errors }
}

function Get-PatchControl {
    param([int] $MaxAgeDays)
    $patch = Get-LastPatch
    if ($null -eq $patch.Utc) {
        $why = 'no installed update found'
        if (@($patch.Errors).Count -gt 0) { $why = (@($patch.Errors) -join '; ') }
        return New-Control -Control 'Patch age' -Value 'unknown' -Status 'Unknown' -Evidence $why
    }
    $age = [int][math]::Floor(([DateTime]::UtcNow - $patch.Utc).TotalDays)
    $status = 'Fail'
    if ($age -le $MaxAgeDays) { $status = 'Pass' }
    return New-Control -Control 'Patch age' -Value ("$(Format-DateText -Time $patch.Utc) ($age days ago)") -Status $status -Evidence "Newest update from $($patch.Source); limit $MaxAgeDays days"
}

function Get-BitLockerControl {
    $windowsDir = [Environment]::GetFolderPath('Windows')
    if (-not $windowsDir) { $windowsDir = 'C:\Windows' }
    $drive = ([IO.Path]::GetPathRoot($windowsDir)).TrimEnd('\')
    if (Get-Command -Name 'Get-BitLockerVolume' -ErrorAction SilentlyContinue) {
        $volume = Get-BitLockerVolume -MountPoint $drive
        $protection = [string]$volume.ProtectionStatus
        $percent = [int][math]::Round([double]$volume.EncryptionPercentage, 0)
        $detail = "$drive $([string]$volume.VolumeStatus), $percent% encrypted, method $([string]$volume.EncryptionMethod)"
    }
    else {
        $volume = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftVolumeEncryption' -ClassName 'Win32_EncryptableVolume' -Filter "DriveLetter='$drive'"
        if ($null -eq $volume) { throw "No BitLocker volume object for $drive" }
        $answer = Invoke-CimMethod -InputObject $volume -MethodName 'GetProtectionStatus'
        $protection = switch ([int]$answer.ProtectionStatus) { 0 { 'Off' } 1 { 'On' } default { 'Unknown' } }
        $detail = "$drive protection status read through WMI"
    }
    if ($protection -eq 'On') { return New-Control -Control 'BitLocker' -Value 'On' -Status 'Pass' -Evidence $detail }
    if ($protection -eq 'Off') { return New-Control -Control 'BitLocker' -Value 'Off' -Status 'Fail' -Evidence $detail }
    return New-Control -Control 'BitLocker' -Value $protection -Status 'Unknown' -Evidence $detail
}

function Get-AntivirusControl {
    param([bool] $IsWorkstation)
    $active = @()
    $notes = @()
    $securityCenterRead = $false
    if ($IsWorkstation) {
        try {
            foreach ($product in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName 'AntivirusProduct')) {
                if ((([int]$product.productState -band $ProductStateOnMask) -eq $ProductStateOn)) { $active += [string]$product.displayName }
            }
            $securityCenterRead = $true
            $notes += "Security Center: $(if ($active.Count -gt 0) { $active -join ', ' } else { 'no active product' })"
        }
        catch { $notes += "Security Center unreadable: $($_.Exception.Message)" }
    }
    if (Get-Command -Name 'Get-MpComputerStatus' -ErrorAction SilentlyContinue) {
        try {
            $defender = Get-MpComputerStatus
            $realTime = [bool](Get-PropertyOrNull -Source $defender -Name 'RealTimeProtectionEnabled')
            $enabled = [bool](Get-PropertyOrNull -Source $defender -Name 'AntivirusEnabled')
            $mode = [string](Get-PropertyOrNull -Source $defender -Name 'AMRunningMode')
            $isPassive = ($mode -like '*Passive*') -or ($mode -like '*EDR Block*')
            $notes += "Defender real-time $(if ($realTime) { 'on' } else { 'off' })$(if ($mode) { ', mode ' + $mode })"
            if ($enabled -and $realTime -and -not $isPassive -and -not $securityCenterRead) { $active += 'Microsoft Defender' }
        }
        catch { $notes += "Defender unreadable: $($_.Exception.Message)" }
    }
    $evidence = $notes -join '; '
    if ($notes.Count -eq 0) { return New-Control -Control 'Antivirus' -Value 'not readable' -Status 'Unknown' -Evidence 'Neither Security Center nor Defender could be read' }
    if ($active.Count -gt 0) { return New-Control -Control 'Antivirus' -Value (($active | Select-Object -Unique) -join ', ') -Status 'Pass' -Evidence $evidence }
    return New-Control -Control 'Antivirus' -Value 'none active' -Status 'Fail' -Evidence $evidence
}

function Get-EdrControl {
    param($Services)
    $running = @()
    $stopped = @()
    foreach ($product in $EdrProducts) {
        foreach ($service in @(Find-Service -Services $Services -Patterns @($product.Service))) {
            if ([string]$service.State -eq 'Running') { $running += $product.Tool } else { $stopped += $product.Tool }
        }
    }
    if ($running.Count -gt 0) { return New-Control -Control 'EDR' -Value (($running | Select-Object -Unique) -join ', ') -Status 'Pass' -Evidence 'EDR service running' }
    if ($stopped.Count -gt 0) { return New-Control -Control 'EDR' -Value (($stopped | Select-Object -Unique) -join ', ') -Status 'Fail' -Evidence 'EDR service installed but not running' }
    return New-Control -Control 'EDR' -Value 'none detected' -Status 'Unknown' -Evidence 'No product from the short list (Defender for Endpoint, CrowdStrike, SentinelOne, Huntress, Cylance, Carbon Black, Cortex); not every product is listed'
}

function Get-FirewallControl {
    $profiles = @(Get-NetFirewallProfile -PolicyStore 'ActiveStore')
    $parts = @()
    $off = @()
    foreach ($firewallProfile in $profiles) {
        $isOn = ([string]$firewallProfile.Enabled -eq 'True')
        $parts += "$($firewallProfile.Name) $(if ($isOn) { 'on' } else { 'off' })"
        if (-not $isOn) { $off += [string]$firewallProfile.Name }
    }
    if ($profiles.Count -eq 0) { return New-Control -Control 'Firewall' -Value 'not readable' -Status 'Unknown' -Evidence 'No firewall profiles returned' }
    $status = 'Pass'
    if ($off.Count -gt 0) { $status = 'Fail' }
    return New-Control -Control 'Firewall' -Value ($parts -join ', ') -Status $status -Evidence 'Enforced state (ActiveStore: local settings and Group Policy combined)'
}

function Get-LocalAdminName {
    # Members of the local Administrators group, by SID so the group name's language does not matter.
    try {
        return @(Get-LocalGroupMember -SID $AdministratorsSid -ErrorAction Stop | ForEach-Object { [string]$_.Name })
    }
    catch {
        $group = Get-CimInstance -ClassName Win32_Group -Filter "SID='$AdministratorsSid'"
        $names = @()
        foreach ($member in @(Get-CimAssociatedInstance -InputObject $group -Association Win32_GroupUser)) {
            $names += ("$($member.Domain)\$($member.Name)")
        }
        return $names
    }
}

function Get-LocalAdminControl {
    param([int] $MaxMembers)
    $names = @(Get-LocalAdminName)
    $status = 'Pass'
    if ($names.Count -gt $MaxMembers) { $status = 'Fail' }
    $list = if ($names.Count -gt 0) { $names -join ', ' } else { 'none' }
    return New-Control -Control 'Local admins' -Value "$($names.Count) member(s)" -Status $status -Evidence "Limit $MaxMembers; members: $list"
}

function Get-RdpControl {
    $denyPolicy = Get-RegistryValueOrNull -Path $TerminalPolicyKey -Name 'fDenyTSConnections'
    $deny = Get-RegistryValueOrNull -Path $TerminalServerKey -Name 'fDenyTSConnections'
    $nlaPolicy = Get-RegistryValueOrNull -Path $TerminalPolicyKey -Name 'UserAuthentication'
    $nla = Get-RegistryValueOrNull -Path $RdpTcpKey -Name 'UserAuthentication'
    $isOff = $true
    if ($null -ne $denyPolicy) { $isOff = ([int]$denyPolicy -eq 1) }
    elseif ($null -ne $deny) { $isOff = ([int]$deny -eq 1) }
    $nlaRequired = $true
    if ($null -ne $nlaPolicy) { $nlaRequired = ([int]$nlaPolicy -eq 1) }
    elseif ($null -ne $nla) { $nlaRequired = ([int]$nla -eq 1) }
    if ($isOff) { return New-Control -Control 'RDP' -Value 'Off' -Status 'Pass' -Evidence 'Remote Desktop connections are not allowed' }
    if ($nlaRequired) { return New-Control -Control 'RDP' -Value 'On, NLA required' -Status 'Pass' -Evidence 'Enabled with Network Level Authentication; internet exposure is not tested here (see test-rdp-exposure)' }
    return New-Control -Control 'RDP' -Value 'On, NLA not required' -Status 'Fail' -Evidence 'Remote Desktop is enabled without Network Level Authentication'
}

function Get-Smb1Control {
    $enabled = $null
    $source = ''
    try {
        $enabled = [bool](Get-SmbServerConfiguration -ErrorAction Stop).EnableSMB1Protocol
        $source = 'Get-SmbServerConfiguration'
    }
    catch {
        $raw = Get-RegistryValueOrNull -Path $LanmanServerKey -Name 'SMB1'
        if ($null -ne $raw) { $enabled = ([int]$raw -ne 0); $source = 'LanmanServer SMB1 registry value' }
    }
    if ($null -eq $enabled) { return New-Control -Control 'SMB1' -Value 'not readable' -Status 'Unknown' -Evidence 'Server configuration and the registry value both unreadable' }
    if ($enabled) { return New-Control -Control 'SMB1' -Value 'Enabled' -Status 'Fail' -Evidence "SMB1 server is on ($source)" }
    return New-Control -Control 'SMB1' -Value 'Disabled' -Status 'Pass' -Evidence "SMB1 server is off ($source)"
}

function Get-SecureBootControl {
    $state = Get-RegistryValueOrNull -Path $SecureBootStateKey -Name 'UEFISecureBootEnabled'
    if ($null -ne $state) {
        if ([int]$state -eq 1) { return New-Control -Control 'Secure Boot' -Value 'On' -Status 'Pass' -Evidence 'UEFISecureBootEnabled is 1' }
        return New-Control -Control 'Secure Boot' -Value 'Off' -Status 'Fail' -Evidence 'UEFISecureBootEnabled is 0'
    }
    try {
        if (Confirm-SecureBootUEFI) { return New-Control -Control 'Secure Boot' -Value 'On' -Status 'Pass' -Evidence 'Confirm-SecureBootUEFI' }
        return New-Control -Control 'Secure Boot' -Value 'Off' -Status 'Fail' -Evidence 'Confirm-SecureBootUEFI'
    }
    catch {
        if ($_.Exception.GetType().Name -eq 'PlatformNotSupportedException') {
            return New-Control -Control 'Secure Boot' -Value 'Not available' -Status 'Fail' -Evidence 'This PC boots in legacy BIOS mode: Secure Boot needs UEFI'
        }
        throw
    }
}

function Get-TpmControl {
    $present = $false
    $ready = $false
    if (Get-Command -Name 'Get-Tpm' -ErrorAction SilentlyContinue) {
        $tpm = Get-Tpm
        $present = [bool](Get-PropertyOrNull -Source $tpm -Name 'TpmPresent')
        $ready = [bool](Get-PropertyOrNull -Source $tpm -Name 'TpmReady')
    }
    else {
        $chip = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftTpm' -ClassName 'Win32_Tpm'
        $present = ($null -ne $chip)
        $ready = $present -and [bool](Get-PropertyOrNull -Source $chip -Name 'IsEnabled_InitialValue')
    }
    $version = ''
    try {
        $chip = Get-CimInstance -Namespace 'root/CIMV2/Security/MicrosoftTpm' -ClassName 'Win32_Tpm'
        $spec = [string](Get-PropertyOrNull -Source $chip -Name 'SpecVersion')
        if ($spec) { $version = ' version ' + ($spec -split ',')[0].Trim() }
    }
    catch { $null = $_ }
    if (-not $present) { return New-Control -Control 'TPM' -Value 'Not present' -Status 'Fail' -Evidence 'No TPM found (virtual machines often have none)' }
    if (-not $ready) { return New-Control -Control 'TPM' -Value 'Present, not ready' -Status 'Fail' -Evidence "TPM$version is present but not ready for use" }
    return New-Control -Control 'TPM' -Value 'Present and ready' -Status 'Pass' -Evidence "TPM$version"
}

function Get-ScreenLockControl {
    param([int] $MaxSeconds)
    $seconds = Get-RegistryValueOrNull -Path $SystemPolicyKey -Name 'InactivityTimeoutSecs'
    if ($null -eq $seconds -or [int]$seconds -lt 1) {
        return New-Control -Control 'Screen lock' -Value 'Not set' -Status 'Fail' -Evidence 'Machine policy InactivityTimeoutSecs is not set (per-user screen saver policies are not read)'
    }
    $status = 'Fail'
    if ([int]$seconds -le $MaxSeconds) { $status = 'Pass' }
    return New-Control -Control 'Screen lock' -Value "$([int]$seconds) s" -Status $status -Evidence "InactivityTimeoutSecs; limit $MaxSeconds s"
}

function Read-LocalPolicy {
    # The local security policy as name/value pairs, from secedit's INF export (UTF-16, key names are not translated).
    $folder = [IO.Path]::GetTempPath()
    $id = [Guid]::NewGuid().ToString('N')
    $infFile = Join-Path -Path $folder -ChildPath ("outpost-secpol-$id.inf")
    $logFile = Join-Path -Path $folder -ChildPath ("outpost-secpol-$id.log")
    $exe = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'secedit.exe'
    $policy = @{}
    try {
        $null = Invoke-NativeText -FilePath $exe -Arguments @('/export', '/cfg', $infFile, '/areas', 'SECURITYPOLICY', '/log', $logFile)
        if (-not (Test-Path -LiteralPath $infFile)) { throw 'secedit did not write the policy export' }
        foreach ($line in @(Get-Content -LiteralPath $infFile -Encoding Unicode)) {
            if ($line -match '^\s*([A-Za-z]+)\s*=\s*(.*?)\s*$') { $policy[$Matches[1]] = $Matches[2] }
        }
    }
    finally {
        Remove-Item -LiteralPath $infFile, $logFile -Force -ErrorAction SilentlyContinue
    }
    return $policy
}

function Get-PolicyNumber {
    param($Policy, [string] $Name)
    if ($null -eq $Policy -or -not $Policy.ContainsKey($Name)) { return $null }
    $number = 0
    if (-not [int]::TryParse([string]$Policy[$Name], [ref]$number)) { return $null }
    return $number
}

function Get-PasswordLengthControl {
    param($Policy, [int] $MinLength)
    $length = Get-PolicyNumber -Policy $Policy -Name 'MinimumPasswordLength'
    if ($null -eq $length) { return New-Control -Control 'Password length' -Value 'not readable' -Status 'Unknown' -Evidence 'MinimumPasswordLength not in the secedit export' }
    $status = 'Fail'
    if ($length -ge $MinLength) { $status = 'Pass' }
    return New-Control -Control 'Password length' -Value "$length characters" -Status $status -Evidence "MinimumPasswordLength; required $MinLength"
}

function Get-PasswordComplexityControl {
    param($Policy)
    $complexity = Get-PolicyNumber -Policy $Policy -Name 'PasswordComplexity'
    if ($null -eq $complexity) { return New-Control -Control 'Password complexity' -Value 'not readable' -Status 'Unknown' -Evidence 'PasswordComplexity not in the secedit export' }
    if ($complexity -eq 1) { return New-Control -Control 'Password complexity' -Value 'Required' -Status 'Pass' -Evidence 'PasswordComplexity is 1' }
    return New-Control -Control 'Password complexity' -Value 'Not required' -Status 'Fail' -Evidence 'PasswordComplexity is 0'
}

function Get-LockoutControl {
    param($Policy)
    $count = Get-PolicyNumber -Policy $Policy -Name 'LockoutBadCount'
    if ($null -eq $count) { return New-Control -Control 'Account lockout' -Value 'not readable' -Status 'Unknown' -Evidence 'LockoutBadCount not in the secedit export' }
    if ($count -gt 0) { return New-Control -Control 'Account lockout' -Value "After $count bad attempts" -Status 'Pass' -Evidence 'LockoutBadCount' }
    return New-Control -Control 'Account lockout' -Value 'Never locks out' -Status 'Fail' -Evidence 'LockoutBadCount is 0'
}

function Get-ServerBackupSeen {
    # True when Windows Server Backup has logged a finished run (language-independent event IDs).
    try {
        return (@(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Backup'; Id = $ServerBackupEventIds } -MaxEvents 1 -ErrorAction Stop).Count -gt 0)
    }
    catch {
        if ($_.FullyQualifiedErrorId -like '*NoMatching*') { return $false }
        throw
    }
}

function Get-BackupControl {
    param($Services)
    $names = @()
    foreach ($product in $BackupProducts) {
        if (@(Find-Service -Services $Services -Patterns $product.Services).Count -gt 0) { $names += $product.Tool }
    }
    if (Get-ServerBackupSeen) { $names += 'Windows Server Backup' }
    $evidence = 'Services and event logs; run test-backup-status to know whether the last backup succeeded'
    if ($names.Count -gt 0) { return New-Control -Control 'Backup product' -Value ($names -join ', ') -Status 'Pass' -Evidence $evidence }
    return New-Control -Control 'Backup product' -Value 'none found' -Status 'Fail' -Evidence 'No known backup product service or Windows Server Backup run found; a cloud or network backup may leave no local trace'
}

function Get-RemoteToolControl {
    param($Services)
    $names = @()
    foreach ($tool in $RemoteTools) {
        if (@(Find-Service -Services $Services -Patterns $tool.Services).Count -gt 0) { $names += $tool.Tool }
    }
    if ($names.Count -eq 0) { return New-Control -Control 'Remote access tools' -Value 'none found' -Status 'Pass' -Evidence 'No remote access service from the short list' }
    return New-Control -Control 'Remote access tools' -Value ($names -join ', ') -Status 'Unknown' -Evidence 'Review: only tools you approved should be here (get-remote-access-tools lists them in detail)'
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    $Config = [pscustomobject]@{
        MaxPatchAgeDays      = Read-OutpostInt -Name 'MaxPatchAgeDays' -Min 1 -Max 3650
        MaxScreenLockSeconds = Read-OutpostInt -Name 'MaxScreenLockSeconds' -Min 1 -Max 86400
        MinPasswordLength    = Read-OutpostInt -Name 'MinPasswordLength' -Min 1 -Max 128
        MaxLocalAdmins       = Read-OutpostInt -Name 'MaxLocalAdmins' -Min 1 -Max 100
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'Administrator rights are required to read BitLocker, the security policy and the services. Run the script as SYSTEM or an administrator.'
    }

    # Detect
    Write-OutpostLine -Text 'Collecting the device evidence for a cyber-insurance questionnaire (read-only).'
    $services = @(Get-CimInstance -ClassName Win32_Service)
    $isWorkstation = ((Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -eq $WorkstationProductType)
    $policy = $null
    $policyError = ''
    try { $policy = Read-LocalPolicy } catch { $policyError = (($_.Exception.Message -replace '\s+', ' ').Trim()) }

    $controls = New-Object -TypeName System.Collections.ArrayList
    [void]$controls.Add((Invoke-Control -Name 'OS support' -Code { Get-OsSupportControl }))
    [void]$controls.Add((Invoke-Control -Name 'Patch age' -Code { Get-PatchControl -MaxAgeDays $Config.MaxPatchAgeDays }))
    [void]$controls.Add((Invoke-Control -Name 'BitLocker' -Code { Get-BitLockerControl }))
    [void]$controls.Add((Invoke-Control -Name 'Antivirus' -Code { Get-AntivirusControl -IsWorkstation $isWorkstation }))
    [void]$controls.Add((Invoke-Control -Name 'EDR' -Code { Get-EdrControl -Services $services }))
    [void]$controls.Add((Invoke-Control -Name 'Firewall' -Code { Get-FirewallControl }))
    [void]$controls.Add((Invoke-Control -Name 'Local admins' -Code { Get-LocalAdminControl -MaxMembers $Config.MaxLocalAdmins }))
    [void]$controls.Add((Invoke-Control -Name 'RDP' -Code { Get-RdpControl }))
    [void]$controls.Add((Invoke-Control -Name 'SMB1' -Code { Get-Smb1Control }))
    [void]$controls.Add((Invoke-Control -Name 'Secure Boot' -Code { Get-SecureBootControl }))
    [void]$controls.Add((Invoke-Control -Name 'TPM' -Code { Get-TpmControl }))
    [void]$controls.Add((Invoke-Control -Name 'Screen lock' -Code { Get-ScreenLockControl -MaxSeconds $Config.MaxScreenLockSeconds }))
    if ($null -eq $policy) {
        foreach ($policyName in @('Password length', 'Password complexity', 'Account lockout')) {
            [void]$controls.Add((New-Control -Control $policyName -Value 'not readable' -Status 'Unknown' -Evidence "Local security policy could not be exported: $policyError"))
        }
    }
    else {
        [void]$controls.Add((Invoke-Control -Name 'Password length' -Code { Get-PasswordLengthControl -Policy $policy -MinLength $Config.MinPasswordLength }))
        [void]$controls.Add((Invoke-Control -Name 'Password complexity' -Code { Get-PasswordComplexityControl -Policy $policy }))
        [void]$controls.Add((Invoke-Control -Name 'Account lockout' -Code { Get-LockoutControl -Policy $policy }))
    }
    [void]$controls.Add((Invoke-Control -Name 'Backup product' -Code { Get-BackupControl -Services $services }))
    [void]$controls.Add((Invoke-Control -Name 'Remote access tools' -Code { Get-RemoteToolControl -Services $services }))

    foreach ($control in $controls) {
        Add-OutpostRow -Values @{ Control = $control.Control; Value = $control.Value; Status = $control.Status; Evidence = $control.Evidence }
    }

    # Finish
    $passCount = @($controls | Where-Object { $_.Status -eq 'Pass' }).Count
    $failNames = @($controls | Where-Object { $_.Status -eq 'Fail' } | ForEach-Object { $_.Control })
    $unknownCount = @($controls | Where-Object { $_.Status -eq 'Unknown' }).Count
    $answer = "$passCount of $($controls.Count) controls pass; fails: "
    if ($failNames.Count -gt 0) { $answer += ($failNames -join ', ') } else { $answer += 'none' }
    if ($unknownCount -gt 0) { $answer += "; $unknownCount unknown" }
    Complete-OutpostRun -Status 'OK' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
