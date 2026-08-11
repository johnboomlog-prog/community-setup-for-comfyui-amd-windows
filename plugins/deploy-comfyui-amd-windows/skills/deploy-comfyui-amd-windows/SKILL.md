---
name: deploy-comfyui-amd-windows
description: "Guide a Radeon/A-card Windows user through an interactive, evidence-based ComfyUI deployment: inspect the computer, explain and collect workload/storage/page-file choices, select native ROCm, WSL ROCm, or an explicitly accepted fallback, install or repair the backend, verify real inference, and create a desktop launcher. Use for zero-to-working deployments, AMD bundle migration, AMD node compatibility, or broken ROCm/HIP recovery. Do not use for NVIDIA CUDA deployments."
---

# Deploy ComfyUI on AMD Windows

Build a reproducible AMD deployment chosen from the actual host, not from a preselected backend. Treat success as a chain of verified gates, not as “the UI opened.” Work in the user's chosen install directory and preserve existing installations unless the user explicitly authorizes replacement.

This directory follows the portable `SKILL.md` plus bundled resources pattern. Read [references/agent-portability.md](references/agent-portability.md) only when installing it into another coding agent.

## User interaction contract

Make the skill visibly interactive. On a new invocation, begin in the user's language with a short welcome that names the skill, states that phase 1 is read-only, and explains that no software or system setting will change without approval. Do not ask the user to paste another long prompt.

If the user has not already stated the goal, ask only this first question and wait:

```text
已启动“AMD ComfyUI Windows 部署”。我会先只读检查硬件、磁盘和虚拟内存，再给出适配路线；任何下载或系统修改都会先征求你的同意。

你这次希望：
1. 从零安装 ComfyUI
2. 修复或升级现有 ComfyUI
3. 迁移现有 AMD 整合包
4. 只检查兼容性和部署建议

回复序号即可；如果知道现有 ComfyUI 路径，也可以一起发给我。
```

If the user's opening request already answers this question, acknowledge the selected goal and immediately start read-only discovery. Do not redundantly ask for information that scripts can discover.

Keep the user oriented throughout the run:

- announce the current phase: `只读检查`, `路线选择`, `部署计划`, `等待批准`, `安装`, or `验证与交付`;
- after discovery, summarize GPU, RAM, disks, page file, existing installation, and recommended route before asking the next decision;
- ask one consequential choice at a time, normally workload profile first, then target volume, then page-file policy when attention is required;
- before every mutation, state exactly what changes, where, approximate download/disk use, whether administrator rights or reboot are required, and how to roll back;
- after every gate, report `通过`, `未通过`, or `等待用户操作` and name the generated evidence file;
- when reboot is required, persist the reports and tell the user to return to the same conversation with `已重启，继续 AMD ComfyUI 部署`; resume by rereading the reports and rechecking live state.

Suggested explicit invocation for clients that support `$skill-name`:

```text
使用 $deploy-comfyui-amd-windows 引导我从零部署这台 AMD Windows 电脑上的 ComfyUI。先说明操作方式并进行只读检查，再让我选择用途、磁盘和虚拟内存方案。
```

## Operating rules

- Start read-only. Inventory the host before installing, upgrading, killing processes, changing security settings, or editing an existing environment.
- Consult AMD's current Windows compatibility matrix and PyTorch installation page on every new deployment. Never assume versions recorded in this skill are still current.
- Use native ROCm PyTorch only when the exact GPU, Windows version, Python version, driver, and PyTorch combination is currently supported. For unsupported hardware, explain the supported Linux/WSL or DirectML alternatives; do not force a misleading native ROCm install.
- Interpret `torch.cuda.*` as PyTorch's device API. Confirm the device name and `torch.version.hip`; the namespace alone does not imply NVIDIA.
- Reject CUDA-only dependencies by default, including xFormers, TensorRT, CUDA FlashAttention, and NVIDIA-only SageAttention builds. Require explicit AMD/ROCm evidence and an isolated smoke test for acceleration nodes.
- Make every mutation reversible. Pin repository commits and package versions, checksum downloaded installers/wheels, keep a report, and never overwrite a healthy install during discovery.
- Do not globally disable antivirus, Smart App Control, execution policy, or UAC. Diagnose first and request the narrowest necessary approval or allow-list.

## Workflow

### 1. Discover the device before choosing a backend

