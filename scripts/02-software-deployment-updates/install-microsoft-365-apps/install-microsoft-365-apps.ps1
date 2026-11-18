#Requires -Version 5.1
<#
.SYNOPSIS
    Installs Microsoft 365 Apps (Word, Excel, Outlook and the rest) silently with the Office Deployment Tool and a generated configuration.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It downloads the Office Deployment Tool
    (setup.exe) from Microsoft's own address, refuses to run it unless its
    Authenticode signature is valid and belongs to Microsoft Corporation,
    writes a configuration.xml from the inputs into a protected folder under
    %ProgramData%\MSPOutpost, runs "setup.exe /configure", waits for it, and
    then checks that Windows lists the product as installed. The setup tool and
    configuration are deleted afterwards. The ODT's own log is kept in
    %ProgramData%\MSPOutpost\Logs\microsoft-365-odt.

    It installs one Microsoft 365 product. It does not remove an older Office
    (the configuration has no RemoveMSI), does not sign anyone in or activate
    anything (users sign in with their Microsoft 365 account), and does not
    change an Office that is already there: if a Click-to-Run Office with the
    same Products value is installed, it ends in OK without doing anything; if
    a different product is installed, it stops with an error and changes
    nothing. A leftover Windows Installer (MSI) Office can make setup.exe fail;
    uninstall it first.

    The install accepts the Office licence terms on the user's behalf
    (AcceptEULA), which is what running an unattended Office install means:
    run it only for people licensed to use the product. It needs about 8 GB
    free on the system drive, internet access to officecdn.microsoft.com and
    the Office CDN, and typically takes 10 to 40 minutes (longer on a slow
    link: raise TimeoutMinutes). A dry run only describes the install; it
    downloads nothing.

    On a Windows Arm64 PC the 64-bit edition installs the native Arm64 build
    (setup.exe chooses it); Architecture Auto does that for you.

.PARAMETER Channel
    Update channel: Current, MonthlyEnterprise or SemiAnnual. Default
    MonthlyEnterprise (the monthly, predictable one for managed PCs).
    Environment variable: Channel

.PARAMETER Architecture
    Auto (default), x64, x86 or arm64. Auto installs the 64-bit edition on a
    64-bit Windows PC (the native Arm64 build on an Arm PC) and 32-bit on a
    32-bit one. arm64 is accepted only on an Arm64 PC and x64 only on an x64
    PC; x86 works anywhere. Environment variable: Architecture

.PARAMETER Products
    O365BusinessRetail (Microsoft 365 Apps for business, default) or
    O365ProPlusRetail (Microsoft 365 Apps for enterprise).
    Environment variable: Products

.PARAMETER ExcludeApps
    Apps to leave out, a list separated by comma or semicolon, from: Access,
    Bing, Excel, Groove, Lync, OneDrive, OneNote, Outlook, OutlookForWindows,
    PowerPoint, Publisher, Teams, Word. Groove is the old OneDrive for
    Business sync app and Lync is Skype for Business. Default Groove,Lync.
    None means exclude nothing. Environment variable: ExcludeApps

.PARAMETER Language
    MatchOS (default: the Windows display language) or a culture such as
    en-us, fr-ca or de-de. Environment variable: Language

.PARAMETER SharedComputerLicensing
    true turns on shared computer activation, for shared PCs and Remote
    Desktop servers. Default false. Environment variable: SharedComputerLicensing

.PARAMETER TimeoutMinutes
    How long to wait for setup.exe. Whole number, 10 to 240. Default 60.
    Environment variable: TimeoutMinutes

.PARAMETER DryRun
    true prints what would be done and downloads nothing. -WhatIf does the
    same. Default false. Environment variable: DryRun

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\install-microsoft-365-apps.ps1

    Installs Microsoft 365 Apps for business on the monthly enterprise channel, without OneDrive's old sync app and Skype for Business.

.EXAMPLE
    .\install-microsoft-365-apps.ps1 -Products O365ProPlusRetail -Channel SemiAnnual -ExcludeApps Groove,Lync,Teams,Publisher,Access -Language en-us

    Installs Microsoft 365 Apps for enterprise on the semi-annual channel in English without Teams, Publisher and Access.

