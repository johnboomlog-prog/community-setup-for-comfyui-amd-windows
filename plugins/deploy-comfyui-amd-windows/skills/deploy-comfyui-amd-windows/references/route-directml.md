# DirectML fallback route

DirectML is a fallback, not ROCm. Use it only when no official native-Windows or WSL ROCm route matches and the user explicitly accepts lower performance and narrower model/custom-node compatibility.

Primary source: <https://learn.microsoft.com/windows/ai/directml/pytorch-windows>

## Gates

1. Verify Windows build 16299 or newer and a current GPU driver.
2. Resolve the current `torch-directml` Python and PyTorch constraints from Microsoft/PyPI before creating the environment. Do not mix it with ROCm wheels.
3. Clone and pin official ComfyUI, install compatible requirements, and launch with `--directml`.
4. Verify the DirectML device explicitly; `torch.version.hip` should not be used as this route's success condition.
5. Run a small supported image workflow. Reject models/nodes requiring unsupported FP8, CUDA, Triton, ROCm kernels, or large-memory behavior not proven on DirectML.
6. Label the deployment and launcher `DirectML experimental`; never report it as native ROCm.

If dependency constraints cannot be resolved cleanly or the starter inference fails, mark the route blocked and recommend supported hardware/OS rather than adding ZLUDA or unofficial GPU overrides automatically.
