import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { spawnSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';
import {
  loadStoreListings, loadGooglePlayListings, applyStoreListings, requiredStoreLocales,
} from '../store_listings.mjs';
import { writeStoredZip } from '../stored_zip.mjs';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const englishBase = {
  title: 'CB FileHub', description: 'Old copy', features: ['Old feature'],
  privacyPolicy: 'https://example.test/privacy', licenseTerms: 'Existing terms',
  supportContact: 'support@example.test', releaseNotes: 'Current release notes',
  images: [
    { id: 'old-shot', fileName: 'browser.png', fileStatus: 'Uploaded', imageType: 'Screenshot' },
    { id: 'keep-icon', fileName: 'icon.png', fileStatus: 'Uploaded', imageType: 'Icon' },
  ],
};

function makePng(width, height) {
  const png = Buffer.alloc(33);
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(png);
  png.writeUInt32BE(13, 8);
  png.write('IHDR', 12, 'ascii');
  png.writeUInt32BE(width, 16);
  png.writeUInt32BE(height, 20);
  return png;
}

function readZip(file) {
  const data = fs.readFileSync(file);
  const end = data.length - 22;
  assert.equal(data.readUInt32LE(end), 0x06054b50);
  const count = data.readUInt16LE(end + 10);
  let offset = data.readUInt32LE(end + 16);
  const entries = {};
  for (let index = 0; index < count; index += 1) {
    assert.equal(data.readUInt32LE(offset), 0x02014b50);
    const crc = data.readUInt32LE(offset + 16);
    const size = data.readUInt32LE(offset + 24);
    const nameLength = data.readUInt16LE(offset + 28);
    const local = data.readUInt32LE(offset + 42);
    const name = data.toString('utf8', offset + 46, offset + 46 + nameLength);
    const start = local + 30 + data.readUInt16LE(local + 26);
    const content = data.subarray(start, start + size);
    assert.equal(zlib.crc32(content), crc, name);
    entries[name] = content;
    offset += 46 + nameLength;
  }
  return entries;
}

test('checked-in listings cover every app language and meet Store text limits', () => {
  const content = loadStoreListings();
  const play = loadGooglePlayListings();
  assert.deepEqual(Object.keys(content).sort(), [...requiredStoreLocales].sort());
  assert.deepEqual(Object.keys(play).sort(), ['en-US', 'tr-TR', 'vi', 'zh-CN']);
  assert.equal(play['en-US'].fullDescription, content['en-us'].description);
  assert.equal(play.vi.fullDescription, content['vi-vn'].description);
  for (const listing of Object.values(content)) {
    assert.ok(listing.description.includes('qBittorrent'));
    for (const capability of ['SSH', 'SMB', 'WebDAV', 'GGUF', 'Google Drive', 'Dropbox', 'OneDrive', 'ZIP']) {
      assert.ok(listing.description.includes(capability), capability);
    }
    assert.equal(listing.features.length, 12);
    assert.ok(!listing.description.includes('\r'));
    assert.deepEqual(listing.features, listing.description.split('\n')
      .filter((line) => line.startsWith('- ')).map((line) => line.slice(2)));
    assert.ok(listing.description.length < 2000, 'Keep the checked-in copy concise');
  }
});

test('MSIX manifest declares exactly the Store listing languages', () => {
  const pubspec = fs.readFileSync(path.join(repo, 'cb_file_manager/pubspec.yaml'), 'utf8');
  const line = pubspec.match(/^msix_config:[\s\S]*?^\s+languages:\s*(.+)$/m);
  assert.ok(line, 'msix_config.languages is missing');
  const languages = line[1].split(',').map((language) => language.trim()).sort();
  assert.deepEqual(languages, [...requiredStoreLocales].sort());
});

test('every listing ships localized screenshots and the shared hero art', () => {
  const content = loadStoreListings();
  for (const [locale, { images }] of Object.entries(content)) {
    const screenshots = images.filter((image) => image.imageType === 'Screenshot');
    assert.equal(screenshots.length, 10, locale);
    assert.ok(screenshots.every((image) => image.description.length > 0), locale);
    const names = screenshots.map((image) => path.basename(image.source));
    assert.ok(names.some((name) => name.startsWith('11_')), `${locale} shows the torrent library`);
    assert.ok(names.some((name) => name.startsWith('12_')), `${locale} shows tag assignment`);
    assert.deepEqual(images.filter((image) => image.imageType === 'PromotionalArt16x9')
      .map((image) => path.basename(image.source)), ['hero_16x9.png']);
    for (const image of images) {
      assert.match(image.fileName, new RegExp(`^store-${locale}-\\d{2}-[0-9a-f]{12}\\.png$`));
    }
  }
  const english = content['en-us'].images.map((image) => image.source);
  for (const locale of ['vi-vn', 'tr-tr', 'zh-cn']) {
    const localized = content[locale].images.filter((image) => image.imageType === 'Screenshot');
    assert.ok(localized.every((image) => !english.includes(image.source)), `${locale} uses its own screenshots`);
  }
});

test('updates text, replaces managed images and preserves other Store data', () => {
  const input = {
    id: 'draft', targetPublishMode: 'Manual',
    listings: {
      'en-us': { baseListing: englishBase, platformOverrides: { Windows81: { title: 'Platform title' } } },
      'vi-vn': { baseListing: { ...englishBase, title: 'Existing Vietnamese title', privacyPolicy: 'https://example.test/vi' }, platformOverrides: {} },
      'ja-jp': { baseListing: { title: 'Japanese', description: 'Keep this' } },
    },
  };
  const before = structuredClone(input);
  const content = loadStoreListings();
  const { submission: output, uploads } = applyStoreListings(input, content);
  assert.deepEqual(input, before);
  for (const locale of ['en-us', 'vi-vn']) {
    const listing = output.listings[locale].baseListing;
    assert.equal(listing.description, content[locale].description);
    assert.deepEqual(listing.features, content[locale].features);
    for (const key of ['title', 'privacyPolicy', 'licenseTerms', 'supportContact', 'releaseNotes']) {
      assert.deepEqual(listing[key], input.listings[locale].baseListing[key]);
    }
    assert.deepEqual(output.listings[locale].platformOverrides, input.listings[locale].platformOverrides);
    assert.deepEqual(listing.images.slice(0, 2), [
      { ...englishBase.images[0], fileStatus: 'PendingDelete' },
      englishBase.images[1],
    ]);
    assert.deepEqual(listing.images.slice(2), content[locale].images.map((image) => ({
      fileName: image.fileName, fileStatus: 'PendingUpload',
      imageType: image.imageType, description: image.description,
    })));
  }
  assert.deepEqual(output.listings['ja-jp'], input.listings['ja-jp']);
  const expectedUploads = Object.values(content).flatMap((listing) => listing.images);
  assert.deepEqual(uploads, expectedUploads);
});

test('keeps already uploaded images when their content-addressed names match', () => {
  const content = { 'en-us': loadStoreListings()['en-us'] };
  const uploaded = content['en-us'].images.map((image, index) => ({
    id: `img-${index}`, fileName: image.fileName, fileStatus: 'Uploaded',
    imageType: image.imageType, description: 'Old caption',
  }));
  const input = { listings: { 'en-us': { baseListing: { ...englishBase, images: [englishBase.images[1], ...uploaded] } } } };
  const { submission, uploads } = applyStoreListings(input, content);
  assert.deepEqual(uploads, []);
  const images = submission.listings['en-us'].baseListing.images;
  assert.deepEqual(images[0], englishBase.images[1]);
  assert.deepEqual(images.slice(1).map((image) => [image.id, image.fileStatus, image.description]),
    content['en-us'].images.map((image, index) => [`img-${index}`, 'Uploaded', image.description]));

  // A draft whose upload never finished must upload again.
  const pending = structuredClone(input);
  pending.listings['en-us'].baseListing.images[1].fileStatus = 'PendingUpload';
  assert.equal(applyStoreListings(pending, content).uploads.length, content['en-us'].images.length);
});

test('seeds new languages from existing metadata without copying other listings images', () => {
  const content = loadStoreListings();
  const { submission } = applyStoreListings({ listings: { 'en-us': { baseListing: englishBase } } }, content);
  for (const locale of ['vi-vn', 'tr-tr', 'zh-cn']) {
    const listing = submission.listings[locale].baseListing;
    assert.equal(listing.title, englishBase.title);
    assert.equal(listing.description, content[locale].description);
    assert.ok(listing.images.every((image) => image.fileStatus === 'PendingUpload' && !image.id));
    assert.equal(listing.images.length, content[locale].images.length);
  }
  assert.throws(() => applyStoreListings({ listings: {} }, content), /initial listing/);
});

test('leaves Store images untouched when image updates are disabled', () => {
  const content = loadStoreListings(undefined, { images: false });
  assert.ok(Object.values(content).every((listing) => !('images' in listing)));
  const { submission, uploads } = applyStoreListings({ listings: { 'en-us': { baseListing: englishBase } } }, content);
  assert.deepEqual(uploads, []);
  assert.deepEqual(submission.listings['en-us'].baseListing.images, englishBase.images);
  assert.deepEqual(submission.listings['vi-vn'].baseListing.images, []);
});

test('rejects missing locales, overlong text/features, unsafe paths and invalid images', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-store-copy-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  fs.writeFileSync(path.join(directory, 'shot.png'), makePng(2400, 1350));
  fs.writeFileSync(path.join(directory, 'small.png'), makePng(800, 600));
  fs.writeFileSync(path.join(directory, 'hero.png'), makePng(1920, 1080));
  fs.writeFileSync(path.join(directory, 'fake.png'), 'not a png');
  const playCodes = { 'en-us': 'en-US', 'vi-vn': 'vi', 'tr-tr': 'tr-TR', 'zh-cn': 'zh-CN' };
  const shot = { file: 'shot.png', imageType: 'Screenshot', description: 'Caption' };
  const write = (locale, overrides = {}) => {
    fs.writeFileSync(path.join(directory, `${locale}.txt`), 'Description\n\n- Feature');
    fs.writeFileSync(path.join(directory, `${locale}.json`), JSON.stringify({
      descriptionFile: `${locale}.txt`, shortDescription: 'Short description',
      googlePlayLanguage: playCodes[locale], microsoftStoreImages: [shot], ...overrides,
    }));
  };
  write('en-us');
  assert.throws(() => loadStoreListings(directory), /Missing required Store listing/);
  for (const locale of requiredStoreLocales) write(locale);
  assert.equal(Object.keys(loadStoreListings(directory)).length, 4);
  write('en-us', { descriptionFile: '../secret.txt' });
  assert.throws(() => loadStoreListings(directory), /sibling/);
  write('en-us');
  fs.writeFileSync(path.join(directory, 'en-us.txt'), Array(21).fill('- Feature').join('\n'));
  assert.throws(() => loadStoreListings(directory), /1–20 features/);
  fs.writeFileSync(path.join(directory, 'en-us.txt'), `- ${'x'.repeat(201)}`);
  assert.throws(() => loadStoreListings(directory), /1–200 characters/);
  write('en-us', { shortDescription: 'x'.repeat(81) });
  assert.throws(() => loadStoreListings(directory), /1–80 characters/);
  write('en-us', { googlePlayLanguage: 'vi' });
  assert.throws(() => loadGooglePlayListings(directory), /unique Google Play/);
  write('en-us');
  fs.writeFileSync(path.join(directory, 'en-us.txt'), 'x'.repeat(4001));
  assert.throws(() => loadStoreListings(directory), /1–4000 characters/);
  fs.writeFileSync(path.join(directory, 'en-us.txt'), `${'x'.repeat(3990)}\n- Feature`);
  assert.equal(loadGooglePlayListings(directory)['en-US'].fullDescription.length, 4000);

  const imageCases = [
    [[], /at least one image/],
    [[{ ...shot, imageType: 'Poster' }], /imageType must be one of/],
    [[{ ...shot, file: 'missing.png' }], /not found/],
    [[{ ...shot, file: 'fake.png' }], /not a PNG/],
    [[{ ...shot, file: 'small.png' }], /at least 1366x768/],
    [[shot, { file: 'shot.png', imageType: 'PromotionalArt16x9' }], /1920x1080 or 3840x2160/],
    [[{ file: 'hero.png', imageType: 'PromotionalArt16x9' }], /at least one Screenshot/],
    [Array(11).fill(shot), /at most 10 Screenshot/],
    [[{ ...shot, description: 'x'.repeat(201) }], /at most 200 characters/],
  ];
  for (const [images, error] of imageCases) {
    write('en-us', { microsoftStoreImages: images });
    assert.throws(() => loadStoreListings(directory), error);
  }
  write('en-us', { microsoftStoreImages: [shot, { file: 'hero.png', imageType: 'PromotionalArt16x9' }] });
  assert.equal(loadStoreListings(directory)['en-us'].images.length, 2);
});

