import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { prepareGooglePlayListings, discardGooglePlayEdit } from '../google_play_listings.mjs';
import { loadGooglePlayListings } from '../store_listings.mjs';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const english = { language: 'en-US', title: 'Existing title', video: 'https://example.test/video', fullDescription: 'Old' };
const options = { packageName: 'com.example.test', accessToken: 'fake-token' };

function mockApi({ listings = [english], failLanguage, missingId = false } = {}) {
  const calls = [];
  const fetchImpl = async (url, request) => {
    const call = { url, method: request.method, body: request.body && JSON.parse(request.body) };
    calls.push(call);
    assert.equal(request.headers.Authorization, 'Bearer fake-token');
    if (request.method === 'POST') {
      return Response.json(missingId ? {} : { id: 'edit 123' });
    }
    if (request.method === 'GET') return Response.json({ listings });
    if (request.method === 'DELETE') return new Response(null, { status: 204 });
    if (request.method === 'PUT') {
      if (url.endsWith(`/listings/${failLanguage}`)) return Response.json({ error: 'Rejected' }, { status: 400 });
      return Response.json({});
    }
    throw new Error(`Unexpected mock request ${request.method} ${url}`);
  };
  return { calls, fetchImpl };
}

test('prepares every description in one uncommitted edit, preserving titles/video', async () => {
  const vietnamese = { language: 'vi', title: 'Tên hiện có', video: 'https://example.test/vi' };
  const unrelated = { language: 'ja-JP', title: 'Keep Japanese' };
  const current = [english, vietnamese, unrelated];
  const before = structuredClone(current);
  const content = loadGooglePlayListings();
  const mock = mockApi({ listings: current });
  assert.equal(await prepareGooglePlayListings({ ...options, ...mock, content }), 'edit 123');
  assert.deepEqual(mock.calls.map((call) => call.method), ['POST', 'GET', 'PUT', 'PUT', 'PUT', 'PUT']);
  for (const [index, language] of ['en-US', 'tr-TR', 'vi', 'zh-CN'].entries()) {
    const call = mock.calls[index + 2];
    assert.ok(call.url.endsWith(`/edits/edit%20123/listings/${language}`));
    const existing = current.find((entry) => entry.language === language);
    assert.deepEqual(call.body, { ...existing, language, title: existing?.title ?? english.title, ...content[language] });
  }
  assert.deepEqual(current, before);
  assert.ok(mock.calls.every((call) => !call.url.includes(':commit') && !call.url.includes('images')));
});

test('new language listings inherit only the existing product title', async () => {
  const mock = mockApi();
  await prepareGooglePlayListings({ ...options, ...mock, content: loadGooglePlayListings() });
  for (const language of ['tr-TR', 'vi', 'zh-CN']) {
    const body = mock.calls.find((call) => call.url.endsWith(`/listings/${language}`)).body;
    assert.equal(body.title, english.title);
    assert.equal(body.language, language);
    assert.equal(body.video, undefined);
  }
});

test('failed listing update discards the whole edit instead of leaving partial changes', async () => {
  const mock = mockApi({ failLanguage: 'vi' });
  await assert.rejects(
    prepareGooglePlayListings({ ...options, ...mock, content: loadGooglePlayListings() }), /400/,
  );
  assert.equal(mock.calls.at(-1).method, 'DELETE');
  assert.ok(mock.calls.at(-1).url.endsWith('/edits/edit%20123'));
});

test('missing initial Store title fails and discards its edit', async () => {
  const mock = mockApi({ listings: [] });
  await assert.rejects(
    prepareGooglePlayListings({ ...options, ...mock, content: loadGooglePlayListings() }), /initial Google Play listing title/,
  );
  assert.deepEqual(mock.calls.map((call) => call.method), ['POST', 'GET', 'DELETE']);
});

test('cleanup tolerates an edit that the upload action already removed', async () => {
  await discardGooglePlayEdit({
    ...options, editId: 'gone',
    fetchImpl: async (url, request) => {
      assert.equal(request.method, 'DELETE');
      assert.ok(url.endsWith('/edits/gone'));
      return new Response(null, { status: 404 });
    },
  });
});

test('prepare CLI validates copy before auth and produces an edit id with mocked OAuth/API', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-play-copy-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const requestsPath = path.join(directory, 'requests.json');
  const mock = path.join(directory, 'mock.mjs');
  fs.writeFileSync(mock, `
    import fs from 'node:fs';
    const calls = [];
    globalThis.fetch = async (url, options) => {
      calls.push({ url: String(url), method: options.method });
      fs.writeFileSync(process.env.TEST_REQUESTS, JSON.stringify(calls));
      if (String(url) === 'https://oauth2.googleapis.com/token') return Response.json({ access_token: 'fake-token' });
      if (options.method === 'POST' && String(url).endsWith('/edits')) return Response.json({ id: 'prepared' });
      if (options.method === 'GET' && String(url).endsWith('/listings')) return Response.json({ listings: [${JSON.stringify(english)}] });
      if (options.method === 'PUT' && /\\/listings\\/(en-US|tr-TR|vi|zh-CN)$/.test(String(url))) return Response.json({});
      throw new Error('Unexpected mocked request: ' + url);
    };
  `);
  const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const env = {
    ...process.env, TEST_REQUESTS: requestsPath,
    GOOGLE_PLAY_PACKAGE_NAME: 'com.example.test',
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: JSON.stringify({
      client_email: 'test@example.test', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    }),
    STORE_LISTINGS_DIR: path.join(repo, 'store/listings'),
  };
  const args = ['--import', pathToFileURL(mock).href, 'scripts/google_play_listings.mjs', 'prepare'];
  const prepared = spawnSync(process.execPath, args, { cwd: repo, env, encoding: 'utf8' });
  assert.equal(prepared.status, 0, prepared.stderr);
  assert.equal(prepared.stdout.trim(), 'prepared');
  const calls = JSON.parse(fs.readFileSync(requestsPath, 'utf8'));
  assert.deepEqual(calls.map((call) => call.method), ['POST', 'POST', 'GET', 'PUT', 'PUT', 'PUT', 'PUT']);

  fs.unlinkSync(requestsPath);
  fs.mkdirSync(path.join(directory, 'invalid'));
  fs.writeFileSync(path.join(directory, 'invalid/en-us.json'), JSON.stringify({ descriptionFile: 'en-us.txt' }));
  fs.writeFileSync(path.join(directory, 'invalid/en-us.txt'), 'x'.repeat(4001));
  const rejected = spawnSync(process.execPath, args, {
    cwd: repo, env: { ...env, STORE_LISTINGS_DIR: path.join(directory, 'invalid') }, encoding: 'utf8',
  });
  assert.notEqual(rejected.status, 0);
  assert.match(rejected.stderr, /4000/);
  assert.equal(fs.existsSync(requestsPath), false, 'Invalid copy must not authenticate or touch Google Play');
});
