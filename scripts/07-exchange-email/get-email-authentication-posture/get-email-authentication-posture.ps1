#Requires -Version 5.1
<#
.SYNOPSIS
    Reads a domain's public email DNS records (MX, SPF, DMARC, DKIM, MTA-STS, TLS-RPT) and says which ones protect it from spoofing.

.DESCRIPTION
    THIS SCRIPT IS READ-ONLY. It asks DNS (Resolve-DnsName) about one or more
    domains and writes one row per record found, each with a verdict. It sends
    no email, connects to no mail server and needs no sign-in; any Windows PC
    with internet DNS can run it.

    Per domain it reads:

      * MX: where the domain receives mail ("no MX" and "null MX" are noted:
        fine for a domain that never receives mail).
      * SPF: the "v=spf1" TXT record. Verdict Pass for -all, Warn for ~all,
        Fail for ?all, +all, no "all" at all, no record, more than one record
        (receivers treat that as an error) or more than 10 DNS lookups
        (also an error). The lookup count follows include: and redirect=.
      * DMARC: the TXT record at _dmarc.<domain>. Pass for p=reject and for
        p=quarantine at 100 percent, Warn for p=none (watching only) or
        quarantine on part of the mail, Fail for no record or an invalid one.
        The detail says whether a report address (rua) is set.
      * DKIM: DKIM keys cannot be listed from DNS, so it tries the common
        selector names (default, selector1, selector2, google, k1, k2, k3, s1,
        s2, mail, dkim, smtp, mandrill, everlytickey1, pm, mxvip) plus
        DkimSelectors, at <selector>._domainkey.<domain>. A key found is Pass,
        Warn when it is revoked or looks like 1024 bits, Fail under 1024 bits.
        When none is found the row says Warn: a selector this script does not
        know may still exist. Give it with DkimSelectors (the selector is in
        the DKIM-Signature header of a real email from the domain).
      * MTA-STS (_mta-sts.<domain>) and TLS-RPT (_smtp._tls.<domain>): optional
        extras. Present is Pass, absent is Info. The MTA-STS policy file on the
        web is not downloaded, only the DNS record is read.

    It checks exactly the names it is given. DMARC set on a parent domain
    protects its subdomains, but this script does not guess which part of a
    name is the parent: give it each domain you care about. A domain that does
    not exist ends with one row saying so.

    Verdicts: Pass, Warn, Fail, Info. The run is OK whatever the verdicts are:
    the rows and the answer carry the finding. If DNS itself cannot be reached
    the run ends in an error instead of guessing.

.PARAMETER Domain
    The domain(s) to check, separated by commas, for example "example.com".
    Required. At most 20. Environment variable: Domain

.PARAMETER DkimSelectors
    Extra DKIM selector names to try, separated by commas, for example
    "mailchimp, sig1". Default none. Environment variable: DkimSelectors

.PARAMETER DnsServer
    IP address of a DNS server to ask instead of this PC's own, for example
    1.1.1.1 to see what the public sees. Default empty = this PC's DNS.
    Environment variable: DnsServer

.PARAMETER DryRun
    Reserved; ignored by Reports.

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\get-email-authentication-posture.ps1 -Domain example.com

    Prints every email-authentication record example.com publishes and a verdict for each.

.EXAMPLE
    .\get-email-authentication-posture.ps1 -Domain "example.com, example.org" -DkimSelectors mailchimp -DnsServer 1.1.1.1 -OutputFormat Csv

    Checks two domains, also tries the selector "mailchimp", asking 1.1.1.1.

