#Requires -Version 5.1
<#
.SYNOPSIS
    Turns on BitLocker for the Windows drive with a TPM protector and makes sure the recovery key is stored before encrypting.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It protects the Windows drive (the one holding
    C:\Windows) with BitLocker and a TPM, and makes sure the recovery key is
    stored before encrypting. It handles three states of that drive:

      * Not encrypted: adds a recovery password protector, stores the key
        (below), then starts encryption with the TPM protector
        (Enable-BitLocker -UsedSpaceOnly -SkipHardwareTest).
      * Encrypted with protection Off (Windows 11 automatic device encryption
        leaves C: like this, often with no protectors at all): adds the missing
        recovery and TPM protectors, stores the key, then Resume-BitLocker.
      * Protected: nothing to change when the recovery key is known to be stored
        (Entra ID: a "backup succeeded" event for the recovery protector;
        Active Directory cannot be verified from the PC and is reported as
        such). When it is protected but the key escrow is not confirmed, it
        escrows the key (CHANGED).

    Where the key is stored, in order: Microsoft Entra ID when the PC is
    Entra-joined (dsregcmd; BackupToAAD-BitLockerKeyProtector), Active
    Directory when it is domain-joined (Backup-BitLockerKeyProtector), both
    when hybrid. With EscrowRequired true (default) and neither, it ends in
    ERROR BEFORE encrypting anything: the script never encrypts without a
    recorded key. It also needs a TPM that is present and ready.

    -SkipHardwareTest means no restart test: if the firmware or boot
    configuration cannot release the key from the TPM, the PC asks for the
    48-digit recovery password at the next start. That is why the key is stored
    first, and why you should not use this on a PC you cannot reach or in front
    of when no one holds the key.

    If a step fails after the recovery protector was added and encryption has
    not started, the protector it added is removed again.

    EscrowRequired false, workgroup PC (no Entra ID, no Active Directory): the
    recovery password is written to your RMM custom field named by ResultField,
    BEFORE encryption starts, and nowhere else. Make that a secure / secret
    field. The recovery password is NEVER printed, logged or put in the answer
    or the rows: the run reports only the key protector IDs, and the
    BitLocker warning that contains the key is discarded. Without a
    ResultField, or on an RMM this library cannot write to (NinjaOne, Datto
    RMM, Syncro), it refuses before changing anything. OutputFormat Answer is
    refused in this mode. On a workgroup PC a ResultField is treated as that
    secret field on every run, so a status message never overwrites the key;
    when the key goes to Entra ID or Active Directory, ResultField is an
    ordinary answer field.

    Not touched: data drives and other protectors. BitLocker needs Windows Pro,
    Enterprise or Education (Home is skipped) and a recovery partition.

.PARAMETER EscrowRequired
    true (default): refuse to encrypt unless the recovery key can be stored in
    Entra ID or Active Directory. false: when neither exists, put the recovery
    password in ResultField instead. Environment variable: EscrowRequired

.PARAMETER EncryptionMethod
    XtsAes256 (default), XtsAes128, Aes256 or Aes128.
    Environment variable: EncryptionMethod

.PARAMETER DryRun
    true to list what would be changed and change nothing. Default false.
    -WhatIf does the same. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Json or Csv (Answer is refused when the password goes to
    ResultField). Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    On a PC with nowhere to escrow the key (EscrowRequired false): the RMM
    custom field (a secure field) that receives the recovery password. Where
    the key goes to Entra ID or Active Directory it is an ordinary answer
    field. Environment variable: ResultField

.EXAMPLE
    .\enable-bitlocker.ps1 -DryRun true

    Lists what it would do; ends in ERROR when the key could not be stored.

.EXAMPLE
    .\enable-bitlocker.ps1 -EscrowRequired false -ResultField RecoveryKey

    On a workgroup PC, encrypts C: and writes the recovery password to the
    RecoveryKey custom field.

.NOTES
    Name:        Turn on BitLocker and store the recovery key
    Slug:        enable-bitlocker
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    04 Security hardening & compliance
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, TPM 1.2 or 2.0 ready, Windows Pro or higher
    Changes:     Adds BitLocker key protectors to the Windows drive, backs up the recovery key to Entra ID or Active Directory (or the RMM field), starts encryption
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 2 minutes; encryption continues in the background
    Answer:      "BitLocker enabled on C: (XtsAes256, used space only); key escrowed to Entra ID; protector IDs RP {1111aaaa-0000-0000-0000-000000000001} TPM {2222bbbb-0000-0000-0000-000000000002}"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/enable-bitlocker
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $EscrowRequired = 'true',
    [string] $EncryptionMethod = 'XtsAes256',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'enable-bitlocker'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('EscrowRequired', 'EncryptionMethod')
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
$HomeSkus = @(98, 99, 100, 101)
$ProtectionOn = @('On', '1')
$EscrowEventId = 845

