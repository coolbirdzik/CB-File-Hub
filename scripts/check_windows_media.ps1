param(
    [string]$Bundle = "$PSScriptRoot/../cb_file_manager/build/windows/x64/runner/Release",
    [string]$Fixtures = "$PSScriptRoot/../cb_file_manager/build/windows-media-fixtures"
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$generator = 'Visual Studio 17 2022'
$cmakeTool = 'cmake'
$appCache = "$repo/cb_file_manager/build/windows/x64/CMakeCache.txt"
if (Test-Path -LiteralPath $appCache) {
    $line = Get-Content -LiteralPath $appCache | Where-Object { $_ -like 'CMAKE_GENERATOR:INTERNAL=Visual Studio*' } | Select-Object -First 1
    if ($line) { $generator = $line.Split('=', 2)[1] }
    $line = Get-Content -LiteralPath $appCache | Where-Object { $_ -like 'CMAKE_COMMAND:INTERNAL=*' } | Select-Object -First 1
    if ($line) { $cmakeTool = $line.Split('=', 2)[1] }
}
$build = "$repo/cb_file_manager/build/windows-thumbnail-test/$($generator.Replace(' ', '-'))"
& $cmakeTool -S "$repo/native/tests/windows_thumbnail" -B $build -G $generator -A x64 "-DFFMPEG_DIR=$repo/cb_file_manager/windows/ffmpeg-slim"
if ($LASTEXITCODE) { throw 'Thumbnail component configure failed' }
& $cmakeTool --build $build --config Release
if ($LASTEXITCODE) { throw 'Thumbnail component build failed' }
$previous = @{}
foreach ($name in @('CB_BUNDLE_DIR', 'CB_MEDIA_FIXTURES', 'CB_THUMBNAIL_TEST_EXE')) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    $env:CB_BUNDLE_DIR = [IO.Path]::GetFullPath($Bundle)
    $env:CB_MEDIA_FIXTURES = [IO.Path]::GetFullPath($Fixtures)
    $env:CB_THUMBNAIL_TEST_EXE = "$build/Release/thumbnail_component.exe"
    & python -m unittest discover -s "$repo/scripts/tests" -p test_windows_bundle_runtime.py -v
    if ($LASTEXITCODE) { throw 'Windows runtime component checks failed' }
} finally {
    foreach ($name in $previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
    }
}
