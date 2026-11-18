#Requires -Version 5.1
<#
.SYNOPSIS
    Removes preinstalled consumer apps (Candy Crush, TikTok, Clipchamp and similar) from a Windows 10/11 PC, for every user and for new users.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It removes a fixed, safe list of consumer apps
    twice: from every existing user profile (Remove-AppxPackage -AllUsers) and
    from the Windows image (Remove-AppxProvisionedPackage), so users created
    later do not get them back. Optionally it also sets one documented policy
    that stops Windows installing promoted apps.

    The default list: Candy Crush and other King games, Spotify, Disney+,
    TikTok, Prime Video, Clipchamp, Bing News, Weather, Finance and Sports,
    Solitaire Collection, People, Feedback Hub, Groove Music and Movies and TV
    (Zune), Mixed Reality Portal, 3D Builder, 3D Viewer, Print 3D, Tips
    (Get Started) and Skype. Note that on Windows 11 "Microsoft.ZuneMusic" is
    also the Media Player app; add it to KeepApps to keep it. Xbox apps are on
    the list only when RemoveXbox is true, Phone Link only when RemovePhoneLink
    is true.

    It NEVER touches (whatever ExtraApps says): Microsoft Store, App Installer
    (winget), Calculator, Photos, Notepad, Terminal, Paint, Snipping Tool,
    Edge, Teams, Outlook, Office, OneDrive, Company Portal, Windows Security,
    any framework or runtime package (VCLibs, .NET Native, UI.Xaml, Windows App
    Runtime, image and video codecs), anything Windows marks as non-removable
    or as a system app, and anything under Microsoft.Windows.* or
    MicrosoftWindows.*. A name in ExtraApps that falls under that protection is
    skipped with a warning.

    Before the first change the script saves the list of every package it will
    remove (name, full name, version, install folder) to
    %ProgramData%\MSPOutpost\Backups\remove-windows-bloatware\<time>\removed-apps.csv,
    so an app can be put back (Add-AppxPackage -Register, or the Store).

    A change is counted per app (its image copy and its user copies are one
    change) plus one for the policy. The default list is about 21 apps, within
    the default MaxChanges of 25 for a High-risk script. With many ExtraApps
    or RemoveXbox, set MaxChanges to the number the dry run plans (its warning
    says it).

    A High-risk Action: it only lists what it would do until BOTH DryRun=false
    AND Approve=remove-windows-bloatware are set. Run it again afterwards: it
    says "Nothing to remove". Removing an app that a user has open closes that
    app. Windows can bring a removed app back with a feature update; run the
    script again after one.

.PARAMETER RemoveXbox
    true also removes the Xbox app, the Xbox Game Bar overlay and the Gaming
    app. The Xbox identity and Gaming Services packages stay. Default false.
    Environment variable: RemoveXbox

.PARAMETER RemovePhoneLink
    true also removes Phone Link (Microsoft.YourPhone). Default false.
    Environment variable: RemovePhoneLink

.PARAMETER DisableConsumerFeatures
    true sets the policy "Turn off Microsoft consumer experiences"
    (HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent
    DisableWindowsConsumerFeatures = 1), so Windows stops installing promoted
    apps for new users. Microsoft applies this policy on Enterprise and
    Education editions only; on Pro it is stored but has no effect. The key is
    exported to the backup folder first. Default false.
    Environment variable: DisableConsumerFeatures

.PARAMETER ExtraApps
    More package names to remove, a list separated by comma or semicolon. The
    * and ? wildcards work on the package Name (for example Microsoft.Bing*,
    ContosoPromo.*). At least 3 characters besides wildcards. Never overrides
    the protected list. Default empty.
    Environment variable: ExtraApps

.PARAMETER KeepApps
    Package names to keep even though they are on the list (wildcards work),
    for example Microsoft.ZuneMusic or Microsoft.Bing*. Default empty.
    Environment variable: KeepApps

.PARAMETER DryRun
    Default true for this script. false (with Approve) makes real changes.
    Environment variable: DryRun

.PARAMETER Approve
    Must be remove-windows-bloatware for DryRun=false to take effect.
    Environment variable: Approve

.PARAMETER MaxChanges
    The most changes one run may make (one per app). Default 25.
    Environment variable: MaxChanges

