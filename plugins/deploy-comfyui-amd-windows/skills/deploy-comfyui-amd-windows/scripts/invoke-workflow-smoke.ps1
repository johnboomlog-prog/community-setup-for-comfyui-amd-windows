[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [Parameter(Mandatory)][string]$WorkflowPath,
    [ValidateRange(10,3600)][int]$TimeoutSec = 300,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$base = $BaseUrl.TrimEnd('/')
$workflow = Get-Content -LiteralPath $WorkflowPath -Raw -Encoding UTF8 | ConvertFrom-Json
$body = [ordered]@{ prompt = $workflow; client_id = [guid]::NewGuid().ToString('N') } | ConvertTo-Json -Depth 30 -Compress
$result = [ordered]@{ baseUrl = $base; workflow = [IO.Path]::GetFullPath($WorkflowPath); passed = $false; startedAt = (Get-Date).ToString('o') }
try {
    $queued = Invoke-RestMethod "$base/prompt" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 30
    $promptId = [string]$queued.prompt_id
    if (-not $promptId) { throw 'ComfyUI did not return a prompt_id.' }
    $result.promptId = $promptId
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $history = Invoke-RestMethod "$base/history/$promptId" -TimeoutSec 10
        $entry = $history.PSObject.Properties[$promptId].Value
        if ($entry) {
            $status = $entry.status.status_str
            if ($status -eq 'error') { throw "Workflow failed: $($entry.status.messages | ConvertTo-Json -Depth 8 -Compress)" }
            if ($entry.outputs) {
                $result.passed = $true
                $result.completedAt = (Get-Date).ToString('o')
                $result.outputNodes = @($entry.outputs.PSObject.Properties.Name)
                break
            }
        }
        Start-Sleep -Seconds 2
    }
    if (-not $result.passed) { throw "Workflow did not finish within $TimeoutSec seconds." }
} catch {
    $result.error = $_.Exception.Message
}
$json = $result | ConvertTo-Json -Depth 10
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
}
$json
if (-not $result.passed) { exit 1 }

