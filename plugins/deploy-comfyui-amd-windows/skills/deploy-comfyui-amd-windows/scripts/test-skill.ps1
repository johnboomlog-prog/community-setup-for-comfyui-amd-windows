[CmdletBinding()]
param(
    [string]$PythonPath,
    [string]$ComfyUIRoot,
    [string]$BaseUrl = 'http://127.0.0.1:8188',
    [string]$RoutePath,
    [string]$PlanPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("amd-comfyui-skill-test-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check([string]$Name, [bool]$Passed, [object]$Detail) {
    $checks.Add([ordered]@{ name = $Name; passed = $Passed; detail = $Detail })
}

try {
    $skillMd = Get-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Raw -Encoding UTF8
    Add-Check 'skill-frontmatter' ([bool]($skillMd -match '(?s)^---\s*\r?\nname:\s*deploy-comfyui-amd-windows\s*\r?\ndescription:.+?\r?\n---')) 'name and description present'
    $openaiYaml = Get-Content -LiteralPath (Join-Path $skillRoot 'agents\openai.yaml') -Raw -Encoding UTF8
    $interactionPassed = $skillMd.Contains('## User interaction contract') -and $skillMd.Contains('phase 1 is read-only') -and $skillMd.Contains('ask only this first question') -and $openaiYaml.Contains('$deploy-comfyui-amd-windows')
    Add-Check 'guided-user-onboarding' $interactionPassed ([ordered]@{ interactionContract=$skillMd.Contains('## User interaction contract'); explicitInvocation=$openaiYaml.Contains('$deploy-comfyui-amd-windows') })

    $parseFailures = @()
    foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1) {
        $tokens = $null; $errors = $null
        [Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        if ($errors.Count) { $parseFailures += [ordered]@{ script = $script.Name; errors = @($errors.Message) } }
    }
    Add-Check 'powershell-parse' ($parseFailures.Count -eq 0) $parseFailures

    if ($PlanPath) {
        $plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $planPassed = $plan.schemaVersion -eq 1 -and $plan.route.selectedRoute -eq 'windows-native-rocm' -and @($plan.rocm.sdkArtifacts).Count -ge 1 -and @($plan.rocm.torchArtifacts).Count -eq 3 -and $plan.comfyUI.commit -match '^[a-f0-9]{40}$' -and $plan.storage.hardMinimumBytes -gt 0 -and $plan.storage.recommendedFreeBytes -gt $plan.storage.hardMinimumBytes -and $plan.storage.spaceLevel -in @('blocked','minimum-only','recommended','ideal') -and $plan.storage.targetDrive -and $plan.pageFile.customRange.minimumGB -gt 0 -and $plan.pageFile.customRange.recommendedGB -ge $plan.pageFile.customRange.minimumGB -and $plan.pageFile.status -in @('system-managed','recommended','minimum-only','insufficient')
        Add-Check 'official-plan-shape' $planPassed ([ordered]@{ sdk = @($plan.rocm.sdkArtifacts).Count; torch = @($plan.rocm.torchArtifacts).Count; commit = $plan.comfyUI.commit; targetDrive = $plan.storage.targetDrive; hardMinimumGB = $plan.storage.hardMinimumGB; recommendedFreeGB = $plan.storage.recommendedFreeGB; spaceLevel = $plan.storage.spaceLevel; pageFileStatus=$plan.pageFile.status; pageFileRecommendedGB=$plan.pageFile.customRange.recommendedGB })
    }
    if ($RoutePath) {
        $route = Get-Content -LiteralPath $RoutePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $routePassed = $route.schemaVersion -eq 1 -and $route.selectedRoute -in @('windows-native-rocm','wsl-rocm','wsl-rocm-setup-required','windows-directml-experimental','blocked') -and $route.gpu.name
        Add-Check 'deployment-route-shape' ([bool]$routePassed) ([ordered]@{ selected = $route.selectedRoute; gpu = $route.gpu.name; reason = $route.reason })
    }

    if ($PythonPath) {
        $rocmOut = Join-Path $tempRoot 'rocm.json'
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-rocm-pytorch.ps1') -PythonPath $PythonPath -OutputPath $rocmOut | Out-Null
        $code = $LASTEXITCODE
        $rocm = if (Test-Path $rocmOut) { Get-Content $rocmOut -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
        Add-Check 'rocm-compute' ($code -eq 0 -and $rocm.passed) $rocm
    }

    $apiOut = Join-Path $tempRoot 'api.json'
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-comfyui-api.ps1') -BaseUrl $BaseUrl -RequiredNode 'EmptyImage,PreviewImage' -OutputPath $apiOut | Out-Null
    $apiCode = $LASTEXITCODE
    $api = if (Test-Path $apiOut) { Get-Content $apiOut -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
    Add-Check 'comfyui-api' ($apiCode -eq 0 -and $api.passed) $api

    if ($apiCode -eq 0) {
        $workflowOut = Join-Path $tempRoot 'workflow.json'
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'invoke-workflow-smoke.ps1') -BaseUrl $BaseUrl -WorkflowPath (Join-Path $skillRoot 'assets\selftest-empty-image.api.json') -OutputPath $workflowOut | Out-Null
        $workflowCode = $LASTEXITCODE
        $workflow = if (Test-Path $workflowOut) { Get-Content $workflowOut -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
        Add-Check 'workflow-submit-and-complete' ($workflowCode -eq 0 -and $workflow.passed) $workflow
    }

    if ($ComfyUIRoot -and $PythonPath) {
        $cmd = Join-Path $tempRoot 'launcher.cmd'
        $lnk = Join-Path $tempRoot 'launcher.lnk'
        $stopScript = Join-Path $tempRoot 'stop-comfyui.ps1'
        $stopLnk = Join-Path $tempRoot 'stop-comfyui.lnk'
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'new-desktop-launcher.ps1') -ComfyUIRoot $ComfyUIRoot -PythonPath $PythonPath -LauncherPath $cmd -ShortcutPath $lnk -StopScriptPath $stopScript -StopShortcutPath $stopLnk | Out-Null
        $launcherCode = $LASTEXITCODE
        $bytes = if (Test-Path $cmd) { [IO.File]::ReadAllBytes($cmd) } else { @() }
        $text = if ($bytes.Count) { [Text.Encoding]::UTF8.GetString($bytes) } else { '' }
        $lf = ([regex]::Matches($text,"`n")).Count
        $crlf = ([regex]::Matches($text,"`r`n")).Count
        $bom = $bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $cachePinned = $text -match 'set "HF_HOME=%COMFYUI_ROOT%' -and $text -match 'set "TORCH_HOME=%COMFYUI_ROOT%' -and $text -match 'set "TRITON_CACHE_DIR=%COMFYUI_ROOT%'
        $stopText = if (Test-Path $stopScript) { Get-Content -LiteralPath $stopScript -Raw -Encoding UTF8 } else { '' }
        $stopTokens = $null; $stopErrors = $null
        if ($stopText) { [Management.Automation.Language.Parser]::ParseFile($stopScript,[ref]$stopTokens,[ref]$stopErrors) | Out-Null }
        $safeShutdown = $stopText -match 'Get-NetTCPConnection' -and $stopText -match 'ExpectedPython' -and $stopText -match 'queue_running' -and $stopText -match 'queue_pending' -and $stopText -match 'Stop-Process -Id \$target\.ProcessId'
        $shell = New-Object -ComObject WScript.Shell
        $startShortcut = if (Test-Path $lnk) { $shell.CreateShortcut($lnk) } else { $null }
        $stopShortcut = if (Test-Path $stopLnk) { $shell.CreateShortcut($stopLnk) } else { $null }
        $pairedIcons = $startShortcut -and $stopShortcut -and $startShortcut.IconLocation -match 'community-node-setup\.ico' -and $stopShortcut.IconLocation -match 'community-node-stop\.ico'
        Add-Check 'launcher-artifacts' ($launcherCode -eq 0 -and (Test-Path $cmd) -and (Test-Path $lnk) -and (Test-Path $stopScript) -and (Test-Path $stopLnk) -and $lf -eq $crlf -and -not $bom -and $cachePinned -and $stopErrors.Count -eq 0 -and $safeShutdown -and $pairedIcons) ([ordered]@{ crlfOnly = ($lf -eq $crlf); utf8Bom = $bom; startShortcut = (Test-Path $lnk); stopScript = (Test-Path $stopScript); stopShortcut = (Test-Path $stopLnk); pairedStartStopIcons = $pairedIcons; stopScriptParseErrors = @($stopErrors.Message); instanceSafeShutdown = $safeShutdown; cachesUnderComfyUI = $cachePinned })
    }
} catch {
    Add-Check 'selftest-exception' $false $_.Exception.Message
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

$failed = @($checks | Where-Object { -not $_.passed })
$report = [ordered]@{ generatedAt = (Get-Date).ToString('o'); passed = ($failed.Count -eq 0); checks = $checks }
$json = $report | ConvertTo-Json -Depth 15
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath), $json, [Text.UTF8Encoding]::new($false))
}
$json
if (-not $report.passed) { exit 1 }
