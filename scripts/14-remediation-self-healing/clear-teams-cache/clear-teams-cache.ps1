#Requires -Version 5.1
<#
.SYNOPSIS
    Clears the Microsoft Teams cache (new and classic Teams) for every user on
    the PC; users may need to sign in to Teams again afterwards.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. For every user profile under C:\Users (or only
    the ones in Users) it deletes the contents of these cache folders:

      * new Teams: AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams
      * classic Teams, inside AppData\Roaming\Microsoft\Teams: Cache,
        blob_storage, databases, GPUCache, IndexedDB, Local Storage, tmp,
        Code Cache, Service Worker\CacheStorage and Application Cache\Cache.

    It never deletes the whole Teams folder, a profile, or anything else, so
    classic Teams keeps its settings (desktop-config.json) and backgrounds.
    Teams rebuilds its cache the next time the user opens it and may ask them
    to sign in again.

    If Teams is running for a user, that user is skipped and the row says so,
    unless CloseTeams is true: then that user's Teams processes are stopped
    first (the user loses any unsent message in Teams). If the script cannot tell
    whether Teams is running for a user (the account name of the profile or of
    a Teams process cannot be read), it treats Teams as running and skips that
    user, even with CloseTeams. The script never starts Teams again. Users with no Teams cache are not listed.

.PARAMETER Users
    Only these users (profile folder names or account names, separated by
    commas or semicolons). Default empty: every profile.
    Environment variable: Users

.PARAMETER CloseTeams
    true to stop a user's running Teams before clearing their cache. Default
    false: a user whose Teams is running is skipped. Environment variable: CloseTeams

.PARAMETER DryRun
    true to list what would be changed and change nothing. Default false.
    -WhatIf does the same. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\clear-teams-cache.ps1 -DryRun true

    Lists the Teams caches it would clear and how large they are.

.EXAMPLE
    .\clear-teams-cache.ps1 -Users jsmith -CloseTeams true

    Closes jsmith's Teams and clears the cache for that user only.

.NOTES
    Name:        Teams won't load - clear the Teams cache
    Slug:        clear-teams-cache
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    14 Remediation & self-healing
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights
    Changes:     Deletes the cache folders of new and classic Teams in each user profile; with CloseTeams, stops that user's Teams processes
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 1 minute
    Answer:      "Cleared Teams cache for 3 user(s), 412.6 MB"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/clear-teams-cache
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs.
    [string] $Users = '',
    [string] $CloseTeams = 'false',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'clear-teams-cache'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('Users', 'CloseTeams')
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
$ProfileListKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$NewTeamsCachePath = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams'
$ClassicTeamsPath = 'AppData\Roaming\Microsoft\Teams'
$ClassicCacheNames = @('Cache', 'blob_storage', 'databases', 'GPUCache', 'IndexedDB', 'Local Storage', 'tmp', 'Code Cache', 'Service Worker\CacheStorage', 'Application Cache\Cache')
$TeamsProcessNames = @('ms-teams.exe', 'msteams.exe', 'Teams.exe')
$WebViewProcessName = 'msedgewebview2.exe'
$ProcessWaitSeconds = 15

# ---- Functions ------------------------------------------------------------
function Get-UsersFolder {
    # C:\Users without trusting the environment (stripped in some RMM agents).
    $windows = [Environment]::GetFolderPath('Windows')
    if (-not $windows) { $windows = $env:SystemRoot }
    if (-not $windows) { $windows = 'C:\Windows' }
    $drive = Split-Path -Path $windows -Qualifier
    if ($drive -notmatch '^[A-Za-z]:$') {
        Stop-OutpostRun -Message "Could not work out the system drive from the Windows folder '$windows'. Run the script from an elevated PowerShell or a standard RMM agent."
    }
    return "$drive\Users"
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

function Get-ProfileAccountMap {
    # Profile folder path (lower case) -> DOMAIN\user, from the ProfileList registry key.
    $map = @{}
    foreach ($key in @(Get-ChildItem -LiteralPath $ProfileListKey -ErrorAction SilentlyContinue)) {
        $path = ''
        try { $path = [string](Get-ItemPropertyValue -LiteralPath $key.PSPath -Name 'ProfileImagePath') } catch { $path = '' }
        if ([string]::IsNullOrEmpty($path)) { continue }
        $account = ''
        try {
            $sid = New-Object -TypeName Security.Principal.SecurityIdentifier -ArgumentList $key.PSChildName
            $account = $sid.Translate([Security.Principal.NTAccount]).Value
        }
        catch { $account = '' }
        $map[[Environment]::ExpandEnvironmentVariables($path).ToLowerInvariant()] = $account
    }
    return $map
}

function Get-TeamsProcess {
    # Every running Teams process (and the Teams web view helpers) with its owner.
    $found = New-Object -TypeName System.Collections.ArrayList
    foreach ($process in @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue)) {
        $isTeams = $TeamsProcessNames -contains $process.Name
        $isWebView = $process.Name -eq $WebViewProcessName -and $process.CommandLine -and ($process.CommandLine -like '*ms-teams*' -or $process.CommandLine -like '*MSTeams_8wekyb3d8bbwe*')
        if (-not ($isTeams -or $isWebView)) { continue }
        $owner = ''
        try {
            $result = Invoke-CimMethod -InputObject $process -MethodName GetOwner
            if ($result.User) { $owner = "$($result.Domain)\$($result.User)" }
        }
        catch { $owner = '' }
        [void]$found.Add([pscustomobject]@{ ProcessId = [int]$process.ProcessId; Name = [string]$process.Name; Owner = $owner })
    }
    return @($found)
}

