[CmdletBinding()]
param(
    [string]$ComfyUIRoot,
    [string]$PythonPath,
    [string]$InstallRoot,
    [string[]]$SearchRoot = @(),
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Invoke-Safely {
    param([scriptblock]$Action)
    try { & $Action } catch { $null }
}

function Get-PythonProbe {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $probe = & $Path -c "import json,platform,sys; print(json.dumps({'path':sys.executable,'version':platform.python_version(),'bits':platform.architecture()[0]}))" 2>$null
    $ErrorActionPreference = $oldPreference
    if ($LASTEXITCODE -ne 0 -or -not $probe) { return [ordered]@{ path = $Path; error = 'probe_failed' } }
    try { $probe | Select-Object -Last 1 | ConvertFrom-Json } catch { [ordered]@{ path = $Path; error = 'invalid_probe_output' } }
}

$os = Invoke-Safely { Get-CimInstance Win32_OperatingSystem }
$computer = Invoke-Safely { Get-CimInstance Win32_ComputerSystem }
$processor = Invoke-Safely { Get-CimInstance Win32_Processor | Select-Object -First 1 }
$gpus = @(Invoke-Safely { Get-CimInstance Win32_VideoController } | Where-Object { $_ } | ForEach-Object {
    [ordered]@{
        name = $_.Name
        driverVersion = $_.DriverVersion
        pnpDeviceId = $_.PNPDeviceID
        status = $_.Status
        amdCandidate = [bool]($_.Name -match 'AMD|Radeon')
    }
})

$logicalDisks = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq [IO.DriveType]::Fixed } | ForEach-Object {
    [ordered]@{
        device = $_.Name.TrimEnd('\'); root = $_.RootDirectory.FullName; volumeName = $_.VolumeLabel; fileSystem = $_.DriveFormat; driveType = 'fixed'
        sizeBytes = [int64]$_.TotalSize; freeBytes = [int64]$_.AvailableFreeSpace
        sizeGB = [math]::Round($_.TotalSize / 1GB, 2); freeGB = [math]::Round($_.AvailableFreeSpace / 1GB, 2)
    }
})
$pageFiles = @(Invoke-Safely { Get-CimInstance Win32_PageFileUsage } | Where-Object { $_ } | ForEach-Object {
    [ordered]@{ name = $_.Name; allocatedMB = $_.AllocatedBaseSize; currentMB = $_.CurrentUsage; peakMB = $_.PeakUsage }
})
$pageFileSettings = @(Invoke-Safely { Get-CimInstance Win32_PageFileSetting } | Where-Object { $_ } | ForEach-Object {
    [ordered]@{ name = $_.Name; initialMB = $_.InitialSize; maximumMB = $_.MaximumSize }
})
$memoryPerformance = Invoke-Safely { Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory | Select-Object -First 1 }
$automaticManagedPagefile = if ($computer -and $computer.AutomaticManagedPagefile -ne $null) { [bool]$computer.AutomaticManagedPagefile } else { $null }
function Get-NumericSum([object[]]$Items, [string]$PropertyName) {
    [double]$sum = 0
    foreach ($item in @($Items)) {
        if ($null -ne $item -and $null -ne $item[$PropertyName]) { $sum += [double]$item[$PropertyName] }
    }
    $sum
}
$pageFileInitialMB = Get-NumericSum $pageFileSettings 'initialMB'
$pageFileMaximumMB = Get-NumericSum $pageFileSettings 'maximumMB'
$pageFileAllocatedMB = Get-NumericSum $pageFiles 'allocatedMB'
$pageFileCurrentMB = Get-NumericSum $pageFiles 'currentMB'
$pageFilePeakMB = Get-NumericSum $pageFiles 'peakMB'
if ($logicalDisks.Count -eq 0) {
    $logicalDisks = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Root } | ForEach-Object {
        $volume = Invoke-Safely { Get-Volume -DriveLetter $_.Name -ErrorAction Stop }
        [ordered]@{
            device = "$($_.Name):"; root = $_.Root
            volumeName = if ($volume) { $volume.FileSystemLabel } else { $null }
            fileSystem = if ($volume) { $volume.FileSystem } else { $null }
            driveType = if ($volume) { [string]$volume.DriveType } else { 'filesystem' }
            sizeBytes = if ($_.Used -ne $null -and $_.Free -ne $null) { [int64]($_.Used + $_.Free) } else { $null }
            freeBytes = if ($_.Free -ne $null) { [int64]$_.Free } else { $null }
            sizeGB = if ($_.Used -ne $null) { [math]::Round(($_.Used + $_.Free) / 1GB, 2) } else { $null }
            freeGB = if ($_.Free -ne $null) { [math]::Round($_.Free / 1GB, 2) } else { $null }
        }
    })
}