.NOTES
    Name:        Is this domain protected from email spoofing - SPF, DKIM and DMARC check
    Slug:        get-email-authentication-posture
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Report
    Category:    07 Exchange & email
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       Either
    Requires:    PowerShell 5.1, the DnsClient module (Resolve-DnsName), internet DNS
    Changes:     None
    Risk:        Low
    Reboot:      Never
    Runtime:     10 to 60 seconds per domain
    Answer:      "example.com: SPF -all; DMARC p=reject; DKIM 2 selector(s); 0 fail, 1 warn"
    Fields:      Domain, Check, Record, Verdict, Detail
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/get-email-authentication-posture
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $Domain = '',
    [string] $DkimSelectors = '',
    [string] $DnsServer = '',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'get-email-authentication-posture'
    Version = '1.0.0'
    Type    = 'Report'
    Risk    = 'Low'
    Inputs  = @('Domain', 'DkimSelectors', 'DnsServer')
    Fields  = @('Domain', 'Check', 'Record', 'Verdict', 'Detail')
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
$MaxDomains = 20
$MaxSpfLookups = 10
$MaxRecordTextTable = 70
$MaxRecordTextData = 500
$CommonDkimSelectors = @('default', 'selector1', 'selector2', 'google', 'k1', 'k2', 'k3', 's1', 's2', 'mail', 'dkim', 'smtp', 'mandrill', 'everlytickey1', 'pm', 'mxvip')
$DomainPattern = '^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'
$SelectorPattern = '^[a-z0-9_-]{1,63}(\.[a-z0-9_-]{1,63})*$'

# ---- Functions ------------------------------------------------------------
function Limit-Text {
    param([string] $Text, [int] $Length)
    if ($Text.Length -le $Length) { return $Text }
    return $Text.Substring(0, $Length - 3) + '...'
}

function Get-DnsAnswer {
    # One DNS question. State is Found, NoRecords (name exists, no such record), NotFound
    # (the name does not exist) or Error (the lookup itself failed). Codes, not English text.
    param([Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][string] $Type)
    $cacheKey = "$Type|$Name"
    if ($script:DnsCache.ContainsKey($cacheKey)) { return $script:DnsCache[$cacheKey] }
    $outcome = $null
    for ($attempt = 1; $attempt -le 2 -and $null -eq $outcome; $attempt++) {
        $arguments = @{ Name = $Name; Type = $Type; DnsOnly = $true; NoHostsFile = $true; ErrorAction = 'Stop' }
        if ($Config.DnsServer -ne '') { $arguments['Server'] = $Config.DnsServer }
        try {
            $records = @(Resolve-DnsName @arguments | Where-Object { [string]$_.Type -eq $Type })
            $state = if ($records.Count -gt 0) { 'Found' } else { 'NoRecords' }
            $outcome = [pscustomobject]@{ State = $state; Records = $records; Message = '' }
        }
        catch {
            $errorId = [string]$_.FullyQualifiedErrorId
            if ($errorId -match 'DNS_ERROR_RCODE_NAME_ERROR') { $outcome = [pscustomobject]@{ State = 'NotFound'; Records = @(); Message = '' } }
            elseif ($errorId -match 'DNS_INFO_NO_RECORDS') { $outcome = [pscustomobject]@{ State = 'NoRecords'; Records = @(); Message = '' } }
            elseif ($attempt -eq 2) { $outcome = [pscustomobject]@{ State = 'Error'; Records = @(); Message = ($_.Exception.Message -replace '\s+', ' ').Trim() } }
        }
    }
    $script:DnsCache[$cacheKey] = $outcome
    return $outcome
}

function Get-TxtValue {
    # The TXT records at a name as strings (a record split in several strings is joined).
    param([Parameter(Mandatory = $true)][string] $Name)
    $answer = Get-DnsAnswer -Name $Name -Type 'TXT'
    return @($answer.Records | ForEach-Object { (@($_.Strings) -join '') })
}

function Get-RecordsStartingWith {
    # TXT records whose first word (a version tag such as v=spf1) matches, ignoring case.
    param([Parameter(Mandatory = $true)][string] $Name, [Parameter(Mandatory = $true)][string] $Tag)
    return @(Get-TxtValue -Name $Name | Where-Object { (($_.Trim() -split '[\s;]+')[0]) -ieq $Tag })
}

function ConvertFrom-TagList {
    # "v=DMARC1; p=reject; pct=100" as a hashtable with lower-case keys.
    param([Parameter(Mandatory = $true)][string] $Text)
    $tags = @{}
    foreach ($part in ($Text -split ';')) {
        $pair = $part.Trim()
        $index = $pair.IndexOf('=')
        if ($index -gt 0) { $tags[$pair.Substring(0, $index).Trim().ToLowerInvariant()] = $pair.Substring($index + 1).Trim() }
    }
    return $tags
}

