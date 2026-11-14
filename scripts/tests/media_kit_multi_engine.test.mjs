import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const root = fileURLToPath(new URL('../../', import.meta.url));
const packageConfig = new URL('../../cb_file_manager/.dart_tool/package_config.json', import.meta.url);

test('Windows texture callbacks stay with their engine after another engine opens/closes', (t) => {
  if (!fs.existsSync(packageConfig)) return t.skip('Run flutter pub get first');
  const packages = JSON.parse(fs.readFileSync(packageConfig, 'utf8')).packages;
  const pkg = packages.find((item) => item.name === 'media_kit_video');
  assert.ok(pkg, 'media_kit_video must be resolved');
  const plugin = fileURLToPath(new URL('windows/', new URL(`${pkg.rootUri.replace(/\/$/, '')}/`, packageConfig)));
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-media-kit-unit-'));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const cmakePath = (value) => value.replaceAll('\\', '/');
  let cmake = process.env.CMAKE_COMMAND ?? 'cmake';
  const run = (command, args, expected = 0) => {
    const result = spawnSync(command === 'cmake' ? cmake : command, args, { encoding: 'utf8' });
    assert.equal(result.status, expected, `${command}: ${result.error ?? ''}\n${result.stdout}\n${result.stderr}`);
  };
  fs.writeFileSync(path.join(temporary, 'CMakeLists.txt'), `
cmake_minimum_required(VERSION 3.14)
project(media_kit_window_dispatch_unit LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
add_subdirectory(plugin)
include("${cmakePath(path.join(root, 'cb_file_manager/windows/cmake/media_kit_video_multi_engine.cmake'))}")
coolbird_patch_media_kit_video()
add_executable(dispatch_patched patched.cpp)
add_executable(dispatch_upstream upstream.cpp)
`);
  fs.mkdirSync(path.join(temporary, 'plugin'));
  const upstream = fs.readFileSync(path.join(plugin, 'media_kit_video_plugin.cc'), 'utf8').replaceAll('\r\n', '\n');
  fs.writeFileSync(path.join(temporary, 'plugin/media_kit_video_plugin.cc'), upstream);
  fs.writeFileSync(path.join(temporary, 'plugin/CMakeLists.txt'), `
add_library(media_kit_video_plugin STATIC EXCLUDE_FROM_ALL media_kit_video_plugin.cc)
`);
  // Configure compiles neither Flutter nor the plugin; it runs the real patch.
  for (const name of ['patched', 'upstream']) fs.writeFileSync(path.join(temporary, `${name}.cpp`), 'int main() {}');
  const generatorArgs = [];
  if (process.platform === 'win32' && !process.env.CMAKE_GENERATOR) {
    const vswhere = path.join(process.env['ProgramFiles(x86)'] ?? 'C:/Program Files (x86)', 'Microsoft Visual Studio/Installer/vswhere.exe');
    const version = spawnSync(vswhere, ['-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationVersion'], { encoding: 'utf8' }).stdout?.trim();
    const major = Number(version?.split('.')[0]);
    const year = { 16: 2019, 17: 2022, 18: 2026 }[major];
    assert.ok(year, `A supported Visual Studio C++ toolchain is required (${version})`);
    const installation = spawnSync(vswhere, ['-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], { encoding: 'utf8' }).stdout.trim();
    const bundledCmake = path.join(installation, 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe');
    if (!process.env.CMAKE_COMMAND && fs.existsSync(bundledCmake)) cmake = bundledCmake;
    generatorArgs.push('-G', `Visual Studio ${major} ${year}`, '-A', 'x64');
  }
  run('cmake', ['-S', temporary, '-B', path.join(temporary, 'build'), ...generatorArgs]);
  const patched = fs.readFileSync(path.join(temporary, 'build/media_kit_video_multi_engine.cc'), 'utf8');
  assert.ok(patched.includes('::SetPropW(flutter_window_, kWindowInstance, this);'));
  for (const [name, source] of [['patched', patched], ['upstream', upstream]]) {
    const dispatch = source.match(/LRESULT CALLBACK MediaKitVideoPlugin::WindowProcDelegate\([\s\S]*?(?=\nvoid MediaKitVideoPlugin::ProcessMainThreadTasks)/)?.[0];
    const destructor = source.match(/MediaKitVideoPlugin::~MediaKitVideoPlugin\(\)[\s\S]*?(?=\nvoid MediaKitVideoPlugin::RunOnMainThread)/)?.[0];
    assert.ok(dispatch && destructor, 'Upstream host entry points must be found');
    // Compile the actual generated dispatch and destructor against a tiny Win32
    // double. Two engine queues, normal message forwarding and teardown are
    // exercised without launching the app or running desktop E2E.
    fs.writeFileSync(path.join(temporary, `${name}.cpp`), `
#include <cstdint>
#include <map>
using HWND = intptr_t;
using UINT = unsigned;
using WPARAM = uintptr_t;
using LPARAM = intptr_t;
using LONG_PTR = intptr_t;
using LRESULT = intptr_t;
using WNDPROC = LRESULT (*)(HWND, UINT, WPARAM, LPARAM);
#define CALLBACK
constexpr int GWLP_WNDPROC = -4;
constexpr wchar_t kWindowInstance[] = L"CBFileHub.MediaKitVideo.Instance";
std::map<HWND, void*> properties;
std::map<HWND, LONG_PTR> procedures;
void* GetPropW(HWND window, const wchar_t*) { return properties[window]; }
void RemovePropW(HWND window, const wchar_t*) { properties.erase(window); }
LONG_PTR GetWindowLongPtr(HWND window, int) { return procedures[window]; }
LONG_PTR SetWindowLongPtr(HWND window, int, LONG_PTR value) {
  auto previous = procedures[window]; procedures[window] = value; return previous;
}
LRESULT CallWindowProc(WNDPROC proc, HWND window, UINT msg, WPARAM w, LPARAM l) {
  return proc(window, msg, w, l);
}
LRESULT DefWindowProc(HWND, UINT, WPARAM, LPARAM) { return -1; }
LRESULT FirstProc(HWND, UINT, WPARAM, LPARAM) { return 11; }
LRESULT SecondProc(HWND, UINT, WPARAM, LPARAM) { return 22; }
LRESULT ReclaimedProc(HWND, UINT, WPARAM, LPARAM) { return 33; }
class MediaKitVideoPlugin {
 public:
  static constexpr UINT kMainThreadTaskMessage = 2025;
  static MediaKitVideoPlugin* instance_;
  HWND flutter_window_;
  WNDPROC original_window_proc_;
  int drained = 0;
  MediaKitVideoPlugin(HWND window, WNDPROC proc) : flutter_window_(window), original_window_proc_(proc) {
    properties[window] = this;
    procedures[window] = reinterpret_cast<LONG_PTR>(WindowProcDelegate);
    instance_ = this;
  }
  ~MediaKitVideoPlugin();
  static LRESULT CALLBACK WindowProcDelegate(HWND, UINT, WPARAM, LPARAM);
  void ProcessMainThreadTasks() { ++drained; }
};
MediaKitVideoPlugin* MediaKitVideoPlugin::instance_ = nullptr;
${dispatch}
${destructor}
int main() {
  MediaKitVideoPlugin first(1, FirstProc);
  {
    MediaKitVideoPlugin second(2, SecondProc);
    MediaKitVideoPlugin::WindowProcDelegate(1, 2025, 0, 0);
    if (first.drained != 1 || second.drained != 0) return 1;
    MediaKitVideoPlugin::WindowProcDelegate(2, 2025, 0, 0);
    if (first.drained != 1 || second.drained != 1) return 2;
    if (MediaKitVideoPlugin::WindowProcDelegate(1, 0, 0, 0) != 11) return 3;
    if (MediaKitVideoPlugin::WindowProcDelegate(2, 0, 0, 0) != 22) return 4;
    procedures[2] = reinterpret_cast<LONG_PTR>(ReclaimedProc);
  }
  if (GetPropW(2, kWindowInstance) != nullptr) return 5;
  if (procedures[2] != reinterpret_cast<LONG_PTR>(ReclaimedProc)) return 6;
  MediaKitVideoPlugin::WindowProcDelegate(1, 2025, 0, 0);
  if (first.drained != 2) return 7;
  if (MediaKitVideoPlugin::WindowProcDelegate(2, 2025, 0, 0) != -1) return 8;
  return 0;
}
`);
  }
  run('cmake', ['--build', path.join(temporary, 'build'), '--config', 'Release', '--target', 'dispatch_patched', 'dispatch_upstream']);
  const executable = (name) => path.join(temporary, 'build', ...(process.platform === 'win32' ? ['Release', `${name}.exe`] : [name]));
  run(executable('dispatch_upstream'), [], 1); // Reproduce the original cross-engine bug.
  run(executable('dispatch_patched'), []);
});