test('stored ZIP round-trips entries with valid CRCs', (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-store-zip-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  fs.writeFileSync(path.join(directory, 'a.bin'), Buffer.alloc(3 * 1024 * 1024 + 7, 0xab));
  fs.writeFileSync(path.join(directory, 'b.txt'), 'hello');
  const zip = path.join(directory, 'out.zip');
  writeStoredZip(zip, [
    { name: 'package.msix', source: path.join(directory, 'a.bin') },
    { name: 'store-vi-vn-01-abc.png', source: path.join(directory, 'b.txt') },
  ]);
  const entries = readZip(zip);
  assert.deepEqual(Object.keys(entries), ['package.msix', 'store-vi-vn-01-abc.png']);
  assert.equal(entries['package.msix'].length, 3 * 1024 * 1024 + 7);
  assert.equal(entries['store-vi-vn-01-abc.png'].toString(), 'hello');
  assert.throws(() => writeStoredZip(zip, [
    { name: 'x', source: path.join(directory, 'b.txt') },
    { name: 'x', source: path.join(directory, 'b.txt') },
  ]), /duplicate/);
});

function runSubmit(t, { commitStatus = 'PreProcessing', statusDetails = {} } = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cb-store-submit-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const msix = path.join(directory, 'package.msix');
  const result = path.join(directory, 'requests.json');
  const uploaded = path.join(directory, 'uploaded.zip');
  const mock = path.join(directory, 'mock.mjs');
  fs.writeFileSync(msix, 'test package');
  fs.writeFileSync(mock, `
    import fs from 'node:fs';
    const calls = [];
    let statusPolls = 0;
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
        const chunks = [];
        for await (const chunk of options.body) chunks.push(chunk);
        fs.writeFileSync(process.env.TEST_UPLOADED, Buffer.concat(chunks));
        response = {};
      }
      else if (method === 'POST' && String(url).endsWith('/commit')) response = { status: 'CommitStarted' };
      else if (method === 'GET' && String(url).endsWith('/submissions/draft/status')) {
        statusPolls += 1;
        response = statusPolls === 1
          ? { status: 'CommitStarted' }
          : { status: ${JSON.stringify(commitStatus)}, statusDetails: ${JSON.stringify(statusDetails)} };
      }
      else throw new Error('Unexpected mock request: ' + method + ' ' + url);
      return new Response(JSON.stringify(response), { status: 200 });
    };
  `);
  const child = spawnSync(process.execPath, ['--import', pathToFileURL(mock).href, 'scripts/partner_center_msix.mjs', 'submit'], {
    cwd: repo, encoding: 'utf8',
    env: {
      ...process.env, PARTNER_CENTER_TENANT_ID: 'tenant', PARTNER_CENTER_CLIENT_ID: 'client',
      PARTNER_CENTER_CLIENT_SECRET: 'test-only', PARTNER_CENTER_APP_ID: 'app',
      PARTNER_CENTER_PACKAGE_PATH: msix, PARTNER_CENTER_PACKAGE_FILE_NAME: 'new.msix',
      PARTNER_CENTER_LISTINGS_DIR: path.join(repo, 'store/listings'),
      PARTNER_CENTER_COMMIT_SUBMISSION: 'true', PARTNER_CENTER_TARGET_PUBLISH_MODE: 'Immediate',
      PARTNER_CENTER_COMMIT_POLL_SECONDS: '0', RUNNER_TEMP: directory,
      TEST_REQUESTS: result, TEST_UPLOADED: uploaded,
    },
  });
  return { child, calls: JSON.parse(fs.readFileSync(result, 'utf8')), uploaded, directory };
}

