#Requires -Version 5.1
<#
.SYNOPSIS
    Downloads an .msi or .exe installer over HTTPS, checks it, installs it silently and verifies the install.

.DESCRIPTION
    THIS SCRIPT CHANGES THINGS. It downloads the installer at Url into a
    temporary folder under %ProgramData%\MSPOutpost\Downloads (3 tries),
    checks it, runs it silently, optionally checks that the application is
    now listed as installed, and deletes the download. It installs only what
    you point it at, and never uninstalls or changes any other software.

    The file is never run until it is verified, one of two ways:
      * Sha256 is set: the download must match that SHA-256 exactly.
      * Sha256 is empty: the file must carry a valid Authenticode signature
        whose publisher is one of TrustedPublishers.
    With neither, the script refuses before it downloads anything.

    Only https:// is accepted, and a redirect to a plain http:// address is
    refused. The file type is read from the downloaded bytes (a Windows
    Installer package or a program), not from the URL.

    An .msi is run with msiexec /i and, unless Arguments already holds a
    /q switch, /qn /norestart. An .exe needs Arguments with its silent
    switches (for example /S, /VERYSILENT /NORESTART or /quiet /norestart).
    Exit codes in SuccessCodes count as success; 3010 and 1641 mean a reboot
    is needed, which the script reports and does not do.

    When DetectName is set and an installed application matching it is
    already listed, the script does nothing and says so (so the same job can
    run on a schedule). After a real install it must find that application,
    or it ends in ERROR.

.PARAMETER Url
    The https:// address of the installer. Required.
    Environment variable: Url

.PARAMETER Sha256
    The expected SHA-256 of the file, 64 hex characters, from the vendor.
    Required unless TrustedPublishers is set. Default empty.
    Environment variable: Sha256

.PARAMETER TrustedPublishers
    Used only when Sha256 is empty: a list (comma or semicolon) of publisher
    names. The file must be validly signed and the signing certificate's name
    (CN) or organisation (O) must equal one of them, for example
    "Igor Pavlov". Default empty. Environment variable: TrustedPublishers

.PARAMETER Arguments
    Silent switches for the installer. For an .msi the default is /qn
    /norestart. Required for an .exe. Default empty.
    Environment variable: Arguments

.PARAMETER SuccessCodes
    Exit codes that mean success. Default 0,3010,1641.
    Environment variable: SuccessCodes

.PARAMETER DetectName
    Name of the application as shown in Apps & features; * and ? work, and
    a name without a wildcard matches anywhere in the name. Skips the install
    when already present and verifies it afterwards. Default empty.
    Environment variable: DetectName

.PARAMETER TimeoutMinutes
    How long to wait for the installer. Whole number, 1 to 480. Default 30.
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
    .\install-application-from-url.ps1 -Url https://www.7-zip.org/a/7z2600-x64.msi -Sha256 c388d0444871ca11b21237001af158cfddad7e137851795e5b65cee69b518495 -DetectName 7-Zip

    Installs 7-Zip from the vendor file after checking its hash, unless 7-Zip is already installed.

.EXAMPLE
    .\install-application-from-url.ps1 -Url https://example.com/setup.exe -TrustedPublishers "Example Corp" -Arguments "/S"

    Installs a signed program, only when it is signed by Example Corp.

.NOTES
    Name:        Install an application from a URL, verified
    Slug:        install-application-from-url
    Version:     1.0.0
    Updated:     2026-11-16
    Type:        Action
    Category:    02 Software deployment & updates
    Platforms:   Windows 10, Windows 11, Windows Server 2016+
    RunAs:       System
    Requires:    PowerShell 5.1, administrator rights, internet access to the URL
    Changes:     Downloads an installer to a temporary folder, runs it, then deletes it
    Risk:        Low
    Reboot:      May
    Runtime:     1 to 10 minutes
    Answer:      "Installed 7-Zip 26.00 (x64 edition) from www.7-zip.org; reboot needed"
    Fields:      Item, Change, Result
    Runtime-Lib: 1.0.0
    Source:      https://mspoutpost.com/scripts/install-application-from-url
    License:     MIT
    Disclaimer:  Provided "as is" under the MIT License, without warranty of any kind. Test before production use. MSP Outpost and User First Digital Inc. accept no liability for any damage or loss.
    Changelog:
      1.0.0  2026-11-16  First version.
#>

[CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
param(
    # Inputs. Strings on purpose: RMMs send text.
    [string] $Url = '',
    [string] $Sha256 = '',
    [string] $TrustedPublishers = '',
    [string] $Arguments = '',
    [string] $SuccessCodes = '0,3010,1641',
    [string] $DetectName = '',
    [string] $TimeoutMinutes = '30',

    # Reserved inputs (standard section 5). Keep them in every script.
    [string] $DryRun = '',
    [string] $OutputFormat = 'Text',
    [string] $ExportPath = '',
    [string] $ResultField = '',
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $UnknownArguments
)

# Identity: must match the .NOTES header (the build checks it).
$OutpostScript = @{
    Slug    = 'install-application-from-url'
    Version = '1.0.0'
    Type    = 'Action'
    Risk    = 'Low'
    Inputs  = @('Url', 'Sha256', 'TrustedPublishers', 'Arguments', 'SuccessCodes', 'DetectName', 'TimeoutMinutes')
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
$UninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$RebootExitCodes = @(3010)
$RestartStartedExitCode = 1641
$InstallInProgressExitCode = 1618
$MinNameLetters = 3
$DownloadTries = 3
$DownloadRetrySeconds = 5
$DownloadTimeoutSeconds = 900
$VerifyWaitSeconds = 60
$DefaultMsiArguments = '/qn /norestart'

# ---- Functions ------------------------------------------------------------
function Get-RegistryValue {
    # Strict mode throws on a missing property, so read through the property bag.
    param($Item, [string] $PropertyName)
    $property = $Item.PSObject.Properties[$PropertyName]
    if ($property) { return $property.Value }
    return $null
}

function Find-InstalledApplication {
    # Machine-wide applications whose name matches the pattern (64-bit and 32-bit).
    param([string] $Pattern)
    $found = @()
    foreach ($keyPattern in $UninstallKeys) {
        foreach ($item in @(Get-ItemProperty -Path $keyPattern -ErrorAction SilentlyContinue)) {
            $displayName = Get-RegistryValue -Item $item -PropertyName 'DisplayName'
            if (-not $displayName) { continue }
            if ($displayName -notlike $Pattern) { continue }
            $found += ("$displayName " + [string](Get-RegistryValue -Item $item -PropertyName 'DisplayVersion')).Trim()
        }
    }
    return $found
}

function Get-SafeUrl {
    # Scheme, host and path only: a query string may carry a SAS or S3 token.
    param([Uri] $Address)
    return $Address.GetLeftPart([UriPartial]::Path)
}

function Save-Download {
    # Downloads with retries; refuses a redirect that ends on plain http.
    param([string] $Address, [string] $TargetFile, [string] $DisplayAddress)
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
                throw "The address redirected to a non-https location ($finalScheme). Use the final https address."
            }
            return
        }
        catch {
            $lastMessage = $_.Exception.Message
            if ($lastMessage -like '*non-https*') { break }
            if ($try -lt $DownloadTries) { Start-Sleep -Seconds ($DownloadRetrySeconds * $try) }
        }
    }
    throw "Could not download $DisplayAddress after $DownloadTries tries: $lastMessage Check the address and internet access."
}

function Get-InstallerKind {
    # 'msi' (OLE compound file) or 'exe' (MZ), read from the first bytes.
    param([string] $File)
    $stream = [IO.File]::OpenRead($File)
    try {
        $buffer = New-Object -TypeName byte[] -ArgumentList 8
        $count = $stream.Read($buffer, 0, 8)
    }
    finally { $stream.Dispose() }
    if ($count -ge 8 -and $buffer[0] -eq 0xD0 -and $buffer[1] -eq 0xCF -and $buffer[2] -eq 0x11 -and $buffer[3] -eq 0xE0) { return 'msi' }
    if ($count -ge 2 -and $buffer[0] -eq 0x4D -and $buffer[1] -eq 0x5A) { return 'exe' }
    return ''
}

function Confirm-Installer {
    # Throws unless the file matches the hash or is signed by a trusted publisher.
    param([string] $File, [string] $ExpectedHash, [string[]] $Publishers)
    if ($ExpectedHash -ne '') {
        $actual = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
        if ($actual -ne $ExpectedHash) {
            throw "The download does not match Sha256. Expected $($ExpectedHash.ToUpperInvariant()) but the file is $actual. The file was not run; check the URL and the hash."
        }
        return 'SHA-256 matched'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $File
    if ([string]$signature.Status -ne 'Valid') {
        throw "The download has no valid signature (status $($signature.Status)) and no Sha256 was given. The file was not run; set Sha256."
    }
    $certificate = $signature.SignerCertificate
    $names = @($certificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false))
    $organisation = [regex]::Match($certificate.Subject, '(?:^|,\s*)O=("(?:[^"]|"")*"|[^,]*)')
    if ($organisation.Success) { $names += $organisation.Groups[1].Value.Trim('"') }
    foreach ($publisher in $Publishers) {
        foreach ($signerName in $names) {
            if ($signerName -ieq $publisher) { return "signed by $signerName" }
        }
    }
    throw "The file is signed by '$($names -join ' / ')', which is not in TrustedPublishers. The file was not run."
}

