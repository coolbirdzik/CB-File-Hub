import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

const bash = process.platform === 'win32'
  ? path.join(process.env.ProgramFiles || 'C:/Program Files', 'Git/bin/bash.exe')
  : '/bin/bash';
const shellPath = (value) => value.replaceAll('\\', '/');

function command(executable, args, options = {}) {
  const result = spawnSync(executable, args, { encoding: 'utf8', timeout: 30_000, ...options });
  assert.ifError(result.error);
  return result;
}

function requireSuccess(result) {
  assert.equal(result.status, 0, result.stdout + result.stderr);
}

function fixture(t, native = false) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-macos-subtitles-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const repo = path.join(root, 'repo');
  const script = path.join(repo, 'scripts/stage_macos_subtitle_runtime.sh');
  fs.mkdirSync(path.dirname(script), { recursive: true });
  fs.writeFileSync(script, fs.readFileSync(
    new URL('../stage_macos_subtitle_runtime.sh', import.meta.url), 'utf8',
  ).replaceAll('\r\n', '\n'));
  const notices = path.join(repo, 'native/subtitles/THIRD_PARTY_NOTICES.md');
  fs.mkdirSync(path.dirname(notices), { recursive: true });
  fs.copyFileSync(new URL('../../native/subtitles/THIRD_PARTY_NOTICES.md', import.meta.url), notices);
  const app = path.join(root, 'CB File Hub.app');
  const contents = path.join(app, 'Contents');
  const helpers = path.join(contents, 'Helpers/subtitles');
  const resources = path.join(contents, 'Resources/subtitles');
  fs.mkdirSync(helpers, { recursive: true });
  const names = ['LICENSE-whisper', 'LICENSE-FFmpeg', 'THIRD_PARTY_NOTICES.md'];
  for (const name of names) fs.writeFileSync(path.join(helpers, name), 'legacy unsigned data');
  const whisperLicense = path.join(root, 'whisper-license');
  const ffmpegLicense = path.join(root, 'ffmpeg-license');
  fs.writeFileSync(whisperLicense, 'Whisper license');
  fs.writeFileSync(ffmpegLicense, 'FFmpeg license');
  const binary = path.join(root, 'worker');
  const tools = path.join(root, 'tools');
  fs.mkdirSync(tools);
  const log = path.join(root, 'signatures');
  function tool(name, body) {
    fs.writeFileSync(path.join(tools, name), `#!/bin/bash\nset -eu\n${body}\n`, { mode: 0o755 });
  }
  if (!native) {
    fs.writeFileSync(binary, 'compiled helper fixture');
    tool('lipo', 'input=$2; while [ "$1" != -output ]; do shift; done; cp "$input" "$2"');
    tool('otool', 'echo "${CB_TEST_DYLIB:-/usr/lib/libSystem.B.dylib}"');
    tool('codesign', 'printf "%s\\n" "${@: -1}" >> "$CB_TEST_SIGN_LOG"');
  }
  function stage(environment = {}) {
    return command(bash, [script, contents, whisperLicense, ffmpegLicense, binary].map(shellPath), {
      env: {
        ...process.env,
        PATH: native ? process.env.PATH : `${tools}${path.delimiter}${process.env.PATH}`,
        CB_TEST_SIGN_LOG: shellPath(log),
        CODE_SIGNING_ALLOWED: 'YES',
        EXPANDED_CODE_SIGN_IDENTITY: '-',
        ...environment,
      },
    });
  }
  function checkLayout() {
    assert.deepEqual(fs.readdirSync(helpers), ['cb-subtitle-worker']);
    for (const name of names) assert.ok(fs.statSync(path.join(resources, name)).size > 0);
    assert.equal(fs.readFileSync(path.join(resources, 'LICENSE-whisper'), 'utf8'), 'Whisper license');
    assert.equal(fs.readFileSync(path.join(resources, 'LICENSE-FFmpeg'), 'utf8'), 'FFmpeg license');
  }
  return { root, app, contents, helpers, resources, binary, log, stage, checkLayout };
}

test('staging repairs old Helpers data and signs only the helper', (t) => {
  const f = fixture(t);
  requireSuccess(f.stage());
  f.checkLayout();
  const signed = fs.readFileSync(f.log, 'utf8').trim().replaceAll('\\', '/');
  assert.ok(signed.endsWith('/Contents/Helpers/subtitles/cb-subtitle-worker'), signed);
  assert.equal(signed.split('\n').length, 1);
});

test('unsigned builds still keep license data out of Helpers', (t) => {
  const f = fixture(t);
  requireSuccess(f.stage({ CODE_SIGNING_ALLOWED: 'NO' }));
  f.checkLayout();
  assert.equal(fs.existsSync(f.log), false);
});

test('unbundled Homebrew dependency still stops staging', (t) => {
  const f = fixture(t);
  const result = f.stage({ CB_TEST_DYLIB: '/opt/homebrew/lib/libavcodec.dylib' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unbundled package-manager dependency/);
  assert.equal(fs.existsSync(f.log), false);
});

test('real macOS signing rejects legacy data and accepts the staged bundle', {
  skip: process.platform !== 'darwin' ? 'Requires Apple codesign and Mach-O tools' : false,
}, (t) => {
  const f = fixture(t, true);
  const mainDir = path.join(f.contents, 'MacOS');
  fs.mkdirSync(mainDir);
  const main = path.join(mainDir, 'bundle-probe');
  const source = path.join(f.root, 'main.c');
  fs.writeFileSync(source, 'int main(void) { return 0; }\n');
  requireSuccess(command('xcrun', ['clang', source, '-o', main]));
  fs.copyFileSync(main, f.binary);
  fs.writeFileSync(path.join(f.contents, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>bundle-probe</string>
<key>CFBundleIdentifier</key><string>net.coolbird.tests.subtitle-signing</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>\n`);
  const signArgs = ['--force', '--sign', '-', '--timestamp=none', f.app];
  const rejected = command('/usr/bin/codesign', signArgs);
  assert.notEqual(rejected.status, 0, 'Legacy license files in Helpers must fail signing');
  requireSuccess(f.stage());
  f.checkLayout();
  requireSuccess(command('/usr/bin/codesign', signArgs));
  requireSuccess(command('/usr/bin/codesign', ['--verify', '--deep', '--strict', '--verbose=2', f.app]));
});