function Get-CacheTree {
    # Every file and sub-folder below Root, never following junctions or links.
    param([string] $Root)
    $files = New-Object -TypeName System.Collections.ArrayList
    $dirs = New-Object -TypeName System.Collections.ArrayList
    if (Test-Path -LiteralPath $Root -PathType Container) {
        $pending = New-Object -TypeName 'System.Collections.Generic.Stack[string]'
        $pending.Push($Root)
        while ($pending.Count -gt 0) {
            $current = $pending.Pop()
            foreach ($child in @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)) {
                if (([int]$child.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($child.PSIsContainer) {
                    $pending.Push($child.FullName)
                    [void]$dirs.Add($child.FullName)
                }
                else { [void]$files.Add($child) }
            }
        }
    }
    return [pscustomobject]@{ Files = $files; Dirs = $dirs }
}

function Get-TeamsCacheEntry {
    # One entry per profile and Teams client that has a cache folder.
    param([object] $UserFolder, [string] $Account)
    $entries = New-Object -TypeName System.Collections.ArrayList
    $newRoot = $UserFolder.FullName + '\' + $NewTeamsCachePath
    $classicRoots = @($ClassicCacheNames | ForEach-Object { $UserFolder.FullName + '\' + $ClassicTeamsPath + '\' + $_ })
    foreach ($client in @(
            @{ Name = 'New Teams'; Roots = @($newRoot) },
            @{ Name = 'Classic Teams'; Roots = $classicRoots })) {
        $existing = @($client.Roots | Where-Object { Test-Path -LiteralPath $_ -PathType Container })
        if ($existing.Count -eq 0) { continue }
        $trees = @($existing | ForEach-Object { Get-CacheTree -Root $_ })
        $fileCount = 0
        $bytes = [long]0
        foreach ($tree in $trees) { foreach ($file in $tree.Files) { $fileCount++; $bytes += [long]$file.Length } }
        [void]$entries.Add([pscustomobject]@{
                User      = $UserFolder.Name
                Account   = $Account
                Client    = $client.Name
                Trees     = $trees
                FileCount = $fileCount
                Bytes     = $bytes
            })
    }
    return @($entries)
}

function Clear-CacheEntry {
    # Deletes the files, then the now-empty sub-folders (never the cache folder itself).
    param([object] $Entry)
    foreach ($tree in $Entry.Trees) {
        foreach ($file in $tree.Files) {
            if (-not [IO.File]::Exists($file.FullName)) { continue }
            try {
                [IO.File]::SetAttributes($file.FullName, [IO.FileAttributes]::Normal)
                [IO.File]::Delete($file.FullName)
            }
            catch { $script:Locked++ }
        }
        foreach ($dir in @($tree.Dirs | Sort-Object -Property @{ Expression = { $_.Length } } -Descending)) {
            try { [IO.Directory]::Delete($dir) } catch { $null = $_ }
        }
    }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        Users      = @(Read-OutpostList -Name 'Users')
        CloseTeams = Read-OutpostBool -Name 'CloseTeams'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $script:Locked = 0

    # Detect
    $accountMap = Get-ProfileAccountMap
    $usersRoot = Get-UsersFolder
    $userFolders = @()
    if (Test-Path -LiteralPath $usersRoot) {
        $userFolders = @(Get-ChildItem -LiteralPath $usersRoot -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $SkippedUserFolders -notcontains $_.Name -and (([int]$_.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -eq 0) })
    }
    $selectedFolders = New-Object -TypeName System.Collections.ArrayList
    foreach ($userFolder in $userFolders) {
        $account = ''
        if ($accountMap.ContainsKey($userFolder.FullName.ToLowerInvariant())) { $account = [string]$accountMap[$userFolder.FullName.ToLowerInvariant()] }
        $accountName = if ($account -ne '') { $account.Substring($account.LastIndexOf('\') + 1) } else { '' }
        $wanted = @($Config.Users).Count -eq 0
        foreach ($name in @($Config.Users)) {
            if ($userFolder.Name -ieq $name -or $accountName -ieq $name -or $account -ieq $name) { $wanted = $true }
        }
        if ($wanted) { [void]$selectedFolders.Add([pscustomobject]@{ Folder = $userFolder; Account = $account }) }
    }
    foreach ($name in @($Config.Users)) {
        $matched = @($selectedFolders | Where-Object { $_.Folder.Name -ieq $name -or $_.Account -ieq $name -or ($_.Account -ne '' -and $_.Account.Substring($_.Account.LastIndexOf('\') + 1) -ieq $name) })
        if ($matched.Count -eq 0) { Write-OutpostWarning -Text "User '$name' has no profile on this PC; skipped." }
    }
    Write-OutpostLine -Text "Looking for Teams caches in $($selectedFolders.Count) profile(s)."

    $entries = New-Object -TypeName System.Collections.ArrayList
    foreach ($selected in $selectedFolders) {
        foreach ($entry in @(Get-TeamsCacheEntry -UserFolder $selected.Folder -Account $selected.Account)) { [void]$entries.Add($entry) }
    }
    if ($entries.Count -eq 0) {
        Complete-OutpostRun -Status 'OK' -Answer 'No Teams cache found.'
    }
    $withFiles = @($entries | Where-Object { $_.FileCount -gt 0 })
    if ($withFiles.Count -eq 0) {
        Complete-OutpostRun -Status 'OK' -Answer "Already clear: the Teams cache is empty for $(@($entries | ForEach-Object { $_.User } | Select-Object -Unique).Count) user(s)."
    }

    # Decide per user whether Teams is running (a running Teams holds its cache files open).
    $teamsProcesses = @(Get-TeamsProcess)
    $actionable = New-Object -TypeName System.Collections.ArrayList
    $skipped = New-Object -TypeName System.Collections.ArrayList
    $stopForUser = @{}
    $unknownOwnerCount = @($teamsProcesses | Where-Object { $_.Owner -eq '' }).Count
    foreach ($entry in $withFiles) {
        # Owner unknown (profile account or a Teams process): cannot rule Teams out, so treat it as running.
        if ($entry.Account -eq '' -or $unknownOwnerCount -gt 0) {
            Add-OutpostRow -Values @{ Item = "$($entry.User) ($($entry.Client))"; Change = 'Skipped: cannot tell whether Teams is running (an account owner could not be read)'; Result = 'Skipped' }
            if (-not $skipped.Contains($entry.User)) { [void]$skipped.Add($entry.User) }
            continue
        }
        $owned = @($teamsProcesses | Where-Object { $_.Owner -ne '' -and ($_.Owner -ieq $entry.Account) })
        if ($owned.Count -gt 0 -and -not $Config.CloseTeams) {
            Add-OutpostRow -Values @{ Item = "$($entry.User) ($($entry.Client))"; Change = 'Skipped: Teams is running for this user (set CloseTeams to true to close it first)'; Result = 'Skipped' }
            if (-not $skipped.Contains($entry.User)) { [void]$skipped.Add($entry.User) }
            continue
        }
        if ($owned.Count -gt 0) { $stopForUser[$entry.User] = $owned }
        [void]$actionable.Add($entry)
    }
    if ($actionable.Count -eq 0) {
        Stop-OutpostRun -Message "Teams is running for $($skipped -join ', '), so nothing was cleared (a user whose Teams owner cannot be read counts as running). Ask them to quit Teams or run again with CloseTeams set to true."
    }

    # Act
    $stoppedUsers = @{}
    foreach ($entry in $actionable) {
        if ($stopForUser.ContainsKey($entry.User) -and -not $stoppedUsers.ContainsKey($entry.User)) {
            $stoppedUsers[$entry.User] = $true
            $running = @($stopForUser[$entry.User])
            $null = Invoke-OutpostChange -Item $entry.User -Change "Stop $(@($running).Count) Teams process(es)" -Action {
                foreach ($process in $running) { Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue }
                Wait-Process -Id @($running | ForEach-Object { $_.ProcessId }) -Timeout $ProcessWaitSeconds -ErrorAction SilentlyContinue
            }
        }
        $changeText = "Delete $($entry.FileCount) cache file(s), $(Format-ByteSize -Bytes $entry.Bytes)"
        $null = Invoke-OutpostChange -Item "$($entry.User) ($($entry.Client))" -Change $changeText -Action {
            Clear-CacheEntry -Entry $entry
        }
    }

    # Verify (skipped in a dry run: nothing was changed)
    if (-not $script:OutpostRun.DryRun) {
        $remaining = 0
        foreach ($entry in $actionable) {
            foreach ($tree in $entry.Trees) {
                foreach ($file in $tree.Files) { if ([IO.File]::Exists($file.FullName)) { $remaining++ } }
            }
        }
        if ($remaining -gt 0) {
            Stop-OutpostRun -Message "$remaining Teams cache file(s) could not be deleted because they are in use. Close Teams for that user (CloseTeams true) and run again."
        }
    }

    # Finish
    $totalBytes = [long]0
    foreach ($entry in $actionable) { $totalBytes += $entry.Bytes }
    $userCount = @($actionable | ForEach-Object { $_.User } | Select-Object -Unique).Count
    $skippedText = if ($skipped.Count -gt 0) { "; skipped $($skipped.Count) user(s) with Teams running" } else { '' }
    Complete-OutpostRun -Status 'CHANGED' -Answer "Cleared Teams cache for $userCount user(s), $(Format-ByteSize -Bytes $totalBytes)$skippedText"
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
