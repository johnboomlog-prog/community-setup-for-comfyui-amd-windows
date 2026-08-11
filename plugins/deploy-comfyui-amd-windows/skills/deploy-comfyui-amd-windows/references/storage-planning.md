# Storage planning gate

ComfyUI code is small compared with models, duplicated downloads, Python packages, compiler caches, previews, and video output. Treat storage as a pre-download compatibility gate.

## Inspect

- Enumerate fixed volumes with filesystem, total bytes, and free bytes.
- Resolve the intended install root to its actual volume.
- Prefer NTFS or ReFS. Reject FAT32 because individual model files commonly exceed its 4 GB limit. Treat exFAT as model-only storage, not the default Python/custom-node environment.
- Warn about very long paths and unusual permissions. Spaces and Unicode can work, but some third-party build scripts remain fragile; prefer a short path such as `D:\AI\ComfyUI-AMD` for a new general-purpose deployment.
- Check page-file placement separately; a nearly full system drive can still fail even when models live elsewhere.

## Estimate peak use

Use current remote `Content-Length` values when available. Include:

1. retained downloads;
2. expanded ROCm/Python packages and ComfyUI environment;
3. starter or selected production models;
4. Hugging Face, Torch, Triton, and custom-node build caches;
5. outputs and temporary video frames;
6. at least 20 GB safety margin.

Use workload reserves as planning policy, not exact promises:

- `StarterImage`: 30 GB future reserve;
- `ImageProduction`: 100 GB future reserve;
- `VideoProduction`: 300 GB future reserve;
- `Custom`: require an explicit reserve.

Report three distinct free-space thresholds. These numbers mean free space on the target volume before installation, not total disk capacity:

- hard minimum: dynamically calculated from current artifact sizes, expansion, workload reserve, and safety margin; block below it;
- recommended: at least 120 GB for `StarterImage`, 250 GB for `ImageProduction`, and 600 GB for `VideoProduction`, or 1.5 times the calculated hard minimum when that is larger;
- ideal: at least 200 GB, 500 GB, and 1 TB respectively, or 1.5 times the recommendation when that is larger.

Classify each viable NTFS/ReFS volume as `blocked`, `minimum-only`, `recommended`, or `ideal`. Do not silently deploy at `minimum-only`: require explicit user approval because model growth, cache rebuilds, previews, failed downloads, and video frames can exhaust the remaining capacity.

If an artifact does not expose a size, add an uncertainty reserve and flag the estimate. Do not begin a multi-gigabyte download when the target cannot satisfy estimated peak use.

## Cache placement

Set process-local `HF_HOME`, `HUGGINGFACE_HUB_CACHE`, `TORCH_HOME`, and `TRITON_CACHE_DIR` under the approved AI install root. Do not change machine-wide variables. Record cache paths in the handoff so users know what consumes space.
