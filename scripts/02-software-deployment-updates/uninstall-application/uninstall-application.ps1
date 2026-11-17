#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls an application silently by name, and checks it is gone.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It finds installed applications whose name
    matches Name (the machine-wide installed-programs list, 64-bit and
    32-bit), runs each one's silent uninstaller and checks the entry is gone.
    It never touches per-user installs, Microsoft Store apps, updates or
    hotfixes, entries marked as system components, or entries marked as not
    removable.

    How each application is uninstalled:
      * Windows Installer (MSI): msiexec /x {ProductCode} /qn /norestart.
      * The entry's own QuietUninstallString, when it has one.
      * Otherwise its UninstallString plus the silent switch of an installer
        type the script positively identifies: NSIS (/S, run in place with
        _?= so the script can wait for it), Inno Setup (/VERYSILENT /SUPPRESSMSGBOXES
        /NORESTART) or a WiX bundle (/quiet /norestart).
      * No known silent method: ERROR naming the application. The script
        never starts an interactive uninstaller.

    Exit codes 0, 3010 and 1641 are success. 3010 and 1641 mean a reboot is
    needed to finish; the script says so and does not reboot.

    Name without a wildcard (* or ?) matches anywhere in the name. With
    ExactMatch true the whole name must match, ignoring case. More than one
    match is an ERROR that lists them, unless AllowMultiple is true. A name
    with fewer than 3 letters outside wildcards is refused.

    Risk is High: it changes nothing unless DryRun is false AND Approve is
    set to uninstall-application. It refuses to remove more than MaxChanges
    applications (default 25) in one run. The dry
    run still lists the applications and fails if one has no silent method.

.PARAMETER Name
    Application name to remove, as shown in Apps & features. Wildcards * and ?
    work. Required.
    Environment variable: Name

.PARAMETER ExactMatch
    true to require the whole name to match instead of a part of it.
    Default false. Environment variable: ExactMatch

.PARAMETER Publisher
    Only applications whose publisher contains this text. Default empty.
    Environment variable: Publisher

.PARAMETER AllowMultiple
    true to remove every match instead of stopping when there are several.
    Default false. Environment variable: AllowMultiple

.PARAMETER TimeoutSeconds
    How long to wait for each uninstaller. Whole number, 30 to 7200.
    Default 600. Environment variable: TimeoutSeconds

.PARAMETER DryRun
    Defaults to true for this script. Set false AND Approve=uninstall-application
    to uninstall. -WhatIf does the same as true. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\uninstall-application.ps1 -Name "Zoom" -ExactMatch true

    Dry run: shows what removing the application named exactly Zoom would do.

.EXAMPLE
    .\uninstall-application.ps1 -Name "Java*" -Publisher Oracle -AllowMultiple true -DryRun false

    Removes every Oracle application whose name starts with Java.

.NOTES
    Name:        Uninstall an application silently by name
    Slug:        uninstall-application
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    02 Software deployment & updates
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Runs the silent uninstaller of each matching application
    Risk:        High
    Reboot:      May
    Runtime:     1 to 10 minutes
    Answer:      "Uninstalled Zoom 6.2.5; reboot needed"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/uninstall-application
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # THIS SCRIPT'S inputs. Strings on purpose: RMMs send text.
    [string] $Name = '',
    [string] $ExactMatch = 'false',
    [string] $Publisher = '',
    [string] $AllowMultiple = 'false',
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
    Slug    = 'uninstall-application'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('Name', 'ExactMatch', 'Publisher', 'AllowMultiple', 'TimeoutSeconds')
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
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$MsiExecPath = "$env:SystemRoot\System32\msiexec.exe"
$SuccessExitCodes = @(0, 3010, 1641)
$RebootExitCodes = @(3010, 1641)
$VerifyWaitSeconds = 60
$MinNameLetters = 3
$MarkerReadBytes = 8388608

# ---- Functions ------------------------------------------------------------
function Get-RegistryValue {
    # Strict mode throws on a missing property, so read through the property bag.
    param($Item, [string] $PropertyName)
    $property = $Item.PSObject.Properties[$PropertyName]
    if ($property) { return $property.Value }
    return $null
}

function Get-InstalledApplication {
    # Machine-wide applications that can be uninstalled by the user:
    # no system components, updates or hotfixes.
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
                Publisher            = [string](Get-RegistryValue -Item $item -PropertyName 'Publisher')
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

function Split-CommandLine {
    # A command line into the program and its arguments.
    param([string] $CommandLine)
    $text = $CommandLine.Trim()
    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -gt 0) {
            return [pscustomobject]@{ File = $text.Substring(1, $end - 1); Arguments = $text.Substring($end + 1).Trim() }
        }
    }
    $match = [regex]::Match($text, '^(.+?\.exe)(\s+(.*))?$', 'IgnoreCase')
    if ($match.Success) {
        return [pscustomobject]@{ File = $match.Groups[1].Value; Arguments = $match.Groups[3].Value.Trim() }
    }
    return [pscustomobject]@{ File = $text; Arguments = '' }
}

