# Read-only inventory of locally obtained DLSS/Streamline files for MW3 Campaign.
# NEVER executes files, downloads anything, imports registry entries, or installs DLLs.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string]$Directory,
    [switch]$Recurse
)

$ErrorActionPreference = 'Stop'
$knownNvidiaFiles = @(
    'sl.interposer.dll', 'sl.common.dll', 'sl.dlss.dll', 'sl.dlss_nr.dll',
    'sl.dlss_d.dll', 'sl.dlss_g.dll', 'sl.nis.dll',
    'nvngx_dlss.dll', 'nvngx_dlssnr.dll'
)

function Get-PeArchitecture([string]$FilePath) {
    $stream = [System.IO.File]::Open($FilePath, 'Open', 'Read', 'ReadWrite')
    $reader = [System.IO.BinaryReader]::new($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) {
            return 'not-PE'
        }
        $stream.Position = 0x3C
        $peOffset = $reader.ReadInt32()
        if ($peOffset -lt 64 -or ($peOffset + 6) -gt $stream.Length) {
            return 'invalid-PE'
        }
        $stream.Position = $peOffset
        if ($reader.ReadUInt32() -ne 0x00004550) {
            return 'invalid-PE'
        }
        $machine = $reader.ReadUInt16()
        switch ($machine) {
            0x8664 { return 'x64' }
            0x014C { return 'x86' }
            0xAA64 { return 'arm64' }
            default { return ('other-0x{0:X4}' -f $machine) }
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

$extensions = @('.dll', '.exe', '.addon64', '.reg', '.bat', '.cmd', '.ps1')
$files = @(Get-ChildItem -LiteralPath $Directory -File -Recurse:$Recurse |
    Where-Object { $_.Extension.ToLowerInvariant() -in $extensions } |
    Sort-Object FullName)

if ($files.Count -eq 0) {
    Write-Warning 'No DLL, executable, add-on, registry or script files found.'
    exit 1
}

$results = @(
    foreach ($file in $files) {
        $isNvidiaRuntime = $file.Name.ToLowerInvariant() -in $knownNvidiaFiles
        $pe = if ($file.Extension.ToLowerInvariant() -in @('.dll', '.exe', '.addon64')) {
            Get-PeArchitecture -FilePath $file.FullName
        } else { 'not-applicable' }

        $signatureStatus = 'not-applicable'
        $signer = ''
        if ($pe -ne 'not-applicable') {
            $signature = Get-AuthenticodeSignature -LiteralPath $file.FullName
            $signatureStatus = $signature.Status.ToString()
            if ($null -ne $signature.SignerCertificate) {
                $signer = $signature.SignerCertificate.Subject
            }
        }

        $assessment = 'review-manually'
        if ($file.Extension.ToLowerInvariant() -eq '.reg') {
            $assessment = 'registry-file-do-not-import'
        }
        elseif ($isNvidiaRuntime) {
            if ($pe -ne 'x64') {
                $assessment = 'reject-wrong-architecture'
            }
            elseif ($signatureStatus -eq 'Valid' -and $signer -match 'NVIDIA') {
                $assessment = 'nvidia-signature-valid-not-a-malware-guarantee'
            }
            else {
                $assessment = 'unverified-nvidia-runtime-do-not-load'
            }
        }
        elseif ($pe -eq 'x86' -or $pe -eq 'arm64' -or $pe -eq 'invalid-PE') {
            $assessment = 'not-compatible-with-x64-runtime'
        }

        [PSCustomObject]@{
            File = $file.FullName
            SizeBytes = $file.Length
            SHA256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            PE = $pe
            Authenticode = $signatureStatus
            Signer = $signer
            Assessment = $assessment
        }
    }
)

# Structured portable output for review, not a malware verdict.
$results | ConvertTo-Json -Depth 3
