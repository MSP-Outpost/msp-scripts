#Requires -Version 5.1
<#
.SYNOPSIS
    Repairs a corrupted Windows image: DISM component store check and repair, then SFC.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It checks first and repairs only what is broken:

      * DISM ScanHealth reads the component store state (Healthy, Repairable or
        NonRepairable) and sfc /verifyonly checks the protected system files.
        Both only read.
      * When the component store is damaged, DISM RestoreHealth repairs it from
        Windows Update, or from Source when you give one (an install.wim or
        install.esd of the SAME Windows build; LimitAccess then stops it
        contacting Windows Update).
      * When system files are damaged, or the store was just repaired, it runs
        sfc /scannow, then re-checks with sfc /verifyonly.

    Results come from the DISM health state, sfc's own output (decoded from
    UTF-16) and the [SR] lines sfc adds to C:\Windows\Logs\CBS\CBS.log.

    Mode Auto (default) checks and repairs what it finds. Mode Scan only
    checks and changes nothing: damage found is reported as an ERROR so the
    RMM flags it. Mode Repair runs RestoreHealth and sfc /scannow even when
    the checks look clean.

    Takes 10 to 40 minutes. Set your RMM script timeout to at least 60
    minutes. Each sfc run is stopped after 60 minutes; the DISM step is not
    timed. It never reboots; when files are replaced on the next boot the
    answer says "reboot needed".

.PARAMETER Mode
    Auto (check, then repair what is damaged), Scan (check only) or Repair
    (always run RestoreHealth and sfc /scannow). Default Auto.
    Environment variable: Mode

.PARAMETER Source
    Optional repair source for DISM, for example wim:D:\sources\install.wim:1
    or esd:D:\sources\install.esd:1 (image index after the last colon). Must
    match the installed Windows build. Default empty (use Windows Update).
    Environment variable: Source

.PARAMETER LimitAccess
    true to stop DISM using Windows Update (use with Source). Default false.
    Environment variable: LimitAccess

.PARAMETER DryRun
    true to run the read-only checks and list the repairs it would make,
    making none. Default false. -WhatIf does the same. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\repair-windows-image.ps1 -Mode Scan

    Checks the component store and system files and changes nothing.

.EXAMPLE
    .\repair-windows-image.ps1 -Source wim:D:\sources\install.wim:1 -LimitAccess true

    Repairs from a mounted Windows ISO without using Windows Update.

.NOTES
    Name:        Windows corrupted or SFC fails - DISM then SFC repair
    Slug:        repair-windows-image
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    14 Remediation & self-healing
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, internet or a Source for DISM
    Changes:     Repairs the Windows component store (DISM) and replaces corrupt protected system files (SFC)
    Risk:        Low
    Reboot:      May
    Runtime:     10 to 40 minutes
    Answer:      "Repaired: DISM restored the component store; SFC fixed 3 files"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/repair-windows-image
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # THIS SCRIPT'S inputs.
    [string] $Mode = 'Auto',
    [string] $Source = '',
    [string] $LimitAccess = 'false',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'repair-windows-image'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('Mode', 'Source', 'LimitAccess')
    Fields  = @('Item', 'Change', 'Result')
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
$SfcPath = "$env:SystemRoot\System32\sfc.exe"
$CbsLogPath = "$env:SystemRoot\Logs\CBS\CBS.log"
$SfcTimeoutMinutes = 60
$CbsRestartKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
$UpdateRestartKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
$SessionManagerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
$RestartPendingAnswer = 'Skipped: a repair or update is waiting for a restart; restart the PC, then run again.'

# ---- Functions ------------------------------------------------------------
function Get-RestartHint {
    # Restart flags that many healthy PCs carry: a warning only. sfc's own
    # "repair pending" verdict decides whether it can run.
    $hints = @()
    if (Test-Path -LiteralPath $UpdateRestartKey) { $hints += 'Windows Update asks for a restart' }
    $renames = Get-ItemProperty -LiteralPath $SessionManagerKey -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($renames) { $hints += 'file renames wait for a restart' }
    return $hints
}

