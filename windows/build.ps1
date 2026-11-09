# Builds XK-7D Companion for Windows: tests, a self-contained app folder with Prism and WinSparkle,
# the packaged app's self-test, the UI Automation check, and the installer. Runs on Windows (CI's
# windows-latest); nothing here needs a Mac.
#
#   windows\build.ps1                      the release build: windows\dist\XK-7D-Companion-<version>-Setup.exe
#   windows\build.ps1 -Version 1.1.1 -TestFeed http://127.0.0.1:8765/appcast-windows.xml -TestKey KEY -OutName test-b
#                                          a test build for the update rehearsal (see .github/workflows/build.yml)
param(
    [string]$Version = "",
    [string]$TestFeed = "",
    [string]$TestKey = "",
    [string]$OutName = "",
    [switch]$SkipTests,
    [switch]$SkipUia
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$root = Split-Path -Parent $here
if (-not $Version) { $Version = (Get-Content "$root\VERSION" -Raw).Trim() }
if (-not $OutName) { $OutName = "XK-7D-Companion-$Version-Setup" }
$dist = Join-Path $here 'dist'
$app = Join-Path $dist 'app'
$cache = Join-Path $env:LOCALAPPDATA 'xk7d-build'
New-Item -ItemType Directory -Force $dist, $cache | Out-Null
if (Test-Path $app) { Remove-Item -Recurse -Force $app }

function Fetch([string]$url, [string]$sha, [string]$file) {
    $path = Join-Path $cache $file
    if (-not (Test-Path $path)) { Invoke-WebRequest -Uri $url -OutFile "$path.part" -UseBasicParsing; Move-Item "$path.part" $path }
    $got = (Get-FileHash $path -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $sha) { Remove-Item $path; throw "$file didn't match its checksum ($got). Removed it; run the build again." }
    return $path
}

if (-not $SkipTests) {
    dotnet test "$here\XK7DCore.Tests" -c Release --nologo
    if ($LASTEXITCODE -ne 0) { throw "core tests failed" }
}

$props = @("-p:Version=$Version")
if ($TestFeed) { $props += "-p:XK7DTestFeed=$TestFeed"; $props += "-p:XK7DTestKey=$TestKey" }
dotnet publish "$here\XK7DCompanion" -c Release -r win-x64 --self-contained true -p:DebugType=none -o $app --nologo @props
if ($LASTEXITCODE -ne 0) { throw "publish failed" }

# Prism 0.18.3 (prism.dll, MPL-2.0) from the prismatoid wheel on PyPI, the same build Wavelength ships.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$wheel = Fetch 'https://files.pythonhosted.org/packages/06/dd/1c444449301f54d5feee854a7261d105fb05823ce4747a7551110c94c913/prismatoid-0.18.3-cp310-abi3-win_amd64.whl' `
    '8c491c4b29878ed33e43c703033b94f2c4840386d34da24076b3cf083a6578eb' 'prismatoid-0.18.3-win_amd64.whl'
# WinSparkle 0.9.4 (MIT), from its GitHub release.
$ws = Fetch 'https://github.com/vslavik/winsparkle/releases/download/v0.9.4/WinSparkle-0.9.4.zip' `
    '6037df37fc263bd1650a1c4949681a9d40ffe991d01f35892a406cb5d103c976' 'WinSparkle-0.9.4.zip'
$licenses = Join-Path $app 'licenses'
New-Item -ItemType Directory -Force (Join-Path $licenses 'prism'), (Join-Path $licenses 'winsparkle') | Out-Null
$z = [System.IO.Compression.ZipFile]::OpenRead($wheel)
try {
    foreach ($e in $z.Entries) {
        if ($e.FullName -eq 'prism/_native/prism.dll') { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $app 'prism.dll'), $true) }
        elseif ($e.FullName -like 'prismatoid-0.18.3.dist-info/licenses/*' -and $e.Name) {
            $dest = Join-Path (Join-Path $licenses 'prism') ($e.FullName.Substring('prismatoid-0.18.3.dist-info/licenses/'.Length) -replace '/', '-')
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
        }
    }
} finally { $z.Dispose() }
$z = [System.IO.Compression.ZipFile]::OpenRead($ws)
try {
    foreach ($e in $z.Entries) {
        switch ($e.FullName) {
            'WinSparkle-0.9.4/x64/Release/WinSparkle.dll' { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $app 'WinSparkle.dll'), $true) }
            'WinSparkle-0.9.4/COPYING' { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $licenses 'winsparkle\COPYING.txt'), $true) }
            'WinSparkle-0.9.4/bin/winsparkle-tool.exe' { [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $dist 'winsparkle-tool.exe'), $true) }
        }
    }
} finally { $z.Dispose() }
Copy-Item "$root\LICENSE" (Join-Path $app 'LICENSE.txt')
@"
XK-7D Companion is MIT licensed (LICENSE.txt). It includes:
- Prism (prism.dll), Mozilla Public License 2.0, https://pypi.org/project/prismatoid/ (licenses\prism)
- WinSparkle (WinSparkle.dll), MIT, https://winsparkle.org (licenses\winsparkle)
- The .NET runtime, MIT, https://github.com/dotnet/runtime
"@ | Set-Content (Join-Path $app 'THIRD-PARTY-NOTICES.txt') -Encoding utf8
foreach ($need in 'XK7DCompanion.exe', 'prism.dll', 'WinSparkle.dll') {
    if (-not (Test-Path (Join-Path $app $need))) { throw "$need is missing from the app folder" }
}

# The packaged app's self-test, run from a copy somewhere else, so nothing can lean on this folder.
$check = Join-Path $env:TEMP ("xk7d-check-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
Copy-Item -Recurse $app $check
$log = Join-Path $check 'selftest.log'
$env:XK7D_TEST_DIR = Join-Path $check 'settings'
$p = Start-Process (Join-Path $check 'XK7DCompanion.exe') -ArgumentList '--self-test', "`"$log`"" -Wait -PassThru
Remove-Item Env:\XK7D_TEST_DIR
Get-Content $log
if ($p.ExitCode -ne 0) { throw "the packaged app's self-test failed (exit $($p.ExitCode))" }
Write-Host "OK: the packaged app passed its self-test from $check"

if (-not $SkipUia -and -not $TestFeed) {
    dotnet run --project "$here\UiaCheck" -c Release -- (Join-Path $check 'XK7DCompanion.exe')
    if ($LASTEXITCODE -ne 0) { throw "the UI Automation check failed" }
}

$iscc = (Get-Command ISCC -ErrorAction SilentlyContinue).Source
if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $iscc)) { throw "Inno Setup 6 isn't installed (choco install innosetup)" }
& $iscc /Q "/DAppVersion=$Version" "/DSourceDir=$app" "/DOutputName=$OutName" "$here\installer\XK7DCompanion.iss"
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
$setup = Join-Path $dist "$OutName.exe"
Write-Host "Built $setup ($((Get-Item $setup).Length) bytes, sha256 $((Get-FileHash $setup -Algorithm SHA256).Hash.ToLower()))"
