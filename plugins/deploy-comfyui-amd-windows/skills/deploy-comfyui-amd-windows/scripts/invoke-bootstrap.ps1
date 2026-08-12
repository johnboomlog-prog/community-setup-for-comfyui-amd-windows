[CmdletBinding(SupportsShouldProcess, ConfirmImpact='Medium')]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [string]$PythonPath,
    [switch]$InstallPrerequisites,
    [switch]$InstallBuildTools,
    [switch]$SkipStarterProfile,
    [switch]$AllowBelowRecommendedSpace,
    [switch]$AllowBelowRecommendedPageFile,
    [Parameter(Mandatory)][switch]$ConfirmSupportedGpu,
    [Parameter(Mandatory)][switch]$DriverReady,
    [int]$ApiTimeoutSec = 240
)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($plan.schemaVersion -ne 1) { throw 'Unsupported deployment-plan schema.' }
if ($plan.route.selectedRoute -ne 'windows-native-rocm') { throw 'invoke-bootstrap.ps1 only executes a reviewed windows-native-rocm plan.' }
if (-not $plan.storage.fileSystemSupported) { throw "Target filesystem is not approved for a Python environment and large models: $($plan.storage.targetFileSystem)" }
if (-not $plan.storage.spaceSufficient) { throw "The plan reports insufficient free space. Required $($plan.storage.estimatedPeakGB) GB; planned free $($plan.storage.targetFreeGB) GB." }
if ($plan.pageFile.status -eq 'insufficient') { throw "The page file is below the workload minimum of $($plan.pageFile.customRange.minimumGB) GB. Configure it, reboot, and regenerate the plan before deployment." }
if ($plan.pageFile.status -eq 'minimum-only' -and -not $AllowBelowRecommendedPageFile) { throw "The page file meets only the minimum. Recommended $($plan.pageFile.customRange.recommendedGB) GB for $($plan.pageFile.workloadProfile). Obtain explicit user approval or configure it, reboot, and regenerate the plan." }
if (-not $plan.compatibility.matchedInOfficialPage -or -not $ConfirmSupportedGpu) { throw 'GPU support gate failed. An agent must review the current official matrix and pass -ConfirmSupportedGpu.' }
if (-not $DriverReady) { throw "Install the required AMD graphics driver ($($plan.compatibility.requiredAdrenalinDriver) in this plan), reboot, then rerun with -DriverReady." }

$root = [IO.Path]::GetFullPath([string]$plan.installRoot)
if (Test-Path -LiteralPath $root) {
    if (@(Get-ChildItem -LiteralPath $root -Force).Count -gt 0) { throw "Install root must be new or empty: $root" }
}
$targetDrive = [IO.Path]::GetPathRoot($root)
$liveDrive = [IO.DriveInfo]::new($targetDrive)
if (-not $liveDrive.IsReady) { throw "Target drive is not ready: $targetDrive" }
if ([int64]$liveDrive.AvailableFreeSpace -lt [int64]$plan.storage.estimatedPeakBytes) {
    throw "Free space changed after planning. Required $($plan.storage.estimatedPeakGB) GB; now available $([math]::Round($liveDrive.AvailableFreeSpace/1GB,2)) GB."
}
if ($plan.storage.recommendedFreeBytes -and [int64]$liveDrive.AvailableFreeSpace -lt [int64]$plan.storage.recommendedFreeBytes -and -not $AllowBelowRecommendedSpace) {
    throw "Free space meets the hard minimum but is below the recommended level. Hard minimum $($plan.storage.hardMinimumGB) GB; recommended $($plan.storage.recommendedFreeGB) GB; now available $([math]::Round($liveDrive.AvailableFreeSpace/1GB,2)) GB. Obtain explicit user approval, then rerun with -AllowBelowRecommendedSpace."
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDirectory)
    Write-Host "[RUN] $FilePath $($ArgumentList -join ' ')"
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($WorkingDirectory) { Push-Location $WorkingDirectory }
    try { & $FilePath @ArgumentList; $code = $LASTEXITCODE }
    finally { if ($WorkingDirectory) { Pop-Location }; $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "Command failed with exit code ${code}: $FilePath" }
}

function Resolve-Python312 {
    if ($PythonPath -and (Test-Path -LiteralPath $PythonPath)) { return [IO.Path]::GetFullPath($PythonPath) }
    $py = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($py) {
        $candidate = & $py.Source -3.12 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $candidate) { return ($candidate | Select-Object -Last 1).Trim() }
    }
    $candidates = @()
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += @(
        "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
        "$env:ProgramFiles\Python312\python.exe"
    )
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        $version = & $candidate --version 2>&1
        if ([string]$version -match "Python\s+$([regex]::Escape([string]$plan.compatibility.requiredPython))\.") { return [IO.Path]::GetFullPath($candidate) }
    }
    $null
}