function Get-ImageHealthState {
    # DISM /Online /Cleanup-Image /ScanHealth through the Dism module: the
    # state is an enum (Healthy, Repairable, NonRepairable), so it does not
    # depend on the language of the Windows install.
    $result = Repair-WindowsImage -Online -ScanHealth
    if (-not $result -or -not ($result.PSObject.Properties.Name -contains 'ImageHealthState')) {
        throw 'DISM ScanHealth did not return an image health state. Run DISM /Online /Cleanup-Image /ScanHealth by hand and read C:\Windows\Logs\DISM\dism.log.'
    }
    return [string]$result.ImageHealthState
}

function Read-CbsRepairLine {
    param([long] $FromByte)
    if (-not (Test-Path -LiteralPath $CbsLogPath)) { return @() }
    $stream = New-Object -TypeName System.IO.FileStream -ArgumentList $CbsLogPath, ([System.IO.FileMode]::Open), ([System.IO.FileAccess]::Read), ([System.IO.FileShare]::ReadWrite)
    try {
        if ($FromByte -gt 0 -and $FromByte -le $stream.Length) { $null = $stream.Seek($FromByte, [System.IO.SeekOrigin]::Begin) }
        $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $stream, ([System.Text.Encoding]::Default)
        $text = $reader.ReadToEnd()
    }
    finally { $stream.Dispose() }
    return @($text -split "`r?`n" | Where-Object { $_ -match '\[SR\]' })
}

function Invoke-SfcRun {
    # Runs sfc.exe, decodes its UTF-16 output and collects the [SR] lines it
    # added to CBS.log during the run.
    param([string] $Argument)
    $startByte = 0
    if (Test-Path -LiteralPath $CbsLogPath) { $startByte = (Get-Item -LiteralPath $CbsLogPath).Length }
    $info = New-Object -TypeName System.Diagnostics.ProcessStartInfo
    $info.FileName = $SfcPath
    $info.Arguments = $Argument
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.StandardOutputEncoding = [System.Text.Encoding]::Unicode
    $process = [System.Diagnostics.Process]::Start($info)
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    if (-not $process.WaitForExit($SfcTimeoutMinutes * 60 * 1000)) {
        try { $process.Kill() } catch { $null = $_ }
        throw "sfc $Argument did not finish in $SfcTimeoutMinutes minutes and was stopped. Reboot the machine and run again."
    }
    $output = ($outputTask.Result -replace "`0", '')
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output   = $output
        CbsLines = @(Read-CbsRepairLine -FromByte $startByte)
    }
}

function Get-SfcVerdict {
    # State: Clean, Corrupt (found, not repaired), Repaired, Unrepairable,
    # Pending (needs a reboot first) or Failed (could not tell).
    param([object] $Run)
    $cbsText = $Run.CbsLines -join "`n"
    $repairedFiles = @($Run.CbsLines | Where-Object { $_ -match 'Repairing corrupted file' } | ForEach-Object { ($_ -replace '^.*Repairing corrupted file\s*', '') -replace '\s+from store\s*$', '' } | Select-Object -Unique)
    $cannotFiles = @($Run.CbsLines | Where-Object { $_ -match 'Cannot repair member file' } | Select-Object -Unique)
    $hasHint = ($repairedFiles.Count + $cannotFiles.Count) -gt 0 -or $cbsText -match 'Hashes for file member|do not match'
    $state = 'Failed'
    if ($Run.Output -match 'repair pending|pending which requires') { $state = 'Pending' }
    elseif ($Run.Output -match 'did not find any integrity violations') { $state = 'Clean' }
    elseif ($cannotFiles.Count -gt 0 -or $Run.Output -match 'unable to fix') { $state = 'Unrepairable' }
    elseif ($Run.Output -match 'successfully repaired') { $state = 'Repaired' }
    elseif ($Run.Output -match 'found integrity violations') { $state = 'Corrupt' }
    elseif ($Run.Output -match 'could not perform the requested operation') { $state = 'Failed' }
    elseif ($hasHint -and $repairedFiles.Count -gt 0) { $state = 'Repaired' }
    elseif ($hasHint) { $state = 'Corrupt' }
    elseif ($Run.ExitCode -eq 0 -and $cbsText -match 'Verify complete') { $state = 'Clean' }
    return [pscustomobject]@{
        State         = $state
        RepairedCount = $repairedFiles.Count
        CannotCount   = $cannotFiles.Count
    }
}

