# Deployment workflow

## Preflight record

Record the approved install root and free space; Windows/GPU/driver/RAM/page file; Python/Git/MSVC locations; port owner and API health; existing installations/backups; official compatibility decision; and pinned artifact URLs, SHA-256 values, and commits.

## Clean installation sequence

1. Create a new versioned directory. Never install over an unknown bundle.
2. Select the exact 64-bit Python required by current AMD wheels.
3. Create a dedicated virtual environment or deliberately managed embedded Python.
4. Upgrade only packaging tools required by official instructions.
5. Install every ROCm SDK artifact currently listed by AMD, followed by the matching PyTorch, torchvision, and torchaudio artifacts. Record source URLs and local SHA-256 values.
6. Run `test-rocm-pytorch.ps1`; stop on failure.
7. Clone <https://github.com/comfyanonymous/ComfyUI> at a recorded commit.
8. Install requirements in the same interpreter. Ensure resolution does not replace AMD torch.
9. Start without third-party nodes and pass `test-comfyui-api.ps1`.
10. Add custom nodes one family at a time.
11. Install a reviewed starter model profile and execute a representative API workflow. API health without inference is only `runtime-ready`, not `user-ready`.
12. Generate and cold-start-test the launcher twice.

## Existing installations

Do not begin with broad upgrades. Capture `pip freeze`, Git revisions, startup scripts, custom nodes, model paths, API status, and logs. Back up configuration/workflows and record model directories. Prefer cloning the environment to a new versioned directory for risky upgrades.

## Download and permission policy

Prefer AMD, Python, Microsoft, and official ComfyUI sources. Pin Git commits. Verify publisher hashes; if none exists, record that limitation and require explicit trust before execution. Never execute a downloaded binary before validation.

Distinguish an agent sandbox denial from Windows host security. Request approval only for the exact write, process, package, or network operation. Use per-process `-ExecutionPolicy Bypass` for a known script when needed; do not alter machine-wide policy. Never copy secrets or agent credentials into reports.
