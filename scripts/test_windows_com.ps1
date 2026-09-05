# Run in Visual Studio Developer PowerShell after a Debug Windows build:
# powershell -File scripts/test_windows_com.ps1
$ErrorActionPreference = 'Stop'
Get-Command cl.exe -ErrorAction Stop | Out-Null
$app = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../cb_file_manager'))
$output = Join-Path $app 'build/native_com_test'
$ephemeral = Join-Path $app 'windows/flutter/ephemeral'
$wrapper = Join-Path $app 'build/windows/x64/flutter/Debug/flutter_wrapper_plugin.lib'
if (!(Test-Path -LiteralPath $wrapper)) {
    throw 'Build the Windows app in Debug first to generate Flutter wrapper libraries.'
}
New-Item -ItemType Directory -Force -Path $output | Out-Null
$compilerArgs = @(
    '/nologo', '/std:c++17', '/EHsc', '/MDd', '/DNOMINMAX', '/DUNICODE', '/D_UNICODE',
    "/I`"$ephemeral`"",
    "/I`"$ephemeral/cpp_client_wrapper/include`"",
    "`"$app/windows/runner/tests/file_operations_com_test.cpp`"",
    "/Fo`"$output/file_operations_com_test.obj`"",
    "/Fe`"$output/file_operations_com_test.exe`"",
    '/link', "`"$wrapper`"", "`"$ephemeral/flutter_windows.dll.lib`"",
    'ole32.lib', 'shell32.lib', 'oleaut32.lib', 'user32.lib', 'uuid.lib'
)
$responseFile = Join-Path $output 'compile.rsp'
Set-Content -LiteralPath $responseFile -Value $compilerArgs
& cl.exe "@$responseFile"
if ($LASTEXITCODE -ne 0) { throw 'Native regression test compilation failed.' }
$previousPath = $env:PATH
try {
    $env:PATH = "$app/build/windows/x64/runner/Debug;$previousPath"
    & "$output/file_operations_com_test.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Native COM regression test failed.' }
} finally {
    $env:PATH = $previousPath
}
