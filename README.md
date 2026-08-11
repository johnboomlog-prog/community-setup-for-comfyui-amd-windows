# Community Setup for ComfyUI on AMD Windows

[中文说明](#给普通用户先看这里) · [English](#english-quick-start)

这是一个面向 AMD Radeon（A 卡）Windows 用户的非官方社区部署工具。它会先检查显卡、内存、磁盘和虚拟内存，再根据 AMD 当前兼容信息制定方案；只有经过用户确认后才会下载、安装并验证 ComfyUI。

> 当前状态：`0.2.0` 预览版。Windows 原生 ROCm 路线自动化程度最高。WSL ROCm 和 DirectML 目前以诊断、报告和智能体辅助处理为主。

## 给普通用户：先看这里

### 我该下载哪个？

| 你的情况 | 下载/使用 | 是否需要 Vibe Coding |
|---|---|---|
| 只想把 ComfyUI 装好 | Releases 中的 `Community-Setup-for-ComfyUI-AMD-Windows.exe` | 不需要 |
| EXE 被安全软件拦截 | `Community-Setup-for-ComfyUI-AMD-Windows-portable.zip` | 不需要 |
| 需要排查特殊显卡、WSL、节点或损坏环境 | 仓库里的 Codex Skill/插件 | 需要一个支持 Skill 的智能体 |
| 只是开发或审查本项目 | 克隆完整源码仓库 | 不需要 |

正常用户不要下载 `Source code (zip)`。它是给开发者看的，不是安装包。

### 最简单的使用方法

1. 打开仓库右侧的 **Releases**。
2. 下载 `Community-Setup-for-ComfyUI-AMD-Windows.exe`。
3. 双击 EXE。首次运行会把内置向导文件释放到当前用户的 `%LOCALAPPDATA%\CommunitySetupForComfyUI\<版本号>`，不会把 ComfyUI 安装到这里。
4. 按界面中的 `STEP 1 → STEP 5` 依次操作。先检测和规划，最后一步才会下载、安装。
5. 安装和真实推理验证成功后，向导会在桌面创建 ComfyUI 启动器。以后直接双击桌面图标即可。

界面会根据 Windows 显示语言自动选择中文或英文，也可以使用右上角按钮随时切换。

### 每一步到底在做什么？

| 步骤 | 做什么 | 会不会修改电脑 |
|---|---|---|
| STEP 1 | 检查 AMD 显卡、系统、内存、磁盘、Python/Git 和已有 ComfyUI | 不会，只读 |
| STEP 2 | 查询 AMD 当前官方兼容资料并选择 Windows ROCm、WSL 或备选路线 | 不会，只联网读取资料 |
| STEP 3 | 根据图片/视频用途估算模型空间、安装盘空间和虚拟内存 | 不会，只生成计划 |
| STEP 4 | 试运行即将执行的安装步骤 | 不会 |
| STEP 5 | 经你最终确认后下载、安装、测试 GPU 和真实 ComfyUI 工作流 | 会，界面会再次确认 |

虚拟内存不是“越大越好”。视频工作流和大模型可能在显存溢出、模型加载或编译阶段占用大量系统提交内存，因此向导会结合物理内存、用途与目标盘剩余空间给出建议。需要修改时会明确显示盘符、建议范围和重启要求，不会静默更改。

### Windows 弹出安全提示怎么办？

当前社区预览版没有商业代码签名证书，Windows SmartScreen 或安全软件可能提示“未知发布者”。你可以：

- 先核对 Release 页面提供的 `SHA256SUMS.txt`；
- 不信任 EXE 时改用 portable ZIP，解压后双击 `launcher\Start-Community-Setup-for-ComfyUI.cmd`；
- 仍不放心就不要运行，先让安全软件扫描或审查源码。

本项目不会要求关闭杀毒软件、关闭 UAC、全局降低 PowerShell 安全策略或静默安装显卡驱动。

## 两种产品，不要混淆

### A. 独立部署向导（普通用户）

这是 EXE/portable ZIP 图形界面版，不需要 Codex、Claude Code、Cursor、Python 或 Node.js 才能启动。它可以独立完成当前受支持的 Windows 原生 ROCm 部署流程。

如果检测结果表明机器更适合 WSL、DirectML，或上游兼容资料发生变化，向导会停止自动安装并保留机器可读报告，而不是冒险套用错误方案。这时才建议把报告交给智能体处理。

### B. Codex Skill/插件（智能体用户）

它适合复杂诊断、已有环境修复、WSL 路线、第三方节点兼容性和部署失败后的继续处理。克隆仓库后，可以把它作为本地 marketplace 安装：

```powershell
codex plugin marketplace add <本仓库所在目录>
codex plugin add deploy-comfyui-amd-windows@amd-comfyui-community
```

新开一个 Codex 对话，然后输入：

```text
使用 $deploy-comfyui-amd-windows 检查这台 AMD Windows 电脑，并引导我安全部署 ComfyUI。
```

其他智能体可以复制 `plugins/deploy-comfyui-amd-windows/skills/deploy-comfyui-amd-windows` 到其 Skill 目录；不支持 Skill 的智能体也可以被要求先阅读其中的 `SKILL.md`。

## 安全边界

- AMD 部署不混入 CUDA 专用依赖。
- 下载或系统修改前，先检测、解释并取得用户确认。
- 不静默安装 GPU 驱动，不关闭杀毒软件或 UAC。
- 新部署只使用新的或空的安装目录。
- 下载来源限制为经过审查的 HTTPS 地址，并记录 SHA-256。
- 成功标准包括 ROCm/HIP GPU 计算、ComfyUI API、真实工作流和桌面启动器测试，而不只是浏览器能打开。

## 项目结构（开发者）

```text
plugins/deploy-comfyui-amd-windows/
├─ launcher/                  独立图形向导及 portable ZIP 入口
├─ skills/.../SKILL.md        智能体工作流程
├─ skills/.../scripts/        检测、规划、部署和验证脚本
└─ .codex-plugin/plugin.json  Codex 插件清单
packaging/                    单文件 EXE/ZIP 构建脚本
.github/workflows/release.yml 标签发布时自动生成 Release 文件
```

本地构建发布包：

```powershell
.\packaging\build-release.ps1 -Version 0.2.0
```

输出位于 `dist/`。推送 `v*` 标签后，GitHub Actions 会自动构建 EXE、portable ZIP、SHA-256 清单并附加到 GitHub Release。

## English quick start

This is an unofficial community deployment tool for ComfyUI on AMD Radeon GPUs under Windows.

Most users should open **Releases** and download `Community-Setup-for-ComfyUI-AMD-Windows.exe`. Double-click it and follow `STEP 1 → STEP 5`. No Codex, coding agent, Python, or Node.js is required to start the wizard. The wizard inspects the PC first and asks for explicit approval before downloads or system changes.

If security software blocks the unsigned preview EXE, download `Community-Setup-for-ComfyUI-AMD-Windows-portable.zip`, extract it, and double-click `launcher\Start-Community-Setup-for-ComfyUI.cmd`. Verify files against `SHA256SUMS.txt` when appropriate.

The current GUI automates the native Windows ROCm route. WSL ROCm, DirectML, unusual hardware, custom-node failures, and repair work may require the included Skill plus a capable coding agent.

## License and naming

MIT. This independent community project is not affiliated with, endorsed by, or sponsored by ComfyUI, AMD, Microsoft, or OpenAI. Product names are used only to describe compatibility and purpose. The red block-A icon is original community artwork and does not reuse official logo artwork or wordmarks.
