[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PythonPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw "Python executable not found: $PythonPath" }

$code = @'
import json, platform, traceback
r = {"python": platform.python_version(), "passed": False}
try:
    import torch
    r.update({
        "torch": torch.__version__,
        "hip": getattr(torch.version, "hip", None),
        "cuda_api_available": bool(torch.cuda.is_available()),
        "device_count": int(torch.cuda.device_count()) if torch.cuda.is_available() else 0,
    })
    names = [torch.cuda.get_device_name(i) for i in range(r["device_count"])]
    r["device_names"] = names
    r["amd_device"] = any(("AMD" in n.upper() or "RADEON" in n.upper()) for n in names)
    if r["hip"] and r["cuda_api_available"] and r["amd_device"]:
        a = torch.randn((256, 256), device="cuda")
        b = a @ a
        torch.cuda.synchronize()
        r["smoke_sum"] = float(b.abs().sum().item())
        r["passed"] = True
except Exception as e:
    r["error"] = str(e)
    r["traceback"] = traceback.format_exc()
print(json.dumps(r, ensure_ascii=False))
'@

$probePath = Join-Path ([IO.Path]::GetTempPath()) ("comfyui-rocm-probe-{0}.py" -f [guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllText($probePath, $code, [Text.UTF8Encoding]::new($false))
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = & $PythonPath $probePath 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
} finally {
    if (Test-Path -LiteralPath $probePath) { Remove-Item -LiteralPath $probePath -Force }
}
$line = @($raw) | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
if (-not $line) { throw "PyTorch probe produced no JSON (exit $exitCode): $($raw -join [Environment]::NewLine)" }
$result = $line | ConvertFrom-Json
$json = $result | ConvertTo-Json -Depth 8
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
}
$json
if ($exitCode -ne 0 -or -not $result.passed) { exit 1 }
