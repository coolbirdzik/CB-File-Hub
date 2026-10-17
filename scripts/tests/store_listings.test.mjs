import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import { loadStoreListings, loadGooglePlayListings, applyStoreListings } from '../store_listings.mjs';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const englishBase = {
  title: 'CB FileHub', description: 'Old copy', features: ['Old feature'],
  privacyPolicy: 'https://example.test/privacy', licenseTerms: 'Existing terms',
  supportContact: 'support@example.test', releaseNotes: 'Current release notes',
  images: [{ id: 'keep-image', fileName: 'browser.png', fileStatus: 'Uploaded', imageType: 'Screenshot' }],
};

test('both checked-in listings cover the app and meet Store text limits', () => {
  const content = loadStoreListings();
  const play = loadGooglePlayListings();
  assert.deepEqual(Object.keys(content), ['en-us', 'vi-vn']);
  assert.deepEqual(Object.keys(play), ['en-US', 'vi']);
  assert.equal(play['en-US'].fullDescription, content['en-us'].description);
  assert.equal(play.vi.fullDescription, content['vi-vn'].description);
  for (const listing of Object.values(content)) {
    assert.ok(listing.description.includes('qBittorrent'));
    for (const capability of ['SSH', 'SMB', 'WebDAV', 'GGUF', 'Google Drive', 'Dropbox', 'OneDrive', 'ZIP']) {
      assert.ok(listing.description.includes(capability), capability);
    }
    assert.equal(listing.features.length, 12);
    assert.deepEqual(listing.features, listing.description.split(/\r?\n/)
      .filter((line) => line.startsWith('- ')).map((line) => line.slice(2)));
    assert.ok(listing.description.length < 2000, 'Keep the checked-in copy concise');
  }
});

test('updates both descriptions, preserves Store assets/legal fields and unrelated locales', () => {
  const input = {
    id: 'draft', targetPublishMode: 'Manual',
    listings: {
      'en-us': { baseListing: englishBase, platformOverrides: { Windows81: { title: 'Platform title' } } },
      'vi-vn': { baseListing: { ...englishBase, title: 'Existing Vietnamese title', privacyPolicy: 'https://example.test/vi' }, platformOverrides: {} },
      'tr-tr': { baseListing: { title: 'Turkish', description: 'Keep this' } },
    },
  };
  const before = structuredClone(input);
  const content = loadStoreListings();
  const output = applyStoreListings(input, content);
  assert.deepEqual(input, before);
  for (const locale of ['en-us', 'vi-vn']) {
    assert.equal(output.listings[locale].baseListing.description, content[locale].description);
    assert.deepEqual(output.listings[locale].baseListing.features, content[locale].features);
    for (const key of ['title', 'images', 'privacyPolicy', 'licenseTerms', 'supportContact', 'releaseNotes']) {
      assert.deepEqual(output.listings[locale].baseListing[key], input.listings[locale].baseListing[key]);
    }
    assert.deepEqual(output.listings[locale].platformOverrides, input.listings[locale].platformOverrides);
  }
  assert.deepEqual(output.listings['tr-tr'], input.listings['tr-tr']);
});

test('seeds a new Vietnamese listing from existing Store metadata', () => {
  const output = applyStoreListings({ listings: { 'en-us': { baseListing: englishBase } } }, loadStoreListings());
  assert.equal(output.listings['vi-vn'].baseListing.title, englishBase.title);
  assert.deepEqual(output.listings['vi-vn'].baseListing.images, englishBase.images);
  assert.notEqual(output.listings['vi-vn'].baseListing.description, englishBase.description);
  assert.throws(() => applyStoreListings({ listings: {} }, loadStoreListings()), /initial listing/);
});

