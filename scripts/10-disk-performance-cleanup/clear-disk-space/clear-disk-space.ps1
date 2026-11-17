#Requires -Version 5.1
<#
.SYNOPSIS
    Frees disk space on the system drive by clearing temp files, update and
    crash leftovers, and (on request) browser caches and the Recycle Bin.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It looks at these places, measures what it
    could free, and (when at least MinimumMB would be freed) deletes:

      * Windows\Temp and every user's AppData\Local\Temp,
      * the Windows Update download cache (SoftwareDistribution\Download): it
        stops the Windows Update service first and puts it back as it found it,
      * the Delivery Optimization cache (Delete-DeliveryOptimizationCache),
      * crash dumps (Windows\Minidump and MEMORY.DMP),
      * Windows Error Reporting queues and archives,
      * only with IncludeBrowserCaches: the cache folders of Chrome, Edge and
        Firefox in every profile (never cookies, passwords or history),
      * only with ComponentCleanup: DISM component store cleanup (slow; its
        size is only known afterwards).

    Files are only deleted when they have not changed for MinAgeDays days (the
    Delivery Optimization and DISM steps take everything). It never empties the
    Recycle Bin: that is users' data. A file
    that is in use is skipped silently and counted. It never touches documents,
    desktops, downloads, application settings or installed programs.

    The table has one row per category. The answer says how much was freed on
    the system drive and the free space before and after. When less than
    MinimumMB would be freed it changes nothing and says so.

.PARAMETER MinAgeDays
    Only delete files that have not been modified for at least this many days,
    so files a program is using right now survive. Whole number, 0 to 3650.
    Default 2. Environment variable: MinAgeDays

.PARAMETER MinimumMB
    Do nothing unless at least this many MB can be freed. Whole number, 0 to
    1048576. Default 50. Environment variable: MinimumMB

.PARAMETER IncludeBrowserCaches
    true to also clear the Chrome, Edge and Firefox cache folders of every
    profile. Default false. Environment variable: IncludeBrowserCaches

.PARAMETER ComponentCleanup
    true to also run DISM component store cleanup (can take many minutes).
    Default false. Environment variable: ComponentCleanup

.PARAMETER DryRun
    true to list what would be deleted and delete nothing. Default false.
    -WhatIf does the same. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\clear-disk-space.ps1 -DryRun true

    Shows what a cleanup would delete and how much it would free.

.EXAMPLE
    .\clear-disk-space.ps1 -MinAgeDays 7 -IncludeBrowserCaches true

    Also clears browser caches, but only files untouched for a week.

.NOTES
    Name:        Disk full first aid - silent cleanup
    Slug:        clear-disk-space
    Version:     1.0.1
    Updated:     2026-11-17
    Type:        Action
    Category:    10 Disk, performance & cleanup
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Deletes temp, update-cache, crash-dump and error-report files; optionally browser caches and DISM component leftovers; briefly stops and restarts Windows Update
    Risk:        Low
    Reboot:      Never
    Runtime:     1 to 10 minutes (longer with ComponentCleanup)
    Answer:      "Freed 6.2 GB on C: (was 4% free, now 9%)"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/clear-disk-space
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.1  2026-11-17  Freed nothing and locked nothing (Windows kept its Delivery Optimization files) now ends OK, not ERROR.
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs.
    [string] $MinAgeDays = '2',
    [string] $MinimumMB = '50',
    [string] $IncludeBrowserCaches = 'false',
    [string] $ComponentCleanup = 'false',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'clear-disk-space'
    Version = '1.0.1'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('MinAgeDays', 'MinimumMB', 'IncludeBrowserCaches', 'ComponentCleanup')
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
$SkippedUserFolders = @('All Users', 'Default', 'Default User', 'Public')
$BrowserCacheNames = @('Cache', 'Code Cache', 'GPUCache')
$ServiceWaitSeconds = 60

# ---- Functions ------------------------------------------------------------
function Initialize-CleanupPath {
    # Drive and folders without trusting the environment: some agents start scripts
    # with a stripped one, where SystemDrive and SystemRoot are empty.
    $windows = [Environment]::GetFolderPath('Windows')
    if (-not $windows) { $windows = $env:SystemRoot }
    if (-not $windows) { $windows = 'C:\Windows' }
    $drive = Split-Path -Path $windows -Qualifier
    if ($drive -notmatch '^[A-Za-z]:$') {
        Stop-OutpostRun -Message "Could not work out the system drive from the Windows folder '$windows'. Run the script from an elevated PowerShell or a standard RMM agent."
    }
    $script:SystemDrive = $drive
    $script:WindowsFolder = $windows
    $script:UsersFolder = "$drive\Users"
    $script:ProgramDataFolder = "$drive\ProgramData"
    $script:DeliveryOptimizationFolder = "$windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
}

