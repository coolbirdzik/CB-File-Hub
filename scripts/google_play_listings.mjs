import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  defaultListingsDirectory, loadGooglePlayListings, loadGooglePlayImages,
} from './store_listings.mjs';

const apiRoot = 'https://androidpublisher.googleapis.com/androidpublisher/v3';

function requiredEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

async function accessToken() {
  const raw = requiredEnv('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON');
  const account = JSON.parse(raw.startsWith('{') ? raw : fs.readFileSync(raw, 'utf8'));
  const tokenUri = account.token_uri || 'https://oauth2.googleapis.com/token';
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode({
    iss: account.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: tokenUri, iat: now, exp: now + 3600,
  })}`;
  const signature = crypto.sign('RSA-SHA256', Buffer.from(unsigned), account.private_key).toString('base64url');
  const response = await fetch(tokenUri, {
    method: 'POST', signal: AbortSignal.timeout(60000),
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${unsigned}.${signature}`,
    }),
  });
  const payload = await response.json();
  if (!response.ok || !payload.access_token) throw new Error('Google Play authentication failed');
  return payload.access_token;
}

function api({ packageName, accessToken, fetchImpl = fetch }) {
  const base = `${apiRoot}/applications/${encodeURIComponent(packageName)}/edits`;
  const request = async (method, suffix = '', body, media = false) => {
    const url = media
      ? `${base.replace('/androidpublisher/v3/', '/upload/androidpublisher/v3/')}${suffix}?uploadType=media`
      : `${base}${suffix}`;
    const response = await fetchImpl(url, {
      method, signal: AbortSignal.timeout(60000),
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': media ? 'image/png' : 'application/json',
        ...(media ? { 'Content-Length': String(body.length) } : {}),
      },
      ...(body === undefined ? {} : { body: media ? body : JSON.stringify(body) }),
    });
    if (method === 'DELETE' && response.status === 404 && !suffix.includes('/listings/')) return null;
    const text = await response.text();
    if (!response.ok) throw new Error(`Google Play ${method} ${suffix}: ${response.status} ${text}`);
    return text ? JSON.parse(text) : null;
  };
  request.upload = (suffix, data) => request('POST', suffix, data, true);
  return request;
}

function normalizedHash(hash) {
  if (typeof hash !== 'string') return null;
  if (/^[a-f0-9]{64}$/i.test(hash)) return hash.toLowerCase();
  if (/^[A-Za-z0-9_+\/-]{43}=?$/.test(hash)) return Buffer.from(hash, 'base64url').toString('hex');
  return null;
}

async function updateImages(request, suffix, language, types) {
  for (const [type, planned] of Object.entries(types)) {
    const resource = `${suffix}/listings/${encodeURIComponent(language)}/${encodeURIComponent(type)}`;
    const current = (await request('GET', resource))?.images ?? [];
    if (current.length === planned.length && current.every((image, i) => normalizedHash(image.sha256) === planned[i].sha256)) {
      console.error(`Google Play ${language}/${type}: unchanged`);
      continue;
    }
    // Read and recheck all local bytes before clearing this type in the edit.
    const files = planned.map((image) => {
      const data = fs.readFileSync(image.source);
      if (crypto.createHash('sha256').update(data).digest('hex') !== image.sha256) {
        throw new Error(`Google Play image changed after validation: ${image.source}`);
      }
      return data;
    });
    await request('DELETE', resource);
    // Sequential uploads preserve the configured screenshot order.
    for (const data of files) {
      const uploaded = await request.upload(resource, data);
      if (!uploaded?.image?.id) throw new Error(`Google Play ${language}/${type}: upload returned no image id`);
    }
    console.error(`Google Play ${language}/${type}: uploaded ${files.length} image(s)`);
  }
}

// Leave the edit uncommitted: upload-google-play adds the AAB and commits the
// package, descriptions and images together via its existingEditId input.
export async function prepareGooglePlayListings(options) {
  for (const language of Object.keys(options.images ?? {})) {
    if (!options.content[language]) throw new Error(`Google Play images require a listing for ${language}`);
  }
  const request = api(options);
  const edit = await request('POST', '', {});
  if (!edit?.id) throw new Error('Google Play did not return an edit id');
  const suffix = `/${encodeURIComponent(edit.id)}`;
  try {
    const current = (await request('GET', `${suffix}/listings`))?.listings ?? [];
    const fallback = current.find((entry) => entry.language === 'en-US' && entry.title) ??
      current.find((entry) => entry.title);
    for (const [language, content] of Object.entries(options.content)) {
      const existing = current.find((entry) => entry.language === language);
      const title = existing?.title || fallback?.title;
      if (!title) throw new Error(`Prepare the initial Google Play listing title before adding ${language}`);
      await request('PUT', `${suffix}/listings/${encodeURIComponent(language)}`, {
        ...existing, language, title, ...content,
      });
      if (options.images?.[language]) await updateImages(request, suffix, language, options.images[language]);
    }
    return edit.id;
  } catch (error) {
    try {
      await request('DELETE', suffix);
    } catch (cleanupError) {
      console.error(`Could not discard failed Google Play edit: ${cleanupError.message}`);
    }
    throw error;
  }
}

export async function discardGooglePlayEdit(options) {
  await api(options)('DELETE', `/${encodeURIComponent(options.editId)}`);
}

async function main() {
  const command = process.argv[2];
  if (!['prepare', 'discard'].includes(command)) {
    throw new Error('Usage: node scripts/google_play_listings.mjs <prepare|discard>');
  }
  // Fail on invalid local text/images before requesting tokens or opening an edit.
  const directory = process.env.STORE_LISTINGS_DIR || defaultListingsDirectory;
  const content = command === 'prepare'
    ? loadGooglePlayListings(directory)
    : undefined;
  const images = command === 'prepare' && process.env.GOOGLE_PLAY_UPDATE_IMAGES !== 'false'
    ? loadGooglePlayImages(directory) : undefined;
  const packageName = requiredEnv('GOOGLE_PLAY_PACKAGE_NAME');
  const editId = command === 'discard' ? requiredEnv('GOOGLE_PLAY_EDIT_ID') : undefined;
  const options = { packageName, accessToken: await accessToken() };
  if (command === 'prepare') {
    console.log(await prepareGooglePlayListings({ ...options, content, images }));
  } else {
    await discardGooglePlayEdit({ ...options, editId });
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