function Get-SpfAll {
    # The "all" term that ends an SPF record: -all, ~all, ?all or +all, or '' when there is none.
    # A redirect= with no all is followed (a few levels).
    param([Parameter(Mandatory = $true)][string] $Text, [int] $Depth = 0)
    $terms = @($Text.ToLowerInvariant() -split '\s+')
    foreach ($term in $terms) {
        if ($term -match '^([+\-~?]?)all$') {
            $qualifier = $Matches[1]
            if ($qualifier -eq '') { $qualifier = '+' }
            return "${qualifier}all"
        }
    }
    if ($Depth -lt 3) {
        foreach ($term in $terms) {
            if ($term -match '^redirect=(\S+)$') {
                $target = @(Get-RecordsStartingWith -Name $Matches[1] -Tag 'v=spf1')
                if ($target.Count -eq 1) { return Get-SpfAll -Text $target[0] -Depth ($Depth + 1) }
            }
        }
    }
    return ''
}

function Get-SpfLookupCount {
    # DNS lookups an SPF record makes (a, mx, ptr, exists, include, redirect), following includes.
    # Stops counting once past the limit.
    param([Parameter(Mandatory = $true)][string] $Text, [int] $Depth, [hashtable] $Seen)
    $count = 0
    foreach ($term in @($Text.ToLowerInvariant() -split '\s+')) {
        $bare = $term -replace '^[+\-~?]', ''
        $nested = ''
        if ($bare -match '^(a|mx|ptr)([:/]|$)' -or $bare -match '^exists:') { $count++ }
        elseif ($bare -match '^include:(\S+)$') { $count++; $nested = $Matches[1] }
        elseif ($bare -match '^redirect=(\S+)$') { $count++; $nested = $Matches[1] }
        if ($nested -ne '' -and $Depth -lt 10 -and -not $Seen.ContainsKey($nested)) {
            $Seen[$nested] = $true
            $records = @(Get-RecordsStartingWith -Name $nested -Tag 'v=spf1')
            if ($records.Count -ge 1) { $count += Get-SpfLookupCount -Text $records[0] -Depth ($Depth + 1) -Seen $Seen }
        }
        if ($count -gt $MaxSpfLookups) { return $count }
    }
    return $count
}

function Add-PostureRow {
    param([string] $Domain, [string] $Check, [string] $Record, [string] $Verdict, [string] $Detail)
    # The text table is cut at the screen width, so records are shortened there; Json and Csv keep them.
    $limit = if ($script:OutpostRun.Format -eq 'Text') { $MaxRecordTextTable } else { $MaxRecordTextData }
    Add-OutpostRow -Values @{ Domain = $Domain; Check = $Check; Record = (Limit-Text -Text $Record -Length $limit); Verdict = $Verdict; Detail = $Detail }
}

function Test-DkimKey {
    # Verdict and detail for one DKIM TXT value.
    param([Parameter(Mandatory = $true)][string] $Text)
    $tags = ConvertFrom-TagList -Text $Text
    $key = ''
    if ($tags.ContainsKey('p')) { $key = ($tags['p'] -replace '\s', '') }
    if ($key -eq '') { return @{ Verdict = 'Warn'; Detail = 'Key is empty: this selector has been revoked' } }
    if ($tags.ContainsKey('k') -and $tags['k'] -ieq 'ed25519') { return @{ Verdict = 'Pass'; Detail = 'Ed25519 key' } }
    $bytes = $null
    try { $bytes = [Convert]::FromBase64String($key) } catch { $bytes = $null }
    if ($null -eq $bytes) { return @{ Verdict = 'Fail'; Detail = 'Key is not valid base64' } }
    # A DER-encoded RSA public key is about 94 bytes for 512 bits, 162 for 1024, 294 for 2048, 550 for 4096.
    if ($bytes.Length -lt 150) { return @{ Verdict = 'Fail'; Detail = "Key is under 1024 bits ($($bytes.Length) bytes): too weak" } }
    if ($bytes.Length -lt 200) { return @{ Verdict = 'Warn'; Detail = 'Key looks like 1024 bits: 2048 bits is recommended' } }
    return @{ Verdict = 'Pass'; Detail = 'Key published' }
}

