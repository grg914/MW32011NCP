# MW3 (2011) Campaign x64 - DLSS-only profile and 4K mode-list workaround.
# No engine executable, Windows registry, Windows resolution, or config.cfg edits.
# Optionally stage d3d9.dll from the official v0.0.3-x64 ZIP.
# This applies a DLSS-focused profile to the existing mod, NOT a stripped binary.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GameDir,
    [string]$ReleaseZip,
    [ValidateRange(50, 100)]
    [int]$RenderScalePercent = 67,
    [switch]$FourKCheckOnly,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $GameDir -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $root 'iw5sp.exe') -PathType Leaf)) {
    throw 'iw5sp.exe not found. Select the MW3 (2011) Steam install folder.'
}
$dll = Join-Path $root 'd3d9.dll'
$ini = Join-Path $root 'mw3ncp_config.ini'
$dxvk = Join-Path $root 'dxvk.conf'
$tempDir = $null
$sourceDll = $null

try {
    if ($ReleaseZip) {
        $zip = (Resolve-Path -LiteralPath $ReleaseZip -ErrorAction Stop).ProviderPath
        if ([System.IO.Path]::GetExtension($zip) -ine '.zip') { throw 'ReleaseZip must be a ZIP file.' }
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('mw3-dlss-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $tempDir -ErrorAction Stop
        $files = @(Get-ChildItem -LiteralPath $tempDir -Recurse -File -Filter 'd3d9.dll')
        if ($files.Count -ne 1) { throw "Expected one d3d9.dll, got $($files.Count)." }
        $sourceDll = $files[0].FullName
        $fs = [System.IO.File]::OpenRead($sourceDll)
        $reader = [System.IO.BinaryReader]::new($fs)
        try {
            if ($reader.ReadUInt16() -ne 0x5A4D) { throw 'Invalid MZ header.' }
            [void]$fs.Seek(60, [System.IO.SeekOrigin]::Begin)
            $offset = $reader.ReadUInt32()
            if ($offset -gt ($fs.Length - 24)) { throw 'Invalid PE header offset.' }
            [void]$fs.Seek($offset, [System.IO.SeekOrigin]::Begin)
            if ($reader.ReadUInt32() -ne 0x00004550) { throw 'Invalid PE signature.' }
            if ($reader.ReadUInt16() -ne 0x8664) { throw 'Not an x64 DLL.' }
        } finally {
            $reader.Dispose()
            $fs.Dispose()
        }
        Write-Host "DLL SHA-256: $((Get-FileHash -LiteralPath $sourceDll -Algorithm SHA256).Hash)"
        Write-Warning 'An x64 PE header check does NOT establish authenticity. Verify the GitHub release and scan the ZIP.'
    } elseif (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
        Write-Warning 'No mod DLL was supplied. The script will only prepare the config; download the official x64 release ZIP.'
    }

    # DXVK reads $PWD/dxvk.conf or DXVK_CONFIG_FILE, then DXVK_CONFIG.
    # Older MW3 builds can truncate large adapter-mode lists. Preserve the
    # desktop display resolution while offering a short fallback mode set.
    $oldDxvk = if (Test-Path -LiteralPath $dxvk -PathType Leaf) {
        [System.IO.File]::ReadAllText($dxvk)
    } else { '' }
    $newLines = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($line in @($oldDxvk -split '\r?\n')) {
        if ($line -match '^\s*d3d9\.modeCountCompatibility\s*=') {
            if (-not $found) {
                $newLines.Add('d3d9.modeCountCompatibility = True')
                $found = $true
            }
        } else {
            $newLines.Add($line)
        }
    }
    if (-not $found) { $newLines.Add('d3d9.modeCountCompatibility = True') }
    $dxvkNew = ($newLines.ToArray() -join [Environment]::NewLine).Trim() + [Environment]::NewLine

    $settings = [ordered]@{
        Video = [ordered]@{
            GraphicsApi = 'Vulkan'
            StreamlineEnabled = $(if ($FourKCheckOnly) { '0' } else { '1' })
            InternalRenderScalePercent = [string]$RenderScalePercent
            TextureRenderRes = '1x'
            BulkTexturePrecache = '0'
            CustomAssetOverrides = '0'
            FsrSharpenEnabled = '0'
            MotionBlurEnabled = '0'
            ForceHighQualityShadows = '0'
            ForceHighQualityLighting = '0'
        }
        Experimental = [ordered]@{
            DLSSModeX64 = '3'
            DlssNeuralRenderingEnabled = '0'
        }
        Options = [ordered]@{
            # Enables the mod's existing in-game Options tabs. The new
            # Advanced Video DLSS selector is in the separately built DLL
            # from this branch; the published v0.0.3-x64 ZIP lacks that row.
            # Keep the stock Options menu for the 4K-only diagnostic.
            UseCustomOptionsScreen = $(if ($FourKCheckOnly) { '0' } else { '1' })
        }
    }

    Write-Host "MW3 folder: $root"
    Write-Host "DLSS Quality, render scale $RenderScalePercent%, DXVK desktop-mode compatibility."
    if ($FourKCheckOnly) { Write-Host '4K check only: DLSS disabled for this boot; test the 4K display list first.' }
    Write-Host 'Windows output resolution is not changed; DLSS 5 is NOT implemented.'
    Write-Warning 'The published v0.0.3-x64 DLL does not contain the new in-game DLSS selector. Build this branch to display that menu row.'
    if ($DryRun) {
        Write-Host 'DryRun complete: no game file was changed.'
        return
    }

    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' +
        [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $targets = @($dll, $ini, $dxvk)
    $backups = @{}
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $backup = "$target.before-dlss-$stamp.bak"
            Copy-Item -LiteralPath $target -Destination $backup -ErrorAction Stop
            $backups[$target] = $backup
        } else {
            $backups[$target] = $null
        }
    }

    try {
        if ($sourceDll) {
            Copy-Item -LiteralPath $sourceDll -Destination $dll -Force -ErrorAction Stop
        }
        if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) {
            [System.IO.File]::WriteAllText($ini, '[Video]' + [Environment]::NewLine)
        }
        if (-not ('Mw3DlssIniApi' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Mw3DlssIniApi {
    [DllImport("kernel32.dll", EntryPoint="WritePrivateProfileStringW", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool Write(string section, string key, string value, string path);
    [DllImport("kernel32.dll", EntryPoint="GetPrivateProfileStringW", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern uint Read(string section, string key, string fallback, StringBuilder result, uint size, string path);
}
'@
        }
        foreach ($section in $settings.Keys) {
            foreach ($key in $settings[$section].Keys) {
                $value = [string]$settings[$section][$key]
                if (-not [Mw3DlssIniApi]::Write($section, $key, $value, $ini)) {
                    throw "INI write failed: [$section] $key"
                }
                $buf = [System.Text.StringBuilder]::new(100)
                [void][Mw3DlssIniApi]::Read($section, $key, 'MISSING', $buf, [uint32]$buf.Capacity, $ini)
                if ($buf.ToString() -cne $value) { throw "INI verification failed: [$section] $key" }
            }
        }
        [System.IO.File]::WriteAllText($dxvk, $dxvkNew, [System.Text.Encoding]::ASCII)
        if (-not ([System.IO.File]::ReadAllText($dxvk) -match '(?m)^d3d9\.modeCountCompatibility = True\r?$')) {
            throw 'DXVK configuration verification failed.'
        }
    } catch {
        foreach ($target in $targets) {
            if ($backups[$target]) {
                Copy-Item -LiteralPath $backups[$target] -Destination $target -Force
            } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
                Remove-Item -LiteralPath $target -Force
            }
        }
        throw "Installation failed; original files restored: $_"
    }
    Write-Host "Installed. Original files backed up with suffix: before-dlss-$stamp.bak"
    Write-Host 'Restart the game. Keep Windows set to 3840x2160; do not run vid_restart.'
} finally {
    if ($tempDir -and (Test-Path -LiteralPath $tempDir)) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