function Get-SfcAdvice {
    param([string] $State)
    switch ($State) {
        'Pending' { 'a repair is pending: reboot, then run again' }
        'Failed' { 'sfc could not run: reboot, then run again; if it repeats, read C:\Windows\Logs\CBS\CBS.log' }
        'Unrepairable' { 'SFC cannot fix some files: reboot and run again, then repair with a Source of the same Windows build (install.wim) and LimitAccess true, or reset or reinstall Windows' }
        default { "sfc reported $State" }
    }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        Mode        = Read-OutpostChoice -Name 'Mode' -Allowed @('Auto', 'Scan', 'Repair')
        Source      = Read-OutpostText -Name 'Source'
        LimitAccess = Read-OutpostBool -Name 'LimitAccess'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    if (-not (Test-Path -LiteralPath $SfcPath)) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: sfc.exe was not found; this is not a full Windows install.'
    }
    if (-not (Get-Command -Name 'Repair-WindowsImage' -ErrorAction SilentlyContinue)) {
        Stop-OutpostRun -Message 'The DISM PowerShell module (Repair-WindowsImage) is missing. Repair the module with DISM on a healthy machine of the same build, or reinstall Windows.'
    }
    if ($Config.LimitAccess -and $Config.Source -eq '') {
        Stop-OutpostRun -Message 'LimitAccess is true but Source is empty, so DISM would have nowhere to repair from. Set Source (for example wim:D:\sources\install.wim:1) or set LimitAccess to false.'
    }
    if ($Config.Source -ne '' -and $Config.Source -notmatch '^(wim|esd|swm):' -and -not (Test-Path -LiteralPath $Config.Source)) {
        Stop-OutpostInput -Name 'Source' -Value $Config.Source -Expected 'wim:<path>:<index>, esd:<path>:<index> or an existing folder'
    }

    # Detect: a pending restart makes sfc refuse, so end here and say so.
    if (Test-Path -LiteralPath $CbsRestartKey) { Complete-OutpostRun -Status 'SKIPPED' -Answer $RestartPendingAnswer }
    foreach ($hint in @(Get-RestartHint)) { Write-OutpostWarning -Text "$hint; if sfc then refuses, restart the PC and run again." }
    # Read-only checks.
    Write-OutpostLine -Text 'Checking the component store with DISM ScanHealth (a few minutes).'
    $storeState = Get-ImageHealthState
    Write-OutpostLine -Text "Component store: $storeState."
    Write-OutpostLine -Text 'Checking system files with sfc /verifyonly (a few minutes).'
    $verifyRun = Invoke-SfcRun -Argument '/verifyonly'
    $verifyVerdict = Get-SfcVerdict -Run $verifyRun
    Write-OutpostLine -Text "System files: $($verifyVerdict.State)."

    if ($verifyVerdict.State -eq 'Pending') { Complete-OutpostRun -Status 'SKIPPED' -Answer $RestartPendingAnswer }
    if ($verifyVerdict.State -eq 'Failed') {
        Stop-OutpostRun -Message "sfc /verifyonly could not give a result: $(Get-SfcAdvice -State $verifyVerdict.State)."
    }
    $storeDamaged = $storeState -ne 'Healthy'
    $filesDamaged = $verifyVerdict.State -ne 'Clean'
    if (-not $storeDamaged -and -not $filesDamaged) {
        if ($Config.Mode -ne 'Repair') {
            Complete-OutpostRun -Status 'OK' -Answer 'Healthy: no corruption found (component store healthy; SFC found no violations).'
        }
        Write-OutpostLine -Text 'No corruption found; Mode Repair runs the repair steps anyway.'
    }
    $found = @()
    if ($storeDamaged) { $found += "component store $storeState" }
    if ($filesDamaged) { $found += "SFC $($verifyVerdict.State.ToLowerInvariant()) system files" }
    if ($Config.Mode -eq 'Scan') {
        Stop-OutpostRun -Message "Corruption found ($($found -join '; ')) and Mode is Scan, so nothing was repaired. Run again with Mode Auto."
    }

    # Act: DISM first (it supplies the files SFC copies from), then SFC.
    $dismRepaired = $false
    $restartNeeded = $false
    if ($storeDamaged -or $Config.Mode -eq 'Repair') {
        $null = Invoke-OutpostChange -Item 'Component store' -Change 'DISM RestoreHealth' -Action {
            $repairArgs = @{ Online = $true; RestoreHealth = $true }
            if ($Config.Source -ne '') { $repairArgs['Source'] = $Config.Source }
            if ($Config.LimitAccess) { $repairArgs['LimitAccess'] = $true }
            try { $restoreResult = Repair-WindowsImage @repairArgs }
            catch {
                throw "DISM RestoreHealth failed: $($_.Exception.Message) Next step: supply Source (wim:D:\sources\install.wim:1 from the same Windows build) with LimitAccess true, or check the machine can reach Windows Update."
            }
            if ($restoreResult -and $restoreResult.PSObject.Properties.Name -contains 'RestartNeeded' -and $restoreResult.RestartNeeded) { $script:RestartNeeded = $true }
            $script:DismRepaired = $storeDamaged
        }
    }
    $sfcRepairedCount = 0
    $sfcRan = $false
    if ($filesDamaged -or $storeDamaged -or $Config.Mode -eq 'Repair') {
        $scanRun = $null
        $null = Invoke-OutpostChange -Item 'System files' -Change 'sfc /scannow' -Action {
            $script:ScanRun = Invoke-SfcRun -Argument '/scannow'
        }
        if ($scanRun) {
            $sfcRan = $true
            $scanVerdict = Get-SfcVerdict -Run $scanRun
            Write-OutpostLine -Text "sfc /scannow: $($scanVerdict.State); $($scanVerdict.RepairedCount) file(s) repaired."
            if ($scanVerdict.State -in @('Unrepairable', 'Pending', 'Failed')) {
                Stop-OutpostRun -Message "sfc /scannow: $(Get-SfcAdvice -State $scanVerdict.State)."
            }
            $sfcRepairedCount = $scanVerdict.RepairedCount
        }
    }

    # Verify (skipped in a dry run: nothing was changed)
    $finalNote = ''
    if (-not $script:OutpostRun.DryRun) {
        if ($dismRepaired) {
            $afterState = Get-ImageHealthState
            if ($afterState -ne 'Healthy') {
                Stop-OutpostRun -Message "DISM RestoreHealth finished but the component store is still $afterState. Supply Source (install.wim of the same build) with LimitAccess true, or reset or reinstall Windows."
            }
        }
        if ($sfcRan) {
            $afterRun = Invoke-SfcRun -Argument '/verifyonly'
            $afterVerdict = Get-SfcVerdict -Run $afterRun
            if ($afterVerdict.State -eq 'Pending') { $finalNote = '; reboot needed to finish' }
            elseif ($afterVerdict.State -ne 'Clean') {
                Stop-OutpostRun -Message "SFC still finds damaged files after the repair ($($afterVerdict.State)). Reboot and run again; if it repeats, repair with a Source of the same Windows build and LimitAccess true, or reset or reinstall Windows."
            }
        }
        if ($restartNeeded -and $finalNote -eq '') { $finalNote = '; reboot needed to finish' }
    }

    # Finish
    if (-not $storeDamaged -and -not $filesDamaged) {
        Complete-OutpostRun -Status 'OK' -Answer 'Healthy: no corruption found; the repair steps ran clean.'
    }
    $did = @()
    if ($storeDamaged) { $did += 'DISM restored the component store' }
    if ($filesDamaged -and $sfcRepairedCount -gt 0) { $did += "SFC fixed $sfcRepairedCount file(s)" }
    elseif ($filesDamaged) { $did += 'SFC fixed the damaged system files' }
    Complete-OutpostRun -Status 'CHANGED' -Answer ("Repaired: $($did -join '; ')$finalNote")
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
