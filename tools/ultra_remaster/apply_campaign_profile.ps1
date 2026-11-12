# Apply a reversible Campaign-first performance preset to MW32011NCP.
# No injection, DLL loading, NVIDIA binary bundling, or HDR enablement occurs here.
# Run against the generated mw3ncp_config.ini next to iw5sp.exe / mod d3d9.dll.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,
    [ValidateSet('FpsFirst', 'UltraPreview')]
    [string]$Profile = 'FpsFirst',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config missing. Start MW3 with MW32011NCP installed once, then point -ConfigPath at mw3ncp_config.ini."
}
$resolved = (Resolve-Path -LiteralPath $ConfigPath).ProviderPath
if ([System.IO.Path]::GetFileName($resolved) -ine 'mw3ncp_config.ini') {
    throw "Refusing to modify a file not named mw3ncp_config.ini."
}
if (-not (Test-Path -LiteralPath (Join-Path (Split-Path $resolved -Parent) 'iw5sp.exe') -PathType Leaf)) {
    Write-Warning 'iw5sp.exe was not found beside this config. Make sure it is the MW3 (2011) Campaign installation.'
}

# The same INI API used by the native mod preserves other sections and settings.
# Windows-specific by design; this mod only runs under Windows.
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class CampaignIniApi {
    [DllImport("kernel32.dll", EntryPoint = "GetPrivateProfileStringW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint Read(string section, string key, string fallback,
        StringBuilder buffer, uint bufferSize, string path);
    [DllImport("kernel32.dll", EntryPoint = "WritePrivateProfileStringW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool Write(string section, string key, string value, string path);
}
'@

function Read-Setting([string]$Section, [string]$Key) {
    $missing = '__MW3NCP_SETTING_MISSING__'
    $buffer = [System.Text.StringBuilder]::new(256)
    [void][CampaignIniApi]::Read($Section, $Key, $missing, $buffer, [uint32]$buffer.Capacity, $resolved)
    return $buffer.ToString()
}

# All names and sections below are checked against proxy_d3d9/src/mod_config.cpp.
# Render scale defines the REAL input size; DLSSModeX64 alone does not.
$common = [ordered]@{
    GraphicsApi = 'Vulkan'
    StreamlineEnabled = '1'
    ForceAnisotropicFiltering = '1'
    ForceHighQualityLighting = '0'
    FramePacingEnabled = '1'
    WaitCoalescingEnabled = '1'
    IwdReadAccelEnabled = '1'
    SkipRedundantShadowActivation = '1'
    SkipRedundantConsoleFontInit = '1'
    SkipRedundantMasterSequencerReactivation = '1'
    SkipRedundantOrchestratorExtraCalls = '1'
    PauseBlurStepCap = '2'
    ProactiveLevelTexturePreload = '0'
    CustomAssetOverrides = '1'
    MotionBlurEnabled = '0'
}

$video = [ordered]@{}
foreach ($key in $common.Keys) { $video[$key] = $common[$key] }
if ($Profile -eq 'FpsFirst') {
    $video['InternalRenderScalePercent'] = '67'
    $video['TextureRenderRes'] = '1x'
    $video['BulkTexturePrecache'] = '0'
    $video['ForceHighQualityShadows'] = '0'
} else {
    # An optional second benchmark. 2x textures can cause cache-building hitches.
    # 75% render scale still permits DLSS upscaling; avoid DLAA (>100%).
    $video['InternalRenderScalePercent'] = '75'
    $video['TextureRenderRes'] = '2x'
    $video['BulkTexturePrecache'] = '0'
    $video['ForceHighQualityShadows'] = '1'
}

$settings = [ordered]@{
    Video = $video
    Experimental = [ordered]@{
        DLSSModeX64 = '3'                # eMaxQuality (NOT a render-scale override)
        DlssNeuralRenderingEnabled = '0' # detection only; no functioning DLSS 5 eval yet
        LiveBlurStepCap = '3'
    }
}

$changes = @(
    foreach ($section in $settings.Keys) {
        foreach ($key in $settings[$section].Keys) {
            $old = Read-Setting $section $key
            $new = [string]$settings[$section][$key]
            if ($old -cne $new) {
                [PSCustomObject]@{ Section = $section; Key = $key; Old = $old; New = $new }
            }
        }
    }
)

Write-Host "MW3 Campaign preset: $Profile"
if ($changes.Count -eq 0) {
    Write-Host 'No changes: every target setting already matches.'
    return
}
$changes | Format-Table Section, Key, Old, New -AutoSize | Out-Host
if ($DryRun) {
    Write-Host 'Dry run: no file was changed and no backup was needed.'
    return
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$backup = "$resolved.before-$stamp-$([Guid]::NewGuid().ToString('N').Substring(0,8)).bak"
Copy-Item -LiteralPath $resolved -Destination $backup -ErrorAction Stop
Write-Host "Original backed up: $backup"

try {
    foreach ($change in $changes) {
        if (-not [CampaignIniApi]::Write($change.Section, $change.Key, $change.New, $resolved)) {
            throw "Write failed for [$($change.Section)] $($change.Key)."
        }
        if ((Read-Setting $change.Section $change.Key) -cne $change.New) {
            throw "Verification failed for [$($change.Section)] $($change.Key)."
        }
    }
}
catch {
    Copy-Item -LiteralPath $backup -Destination $resolved -Force
    throw "Config restored from backup after failure: $_"
}

Write-Host 'Preset applied and re-read successfully. RESTART the game: render-scale render targets are created at launch.'
Write-Host 'This does not add native HDR10 or functional DLSS 5 Neural Rendering.'