Read [references/compatibility.md](references/compatibility.md), then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/inspect-host.ps1 -OutputPath amd-comfyui-host.json
```

If the user points to an existing installation, pass `-ComfyUIRoot` and `-PythonPath`. Once a candidate install location is known, pass `-InstallRoot` to assess that volume. Use `-SearchRoot` only for bounded directories the user placed in scope; never recursively scan an entire system drive by default.

Do not download or install anything yet. The report must cover OS/build/architecture, exact AMD GPU, driver, CPU virtualization, RAM, page-file automatic mode/settings/runtime usage, commit charge/limit, disk, Python/Git/winget/MSVC, WSL features/distributions, port ownership, and existing ComfyUI.

Inspect every fixed volume's filesystem, capacity, and free bytes. Read [references/storage-planning.md](references/storage-planning.md). Reject FAT32 for model storage, prefer NTFS/ReFS for the Python environment, and never default to C: merely because it exists.

### 2. Select the deployment route

Compare the host report with current primary-source matrices:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/select-deployment-route.ps1 `
  -HostReportPath amd-comfyui-host.json -OutputPath amd-comfyui-route.json
```

Use this priority unless the user explicitly chooses otherwise:

1. `windows-native-rocm`: exact GPU and Windows environment pass AMD's native Windows matrix.
2. `wsl-rocm`: native Windows is ineligible but the exact GPU passes AMD's WSL matrix; read [references/route-wsl-rocm.md](references/route-wsl-rocm.md).
3. `windows-directml-experimental`: only with explicit `-AllowDirectMLFallback`; read [references/route-directml.md](references/route-directml.md).
4. `blocked`: no supported route. Stop rather than installing an arbitrary wheel combination.

An agent must review the route evidence. Never infer support solely from “RX 7000 series” or RDNA generation when the exact SKU is absent.

### 3. Resolve a pinned plan for the selected route

Follow [references/deployment-workflow.md](references/deployment-workflow.md). Resolve current versions and download URLs from primary sources. Record URLs, SHA-256 values, repository commit, install root, Python executable, and intended launcher location before mutation.

Generate a machine-specific plan directly from AMD's current official documentation and the official ComfyUI repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/new-official-plan.ps1 `
  -RoutePath amd-comfyui-route.json -InstallRoot <new-empty-directory> `
  -WorkloadProfile StarterImage `
  -OutputPath amd-comfyui-install-plan.json
```

Choose `StarterImage`, `ImageProduction`, `VideoProduction`, or `Custom` before planning. The plan performs HEAD requests for current component/model sizes, estimates temporary downloads plus installed expansion, adds a safety margin and workload reserve, checks the target filesystem/free space, and ranks alternative volumes. It reports a dynamic hard minimum plus recommended free-space floors of 120 GB for starter images, 250 GB for image production, and 600 GB for video production; these mean free space before installation, not total disk size. Exit code 3 means the hard storage gate did not pass; do not start downloads.

Review the captured GPU match, required Python and driver, every AMD artifact URL, and the pinned ComfyUI commit. The plan parser must resolve both the ROCm SDK artifacts and torch/torchvision/torchaudio; three PyTorch wheels alone are not a complete current Windows installation.

Read [references/pagefile-planning.md](references/pagefile-planning.md). Explain that the page file extends the Windows commit limit for RAM-heavy model loading, VAE, upscaling, video frames, and concurrent applications, but heavy paging is slower than RAM. Present the detected configuration and the plan's custom minimum/recommended/maximum range. Ask the user to choose Windows automatic management or a concrete custom value inside the range; do not mutate the page file merely because the plan generated a recommendation.

For an approved change, dry-run first. `AutomaticManaged` lets Windows select size and placement. `Custom` lets the user select an NTFS/ReFS drive and reviewed size while preserving other page files:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/set-pagefile.ps1 `
  -PlanPath amd-comfyui-install-plan.json -Mode Custom -DriveLetter E: `
  -InitialGB 64 -MaximumGB 64 -ConfirmPageFileChange -WhatIf
```

Run the approved command elevated without `-WhatIf`, reboot, then regenerate the host report and deployment plan. Never silently remove the system-volume page file because crash-dump requirements may depend on it.

The bootstrap blocks an `insufficient` page-file plan. A `minimum-only` plan requires explicit user acceptance through `-AllowBelowRecommendedPageFile`; prefer reconfiguration to the recommended value. This override never converts an insufficient plan into a supported one.

Use `scripts/download-verified.ps1` for publisher artifacts with known hashes. AMD's installation page may not publish hashes for its wheel links; the bootstrap restricts first download to `https://repo.radeon.com`, then records every resulting SHA-256 in `artifact-manifest.json` before installation.

### 4. Bootstrap a computer without ComfyUI

After an agent has confirmed the exact GPU in AMD's current matrix and the user has installed the required driver and rebooted, run a dry run first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/invoke-bootstrap.ps1 `
  -PlanPath amd-comfyui-install-plan.json -ConfirmSupportedGpu -DriverReady -WhatIf
