# Repackage the code-only CI DLL with the local NVIDIA/DXVK runtimes already
# extracted by the legitimate MW32011NCP v0.0.3-x64 installation.
# IMPORTANT: Never install the code-only artifact directly in MW3.
# This script modifies ONLY our unsigned proxy DLL; NVIDIA DLLs stay unchanged
# and signed inside its Win32 RT_RCDATA resources. No C++ compiler is required.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GameDir,
    [Parameter(Mandatory=$true)][string]$BuiltDllZip,
    # Optional: replace the four embedded NVIDIA Streamline DLLs with a newer
    # matching signed x64 runtime from the user's own extracted SDK folder.
    [string]$StreamlineRuntimeDir,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$game = (Resolve-Path -LiteralPath $GameDir -ErrorAction Stop).ProviderPath
$zip = (Resolve-Path -LiteralPath $BuiltDllZip -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath (Join-Path $game 'iw5sp.exe') -PathType Leaf)) {
    throw 'GameDir must contain the 64-bit Steam MW3 2011 campaign executable iw5sp.exe.'
}
if ([System.IO.Path]::GetExtension($zip) -ine '.zip') { throw 'BuiltDllZip must be a .zip file.' }
# The CI workflow is a code-only build, not the official v0.0.3-x64 release.
if ([System.IO.Path]::GetFileName($zip) -notlike '*dlss-menu-code-only*') {
    Write-Warning 'ZIP filename is unexpected. Use the code-only artifact from the PR #3 GitHub Actions Build workflow.'
}
$runtime = Join-Path $env:LOCALAPPDATA 'MW32011NCP\runtime_x64'
$streamlineSource = if ($StreamlineRuntimeDir) {
    (Resolve-Path -LiteralPath $StreamlineRuntimeDir -ErrorAction Stop).ProviderPath
} else {
    Join-Path $runtime 'streamline'
}
if (-not (Test-Path -LiteralPath $streamlineSource -PathType Container)) {
    throw "Streamline source directory missing: $streamlineSource"
}
# All NVIDIA DLLs must come from ONE compatible Streamline release.
# Do not mix the 2.14.1 interposer with an unrelated 2.14.16 plugin.
$vendor = @(
    @{ Id = 110; Path = (Join-Path $runtime 'dxvk\d3d9.dll'); Name='DXVK D3D9' },
    @{ Id = 111; Path = (Join-Path $streamlineSource 'sl.interposer.dll'); Name='NVIDIA Streamline interposer' },
    @{ Id = 112; Path = (Join-Path $streamlineSource 'sl.common.dll'); Name='NVIDIA Streamline common' },
    @{ Id = 113; Path = (Join-Path $streamlineSource 'sl.dlss.dll'); Name='NVIDIA Streamline DLSS' },
    @{ Id = 114; Path = (Join-Path $streamlineSource 'nvngx_dlss.dll'); Name='NVIDIA NGX DLSS' }
)
$streamlineVersions = @()
foreach ($item in $vendor) {
    if (-not (Test-Path -LiteralPath $item.Path -PathType Leaf)) {
        throw "Missing $($item.Name): $($item.Path). Launch the official mod with StreamlineEnabled=1 once, exit, then retry."
    }
    $bytes = (Get-Item -LiteralPath $item.Path).Length
    if ($bytes -lt 1024 -or $bytes -gt 500MB) {
        throw "Unexpected file size for $($item.Path). Refusing to pack a possibly corrupt DLL."
    }
    # All four NVIDIA libraries come from the installed NVIDIA Streamline release;
    # avoid replacing them with arbitrary, unsigned DLLs from mod archives.
    if ($item.Id -ge 111) {
        $auth = Get-AuthenticodeSignature -LiteralPath $item.Path
        if ($auth.Status -ne 'Valid' -or
            $null -eq $auth.SignerCertificate -or
            $auth.SignerCertificate.Subject -notmatch 'NVIDIA') {
            throw "NVIDIA signature invalid or missing: $($item.Path) ($($auth.Status)). Do not disable signature checks."
        }
    }
    $info = (Get-Item -LiteralPath $item.Path).VersionInfo
    Write-Host "$($item.Name): $($item.Path), version $($info.FileVersion), $([Math]::Round($bytes / 1MB, 1)) MB"
    if ($item.Id -in @(111,112,113)) {
        $streamlineVersions += $info.FileVersion
    }
}
if (@($streamlineVersions | Select-Object -Unique).Count -ne 1) {
    throw 'sl.interposer.dll, sl.common.dll and sl.dlss.dll must be from the SAME Streamline SDK release/version.'
}
Write-Host "NVIDIA Streamline SDK: $($streamlineVersions[0])"
Write-Host 'The files sl.dlss_nr.dll and nvngx_dlssnr.dll are deliberately NOT loaded: DLSS 5 is not implemented.'

