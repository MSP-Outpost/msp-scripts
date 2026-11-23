#Requires -Version 5.1
<#
.SYNOPSIS
    Creates Microsoft 365 (Entra ID) users from a CSV file, with an optional licence and groups, and puts each new user's first password in a secure RMM field.
.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It reads the CSV in CsvPath and, for every row whose user principal name does not exist yet, it:
      1. CREATES the cloud user (accountEnabled true, a random initial password, change required at the first sign-in);
      2. when LicenseSku is set: assigns that licence (the row needs a usage location: its UsageLocation column or DefaultUsageLocation);
      3. when AddToGroups is set: adds the user to each of those security or Microsoft 365 groups.
    Users that already exist are SKIPPED and not touched at all (not even their licence or groups), which is what makes a second run safe: it says "Already created". If a run stops half way through a user, finish that user by hand; running it again will skip them.
    It never deletes or changes an existing user, never touches a user outside the CSV, never sets a manager, and never prints, logs, exports or returns a password.

    CSV: a header row and one user per row. Columns (header names, any order): UserPrincipalName (required), DisplayName (or both GivenName and Surname), GivenName, Surname, JobTitle, Department, UsageLocation (two-letter country code such as US). Save it as UTF-8. At most 200 rows. The whole file is checked before anything is created: a bad row, a duplicate name, a domain the tenant has not verified, an unknown or exhausted licence or a group that cannot be changed stops the run with nothing created.

    PASSWORDS. Each password is made here (24 characters, random, from the cryptographic generator) and written ONCE, before the users are created, to the secure RMM custom field named in ResultField, as one value: "user@contoso.com=Password user2@contoso.com=Password2". Split on spaces, then at the first "=". ResultField must be a secure (secret) field of NinjaOne, Datto RMM (UDF number) or Syncro; the run refuses to create anyone without one, and OutputFormat Answer is refused. A field holds about 240 characters (Datto RMM keeps 255), so one run creates a BATCH of users that fits (about 4 to 5 users): the rest are listed as "Deferred". Copy the passwords out of the field, then run again for the next batch; a second run overwrites the field. When ResultField is set the answer is never written to it, even on a run that creates nobody, so a second run cannot wipe passwords you have not copied.
    HIGH RISK: it is a dry run (it lists what it would create) until DryRun=false AND Approve=new-m365-users-from-csv are both set. Every create, licence and group add counts as one change toward MaxChanges (default 25): raise MaxChanges for a longer file.

    Microsoft Graph application permissions (admin consent): User.Create (create users), LicenseAssignment.ReadWrite.All (assign the licence), GroupMember.ReadWrite.All (add to groups), and Directory.Read.All (read users, groups, the tenant's verified domains and its licence subscriptions).

    Where each fact comes from (read in Microsoft's reference): POST v1.0/users needs accountEnabled, displayName, mailNickname, passwordProfile and userPrincipalName, returns 201, and the UPN domain must be a verified domain of the tenant (User.Create is the least privileged application permission); usageLocation is required for a user who is assigned a licence; POST v1.0/users/{id}/assignLicense with addLicenses (skuId, disabledPlans) and the required removeLicenses (LicenseAssignment.ReadWrite.All); POST v1.0/groups/{id}/members/$ref (GroupMember.ReadWrite.All; only security and Microsoft 365 groups; 400 for a group or user not yet replicated); GET v1.0/subscribedSkus with prepaidUnits and consumedUnits; GET v1.0/organization verifiedDomains.
    Not confirmed in the documentation, so read defensively: how long a new user takes to be usable for a licence or group add (the script retries an add that answers 400 or 404 up to 6 times, 5 seconds apart); that User.Create alone can create a user whose UPN is free but whose mailNickname or proxy address clashes with another object (the create is then refused and the run stops); that Directory.Read.All is enough to read verifiedDomains and subscribedSkus (Microsoft lists Organization.Read.All and LicenseAssignment.Read.All as the least privileged permissions for those two pages, so grant them if a read is refused); the password complexity rule for a tenant with a custom policy (the generated password has upper and lower case letters, digits and symbols).
.PARAMETER TenantId
    The client tenant: its ID (a GUID) or a domain such as contoso.onmicrosoft.com. Required.
    Environment variable: TenantId
.PARAMETER ClientId
    The app registration's Application (client) ID, a GUID. Required.
    Environment variable: ClientId
.PARAMETER CertificateThumbprint
    Thumbprint (40 hex characters) of the app's certificate with its private key in LocalMachine\My or CurrentUser\My on this computer. Preferred. When empty, the secret is read from the environment variable ClientSecret (a secure RMM field).
    Environment variable: CertificateThumbprint
.PARAMETER CsvPath
    Full path of the CSV file on this computer. Required.
    Environment variable: CsvPath
.PARAMETER DefaultUsageLocation
    Two-letter country code used for rows with no UsageLocation, such as CA. Default empty.
    Environment variable: DefaultUsageLocation
.PARAMETER LicenseSku
    The licence to assign to every new user: the SKU part number (such as O365_BUSINESS_PREMIUM) or the SKU ID (a GUID). Default empty: no licence.
    Environment variable: LicenseSku
.PARAMETER AddToGroups
    Groups every new user joins: display names or group IDs, separated by comma or semicolon. Security or Microsoft 365 groups only. Default empty.
    Environment variable: AddToGroups
.PARAMETER DryRun
    true (the default for this High-risk script) lists every change and makes none. The script changes things only with DryRun=false and Approve=new-m365-users-from-csv.
    Environment variable: DryRun
.PARAMETER OutputFormat
    Text (default), Json or Csv. Not Answer. Environment variable: OutputFormat
.PARAMETER ExportPath
    Also write the rows (never a password) to this .csv or .json file. Environment variable: ExportPath
.PARAMETER ResultField
    The SECURE RMM custom field that receives the initial passwords. Required for a real run that creates users.
    Environment variable: ResultField
.EXAMPLE
    .\new-m365-users-from-csv.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -CsvPath C:\Temp\newusers.csv -DefaultUsageLocation CA -LicenseSku O365_BUSINESS_PREMIUM
    Dry run: lists the users it would create and license; changes nothing.
.EXAMPLE
    .\new-m365-users-from-csv.ps1 -TenantId contoso.onmicrosoft.com -ClientId 11111111-2222-3333-4444-555555555555 -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567 -CsvPath C:\Temp\newusers.csv -DefaultUsageLocation CA -AddToGroups "All Staff" -ResultField NewUserPasswords -DryRun false -Approve new-m365-users-from-csv
    Creates the missing users, adds them to All Staff and writes their passwords to the secure field NewUserPasswords.
.NOTES
    Name:        Create Microsoft 365 users from a CSV file
    Slug:        new-m365-users-from-csv
    Version:     1.0.1
    Updated:     2026-11-23
    Type:        Action
    Category:    06 Identity: AD / Entra / M365 users
    Platforms:   Windows 10, 11, Server 2016+, with the app certificate
    RunAs:       Either
    Requires:    PowerShell 5.1; Graph: User.Create, LicenseAssignment.ReadWrite.All, GroupMember.ReadWrite.All; a secure RMM field
    Changes:     Creates Entra ID users; assigns a licence; adds the users to groups; writes the initial passwords to a secure RMM field
    Risk:        High
    Reboot:      Never
    Runtime:     Under 3 minutes
    Answer:      "Created 4 user(s) (4 licensed, 8 group memberships); passwords are in the secure field; 2 already existed"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/new-m365-users-from-csv
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.1  2026-11-23  Wording only: the 1.0.0 changelog line is corrected (that version was tested before listing). No code change.
      1.0.0  2026-11-19  First version.
#>
[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text. Defaults are the
    # place to edit when your RMM cannot pass arguments or variables.
    [string] $TenantId = '',
    [string] $ClientId = '',
    [string] $CertificateThumbprint = '',
    [string] $CsvPath = '',
    [string] $DefaultUsageLocation = '',
    [string] $LicenseSku = '',
    [string] $AddToGroups = '',
    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)
# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'new-m365-users-from-csv'
    Version = '1.0.1'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('TenantId', 'ClientId', 'CertificateThumbprint', 'CsvPath', 'DefaultUsageLocation', 'LicenseSku', 'AddToGroups')
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
$GroupFieldList = 'id,displayName,groupTypes,mailEnabled,securityEnabled,onPremisesSyncEnabled,isAssignableToRole'
$SkuFieldList = 'skuId,skuPartNumber,appliesTo,capabilityStatus,prepaidUnits,consumedUnits'
$UpnPattern = '^[A-Za-z0-9''._!#^~-]+@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$'
$GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
$PasswordLength = 24
$MaxRows = 200
$SecretFieldCapacity = 240
$RetryTries = 6
$RetrySeconds = 5
$MaxProblemsShown = 6
# ---- Functions ------------------------------------------------------------
function Get-PropertyValue {
    # A property an object may not have: null instead of a strict-mode error.
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $found = $Object.PSObject.Properties[$Name]
    if ($null -eq $found) { return $null }
    return $found.Value
}
function Get-RandomIndex {
    # An unbiased random number from 0 to Count - 1 (rejection sampling on one random byte).
    param([Parameter(Mandatory = $true)] $Generator, [Parameter(Mandatory = $true)][int] $Count)
    $limit = 256 - (256 % $Count)
    $buffer = New-Object -TypeName byte[] -ArgumentList 1
    do { $Generator.GetBytes($buffer) } while ($buffer[0] -ge $limit)
    return ([int]$buffer[0] % $Count)
}
function New-RandomPassword {
    # PasswordLength characters from the cryptographic generator, at least one of each class,
    # no look-alike letters and none of the characters RMMs refuse (& | ; $ > < ` !).
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '-_=+.@#%*')
    $all = -join $sets
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
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
function Read-CsvText {
    # One cell as trimmed text; '' when the column or the value is missing.
    param($Row, [string] $Column)
    return ([string](Get-PropertyValue -Object $Row -Name $Column)).Trim()
}
function Find-GraphUserId {
    # The id of the user with this UPN, or '' when there is none.
    param([string] $Upn)
    $path = 'v1.0/users?$filter=' + [Uri]::EscapeDataString("userPrincipalName eq '" + $Upn.Replace("'", "''") + "'") + '&$select=id,userPrincipalName'
    $found = @(Invoke-OutpostGraph -Path $path -All)
    if ($found.Count -eq 0) { return '' }
    return [string](Get-PropertyValue -Object $found[0] -Name 'id')
}
function Get-GroupVerdict {
    # Whether Graph can add a member to this group, and why not.
    param($Group)
    $types = @(Get-PropertyValue -Object $Group -Name 'groupTypes')
    $unified = $types -contains 'Unified'
    $mailEnabled = [bool](Get-PropertyValue -Object $Group -Name 'mailEnabled')
    $reason = ''
    if ($types -contains 'DynamicMembership') { $reason = 'dynamic membership (membership follows a rule)' }
    elseif ([bool](Get-PropertyValue -Object $Group -Name 'onPremisesSyncEnabled')) { $reason = 'synced from on-premises Active Directory' }
    elseif ([bool](Get-PropertyValue -Object $Group -Name 'isAssignableToRole')) { $reason = 'role-assignable group (grants an Entra administrator role)' }
    elseif ($mailEnabled -and -not $unified) { $reason = 'mail-enabled security or distribution group (managed in Exchange)' }
    return [pscustomobject]@{ Addable = ($reason -eq ''); Reason = $reason }
}
function Resolve-TargetGroup {
    # One group by name or id, checked to be one Graph can add members to. Stops the run otherwise.
    param([string] $Text)
    $groupId = $Text
    if ($Text -notmatch $GuidPattern) {
        $path = 'v1.0/groups?$filter=' + [Uri]::EscapeDataString("displayName eq '" + $Text.Replace("'", "''") + "'") + '&$select=id,displayName'
        $candidates = @(Invoke-OutpostGraph -Path $path -All)
        if ($candidates.Count -ne 1) { Stop-OutpostRun -Message "AddToGroups: '$Text' matches $($candidates.Count) groups. Use the group's ID, or an exact unique name. Nothing was created." }
        $groupId = [string](Get-PropertyValue -Object $candidates[0] -Name 'id')
    }
    $group = $null
    try { $group = Invoke-OutpostGraph -Path ('v1.0/groups/' + $groupId + '?$select=' + $GroupFieldList) }
    catch { Stop-OutpostRun -Message "AddToGroups: could not read the group '$Text' ($($_.Exception.Message)). Nothing was created." }
    $verdict = Get-GroupVerdict -Group $group
    if (-not $verdict.Addable) { Stop-OutpostRun -Message "AddToGroups: '$Text' cannot be changed by this script: $($verdict.Reason). Remove it from AddToGroups. Nothing was created." }
    return [pscustomobject]@{ Id = $groupId; Name = [string](Get-PropertyValue -Object $group -Name 'displayName') }
}
function Invoke-GraphWithRetry {
    # A new user or group takes a few seconds to be usable everywhere: a 400 or 404 is retried.
    param([Parameter(Mandatory = $true)][scriptblock] $Call)
    for ($try = 1; $try -le $RetryTries; $try++) {
        try { return (& $Call) }
        catch {
            if ($try -lt $RetryTries -and $_.Exception.Message -match 'HTTP (400|404) ') { Start-Sleep -Seconds $RetrySeconds; continue }
            throw
        }
    }
}
function Test-UserCreated {
    # True when the user exists with the licence and every group.
    param([string] $UserId, [string] $Upn, [string] $SkuId, $Groups)
    if ((Find-GraphUserId -Upn $Upn) -eq '') { return $false }
    if ($SkuId -ne '') {
        $user = Invoke-OutpostGraph -Path ('v1.0/users/' + $UserId + '?$select=id,assignedLicenses')
        $held = @(@(Get-PropertyValue -Object $user -Name 'assignedLicenses') | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'skuId') })
        if ($held -notcontains $SkuId) { return $false }
    }
    if (@($Groups).Count -gt 0) {
        $memberOf = @(Invoke-OutpostGraph -Path ('v1.0/users/' + $UserId + '/memberOf/microsoft.graph.group?$count=true&$select=id') -All -Eventual)
        $heldGroups = @($memberOf | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'id') })
        foreach ($group in @($Groups)) { if ($heldGroups -notcontains $group.Id) { return $false } }
    }
    return $true
}
# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: the whole file and the tenant are checked before anything is created.
    Read-OutpostM365Inputs
    $Config = [pscustomobject]@{
        CsvPath              = Read-OutpostText -Name 'CsvPath' -Required
        DefaultUsageLocation = (Read-OutpostText -Name 'DefaultUsageLocation').ToUpperInvariant()
        LicenseSku           = Read-OutpostText -Name 'LicenseSku'
        AddToGroups          = @(Read-OutpostList -Name 'AddToGroups')
    }
    if ($Config.DefaultUsageLocation -ne '' -and $Config.DefaultUsageLocation -notmatch '^[A-Z]{2}$') {
        Stop-OutpostInput -Name 'DefaultUsageLocation' -Value $Config.DefaultUsageLocation -Expected 'a two-letter country code such as CA, or empty'
    }
    if (-not (Test-Path -LiteralPath $Config.CsvPath -PathType Leaf)) {
        Stop-OutpostRun -Message "The CSV file '$($Config.CsvPath)' was not found on this computer. Correct CsvPath and run again."
    }
    $csvRows = @(Import-Csv -LiteralPath $Config.CsvPath -Encoding UTF8)
    if ($csvRows.Count -eq 0) { Stop-OutpostRun -Message "The CSV file '$($Config.CsvPath)' has no rows. It needs a header row and one user per row." }
    if ($csvRows.Count -gt $MaxRows) { Stop-OutpostRun -Message "The CSV has $($csvRows.Count) rows; the most one run takes is $MaxRows. Split the file." }
    if ($null -eq $csvRows[0].PSObject.Properties['UserPrincipalName']) {
        Stop-OutpostRun -Message 'The CSV has no UserPrincipalName column. The first line must be a header with the column names (UserPrincipalName, DisplayName, ...).'
    }
    $users = New-Object -TypeName System.Collections.ArrayList
    $problems = New-Object -TypeName System.Collections.ArrayList
    $seen = @{}
    $line = 1
    foreach ($row in $csvRows) {
        $line++
        $upn = Read-CsvText -Row $row -Column 'UserPrincipalName'
        if ($upn -notmatch $UpnPattern) { [void]$problems.Add("line ${line}: '$upn' is not a user principal name such as new.user@contoso.com"); continue }
        if ($seen.ContainsKey($upn.ToLowerInvariant())) { [void]$problems.Add("line ${line}: $upn appears twice"); continue }
        $seen[$upn.ToLowerInvariant()] = $true
        $given = Read-CsvText -Row $row -Column 'GivenName'
        $surname = Read-CsvText -Row $row -Column 'Surname'
        $display = Read-CsvText -Row $row -Column 'DisplayName'
        if ($display -eq '' -and $given -ne '' -and $surname -ne '') { $display = "$given $surname" }
        if ($display -eq '') { [void]$problems.Add("line ${line}: $upn has no DisplayName (or GivenName and Surname)"); continue }
        $location = (Read-CsvText -Row $row -Column 'UsageLocation').ToUpperInvariant()
        if ($location -eq '') { $location = $Config.DefaultUsageLocation }
        if ($location -ne '' -and $location -notmatch '^[A-Z]{2}$') { [void]$problems.Add("line ${line}: $upn has the usage location '$location'; use a two-letter country code"); continue }
        if ($Config.LicenseSku -ne '' -and $location -eq '') { [void]$problems.Add("line ${line}: $upn has no UsageLocation and DefaultUsageLocation is empty; a licence needs one"); continue }
        $nickname = (($upn.Split('@')[0]) -replace '[^A-Za-z0-9._-]', '')
        if ($nickname.Length -gt 64) { $nickname = $nickname.Substring(0, 64) }
        if ($nickname -eq '') { [void]$problems.Add("line ${line}: $upn has no usable mail alias"); continue }
        [void]$users.Add([pscustomobject]@{
            Upn = $upn; DisplayName = $display; GivenName = $given; Surname = $surname; Nickname = $nickname; UsageLocation = $location
            JobTitle = (Read-CsvText -Row $row -Column 'JobTitle'); Department = (Read-CsvText -Row $row -Column 'Department')
        })
    }
    if ($problems.Count -gt 0) {
        $shown = @($problems | Select-Object -First $MaxProblemsShown) -join '; '
        $more = ''
        if ($problems.Count -gt $MaxProblemsShown) { $more = " (and $($problems.Count - $MaxProblemsShown) more)" }
        Stop-OutpostRun -Message "The CSV has $($problems.Count) problem(s): $shown$more. Nothing was created; fix the file and run again."
    }

    # Detect (read-only)
    Write-OutpostLine -Text "Checking $($users.Count) user(s) from $($Config.CsvPath) against tenant $($script:OutpostM365.Tenant)."
    $verifiedDomains = @{}
    $organization = Invoke-OutpostGraph -Path 'v1.0/organization?$select=verifiedDomains'
    foreach ($org in @(Get-PropertyValue -Object $organization -Name 'value')) {
        foreach ($domain in @(Get-PropertyValue -Object $org -Name 'verifiedDomains')) { $verifiedDomains[([string](Get-PropertyValue -Object $domain -Name 'name')).ToLowerInvariant()] = $true }
    }
    if ($verifiedDomains.Count -eq 0) { Stop-OutpostRun -Message 'Could not read the tenant''s verified domains. Grant the app Directory.Read.All (or Organization.Read.All) and run again.' }
    $badDomains = @($users | Where-Object { -not $verifiedDomains.ContainsKey($_.Upn.Split('@')[1].ToLowerInvariant()) } | ForEach-Object { $_.Upn })
    if ($badDomains.Count -gt 0) {
        Stop-OutpostRun -Message ("The domain of $($badDomains.Count) user(s) is not a verified domain of the tenant: " + (@($badDomains | Select-Object -First $MaxProblemsShown) -join ', ') + '. Add and verify the domain in Microsoft 365, or correct the file. Nothing was created.')
    }

    $existing = New-Object -TypeName System.Collections.ArrayList
    $toCreate = New-Object -TypeName System.Collections.ArrayList
    foreach ($user in $users) {
        if ((Find-GraphUserId -Upn $user.Upn) -ne '') { [void]$existing.Add($user) } else { [void]$toCreate.Add($user) }
    }
    foreach ($user in $existing) { Add-OutpostRow -Values @{ Item = $user.Upn; Change = 'Create user'; Result = 'Skipped: already exists' } }

    $skuId = ''
    $skuName = ''
    $freeUnits = $null
    if ($Config.LicenseSku -ne '' -and $toCreate.Count -gt 0) {
        $skus = @(Invoke-OutpostGraph -Path ('v1.0/subscribedSkus?$select=' + $SkuFieldList) -All)
        $sku = $null
        foreach ($candidate in $skus) {
            if (([string](Get-PropertyValue -Object $candidate -Name 'skuPartNumber') -ieq $Config.LicenseSku) -or ([string](Get-PropertyValue -Object $candidate -Name 'skuId') -ieq $Config.LicenseSku)) { $sku = $candidate; break }
        }
        if ($null -eq $sku) {
            $known = @($skus | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'skuPartNumber') } | Select-Object -First 12) -join ', '
            Stop-OutpostRun -Message "LicenseSku '$($Config.LicenseSku)' is not a subscription of this tenant. Subscriptions: $known. Nothing was created."
        }
        $skuId = [string](Get-PropertyValue -Object $sku -Name 'skuId')
        $skuName = [string](Get-PropertyValue -Object $sku -Name 'skuPartNumber')
        if ((Get-PropertyValue -Object $sku -Name 'appliesTo') -eq 'Company') { Stop-OutpostRun -Message "The licence $skuName applies to the company, not to users, so it cannot be assigned. Nothing was created." }
        $prepaid = Get-PropertyValue -Object $sku -Name 'prepaidUnits'
        $enabledUnits = Get-PropertyValue -Object $prepaid -Name 'enabled'
        $usedUnits = Get-PropertyValue -Object $sku -Name 'consumedUnits'
        if ($null -ne $enabledUnits -and $null -ne $usedUnits) { $freeUnits = [int]$enabledUnits - [int]$usedUnits }
    }
    $groups = @()
    if ($Config.AddToGroups.Count -gt 0 -and $toCreate.Count -gt 0) {
        $groups = @(foreach ($text in $Config.AddToGroups) { Resolve-TargetGroup -Text $text })
    }

    # The batch: as many new users as their passwords fit into one secure field.
    $batch = New-Object -TypeName System.Collections.ArrayList
    $deferred = New-Object -TypeName System.Collections.ArrayList
    $used = 0
    foreach ($user in $toCreate) {
        $size = $user.Upn.Length + 1 + $PasswordLength + 1
        if (($used + $size) -le $SecretFieldCapacity) { [void]$batch.Add($user); $used += $size } else { [void]$deferred.Add($user) }
    }
    if ($skuId -ne '' -and $null -ne $freeUnits -and $freeUnits -lt $batch.Count) {
        Stop-OutpostRun -Message "The licence $skuName has $freeUnits unit(s) free and $($batch.Count) user(s) would be created in this run. Buy licences or shorten the file. Nothing was created."
    }
    foreach ($user in $deferred) { Add-OutpostRow -Values @{ Item = $user.Upn; Change = 'Create user'; Result = 'Deferred: the password field is full; copy the passwords, then run again' } }

    # The passwords go only to a secure RMM field. With a ResultField the answer is never written to it, even when nobody is created.
    if (($batch.Count -gt 0 -and -not $script:OutpostRun.DryRun) -or (Get-OutpostRawInput -Name 'ResultField') -ne '') { Assert-OutpostSecretField }

    $perUser = 1
    if ($skuId -ne '') { $perUser++ }
    $perUser += @($groups).Count
    $planned = $batch.Count * $perUser
    if ($batch.Count -eq 0) {
        Complete-OutpostRun -Status 'OK' -Answer "Already created: all $($users.Count) user(s) in the CSV exist"
    }
    Assert-OutpostChangeLimit -Planned $planned

    # Act: passwords first (stored before any user exists), then each user in order.
    $passwords = @{}
    if (-not $script:OutpostRun.DryRun) {
        $entries = New-Object -TypeName System.Collections.ArrayList
        foreach ($user in $batch) {
            $passwords[$user.Upn] = New-RandomPassword
            [void]$entries.Add($user.Upn + '=' + $passwords[$user.Upn])
        }
        Write-OutpostSecretField -Value (@($entries) -join ' ')
        $entries = $null
    }
    $created = New-Object -TypeName System.Collections.ArrayList
    $licensedCount = 0
    $membershipCount = 0
    foreach ($user in $batch) {
        $state = @{ Id = '' }
        $upn = $user.Upn
        $null = Invoke-OutpostChange -Item $upn -Change 'Create user' -Action {
            $newUser = @{
                accountEnabled = $true
                displayName = $user.DisplayName
                mailNickname = $user.Nickname
                userPrincipalName = $upn
                passwordProfile = @{ forceChangePasswordNextSignIn = $true; password = $passwords[$upn] }
            }
            if ($user.UsageLocation -ne '') { $newUser['usageLocation'] = $user.UsageLocation }
            if ($user.GivenName -ne '') { $newUser['givenName'] = $user.GivenName }
            if ($user.Surname -ne '') { $newUser['surname'] = $user.Surname }
            if ($user.JobTitle -ne '') { $newUser['jobTitle'] = $user.JobTitle }
            if ($user.Department -ne '') { $newUser['department'] = $user.Department }
            $reply = Invoke-OutpostGraph -Path 'v1.0/users' -Method POST -Body $newUser
            $state.Id = [string](Get-PropertyValue -Object $reply -Name 'id')
            if ($state.Id -eq '') { throw "Graph created $upn but returned no user id." }
        }
        $passwords[$upn] = ''
        if ($skuId -ne '') {
            $done = Invoke-OutpostChange -Item $upn -Change "Assign licence $skuName" -Action {
                $null = Invoke-GraphWithRetry -Call {
                    Invoke-OutpostGraph -Path ('v1.0/users/' + $state.Id + '/assignLicense') -Method POST -Body @{ addLicenses = @(@{ skuId = $skuId; disabledPlans = @() }); removeLicenses = @() }
                }
            }
            if ($done) { $licensedCount++ }
        }
        foreach ($group in $groups) {
            $targetId = $group.Id
            $done = Invoke-OutpostChange -Item $upn -Change "Add to group $($group.Name)" -Action {
                $null = Invoke-GraphWithRetry -Call {
                    Invoke-OutpostGraph -Path ('v1.0/groups/' + $targetId + '/members/$ref') -Method POST -Body @{ '@odata.id' = ('https://graph.microsoft.com/v1.0/directoryObjects/' + $state.Id) }
                }
            }
            if ($done) { $membershipCount++ }
        }
        [void]$created.Add([pscustomobject]@{ Upn = $upn; Id = $state.Id })
    }
    $passwords = $null
    if ($script:OutpostRun.DryRun) {
        if ($skuId -ne '') { $licensedCount = $batch.Count }
        $membershipCount = $batch.Count * @($groups).Count
    }

    # Verify (skipped in a dry run). Entra shows a new user, a licence or a membership a few seconds late: read up to 6 times.
    if (-not $script:OutpostRun.DryRun) {
        $notReady = @()
        for ($read = 1; $read -le $RetryTries; $read++) {
            $notReady = @($created | Where-Object { -not (Test-UserCreated -UserId $_.Id -Upn $_.Upn -SkuId $skuId -Groups $groups) })
            if ($notReady.Count -eq 0) { break }
            Start-Sleep -Seconds $RetrySeconds
        }
        if ($notReady.Count -gt 0) {
            Stop-OutpostRun -Message ("$($notReady.Count) created user(s) do not yet show everything that was set: " + (@($notReady | Select-Object -First $MaxProblemsShown | ForEach-Object { $_.Upn }) -join ', ') + '. Check them in the Entra admin center (the passwords are already in the secure field).')
        }
    }

    # Finish
    $parts = @("$($batch.Count) user(s)")
    if ($skuId -ne '') { $parts = @("$($batch.Count) user(s) ($licensedCount licensed, $membershipCount group membership(s))") }
    elseif ($membershipCount -gt 0) { $parts = @("$($batch.Count) user(s) ($membershipCount group membership(s))") }
    $tail = ''
    if (-not $script:OutpostRun.DryRun) { $tail = '; passwords are in the secure field' }
    if ($existing.Count -gt 0) { $tail += "; $($existing.Count) already existed" }
    if ($deferred.Count -gt 0) { $tail += "; $($deferred.Count) deferred: copy the passwords, then run again" }
    Complete-OutpostRun -Status 'CHANGED' -Answer ("Created " + $parts[0] + $tail)
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
