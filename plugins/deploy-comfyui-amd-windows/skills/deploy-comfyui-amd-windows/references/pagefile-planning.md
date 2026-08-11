# Windows page-file planning

The page file extends the Windows commit limit: approximately physical RAM plus page files. RAM-heavy model loading, VAE decode, upscaling, video frames, and other open applications can exhaust commit even when GPU VRAM is the immediate accelerator memory. A page file reduces abrupt allocation failures; it does not make disk perform like RAM and heavy paging will be slow.

Microsoft states that page-file sizing is workload-specific and depends on peak commit charge and crash-dump requirements. Prefer Windows-managed sizing, especially on systems above 32 GB RAM. See [Microsoft's sizing guidance](https://learn.microsoft.com/en-us/troubleshoot/windows-client/performance/how-to-determine-the-appropriate-page-file-size-for-64-bit-versions-of-windows).

## Decision sequence

1. Inspect `AutomaticManagedPagefile`, `Win32_PageFileSetting`, `Win32_PageFileUsage`, committed bytes, commit limit, peak use, RAM, and all fixed volumes.
2. Explain the reason and tradeoff before asking the user to choose.
3. Offer `AutomaticManaged` as the default. Offer `Custom` only when the user wants predictable disk reservation or an AI-specific target drive.
4. For custom sizing, present the plan's minimum, recommended, and maximum-recommended values and ask the user for a concrete value inside that range. Recommend initial size equal to maximum size when predictable reservation matters.
5. Use NTFS/ReFS on a fast SSD/NVMe. Preserve at least 20 GB after projected growth. Do not assume the largest drive is the fastest; ask when media type cannot be mapped reliably.
6. Preserve other page files by default. A small system-volume page file may be needed for crash dumps. Never remove it silently.
7. Run `set-pagefile.ps1` with `-WhatIf`, show the exact change, obtain explicit approval, then run elevated. Reboot and regenerate both host report and deployment plan.

The bundled custom ranges are AI workload planning policy, not Microsoft guarantees. They scale with RAM and workload profile. Real peak commit observations should override the heuristic during later tuning.
