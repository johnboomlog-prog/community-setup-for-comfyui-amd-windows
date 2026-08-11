# AMD ComfyUI Windows Guided Deployment

[中文](#中文说明) | [English](#english)

An open-source Codex plugin and portable `SKILL.md` workflow for deploying ComfyUI on AMD Radeon GPUs under Windows.

The plugin starts with read-only inspection, checks current AMD compatibility evidence, plans storage and Windows page-file capacity, selects a supported backend route, validates real ROCm computation and inference, and creates a verified desktop launcher.

> Status: `0.1.0` preview. Windows-native ROCm is the most complete automated route. WSL ROCm and DirectML have decision guidance but are not yet automated to the same end-to-end level.

## Safety principles

- No CUDA-only dependencies for AMD deployments.
- No download or system change before inspection and user approval.
- No silent GPU driver installation, antivirus disabling, UAC disabling, or global execution-policy changes.
- New deployments use a new or empty installation root.
- Downloads are restricted to reviewed HTTPS origins and recorded with SHA-256 after retrieval.
- Success requires GPU computation, ComfyUI API checks, a real workflow, and launcher tests—not merely an open browser window.

## Install as a Codex marketplace plugin

Clone [johnboomlog-prog/amd-comfyui-codex-marketplace](https://github.com/johnboomlog-prog/amd-comfyui-codex-marketplace), then add its root as a local marketplace:

```powershell
codex plugin marketplace add <path-to-this-repository>
codex plugin add deploy-comfyui-amd-windows@amd-comfyui-community
```

Start a new Codex task after installation and invoke:

```text
Use $deploy-comfyui-amd-windows to inspect this AMD Windows computer and guide me through a safe ComfyUI deployment.
```

## Install as a standalone skill

Copy:

```text
plugins/deploy-comfyui-amd-windows/skills/deploy-comfyui-amd-windows
```

into your agent's user-level or project-level skills directory. Agents without native skill support can be instructed to read the included `SKILL.md` as the governing procedure.

## Validated baseline

The current preview has been exercised on Windows 11 with an AMD Radeon RX 7900 XTX, Python 3.12, ROCm PyTorch, and ComfyUI. Its reusable tests cover:

- PowerShell parsing and skill structure;
- guided onboarding metadata;
- ROCm/HIP tensor allocation and matrix multiplication;
- ComfyUI API health and node registration;
- real workflow submission and completion;
- deterministic desktop launcher generation;
- storage and page-file planning gates.

Hardware and software compatibility changes over time. The skill intentionally rechecks AMD's current primary documentation instead of treating this baseline as universal support.

## English

Use the plugin from chat. It explains each phase, asks one consequential choice at a time, requests narrowly scoped approval before mutations, persists evidence reports across reboots, and answers in the user's language.

## 中文说明

这是一个面向 AMD Radeon Windows 用户的引导式 ComfyUI 部署插件。用户在聊天中启动 Skill 后，它会先进行只读检查，再依次说明并询问用途、目标磁盘和虚拟内存方案。下载、安装、系统修改和重启前都会明确说明并征求同意。

推荐调用方式：

```text
使用 $deploy-comfyui-amd-windows 引导我从零部署这台 AMD Windows 电脑上的 ComfyUI。
```

## License

MIT. This project is independent community software and is not affiliated with AMD, Microsoft, ComfyUI, or OpenAI.
