# Standalone Win32 unit test, run from Visual Studio Developer PowerShell.
$ErrorActionPreference = 'Stop'
Get-Command cl.exe -ErrorAction Stop | Out-Null
$app = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../cb_file_manager'))
$output = Join-Path $app 'build/native_media_kit_reference_cleanup_test'
New-Item -ItemType Directory -Force -Path $output | Out-Null
Push-Location -LiteralPath $output
try {
    & cl.exe /nologo /std:c++17 /utf-8 /EHsc /W4 /WX /DNOMINMAX /DUNICODE /D_UNICODE `
        "$app/windows/runner/tests/media_kit_reference_cleanup_test.cpp" `
        /Fe:media_kit_reference_cleanup_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Media kit reference cleanup compilation failed.' }
    & ./media_kit_reference_cleanup_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Media kit reference cleanup test failed.' }
} finally {
    Pop-Location
}