.PARAMETER OutputFormat
    Text (default), Answer, Json or Csv. Environment variable: OutputFormat

.PARAMETER ExportPath
    Also write the rows to this .csv or .json file. Environment variable: ExportPath

.PARAMETER ResultField
    Also write the answer to this RMM custom field. Environment variable: ResultField

.EXAMPLE
    .\remove-windows-bloatware.ps1

    Dry run: lists every app it would remove and how many changes that is.

.EXAMPLE
    .\remove-windows-bloatware.ps1 -DryRun false -Approve remove-windows-bloatware -KeepApps Microsoft.ZuneMusic

    Removes the listed apps for all users and from the image, except Media Player.

.NOTES
    Name:        New PC full of junk apps - Windows 11 debloat (safe MSP profile)
    Slug:        remove-windows-bloatware
    Version:     1.0.0
    Updated:     2026-11-17
    Type:        Action
    Category:    01 Onboarding & provisioning
    Platforms:   Windows 10, Windows 11
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, the Appx and Dism modules (not on Server Core)
    Changes:     Removes listed consumer Appx packages for all users and from the Windows image; optionally sets one policy value
    Risk:        High
    Reboot:      Never
    Runtime:     1 to 5 minutes
    Answer:      "Removed 14 app(s) for all users and 15 from the image; kept 1 by KeepApps"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/remove-windows-bloatware
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-17  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $RemoveXbox = 'false',
    [string] $RemovePhoneLink = 'false',
    [string] $DisableConsumerFeatures = 'false',
    [string] $ExtraApps = '',
    [string] $KeepApps = '',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'remove-windows-bloatware'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'High'
    Inputs  = @('RemoveXbox', 'RemovePhoneLink', 'DisableConsumerFeatures', 'ExtraApps', 'KeepApps')
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
# Package Name patterns (-like). Literal names except the King games.
$DefaultApps = @(
    'king.com.*',
    'SpotifyAB.SpotifyMusic',
    'Disney.37853FC22B2CE',
    'BytedancePte.Ltd.TikTok',
    'AmazonVideo.PrimeVideo',
    'Clipchamp.Clipchamp',
    'Microsoft.BingNews',
    'Microsoft.BingWeather',
    'Microsoft.BingFinance',
    'Microsoft.BingSports',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.People',
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo',
    'Microsoft.MixedReality.Portal',
    'Microsoft.3DBuilder',
    'Microsoft.Microsoft3DViewer',
    'Microsoft.Print3D',
    'Microsoft.Getstarted',
    'Microsoft.SkypeApp'
)
$XboxApps = @('Microsoft.XboxApp', 'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay')
$PhoneLinkApps = @('Microsoft.YourPhone')
# Never removed, whatever the inputs say.
$ProtectedApps = @(
    'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.Services.Store.*',
    'Microsoft.WindowsCalculator', 'Microsoft.Windows.Photos', 'Microsoft.WindowsNotepad', 'Microsoft.WindowsTerminal*',
    'Microsoft.Paint', 'Microsoft.ScreenSketch', 'Microsoft.MicrosoftEdge*', 'Microsoft.Edge*', 'MSTeams', 'MicrosoftTeams',
    'Microsoft.Office.*', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.OutlookForWindows', 'Microsoft.OneDrive*', 'Microsoft.CompanyPortal',
    'Microsoft.SecHealthUI', 'Microsoft.SecurityHealth*', 'Microsoft.Windows.*', 'MicrosoftWindows.*', 'Microsoft.AAD.*',
    'Microsoft.AccountsControl', 'Microsoft.LockApp', 'Microsoft.Win32WebViewHost', 'Microsoft.WebView2*',
    'Microsoft.VCLibs*', 'Microsoft.NET.*', 'Microsoft.UI.Xaml*', 'Microsoft.WindowsAppRuntime*', 'Microsoft.WindowsAppSDK*',
    'Microsoft.DirectXRuntime*', 'Microsoft.*Extension*', 'Microsoft.*Extensions', 'Microsoft.GamingServices',
    'Microsoft.XboxIdentityProvider', 'Microsoft.Xbox.TCUI'
)
$PolicyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
$PolicyValueName = 'DisableWindowsConsumerFeatures'
$MinNameLetters = 3