$pythonCandidates = [System.Collections.Generic.List[string]]::new()
if ($PythonPath) { $pythonCandidates.Add($PythonPath) }
foreach ($name in @('python.exe', 'python3.exe')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { $pythonCandidates.Add($cmd.Source) }
}
$pyLauncher = Get-Command py.exe -ErrorAction SilentlyContinue
if ($pyLauncher) {
    $listed = & $pyLauncher.Source -0p 2>$null
    foreach ($line in $listed) {
        if ($line -match '\*\s+(.+python\.exe)\s*$') { $pythonCandidates.Add($Matches[1].Trim()) }
    }
}
$pythons = @($pythonCandidates | Select-Object -Unique | ForEach-Object { Get-PythonProbe $_ } | Where-Object { $_ })

$wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
$wslStatus = $null
$wslDistributions = @()
if ($wslCommand) {
    $wslStatus = Invoke-Safely { (& $wslCommand.Source --status 2>&1) -join [Environment]::NewLine }
    $wslDistributions = @(Invoke-Safely { & $wslCommand.Source --list --quiet 2>$null } | ForEach-Object { (([string]$_) -replace "`0",'').Trim() } | Where-Object { $_ })
}
$wslFeature = Invoke-Safely { (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction Stop).State }
$vmPlatformFeature = Invoke-Safely { (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop).State }

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vcvarsCandidates = [System.Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $vswhere) {
    $vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsInstall) { $vcvarsCandidates.Add((Join-Path ($vsInstall | Select-Object -Last 1) 'VC\Auxiliary\Build\vcvars64.bat')) }
}
foreach ($candidate in @(
    "$env:ProgramFiles\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
    "$env:ProgramFiles\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat",
    "$env:ProgramFiles\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
)) { if (Test-Path -LiteralPath $candidate) { $vcvarsCandidates.Add($candidate) } }

$roots = [System.Collections.Generic.List[string]]::new()
if ($ComfyUIRoot -and (Test-Path -LiteralPath (Join-Path $ComfyUIRoot 'main.py'))) { $roots.Add((Resolve-Path -LiteralPath $ComfyUIRoot).Path) }
foreach ($base in $SearchRoot) {
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { continue }
    Get-ChildItem -LiteralPath $base -Filter main.py -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -eq 'ComfyUI' } |
        ForEach-Object { $roots.Add($_.Directory.FullName) }
}

$port = 8188
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | ForEach-Object {
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue
    [ordered]@{ address = $_.LocalAddress; port = $_.LocalPort; pid = $_.OwningProcess; commandLine = $proc.CommandLine }
})
$apiHealthy = $false
$apiSystem = $null
try { $apiSystem = Invoke-RestMethod "http://127.0.0.1:$port/system_stats" -TimeoutSec 2; $apiHealthy = $true } catch {}
if ($gpus.Count -eq 0 -and $apiSystem -and $apiSystem.devices) {
    $gpus = @($apiSystem.devices | ForEach-Object {
        [ordered]@{
            name = $_.name
            driverVersion = $null
            pnpDeviceId = $null
            status = 'reported-by-comfyui-api'
            amdCandidate = [bool]($_.name -match 'AMD|Radeon')
            vramGB = [math]::Round($_.vram_total / 1GB, 2)
        }
    })
}

$securityProducts = @()
try {
    $securityProducts = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct | ForEach-Object {
        [ordered]@{ name = $_.displayName; executable = $_.pathToSignedProductExe; state = $_.productState }
    })
} catch {}