$git = Get-Command git.exe -ErrorAction SilentlyContinue
$python = Resolve-Python312
if ((-not $git -or -not $python) -and -not $InstallPrerequisites) {
    throw 'Python/Git prerequisites are missing. Review the plan, then rerun with -InstallPrerequisites or install them manually.'
}
if ($InstallPrerequisites -and (-not $git -or -not $python)) {
    $winget = (Get-Command winget.exe -ErrorAction Stop).Source
    foreach ($id in @($plan.prerequisites.wingetPackages)) {
        if ($PSCmdlet.ShouldProcess($id, 'Install prerequisite with winget')) {
            Invoke-Checked $winget @('install','--id',$id,'--exact','--accept-package-agreements','--accept-source-agreements','--silent') $null
        }
    }
    if ($InstallBuildTools -and $PSCmdlet.ShouldProcess($plan.prerequisites.optionalBuildTools, 'Install Visual Studio C++ Build Tools')) {
        Invoke-Checked $winget @('install','--id',$plan.prerequisites.optionalBuildTools,'--exact','--accept-package-agreements','--accept-source-agreements','--silent','--override','--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended') $null
    }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $git -and (Test-Path "$env:ProgramFiles\Git\cmd\git.exe")) { $git = Get-Item "$env:ProgramFiles\Git\cmd\git.exe" }
    $python = Resolve-Python312
}
if (-not $git -or -not $python) { throw 'Prerequisite installation completed but Python 3.12 or Git is not visible. Restart the terminal or reboot, then resume.' }
$gitPath = if ($git.Source) { $git.Source } else { $git.FullName }

$summary = [ordered]@{ whatIf = [bool]$WhatIfPreference; installRoot = $root; python = $python; gpu = $plan.gpu.name; comfyCommit = $plan.comfyUI.commit }
if (-not $PSCmdlet.ShouldProcess($root, 'Deploy a new isolated AMD ROCm ComfyUI environment')) { $summary | ConvertTo-Json; return }

$downloads = Join-Path $root 'downloads'
$venv = Join-Path $root 'python_env'
$venvPython = Join-Path $venv 'Scripts\python.exe'
$comfy = Join-Path $root 'ComfyUI'
New-Item -ItemType Directory -Path $downloads -Force | Out-Null
Invoke-Checked $python @('-m','venv',$venv) $null
Invoke-Checked $venvPython @('-m','pip','install','--upgrade','pip','setuptools','wheel') $null