test('rejects missing locales, overlong text/features and unsafe description paths', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-store-copy-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const write = (locale, overrides = {}) => {
    fs.writeFileSync(path.join(directory, `${locale}.txt`), 'Description\n\n- Feature');
    fs.writeFileSync(path.join(directory, `${locale}.json`), JSON.stringify({
      descriptionFile: `${locale}.txt`, shortDescription: 'Short description',
      googlePlayLanguage: locale === 'en-us' ? 'en-US' : 'vi', ...overrides,
    }));
  };
  write('en-us');
  assert.throws(() => loadStoreListings(directory), /vi-vn/);
  write('vi-vn');
  write('en-us', { descriptionFile: '../secret.txt' });
  assert.throws(() => loadStoreListings(directory), /sibling/);
  write('en-us');
  fs.writeFileSync(path.join(directory, 'en-us.txt'), Array(21).fill('- Feature').join('\n'));
  assert.throws(() => loadStoreListings(directory), /1–20 features/);
  fs.writeFileSync(path.join(directory, 'en-us.txt'), `- ${'x'.repeat(201)}`);
  assert.throws(() => loadStoreListings(directory), /1–200 characters/);
  write('en-us');
  write('en-us', { shortDescription: 'x'.repeat(81) });
  assert.throws(() => loadStoreListings(directory), /1–80 characters/);
  write('en-us', { googlePlayLanguage: 'vi' });
  assert.throws(() => loadGooglePlayListings(directory), /unique Google Play/);
  write('en-us');
  fs.writeFileSync(path.join(directory, 'en-us.txt'), 'x'.repeat(4001));
  assert.throws(() => loadStoreListings(directory), /1–4000 characters/);
  fs.writeFileSync(path.join(directory, 'en-us.txt'), `${'x'.repeat(3990)}\n- Feature`);
  assert.equal(loadGooglePlayListings(directory)['en-US'].fullDescription.length, 4000);
});

test('submit CLI sends bilingual copy in its PUT and retains package/commit behavior without network', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-store-submit-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const archive = path.join(directory, 'package.zip');
  const result = path.join(directory, 'requests.json');
  const mock = path.join(directory, 'mock.mjs');
  fs.writeFileSync(archive, 'test archive');
  fs.writeFileSync(mock, `
    import fs from 'node:fs';
    const calls = [];
    globalThis.fetch = async (url, options = {}) => {
      const method = options.method || 'GET';
      const request = { url: String(url), method };
      if (options.body && typeof options.body === 'string' && options.body.startsWith('{')) request.body = JSON.parse(options.body);
      calls.push(request);
      fs.writeFileSync(process.env.TEST_REQUESTS, JSON.stringify(calls));
      let response;
      if (String(url).includes('/oauth2/token')) response = { access_token: 'fake-token' };
      else if (method === 'GET' && String(url).endsWith('/applications/app')) response = {};
      else if (method === 'POST' && String(url).endsWith('/submissions')) response = {
        id: 'draft', fileUploadUrl: 'https://example.test/upload',
        listings: { 'en-us': { baseListing: ${JSON.stringify(englishBase)} } },
        applicationPackages: [{ id: 'old', fileName: 'old.msix' }]
      };
      else if (method === 'PUT' && String(url).endsWith('/submissions/draft')) response = {};
      else if (method === 'PUT' && String(url) === 'https://example.test/upload') {
        for await (const chunk of options.body) {};
        response = {};
      }
      else if (method === 'POST' && String(url).endsWith('/commit')) response = {};
      else throw new Error('Unexpected mock request: ' + method + ' ' + url);
      return new Response(JSON.stringify(response), { status: 200 });
    };
  `);
  const child = spawnSync(process.execPath, ['--import', pathToFileURL(mock).href, 'scripts/partner_center_msix.mjs', 'submit'], {
    cwd: repo, encoding: 'utf8',
    env: {
      ...process.env, PARTNER_CENTER_TENANT_ID: 'tenant', PARTNER_CENTER_CLIENT_ID: 'client',
      PARTNER_CENTER_CLIENT_SECRET: 'test-only', PARTNER_CENTER_APP_ID: 'app',
      PARTNER_CENTER_PACKAGE_ARCHIVE: archive, PARTNER_CENTER_PACKAGE_FILE_NAME: 'new.msix',
      PARTNER_CENTER_LISTINGS_DIR: path.join(repo, 'store/listings'),
      PARTNER_CENTER_COMMIT_SUBMISSION: 'true', PARTNER_CENTER_TARGET_PUBLISH_MODE: 'Immediate',
      TEST_REQUESTS: result,
    },
  });
  assert.equal(child.status, 0, child.stderr);
  assert.equal(child.stdout.trim(), 'draft');
  const calls = JSON.parse(fs.readFileSync(result, 'utf8'));
  const payload = calls.find((call) => call.method === 'PUT' && call.url.endsWith('/submissions/draft')).body;
  assert.equal(payload.targetPublishMode, 'Immediate');
  assert.equal(payload.applicationPackages[0].fileStatus, 'PendingDelete');
  assert.equal(payload.applicationPackages[1].fileName, 'new.msix');
  assert.equal(payload.applicationPackages[1].fileStatus, 'PendingUpload');
  assert.equal(payload.listings['vi-vn'].baseListing.description, loadStoreListings()['vi-vn'].description);
  assert.deepEqual(payload.listings['en-us'].baseListing.images, englishBase.images);
  assert.ok(calls.some((call) => call.url.endsWith('/commit')));
});
