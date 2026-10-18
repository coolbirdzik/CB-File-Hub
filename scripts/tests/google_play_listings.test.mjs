import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { prepareGooglePlayListings, discardGooglePlayEdit } from '../google_play_listings.mjs';
import { loadGooglePlayListings, loadGooglePlayImages } from '../store_listings.mjs';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const english = { language: 'en-US', title: 'Existing title', video: 'https://example.test/video', fullDescription: 'Old' };
const options = { packageName: 'com.example.test', accessToken: 'fake-token' };

function mockApi({ listings = [english], failLanguage, missingId = false, images = {}, failUpload,
  missingImageId = false, failImageDelete = false } = {}) {
  const calls = [];
  let uploads = 0;
  const fetchImpl = async (url, request) => {
    const media = url.includes('/upload/');
    const call = { url, method: request.method, headers: request.headers,
      body: media ? request.body : request.body && JSON.parse(request.body) };
    calls.push(call);
    assert.equal(request.headers.Authorization, 'Bearer fake-token');
    if (media) {
      uploads += 1;
      if (uploads === failUpload) return Response.json({ error: 'Image rejected' }, { status: 400 });
      return Response.json(missingImageId ? {} : { image: { id: `image-${uploads}` } });
    }
    if (/\/listings\/[^/]+\/[^/]+$/.test(url)) {
      if (request.method === 'GET') return Response.json({ images: images[url.split('/').at(-1)] ?? [] });
      if (request.method === 'DELETE') return new Response(null, { status: failImageDelete ? 404 : 204 });
    }
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

test('uploads only configured image types in order using raw PNG media in the same edit', async () => {
  const plan = loadGooglePlayImages()['en-US'];
  const images = { 'en-US': { phoneScreenshots: plan.phoneScreenshots.slice(0, 2), icon: plan.icon } };
  const mock = mockApi();
  await prepareGooglePlayListings({ ...options, ...mock, content: { 'en-US': loadGooglePlayListings()['en-US'] }, images });
  assert.deepEqual(mock.calls.map(({ method }) => method), ['POST', 'GET', 'PUT', 'GET', 'DELETE', 'POST', 'POST', 'GET', 'DELETE', 'POST']);
  const uploaded = mock.calls.filter(({ url }) => url.includes('/upload/'));
  const expected = [...images['en-US'].phoneScreenshots, ...plan.icon];
  for (const [i, call] of uploaded.entries()) {
    assert.equal(call.method, 'POST');
    assert.equal(call.headers['Content-Type'], 'image/png');
    assert.equal(call.headers['Content-Length'], String(call.body.length));
    assert.ok(call.body.equals(fs.readFileSync(expected[i].source)));
    assert.match(call.url, /^https:\/\/androidpublisher.googleapis.com\/upload\/androidpublisher\/v3\/applications\/com.example.test\/edits\/edit%20123\/listings\/en-US\/(phoneScreenshots|icon)\?uploadType=media$/);
  }
  const removed = mock.calls.filter(({ method }) => method === 'DELETE');
  assert.deepEqual(removed.map(({ url }) => url.split('/').at(-1)), ['phoneScreenshots', 'icon']);
  assert.equal(mock.calls[2].body.video, english.video);
  assert.ok(mock.calls.every(({ url }) => !url.includes(':commit') && !url.includes('sevenInchScreenshots') && !url.includes('featureGraphic')));
});

test('matching ordered hashes skip uploads, including base64 and uppercase hex hashes', async () => {
  const planned = loadGooglePlayImages()['en-US'].phoneScreenshots.slice(0, 2);
  const mock = mockApi({ images: { phoneScreenshots: [
    { sha256: planned[0].sha256.toUpperCase() },
    { sha256: Buffer.from(planned[1].sha256, 'hex').toString('base64') },
  ] } });
  await prepareGooglePlayListings({ ...options, ...mock, content: { 'en-US': { fullDescription: 'Copy' } },
    images: { 'en-US': { phoneScreenshots: planned } } });
  assert.deepEqual(mock.calls.map(({ method }) => method), ['POST', 'GET', 'PUT', 'GET']);
});

test('changed screenshot order replaces the configured group', async () => {
  const planned = loadGooglePlayImages()['en-US'].phoneScreenshots.slice(0, 2);
  const mock = mockApi({ images: { phoneScreenshots: [...planned].reverse().map(({ sha256 }) => ({ sha256 })) } });
  await prepareGooglePlayListings({ ...options, ...mock, content: { 'en-US': {} },
    images: { 'en-US': { phoneScreenshots: planned } } });
  assert.deepEqual(mock.calls.map(({ method }) => method), ['POST', 'GET', 'PUT', 'GET', 'DELETE', 'POST', 'POST']);
});

test('partial image upload failure, missing image id and failed clearing all discard the entire edit', async (t) => {
  const planned = loadGooglePlayImages()['en-US'].phoneScreenshots.slice(0, 2);
  for (const [settings, error, uploads] of [
    [{ failUpload: 2 }, /400.*Image rejected/, 2],
    [{ missingImageId: true }, /no image id/, 1],
    [{ failImageDelete: true }, /404/, 0],
  ]) {
    await t.test(JSON.stringify(settings), async () => {
      const mock = mockApi(settings);
      await assert.rejects(prepareGooglePlayListings({ ...options, ...mock, content: { 'en-US': {} },
        images: { 'en-US': { phoneScreenshots: planned } } }), error);
      assert.equal(mock.calls.filter(({ url }) => url.includes('/upload/')).length, uploads);
      assert.equal(mock.calls.at(-1).method, 'DELETE');
      assert.ok(mock.calls.at(-1).url.endsWith('/edits/edit%20123'));
      assert.ok(mock.calls.every(({ url }) => !url.includes(':commit')));
    });
  }
});

test('local file changed after validation aborts before clearing images', async (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-play-change-'));
  t.after(() => {
    assert.equal(path.dirname(directory), path.resolve(os.tmpdir()));
    assert.ok(path.basename(directory).startsWith('cb-play-change-'));
    fs.rmSync(directory, { recursive: true, force: true });
  });
  const source = path.join(directory, 'changed.png');
  fs.writeFileSync(source, 'changed bytes');
  const mock = mockApi();
  await assert.rejects(prepareGooglePlayListings({ ...options, ...mock, content: { 'en-US': {} },
    images: { 'en-US': { phoneScreenshots: [{ source, sha256: '0'.repeat(64) }] } } }), /changed after validation/);
  assert.deepEqual(mock.calls.map(({ method }) => method), ['POST', 'GET', 'PUT', 'GET', 'DELETE']);
  assert.ok(mock.calls.at(-1).url.endsWith('/edits/edit%20123'));
});

test('images without a matching listing fail before opening an edit', async () => {
  const mock = mockApi();
  await assert.rejects(prepareGooglePlayListings({ ...options, ...mock, content: { 'en-US': {} },
    images: { vi: {} } }), /require a listing for vi/);
  assert.equal(mock.calls.length, 0);
});

test('prepare CLI validates before auth, uploads artwork and supports the text-only switch', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-play-copy-'));
  t.after(() => {
    assert.equal(path.dirname(directory), path.resolve(os.tmpdir()));
    assert.ok(path.basename(directory).startsWith('cb-play-copy-'));
    fs.rmSync(directory, { recursive: true, force: true });
  });
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
      if (options.method === 'GET' && /\\/listings\\/[^/]+\\/[^/]+$/.test(String(url))) return Response.json({ images: [] });
      if (options.method === 'DELETE') return Response.json({ deleted: [] });
      if (options.method === 'POST' && String(url).includes('/upload/')) {
        if (!Buffer.isBuffer(options.body) || options.headers['Content-Type'] !== 'image/png') throw new Error('Expected raw PNG');
        return Response.json({ image: { id: 'uploaded' } });
      }
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
    GOOGLE_PLAY_UPDATE_IMAGES: 'true',
  };
  const args = ['--import', pathToFileURL(mock).href, 'scripts/google_play_listings.mjs', 'prepare'];
  const prepared = spawnSync(process.execPath, args, { cwd: repo, env, encoding: 'utf8' });
  assert.equal(prepared.status, 0, prepared.stderr);
  assert.equal(prepared.stdout.trim(), 'prepared');
  const calls = JSON.parse(fs.readFileSync(requestsPath, 'utf8'));
  assert.equal(calls.filter((call) => call.url.includes('/upload/')).length, 40);
  assert.equal(calls.filter((call) => call.method === 'DELETE').length, 16);
  assert.equal(calls.filter((call) => call.method === 'PUT').length, 4);

  const textOnly = spawnSync(process.execPath, args, {
    cwd: repo, env: { ...env, GOOGLE_PLAY_UPDATE_IMAGES: 'false' }, encoding: 'utf8',
  });
  assert.equal(textOnly.status, 0, textOnly.stderr);
  assert.deepEqual(JSON.parse(fs.readFileSync(requestsPath, 'utf8')).map((call) => call.method),
    ['POST', 'POST', 'GET', 'PUT', 'PUT', 'PUT', 'PUT']);

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

  // Use valid existing text/MS assets but deliberately invalid Play artwork.
  const invalid = path.join(directory, 'invalid');
  for (const locale of ['en-us', 'vi-vn', 'tr-tr', 'zh-cn']) {
    const entry = JSON.parse(fs.readFileSync(path.join(repo, 'store/listings', `${locale}.json`), 'utf8'));
    for (const image of entry.microsoftStoreImages) image.file = path.relative(invalid, path.resolve(repo, 'store/listings', image.file));
    entry.googlePlayImages = { icon: ['missing.png'] };
    fs.writeFileSync(path.join(invalid, `${locale}.json`), JSON.stringify(entry));
    fs.copyFileSync(path.join(repo, 'store/listings', `${locale}.txt`), path.join(invalid, `${locale}.txt`));
  }
  const badImage = spawnSync(process.execPath, args, {
    cwd: repo, env: { ...env, STORE_LISTINGS_DIR: invalid }, encoding: 'utf8',
  });
  assert.notEqual(badImage.status, 0);
  assert.match(badImage.stderr, /googlePlayImages.icon.*not found/);
  assert.equal(fs.existsSync(requestsPath), false, 'Invalid artwork must fail before authentication');
});