$manifest = @()
$sdkFiles = @()
$torchFiles = @()
foreach ($group in @('sdkArtifacts','torchArtifacts')) {
    foreach ($urlText in @($plan.rocm.$group)) {
        $uri = [uri]$urlText
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'repo.radeon.com') { throw "Artifact outside allow-list: $urlText" }
        $before = @(Get-ChildItem -LiteralPath $downloads -File | Select-Object -ExpandProperty FullName)
        Invoke-Checked $venvPython @('-m','pip','download','--no-deps','--dest',$downloads,$urlText) $null
        $after = @(Get-ChildItem -LiteralPath $downloads -File | Select-Object -ExpandProperty FullName)
        $file = @($after | Where-Object { $_ -notin $before } | Select-Object -First 1)
        if (-not $file) { throw "Could not identify downloaded artifact for $urlText" }
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        $manifest += [ordered]@{ source = $urlText; file = $file; sha256 = $hash; group = $group }
        if ($group -eq 'sdkArtifacts') { $sdkFiles += $file } else { $torchFiles += $file }
    }
}
[IO.File]::WriteAllText((Join-Path $root 'artifact-manifest.json'), ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Invoke-Checked $venvPython (@('-m','pip','install','--no-cache-dir') + $sdkFiles) $null
Invoke-Checked $venvPython (@('-m','pip','install','--no-cache-dir') + $torchFiles) $null

& (Join-Path $PSScriptRoot 'test-rocm-pytorch.ps1') -PythonPath $venvPython -OutputPath (Join-Path $root 'rocm-test.json')
if ($LASTEXITCODE -ne 0) { throw 'ROCm compute gate failed.' }

Invoke-Checked $gitPath @('clone','--no-checkout',[string]$plan.comfyUI.repository,$comfy) $root
Invoke-Checked $gitPath @('-C',$comfy,'checkout','--detach',[string]$plan.comfyUI.commit) $root
Invoke-Checked $venvPython @('-m','pip','install','-r',(Join-Path $comfy 'requirements.txt')) $null
& (Join-Path $PSScriptRoot 'test-rocm-pytorch.ps1') -PythonPath $venvPython -OutputPath (Join-Path $root 'rocm-after-comfy-requirements.json')
if ($LASTEXITCODE -ne 0) { throw 'ComfyUI requirements replaced or broke the ROCm PyTorch environment.' }

if (-not $SkipStarterProfile) {
    foreach ($model in @($plan.starterProfile.models)) {
        $uri = [uri]$model.source
        if ($uri.Scheme -ne 'https' -or $uri.Host -ne [string]$model.initialHost -or $uri.Host -notin @($plan.trust.artifactDomainAllowList)) {
            throw "Starter model source is outside the reviewed allow-list: $($model.source)"
        }
        $modelTarget = [IO.Path]::GetFullPath((Join-Path $comfy ([string]$model.relativePath)))
        if (-not $modelTarget.StartsWith($comfy + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Starter model path escapes ComfyUI root.' }
        New-Item -ItemType Directory -Path (Split-Path -Parent $modelTarget) -Force | Out-Null
        $partial = "$modelTarget.partial"
        try {
            Invoke-WebRequest -Uri $uri -OutFile $partial -UseBasicParsing -Headers @{ 'User-Agent' = 'AMD-ComfyUI-Skill/1.0' }
            $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash
            Move-Item -LiteralPath $partial -Destination $modelTarget
            $manifest += [ordered]@{ source = $uri.AbsoluteUri; file = $modelTarget; sha256 = $hash; group = 'starterModel' }
        } finally {
            if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        }
    }
    [IO.File]::WriteAllText((Join-Path $root 'artifact-manifest.json'), ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}

$launcher = Join-Path $root 'Launch_ComfyUI_AMD_ROCm.cmd'
$shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'ComfyUI AMD ROCm.lnk'
$stopScript = Join-Path $root 'Stop_ComfyUI_AMD_ROCm.ps1'
$stopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Stop ComfyUI AMD ROCm.lnk'
& (Join-Path $PSScriptRoot 'new-desktop-launcher.ps1') -ComfyUIRoot $comfy -PythonPath $venvPython -Port ([int]$plan.port) -LauncherPath $launcher -ShortcutPath $shortcut -StopScriptPath $stopScript -StopShortcutPath $stopShortcut
if ($LASTEXITCODE -ne 0) { throw 'Launcher generation failed.' }

Start-Process -FilePath $launcher -WorkingDirectory $comfy
$deadline = (Get-Date).AddSeconds($ApiTimeoutSec)
$healthy = $false
while ((Get-Date) -lt $deadline) {
    try { Invoke-RestMethod "http://127.0.0.1:$($plan.port)/system_stats" -TimeoutSec 3 | Out-Null; $healthy = $true; break } catch { Start-Sleep -Seconds 2 }
}
if (-not $healthy) { throw "ComfyUI did not become healthy within $ApiTimeoutSec seconds. Inspect the launcher console." }
& (Join-Path $PSScriptRoot 'test-comfyui-api.ps1') -BaseUrl "http://127.0.0.1:$($plan.port)" -RequiredNode @('KSampler','VAEDecode') -OutputPath (Join-Path $root 'comfyui-api-test.json')
if ($LASTEXITCODE -ne 0) { throw 'ComfyUI API gate failed.' }
if (-not $SkipStarterProfile) {
    $workflow = Join-Path $skillRoot ([string]$plan.starterProfile.workflowAsset)
    & (Join-Path $PSScriptRoot 'invoke-workflow-smoke.ps1') -BaseUrl "http://127.0.0.1:$($plan.port)" -WorkflowPath $workflow -OutputPath (Join-Path $root 'starter-workflow-test.json')
    if ($LASTEXITCODE -ne 0) { throw 'Starter image inference gate failed.' }
}

$report = [ordered]@{
    completedAt = (Get-Date).ToString('o')
    passed = $true
    gpu = $plan.gpu
    installRoot = $root
    python = $venvPython
    comfyUIRoot = $comfy
    comfyUICommit = $plan.comfyUI.commit
    launcher = $launcher
    shortcut = $shortcut
    stopScript = $stopScript
    stopShortcut = $stopShortcut
    artifactManifest = (Join-Path $root 'artifact-manifest.json')
    starterProfilePassed = [bool](-not $SkipStarterProfile)
}
[IO.File]::WriteAllText((Join-Path $root 'deployment-report.json'), ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
$report | ConvertTo-Json -Depth 8
