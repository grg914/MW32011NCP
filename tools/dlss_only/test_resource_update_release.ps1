# Windows CI: run the same RT_RCDATA replacement against the actual official
# v0.0.3-x64 d3d9.dll. No third-party DLLs run and no game files are changed.
# Uses synthetic NVIDIA-sized byte payloads to avoid redistributing SDK binaries.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('mw3-release-rc-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $zipPath = Join-Path $temp 'release.zip'
    $uri = 'https://github.com/k8se10/MW32011NCP/releases/download/v0.0.3-x64/MW32011NCP-v0.0.3-x64.zip'
    Invoke-WebRequest -Uri $uri -OutFile $zipPath -ErrorAction Stop
    Expand-Archive -LiteralPath $zipPath -DestinationPath (Join-Path $temp 'release') -ErrorAction Stop
    $files = @(Get-ChildItem -LiteralPath (Join-Path $temp 'release') -Filter 'd3d9.dll' -File -Recurse)
    if ($files.Count -ne 1) { throw "Expected one proxy d3d9.dll, found $($files.Count)." }
    $proxy = Join-Path $temp 'official-patched.dll'
    Copy-Item -LiteralPath $files[0].FullName -Destination $proxy
    $actual = (Get-FileHash -LiteralPath $proxy -Algorithm SHA256).Hash
    $expected = '0FA30009BA059A321B783C3FB9AC98B6EA0AC39163984A2323BA5BD39A7B94E7'
    if ($actual -cne $expected) {
        throw "Official proxy SHA-256 does not match previously verified user release; got $actual. Refusing to patch."
    }
    Write-Host "OFFICIAL proxy verified SHA-256: $actual"
    $source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'update_streamline_runtime.ps1'))
    $start = $source.IndexOf("Add-Type -TypeDefinition @'")
    if ($start -lt 0) { throw 'C# helper not found' }
    $start += "Add-Type -TypeDefinition @'".Length
    $end = $source.IndexOf("'@", $start)
    if ($end -lt 0) { throw 'C# helper not terminated' }
    Add-Type -TypeDefinition $source.Substring($start,$end-$start)
    $ids = [int[]]@(111,112,113,114)
    $langs = [uint16[]]::new($ids.Length)
    for ($i=0;$i -lt $ids.Length;++$i) {
        $langs[$i] = [MW3NcpNvidiaResources]::GetLanguage($proxy,$ids[$i])
        Write-Host "Original resource $($ids[$i]) lang $($langs[$i])"
    }
    $payloads = [byte[][]]::new(4)
    $sizes = @(12000000,2000000,1800000,65000000)
    for ($i=0;$i -lt 4;++$i) {
        $payloads[$i] = [byte[]]::new($sizes[$i])
        $payloads[$i][0] = 0x4d
        $payloads[$i][1] = 0x5a
        $payloads[$i][$payloads[$i].Length-1] = [byte](111+$i)
    }
    [MW3NcpNvidiaResources]::Write($proxy,$ids,$langs,$payloads)
    for ($i=0;$i -lt 4;++$i) {
        $r = [MW3NcpNvidiaResources]::Read($proxy,$ids[$i],$langs[$i])
        if ($r.Length -ne $payloads[$i].Length -or $r[$r.Length-1] -ne [byte]($i+111)) {
            throw "Updated resource $($ids[$i]) data mismatch"
        }
    }
    Write-Host 'PASS: Updated original MW32011NCP x64 binary with large synthetic Streamline payloads.'
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue
    }
}
