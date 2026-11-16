import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const bash = process.platform === 'win32'
  ? 'C:/Program Files/Git/bin/bash.exe' : '/bin/bash';
const script = new URL('../stage_macos_arch_bundle.sh', import.meta.url);
const unix = (value) => value.replaceAll('\\', '/');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-mac-arch-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const source = path.join(root, 'source.app');
  const dest = path.join(root, 'thin.app');
  function put(relative, text) {
    const name = path.join(source, relative);
    fs.mkdirSync(path.dirname(name), { recursive: true });
    fs.writeFileSync(name, text);
  }
  put('Contents/MacOS/app', 'MACHO:arm64 x86_64\nmain');
  put('Contents/Frameworks/Flutter.framework/Flutter', 'MACHO:arm64 x86_64\nengine');
  put('Contents/Frameworks/LiteRtLm.framework/LiteRtLm', 'MACHO:arm64\noptional');
  for (const arch of ['arm64', 'x86_64']) {
    put(`Contents/Helpers/llama/${arch}/llama-server`, `MACHO:${arch}\nserver`);
  }
  put('Contents/Resources/license.txt', 'license');
  const tools = path.join(root, 'tools');
  fs.mkdirSync(tools);
  const tool = (name, body) => fs.writeFileSync(path.join(tools, name),
    `#!/bin/bash\nset -eu\n${body}\n`, { mode: 0o755 });
  tool('ditto', 'cp -a "$1" "$2"');
  tool('file', 'if head -n1 "$2" | grep -q ^MACHO:; then echo Mach-O; else echo ASCII; fi');
  tool('stat', 'echo 755');
  tool('lipo', `if [ "$1" = -archs ]; then head -n1 "$2" | sed 's/^MACHO://';
else printf 'MACHO:%s\\nthinned\\n' "$3" > "$5"; fi`);
  const localScript = path.join(root, 'stage.sh');
  const shellTools = process.platform === 'win32'
    ? unix(tools).replace(/^([a-z]):/i, (_, drive) => `/${drive.toLowerCase()}`)
    : tools;
  fs.writeFileSync(localScript, fs.readFileSync(script, 'utf8').replaceAll('\r\n', '\n')
    .replace('set -euo pipefail', `set -euo pipefail\nexport PATH="${shellTools}:/usr/bin:/bin:$PATH"`));
  return { source, dest, put, run(arch) {
    const result = spawnSync(bash, [unix(localScript), unix(source), unix(dest), arch], {
      encoding: 'utf8', timeout: 30_000,
      env: { ...process.env, PATH: `${tools}${path.delimiter}${process.env.PATH}` },
    });
    assert.ifError(result.error);
    return result;
  } };
}

for (const arch of ['arm64', 'x86_64']) {
  test(`stages ${arch}, preserves source/licenses and removes foreign helpers`, (t) => {
    const f = fixture(t);
    const result = f.run(arch);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.match(fs.readFileSync(path.join(f.dest, 'Contents/MacOS/app'), 'utf8'), new RegExp(`^MACHO:${arch}\\n`));
    assert.deepEqual(fs.readdirSync(path.join(f.dest, 'Contents/Helpers/llama')), [arch]);
    assert.equal(fs.readFileSync(path.join(f.dest, 'Contents/Resources/license.txt'), 'utf8'), 'license');
    assert.match(fs.readFileSync(path.join(f.source, 'Contents/MacOS/app'), 'utf8'), /arm64 x86_64/);
    assert.equal(fs.existsSync(path.join(f.dest, 'Contents/Frameworks/LiteRtLm.framework')), arch === 'arm64');
  });
}

test('refuses a package with a required framework missing its target slice', (t) => {
  const f = fixture(t);
  f.put('Contents/Frameworks/Flutter.framework/Flutter', 'MACHO:arm64\nengine');
  const result = f.run('x86_64');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /has no x86_64 slice/);
});

test('rejects unsupported architecture and existing destination', (t) => {
  const f = fixture(t);
  assert.notEqual(f.run('armv7').status, 0);
  fs.mkdirSync(f.dest);
  assert.match(f.run('arm64').stderr, /destination already exists/);
});

test('real Mach-O slices can be signed after staging', {
  skip: process.platform !== 'darwin' && 'Requires Apple clang, lipo and codesign',
}, (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-native-mac-arch-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const run = (command, args) => {
    const result = spawnSync(command, args, { encoding: 'utf8', timeout: 60_000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    return result.stdout.trim();
  };
  const app = path.join(root, 'Source.app');
  fs.mkdirSync(path.join(app, 'Contents/MacOS'), { recursive: true });
  const c = path.join(root, 'main.c');
  fs.writeFileSync(c, 'int main(void) { return 0; }\n');
  const slices = ['arm64', 'x86_64'].map((arch) => {
    const output = path.join(root, arch);
    run('clang', ['-arch', arch, c, '-o', output]);
    return output;
  });
  run('lipo', ['-create', ...slices, '-output', path.join(app, 'Contents/MacOS/app')]);
  fs.writeFileSync(path.join(app, 'Contents/Info.plist'), `<?xml version="1.0"?>
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.cb.arch</string>
<key>CFBundleExecutable</key><string>app</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>`);
  for (const arch of ['arm64', 'x86_64']) {
    const dest = path.join(root, `${arch}.app`);
    run(bash, [fileURLToPath(script), app, dest, arch]);
    assert.equal(run('lipo', ['-archs', path.join(dest, 'Contents/MacOS/app')]), arch);
    run('codesign', ['--force', '--sign', '-', dest]);
    run('codesign', ['--verify', '--deep', '--strict', dest]);
  }
});
