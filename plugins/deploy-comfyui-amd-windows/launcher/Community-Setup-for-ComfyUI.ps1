[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Join-Path $pluginRoot 'skills\deploy-comfyui-amd-windows'
$scriptsRoot = Join-Path $skillRoot 'scripts'
$iconPath = Join-Path $PSScriptRoot 'assets\community-wizard.ico'
$reportRoot = Join-Path $env:LOCALAPPDATA 'AMD-ComfyUI-Deployment-Wizard\reports'
$hostPath = Join-Path $reportRoot 'amd-comfyui-host.json'
$routePath = Join-Path $reportRoot 'amd-comfyui-route.json'
$planPath = Join-Path $reportRoot 'amd-comfyui-install-plan.json'
$logPath = Join-Path $reportRoot 'wizard.log'
$script:UiLanguage = 'zh-CN'
$requiredFiles = @('inspect-host.ps1','select-deployment-route.ps1','new-official-plan.ps1','set-pagefile.ps1','invoke-bootstrap.ps1') | ForEach-Object { Join-Path $scriptsRoot $_ }
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })

if ($SelfTest) {
    [ordered]@{
        name = 'Community Setup for ComfyUI on AMD Windows'; windows = [bool]($env:OS -eq 'Windows_NT')
        powershell = $PSVersionTable.PSVersion.ToString(); apartmentState = [Threading.Thread]::CurrentThread.ApartmentState.ToString()
        pluginRoot = $pluginRoot; requiredFiles = $requiredFiles; missingFiles = $missingFiles
        valid = [bool](($env:OS -eq 'Windows_NT') -and $missingFiles.Count -eq 0)
    } | ConvertTo-Json -Depth 4
    if ($missingFiles.Count -gt 0) { exit 2 }; exit 0
}
if ($missingFiles.Count -gt 0) { throw "Wizard package is incomplete: $($missingFiles -join ', ')" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null

function ConvertTo-PsLiteral([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function U([string]$Zh,[string]$En) { if ($script:UiLanguage -eq 'en-US') { $En } else { $Zh } }
function Add-Log([string]$Message) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    $logBox.AppendText($line + [Environment]::NewLine); $logBox.SelectionStart = $logBox.TextLength; $logBox.ScrollToCaret()
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
function Set-Stage([string]$Text, [Drawing.Color]$Color = [Drawing.Color]::FromArgb(35,105,70)) { $statusLabel.Text = $Text; $statusLabel.ForeColor = $Color }
function Set-StepProgress([int]$CurrentStep) {
    $script:CurrentStep = $CurrentStep
    $buttons = @($scanButton,$routeButton,$planButton,$dryRunButton,$deployButton)
    for ($index = 0; $index -lt $buttons.Count; $index++) {
        $button = $buttons[$index]
        $button.UseVisualStyleBackColor = $false
        if (($index + 1) -lt $CurrentStep) {
            $button.BackColor = [Drawing.Color]::FromArgb(31,122,73); $button.ForeColor = [Drawing.Color]::White
        } elseif (($index + 1) -eq $CurrentStep) {
            $button.BackColor = [Drawing.Color]::FromArgb(37,99,235); $button.ForeColor = [Drawing.Color]::White
        } else {
            $button.BackColor = [Drawing.Color]::FromArgb(229,231,235); $button.ForeColor = [Drawing.Color]::FromArgb(75,85,99)
        }
    }
}
function New-StepArrow {
    $arrow = [Windows.Forms.Label]::new(); $arrow.Text = '→'; $arrow.Size = [Drawing.Size]::new(30,34)
    $arrow.TextAlign = 'MiddleCenter'; $arrow.Font = [Drawing.Font]::new('Segoe UI Symbol',14,[Drawing.FontStyle]::Bold)
    $arrow.ForeColor = [Drawing.Color]::FromArgb(107,114,128)
    $arrow
}
function Set-UiLanguage([ValidateSet('zh-CN','en-US')][string]$Language) {
    $script:UiLanguage = $Language
    $form.Text = U 'AMD Windows 社区部署向导 for ComfyUI' 'Community Setup for ComfyUI on AMD Windows'
    $title.Text = U 'AMD Windows 社区部署向导 for ComfyUI' 'Community Setup for ComfyUI on AMD Windows'
    $subtitle.Text = U '非官方社区项目，与 ComfyUI、AMD、Microsoft 或 OpenAI 无隶属关系。无需 Codex 或 Vibe Coding。' 'Unofficial community project; not affiliated with ComfyUI, AMD, Microsoft, or OpenAI. No coding agent required.'
    $languageButton.Text = U 'English' '中文'
    $settings.Text = U '部署选择' 'Deployment choices'; $installLabel.Text = U '安装目录' 'Install folder'; $browseButton.Text = U '选择…' 'Browse…'; $profileLabel.Text = U '用途' 'Workload'
    $selectedProfile = [math]::Max(0,$profileBox.SelectedIndex); $profileBox.Items.Clear()
    [void]$profileBox.Items.AddRange(@((U '入门图片（建议至少 120 GB）' 'Starter images (120 GB+ recommended)'),(U '图片生产（建议至少 250 GB）' 'Image production (250 GB+ recommended)'),(U '视频生产（建议至少 600 GB）' 'Video production (600 GB+ recommended)'))); $profileBox.SelectedIndex = $selectedProfile
    $prereqBox.Text = U '缺少时允许安装 Python、Git、VC++ 运行库' 'Allow Python, Git, and VC++ runtime installation if missing'
    $pageFileTitle.Text = U '重要：虚拟内存决定大模型、超分与视频任务能否稳定运行' 'Important: virtual memory determines stability for large models, upscaling, and video'
    $pageFileAutoButton.Text = U '采用 Windows 自动管理' 'Use Windows automatic management'; $pageFileSettingsButton.Text = U '仅打开 Windows 高级设置' 'Open Windows advanced settings only'
    $stepHint.Text = U '操作提示：按箭头顺序，单击当前蓝色步骤一次；等待按钮变绿后，再点击下一步。' 'Follow the arrows. Click the current blue step once; wait until it turns green before continuing.'
    $scanButton.Text = U 'STEP 1  只读检测' 'STEP 1  Inspect'; $routeButton.Text = U 'STEP 2  官方路线' 'STEP 2  Official route'; $planButton.Text = U 'STEP 3  部署计划' 'STEP 3  Plan'; $dryRunButton.Text = U 'STEP 4  安装试运行' 'STEP 4  Dry run'; $deployButton.Text = U 'STEP 5  正式安装' 'STEP 5  Install'
    $side.Text = U '确认与辅助' 'Approval and help'; $approvalBox.Text = U '我已核对官方兼容结果、所需驱动、目标目录和空间，并理解安装会下载软件及模型。' 'I reviewed compatibility, driver, destination, and storage, and understand that installation downloads software and models.'
    $driverBox.Text = U '所需 AMD 驱动已安装，并已按要求重启' 'The required AMD driver is installed and Windows was restarted'; $belowSpaceBox.Text = U '空间仅达最低值时，我接受余量不足风险' 'I accept limited headroom when only the minimum storage is available'
    $pageFileButton.Text = U '打开 Windows 高级系统设置' 'Open Windows advanced system settings'; $reportsButton.Text = U '打开报告目录' 'Open reports'; $copyPromptButton.Text = U '复制求助提示词' 'Copy help prompt'
    if (Test-Path $planPath) { Show-PlanSummary } elseif (Test-Path $routePath) { Show-RouteSummary } elseif (Test-Path $hostPath) { Show-HostSummary } else {
        $pageFileSummary.Text = U '完成 STEP 3 后，这里会显示当前虚拟内存、适合本用途的最低/推荐容量，以及应该配置到哪个盘符。' 'After STEP 3, this panel shows current virtual memory, minimum/recommended sizes, and the recommended drive.'
        $summaryBox.Text = U "欢迎。`r`n`r`n第一步只读取电脑配置，不下载、不安装、不修改系统。`r`n选择用途和安装目录后，点击【STEP 1  只读检测】一次并等待完成。" "Welcome.`r`n`r`nSTEP 1 only reads system information. It does not download, install, or change settings.`r`nChoose a workload and install folder, then click STEP 1 once and wait."
        $statusLabel.Text = U '状态：等待只读检测' 'Status: waiting for read-only inspection'
    }
    if (-not $script:TaskBusy -and $script:CurrentStep) {
        $statusLabel.Text = switch ([int]$script:CurrentStep) {
            1 { U '状态：等待只读检测' 'Status: waiting for read-only inspection' }
            2 { U '通过：只读检测完成，请继续 STEP 2' 'Passed: inspection complete; continue with STEP 2' }
            3 { U '通过：官方路线确认，请继续 STEP 3' 'Passed: official route confirmed; continue with STEP 3' }
            4 { U '通过：部署计划完成，请确认选项后运行 STEP 4' 'Passed: plan complete; review choices and run STEP 4' }
            5 { U '通过：试运行完成，可以执行 STEP 5' 'Passed: dry run complete; STEP 5 is ready' }
            default { U '完成：ComfyUI 已部署并通过验证' 'Complete: ComfyUI deployed and verified' }
        }
    }
}
function Invoke-PageFileChange([ValidateSet('AutomaticManaged','Custom')][string]$Mode) {
    if (-not (Test-Path -LiteralPath $planPath)) { [Windows.Forms.MessageBox]::Show((U '请先完成 STEP 3，生成部署计划。' 'Complete STEP 3 and generate a deployment plan first.')); return }
    $plan = Read-Json $planPath
    if ($Mode -eq 'Custom' -and (-not $script:PageFileDrive -or -not $script:PageFileRecommendedGB)) {
        [Windows.Forms.MessageBox]::Show((U '没有找到可安全容纳推荐虚拟内存的 NTFS/ReFS 磁盘。请先释放空间或选择 Windows 自动管理。' 'No NTFS/ReFS drive can safely hold the recommended page file. Free space or use Windows automatic management.')); return
    }
    $detail = if ($Mode -eq 'AutomaticManaged') {
        U '启用 Windows 自动管理虚拟内存。Windows 将决定容量和放置位置。' 'Enable Windows automatic page-file management. Windows will choose its size and placement.'
    } else {
        U "在 $($script:PageFileDrive) 创建或更新固定虚拟内存：$($script:PageFileRecommendedGB) GB。其他盘符已有的虚拟内存会保留。" "Create or update a fixed $($script:PageFileRecommendedGB) GB page file on $($script:PageFileDrive). Existing page files on other drives are preserved."
    }
    $message = U "为什么需要：模型加载、VAE、超分和视频帧会占用大量提交内存；不足时可能报错或直接退出。`r`n`r`n即将执行：$detail`r`n`r`n该操作需要管理员权限，完成后必须重启。是否继续？" "Why this is needed: model loading, VAE, upscaling, and video frames consume substantial committed memory; insufficient capacity can cause errors or exits.`r`n`r`nAction: $detail`r`n`r`nAdministrator approval and a restart are required. Continue?"
    if ([Windows.Forms.MessageBox]::Show($message,(U '确认虚拟内存配置' 'Confirm virtual-memory configuration'),'YesNo','Warning') -ne 'Yes') { return }
    $setScript = Join-Path $scriptsRoot 'set-pagefile.ps1'
    $command = "& $(ConvertTo-PsLiteral $setScript) -PlanPath $(ConvertTo-PsLiteral $planPath) -Mode $Mode -ConfirmPageFileChange -Confirm:`$false"
    if ($Mode -eq 'Custom') {
        $command += " -DriveLetter $(ConvertTo-PsLiteral $script:PageFileDrive) -InitialGB $($script:PageFileRecommendedGB) -MaximumGB $($script:PageFileRecommendedGB)"
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    try {
        $process = Start-Process "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -Wait -PassThru -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
        if ($process.ExitCode -ne 0) { throw (U "虚拟内存配置命令退出码：$($process.ExitCode)" "Page-file command exit code: $($process.ExitCode)") }
        Set-Stage (U '等待用户操作：请保存工作并重启 Windows，然后从 STEP 1 重新检测' 'Waiting for user: save your work, restart Windows, then rerun STEP 1') ([Drawing.Color]::DarkOrange)
        [Windows.Forms.MessageBox]::Show((U '虚拟内存配置命令已完成。请保存当前工作，手动重启 Windows；重启后重新打开向导，从 STEP 1 开始检测。' 'The page-file command completed. Save your work and restart Windows manually, then reopen the wizard and run STEP 1 again.'),(U '需要重启' 'Restart required'),'OK','Information')
    } catch {
        Set-Stage (U '未通过：虚拟内存配置未完成' 'Failed: virtual-memory configuration did not complete') ([Drawing.Color]::Firebrick)
        [Windows.Forms.MessageBox]::Show((U "虚拟内存配置失败或管理员授权被取消：`r`n$($_.Exception.Message)" "Configuration failed or administrator approval was cancelled:`r`n$($_.Exception.Message)"),(U '配置未完成' 'Configuration incomplete'),'OK','Error')
    }
}
function Set-Busy([bool]$Busy) {
    $script:TaskBusy = $Busy; $scanButton.Enabled = -not $Busy
    $routeButton.Enabled = (-not $Busy) -and (Test-Path $hostPath); $planButton.Enabled = (-not $Busy) -and (Test-Path $routePath)
    $dryRunButton.Enabled = (-not $Busy) -and (Test-Path $planPath); $deployButton.Enabled = (-not $Busy) -and (Test-Path $planPath)
}
function Start-WizardTask([string]$Name,[string]$Command,[scriptblock]$Completed) {
    if ($script:TaskBusy) { return }; Add-Log((U "开始：$Name" "Started: $Name")); Set-Stage (U "正在执行：$Name …" "Running: $Name …") ([Drawing.Color]::DarkOrange); Set-Busy $true
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
    $start = [Diagnostics.ProcessStartInfo]::new(); $start.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $start.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"; $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true; $start.WorkingDirectory = $reportRoot
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    if (-not $process.Start()) { throw "Could not start task: $Name" }
    $script:CurrentTask = [pscustomobject]@{ Name=$Name; Process=$process; StdOut=$process.StandardOutput.ReadToEndAsync(); StdErr=$process.StandardError.ReadToEndAsync(); Completed=$Completed }
    $taskTimer.Start()
}
function Get-DefaultInstallRoot {
    $drive = [IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' -and $_.DriveFormat -in @('NTFS','ReFS') } | Sort-Object AvailableFreeSpace -Descending | Select-Object -First 1
    if ($drive) { return (Join-Path $drive.RootDirectory.FullName 'ComfyUI-AMD') }; 'C:\ComfyUI-AMD'
}
function Show-HostSummary {
    $r=Read-Json $hostPath; $gpu=@($r.gpu | Where-Object {$_.amdCandidate}) | Select-Object -First 1
    $disks=@($r.disks | ForEach-Object { if($script:UiLanguage -eq 'en-US'){"{0} {1}, {2} GB free" -f $_.device,$_.fileSystem,$_.freeGB}else{"{0} {1}，可用 {2} GB" -f $_.device,$_.fileSystem,$_.freeGB} }) -join (U '；' '; ')
    $gpuName=if($gpu){$gpu.name}else{U '未发现 AMD Radeon' 'No AMD Radeon detected'}; $driver=if($gpu){$gpu.driverVersion}else{U '未知' 'Unknown'}
    $pageFile=if($r.pageFile.automaticManaged){U 'Windows 自动管理' 'Windows automatic management'}else{U "最大 $($r.pageFile.totalConfiguredMaximumGB) GB" "Maximum $($r.pageFile.totalConfiguredMaximumGB) GB"}
    $summaryBox.Text=U "只读检测完成`r`n`r`n系统：$($r.os.caption)（Build $($r.os.build)，$($r.os.architecture)）`r`n显卡：$gpuName`r`n驱动：$driver`r`n内存：$($r.computer.ramGB) GB`r`n虚拟内存：$pageFile`r`n磁盘：$disks`r`n目标目录：$($installRootBox.Text)`r`n`r`n下一步会联网读取 AMD 当前官方兼容列表，但不会下载或安装软件。" "Read-only inspection complete`r`n`r`nSystem: $($r.os.caption) (Build $($r.os.build), $($r.os.architecture))`r`nGPU: $gpuName`r`nDriver: $driver`r`nRAM: $($r.computer.ramGB) GB`r`nVirtual memory: $pageFile`r`nDisks: $disks`r`nDestination: $($installRootBox.Text)`r`n`r`nThe next step reads AMD's current compatibility pages. It does not download or install software."
}
function Show-RouteSummary {
    $r=Read-Json $routePath
    $summaryBox.Text=U "官方兼容路线查询完成`r`n`r`n显卡：$($r.gpu.name)`r`n识别关键字：$($r.gpu.key)`r`nWindows 原生 ROCm：$($r.gpu.nativeWindowsMatrixMatch)`r`nWSL ROCm：$($r.gpu.wslMatrixMatch)`r`n选择路线：$($r.selectedRoute)`r`n原因：$($r.reason)`r`n`r`n第一版向导只直接安装 windows-native-rocm。其他路线会保留报告，建议交给支持本 Skill 的智能体继续处理。" "Official route check complete`r`n`r`nGPU: $($r.gpu.name)`r`nLookup key: $($r.gpu.key)`r`nNative Windows ROCm: $($r.gpu.nativeWindowsMatrixMatch)`r`nWSL ROCm: $($r.gpu.wslMatrixMatch)`r`nSelected route: $($r.selectedRoute)`r`nReason: $($r.reason)`r`n`r`nThis preview directly installs only windows-native-rocm. Reports are preserved for agent-assisted WSL or DirectML follow-up."
}
function Show-PlanSummary {
    $p=Read-Json $planPath
    $summaryBox.Text=U "部署计划已生成`r`n`r`n安装目录：$($p.installRoot)`r`n工作负载：$($p.storage.workloadProfile)`r`n预计下载：$($p.storage.knownDownloadGB) GB（另有 $($p.storage.unknownArtifactCount) 个未知大小组件）`r`n硬性最低空间：$($p.storage.hardMinimumGB) GB`r`n建议安装前可用空间：$($p.storage.recommendedFreeGB) GB`r`n当前目标盘可用：$($p.storage.targetFreeGB) GB`r`n空间等级：$($p.storage.spaceLevel)`r`n`r`n内存：$($p.pageFile.ramGB) GB`r`n虚拟内存状态：$($p.pageFile.status)`r`n建议：最低 $($p.pageFile.customRange.minimumGB) GB，推荐 $($p.pageFile.customRange.recommendedGB) GB，上限建议 $($p.pageFile.customRange.maximumRecommendedGB) GB`r`n`r`n要求 Python：$($p.compatibility.requiredPython)`r`n要求 AMD 驱动：$($p.compatibility.requiredAdrenalinDriver)`r`n固定 ComfyUI 提交：$($p.comfyUI.commit)`r`n`r`n若虚拟内存不足，请先配置并重启，再重新检测。" "Deployment plan generated`r`n`r`nInstall folder: $($p.installRoot)`r`nWorkload: $($p.storage.workloadProfile)`r`nKnown download: $($p.storage.knownDownloadGB) GB ($($p.storage.unknownArtifactCount) components have unknown size)`r`nHard minimum storage: $($p.storage.hardMinimumGB) GB`r`nRecommended free space: $($p.storage.recommendedFreeGB) GB`r`nCurrent target free space: $($p.storage.targetFreeGB) GB`r`nStorage level: $($p.storage.spaceLevel)`r`n`r`nRAM: $($p.pageFile.ramGB) GB`r`nVirtual-memory status: $($p.pageFile.status)`r`nRange: minimum $($p.pageFile.customRange.minimumGB) GB, recommended $($p.pageFile.customRange.recommendedGB) GB, suggested maximum $($p.pageFile.customRange.maximumRecommendedGB) GB`r`n`r`nRequired Python: $($p.compatibility.requiredPython)`r`nRequired AMD driver: $($p.compatibility.requiredAdrenalinDriver)`r`nPinned ComfyUI commit: $($p.comfyUI.commit)`r`n`r`nIf virtual memory is insufficient, configure it, restart Windows, and inspect again."
    $approvalBox.Enabled=[bool]($p.compatibility.matchedInOfficialPage -and $p.storage.spaceSufficient -and $p.pageFile.status -ne 'insufficient')
    $belowSpaceBox.Enabled=[bool]($p.storage.spaceLevel -eq 'minimum-only')
    $candidate = @($p.pageFile.targetCandidates | Where-Object { $_.canHostRecommended }) | Select-Object -First 1
    $script:PageFileDrive = if ($candidate) { ([string]$candidate.root).TrimEnd('\') } else { $null }
    $script:PageFileRecommendedGB = [int]$p.pageFile.customRange.recommendedGB
    $current = if ($p.pageFile.current.automaticManaged -eq $true) { U 'Windows 自动管理' 'Windows automatic management' } else { "$($p.pageFile.currentConfiguredMaximumGB) GB" }
    $target = if ($candidate) { U "$($script:PageFileDrive) 盘固定 $($script:PageFileRecommendedGB) GB" "fixed $($script:PageFileRecommendedGB) GB on $($script:PageFileDrive)" } else { U '没有满足空间要求的目标盘' 'no drive has enough safe headroom' }
    $pageFileSummary.Text = U "当前：$current｜状态：$($p.pageFile.status)｜本用途最低 $($p.pageFile.customRange.minimumGB) GB，推荐 $($script:PageFileRecommendedGB) GB，上限建议 $($p.pageFile.customRange.maximumRecommendedGB) GB`r`n推荐选择：保持 Windows 自动管理，或配置到 $target。修改后必须重启并重新检测。" "Current: $current | Status: $($p.pageFile.status) | Minimum $($p.pageFile.customRange.minimumGB) GB, recommended $($script:PageFileRecommendedGB) GB, suggested maximum $($p.pageFile.customRange.maximumRecommendedGB) GB`r`nChoose Windows automatic management or $target. Restart and inspect again after any change."
    $pageFileAutoButton.Enabled = [bool]($p.pageFile.status -in @('insufficient','minimum-only'))
    $pageFileCustomButton.Enabled = [bool]($candidate -and $p.pageFile.status -in @('insufficient','minimum-only'))
    $pageFileCustomButton.Text = if ($candidate) { U "配置到 $($script:PageFileDrive)｜$($script:PageFileRecommendedGB) GB" "$($script:PageFileDrive) | $($script:PageFileRecommendedGB) GB" } else { U '没有合适的目标盘' 'No suitable drive' }
    if ($p.pageFile.status -in @('system-managed','recommended')) {
        $pageFilePanel.BackColor = [Drawing.Color]::FromArgb(220,252,231); $pageFileTitle.ForeColor = [Drawing.Color]::FromArgb(22,101,52)
    } else {
        $pageFilePanel.BackColor = [Drawing.Color]::FromArgb(255,247,214); $pageFileTitle.ForeColor = [Drawing.Color]::FromArgb(154,83,0)
    }
}

$form=[Windows.Forms.Form]::new(); $form.Text='AMD Windows 社区部署向导 for ComfyUI'; $form.StartPosition='CenterScreen'; $form.Size=[Drawing.Size]::new(1040,850); $form.MinimumSize=[Drawing.Size]::new(900,790); $form.BackColor=[Drawing.Color]::FromArgb(246,248,250); $form.Font=[Drawing.Font]::new('Microsoft YaHei UI',9)
if(Test-Path $iconPath){$form.Icon=[Drawing.Icon]::new($iconPath)}
$title=[Windows.Forms.Label]::new(); $title.Text='AMD Windows 社区部署向导 for ComfyUI'; $title.Font=[Drawing.Font]::new('Microsoft YaHei UI',19,[Drawing.FontStyle]::Bold); $title.Location=[Drawing.Point]::new(24,18); $title.AutoSize=$true; $form.Controls.Add($title)
$languageButton=[Windows.Forms.Button]::new(); $languageButton.Text='English'; $languageButton.Location=[Drawing.Point]::new(887,18); $languageButton.Size=[Drawing.Size]::new(106,30); $languageButton.Anchor='Top,Right'; $form.Controls.Add($languageButton)
$subtitle=[Windows.Forms.Label]::new(); $subtitle.Text='非官方社区项目，与 ComfyUI、AMD、Microsoft 或 OpenAI 无隶属关系。无需 Codex 或 Vibe Coding。'; $subtitle.Location=[Drawing.Point]::new(28,58); $subtitle.Size=[Drawing.Size]::new(930,24); $subtitle.ForeColor=[Drawing.Color]::FromArgb(75,85,99); $form.Controls.Add($subtitle)
$settings=[Windows.Forms.GroupBox]::new(); $settings.Text='部署选择'; $settings.Location=[Drawing.Point]::new(24,92); $settings.Size=[Drawing.Size]::new(970,112); $settings.Anchor='Top,Left,Right'; $form.Controls.Add($settings)
$installLabel=[Windows.Forms.Label]::new(); $installLabel.Text='安装目录'; $installLabel.Location=[Drawing.Point]::new(18,31); $installLabel.AutoSize=$true; $settings.Controls.Add($installLabel)
$installRootBox=[Windows.Forms.TextBox]::new(); $installRootBox.Text=Get-DefaultInstallRoot; $installRootBox.Location=[Drawing.Point]::new(86,27); $installRootBox.Size=[Drawing.Size]::new(560,25); $settings.Controls.Add($installRootBox)
$browseButton=[Windows.Forms.Button]::new(); $browseButton.Text='选择…'; $browseButton.Location=[Drawing.Point]::new(656,26); $browseButton.Size=[Drawing.Size]::new(70,28); $settings.Controls.Add($browseButton)
$profileLabel=[Windows.Forms.Label]::new(); $profileLabel.Text='用途'; $profileLabel.Location=[Drawing.Point]::new(18,72); $profileLabel.AutoSize=$true; $settings.Controls.Add($profileLabel)
$profileBox=[Windows.Forms.ComboBox]::new(); $profileBox.DropDownStyle='DropDownList'; [void]$profileBox.Items.AddRange(@('入门图片（建议至少 120 GB）','图片生产（建议至少 250 GB）','视频生产（建议至少 600 GB）')); $profileBox.SelectedIndex=0; $profileBox.Location=[Drawing.Point]::new(86,68); $profileBox.Size=[Drawing.Size]::new(260,26); $settings.Controls.Add($profileBox)
$prereqBox=[Windows.Forms.CheckBox]::new(); $prereqBox.Text='缺少时允许安装 Python、Git、VC++ 运行库'; $prereqBox.Checked=$true; $prereqBox.Location=[Drawing.Point]::new(380,68); $prereqBox.Size=[Drawing.Size]::new(320,26); $settings.Controls.Add($prereqBox)
$pageFilePanel=[Windows.Forms.Panel]::new(); $pageFilePanel.Location=[Drawing.Point]::new(24,212); $pageFilePanel.Size=[Drawing.Size]::new(970,92); $pageFilePanel.Anchor='Top,Left,Right'; $pageFilePanel.BorderStyle='FixedSingle'; $pageFilePanel.BackColor=[Drawing.Color]::FromArgb(255,247,214); $form.Controls.Add($pageFilePanel)
$pageFileTitle=[Windows.Forms.Label]::new(); $pageFileTitle.Text='重要：虚拟内存决定大模型、超分与视频任务能否稳定运行'; $pageFileTitle.Location=[Drawing.Point]::new(12,8); $pageFileTitle.Size=[Drawing.Size]::new(610,22); $pageFileTitle.Font=[Drawing.Font]::new('Microsoft YaHei UI',9,[Drawing.FontStyle]::Bold); $pageFileTitle.ForeColor=[Drawing.Color]::FromArgb(154,83,0); $pageFilePanel.Controls.Add($pageFileTitle)
$pageFileSummary=[Windows.Forms.Label]::new(); $pageFileSummary.Text='完成 STEP 3 后，这里会显示当前虚拟内存、适合本用途的最低/推荐容量，以及应该配置到哪个盘符。'; $pageFileSummary.Location=[Drawing.Point]::new(12,33); $pageFileSummary.Size=[Drawing.Size]::new(620,48); $pageFileSummary.ForeColor=[Drawing.Color]::FromArgb(92,61,0); $pageFilePanel.Controls.Add($pageFileSummary)
$pageFileAutoButton=[Windows.Forms.Button]::new(); $pageFileAutoButton.Text='采用 Windows 自动管理'; $pageFileAutoButton.Location=[Drawing.Point]::new(650,15); $pageFileAutoButton.Size=[Drawing.Size]::new(145,29); $pageFileAutoButton.Enabled=$false; $pageFilePanel.Controls.Add($pageFileAutoButton)
$pageFileCustomButton=[Windows.Forms.Button]::new(); $pageFileCustomButton.Text='等待容量建议'; $pageFileCustomButton.Location=[Drawing.Point]::new(805,15); $pageFileCustomButton.Size=[Drawing.Size]::new(145,29); $pageFileCustomButton.Enabled=$false; $pageFilePanel.Controls.Add($pageFileCustomButton)
$pageFileSettingsButton=[Windows.Forms.Button]::new(); $pageFileSettingsButton.Text='仅打开 Windows 高级设置'; $pageFileSettingsButton.Location=[Drawing.Point]::new(650,50); $pageFileSettingsButton.Size=[Drawing.Size]::new(300,27); $pageFilePanel.Controls.Add($pageFileSettingsButton)
$stepHint=[Windows.Forms.Label]::new(); $stepHint.Text='操作提示：按箭头顺序，单击当前蓝色步骤一次；等待按钮变绿后，再点击下一步。'; $stepHint.Location=[Drawing.Point]::new(28,311); $stepHint.Size=[Drawing.Size]::new(930,22); $stepHint.ForeColor=[Drawing.Color]::FromArgb(75,85,99); $form.Controls.Add($stepHint)
$actions=[Windows.Forms.FlowLayoutPanel]::new(); $actions.Location=[Drawing.Point]::new(24,334); $actions.Size=[Drawing.Size]::new(970,42); $actions.Anchor='Top,Left,Right'; $form.Controls.Add($actions)
$scanButton=[Windows.Forms.Button]::new(); $scanButton.Text='STEP 1  只读检测'; $scanButton.Size=[Drawing.Size]::new(135,34); $actions.Controls.Add($scanButton)
$actions.Controls.Add((New-StepArrow))
$routeButton=[Windows.Forms.Button]::new(); $routeButton.Text='STEP 2  官方路线'; $routeButton.Size=[Drawing.Size]::new(150,34); $routeButton.Enabled=$false; $actions.Controls.Add($routeButton)
$actions.Controls.Add((New-StepArrow))
$planButton=[Windows.Forms.Button]::new(); $planButton.Text='STEP 3  部署计划'; $planButton.Size=[Drawing.Size]::new(135,34); $planButton.Enabled=$false; $actions.Controls.Add($planButton)
$actions.Controls.Add((New-StepArrow))
$dryRunButton=[Windows.Forms.Button]::new(); $dryRunButton.Text='STEP 4  安装试运行'; $dryRunButton.Size=[Drawing.Size]::new(150,34); $dryRunButton.Enabled=$false; $actions.Controls.Add($dryRunButton)
$actions.Controls.Add((New-StepArrow))
$deployButton=[Windows.Forms.Button]::new(); $deployButton.Text='STEP 5  正式安装'; $deployButton.Size=[Drawing.Size]::new(140,34); $deployButton.Enabled=$false; $actions.Controls.Add($deployButton)
Set-StepProgress 1
$summaryBox=[Windows.Forms.RichTextBox]::new(); $summaryBox.Location=[Drawing.Point]::new(24,387); $summaryBox.Size=[Drawing.Size]::new(620,257); $summaryBox.Anchor='Top,Bottom,Left,Right'; $summaryBox.ReadOnly=$true; $summaryBox.BackColor=[Drawing.Color]::White; $summaryBox.Text="欢迎。`r`n`r`n第一步只读取电脑配置，不下载、不安装、不修改系统。`r`n选择用途和安装目录后，点击【STEP 1  只读检测】一次并等待完成。"; $form.Controls.Add($summaryBox)
$side=[Windows.Forms.GroupBox]::new(); $side.Text='确认与辅助'; $side.Location=[Drawing.Point]::new(658,387); $side.Size=[Drawing.Size]::new(336,257); $side.Anchor='Top,Bottom,Right'; $form.Controls.Add($side)
$approvalBox=[Windows.Forms.CheckBox]::new(); $approvalBox.Text='我已核对官方兼容结果、所需驱动、目标目录和空间，并理解安装会下载软件及模型。'; $approvalBox.Location=[Drawing.Point]::new(18,30); $approvalBox.Size=[Drawing.Size]::new(295,64); $approvalBox.Enabled=$false; $side.Controls.Add($approvalBox)
$driverBox=[Windows.Forms.CheckBox]::new(); $driverBox.Text='所需 AMD 驱动已安装，并已按要求重启'; $driverBox.Location=[Drawing.Point]::new(18,100); $driverBox.Size=[Drawing.Size]::new(295,40); $side.Controls.Add($driverBox)
$belowSpaceBox=[Windows.Forms.CheckBox]::new(); $belowSpaceBox.Text='空间仅达最低值时，我接受余量不足风险'; $belowSpaceBox.Location=[Drawing.Point]::new(18,143); $belowSpaceBox.Size=[Drawing.Size]::new(295,34); $belowSpaceBox.Enabled=$false; $side.Controls.Add($belowSpaceBox)
$pageFileButton=[Windows.Forms.Button]::new(); $pageFileButton.Text='打开 Windows 高级系统设置'; $pageFileButton.Location=[Drawing.Point]::new(18,184); $pageFileButton.Size=[Drawing.Size]::new(275,30); $side.Controls.Add($pageFileButton)
$reportsButton=[Windows.Forms.Button]::new(); $reportsButton.Text='打开报告目录'; $reportsButton.Location=[Drawing.Point]::new(18,221); $reportsButton.Size=[Drawing.Size]::new(132,30); $side.Controls.Add($reportsButton)
$copyPromptButton=[Windows.Forms.Button]::new(); $copyPromptButton.Text='复制求助提示词'; $copyPromptButton.Location=[Drawing.Point]::new(161,221); $copyPromptButton.Size=[Drawing.Size]::new(132,30); $side.Controls.Add($copyPromptButton)
$statusLabel=[Windows.Forms.Label]::new(); $statusLabel.Text='状态：等待只读检测'; $statusLabel.Location=[Drawing.Point]::new(28,654); $statusLabel.Size=[Drawing.Size]::new(950,24); $statusLabel.Anchor='Bottom,Left,Right'; $statusLabel.Font=[Drawing.Font]::new('Microsoft YaHei UI',9,[Drawing.FontStyle]::Bold); $form.Controls.Add($statusLabel)
$logBox=[Windows.Forms.RichTextBox]::new(); $logBox.Location=[Drawing.Point]::new(24,682); $logBox.Size=[Drawing.Size]::new(970,108); $logBox.Anchor='Bottom,Left,Right'; $logBox.ReadOnly=$true; $logBox.BackColor=[Drawing.Color]::FromArgb(25,28,34); $logBox.ForeColor=[Drawing.Color]::Gainsboro; $logBox.Font=[Drawing.Font]::new('Consolas',8.5); $form.Controls.Add($logBox)

$taskTimer=[Windows.Forms.Timer]::new(); $taskTimer.Interval=350
$taskTimer.Add_Tick({
    if(-not $script:CurrentTask -or -not $script:CurrentTask.Process.HasExited){return}; $taskTimer.Stop(); $task=$script:CurrentTask
    $stdout=$task.StdOut.Result.Trim(); $stderr=$task.StdErr.Result.Trim(); if($stdout){Add-Log $stdout}; if($stderr){Add-Log (U "错误输出：$stderr" "Error output: $stderr")}
    $code=$task.Process.ExitCode; Add-Log (U "完成：$($task.Name)，退出码 $code" "Completed: $($task.Name), exit code $code"); $script:CurrentTask=$null; Set-Busy $false; & $task.Completed $code
})
$browseButton.Add_Click({$dialog=[Windows.Forms.FolderBrowserDialog]::new(); $dialog.Description=U '选择安装目录所在位置' 'Choose the parent folder for installation'; $dialog.SelectedPath=Split-Path -Parent $installRootBox.Text; if($dialog.ShowDialog() -eq 'OK'){$installRootBox.Text=Join-Path $dialog.SelectedPath 'ComfyUI-AMD'}})
$scanButton.Add_Click({$install=$installRootBox.Text.Trim(); if(-not [IO.Path]::IsPathRooted($install)){[Windows.Forms.MessageBox]::Show((U '请选择绝对安装路径。' 'Choose an absolute install path.'));return}; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'inspect-host.ps1')) -InstallRoot $(ConvertTo-PsLiteral $install) -OutputPath $(ConvertTo-PsLiteral $hostPath)"; Start-WizardTask (U '只读检测' 'Read-only inspection') $cmd {param($code) if($code -eq 0 -and (Test-Path $hostPath)){Show-HostSummary;Set-Stage (U '通过：只读检测完成' 'Passed: read-only inspection complete');Set-StepProgress 2}else{Set-Stage (U '未通过：只读检测失败' 'Failed: read-only inspection') ([Drawing.Color]::Firebrick)}}})
$routeButton.Add_Click({$cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'select-deployment-route.ps1')) -HostReportPath $(ConvertTo-PsLiteral $hostPath) -OutputPath $(ConvertTo-PsLiteral $routePath)"; Start-WizardTask (U '查询 AMD 官方兼容路线' 'Check AMD official compatibility routes') $cmd {param($code) if(Test-Path $routePath){Show-RouteSummary;$r=Read-Json $routePath;if($r.selectedRoute -eq 'windows-native-rocm'){Set-Stage (U '通过：可使用 Windows 原生 ROCm 路线' 'Passed: native Windows ROCm is eligible');Set-StepProgress 3}else{Set-Stage (U "等待处理：当前路线为 $($r.selectedRoute)" "Attention required: selected route is $($r.selectedRoute)") ([Drawing.Color]::DarkOrange)}}else{Set-Stage (U '未通过：无法取得官方兼容路线' 'Failed: could not resolve an official route') ([Drawing.Color]::Firebrick)}}})
$planButton.Add_Click({$r=Read-Json $routePath; if($r.selectedRoute -ne 'windows-native-rocm'){[Windows.Forms.MessageBox]::Show((U '第一版向导只自动部署 Windows 原生 ROCm。报告可交给智能体继续。' 'This preview automates only native Windows ROCm. Preserve the reports for agent-assisted follow-up.'));return}; $profile=@('StarterImage','ImageProduction','VideoProduction')[$profileBox.SelectedIndex]; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'new-official-plan.ps1')) -RoutePath $(ConvertTo-PsLiteral $routePath) -InstallRoot $(ConvertTo-PsLiteral $installRootBox.Text.Trim()) -WorkloadProfile $profile -OutputPath $(ConvertTo-PsLiteral $planPath)"; Start-WizardTask (U '生成机器专属部署计划' 'Generate a machine-specific plan') $cmd {param($code) if(Test-Path $planPath){Show-PlanSummary;if($code -eq 0){Set-Stage (U '通过：部署计划满足基础门槛' 'Passed: deployment plan meets the gates');Set-StepProgress 4}else{Set-Stage (U '等待处理：计划生成，但有门槛未通过' 'Attention required: plan generated, but a gate failed') ([Drawing.Color]::DarkOrange)}}else{Set-Stage (U '未通过：计划生成失败' 'Failed: plan generation') ([Drawing.Color]::Firebrick)}}})
$dryRunButton.Add_Click({if(-not $approvalBox.Checked -or -not $driverBox.Checked){[Windows.Forms.MessageBox]::Show((U '请先阅读计划并完成兼容性/驱动确认。' 'Review the plan and complete the compatibility/driver confirmations first.'));return}; $flags='-ConfirmSupportedGpu -DriverReady -WhatIf -Confirm:$false'; if($prereqBox.Checked){$flags+=' -InstallPrerequisites'}; if($belowSpaceBox.Checked){$flags+=' -AllowBelowRecommendedSpace'}; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'invoke-bootstrap.ps1')) -PlanPath $(ConvertTo-PsLiteral $planPath) $flags"; Start-WizardTask (U '安装试运行（不修改电脑）' 'Installation dry run (no changes)') $cmd {param($code) if($code -eq 0){Set-Stage (U '通过：试运行完成，可以开始安装' 'Passed: dry run complete; installation is ready');Set-StepProgress 5}else{Set-Stage (U '未通过：请查看日志和计划' 'Failed: review the log and plan') ([Drawing.Color]::Firebrick)}}})
$deployButton.Add_Click({if(-not $approvalBox.Checked -or -not $driverBox.Checked){[Windows.Forms.MessageBox]::Show((U '开始安装前必须完成两项确认。' 'Complete both confirmations before installation.'));return}; $answer=[Windows.Forms.MessageBox]::Show((U "即将联网下载并安装到：`r`n$($installRootBox.Text)`r`n`r`n安装可能持续较长时间。是否继续？" "The wizard will download and install to:`r`n$($installRootBox.Text)`r`n`r`nInstallation can take a long time. Continue?"),(U '最后确认' 'Final confirmation'),'YesNo','Warning'); if($answer -ne 'Yes'){return}; $flags='-ConfirmSupportedGpu -DriverReady -Confirm:$false'; if($prereqBox.Checked){$flags+=' -InstallPrerequisites'}; if($belowSpaceBox.Checked){$flags+=' -AllowBelowRecommendedSpace'}; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'invoke-bootstrap.ps1')) -PlanPath $(ConvertTo-PsLiteral $planPath) $flags"; Start-WizardTask (U '部署并验证 ComfyUI' 'Deploy and verify ComfyUI') $cmd {param($code) if($code -eq 0){Set-Stage (U '完成：ComfyUI 已部署并通过验证' 'Complete: ComfyUI deployed and verified');Set-StepProgress 6;[Windows.Forms.MessageBox]::Show((U "部署与验证完成。`r`n`r`n桌面已创建两个入口：`r`n• ComfyUI AMD ROCm：启动/打开`r`n• Stop ComfyUI AMD ROCm：安全关闭`r`n`r`n关闭器会先检查任务队列，不会误关其他 Python 程序。" "Deployment and verification completed.`r`n`r`nTwo desktop shortcuts were created:`r`n• ComfyUI AMD ROCm: start/open`r`n• Stop ComfyUI AMD ROCm: safe shutdown`r`n`r`nThe shutdown tool checks the queue first and will not stop unrelated Python programs."))}else{Set-Stage (U '未完成：报告可交给智能体继续处理' 'Incomplete: use the reports for agent-assisted follow-up') ([Drawing.Color]::Firebrick)}}})
$pageFileButton.Add_Click({Start-Process SystemPropertiesAdvanced.exe}); $pageFileSettingsButton.Add_Click({Start-Process SystemPropertiesAdvanced.exe})
$pageFileAutoButton.Add_Click({Invoke-PageFileChange 'AutomaticManaged'}); $pageFileCustomButton.Add_Click({Invoke-PageFileChange 'Custom'})
$reportsButton.Add_Click({Start-Process explorer.exe -ArgumentList $reportRoot})
$copyPromptButton.Add_Click({$prompt=U "请使用 deploy-comfyui-amd-windows Skill 分析 AMD ComfyUI 独立部署向导的报告并继续处理。报告目录：$reportRoot。先只读检查报告和日志，不要未经同意下载、安装或修改系统。" "Use the deploy-comfyui-amd-windows Skill to analyze and continue this standalone wizard run. Reports: $reportRoot. Inspect reports and logs read-only first; do not download, install, or change system settings without approval."; [Windows.Forms.Clipboard]::SetText($prompt);Set-Stage (U '已复制求助提示词' 'Help prompt copied')})
$languageButton.Add_Click({ if($script:UiLanguage -eq 'zh-CN'){Set-UiLanguage 'en-US'}else{Set-UiLanguage 'zh-CN'} })
$form.Add_FormClosing({if($script:TaskBusy -and [Windows.Forms.MessageBox]::Show((U '任务仍在运行。确定关闭向导吗？' 'A task is still running. Close the wizard?'),(U '确认' 'Confirm'),'YesNo','Warning') -ne 'Yes'){$_.Cancel=$true}})
$initialLanguage = if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'zh') { 'zh-CN' } else { 'en-US' }
Set-UiLanguage $initialLanguage; Add-Log (U "向导启动。报告目录：$reportRoot" "Wizard started. Reports: $reportRoot"); [void]$form.ShowDialog()
