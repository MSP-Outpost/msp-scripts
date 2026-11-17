#Requires -Version 5.1
<#
.SYNOPSIS
    Alerts when events that match an event ID, source or text appear in a Windows event log.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. It reads one event log for the last
    LookbackMinutes and counts the events that match every filter you set:
    event IDs, providers (sources), a piece of the message text, and a
    severity. It alerts (exit 1) when the count is more than MaxEvents. The 25
    newest matches are listed.

    Set at least one of EventIds, Providers, MessageMatch, or a Level other
    than Any. A filter left empty is not applied. At most 5000 events are read
    per run; narrow the filters if that is not enough.

    A Providers name that is not registered on the PC produces a WARNING (it
    may be misspelled) and the run still ends OK when nothing matched.

    Message text is matched as plain text, ignoring case. An unknown LogName is
    an error, so a typo cannot pass as "no events".

.PARAMETER LogName
    The event log to read, e.g. System, Application, Security or
    "Microsoft-Windows-TaskScheduler/Operational". Default System.
    Environment variable: LogName

.PARAMETER EventIds
    Event IDs to match, separated by commas, e.g. "41, 6008". At most 20.
    Default any.
    Environment variable: EventIds

.PARAMETER Providers
    Event sources to match, separated by commas, e.g. "disk, Ntfs". Wildcards
    * and ? work. Default any.
    Environment variable: Providers

.PARAMETER MessageMatch
    Text the event message must contain. Default any.
    Environment variable: MessageMatch

.PARAMETER Level
    Severity: Critical, Error (Critical and Error), Warning (Critical, Error
    and Warning) or Any. Default Error.
    Environment variable: Level

.PARAMETER LookbackMinutes
    How far back to read. Whole number, 1 to 43200. Default 60.
    Environment variable: LookbackMinutes

.PARAMETER MaxEvents
    Alert when more than this many events match. Whole number, 0 to 100000.
    Default 0 (any match alerts).
    Environment variable: MaxEvents

.PARAMETER DryRun
    Reserved; ignored by Monitors.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\test-event-log-match.ps1 -EventIds "7034, 7031" -Providers "Service Control Manager" -Level Any

    Alerts when a service crashed in the last hour.

.EXAMPLE
    .\test-event-log-match.ps1 -LogName Application -MessageMatch "backup failed" -LookbackMinutes 1440

    Alerts when an Application event from the last day mentions "backup failed".

.NOTES
    Name:        Something is logging errors - event ID and text match monitor
    Slug:        test-event-log-match
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Monitor
    Category:    09 Monitoring & health checks
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1; administrator rights
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 20 seconds
    Answer:      "3 matching events in System in the last 60 min; latest 7034 Service Control Manager"
    Fields:      TimeUtc, Level, EventId, Provider, Message
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/test-event-log-match
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # THIS SCRIPT'S inputs. Strings on purpose: RMMs send text. Defaults are the
    # place to edit when your RMM cannot pass arguments or variables.
    [string] $LogName = 'System',
    [string] $EventIds = '',
    [string] $Providers = '',
    [string] $MessageMatch = '',
    [string] $Level = 'Error',
    [string] $LookbackMinutes = '60',
    [string] $MaxEvents = '0',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'test-event-log-match'
    Version = '1.0.0'
    Type    = 'Monitor'
    Risk    = 'Low'
    Inputs  = @('LogName', 'EventIds', 'Providers', 'MessageMatch', 'Level', 'LookbackMinutes', 'MaxEvents')
    Fields  = @('TimeUtc', 'Level', 'EventId', 'Provider', 'Message')
}

#region MSP Outpost runtime 1.0.0 -- do not edit.
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
    # DOMAIN\user of the console session, or $null when nobody is signed in.
    $user = (Get-CimInstance -ClassName Win32_ComputerSystem).UserName
    if ([string]::IsNullOrWhiteSpace($user)) { return $null }
    return $user
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
    return (Join-Path -Path $base -ChildPath 'MSPOutpost')
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

