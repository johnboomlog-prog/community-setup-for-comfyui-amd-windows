[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$HostReportPath,
    [ValidateSet('Auto','NativeWindows','WSL','DirectML')][string]$Preference = 'Auto',
    [switch]$AllowDirectMLFallback,
    [string]$CacheDirectory,
    [ValidateRange(0,168)][int]$CacheMaxHours = 6,
    [string]$OutputPath = (Join-Path $PWD 'amd-comfyui-route.json')
)

$ErrorActionPreference = 'Stop'
$nativeMatrix = 'https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/windows/windows_compatibility.html'
$wslMatrix = 'https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/wsl/wsl_compatibility.html'
$directMLDoc = 'https://learn.microsoft.com/windows/ai/directml/pytorch-windows'

if (-not $CacheDirectory) { $CacheDirectory = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($HostReportPath))) '.amd-comfyui-matrix-cache' }
function Get-OfficialText([string]$Uri, [string]$CacheName) {
    $cache = Join-Path $CacheDirectory $CacheName
    if (Test-Path -LiteralPath $cache) {
        $age = (Get-Date) - (Get-Item -LiteralPath $cache).LastWriteTime
        if ($age.TotalHours -le $CacheMaxHours) { return Get-Content -LiteralPath $cache -Raw -Encoding UTF8 }
    }
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'AMD-ComfyUI-Skill/1.0' }
    $plain = [Net.WebUtility]::HtmlDecode(([regex]::Replace([string]$response.Content,'<[^>]+>','')))
    New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($cache),$plain,[Text.UTF8Encoding]::new($false))
    $plain
}
function Get-GpuKey([string]$Name) {
    if ($Name -match '(RX\s+\d{4}\s*(?:XTX|XT|GRE)?)') { return $Matches[1] }
    if ($Name -match '(PRO\s+W\d{4}(?:\s+Dual Slot|\s+48GB)?)') { return $Matches[1] }
    if ($Name -match '(R\d{4}[A-Z]*)') { return $Matches[1] }
    ($Name -replace '^.*?Radeon\s*','').Trim()
}

$hostReport = Get-Content -LiteralPath $HostReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$gpu = @($hostReport.gpu | Where-Object { $_.amdCandidate }) | Select-Object -First 1
if (-not $gpu -and $hostReport.comfyUI.systemStats.devices) {
    $gpu = @($hostReport.comfyUI.systemStats.devices | Where-Object { $_.name -match 'AMD|Radeon' }) | Select-Object -First 1
}
if (-not $gpu) { throw 'No AMD Radeon GPU is present in the host report.' }
$gpuKey = Get-GpuKey ([string]$gpu.name)
$nativeText = Get-OfficialText $nativeMatrix 'native-windows-matrix.txt'
$wslText = Get-OfficialText $wslMatrix 'wsl-matrix.txt'
$nativeGpu = [bool]($gpuKey -and $nativeText -match [regex]::Escape($gpuKey))
$wslGpu = [bool]($gpuKey -and $wslText -match [regex]::Escape($gpuKey))
$build = [int]$hostReport.os.build
$isWindows11 = $build -ge 22000
$nativeCandidate = $nativeGpu -and $isWindows11 -and $hostReport.os.architecture -match '64|AMD64|x86-64'
$wslInstalled = [bool]($hostReport.wsl.commandAvailable -and (@($hostReport.wsl.distributions).Count -gt 0 -or $hostReport.wsl.statusText))
$wslCandidate = $wslGpu -and $isWindows11
$directMLCandidate = $build -ge 16299

$selected = $null
$confidence = 'automatic-with-agent-review'
$reason = $null
switch ($Preference) {
    'NativeWindows' {
        if ($nativeCandidate) { $selected = 'windows-native-rocm'; $reason = 'Exact GPU appears in AMD Windows matrix and the host is 64-bit Windows 11.' }
        else { $selected = 'blocked'; $reason = 'Requested native Windows ROCm route does not pass the current matrix and OS gates.' }
    }
    'WSL' {
        if ($wslCandidate) { $selected = if ($wslInstalled) { 'wsl-rocm' } else { 'wsl-rocm-setup-required' }; $reason = 'Exact GPU appears in AMD WSL matrix.' }
        else { $selected = 'blocked'; $reason = 'Requested WSL ROCm route does not pass the current matrix and OS gates.' }
    }
    'DirectML' {
        if ($AllowDirectMLFallback -and $directMLCandidate) { $selected = 'windows-directml-experimental'; $confidence = 'explicit-user-fallback'; $reason = 'User explicitly allowed the lower-compatibility DirectML fallback.' }
        else { $selected = 'blocked'; $reason = 'DirectML requires explicit -AllowDirectMLFallback and a supported Windows build.' }
    }
    default {
        if ($nativeCandidate) { $selected = 'windows-native-rocm'; $reason = 'Preferred route: exact GPU appears in AMD native Windows matrix.' }
        elseif ($wslCandidate) { $selected = if ($wslInstalled) { 'wsl-rocm' } else { 'wsl-rocm-setup-required' }; $reason = 'Native Windows ROCm is not eligible; exact GPU appears in AMD WSL matrix.' }
        elseif ($AllowDirectMLFallback -and $directMLCandidate) { $selected = 'windows-directml-experimental'; $confidence = 'explicit-user-fallback'; $reason = 'No official ROCm route matched; user allowed DirectML.' }
        else { $selected = 'blocked'; $confidence = 'high'; $reason = 'No official ROCm route matched and no experimental fallback was authorized.' }
    }
}

$route = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString('o')
    hostReport = [IO.Path]::GetFullPath($HostReportPath)
    preference = $Preference
    selectedRoute = $selected
    confidence = $confidence
    reason = $reason
    gpu = [ordered]@{ name = $gpu.name; key = $gpuKey; nativeWindowsMatrixMatch = $nativeGpu; wslMatrixMatch = $wslGpu }
    host = [ordered]@{ windowsBuild = $build; windows11 = $isWindows11; architecture = $hostReport.os.architecture; wslInstalled = $wslInstalled; wslDistributions = @($hostReport.wsl.distributions) }
    evidence = [ordered]@{ nativeWindowsMatrix = $nativeMatrix; wslMatrix = $wslMatrix; directML = $directMLDoc }
    matrixCache = [ordered]@{ directory = [IO.Path]::GetFullPath($CacheDirectory); maxAgeHours = $CacheMaxHours }
    requiresAgentReview = $true
    nextAction = switch -Wildcard ($selected) {
        'windows-native-rocm' { 'Generate a native Windows ROCm plan with new-official-plan.ps1.' }
        'wsl-rocm*' { 'Follow references/route-wsl-rocm.md; do not run the native Windows bootstrap.' }
        'windows-directml-experimental' { 'Follow references/route-directml.md and require a model-specific smoke test.' }
        default { 'Stop deployment and explain the failed compatibility gates.' }
    }
}
$json = $route | ConvertTo-Json -Depth 10
$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),$json,[Text.UTF8Encoding]::new($false))
$json
if ($selected -eq 'blocked') { exit 2 }
