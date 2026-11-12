# Standalone Windows smoke tests for apply_campaign_profile.ps1.
# No game installation or DLLs are touched. Uses a temporary dummy INI.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Reason) {
    if (-not $Condition) { throw "ASSERTION FAILED: $Reason" }
}
function Assert-IniLine([string]$Content, [string]$Name, [string]$Value) {
    $escapedName = [regex]::Escape($Name)
    $escapedValue = [regex]::Escape($Value)
    $pattern = '(?m)^' + $escapedName + '=' + $escapedValue + '\r?$'
    Assert-True ([regex]::IsMatch($Content, $pattern)) "$Name must equal $Value"
}

$root = Join-Path ([System.IO.Path]::GetTempPath()) ("mw3ncp-fps-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$config = Join-Path $root 'mw3ncp_config.ini'
$script = Join-Path $PSScriptRoot 'apply_campaign_profile.ps1'
$original = (@(
    '[Video]'
    'GraphicsApi=LegacyD3D9'
    'UnknownUserSetting=preserve-me'
    ''
    '[Experimental]'
    'DLSSModeX64=6'
    ''
) -join [Environment]::NewLine)
$backupPattern = $config + '.before-*.bak'
try {
    [System.IO.File]::WriteAllText($config, $original, [System.Text.Encoding]::ASCII)
    $originalHash = (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash

    & $script -ConfigPath $config -Profile FpsFirst -DryRun | Out-Null
    Assert-True ((Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -eq $originalHash) 'DryRun modified the file'
    Assert-True (@(Get-ChildItem -Path $backupPattern).Count -eq 0) 'DryRun created a backup'

    & $script -ConfigPath $config -Profile FpsFirst | Out-Null
    $afterFps = [System.IO.File]::ReadAllText($config)
    Assert-IniLine $afterFps 'GraphicsApi' 'Vulkan'
    Assert-IniLine $afterFps 'InternalRenderScalePercent' '67'
    Assert-IniLine $afterFps 'TextureRenderRes' '1x'
    Assert-IniLine $afterFps 'DLSSModeX64' '3'
    Assert-IniLine $afterFps 'DlssNeuralRenderingEnabled' '0'
    Assert-IniLine $afterFps 'ForceHighQualityShadows' '0'
    Assert-IniLine $afterFps 'UnknownUserSetting' 'preserve-me'
    $backups = @(Get-ChildItem -Path $backupPattern)
    Assert-True ($backups.Count -eq 1) 'No single backup created'
    Assert-True ((Get-FileHash -LiteralPath $backups[0].FullName -Algorithm SHA256).Hash -eq $originalHash) 'Backup hash mismatch'

    & $script -ConfigPath $config -Profile UltraPreview | Out-Null
    $afterUltra = [System.IO.File]::ReadAllText($config)
    Assert-IniLine $afterUltra 'InternalRenderScalePercent' '75'
    Assert-IniLine $afterUltra 'TextureRenderRes' '2x'
    Assert-IniLine $afterUltra 'ForceHighQualityShadows' '1'
    Assert-IniLine $afterUltra 'StreamlineEnabled' '1'
    Assert-True (@(Get-ChildItem -Path $backupPattern).Count -eq 2) 'Second preset should create second backup'
    Write-Host 'PASS: dry run, backup, option preservation, FpsFirst and UltraPreview.'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
