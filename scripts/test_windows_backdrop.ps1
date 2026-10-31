# Standalone Win32 unit test, run from Visual Studio Developer PowerShell.
$ErrorActionPreference = 'Stop'
Get-Command cl.exe -ErrorAction Stop | Out-Null
$app = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../cb_file_manager'))
$output = Join-Path $app 'build/native_backdrop_test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Push-Location -LiteralPath $output
try {
    & cl.exe /nologo /std:c++17 /utf-8 /EHsc /W4 /WX /DNOMINMAX /DUNICODE /D_UNICODE `
        "$app/windows/runner/tests/window_backdrop_test.cpp" `
        /Fe:window_backdrop_test.exe /link user32.lib dwmapi.lib
    if ($LASTEXITCODE -ne 0) { throw 'Native backdrop test compilation failed.' }
    & ./window_backdrop_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native backdrop unit test failed.' }
} finally {
    Pop-Location
}
