# CI-only regression test: resource update roundtrip with large payload, no NVIDIA binaries.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$test = Join-Path ([System.IO.Path]::GetTempPath()) ('mw3-rc-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $test | Out-Null
try {
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue) -or -not (Get-Command rc.exe -ErrorAction SilentlyContinue)) {
        throw 'Test requires cl.exe and rc.exe on Windows.'
    }
    [IO.File]::WriteAllText((Join-Path $test 'dummy.c'), '__declspec(dllexport) int Dummy(void) { return 1; }')
    $rcLines = New-Object System.Collections.Generic.List[string]
    $sizes = @(1048576, 114688, 131072, 163840, 4194304)
    for ($i=0; $i -lt 5; ++$i) {
        $name = 'resource_' + (110+$i) + '.bin'
        $bytes = [byte[]]::new($sizes[$i])
        $bytes[0] = 0x4D
        $bytes[1] = 0x5A
        $bytes[$sizes[$i]-1] = [byte](110 + $i)
        [IO.File]::WriteAllBytes((Join-Path $test $name), $bytes)
        $rcLines.Add('LANGUAGE 9,1')
        $rcLines.Add((110+$i).ToString() + ' RCDATA "' + $name + '"')
    }
    [IO.File]::WriteAllLines((Join-Path $test 'dummy.rc'), $rcLines)
    Push-Location $test
    try {
        & rc.exe /nologo /fo dummy.res dummy.rc
        if ($LASTEXITCODE -ne 0) { throw "rc failed: $LASTEXITCODE" }
        & cl.exe /nologo /LD /Fe:dummy.dll dummy.c dummy.res
        if ($LASTEXITCODE -ne 0) { throw "cl failed: $LASTEXITCODE" }
    } finally { Pop-Location }
    $dll = Join-Path $test 'dummy.dll'
    $updater = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'update_streamline_runtime.ps1'))
    $start = $updater.IndexOf("Add-Type -TypeDefinition @'")
    if ($start -lt 0) { throw 'C# helper not found.' }
    $start += "Add-Type -TypeDefinition @'".Length
    $end = $updater.IndexOf("'@", $start)
    if ($end -lt 0) { throw 'Unterminated C# helper.' }
    $code = $updater.Substring($start, $end-$start)
    Add-Type -TypeDefinition $code
    $ids = [int[]]@(111,112,113,114)
    $langs = [uint16[]]@(1033,1033,1033,1033)
    $payloads = [byte[][]]::new(4)
    $newSizes = @(180000, 240000, 260000, 64000000)
    for ($i=0; $i -lt 4; ++$i) {
        $payloads[$i] = [byte[]]::new($newSizes[$i])
        $payloads[$i][0] = 0x4D
        $payloads[$i][1] = 0x5A
        $payloads[$i][$payloads[$i].Length - 1] = [byte]($i + 111)
    }
    foreach ($resId in $ids) {
        $lang = [MW3NcpNvidiaResources]::GetLanguage($dll,$resId)
        if ($lang -ne 1033) { throw "Expected language 1033; got $lang for $resId" }
    }
    [MW3NcpNvidiaResources]::Write($dll,$ids,$langs,$payloads)
    for ($i=0; $i -lt 4; ++$i) {
        $bytes = [MW3NcpNvidiaResources]::Read($dll,$ids[$i],$langs[$i])
        if ($bytes.Length -ne $payloads[$i].Length -or $bytes[0] -ne 0x4D -or $bytes[$bytes.Length-1] -ne [byte]($i+111)) {
            throw "Resource not readable after patch: $($ids[$i])"
        }
    }
    Write-Host 'PASS: resource patch and readback with 64MB DLSS-like payload on Windows.'
} finally {
    if (Test-Path $test) { Remove-Item -Recurse -Force -LiteralPath $test -ErrorAction SilentlyContinue }
}
