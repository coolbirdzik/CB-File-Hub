import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defaultListingsDirectory, loadGooglePlayListings } from './store_listings.mjs';

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
  return async (method, suffix = '', body) => {
    const response = await fetchImpl(`${base}${suffix}`, {
      method, signal: AbortSignal.timeout(60000),
      headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    if (method === 'DELETE' && response.status === 404) return null;
    const text = await response.text();
    if (!response.ok) throw new Error(`Google Play ${method} ${suffix}: ${response.status} ${text}`);
    return text ? JSON.parse(text) : null;
  };
}

// Leave the edit uncommitted: upload-google-play adds the AAB and commits both
// the package and these descriptions together via its existingEditId input.
export async function prepareGooglePlayListings(options) {
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
  // Fail on invalid local text before requesting tokens or opening an edit.
  const content = command === 'prepare'
    ? loadGooglePlayListings(process.env.STORE_LISTINGS_DIR || defaultListingsDirectory)
    : undefined;
  const packageName = requiredEnv('GOOGLE_PLAY_PACKAGE_NAME');
  const editId = command === 'discard' ? requiredEnv('GOOGLE_PLAY_EDIT_ID') : undefined;
  const options = { packageName, accessToken: await accessToken() };
  if (command === 'prepare') {
    console.log(await prepareGooglePlayListings({ ...options, content }));
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