function Format-ByteSize {
    param([long] $Bytes)
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $size = [double]$Bytes
    if ($size -ge 1073741824.0) { return ($size / 1073741824.0).ToString('0.0', $culture) + ' GB' }
    if ($size -ge 1048576.0) { return ($size / 1048576.0).ToString('0.0', $culture) + ' MB' }
    if ($size -ge 1024.0) { return ($size / 1024.0).ToString('0', $culture) + ' KB' }
    return "$Bytes bytes"
}

function Get-SystemDriveSpace {
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$SystemDrive'"
    if (-not $disk -or -not $disk.Size) {
        throw "Could not read the size of drive $SystemDrive."
    }
    return [pscustomobject]@{
        FreeBytes   = [long]$disk.FreeSpace
        SizeBytes   = [long]$disk.Size
        FreePercent = [int][math]::Floor((100.0 * [double]$disk.FreeSpace / [double]$disk.Size) + 0.5)
    }
}

function Get-UserFolder {
    # Every profile folder under C:\Users, without the shared and template ones.
    if (-not (Test-Path -LiteralPath $script:UsersFolder)) { return @() }
    return @(Get-ChildItem -LiteralPath $script:UsersFolder -Directory -Force -ErrorAction SilentlyContinue |
            Where-Object { $SkippedUserFolders -notcontains $_.Name -and (([int]$_.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -eq 0) })
}

function Get-CleanupTree {
    # Walks a folder (never into junctions or links) and returns the files that
    # are older than Cutoff plus every sub-folder with its own age. A root that
    # is a file is returned as one file.
    param([string] $Root, [datetime] $Cutoff, [string[]] $SkipNames)
    $files = New-Object -TypeName System.Collections.ArrayList
    $dirs = New-Object -TypeName System.Collections.ArrayList
    $item = Get-Item -LiteralPath $Root -Force -ErrorAction SilentlyContinue
    if ($item) {
        if (-not $item.PSIsContainer) {
            if ($item.LastWriteTime -lt $Cutoff) { [void]$files.Add($item) }
        }
        else {
            $pending = New-Object -TypeName 'System.Collections.Generic.Stack[string]'
            $pending.Push($item.FullName)
            while ($pending.Count -gt 0) {
                $current = $pending.Pop()
                foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
                    if (([int]$child.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    if ($child.PSIsContainer) {
                        $pending.Push($child.FullName)
                        [void]$dirs.Add([pscustomobject]@{ FullName = $child.FullName; LastWriteTime = $child.LastWriteTime })
                    }
                    elseif (@($SkipNames) -notcontains $child.Name -and $child.LastWriteTime -lt $Cutoff) {
                        [void]$files.Add($child)
                    }
                }
            }
        }
    }
    return [pscustomobject]@{ Files = $files; Dirs = $dirs }
}

function Initialize-CleanupCategory {
    param(
        [string] $Name,
        [string] $Kind,
        [string[]] $Roots,
        [bool] $ApplyAge = $true,
        [string[]] $SkipNames = @(),
        [bool] $RemoveDirs = $true,
        [string] $Service = ''
    )
    return [pscustomobject]@{
        Name       = $Name
        Kind       = $Kind
        Roots      = @($Roots)
        ApplyAge   = $ApplyAge
        SkipNames  = @($SkipNames)
        RemoveDirs = $RemoveDirs
        Service    = $Service
        Trees      = @()
        FileCount  = 0
        Bytes      = [long]0
    }
}

function Get-BrowserCacheRoot {
    param([object[]] $UserFolders)
    $roots = New-Object -TypeName System.Collections.ArrayList
    foreach ($userFolder in $UserFolders) {
        $local = $userFolder.FullName + '\AppData\Local'
        foreach ($dataFolder in @("$local\Google\Chrome\User Data", "$local\Microsoft\Edge\User Data")) {
            foreach ($profileFolder in @(Get-ChildItem -LiteralPath $dataFolder -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($profileFolder.Name -ne 'Default' -and $profileFolder.Name -notlike 'Profile *') { continue }
                foreach ($cacheName in $BrowserCacheNames) { [void]$roots.Add($profileFolder.FullName + '\' + $cacheName) }
            }
        }
        foreach ($firefoxProfile in @(Get-ChildItem -LiteralPath "$local\Mozilla\Firefox\Profiles" -Directory -Force -ErrorAction SilentlyContinue)) {
            [void]$roots.Add($firefoxProfile.FullName + '\cache2')
        }
    }
    return @($roots)
}

function Get-CleanupCategory {
    param([object] $Options)
    $userFolders = @(Get-UserFolder)
    $categories = @()
    $categories += Initialize-CleanupCategory -Name 'Windows Temp' -Kind 'Files' -Roots @("$WindowsFolder\Temp")
    $userTemp = @($userFolders | ForEach-Object { $_.FullName + '\AppData\Local\Temp' })
    $categories += Initialize-CleanupCategory -Name 'User temp folders' -Kind 'Files' -Roots $userTemp
    $categories += Initialize-CleanupCategory -Name 'Windows Update download cache' -Kind 'Files' -Roots @("$WindowsFolder\SoftwareDistribution\Download") -Service 'wuauserv'
    if (Get-Command -Name 'Delete-DeliveryOptimizationCache' -ErrorAction SilentlyContinue) {
        $categories += Initialize-CleanupCategory -Name 'Delivery Optimization cache' -Kind 'DeliveryOptimization' -Roots @($DeliveryOptimizationFolder) -ApplyAge $false
    }
    $categories += Initialize-CleanupCategory -Name 'Crash dumps' -Kind 'Files' -Roots @("$WindowsFolder\Minidump", "$WindowsFolder\MEMORY.DMP")
    $categories += Initialize-CleanupCategory -Name 'Windows Error Reporting' -Kind 'Files' -Roots @("$ProgramDataFolder\Microsoft\Windows\WER\ReportQueue", "$ProgramDataFolder\Microsoft\Windows\WER\ReportArchive", "$ProgramDataFolder\Microsoft\Windows\WER\Temp")
    if ($Options.IncludeBrowserCaches) {
        $categories += Initialize-CleanupCategory -Name 'Browser caches' -Kind 'Files' -Roots @(Get-BrowserCacheRoot -UserFolders $userFolders)
    }
    if ($Options.ComponentCleanup) {
        $categories += Initialize-CleanupCategory -Name 'Component store (DISM)' -Kind 'ComponentStore' -Roots @() -ApplyAge $false
    }
    return ,$categories
}

function Measure-CleanupCategory {
    # Fills Trees, FileCount and Bytes. Never deletes.
    param([object] $Category, [datetime] $Cutoff)
    $cutoffForCategory = if ($Category.ApplyAge) { $Cutoff } else { [datetime]::MaxValue }
    $trees = @()
    $count = 0
    $bytes = [long]0
    foreach ($root in $Category.Roots) {
        $tree = Get-CleanupTree -Root $root -Cutoff $cutoffForCategory -SkipNames $Category.SkipNames
        $trees += $tree
        foreach ($file in $tree.Files) { $count++; $bytes += [long]$file.Length }
    }
    $Category.Trees = $trees
    $Category.FileCount = $count
    $Category.Bytes = $bytes
}

function Remove-CleanupTree {
    # Deletes the files of a tree (skipping and counting files in use), then the
    # sub-folders that are empty and were older than the cutoff.
    param([object] $Tree, [datetime] $Cutoff, [bool] $RemoveDirs)
    foreach ($file in $Tree.Files) {
        if (-not [IO.File]::Exists($file.FullName)) { continue }
        try {
            [IO.File]::SetAttributes($file.FullName, [IO.FileAttributes]::Normal)
            [IO.File]::Delete($file.FullName)
            $script:Freed += [long]$file.Length
        }
        catch {
            $script:Locked++
        }
    }
    if ($RemoveDirs) {
        foreach ($dir in @($Tree.Dirs | Sort-Object -Property @{ Expression = { $_.FullName.Length } } -Descending)) {
            if ($dir.LastWriteTime -ge $Cutoff) { continue }
            try { [IO.Directory]::Delete($dir.FullName) } catch { $null = $_ }
        }
    }
}

function Invoke-CleanupCategory {
    param([object] $Category, [datetime] $Cutoff)
    if ($Category.Kind -eq 'ComponentStore') {
        $before = (Get-SystemDriveSpace).FreeBytes
        & "$WindowsFolder\System32\dism.exe" /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "DISM component cleanup failed with exit code $LASTEXITCODE. See $WindowsFolder\Logs\DISM\dism.log."
        }
        $after = (Get-SystemDriveSpace).FreeBytes
        if ($after -gt $before) { $script:Freed += ($after - $before) }
        return
    }
    if ($Category.Kind -eq 'DeliveryOptimization') {
        try { Delete-DeliveryOptimizationCache -Force }
        catch { Write-OutpostWarning -Text "Delivery Optimization cache: $($_.Exception.Message)" }
        $remaining = [long]0
        $tree = Get-CleanupTree -Root $Category.Roots[0] -Cutoff ([datetime]::MaxValue) -SkipNames @()
        foreach ($file in $tree.Files) { $remaining += [long]$file.Length }
        if ($Category.Bytes -gt $remaining) { $script:Freed += ($Category.Bytes - $remaining) }
        return
    }
    $wasRunning = $false
    try {
        if ($Category.Service -ne '') {
            $categoryService = Get-Service -Name $Category.Service -ErrorAction SilentlyContinue
            if ($categoryService -and $categoryService.Status -eq 'Running') {
                $wasRunning = $true
                Stop-Service -Name $Category.Service -Force
                $categoryService.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($ServiceWaitSeconds))
            }
        }
        $cutoffForCategory = if ($Category.ApplyAge) { $Cutoff } else { [datetime]::MaxValue }
        foreach ($tree in @($Category.Trees)) {
            Remove-CleanupTree -Tree $tree -Cutoff $cutoffForCategory -RemoveDirs $Category.RemoveDirs
        }
    }
    finally {
        if ($wasRunning) { Start-Service -Name $Category.Service }
    }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        MinAgeDays           = Read-OutpostInt -Name 'MinAgeDays' -Min 0 -Max 3650
        MinimumMB            = Read-OutpostInt -Name 'MinimumMB' -Min 0 -Max 1048576
        IncludeBrowserCaches = Read-OutpostBool -Name 'IncludeBrowserCaches'
        ComponentCleanup     = Read-OutpostBool -Name 'ComponentCleanup'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    Initialize-CleanupPath
    $script:Freed = [long]0
    $script:Locked = 0

    # Detect
    $spaceBefore = Get-SystemDriveSpace
    $cutoff = (Get-Date).AddDays(-$Config.MinAgeDays)
    Write-OutpostLine -Text ("{0} is {1}% free ({2} of {3}). Looking for files not changed for {4} day(s)." -f $SystemDrive, $spaceBefore.FreePercent, (Format-ByteSize -Bytes $spaceBefore.FreeBytes), (Format-ByteSize -Bytes $spaceBefore.SizeBytes), $Config.MinAgeDays)
    $candidates = @()
    $foundBytes = [long]0
    $allCategories = Get-CleanupCategory -Options $Config
    foreach ($category in $allCategories) {
        Measure-CleanupCategory -Category $category -Cutoff $cutoff
        if ($category.FileCount -gt 0 -or $category.Kind -eq 'ComponentStore') {
            $candidates += $category
            $foundBytes += $category.Bytes
        }
    }
    $thresholdBytes = [long]$Config.MinimumMB * 1MB
    if (@($candidates).Count -eq 0 -or ($foundBytes -lt $thresholdBytes -and -not $Config.ComponentCleanup)) {
        Complete-OutpostRun -Status 'OK' -Answer ("Nothing worth cleaning: {0} can be freed on {1} (threshold {2} MB)." -f (Format-ByteSize -Bytes $foundBytes), $SystemDrive, $Config.MinimumMB)
    }

    # Act
    foreach ($category in $candidates) {
        if ($category.Kind -eq 'ComponentStore') {
            $changeText = 'Run DISM component store cleanup (size known afterwards)'
        }
        else {
            $changeText = "Delete $($category.FileCount) file(s), $(Format-ByteSize -Bytes $category.Bytes)"
        }
        $lockedBefore = $script:Locked
        $null = Invoke-OutpostChange -Item $category.Name -Change $changeText -Action {
            Invoke-CleanupCategory -Category $category -Cutoff $cutoff
        }
        if ($script:Locked -gt $lockedBefore) {
            Write-OutpostWarning -Text "$($category.Name): $($script:Locked - $lockedBefore) file(s) in use were skipped."
        }
    }

    # Verify (skipped in a dry run: nothing was changed)
    if (-not $script:OutpostRun.DryRun) {
        if ($script:Freed -eq 0 -and $foundBytes -gt 0) {
            if ($script:Locked -gt 0) {
                Stop-OutpostRun -Message "No file could be deleted: $($script:Locked) file(s) were in use. Run again after a reboot."
            }
            # Nothing locked by us, nothing freed: Windows kept what it is still using
            # (Delivery Optimization keeps an active download's files). Not a failure.
            Complete-OutpostRun -Status 'OK' -Answer ("Nothing was freed on {0}: Windows kept the files it is still using. Run again later." -f $SystemDrive)
        }
    }

    # Finish
    $spaceAfter = if ($script:OutpostRun.DryRun) { $spaceBefore } else { Get-SystemDriveSpace }
    $lockedText = if ($script:Locked -gt 0) { "; $($script:Locked) file(s) in use skipped" } else { '' }
    if ($script:OutpostRun.DryRun) {
        Complete-OutpostRun -Status 'CHANGED' -Answer ("freed about {0} on {1} ({2}% free now)" -f (Format-ByteSize -Bytes $foundBytes), $SystemDrive, $spaceBefore.FreePercent)
    }
    Complete-OutpostRun -Status 'CHANGED' -Answer ("Freed {0} on {1} (was {2}% free, now {3}%){4}" -f (Format-ByteSize -Bytes $script:Freed), $SystemDrive, $spaceBefore.FreePercent, $spaceAfter.FreePercent, $lockedText)
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
