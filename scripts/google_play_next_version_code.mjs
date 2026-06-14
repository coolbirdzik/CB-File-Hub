import crypto from 'node:crypto';
import fs from 'node:fs';

const ANDROID_PUBLISHER_SCOPE =
  'https://www.googleapis.com/auth/androidpublisher';
const DEFAULT_TOKEN_URI = 'https://oauth2.googleapis.com/token';
const API_ROOT = 'https://androidpublisher.googleapis.com/androidpublisher/v3';

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function base64Url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

function readServiceAccount(rawValue) {
  const trimmed = rawValue.trim();
  const jsonText = trimmed.startsWith('{')
    ? trimmed
    : fs.readFileSync(trimmed, 'utf8');
  return JSON.parse(jsonText);
}

function createJwt(serviceAccount) {
  const tokenUri = serviceAccount.token_uri || DEFAULT_TOKEN_URI;
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };
  const payload = {
    iss: serviceAccount.client_email,
    scope: ANDROID_PUBLISHER_SCOPE,
    aud: tokenUri,
    exp: now + 3600,
    iat: now,
  };
  const unsignedToken = `${base64Url(JSON.stringify(header))}.${base64Url(
    JSON.stringify(payload),
  )}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsignedToken);
  signer.end();
  const signature = signer.sign(serviceAccount.private_key, 'base64');
  return {
    assertion: `${unsignedToken}.${signature
      .replaceAll('+', '-')
      .replaceAll('/', '_')
      .replaceAll('=', '')}`,
    tokenUri,
  };
}

async function getAccessToken(serviceAccount) {
  const { assertion, tokenUri } = createJwt(serviceAccount);
  const body = new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  });

  const response = await fetch(tokenUri, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  const payload = await parseResponse(response);
  if (!response.ok) {
    throw new Error(`OAuth token request failed: ${formatError(payload)}`);
  }
  if (!payload.access_token) {
    throw new Error('OAuth token response did not include access_token');
  }
  return payload.access_token;
}

async function parseResponse(response) {
  const text = await response.text();
  if (text === '') {
    return null;
  }
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

function formatError(payload) {
  if (!payload) {
    return '(empty response)';
  }
  if (typeof payload === 'string') {
    return payload;
  }
  return JSON.stringify(payload);
}

async function apiRequest(accessToken, method, path) {
  const response = await fetch(`${API_ROOT}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
    },
  });
  const payload = await parseResponse(response);
  if (!response.ok) {
    throw new Error(
      `Google Play API ${method} ${path} failed: ${formatError(payload)}`,
    );
  }
  return payload;
}

function addVersionCode(versionCodes, value) {
  const number = Number.parseInt(String(value), 10);
  if (Number.isSafeInteger(number) && number > 0) {
    versionCodes.add(number);
  }
}

function collectVersionCodesFromTracks(versionCodes, tracksResponse) {
  for (const track of tracksResponse?.tracks || []) {
    for (const release of track.releases || []) {
      for (const versionCode of release.versionCodes || []) {
        addVersionCode(versionCodes, versionCode);
      }
    }
  }
}

function collectVersionCodesFromArtifacts(versionCodes, artifacts) {
  for (const artifact of artifacts || []) {
    addVersionCode(versionCodes, artifact.versionCode);
  }
}

async function main() {
  const minVersionCode = Number.parseInt(
    requiredEnv('MIN_ANDROID_VERSION_CODE'),
    10,
  );
  if (!Number.isSafeInteger(minVersionCode) || minVersionCode < 1) {
    throw new Error(
      `MIN_ANDROID_VERSION_CODE must be a positive integer, got ${process.env.MIN_ANDROID_VERSION_CODE}`,
    );
  }

  const packageName = requiredEnv('GOOGLE_PLAY_PACKAGE_NAME');
  const serviceAccount = readServiceAccount(
    requiredEnv('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON'),
  );
  const accessToken = await getAccessToken(serviceAccount);
  const encodedPackageName = encodeURIComponent(packageName);

  const edit = await apiRequest(
    accessToken,
    'POST',
    `/applications/${encodedPackageName}/edits`,
  );
  if (!edit?.id) {
    throw new Error('Google Play edit creation did not return an edit id');
  }

  const versionCodes = new Set();
  try {
    const encodedEditId = encodeURIComponent(edit.id);
    const [bundles, apks, tracks] = await Promise.all([
      apiRequest(
        accessToken,
        'GET',
        `/applications/${encodedPackageName}/edits/${encodedEditId}/bundles`,
      ),
      apiRequest(
        accessToken,
        'GET',
        `/applications/${encodedPackageName}/edits/${encodedEditId}/apks`,
      ),
      apiRequest(
        accessToken,
        'GET',
        `/applications/${encodedPackageName}/edits/${encodedEditId}/tracks`,
      ),
    ]);

    collectVersionCodesFromArtifacts(versionCodes, bundles?.bundles);
    collectVersionCodesFromArtifacts(versionCodes, apks?.apks);
    collectVersionCodesFromTracks(versionCodes, tracks);
  } finally {
    try {
      await apiRequest(
        accessToken,
        'DELETE',
        `/applications/${encodedPackageName}/edits/${encodeURIComponent(edit.id)}`,
      );
    } catch (error) {
      console.error(`Warning: could not delete temporary Google Play edit: ${error.message}`);
    }
  }

  const sortedVersionCodes = [...versionCodes].sort((a, b) => a - b);
  const googlePlayMax = sortedVersionCodes.at(-1) || 0;
  const nextVersionCode = Math.max(minVersionCode, googlePlayMax + 1);

  console.error(
    `Google Play versionCodes: ${
      sortedVersionCodes.length > 0 ? sortedVersionCodes.join(', ') : '(none)'
    }`,
  );
  console.error(
    `Resolved Android versionCode: max(${minVersionCode}, ${googlePlayMax} + 1) = ${nextVersionCode}`,
  );
  console.log(nextVersionCode);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
