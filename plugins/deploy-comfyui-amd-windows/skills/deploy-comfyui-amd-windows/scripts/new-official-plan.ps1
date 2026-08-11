[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RoutePath,
    [Parameter(Mandatory)][string]$InstallRoot,
    [ValidateRange(1024,65535)][int]$Port = 8188,
    [ValidateSet('StarterImage','ImageProduction','VideoProduction','Custom')][string]$WorkloadProfile = 'StarterImage',
    [ValidateRange(0,4096)][int]$AdditionalReserveGB = 0,
    [string]$OutputPath = (Join-Path $PWD 'amd-comfyui-install-plan.json')
)

$ErrorActionPreference = 'Stop'
$pytorchDoc = 'https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installryz/windows/install-pytorch.html'
$compatDoc = 'https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/windows/windows_compatibility.html'
$comfyRepo = 'https://github.com/comfyanonymous/ComfyUI.git'
$starterModel = 'https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors'

function Get-WebText([string]$Uri) {
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Headers @{ 'User-Agent' = 'AMD-ComfyUI-Skill/1.0' }
    $withoutTags = [regex]::Replace([string]$response.Content, '<[^>]+>', '')
    [Net.WebUtility]::HtmlDecode($withoutTags)
}
function Get-RemoteSize([string]$Uri) {
    try {
        $response = Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 20 -Headers @{ 'User-Agent' = 'AMD-ComfyUI-Skill/1.0' }
        if ($response.Headers['Content-Length']) { return [int64]$response.Headers['Content-Length'] }
    } catch {}
    $null
}

$route = Get-Content -LiteralPath $RoutePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($route.schemaVersion -ne 1) { throw 'Unsupported route schema.' }
if ($route.selectedRoute -ne 'windows-native-rocm') { throw "This plan generator only accepts windows-native-rocm, but the selected route is $($route.selectedRoute)." }
if (-not $route.gpu.nativeWindowsMatrixMatch) { throw 'Route lacks an official native Windows GPU matrix match.' }
$gpu = [pscustomobject]@{ Name = $route.gpu.name; PNPDeviceID = $null; DriverVersion = $null }

$installHtml = Get-WebText $pytorchDoc
$compatHtml = Get-WebText $compatDoc
$urls = @([regex]::Matches($installHtml, 'https://repo\.radeon\.com/[^\s"''<>]+?(?:\.whl|\.tar\.gz)', 'IgnoreCase') |
    ForEach-Object { $_.Value.TrimEnd('.',',',';',')') } | Select-Object -Unique)
$sdkUrls = @($urls | Where-Object { $_ -match '/rocm_sdk_[^/]+\.whl$|/rocm-[^/]+\.tar\.gz$' })
$torchUrls = @($urls | Where-Object { $_ -match '/torch(?:-|vision|audio)[^/]+\.whl$' })
if ($sdkUrls.Count -lt 1 -or ($torchUrls | Where-Object { $_ -match '/torch-' }).Count -ne 1 -or
    ($torchUrls | Where-Object { $_ -match '/torchvision-' }).Count -ne 1 -or
    ($torchUrls | Where-Object { $_ -match '/torchaudio-' }).Count -ne 1) {
    throw 'Could not deterministically resolve the official ROCm SDK and PyTorch artifacts. AMD documentation may have changed; inspect it manually.'
}

$pythonVersion = if ($installHtml -match 'Python\s+(3\.\d+)') { $Matches[1] } else { $null }
$driverVersion = if ($installHtml -match '(\d+\.\d+\.\d+)\s+graphics driver') { $Matches[1] } else { $null }
$gpuKey = if ($gpu.Name -match '(RX\s+\d{4}\s*(?:XTX|XT|GRE)?)') { $Matches[1] } else { ($gpu.Name -replace '^.*?Radeon\s*','').Trim() }
$compatibilityMatched = [bool]($gpuKey -and $compatHtml -match [regex]::Escape($gpuKey))

$commit = $null
try {
    $head = Invoke-RestMethod 'https://api.github.com/repos/comfyanonymous/ComfyUI/commits?per_page=1' -Headers @{ 'User-Agent' = 'AMD-ComfyUI-Skill/1.0' }
    $commit = @($head)[0].sha
} catch {}
if (-not $commit -or $commit -notmatch '^[a-f0-9]{40}$') { throw 'Could not resolve the current official ComfyUI commit.' }

