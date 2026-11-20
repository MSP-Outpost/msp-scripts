#Requires -Version 5.1
<#
.SYNOPSIS
    Offboards one Microsoft 365 user: blocks sign-in, revokes sessions, removes groups and licences, converts the mailbox to shared and hands it to a manager.
.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. For the ONE user in UserPrincipalName it can, each as a separate logged change and each switched off by its input:
      1. block sign-in (accountEnabled = false);
      2. revoke all sign-in sessions and refresh tokens;
      3. remove the user from groups: Microsoft 365 groups and security groups only. Dynamic-membership groups, groups synced from on-premises Active Directory, role-assignable groups and mail-enabled security or distribution groups (managed in Exchange) are skipped and listed;
      4. convert the mailbox to a shared mailbox (Exchange Online);
      5. set the automatic reply to AutoReplyText for internal and external senders (Exchange Online);
      6. when ManagerUpn is set: forward the mail to the manager and keep a copy (Forward), grant the manager Full Access to the mailbox (FullAccess) or both, as ManagerMailboxAccess says (Exchange Online);
      7. hide the mailbox from address lists (Exchange Online);
      8. remove the licences assigned directly to the user (licences inherited from a group go when the group membership goes, and are listed otherwise).
    ORDER: the mailbox is converted to shared BEFORE the licences are removed, so the mailbox is never left unlicensed and unconverted; if a mailbox step fails the run stops before any licence is removed. Before anything changes, the user's groups, licences and mailbox settings (forwarding, auto-reply, address-list visibility) are written as JSON under the MSP Outpost data folder (the file is named in the output) so each step can be undone by hand.
    It NEVER deletes the user, the mailbox, a group or a licence subscription, never resets the password and never removes OneDrive data. High risk: it is a dry run until DryRun=false AND Approve=invoke-m365-offboarding are both set. Running it again repeats only what is still undone, plus the steps that always run (sign-in sessions are revoked again, and the auto-reply, forwarding and Full Access steps run again when their inputs are set). Users synced from on-premises Active Directory cannot be blocked or hidden from Microsoft 365: those two steps are skipped with a note and must be done in Active Directory.

    Microsoft Graph application permissions (admin consent): User.EnableDisableAccount.All and User.Read.All (block sign-in), User.RevokeSessions.All, GroupMember.ReadWrite.All and Directory.Read.All (groups), LicenseAssignment.ReadWrite.All (licences). The app also needs an Entra administrator role that may change administrators if the user is one (Microsoft's rule for sensitive actions). Exchange steps need ExchangeOnlineManagement 3.1 or later, the Exchange.ManageAsApp permission and the Exchange Administrator role on the app. Exchange steps are only used when switched on; when the module is missing the run is SKIPPED before anything changes.

    Where each fact comes from (read in Microsoft's reference): PATCH v1.0/users/{id} accountEnabled (User.EnableDisableAccount.All + User.Read.All is the least-privileged pair; sensitive-action role rule for app-only calls); POST v1.0/users/{id}/revokeSignInSessions (User.RevokeSessions.All); GET v1.0/users/{id}/memberOf/microsoft.graph.group (needs ConsistencyLevel eventual and $count for the cast; Directory.Read.All for another user); DELETE v1.0/groups/{id}/members/{id}/$ref (GroupMember.ReadWrite.All; dynamic groups cannot be changed; role-assignable groups also need RoleManagement.ReadWrite.Directory, which this script does not use); POST v1.0/users/{id}/assignLicense with removeLicenses (LicenseAssignment.ReadWrite.All); licenseAssignmentStates.assignedByGroup (null when assigned directly); Set-Mailbox -Type Shared, -ForwardingAddress, -DeliverToMailboxAndForward, -HiddenFromAddressListsEnabled; Set-MailboxAutoReplyConfiguration -AutoReplyState Enabled -InternalMessage -ExternalMessage -ExternalAudience All; Add-MailboxPermission -AccessRights FullAccess.
    Not confirmed in the documentation, so read defensively: the Get-Mailbox output property names ForwardingAddress, ForwardingSmtpAddress, DeliverToMailboxAndForward, RecipientTypeDetails and HiddenFromAddressListsEnabled (named on the Set-Mailbox page, not on Get-Mailbox); what Add-MailboxPermission does when the manager already has the permission (the run reports the error); whether a mail-enabled group is always unmanageable from Graph (this script skips them rather than try); the exact Exchange role the app needs (Exchange Administrator is Microsoft's usual answer).
.PARAMETER TenantId
    The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required.
    Environment variable: TenantId
.PARAMETER ClientId
    The app registration's Application (client) ID, a GUID. Required.
    Environment variable: ClientId
.PARAMETER CertificateThumbprint
    Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field).
    Environment variable: CertificateThumbprint
.PARAMETER UserPrincipalName
    The user to offboard, such as jane@contoso.com. Required. One user per run.
    Environment variable: UserPrincipalName
.PARAMETER BlockSignIn
    true to block sign-in. Default true.
    Environment variable: BlockSignIn
.PARAMETER RevokeSessions
    true to revoke sessions and refresh tokens. Default true.
    Environment variable: RevokeSessions
.PARAMETER RemoveFromGroups
    true to remove the user from groups (not dynamic, not synced, not role-assignable, not mail-enabled security or distribution). Default true.
    Environment variable: RemoveFromGroups
.PARAMETER ConvertToShared
    true to convert the mailbox to a shared mailbox. Default true.
    Environment variable: ConvertToShared
.PARAMETER AutoReplyText
    Text of the automatic reply for internal and external senders. Empty (default) leaves the auto-reply alone.
    Environment variable: AutoReplyText
.PARAMETER ManagerUpn
    The manager who receives the mail or the access, such as boss@contoso.com. Empty (default) skips that step.
    Environment variable: ManagerUpn
.PARAMETER ManagerMailboxAccess
    What ManagerUpn gets: FullAccess (default), Forward (forward and keep a copy), Both or None.
    Environment variable: ManagerMailboxAccess
.PARAMETER HideFromAddressLists
    true to hide the mailbox from address lists. Default true.
    Environment variable: HideFromAddressLists
.PARAMETER RemoveLicenses
    true to remove the directly assigned licences, after the mailbox steps. Default true.
    Environment variable: RemoveLicenses
.PARAMETER DryRun
    true (the default for this High-risk script) lists every change and makes none. The script changes things only with DryRun=false and Approve=invoke-m365-offboarding.
    Environment variable: DryRun
.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat
.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath
.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField
.EXAMPLE
    .\invoke-m365-offboarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName jane@contoso.com -ManagerUpn boss@contoso.com
    Dry run: lists everything it would do for Jane and changes nothing.
.EXAMPLE
    .\invoke-m365-offboarding.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -UserPrincipalName jane@contoso.com -AutoReplyText "Jane has left. Please write to sales@contoso.com." -DryRun false -Approve invoke-m365-offboarding
    Offboards Jane for real, with an auto-reply and the defaults for the other steps.
.NOTES
    Name:        Employee left - Microsoft 365 offboarding
    Slug:        invoke-m365-offboarding
    Version:     1.0.0
    Updated:     2026-11-18
    Type:        Action
    Category:    17 Offboarding & decommission
    Platforms:   Windows 10, 11, Server 2016+, with the app certificate
    RunAs:       Either
    Requires:    PowerShell 5.1; Graph user, group and license permissions (see the script); Exchange app access for mail
    Changes:     Blocks sign-in; revokes sessions; removes group memberships; converts the mailbox to shared; sets the auto-reply, forwarding, manager access and address-list visibility; removes direct licences; writes a before-state JSON file
    Risk:        High
    Reboot:      Never
    Runtime:     Under 3 minutes
    Answer:      "Offboarded jane@contoso.com: sign-in blocked, sessions revoked, 4 groups, mailbox shared, 2 licences"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/invoke-m365-offboarding
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-18  First version (untested).
#>
[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text. Defaults are the
    # place to edit when your RMM cannot pass arguments or variables.
    [string] $TenantId = '',
    [string] $ClientId = '',
    [string] $CertificateThumbprint = '',
    [string] $UserPrincipalName = '',
    [string] $BlockSignIn = 'true',
    [string] $RevokeSessions = 'true',
    [string] $RemoveFromGroups = 'true',
    [string] $ConvertToShared = 'true',
    [string] $AutoReplyText = '',
    [string] $ManagerUpn = '',
    [string] $ManagerMailboxAccess = 'FullAccess',
    [string] $HideFromAddressLists = 'true',
    [string] $RemoveLicenses = 'true',
    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)
# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'invoke-m365-offboarding'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('TenantId', 'ClientId', 'CertificateThumbprint', 'UserPrincipalName', 'BlockSignIn', 'RevokeSessions', 'RemoveFromGroups', 'ConvertToShared', 'AutoReplyText', 'ManagerUpn', 'ManagerMailboxAccess', 'HideFromAddressLists', 'RemoveLicenses')
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
#region MSP Outpost Microsoft 365 1.0.0 -- do not edit (shared by every MSP Outpost Microsoft 365 script)
# App-only sign-in to one client tenant, then Microsoft Graph over REST (no Graph module to install).
# Inputs every Microsoft 365 script declares: TenantId, ClientId, CertificateThumbprint.
#   Certificate (preferred): the app registration's certificate with its private key in
#   Cert:\LocalMachine\My (or the running account's CurrentUser\My). Nothing secret is passed.
#   Client secret (when there is no certificate): the secret in the environment variable
#   ClientSecret, from a secure/hidden RMM field. It is never printed, logged or written.
# The token lives in memory for this run only.
$script:OutpostM365 = @{ Token = $null; Expires = [DateTime]::MinValue; Tenant = ''; Client = ''; Thumbprint = ''; Certificate = $null }
$OutpostGraphRoot = 'https://graph.microsoft.com/'
$OutpostLoginRoot = 'https://login.microsoftonline.com/'

function ConvertTo-OutpostBase64Url {
    param([Parameter(Mandatory = $true)][byte[]] $Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Read-OutpostM365Inputs {
    # Reads and checks TenantId, ClientId and CertificateThumbprint (or the ClientSecret variable).
    $tenant = Read-OutpostText -Name 'TenantId' -Required
    if ($tenant -notmatch '^([0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}|[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,})$') {
        Stop-OutpostInput -Name 'TenantId' -Value $tenant -Expected 'the tenant ID (a GUID) or a domain such as contoso.onmicrosoft.com'
    }
    $client = Read-OutpostText -Name 'ClientId' -Required
    if ($client -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        Stop-OutpostInput -Name 'ClientId' -Value $client -Expected "the app registration's Application (client) ID, a GUID"
    }
    $thumb = (Read-OutpostText -Name 'CertificateThumbprint') -replace '[^0-9A-Fa-f]', ''
    $script:OutpostM365.Tenant = $tenant
    $script:OutpostM365.Client = $client
    $script:OutpostM365.Thumbprint = $thumb.ToUpperInvariant()
    if ($thumb) {
        if ($thumb.Length -ne 40) { Stop-OutpostInput -Name 'CertificateThumbprint' -Value $thumb -Expected '40 hexadecimal characters' }
        $cert = $null
        foreach ($store in @('Cert:\LocalMachine\My', 'Cert:\CurrentUser\My')) {
            $found = Get-ChildItem -LiteralPath $store -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $script:OutpostM365.Thumbprint } | Select-Object -First 1
            if ($null -ne $found) { $cert = $found; break }
        }
        if ($null -eq $cert) { Stop-OutpostRun -Message "No certificate with thumbprint $($script:OutpostM365.Thumbprint) in LocalMachine\My or CurrentUser\My on this computer." }
        if (-not $cert.HasPrivateKey) { Stop-OutpostRun -Message "The certificate $($script:OutpostM365.Thumbprint) has no private key on this computer (import the .pfx, not the .cer)." }
        if ($cert.NotAfter -lt [DateTime]::Now) { Stop-OutpostRun -Message "The certificate $($script:OutpostM365.Thumbprint) expired on $($cert.NotAfter.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture))." }
        $script:OutpostM365.Certificate = $cert
    }
    elseif (-not (Read-OutpostSecret -Name 'ClientSecret')) {
        Stop-OutpostRun -Message 'Set CertificateThumbprint (preferred), or put the app secret in the environment variable ClientSecret (a secure/hidden RMM field).'
    }
}

function New-OutpostClientAssertion {
    param([Parameter(Mandatory = $true)][string] $Audience)
    $cert = $script:OutpostM365.Certificate
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $head = @{ alg = 'RS256'; typ = 'JWT'; x5t = (ConvertTo-OutpostBase64Url -Bytes $cert.GetCertHash()) } | ConvertTo-Json -Compress
    $claims = @{ aud = $Audience; iss = $script:OutpostM365.Client; sub = $script:OutpostM365.Client; jti = [guid]::NewGuid().ToString(); nbf = $now - 60; exp = $now + 600 } | ConvertTo-Json -Compress
    $unsigned = (ConvertTo-OutpostBase64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($head))) + '.' + (ConvertTo-OutpostBase64Url -Bytes ([Text.Encoding]::UTF8.GetBytes($claims)))
    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if ($null -eq $rsa) { Stop-OutpostRun -Message "The certificate $($script:OutpostM365.Thumbprint) does not hold an RSA private key." }
    $signature = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    return $unsigned + '.' + (ConvertTo-OutpostBase64Url -Bytes $signature)
}

function Get-OutpostM365Token {
    # A token for one resource ('https://graph.microsoft.com' or 'https://outlook.office365.com').
    param([string] $Resource = 'https://graph.microsoft.com')
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $tokenUri = $OutpostLoginRoot + [Uri]::EscapeDataString($script:OutpostM365.Tenant) + '/oauth2/v2.0/token'
    $form = @{ client_id = $script:OutpostM365.Client; scope = "$Resource/.default"; grant_type = 'client_credentials' }
    if ($null -ne $script:OutpostM365.Certificate) {
        $form['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        $form['client_assertion'] = New-OutpostClientAssertion -Audience $tokenUri
    }
    else { $form['client_secret'] = Read-OutpostSecret -Name 'ClientSecret' -Required }
    try {
        $reply = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $form -ContentType 'application/x-www-form-urlencoded' -UseBasicParsing -ErrorAction Stop
    }
    catch {
        $why = Get-OutpostM365Error -ErrorRecord $_
        Stop-OutpostRun -Message "Sign-in to tenant $($script:OutpostM365.Tenant) as app $($script:OutpostM365.Client) failed: $why"
    }
    return $reply
}

function Get-OutpostM365Error {
    # The service's own error code and message, never the request (which may carry a secret).
    param([Parameter(Mandatory = $true)] $ErrorRecord)
    $text = ''
    if ($null -ne $ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) { $text = [string]$ErrorRecord.ErrorDetails.Message }
    $status = ''
    $response = $ErrorRecord.Exception.PSObject.Properties['Response']
    if ($null -ne $response -and $null -ne $response.Value) { try { $status = [string][int]$response.Value.StatusCode } catch { $status = '' } }
    if (-not $text -and $null -ne $response -and $null -ne $response.Value -and $response.Value.PSObject.Methods['GetResponseStream']) {
        # Windows PowerShell 5.1 leaves some error bodies (Graph's 401) unread in the response stream.
        try {
            $stream = $response.Value.GetResponseStream()
            if ($stream.CanSeek) { $stream.Position = 0 }
            $text = (New-Object -TypeName System.IO.StreamReader -ArgumentList $stream).ReadToEnd()
        }
        catch { $text = '' }
    }
    $message = ''
    if ($text) {
        try {
            $parsed = $text | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.PSObject.Properties['error_description']) { $message = (([string]$parsed.error_description) -split "`r?`n")[0] }
            elseif ($parsed.PSObject.Properties['error'] -and $parsed.error.PSObject.Properties['message']) { $message = "$($parsed.error.code): $($parsed.error.message)" }
        }
        catch { $message = '' }
    }
    if (-not $message) { $message = $ErrorRecord.Exception.Message }
    if ($status) { return "HTTP $status $message" }
    return $message
}

function Connect-OutpostGraph {
    if ($script:OutpostM365.Token -and $script:OutpostM365.Expires -gt [DateTime]::UtcNow.AddMinutes(5)) { return }
    $reply = Get-OutpostM365Token -Resource 'https://graph.microsoft.com'
    $script:OutpostM365.Token = [string]$reply.access_token
    $script:OutpostM365.Expires = [DateTime]::UtcNow.AddSeconds([int]$reply.expires_in)
}

function Invoke-OutpostGraph {
    # One Graph call. -Path is relative to https://graph.microsoft.com/ ('v1.0/users?$select=id')
    # or a full nextLink. -All follows @odata.nextLink and returns every item of "value": wrap the call in @().
    # Throttling (429) and brief outages (503, 504) are retried up to 4 times.
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string] $Method = 'GET',
        $Body = $null,
        [switch] $All,
        [switch] $Eventual
    )
    Connect-OutpostGraph
    $uri = $Path
    if ($uri -notmatch '^https://') { $uri = $OutpostGraphRoot + $uri.TrimStart('/') }
    if (-not $uri.StartsWith($OutpostGraphRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "Refusing a Graph call outside $OutpostGraphRoot" }
    $items = New-Object -TypeName System.Collections.ArrayList
    while ($uri) {
        $headers = @{ Authorization = "Bearer $($script:OutpostM365.Token)" }
        if ($Eventual) { $headers['ConsistencyLevel'] = 'eventual' }
        $call = @{ Method = $Method; Uri = $uri; Headers = $headers; UseBasicParsing = $true; ErrorAction = 'Stop' }
        if ($null -ne $Body) { $call['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress); $call['ContentType'] = 'application/json' }
        # A bodiless POST (revokeSignInSessions, wipe) still needs a JSON content type:
        # without one Graph answers HTTP 415 (live 2026-11-19).
        elseif ($Method -eq 'POST') { $call['Body'] = '{}'; $call['ContentType'] = 'application/json' }
        $reply = $null
        for ($try = 1; $try -le 5; $try++) {
            try { $reply = Invoke-RestMethod @call; break }
            catch {
                $why = Get-OutpostM365Error -ErrorRecord $_
                if ($try -lt 5 -and $why -match '^HTTP (429|503|504) ') { Start-Sleep -Seconds (5 * $try); continue }
                throw "Graph $Method $($uri.Substring($OutpostGraphRoot.Length).Split('?')[0]) failed: $why"
            }
        }
        if (-not $All) { return $reply }
        if ($null -ne $reply -and $reply.PSObject.Properties['value']) { foreach ($item in @($reply.value)) { [void]$items.Add($item) } }
        $uri = $null
        if ($null -ne $reply -and $reply.PSObject.Properties['@odata.nextLink']) { $uri = [string]$reply.'@odata.nextLink' }
    }
    return $items.ToArray()
}

function Get-OutpostTenantDomain {
    # The tenant's initial domain (contoso.onmicrosoft.com), which Exchange Online calls the Organization.
    $org = Invoke-OutpostGraph -Path 'v1.0/organization?$select=verifiedDomains'
    foreach ($domain in @($org.value[0].verifiedDomains)) { if ($domain.isInitial) { return [string]$domain.name } }
    throw 'The tenant reports no initial (onmicrosoft.com) domain.'
}

function Connect-OutpostExchange {
    # Exchange Online PowerShell (module ExchangeOnlineManagement 3.1 or later) as the same app.
    # Needs the app's Exchange.ManageAsApp permission and an Exchange role (Microsoft's app-only guide).
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: the ExchangeOnlineManagement module is not installed on this computer (Install-Module ExchangeOnlineManagement).'
    }
    Import-Module -Name ExchangeOnlineManagement -ErrorAction Stop
    $organization = Get-OutpostTenantDomain
    if ($null -ne $script:OutpostM365.Certificate) {
        Connect-ExchangeOnline -AppId $script:OutpostM365.Client -Certificate $script:OutpostM365.Certificate -Organization $organization -ShowBanner:$false -ErrorAction Stop
    }
    else {
        $reply = Get-OutpostM365Token -Resource 'https://outlook.office365.com'
        Connect-ExchangeOnline -AccessToken ([string]$reply.access_token) -Organization $organization -ShowBanner:$false -ErrorAction Stop
    }
}

function Disconnect-OutpostExchange {
    if (Get-Command -Name Disconnect-ExchangeOnline -ErrorAction SilentlyContinue) { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue }
}
#endregion MSP Outpost Microsoft 365
# ---- Constants ------------------------------------------------------------
$UserFieldList = 'id,userPrincipalName,displayName,accountEnabled,onPremisesSyncEnabled,userType,assignedLicenses,licenseAssignmentStates'
$GroupFieldList = 'id,displayName,groupTypes,mailEnabled,securityEnabled,onPremisesSyncEnabled,isAssignableToRole'
# ---- Functions ------------------------------------------------------------
function Get-PropertyValue {
    # A property an object may not have: null instead of a strict-mode error.
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $found = $Object.PSObject.Properties[$Name]
    if ($null -eq $found) { return $null }
    return $found.Value
}
function Get-GraphUser {
    param([string] $Upn)
    $path = 'v1.0/users/' + [Uri]::EscapeDataString($Upn) + '?$select=' + $UserFieldList
    return Invoke-OutpostGraph -Path $path
}
function Get-DirectLicenseId {
    # SKU ids assigned to the user directly (assignedByGroup is null), and those inherited from a group.
    param($User)
    $assigned = @(@(Get-PropertyValue -Object $User -Name 'assignedLicenses') | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'skuId') } | Where-Object { $_ })
    $states = Get-PropertyValue -Object $User -Name 'licenseAssignmentStates'
    if ($null -eq $states) { return [pscustomobject]@{ Direct = $assigned; Inherited = @() } }
    $direct = New-Object -TypeName System.Collections.ArrayList
    $inherited = New-Object -TypeName System.Collections.ArrayList
    foreach ($state in @($states)) {
        $sku = [string](Get-PropertyValue -Object $state -Name 'skuId')
        if (-not $sku) { continue }
        if ([string](Get-PropertyValue -Object $state -Name 'assignedByGroup')) { if ($inherited -notcontains $sku) { [void]$inherited.Add($sku) } }
        elseif ($direct -notcontains $sku) { [void]$direct.Add($sku) }
    }
    return [pscustomobject]@{ Direct = @($direct); Inherited = @($inherited) }
}
function Get-GroupVerdict {
    # Whether Graph can remove a member from this group, and why not.
    param($Group)
    $types = @(Get-PropertyValue -Object $Group -Name 'groupTypes')
    $unified = $types -contains 'Unified'
    $mailEnabled = [bool](Get-PropertyValue -Object $Group -Name 'mailEnabled')
    $reason = ''
    if ($types -contains 'DynamicMembership') { $reason = 'dynamic membership (change the rule instead)' }
    elseif ([bool](Get-PropertyValue -Object $Group -Name 'onPremisesSyncEnabled')) { $reason = 'synced from on-premises Active Directory' }
    elseif ([bool](Get-PropertyValue -Object $Group -Name 'isAssignableToRole')) { $reason = 'role-assignable group (needs RoleManagement.ReadWrite.Directory)' }
    elseif ($mailEnabled -and -not $unified) { $reason = 'mail-enabled security or distribution group (remove in Exchange)' }
    return [pscustomobject]@{ Removable = ($reason -eq ''); Reason = $reason }
}
function Get-MailboxState {
    param([string] $Upn)
    $mailbox = $null
    try { $mailbox = Get-Mailbox -Identity $Upn -ErrorAction Stop }
    catch { return $null }
    $reply = $null
    try { $reply = Get-MailboxAutoReplyConfiguration -Identity $Upn -ErrorAction Stop } catch { $reply = $null }
    return [pscustomobject]@{
        RecipientTypeDetails = [string](Get-PropertyValue -Object $mailbox -Name 'RecipientTypeDetails')
        ForwardingAddress = [string](Get-PropertyValue -Object $mailbox -Name 'ForwardingAddress')
        ForwardingSmtpAddress = [string](Get-PropertyValue -Object $mailbox -Name 'ForwardingSmtpAddress')
        DeliverToMailboxAndForward = [bool](Get-PropertyValue -Object $mailbox -Name 'DeliverToMailboxAndForward')
        HiddenFromAddressListsEnabled = [bool](Get-PropertyValue -Object $mailbox -Name 'HiddenFromAddressListsEnabled')
        AutoReplyState = [string](Get-PropertyValue -Object $reply -Name 'AutoReplyState')
        InternalMessage = [string](Get-PropertyValue -Object $reply -Name 'InternalMessage')
        ExternalMessage = [string](Get-PropertyValue -Object $reply -Name 'ExternalMessage')
        ExternalAudience = [string](Get-PropertyValue -Object $reply -Name 'ExternalAudience')
    }
}
function Add-SkippedRow {
    param([string] $Item, [string] $Change, [string] $Why)
    Add-OutpostRow -Values @{ Item = $Item; Change = $Change; Result = "Skipped: $Why" }
}
# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate
    Read-OutpostM365Inputs
    $Config = [pscustomobject]@{
        UserPrincipalName    = Read-OutpostText -Name 'UserPrincipalName' -Required
        BlockSignIn          = Read-OutpostBool -Name 'BlockSignIn'
        RevokeSessions       = Read-OutpostBool -Name 'RevokeSessions'
        RemoveFromGroups     = Read-OutpostBool -Name 'RemoveFromGroups'
        ConvertToShared      = Read-OutpostBool -Name 'ConvertToShared'
        AutoReplyText        = Read-OutpostText -Name 'AutoReplyText'
        ManagerUpn           = Read-OutpostText -Name 'ManagerUpn'
        ManagerMailboxAccess = Read-OutpostChoice -Name 'ManagerMailboxAccess' -Allowed @('FullAccess', 'Forward', 'Both', 'None')
        HideFromAddressLists = Read-OutpostBool -Name 'HideFromAddressLists'
        RemoveLicenses       = Read-OutpostBool -Name 'RemoveLicenses'
    }
    $addressPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    if ($Config.UserPrincipalName -notmatch $addressPattern) {
        Stop-OutpostInput -Name 'UserPrincipalName' -Value $Config.UserPrincipalName -Expected 'a user principal name such as jane@contoso.com'
    }
    if ($Config.ManagerUpn -ne '' -and $Config.ManagerUpn -notmatch $addressPattern) {
        Stop-OutpostInput -Name 'ManagerUpn' -Value $Config.ManagerUpn -Expected 'a user principal name such as boss@contoso.com, or empty'
    }
    if ($Config.ManagerUpn -ieq $Config.UserPrincipalName) {
        Stop-OutpostRun -Message 'ManagerUpn is the same account as UserPrincipalName. Name a different person, or leave ManagerUpn empty.'
    }
    $managerWanted = ($Config.ManagerUpn -ne '') -and ($Config.ManagerMailboxAccess -ne 'None')
    $replyWanted = $Config.AutoReplyText -ne ''
    $needExchange = $Config.ConvertToShared -or $replyWanted -or $managerWanted -or $Config.HideFromAddressLists
    if (-not ($Config.BlockSignIn -or $Config.RevokeSessions -or $Config.RemoveFromGroups -or $Config.RemoveLicenses -or $needExchange)) {
        Stop-OutpostRun -Message 'Every step is switched off, so there is nothing to do. Turn at least one step on, or set AutoReplyText or ManagerUpn.'
    }
    $upn = $Config.UserPrincipalName

    # Detect (read-only)
    Write-OutpostLine -Text "Offboarding $upn in tenant $($script:OutpostM365.Tenant) as app $($script:OutpostM365.Client)."
    $user = $null
    try { $user = Get-GraphUser -Upn $upn }
    catch { Stop-OutpostRun -Message "Could not read the user $upn ($($_.Exception.Message)). Check the spelling and the app's User.Read.All permission." }
    $userId = [string](Get-PropertyValue -Object $user -Name 'id')
    $isEnabled = [bool](Get-PropertyValue -Object $user -Name 'accountEnabled')
    $isSynced = [bool](Get-PropertyValue -Object $user -Name 'onPremisesSyncEnabled')
    if ($isSynced) { Write-OutpostWarning -Text "$upn is synced from on-premises Active Directory: blocking sign-in and hiding from address lists must be done in Active Directory and are skipped here." }
    if ($Config.ManagerUpn -ne '') {
        try { $null = Get-GraphUser -Upn $Config.ManagerUpn }
        catch { Stop-OutpostRun -Message "Could not read the manager $($Config.ManagerUpn) ($($_.Exception.Message)). Correct ManagerUpn or leave it empty." }
    }

    $skuNames = @{}
    try {
        foreach ($sku in @(Invoke-OutpostGraph -Path 'v1.0/subscribedSkus?$select=skuId,skuPartNumber' -All)) { $skuNames[[string]$sku.skuId] = [string]$sku.skuPartNumber }
    }
    catch { Write-OutpostWarning -Text "Could not read the subscribed SKUs ($($_.Exception.Message)); licences are shown by id." }
    $licences = Get-DirectLicenseId -User $user

    $removableGroups = New-Object -TypeName System.Collections.ArrayList
    $skippedGroups = New-Object -TypeName System.Collections.ArrayList
    $allGroups = @()
    if ($Config.RemoveFromGroups -or $Config.RemoveLicenses) {
        $groupPath = 'v1.0/users/' + [Uri]::EscapeDataString($userId) + '/memberOf/microsoft.graph.group?$count=true&$select=' + $GroupFieldList
        $allGroups = @(Invoke-OutpostGraph -Path $groupPath -All -Eventual)
        foreach ($group in $allGroups) {
            $verdict = Get-GroupVerdict -Group $group
            if ($verdict.Removable) { [void]$removableGroups.Add($group) }
            else { [void]$skippedGroups.Add([pscustomobject]@{ Name = [string](Get-PropertyValue -Object $group -Name 'displayName'); Reason = $verdict.Reason }) }
        }
    }

    $mailbox = $null
    if ($needExchange) {
        Connect-OutpostExchange
        $mailbox = Get-MailboxState -Upn $upn
        if ($null -eq $mailbox) { Write-OutpostWarning -Text "$upn has no Exchange Online mailbox: the mailbox steps are skipped." }
    }

    # Before-state: written first, named in the output.
    $beforeFile = ''
    $groupState = @($allGroups | ForEach-Object { [ordered]@{ id = [string](Get-PropertyValue -Object $_ -Name 'id'); displayName = [string](Get-PropertyValue -Object $_ -Name 'displayName'); groupTypes = @(Get-PropertyValue -Object $_ -Name 'groupTypes'); mailEnabled = [bool](Get-PropertyValue -Object $_ -Name 'mailEnabled'); securityEnabled = [bool](Get-PropertyValue -Object $_ -Name 'securityEnabled') } })
    $licenceState = @(@($licences.Direct) + @($licences.Inherited) | ForEach-Object { [ordered]@{ skuId = $_; skuPartNumber = [string]$skuNames[$_]; assignedByGroup = ($licences.Inherited -contains $_ -and $licences.Direct -notcontains $_) } })
    $beforeState = [ordered]@{
        script          = $OutpostScript.Slug
        capturedUtc     = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        tenant          = $script:OutpostM365.Tenant
        userId          = $userId
        userPrincipalName = $upn
        accountEnabled  = $isEnabled
        onPremisesSyncEnabled = $isSynced
        groups          = $groupState
        licences        = $licenceState
        mailbox         = $mailbox
    }
    if (-not $script:OutpostRun.DryRun) {
        $folder = Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Offboarding'
        $null = New-Item -Path $folder -ItemType Directory -Force
        $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss', [Globalization.CultureInfo]::InvariantCulture)
        $beforeFile = Join-Path -Path $folder -ChildPath (($upn -replace '[^A-Za-z0-9.@_-]', '_') + '-' + $stamp + '.json')
        ConvertTo-Json -InputObject $beforeState -Depth 6 | Set-Content -LiteralPath $beforeFile -Encoding UTF8
        Write-OutpostLine -Text "Before-state saved to $beforeFile"
    }
    else { Write-OutpostLine -Text 'DRY RUN: a real run first saves the before-state JSON (groups, licences, mailbox settings) under the MSP Outpost data folder.' }

    # Plan
    $needBlock = $Config.BlockSignIn -and $isEnabled -and -not $isSynced
    $needSharedConvert = $false
    $needReply = $false
    $needForward = $false
    $needAccess = $false
    $needHide = $false
    if ($null -ne $mailbox) {
        $needSharedConvert = $Config.ConvertToShared -and ($mailbox.RecipientTypeDetails -ne 'SharedMailbox')
        $needReply = $replyWanted
        $needForward = $managerWanted -and (@('Forward', 'Both') -contains $Config.ManagerMailboxAccess)
        $needAccess = $managerWanted -and (@('FullAccess', 'Both') -contains $Config.ManagerMailboxAccess)
        $needHide = $Config.HideFromAddressLists -and -not $mailbox.HiddenFromAddressListsEnabled -and -not $isSynced
    }
    $licencesToRemove = @()
    if ($Config.RemoveLicenses) { $licencesToRemove = @($licences.Direct) }
    $groupsToRemove = @()
    if ($Config.RemoveFromGroups) { $groupsToRemove = @($removableGroups) }
    $planned = 0
    if ($needBlock) { $planned++ }
    if ($Config.RevokeSessions) { $planned++ }
    $planned += $groupsToRemove.Count
    foreach ($flag in @($needSharedConvert, $needReply, $needForward, $needAccess, $needHide)) { if ($flag) { $planned++ } }
    if ($licencesToRemove.Count -gt 0) { $planned++ }
    if ($planned -eq 0) {
        Disconnect-OutpostExchange
        Complete-OutpostRun -Status 'OK' -Answer "Already offboarded: nothing left to change for $upn."
    }
    Assert-OutpostChangeLimit -Planned $planned

    # Act, in order. A failed step stops the run (Invoke-OutpostChange throws) before the licences are touched.
    $done = New-Object -TypeName System.Collections.ArrayList
    if ($Config.BlockSignIn -and $isSynced) { Add-SkippedRow -Item $upn -Change 'Block sign-in' -Why 'synced from on-premises Active Directory' }
    if ($needBlock) {
        $null = Invoke-OutpostChange -Item $upn -Change 'Block sign-in' -Action {
            $null = Invoke-OutpostGraph -Path ('v1.0/users/' + $userId) -Method PATCH -Body @{ accountEnabled = $false }
        }
        [void]$done.Add('sign-in blocked')
    }
    if ($Config.RevokeSessions) {
        $null = Invoke-OutpostChange -Item $upn -Change 'Revoke sign-in sessions' -Action {
            $null = Invoke-OutpostGraph -Path ('v1.0/users/' + $userId + '/revokeSignInSessions') -Method POST
        }
        [void]$done.Add('sessions revoked')
    }
    if ($Config.RemoveFromGroups) {
        foreach ($skipped in $skippedGroups) { Add-SkippedRow -Item $skipped.Name -Change 'Remove from group' -Why $skipped.Reason }
        foreach ($group in $groupsToRemove) {
            $groupId = [string](Get-PropertyValue -Object $group -Name 'id')
            $groupName = [string](Get-PropertyValue -Object $group -Name 'displayName')
            $null = Invoke-OutpostChange -Item $groupName -Change "Remove $upn from group" -Action {
                $null = Invoke-OutpostGraph -Path ('v1.0/groups/' + $groupId + '/members/' + $userId + '/$ref') -Method DELETE
            }
        }
        if ($groupsToRemove.Count -gt 0) { [void]$done.Add("$($groupsToRemove.Count) group(s)") }
    }
    if ($needSharedConvert) {
        $null = Invoke-OutpostChange -Item $upn -Change 'Convert mailbox to shared' -Action { Set-Mailbox -Identity $upn -Type Shared -ErrorAction Stop }
        [void]$done.Add('mailbox shared')
    }
    if ($needReply) {
        $null = Invoke-OutpostChange -Item $upn -Change 'Set automatic reply' -Action {
            Set-MailboxAutoReplyConfiguration -Identity $upn -AutoReplyState Enabled -InternalMessage $Config.AutoReplyText -ExternalMessage $Config.AutoReplyText -ExternalAudience All -ErrorAction Stop
        }
        [void]$done.Add('auto-reply set')
    }
    if ($needForward) {
        $null = Invoke-OutpostChange -Item $upn -Change "Forward mail to $($Config.ManagerUpn) and keep a copy" -Action {
            Set-Mailbox -Identity $upn -ForwardingAddress $Config.ManagerUpn -DeliverToMailboxAndForward $true -ErrorAction Stop
        }
        [void]$done.Add('mail forwarded')
    }
    if ($needAccess) {
        $null = Invoke-OutpostChange -Item $upn -Change "Grant $($Config.ManagerUpn) Full Access to the mailbox" -Action {
            Add-MailboxPermission -Identity $upn -User $Config.ManagerUpn -AccessRights FullAccess -InheritanceType All -ErrorAction Stop
        }
        [void]$done.Add('manager access')
    }
    if ($Config.HideFromAddressLists -and $isSynced) { Add-SkippedRow -Item $upn -Change 'Hide from address lists' -Why 'synced from on-premises Active Directory' }
    if ($needHide) {
        $null = Invoke-OutpostChange -Item $upn -Change 'Hide mailbox from address lists' -Action { Set-Mailbox -Identity $upn -HiddenFromAddressListsEnabled $true -ErrorAction Stop }
        [void]$done.Add('hidden from lists')
    }
    if ($licencesToRemove.Count -gt 0) {
        $names = @($licencesToRemove | ForEach-Object { if ($skuNames.ContainsKey($_)) { $skuNames[$_] } else { $_ } }) -join ', '
        $null = Invoke-OutpostChange -Item $upn -Change "Remove licences: $names" -Action {
            $null = Invoke-OutpostGraph -Path ('v1.0/users/' + $userId + '/assignLicense') -Method POST -Body @{ addLicenses = @(); removeLicenses = @($licencesToRemove) }
        }
        [void]$done.Add("$($licencesToRemove.Count) licence(s)")
    }
    if ($Config.RemoveLicenses -and @($licences.Inherited).Count -gt 0) {
        Write-OutpostWarning -Text "$(@($licences.Inherited).Count) licence(s) are assigned through a group and stay until the user leaves that group (or the group is changed)."
    }

    # Verify (skipped in a dry run: nothing was changed)
    if (-not $script:OutpostRun.DryRun) {
        # Entra shows a block or a licence removal a few seconds late (live 2026-11-19), so
        # read up to 6 times before calling it a failure.
        for ($read = 1; $read -le 6; $read++) {
            $after = Get-GraphUser -Upn $upn
            $stillOn = $needBlock -and [bool](Get-PropertyValue -Object $after -Name 'accountEnabled')
            $stillLicensed = ($licencesToRemove.Count -gt 0) -and (@((Get-DirectLicenseId -User $after).Direct | Where-Object { $licencesToRemove -contains $_ }).Count -gt 0)
            if (-not $stillOn -and -not $stillLicensed) { break }
            Start-Sleep -Seconds 5
        }
        if ($needBlock -and [bool](Get-PropertyValue -Object $after -Name 'accountEnabled')) {
            Stop-OutpostRun -Message "$upn is still enabled after the block. Check the app's User.EnableDisableAccount.All permission and the role it needs for administrators."
        }
        if ($licencesToRemove.Count -gt 0) {
            $left = @((Get-DirectLicenseId -User $after).Direct | Where-Object { $licencesToRemove -contains $_ })
            if ($left.Count -gt 0) { Stop-OutpostRun -Message "$($left.Count) licence(s) are still assigned to $upn after removal. Check LicenseAssignment.ReadWrite.All and the licence error in the Entra portal." }
        }
        if ($needSharedConvert) {
            $afterMailbox = Get-MailboxState -Upn $upn
            if ($null -eq $afterMailbox -or $afterMailbox.RecipientTypeDetails -ne 'SharedMailbox') { Stop-OutpostRun -Message "The mailbox of $upn is not shared after the conversion. Check it in the Exchange admin center." }
        }
    }
    Disconnect-OutpostExchange

    # Finish
    $summary = @($done) -join ', '
    Complete-OutpostRun -Status 'CHANGED' -Answer "Offboarded ${upn}: $summary"
}
catch {
    Disconnect-OutpostExchange
    Stop-OutpostRun -ErrorRecord $_
}
