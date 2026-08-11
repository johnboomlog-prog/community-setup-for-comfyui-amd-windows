[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][ValidateSet('AutomaticManaged','Custom')][string]$Mode,
    [ValidatePattern('^[A-Za-z]:$')][string]$DriveLetter,
    [ValidateRange(1,4095)][int]$InitialGB,
    [ValidateRange(1,4095)][int]$MaximumGB,
    [Parameter(Mandatory)][switch]$ConfirmPageFileChange
)

$ErrorActionPreference = 'Stop'
$savedWhatIf = $WhatIfPreference
$WhatIfPreference = $false
Import-Module CimCmdlets -ErrorAction Stop
$WhatIfPreference = $savedWhatIf
$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($plan.schemaVersion -ne 1 -or -not $plan.pageFile) { throw 'The deployment plan does not contain a supported page-file recommendation.' }
if (-not $ConfirmPageFileChange) { throw 'Explain why virtual memory is needed, present the recommendation, and obtain explicit user approval first.' }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $WhatIfPreference -and -not $isAdmin) { throw 'Changing the page file requires an elevated Administrator PowerShell session.' }

if ($Mode -eq 'AutomaticManaged') {
    if ($PSCmdlet.ShouldProcess('Windows page-file configuration','Enable Windows automatic page-file management')) {
        $computer = Get-CimInstance Win32_ComputerSystem
        Set-CimInstance -InputObject $computer -Property @{ AutomaticManagedPagefile = $true } | Out-Null
    }
    [ordered]@{ mode=$Mode; changed=[bool](-not $WhatIfPreference); rebootRequired=$true; note='Windows chooses page-file placement and size. Reboot, then regenerate the host report and deployment plan.' } | ConvertTo-Json
    return
}

if (-not $DriveLetter -or -not $InitialGB -or -not $MaximumGB) { throw 'Custom mode requires -DriveLetter, -InitialGB, and -MaximumGB.' }
if ($InitialGB -gt $MaximumGB) { throw 'InitialGB cannot exceed MaximumGB.' }
$range = $plan.pageFile.customRange
if ($InitialGB -lt [int]$range.minimumGB -or $MaximumGB -gt [int]$range.maximumRecommendedGB) {
    throw "Choose values inside the reviewed range: $($range.minimumGB)-$($range.maximumRecommendedGB) GB; recommended $($range.recommendedGB) GB."
}
$root = "$($DriveLetter.ToUpper())\"
$drive = [IO.DriveInfo]::new($root)
if (-not $drive.IsReady) { throw "Drive is not ready: $root" }
if ($drive.DriveFormat -notin @('NTFS','ReFS')) { throw "Page-file target must be NTFS or ReFS: $($drive.DriveFormat)" }
$pageFileName = Join-Path $root 'pagefile.sys'
$existing = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $pageFileName } | Select-Object -First 1
$existingMaximumBytes = if ($existing) { [int64]$existing.MaximumSize * 1MB } else { [int64]0 }
$additionalBytes = [int64][math]::Max([double]0, [double](($MaximumGB * 1GB) - $existingMaximumBytes))
if ([int64]$drive.AvailableFreeSpace -lt ($additionalBytes + 20GB)) {
    throw "Insufficient headroom on $root. Expanding this page file can require $([math]::Round($additionalBytes/1GB,2)) additional GB and the skill preserves 20 GB free."
}

$target = "$pageFileName ($InitialGB-$MaximumGB GB)"
if ($PSCmdlet.ShouldProcess($target,'Disable global automatic management and create/update this page file while preserving other page files')) {
    $computer = Get-CimInstance Win32_ComputerSystem
    Set-CimInstance -InputObject $computer -Property @{ AutomaticManagedPagefile = $false } | Out-Null
    $properties = @{ InitialSize=[uint32]($InitialGB * 1024); MaximumSize=[uint32]($MaximumGB * 1024) }
    if ($existing) { Set-CimInstance -InputObject $existing -Property $properties | Out-Null }
    else {
        $newProperties = @{ Name=$pageFileName; InitialSize=$properties.InitialSize; MaximumSize=$properties.MaximumSize }
        New-CimInstance -ClassName Win32_PageFileSetting -Property $newProperties | Out-Null
    }
}
[ordered]@{
    mode=$Mode; drive=$DriveLetter.ToUpper(); initialGB=$InitialGB; maximumGB=$MaximumGB
    preservedOtherPageFiles=$true; changed=[bool](-not $WhatIfPreference); rebootRequired=$true
    note='Reboot, rerun inspect-host.ps1, and regenerate the deployment plan before installing ComfyUI.'
} | ConvertTo-Json