# ---- Functions ------------------------------------------------------------
function Get-DsregValue {
    # The first "Key : Value" line of each key in dsregcmd /status, as a hashtable.
    $found = @{}
    $exe = Join-Path -Path ([Environment]::SystemDirectory) -ChildPath 'dsregcmd.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $found }
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $lines = @(& $exe /status 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $savedPreference }
    foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z]+)\s*:\s*(.+?)\s*$' -and -not $found.ContainsKey($Matches[1])) { $found[$Matches[1]] = $Matches[2] }
    }
    return $found
}

function Get-EscrowTarget {
    # Where the recovery key can be stored: 'Entra ID', 'Active Directory', both, or nothing.
    $targets = @()
    $dsreg = Get-DsregValue
    if ($dsreg.ContainsKey('AzureAdJoined') -and $dsreg['AzureAdJoined'] -eq 'YES') { $targets += 'Entra ID' }
    if ([bool](Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) { $targets += 'Active Directory' }
    return $targets
}

function Get-OsVolume {
    param([Parameter(Mandatory = $true)][string] $Drive)
    return (Get-BitLockerVolume -MountPoint $Drive -ErrorAction Stop)
}

function Get-ProtectorId {
    param($Volume, [Parameter(Mandatory = $true)][string] $Type)
    return @($Volume.KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq $Type } | ForEach-Object { [string]$_.KeyProtectorId })
}

function Get-ProtectorText {
    # "RP {id} TPM {id}": IDs only, never a key.
    param($Volume)
    $parts = @()
    foreach ($id in @(Get-ProtectorId -Volume $Volume -Type 'RecoveryPassword')) { $parts += "RP $id" }
    foreach ($id in @(Get-ProtectorId -Volume $Volume -Type 'Tpm')) { $parts += "TPM $id" }
    return ($parts -join ' ')
}

function Test-EntraEscrowEvidence {
    # True when every recovery protector ID appears in a "backup to Entra ID succeeded" event (845).
    param([string[]] $Ids)
    if ($Ids.Count -eq 0) { return $false }
    $logName = 'Microsoft-Windows-BitLocker/BitLocker Management'
    $texts = @()
    try {
        foreach ($entry in @(Get-WinEvent -FilterHashtable @{ LogName = $logName; Id = $EscrowEventId } -MaxEvents 200 -ErrorAction Stop)) {
            try { $texts += [string]$entry.ToXml() } catch { $null = $_ }
        }
    }
    catch { return $false }
    foreach ($id in $Ids) {
        $seen = $false
        foreach ($text in $texts) { if ($text.IndexOf($id.Trim('{', '}'), [StringComparison]::OrdinalIgnoreCase) -ge 0) { $seen = $true; break } }
        if (-not $seen) { return $false }
    }
    return $true
}

