# MW3 Campaign-only DLSS 5: local runtime audit

This is a read-only preparatory step, NOT a functioning DLSS 5 integration.
The existing iw5sp.exe process is already x64. MW32011NCP already offers
Vulkan via DXVK and conventional DLSS/DLAA; DLSS 5 Neural Rendering is
currently load-status detection only, not actual neural evaluation.

## Before testing any binaries

1. Keep the experiment limited to Campaign (not Multiplayer/VAC).
2. Do NOT commit NVIDIA proprietary DLLs, commercial-game files or third-party
   injection payloads to GitHub.
3. From the repository root on Windows, run a read-only local inventory:

        powershell -NoProfile -File .\tools\dlss5_campaign\audit_runtime.ps1 -Directory "C:\path\to\DLSS5" -Recurse > dlss5-runtime-audit.json

4. Review the reported SHA256, architecture, Authenticode status and signer.
   A valid signature is helpful for verifying the publisher but does not
   guarantee the file is harmless. Never automatically import any .reg file.
5. NVIDIA DLLs with missing/invalid NVIDIA signatures must be checked
   against an independently verified official SDK/runtime distribution.
   Third-party add-ons need separate source and binary inspection.
6. File names alone DO NOT establish DLSS 5 compatibility.

For a **real antivirus scan** of the checkout and local runtime files on
Windows with Microsoft Defender (separate from this read-only inventory), run:

        Start-MpScan -ScanType CustomScan -ScanPath "C:\path\to\MW32011NCP"
        Start-MpScan -ScanType CustomScan -ScanPath "C:\path\to\DLSS5"

Defender results can still contain false positives or miss malware. Use the
actual archives/build artifacts you intend to run, not just the source tree.

## Repository security: limited initial review

At the start, this fork was identical to k8se10/MW32011NCP at commit
b08a5095b102f6d857e6c7613878291016f9dffa. A targeted source review
of Windows scripts and GitHub Actions found no obvious exfiltration command.
This is NOT a virus-free certification: the repository also contains a
precompiled DXVK d3d9.dll and native process-hooking source code. Some
scripts and build actions download third-party dependencies. Neither the
compiled DLL nor any user-provided NVIDIA binaries have been antivirus
scanned or executed during this review.

## Missing engineering work (not implemented here)

- Obtain a verifiably compatible NVIDIA Streamline DLSS_NR API header and
  matching binaries, with legitimate permission to use them.
- Explicitly gate Neural Rendering on the Campaign mode, x64, Vulkan and
  supported RTX 50-series hardware; the existing executable-level SP gate
  also includes Survival.
- Implement validated neural options and input/output resource tagging
  (color, depth, motion vectors), plus a correctly synchronized Vulkan
  command-buffer evaluation and graceful DLSS Quality fallback.
- Build with MSVC x64, inspect diagnostics and test in-game only in Campaign.
  No DLSS 5 support claim should be made until genuine neural evaluation
  is proven via logs and visual output.

Background:
https://github.com/NVIDIA-RTX/Streamline
https://developer.nvidia.com/blog/whats-new-for-game-developers-dlss-5-with-3d-guided-neural-rendering-nvidia-ace-updates-and-new-rtx-kit-capabilities/
