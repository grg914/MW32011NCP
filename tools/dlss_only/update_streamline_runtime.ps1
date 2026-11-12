# Update the FOUR signed NVIDIA Super Resolution DLLs inside an existing
# MW32011NCP d3d9.dll without changing the known-working DXVK 4K backend.
# Unlike copying DLLs to AppData, these files survive the mod's next launch
# because it extracts runtime resources from the patched proxy itself.
# Never embeds DLSS 5 NR, frame generation, or other unsupported plugins.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$GameDir,
    [Parameter(Mandatory = $true)][string]$StreamlineRuntimeDir,
    [switch]$DryRun
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$game = (Resolve-Path -LiteralPath $GameDir -ErrorAction Stop).ProviderPath
$src = (Resolve-Path -LiteralPath $StreamlineRuntimeDir -ErrorAction Stop).ProviderPath
if (-not (Test-Path -LiteralPath $src -PathType Container)) { throw 'StreamlineRuntimeDir must be an existing directory.' }
if (-not (Test-Path -LiteralPath (Join-Path $game 'iw5sp.exe') -PathType Leaf)) {
    throw 'GameDir does not contain the MW3 Steam campaign executable iw5sp.exe.'
}
$proxy = Join-Path $game 'd3d9.dll'
if (-not (Test-Path -LiteralPath $proxy -PathType Leaf)) {
    throw 'The MW32011NCP d3d9.dll was not found beside iw5sp.exe.'
}

# Resource identifiers are defined in proxy_d3d9/resource.h.
$items = @(
    @{ Name = 'sl.interposer.dll'; Id = 111 },
    @{ Name = 'sl.common.dll';     Id = 112 },
    @{ Name = 'sl.dlss.dll';       Id = 113 },
    @{ Name = 'nvngx_dlss.dll';    Id = 114 }
)
$slVersions = @()
foreach ($item in $items) {
    $path = Join-Path $src $item.Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing $($item.Name) in $src. Do not mix DLLs from unrelated SDK versions."
    }
    $file = Get-Item -LiteralPath $path
    if ($file.Length -lt 65536 -or $file.Length -gt 300MB) {
        throw "Unexpected file size for $($item.Name): $($file.Length) bytes."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or
        $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch 'NVIDIA') {
        throw "Authenticode signature for $($item.Name) is not valid NVIDIA: $($signature.Status). No files changed."
    }

    $fs = [System.IO.File]::OpenRead($path)
    $reader = [System.IO.BinaryReader]::new($fs)
    try {
        if ($reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE DLL: $path" }
        [void]$fs.Seek(0x3c, [System.IO.SeekOrigin]::Begin)
        $peOffset = $reader.ReadUInt32()
        if ($peOffset -gt ($fs.Length - 24)) { throw "Invalid PE offset: $path" }
        [void]$fs.Seek($peOffset, [System.IO.SeekOrigin]::Begin)
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw "Not an x64 PE DLL: $path"
        }
    } finally {
        $reader.Dispose()
        $fs.Dispose()
    }
    $item.Path = $path
    $item.Version = $file.VersionInfo.FileVersion
    $item.Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($item.Id -lt 114) { $slVersions += $item.Version }
    Write-Host "$($item.Name): version $($item.Version); NVIDIA signature valid."
}
if (@($slVersions | Select-Object -Unique).Count -ne 1) {
    throw 'The three sl.* DLLs have different FileVersions. Use one coherent NVIDIA Streamline SDK release.'
}
Write-Host 'Ignoring sl.dlss_nr.dll and nvngx_dlssnr.dll: DLSS 5 NR is not supported by this MW3 mod.'

