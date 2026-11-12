# Windows smoke test for the DLSS focused installer: no real game touched.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT: $Message" }
}
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('mw3-dlss-smoke-' + [Guid]::NewGuid().ToString('N'))
$game = Join-Path $root 'game'
$release = Join-Path $root 'release'
$zip = Join-Path $root 'release.zip'
$script = Join-Path $PSScriptRoot 'install_dlss_only.ps1'
New-Item -Path $game -ItemType Directory -Force | Out-Null
New-Item -Path $release -ItemType Directory -Force | Out-Null
try {
    [System.IO.File]::WriteAllBytes((Join-Path $game 'iw5sp.exe'), [byte[]](0))
    [System.IO.File]::WriteAllText(
        (Join-Path $game 'mw3ncp_config.ini'),
        "[Video]$([Environment]::NewLine)GraphicsApi=LegacyD3D9$([Environment]::NewLine)UnknownKey=preserve$([Environment]::NewLine)")
    [System.IO.File]::WriteAllText(
        (Join-Path $game 'dxvk.conf'),
        "d3d9.forceAspectRatio = 16:9$([Environment]::NewLine)d3d9.modeCountCompatibility = False$([Environment]::NewLine)")

    # Minimal synthetic amd64 PE header; never executed, only used for archive validation.
    $pe = [byte[]]::new(512)
    $pe[0] = 0x4D
    $pe[1] = 0x5A
    $pe[60] = 0x80
    $pe[128] = 0x50
    $pe[129] = 0x45
    $pe[132] = 0x64
    $pe[133] = 0x86
    [System.IO.File]::WriteAllBytes((Join-Path $release 'd3d9.dll'), $pe)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($release, $zip)

    $beforeIni = (Get-FileHash -LiteralPath (Join-Path $game 'mw3ncp_config.ini') -Algorithm SHA256).Hash
    $beforeDxvk = (Get-FileHash -LiteralPath (Join-Path $game 'dxvk.conf') -Algorithm SHA256).Hash
    & $script -GameDir $game -ReleaseZip $zip -DryRun | Out-Null
    Assert (-not (Test-Path -LiteralPath (Join-Path $game 'd3d9.dll'))) 'dry run installed DLL'
    Assert ($beforeIni -eq (Get-FileHash -LiteralPath (Join-Path $game 'mw3ncp_config.ini') -Algorithm SHA256).Hash) 'dry run modified INI'
    Assert ($beforeDxvk -eq (Get-FileHash -LiteralPath (Join-Path $game 'dxvk.conf') -Algorithm SHA256).Hash) 'dry run modified DXVK config'

    & $script -GameDir $game -ReleaseZip $zip | Out-Null
    Assert ((Test-Path -LiteralPath (Join-Path $game 'd3d9.dll'))) 'DLL was not installed'
    $ini = [System.IO.File]::ReadAllText((Join-Path $game 'mw3ncp_config.ini'))
    $dxvk = [System.IO.File]::ReadAllText((Join-Path $game 'dxvk.conf'))
    foreach ($expected in @('GraphicsApi=Vulkan', 'StreamlineEnabled=1', 'UseCustomOptionsScreen=1', 'InternalRenderScalePercent=67',
        'TextureRenderRes=1x', 'FsrSharpenEnabled=0', 'MotionBlurEnabled=0',
        'DLSSModeX64=3', 'DlssNeuralRenderingEnabled=0', 'UnknownKey=preserve')) {
        Assert ($ini.Contains($expected)) "Missing INI setting $expected"
    }
    Assert ($dxvk.Contains('d3d9.modeCountCompatibility = True')) 'DXVK native mode fix missing'
    Assert ($dxvk.Contains('d3d9.forceAspectRatio = 16:9')) 'DXVK custom option lost'
    Assert (@(Get-ChildItem -LiteralPath $game -Filter '*.before-dlss-*.bak').Count -eq 2) 'Expected INI + DXVK backups'
    # 4K isolation test: keep Vulkan mode compatibility, turn OFF DLSS without
    # modifying the game's resolution or deleting the previous backups.
    & $script -GameDir $game -FourKCheckOnly | Out-Null
    $isolated = [System.IO.File]::ReadAllText((Join-Path $game 'mw3ncp_config.ini'))
    Assert ($isolated.Contains('StreamlineEnabled=0')) '4K-only test must turn off DLSS'
    Assert ($isolated.Contains('UseCustomOptionsScreen=0')) '4K-only test should preserve native Options menu'
    Assert ($isolated.Contains('GraphicsApi=Vulkan')) '4K-only test must retain Vulkan'
    & $script -GameDir $game | Out-Null
    $enabledAgain = [System.IO.File]::ReadAllText((Join-Path $game 'mw3ncp_config.ini'))
    Assert ($enabledAgain.Contains('StreamlineEnabled=1')) 'DLSS profile did not re-enable NVIDIA Streamline'
    Assert ($enabledAgain.Contains('UseCustomOptionsScreen=1')) 'DLSS mode did not re-enable Advanced Video Options'

    Write-Host 'PASS: release architecture, dry run, rollback backups, DXVK mode option, DLSS profile, preservation.'
}
finally {
    Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue
}
