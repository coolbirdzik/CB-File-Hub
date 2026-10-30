# Standalone Win32 unit test, run from Visual Studio Developer PowerShell.
$ErrorActionPreference = 'Stop'
Get-Command cl.exe -ErrorAction Stop | Out-Null
$app = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../cb_file_manager'))
$output = Join-Path $app 'build/native_custom_frame_test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Push-Location -LiteralPath $output
try {
    & cl.exe /nologo /std:c++17 /utf-8 /EHsc /W4 /WX /DNOMINMAX /DUNICODE /D_UNICODE `
        "$app/windows/runner/tests/custom_frame_message_test.cpp" `
        "$app/windows/runner/flutter_mouse_input_guard.cpp" `
        /Fe:custom_frame_message_test.exe /link user32.lib dwmapi.lib comctl32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Native frame test compilation failed.' }
    & ./custom_frame_message_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native frame unit test failed.' }
} finally {
    Pop-Location
}