if (-not ('MW3NcpNvidiaResources' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class MW3NcpNvidiaResources {
    private const uint LOAD_LIBRARY_AS_DATAFILE = 2;
    private static readonly IntPtr RT_RCDATA = new IntPtr(10);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate bool EnumLangProc(IntPtr module, IntPtr type, IntPtr name, ushort lang, IntPtr data);
    [DllImport("kernel32.dll", EntryPoint="LoadLibraryExW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern IntPtr LoadData(string path, IntPtr unused, uint flags);
    [DllImport("kernel32.dll", EntryPoint="FreeLibrary", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FreeData(IntPtr module);
    [DllImport("kernel32.dll", EntryPoint="EnumResourceLanguagesW", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumLanguages(IntPtr module, IntPtr type, IntPtr name, EnumLangProc callback, IntPtr user);
    [DllImport("kernel32.dll", EntryPoint="FindResourceExW", SetLastError=true)]
    private static extern IntPtr Find(IntPtr module, IntPtr type, IntPtr name, ushort lang);
    [DllImport("kernel32.dll", EntryPoint="SizeofResource", SetLastError=true)]
    private static extern uint Size(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", EntryPoint="LoadResource", SetLastError=true)]
    private static extern IntPtr Load(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", EntryPoint="LockResource", SetLastError=true)]
    private static extern IntPtr Lock(IntPtr resourceData);
    [DllImport("kernel32.dll", EntryPoint="BeginUpdateResourceW", CharSet=CharSet.Unicode, SetLastError=true)]
    private static extern IntPtr Begin(string path, bool deleteResources);
    [DllImport("kernel32.dll", EntryPoint="UpdateResourceW", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Update(IntPtr updater, IntPtr type, IntPtr name, ushort lang, byte[] bytes, uint count);
    [DllImport("kernel32.dll", EntryPoint="EndUpdateResourceW", SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool End(IntPtr updater, bool discard);
    private static IntPtr Open(string path) {
        IntPtr module = LoadData(path, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot read the proxy DLL resources");
        return module;
    }
    public static ushort GetLanguage(string path, int id) {
        IntPtr module = Open(path);
        try {
            List<ushort> languages = new List<ushort>();
            EnumLangProc callback = delegate(IntPtr h, IntPtr t, IntPtr n, ushort lang, IntPtr data) {
                languages.Add(lang);
                return true;
            };
            EnumLanguages(module, RT_RCDATA, new IntPtr(id), callback, IntPtr.Zero);
            if (languages.Count != 1) throw new InvalidOperationException("Expected exactly one existing RT_RCDATA language for resource " + id + ", found " + languages.Count);
            return languages[0];
        } finally { FreeData(module); }
    }
    public static byte[] Read(string path, int id, ushort language) {
        IntPtr module = Open(path);
        try {
            IntPtr resource = Find(module, RT_RCDATA, new IntPtr(id), language);
            if (resource == IntPtr.Zero) throw new InvalidOperationException("Resource missing: " + id);
            uint count = Size(module, resource);
            if (count < 65536 || count > 300 * 1024 * 1024) throw new InvalidOperationException("Unexpected resource size for " + id);
            IntPtr data = Load(module, resource);
            IntPtr ptr = Lock(data);
            if (ptr == IntPtr.Zero) throw new InvalidOperationException("Cannot access resource " + id);
            byte[] result = new byte[(int)count];
            Marshal.Copy(ptr, result, 0, (int)count);
            return result;
        } finally { FreeData(module); }
    }
    public static void Write(string path, int[] ids, ushort[] languages, byte[][] contents) {
        IntPtr update = Begin(path, false);
        if (update == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "BeginUpdateResource failed");
        bool finished = false;
        try {
            for (int i = 0; i < ids.Length; ++i) {
                if (!Update(update, RT_RCDATA, new IntPtr(ids[i]), languages[i], contents[i], (uint)contents[i].Length))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "UpdateResource failed for resource " + ids[i]);
            }
            if (!End(update, false)) throw new Win32Exception(Marshal.GetLastWin32Error(), "EndUpdateResource failed");
            finished = true;
        } finally { if (!finished) End(update, true); }
    }
}
'@
}

$resourceLanguages = @()
foreach ($item in $items) {
    $lang = [MW3NcpNvidiaResources]::GetLanguage($proxy, [int]$item.Id)
    $resourceLanguages += [uint16]$lang
    Write-Host "Proxy contains NVIDIA resource $($item.Id), lang=$lang."
}
if ($DryRun) {
    Write-Host 'DryRun: source NVIDIA DLLs verified. Original 4K mod DLL not changed.'
    return
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' +
    [Guid]::NewGuid().ToString('N').Substring(0,8)
$backup = "$proxy.before-streamline-$stamp.bak"
$temp = Join-Path $env:TEMP ("mw3-streamline-update-" + [Guid]::NewGuid().ToString('N') + '.dll')
Copy-Item -LiteralPath $proxy -Destination $backup -ErrorAction Stop
try {
    Copy-Item -LiteralPath $proxy -Destination $temp -ErrorAction Stop
    $ids = [int[]]@($items | ForEach-Object { [int]$_.Id })
    $langs = [uint16[]]$resourceLanguages
    $payloads = [byte[][]]@($items | ForEach-Object { [System.IO.File]::ReadAllBytes($_.Path) })
    [MW3NcpNvidiaResources]::Write($temp, $ids, $langs, $payloads)

    for ($i = 0; $i -lt $items.Count; ++$i) {
        $embedded = [MW3NcpNvidiaResources]::Read($temp, [int]$items[$i].Id, [uint16]$langs[$i])
        $gotHash = [Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($embedded)
        )
        if ($gotHash -cne $items[$i].Hash) {
            throw "Resource checksum mismatch for $($items[$i].Name). No changes installed."
        }
    }
    Copy-Item -LiteralPath $temp -Destination $proxy -Force -ErrorAction Stop
    Write-Host 'SUCCESS: signed NVIDIA DLSS Super Resolution runtime embedded in the existing mod proxy.'
    Write-Host "Backup: $backup"
    Write-Host 'Keep the DXVK 4K mode fix; restart MW3 entirely. DLSS 5 NR is not enabled.'
} catch {
    # Existing original DLL is retained as an independent backup.
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        Copy-Item -LiteralPath $backup -Destination $proxy -Force -ErrorAction SilentlyContinue
    }
    throw "Update failed. Original DLL restored when possible. $($_.Exception.Message)"
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}
