# Standalone Win32 unit test, run from Visual Studio Developer PowerShell.
$ErrorActionPreference = 'Stop'
Get-Command cl.exe -ErrorAction Stop | Out-Null
$app = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../cb_file_manager'))
$output = Join-Path $app 'build/native_torrent_launch_test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Push-Location -LiteralPath $output
try {
    & cl.exe /nologo /std:c++17 /utf-8 /EHsc /W4 /WX /DNOMINMAX /DUNICODE /D_UNICODE `
        "$app/windows/runner/tests/torrent_launch_test.cpp" `
        "$app/windows/runner/torrent_launch.cpp" `
        /Fe:torrent_launch_test.exe /link user32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Native torrent launch test compilation failed.' }
    & ./torrent_launch_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native torrent launch unit test failed.' }
} finally {
    Pop-Location
}
