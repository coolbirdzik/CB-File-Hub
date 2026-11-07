import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

// Exercise the real build function with fake Flutter/package commands. Never
// source build.sh: its main dispatcher could run a real build or read .env.
const source = fs.readFileSync(new URL('../build.sh', import.meta.url), 'utf8')
  .replaceAll('\r\n', '\n');
const start = source.indexOf('build_windows_portable() {');
const end = source.indexOf('\n# Build Windows EXE', start);
assert.ok(start >= 0 && end > start);
const buildFunction = source.slice(start, end);
const shellQuote = (value) => `'${value.replaceAll("'", "'\\''")}'`;
const bash = process.platform === 'win32'
  ? path.join(process.env.ProgramFiles || 'C:/Program Files', 'Git/bin/bash.exe')
  : 'bash';

function runBuild(t, failures) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-windows-build-'));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const project = path.join(temporary, 'app');
  fs.mkdirSync(path.join(project, 'build/windows/x64/runner/Release'), { recursive: true });
  const scripts = path.join(temporary, 'scripts');
  fs.mkdirSync(scripts);
  for (const name of ['fetch_llama_runtime.sh', 'fetch_aria2_runtime.sh']) {
    fs.writeFileSync(path.join(scripts, name), 'exit 0\n');
  }
  const fixture = `
set -e
export PATH=/usr/bin:/bin:$PATH
cd ${shellQuote(temporary.replaceAll('\\', '/'))}
PROJECT_DIR="$PWD/app"
BUILD_DIR="$PROJECT_DIR/build"
SCRIPT_DIR="$PWD/scripts"
COUNTER="$PWD/count"
PACKAGED="$PWD/packaged"
CLOUD_DEFINES=()
print_info() { echo "$*"; }
print_warning() { echo "$*"; }
print_error() { echo "$*"; }
print_success() { echo "$*"; }
clean_build() { :; }
install_deps() { :; }
get_version_name() { echo 1.0.0; }
get_windows_version_code() { echo 1; }
sleep() { :; }
verify_windows_release_bundle() { :; }
zip() { touch "$PACKAGED"; }
flutter() {
  local attempt=0
  if [ -f "$COUNTER" ]; then attempt=$(cat "$COUNTER"); fi
  attempt=$((attempt + 1))
  echo "$attempt" > "$COUNTER"
  case "$attempt" in
${failures.map((message, index) => `    ${index + 1}) echo ${shellQuote(message)}; return 1 ;;`).join('\n')}
  esac
  echo 'Build succeeded'
}
${buildFunction}
build_windows_portable
`;
  const fixturePath = path.join(temporary, 'fixture.sh');
  fs.writeFileSync(fixturePath, fixture);
  const result = spawnSync(bash, [fixturePath.replaceAll('\\', '/')], {
    encoding: 'utf8', timeout: 30_000,
  });
  assert.ifError(result.error);
  assert.ok(fs.existsSync(path.join(temporary, 'count')), result.stdout + result.stderr);
  return {
    status: result.status,
    output: result.stdout + result.stderr,
    attempts: Number(fs.readFileSync(path.join(temporary, 'count'), 'utf8')),
    packaged: fs.existsSync(path.join(temporary, 'packaged')),
  };
}

test('Flutter failure through tee stops before packaging', (t) => {
  const result = runBuild(t, ['Unable to generate build files']);
  assert.notEqual(result.status, 0, result.output);
  assert.equal(result.attempts, 1);
  assert.equal(result.packaged, false);
  assert.doesNotMatch(result.output, /Creating ZIP/);
});

test('failed CMake retry stops before packaging', (t) => {
  const result = runBuild(t, ['MSB3073 CMake failed', 'MSB3073 CMake failed again']);
  assert.notEqual(result.status, 0, result.output);
  assert.equal(result.attempts, 2);
  assert.equal(result.packaged, false);
});

test('successful CMake retry permits packaging', (t) => {
  const result = runBuild(t, ['MSB3073 CMake failed']);
  assert.equal(result.status, 0, result.output);
  assert.equal(result.attempts, 2);
  assert.equal(result.packaged, true);
});

test('successful initial build packages without retry', (t) => {
  const result = runBuild(t, []);
  assert.equal(result.status, 0, result.output);
  assert.equal(result.attempts, 1);
  assert.equal(result.packaged, true);
});
