#Requires -Version 5.1
<#
.SYNOPSIS
    Lists the other RMM and remote-management agents installed on this PC.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. It looks for about 25 RMM, endpoint-management
    and remote-management agents (Datto RMM, NinjaOne, N-able N-central and
    N-sight, Kaseya, ConnectWise Automate and RMM, Atera, Syncro, Tactical
    RMM, Action1, Pulseway, Level, SuperOps, ManageEngine, Naverisk, ImmyBot,
    GoTo Resolve, Xcitium and more) in three places: Windows services, the
    installed-programs list (HKLM, 64-bit and 32-bit) and program folders.

    A product counts as installed when it has a service or an
    installed-programs entry. A program folder on its own is reported as a
    leftover and is not counted. Microsoft Intune's management extension is
    listed as "Microsoft (MDM)".

    Use it before onboarding a client to see which tool the old provider left
    behind, and after a migration to prove the old agent is gone.

    ResultField receives the product names as a comma list, or "None".

.PARAMETER DryRun
    Reserved; ignored by Reports.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the product list to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\get-rmm-agents.ps1

    Prints one row per RMM agent found, then the one-line answer.

.EXAMPLE
    .\get-rmm-agents.ps1 -OutputFormat Json

    Prints one JSON object with the rows.

.NOTES
    Name:        Which other RMM agents are on this PC
    Slug:        get-rmm-agents
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Report
    Category:    01 Onboarding & provisioning
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 15 seconds
    Answer:      "2 RMM agents: Datto RMM, ScreenConnect"
    Fields:      Product, Evidence, Version, ServiceState
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/get-rmm-agents
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # This script has no inputs of its own.

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'get-rmm-agents'
    Version = '1.0.0'
    Type    = 'Report'
    Risk    = 'Low'
    Inputs  = @()
    Fields  = @('Product', 'Evidence', 'Version', 'ServiceState')
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
# Detection table. Services: service names (wildcards allowed). Names: the
# installed-programs display name (wildcards allowed). Folders: program
# folders; environment variables are expanded when the script runs.
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$RmmAgents = @(
    @{ Product = 'Datto RMM'; Services = @('CagService'); Names = @('Datto RMM*', 'CentraStage*'); Folders = @('%ProgramData%\CentraStage', '%ProgramFiles(x86)%\CentraStage', '%ProgramFiles%\CentraStage') },
    @{ Product = 'NinjaOne'; Services = @('NinjaRMMAgent'); Names = @('NinjaRMMAgent*', 'NinjaOne*'); Folders = @('%ProgramFiles%\NinjaRMMAgent', '%ProgramData%\NinjaRMMAgent', '%ProgramFiles(x86)%\NinjaRMMAgent') },
    @{ Product = 'N-able N-central'; Services = @('Windows Agent Service', 'Windows Agent Maintenance Service'); Names = @('Windows Agent', 'N-able N-central*'); Folders = @('%ProgramFiles(x86)%\N-able Technologies\Windows Agent', '%ProgramFiles%\N-able Technologies\Windows Agent') },
    @{ Product = 'N-able N-sight'; Services = @('Advanced Monitoring Agent*'); Names = @('Advanced Monitoring Agent*'); Folders = @('%ProgramFiles(x86)%\Advanced Monitoring Agent', '%ProgramFiles%\Advanced Monitoring Agent', '%ProgramFiles(x86)%\Advanced Monitoring Agent GP') },
    @{ Product = 'Kaseya VSA'; Services = @('Kaseya Agent*', 'KaseyaAgent*'); Names = @('Kaseya Agent*'); Folders = @('%ProgramFiles%\Kaseya', '%ProgramFiles(x86)%\Kaseya') },
    @{ Product = 'ConnectWise Automate'; Services = @('LTService', 'LTSvcMon'); Names = @('LabTech*', 'ConnectWise Automate*'); Folders = @('%WinDir%\LTSvc') },
    @{ Product = 'ConnectWise RMM'; Services = @('ITSPlatform*'); Names = @('ITSPlatform*', 'ConnectWise RMM*'); Folders = @('%ProgramFiles(x86)%\ITSPlatform', '%ProgramFiles%\ITSPlatform') },
    @{ Product = 'Atera'; Services = @('AteraAgent'); Names = @('AteraAgent*', 'Atera Agent*'); Folders = @('%ProgramFiles%\ATERA Networks', '%ProgramFiles(x86)%\ATERA Networks') },
    @{ Product = 'Syncro'; Services = @('Syncro', 'SyncroLive', 'SyncroOvermind'); Names = @('Syncro*'); Folders = @('%ProgramFiles%\RepairTech', '%ProgramFiles(x86)%\RepairTech', '%ProgramData%\Syncro') },
    @{ Product = 'Tactical RMM'; Services = @('tacticalrmm', 'tacticalagent'); Names = @('Tactical RMM*', 'Tactical Agent*'); Folders = @('%ProgramFiles%\TacticalAgent', '%ProgramData%\TacticalRMM') },
    @{ Product = 'Action1'; Services = @('A1Agent'); Names = @('Action1 Agent*', 'Action1*'); Folders = @('%WinDir%\Action1', '%ProgramFiles%\Action1') },
    @{ Product = 'Pulseway'; Services = @('PCMonitorSrv'); Names = @('Pulseway*'); Folders = @('%ProgramFiles%\Pulseway', '%ProgramFiles(x86)%\Pulseway') },
    @{ Product = 'Level'; Services = @('Level'); Names = @('Level'); Folders = @('%ProgramFiles%\Level') },
    @{ Product = 'SuperOps'; Services = @('SuperOps*'); Names = @('SuperOps*'); Folders = @('%ProgramFiles%\SuperOps', '%ProgramFiles(x86)%\SuperOps') },
    @{ Product = 'ManageEngine Endpoint Central'; Services = @('ManageEngine*', 'DesktopCentral*'); Names = @('ManageEngine*Agent*', 'ManageEngine UEMS*', 'ManageEngine Desktop Central*'); Folders = @('%ProgramFiles(x86)%\DesktopCentral_Agent', '%ProgramFiles%\DesktopCentral_Agent') },
    @{ Product = 'Naverisk'; Services = @('Naverisk*'); Names = @('Naverisk*'); Folders = @('%ProgramFiles(x86)%\Naverisk', '%ProgramFiles%\Naverisk') },
    @{ Product = 'Auvik collector'; Services = @('Auvik*'); Names = @('Auvik*'); Folders = @('%ProgramFiles(x86)%\Auvik', '%ProgramFiles%\Auvik') },
    @{ Product = 'ImmyBot'; Services = @('Immy*'); Names = @('Immy*'); Folders = @('%ProgramFiles%\ImmyBot', '%ProgramData%\ImmyBot') },
    @{ Product = 'GoTo Resolve'; Services = @('GoToResolve*', 'GoTo Resolve*'); Names = @('GoTo Resolve*'); Folders = @('%ProgramFiles(x86)%\GoTo Resolve Unattended', '%ProgramFiles%\GoTo Resolve Unattended') },
    @{ Product = 'Xcitium (Comodo)'; Services = @('ITSMService', 'Xcitium*'); Names = @('COMODO ITSM*', 'Comodo ITSM*', 'ITarian*', 'Xcitium*'); Folders = @('%ProgramFiles%\COMODO\COMODO ITSM', '%ProgramFiles(x86)%\COMODO\COMODO ITSM') },
    @{ Product = 'Automox'; Services = @('amagent'); Names = @('Automox Agent*'); Folders = @('%ProgramFiles(x86)%\Automox', '%ProgramFiles%\Automox') },
    @{ Product = 'Barracuda RMM'; Services = @('Barracuda RMM*'); Names = @('Barracuda RMM*', 'Service Center*Agent*'); Folders = @('%ProgramFiles(x86)%\Barracuda RMM', '%ProgramFiles%\Barracuda RMM') },
    @{ Product = 'MeshCentral'; Services = @('Mesh Agent'); Names = @('Mesh Agent*'); Folders = @('%ProgramFiles%\Mesh Agent') },
    @{ Product = 'ScreenConnect'; Services = @('ScreenConnect Client (*)'); Names = @('ScreenConnect Client (*)'); Folders = @('%ProgramFiles(x86)%\ScreenConnect Client (*)', '%ProgramFiles%\ScreenConnect Client (*)') },
    @{ Product = 'Microsoft (MDM)'; Services = @('IntuneManagementExtension'); Names = @('Microsoft Intune Management Extension'); Folders = @('%ProgramFiles(x86)%\Microsoft Intune Management Extension') }
)

