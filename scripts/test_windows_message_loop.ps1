# Standalone Win32 unit test, run from Visual Studio Developer PowerShell.
$ErrorActionPreference = 'Stop'
Get-Command cl.exe -ErrorAction Stop | Out-Null
$app = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../cb_file_manager'))
$output = Join-Path $app 'build/native_message_loop_test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Push-Location -LiteralPath $output
try {
    & cl.exe /nologo /std:c++17 /utf-8 /EHsc /W4 /WX /DNOMINMAX /DUNICODE /D_UNICODE `
        "$app/windows/runner/tests/priority_message_loop_test.cpp" `
        /Fe:priority_message_loop_test.exe /link user32.lib
    if ($LASTEXITCODE -ne 0) { throw 'Native message loop test compilation failed.' }
    & ./priority_message_loop_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Native message loop unit test failed.' }
} finally {
    Pop-Location
}