# ---- Functions ------------------------------------------------------------
function Get-ObjectValue {
    # Strict mode throws on a missing property, so read through the property bag.
    param($Item, [string] $PropertyName)
    $property = $Item.PSObject.Properties[$PropertyName]
    if ($property) { return $property.Value }
    return $null
}

function Test-NameMatch {
    # True when the package name matches any of the -like patterns.
    param([string] $Name, [string[]] $Patterns)
    foreach ($pattern in $Patterns) {
        if ($Name -like $pattern) { return $true }
    }
    return $false
}

function Test-ProtectedPackage {
    # On the never-touch list, or marked by Windows as non-removable, a framework or a system app.
    param($Package, [string] $Name)
    if (Test-NameMatch -Name $Name -Patterns $ProtectedApps) { return $true }
    if ((Get-ObjectValue -Item $Package -PropertyName 'NonRemovable') -eq $true) { return $true }
    if ((Get-ObjectValue -Item $Package -PropertyName 'IsFramework') -eq $true) { return $true }
    if ([string](Get-ObjectValue -Item $Package -PropertyName 'SignatureKind') -eq 'System') { return $true }
    return $false
}

function Get-InstalledPackage {
    # Every package for every user. A Windows PC always has some, so none means the call failed.
    $packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    if ($packages.Count -eq 0) { throw 'Get-AppxPackage -AllUsers returned nothing. Run this as SYSTEM or an elevated administrator on Windows 10/11.' }
    return $packages
}

function Initialize-DismTemp {
    # The Dism cmdlets build paths from TEMP and fail with "path1 is null" when an
    # agent starts the script with a stripped environment. Give them a folder.
    $tempFolder = Join-Path -Path ([Environment]::GetFolderPath('Windows')) -ChildPath 'Temp'
    foreach ($variableName in @('TEMP', 'TMP')) {
        if (-not [Environment]::GetEnvironmentVariable($variableName)) { [Environment]::SetEnvironmentVariable($variableName, $tempFolder, 'Process') }
    }
    return $tempFolder
}

function Get-ProvisionedPackage {
    $tempFolder = Initialize-DismTemp
    return @(Get-AppxProvisionedPackage -Online -ScratchDirectory $tempFolder -ErrorAction Stop)
}

function Get-PackagePlan {
    # Sorts every installed and provisioned package into: remove, keep (by KeepApps), protected (skipped).
    param([string[]] $WantedPatterns, [string[]] $KeepPatterns)
    $plan = @{
        Installed   = @{}
        Provisioned = @{}
        Kept        = @{}
        Protected   = @{}
    }
    foreach ($package in (Get-InstalledPackage)) {
        $name = [string]$package.Name
        if (-not (Test-NameMatch -Name $name -Patterns $WantedPatterns)) { continue }
        if (Test-ProtectedPackage -Package $package -Name $name) { $plan.Protected[$name] = $true; continue }
        if (Test-NameMatch -Name $name -Patterns $KeepPatterns) { $plan.Kept[$name] = $true; continue }
        if (-not $plan.Installed.ContainsKey($name)) { $plan.Installed[$name] = New-Object -TypeName System.Collections.ArrayList }
        [void]$plan.Installed[$name].Add($package)
    }
    foreach ($package in (Get-ProvisionedPackage)) {
        $name = [string]$package.DisplayName
        if (-not (Test-NameMatch -Name $name -Patterns $WantedPatterns)) { continue }
        if (Test-NameMatch -Name $name -Patterns $ProtectedApps) { $plan.Protected[$name] = $true; continue }
        if (Test-NameMatch -Name $name -Patterns $KeepPatterns) { $plan.Kept[$name] = $true; continue }
        if (-not $plan.Provisioned.ContainsKey($name)) { $plan.Provisioned[$name] = New-Object -TypeName System.Collections.ArrayList }
        [void]$plan.Provisioned[$name].Add($package)
    }
    return $plan
}

function Test-WidePattern {
    # A pattern needs real letters besides wildcards.
    param([string] $Pattern)
    return (($Pattern -replace '[\*\?\[\]\s]', '').Length -lt $MinNameLetters)
}

function Get-PolicyValue {
    $item = Get-ItemProperty -LiteralPath $PolicyKey -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    return Get-ObjectValue -Item $item -PropertyName $PolicyValueName
}

