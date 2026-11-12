# MW3 (2011) Campaign: HDR strategy alongside DLSS 5

**Status: HDR support has NOT been added to MW32011NCP by this document.**
This is a reproducible test plan for the existing x64 Campaign renderer.
The user's RTX 5060 Ti is compatible with NVIDIA RTX HDR. A real HDR
monitor/TV and a supported Windows installation are still required.

## Uploaded "PhotorealisticCODMW3" Nexus mod: source inspection

The user-provided ZIP includes a ReShade 3.4.1 **32-bit** D3D9 proxy DLL,
a log from an old **iw5mp.exe** session, and these active preset effects:

- AdaptiveSharpen
- Bloom (qUINT)
- LiftGammaGain
- Lightroom (qUINT)
- MXAO (qUINT)
- UnsharpMask

There is **no HDR10 / PQ / scRGB output pipeline** in that preset.
Its exposure, bloom and grading are SDR post-processing operations.
Do **not** install its 32-bit d3d9.dll on the present x64 iw5sp.exe.
Do not replace MW32011NCP's x64 Vulkan/DXVK D3D9 proxy with ReShade's.

## Practical HDR output path available now: NVIDIA RTX HDR

This is *SDR-to-HDR conversion at the driver/display stage*, not native
HDR scene rendering, and it does not require a code change to the mod.
NVIDIA says RTX HDR supports D3D9-12 and Vulkan.

Prerequisites documented by NVIDIA (subject to driver changes):
- Windows 11, version 22H2 (OS build 22621) or newer.
- GeForce RTX 20-series or newer (RTX 5060 Ti qualifies), single GPU.
- HDR-capable monitor reported at least HDR400; Windows "Use HDR" on.
- NVIDIA driver at least 565.90 and current NVIDIA App.
- Turn **Windows Auto HDR OFF** and do not enable in-game native HDR in
  parallel. Disable Fast Sync. Fullscreen / appropriate flip presentation
  is required; DXVK on Windows may present fullscreen differently.

Procedure:
1. Enable HDR: Windows Settings -> System -> Display -> HDR.
2. Disable Windows Auto HDR on that display.
3. Update NVIDIA App and driver.
4. NVIDIA App -> Graphics -> select/add iw5sp.exe (not iw5mp.exe) ->
   RTX HDR -> On, if the setting is available.
5. Keep MW32011NCP GraphicsApi=Vulkan and StreamlineEnabled=1 for
   conventional DLSS, and start **Campaign**. RTX HDR is a
   separate NVIDIA-driver effect; it is not a new game/mod INI key.
6. Use NVIDIA overlay (Alt+F3 / Alt+Z Game Filters) for RTX HDR peak
   brightness, middle gray, contrast and saturation.
7. Compare identical scenes with RTX HDR ON vs OFF; confirm that Windows
   display remains in HDR mode. Check highlights and HUD for clipping.
   A Windows "HDR on" indication alone does not prove RTX HDR is active.

If RTX HDR is unavailable, check screen capability/Windows version/
driver, that Auto HDR is disabled and that iw5sp.exe is correctly targeted.
Fullscreen behavior can vary with the bundled DXVK fork, so treat this
as an **unverified integration test** and do not promise compatibility.

Do not configure dxgi.enableHDR as a magic switch: it exposes an HDR10
DXGI color space to applications that support it, principally D3D11/
DXGI. MW3 uses D3D9 and has no native HDR presentation implementation;
the flag alone does not convert its SDR frame into HDR.

## Long-term native renderer integration (not built here)

To add an independent HDR output *within* MW32011NCP rather than relying
on RTX HDR requires a separate engineering milestone:

1. Define a user-facing HDR mode (Disabled / HDR10) and preserve a
   correct SDR fallback. Keep the user option separate from DLSS/NR.
2. Verify display HDR support and Vulkan WSI color-space/format
   availability, including the requirements for full-screen Windows DXVK.
3. Decide where to intercept the final post-DLSS/NR **scene + HUD**
   image; add correct linear-light/tone-mapping/color-space conversion,
   and HDR10 PQ/BT.2020 output metadata when supported.
4. Ensure brightness/paper-white/peak-nits and UI composition are
   handled consistently. A post-process SDR->HDR conversion cannot
   recover highlight information already clipped by MW3's SDR render.
   Truly native scene HDR requires substantial engine render-target
   and lighting work.
5. Never apply NVIDIA RTX HDR or Windows Auto HDR to an already
   HDR-outputting renderer: double tone mapping degrades output.
6. Run side-by-side SDR/HDR and DLSS Quality (and, later, true DLSS 5)
   experiments, checking frame pacing, colors, UI and presentation.
7. Keep all experimental hooks strictly Campaign-only and separate
   from the VAC-protected multiplayer executable.

## Primary references

- NVIDIA RTX HDR requirements: https://nvidia.custhelp.com/app/answers/detail/a_id/5521
- NVIDIA App graphics settings: https://www.nvidia.com/en-us/geforce/news/gfecnt/202410/nvidia-app-beta-update-g-sync-controls-rtx-hdr-multi-monitor/
- DXVK Windows notes (HDR/fullscreen caveats): https://github.com/doitsujin/dxvk/wiki/Windows
- Existing in-repo renderer: proxy_d3d9/src/streamline_evaluate_x64.cpp
- DLSS 5 work-in-progress: tools/dlss5_campaign/README.md
