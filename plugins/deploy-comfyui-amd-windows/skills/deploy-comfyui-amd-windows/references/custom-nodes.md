# AMD custom-node admission

Before installation, determine whether upstream explicitly supports Windows AMD/ROCm or has a credible maintained ROCm branch; whether dependencies replace torch; whether it compiles CUDA or requires `nvcc`, cuDNN, TensorRT, xFormers, NVIDIA FlashAttention, or NVIDIA-only SageAttention; whether it silently falls back to CPU/generic attention; whether the requested model precision is supported on the exact GPU; and whether it can be pinned and smoke-tested.

Install one node family, restart, and query `/object_info` for required class types. Run a tiny representative job while recording wall time, GPU activity, VRAM, process memory, and logs. Compare against a clean baseline. UI registration alone is not evidence of acceleration.

Block swap and VAE tiling trade memory for transfers and scheduling overhead. Warm the complete path, then benchmark one variable at a time. Larger batches, Torch Compile, and graph capture are not automatically faster on Windows AMD; keep them disabled until repeatable tests show a wall-clock benefit without residual paging or memory penalties.

After any HIP kernel error, terminate the affected ComfyUI process and cold-start before interpreting another result.