function Get-InstallerType {
    # Names the installer that built an uninstaller by the text inside it.
    param([string] $File)
    if ((Split-Path -Path $File -Leaf) -match '^unins\d+\.exe$') { return 'Inno' }
    $stream = [IO.File]::OpenRead($File)
    try {
        $buffer = New-Object -TypeName byte[] -ArgumentList ([int][math]::Min($stream.Length, $MarkerReadBytes))
        $count = $stream.Read($buffer, 0, $buffer.Length)
        $text = [Text.Encoding]::GetEncoding(28591).GetString($buffer, 0, $count)
    }
    finally { $stream.Dispose() }
    if ($text.IndexOf('Inno Setup', [StringComparison]::Ordinal) -ge 0) { return 'Inno' }
    # NSIS only when both of its own markers are present: the setup header and the build tag.
    if ($text.IndexOf('NullsoftInst', [StringComparison]::Ordinal) -ge 0 -and $text.IndexOf('Nullsoft Install System', [StringComparison]::Ordinal) -ge 0) { return 'NSIS' }
    return ''
}

function Get-UninstallPlan {
    # How to remove one application silently, or why that is not possible.
    param($Application)
    $plan = [pscustomobject]@{ Method = ''; File = ''; Arguments = ''; Problem = '' }
    $guidPattern = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
    if ($Application.IsNoRemove) {
        $plan.Problem = "'$($Application.DisplayName)' is marked as not removable (NoRemove). Remove it by hand if you are sure."
        return $plan
    }

    $productCode = ''
    if ($Application.KeyName -match "^$guidPattern`$" -and ($Application.IsWindowsInstaller -or $Application.UninstallString -match 'msiexec')) {
        $productCode = $Application.KeyName
    }
    elseif ($Application.UninstallString -match 'msiexec') {
        $found = [regex]::Match($Application.UninstallString, $guidPattern)
        if ($found.Success) { $productCode = $found.Value }
    }
    if ($productCode -ne '') {
        $plan.Method = 'MSI'
        $plan.File = $MsiExecPath
        $plan.Arguments = "/x $productCode /qn /norestart"
        return $plan
    }

    $command = $Application.QuietUninstallString
    $isQuiet = $command.Trim() -ne ''
    if (-not $isQuiet) { $command = $Application.UninstallString }
    if ($command.Trim() -eq '') {
        $plan.Problem = "'$($Application.DisplayName)' has no uninstall command in the registry. Remove it by hand."
        return $plan
    }
    $parts = Split-CommandLine -CommandLine $command
    $isBareName = -not ($parts.File -match '[\\/]')
    if (-not $isBareName -and -not (Test-Path -LiteralPath $parts.File -PathType Leaf)) {
        $plan.Problem = "The uninstaller of '$($Application.DisplayName)' was not found at $($parts.File). Repair or remove the application by hand."
        return $plan
    }
    if ($isQuiet) {
        $plan.Method = 'EXE quiet'
        $plan.File = $parts.File
        $plan.Arguments = $parts.Arguments
        return $plan
    }

    $silentSwitch = ''
    $method = ''
    if ($Application.IsBundle -or $parts.File -match '\\Package Cache\\') {
        $method = 'WiX bundle'
        $silentSwitch = '/quiet /norestart'
    }
    elseif (-not $isBareName) {
        $installerType = Get-InstallerType -File $parts.File
        if ($installerType -eq 'Inno') { $method = 'Inno Setup'; $silentSwitch = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
        elseif ($installerType -eq 'NSIS') { $method = 'NSIS'; $silentSwitch = '/S _?=' + (Split-Path -Path $parts.File -Parent) }
    }
    if ($silentSwitch -eq '') {
        $plan.Problem = "No silent uninstall method is known for '$($Application.DisplayName)' (uninstall command: $command). Uninstall it by hand or ask the vendor for its silent switch."
        return $plan
    }
    $plan.Method = $method
    $plan.File = $parts.File
    $plan.Arguments = (($parts.Arguments + ' ' + $silentSwitch).Trim())
    return $plan
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

function Wait-ApplicationGone {
    param($Application)
    $deadline = (Get-Date).AddSeconds($VerifyWaitSeconds)
    while (Test-Path -LiteralPath $Application.KeyPath) {
        if ((Get-Date) -gt $deadline) { return $false }
        Start-Sleep -Seconds 3
    }
    return $true
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        Name           = Read-OutpostText -Name 'Name' -Required
        ExactMatch     = Read-OutpostBool -Name 'ExactMatch'
        Publisher      = Read-OutpostText -Name 'Publisher'
        AllowMultiple  = Read-OutpostBool -Name 'AllowMultiple'
        TimeoutSeconds = Read-OutpostInt -Name 'TimeoutSeconds' -Min 30 -Max 7200
    }
    $nameLetters = ($Config.Name -replace '[\*\?\[\]\s]', '').Length
    if ($nameLetters -lt $MinNameLetters) {
        Stop-OutpostInput -Name 'Name' -Value $Config.Name -Expected "a name with at least $MinNameLetters letters besides wildcards, so one run cannot remove everything"
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }

    # Detect
    $hasWildcard = $Config.Name -match '[\*\?]'
    $namePattern = if ($hasWildcard) { $Config.Name } else { '*' + [WildcardPattern]::Escape($Config.Name) + '*' }
    $matchedApplications = @()
    $seen = @{}
    foreach ($application in @(Get-InstalledApplication)) {
        if ($Config.ExactMatch) { if ($application.DisplayName -ne $Config.Name) { continue } }
        elseif ($application.DisplayName -notlike $namePattern) { continue }
        if ($Config.Publisher -ne '' -and $application.Publisher -notlike "*$($Config.Publisher)*") { continue }
        $identity = "$($application.DisplayName)|$($application.DisplayVersion)|$($application.UninstallString)"
        if ($seen.ContainsKey($identity)) { continue }
        $seen[$identity] = $true
        $matchedApplications += $application
    }
    $publisherText = ''
    if ($Config.Publisher -ne '') { $publisherText = " from publisher '$($Config.Publisher)'" }
    if ($matchedApplications.Count -eq 0) {
        Complete-OutpostRun -Status 'OK' -Answer "Already absent: no installed application matches '$($Config.Name)'$publisherText."
    }
    $labels = @($matchedApplications | ForEach-Object { ("$($_.DisplayName) $($_.DisplayVersion)").Trim() })
    Write-OutpostLine -Text ("Matched {0} application(s): {1}" -f $matchedApplications.Count, ($labels -join '; '))
    if ($matchedApplications.Count -gt 1 -and -not $Config.AllowMultiple) {
        Stop-OutpostRun -Message "$($matchedApplications.Count) applications match '$($Config.Name)': $($labels -join '; '). Narrow Name, set ExactMatch true, or set AllowMultiple true to remove all of them."
    }

    $plans = @()
    $problems = @()
    foreach ($application in $matchedApplications) {
        $plan = Get-UninstallPlan -Application $application
        if ($plan.Problem -ne '') { $problems += $plan.Problem }
        $plans += [pscustomobject]@{ Application = $application; Plan = $plan; Label = ("$($application.DisplayName) $($application.DisplayVersion)").Trim() }
    }
    if ($problems.Count -gt 0) {
        Stop-OutpostRun -Message ($problems -join ' ')
    }

    Assert-OutpostChangeLimit -Planned $plans.Count

    # Act
    $state = @{ RebootNeeded = $false }
    $failures = @()
    $done = @()
    foreach ($entry in $plans) {
        try {
            $changed = Invoke-OutpostChange -Item $entry.Label -Change "Uninstall ($($entry.Plan.Method))" -Action {
                $exitCode = Invoke-Uninstaller -Plan $entry.Plan -WaitSeconds $Config.TimeoutSeconds
                if ($SuccessExitCodes -contains $exitCode) {
                    if ($RebootExitCodes -contains $exitCode) { $state.RebootNeeded = $true }
                }
                elseif (Test-Path -LiteralPath $entry.Application.KeyPath) {
                    throw "The uninstaller exited with code $exitCode and the application is still installed."
                }
                else {
                    Write-OutpostWarning -Text "The uninstaller of $($entry.Label) exited with code $exitCode but the application is gone."
                }
            }
            if ($changed) { $done += $entry }
        }
        catch {
            $failures += "$($entry.Label): $($_.Exception.Message)"
        }
    }

    # Verify (skipped in a dry run: nothing was changed)
    if (-not $script:OutpostRun.DryRun) {
        foreach ($entry in $done) {
            if (-not (Wait-ApplicationGone -Application $entry.Application)) {
                $failures += "$($entry.Label): still listed in installed programs $VerifyWaitSeconds seconds after the uninstaller finished."
            }
        }
    }
    if ($failures.Count -gt 0) {
        Stop-OutpostRun -Message ('Not uninstalled: ' + ($failures -join ' | ') + ' Check the application and the change log, then run again.')
    }

    # Finish
    $answer = if ($plans.Count -eq 1) { "Uninstalled $($plans[0].Label)" } else { "Uninstalled $($plans.Count) applications: " + (@($plans | ForEach-Object { $_.Label }) -join ', ') }
    if ($state.RebootNeeded) { $answer += '; reboot needed' }
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