.NOTES
    Name:        Install Microsoft 365 Apps (Office) with a generated configuration
    Slug:        install-microsoft-365-apps
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Action
    Category:    02 Software deployment & updates
    Platforms:   Windows 10 1809+, Windows 11, Windows Server 2019+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, internet access to Microsoft, 8 GB free disk
    Changes:     Downloads the Office Deployment Tool and installs Microsoft 365 Apps
    Risk:        Low
    Reboot:      May
    Runtime:     10 to 60 minutes
    Answer:      "Installed Microsoft 365 Apps O365BusinessRetail 16.0.19231.20154 (x64, MonthlyEnterprise)"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/install-microsoft-365-apps
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $Channel = 'MonthlyEnterprise',
    [string] $Architecture = 'Auto',
    [string] $Products = 'O365BusinessRetail',
    [string] $ExcludeApps = 'Groove,Lync',
    [string] $Language = 'MatchOS',
    [string] $SharedComputerLicensing = 'false',
    [string] $TimeoutMinutes = '60',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'install-microsoft-365-apps'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('Channel', 'Architecture', 'Products', 'ExcludeApps', 'Language', 'SharedComputerLicensing', 'TimeoutMinutes')
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
$SetupUrl = 'https://officecdn.microsoft.com/pr/wsus/setup.exe'
$SetupPublisher = 'Microsoft Corporation'
$ClickToRunKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration'
)
$Channels = @('Current', 'MonthlyEnterprise', 'SemiAnnual')
$ArchitectureChoices = @('Auto', 'x64', 'x86', 'arm64')
$ProductChoices = @('O365BusinessRetail', 'O365ProPlusRetail')
$AppIds = @('Access', 'Bing', 'Excel', 'Groove', 'Lync', 'OneDrive', 'OneNote', 'Outlook', 'OutlookForWindows', 'PowerPoint', 'Publisher', 'Teams', 'Word')
$MinBuild = 17763
$MinFreeGB = 8
$ArmProcessorCode = 12
$RebootExitCode = 3010
$DownloadTries = 3
$DownloadRetrySeconds = 5
$DownloadTimeoutSeconds = 600
$VerifyWaitSeconds = 120

# ---- Functions ------------------------------------------------------------
function Get-ObjectValue {
    # Strict mode throws on a missing property, so read through the property bag.
    param($Item, [string] $PropertyName)
    $property = $Item.PSObject.Properties[$PropertyName]
    if ($property) { return $property.Value }
    return $null
}

function Get-ClickToRunState {
    # The installed Click-to-Run Office: its product ids, version and platform, or $null when absent.
    foreach ($keyPath in $ClickToRunKeys) {
        $item = Get-ItemProperty -LiteralPath $keyPath -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        $releaseText = [string](Get-ObjectValue -Item $item -PropertyName 'ProductReleaseIds')
        $releaseIds = @($releaseText -split '[,;\s]+' | Where-Object { $_ -ne '' })
        if ($releaseIds.Count -eq 0) { continue }
        return [pscustomobject]@{
            ReleaseIds = $releaseIds
            Version    = [string](Get-ObjectValue -Item $item -PropertyName 'VersionToReport')
            Platform   = [string](Get-ObjectValue -Item $item -PropertyName 'Platform')
        }
    }
    return $null
}

function Get-SafeUrl {
    param([Uri] $Address)
    return $Address.GetLeftPart([UriPartial]::Path)
}

function Save-Download {
    # Downloads with retries; refuses a redirect that ends on plain http.
    param([string] $Address, [string] $TargetFile)
    $lastMessage = ''
    for ($try = 1; $try -le $DownloadTries; $try++) {
        try {
            if (Test-Path -LiteralPath $TargetFile) { Remove-Item -LiteralPath $TargetFile -Force }
            $response = Invoke-WebRequest -Uri $Address -OutFile $TargetFile -UseBasicParsing -TimeoutSec $DownloadTimeoutSeconds -PassThru
            $finalScheme = 'https'
            $baseResponse = $response.BaseResponse
            if ($baseResponse.PSObject.Properties['ResponseUri']) { $finalScheme = $baseResponse.ResponseUri.Scheme }
            elseif ($baseResponse.PSObject.Properties['RequestMessage']) { $finalScheme = $baseResponse.RequestMessage.RequestUri.Scheme }
            if ($finalScheme -ne 'https') {
                Remove-Item -LiteralPath $TargetFile -Force -ErrorAction SilentlyContinue
                throw "The address redirected to a non-https location ($finalScheme)."
            }
            return
        }
        catch {
            $lastMessage = $_.Exception.Message
            if ($lastMessage -like '*non-https*') { break }
            if ($try -lt $DownloadTries) { Start-Sleep -Seconds ($DownloadRetrySeconds * $try) }
        }
    }
    throw "Could not download $Address after $DownloadTries tries: $lastMessage Check internet access to officecdn.microsoft.com."
}

