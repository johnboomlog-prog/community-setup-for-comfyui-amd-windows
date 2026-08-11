[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$pluginRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Join-Path $pluginRoot 'skills\deploy-comfyui-amd-windows'
$scriptsRoot = Join-Path $skillRoot 'scripts'
$iconPath = Join-Path $skillRoot 'assets\comfyui.ico'
$reportRoot = Join-Path $env:LOCALAPPDATA 'AMD-ComfyUI-Deployment-Wizard\reports'
$hostPath = Join-Path $reportRoot 'amd-comfyui-host.json'
$routePath = Join-Path $reportRoot 'amd-comfyui-route.json'
$planPath = Join-Path $reportRoot 'amd-comfyui-install-plan.json'
$logPath = Join-Path $reportRoot 'wizard.log'
$requiredFiles = @('inspect-host.ps1','select-deployment-route.ps1','new-official-plan.ps1','invoke-bootstrap.ps1') | ForEach-Object { Join-Path $scriptsRoot $_ }
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })

if ($SelfTest) {
    [ordered]@{
        name = 'AMD ComfyUI Deployment Wizard'; windows = [bool]($env:OS -eq 'Windows_NT')
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
function Add-Log([string]$Message) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $Message
    $logBox.AppendText($line + [Environment]::NewLine); $logBox.SelectionStart = $logBox.TextLength; $logBox.ScrollToCaret()
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}
function Set-Stage([string]$Text, [Drawing.Color]$Color = [Drawing.Color]::FromArgb(35,105,70)) { $statusLabel.Text = $Text; $statusLabel.ForeColor = $Color }
function Set-Busy([bool]$Busy) {
    $script:TaskBusy = $Busy; $scanButton.Enabled = -not $Busy
    $routeButton.Enabled = (-not $Busy) -and (Test-Path $hostPath); $planButton.Enabled = (-not $Busy) -and (Test-Path $routePath)
    $dryRunButton.Enabled = (-not $Busy) -and (Test-Path $planPath); $deployButton.Enabled = (-not $Busy) -and (Test-Path $planPath)
}
function Start-WizardTask([string]$Name,[string]$Command,[scriptblock]$Completed) {
    if ($script:TaskBusy) { return }; Add-Log("开始：$Name"); Set-Stage "正在执行：$Name …" ([Drawing.Color]::DarkOrange); Set-Busy $true
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
    $disks=@($r.disks | ForEach-Object { "{0} {1}，可用 {2} GB" -f $_.device,$_.fileSystem,$_.freeGB }) -join '；'
    $summaryBox.Text="只读检测完成`r`n`r`n系统：$($r.os.caption)（Build $($r.os.build)，$($r.os.architecture)）`r`n显卡：$(if($gpu){$gpu.name}else{'未发现 AMD Radeon'})`r`n驱动：$(if($gpu){$gpu.driverVersion}else{'未知'})`r`n内存：$($r.computer.ramGB) GB`r`n虚拟内存：$(if($r.pageFile.automaticManaged){'Windows 自动管理'}else{"最大 $($r.pageFile.totalConfiguredMaximumGB) GB"})`r`n磁盘：$disks`r`n目标目录：$($installRootBox.Text)`r`n`r`n下一步会联网读取 AMD 当前官方兼容列表，但不会下载或安装软件。"
}
function Show-RouteSummary {
    $r=Read-Json $routePath
    $summaryBox.Text="官方兼容路线查询完成`r`n`r`n显卡：$($r.gpu.name)`r`n识别关键字：$($r.gpu.key)`r`nWindows 原生 ROCm：$($r.gpu.nativeWindowsMatrixMatch)`r`nWSL ROCm：$($r.gpu.wslMatrixMatch)`r`n选择路线：$($r.selectedRoute)`r`n原因：$($r.reason)`r`n`r`n第一版向导只直接安装 windows-native-rocm。其他路线会保留报告，建议交给支持本 Skill 的智能体继续处理。"
}
function Show-PlanSummary {
    $p=Read-Json $planPath
    $summaryBox.Text="部署计划已生成`r`n`r`n安装目录：$($p.installRoot)`r`n工作负载：$($p.storage.workloadProfile)`r`n预计下载：$($p.storage.knownDownloadGB) GB（另有 $($p.storage.unknownArtifactCount) 个未知大小组件）`r`n硬性最低空间：$($p.storage.hardMinimumGB) GB`r`n建议安装前可用空间：$($p.storage.recommendedFreeGB) GB`r`n当前目标盘可用：$($p.storage.targetFreeGB) GB`r`n空间等级：$($p.storage.spaceLevel)`r`n`r`n内存：$($p.pageFile.ramGB) GB`r`n虚拟内存状态：$($p.pageFile.status)`r`n建议：最低 $($p.pageFile.customRange.minimumGB) GB，推荐 $($p.pageFile.customRange.recommendedGB) GB，上限建议 $($p.pageFile.customRange.maximumRecommendedGB) GB`r`n`r`n要求 Python：$($p.compatibility.requiredPython)`r`n要求 AMD 驱动：$($p.compatibility.requiredAdrenalinDriver)`r`n固定 ComfyUI 提交：$($p.comfyUI.commit)`r`n`r`n若虚拟内存不足，请先打开 Windows 高级系统设置调整并重启，再重新检测。"
    $approvalBox.Enabled=[bool]($p.compatibility.matchedInOfficialPage -and $p.storage.spaceSufficient -and $p.pageFile.status -ne 'insufficient')
    $belowSpaceBox.Enabled=[bool]($p.storage.spaceLevel -eq 'minimum-only')
}

$form=[Windows.Forms.Form]::new(); $form.Text='AMD ComfyUI Windows 独立部署向导'; $form.StartPosition='CenterScreen'; $form.Size=[Drawing.Size]::new(1040,760); $form.MinimumSize=[Drawing.Size]::new(900,680); $form.BackColor=[Drawing.Color]::FromArgb(246,248,250); $form.Font=[Drawing.Font]::new('Microsoft YaHei UI',9)
if(Test-Path $iconPath){$form.Icon=[Drawing.Icon]::new($iconPath)}
$title=[Windows.Forms.Label]::new(); $title.Text='AMD ComfyUI Windows 独立部署向导'; $title.Font=[Drawing.Font]::new('Microsoft YaHei UI',19,[Drawing.FontStyle]::Bold); $title.Location=[Drawing.Point]::new(24,18); $title.AutoSize=$true; $form.Controls.Add($title)
$subtitle=[Windows.Forms.Label]::new(); $subtitle.Text='无需 Codex 或 Vibe Coding。先只读检测，再按官方证据规划；下载和安装前必须由你确认。'; $subtitle.Location=[Drawing.Point]::new(28,58); $subtitle.Size=[Drawing.Size]::new(930,24); $subtitle.ForeColor=[Drawing.Color]::FromArgb(75,85,99); $form.Controls.Add($subtitle)
$settings=[Windows.Forms.GroupBox]::new(); $settings.Text='部署选择'; $settings.Location=[Drawing.Point]::new(24,92); $settings.Size=[Drawing.Size]::new(970,112); $settings.Anchor='Top,Left,Right'; $form.Controls.Add($settings)
$installLabel=[Windows.Forms.Label]::new(); $installLabel.Text='安装目录'; $installLabel.Location=[Drawing.Point]::new(18,31); $installLabel.AutoSize=$true; $settings.Controls.Add($installLabel)
$installRootBox=[Windows.Forms.TextBox]::new(); $installRootBox.Text=Get-DefaultInstallRoot; $installRootBox.Location=[Drawing.Point]::new(86,27); $installRootBox.Size=[Drawing.Size]::new(560,25); $settings.Controls.Add($installRootBox)
$browseButton=[Windows.Forms.Button]::new(); $browseButton.Text='选择…'; $browseButton.Location=[Drawing.Point]::new(656,26); $browseButton.Size=[Drawing.Size]::new(70,28); $settings.Controls.Add($browseButton)
$profileLabel=[Windows.Forms.Label]::new(); $profileLabel.Text='用途'; $profileLabel.Location=[Drawing.Point]::new(18,72); $profileLabel.AutoSize=$true; $settings.Controls.Add($profileLabel)
$profileBox=[Windows.Forms.ComboBox]::new(); $profileBox.DropDownStyle='DropDownList'; [void]$profileBox.Items.AddRange(@('入门图片（建议至少 120 GB）','图片生产（建议至少 250 GB）','视频生产（建议至少 600 GB）')); $profileBox.SelectedIndex=0; $profileBox.Location=[Drawing.Point]::new(86,68); $profileBox.Size=[Drawing.Size]::new(260,26); $settings.Controls.Add($profileBox)
$prereqBox=[Windows.Forms.CheckBox]::new(); $prereqBox.Text='缺少时允许安装 Python、Git、VC++ 运行库'; $prereqBox.Checked=$true; $prereqBox.Location=[Drawing.Point]::new(380,68); $prereqBox.Size=[Drawing.Size]::new(320,26); $settings.Controls.Add($prereqBox)
$actions=[Windows.Forms.FlowLayoutPanel]::new(); $actions.Location=[Drawing.Point]::new(24,216); $actions.Size=[Drawing.Size]::new(970,42); $actions.Anchor='Top,Left,Right'; $form.Controls.Add($actions)
$scanButton=[Windows.Forms.Button]::new(); $scanButton.Text='1. 只读检测'; $scanButton.Size=[Drawing.Size]::new(130,34); $actions.Controls.Add($scanButton)
$routeButton=[Windows.Forms.Button]::new(); $routeButton.Text='2. 查询官方路线'; $routeButton.Size=[Drawing.Size]::new(145,34); $routeButton.Enabled=$false; $actions.Controls.Add($routeButton)
$planButton=[Windows.Forms.Button]::new(); $planButton.Text='3. 生成计划'; $planButton.Size=[Drawing.Size]::new(125,34); $planButton.Enabled=$false; $actions.Controls.Add($planButton)
$dryRunButton=[Windows.Forms.Button]::new(); $dryRunButton.Text='4. 安装试运行'; $dryRunButton.Size=[Drawing.Size]::new(135,34); $dryRunButton.Enabled=$false; $actions.Controls.Add($dryRunButton)
$deployButton=[Windows.Forms.Button]::new(); $deployButton.Text='5. 开始安装'; $deployButton.Size=[Drawing.Size]::new(130,34); $deployButton.Enabled=$false; $deployButton.BackColor=[Drawing.Color]::FromArgb(31,122,73); $deployButton.ForeColor=[Drawing.Color]::White; $actions.Controls.Add($deployButton)
$summaryBox=[Windows.Forms.RichTextBox]::new(); $summaryBox.Location=[Drawing.Point]::new(24,270); $summaryBox.Size=[Drawing.Size]::new(620,292); $summaryBox.Anchor='Top,Bottom,Left,Right'; $summaryBox.ReadOnly=$true; $summaryBox.BackColor=[Drawing.Color]::White; $summaryBox.Text="欢迎。`r`n`r`n第一步只读取电脑配置，不下载、不安装、不修改系统。`r`n选择用途和安装目录后，点击【1. 只读检测】。"; $form.Controls.Add($summaryBox)
$side=[Windows.Forms.GroupBox]::new(); $side.Text='确认与辅助'; $side.Location=[Drawing.Point]::new(658,270); $side.Size=[Drawing.Size]::new(336,292); $side.Anchor='Top,Bottom,Right'; $form.Controls.Add($side)
$approvalBox=[Windows.Forms.CheckBox]::new(); $approvalBox.Text='我已核对官方兼容结果、所需驱动、目标目录和空间，并理解安装会下载软件及模型。'; $approvalBox.Location=[Drawing.Point]::new(18,30); $approvalBox.Size=[Drawing.Size]::new(295,64); $approvalBox.Enabled=$false; $side.Controls.Add($approvalBox)
$driverBox=[Windows.Forms.CheckBox]::new(); $driverBox.Text='所需 AMD 驱动已安装，并已按要求重启'; $driverBox.Location=[Drawing.Point]::new(18,100); $driverBox.Size=[Drawing.Size]::new(295,40); $side.Controls.Add($driverBox)
$belowSpaceBox=[Windows.Forms.CheckBox]::new(); $belowSpaceBox.Text='空间仅达最低值时，我接受余量不足风险'; $belowSpaceBox.Location=[Drawing.Point]::new(18,143); $belowSpaceBox.Size=[Drawing.Size]::new(295,34); $belowSpaceBox.Enabled=$false; $side.Controls.Add($belowSpaceBox)
$pageFileButton=[Windows.Forms.Button]::new(); $pageFileButton.Text='打开 Windows 高级系统设置'; $pageFileButton.Location=[Drawing.Point]::new(18,184); $pageFileButton.Size=[Drawing.Size]::new(275,30); $side.Controls.Add($pageFileButton)
$reportsButton=[Windows.Forms.Button]::new(); $reportsButton.Text='打开报告目录'; $reportsButton.Location=[Drawing.Point]::new(18,221); $reportsButton.Size=[Drawing.Size]::new(132,30); $side.Controls.Add($reportsButton)
$copyPromptButton=[Windows.Forms.Button]::new(); $copyPromptButton.Text='复制求助提示词'; $copyPromptButton.Location=[Drawing.Point]::new(161,221); $copyPromptButton.Size=[Drawing.Size]::new(132,30); $side.Controls.Add($copyPromptButton)
$statusLabel=[Windows.Forms.Label]::new(); $statusLabel.Text='状态：等待只读检测'; $statusLabel.Location=[Drawing.Point]::new(28,574); $statusLabel.Size=[Drawing.Size]::new(950,24); $statusLabel.Anchor='Bottom,Left,Right'; $statusLabel.Font=[Drawing.Font]::new('Microsoft YaHei UI',9,[Drawing.FontStyle]::Bold); $form.Controls.Add($statusLabel)
$logBox=[Windows.Forms.RichTextBox]::new(); $logBox.Location=[Drawing.Point]::new(24,602); $logBox.Size=[Drawing.Size]::new(970,98); $logBox.Anchor='Bottom,Left,Right'; $logBox.ReadOnly=$true; $logBox.BackColor=[Drawing.Color]::FromArgb(25,28,34); $logBox.ForeColor=[Drawing.Color]::Gainsboro; $logBox.Font=[Drawing.Font]::new('Consolas',8.5); $form.Controls.Add($logBox)

$taskTimer=[Windows.Forms.Timer]::new(); $taskTimer.Interval=350
$taskTimer.Add_Tick({
    if(-not $script:CurrentTask -or -not $script:CurrentTask.Process.HasExited){return}; $taskTimer.Stop(); $task=$script:CurrentTask
    $stdout=$task.StdOut.Result.Trim(); $stderr=$task.StdErr.Result.Trim(); if($stdout){Add-Log $stdout}; if($stderr){Add-Log "错误输出：$stderr"}
    $code=$task.Process.ExitCode; Add-Log "完成：$($task.Name)，退出码 $code"; $script:CurrentTask=$null; Set-Busy $false; & $task.Completed $code
})
$browseButton.Add_Click({$dialog=[Windows.Forms.FolderBrowserDialog]::new(); $dialog.Description='选择安装目录所在位置'; $dialog.SelectedPath=Split-Path -Parent $installRootBox.Text; if($dialog.ShowDialog() -eq 'OK'){$installRootBox.Text=Join-Path $dialog.SelectedPath 'ComfyUI-AMD'}})
$scanButton.Add_Click({$install=$installRootBox.Text.Trim(); if(-not [IO.Path]::IsPathRooted($install)){[Windows.Forms.MessageBox]::Show('请选择绝对安装路径。');return}; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'inspect-host.ps1')) -InstallRoot $(ConvertTo-PsLiteral $install) -OutputPath $(ConvertTo-PsLiteral $hostPath)"; Start-WizardTask '只读检测' $cmd {param($code) if($code -eq 0 -and (Test-Path $hostPath)){Show-HostSummary;Set-Stage '通过：只读检测完成'}else{Set-Stage '未通过：只读检测失败' ([Drawing.Color]::Firebrick)}}})
$routeButton.Add_Click({$cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'select-deployment-route.ps1')) -HostReportPath $(ConvertTo-PsLiteral $hostPath) -OutputPath $(ConvertTo-PsLiteral $routePath)"; Start-WizardTask '查询 AMD 官方兼容路线' $cmd {param($code) if(Test-Path $routePath){Show-RouteSummary;$r=Read-Json $routePath;if($r.selectedRoute -eq 'windows-native-rocm'){Set-Stage '通过：可使用 Windows 原生 ROCm 路线'}else{Set-Stage "等待处理：当前路线为 $($r.selectedRoute)" ([Drawing.Color]::DarkOrange)}}else{Set-Stage '未通过：无法取得官方兼容路线' ([Drawing.Color]::Firebrick)}}})
$planButton.Add_Click({$r=Read-Json $routePath; if($r.selectedRoute -ne 'windows-native-rocm'){[Windows.Forms.MessageBox]::Show('第一版向导只自动部署 Windows 原生 ROCm。报告可交给智能体继续。');return}; $profile=@('StarterImage','ImageProduction','VideoProduction')[$profileBox.SelectedIndex]; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'new-official-plan.ps1')) -RoutePath $(ConvertTo-PsLiteral $routePath) -InstallRoot $(ConvertTo-PsLiteral $installRootBox.Text.Trim()) -WorkloadProfile $profile -OutputPath $(ConvertTo-PsLiteral $planPath)"; Start-WizardTask '生成机器专属部署计划' $cmd {param($code) if(Test-Path $planPath){Show-PlanSummary;if($code -eq 0){Set-Stage '通过：部署计划满足基础门槛'}else{Set-Stage '等待处理：计划生成，但有门槛未通过' ([Drawing.Color]::DarkOrange)}}else{Set-Stage '未通过：计划生成失败' ([Drawing.Color]::Firebrick)}}})
$dryRunButton.Add_Click({if(-not $approvalBox.Checked -or -not $driverBox.Checked){[Windows.Forms.MessageBox]::Show('请先阅读计划并完成兼容性/驱动确认。');return}; $flags='-ConfirmSupportedGpu -DriverReady -WhatIf -Confirm:$false'; if($prereqBox.Checked){$flags+=' -InstallPrerequisites'}; if($belowSpaceBox.Checked){$flags+=' -AllowBelowRecommendedSpace'}; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'invoke-bootstrap.ps1')) -PlanPath $(ConvertTo-PsLiteral $planPath) $flags"; Start-WizardTask '安装试运行（不修改电脑）' $cmd {param($code) if($code -eq 0){Set-Stage '通过：试运行完成，可以开始安装'}else{Set-Stage '未通过：请查看日志和计划' ([Drawing.Color]::Firebrick)}}})
$deployButton.Add_Click({if(-not $approvalBox.Checked -or -not $driverBox.Checked){[Windows.Forms.MessageBox]::Show('开始安装前必须完成两项确认。');return}; $answer=[Windows.Forms.MessageBox]::Show("即将联网下载并安装到：`r`n$($installRootBox.Text)`r`n`r`n安装可能持续较长时间。是否继续？",'最后确认','YesNo','Warning'); if($answer -ne 'Yes'){return}; $flags='-ConfirmSupportedGpu -DriverReady -Confirm:$false'; if($prereqBox.Checked){$flags+=' -InstallPrerequisites'}; if($belowSpaceBox.Checked){$flags+=' -AllowBelowRecommendedSpace'}; $cmd="& $(ConvertTo-PsLiteral (Join-Path $scriptsRoot 'invoke-bootstrap.ps1')) -PlanPath $(ConvertTo-PsLiteral $planPath) $flags"; Start-WizardTask '部署并验证 ComfyUI' $cmd {param($code) if($code -eq 0){Set-Stage '完成：ComfyUI 已部署并通过验证';[Windows.Forms.MessageBox]::Show('部署与验证完成。桌面启动器已创建。')}else{Set-Stage '未完成：报告可交给智能体继续处理' ([Drawing.Color]::Firebrick)}}})
$pageFileButton.Add_Click({Start-Process SystemPropertiesAdvanced.exe}); $reportsButton.Add_Click({Start-Process explorer.exe -ArgumentList $reportRoot})
$copyPromptButton.Add_Click({$prompt="请使用 deploy-comfyui-amd-windows Skill 分析 AMD ComfyUI 独立部署向导的报告并继续处理。报告目录：$reportRoot。先只读检查报告和日志，不要未经同意下载、安装或修改系统。"; [Windows.Forms.Clipboard]::SetText($prompt);Set-Stage '已复制求助提示词'})
$form.Add_FormClosing({if($script:TaskBusy -and [Windows.Forms.MessageBox]::Show('任务仍在运行。确定关闭向导吗？','确认','YesNo','Warning') -ne 'Yes'){$_.Cancel=$true}})
Add-Log "向导启动。报告目录：$reportRoot"; [void]$form.ShowDialog()
