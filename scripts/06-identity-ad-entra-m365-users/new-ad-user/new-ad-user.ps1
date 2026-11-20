#Requires -Version 5.1
<#
.SYNOPSIS
    Creates Active Directory users, one or from a CSV, copying OU, groups and attributes from a template user; the first password goes to a secure RMM field.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. For each user it creates, in this order:
    1. The user account in the OU: TargetOu when set, else the template user's
       OU, else the domain's default Users container. The sign-in name is
       AccountName; the user principal name is AccountName@UpnSuffix (default:
       the template's suffix, else the domain's DNS name); the common name is
       the display name, which is DisplayName or "GivenName Surname".
    2. A random 20-character password (cryptographic random number generator),
       enabled, with "must change password at next sign-in".
    3. From the template user (TemplateUser, optional): Description, Department,
       Company, Title, Office, Manager, street address, city, state, postal
       code and logon script path, and every group the template is a direct
       member of. Never copied: name, sign-in name, UPN, mail, password, account
       flags, and any group that is privileged (adminCount 1, Domain Admins,
       Enterprise Admins, Schema Admins, a built-in group): those are skipped
       with a warning, so a template can never hand out admin rights.

    THE PASSWORD IS NEVER PRINTED. In single-user mode (AccountName) it is
    written only to the RMM custom field named by ResultField (a secure /
    secret field; NinjaOne, Datto RMM and Syncro are supported) before the
    account is created. The script refuses without one. OutputFormat Answer is
    refused for the same reason. A field holds one password, so CSV mode
    (CsvPath) cannot use it: every user from the CSV gets a random password
    nobody knows, and you issue the first real password with
    reset-ad-user-password, one user at a time.

    CSV mode: a header line then one user per row. Columns: AccountName
    (required), GivenName, Surname, DisplayName, TemplateUser, TargetOu. An empty
    cell uses the matching input. At most 200 rows. A row that fails does not
    stop the others; the run ends ERROR listing the failures.

    Second run: a user whose sign-in name already exists is left alone: OK
    "Already exists". Nothing existing is changed, not even its groups.

    Run it on a domain controller or a member server with the ActiveDirectory
    module (RSAT). Without the module it ends ERROR; on a computer that is not
    in a domain it ends SKIPPED.

.PARAMETER AccountName
    The new sign-in name (sAMAccountName): 1 to 20 letters, digits, dot, dash or
    underscore. Required unless CsvPath is set. (Named AccountName, not
    UserName: Windows already has an environment variable called USERNAME.)
    Environment variable: AccountName

.PARAMETER GivenName
    First name. Default empty. Environment variable: GivenName

.PARAMETER Surname
    Last name. Default empty. Environment variable: Surname

.PARAMETER DisplayName
    Display name and common name. Default: "GivenName Surname", else
    AccountName. May not contain , = + < > # ; " or a backslash.
    Environment variable: DisplayName

.PARAMETER TemplateUser
    Sign-in name of an existing user to copy the OU, groups and attributes
    from. Default empty: nothing is copied. Environment variable: TemplateUser

.PARAMETER TargetOu
    Distinguished name of the OU or container for the new user, e.g.
    "OU=Staff,DC=contoso,DC=com". Default empty: the template's OU, else the
    domain's Users container. It must exist. Environment variable: TargetOu

.PARAMETER UpnSuffix
    The part after the @ in the user principal name. Default empty: the
    template's suffix, else the domain's DNS name. Environment variable: UpnSuffix

.PARAMETER CsvPath
    Path of a CSV file of users to create (see above). Default empty: create
    the one user in AccountName. Environment variable: CsvPath

.PARAMETER DryRun
    true to list what would be created and create nothing. Default false.
    -WhatIf does the same. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Json or Csv. Answer is refused in single-user mode because it
    would print the password. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows (never a password) to this .csv or .json file.
    Environment variable: ExportPath

.PARAMETER ResultField
    The RMM custom field that receives the password, a secure field (single-user
    mode; required there). NinjaOne: the field name; Datto RMM: the UDF number
    1-300; Syncro: the asset field. Environment variable: ResultField

.EXAMPLE
    .\new-ad-user.ps1 -AccountName jsmith -GivenName Jo -Surname Smith -TemplateUser template-sales -ResultField NewUserPassword

    Creates jsmith like the template-sales user and stores the first password in the field.

.EXAMPLE
    .\new-ad-user.ps1 -CsvPath C:\Temp\new-users.csv -TargetOu "OU=Staff,DC=contoso,DC=com"

    Creates every user in the CSV in the Staff OU (passwords come later from reset-ad-user-password).