test('submit CLI sends listings, uploads package and images in one ZIP, then waits for commit', (t) => {
  const { child, calls, uploaded, directory } = runSubmit(t, {
    statusDetails: { warnings: [{ code: 'ListingOptInWarning', details: 'Added listings' }] },
  });
  assert.equal(child.status, 0, child.stderr);
  assert.equal(child.stdout.trim(), 'draft');
  assert.match(child.stderr, /ListingOptInWarning/);
  assert.match(child.stderr, /status: PreProcessing/);
  const payload = calls.find((call) => call.method === 'PUT' && call.url.endsWith('/submissions/draft')).body;
  assert.equal(payload.targetPublishMode, 'Immediate');
  assert.equal(payload.applicationPackages[0].fileStatus, 'PendingDelete');
  assert.equal(payload.applicationPackages[1].fileName, 'new.msix');
  assert.equal(payload.applicationPackages[1].fileStatus, 'PendingUpload');
  const content = loadStoreListings();
  for (const locale of requiredStoreLocales) {
    assert.equal(payload.listings[locale].baseListing.description, content[locale].description);
  }
  assert.deepEqual(payload.listings['en-us'].baseListing.images.slice(0, 2), [
    { ...englishBase.images[0], fileStatus: 'PendingDelete' }, englishBase.images[1],
  ]);

  const entries = readZip(uploaded);
  const expected = ['new.msix', ...Object.values(content).flatMap((listing) => listing.images.map((image) => image.fileName))];
  assert.deepEqual(Object.keys(entries), expected);
  assert.equal(entries['new.msix'].toString(), 'test package');
  const firstImage = content['zh-cn'].images[0];
  assert.ok(entries[firstImage.fileName].equals(fs.readFileSync(firstImage.source)));
  for (const listing of Object.values(payload.listings)) {
    for (const image of listing.baseListing.images.filter((entry) => entry.fileStatus === 'PendingUpload')) {
      assert.ok(entries[image.fileName], image.fileName);
    }
  }
  assert.ok(calls.some((call) => call.url.endsWith('/commit')));
  assert.equal(calls.filter((call) => call.url.endsWith('/status')).length, 2);
  assert.ok(!fs.readdirSync(directory).some((name) => name.startsWith('partner-center-')), 'temporary ZIP is removed');
});

test('submit CLI fails when Partner Center rejects the commit', (t) => {
  const { child } = runSubmit(t, {
    commitStatus: 'CommitFailed',
    statusDetails: { errors: [{ code: 'InvalidParameterValue', details: 'Image size is invalid' }] },
  });
  assert.equal(child.status, 1);
  assert.match(child.stderr, /failed to commit: InvalidParameterValue: Image size is invalid/);
});