function Write-OutpostField {
    param([string] $Name, [string] $Value)
    try {
        if (Get-Command -Name 'Ninja-Property-Set' -ErrorAction SilentlyContinue) {
            Ninja-Property-Set $Name $Value
            return
        }
        if ($env:NINJARMMCLI -and (Test-Path -LiteralPath $env:NINJARMMCLI)) {
            & $env:NINJARMMCLI set $Name $Value | Out-Null
            return
        }
        if ($env:SyncroModule) {
            Import-Module -Name $env:SyncroModule -WarningAction SilentlyContinue
            Set-Asset-Field -Name $Name -Value $Value
            return
        }
        if ($env:CS_PROFILE_UID -or (Test-Path -LiteralPath 'HKLM:\SOFTWARE\CentraStage')) {
            if ($Name -notmatch '^(?:Custom)?([1-9][0-9]?|[12][0-9][0-9]|300)$') {
                Write-OutpostWarning -Text "Datto RMM: ResultField must be a UDF number from 1 to 300, not '$Name'."
                return
            }
            $udf = 'Custom' + $Matches[1]
            if ($Value.Length -gt 255) { $Value = $Value.Substring(0, 255) }
            $null = New-ItemProperty -Path 'HKLM:\SOFTWARE\CentraStage' -Name $udf -Value $Value -PropertyType String -Force
            return
        }
        Write-OutpostWarning -Text 'ResultField is set but no supported RMM was detected; the answer is in the RESULT line.'
    }
    catch {
        Write-OutpostWarning -Text "Could not write ResultField '$Name': $($_.Exception.Message)"
    }
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
    if ($resultField -ne '') {
        $fieldValue = if ($null -ne $script:OutpostRun.FieldValue) { $script:OutpostRun.FieldValue } else { $Answer }
        Write-OutpostField -Name $resultField -Value $fieldValue
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
$MaxEventsRead = 5000
$MaxRows = 25
$MessageRowLength = 100

# ---- Functions ------------------------------------------------------------
function Get-LevelNumber {
    param([string] $Name)
    switch ($Name) {
        'Critical' { return @(1) }
        'Error' { return @(1, 2) }
        'Warning' { return @(1, 2, 3) }
        default { return @() }
    }
}

function Get-MatchingEvent {
    param([hashtable] $Filter)
    try {
        return @(Get-WinEvent -FilterHashtable $Filter -MaxEvents $MaxEventsRead)
    }
    catch {
        # Expected "nothing to find" outcomes: no events matched, or a named provider
        # that has never logged here (NoMatchingProvidersFound; the message check is a fallback).
        $errorId = [string]$_.FullyQualifiedErrorId
        if ($errorId -like 'NoMatchingEventsFound*' -or $errorId -like 'NoMatchingProvidersFound*' -or $_.Exception.Message -like '*not an event provider*') { return @() }
        throw
    }
}

function Format-MessageText {
    param($LogEvent, [int] $Length)
    $text = [string]$LogEvent.Message
    $text = ($text -replace '\s+', ' ' -replace '[^\x20-\x7E]', '?').Trim()
    if ($text.Length -gt $Length) { $text = $text.Substring(0, $Length - 3) + '...' }
    return $text
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    $idNumbers = @()
    foreach ($text in @(Read-OutpostList -Name 'EventIds')) {
        $number = 0
        if (-not [int]::TryParse($text, [ref]$number) -or $number -lt 0 -or $number -gt 65535) {
            Stop-OutpostInput -Name 'EventIds' -Value $text -Expected 'event IDs from 0 to 65535 separated by commas'
        }
        $idNumbers += $number
    }
    if ($idNumbers.Count -gt 20) {
        Stop-OutpostRun -Message "EventIds has $($idNumbers.Count) values; Windows accepts at most 20 in one filter. Split them across two monitors."
    }
    $Config = [pscustomobject]@{
        LogName         = Read-OutpostText -Name 'LogName' -Required
        EventIds        = $idNumbers
        Providers       = @(Read-OutpostList -Name 'Providers')
        MessageMatch    = Read-OutpostText -Name 'MessageMatch'
        Level           = Read-OutpostChoice -Name 'Level' -Allowed @('Critical', 'Error', 'Warning', 'Any')
        LookbackMinutes = Read-OutpostInt -Name 'LookbackMinutes' -Min 1 -Max 43200
        MaxEvents       = Read-OutpostInt -Name 'MaxEvents' -Min 0 -Max 100000
    }
    if ($Config.EventIds.Count -eq 0 -and $Config.Providers.Count -eq 0 -and $Config.MessageMatch -eq '' -and $Config.Level -eq 'Any') {
        Stop-OutpostRun -Message 'No filter is set, so every event would match. Set EventIds, Providers, MessageMatch, or a Level other than Any.'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'Administrator rights are required to read event logs. Run the script as SYSTEM or an administrator.'
    }
    if ($Config.LogName -match '[*?]') {
        Stop-OutpostRun -Message "LogName '$($Config.LogName)' must be one exact log name, without * or ?. Run Get-WinEvent -ListLog * to see the names."
    }
    $logInfo = $null
    try { $logInfo = Get-WinEvent -ListLog $Config.LogName -ErrorAction Stop }
    catch {
        Stop-OutpostRun -Message "The event log '$($Config.LogName)' was not found. Run Get-WinEvent -ListLog * to see the names, then set LogName."
    }
    if (-not $logInfo.IsEnabled) {
        Stop-OutpostRun -Message "The event log '$($Config.LogName)' is disabled, so no events are being recorded. Enable it or set a different LogName."
    }

    foreach ($providerName in $Config.Providers) {
        if ($providerName -match '[*?]') { continue }
        try { $null = Get-WinEvent -ListProvider $providerName -ErrorAction Stop }
        catch { Write-OutpostWarning -Text "Provider '$providerName' is not registered on this PC, so it may be misspelled. Run Get-WinEvent -ListProvider * to see the names." }
    }

    # Detect
    Write-OutpostLine -Text "Reading $($Config.LogName) for the last $($Config.LookbackMinutes) minute(s)."
    $filter = @{ LogName = $Config.LogName; StartTime = (Get-Date).AddMinutes(-$Config.LookbackMinutes) }
    if ($Config.EventIds.Count -gt 0) { $filter['Id'] = [int[]]$Config.EventIds }
    if ($Config.Providers.Count -gt 0) { $filter['ProviderName'] = [string[]]$Config.Providers }
    $levelNumbers = @(Get-LevelNumber -Name $Config.Level)
    if ($levelNumbers.Count -gt 0) { $filter['Level'] = [int[]]$levelNumbers }
    $events = @(Get-MatchingEvent -Filter $filter)
    if ($events.Count -ge $MaxEventsRead) {
        Write-OutpostWarning -Text "Read the newest $MaxEventsRead events only; narrow the filters or shorten LookbackMinutes."
    }
    if ($Config.MessageMatch -ne '') {
        $events = @($events | Where-Object { ([string]$_.Message).IndexOf($Config.MessageMatch, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
    }

    foreach ($logEvent in ($events | Select-Object -First $MaxRows)) {
        Add-OutpostRow -Values @{
            TimeUtc  = $logEvent.TimeCreated.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
            Level    = [string]$logEvent.LevelDisplayName
            EventId  = $logEvent.Id
            Provider = [string]$logEvent.ProviderName
            Message  = Format-MessageText -LogEvent $logEvent -Length $MessageRowLength
        }
    }

    # Finish
    $count = $events.Count
    $scope = "in $($Config.LogName) in the last $($Config.LookbackMinutes) min"
    if ($count -eq 0) {
        Complete-OutpostRun -Status 'OK' -Answer "No matching events $scope."
    }
    $newest = $events | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1
    $summary = "$count matching event(s) $scope; latest $($newest.Id) $($newest.ProviderName)"
    if ($count -gt $Config.MaxEvents) { Complete-OutpostRun -Status 'ALERT' -Answer $summary }
    Complete-OutpostRun -Status 'OK' -Answer "$summary; within limit $($Config.MaxEvents)"
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