function Confirm-SetupFile {
    # Throws unless the file is a program with a valid Authenticode signature from Microsoft Corporation.
    param([string] $File)
    $stream = [IO.File]::OpenRead($File)
    try {
        $buffer = New-Object -TypeName byte[] -ArgumentList 2
        $count = $stream.Read($buffer, 0, 2)
    }
    finally { $stream.Dispose() }
    if ($count -lt 2 -or $buffer[0] -ne 0x4D -or $buffer[1] -ne 0x5A) {
        throw 'The download is not a Windows program, so it was not run. Check that officecdn.microsoft.com is reachable and not replaced by a proxy page.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $File
    if ([string]$signature.Status -ne 'Valid') {
        throw "The download has no valid signature (status $($signature.Status)), so it was not run. A proxy or antivirus may have changed the file."
    }
    $certificate = $signature.SignerCertificate
    $names = @($certificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false))
    $organisation = [regex]::Match($certificate.Subject, '(?:^|,\s*)O=("(?:[^"]|"")*"|[^,]*)')
    if ($organisation.Success) { $names += $organisation.Groups[1].Value.Trim('"') }
    foreach ($signerName in $names) {
        if ($signerName -ieq $SetupPublisher) { return "signed by $signerName" }
    }
    throw "The download is signed by '$($names -join ' / ')', not $SetupPublisher, so it was not run."
}