function Test-TpmReady {
    # '' when the TPM is present and ready, otherwise what is wrong.
    if (-not (Get-Command -Name 'Get-Tpm' -ErrorAction SilentlyContinue)) { return 'the TPM cmdlets are not available on this PC' }
    try { $tpm = Get-Tpm -ErrorAction Stop } catch { return "the TPM could not be read ($($_.Exception.Message))" }
    if (-not $tpm.TpmPresent) { return 'no TPM was found; enable it in the firmware (fTPM or PTT) or use a policy that allows BitLocker without a TPM' }
    if (-not $tpm.TpmReady) { return 'the TPM is present but not ready; enable and initialize it (Initialize-Tpm, or clear it in the firmware)' }
    return ''
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    $fieldName = Get-OutpostRawInput -Name 'ResultField'
    $Config = [pscustomobject]@{
        EscrowRequired   = Read-OutpostBool -Name 'EscrowRequired'
        EncryptionMethod = Read-OutpostChoice -Name 'EncryptionMethod' -Allowed @('XtsAes256', 'XtsAes128', 'Aes256', 'Aes128')
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ($HomeSkus -contains [int]$osInfo.OperatingSystemSKU) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: BitLocker is not available on Windows Home editions.'
    }
    if (-not (Get-Command -Name 'Get-BitLockerVolume' -ErrorAction SilentlyContinue)) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: the BitLocker PowerShell tools are not installed on this PC.'
    }
    $drive = Split-Path -Path ([Environment]::GetFolderPath('Windows')) -Qualifier

    # Detect
    $volume = Get-OsVolume -Drive $drive
    $volumeStatus = [string]$volume.VolumeStatus
    $isProtected = $ProtectionOn -contains [string]$volume.ProtectionStatus
    $targets = @(Get-EscrowTarget)
    $recoveryIds = @(Get-ProtectorId -Volume $volume -Type 'RecoveryPassword')
    $noTarget = ($targets.Count -eq 0)
    $useField = $noTarget -and -not $Config.EscrowRequired
    # On a PC with nowhere to escrow, ResultField is the secret field: guard it on every run.
    if ($noTarget -and $fieldName -ne '') { Assert-OutpostSecretField }

    $mode = 'Encrypt'
    if ($isProtected) {
        $unconfirmed = ($recoveryIds.Count -eq 0)
        if (-not $unconfirmed -and ($targets -contains 'Entra ID')) { $unconfirmed = -not (Test-EntraEscrowEvidence -Ids $recoveryIds) }
        if ($noTarget -or -not $unconfirmed) {
            if ($recoveryIds.Count -eq 0) { Write-OutpostWarning -Text "$drive is protected but has no recovery password key protector." }
            $note = 'no Entra ID or Active Directory to hold a recovery key'
            if ($targets -contains 'Entra ID') { $note = 'recovery key escrow to Entra ID confirmed' }
            elseif ($targets -contains 'Active Directory') { $note = 'recovery key escrow to Active Directory cannot be verified from this PC' }
            Complete-OutpostRun -Status 'OK' -Answer ("Already protected: BitLocker is On for $drive ($([string]$volume.EncryptionMethod), $([int]$volume.EncryptionPercentage)% encrypted); $note; " + (Get-ProtectorText -Volume $volume))
        }
        $mode = 'Escrow'
    }
    elseif ($volumeStatus -ne 'FullyDecrypted') { $mode = 'Resume' }

    if ($noTarget) {
        if ($Config.EscrowRequired) {
            Stop-OutpostRun -Message "No escrow target: this PC is neither Entra-joined nor domain-joined, so the recovery key cannot be stored and $drive was not changed. Join it, or set EscrowRequired to false and ResultField to a secure custom field to keep the recovery password in your RMM."
        }
        Assert-OutpostSecretField
    }
    if (@('DecryptionInProgress', 'DecryptionPaused') -contains $volumeStatus) {
        Stop-OutpostRun -Message "$drive is being decrypted ($volumeStatus). Let it finish, then run again."
    }
    $needsTpmProtector = ($mode -ne 'Escrow') -and (@(Get-ProtectorId -Volume $volume -Type 'Tpm').Count -eq 0)
    if ($needsTpmProtector) {
        $tpmProblem = Test-TpmReady
        if ($tpmProblem -ne '') { Stop-OutpostRun -Message "BitLocker with a TPM cannot start: $tpmProblem." }
    }
    $escrowText = 'key escrowed to ' + ($targets -join ' and ')
    if ($useField) { $escrowText = "recovery password written to field $fieldName" }
    $headline = "BitLocker enabled on $drive ($($Config.EncryptionMethod), used space only)"
    if ($mode -eq 'Resume') { $headline = "BitLocker protection resumed on $drive" }
    if ($mode -eq 'Escrow') { $headline = "Recovery key escrowed for $drive (already protected)" }
    Write-OutpostLine -Text "$headline; mode $mode; $escrowText."

    # Act: recovery protector, then the key stored, then TPM and encryption. Nothing is encrypted before the key is stored.
    $state = @{ AddedIds = @() }
    try {
        if ($recoveryIds.Count -eq 0) {
            $null = Invoke-OutpostChange -Item $drive -Change 'Add a recovery password key protector' -Action {
                $null = Add-BitLockerKeyProtector -MountPoint $drive -RecoveryPasswordProtector -WarningAction SilentlyContinue -ErrorAction Stop 3>$null
            }
            if (-not $script:OutpostRun.DryRun) { $state.AddedIds = @(Get-ProtectorId -Volume (Get-OsVolume -Drive $drive) -Type 'RecoveryPassword') }
        }
        foreach ($target in $targets) {
            $null = Invoke-OutpostChange -Item $drive -Change "Back up the recovery key to $target" -Action {
                foreach ($recoveryId in @(Get-ProtectorId -Volume (Get-OsVolume -Drive $drive) -Type 'RecoveryPassword')) {
                    if ($target -eq 'Entra ID') { $null = BackupToAAD-BitLockerKeyProtector -MountPoint $drive -KeyProtectorId $recoveryId -WarningAction SilentlyContinue -ErrorAction Stop 3>$null }
                    else { $null = Backup-BitLockerKeyProtector -MountPoint $drive -KeyProtectorId $recoveryId -WarningAction SilentlyContinue -ErrorAction Stop 3>$null }
                }
            }
        }
        if ($useField -and -not $script:OutpostRun.DryRun) {
            # The key goes to the RMM field before encryption starts, so a failed write changes nothing more.
            $passwords = @((Get-OsVolume -Drive $drive).KeyProtector | Where-Object { [string]$_.KeyProtectorType -eq 'RecoveryPassword' } | ForEach-Object { [string]$_.RecoveryPassword } | Where-Object { $_ -ne '' })
            if ($passwords.Count -eq 0) { Stop-OutpostRun -Message "No recovery password could be read for $drive to store in ResultField, so nothing was encrypted." }
            Write-OutpostSecretField -Value $passwords[0]
            $passwords = $null
        }
        if ($mode -eq 'Encrypt') {
            $null = Invoke-OutpostChange -Item $drive -Change "Add the TPM protector and start encryption ($($Config.EncryptionMethod), used space only, no hardware test)" -Action {
                $null = Enable-BitLocker -MountPoint $drive -EncryptionMethod $Config.EncryptionMethod -UsedSpaceOnly -SkipHardwareTest -TpmProtector -WarningAction SilentlyContinue -ErrorAction Stop 3>$null
            }
        }
        if ($mode -eq 'Resume') {
            if ($needsTpmProtector) {
                $null = Invoke-OutpostChange -Item $drive -Change 'Add the TPM key protector' -Action {
                    $null = Add-BitLockerKeyProtector -MountPoint $drive -TpmProtector -WarningAction SilentlyContinue -ErrorAction Stop 3>$null
                }
            }
            $null = Invoke-OutpostChange -Item $drive -Change 'Resume BitLocker protection' -Action {
                $null = Resume-BitLocker -MountPoint $drive -WarningAction SilentlyContinue -ErrorAction Stop 3>$null
            }
        }
    }
    catch {
        $failure = $_
        # Encryption did not start: take back the recovery protector this run added.
        try {
            $now = Get-OsVolume -Drive $drive
            if ($mode -eq 'Encrypt' -and ([string]$now.VolumeStatus -eq 'FullyDecrypted') -and ($ProtectionOn -notcontains [string]$now.ProtectionStatus)) {
                foreach ($addedId in $state.AddedIds) { $null = Remove-BitLockerKeyProtector -MountPoint $drive -KeyProtectorId $addedId -WarningAction SilentlyContinue -ErrorAction Stop 3>$null }
            }
        }
        catch { Write-OutpostWarning -Text "Could not remove the recovery protector this run added: $($_.Exception.Message)" }
        Stop-OutpostRun -Message "BitLocker was not changed on $drive as intended." -ErrorRecord $failure
    }

    # Verify (skipped in a dry run: nothing was changed). ProtectionStatus can stay Off for a while
    # during the first encryption pass, so for a new encryption the progress is what counts.
    if (-not $script:OutpostRun.DryRun) {
        $final = $null
        $good = $false
        for ($attempt = 0; $attempt -lt 10 -and -not $good; $attempt++) {
            $final = Get-OsVolume -Drive $drive
            $hasRecovery = @(Get-ProtectorId -Volume $final -Type 'RecoveryPassword').Count -gt 0
            $hasTpm = @(Get-ProtectorId -Volume $final -Type 'Tpm').Count -gt 0
            $started = (@('EncryptionInProgress', 'FullyEncrypted') -contains [string]$final.VolumeStatus) -or ([double]$final.EncryptionPercentage -gt 0)
            if ($mode -eq 'Escrow') { $good = $hasRecovery }
            elseif ($mode -eq 'Resume') { $good = $hasRecovery -and $hasTpm -and ($ProtectionOn -contains [string]$final.ProtectionStatus) }
            else { $good = $hasRecovery -and $hasTpm -and $started }
            if (-not $good) { Start-Sleep -Seconds 2 }
        }
        if (-not $good) {
            Stop-OutpostRun -Message "BitLocker on $drive is not as expected after the change (status $([string]$final.VolumeStatus), protection $([string]$final.ProtectionStatus), $([int]$final.EncryptionPercentage)%). Run manage-bde -status $drive and check the TPM and the recovery partition."
        }
        if ($mode -eq 'Encrypt' -and -not ($ProtectionOn -contains [string]$final.ProtectionStatus)) {
            Write-OutpostWarning -Text "$drive is encrypting; protection shows Off until the first pass completes."
        }
        Complete-OutpostRun -Status 'CHANGED' -Answer ("$headline; $escrowText; protector IDs " + (Get-ProtectorText -Volume $final))
    }

    # Finish (dry run)
    Complete-OutpostRun -Status 'CHANGED' -Answer "$headline; $escrowText"
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
