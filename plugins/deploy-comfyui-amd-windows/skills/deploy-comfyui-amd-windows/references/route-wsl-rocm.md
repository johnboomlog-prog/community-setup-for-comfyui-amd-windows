# WSL ROCm route

Use this route only when the exact GPU appears in AMD's current WSL compatibility matrix and native Windows is unavailable or the user explicitly prefers WSL.

Primary sources:

- WSL compatibility matrix: <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/compatibility/compatibilityrad/wsl/wsl_compatibility.html>
- AMD WSL guide: <https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installrad/wsl/howto_wsl.html>
- Microsoft WSL installation: <https://learn.microsoft.com/windows/wsl/install>

## Gates

1. Verify 64-bit Windows 11, virtualization firmware, WSL2, a currently supported Ubuntu release, exact GPU SKU, and AMD's required Windows WSL driver.
2. If WSL or virtualization requires installation/reboot, record the resume point and stop until reboot completes.
3. Follow AMD's current ROCDXG/WSL instructions; do not reuse native-Windows wheel URLs inside Linux.
4. Create a Linux virtual environment, install the current AMD-supported PyTorch/ROCm combination, and verify `torch.version.hip`, AMD device name, and GPU matrix multiplication inside WSL.
5. Clone and pin official ComfyUI inside the Linux filesystem, not `/mnt/c`, for normal performance.
6. Start ComfyUI listening on localhost, verify Windows can reach `/system_stats`, then run a real starter workflow.
7. Create a Windows `.cmd`/shortcut that starts the selected WSL distro with the pinned Linux launch script and then opens the localhost URL. Prevent duplicate instances through API health checking.

Do not call this route complete until both the Linux GPU test and Windows-to-WSL ComfyUI API/inference tests pass.
