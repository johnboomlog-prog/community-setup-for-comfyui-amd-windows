# Compatibility gate

Always re-check these primary sources because supported GPUs, drivers, Python versions, and wheel URLs change:

- AMD Radeon Windows compatibility matrix: <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/windows/windows_compatibility.html>
- AMD PyTorch on Windows installation: <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installryz/windows/install-pytorch.html>
- AMD HIP SDK Windows requirements: <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/shared/hipsdk/reference/system-requirements.html>
- AMD WSL compatibility matrix: <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/wsl/wsl_compatibility.html>
- AMD ComfyUI Windows guide: <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/advanced/advancedryz/windows/comfyui/installcomfyui.html>
- ComfyUI system requirements: <https://docs.comfy.org/installation/system_requirements>
- ComfyUI manual install: <https://docs.comfy.org/installation/manual_install>

## Decision rules

1. Match the exact Radeon model and gfx architecture independently against the native Windows and WSL matrices before choosing a route.
2. Match Windows build, Radeon driver, Python ABI, ROCm release, and PyTorch wheel as a set. Do not mix releases.
3. AMD's Windows ROCm support is a subset of Linux ROCm. Linux support does not establish Windows support.
4. Prefer AMD's Python constraint over ComfyUI's general Python recommendation when they differ.
5. Verify wheel architecture and use 64-bit Python. Reject a Microsoft Store alias that cannot create a normal isolated environment.
6. On PyTorch ROCm, device functions remain under `torch.cuda`. Require both `torch.version.hip` and an AMD device name.
7. Treat precision and kernel features separately from basic GPU support. A GPU may run PyTorch while a particular FP8 or fused-attention path remains unsupported.

For unsupported native-Windows combinations, offer an officially supported Linux configuration first. WSL or DirectML may be reasonable, but they are separate backends with different compatibility and performance; never label them ROCm-Windows.