.NOTES
    Name:        New employee - create the AD user like a template user
    Slug:        new-ad-user
    Version:     1.0.0
    Updated:     2026-11-19
    Type:        Action
    Category:    06 Identity: AD / Entra / M365 users
    Platforms:   Windows Server 2016+ (domain controller or domain member)
    RunAs:       System
    Requires:    PowerShell 5.1; admin rights; ActiveDirectory module; rights to create users; a secure RMM field for the password
    Changes:     Creates AD users, adds them to the template's non-privileged groups and writes the first password to the RMM custom field
    Risk:        Low
    Reboot:      Never
    Runtime:     Under 20 seconds per user
    Answer:      "Created jsmith in OU=Staff,DC=contoso,DC=com; must change password at first sign-in; password written to field NewUserPassword; added to 3 group(s)"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/new-ad-user
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-19  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $AccountName = '',
    [string] $GivenName = '',
    [string] $Surname = '',
    [string] $DisplayName = '',
    [string] $TemplateUser = '',
    [string] $TargetOu = '',
    [string] $UpnSuffix = '',
    [string] $CsvPath = '',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'new-ad-user'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('AccountName', 'GivenName', 'Surname', 'DisplayName', 'TemplateUser', 'TargetOu', 'UpnSuffix', 'CsvPath')
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
$TemplateProperties = @('MemberOf', 'UserPrincipalName', 'Description', 'Department', 'Company', 'Title', 'Office', 'Manager', 'StreetAddress', 'City', 'State', 'PostalCode', 'ScriptPath')
$CopiedAttributes = @('Description', 'Department', 'Company', 'Title', 'Office', 'Manager', 'StreetAddress', 'City', 'State', 'PostalCode', 'ScriptPath')
$AccountNamePattern = '^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$'
$DisplayNameBadPattern = '[,=+<>#;"\\]'
$SuffixPattern = '^[A-Za-z0-9][A-Za-z0-9.-]*$'
$PrivilegedGroupSidPattern = '^S-1-5-32-|-(512|516|518|519|520|521|498)$'
$PasswordLength = 20
$MaxCsvRows = 200

# ---- Functions ------------------------------------------------------------
function Assert-DomainMember {
    # SKIPPED when this computer is not in a domain, ERROR when the module is missing, else loads it.
    if (-not [bool](Get-CimInstance -ClassName Win32_ComputerSystem).PartOfDomain) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: this computer is not joined to an Active Directory domain.'
    }
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Stop-OutpostRun -Message 'The ActiveDirectory PowerShell module was not found. On a domain controller run Install-WindowsFeature RSAT-AD-PowerShell; on a member server install the RSAT Active Directory tools. Then run again.'
    }
    Import-Module -Name ActiveDirectory
}