$storageTarget = $null
if ($InstallRoot) {
    $installFull = [IO.Path]::GetFullPath($InstallRoot)
    $installDrive = [IO.Path]::GetPathRoot($installFull).TrimEnd('\')
    $targetDisk = @($logicalDisks | Where-Object { ([string]$_.root).TrimEnd('\') -ieq $installDrive -or ([string]$_.device).TrimEnd('\') -ieq $installDrive }) | Select-Object -First 1
    $storageTarget = [ordered]@{
        installRoot = $installFull; drive = $installDrive; found = [bool]$targetDisk
        fileSystem = if ($targetDisk) { $targetDisk.fileSystem } else { $null }
        freeBytes = if ($targetDisk) { $targetDisk.freeBytes } else { $null }
        freeGB = if ($targetDisk) { $targetDisk.freeGB } else { $null }
        largeFileCapable = [bool]($targetDisk -and $targetDisk.fileSystem -in @('NTFS','ReFS','exFAT'))
        preferredForPythonEnvironment = [bool]($targetDisk -and $targetDisk.fileSystem -in @('NTFS','ReFS'))
    }
}

$report = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    readOnly = $true
    os = [ordered]@{
        caption = if ($os) { $os.Caption } else { [Environment]::OSVersion.VersionString }
        version = if ($os) { $os.Version } else { [Environment]::OSVersion.Version.ToString() }
        build = if ($os) { $os.BuildNumber } else { [Environment]::OSVersion.Version.Build }
        architecture = if ($os) { $os.OSArchitecture } else { $env:PROCESSOR_ARCHITECTURE }
        cimAccessible = [bool]$os
    }
    computer = [ordered]@{
        manufacturer = if ($computer) { $computer.Manufacturer } else { $null }
        model = if ($computer) { $computer.Model } else { $null }
        ramGB = if ($computer) { [math]::Round($computer.TotalPhysicalMemory / 1GB, 2) } elseif ($apiSystem -and $apiSystem.system.ram_total) { [math]::Round($apiSystem.system.ram_total / 1GB, 2) } else { $null }
    }
    cpu = [ordered]@{
        name = if ($processor) { $processor.Name } else { $env:PROCESSOR_IDENTIFIER }
        architecture = $env:PROCESSOR_ARCHITECTURE
        virtualizationFirmwareEnabled = if ($processor) { $processor.VirtualizationFirmwareEnabled } else { $null }
        secondLevelAddressTranslation = if ($processor) { $processor.SecondLevelAddressTranslationExtensions } else { $null }
    }
    gpu = $gpus
    disks = $logicalDisks
    storageTarget = $storageTarget
    pageFile = [ordered]@{
        automaticManaged = $automaticManagedPagefile
        settings = $pageFileSettings
        usage = $pageFiles
        totalConfiguredInitialGB = [math]::Round($pageFileInitialMB / 1024,2)
        totalConfiguredMaximumGB = [math]::Round($pageFileMaximumMB / 1024,2)
        totalAllocatedGB = [math]::Round($pageFileAllocatedMB / 1024,2)
        totalCurrentUsageGB = [math]::Round($pageFileCurrentMB / 1024,2)
        totalPeakUsageGB = [math]::Round($pageFilePeakMB / 1024,2)
        committedGB = if ($memoryPerformance) { [math]::Round($memoryPerformance.CommittedBytes / 1GB,2) } else { $null }
        commitLimitGB = if ($memoryPerformance) { [math]::Round($memoryPerformance.CommitLimit / 1GB,2) } else { $null }
        percentCommitted = if ($memoryPerformance) { [int]$memoryPerformance.PercentCommittedBytesInUse } else { $null }
        availableMemoryGB = if ($memoryPerformance) { [math]::Round($memoryPerformance.AvailableMBytes / 1024,2) } else { $null }
    }
    pageFiles = $pageFiles
    tools = [ordered]@{
        git = (Invoke-Safely { (Get-Command git.exe -ErrorAction Stop).Source })
        winget = (Invoke-Safely { (Get-Command winget.exe -ErrorAction Stop).Source })
        python = $pythons
        vcvars64 = @($vcvarsCandidates | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ })
    }
    wsl = [ordered]@{
        commandAvailable = [bool]$wslCommand
        featureState = $wslFeature
        virtualMachinePlatformState = $vmPlatformFeature
        statusText = $wslStatus
        distributions = $wslDistributions
    }
    comfyUI = [ordered]@{
        roots = @($roots | Select-Object -Unique)
        port = $port
        listeners = $listeners
        apiHealthy = $apiHealthy
        systemStats = $apiSystem
    }
    securityProducts = $securityProducts
    notes = @(
        'This inventory does not decide official ROCm support. Compare the exact values with AMD current Windows compatibility matrix.',
        'PyTorch ROCm uses the torch.cuda namespace; verify torch.version.hip and the AMD device name.'
    )
}

$json = $report | ConvertTo-Json -Depth 12
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
}
$json
