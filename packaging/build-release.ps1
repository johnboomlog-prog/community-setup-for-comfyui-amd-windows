[CmdletBinding()]
param(
    [string]$Version = '0.2.0',
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pluginRoot = Join-Path $repoRoot 'plugins\deploy-comfyui-amd-windows'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'dist' }
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$workRoot = Join-Path $outputRoot 'build'
$payloadRoot = Join-Path $workRoot 'payload'
$payloadZip = Join-Path $workRoot 'community-setup-payload.zip'
$sourcePath = Join-Path $workRoot 'Launcher.generated.cs'
$exePath = Join-Path $outputRoot 'Community-Setup-for-ComfyUI-AMD-Windows.exe'
$portableRoot = Join-Path $workRoot 'Community-Setup-for-ComfyUI-AMD-Windows'
$portableZip = Join-Path $outputRoot 'Community-Setup-for-ComfyUI-AMD-Windows-portable.zip'
$checksumPath = Join-Path $outputRoot 'SHA256SUMS.txt'

if (-not (Test-Path -LiteralPath $pluginRoot -PathType Container)) {
    throw "Plugin root not found: $pluginRoot"
}

if (Test-Path -LiteralPath $outputRoot) {
    Remove-Item -LiteralPath $outputRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $pluginRoot 'launcher') -Destination $payloadRoot -Recurse
$skillDestination = Join-Path $payloadRoot 'skills\deploy-comfyui-amd-windows'
New-Item -ItemType Directory -Path $skillDestination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $pluginRoot 'skills\deploy-comfyui-amd-windows\scripts') -Destination $skillDestination -Recurse
Copy-Item -LiteralPath (Join-Path $pluginRoot 'skills\deploy-comfyui-amd-windows\assets') -Destination $skillDestination -Recurse

Compress-Archive -Path (Join-Path $payloadRoot '*') -DestinationPath $payloadZip -CompressionLevel Optimal

$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Launcher.cs') -Raw -Encoding UTF8
$source = $source.Replace('__RELEASE_VERSION__', $Version)
[IO.File]::WriteAllText($sourcePath, $source, [Text.UTF8Encoding]::new($false))

$frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
if (-not (Test-Path -LiteralPath (Join-Path $frameworkRoot 'csc.exe'))) {
    $frameworkRoot = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319'
}
$compiler = Join-Path $frameworkRoot 'csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The built-in .NET Framework C# compiler was not found.'
}

$iconPath = Join-Path $pluginRoot 'launcher\assets\community-wizard.ico'
& $compiler /nologo /target:winexe /optimize+ "/out:$exePath" "/win32icon:$iconPath" "/resource:$payloadZip,community_setup_payload.zip" /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll $sourcePath
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exePath)) {
    throw "EXE compilation failed with exit code $LASTEXITCODE."
}

New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $pluginRoot 'launcher') -Destination $portableRoot -Recurse
Copy-Item -LiteralPath (Join-Path $pluginRoot 'skills') -Destination $portableRoot -Recurse
Compress-Archive -Path (Join-Path $portableRoot '*') -DestinationPath $portableZip -CompressionLevel Optimal

$hashLines = foreach ($file in @($exePath, $portableZip)) {
    $hash = Get-FileHash -LiteralPath $file -Algorithm SHA256
    '{0}  {1}' -f $hash.Hash.ToLowerInvariant(), (Split-Path -Leaf $file)
}
[IO.File]::WriteAllLines($checksumPath, $hashLines, [Text.UTF8Encoding]::new($false))

Remove-Item -LiteralPath $workRoot -Recurse -Force
Write-Host "Built: $exePath"
Write-Host "Built: $portableZip"
Write-Host "Checksums: $checksumPath"