# ---- Functions ------------------------------------------------------------
function Get-RegistryValue {
    # Strict mode throws on a missing property, so read through the property bag.
    param($Item, [string] $Name)
    $property = $Item.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-InstalledProgram {
    $programs = @()
    foreach ($keyPattern in $UninstallKeys) {
        foreach ($item in @(Get-ItemProperty -Path $keyPattern -ErrorAction SilentlyContinue)) {
            $displayName = Get-RegistryValue -Item $item -Name 'DisplayName'
            if ($displayName) {
                $programs += [pscustomobject]@{ DisplayName = [string]$displayName; DisplayVersion = [string](Get-RegistryValue -Item $item -Name 'DisplayVersion') }
            }
        }
    }
    return $programs
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

function Get-FileVersionText {
    param([string] $Path)
    try {
        if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            $text = (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
            if ($text) { return ([string]$text -split ' ')[0] }
        }
    }
    catch { $null = $_ }
    return ''
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: this script reads no inputs; the runtime checked the reserved ones.

    # Detect
    Write-OutpostLine -Text 'Looking for RMM agents in services, installed programs and program folders.'
    $services = @(Get-CimInstance -ClassName Win32_Service)
    $programs = @(Get-InstalledProgram)

    $foundNames = @()
    $leftoverNames = @()
    foreach ($agent in $RmmAgents) {
        $evidence = @()
        $version = ''
        $serviceState = ''
        $isInstalled = $false

        foreach ($service in $services) {
            foreach ($pattern in $agent.Services) {
                if ($service.Name -like $pattern) {
                    $isInstalled = $true
                    $evidence += "Service $($service.Name)"
                    if ($serviceState -eq '' -or $service.State -eq 'Running') { $serviceState = [string]$service.State }
                    if ($version -eq '') { $version = Get-FileVersionText -Path (Get-ExecutablePath -CommandLine $service.PathName) }
                    break
                }
            }
        }
        foreach ($program in $programs) {
            foreach ($pattern in $agent.Names) {
                if ($program.DisplayName -like $pattern) {
                    $isInstalled = $true
                    $evidence += "Installed program '$($program.DisplayName)'"
                    if ($program.DisplayVersion) { $version = $program.DisplayVersion }
                    break
                }
            }
        }
        $folderEvidence = @()
        foreach ($folder in $agent.Folders) {
            $expanded = [Environment]::ExpandEnvironmentVariables($folder)
            foreach ($found in @(Get-Item -Path $expanded -Force -ErrorAction SilentlyContinue)) {
                $folderEvidence += "Folder $($found.FullName)"
            }
        }

        if ($isInstalled) {
            $foundNames += $agent.Product
            Add-OutpostRow -Values @{ Product = $agent.Product; Evidence = (($evidence + $folderEvidence) -join '; '); Version = $version; ServiceState = $serviceState }
        }
        elseif ($folderEvidence.Count -gt 0) {
            $leftoverNames += $agent.Product
            Add-OutpostRow -Values @{ Product = $agent.Product; Evidence = ('Leftover folder only: ' + ($folderEvidence -join '; ')); Version = ''; ServiceState = '' }
        }
    }

    # Finish
    $leftoverText = ''
    if ($leftoverNames.Count -gt 0) { $leftoverText = '; leftover folder of: ' + ($leftoverNames -join ', ') }
    if ($foundNames.Count -eq 0) {
        Set-OutpostFieldValue -Value 'None'
        Complete-OutpostRun -Status 'OK' -Answer ('No other RMM agents found' + $leftoverText)
    }
    Set-OutpostFieldValue -Value ($foundNames -join ', ')
    $plural = if ($foundNames.Count -eq 1) { '' } else { 's' }
    Complete-OutpostRun -Status 'OK' -Answer ("$($foundNames.Count) RMM agent${plural}: " + ($foundNames -join ', ') + $leftoverText)
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