$hostReport = Get-Content -LiteralPath ([string]$route.hostReport) -Raw -Encoding UTF8 | ConvertFrom-Json
$installFull = [IO.Path]::GetFullPath($InstallRoot)
$targetDrive = [IO.Path]::GetPathRoot($installFull).TrimEnd('\')
$targetDisk = @($hostReport.disks | Where-Object { ([string]$_.root).TrimEnd('\') -ieq $targetDrive -or ([string]$_.device).TrimEnd('\') -ieq $targetDrive }) | Select-Object -First 1
$artifactSizes = @()
foreach ($artifact in @(($sdkUrls + $torchUrls + $starterModel) | Select-Object -Unique)) {
    $artifactSizes += [pscustomobject][ordered]@{ source = $artifact; bytes = Get-RemoteSize $artifact }
}
$knownBytes = [int64]0
foreach ($item in $artifactSizes) { if ($item.bytes -ne $null) { $knownBytes += [int64]$item.bytes } }
$unknownCount = @($artifactSizes | Where-Object { $_.bytes -eq $null }).Count
$profileReserveGB = switch ($WorkloadProfile) {
    'StarterImage' { 30 }
    'ImageProduction' { 100 }
    'VideoProduction' { 300 }
    'Custom' { if ($AdditionalReserveGB -lt 1) { throw 'Custom workload requires -AdditionalReserveGB.' }; $AdditionalReserveGB }
}
if ($WorkloadProfile -ne 'Custom') { $profileReserveGB += $AdditionalReserveGB }
$estimatedExpansionBytes = [int64]([math]::Ceiling($knownBytes * 2.5))
$uncertaintyBytes = if ($unknownCount -gt 0) { [int64](20GB) } else { [int64]0 }
$minimumRequiredBytes = [int64]($estimatedExpansionBytes + ($profileReserveGB * 1GB) + 20GB + $uncertaintyBytes)
$recommendedFloorGB = switch ($WorkloadProfile) {
    'StarterImage' { 120 }
    'ImageProduction' { 250 }
    'VideoProduction' { 600 }
    'Custom' { 0 }
}
$idealFloorGB = switch ($WorkloadProfile) {
    'StarterImage' { 200 }
    'ImageProduction' { 500 }
    'VideoProduction' { 1000 }
    'Custom' { 0 }
}
$minimumGB = [double]($minimumRequiredBytes / 1GB)
$recommendedCalculatedGB = [math]::Ceiling(($minimumGB * 1.5) / 10) * 10
$recommendedFreeGB = [double][math]::Max($recommendedFloorGB, $recommendedCalculatedGB)
$idealCalculatedGB = [math]::Ceiling(($recommendedFreeGB * 1.5) / 10) * 10
$idealFreeGB = [double][math]::Max($idealFloorGB, $idealCalculatedGB)
$recommendedFreeBytes = [int64]($recommendedFreeGB * 1GB)
$idealFreeBytes = [int64]($idealFreeGB * 1GB)
$targetFreeBytes = if ($targetDisk -and $targetDisk.freeBytes -ne $null) { [int64]$targetDisk.freeBytes } else { $null }
$fileSystem = if ($targetDisk) { [string]$targetDisk.fileSystem } else { $null }
$fileSystemSupported = $fileSystem -in @('NTFS','ReFS')
$spaceSufficient = $targetFreeBytes -ne $null -and $targetFreeBytes -ge $minimumRequiredBytes
$recommendedSpaceAvailable = $targetFreeBytes -ne $null -and $targetFreeBytes -ge $recommendedFreeBytes
$spaceLevel = if (-not $fileSystemSupported -or -not $spaceSufficient) { 'blocked' } elseif (-not $recommendedSpaceAvailable) { 'minimum-only' } elseif ($targetFreeBytes -lt $idealFreeBytes) { 'recommended' } else { 'ideal' }
$alternatives = @($hostReport.disks | Where-Object { $_.freeBytes -ne $null -and $_.fileSystem -in @('NTFS','ReFS') } | Sort-Object -Property freeBytes -Descending | ForEach-Object {
    $free = [int64]$_.freeBytes
    $level = if ($free -lt $minimumRequiredBytes) { 'blocked' } elseif ($free -lt $recommendedFreeBytes) { 'minimum-only' } elseif ($free -lt $idealFreeBytes) { 'recommended' } else { 'ideal' }
    [ordered]@{ root=$_.root; fileSystem=$_.fileSystem; freeGB=$_.freeGB; meetsHardMinimum=($free -ge $minimumRequiredBytes); meetsRecommended=($free -ge $recommendedFreeBytes); spaceLevel=$level }
})

function Round-Up8GB([double]$Value) { [int]([math]::Ceiling($Value / 8) * 8) }
$ramGB = if ($hostReport.computer.ramGB) { [double]$hostReport.computer.ramGB } else { 32.0 }
$pageFileMinimumGB = switch ($WorkloadProfile) {
    'StarterImage' { Round-Up8GB ([math]::Max(16, $ramGB * 0.5)) }
    'ImageProduction' { Round-Up8GB ([math]::Max(32, $ramGB)) }
    'VideoProduction' { Round-Up8GB ([math]::Max(64, $ramGB * 1.5)) }
    'Custom' { Round-Up8GB ([math]::Max(16, $ramGB * 0.5)) }
}
$pageFileRecommendedGB = switch ($WorkloadProfile) {
    'StarterImage' { Round-Up8GB ([math]::Max(32, $ramGB)) }
    'ImageProduction' { Round-Up8GB ([math]::Max(64, $ramGB * 1.5)) }
    'VideoProduction' { Round-Up8GB ([math]::Max(96, $ramGB * 2)) }
    'Custom' { Round-Up8GB ([math]::Max(32, $ramGB)) }
}
$pageFileUpperGB = switch ($WorkloadProfile) {
    'StarterImage' { Round-Up8GB ([math]::Max(64, $ramGB * 1.5)) }
    'ImageProduction' { Round-Up8GB ([math]::Max(96, $ramGB * 2)) }
    'VideoProduction' { Round-Up8GB ([math]::Max(128, $ramGB * 3)) }
    'Custom' { Round-Up8GB ([math]::Max(64, $ramGB * 1.5)) }
}
$pageFileInfo = $hostReport.pageFile
if (-not $pageFileInfo -and $hostReport.pageFiles) {
    $legacyAllocated = (($hostReport.pageFiles | Measure-Object allocatedMB -Sum).Sum)
    $pageFileInfo = [pscustomobject]@{ automaticManaged=$null; settings=@(); usage=$hostReport.pageFiles; totalConfiguredMaximumGB=0; totalAllocatedGB=[math]::Round($legacyAllocated/1024,2); commitLimitGB=$null; committedGB=$null; percentCommitted=$null }
}
$configuredPageFileGB = if ($pageFileInfo.totalConfiguredMaximumGB) { [double]$pageFileInfo.totalConfiguredMaximumGB } elseif ($pageFileInfo.totalAllocatedGB) { [double]$pageFileInfo.totalAllocatedGB } else { 0 }
$pageFileStatus = if ($pageFileInfo.automaticManaged -eq $true) { 'system-managed' } elseif ($configuredPageFileGB -ge $pageFileRecommendedGB) { 'recommended' } elseif ($configuredPageFileGB -ge $pageFileMinimumGB) { 'minimum-only' } else { 'insufficient' }
$pageFileCandidates = @($hostReport.disks | Where-Object { $_.freeBytes -ne $null -and $_.fileSystem -in @('NTFS','ReFS') } | Sort-Object freeBytes -Descending | ForEach-Object {
    $drive = ([string]$_.root).TrimEnd('\')
    $existingOnDriveMB = 0
    if ($pageFileInfo -and $pageFileInfo.settings) {
        $existingOnDriveMB = (($pageFileInfo.settings | Where-Object { ([IO.Path]::GetPathRoot([string]$_.name)).TrimEnd('\') -ieq $drive } | Measure-Object maximumMB -Sum).Sum)
    }
    $additionalBytes = [int64]([math]::Max([double]0, [double](($pageFileRecommendedGB * 1GB) - ($existingOnDriveMB * 1MB))))
    [ordered]@{
        root=$_.root; fileSystem=$_.fileSystem; freeGB=$_.freeGB
        existingConfiguredMaximumGB=[math]::Round($existingOnDriveMB/1024,2)
        additionalRequiredForRecommendedGB=[math]::Round($additionalBytes/1GB,2)
        canHostRecommended=[bool]([int64]$_.freeBytes -ge ($additionalBytes + 20GB))
    }
})

$plan = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    route = [ordered]@{ source = [IO.Path]::GetFullPath($RoutePath); selectedRoute = $route.selectedRoute; gpuKey = $route.gpu.key }
    installRoot = $installFull
    port = $Port
    gpu = [ordered]@{ name = $gpu.Name; pnpDeviceId = $gpu.PNPDeviceID; driverVersion = $gpu.DriverVersion; compatibilitySearchKey = $gpuKey }
    compatibility = [ordered]@{
        matchedInOfficialPage = $compatibilityMatched
        requiresAgentReview = $true
        requiredPython = $pythonVersion
        requiredAdrenalinDriver = $driverVersion
        source = $compatDoc
    }
    prerequisites = [ordered]@{
        wingetPackages = @('Python.Python.3.12','Git.Git','Microsoft.VCRedist.2015+.x64')
        optionalBuildTools = 'Microsoft.VisualStudio.2022.BuildTools'
    }
    rocm = [ordered]@{ source = $pytorchDoc; sdkArtifacts = $sdkUrls; torchArtifacts = $torchUrls }
    comfyUI = [ordered]@{ repository = $comfyRepo; commit = $commit }
    starterProfile = [ordered]@{
        name = 'sdxl-turbo-official-amd-guide'
        requiredForUserReady = $true
        source = 'https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/advanced/advancedryz/windows/comfyui/installcomfyui.html'
        models = @([ordered]@{
            source = $starterModel
            relativePath = 'models/checkpoints/sd_xl_turbo_1.0_fp16.safetensors'
            initialHost = 'huggingface.co'
        })
        workflowAsset = 'assets/starter-sdxl-turbo.api.json'
    }
    storage = [ordered]@{
        workloadProfile = $WorkloadProfile
        targetDrive = $targetDrive
        targetFileSystem = $fileSystem
        targetFreeBytes = $targetFreeBytes
        targetFreeGB = if ($targetFreeBytes -ne $null) { [math]::Round($targetFreeBytes / 1GB,2) } else { $null }
        artifactSizes = $artifactSizes
        knownDownloadBytes = $knownBytes
        knownDownloadGB = [math]::Round($knownBytes / 1GB,2)
        unknownArtifactCount = $unknownCount
        profileReserveGB = $profileReserveGB
        safetyMarginGB = 20
        hardMinimumBytes = $minimumRequiredBytes
        hardMinimumGB = [math]::Round($minimumRequiredBytes / 1GB,2)
        estimatedPeakBytes = $minimumRequiredBytes
        estimatedPeakGB = [math]::Round($minimumRequiredBytes / 1GB,2)
        recommendedFreeBytes = $recommendedFreeBytes
        recommendedFreeGB = $recommendedFreeGB
        idealFreeBytes = $idealFreeBytes
        idealFreeGB = $idealFreeGB
        fileSystemSupported = $fileSystemSupported
        spaceSufficient = $spaceSufficient
        recommendedSpaceAvailable = $recommendedSpaceAvailable
        spaceLevel = $spaceLevel
        alternativeTargets = $alternatives
    }
    pageFile = [ordered]@{
        purpose = 'Extend the Windows commit limit for RAM-heavy model loading, VAE, upscaling, video frames, and concurrent applications; it is a safety backstop, not a substitute for RAM.'
        officialGuidance = 'Microsoft states that sizing is workload-specific and depends on peak commit charge and crash-dump requirements; system-managed is the default recommendation, especially above 32 GB RAM.'
        source = 'https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows'
        workloadProfile = $WorkloadProfile
        ramGB = [math]::Round($ramGB,2)
        preferredMode = 'SystemManaged'
        customRange = [ordered]@{ minimumGB=$pageFileMinimumGB; recommendedGB=$pageFileRecommendedGB; maximumRecommendedGB=$pageFileUpperGB }
        current = $pageFileInfo
        currentConfiguredMaximumGB = $configuredPageFileGB
        status = $pageFileStatus
        requiresUserChoice = [bool]($pageFileStatus -in @('insufficient','minimum-only'))
        targetCandidates = $pageFileCandidates
        rules = @(
            'Explain commit-limit and disk-space tradeoffs before asking for a choice.',
            'Prefer Windows system-managed unless the user needs a predictable fixed reservation.',
            'For a custom size, require a value inside customRange and prefer recommendedGB.',
            'Use NTFS/ReFS on a fast SSD/NVMe with sufficient free space; keep crash-dump requirements in mind.',
            'Apply only with explicit approval and administrator rights, reboot, then regenerate the host report and plan.'
        )
    }
    trust = [ordered]@{
        artifactDomainAllowList = @('repo.radeon.com','huggingface.co')
        publisherDoesNotExposeHashesInInstallPage = $true
        action = 'Download from the recorded HTTPS origin, then record local SHA-256 before installation.'
    }
}
$json = $plan | ConvertTo-Json -Depth 10
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
$json
if (-not $compatibilityMatched) { exit 2 }
if (-not $fileSystemSupported -or -not $spaceSufficient) { exit 3 }