function Get-AdValue {
    # A property of an AD object, or $null when the object does not have it (strict mode throws on a missing one).
    param($Object, [string] $Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertTo-LdapText {
    # Escapes a value for an LDAP filter (RFC 4515).
    param([string] $Text)
    return ($Text -replace '\\', '\5c' -replace '\*', '\2a' -replace '\(', '\28' -replace '\)', '\29')
}

function Find-AdUser {
    # One user by sign-in name, DOMAIN\name or UPN, or $null when there is none.
    param([string] $Name, [string[]] $Property)
    $clean = $Name -replace '^[^\\]+\\', ''
    $escaped = ConvertTo-LdapText -Text $clean
    $filter = "(&(objectCategory=person)(objectClass=user)(sAMAccountName=$escaped))"
    if ($clean -match '@') { $filter = "(&(objectCategory=person)(objectClass=user)(userPrincipalName=$escaped))" }
    $found = @(Get-ADUser -LDAPFilter $filter -Properties $Property)
    if ($found.Count -eq 0) { return $null }
    return $found[0]
}

function Get-ParentDn {
    param([string] $DistinguishedName)
    return ($DistinguishedName -replace '^CN=(?:[^,\\]|\\.)+,', '')
}

function Assert-Container {
    # Stops unless this distinguished name is an existing OU or container.
    param([string] $DistinguishedName, [string] $InputName)
    $found = $null
    try { $found = Get-ADObject -Identity $DistinguishedName }
    catch { $found = $null }
    if ($null -eq $found -or @('organizationalUnit', 'container') -notcontains [string]$found.ObjectClass) {
        Stop-OutpostRun -Message "The OU '$DistinguishedName' ($InputName) was not found (or is not an OU or container). Create it or correct the value, then run again. Nothing was changed."
    }
}

function Get-RandomIndex {
    param($Generator, [int] $Count)
    $buffer = New-Object -TypeName byte[] -ArgumentList 4
    $Generator.GetBytes($buffer)
    return [int]([BitConverter]::ToUInt32($buffer, 0) % $Count)
}

function New-RandomPassword {
    # A random password with upper, lower, digit and symbol characters (no look-alike characters). Never printed.
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!@#%^&*-_=+')
    $all = $sets -join ''
    $generator = New-Object -TypeName System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $chars = New-Object -TypeName System.Collections.ArrayList
        foreach ($set in $sets) { [void]$chars.Add($set[(Get-RandomIndex -Generator $generator -Count $set.Length)]) }
        while ($chars.Count -lt $PasswordLength) { [void]$chars.Add($all[(Get-RandomIndex -Generator $generator -Count $all.Length)]) }
        for ($i = $chars.Count - 1; $i -gt 0; $i--) {
            $j = Get-RandomIndex -Generator $generator -Count ($i + 1)
            $swap = $chars[$i]
            $chars[$i] = $chars[$j]
            $chars[$j] = $swap
        }
        return (-join $chars)
    }
    finally { $generator.Dispose() }
}

function Get-CsvCell {
    # A trimmed cell of a CSV row, or '' when the column is missing or empty.
    param($Row, [string] $Column)
    $value = Get-AdValue -Object $Row -Name $Column
    if ($null -eq $value) { return '' }
    return ([string]$value).Trim()
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config. Nothing is changed before this is done.
    $Config = [pscustomobject]@{
        AccountName  = Read-OutpostText -Name 'AccountName'
        GivenName    = Read-OutpostText -Name 'GivenName'
        Surname      = Read-OutpostText -Name 'Surname'
        DisplayName  = Read-OutpostText -Name 'DisplayName'
        TemplateUser = Read-OutpostText -Name 'TemplateUser'
        TargetOu     = Read-OutpostText -Name 'TargetOu'
        UpnSuffix    = Read-OutpostText -Name 'UpnSuffix'
        CsvPath      = Read-OutpostText -Name 'CsvPath'
    }
    $isCsvMode = ($Config.CsvPath -ne '')
    $fieldName = Get-OutpostRawInput -Name 'ResultField'
    if (-not $isCsvMode) {
        if ($Config.AccountName -eq '') { Stop-OutpostRun -Message 'Set AccountName (the new sign-in name) or CsvPath (a CSV of users). Nothing was changed.' }
        Assert-OutpostSecretField
    }
    if ($Config.UpnSuffix -ne '' -and $Config.UpnSuffix -notmatch $SuffixPattern) {
        Stop-OutpostInput -Name 'UpnSuffix' -Value $Config.UpnSuffix -Expected 'a domain name such as contoso.com'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    Assert-DomainMember
    $domainInfo = Get-ADDomain

    # Validate: the list of users to create.
    $sourceRows = @()
    if ($isCsvMode) {
        if (-not (Test-Path -LiteralPath $Config.CsvPath -PathType Leaf)) {
            Stop-OutpostRun -Message "The CSV file '$($Config.CsvPath)' (CsvPath) was not found. Correct the path, then run again. Nothing was changed."
        }
        $sourceRows = @(Import-Csv -LiteralPath $Config.CsvPath)
        if ($sourceRows.Count -eq 0) { Stop-OutpostRun -Message "The CSV file '$($Config.CsvPath)' has no users. It needs a header line and one user per row. Nothing was changed." }
        if ($sourceRows.Count -gt $MaxCsvRows) { Stop-OutpostRun -Message "The CSV file has $($sourceRows.Count) users; the limit is $MaxCsvRows per run. Split it. Nothing was changed." }
    }
    else {
        $sourceRows = @([pscustomobject]@{ AccountName = $Config.AccountName; GivenName = $Config.GivenName; Surname = $Config.Surname; DisplayName = $Config.DisplayName; TemplateUser = $Config.TemplateUser; TargetOu = $Config.TargetOu })
    }
    $templates = @{}
    $requests = New-Object -TypeName System.Collections.ArrayList
    $seenNames = @{}
    foreach ($sourceRow in $sourceRows) {
        $samName = Get-CsvCell -Row $sourceRow -Column 'AccountName'
        if ($samName -notmatch $AccountNamePattern) {
            Stop-OutpostRun -Message "The sign-in name '$samName' is not valid: use 1 to 20 letters, digits, dot, dash or underscore. Correct AccountName (or the CSV row), then run again. Nothing was changed."
        }
        if ($seenNames.ContainsKey($samName.ToLowerInvariant())) { Stop-OutpostRun -Message "The sign-in name '$samName' appears twice. Remove the duplicate, then run again. Nothing was changed." }
        $seenNames[$samName.ToLowerInvariant()] = $true
        $givenText = Get-CsvCell -Row $sourceRow -Column 'GivenName'
        if ($givenText -eq '') { $givenText = $Config.GivenName }
        $surnameText = Get-CsvCell -Row $sourceRow -Column 'Surname'
        if ($surnameText -eq '') { $surnameText = $Config.Surname }
        $displayText = Get-CsvCell -Row $sourceRow -Column 'DisplayName'
        if ($displayText -eq '' -and -not $isCsvMode) { $displayText = $Config.DisplayName }
        if ($displayText -eq '') { $displayText = ($givenText + ' ' + $surnameText).Trim() }
        if ($displayText -eq '') { $displayText = $samName }
        if ($displayText -match $DisplayNameBadPattern) {
            Stop-OutpostRun -Message "The display name '$displayText' contains a character that is not allowed in a common name (, = + < > # ; `" or a backslash). Change DisplayName, then run again. Nothing was changed."
        }
        $templateText = Get-CsvCell -Row $sourceRow -Column 'TemplateUser'
        if ($templateText -eq '') { $templateText = $Config.TemplateUser }
        $ouText = Get-CsvCell -Row $sourceRow -Column 'TargetOu'
        if ($ouText -eq '') { $ouText = $Config.TargetOu }
        $template = $null
        if ($templateText -ne '') {
            if (-not $templates.ContainsKey($templateText)) {
                $found = Find-AdUser -Name $templateText -Property $TemplateProperties
                if ($null -eq $found) { Stop-OutpostRun -Message "The template user '$templateText' was not found in Active Directory. Check TemplateUser, then run again. Nothing was changed." }
                $templates[$templateText] = $found
            }
            $template = $templates[$templateText]
        }
        if ($ouText -eq '') {
            if ($null -ne $template) { $ouText = Get-ParentDn -DistinguishedName ([string]$template.DistinguishedName) }
            else { $ouText = [string]$domainInfo.UsersContainer }
        }
        $suffixText = $Config.UpnSuffix
        if ($suffixText -eq '' -and $null -ne $template -and ([string]$template.UserPrincipalName) -match '@(.+)$') { $suffixText = $Matches[1] }
        if ($suffixText -eq '') { $suffixText = [string]$domainInfo.DNSRoot }
        [void]$requests.Add([pscustomobject]@{ Sam = $samName; Given = $givenText; Surname = $surnameText; Display = $displayText; Template = $template; Ou = $ouText; Upn = ($samName + '@' + $suffixText) })
    }
    foreach ($ouDn in @($requests | ForEach-Object { $_.Ou } | Sort-Object -Unique)) { Assert-Container -DistinguishedName $ouDn -InputName 'TargetOu' }

    # Detect: who exists already, name clashes, and the groups to copy.
    $plan = @()
    $existingCount = 0
    $planned = 0
    foreach ($request in $requests) {
        $existing = Find-AdUser -Name $request.Sam -Property @('DistinguishedName')
        if ($null -ne $existing) {
            $existingCount++
            Add-OutpostRow -Values @{ Item = $request.Sam; Change = 'Create the user'; Result = 'Already exists' }
            continue
        }
        $upnClash = Find-AdUser -Name $request.Upn -Property @('DistinguishedName')
        if ($null -ne $upnClash) {
            Stop-OutpostRun -Message "The user principal name $($request.Upn) is already used by $($upnClash.SamAccountName). Change UpnSuffix or AccountName, then run again. Nothing was changed."
        }
        $nameClash = @(Get-ADObject -LDAPFilter ('(cn=' + (ConvertTo-LdapText -Text $request.Display) + ')') -SearchBase $request.Ou -SearchScope OneLevel)
        if ($nameClash.Count -gt 0) {
            Stop-OutpostRun -Message "An object named '$($request.Display)' already exists in $($request.Ou). Set DisplayName to something unique, then run again. Nothing was changed."
        }
        $groups = @()
        if ($null -ne $request.Template) {
            foreach ($groupDn in @(Get-AdValue -Object $request.Template -Name 'MemberOf' | Where-Object { $_ })) {
                $groupInfo = Get-ADGroup -Identity ([string]$groupDn) -Properties adminCount
                $isPrivileged = ([string]$groupInfo.SID.Value -match $PrivilegedGroupSidPattern) -or ([int](Get-AdValue -Object $groupInfo -Name 'adminCount') -eq 1)
                if ($isPrivileged) {
                    Write-OutpostWarning -Text "Group $($groupInfo.Name) is privileged and is not copied to $($request.Sam)."
                    continue
                }
                $groups += [pscustomobject]@{ Dn = [string]$groupInfo.DistinguishedName; Name = [string]$groupInfo.Name }
            }
        }
        $plan += [pscustomobject]@{ Request = $request; Groups = $groups }
        $planned += 1 + $groups.Count
    }
    Write-OutpostLine -Text "$($requests.Count) user(s) requested: $($plan.Count) to create, $existingCount already exist."
    if ($plan.Count -eq 0) {
        if ($requests.Count -eq 1) {
            $only = Find-AdUser -Name $requests[0].Sam -Property @('DistinguishedName')
            Complete-OutpostRun -Status 'OK' -Answer "Already exists: $($requests[0].Sam) ($($only.DistinguishedName))"
        }
        Complete-OutpostRun -Status 'OK' -Answer "Already exist: all $($requests.Count) user(s); nothing created"
    }

    # Act: the password goes to the RMM field FIRST (single-user mode), then the account is created; it is never printed.
    Assert-OutpostChangeLimit -Planned $planned
    $failed = @()
    $createdCount = 0
    $groupCount = 0
    $state = @{ Password = ''; Guid = '' }
    foreach ($item in $plan) {
        $request = $item.Request
        $state.Guid = ''
        try {
            $null = Invoke-OutpostChange -Item $request.Sam -Change "Create the user in $($request.Ou)" -Action {
                $state.Password = New-RandomPassword
                if (-not $isCsvMode) { Write-OutpostSecretField -Value $state.Password }
                $newUser = @{
                    Name                  = $request.Display
                    SamAccountName        = $request.Sam
                    UserPrincipalName     = $request.Upn
                    DisplayName           = $request.Display
                    Path                  = $request.Ou
                    AccountPassword       = (ConvertTo-SecureString -String $state.Password -AsPlainText -Force)
                    Enabled               = $true
                    ChangePasswordAtLogon = $true
                    PassThru              = $true
                }
                if ($request.Given -ne '') { $newUser['GivenName'] = $request.Given }
                if ($request.Surname -ne '') { $newUser['Surname'] = $request.Surname }
                if ($null -ne $request.Template) {
                    foreach ($attribute in $CopiedAttributes) {
                        $copied = Get-AdValue -Object $request.Template -Name $attribute
                        if ($null -ne $copied -and ([string]$copied) -ne '') { $newUser[$attribute] = [string]$copied }
                    }
                }
                $state.Guid = [string](New-ADUser @newUser).ObjectGUID
                $state.Password = ''
            }
            $state.Password = ''
            if (-not $script:OutpostRun.DryRun) { $createdCount++ }
            foreach ($group in $item.Groups) {
                $null = Invoke-OutpostChange -Item $request.Sam -Change "Add to group $($group.Name) ($($group.Dn))" -Action {
                    Add-ADGroupMember -Identity $group.Dn -Members $state.Guid
                }
                if (-not $script:OutpostRun.DryRun) { $groupCount++ }
            }
            if (-not $script:OutpostRun.DryRun) {
                $after = Get-ADUser -Identity $state.Guid -Properties Enabled, pwdLastSet, MemberOf
                if (-not [bool](Get-AdValue -Object $after -Name 'Enabled')) { $failed += "$($request.Sam) was created but is disabled (the domain password policy may have rejected the password; run reset-ad-user-password on it)" }
                $memberOf = @(Get-AdValue -Object $after -Name 'MemberOf' | Where-Object { $_ } | ForEach-Object { [string]$_ })
                foreach ($group in $item.Groups) { if ($memberOf -notcontains $group.Dn) { $failed += "$($request.Sam) is not in group $($group.Name)" } }
            }
        }
        catch {
            $state.Password = ''
            $failed += "$($request.Sam): $($_.Exception.Message)"
            Write-OutpostWarning -Text "Could not finish $($request.Sam): $($_.Exception.Message)"
        }
    }
    $state.Password = ''
    if ($failed.Count -gt 0) {
        Stop-OutpostRun -Message ('Creating users did not finish: ' + ($failed -join '; ') + '. Users already created are skipped when you run again.')
    }

    # Finish
    if ($isCsvMode) {
        Complete-OutpostRun -Status 'CHANGED' -Answer "Created $($plan.Count) of $($requests.Count) user(s) from the CSV ($existingCount already existed); $groupCount group membership(s) added; passwords not issued: use reset-ad-user-password"
    }
    $only = $plan[0]
    Complete-OutpostRun -Status 'CHANGED' -Answer "Created $($only.Request.Sam) in $($only.Request.Ou); must change password at first sign-in; password written to field $fieldName; added to $($only.Groups.Count) group(s)"
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