function Test-EmailDomain {
    # Checks one domain, adds its rows and returns a summary: Exists, Spf, Dmarc, Dkim (count).
    param([Parameter(Mandatory = $true)][string] $Name)
    $summary = @{ Exists = $true; Spf = 'no SPF'; Dmarc = 'no DMARC'; Dkim = 0 }

    # MX (also tells whether the domain exists at all)
    $mx = Get-DnsAnswer -Name $Name -Type 'MX'
    if ($mx.State -eq 'Error') { Stop-OutpostRun -Message "DNS lookups failed for ${Name}: $($mx.Message). Check this PC's DNS or set DnsServer." }
    if ($mx.State -eq 'NotFound') {
        Add-PostureRow -Domain $Name -Check 'Domain' -Record '' -Verdict 'Fail' -Detail 'The domain does not exist (DNS says NXDOMAIN)'
        $summary.Exists = $false
        return $summary
    }
    if ($mx.State -eq 'NoRecords') {
        Add-PostureRow -Domain $Name -Check 'MX' -Record '' -Verdict 'Info' -Detail 'No MX record: the domain does not receive email (fine if it never should)'
    }
    foreach ($record in @($mx.Records | Sort-Object -Property Preference)) {
        $exchange = ([string]$record.NameExchange).TrimEnd('.')
        if ($exchange -eq '') {
            Add-PostureRow -Domain $Name -Check 'MX' -Record '. (null MX)' -Verdict 'Info' -Detail 'The domain says it receives no email'
        }
        else {
            Add-PostureRow -Domain $Name -Check 'MX' -Record "$($record.Preference) $exchange" -Verdict 'Pass' -Detail 'Receives email here'
        }
    }

    # SPF
    $spfTxt = Get-DnsAnswer -Name $Name -Type 'TXT'
    if ($spfTxt.State -eq 'Error') { Stop-OutpostRun -Message "DNS lookups failed for ${Name}: $($spfTxt.Message). Check this PC's DNS or set DnsServer." }
    $spfRecords = @(Get-RecordsStartingWith -Name $Name -Tag 'v=spf1')
    if ($spfRecords.Count -eq 0) {
        Add-PostureRow -Domain $Name -Check 'SPF' -Record '' -Verdict 'Fail' -Detail 'No SPF record: anyone can send email that claims to be from this domain'
    }
    foreach ($spf in $spfRecords) {
        $allTerm = Get-SpfAll -Text $spf
        $lookups = Get-SpfLookupCount -Text $spf -Depth 0 -Seen @{}
        $lookupText = if ($lookups -gt $MaxSpfLookups) { "more than $MaxSpfLookups DNS lookups (receivers treat that as an error)" } else { "$lookups of $MaxSpfLookups DNS lookups" }
        $verdict = 'Pass'
        $detail = 'Ends in -all: only the listed senders may send'
        switch ($allTerm) {
            '-all' { }
            '~all' { $verdict = 'Warn'; $detail = 'Ends in ~all (soft fail): unlisted senders are marked, not rejected' }
            '?all' { $verdict = 'Fail'; $detail = 'Ends in ?all (neutral): says nothing about unlisted senders' }
            '+all' { $verdict = 'Fail'; $detail = 'Ends in +all: allows EVERYONE to send as this domain' }
            default { $verdict = 'Fail'; $detail = 'No "all" term at the end: unlisted senders are not covered' }
        }
        if ($spfRecords.Count -gt 1) { $verdict = 'Fail'; $detail = 'More than one SPF record: receivers treat that as an error. ' + $detail }
        if ($lookups -gt $MaxSpfLookups) { $verdict = 'Fail' }
        if ($spf -match '(^|\s)[+\-~?]?ptr([:\s]|$)') { if ($verdict -eq 'Pass') { $verdict = 'Warn' }; $detail += '; uses the deprecated ptr term' }
        Add-PostureRow -Domain $Name -Check 'SPF' -Record $spf -Verdict $verdict -Detail "$detail; $lookupText"
        $summary.Spf = if ($allTerm -ne '') { "SPF $allTerm" } else { 'SPF without all' }
    }
    if ($spfRecords.Count -gt 1) { $summary.Spf = 'SPF duplicated' }

    # DMARC
    $dmarcName = "_dmarc.$Name"
    $dmarcAnswer = Get-DnsAnswer -Name $dmarcName -Type 'TXT'
    if ($dmarcAnswer.State -eq 'Error') { Stop-OutpostRun -Message "DNS lookups failed for ${dmarcName}: $($dmarcAnswer.Message). Check this PC's DNS or set DnsServer." }
    $dmarcRecords = @(Get-RecordsStartingWith -Name $dmarcName -Tag 'v=dmarc1')
    if ($dmarcRecords.Count -eq 0) {
        Add-PostureRow -Domain $Name -Check 'DMARC' -Record '' -Verdict 'Fail' -Detail 'No DMARC record: receivers have no instruction for spoofed mail and you get no reports'
    }
    foreach ($dmarc in $dmarcRecords) {
        $tags = ConvertFrom-TagList -Text $dmarc
        $policy = ''
        if ($tags.ContainsKey('p')) { $policy = $tags['p'].ToLowerInvariant() }
        $percent = 100
        if ($tags.ContainsKey('pct')) {
            $parsedPercent = 0
            if ([int]::TryParse($tags['pct'], [ref]$parsedPercent)) { $percent = $parsedPercent }
        }
        $verdict = 'Pass'
        $detail = "p=$policy"
        switch ($policy) {
            'reject' { }
            'quarantine' { if ($percent -lt 100) { $verdict = 'Warn'; $detail = "p=quarantine on only $percent percent of mail" } }
            'none' { $verdict = 'Warn'; $detail = 'p=none: watching only, spoofed mail is still delivered' }
            default { $verdict = 'Fail'; $detail = "Invalid or missing p= policy ('$policy')" }
        }
        if ($dmarcRecords.Count -gt 1) { $verdict = 'Fail'; $detail = 'More than one DMARC record: receivers ignore them. ' + $detail }
        if ($tags.ContainsKey('sp') -and $tags['sp'] -ne $policy) { $detail += "; subdomains: sp=$($tags['sp'])" }
        if (-not $tags.ContainsKey('rua')) { $detail += '; no rua= address, so no aggregate reports' }
        Add-PostureRow -Domain $Name -Check 'DMARC' -Record $dmarc -Verdict $verdict -Detail $detail
        $summary.Dmarc = if ($policy -ne '') { "DMARC p=$policy" } else { 'DMARC invalid' }
    }
    if ($dmarcRecords.Count -gt 1) { $summary.Dmarc = 'DMARC duplicated' }

    # DKIM
    foreach ($selector in $Config.Selectors) {
        $dkimName = "$selector._domainkey.$Name"
        $keys = @(Get-TxtValue -Name $dkimName | Where-Object { $_ -match '(^|[\s;])(v=DKIM1|p=)' })
        foreach ($key in $keys) {
            $keyResult = Test-DkimKey -Text $key
            Add-PostureRow -Domain $Name -Check "DKIM $selector" -Record $key -Verdict $keyResult.Verdict -Detail $keyResult.Detail
            $summary.Dkim++
        }
    }
    if ($summary.Dkim -eq 0) {
        Add-PostureRow -Domain $Name -Check 'DKIM' -Record '' -Verdict 'Warn' -Detail "No DKIM key found at $($Config.Selectors.Count) common selector name(s); another selector may exist. Give it with DkimSelectors."
    }

    # MTA-STS and TLS-RPT
    $stsRecords = @(Get-RecordsStartingWith -Name "_mta-sts.$Name" -Tag 'v=stsv1')
    if ($stsRecords.Count -gt 0) {
        Add-PostureRow -Domain $Name -Check 'MTA-STS' -Record $stsRecords[0] -Verdict 'Pass' -Detail 'DNS record present (the policy file on the web was not checked)'
    }
    else {
        Add-PostureRow -Domain $Name -Check 'MTA-STS' -Record '' -Verdict 'Info' -Detail 'Not set up (optional): makes senders use encrypted delivery to this domain'
    }
    $tlsRecords = @(Get-RecordsStartingWith -Name "_smtp._tls.$Name" -Tag 'v=tlsrptv1')
    if ($tlsRecords.Count -gt 0) {
        Add-PostureRow -Domain $Name -Check 'TLS-RPT' -Record $tlsRecords[0] -Verdict 'Pass' -Detail 'Reports on failed encrypted delivery are requested'
    }
    else {
        Add-PostureRow -Domain $Name -Check 'TLS-RPT' -Record '' -Verdict 'Info' -Detail 'Not set up (optional)'
    }
    return $summary
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        Domains   = @(Read-OutpostList -Name 'Domain' -Required | ForEach-Object { $_.ToLowerInvariant().TrimEnd('.') })
        Selectors = @()
        DnsServer = Read-OutpostText -Name 'DnsServer'
    }
    if ($Config.Domains.Count -gt $MaxDomains) {
        Stop-OutpostInput -Name 'Domain' -Value "$($Config.Domains.Count) domains" -Expected "at most $MaxDomains domains per run"
    }
    foreach ($name in $Config.Domains) {
        if ($name -notmatch $DomainPattern) {
            Stop-OutpostInput -Name 'Domain' -Value $name -Expected 'domain names such as example.com (no http://, no user@ part)'
        }
    }
    $extraSelectors = @(Read-OutpostList -Name 'DkimSelectors' | ForEach-Object { $_.ToLowerInvariant() })
    foreach ($selector in $extraSelectors) {
        if ($selector -notmatch $SelectorPattern) {
            Stop-OutpostInput -Name 'DkimSelectors' -Value $selector -Expected 'selector names such as selector1 (letters, digits, - and _)'
        }
    }
    $Config.Selectors = @($CommonDkimSelectors + $extraSelectors | Select-Object -Unique)
    if ($Config.DnsServer -ne '') {
        $parsedAddress = $null
        if (-not [Net.IPAddress]::TryParse($Config.DnsServer, [ref]$parsedAddress)) {
            Stop-OutpostInput -Name 'DnsServer' -Value $Config.DnsServer -Expected 'an IP address such as 1.1.1.1'
        }
    }
    if (-not (Get-Command -Name 'Resolve-DnsName' -ErrorAction SilentlyContinue)) {
        Stop-OutpostRun -Message 'Resolve-DnsName is not available here (the DnsClient module). Run it on Windows 8.1, Server 2012 R2 or later, in Windows PowerShell 5.1.'
    }
    $script:DnsCache = @{}

    # Detect
    Write-OutpostLine -Text "Reading the email DNS records of $($Config.Domains.Count) domain(s)."
    $summaries = @{}
    foreach ($name in $Config.Domains) {
        $summaries[$name] = Test-EmailDomain -Name $name
    }

    # Finish
    $rows = @($script:OutpostRun.Rows)
    $failCount = @($rows | Where-Object { $_.Verdict -eq 'Fail' }).Count
    $warnCount = @($rows | Where-Object { $_.Verdict -eq 'Warn' }).Count
    if ($Config.Domains.Count -eq 1) {
        $name = $Config.Domains[0]
        $one = $summaries[$name]
        if (-not $one.Exists) {
            Complete-OutpostRun -Status 'OK' -Answer "${name}: the domain does not exist"
        }
        Complete-OutpostRun -Status 'OK' -Answer ("${name}: $($one.Spf); $($one.Dmarc); DKIM $($one.Dkim) selector(s); $failCount fail, $warnCount warn")
    }
    $failingDomains = @()
    foreach ($name in $Config.Domains) {
        if (@($rows | Where-Object { $_.Domain -eq $name -and $_.Verdict -eq 'Fail' }).Count -gt 0) { $failingDomains += $name }
    }
    $answer = "$($Config.Domains.Count) domain(s) checked: $failCount fail, $warnCount warn"
    if ($failingDomains.Count -gt 0) { $answer += '; with a fail: ' + ($failingDomains -join ', ') }
    Complete-OutpostRun -Status 'OK' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