```

Then rerun without `-WhatIf`. Add `-InstallPrerequisites` when Python 3.12, Git, or the VC++ runtime are missing. Add `-InstallBuildTools` only when planned custom nodes compile native extensions. The bootstrap creates a new virtual environment, downloads and records official ROCm SDK/PyTorch artifacts, verifies GPU compute, pins ComfyUI, installs requirements, re-verifies ROCm, creates the desktop launcher, starts it, waits for API health, and writes `deployment-report.json`.

If the selected volume only meets the hard minimum but is below the recommendation, stop and explain the risk. Use `-AllowBelowRecommendedSpace` only after the user explicitly accepts reduced room for models, caches, outputs, and retry files. Falling below the hard minimum can never be overridden.

By default it also downloads the starter SDXL Turbo checkpoint used in AMD's ComfyUI guide and runs the bundled 512×512 API workflow. This inference gate distinguishes “the server opened” from “the user can actually generate an image.” Use `-SkipStarterProfile` only when the user explicitly wants a runtime-only installation or selects another model profile; in that case, do not call the machine user-ready until a representative model workflow succeeds.

It deliberately refuses non-empty install roots and rechecks live free space immediately before mutation. It never installs the AMD graphics driver silently because driver selection and reboot are host-level safety boundaries.

### 5. Verify the compute layer

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-rocm-pytorch.ps1 -PythonPath <python.exe> -OutputPath rocm-test.json
```

The gate passes only when PyTorch imports, `torch.version.hip` is populated, `torch.cuda.is_available()` is true, the device is AMD Radeon, and a GPU allocation plus matrix multiplication complete. Do not proceed to custom nodes when this gate fails.

### 6. Start the minimal ComfyUI baseline

Start official ComfyUI without third-party custom nodes first. On environments that compile extensions, load the Visual Studio x64 build environment. Set process-local `HIP_VISIBLE_DEVICES`, `ROCM_SDK_TARGET_FAMILY`, and a writable `TRITON_CACHE_DIR`; do not add global variables unless the user asks.

Wait for `/system_stats` instead of relying on a browser window. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/test-comfyui-api.ps1 -RequiredNode KSampler,VAEDecode -OutputPath comfyui-api-test.json
```

The gate passes only if `/system_stats`, `/queue`, and `/object_info` respond and all required node types are registered.

### 7. Add custom nodes incrementally

Read [references/custom-nodes.md](references/custom-nodes.md). Install one node family at a time at a pinned revision. Restart, query `/object_info`, and execute the smallest representative workflow after each addition. Capture logs and timing. If a HIP kernel error occurs, restart ComfyUI before further tests because the process context may remain poisoned.

### 8. Create and verify the launcher

Generate a launcher only after the baseline API passes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/new-desktop-launcher.ps1 `
  -ComfyUIRoot <ComfyUI> -PythonPath <python.exe> -Port 8188
```

The generator creates a CRLF `.cmd` plus a `.lnk` using the included ComfyUI icon. The launcher health-checks `/system_stats`, avoids duplicate instances, loads `vcvars64.bat` when available, sets AMD variables only for the child process, preserves a visible log window, and opens the browser.

Keep Hugging Face, Torch, and Triton caches under the selected ComfyUI root so later model/node activity cannot silently fill the system drive.

Launch it once, wait for health, rerun the API test, close ComfyUI normally, then launch it a second time. A deployment is complete only when both cold starts succeed and a second click does not create another instance.

### 9. Hand off

Write a short deployment report containing exact GPU/driver/Windows/Python/PyTorch/HIP/ComfyUI versions; paths; passed and failed gates; required custom nodes; narrow security exceptions; rollback location; and verification commands. Use [references/troubleshooting.md](references/troubleshooting.md) when a gate fails. Never report completion merely because installation commands returned zero.

## Script inventory

- `scripts/inspect-host.ps1`: read-only Windows, GPU, toolchain, port, and existing-install inventory.
- `scripts/select-deployment-route.ps1`: compare the device with current official matrices and select a backend before downloads.
- `scripts/new-official-plan.ps1`: resolve a machine-specific plan from current AMD and ComfyUI primary sources.
- `scripts/set-pagefile.ps1`: apply an explicitly approved automatic or custom Windows page-file choice with validation and `WhatIf` support.
- `scripts/invoke-bootstrap.ps1`: deploy a new environment from the reviewed plan and validate it end to end.
- `scripts/test-rocm-pytorch.ps1`: structured ROCm/PyTorch GPU smoke test.
- `scripts/test-comfyui-api.ps1`: structured ComfyUI health and node-registration test.
- `scripts/invoke-workflow-smoke.ps1`: submit and wait for a real API workflow, failing on execution errors or timeout.
- `scripts/test-skill.ps1`: run the portable structural, ROCm, API, workflow, plan, and launcher self-test suite.
- `scripts/download-verified.ps1`: checksum-gated downloader.
- `scripts/new-desktop-launcher.ps1`: deterministic launcher and desktop shortcut generator.
