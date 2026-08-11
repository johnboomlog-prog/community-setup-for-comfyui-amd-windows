# Troubleshooting by failed gate

## Host and PyTorch

- Unsupported GPU/driver/Windows/Python: re-check AMD's current matrix; do not improvise wheel combinations.
- Missing DLL: verify the current Microsoft Visual C++ 2015–2022 redistributable and AMD driver before copying third-party DLLs.
- `torch.cuda.is_available()` false: inspect `torch.__version__`, `torch.version.hip`, driver, Python ABI, and whether pip replaced AMD wheels.
- Non-AMD device: the wrong interpreter/backend is active.
- HIP allocation/kernel failure: cold-start; the process context may remain unusable.

## ComfyUI and launcher

- Browser opens but API is absent: inspect console and port listener; UI launch is not health.
- Core API works but nodes are missing: verify the exact Python, import logs, dependencies, and startup environment.
- A bundle launcher exposes nodes but direct launch does not: compare environment variables, MSVC `PATH/INCLUDE/LIB`, working directory, and Python path.
- Duplicate instances: identify the exact PID owning the port and inspect its command line before stopping it.
- Truncated batch lines or “not recognized”: regenerate as UTF-8 without BOM and CRLF.
- Blocked PowerShell: use per-process `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <known-script>`, not a global policy change.

## Security and performance

Review the exact Windows Security, Smart App Control, or antivirus event. An event marked “allowed” argues against it being the current blocker. Prefer a narrow allow-list for the pinned Python executable or install folder; never disable all protection.

Warm the full model/node path before measuring and separate loading, sampling, VAE, and encoding. Windows GPU counters can spike above 100%, and API VRAM can differ from driver allocation; use them as trends and successful wall-clock execution as the primary measure.
