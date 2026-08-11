[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [string[]]$RequiredNode = @(),
    [int]$TimeoutSec = 10,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$RequiredNode = @($RequiredNode | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$base = $BaseUrl.TrimEnd('/')
$report = [ordered]@{ baseUrl = $base; generatedAt = (Get-Date).ToString('o'); passed = $false }
try {
    $system = Invoke-RestMethod "$base/system_stats" -TimeoutSec $TimeoutSec
    $queue = Invoke-RestMethod "$base/queue" -TimeoutSec $TimeoutSec
    $objects = Invoke-RestMethod "$base/object_info" -TimeoutSec $TimeoutSec
    $available = @($objects.PSObject.Properties.Name)
    $missing = @($RequiredNode | Where-Object { $_ -notin $available })
    $report.systemStats = $system
    $report.queueRunning = @($queue.queue_running).Count
    $report.queuePending = @($queue.queue_pending).Count
    $report.nodeCount = $available.Count
    $report.requiredNodes = @($RequiredNode)
    $report.missingNodes = $missing
    $report.passed = ($missing.Count -eq 0)
} catch {
    $report.error = $_.Exception.Message
}
$json = $report | ConvertTo-Json -Depth 12
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
}
$json
if (-not $report.passed) { exit 1 }