function Save-RemovalList {
    # Writes the list of what is about to be removed into the run's backup folder.
    param($Plan)
    $lines = @()
    foreach ($name in @($Plan.Installed.Keys | Sort-Object)) {
        foreach ($package in @($Plan.Installed[$name])) {
            $lines += [pscustomobject]@{
                Kind            = 'Installed'
                Name            = $name
                PackageFullName = [string]$package.PackageFullName
                Version         = [string]$package.Version
                InstallLocation = [string](Get-ObjectValue -Item $package -PropertyName 'InstallLocation')
            }
        }
    }
    foreach ($name in @($Plan.Provisioned.Keys | Sort-Object)) {
        foreach ($package in @($Plan.Provisioned[$name])) {
            $lines += [pscustomobject]@{
                Kind            = 'Provisioned'
                Name            = $name
                PackageFullName = [string]$package.PackageName
                Version         = [string]$package.Version
                InstallLocation = ''
            }
        }
    }
    $stageFolder = Join-Path -Path (Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Work') -ChildPath ([guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -Path $stageFolder -ItemType Directory -Force
        Protect-OutpostFolder -Path $stageFolder
        $stageFile = Join-Path -Path $stageFolder -ChildPath 'removed-apps.csv'
        $lines | Export-Csv -LiteralPath $stageFile -NoTypeInformation -Encoding UTF8
        $copy = Backup-OutpostItem -Path $stageFile
        $final = Join-Path -Path (Split-Path -Path $copy -Parent) -ChildPath 'removed-apps.csv'
        Move-Item -LiteralPath $copy -Destination $final -Force
        Write-OutpostLog -Text "BACKUP  list of $(@($lines).Count) package(s) to be removed  ->  $final"
        return $final
    }
    finally {
        Remove-Item -LiteralPath $stageFolder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        RemoveXbox              = Read-OutpostBool -Name 'RemoveXbox'
        RemovePhoneLink         = Read-OutpostBool -Name 'RemovePhoneLink'
        DisableConsumerFeatures = Read-OutpostBool -Name 'DisableConsumerFeatures'
        ExtraApps               = @(Read-OutpostList -Name 'ExtraApps')
        KeepApps                = @(Read-OutpostList -Name 'KeepApps')
    }
    foreach ($pattern in $Config.ExtraApps) {
        if (Test-WidePattern -Pattern $pattern) {
            Stop-OutpostInput -Name 'ExtraApps' -Value $pattern -Expected "package names with at least $MinNameLetters characters besides wildcards (for example Microsoft.Bing*)"
        }
    }
    foreach ($pattern in $Config.KeepApps) {
        if (Test-WidePattern -Pattern $pattern) {
            Stop-OutpostInput -Name 'KeepApps' -Value $pattern -Expected "package names with at least $MinNameLetters characters besides wildcards (for example Microsoft.ZuneMusic)"
        }
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    if ([int]$osInfo.ProductType -ne 1 -or [int]$osInfo.BuildNumber -lt 10240) {
        Complete-OutpostRun -Status 'SKIPPED' -Answer 'Skipped: this is not a Windows 10 or 11 PC (the listed apps only come with those).'
    }
    if (-not (Get-Command -Name 'Get-AppxPackage' -ErrorAction SilentlyContinue) -or -not (Get-Command -Name 'Remove-AppxProvisionedPackage' -ErrorAction SilentlyContinue)) {
        Stop-OutpostRun -Message 'The Appx and Dism PowerShell modules are not available here (Windows Server Core or a stripped image). Run it on a full Windows 10/11 PC in Windows PowerShell 5.1.'
    }

    # Detect
    $wantedPatterns = @($DefaultApps)
    if ($Config.RemoveXbox) { $wantedPatterns += $XboxApps }
    if ($Config.RemovePhoneLink) { $wantedPatterns += $PhoneLinkApps }
    $wantedPatterns += $Config.ExtraApps
    $plan = Get-PackagePlan -WantedPatterns $wantedPatterns -KeepPatterns $Config.KeepApps
    foreach ($name in @($plan.Protected.Keys | Sort-Object)) {
        Write-OutpostWarning -Text "Skipped $name : it is protected (on the never-touch list, or Windows marks it non-removable or a framework)."
    }
    $installedNames = @($plan.Installed.Keys | Sort-Object)
    $provisionedNames = @($plan.Provisioned.Keys | Sort-Object)
    $keptCount = @($plan.Kept.Keys).Count
    $policyNeeded = $Config.DisableConsumerFeatures -and ((Get-PolicyValue) -ne 1)
    $appNames = @(@($installedNames) + @($provisionedNames) | Sort-Object -Unique)
    $planned = $appNames.Count
    if ($policyNeeded) { $planned++ }

    $keptText = ''
    if ($keptCount -gt 0) { $keptText = "; kept $keptCount by KeepApps" }
    if ($planned -eq 0) {
        Complete-OutpostRun -Status 'OK' -Answer "Nothing to remove: none of the listed apps are installed or in the Windows image$keptText."
    }

    # Safety: the planned count against MaxChanges, before anything changes.
    Assert-OutpostChangeLimit -Planned $planned
    if (-not $script:OutpostRun.DryRun) {
        if ($installedNames.Count + $provisionedNames.Count -gt 0) {
            $listFile = Save-RemovalList -Plan $plan
            Write-OutpostLine -Text "Saved the list of apps to be removed: $listFile"
        }
        if ($policyNeeded -and (Test-Path -LiteralPath $PolicyKey)) { $null = Backup-OutpostItem -Path $PolicyKey }
    }

    # Act. One change per app: the image copy first (so a new user does not get it), then every user.
    $failures = @()
    $appNames = @(@($installedNames) + @($provisionedNames) | Sort-Object -Unique)
    foreach ($name in $appNames) {
        $imagePackages = @()
        if ($plan.Provisioned.ContainsKey($name)) { $imagePackages = @($plan.Provisioned[$name] | ForEach-Object { [string]$_.PackageName }) }
        $fullNames = @()
        if ($plan.Installed.ContainsKey($name)) { $fullNames = @($plan.Installed[$name] | ForEach-Object { [string]$_.PackageFullName }) }
        try {
            $null = Invoke-OutpostChange -Item $name -Change 'Remove for all users and from the image' -Action {
                foreach ($imagePackage in $imagePackages) {
                    $null = Remove-AppxProvisionedPackage -Online -PackageName $imagePackage -ScratchDirectory (Initialize-DismTemp) -ErrorAction Stop
                }
                foreach ($fullName in $fullNames) {
                    Remove-AppxPackage -Package $fullName -AllUsers -ErrorAction Stop
                }
            }
        }
        catch { $failures += "${name}: $($_.Exception.Message)" }
    }
    if ($policyNeeded) {
        $null = Invoke-OutpostChange -Item $PolicyValueName -Change 'Set policy to 1 (turn off consumer experiences)' -Action {
            if (-not (Test-Path -LiteralPath $PolicyKey)) { $null = New-Item -Path $PolicyKey -Force }
            $null = New-ItemProperty -LiteralPath $PolicyKey -Name $PolicyValueName -Value 1 -PropertyType DWord -Force
        }
    }

    # Verify (skipped in a dry run: nothing was changed)
    if (-not $script:OutpostRun.DryRun) {
        $after = Get-PackagePlan -WantedPatterns $wantedPatterns -KeepPatterns $Config.KeepApps
        $leftover = @(@($after.Installed.Keys) + @($after.Provisioned.Keys) | Sort-Object -Unique)
        if ($leftover.Count -gt 0 -or $failures.Count -gt 0) {
            $detail = ''
            if ($failures.Count -gt 0) { $detail = ' First error: ' + $failures[0] }
            Stop-OutpostRun -Message "Still present after removal: $($leftover -join ', ').$detail Windows may have them in use or locked; run the script again after a restart. The removed list is in the backup folder."
        }
        if ($policyNeeded -and ((Get-PolicyValue) -ne 1)) {
            Stop-OutpostRun -Message "The policy $PolicyValueName did not read back as 1 after it was set. Check $PolicyKey."
        }
    }

    # Finish
    $answer = "Removed $($installedNames.Count) app(s) for all users and $($provisionedNames.Count) from the image"
    if ($policyNeeded) { $answer += '; consumer features policy set' }
    $answer += $keptText
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
