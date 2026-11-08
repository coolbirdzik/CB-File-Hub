import assert from 'node:assert/strict';
import { execFile, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

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

// Run the real CMake resolver against a tiny developer archive and loopback
// server, without building Flutter or downloading any external dependency.
async function createFfmpegFixture(t, responseFor) {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-ffmpeg-deps-'));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const payload = path.join(temporary, 'payload');
  fs.mkdirSync(path.join(payload, 'ffmpeg/include/libavcodec'), { recursive: true });
  fs.mkdirSync(path.join(payload, 'ffmpeg/lib'), { recursive: true });
  fs.writeFileSync(path.join(payload, 'ffmpeg/include/libavcodec/avcodec.h'), 'fixture header\n');
  fs.writeFileSync(path.join(payload, 'ffmpeg/lib/avcodec.lib'), 'fixture library\n');
  const archive = path.join(temporary, 'fixture.zip');
  const packed = spawnSync('cmake', ['-E', 'tar', 'cf', archive, '--format=zip', 'ffmpeg'], {
    cwd: payload, encoding: 'utf8', timeout: 30_000,
  });
  assert.ifError(packed.error);
  assert.equal(packed.status, 0, packed.stdout + packed.stderr);
  const body = fs.readFileSync(archive);
  const digest = createHash('sha256').update(body).digest('hex');
  const requests = [];
  const server = createServer((request, response) => {
    requests.push({ url: request.url, headers: request.headers });
    const reply = responseFor(request, requests.length);
    response.writeHead(reply.status, { 'Content-Type': 'application/octet-stream' });
    response.end(reply.body ?? body);
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const baseUrl = `http://127.0.0.1:${server.address().port}`;
  const build = path.join(temporary, 'build');
  const driver = path.join(temporary, 'resolve.cmake');
  const dependencies = fileURLToPath(new URL('../../cb_file_manager/windows/cmake/dependencies.cmake', import.meta.url));
  fs.writeFileSync(driver, `
cmake_minimum_required(VERSION 3.14)
set(CMAKE_SOURCE_DIR "${temporary.replaceAll('\\', '/')}/source")
set(CMAKE_BINARY_DIR "${build.replaceAll('\\', '/')}")
include("${dependencies.replaceAll('\\', '/')}")
set(COOLBIRD_FFMPEG_DOWNLOAD_URL "${baseUrl}/primary")
set(COOLBIRD_FFMPEG_DOWNLOAD_FALLBACK_URL "${baseUrl}/fallback")
set(COOLBIRD_FFMPEG_SHA256 "${digest}")
coolbird_resolve_ffmpeg_dir(RESOLVED)
if(NOT EXISTS "\${RESOLVED}/include/libavcodec/avcodec.h"
    OR NOT EXISTS "\${RESOLVED}/lib/avcodec.lib")
  message(FATAL_ERROR "Invalid FFmpeg development archive: \${RESOLVED}")
endif()
`);
  return {
    requests,
    cachedArchive: path.join(build, `_deps/ffmpeg-${digest}.zip`),
    ready: path.join(build, `_deps/ffmpeg-${digest.slice(0, 12)}/.ready`),
    async run() {
      try {
        const result = await promisify(execFile)('cmake', ['-P', driver], {
          encoding: 'utf8', timeout: 30_000,
        });
        return { status: 0, output: result.stdout + result.stderr };
      } catch (error) {
        assert.equal(typeof error.code, 'number', error.message);
        return { status: error.code, output: error.stdout + error.stderr };
      }
    },
  };
}

test('FFmpeg primary download succeeds and verified cache avoids network', async (t) => {
  const fixture = await createFfmpegFixture(t, () => ({ status: 200 }));
  const first = await fixture.run();
  assert.equal(first.status, 0, first.output);
  assert.ok(fs.existsSync(fixture.ready));
  const second = await fixture.run();
  assert.equal(second.status, 0, second.output);
  assert.deepEqual(fixture.requests.map((request) => request.url), ['/primary']);
});

test('FFmpeg API fallback recovers from HTTP failure without failing CMake', async (t) => {
  const fixture = await createFfmpegFixture(t, (request) => request.url === '/primary'
    ? { status: 504, body: 'gateway timeout' } : { status: 200 });
  const result = await fixture.run();
  assert.equal(result.status, 0, result.output);
  assert.doesNotMatch(result.output, /CMake Error/);
  assert.deepEqual(fixture.requests.map((request) => request.url), ['/primary', '/fallback']);
  assert.equal(fixture.requests[1].headers.accept, 'application/octet-stream');
  assert.equal(fixture.requests[1].headers['user-agent'], 'CB-File-Hub-build');
});

test('FFmpeg retries when both endpoints fail transiently', async (t) => {
  const fixture = await createFfmpegFixture(t, (_request, count) => count <= 2
    ? { status: 503, body: 'temporary outage' } : { status: 200 });
  const result = await fixture.run();
  assert.equal(result.status, 0, result.output);
  assert.deepEqual(fixture.requests.map((request) => request.url), ['/primary', '/fallback', '/primary']);
});

test('FFmpeg checksum mismatch falls back before extracting', async (t) => {
  const fixture = await createFfmpegFixture(t, (request) => request.url === '/primary'
    ? { status: 200, body: 'invalid archive' } : { status: 200 });
  const result = await fixture.run();
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /SHA256\s+mismatch/);
  assert.deepEqual(fixture.requests.map((request) => request.url), ['/primary', '/fallback']);
  assert.ok(fs.existsSync(fixture.ready));
});

test('FFmpeg exhausted downloads remove corrupt responses and never mark ready', async (t) => {
  const fixture = await createFfmpegFixture(t, (request) => request.url === '/primary'
    ? { status: 504, body: 'gateway timeout' } : { status: 200, body: '{"asset":"metadata, not binary"}' });
  const result = await fixture.run();
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /Unable to download FFmpeg archive after multiple attempts/);
  assert.equal(fixture.requests.length, 6);
  assert.equal(fs.existsSync(fixture.cachedArchive), false);
  assert.equal(fs.existsSync(fixture.ready), false);
});

test('FFmpeg rejects corrupt cached archives without extracting or downloading', async (t) => {
  const fixture = await createFfmpegFixture(t, () => ({ status: 200 }));
  fs.mkdirSync(path.dirname(fixture.cachedArchive), { recursive: true });
  fs.writeFileSync(fixture.cachedArchive, 'corrupt cached archive');
  const result = await fixture.run();
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /Cached FFmpeg archive checksum mismatch/);
  assert.deepEqual(fixture.requests, []);
  assert.equal(fs.existsSync(fixture.ready), false);
});