function New-OdtConfiguration {
    # The configuration.xml text. Every value was validated against a fixed set before this runs.
    param([string] $OdtEdition, [string] $OdtChannel, [string] $ProductId, [string] $LanguageId, [string[]] $Excluded, [bool] $IsShared, [string] $LogFolder)
    $lines = @()
    $lines += '<Configuration>'
    $lines += "  <Add OfficeClientEdition=`"$OdtEdition`" Channel=`"$OdtChannel`">"
    $lines += "    <Product ID=`"$ProductId`">"
    $lines += "      <Language ID=`"$LanguageId`" />"
    foreach ($appId in $Excluded) { $lines += "      <ExcludeApp ID=`"$appId`" />" }
    $lines += '    </Product>'
    $lines += '  </Add>'
    $sharedValue = '0'
    if ($IsShared) { $sharedValue = '1' }
    $lines += "  <Property Name=`"SharedComputerLicensing`" Value=`"$sharedValue`" />"
    $lines += '  <Updates Enabled="TRUE" />'
    $lines += '  <Display Level="None" AcceptEULA="TRUE" />'
    $lines += ("  <Logging Level=`"Standard`" Path=`"" + [Security.SecurityElement]::Escape($LogFolder) + '" />')
    $lines += '</Configuration>'
    return ($lines -join "`r`n")
}

function Invoke-OfficeSetup {
    # Runs setup.exe /configure hidden and returns its exit code.
    param([string] $SetupFile, [string] $ConfigFile, [int] $WaitMinutes)
    $process = Start-Process -FilePath $SetupFile -ArgumentList ('/configure "' + $ConfigFile + '"') -PassThru -WindowStyle Hidden
    $null = $process.Handle
    if (-not $process.WaitForExit($WaitMinutes * 60000)) {
        throw "Office setup did not finish within $WaitMinutes minutes (process id $($process.Id) is still running and was left alone). Wait for it, then run this script again, or raise TimeoutMinutes."
    }
    return $process.ExitCode
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        Channel                 = Read-OutpostChoice -Name 'Channel' -Allowed $Channels
        Architecture            = Read-OutpostChoice -Name 'Architecture' -Allowed $ArchitectureChoices
        Products                = Read-OutpostChoice -Name 'Products' -Allowed $ProductChoices
        ExcludeApps             = @(Read-OutpostList -Name 'ExcludeApps')
        Language                = Read-OutpostText -Name 'Language'
        SharedComputerLicensing = Read-OutpostBool -Name 'SharedComputerLicensing'
        TimeoutMinutes          = Read-OutpostInt -Name 'TimeoutMinutes' -Min 10 -Max 240
    }
    $excludedIds = @()
    foreach ($appText in $Config.ExcludeApps) {
        if ($appText -ieq 'None') { continue }
        $match = @($AppIds | Where-Object { $_ -ieq $appText })
        if ($match.Count -eq 0) {
            Stop-OutpostInput -Name 'ExcludeApps' -Value $appText -Expected ('names from: ' + ($AppIds -join ', ') + ', or None')
        }
        if ($excludedIds -notcontains $match[0]) { $excludedIds += $match[0] }
    }
    if ($Config.Language -ieq 'MatchOS') { $languageId = 'MatchOS' }
    elseif ($Config.Language -match '^[A-Za-z]{2,3}-[A-Za-z0-9]{2,8}$') { $languageId = $Config.Language.ToLowerInvariant() }
    else { Stop-OutpostInput -Name 'Language' -Value $Config.Language -Expected 'MatchOS or a culture such as en-us, fr-ca, de-de' }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ([int]$osInfo.BuildNumber -lt $MinBuild) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer "Skipped: Microsoft 365 Apps need Windows 10 version 1809 (build $MinBuild) or later; this is build $($osInfo.BuildNumber)."
    }
    $processorCode = [int](@(Get-CimInstance -ClassName Win32_Processor)[0].Architecture)
    $isArm = ($processorCode -eq $ArmProcessorCode)
    $is64Bit = [Environment]::Is64BitOperatingSystem
    $archLabel = $Config.Architecture
    if ($Config.Architecture -eq 'Auto') {
        if ($isArm) { $archLabel = 'arm64' } elseif ($is64Bit) { $archLabel = 'x64' } else { $archLabel = 'x86' }
    }
    if ($archLabel -eq 'arm64' -and -not $isArm) {
        Stop-OutpostInput -Name 'Architecture' -Value $Config.Architecture -Expected 'Auto, x64 or x86 on this PC (it is not an Arm64 PC)'
    }
    if ($archLabel -eq 'x64' -and ($isArm -or -not $is64Bit)) {
        Stop-OutpostInput -Name 'Architecture' -Value $Config.Architecture -Expected 'Auto, arm64 or x86 on this PC (it is not an x64 PC; on Arm64 the 64-bit edition installs the native Arm64 build)'
    }
    $odtEdition = '64'
    if ($archLabel -eq 'x86') { $odtEdition = '32' }

    # Detect
    $current = Get-ClickToRunState
    if ($current) {
        if ($current.ReleaseIds -contains $Config.Products) {
            Complete-OutpostRun -Status 'OK' -Answer "Already installed: Microsoft 365 Apps $($Config.Products) $($current.Version) ($($current.Platform))."
        }
        Stop-OutpostRun -Message "A different Click-to-Run Office is already installed ($($current.ReleaseIds -join ', ') $($current.Version)) and this script does not change it. Uninstall it first, or set Products to match it."
    }
    $systemRoot = [IO.Path]::GetPathRoot([Environment]::GetFolderPath('System'))
    $driveInfo = New-Object -TypeName System.IO.DriveInfo -ArgumentList $systemRoot
    $freeGB = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 1)
    if ($freeGB -lt $MinFreeGB) {
        Stop-OutpostRun -Message "Only $freeGB GB free on $systemRoot; Microsoft 365 Apps need about $MinFreeGB GB while installing. Free some space (clear-disk-space) and run again."
    }

    # Act
    $setupUri = [Uri]$SetupUrl
    $excludeText = 'none excluded'
    if ($excludedIds.Count -gt 0) { $excludeText = 'without ' + ($excludedIds -join ', ') }
    $changeText = "Download the Office Deployment Tool, verify it, install $archLabel on the $($Config.Channel) channel ($excludeText, language $languageId)"
    $state = @{ RebootNeeded = $false }
    try {
        $null = Invoke-OutpostChange -Item "Microsoft 365 Apps ($($Config.Products))" -Change $changeText -Action {
            $workFolder = Join-Path -Path (Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Downloads') -ChildPath ([guid]::NewGuid().ToString('N'))
            $setupRunning = $false
            try {
                $null = New-Item -Path $workFolder -ItemType Directory -Force
                Protect-OutpostFolder -Path $workFolder
                $rawFile = Join-Path -Path $workFolder -ChildPath 'download.bin'
                Write-OutpostLine -Text "Downloading the Office Deployment Tool from $(Get-SafeUrl -Address $setupUri)"
                Save-Download -Address $SetupUrl -TargetFile $rawFile
                $check = Confirm-SetupFile -File $rawFile
                $setupFile = Join-Path -Path $workFolder -ChildPath 'setup.exe'
                Move-Item -LiteralPath $rawFile -Destination $setupFile -Force
                # Verify again on the file that will run, inside the protected folder, right before launch.
                $null = Confirm-SetupFile -File $setupFile
                $logFolder = Join-Path -Path (Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Logs') -ChildPath 'microsoft-365-odt'
                $null = New-Item -Path $logFolder -ItemType Directory -Force
                $configFile = Join-Path -Path $workFolder -ChildPath 'configuration.xml'
                $configText = New-OdtConfiguration -OdtEdition $odtEdition -OdtChannel $Config.Channel -ProductId $Config.Products -LanguageId $languageId -Excluded $excludedIds -IsShared $Config.SharedComputerLicensing -LogFolder $logFolder
                [IO.File]::WriteAllText($configFile, $configText, (New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false))
                Write-OutpostLine -Text "Verified the setup tool ($check). Installing; this takes 10 to 40 minutes."
                $setupRunning = $true
                $exitCode = Invoke-OfficeSetup -SetupFile $setupFile -ConfigFile $configFile -WaitMinutes $Config.TimeoutMinutes
                $setupRunning = $false
                if ($exitCode -eq $RebootExitCode) { $state.RebootNeeded = $true }
                elseif ($exitCode -ne 0) {
                    throw "Office setup exited with code $exitCode. Its log is in $logFolder. Check disk space, internet access to the Office CDN, and that no old Windows Installer Office is installed."
                }
            }
            finally {
                # A timed-out setup may still be reading its files: leave the folder then.
                if ($workFolder -and (Test-Path -LiteralPath $workFolder) -and -not $setupRunning) {
                    try { Remove-Item -LiteralPath $workFolder -Recurse -Force }
                    catch { Write-OutpostWarning -Text "Could not delete the work folder ${workFolder}: $($_.Exception.Message)" }
                }
            }
        }
    }
    catch {
        Stop-OutpostRun -Message $_.Exception.Message
    }

    # Verify (skipped in a dry run: nothing was changed)
    $installedNow = $null
    if (-not $script:OutpostRun.DryRun) {
        $deadline = (Get-Date).AddSeconds($VerifyWaitSeconds)
        $installedNow = Get-ClickToRunState
        while ((-not $installedNow -or $installedNow.ReleaseIds -notcontains $Config.Products) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            $installedNow = Get-ClickToRunState
        }
        if (-not $installedNow -or $installedNow.ReleaseIds -notcontains $Config.Products) {
            Stop-OutpostRun -Message "Office setup finished but ProductReleaseIds under HKLM\SOFTWARE\Microsoft\Office\ClickToRun\Configuration does not list $($Config.Products) after $VerifyWaitSeconds seconds. See the setup log in the MSPOutpost Logs\microsoft-365-odt folder."
        }
    }

    # Finish
    $answer = "Installed Microsoft 365 Apps $($Config.Products) ($archLabel, $($Config.Channel))"
    if ($installedNow) { $answer = "Installed Microsoft 365 Apps $($Config.Products) $($installedNow.Version) ($archLabel, $($Config.Channel))" }
    if ($state.RebootNeeded) { $answer += '; reboot needed' }
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