function Invoke-Installer {
    # Runs the verified installer hidden and returns its exit code.
    param([string] $File, [string] $Kind, [string] $InstallArguments, [int] $WaitMinutes)
    if ($Kind -eq 'msi') {
        $startFile = Join-Path -Path ([Environment]::GetFolderPath('System')) -ChildPath 'msiexec.exe'
        $startArguments = "/i `"$File`" $InstallArguments"
    }
    else {
        $startFile = $File
        $startArguments = $InstallArguments
    }
    $process = Start-Process -FilePath $startFile -ArgumentList $startArguments.Trim() -PassThru -WindowStyle Hidden
    $null = $process.Handle
    if (-not $process.WaitForExit($WaitMinutes * 60000)) {
        throw "The installer did not finish within $WaitMinutes minutes (process id $($process.Id) is still running and was left alone). Wait for it, then run this script again."
    }
    return $process.ExitCode
}

# ---- Main -----------------------------------------------------------------
Start-OutpostRun
try {
    # Validate: every input read once, typed, into $Config.
    $Config = [pscustomobject]@{
        Url               = Read-OutpostText -Name 'Url' -Required
        Sha256            = Read-OutpostText -Name 'Sha256'
        TrustedPublishers = @(Read-OutpostList -Name 'TrustedPublishers')
        Arguments         = Read-OutpostText -Name 'Arguments'
        SuccessCodes      = @(Read-OutpostList -Name 'SuccessCodes')
        DetectName        = Read-OutpostText -Name 'DetectName'
        TimeoutMinutes    = Read-OutpostInt -Name 'TimeoutMinutes' -Min 1 -Max 480
    }
    $downloadUri = $null
    if (-not [Uri]::TryCreate($Config.Url, [UriKind]::Absolute, [ref]$downloadUri) -or $downloadUri.Scheme -ne 'https') {
        Stop-OutpostInput -Name 'Url' -Value $Config.Url -Expected 'an address that starts with https:// (plain http is refused)'
    }
    if ($Config.Sha256 -ne '' -and $Config.Sha256 -notmatch '^[0-9A-Fa-f]{64}$') {
        Stop-OutpostInput -Name 'Sha256' -Value $Config.Sha256 -Expected '64 hexadecimal characters (a SHA-256)'
    }
    $expectedHash = $Config.Sha256.ToUpperInvariant()
    if ($expectedHash -eq '' -and $Config.TrustedPublishers.Count -eq 0) {
        Stop-OutpostRun -Message 'Nothing to verify the download with, so nothing was downloaded. Set Sha256 to the vendor SHA-256, or set TrustedPublishers to the publisher name of a signed installer.'
    }
    $successCodeList = @()
    foreach ($codeText in $Config.SuccessCodes) {
        $code = 0
        if (-not [int]::TryParse($codeText, [ref]$code)) {
            Stop-OutpostInput -Name 'SuccessCodes' -Value $Config.SuccessCodes -Expected 'a list of whole numbers such as 0,3010,1641'
        }
        $successCodeList += $code
    }
    if ($successCodeList.Count -eq 0) {
        Stop-OutpostInput -Name 'SuccessCodes' -Value '' -Expected 'a list of whole numbers such as 0,3010,1641'
    }
    $pathLooksLikeExe = $downloadUri.AbsolutePath -match '\.exe$'
    if ($pathLooksLikeExe -and $Config.Arguments -eq '') {
        Stop-OutpostRun -Message 'Url points to an .exe, which needs its silent switches. Set Arguments (for example /S, /VERYSILENT /NORESTART or /quiet /norestart).'
    }
    if (-not (Test-OutpostAdmin)) {
        Stop-OutpostRun -Message 'This script needs administrator rights. Run it as SYSTEM from your RMM or from an elevated PowerShell.'
    }

    # Detect
    $detectPattern = ''
    if ($Config.DetectName -ne '') {
        if (($Config.DetectName -replace '[\*\?\[\]\s]', '').Length -lt $MinNameLetters) {
            Stop-OutpostInput -Name 'DetectName' -Value $Config.DetectName -Expected "a name with at least $MinNameLetters letters besides wildcards"
        }
        if ($Config.DetectName -match '[\*\?]') { $detectPattern = $Config.DetectName }
        else { $detectPattern = '*' + [WildcardPattern]::Escape($Config.DetectName) + '*' }
        $already = @(Find-InstalledApplication -Pattern $detectPattern)
        if ($already.Count -gt 0) {
            Complete-OutpostRun -Status 'OK' -Answer "Already installed: $($already[0])."
        }
    }

    # Act
    $itemName = [IO.Path]::GetFileName($downloadUri.AbsolutePath)
    if ($itemName -eq '') { $itemName = $downloadUri.Host }
    $state = @{ RebootNeeded = $false; RestartStarted = $false; Check = '' }
    $changeText = "Download from $($downloadUri.Host), verify, install silently"
    try {
        $null = Invoke-OutpostChange -Item $itemName -Change $changeText -Action {
            $workFolder = Join-Path -Path (Join-Path -Path (Get-OutpostDataFolder) -ChildPath 'Downloads') -ChildPath ([guid]::NewGuid().ToString('N'))
            $installerRunning = $false
            try {
                $null = New-Item -Path $workFolder -ItemType Directory -Force
                Protect-OutpostFolder -Path $workFolder
                $rawFile = Join-Path -Path $workFolder -ChildPath 'download.bin'
                Write-OutpostLine -Text "Downloading $(Get-SafeUrl -Address $downloadUri)"
                Save-Download -Address $Config.Url -TargetFile $rawFile -DisplayAddress (Get-SafeUrl -Address $downloadUri)
                $state.Check = Confirm-Installer -File $rawFile -ExpectedHash $expectedHash -Publishers $Config.TrustedPublishers
                $kind = Get-InstallerKind -File $rawFile
                if ($kind -eq '') {
                    throw 'The verified download is neither a Windows Installer package (.msi) nor a program (.exe), so it was not run.'
                }
                $installerFile = Join-Path -Path $workFolder -ChildPath ('installer.' + $kind)
                Move-Item -LiteralPath $rawFile -Destination $installerFile -Force
                # Verify again on the file that will run, inside the protected folder, right before launch.
                $null = Confirm-Installer -File $installerFile -ExpectedHash $expectedHash -Publishers $Config.TrustedPublishers
                $installArguments = $Config.Arguments
                if ($kind -eq 'msi' -and $installArguments -notmatch '(^|\s)/q') { $installArguments = ($DefaultMsiArguments + ' ' + $installArguments).Trim() }
                if ($kind -eq 'exe' -and $installArguments -eq '') {
                    throw 'The download is a program (.exe), which needs its silent switches. Set Arguments.'
                }
                Write-OutpostLine -Text "Verified ($($state.Check)); running the $kind installer."
                $installerRunning = $true
                $exitCode = Invoke-Installer -File $installerFile -Kind $kind -InstallArguments $installArguments -WaitMinutes $Config.TimeoutMinutes
                $installerRunning = $false
                if ($exitCode -eq $InstallInProgressExitCode -and $successCodeList -notcontains $exitCode) {
                    throw 'Another installation is already in progress on this PC (exit code 1618). Retry later.'
                }
                if ($successCodeList -notcontains $exitCode) {
                    throw "The installer exited with code $exitCode, which is not in SuccessCodes ($($successCodeList -join ',')). Check the silent switches in Arguments."
                }
                if ($RebootExitCodes -contains $exitCode) { $state.RebootNeeded = $true }
                if ($exitCode -eq $RestartStartedExitCode) { $state.RestartStarted = $true }
            }
            finally {
                # A timed-out installer may still be reading its file: leave the folder then.
                if ($workFolder -and (Test-Path -LiteralPath $workFolder) -and -not $installerRunning) {
                    try { Remove-Item -LiteralPath $workFolder -Recurse -Force }
                    catch { Write-OutpostWarning -Text "Could not delete the download folder ${workFolder}: $($_.Exception.Message)" }
                }
            }
        }
    }
    catch {
        Stop-OutpostRun -Message $_.Exception.Message
    }

    # Verify (skipped in a dry run: nothing was changed)
    $installedLabel = ''
    if (-not $script:OutpostRun.DryRun -and $detectPattern -ne '') {
        $deadline = (Get-Date).AddSeconds($VerifyWaitSeconds)
        $installedNow = @(Find-InstalledApplication -Pattern $detectPattern)
        while ($installedNow.Count -eq 0 -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 3
            $installedNow = @(Find-InstalledApplication -Pattern $detectPattern)
        }
        if ($installedNow.Count -eq 0) {
            Stop-OutpostRun -Message "The installer finished but no installed application matches DetectName '$($Config.DetectName)' after $VerifyWaitSeconds seconds. Check DetectName against Apps & features, and the installer's Arguments."
        }
        $installedLabel = $installedNow[0]
    }

    # Finish
    if ($installedLabel -ne '') { $answer = "Installed $installedLabel from $($downloadUri.Host)" }
    else { $answer = "Installed $itemName from $($downloadUri.Host)" }
    if ($state.RestartStarted) { $answer += '; the installer started a restart (exit code 1641)' }
    elseif ($state.RebootNeeded) { $answer += '; reboot needed' }
    Complete-OutpostRun -Status 'CHANGED' -Answer $answer
}
catch {
    Stop-OutpostRun -ErrorRecord $_
}