$stage = Join-Path ([IO.Path]::GetTempPath()) ('mw3-dlss-menu-stage-' + [Guid]::NewGuid().ToString('N'))
$dest = Join-Path $game 'd3d9.dll'
$ini = Join-Path $game 'mw3ncp_config.ini'
New-Item -ItemType Directory -Path $stage | Out-Null
try {
    $unzip = Join-Path $stage 'artifact'
    Expand-Archive -LiteralPath $zip -DestinationPath $unzip -ErrorAction Stop
    $candidates = @(Get-ChildItem -LiteralPath $unzip -Recurse -File -Filter d3d9.dll)
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one d3d9.dll in code-only artifact; found $($candidates.Count)."
    }
    $built = $candidates[0].FullName
    $f = [System.IO.File]::OpenRead($built)
    $br = [System.IO.BinaryReader]::new($f)
    try {
        if ($br.ReadUInt16() -ne 0x5A4D) { throw 'CI artifact is not a PE DLL.' }
        [void]$f.Seek(0x3c, [System.IO.SeekOrigin]::Begin)
        $off = $br.ReadUInt32()
        if ($off -gt $f.Length - 24) { throw 'Corrupt PE header offset.' }
        [void]$f.Seek($off, [System.IO.SeekOrigin]::Begin)
        if ($br.ReadUInt32() -ne 0x00004550 -or $br.ReadUInt16() -ne 0x8664) {
            throw 'CI artifact is not a 64-bit PE DLL.'
        }
    } finally { $br.Dispose(); $f.Dispose() }
    Write-Host "Code-only mod SHA-256: $((Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash)"
    if ($DryRun) {
        Write-Host 'DryRun passed: inputs checked; no game files were changed.'
        return
    }
    # Win32 resource IDs must match proxy_d3d9/resource.h:
    # IDR_DXVK_D3D9 110, IDR_SL_INTERPOSER 111, IDR_SL_COMMON 112,
    # IDR_SL_DLSS 113, IDR_NGX_DLSS 114.
    # RT_RCDATA (type=10), language neutral (0).
    if (-not ('MW3ResourceTools' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class MW3ResourceTools {
    [DllImport("kernel32.dll", EntryPoint="BeginUpdateResourceW", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr Begin(string fileName, bool deleteOldResources);
    [DllImport("kernel32.dll", EntryPoint="UpdateResourceW", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool Update(IntPtr updateHandle, IntPtr type, IntPtr name, ushort language, byte[] data, uint dataLength);
    [DllImport("kernel32.dll", EntryPoint="EndUpdateResourceW", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool End(IntPtr updateHandle, bool discard);
    [DllImport("kernel32.dll", EntryPoint="LoadLibraryExW", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern IntPtr LoadData(string path, IntPtr reserved, uint flags);
    [DllImport("kernel32.dll", EntryPoint="FindResourceW", SetLastError=true)]
    public static extern IntPtr Find(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll", EntryPoint="SizeofResource", SetLastError=true)]
    public static extern uint Size(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", EntryPoint="FreeLibrary", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool Free(IntPtr module);
    [DllImport("kernel32.dll", EntryPoint="WritePrivateProfileStringW", CharSet=CharSet.Unicode, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool WriteIni(string section, string key, string value, string file);
}
'@
    }
    $packed = Join-Path $stage 'd3d9.dll'
    Copy-Item -LiteralPath $built -Destination $packed -ErrorAction Stop
    $handle = [MW3ResourceTools]::Begin($packed, $false)
    if ($handle -eq [IntPtr]::Zero) { throw 'BeginUpdateResource failed on the CI proxy DLL.' }
    $committed = $false
    try {
        foreach ($item in $vendor) {
            $bytes = [System.IO.File]::ReadAllBytes($item.Path)
            if (-not [MW3ResourceTools]::Update($handle, [IntPtr]::new(10), [IntPtr]::new([int]$item.Id), [uint16]0, $bytes, [uint32]$bytes.Length)) {
                throw "UpdateResource failed for $($item.Name); Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
            }
        }
        $committed = [MW3ResourceTools]::End($handle, $false)
        if (-not $committed) { throw "EndUpdateResource failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())." }
    } finally {
        if (-not $committed) { [void][MW3ResourceTools]::End($handle, $true) }
    }
    # Verify RT_RCDATA IDs using LoadLibraryEx(..., LOAD_LIBRARY_AS_DATAFILE).
    # This does NOT execute DllMain or load NVIDIA code.
    $module = [MW3ResourceTools]::LoadData($packed, [IntPtr]::Zero, [uint32]2)
    if ($module -eq [IntPtr]::Zero) { throw 'Packed proxy PE could not be opened as data file.' }
    try {
        foreach ($item in $vendor) {
            $res = [MW3ResourceTools]::Find($module, [IntPtr]::new([int]$item.Id), [IntPtr]::new(10))
            if ($res -eq [IntPtr]::Zero) { throw "Packed RT_RCDATA $($item.Id) not found." }
            $size = [MW3ResourceTools]::Size($module, $res)
            if ($size -ne (Get-Item -LiteralPath $item.Path).Length) {
                throw "Packed RT_RCDATA $($item.Id) has incorrect size."
            }
        }
    } finally { [void][MW3ResourceTools]::Free($module) }

    $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $dllBack = $null
    $iniBack = $null
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
        $dllBack = "$dest.pre-dlss-menu-$stamp.bak"
        Copy-Item -LiteralPath $dest -Destination $dllBack -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $ini -PathType Leaf) {
        $iniBack = "$ini.pre-dlss-menu-$stamp.bak"
        Copy-Item -LiteralPath $ini -Destination $iniBack -ErrorAction Stop
    }
    try {
        Copy-Item -LiteralPath $packed -Destination $dest -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $ini)) {
            [System.IO.File]::WriteAllText($ini, '[Video]' + [Environment]::NewLine)
        }
        $settings = @(
            @('Video','GraphicsApi','Vulkan'),
            @('Video','StreamlineEnabled','1'),
            @('Video','InternalRenderScalePercent','67'),
            @('Experimental','DLSSModeX64','3'),
            @('Experimental','DlssNeuralRenderingEnabled','0'),
            @('Options','UseCustomOptionsScreen','1')
        )
        foreach ($line in $settings) {
            if (-not [MW3ResourceTools]::WriteIni($line[0],$line[1],$line[2],$ini)) {
                throw "Cannot save [$($line[0])] $($line[1]) to mw3ncp_config.ini."
            }
        }
    } catch {
        if ($dllBack) { Copy-Item -LiteralPath $dllBack -Destination $dest -Force }
        elseif (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Force }
        if ($iniBack) { Copy-Item -LiteralPath $iniBack -Destination $ini -Force }
        elseif (Test-Path -LiteralPath $ini) { Remove-Item -LiteralPath $ini -Force }
        throw "Packaging failed; restored previous game files: $_"
    }
    Write-Host 'SUCCESS: Packed the branch DLSS menu DLL with local NVIDIA and DXVK binaries.'
    Write-Host 'Options > Advanced Video > DLSS Super Resolution will appear in the custom mod menu (x64 campaign only).'
    Write-Host "Backups: $dllBack and $iniBack"
    Write-Host 'If the game fails to start: close MW3, restore the .bak files, then inspect proxy_d3d9.log.'
} finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Force -Recurse -ErrorAction SilentlyContinue
    }
}
