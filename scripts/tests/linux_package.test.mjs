import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { describeAsset } from '../../website/scripts/fetch-releases.mjs';

test('Linux downloads identify the distro for each FFmpeg ABI', () => {
  const variants = [
    ['', 'Debian 12'],
    ['-debian13', 'Debian 13'],
    ['-ubuntu24.04', 'Ubuntu 24.04 / Mint 22'],
    ['-ubuntu22.04', 'Ubuntu 22.04 / Mint 21'],
  ];
  for (const [suffix, distro] of variants) {
    assert.deepEqual(describeAsset(`CBFileHub-1.1.31-linux${suffix}-amd64.deb`), {
      platform: 'linux', label: `${distro} (.deb)`, ext: 'deb',
    });
    assert.deepEqual(describeAsset(`CBFileHub-1.1.31-linux${suffix}-x64.tar.gz`), {
      platform: 'linux', label: `Linux portable (${distro})`, ext: 'tar.gz',
    });
  }
});

test('dependency discovery failure cannot produce a package with a broken worker', {
  skip: process.platform !== 'linux' ? 'Requires Linux dpkg tooling' : false,
}, (t) => {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-deb-dependencies-'));
  t.after(() => fs.rmSync(temporary, { recursive: true, force: true }));
  const script = path.join(temporary, 'scripts/package_linux_deb.sh');
  fs.mkdirSync(path.dirname(script), { recursive: true });
  // Also support a Windows checkout mounted into WSL.
  fs.writeFileSync(script, fs.readFileSync(
    new URL('../package_linux_deb.sh', import.meta.url), 'utf8',
  ).replaceAll('\r\n', '\n'));
  const icon = path.join(temporary, 'cb_file_manager/assets/images/logo512.png');
  fs.mkdirSync(path.dirname(icon), { recursive: true });
  fs.copyFileSync(new URL('../../cb_file_manager/assets/images/logo512.png', import.meta.url), icon);
  const bundle = path.join(temporary, 'bundle');
  fs.mkdirSync(path.join(bundle, 'lib'), { recursive: true });
  fs.mkdirSync(path.join(bundle, 'subtitles'));
  fs.copyFileSync('/bin/true', path.join(bundle, 'cb-file-hub'));
  fs.chmodSync(path.join(bundle, 'cb-file-hub'), 0o755);
  fs.copyFileSync('/bin/true', path.join(bundle, 'subtitles/cb-subtitle-worker'));
  // Simulate dependency discovery failing on otherwise valid ELF files.
  // Previously the fallback silently dropped FFmpeg dependencies.
  const tools = path.join(temporary, 'bin');
  fs.mkdirSync(tools);
  fs.writeFileSync(path.join(tools, 'dpkg-shlibdeps'), '#!/bin/sh\nexit 1\n', { mode: 0o755 });
  const output = path.join(temporary, 'broken.deb');
  const result = spawnSync('bash', [
    script,
    bundle, '1.1.31', output,
  ], {
    encoding: 'utf8',
    env: { ...process.env, DEB_ARCH: 'amd64', PATH: `${tools}:${process.env.PATH}` },
    timeout: 30_000,
  });
  assert.ifError(result.error);
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /cannot derive subtitle worker dependencies/);
  assert.equal(fs.existsSync(output), false);
});
