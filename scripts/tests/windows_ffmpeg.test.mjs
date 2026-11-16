import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { promisify } from 'node:util';

const source = fs.readFileSync(new URL('../build_windows_ffmpeg.sh', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const start = source.indexOf('fetch() {');
const end = source.indexOf('\nif ! [ -f "$prefix/.runtime-version"', start);
assert.ok(start >= 0 && end > start);
const fetchFunction = source.slice(start, end);
const bash = process.platform === 'win32'
  ? path.join(process.env.ProgramFiles || 'C:/Program Files', 'Git/bin/bash.exe') : 'bash';
const quote = (s) => `'${s.replaceAll("'", "'\\''")}'`;

async function fixture(t, response) {
  const cache = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-source-download-'));
  t.after(() => fs.rmSync(cache, { recursive: true, force: true }));
  fs.mkdirSync(path.join(cache, 'sources'));
  const body = Buffer.from('verified source fixture\n');
  const sha = createHash('sha256').update(body).digest('hex');
  const requests = [];
  const server = createServer((req, res) => {
    requests.push(req.url);
    const reply = response(req.url, body);
    res.writeHead(reply.status ?? 200);
    res.end(reply.body ?? reply);
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const target = path.join(cache, 'sources/source.tar.gz');
  const driver = path.join(cache, 'fetch.sh');
  fs.writeFileSync(driver, `set -euo pipefail\nexport PATH=/usr/bin:/bin:$PATH\ncache=${quote(cache.replaceAll('\\', '/'))}\n${fetchFunction}\nfetch source.tar.gz ${sha} ${base}/primary ${base}/fallback\n`);
  return {
    target, body, requests,
    async run() {
      try {
        const result = await promisify(execFile)(bash, [driver.replaceAll('\\', '/')], { timeout: 15_000 });
        return { status: 0, output: result.stdout + result.stderr };
      } catch (e) {
        return { status: e.code, output: e.stdout + e.stderr };
      }
    },
    partials: () => fs.readdirSync(path.join(cache, 'sources')).filter((name) => name !== 'source.tar.gz'),
  };
}

test('HTTP 200 HTML is rejected and verified fallback is cached', async (t) => {
  const f = await fixture(t, (url, body) => url === '/primary' ? '<html>challenge page</html>' : body);
  const first = await f.run();
  assert.equal(first.status, 0, first.output);
  assert.deepEqual(fs.readFileSync(f.target), f.body);
  assert.deepEqual(f.requests, ['/primary', '/fallback']);
  assert.deepEqual(f.partials(), []);
  const second = await f.run();
  assert.equal(second.status, 0, second.output);
  assert.deepEqual(f.requests, ['/primary', '/fallback']);
});

test('all checksum failures stop the build and leave no new archive or partials', async (t) => {
  const f = await fixture(t, () => 'invalid payload');
  const result = await f.run();
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /Cannot fetch verified source/);
  assert.equal(fs.existsSync(f.target), false);
  assert.deepEqual(f.partials(), []);
});

test('HTTP failure tries the next source without caching the error body', async (t) => {
  const f = await fixture(t, (url, body) => url === '/primary'
    ? { status: 404, body: 'not found' } : body);
  const result = await f.run();
  assert.equal(result.status, 0, result.output);
  assert.deepEqual(fs.readFileSync(f.target), f.body);
  assert.deepEqual(f.requests, ['/primary', '/fallback']);
  assert.deepEqual(f.partials(), []);
});

test('corrupt cached content is replaced only by a verified response', async (t) => {
  const f = await fixture(t, (_url, body) => body);
  fs.writeFileSync(f.target, 'corrupt cache');
  const result = await f.run();
  assert.equal(result.status, 0, result.output);
  assert.deepEqual(fs.readFileSync(f.target), f.body);
  assert.deepEqual(f.requests, ['/primary']);
});
